"""Niezależna weryfikacja geometrii MCP względem silnika OpenMW.

1. Granice obiektów z gry (Lua `getBoundingBox` = RenderingManager::getCullSafeBoundingBox: rogi AABB każdego
   rysowanego elementu przekształcone do świata) vs granice z parsera NIF MCP. Silnik liczy je na grafie po
   optymalizatorze (spłaszczone statyczne transformacje, połączona geometria nieprzezroczysta; kształty z alfą
   osobno), a dla obiektów stronicowanych składa obrót w odwrotnej kolejności — MCP liczy warianty
   (direct/inverse × flattened/flattened_shapes/shapes) i raportuje najlepiej pasujący.
2. Niebo przewidziane promieniami vs piksele nieba na zrzucie z gry (prosty detektor koloru).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

import numpy as np

from . import objects, scene, visibility


def _refnum(lua_id: str, files: int) -> Optional[tuple]:
    try:
        v = int(lua_id, 16)
    except ValueError:
        return None                                # obiekt wygenerowany (@0x…) — brak w ESM
    return (v & 0xFFFFFF, v >> 24)


def _engine_aabb(so: scene.SceneObject, order: str, mode: str = "shapes"):
    """mode "shapes": rogi AABB każdego kształtu (CullSafeBoundsVisitor na niezoptymalizowanym grafie);
    mode "flattened": rogi AABB całego modelu (optymalizator OpenMW spłaszcza statyczne transformacje i łączy
    geometrię, więc granica liczona jest w układzie modelu)."""
    g = so.geometry
    if g is None:
        return None
    m = objects.world_matrix(so.ref, order)
    if mode == "flattened":
        return None if g.aabb is None else objects.aabb_of(objects.transform(objects.corners(*g.aabb), m))
    if mode == "flattened_shapes":                # transformacje spłaszczone, kształty nie połączone (np. z alfą)
        pts = [objects.transform(objects.corners(*objects.aabb_of(s.model_vertices())), m)
               for s in g.shapes if s.rendered and len(s.local_vertices)]
        return objects.aabb_of(np.vstack(pts)) if pts else None
    pts = []
    for s in g.shapes:
        if s.rendered and len(s.local_vertices):
            lo, hi = s.local_vertices.min(axis=0), s.local_vertices.max(axis=0)
            pts.append(objects.transform(objects.corners(lo, hi), m @ s.matrix))
    return objects.aabb_of(np.vstack(pts)) if pts else None


def content_offset(by_ref: dict, bounds: list[dict], max_offset: int = 4) -> tuple[int, int]:
    """Przesunięcie indeksu pliku silnika względem listy content= profilu (OpenMW dokłada na początek
    wbudowane pliki, np. builtin.omwscripts). Wybór: przesunięcie z największą liczbą zgodnych ID rekordów."""
    best = (0, -1)
    sample = bounds[:3000]
    for off in range(max_offset + 1):
        hits = 0
        for b in sample:
            rn = _refnum(b["id"], 0)
            ref = by_ref.get((rn[0], rn[1] - off)) if rn else None
            if ref is not None and ref.id == b["record"].lower():
                hits += 1
        if hits > best[1]:
            best = (off, hits)
    return best


def compare_bounds(sc: scene.Scene, bounds: list[dict], tol: float = 2.0) -> dict:
    by_ref = {}
    for cell, refs in sc.world.cells.items():
        for rn, ref in refs.items():
            by_ref[rn] = ref
    offset, _ = content_offset(by_ref, bounds)
    record_mismatch = 0
    errs, rows, missing, no_geom, empty_engine = [], [], 0, 0, 0
    cell_objs: dict = {}
    for b in bounds:
        rn = _refnum(b["id"], len(sc.world.files))
        ref = by_ref.get((rn[0], rn[1] - offset)) if rn else None
        if ref is None:
            missing += 1
            continue
        if ref.id != b["record"].lower():
            record_mismatch += 1
            continue
        half = np.array(b["half"])
        if np.any(half < 0) or np.all(np.abs(half) > 1e30):
            empty_engine += 1
            continue
        if ref.cell not in cell_objs:
            cell_objs[ref.cell] = {o.ref.refnum: o for o in sc.objects([ref.cell], None)}
        so = cell_objs[ref.cell].get(ref.refnum)
        if so is None or so.geometry is None:
            no_geom += 1
            continue
        e_lo = np.array(b["center"]) - half
        e_hi = np.array(b["center"]) + half
        best = None
        for order in ("direct", "inverse"):
            for mode in ("flattened", "flattened_shapes", "shapes"):
                a = _engine_aabb(so, order, mode)
                if a is None:
                    continue
                err = float(max(np.abs(a[0] - e_lo).max(), np.abs(a[1] - e_hi).max()))
                if best is None or err < best[0] - 1e-6:
                    best = (err, order, mode)
        if best is None:
            no_geom += 1
            continue
        tilted = abs(ref.rot[0]) > 1e-4 or abs(ref.rot[1]) > 1e-4
        g = so.geometry
        errs.append(best[0])
        rows.append({"id": b["id"], "record": b["record"], "model": so.model, "error": round(best[0], 2),
                     "order": best[1], "mode": best[2], "tilted": tilted, "size": [round(float(v), 1) for v in 2 * half],
                     "billboard": bool(g.stats["billboard_shapes"]), "animated": bool(g.stats["animated_shapes"]),
                     "skinned": bool(g.stats["skinned_shapes"])})
    e = np.array(errs) if errs else np.zeros(0)
    rows.sort(key=lambda r: -r["error"])
    return {"compared": int(len(e)), "content_index_offset": offset, "record_id_mismatch": record_mismatch,
            "missing_in_mcp": missing, "no_geometry": no_geom,
            "engine_empty": empty_engine,
            "within_tol": int((e <= tol).sum()), "tol": tol,
            "median_error": round(float(np.median(e)), 3) if len(e) else None,
            "p95_error": round(float(np.percentile(e, 95)), 3) if len(e) else None,
            "max_error": round(float(e.max()), 2) if len(e) else None,
            "inverse_order_matches": sum(1 for r in rows if r["order"] == "inverse" and r["tilted"]),
            "best_mode": {m: sum(1 for r in rows if r["mode"] == m) for m in ("flattened", "flattened_shapes", "shapes")},
            "worst": rows[:15]}


def sky_mask(png: Path, w: int, h: int) -> np.ndarray:
    from PIL import Image
    im = np.asarray(Image.open(png).convert("RGB").resize((w, h), Image.BILINEAR)).astype(float)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    return (b > r * 1.12) & (b > g * 1.02) & (b > 110)


def compare_sky(cam: visibility.Camera, grid, objs: list, png: Path, w: int = 96, h: int = 54) -> dict:
    fr = visibility.frame(cam, grid, objs, w, h, max_dist=20000.0)
    act = sky_mask(png, w, h)

    def iou(p):
        u = (p | act).sum()
        return round(float((p & act).sum() / u), 3) if u else None
    strict = fr["class"] == visibility.SKY
    loose = fr["class_alpha_transparent"] == visibility.SKY
    terrain_only = visibility.frame(cam, grid, [], w, h, max_dist=20000.0)["class"] == visibility.SKY
    return {"sky_screenshot": round(float(act.mean()), 3), "sky_predicted": round(float(strict.mean()), 3),
            "sky_predicted_alpha_transparent": round(float(loose.mean()), 3),
            "iou": iou(strict), "iou_alpha_transparent": iou(loose), "iou_terrain_only": iou(terrain_only),
            "pixel_agreement": round(float((strict == act).mean()), 3)}
