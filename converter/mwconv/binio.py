"""Niskopoziomowy odczyt/zapis binarny (little-endian) wspólny dla NIF, ESM i BSA."""

from __future__ import annotations

import struct

MAX_COUNT = 10_000_000  # ochrona przed uszkodzonymi licznikami


class FormatError(Exception):
    """Błąd struktury pliku wejściowego (z położeniem)."""


class Reader:
    __slots__ = ("buf", "pos", "end", "name")

    def __init__(self, data: bytes, name: str = "<bufor>", pos: int = 0, end: int | None = None):
        self.buf = memoryview(data)
        self.pos = pos
        self.end = len(data) if end is None else end
        self.name = name

    # --- podstawy -------------------------------------------------------------
    def remaining(self) -> int:
        return self.end - self.pos

    def take(self, n: int) -> memoryview:
        if n < 0 or self.pos + n > self.end:
            raise FormatError(f"{self.name}: koniec danych (pozycja {self.pos}, potrzeba {n}, dostępne {self.remaining()})")
        v = self.buf[self.pos:self.pos + n]
        self.pos += n
        return v

    def skip(self, n: int) -> None:
        self.take(n)

    def _s(self, fmt: str, size: int):
        return struct.unpack_from(fmt, self.take(size))

    def u8(self) -> int:
        return self.take(1)[0]

    def i8(self) -> int:
        return self._s("<b", 1)[0]

    def u16(self) -> int:
        return self._s("<H", 2)[0]

    def i16(self) -> int:
        return self._s("<h", 2)[0]

    def u32(self) -> int:
        return self._s("<I", 4)[0]

    def i32(self) -> int:
        return self._s("<i", 4)[0]

    def u64(self) -> int:
        return self._s("<Q", 8)[0]

    def f32(self) -> float:
        return self._s("<f", 4)[0]

    def floats(self, n: int) -> tuple:
        return self._s(f"<{n}f", 4 * n) if n else ()

    def u16s(self, n: int) -> tuple:
        return self._s(f"<{n}H", 2 * n) if n else ()

    def count(self, n: int) -> int:
        if n > MAX_COUNT:
            raise FormatError(f"{self.name}: nieprawdopodobny licznik {n} na pozycji {self.pos}")
        return n

    def zstring(self, n: int, encoding: str = "cp1252") -> str:
        raw = bytes(self.take(n))
        z = raw.find(b"\0")
        if z >= 0:
            raw = raw[:z]
        return raw.decode(encoding, "replace")


class Writer:
    def __init__(self):
        self.parts: list[bytes] = []

    def raw(self, b: bytes) -> "Writer":
        self.parts.append(bytes(b))
        return self

    def u8(self, v):
        return self.raw(struct.pack("<B", v))

    def u16(self, v):
        return self.raw(struct.pack("<H", v))

    def i16(self, v):
        return self.raw(struct.pack("<h", v))

    def u32(self, v):
        return self.raw(struct.pack("<I", v))

    def i32(self, v):
        return self.raw(struct.pack("<i", v))

    def u64(self, v):
        return self.raw(struct.pack("<Q", v))

    def f32(self, v):
        return self.raw(struct.pack("<f", v))

    def floats(self, vals):
        vals = list(vals)
        return self.raw(struct.pack(f"<{len(vals)}f", *vals))

    def u16s(self, vals):
        vals = list(vals)
        return self.raw(struct.pack(f"<{len(vals)}H", *vals))

    def getvalue(self) -> bytes:
        return b"".join(self.parts)

    def __len__(self):
        return sum(len(p) for p in self.parts)
