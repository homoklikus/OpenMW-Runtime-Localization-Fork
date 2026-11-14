"""Teren TES3 (LAND/LTEX) — odwzorowanie OpenMW 0.51.0 i forka, tylko odczyt.

Źródła semantyki:
* components/esm3/loadland.cpp — VHGT: offset + delty (kolumna 0 kumulowana po wierszach, potem wiersz), × sHeightScale=8;
  VTEX: 16×16 uint16 zapisane blokami 4×4 (transposeTextureData).
* apps/openmw/mwworld/store.cpp — LTEX: mapowanie (plugin, INTV) → ID, ID → DATA (później wczytany wygrywa);
  LAND: ostatni plugin z rekordem dla komórki wygrywa; VTEX 0 = tekstura domyślna, inaczej LTEX[indeks-1] z TEGO pluginu.
* fork apps/openmw/mwrender/terrainstorage.cpp — getProceduralHeightAt (triangulacja „diamond” jak buffercache.cpp),
  getSlopeDegreesAt (różnice centralne co 128 j.), getLandTextureAt (floor(local·16), tryb 'fork').
* tryb 'render' (HIPOTEZA do weryfikacji wizualnej): components/esmterrain/gridsampling.hpp::sampleBlendmaps
  (wiersz X przesunięty o −1) + components/terrain/material.cpp::BlendmapTexMat (skala B/(B+1), przesunięcie
  ±1/(4B)) ⇒ dominujący teksel widocznej tekstury: X = floor(t − 0.25), Y = floor(t + 0.25), t = local·16.
"""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

LAND_SIZE = 65
TEX_SIZE = 16
CELL = 8192.0
HEIGHT_SCALE = 8.0
DEFAULT_TEXTURE = "_land_default.dds"


def _records(data: bytes):
    o = 0
    n = len(data)
    while o + 16 <= n:
        t = data[o:o + 4]
        size = struct.unpack_from("<I", data, o + 4)[0]
        yield t, o + 16, size
        o += 16 + size


def _subs(data: bytes, start: int, size: int):
    o, end = start, start + size
    while o + 8 <= end:
        t = data[o:o + 4]
        n = struct.unpack_from("<I", data, o + 4)[0]
        yield t, o + 8, n
        o += 8 + n


def _plane_z(a, b, c, x, y):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    return a[2] - (nx * (x - a[0]) + ny * (y - a[1])) / nz


def transpose_vtex(raw: tuple[int, ...]) -> list[int]:
    out = [0] * 256
    pos = 0
    for y1 in range(4):
        for x1 in range(4):
            for y2 in range(4):
                for x2 in range(4):
                    out[(y1 * 4 + y2) * 16 + (x1 * 4 + x2)] = raw[pos]
                    pos += 1
    return out


def decode_vhgt(buf: bytes) -> list[float]:
    offset = struct.unpack_from("<f", buf, 0)[0]
    deltas = struct.unpack_from(f"<{LAND_SIZE * LAND_SIZE}b", buf, 4)
    heights = [0.0] * (LAND_SIZE * LAND_SIZE)
    row = offset
    for y in range(LAND_SIZE):
        row += deltas[y * LAND_SIZE]
        heights[y * LAND_SIZE] = row * HEIGHT_SCALE
        col = row
        for x in range(1, LAND_SIZE):
            col += deltas[y * LAND_SIZE + x]
            heights[y * LAND_SIZE + x] = col * HEIGHT_SCALE
    return heights


@dataclass
class _Land:
    plugin: int
    file: str
    vhgt: Optional[bytes]
    vtex: Optional[bytes]
    _heights: Optional[list] = None
    _tex: Optional[list] = None

    def heights(self):
        if self._heights is None and self.vhgt is not None:
            self._heights = decode_vhgt(self.vhgt)
        return self._heights

    def textures(self):
        if self._tex is None and self.vtex is not None:
            self._tex = transpose_vtex(struct.unpack("<256H", self.vtex[:512]))
        return self._tex


