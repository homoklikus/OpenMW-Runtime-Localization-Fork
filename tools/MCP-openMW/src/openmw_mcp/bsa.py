"""Odczyt listy plików z archiwum BSA TES3 (Morrowind) — tylko nazwy, bez rozpakowywania."""

from __future__ import annotations

import struct
from pathlib import Path

from .util import vfs_key


class BsaError(Exception):
    pass


def list_tes3_bsa(path: Path) -> list[str]:
    with open(path, "rb") as f:
        head = f.read(12)
        if len(head) < 12:
            raise BsaError(f"{path}: plik za krótki")
        version, hash_offset, count = struct.unpack("<III", head)
        if version != 0x100:
            raise BsaError(f"{path}: nieobsługiwana wersja BSA 0x{version:x} (oczekiwano TES3 0x100)")
        if count > 1_000_000:
            raise BsaError(f"{path}: podejrzana liczba plików {count}")
        f.seek(12 + count * 8)
        name_offsets = struct.unpack(f"<{count}I", f.read(count * 4))
        names_block_size = hash_offset - count * 12
        names = f.read(names_block_size)
    out = []
    for off in name_offsets:
        end = names.find(b"\0", off)
        if end < 0:
            raise BsaError(f"{path}: uszkodzona tablica nazw")
        out.append(vfs_key(names[off:end].decode("latin-1")))
    return out


def build_tes3_bsa(files: dict[str, bytes]) -> bytes:
    """Minimalny zapis BSA TES3 — tylko do testów."""
    names = list(files)
    count = len(names)
    name_block = b""
    offsets = []
    for n in names:
        offsets.append(len(name_block))
        name_block += n.replace("/", "\\").encode("latin-1") + b"\0"
    data_block = b""
    records = []
    for n in names:
        records.append((len(files[n]), len(data_block)))
        data_block += files[n]
    hash_offset = count * 12 + len(name_block)
    out = struct.pack("<III", 0x100, hash_offset, count)
    for size, off in records:
        out += struct.pack("<II", size, off)
    out += struct.pack(f"<{count}I", *offsets) + name_block
    out += b"\0" * (8 * count)  # hashe (nieużywane przy odczycie listy)
    return out + data_block
