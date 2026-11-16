"""Mapa świata (etap 10) jak OpenMW GlobalMap: każda komórka zewnętrzna = `cell_px` × `cell_px` pikseli (ustawienie
OpenMW „global map cell size” = 18), kolor z palety `omw_map_color_palette.dds` (256 × 1, z OpenMW – GPL) według
wysokości WNAM (9 × 9 na komórkę, −128…127 → indeks 0…255). Wynik: world/map/global.png (północ u góry) i
world/map/map.json (zakres siatki, rozmiar komórki, nazwane komórki zewnętrzne – znaczniki miejsc)."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

PALETTE = Path(__file__).parent / "data" / "omw_map_color_palette.dds"


def palette() -> np.ndarray:
    im = Image.open(PALETTE).convert("RGB")
    return np.array([im.getpixel((i, 0)) for i in range(256)], dtype=np.uint8)


def export(world, wdir: Path, write_json, cell_px: int = 18) -> dict:
    grids = {}
    for k, c in world.cells.items():
        cell = c.cell
        if not cell.interior:
            grids[tuple(cell.grid)] = cell.name or ""
    if not grids:
        return {"cells": 0}
    xs = [g[0] for g in grids]
    ys = [g[1] for g in grids]
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)
    w = cell_px * (max_x - min_x + 1)
    h = cell_px * (max_y - min_y + 1)
    lut = palette()
    idx = np.zeros((h, w), dtype=np.int32)            # wiersz 0 = najbardziej na południe (jak obraz OSG)
    v = (np.arange(cell_px) * 9) // cell_px           # cellX → vertexX (0..8)
    for g, entry in world.lands.items():
        land = entry[0]
        if land is None or land.wnam is None:
            continue
        x, y = g
        if not (min_x <= x <= max_x and min_y <= y <= max_y):
            continue
        block = land.wnam.astype(np.int32)[np.ix_(v, v)] + 128
        ox, oy = (x - min_x) * cell_px, (y - min_y) * cell_px
        idx[oy:oy + cell_px, ox:ox + cell_px] = block
    rgb = lut[idx][::-1]                               # PNG: północ u góry
    out = wdir / "map"
    out.mkdir(parents=True, exist_ok=True)
    tmp = out / "global.tmp.png"
    Image.fromarray(np.ascontiguousarray(rgb), "RGB").save(tmp, "PNG", compress_level=6)
    tmp.replace(out / "global.png")
    named = sorted([[g[0], g[1], n] for g, n in grids.items() if n])
    write_json(out / "map.json", {"format": "mwgodot-worldmap", "version": 1, "cell_px": cell_px,
                                  "min": [min_x, min_y], "max": [max_x, max_y], "size": [w, h], "named": named})
    return {"cells": len(grids), "size": [w, h], "named": len(named)}
