"""Narzędzia wspólne: hashowanie z cache, mapowanie ścieżek, uruchamianie poleceń tylko do odczytu."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional


# --- mapowanie ścieżek -----------------------------------------------------
# OPENMW_MCP_PATH_MAP="/media/x=/mnt/x;/a=/b" — pozwala uruchomić analizę na kopii/montażu
# (np. w testach), gdy pliki .cfg zawierają ścieżki hosta. Domyślnie puste.

def _path_map() -> list[tuple[str, str]]:
    raw = os.environ.get("OPENMW_MCP_PATH_MAP", "")
    pairs = []
    for item in raw.split(";"):
        if "=" in item:
            src, dst = item.split("=", 1)
            if src:
                pairs.append((src.rstrip("/"), dst.rstrip("/")))
    pairs.sort(key=lambda p: len(p[0]), reverse=True)
    return pairs


def map_path(path: str | os.PathLike) -> Path:
    s = str(path)
    for src, dst in _path_map():
        if s == src or s.startswith(src + "/"):
            return Path(dst + s[len(src):])
    return Path(s)


def vfs_key(rel: str) -> str:
    """Klucz VFS OpenMW: ukośniki '/', małe litery, bez wiodącego '/'."""
    return rel.replace("\\", "/").lstrip("/").lower()


# --- uruchamianie poleceń (tylko odczyt) -----------------------------------

@dataclass
class CmdResult:
    rc: int
    out: str
    err: str


Runner = Callable[[list[str], Optional[dict]], CmdResult]


def run_command(cmd: list[str], env_extra: Optional[dict] = None, timeout: float = 30.0) -> CmdResult:
    env = dict(os.environ)
    env["LC_ALL"] = "C"          # etykiety narzędzi (flatpak, git) niezależne od locale
    env["GIT_TERMINAL_PROMPT"] = "0"
    if env_extra:
        env.update(env_extra)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
        return CmdResult(p.returncode, p.stdout, p.stderr)
    except FileNotFoundError:
        return CmdResult(127, "", f"nie znaleziono polecenia: {cmd[0]}")
    except subprocess.TimeoutExpired:
        return CmdResult(124, "", f"przekroczono czas ({timeout}s): {' '.join(cmd)}")


# --- SHA-256 z cache --------------------------------------------------------

class HashCache:
    """Cache sum SHA-256 kluczowany ścieżką + rozmiarem + mtime_ns. Zapis tylko do własnego pliku cache."""

    def __init__(self, path: Optional[Path]):
        self.path = path
        self._lock = threading.Lock()
        self._data: dict[str, list] = {}
        self._dirty = False
        if path and path.is_file():
            try:
                self._data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                self._data = {}

    RACY_SECONDS = 2.0  # jak Git: świeżo zmienionym plikom nie ufamy (granulacja mtime)

    def sha256(self, file: Path) -> str:
        st = file.stat()
        key = str(file)
        stamp = [st.st_size, st.st_mtime_ns, st.st_ino, st.st_ctime_ns]
        import time
        racy = (time.time_ns() - max(st.st_mtime_ns, st.st_ctime_ns)) < self.RACY_SECONDS * 1e9
        with self._lock:
            hit = self._data.get(key)
            if hit and not racy and hit[:-1] == stamp:
                return hit[-1]
        h = hashlib.sha256()
        with open(file, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        digest = h.hexdigest()
        if not racy:
            with self._lock:
                self._data[key] = stamp + [digest]
                self._dirty = True
        return digest

    def save(self) -> None:
        if not self.path or not self._dirty:
            return
        with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._data), encoding="utf-8")
            os.replace(tmp, self.path)
            self._dirty = False


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def stable_hash(obj) -> str:
    """Hash kanonicznego JSON — do etykiet stanu."""
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()
