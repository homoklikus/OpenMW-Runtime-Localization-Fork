"""Scena do analizy widoczności: teren (siatka wysokości jak w OpenMW) + obiekty z geometrią modeli NIF.

* Teren: wierzchołki LAND co 128 j., triangulacja „diamond” jak `land.LandIndex.height_at` (= fork
  getProceduralHeightAt / buffercache.cpp), liczona wektorowo (numpy).
* Obiekty: referencje z `objects.WorldObjects`, modele z VFS profilu (`bsa.VfsReader`: loose > BSA, późniejszy
  katalog data= wygrywa), geometria z `nif.model_geometry` (tylko kształty rysowane przez silnik).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from . import nif, objects
from .land import CELL, LAND_SIZE, LandIndex

STEP = CELL / (LAND_SIZE - 1)                    # 128 j.


def _plane(a, b, c, x, y):
    """Jak land._plane_z: płaszczyzna przez trzy punkty (x, y, z), wartość z w (x, y)."""
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    return a[2] - (nx * (x - a[0]) + ny * (y - a[1])) / nz


class HeightGrid:
    """Wierzchołki terenu dla prostokąta komórek; brak LAND ⇒ NaN."""

    def __init__(self, land: LandIndex, cx0: int, cy0: int, cx1: int, cy1: int):
        self.cx0, self.cy0 = cx0, cy0
        nx, ny = (cx1 - cx0 + 1) * 64 + 1, (cy1 - cy0 + 1) * 64 + 1
        self.h = np.full((ny, nx), np.nan)
        for cy in range(cy0, cy1 + 1):
            for cx in range(cx0, cx1 + 1):
                ld = land.lands.get((cx, cy))
                if ld is None or ld.heights() is None:
                    continue
                a = np.asarray(ld.heights(), dtype=np.float64).reshape(LAND_SIZE, LAND_SIZE)
                oy, ox = (cy - cy0) * 64, (cx - cx0) * 64
                self.h[oy:oy + LAND_SIZE, ox:ox + LAND_SIZE] = a
        self.x0, self.y0 = cx0 * CELL, cy0 * CELL

    def height(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        x = np.asarray(x, dtype=np.float64)
        y = np.asarray(y, dtype=np.float64)
        gx = (x - self.x0) / STEP
        gy = (y - self.y0) / STEP
        ny, nx = self.h.shape
        inside = (gx >= 0) & (gy >= 0) & (gx < nx - 1) & (gy < ny - 1)
        gx = np.clip(gx, 0, nx - 1.000001)
        gy = np.clip(gy, 0, ny - 1.000001)
        sx = np.floor(gx).astype(np.int64)
        sy = np.floor(gy).astype(np.int64)
        xp, yp = gx - sx, gy - sy
        h00 = self.h[sy, sx]
        h10 = self.h[sy, sx + 1]
        h11 = self.h[sy + 1, sx + 1]
        h01 = self.h[sy + 1, sx]
        # parzystość kwadratu liczona w lokalnej siatce komórki (jak land.py); 64 parzyste ⇒ zgodna globalnie
        odd = ((sx + sy) & 1) == 1
        zero, one = np.zeros_like(xp), np.ones_like(xp)
        v0 = (zero, zero, h00)
        v1 = (one, zero, h10)
        v2 = (one, one, h11)
        v3 = (zero, one, h01)
        # nieparzysty: przekątna v1–v3; (1−yp) > xp ⇒ (v0, v1, v3), inaczej (v1, v2, v3)
        # parzysty: przekątna v0–v2; yp > xp ⇒ (v0, v2, v3), inaczej (v0, v1, v2)
        z = np.where(odd,
                     np.where((1 - yp) > xp, _plane(v0, v1, v3, xp, yp), _plane(v1, v2, v3, xp, yp)),
                     np.where(yp > xp, _plane(v0, v2, v3, xp, yp), _plane(v0, v1, v2, xp, yp)))
        z[~inside] = np.nan
        return z


@dataclass
class SceneObject:
    ref: objects.Ref
    type: str
    model: Optional[str]
    provider: Optional[dict]
    matrix: np.ndarray
    geometry: Optional[nif.ModelGeometry]
    error: str = ""
    aabb: Optional[tuple] = None                 # AABB wierzchołków w świecie
    engine_aabb: Optional[tuple] = None          # jak CullSafeBoundsVisitor (rogi AABB kształtów)
    triangles: Optional[np.ndarray] = None       # (T, 3, 3) w świecie
    alpha: Optional[np.ndarray] = None

    @property
    def label(self) -> str:
        return f"{self.ref.id} [{self.type}] {self.model or ''}".strip()


@dataclass
class Scene:
    land: LandIndex
    world: objects.WorldObjects
    vfs: object                                  # bsa.VfsReader
    model_cache: dict = field(default_factory=dict)

    def model(self, key: str):
        if key not in self.model_cache:
            try:
                data = self.vfs.read(key)
                self.model_cache[key] = (nif.model_geometry(nif.parse(data, key)), "")
            except FileNotFoundError:
                self.model_cache[key] = (None, "brak pliku w VFS")
            except nif.NifError as e:
                self.model_cache[key] = (None, f"błąd NIF: {e}")
        return self.model_cache[key]

    def objects(self, cells: list, types: Optional[set] = None, order: str = "direct") -> list[SceneObject]:
        out = []
        for c in cells:
            for ref in self.world.refs(*c):
                base = self.world.base(ref.id)
                if base is None:
                    continue
                t, modl, _ = base
                if types is not None and t not in types:
                    continue
                key = objects.model_key(modl)
                m = objects.world_matrix(ref, order)
                so = SceneObject(ref, t, key, self.vfs.provider(key) if key else None, m, None)
                if key is None:
                    so.error = "brak modelu (MODL)"
                    out.append(so)
                    continue
                g, err = self.model(key)
                so.geometry, so.error = g, err
                if g is not None:
                    if g.aabb is not None:
                        pts = np.vstack([s.model_vertices() for s in g.shapes if s.rendered and len(s.local_vertices)])
                        so.aabb = objects.aabb_of(objects.transform(pts, m))
                    if g.engine_aabb is not None:
                        eng = []
                        for s in g.shapes:
                            if s.rendered and len(s.local_vertices):
                                lo, hi = s.local_vertices.min(axis=0), s.local_vertices.max(axis=0)
                                c8 = objects.corners(lo, hi)
                                eng.append(objects.transform(c8, m @ s.matrix))
                        so.engine_aabb = objects.aabb_of(np.vstack(eng))
                    if len(g.triangles):
                        so.triangles = g.triangles @ m[:3, :3].T + m[:3, 3]
                        so.alpha = g.triangle_alpha
                out.append(so)
        return out

    def height_grid(self, cx: int, cy: int, radius: int = 1) -> HeightGrid:
        return HeightGrid(self.land, cx - radius, cy - radius, cx + radius, cy + radius)


def object_report(so: SceneObject, own_cell: tuple) -> dict:
    def box(b):
        return None if b is None else {"min": [round(float(v), 1) for v in b[0]],
                                       "max": [round(float(v), 1) for v in b[1]]}
    crosses = None
    if so.aabb is not None:
        lo, hi = so.aabb
        x0, y0 = own_cell[0] * CELL, own_cell[1] * CELL
        crosses = bool(lo[0] < x0 or lo[1] < y0 or hi[0] > x0 + CELL or hi[1] > y0 + CELL)
    g = so.geometry
    return {"id": so.ref.id, "type": so.type, "refnum": list(so.ref.refnum), "cell": list(so.ref.cell),
            "moved_from": list(so.ref.moved_from) if so.ref.moved_from else None,
            "position": [round(v, 1) for v in so.ref.pos], "rotation": [round(v, 4) for v in so.ref.rot],
            "scale": round(so.ref.scale, 3), "model": so.model,
            "provider": None if so.provider is None else {"kind": so.provider["kind"], "root": so.provider["root"]},
            "aabb": box(so.aabb), "engine_aabb": box(so.engine_aabb), "crosses_cell_border": crosses,
            "height": None if so.aabb is None else round(float(so.aabb[1][2] - so.aabb[0][2]), 1),
            "triangles": 0 if so.triangles is None else int(len(so.triangles)),
            "alpha_share": None if so.alpha is None or not len(so.alpha) else round(float((so.alpha > 0).mean()), 3),
            "billboard_or_animated": bool(g and (g.stats["billboard_shapes"] or g.stats["animated_shapes"])),
            "error": so.error or None}
