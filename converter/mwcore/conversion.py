"""Stan konwersji i budowa poleceń konwertera dla profilu.

Układ danych (bez duplikowania gry na profil):
  <converted>/base/            konwersja czystej instalacji (wspólna dla wszystkich profili)
  <data>/profiles/<id>/out/    nakładka profilu z modami: tylko zasoby różne od bazy + świat profilu
Profil bez modów gra bezpośrednio z bazy.

Szybka walidacja przed „Graj” (bez hashowania zasobów): obecność i poprawność JSON manifestów,
kompletny stan eksportu (`export_state.json: complete`), brak aktywnej blokady konwersji, zgodność
zapisu konwersji profilu (`conversion_record.json`) z bieżącym zestawem modów i plików ESM/ESP
(nazwy + rozmiary).
"""

from __future__ import annotations

import json
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

from mwconv.install import InstallConfig

from .jsonio import read_json, write_json

READY, MISSING, INCOMPLETE, RUNNING, OUTDATED, BROKEN = "ready", "missing", "incomplete", "running", "outdated", "broken"


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


@dataclass
class OutStatus:
    state: str
    out: str
    details: list = field(default_factory=list)


def content_quick_fp(content: list[str]) -> list:
    out = []
    for c in content:
        try:
            out.append([Path(c).name.lower(), os.path.getsize(c)])
        except OSError:
            out.append([Path(c).name.lower(), -1])
    return out


def out_status(out: Path) -> OutStatus:
    out = Path(out)
    lock = out / ".mwconv" / "convert.lock"
    if lock.exists():
        info = read_json(lock, {}) if lock.stat().st_size < 4096 else {}
        try:
            if _pid_alive(int(info.get("pid", -1))):
                return OutStatus(RUNNING, str(out), [f"PID {info.get('pid')}"])
        except (TypeError, ValueError):
            pass
    if not (out / "world" / "index.json").exists():
        st = INCOMPLETE if (out / ".mwconv" / "cache.sqlite").exists() else MISSING
        return OutStatus(st, str(out), ["brak world/index.json"])
    state_f = out / ".mwconv" / "export_state.json"
    try:
        state = json.loads(state_f.read_text())
    except (OSError, json.JSONDecodeError):
        return OutStatus(INCOMPLETE, str(out), ["eksport świata niekompletny"])
    if not state.get("complete"):
        return OutStatus(INCOMPLETE, str(out), ["eksport świata niekompletny"])
    probs = []
    for rel in ("world/manifest.json", "world/index.json", "world/objects.json"):
        try:
            json.loads((out / rel).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            probs.append(f"uszkodzony {rel}")
    if probs:
        return OutStatus(BROKEN, str(out), probs)
    return OutStatus(READY, str(out))


@dataclass
class Plan:
    base_out: Path
    profile_out: Path | None          # None = profil gra z bazy
    base_cfg: InstallConfig
    profile_cfg: InstallConfig | None
    signature: str = ""

    @property
    def play_out(self) -> Path:
        return self.profile_out or self.base_out


def make_plan(converted: Path, profile_data: Path, base_cfg: InstallConfig, resolution) -> Plan:
    base_out = Path(converted) / "base"
    has_mods = len(resolution.config.data_dirs) > len(base_cfg.data_dirs) or resolution.config.content != base_cfg.content
    return Plan(base_out, (Path(profile_data) / "out") if has_mods else None, base_cfg,
                resolution.config if has_mods else None, resolution.signature)


def convert_args(cfg: InstallConfig, out: Path, scope: str = "full", base_out: Path | None = None,
                 jobs: int = 0, bake_godot: str = "", bake_project: str = "") -> list[str]:
    """Argumenty `python -m mwconv convert` (lista – bez składania poleceń powłoki)."""
    a = ["-m", "mwconv", "convert", "--progress-json", "--out", str(out)]
    for d in cfg.data_dirs:
        a += ["--data", d]
    for arc in cfg.archives:
        a += ["--archive", arc]
    for c in cfg.content:
        a += ["--content", c]
    if scope == "balmora":
        a += ["--cell", "Balmora", "--grid-range=-4,-4,-1,-1"]
    else:
        a += ["--all-cells", "--all-models", "--all-textures"]
    if base_out:
        a += ["--base-out", str(base_out)]
    if jobs:
        a += ["--jobs", str(jobs)]
    if bake_godot:
        a += ["--bake-godot", bake_godot]
        if bake_project:
            a += ["--bake-project", bake_project]
    return a


def steps(plan: Plan, scope: str, **kw) -> list[dict]:
    """Kroki konwersji: baza (zawsze, przyrostowo) i nakładka profilu (jeśli są mody)."""
    st = [{"name": "base", "out": plan.base_out, "args": convert_args(plan.base_cfg, plan.base_out, scope, **kw)}]
    if plan.profile_out is not None:
        st.append({"name": "profile", "out": plan.profile_out,
                   "args": convert_args(plan.profile_cfg, plan.profile_out, scope, base_out=plan.base_out, **kw)})
    return st


def record_path(plan: Plan) -> Path:
    return plan.play_out / ".mwconv" / "conversion_record.json"


def output_stats(out: Path) -> dict:
    """Liczba i rozmiar plików wyników (z cache konwertera – bez przeglądania dysku)."""
    import sqlite3
    db = Path(out) / ".mwconv" / "cache.sqlite"
    files, size = 0, 0
    if db.exists():
        try:
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            for (outs,) in con.execute("SELECT outputs FROM assets WHERE status='ok'"):
                for o in json.loads(outs or "[]"):
                    files += 1
                    try:
                        size += (Path(out) / o).stat().st_size
                    except OSError:
                        pass
            con.close()
        except sqlite3.Error:
            pass
    return {"files": files, "bytes": size}


def write_record(plan: Plan, scope: str) -> None:
    cfg = plan.profile_cfg or plan.base_cfg
    st = output_stats(plan.base_out)
    if plan.profile_out is not None:
        o = output_stats(plan.profile_out)
        st = {"files": st["files"] + o["files"], "bytes": st["bytes"] + o["bytes"]}
    write_json(record_path(plan), {"signature": plan.signature, "scope": scope, "time": time.time(),
                                   "content": content_quick_fp(cfg.content), **st})


def read_record(plan: Plan) -> dict:
    r = read_json(record_path(plan))
    return r if isinstance(r, dict) else {}


def play_status(plan: Plan) -> OutStatus:
    """Czy profil można uruchomić. Szybko: bez hashowania zasobów."""
    b = out_status(plan.base_out)
    if b.state != READY:
        return b
    if plan.profile_out is not None:
        p = out_status(plan.profile_out)
        if p.state != READY:
            return p
    rec = read_json(record_path(plan))
    cfg = plan.profile_cfg or plan.base_cfg
    if not isinstance(rec, dict):
        return OutStatus(OUTDATED, str(plan.play_out), ["brak zapisu konwersji dla tego zestawu modów"])
    if rec.get("signature") != plan.signature:
        return OutStatus(OUTDATED, str(plan.play_out), ["zmienił się zestaw lub kolejność modów"])
    if rec.get("content") != content_quick_fp(cfg.content):
        return OutStatus(OUTDATED, str(plan.play_out), ["zmieniły się pliki ESM/ESP"])
    return OutStatus(READY, str(plan.play_out))


def converter_dir() -> Path:
    return Path(__file__).resolve().parents[1]


def python_exe(configured: str = "") -> str:
    return configured or sys.executable
