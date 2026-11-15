"""Potok konwersji instalacji gracza → katalog danych dla Godota.

  wyniki/
    meshes/**.glb           modele (jeden GLB na plik NIF, tekstury jako zewnętrzne PNG)
    textures/**.png         tekstury
    world/                  model danych świata (patrz world.py)
    reports/                raport konwersji, diagnostyka modeli, benchmark
    .mwconv/cache.sqlite    pamięć podręczna (SHA-256, wznawianie)

Etapy: (1) VFS, (2) ESM/ESP → świat, (3) wybór komórek → potrzebne modele, (4) modele (równolegle),
(5) tekstury (równolegle), (6) zapis komórek/terenu/indeksu, (7) raport.
Każdy etap pomija zasoby, których SHA-256 i wersja konwertera się nie zmieniły.
"""

from __future__ import annotations

import concurrent.futures as cf
import hashlib
import json
import os
import resource
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

from . import __version__
from .cache import Cache
from .install import InstallConfig
from .nif.reader import NifError, parse
from .nif2gltf import NifToGltf, TextureRef
from .textures import convert_texture, texture_out_rel
from .vfs import Vfs, norm
from .world import (cell_file_rel, cell_to_json, content_fingerprint, load_world, select_cells, terrain_to_json,
                    write_json)

MODEL_CONVERTER = f"nif2gltf-{__version__}"
TEXTURE_CONVERTER = f"tex2png-{__version__}"

_VFS: Optional[Vfs] = None
_OUT: Optional[Path] = None


def _worker_init(cfg: dict, out: str):
    global _VFS, _OUT
    _VFS = Vfs.from_install(cfg["data_dirs"], cfg["archives"])
    _OUT = Path(out)


def _rss_mb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0


def convert_model_job(key: str) -> dict:
    """Konwersja jednego NIF (wywoływana w procesie roboczym)."""
    t0 = time.perf_counter()
    vfs, out = _VFS, _OUT
    data = vfs.read(key)
    sha = hashlib.sha256(data).hexdigest()
    rel = key.rsplit(".", 1)[0] + ".glb"
    out_path = out / rel
    deps: list[str] = []

    def resolve(name: str):
        k = vfs.resolve_texture(name)
        if k is None:
            return None
        if k not in deps:
            deps.append(k)
        png = out / texture_out_rel(k)
        uri = os.path.relpath(png, out_path.parent).replace(os.sep, "/")
        return TextureRef(uri=uri, source_path=k)

    if key.endswith(".kf"):
        return _convert_kf_job(key, data, sha, out, t0)
    try:
        nif = parse(data, key)
        glb, rep = NifToGltf(nif, key, resolve).convert()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = out_path.with_suffix(".glb.tmp")
        tmp.write_bytes(glb)
        os.replace(tmp, out_path)
        r = rep.to_dict()
        status = "ok"
        err = None
        size = len(glb)
    except (NifError, Exception) as e:  # noqa: BLE001 – błąd zasobu nie może przerwać całej konwersji
        r, status, err, size = None, "error", f"{type(e).__name__}: {e}", 0
    return {"key": key, "sha256": sha, "status": status, "error": err, "report": r, "deps": deps,
            "outputs": [rel] if status == "ok" else [], "out_size": size, "in_size": len(data),
            "duration_ms": (time.perf_counter() - t0) * 1000, "rss_mb": _rss_mb()}


def kf_out_rel(key: str) -> str:
    return key.rsplit(".", 1)[0] + ".anim.json"


def sibling_kf(vfs: Vfs, mesh_key: str) -> Optional[str]:
    """Konwencja gry: animacje modelu „dir/name.nif” leżą w „dir/xname.kf”."""
    d, _, f = mesh_key.rpartition("/")
    k = f"{d}/x{f.rsplit('.', 1)[0]}.kf" if d else f"x{f.rsplit('.', 1)[0]}.kf"
    return k if k in vfs.files else None


