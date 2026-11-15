"""Skan wszystkich NIF z VFS: odczyt + konwersja w pamięci, bez zapisu modeli.

Cel: przy pierwszym uruchomieniu na prawdziwej grze jednym poleceniem dostać pełną mapę problemów –
błędy pogrupowane wg typu bloku i komunikatu, histogram typów bloków, kontrolerów i strat konwersji.
Raport zawiera tylko metadane (ścieżki, typy bloków, komunikaty) – żadnej geometrii ani tekstur.
"""

from __future__ import annotations

import collections
import concurrent.futures as cf
import os
import re
import time
from pathlib import Path

from .nif.reader import NifError, parse
from .nif2gltf import NifToGltf, TextureRef
from .vfs import Vfs

_V: Vfs | None = None


def _init(data_dirs, archives):
    global _V
    _V = Vfs.from_install(data_dirs, archives)


def _norm_msg(m: str) -> str:
    """Komunikat bez liczb i nazw plików – do grupowania."""
    m = re.sub(r"^[^:]*\.(nif|kf): ", "", m, flags=re.I)
    return re.sub(r"\d+", "N", m)[:160]


def scan_one(key: str) -> dict:
    t0 = time.perf_counter()
    data = _V.read(key)
    out = {"key": key, "size": len(data)}
    try:
        nif = parse(data, key)
        out["blocks"] = collections.Counter(b.type for b in nif.blocks)
        out["trailing"] = nif.trailing
        if key.endswith(".nif"):
            _glb, rep = NifToGltf(nif, key, lambda n: TextureRef("x") if _V.resolve_texture(n) else None).convert()
            out["lossy"] = [_norm_msg(x) for x in rep.lossy]
            out["unsupported"] = [_norm_msg(x) for x in rep.unsupported]
            out["missing_textures"] = rep.missing_textures
            out["tris"] = rep.triangles
        out["ok"] = True
    except NifError as e:
        out.update(ok=False, error=str(e), group=f"{e.block_type or '-'} | {_norm_msg(str(e))}",
                   block_index=e.block_index, offset=e.offset,
                   last_blocks=[b.type for b in e.partial[-3:]])
    except Exception as e:  # noqa: BLE001 – błąd konwertera, nie pliku
        out.update(ok=False, error=f"{type(e).__name__}: {e}", group=f"KONWERTER | {type(e).__name__}")
    out["ms"] = (time.perf_counter() - t0) * 1000
    return out


def scan(data_dirs: list, archives: list, jobs: int = 0, limit: int = 0, log=print) -> dict:
    v = Vfs.from_install(data_dirs, archives)
    keys = v.list("meshes/", ".nif") + v.list("meshes/", ".kf")
    if limit:
        keys = keys[:limit]
    jobs = jobs or max(1, min(4, os.cpu_count() or 2))
    t0 = time.perf_counter()
    results = []
    with cf.ProcessPoolExecutor(jobs, initializer=_init, initargs=(data_dirs, archives)) as ex:
        for i, r in enumerate(ex.map(scan_one, keys, chunksize=16)):
            results.append(r)
            if (i + 1) % 500 == 0:
                log(f"[scan] {i + 1}/{len(keys)}")
    el = time.perf_counter() - t0
    blocks = collections.Counter()
    lossy = collections.Counter()
    unsup = collections.Counter()
    groups: dict[str, list] = collections.defaultdict(list)
    missing = collections.Counter()
    for r in results:
        blocks.update(r.get("blocks", {}))
        lossy.update(set(r.get("lossy", [])))
        unsup.update(set(r.get("unsupported", [])))
        missing.update(r.get("missing_textures", []))
        if not r["ok"]:
            groups[r["group"]].append({k: r.get(k) for k in ("key", "error", "block_index", "offset", "last_blocks")})
    ok = sum(r["ok"] for r in results)
    return {
        "files": len(results), "ok": ok, "failed": len(results) - ok, "seconds": round(el, 2),
        "per_second": round(len(results) / el, 1) if el else None,
        "non_zero_trailing": [r["key"] for r in results if r.get("trailing")],
        "error_groups": {g: {"count": len(v), "examples": v[:5]} for g, v in
                         sorted(groups.items(), key=lambda kv: -len(kv[1]))},
        "block_types": dict(blocks.most_common()),
        "lossy_features": dict(lossy.most_common()),
        "unsupported_features": dict(unsup.most_common()),
        "missing_textures_top": dict(missing.most_common(50)),
        "slowest_ms": sorted(((round(r["ms"], 1), r["key"]) for r in results), reverse=True)[:10],
    }
