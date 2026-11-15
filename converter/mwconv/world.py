"""Scalanie ESM/ESP wg kolejności ładowania i eksport do nowoczesnego modelu danych świata.

Model danych (katalog `world/`, format „mwgodot-world” v1, tekstowy JSON – łatwy do diffowania i edycji):

  world/manifest.json              – pliki źródłowe (nazwa, SHA-256, mastery), wersja konwertera, statystyki
  world/objects.json               – rekordy bazowe z modelem: id → {type, model, glb, name, light, source}
  world/cells/ext/<x>_<y>.json     – komórka zewnętrzna: nagłówek + referencje
  world/cells/int/<slug>.json      – komórka wewnętrzna
  world/terrain/<x>_<y>.json       – teren (wysokości/normalne/kolory base64, mapa tekstur 16×16)
  world/index.json                 – lista komórek (klucz, nazwa, plik, liczba referencji, źródła)

Stabilny identyfikator referencji: "<plik-źródłowy>#<refnum>" (małe litery), gdzie plik źródłowy to
plik, który referencję utworzył (FRMR z indeksem mastera rozwiązanym wg nagłówka pluginu). Dzięki temu
nadpisania pluginów i zmiany z Construction Set 2.0 trafiają w te same referencje po ponownym imporcie.
"""

from __future__ import annotations

import base64
import json
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Optional

import numpy as np

from . import coords
from . import records as recdec
from .esm.reader import (MODEL_TYPES, Cell, CellRef, EsmFile, Land, parse_cell, parse_land, parse_object, parse_region,
                         open_esm_stream, read_esm)
from .vfs import norm

FORMAT = "mwgodot-world"
FORMAT_VERSION = 1


