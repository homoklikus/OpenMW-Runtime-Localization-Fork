"""Zapis plików ESM/ESP TES3 – wyłącznie do tworzenia syntetycznych światów testowych."""

from __future__ import annotations

import struct
from typing import Iterable

import numpy as np

from .reader import encode_heights, untranspose_vtex


def sub(name: str, data: bytes) -> bytes:
    assert len(name) == 4
    return name.encode("ascii") + struct.pack("<I", len(data)) + data


def zs(s: str) -> bytes:
    return s.encode("cp1252") + b"\0"


def record(typ: str, subs: Iterable[bytes], flags: int = 0) -> bytes:
    body = b"".join(subs)
    return typ.encode("ascii") + struct.pack("<III", len(body), 0, flags) + body


def header(masters: list[tuple[str, int]], num_records: int, author: str = "mwgodot", desc: str = "synthetic",
           is_master: bool = True) -> bytes:
    hedr = struct.pack("<fI", 1.3, 1 if is_master else 0)
    hedr += author.encode("cp1252")[:31].ljust(32, b"\0") + desc.encode("cp1252")[:255].ljust(256, b"\0")
    hedr += struct.pack("<I", num_records)
    subs = [sub("HEDR", hedr)]
    for m, size in masters:
        subs.append(sub("MAST", zs(m)))
        subs.append(sub("DATA", struct.pack("<Q", size)))
    return record("TES3", subs)


def stat(id_: str, model: str, typ: str = "STAT", name: str | None = None) -> bytes:
    subs = [sub("NAME", zs(id_)), sub("MODL", zs(model))]
    if name:
        subs.append(sub("FNAM", zs(name)))
    return record(typ, subs)


def light(id_: str, model: str | None, radius: int, color=(255, 200, 120), flags: int = 0x1 | 0x8) -> bytes:
    subs = [sub("NAME", zs(id_))]
    if model:
        subs.append(sub("MODL", zs(model)))
    subs.append(sub("LHDT", struct.pack("<fIiI", 1.0, 1, -1, radius) + bytes([*color, 0]) + struct.pack("<I", flags)))
    return record("LIGH", subs)


def ltex(id_: str, index: int, texture: str) -> bytes:
    return record("LTEX", [sub("NAME", zs(id_)), sub("INTV", struct.pack("<I", index)), sub("DATA", zs(texture))])


def ref_subs(frmr: int, base: str, pos, rot=(0, 0, 0), scale: float = 1.0, deleted: bool = False,
             extra: dict | None = None) -> list[bytes]:
    s = [sub("FRMR", struct.pack("<I", frmr)), sub("NAME", zs(base))]
    if abs(scale - 1.0) > 1e-6:
        s.append(sub("XSCL", struct.pack("<f", scale)))
    if extra:
        if "owner" in extra:
            s.append(sub("ANAM", zs(extra["owner"])))
        if "door_dest" in extra:
            d = extra["door_dest"]
            s.append(sub("DODT", struct.pack("<6f", *d["pos"], *d["rot"])))
        if "door_dest_cell" in extra:
            s.append(sub("DNAM", zs(extra["door_dest_cell"])))
        if "lock_level" in extra:
            s.append(sub("FLTV", struct.pack("<i", int(extra["lock_level"]))))
        if "trap" in extra:
            s.append(sub("TNAM", zs(extra["trap"])))
        if "faction" in extra:
            s.append(sub("CNAM", zs(extra["faction"])))
    if deleted:
        s.append(sub("DELE", struct.pack("<I", 0)))
    s.append(sub("DATA", struct.pack("<6f", *pos, *rot)))
    return s


def cell(name: str, grid=(0, 0), interior: bool = False, refs: Iterable[list[bytes]] = (), region: str | None = None,
         moved: Iterable[tuple[int, tuple, list[bytes]]] = (), water: float | None = None,
         ambient: tuple | None = None) -> bytes:
    flags = (1 | (0x02 if water is not None else 0)) if interior else 0
    s = [sub("NAME", zs(name)), sub("DATA", struct.pack("<Iii", flags, *grid))]
    if region:
        s.append(sub("RGNN", zs(region)))
    if interior and water is not None:
        s.append(sub("WHGT", struct.pack("<f", water)))
    if interior and ambient is not None:
        s.append(sub("AMBI", struct.pack("<IIIf", *ambient)))
    for r in refs:
        s += r
    for mvrf, target, rs in moved:
        s.append(sub("MVRF", struct.pack("<I", mvrf)))
        s.append(sub("CNDT", struct.pack("<ii", *target)))
        s += rs
    return record("CELL", s)


