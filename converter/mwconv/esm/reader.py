"""Czytnik plików ESM/ESP Morrowinda (TES3). Implementacja własna (MIT) na podstawie publicznych opisów
formatu (UESP „Mod File Format”).

Plik to ciąg rekordów: [typ 4B][rozmiar u32][nagłówek u32][flagi u32] + podrekordy [nazwa 4B][rozmiar u32][dane].
Czytamy wszystkie rekordy „płytko” (lista podrekordów), a w szczegółach dekodujemy tylko to, czego
potrzebuje import świata (obiekty z modelem, światła, CELL, LAND, LTEX). Pozostałe rekordy są
przechowywane jako surowe podrekordy, więc nic nie ginie przy ponownym zapisie/analizie.
"""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, Optional

import numpy as np

from ..binio import FormatError, Reader
from .header import (FLAG_BLOCKED, FLAG_DELETED, FLAG_PERSISTENT, EsmHeader, Record, Sub, _zs,  # noqa: F401
                     iter_records, parse_header, read_header)

# typy rekordów, które mają NAME + MODL i mogą być umieszczane w komórkach
MODEL_TYPES = {"STAT", "ACTI", "DOOR", "CONT", "LIGH", "MISC", "WEAP", "ARMO", "CLOT", "BOOK", "ALCH", "APPA",
               "LOCK", "PROB", "REPA", "INGR", "CREA", "NPC_", "BODY", "LEVI", "LEVC"}


# ------------------------------------------------------------------------------------------------
# dekodery szczegółowe
# ------------------------------------------------------------------------------------------------

@dataclass(slots=True)
class CellRef:
    frmr: int
    refnum: int
    mast_index: int
    base: str
    pos: tuple
    rot: tuple
    scale: float = 1.0
    deleted: bool = False
    moved_to: Optional[tuple] = None
    extra: dict = field(default_factory=dict)


@dataclass(slots=True)
class Cell:
    name: str
    flags: int
    grid: tuple
    interior: bool
    region: Optional[str] = None
    ambient: Optional[dict] = None
    water: Optional[float] = None
    refs: list[CellRef] = field(default_factory=list)
    deleted: bool = False

    @property
    def key(self) -> str:
        return f"int:{self.name.lower()}" if self.interior else f"ext:{self.grid[0]},{self.grid[1]}"


REF_EXTRA = {
    "UNAM": ("blocked", "B"), "ANAM": ("owner", "z"), "BNAM": ("global", "z"), "CNAM": ("faction", "z"),
    "INDX": ("faction_rank", "i"), "XSOL": ("soul", "z"), "XCHG": ("charge", "f"), "INTV": ("health", "i"),
    "NAM9": ("count", "i"), "DNAM": ("door_dest_cell", "z"), "FLTV": ("lock_level", "i"), "KNAM": ("key", "z"),
    "TNAM": ("trap", "z"), "XHLT": ("health_left", "i"),
}


