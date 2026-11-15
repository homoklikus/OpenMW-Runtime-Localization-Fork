"""Lekki odczyt ESM/ESP (TES3): rekordy, podrekordy i nagłówek z listą masterów – bez numpy.

Używany przez czytnik pełny (`reader.py`) oraz przez warstwę zarządzania danymi (launcher), która musi
szybko odczytać zależności pluginów bez wczytywania całego pliku.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, Optional

from ..binio import FormatError, Reader

FLAG_DELETED = 0x0020
FLAG_PERSISTENT = 0x0400
FLAG_BLOCKED = 0x2000

@dataclass
class Sub:
    name: str
    data: bytes


@dataclass
class Record:
    type: str
    flags: int
    subs: list[Sub]
    offset: int = 0

    def get(self, name: str) -> Optional[bytes]:
        for s in self.subs:
            if s.name == name:
                return s.data
        return None

    def zstr(self, name: str) -> Optional[str]:
        d = self.get(name)
        if d is None:
            return None
        z = d.find(b"\0")
        return (d[:z] if z >= 0 else d).decode("cp1252", "replace")

    @property
    def deleted(self) -> bool:
        if self.flags & FLAG_DELETED:
            return True
        for s in self.subs:  # w CELL: tylko DELE samej komórki (przed pierwszą referencją)
            if s.name in ("FRMR", "MVRF"):
                return False
            if s.name == "DELE":
                return True
        return False


@dataclass
class EsmHeader:
    version: float
    flags: int
    author: str
    description: str
    num_records: int
    masters: list[tuple[str, int]] = field(default_factory=list)


def _zs(b: bytes) -> str:
    z = b.find(b"\0")
    return (b[:z] if z >= 0 else b).decode("cp1252", "replace")


def iter_records(data: bytes, name: str = "<esm>") -> Iterator[Record]:
    r = Reader(data, name)
    while r.remaining() >= 16:
        off = r.pos
        typ = bytes(r.take(4)).decode("ascii", "replace")
        size = r.u32()
        r.u32()  # nagłówek (nieużywany)
        flags = r.u32()
        end = r.pos + size
        if end > r.end:
            raise FormatError(f"{name}: rekord {typ} na offsecie {off} wychodzi poza plik")
        subs = []
        while r.pos < end:
            if end - r.pos < 8:
                raise FormatError(f"{name}: uszkodzony podrekord w {typ} @ {off}")
            sn = bytes(r.take(4)).decode("ascii", "replace")
            ss = r.u32()
            subs.append(Sub(sn, bytes(r.take(ss))))
        yield Record(typ, flags, subs, off)


def parse_header(rec: Record) -> EsmHeader:
    if rec.type != "TES3":
        raise FormatError("pierwszy rekord nie jest TES3")
    h = rec.get("HEDR")
    if h is None or len(h) < 300:
        raise FormatError("brak/uszkodzony HEDR")
    ver, flags = struct.unpack_from("<fI", h, 0)
    author = _zs(h[8:40])
    desc = _zs(h[40:296])
    nrec = struct.unpack_from("<I", h, 296)[0]
    masters = []
    pending = None
    for s in rec.subs:
        if s.name == "MAST":
            pending = _zs(s.data)
        elif s.name == "DATA" and pending is not None:
            masters.append((pending, struct.unpack_from("<Q", s.data, 0)[0] if len(s.data) >= 8 else 0))
            pending = None
    if pending is not None:
        masters.append((pending, 0))
    return EsmHeader(ver, flags, author, desc, nrec, masters)




def read_header(path) -> EsmHeader:
    """Odczyt samego nagłówka TES3 (pierwszy rekord) – bez czytania całego pliku."""
    p = Path(path)
    with open(p, "rb") as fh:
        head = fh.read(16)
        if len(head) < 16 or head[:4] != b"TES3":
            raise FormatError(f"{p.name}: to nie jest plik ESM/ESP (brak rekordu TES3)")
        size = struct.unpack_from("<I", head, 4)[0]
        if size > 16 * 1024 * 1024:
            raise FormatError(f"{p.name}: nieprawdopodobny rozmiar nagłówka")
        body = fh.read(size)
    rec = next(iter_records(head + body, p.name))
    return parse_header(rec)