def land(grid, heights: np.ndarray, vtex: np.ndarray | None = None, colors: np.ndarray | None = None) -> bytes:
    s = [sub("INTV", struct.pack("<ii", *grid)), sub("DATA", struct.pack("<I", 0x1 | 0x2 | 0x4 | 0x8))]
    h = np.asarray(heights)
    # normalne z gradientu (int8, jak w grze)
    gy, gx = np.gradient(h, 128.0)
    n = np.stack([-gx, -gy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    s.append(sub("VNML", (np.round(n * 127)).astype(np.int8).tobytes()))
    s.append(sub("VHGT", encode_heights(h)))
    small = h[::8, ::8][:9, :9]
    s.append(sub("WNAM", np.clip(small / 128, -128, 127).astype(np.int8).tobytes()))
    if colors is not None:
        s.append(sub("VCLR", np.asarray(colors, np.uint8).tobytes()))
    if vtex is not None:
        s.append(sub("VTEX", untranspose_vtex(np.asarray(vtex, np.uint16)).astype("<u2").tobytes()))
    return record("LAND", s)


def region(id_: str, name: str, weather: dict, color=(120, 160, 90), sounds: Iterable = ()) -> bytes:
    """REGN; sounds: (id dźwięku, szansa 0–100) – SNAM 32 bajty + 1 bajt szansy."""
    from .reader import WEATHERS
    w = bytes(int(weather.get(k, 0)) for k in WEATHERS)
    subs = [sub("NAME", zs(id_)), sub("FNAM", zs(name)), sub("WEAT", w), sub("CNAM", bytes([*color, 0]))]
    for sid, chance in sounds:
        subs.append(sub("SNAM", sid.encode("cp1252")[:31].ljust(32, b"\0") + bytes([chance])))
    return record("REGN", subs)


def dial(name: str, typ: int, deleted: bool = False) -> bytes:
    """DIAL (etap 6): 0 temat, 1 głos, 2 powitanie, 3 perswazja, 4 dziennik."""
    subs = [sub("NAME", zs(name))]
    subs.append(sub("DELE", b"\0\0\0\0") if deleted else sub("DATA", bytes([typ])))
    return record("DIAL", subs)


def info(iid: str, prev: str = "", nxt: str = "", text: str = "", typ: int = 0, disposition: int = 0,
         rank: int = -1, gender: int = -1, pcrank: int = -1, actor: str = "", race: str = "", cls: str = "",
         faction: str = "", cell: str = "", pcfaction: str = "", conditions: Iterable = (), result: str = "",
         quest: str = "", deleted: bool = False, sound: str = "") -> bytes:
    """INFO; warunek: (reguła SCVR, wartość int|float), np. ("01000", 30) = funkcja 00 == 30."""
    subs = [sub("INAM", zs(iid)), sub("PNAM", zs(prev)), sub("NNAM", zs(nxt))]
    if deleted:
        return record("INFO", subs + [sub("DELE", b"\0\0\0\0")])
    subs.append(sub("DATA", struct.pack("<iibbbx", typ, disposition, rank, gender, pcrank)))
    for tag, v in (("ONAM", actor), ("RNAM", race), ("CNAM", cls), ("FNAM", faction), ("ANAM", cell),
                   ("DNAM", pcfaction)):
        if v:
            subs.append(sub(tag, zs(v)))
    if text:
        subs.append(sub("NAME", text.encode("cp1252")))
    for rule, value in conditions:
        subs.append(sub("SCVR", rule.encode("cp1252")))
        subs.append(sub("FLTV", struct.pack("<f", value)) if isinstance(value, float) else sub("INTV", struct.pack("<i", value)))
    if sound:
        subs.append(sub("SNAM", zs(sound)))
    if result:
        subs.append(sub("BNAM", result.replace("\n", "\r\n").encode("cp1252")))
    if quest:
        subs.append(sub({"name": "QSTN", "finished": "QSTF", "restart": "QSTR"}[quest], b"\1"))
    return record("INFO", subs)


def pgrd(cell_name: str, grid, points, edges) -> bytes:
    """PGRD: punkty (x, y, z) względem początku komórki (zewnętrze) albo bezwzględne (wnętrze), krawędzie (i, j)
    – w PGRC kolejno połączenia punktu 0, 1, …; DATA: x, y, ziarnistość, liczba punktów."""
    conns = {i: [] for i in range(len(points))}
    for a, b in edges:
        conns[a].append(b)
    pgrp = b"".join(struct.pack("<iiiBB", int(x), int(y), int(z), 1, len(conns[i])) + b"\0\0"
                    for i, (x, y, z) in enumerate(points))
    pgrc = b"".join(struct.pack("<I", j) for i in range(len(points)) for j in conns[i])
    return record("PGRD", [sub("DATA", struct.pack("<iiHH", grid[0], grid[1], 128, len(points))),
                           sub("NAME", zs(cell_name)), sub("PGRP", pgrp), sub("PGRC", pgrc)])
