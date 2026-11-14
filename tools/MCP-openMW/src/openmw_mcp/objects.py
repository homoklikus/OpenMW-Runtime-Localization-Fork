"""Obiekty świata TES3 (referencje w komórkach zewnętrznych) i ich geometria w układzie świata.

Semantyka z OpenMW 0.51.0:
* components/esm3/loadcell.cpp `Cell::getNextRef` + `adjustRefNum`: FRMR = indeks; górny bajt ≠ 0 i ≤ liczby
  plików nadrzędnych ⇒ referencja z pliku nadrzędnego MAST[bajt−1] (nadpisanie, indeks & 0xFFFFFF), w przeciwnym
  razie nowa referencja bieżącego pliku. Identyfikator = (indeks, plik). Późniejszy plugin wygrywa, DELE usuwa.
* MVRF (indeks) + CNDT (siatka docelowa) poprzedza FRMR przeniesionej referencji — należy ona do komórki docelowej.
* components/esm3/cellref.cpp: XSCL obcinane do [0,5; 2,0]; NAM0 (znacznik sekcji temp) ignorowany.
* Rekordy bazowe: późniejszy plugin wygrywa (ID bez rozróżniania wielkości liter); model = "meshes/" + MODL.
* Obrót referencji (apps/openmw/mwrender/objectpaging.cpp, Misc::Convert::makeOsgQuat):
  Quat(z,−Z)·Quat(y,−Y)·Quat(x,−X) w OSG ⇒ p_świat = t + R·s·p, R = Rx(−x)·Ry(−y)·Rz(−z).
  Uwaga: getCullSafeBoundingBox (Lua getBoundingBox) dla obiektów stronicowanych składa obrót odwrotnie
  (R = Rz·Ry·Rx) — dla obiektów obróconych w X/Y granice z Lua mogą odbiegać od rysowanego obrazu.
"""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np

from .land import CELL, _records, _subs
from .util import vfs_key

# Typy z modelem; zasłaniające kadr na stałe: STATIC_TYPES
MODEL_TYPES = {b"STAT", b"ACTI", b"DOOR", b"CONT", b"LIGH", b"MISC", b"ALCH", b"APPA", b"ARMO", b"BOOK", b"CLOT",
               b"INGR", b"LOCK", b"PROB", b"REPA", b"WEAP", b"NPC_", b"CREA"}
STATIC_TYPES = {"STAT", "ACTI", "DOOR", "CONT", "LIGH"}


def _z(data: bytes, so: int, sn: int) -> str:
    return data[so:so + sn].split(b"\0")[0].decode("latin-1")


@dataclass
class Ref:
    refnum: tuple                                # (indeks, plik)
    id: str
    pos: tuple
    rot: tuple
    scale: float
    file: int                                    # plik, który ostatni zapisał referencję
    cell: tuple
    moved_from: Optional[tuple] = None