def _convert_kf_job(key, data, sha, out, t0):
    from .kf2anim import convert_kf
    rel = kf_out_rel(key)
    try:
        doc, rep = convert_kf(parse(data, key), key)
        p = out / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")))
        os.replace(tmp, p)
        r, status, err, size = rep.to_dict(), "ok", None, p.stat().st_size
    except Exception as e:  # noqa: BLE001
        r, status, err, size = None, "error", f"{type(e).__name__}: {e}", 0
    return {"key": key, "sha256": sha, "status": status, "error": err, "report": r, "deps": [],
            "outputs": [rel] if status == "ok" else [], "out_size": size, "in_size": len(data),
            "duration_ms": (time.perf_counter() - t0) * 1000, "rss_mb": _rss_mb()}


def convert_texture_job(key: str) -> dict:
    t0 = time.perf_counter()
    vfs, out = _VFS, _OUT
    data = vfs.read(key)
    sha = hashlib.sha256(data).hexdigest()
    rel = texture_out_rel(key)
    try:
        info = convert_texture(data, out / rel)
        status, err = "ok", None
        size = (out / rel).stat().st_size
    except Exception as e:  # noqa: BLE001
        info, status, err, size = None, "error", f"{type(e).__name__}: {e}", 0
    return {"key": key, "sha256": sha, "status": status, "error": err, "report": info, "deps": [],
            "outputs": [rel] if status == "ok" else [], "out_size": size, "in_size": len(data),
            "duration_ms": (time.perf_counter() - t0) * 1000, "rss_mb": _rss_mb()}


@dataclass
class Options:
    out: Path
    cells: list[str] = field(default_factory=list)
    grids: list[tuple] = field(default_factory=list)
    all_cells: bool = False
    all_models: bool = False
    all_textures: bool = False
    jobs: int = 0
    verify_hash: bool = False
    bake_godot: str = ""        # ścieżka do binarki Godota ⇒ wypiekanie GLB → .scn z teksturami VRAM
    bake_project: str = ""      # katalog projektu Godota (z tools/bake_models.gd)
    bake_compress: str = "s3tc"   # True: liczy SHA-256 zawsze; False: pomija pliki o tym samym rozmiarze i mtime
    max_tasks_per_child: int = 200


PROGRESS_JSON = False  # True: postęp jako linie JSON na stdout (launcher Godota)


def emit(event: str, **kw):
    if PROGRESS_JSON:
        print("MWPROGRESS " + json.dumps({"event": event, **kw}, ensure_ascii=False), flush=True)


class Progress:
    def __init__(self, label: str, total: int, log: Callable[[str], None]):
        self.label, self.total, self.log = label, total, log
        self.done = 0
        self.t0 = time.perf_counter()
        self.last = 0.0

    def step(self, n: int = 1):
        self.done += n
        now = time.perf_counter()
        if PROGRESS_JSON and (now - self.last > 0.25 or self.done == self.total):
            emit("progress", stage=self.label, done=self.done, total=self.total)
        if now - self.last > 1.0 or self.done == self.total:
            self.last = now
            el = now - self.t0
            rate = self.done / el if el > 0 else 0
            eta = (self.total - self.done) / rate if rate > 0 else 0
            pct = 100.0 * self.done / self.total if self.total else 100
            self.log(f"[{self.label}] {self.done}/{self.total} ({pct:.1f}%) {rate:.1f}/s, pozostało ~{eta:.0f} s")


def _needs(cache: Cache, kind: str, key: str, vfs: Vfs, converter: str, verify: bool, out: Path) -> tuple[bool, str]:
    info = vfs.info(key)
    prev = cache.get(kind, key)
    if prev is None or prev["converter"] != converter or prev["status"] != "ok":
        return True, "nowy/zmiana wersji/poprzedni błąd" if prev else "nowy"
    if any(not (out / o).exists() for o in (prev["outputs"] or [])):
        return True, "brak pliku wynikowego"
    if prev["source"] != info.source:
        return True, "zmiana źródła (inny mod/archiwum)"
    if not verify and prev["size"] == info.size and abs((prev["mtime"] or 0) - info.mtime) < 1e-3:
        return False, "bez zmian (rozmiar+mtime)"
    sha = vfs.sha256(key)
    if sha != prev["sha256"]:
        return True, "zmiana zawartości (SHA-256)"
    return False, "bez zmian (SHA-256)"