def slug(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s or "cell"


def model_glb_rel(model: str) -> str:
    n = norm(model)
    if not n.startswith("meshes/"):
        n = "meshes/" + n
    return n.rsplit(".", 1)[0] + ".glb"


@dataclass(slots=True)
class MergedRef:
    sid: str
    ref: CellRef
    source: str            # plik, który dostarczył obowiązującą wersję
    origin: str            # plik, który referencję utworzył
    history: list = field(default_factory=list)


@dataclass
class MergedCell:
    key: str
    cell: Cell
    refs: dict = field(default_factory=dict)   # sid → MergedRef
    sources: list = field(default_factory=list)


@dataclass
class World:
    content: list[EsmFile]
    objects: dict = field(default_factory=dict)       # id_lower → dict
    cells: dict = field(default_factory=dict)         # key → MergedCell
    lands: dict = field(default_factory=dict)         # (x, y) → (Land, ltex_map, source)
    record_counts: dict = field(default_factory=dict)
    warnings: list = field(default_factory=list)
    regions: dict = field(default_factory=dict)       # id_lower → dict
    ltex_by_file: dict = field(default_factory=dict)  # nazwa pliku → {INTV: tekstura}
    masters_by_file: dict = field(default_factory=dict)
    pathgrids: dict = field(default_factory=dict)     # (x, y) → (punkty [(x, y, z) świat], krawędzie [(i, j)])
    records: dict = field(default_factory=dict)       # typ → {id_lower: rekord} (etap 1: postacie, przedmioty, GMST…)

    def ltex_resolver(self, fname: str) -> dict:
        """Mapa INTV → tekstura widziana przez plik: własne LTEX, potem LTEX masterów (późniejszy wygrywa).

        Edytor gry zwykle zapisuje używane LTEX w pluginie; jeśli nie, korzystamy z masterów."""
        merged: dict = {}
        for m in self.masters_by_file.get(fname, []):
            merged.update(self.ltex_by_file.get(m.lower(), {}))
        merged.update(self.ltex_by_file.get(fname.lower(), {}))
        return merged


def content_fingerprint(paths: Iterable) -> list:
    import hashlib
    fp = []
    for p in paths:
        p = Path(p)
        h = hashlib.sha256()
        with open(p, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        fp.append([p.name, p.stat().st_size, h.hexdigest()])
    return fp


def load_world(paths: Iterable, log: Callable[[str], None] = lambda s: None) -> World:
    paths = list(paths)
    world = World([])
    names_lower = [Path(p).name.lower() for p in paths]
    for fi, path in enumerate(paths):
        f, records = open_esm_stream(path)  # rekordy strumieniowo – bez listy wszystkich rekordów
        world.content.append(f)
        # LTEX są lokalne dla pliku: VTEX odwołuje się do LTEX tego samego pliku (INTV + 1)
        ltex_local: dict[int, str] = {}
        world.ltex_by_file[f.name.lower()] = ltex_local
        world.masters_by_file[f.name] = [m for m, _ in f.header.masters]
        for m, _ in f.header.masters:
            if m.lower() not in names_lower[:fi]:
                world.warnings.append(f"{f.name}: master {m} nie jest załadowany wcześniej")
        t0 = time.perf_counter()
        for rec in records:
            world.record_counts[rec.type] = world.record_counts.get(rec.type, 0) + 1
            if rec.type in recdec.DECODERS:
                recdec.merge(world.records, rec, f.name)
            if rec.type in MODEL_TYPES:
                o = parse_object(rec)
                if o is None:
                    continue
                k = o["id"].lower()
                if rec.deleted:
                    world.objects.pop(k, None)
                    continue
                o["source"] = f.name
                if "model" in o:
                    o["glb"] = model_glb_rel(o["model"])
                prev = world.objects.get(k)
                if prev is not None:
                    o["overridden"] = prev.get("overridden", []) + [prev["source"]]
                world.objects[k] = o
            elif rec.type == "LTEX":
                import struct
                iv = rec.get("INTV")
                tex = rec.zstr("DATA")
                if iv is not None and tex:
                    ltex_local[struct.unpack_from("<I", iv, 0)[0]] = tex
            elif rec.type == "CELL":
                _merge_cell(world, parse_cell(rec), f, names_lower)
            elif rec.type == "REGN":
                rg = parse_region(rec)
                if rg:
                    if rec.deleted:
                        world.regions.pop(rg["id"].lower(), None)
                    else:
                        rg["source"] = f.name
                        world.regions[rg["id"].lower()] = rg
            elif rec.type == "PGRD":
                pg = parse_pathgrid(rec)
                if pg is not None:
                    grid, pts, edges = pg
                    if rec.deleted:
                        world.pathgrids.pop(grid, None)
                    else:
                        world.pathgrids[grid] = (pts, edges)
            elif rec.type == "LAND":
                ld = parse_land(rec)
                if ld.deleted:
                    world.lands.pop(ld.grid, None)
                else:
                    world.lands[ld.grid] = (ld, None, f.name)  # mapa LTEX rozwiązywana po wczytaniu wszystkiego
        log(f"{f.name}: {f.num_records} rekordów w {time.perf_counter() - t0:.2f} s")
    for g, (ld, _none, src) in list(world.lands.items()):
        world.lands[g] = (ld, world.ltex_resolver(src), src)
    return world


def parse_pathgrid(rec):
    """PGRD komórki zewnętrznej → ((x, y), punkty w układzie świata MW, krawędzie). Wnętrza pomijamy
    (używane tylko do wykluczeń roślinności). Format: DATA x,y,granularity,count; PGRP 16 B/punkt
    (x, y, z int32 względem początku komórki, auto u8, liczba połączeń u8); PGRC – indeksy u32 kolejno."""
    import struct
    data = rec.get("DATA")
    if data is None or len(data) < 12:
        return None
    gx, gy, _gran, _count = struct.unpack_from("<iiHH", data, 0)
    name = rec.zstr("NAME") or ""
    if gx == 0 and gy == 0 and name:          # wnętrze (komórka nazwana, siatka 0,0)
        return None
    pts_raw = rec.get("PGRP") or b""
    n = len(pts_raw) // 16
    pts, conns = [], []
    ox, oy = gx * 8192, gy * 8192
    for i in range(n):
        x, y, z, _auto, c = struct.unpack_from("<iiiBB", pts_raw, i * 16)
        pts.append((ox + x, oy + y, z))
        conns.append(c)
    pgrc = rec.get("PGRC") or b""
    idx = list(struct.unpack_from(f"<{len(pgrc) // 4}I", pgrc, 0)) if pgrc else []
    edges, k = [], 0
    for i, c in enumerate(conns):
        for j in idx[k:k + c]:
            if j < n:
                edges.append((i, j))
        k += c
    return (gx, gy), pts, edges


def _merge_cell(world: World, c: Cell, f: EsmFile, names_lower: list[str]):
    key = c.key
    mc = world.cells.get(key)
    if c.deleted:
        world.cells.pop(key, None)
        return
    if mc is None:
        mc = MergedCell(key, c)
        world.cells[key] = mc
    else:
        # nagłówek komórki: późniejszy plik wygrywa (nazwa, region, oświetlenie, woda)
        if c.name:
            mc.cell.name = c.name
        if c.region:
            mc.cell.region = c.region
        if c.ambient:
            mc.cell.ambient = c.ambient
        if c.water is not None:
            mc.cell.water = c.water
        mc.cell.flags = c.flags
    if f.name not in mc.sources:
        mc.sources.append(f.name)
    masters = [m for m, _ in f.header.masters]
    for r in c.refs:
        if r.mast_index == 0:
            origin = f.name
        elif r.mast_index - 1 < len(masters):
            origin = masters[r.mast_index - 1]
        else:
            world.warnings.append(f"{f.name}: referencja z nieznanym indeksem mastera {r.mast_index}")
            origin = f"?{r.mast_index}"
        sid = f"{origin.lower()}#{r.refnum}"
        target = mc
        if r.moved_to is not None and r.moved_to[0] == "ext":
            tkey = f"ext:{r.moved_to[1]},{r.moved_to[2]}"
            # usuń z bieżącej komórki i przenieś do docelowej
            mc.refs.pop(sid, None)
            target = world.cells.get(tkey)
            if target is None:
                target = MergedCell(tkey, Cell("", 0, (r.moved_to[1], r.moved_to[2]), False))
                world.cells[tkey] = target
            if f.name not in target.sources:
                target.sources.append(f.name)
        if r.deleted:
            for cc in (target, mc):
                cc.refs.pop(sid, None)
            continue
        prev = target.refs.get(sid)
        mr = MergedRef(sid, r, f.name, origin)
        if prev is not None:
            mr.history = prev.history + [prev.source]
        target.refs[sid] = mr


# ------------------------------------------------------------------------------------------------
# eksport
# ------------------------------------------------------------------------------------------------

def cell_file_rel(key: str) -> str:
    kind, rest = key.split(":", 1)
    if kind == "ext":
        x, y = rest.split(",")
        return f"cells/ext/{int(x)}_{int(y)}.json"
    return f"cells/int/{slug(rest)}.json"


def select_cells(world: World, names: list[str] = (), grids: list[tuple] = (), all_cells: bool = False) -> list[str]:
    if all_cells:
        return sorted(world.cells)
    out = []
    lname = [n.lower() for n in names]
    for k, mc in world.cells.items():
        nm = (mc.cell.name or "").lower()
        if lname and any(nm == n or nm.startswith(n + ",") for n in lname):
            out.append(k)
        elif not mc.cell.interior and tuple(mc.cell.grid) in set(map(tuple, grids)):
            out.append(k)
    return sorted(set(out))


def ref_to_json(mr: MergedRef, world: World) -> dict:
    r = mr.ref
    base = world.objects.get(r.base.lower())
    t = coords.ref_transform_to_godot(r.pos, r.rot, r.scale)
    j = {
        "sid": mr.sid,
        "base": r.base,
        "mw": {"pos": [round(float(v), 4) for v in r.pos], "rot": [round(float(v), 6) for v in r.rot],
               "scale": round(float(r.scale), 6)},
        "godot": {"origin": [round(v, 6) for v in t["origin"]], "quat": [round(v, 8) for v in t["quat"]],
                  "scale": round(float(r.scale), 6)},
        "source": mr.source,
    }
    if mr.origin.lower() != mr.source.lower():
        j["origin"] = mr.origin
    if mr.history:
        j["overridden"] = mr.history
    if r.extra:
        ex = dict(r.extra)
        if "door_dest" in ex:
            d = ex["door_dest"]
            tt = coords.ref_transform_to_godot(d["pos"], d["rot"], 1.0)
            ex["door_dest"] = {**d, "godot": {"origin": tt["origin"], "quat": tt["quat"]}}
        j["extra"] = ex
    if base is None:
        j["missing_base"] = True
    return j


def cell_to_json(mc: MergedCell, world: World) -> dict:
    c = mc.cell
    j = {
        "format": FORMAT, "version": FORMAT_VERSION,
        "key": mc.key, "name": c.name, "interior": c.interior,
        "grid": list(c.grid) if not c.interior else None,
        "region": c.region, "flags": c.flags, "sources": mc.sources,
        "refs": [ref_to_json(mr, world) for mr in sorted(mc.refs.values(), key=lambda m: m.sid)],
    }
    if c.ambient:
        a = c.ambient
        rgb = lambda v: [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF]  # noqa: E731 – kolory TES3: 0x00BBGGRR
        j["ambient"] = {**a, "ambient_rgb": rgb(a["ambient"]), "sunlight_rgb": rgb(a["sunlight"]),
                        "fog_rgb": rgb(a["fog"])}
    if c.interior:
        j["has_water"] = bool(c.flags & 0x02)
        j["behave_like_exterior"] = bool(c.flags & 0x80)
        if c.water is not None:
            j["water_height_m"] = c.water * coords.SCALE
    else:
        j["has_water"] = True
        j["water_height_m"] = 0.0  # poziom morza w świecie zewnętrznym
    if not c.interior:
        j["origin_godot"] = coords.pos_to_godot((c.grid[0] * coords.CELL_SIZE, c.grid[1] * coords.CELL_SIZE, 0)).tolist()
        j["terrain"] = f"terrain/{c.grid[0]}_{c.grid[1]}.json" if tuple(c.grid) in world.lands else None
    return j


def _b64(a: np.ndarray) -> str:
    return base64.b64encode(np.ascontiguousarray(a).tobytes()).decode("ascii")


def terrain_to_json(grid: tuple, land: Land, ltex: dict, source: str,
                    texture_resolver: Callable[[str], Optional[str]]) -> dict:
    """Teren komórki: 65×65 wierzchołków co 128 jedn., wiersze od południa (y rośnie na północ)."""
    j = {"format": FORMAT, "version": FORMAT_VERSION, "grid": list(grid), "source": source,
         "size": 65, "spacing_m": 128 * coords.SCALE, "cell_size_m": coords.CELL_SIZE * coords.SCALE,
         "layout": "row-major [y][x], y = północ MW = -Z Godota, x = +X",
         "origin_godot": coords.pos_to_godot((grid[0] * coords.CELL_SIZE, grid[1] * coords.CELL_SIZE, 0)).tolist()}
    if land.heights is not None:
        h = (land.heights * coords.SCALE).astype("<f4")
        j["heights_f32_b64"] = _b64(h)
        j["height_min_m"] = float(h.min())
        j["height_max_m"] = float(h.max())
    else:
        j["heights_f32_b64"] = None
    if land.normals is not None:
        n = land.normals.astype(np.float32) / 127.0
        ng = np.stack([n[..., 0], n[..., 2], -n[..., 1]], axis=-1)  # → Godot
        ng = (np.clip(ng, -1, 1) * 127).astype(np.int8)
        j["normals_i8_b64"] = _b64(ng)
    if land.colors is not None:
        j["colors_u8_b64"] = _b64(land.colors.astype(np.uint8))
    if land.textures is not None:
        palette: list[str] = []
        pidx = {}
        grid_idx = np.zeros((16, 16), np.uint8)
        missing = []
        for y in range(16):
            for x in range(16):
                v = int(land.textures[y, x])
                tex = "_land_default.dds" if v == 0 else ltex.get(v - 1)
                if tex is None:
                    missing.append(v)
                    tex = "_land_default.dds"
                png = texture_resolver(tex) or ""
                if png not in pidx:
                    pidx[png] = len(palette)
                    palette.append(png)
                grid_idx[y, x] = pidx[png]
        j["texture_palette"] = palette
        j["texture_grid_u8_b64"] = _b64(grid_idx)
        if missing:
            j["missing_ltex"] = sorted(set(missing))
    return j


def write_json(path: Path, obj, compact: bool = False):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        if compact:
            json.dump(obj, fh, ensure_ascii=False, separators=(",", ":"))
        else:
            json.dump(obj, fh, ensure_ascii=False, indent=1)
    tmp.replace(path)