@dataclass
class WorldObjects:
    files: list = field(default_factory=list)
    bases: dict = field(default_factory=dict)            # id (małe) -> (typ, model, plik)
    cells: dict = field(default_factory=dict)            # (x, y) -> {refnum: Ref}
    deleted: int = 0
    moved: int = 0
    overridden: int = 0

    @classmethod
    def load(cls, content_files: list[Path]) -> "WorldObjects":
        w = cls()
        names = [Path(p).name.lower() for p in content_files]
        where: dict = {}                                  # refnum -> komórka (do przenoszenia/nadpisań)
        for fi, path in enumerate(content_files):
            path = Path(path)
            w.files.append(str(path))
            if path.suffix.lower() not in (".esm", ".esp", ".omwaddon", ".omwgame"):
                continue
            data = path.read_bytes()
            parents: list[int] = []
            for t, start, size in _records(data):
                if t == b"TES3":
                    for st, so, sn in _subs(data, start, size):
                        if st == b"MAST":
                            m = _z(data, so, sn).lower()
                            parents.append(names.index(m) if m in names else -1)
                elif t in MODEL_TYPES:
                    rid = model = None
                    dele = bool(struct.unpack_from("<I", data, start - 4)[0] & 0x20)
                    for st, so, sn in _subs(data, start, size):
                        if st == b"NAME" and rid is None:
                            rid = _z(data, so, sn).lower()
                        elif st == b"MODL":
                            model = _z(data, so, sn)
                        elif st == b"DELE":
                            dele = True
                    if rid is None:
                        continue
                    if dele:
                        w.bases.pop(rid, None)
                    else:
                        w.bases[rid] = (t.decode(), model, fi)
                elif t == b"CELL":
                    w._cell(data, start, size, fi, parents, where)
        return w

    def _cell(self, data, start, size, fi, parents, where):
        subs = list(_subs(data, start, size))
        grid = None
        k = 0
        while k < len(subs):
            st, so, sn = subs[k]
            if st == b"DATA" and sn == 12:
                flags, cx, cy = struct.unpack_from("<Iii", data, so)
                if flags & 1:
                    return                                # komórka wewnętrzna
                grid = (cx, cy)
                k += 1
                break
            if st in (b"FRMR", b"MVRF"):
                return
            k += 1
        if grid is None:
            return

        def adjust(raw: int) -> tuple:
            local = raw >> 24
            if local and local <= len(parents):
                return (raw & 0xFFFFFF, parents[local - 1])
            return (raw, fi)

        moved_target = None
        while k < len(subs):
            st, so, sn = subs[k]
            if st == b"MVRF":
                k += 1
                moved_target = grid
                if k < len(subs) and subs[k][0] == b"CNDT":
                    moved_target = struct.unpack_from("<ii", data, subs[k][1])
                    k += 1
                continue
            if st != b"FRMR":
                k += 1
                continue
            refnum = adjust(struct.unpack_from("<I", data, so)[0])
            rid, pos, rot, scale, dele = "", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), 1.0, False
            k += 1
            while k < len(subs) and subs[k][0] not in (b"FRMR", b"MVRF"):
                st2, so2, sn2 = subs[k]
                if st2 == b"NAME":
                    rid = _z(data, so2, sn2).lower()
                elif st2 == b"XSCL":
                    scale = min(max(struct.unpack_from("<f", data, so2)[0], 0.5), 2.0)
                elif st2 == b"DATA" and sn2 == 24:
                    v = struct.unpack_from("<6f", data, so2)
                    pos, rot = v[:3], v[3:]
                elif st2 == b"DELE":
                    dele = True
                k += 1
            cell = moved_target or grid
            prev = where.get(refnum)
            if prev is not None:
                self.cells.get(prev, {}).pop(refnum, None)
                self.overridden += 1
            if moved_target is not None:
                self.moved += 1
            moved_target = None
            if dele:
                where.pop(refnum, None)
                self.deleted += 1
                continue
            self.cells.setdefault(cell, {})[refnum] = Ref(refnum, rid, pos, rot, scale, fi, cell,
                                                           moved_from=grid if cell != grid else None)
            where[refnum] = cell

    def refs(self, cx: int, cy: int) -> list[Ref]:
        return list(self.cells.get((cx, cy), {}).values())

    def base(self, rid: str) -> Optional[tuple]:
        return self.bases.get(rid.lower())


def model_key(model: Optional[str]) -> Optional[str]:
    """components/misc/resourcehelpers.cpp correctMeshPath: 'meshes/' + MODL."""
    if not model:
        return None
    return vfs_key("meshes/" + model)


def rotation_matrix(rot: tuple, order: str = "direct") -> np.ndarray:
    """direct: R = Rx(−x)·Ry(−y)·Rz(−z) (rysowanie); inverse: R = Rz(−z)·Ry(−y)·Rx(−x)."""
    x, y, z = rot

    def rx(a):
        c, s = math.cos(a), math.sin(a)
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])

    def ry(a):
        c, s = math.cos(a), math.sin(a)
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])

    def rz(a):
        c, s = math.cos(a), math.sin(a)
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

    if order == "inverse":
        return rz(-z) @ ry(-y) @ rx(-x)
    return rx(-x) @ ry(-y) @ rz(-z)


def world_matrix(ref: Ref, order: str = "direct") -> np.ndarray:
    m = np.eye(4)
    m[:3, :3] = rotation_matrix(ref.rot, order) * ref.scale
    m[:3, 3] = ref.pos
    return m


def transform(points: np.ndarray, m: np.ndarray) -> np.ndarray:
    return points @ m[:3, :3].T + m[:3, 3]


def aabb_of(points: np.ndarray):
    if len(points) == 0:
        return None
    return points.min(axis=0), points.max(axis=0)


def corners(lo, hi) -> np.ndarray:
    return np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])


def cells_around(cx: int, cy: int, radius: int = 1) -> list[tuple]:
    return [(cx + dx, cy + dy) for dx in range(-radius, radius + 1) for dy in range(-radius, radius + 1)]


def cell_of(x: float, y: float) -> tuple:
    return (math.floor(x / CELL), math.floor(y / CELL))
