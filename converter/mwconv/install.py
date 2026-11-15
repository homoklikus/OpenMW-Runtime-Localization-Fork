"""Wykrywanie konfiguracji instalacji gracza: openmw.cfg albo Morrowind.ini + „Data Files”."""

from __future__ import annotations

import configparser
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class InstallConfig:
    data_dirs: list[str] = field(default_factory=list)   # rosnący priorytet
    archives: list[str] = field(default_factory=list)    # pełne ścieżki, rosnący priorytet
    content: list[str] = field(default_factory=list)     # pełne ścieżki ESM/ESP w kolejności ładowania
    origin: str = ""

    def to_dict(self):
        return dict(self.__dict__)


def _unquote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        v = v[1:-1].replace("&&", "\0").replace("&\"", "\"").replace("\0", "&")
    return v


def _find_case_insensitive(dirs: list[str], name: str) -> Optional[str]:
    for d in reversed(dirs):
        p = Path(d)
        if not p.is_dir():
            continue
        direct = p / name
        if direct.exists():
            return str(direct)
        low = name.lower()
        for e in p.iterdir():
            if e.name.lower() == low:
                return str(e)
    return None


def from_openmw_cfg(path) -> InstallConfig:
    path = Path(path)
    cfg = InstallConfig(origin=str(path))
    data, content, archives = [], [], []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = _unquote(v)
        if k == "data":
            v = os.path.expanduser(v.replace("?userdata?", "~/.local/share/openmw/"))
            if not os.path.isabs(v):
                v = str((path.parent / v).resolve())
            data.append(v)
        elif k == "content":
            content.append(v)
        elif k == "fallback-archive":
            archives.append(v)
    cfg.data_dirs = data
    for a in archives:
        p = _find_case_insensitive(data, a)
        if p:
            cfg.archives.append(p)
    for c in content:
        if c.lower().endswith((".omwscripts", ".omwaddon", ".omwgame")):
            continue
        p = _find_case_insensitive(data, c)
        if p:
            cfg.content.append(p)
    return cfg


def from_morrowind_dir(root) -> InstallConfig:
    """Katalog oryginalnej gry (zawiera „Data Files” i Morrowind.ini)."""
    root = Path(root)
    data = root / "Data Files" if (root / "Data Files").is_dir() else root
    cfg = InstallConfig(origin=str(root), data_dirs=[str(data)])
    ini = None
    for cand in (root / "Morrowind.ini", data.parent / "Morrowind.ini"):
        if cand.exists():
            ini = cand
            break
    archives = ["Morrowind.bsa"]
    content = []
    if ini is not None:
        cp = configparser.ConfigParser(strict=False, interpolation=None)
        cp.optionxform = str
        text = ini.read_bytes().decode("cp1252", "replace")
        try:
            cp.read_string(text)
        except configparser.Error:
            pass
        if cp.has_section("Archives"):
            for _k, v in sorted(cp.items("Archives"), key=lambda kv: int("".join(c for c in kv[0] if c.isdigit()) or 0)):
                if v and v.lower() not in [a.lower() for a in archives]:
                    archives.append(v.strip())
        if cp.has_section("Game Files"):
            for _k, v in sorted(cp.items("Game Files"), key=lambda kv: int("".join(c for c in kv[0] if c.isdigit()) or 0)):
                if v:
                    content.append(v.strip())
    if not content:
        content = [n for n in ("Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm") if _find_case_insensitive([str(data)], n)]
    for a in archives:
        p = _find_case_insensitive([str(data)], a)
        if p:
            cfg.archives.append(p)
    # ESM przed ESP (jak w grze), w obrębie grupy wg kolejności z ini
    esm = [c for c in content if c.lower().endswith(".esm")]
    esp = [c for c in content if not c.lower().endswith(".esm")]
    for c in esm + esp:
        p = _find_case_insensitive([str(data)], c)
        if p:
            cfg.content.append(p)
    return cfg
