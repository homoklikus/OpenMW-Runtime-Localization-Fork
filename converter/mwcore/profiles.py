"""Profile gry: aktywne mody i kolejność, ustawienia gry, odniesienia do konwersji.

Profil = mały plik JSON w <config>/profiles/<id>.json. Przekonwertowana gra NIE jest kopiowana:
wszystkie profile korzystają ze wspólnej konwersji bazowej, a profil z modami ma tylko nakładkę
z różnicami (<data>/profiles/<id>/out). Usunięcie profilu nigdy nie usuwa zapisów gry.
"""

from __future__ import annotations

import re
import shutil
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .jsonio import read_json, write_json
from .paths import AppPaths
from .settings import validate_game

ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,47}$")


@dataclass
class Profile:
    id: str
    name: str
    mods: list = field(default_factory=list)      # [{"id": ..., "enabled": bool}] w kolejności ładowania
    settings: dict = field(default_factory=dict)  # ustawienia gry (schemat w settings.py)
    created: float = 0.0
    version: int = 1

    def enabled_mods(self) -> list[str]:
        return [m["id"] for m in self.mods if m.get("enabled", True)]

    def to_dict(self) -> dict:
        return asdict(self)


def slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:40] or "profil"
    return s


class ProfileStore:
    def __init__(self, paths: AppPaths):
        self.paths = paths
        self.dir = paths.profiles_dir
        self.dir.mkdir(parents=True, exist_ok=True)
        if not self.list():
            self._save(Profile("default", "Domyślny", created=time.time(), settings=validate_game({})))

    def _file(self, pid: str) -> Path:
        if not ID_RE.match(pid):
            raise ValueError(f"niepoprawny identyfikator profilu: {pid!r}")
        return self.dir / f"{pid}.json"

    def _save(self, p: Profile) -> None:
        write_json(self._file(p.id), p.to_dict())

    def list(self) -> list[Profile]:
        out = []
        for f in sorted(self.dir.glob("*.json")):
            d = read_json(f)
            if isinstance(d, dict) and ID_RE.match(str(d.get("id", ""))):
                out.append(Profile(**{k: d[k] for k in ("id", "name", "mods", "settings", "created", "version") if k in d}))
        return out

    def get(self, pid: str) -> Profile | None:
        try:
            d = read_json(self._file(pid))
        except ValueError:
            return None
        if not isinstance(d, dict):
            return None
        p = Profile(**{k: d[k] for k in ("id", "name", "mods", "settings", "created", "version") if k in d})
        p.settings = validate_game(p.settings)
        return p

    def save(self, p: Profile) -> None:
        p.settings = validate_game(p.settings)
        self._save(p)

    def _unique_id(self, name: str) -> str:
        base = slugify(name)
        pid, k = base, 2
        while (self.dir / f"{pid}.json").exists():
            pid = f"{base}-{k}"
            k += 1
        return pid

    def create(self, name: str, copy_from: str | None = None) -> Profile:
        src = self.get(copy_from) if copy_from else None
        p = Profile(self._unique_id(name), name.strip() or "Profil", created=time.time(),
                    mods=[dict(m) for m in src.mods] if src else [],
                    settings=dict(src.settings) if src else validate_game({}))
        self._save(p)
        return p

    def rename(self, pid: str, name: str) -> Profile:
        p = self.get(pid)
        if p is None:
            raise KeyError(pid)
        p.name = name.strip() or p.name
        self._save(p)
        return p

    def delete(self, pid: str, remove_profile_data: bool = True) -> None:
        """Usuwa profil i jego nakładkę konwersji/projekt. Zapisy gry (<data>/saves/<id>) zostają nietknięte."""
        if len(self.list()) <= 1:
            raise ValueError("nie można usunąć ostatniego profilu")
        self._file(pid).unlink(missing_ok=True)
        if remove_profile_data:
            d = self.paths.profile_data(pid)
            if d.exists():
                shutil.rmtree(d)
