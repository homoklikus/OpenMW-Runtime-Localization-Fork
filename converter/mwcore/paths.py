"""Katalogi aplikacji: XDG na Linuksie, %APPDATA% na Windows, tryb przenośny.

Rozdział (wymaganie projektu): kod i binaria | konfiguracja | cache | dane gry (konwersje, mody) |
profile | zapisy gry | logi. Tryb przenośny: plik `portable.txt` obok launchera albo zmienna
OPENMWGODOT_PORTABLE=<katalog> – wtedy wszystko trafia do <katalog>/userdata.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

APP = "openmwgodot"


def _xdg(var: str, fallback: str) -> Path:
    v = os.environ.get(var)
    return Path(v) if v and os.path.isabs(v) else Path.home() / fallback


@dataclass
class AppPaths:
    config: Path
    data: Path
    cache: Path
    state: Path
    runtime: Path
    portable: bool = False

    @classmethod
    def detect(cls, app_root: Path | None = None) -> "AppPaths":
        port = os.environ.get("OPENMWGODOT_PORTABLE")
        if not port and app_root is not None and (Path(app_root) / "portable.txt").exists():
            port = str(app_root)
        if port:
            u = Path(port) / "userdata"
            return cls(u / "config", u / "data", u / "cache", u / "state", u / "run", portable=True)
        if sys.platform == "win32":
            appdata = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / APP
            local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / APP
            return cls(appdata / "config", local / "data", local / "cache", local / "state", local / "run")
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        return cls(_xdg("XDG_CONFIG_HOME", ".config") / APP, _xdg("XDG_DATA_HOME", ".local/share") / APP,
                   _xdg("XDG_CACHE_HOME", ".cache") / APP, _xdg("XDG_STATE_HOME", ".local/state") / APP,
                   (Path(runtime) / APP) if runtime else _xdg("XDG_STATE_HOME", ".local/state") / APP / "run")

    # --- pochodne ------------------------------------------------------------------------------
    @property
    def launcher_config(self) -> Path:
        return self.config / "launcher.json"

    @property
    def profiles_dir(self) -> Path:
        return self.config / "profiles"

    @property
    def mods_dir(self) -> Path:
        return self.data / "mods"

    @property
    def default_converted(self) -> Path:
        return self.data / "converted"

    def profile_data(self, profile_id: str) -> Path:
        """Dane profilu: nakładka konwersji (różnice względem bazy), projekt CS 2.0, ustawienia runtime."""
        return self.data / "profiles" / profile_id

    def saves(self, profile_id: str) -> Path:
        return self.data / "saves" / profile_id

    @property
    def logs(self) -> Path:
        return self.state / "logs"

    @property
    def locks(self) -> Path:
        return self.runtime / "locks"

    @property
    def staging(self) -> Path:
        return self.cache / "staging"

    def ensure(self) -> "AppPaths":
        for p in (self.config, self.data, self.cache, self.state, self.runtime, self.profiles_dir, self.mods_dir,
                  self.logs, self.locks, self.staging):
            p.mkdir(parents=True, exist_ok=True)
        return self
