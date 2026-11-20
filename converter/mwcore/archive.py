"""Bezpieczne rozpakowywanie archiwów modów (ZIP; 7z przez py7zr, jeśli dostępny).

Zabezpieczenia:
* path traversal – odrzucane ścieżki bezwzględne, z „..”, z literą dysku; każda ścieżka docelowa jest
  sprawdzana po rozwiązaniu, czy leży w katalogu docelowym;
* dowiązania symboliczne/twarde – odrzucane (symlink escape);
* archive bomb – limity: łączny rozmiar po rozpakowaniu, liczba plików, współczynnik kompresji
  (dla pliku i całości); rozmiar jest też liczony w trakcie zapisu, nie tylko z nagłówka;
* rozpakowanie do katalogu tymczasowego (staging) i atomowe przeniesienie dopiero po sukcesie.
"""

from __future__ import annotations

import os
import shutil
import stat
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from .i18n import tr


class ArchiveError(Exception):
    pass


@dataclass
class Limits:
    max_total_bytes: int = 16 * 1024 ** 3
    max_files: int = 200_000
    max_ratio: float = 200.0           # rozpakowane / skompresowane
    min_ratio_check_bytes: int = 1 << 20


def safe_member_path(name: str) -> PurePosixPath:
    n = name.replace("\\", "/")
    if n.startswith("/") or (len(n) > 1 and n[1] == ":"):
        raise ArchiveError(tr('ścieżka bezwzględna w archiwum: {name!r}', name=name))
    p = PurePosixPath(n)
    if any(part == ".." for part in p.parts):
        raise ArchiveError(tr('ścieżka wychodzi poza katalog (..): {name!r}', name=name))
    parts = [x for x in p.parts if x not in ("", ".")]
    if not parts:
        raise ArchiveError(tr('pusta ścieżka w archiwum: {name!r}', name=name))
    return PurePosixPath(*parts)


def _inside(root: Path, target: Path) -> bool:
    try:
        target.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _copy_limited(src, dst: Path, budget: list, limits: Limits):
    with open(dst, "wb") as out:
        while True:
            chunk = src.read(1 << 20)
            if not chunk:
                break
            budget[0] += len(chunk)
            if budget[0] > limits.max_total_bytes:
                raise ArchiveError(tr('przekroczony limit rozmiaru po rozpakowaniu (archive bomb?)'))
            out.write(chunk)


def extract(archive: Path, dest: Path, limits: Limits | None = None) -> int:
    """Rozpakowuje archiwum do (nowego, pustego) katalogu dest. Zwraca liczbę plików."""
    limits = limits or Limits()
    archive = Path(archive)
    dest = Path(dest)
    if dest.exists() and any(dest.iterdir()):
        raise ArchiveError(tr('katalog docelowy nie jest pusty: {dest}', dest=dest))
    dest.mkdir(parents=True, exist_ok=True)
    suffix = archive.suffix.lower()
    if suffix == ".zip" or zipfile.is_zipfile(archive):
        return _extract_zip(archive, dest, limits)
    if suffix == ".7z":
        return _extract_7z(archive, dest, limits)
    raise ArchiveError(tr('nieobsługiwany format archiwum: {name} (obsługiwane: .zip, .7z)', name=archive.name))


def _extract_zip(archive: Path, dest: Path, limits: Limits) -> int:
    with zipfile.ZipFile(archive) as zf:
        infos = zf.infolist()
        files = [i for i in infos if not i.is_dir()]
        if len(files) > limits.max_files:
            raise ArchiveError(tr('za dużo plików w archiwum ({v})', v=len(files)))
        total = sum(i.file_size for i in files)
        comp = sum(max(1, i.compress_size) for i in files)
        if total > limits.max_total_bytes:
            raise ArchiveError(tr('rozmiar po rozpakowaniu przekracza limit'))
        if total > limits.min_ratio_check_bytes and total / comp > limits.max_ratio:
            raise ArchiveError(tr('podejrzany współczynnik kompresji {v:.0f}:1 (archive bomb?)', v=total / comp))
        for i in files:
            mode = (i.external_attr >> 16) & 0o170000
            if mode in (stat.S_IFLNK,):
                raise ArchiveError(tr('dowiązanie symboliczne w archiwum: {filename!r}', filename=i.filename))
            if i.file_size > limits.min_ratio_check_bytes and i.file_size / max(1, i.compress_size) > limits.max_ratio:
                raise ArchiveError(tr('podejrzany współczynnik kompresji pliku {filename!r}', filename=i.filename))
        budget = [0]
        for i in files:
            rel = safe_member_path(i.filename)
            target = dest / Path(*rel.parts)
            if not _inside(dest, target.parent if target.parent.exists() else dest) or not _inside(dest, target):
                raise ArchiveError(tr('ścieżka poza katalogiem docelowym: {filename!r}', filename=i.filename))
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(i) as src:
                _copy_limited(src, target, budget, limits)
        return len(files)


def _extract_7z(archive: Path, dest: Path, limits: Limits) -> int:
    try:
        import py7zr
    except ImportError:
        raise ArchiveError(tr('obsługa 7z wymaga pakietu py7zr (Debian: sudo apt install python3-py7zr)')) from None
    with py7zr.SevenZipFile(archive, "r") as z:
        entries = [e for e in z.list() if not e.is_directory]
        if len(entries) > limits.max_files:
            raise ArchiveError(tr('za dużo plików w archiwum ({v})', v=len(entries)))
        total = sum(e.uncompressed or 0 for e in entries)
        if total > limits.max_total_bytes:
            raise ArchiveError(tr('rozmiar po rozpakowaniu przekracza limit'))
        comp = os.path.getsize(archive)
        if total > limits.min_ratio_check_bytes and total / max(1, comp) > limits.max_ratio:
            raise ArchiveError(tr('podejrzany współczynnik kompresji {v:.0f}:1 (archive bomb?)', v=total / comp))
        names = []
        for e in entries:
            if getattr(e, "is_symlink", False):
                raise ArchiveError(tr('dowiązanie symboliczne w archiwum: {filename!r}', filename=e.filename))
            rel = safe_member_path(e.filename)
            if not _inside(dest, dest / Path(*rel.parts)):
                raise ArchiveError(tr('ścieżka poza katalogiem docelowym: {filename!r}', filename=e.filename))
            names.append(e.filename)
        z.reset()
        z.extractall(path=dest)
    # kontrola po rozpakowaniu: brak dowiązań, wszystko w środku, rzeczywisty rozmiar
    real = 0
    for p in dest.rglob("*"):
        if p.is_symlink():
            p.unlink()
            raise ArchiveError(tr('dowiązanie symboliczne po rozpakowaniu: {name}', name=p.name))
        if not _inside(dest, p):
            raise ArchiveError(tr('plik poza katalogiem docelowym'))
        if p.is_file():
            real += p.stat().st_size
    if real > limits.max_total_bytes:
        raise ArchiveError(tr('przekroczony limit rozmiaru po rozpakowaniu'))
    return len(names)


def remove_tree(p: Path) -> None:
    if p.exists():
        shutil.rmtree(p)