def _run_jobs(fn, keys: list[str], cfg: InstallConfig, opts: Options, label: str, log, cache: Cache, kind: str,
              converter: str, vfs: Vfs, stats: dict):
    jobs = opts.jobs or max(1, min(4, (os.cpu_count() or 2)))
    prog = Progress(label, len(keys), log)
    results = []
    if not keys:
        return results
    t0 = time.perf_counter()
    if jobs == 1:
        _worker_init(cfg.to_dict(), str(opts.out))
        it = map(fn, keys)
        executor = None
    else:
        executor = cf.ProcessPoolExecutor(max_workers=jobs, initializer=_worker_init,
                                          initargs=(cfg.to_dict(), str(opts.out)),
                                          max_tasks_per_child=opts.max_tasks_per_child)
        it = executor.map(fn, keys, chunksize=8)
    try:
        for res in it:
            info = vfs.info(res["key"])
            cache.put(kind, res["key"], source=info.source, sha256=res["sha256"], size=info.size, mtime=info.mtime,
                      converter=converter, status=res["status"], error=res["error"], outputs=res["outputs"],
                      deps=res["deps"], report=res["report"], duration_ms=res["duration_ms"])
            results.append(res)
            prog.step()
    finally:
        if executor:
            executor.shutdown()
    el = time.perf_counter() - t0
    ok = [r for r in results if r["status"] == "ok"]
    stats[label] = {
        "converted": len(results), "ok": len(ok), "errors": len(results) - len(ok), "seconds": round(el, 3),
        "per_second": round(len(results) / el, 2) if el > 0 else None,
        "input_mb": round(sum(r["in_size"] for r in results) / 1e6, 3),
        "output_mb": round(sum(r["out_size"] for r in results) / 1e6, 3),
        "worker_peak_rss_mb": round(max((r["rss_mb"] for r in results), default=0), 1),
        "mean_ms": round(sum(r["duration_ms"] for r in results) / len(results), 2),
        "max_ms": round(max(r["duration_ms"] for r in results), 2), "jobs": jobs,
    }
    return results


def _assets_only(cfg, opts, vfs, cache, state, stats, run_id, T0, log) -> dict:
    """Świat bez zmian: tylko przyrostowe sprawdzenie modeli i tekstur (np. zmieniony luźny plik NIF)."""
    out = opts.out
    needed = set(state.get("needed_models", []))
    todo = [k for k in sorted(needed) if k in vfs.files and
            _needs(cache, "model", k, vfs, MODEL_CONVERTER, opts.verify_hash, out)[0]]
    _run_jobs(convert_model_job, todo, cfg, opts, "models", log, cache, "model", MODEL_CONVERTER, vfs, stats)
    stats.setdefault("models", {})["skipped_unchanged"] = len(needed) - len(todo)
    tex = set(state.get("land_textures", []))
    for k in needed:
        c = cache.get("model", k)
        if c and c["deps"]:
            tex.update(c["deps"])
    if opts.all_textures:
        tex |= {k for k in vfs.list("textures/") if k.endswith((".dds", ".tga", ".bmp"))}
    ttodo = [k for k in sorted(tex) if k in vfs.files and
             _needs(cache, "texture", k, vfs, TEXTURE_CONVERTER, opts.verify_hash, out)[0]]
    _run_jobs(convert_texture_job, ttodo, cfg, opts, "textures", log, cache, "texture", TEXTURE_CONVERTER, vfs, stats)
    stats.setdefault("textures", {})["skipped_unchanged"] = len(tex) - len(ttodo)
    if opts.bake_godot:
        bake(opts, stats, log)
    stats["total_seconds"] = round(time.perf_counter() - T0, 3)
    stats["main_peak_rss_mb"] = round(_rss_mb(), 1)
    write_json(out / "reports" / "conversion_last_incremental.json", {"stats": stats})
    cache.run_finish(run_id, stats)
    cache.close()
    log(f"Gotowe w {stats['total_seconds']} s (świat bez zmian).")
    emit("done", seconds=stats["total_seconds"], errors=0, unchanged=True)
    return stats