@dataclass
class LandIndex:
    files: list[str] = field(default_factory=list)
    lands: dict = field(default_factory=dict)          # (x, y) -> _Land
    ltex_map: dict = field(default_factory=dict)       # (plugin, index) -> id
    ltex_tex: dict = field(default_factory=dict)       # id -> texture
    overridden: dict = field(default_factory=dict)     # (x, y) -> [pliki]

    @classmethod
    def load(cls, content_files: list[Path]) -> "LandIndex":
        idx = cls()
        for plugin, path in enumerate(content_files):
            idx.files.append(str(path))
            if path.suffix.lower() not in (".esm", ".esp", ".omwaddon", ".omwgame"):
                continue
            data = path.read_bytes()
            for t, start, size in _records(data):
                if t == b"LTEX":
                    lid = tex = None
                    index = None
                    deleted = False
                    for st, so, sn in _subs(data, start, size):
                        if st == b"NAME":
                            lid = data[so:so + sn].split(b"\0")[0].decode("latin-1").lower()
                        elif st == b"INTV":
                            index = struct.unpack_from("<I", data, so)[0]
                        elif st == b"DATA":
                            tex = data[so:so + sn].split(b"\0")[0].decode("latin-1")
                        elif st == b"DELE":
                            deleted = True
                    if lid is not None and index is not None and not deleted:
                        idx.ltex_tex[lid] = tex or ""
                        idx.ltex_map.setdefault((plugin, index), lid)
                elif t == b"LAND":
                    xy = vhgt = vtex = None
                    for st, so, sn in _subs(data, start, size):
                        if st == b"INTV":
                            xy = struct.unpack_from("<ii", data, so)
                        elif st == b"VHGT":
                            vhgt = data[so:so + sn]
                        elif st == b"VTEX":
                            vtex = data[so:so + sn]
                    if xy is not None:
                        if xy in idx.lands:
                            idx.overridden.setdefault(xy, [idx.lands[xy].file]).append(str(path))
                        idx.lands[xy] = _Land(plugin, str(path), vhgt, vtex)
        return idx

    # --- tekstury --------------------------------------------------------------
    def texture_name(self, land: _Land, vtex: int) -> Optional[str]:
        if vtex == 0:
            return DEFAULT_TEXTURE
        lid = self.ltex_map.get((land.plugin, vtex - 1))
        return None if lid is None else self.ltex_tex.get(lid)

    def _tex_cell(self, cx: int, cy: int, tx: int, ty: int) -> Optional[str]:
        cx += tx // TEX_SIZE; tx %= TEX_SIZE
        cy += ty // TEX_SIZE; ty %= TEX_SIZE
        land = self.lands.get((cx, cy))
        if land is None or land.textures() is None:
            return None
        return self.texture_name(land, land.textures()[ty * TEX_SIZE + tx])

    def texture_at(self, wx: float, wy: float, mode: str = "fork") -> Optional[str]:
        cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
        lx = min(max(wx / CELL - cx, 0.0), 0.999999)
        ly = min(max(wy / CELL - cy, 0.0), 0.999999)
        if mode == "fork":
            return self._tex_cell(cx, cy, min(int(lx * TEX_SIZE), 15), min(int(ly * TEX_SIZE), 15))
        if mode == "render":
            return self._tex_cell(cx, cy, math.floor(lx * TEX_SIZE - 0.25), math.floor(ly * TEX_SIZE + 0.25))
        raise ValueError(f"nieznany tryb mapowania tekstur: {mode}")

    def texture_grid(self, cx: int, cy: int) -> Optional[list[list[str]]]:
        land = self.lands.get((cx, cy))
        if land is None or land.textures() is None:
            return None
        tex = land.textures()
        return [[self.texture_name(land, tex[y * 16 + x]) for x in range(16)] for y in range(15, -1, -1)]

    # --- wysokość / nachylenie (fork: getProceduralHeightAt / getSlopeDegreesAt) ----
    def height_at(self, wx: float, wy: float) -> Optional[float]:
        cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
        land = self.lands.get((cx, cy))
        if land is None or land.heights() is None:
            return None
        h = land.heights()
        nx, ny = (wx - cx * CELL) / CELL, (wy - cy * CELL) / CELL
        f = LAND_SIZE - 1
        sx = min(max(int(nx * f), 0), LAND_SIZE - 1)
        sy = min(max(int(ny * f), 0), LAND_SIZE - 1)
        ex, ey = min(sx + 1, LAND_SIZE - 1), min(sy + 1, LAND_SIZE - 1)
        if sx == ex or sy == ey:
            return h[sy * LAND_SIZE + sx]
        xp, yp = nx * f - sx, ny * f - sy
        v0 = (0.0, 0.0, h[sy * LAND_SIZE + sx]); v1 = (1.0, 0.0, h[sy * LAND_SIZE + ex])
        v2 = (1.0, 1.0, h[ey * LAND_SIZE + ex]); v3 = (0.0, 1.0, h[ey * LAND_SIZE + sx])
        if (sx + sy) & 1:                       # nieparzysty kwadrat: przekątna v1–v3
            tri = (v0, v1, v3) if (1.0 - yp) > xp else (v1, v2, v3)
        else:                                    # parzysty: przekątna v0–v2
            tri = (v0, v2, v3) if yp > xp else (v0, v1, v2)
        return _plane_z(*tri, xp, yp)

    def slope_at(self, wx: float, wy: float) -> Optional[float]:
        d = CELL / (LAND_SIZE - 1)
        vals = [self.height_at(wx - d, wy), self.height_at(wx + d, wy), self.height_at(wx, wy - d), self.height_at(wx, wy + d)]
        if any(v is None for v in vals):
            return None
        l, r, dn, up = vals
        g = math.hypot((r - l) / (2 * d), (up - dn) / (2 * d))
        return math.degrees(math.atan(g))

    def cell_summary(self, cx: int, cy: int) -> Optional[dict]:
        land = self.lands.get((cx, cy))
        if land is None:
            return None
        out = {"cell": [cx, cy], "file": Path(land.file).name, "plugin_index": land.plugin,
               "overridden_by_load_order": [Path(f).name for f in self.overridden.get((cx, cy), [])]}
        if land.heights():
            hs = land.heights()
            out["height"] = {"min": min(hs), "max": max(hs)}
            slopes = [self.slope_at(cx * CELL + (i + 0.5) * CELL / 16, cy * CELL + (j + 0.5) * CELL / 16)
                      for i in range(16) for j in range(16)]
            slopes = [s for s in slopes if s is not None]
            if slopes:
                out["slope_deg"] = {"min": round(min(slopes), 2), "max": round(max(slopes), 2),
                                    "mean": round(sum(slopes) / len(slopes), 2)}
        if land.textures():
            from collections import Counter
            names = Counter(self.texture_name(land, v) for v in land.textures())
            out["textures"] = dict(names.most_common())
        return out
