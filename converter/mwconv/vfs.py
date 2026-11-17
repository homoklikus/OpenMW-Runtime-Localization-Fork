"""Wirtualny system plików gry: katalogi Data Files + archiwa BSA (TES3), bez rozróżniania wielkości liter.

Kolejność nadpisywania jak w grze: archiwa BSA mają niższy priorytet niż luźne pliki; późniejsze
źródło (dalej na liście) wygrywa. Dla każdej ścieżki pamiętamy źródło (provenance).
"""

from __future__ import annotations

import hashlib
import os
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional


def norm(path: str) -> str:
    return path.replace("\\", "/").lower().lstrip("/")


# ------------------------------------------------------------------------------------------------
# BSA (Morrowind, wersja 0x100)
# ------------------------------------------------------------------------------------------------

def tes3_hash(name: str) -> tuple[int, int]:
    s = name.replace("/", "\\").lower().encode("cp1252")
    n = len(s)
    half = n >> 1
    sum_, off = 0, 0
    for i in range(half):
        sum_ ^= (s[i] << (off & 0x1F)) & 0xFFFFFFFF
        off += 8
    v1 = sum_
    sum_, off = 0, 0
    for i in range(half, n):
        temp = (s[i] << (off & 0x1F)) & 0xFFFFFFFF
        sum_ ^= temp
        k = temp & 0x1F
        sum_ = ((sum_ << (32 - k)) | (sum_ >> k)) & 0xFFFFFFFF if k else sum_
        off += 8
    return v1, sum_


@dataclass
class BsaEntry:
    name: str
    offset: int
    size: int


class BsaArchive:
    def __init__(self, path: str | os.PathLike):
        self.path = Path(path)
        self.entries: dict[str, BsaEntry] = {}
        with open(self.path, "rb") as fh:
            ver, hash_off, count = struct.unpack("<III", fh.read(12))
            if ver != 0x100:
                raise ValueError(f"{path}: nieobsługiwana wersja BSA 0x{ver:x} (oczekiwano 0x100 – Morrowind)")
            recs = struct.unpack(f"<{2 * count}I", fh.read(8 * count))
            name_offs = struct.unpack(f"<{count}I", fh.read(4 * count))
            names_len = hash_off - 12 * count
            names = fh.read(names_len)
        data_start = 12 + hash_off + 8 * count
        for i in range(count):
            size, off = recs[2 * i], recs[2 * i + 1]
            start = name_offs[i]
            end = names.find(b"\0", start)
            nm = names[start:end].decode("cp1252", "replace")
            self.entries[norm(nm)] = BsaEntry(nm, data_start + off, size)

    def read(self, key: str) -> bytes:
        e = self.entries[norm(key)]
        with open(self.path, "rb") as fh:
            fh.seek(e.offset)
            return fh.read(e.size)


def write_bsa(path, files: dict[str, bytes]):
    """Zapis archiwum BSA TES3 (do testów na danych syntetycznych)."""
    items = sorted(((n.replace("/", "\\").lower(), d) for n, d in files.items()), key=lambda x: tes3_hash(x[0]))
    count = len(items)
    names = b""
    name_offs = []
    for n, _ in items:
        name_offs.append(len(names))
        names += n.encode("cp1252") + b"\0"
    hash_off = 12 * count + len(names)
    recs = []
    off = 0
    for _, d in items:
        recs += [len(d), off]
        off += len(d)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x100, hash_off, count))
        fh.write(struct.pack(f"<{2 * count}I", *recs))
        fh.write(struct.pack(f"<{count}I", *name_offs))
        fh.write(names)
        for n, _ in items:
            fh.write(struct.pack("<II", *tes3_hash(n)))
        for _, d in items:
            fh.write(d)


# ------------------------------------------------------------------------------------------------

@dataclass
class VfsFile:
    key: str           # znormalizowana ścieżka (np. "meshes/x/ex_hlaalu_b_01.nif")
    source: str        # katalog lub archiwum
    kind: str          # "dir" | "bsa"
    real: str          # ścieżka na dysku (dir) lub nazwa w archiwum
    size: int
    mtime: float = 0.0


class Vfs:
    def __init__(self):
        self.files: dict[str, VfsFile] = {}
        self._bsa: dict[str, BsaArchive] = {}

    def add_bsa(self, path):
        arc = BsaArchive(path)
        self._bsa[str(path)] = arc
        st = os.stat(path)
        for k, e in arc.entries.items():
            self.files[k] = VfsFile(k, str(path), "bsa", e.name, e.size, st.st_mtime)

    def add_dir(self, root, subdirs: Iterable[str] = ("meshes", "textures", "icons", "bookart", "splash", "localization",
                                                      "sound", "music", "video")):
        root = Path(root)
        if not root.is_dir():
            return
        for entry in root.iterdir():
            if entry.is_dir() and entry.name.lower() in subdirs:
                for dirpath, _dn, fnames in os.walk(entry):
                    for fn in fnames:
                        full = Path(dirpath) / fn
                        rel = full.relative_to(root).as_posix()
                        st = full.stat()
                        k = norm(rel)
                        self.files[k] = VfsFile(k, str(root), "dir", str(full), st.st_size, st.st_mtime)

    @classmethod
    def from_install(cls, data_dirs: list, archives: list) -> "Vfs":
        """Archiwa w podanej kolejności (Fallback Archive), potem katalogi danych (późniejsze wygrywają)."""
        v = cls()
        for a in archives:
            v.add_bsa(a)
        for d in data_dirs:
            v.add_dir(d)
        return v

    def exists(self, key: str) -> bool:
        return norm(key) in self.files

    def info(self, key: str) -> Optional[VfsFile]:
        return self.files.get(norm(key))

    def read(self, key: str) -> bytes:
        f = self.files[norm(key)]
        if f.kind == "dir":
            with open(f.real, "rb") as fh:
                return fh.read()
        return self._bsa[f.source].read(f.real)

    def sha256(self, key: str) -> str:
        return hashlib.sha256(self.read(key)).hexdigest()

    def list(self, prefix: str = "", ext: str = "") -> list[str]:
        p = norm(prefix)
        return sorted(k for k in self.files if k.startswith(p) and k.endswith(ext))

    # --- ścieżki jak w silniku --------------------------------------------------------------------
    def resolve_texture(self, name: str) -> Optional[str]:
        """Nazwa z NIF/ESM → klucz VFS. Prefiks textures/, preferencja .dds jak w grze."""
        n = norm(name)
        if not n:
            return None
        if not n.startswith("textures/"):
            n = "textures/" + n
        base, ext = os.path.splitext(n)
        cands = [base + ".dds", n] if ext != ".dds" else [n]
        for c in cands:
            if c in self.files:
                return c
        return None

    def resolve_mesh(self, name: str) -> Optional[str]:
        n = norm(name)
        if not n:
            return None
        if not n.startswith("meshes/"):
            n = "meshes/" + n
        return n if n in self.files else None