def bake(opts: Options, stats: dict, log) -> None:
    """Wypiekanie GLB, dla których brak aktualnej sceny .scn (przyrostowo)."""
    import subprocess
    out = opts.out
    todo = []
    for glb in sorted((out / "meshes").rglob("*.glb")):
        rel = glb.relative_to(out).as_posix()
        scn = out / "baked" / (rel[:-4] + ".scn")
        if not scn.exists() or scn.stat().st_mtime < glb.stat().st_mtime:
            todo.append(rel)
    stats["bake"] = {"todo": len(todo)}
    if not todo:
        return
    emit("stage", stage="bake", total=len(todo))
    lst = out / ".mwconv" / "bake_list.txt"
    lst.write_text("\n".join(todo))
    project = opts.bake_project or str(Path(__file__).resolve().parents[2] / "godot")
    t = time.perf_counter()
    r = subprocess.run([opts.bake_godot, "--headless", "--path", project, "-s", "res://tools/bake_models.gd", "--",
                        f"--data={out}", f"--list={lst}", f"--compress={opts.bake_compress}"],
                       capture_output=True, text=True)
    line = next((x for x in r.stdout.splitlines() if x.startswith("BAKE ")), "")
    stats["bake"].update(json.loads(line[5:]) if line else {"error": r.stderr[-500:]})
    stats["bake"]["seconds"] = round(time.perf_counter() - t, 2)
    log(f"Wypiekanie: {stats['bake']}")


