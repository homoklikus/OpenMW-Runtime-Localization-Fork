"""Uruchamianie gry i Construction Set: wykrywanie Godota, polecenia (listy argumentów, bez powłoki),
blokady instancji na profil, plik ustawień dla Runtime."""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import time
from pathlib import Path

from .jsonio import read_json, write_json
from .settings import validate_game


def find_godot(configured: str = "", app_root: Path | None = None) -> str | None:
    cands = [configured, os.environ.get("MWGODOT_GODOT", "")]
    if app_root:
        cands += [str(app_root / "bin" / "godot"), str(app_root / "godot" / "godot")]
    for c in cands:
        if c and Path(c).is_file() and os.access(c, os.X_OK):
            return c
    # oficjalne pliki z godotengine.org położone obok projektu, np. Godot_v4.7.2-stable_linux.x86_64
    roots = [Path(app_root), Path(app_root).parent] if app_root else []
    roots.append(Path(__file__).resolve().parents[2])
    for r in roots:
        found = sorted((f for f in r.glob("Godot_v4*") if f.is_file() and os.access(f, os.X_OK)
                        and not f.name.endswith((".zip", ".tar.gz", ".tar.xz"))), key=lambda f: f.name, reverse=True)
        if found:
            return str(found[0])
    for n in ("godot", "godot4", "Godot"):
        w = shutil.which(n)
        if w:
            return w
    return None


def godot_version(godot: str, timeout: float = 10.0) -> str | None:
    try:
        r = subprocess.run([godot, "--version", "--headless"], capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip().splitlines()[-1] if r.returncode == 0 and r.stdout.strip() else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def find_project(configured: str = "", app_root: Path | None = None) -> Path | None:
    cands = [configured]
    here = Path(__file__).resolve()
    cands += [str(here.parents[2] / "godot")]           # repozytorium: converter/mwcore → ../godot
    if app_root:
        cands += [str(app_root / "godot"), str(app_root / "share" / "openmwgodot" / "godot")]
    for c in cands:
        if c and (Path(c) / "project.godot").exists():
            return Path(c)
    return None


def safe_split(extra: str) -> list[str]:
    """Dodatkowe parametry użytkownika → lista argumentów (shlex, bez wykonywania powłoki)."""
    try:
        return shlex.split(extra or "")
    except ValueError:
        return []


def write_runtime_settings(path: Path, settings: dict, profile_id: str, language: str) -> Path:
    write_json(path, {"format": "mwgodot-runtime-settings", "version": 1, "profile": profile_id,
                      "language": language, **validate_game(settings)})
    return path


def user_args(data: Path, base: Path, project: Path, settings: Path, profile: str, saves: Path,
              extra: list[str] | None = None) -> list[str]:
    a = [*(extra or []), f"--data={data}", f"--project={project}", f"--settings={settings}", f"--profile={profile}",
         f"--saves={saves}"]
    if Path(base).resolve() != Path(data).resolve():
        a.append(f"--base={base}")
    return a


def game_command(godot: str, project_dir: Path, uargs: list[str], extra: str = "") -> list[str]:
    return [godot, "--path", str(project_dir), *safe_split(extra), "res://main.tscn", "--", *uargs]


def editor_command(godot: str, project_dir: Path, uargs: list[str], extra: str = "") -> list[str]:
    return [godot, "-e", "--path", str(project_dir), *safe_split(extra), "--", *uargs]


class InstanceLock:
    """Blokada „jedna instancja gry/edytora na profil” (plik z PID; martwe blokady są ignorowane)."""

    def __init__(self, locks_dir: Path, kind: str, profile: str):
        self.path = Path(locks_dir) / f"{kind}-{profile}.lock"

    def holder(self) -> int | None:
        d = read_json(self.path)
        if not isinstance(d, dict):
            return None
        try:
            pid = int(d.get("pid", -1))
            os.kill(pid, 0)
            return pid
        except (ProcessLookupError, ValueError, TypeError):
            return None
        except PermissionError:
            return int(d.get("pid"))

    def acquire(self, pid: int) -> None:
        write_json(self.path, {"pid": pid, "time": time.time()})

    def release(self, pid: int | None = None) -> None:
        d = read_json(self.path)
        if pid is None or (isinstance(d, dict) and d.get("pid") == pid):
            self.path.unlink(missing_ok=True)