def parse_cell(rec: Record) -> Cell:
    name = rec.zstr("NAME") or ""
    data = rec.get("DATA") or b"\0" * 12
    flags, gx, gy = struct.unpack_from("<Iii", data, 0)
    interior = bool(flags & 1)
    cell = Cell(name, flags, (gx, gy), interior, deleted=rec.deleted)
    cell.region = rec.zstr("RGNN")
    refs = []
    cur: Optional[CellRef] = None
    pending_move: Optional[tuple] = None
    i = 0
    subs = rec.subs
    # podrekordy komórki przed pierwszym FRMR/MVRF
    while i < len(subs) and subs[i].name not in ("FRMR", "MVRF"):
        s = subs[i]
        if s.name == "AMBI" and len(s.data) >= 16:
            a, sun, fog, dens = struct.unpack_from("<IIIf", s.data, 0)
            cell.ambient = {"ambient": a, "sunlight": sun, "fog": fog, "fog_density": dens}
        elif s.name == "WHGT" and len(s.data) >= 4:
            cell.water = struct.unpack_from("<f", s.data, 0)[0]
        elif s.name == "INTV" and len(s.data) >= 4 and cell.water is None:
            cell.water = float(struct.unpack_from("<i", s.data, 0)[0])
        i += 1
    while i < len(subs):
        s = subs[i]
        n = s.name
        if n == "MVRF":
            pending_move = None
            # następny CNDT/CNAM określa komórkę docelową
            j = i + 1
            if j < len(subs) and subs[j].name == "CNDT" and len(subs[j].data) >= 8:
                pending_move = ("ext",) + struct.unpack_from("<ii", subs[j].data, 0)
                i = j
            elif j < len(subs) and subs[j].name == "CNAM":
                pending_move = ("int", _zs(subs[j].data))
                i = j
        elif n == "FRMR":
            v = struct.unpack_from("<I", s.data, 0)[0]
            cur = CellRef(v, v & 0x00FFFFFF, v >> 24, "", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
            cur.moved_to = pending_move
            pending_move = None
            refs.append(cur)
        elif cur is not None:
            if n == "NAME":
                cur.base = _zs(s.data)
            elif n == "XSCL":
                cur.scale = struct.unpack_from("<f", s.data, 0)[0]
            elif n == "DATA" and len(s.data) >= 24:
                v = struct.unpack_from("<6f", s.data, 0)
                cur.pos, cur.rot = v[:3], v[3:]
            elif n == "DODT" and len(s.data) >= 24:
                v = struct.unpack_from("<6f", s.data, 0)
                cur.extra["door_dest"] = {"pos": list(v[:3]), "rot": list(v[3:])}
            elif n == "DELE":
                cur.deleted = True
            elif n == "ZNAM":
                cur.extra["disabled"] = True
            elif n in REF_EXTRA:
                key, kind = REF_EXTRA[n]
                if kind == "z":
                    cur.extra[key] = _zs(s.data)
                elif kind == "f" and len(s.data) >= 4:
                    cur.extra[key] = struct.unpack_from("<f", s.data, 0)[0]
                elif kind == "i" and len(s.data) >= 4:
                    cur.extra[key] = struct.unpack_from("<i", s.data, 0)[0]
                elif kind == "B" and len(s.data) >= 1:
                    cur.extra[key] = s.data[0]
        i += 1
    cell.refs = refs
    return cell


@dataclass(slots=True)
class Land:
    grid: tuple
    flags: int
    heights: Optional[np.ndarray] = None   # (65, 65) w jednostkach gry, [y, x]
    normals: Optional[np.ndarray] = None   # (65, 65, 3) int8
    colors: Optional[np.ndarray] = None    # (65, 65, 3) uint8
    textures: Optional[np.ndarray] = None  # (16, 16) uint16, [y, x], 0 = domyślna, n = LTEX(n-1)
    deleted: bool = False


def decode_heights(vhgt: bytes) -> np.ndarray:
    offset = struct.unpack_from("<f", vhgt, 0)[0]
    d = np.frombuffer(vhgt, dtype=np.int8, count=65 * 65, offset=4).astype(np.float64).reshape(65, 65)
    # delta pierwszej kolumny kumuluje się między wierszami, pozostałe – w obrębie wiersza
    col0 = offset + np.cumsum(d[:, 0])
    out = np.empty((65, 65))
    out[:, 0] = col0
    out[:, 1:] = col0[:, None] + np.cumsum(d[:, 1:], axis=1)
    return (out * 8.0).astype(np.float32)


def encode_heights(h: np.ndarray) -> bytes:
    """Odwrotność decode_heights (do syntetycznych ESM). Wysokości muszą być wielokrotnością 8."""
    q = np.round(np.asarray(h, dtype=np.float64) / 8.0).astype(np.int64)
    offset = float(q[0, 0])
    deltas = np.zeros((65, 65), np.int64)
    prev_row = offset
    for y in range(65):
        deltas[y, 0] = q[y, 0] - (prev_row if y else offset)
        if y == 0:
            deltas[0, 0] = 0
        prev_row = q[y, 0]
        for x in range(1, 65):
            deltas[y, x] = q[y, x] - q[y, x - 1]
    if np.abs(deltas).max() > 127:
        raise ValueError("zbyt duże różnice wysokości dla VHGT (|Δ| > 127·8)")
    return struct.pack("<f", offset) + deltas.astype(np.int8).tobytes() + b"\0\0\0"


def transpose_vtex(raw: np.ndarray) -> np.ndarray:
    """VTEX zapisany blokami 4×4 z bloków 4×4 → zwykła siatka 16×16 [y, x]."""
    out = np.zeros((16, 16), np.uint16)
    k = 0
    for y1 in range(4):
        for x1 in range(4):
            for y2 in range(4):
                for x2 in range(4):
                    out[y1 * 4 + y2, x1 * 4 + x2] = raw[k]
                    k += 1
    return out


def untranspose_vtex(grid: np.ndarray) -> np.ndarray:
    raw = np.zeros(256, np.uint16)
    k = 0
    for y1 in range(4):
        for x1 in range(4):
            for y2 in range(4):
                for x2 in range(4):
                    raw[k] = grid[y1 * 4 + y2, x1 * 4 + x2]
                    k += 1
    return raw


def parse_land(rec: Record) -> Land:
    intv = rec.get("INTV")
    gx, gy = struct.unpack_from("<ii", intv, 0)
    dat = rec.get("DATA")
    land = Land((gx, gy), struct.unpack_from("<I", dat, 0)[0] if dat else 0, deleted=rec.deleted)
    v = rec.get("VHGT")
    if v is not None and len(v) >= 4 + 65 * 65:
        land.heights = decode_heights(v)
    v = rec.get("VNML")
    if v is not None and len(v) >= 65 * 65 * 3:
        land.normals = np.frombuffer(v, np.int8, 65 * 65 * 3).reshape(65, 65, 3)
    v = rec.get("VCLR")
    if v is not None and len(v) >= 65 * 65 * 3:
        land.colors = np.frombuffer(v, np.uint8, 65 * 65 * 3).reshape(65, 65, 3)
    v = rec.get("VTEX")
    if v is not None and len(v) >= 512:
        land.textures = transpose_vtex(np.frombuffer(v, "<u2", 256))
    return land


def parse_object(rec: Record) -> Optional[dict]:
    rid = rec.zstr("NAME")
    if rid is None:
        return None
    o = {"type": rec.type, "id": rid}
    m = rec.zstr("MODL")
    if m:
        o["model"] = m
    fn = rec.zstr("FNAM")
    if fn:
        o["name"] = fn
    if rec.type == "LIGH":
        d = rec.get("LHDT")
        if d and len(d) >= 24:
            weight, value, time, radius = struct.unpack_from("<fIiI", d, 0)
            r, g, b, _a = d[16:20]
            flags = struct.unpack_from("<I", d, 20)[0]
            o["light"] = {"radius": radius, "color": [r, g, b], "flags": flags, "time": time,
                          "negative": bool(flags & 0x4), "flicker": bool(flags & 0x8 or flags & 0x40),
                          "pulse": bool(flags & 0x80 or flags & 0x100), "off_default": bool(flags & 0x20),
                          "carry": bool(flags & 0x2)}
    if rec.type == "DOOR":
        o["open_sound"] = rec.zstr("SNAM")
    if rec.type == "NPC_":
        o["race"] = rec.zstr("RNAM")
        o["head"] = rec.zstr("BNAM")
        o["hair"] = rec.zstr("KNAM")
    return o


WEATHERS = ["clear", "cloudy", "foggy", "overcast", "rain", "thunder", "ash", "blight", "snow", "blizzard"]


def parse_region(rec: Record) -> Optional[dict]:
    rid = rec.zstr("NAME")
    if rid is None:
        return None
    o = {"id": rid, "name": rec.zstr("FNAM") or rid}
    w = rec.get("WEAT")
    if w:
        o["weather"] = {WEATHERS[i]: int(b) for i, b in enumerate(w[:len(WEATHERS)])}
    c = rec.get("CNAM")
    if c and len(c) >= 3:
        o["map_color"] = [c[0], c[1], c[2]]
    snd = [_zs(s.data[:32]) for s in rec.subs if s.name == "SNAM"]
    if snd:
        o["sounds"] = snd
    return o


@dataclass
class EsmFile:
    path: str
    name: str
    sha256: str
    header: EsmHeader
    records: list[Record]
    num_records: int = 0


def open_esm_stream(path) -> tuple["EsmFile", Iterator[Record]]:
    """Strumieniowy odczyt: nagłówek od razu, rekordy jako generator (bez listy wszystkich rekordów w pamięci)."""
    p = Path(path)
    data = p.read_bytes()
    it = iter_records(data, p.name)
    first = next(it, None)
    if first is None:
        raise FormatError(f"{p.name}: pusty plik")
    hdr = parse_header(first)
    f = EsmFile(str(p), p.name, hashlib.sha256(data).hexdigest(), hdr, [], 0)

    def gen():
        for rec in it:
            f.num_records += 1
            yield rec
    return f, gen()


def read_esm(path) -> EsmFile:
    p = Path(path)
    data = p.read_bytes()
    recs = list(iter_records(data, p.name))
    if not recs:
        raise FormatError(f"{p.name}: pusty plik")
    hdr = parse_header(recs[0])
    return EsmFile(str(p), p.name, hashlib.sha256(data).hexdigest(), hdr, recs[1:], len(recs) - 1)