def run(cfg: InstallConfig, opts: Options, log: Callable[[str], None] = print) -> dict:
    out = opts.out
    out.mkdir(parents=True, exist_ok=True)
    cache = Cache(out / ".mwconv" / "cache.sqlite")
    run_id = cache.run_start({"cfg": cfg.to_dict(), "cells": opts.cells, "grids": opts.grids,
                              "all_cells": opts.all_cells, "all_models": opts.all_models})
    stats: dict = {"version": __version__, "started": time.strftime("%Y-%m-%d %H:%M:%S")}
    T0 = time.perf_counter()

    # 1. VFS
    emit("stage", stage="vfs")
    t = time.perf_counter()
    vfs = Vfs.from_install(cfg.data_dirs, cfg.archives)
    stats["vfs"] = {"files": len(vfs.files), "nif": len(vfs.list("meshes/", ".nif")),
                    "textures": len(vfs.list("textures/")), "archives": len(cfg.archives),
                    "seconds": round(time.perf_counter() - t, 3)}
    log(f"VFS: {stats['vfs']['files']} plików ({stats['vfs']['nif']} NIF) z {len(cfg.data_dirs)} katalogów i "
        f"{len(cfg.archives)} archiwów")

    # 2. świat – pominięcie, gdy ESM/ESP (SHA-256), wybór komórek, VFS i wersja są te same co ostatnio
    t = time.perf_counter()
    vfs_sig = hashlib.sha256("\n".join(f"{k}|{f.source}|{f.size}|{f.mtime:.3f}" for k, f in sorted(vfs.files.items()))
                             .encode()).hexdigest()
    export_key = {"v": __version__, "content": content_fingerprint(cfg.content), "cells": sorted(opts.cells),
                  "grids": sorted(map(list, opts.grids)), "all_cells": opts.all_cells, "all_models": opts.all_models,
                  "vfs": vfs_sig}
    state_file = out / ".mwconv" / "export_state.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    if state.get("key") == export_key and (out / "world" / "manifest.json").exists():
        stats["world_load"] = {"skipped": True, "reason": "bez zmian (ESM/ESP, wybór, VFS)",
                               "seconds": round(time.perf_counter() - t, 3)}
        stats["world_export"] = {"skipped": True}
        log("Świat bez zmian – pomijam wczytanie ESM/ESP i eksport")
        return _assets_only(cfg, opts, vfs, cache, state, stats, run_id, T0, log)
    emit("stage", stage="world")
    world = load_world(cfg.content, log)
    stats["world_load"] = {"content": [f.name for f in world.content],
                           "records": sum(world.record_counts.values()),
                           "cells": len(world.cells), "lands": len(world.lands), "objects": len(world.objects),
                           "seconds": round(time.perf_counter() - t, 3), "rss_mb": round(_rss_mb(), 1)}

    # 3. wybór komórek
    keys = select_cells(world, opts.cells, opts.grids, opts.all_cells)
    stats["cells_selected"] = keys
    needed_models: set[str] = set()
    missing_models: set[str] = set()
    for k in keys:
        for mr in world.cells[k].refs.values():
            o = world.objects.get(mr.ref.base.lower())
            if o and o.get("model"):
                mk = vfs.resolve_mesh(o["model"])
                if mk:
                    needed_models.add(mk)
                else:
                    missing_models.add(o["model"])
    if opts.all_models:
        needed_models |= set(vfs.list("meshes/", ".nif")) | set(vfs.list("meshes/", ".kf"))
    for mk in list(needed_models):
        if mk.endswith(".nif"):
            kf = sibling_kf(vfs, mk)
            if kf:
                needed_models.add(kf)

    # 4. modele
    todo, skipped = [], 0
    for k in sorted(needed_models):
        need, _why = _needs(cache, "model", k, vfs, MODEL_CONVERTER, opts.verify_hash, out)
        if need:
            todo.append(k)
        else:
            skipped += 1
    log(f"Modele: {len(needed_models)} potrzebnych, {len(todo)} do konwersji, {skipped} bez zmian")
    model_results = _run_jobs(convert_model_job, todo, cfg, opts, "models", log, cache, "model", MODEL_CONVERTER,
                              vfs, stats)
    stats.setdefault("models", {})["skipped_unchanged"] = skipped
    stats["models"]["needed"] = len(needed_models)

    # 5. tekstury: zależności wszystkich potrzebnych modeli + teren
    tex_needed: set[str] = set()
    for k in needed_models:
        c = cache.get("model", k)
        if c and c["deps"] and k.endswith(".nif"):
            tex_needed.update(c["deps"])
    land_tex_keys: dict[str, Optional[str]] = {}

    def land_tex(name: str) -> Optional[str]:
        if name not in land_tex_keys:
            land_tex_keys[name] = vfs.resolve_texture(name)
            if land_tex_keys[name]:
                tex_needed.add(land_tex_keys[name])
        k = land_tex_keys[name]
        return texture_out_rel(k) if k else None

    terrain_cells = []
    for k in keys:
        c = world.cells[k].cell
        if not c.interior and tuple(c.grid) in world.lands:
            terrain_cells.append(tuple(c.grid))
    terrain_json = {}
    for g in terrain_cells:
        ld, ltex, src = world.lands[g]
        terrain_json[g] = terrain_to_json(g, ld, ltex, src, land_tex)

    if opts.all_textures:
        tex_needed |= {k for k in vfs.list("textures/") if k.endswith((".dds", ".tga", ".bmp"))}
    ttodo, tskip = [], 0
    for k in sorted(tex_needed):
        need, _ = _needs(cache, "texture", k, vfs, TEXTURE_CONVERTER, opts.verify_hash, out)
        if need:
            ttodo.append(k)
        else:
            tskip += 1
    log(f"Tekstury: {len(tex_needed)} potrzebnych, {len(ttodo)} do konwersji, {tskip} bez zmian")
    _run_jobs(convert_texture_job, ttodo, cfg, opts, "textures", log, cache, "texture", TEXTURE_CONVERTER, vfs, stats)
    stats.setdefault("textures", {})["skipped_unchanged"] = tskip

    # 6. świat → JSON
    t = time.perf_counter()
    wdir = out / "world"
    index = []
    for k in keys:
        mc = world.cells[k]
        j = cell_to_json(mc, world)
        rel = cell_file_rel(k)
        write_json(wdir / rel, j)
        index.append({"key": k, "name": mc.cell.name, "file": rel, "refs": len(j["refs"]),
                      "interior": mc.cell.interior, "grid": j["grid"], "sources": mc.sources})
    for g, tj in terrain_json.items():
        write_json(wdir / f"terrain/{g[0]}_{g[1]}.json", tj, compact=True)
    used_bases = {mr.ref.base.lower() for k in keys for mr in world.cells[k].refs.values()}
    objs = {}
    for bid in sorted(used_bases):
        o = world.objects.get(bid)
        if o is None:
            continue
        o = dict(o)
        if o.get("model"):
            mk = vfs.resolve_mesh(o["model"])
            c = cache.get("model", mk) if mk else None
            o["glb_ok"] = bool(c and c["status"] == "ok")
            kf = sibling_kf(vfs, mk) if mk else None
            if kf:
                o["anim"] = kf_out_rel(kf)
        objs[bid] = o
    write_json(wdir / "objects.json", objs)
    used_regions = {(world.cells[k].cell.region or "").lower() for k in keys} - {""}
    write_json(wdir / "regions.json", {r: world.regions[r] for r in sorted(used_regions) if r in world.regions})
    write_json(wdir / "index.json", {"format": "mwgodot-world", "version": 1, "cells": index})
    manifest = {
        "format": "mwgodot-world", "version": 1, "converter": __version__,
        "content": [{"name": f.name, "sha256": f.sha256, "masters": [m for m, _ in f.header.masters],
                     "records": f.num_records, "author": f.header.author} for f in world.content],
        "data_dirs": cfg.data_dirs, "archives": [os.path.basename(a) for a in cfg.archives],
        "warnings": world.warnings,
        "units_per_meter": 69.99125109,
        "axis_mapping": "godot(x,y,z) = (mw_x, mw_z, -mw_y) / units_per_meter",
    }
    write_json(wdir / "manifest.json", manifest)
    stats["world_export"] = {"cells": len(keys), "terrain": len(terrain_json), "objects": len(objs),
                             "refs": sum(i["refs"] for i in index), "seconds": round(time.perf_counter() - t, 3),
                             "missing_models": sorted(missing_models)}

    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps({"key": export_key, "needed_models": sorted(needed_models),
                                      "land_textures": sorted(k for k in land_tex_keys.values() if k)}))

    # 7. raport
    errors = [{"key": r["key"], "error": r["error"]} for r in model_results if r["status"] != "ok"]
    diag = {}
    for k in sorted(needed_models):
        c = cache.get("model", k)
        if c and c["report"]:
            rep = c["report"]
            if rep.get("lossy") or rep.get("unsupported") or rep.get("missing_textures"):
                diag[k] = {x: rep.get(x) for x in ("lossy", "unsupported", "missing_textures", "skipped_shapes")}
    if opts.bake_godot:
        bake(opts, stats, log)
    stats["total_seconds"] = round(time.perf_counter() - T0, 3)
    stats["main_peak_rss_mb"] = round(_rss_mb(), 1)
    stats["children_peak_rss_mb"] = round(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024.0, 1)
    write_json(out / "reports" / "conversion.json", {"stats": stats, "model_errors": errors, "diagnostics": diag})
    cache.run_finish(run_id, stats)
    cache.close()
    log(f"Gotowe w {stats['total_seconds']} s. Raport: {out / 'reports' / 'conversion.json'}")
    emit("done", seconds=stats["total_seconds"], errors=len(errors), cells=len(keys))
    return stats
