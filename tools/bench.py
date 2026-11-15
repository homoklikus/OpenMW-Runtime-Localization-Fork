#!/usr/bin/env python3
"""Benchmark konwertera na danych syntetycznych (bez plików gry).

  python3 tools/bench.py --work /tmp/mwbench [--models 2000] [--textures 400] [--jobs 1,2]
                         [--esm-cells 2500 --esm-refs 40 --esm-lands 1400 --esm-objects 30000]

Mierzy: modele/s, tekstury/s, czas wczytania dużego ESM, szczytowe RSS, rozmiary wyników,
czas przebiegu „bez zmian” (cache). Wyniki → JSON na stdout i <work>/bench.json.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import resource
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "converter"))

from mwconv import synthetic  # noqa: E402
from mwconv.esm import writer as W  # noqa: E402
from mwconv.synthetic_world import heights_for, vtex_for  # noqa: E402


def make_models(data: Path, n: int, n_tex: int):
    makers = [synthetic.make_hut, synthetic.make_windmill, synthetic.make_skinned, synthetic.make_crate]
    blobs = [m() for m in makers]
    for i in range(n):
        p = data / "meshes" / "bench" / f"m{i // 500:02d}" / f"model_{i:05d}.nif"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(blobs[i % len(blobs)])
    tex_makers = [synthetic.tex_planks, synthetic.tex_roof, synthetic.tex_sign, synthetic.tex_checker]
    for i in range(n_tex):
        im = tex_makers[i % 4](256) if i % 4 != 3 else tex_makers[3](256)
        fmt = "DXT5" if i % 4 == 2 else "DXT1"
        synthetic.save_dds(im, data / "textures" / "bench" / f"tx_bench_{i:05d}.dds", fmt)
    synthetic.write_assets(data, make_bsa=False)


def make_big_esm(path: Path, cells: int, refs: int, lands: int, objects: int):
    recs = [W.ltex("g", 0, "tx_synth_grass.tga"), W.ltex("d", 1, "tx_synth_dirt.tga"), W.ltex("s", 2, "tx_synth_stone.tga")]
    for i in range(objects):
        recs.append(W.stat(f"bench_obj_{i:05d}", f"bench\\m{(i % 2000) // 500:02d}\\model_{i % 2000:05d}.nif"))
    side = int(math.ceil(math.sqrt(cells)))
    rn = 0
    h = heights_for((0, 0))
    vt = vtex_for((0, 0))
    land_blob = W.land((0, 0), h, vt)
    for c in range(cells):
        gx, gy = c % side - side // 2, c // side - side // 2
        rs = []
        for k in range(refs):
            rn += 1
            rs.append(W.ref_subs(rn, f"bench_obj_{(c * refs + k) % objects:05d}",
                                 (gx * 8192 + (k * 197) % 8192, gy * 8192 + (k * 389) % 8192, 500.0), (0, 0, k * 0.1)))
        recs.append(W.cell("", (gx, gy), False, rs))
        if c < lands:
            # ten sam teren, inne współrzędne (podmiana INTV)
            import struct
            blob = bytearray(land_blob)
            i = blob.find(b"INTV")
            blob[i + 8:i + 16] = struct.pack("<ii", gx, gy)
            recs.append(bytes(blob))
    path.write_bytes(W.header([], len(recs), desc="bench") + b"".join(recs))


def run_convert(data: Path, out: Path, jobs: int, extra=()) -> tuple[dict, float, float]:
    cmd = [sys.executable, "-m", "mwconv", "convert", "--data", str(data), "--content", "bench.esm",
           "--out", str(out), "--jobs", str(jobs), *extra]
    t0 = time.perf_counter()
    r = subprocess.run(cmd, cwd=ROOT / "converter", capture_output=True, text=True)
    el = time.perf_counter() - t0
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("konwersja nie powiodła się")
    rep = json.loads((out / "reports" / "conversion.json").read_text())
    ru = resource.getrusage(resource.RUSAGE_CHILDREN)
    return rep["stats"], el, ru.ru_maxrss / 1024.0


def du(p: Path) -> float:
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) / 1e6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="/tmp/mwbench")
    ap.add_argument("--models", type=int, default=2000)
    ap.add_argument("--textures", type=int, default=400)
    ap.add_argument("--jobs", default="1,2")
    ap.add_argument("--esm-cells", type=int, default=2500)
    ap.add_argument("--esm-refs", type=int, default=40)
    ap.add_argument("--esm-lands", type=int, default=1400)
    ap.add_argument("--esm-objects", type=int, default=30000)
    a = ap.parse_args()
    work = Path(a.work)
    shutil.rmtree(work, ignore_errors=True)
    data = work / "Data Files"
    t0 = time.perf_counter()
    make_models(data, a.models, a.textures)
    make_big_esm(data / "bench.esm", a.esm_cells, a.esm_refs, a.esm_lands, a.esm_objects)
    gen_s = time.perf_counter() - t0
    res = {"input": {"models": a.models, "textures": a.textures, "esm_mb": round((data / "bench.esm").stat().st_size / 1e6, 1),
                     "esm_cells": a.esm_cells, "esm_refs": a.esm_cells * a.esm_refs, "esm_lands": a.esm_lands,
                     "esm_objects": a.esm_objects, "generation_s": round(gen_s, 1)},
           "machine": {"cpus": os.cpu_count(), "python": sys.version.split()[0]}, "runs": []}
    for j in [int(x) for x in a.jobs.split(",")]:
        out = work / f"out_j{j}"
        # 1) pełna konwersja modeli (wszystkie NIF) + 9 komórek ze świata
        stats, el, rss = run_convert(data, out, j, ["--all-models", "--all-textures", "--grid-range=-1,-1,1,1"])
        # 2) ponowny przebieg bez zmian (cache)
        stats2, el2, _ = run_convert(data, out, j, ["--all-models", "--all-textures", "--grid-range=-1,-1,1,1"])
        res["runs"].append({
            "jobs": j, "wall_s": round(el, 2), "models": stats.get("models"), "textures": stats.get("textures"),
            "world_load": stats.get("world_load"), "world_export": {k: v for k, v in stats.get("world_export", {}).items() if k != "missing_models"},
            "children_peak_rss_mb": round(rss, 1), "output_mb": round(du(out), 1),
            "no_change_wall_s": round(el2, 2), "no_change_total_s": stats2.get("total_seconds"),
        })
    (work / "bench.json").write_text(json.dumps(res, indent=1))
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
