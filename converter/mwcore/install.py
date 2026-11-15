"""Wykrywanie i walidacja instalacji Morrowinda (Steam, GOG, ręczna, OpenMW) – tylko odczyt.

Opiera się na `mwconv.install` (parsowanie openmw.cfg / Morrowind.ini), dodaje: typowe lokalizacje,
rozpoznawanie rodzaju ścieżki, raport komponentów (Morrowind/Tribunal/Bloodmoon, archiwa BSA).
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from mwconv.install import InstallConfig, from_morrowind_dir, from_openmw_cfg

COMPONENTS = [("Morrowind", "Morrowind.esm", "Morrowind.bsa", True), ("Tribunal", "Tribunal.esm", "Tribunal.bsa", False),
              ("Bloodmoon", "Bloodmoon.esm", "Bloodmoon.bsa", False)]


@dataclass
class InstallReport:
    kind: str                 # morrowind | openmw_cfg | data | unknown
    path: str
    ok: bool
    data_dir: str = ""
    components: list = field(default_factory=list)   # [{"name", "esm", "bsa", "required"}]
    problems: list = field(default_factory=list)
    config: InstallConfig | None = None

    def summary(self) -> str:
        have = [c["name"] for c in self.components if c["esm"]]
        return ", ".join(have) if have else "—"


def _ci(dirpath: Path, name: str) -> Path | None:
    if not dirpath.is_dir():
        return None
    p = dirpath / name
    if p.exists():
        return p
    low = name.lower()
    for e in dirpath.iterdir():
        if e.name.lower() == low:
            return e
    return None


def candidates() -> list[tuple[str, Path]]:
    home = Path.home()
    out = [
        ("openmw_cfg", home / ".config/openmw/openmw.cfg"),
        ("openmw_cfg", home / ".var/app/org.openmw.OpenMW/config/openmw/openmw.cfg"),
        ("morrowind", home / ".steam/steam/steamapps/common/Morrowind"),
        ("morrowind", home / ".local/share/Steam/steamapps/common/Morrowind"),
        ("morrowind", home / ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Morrowind"),
        ("morrowind", home / "GOG Games/Morrowind"),
        ("morrowind", home / "Games/morrowind/drive_c/GOG Games/Morrowind"),
        ("morrowind", home / ".wine/drive_c/GOG Games/Morrowind"),
        ("morrowind", home / ".wine/drive_c/Program Files (x86)/Bethesda Softworks/Morrowind"),
    ]
    for env in ("MWGODOT_MORROWIND",):
        if os.environ.get(env):
            out.insert(0, ("auto", Path(os.environ[env])))
    return out


def inspect(path: str | Path) -> InstallReport:
    """Rozpoznaje ścieżkę (katalog gry, „Data Files”, openmw.cfg) i sprawdza komponenty. Niczego nie zmienia."""
    p = Path(path).expanduser()
    try:
        if p.is_file() and p.name == "openmw.cfg":
            cfg = from_openmw_cfg(p)
            rep = InstallReport("openmw_cfg", str(p), False, config=cfg,
                                data_dir=cfg.data_dirs[0] if cfg.data_dirs else "")
            names = {Path(c).name.lower(): c for c in cfg.content}
            arcs = {Path(a).name.lower() for a in cfg.archives}
            for n, esm, bsa, req in COMPONENTS:
                rep.components.append({"name": n, "esm": esm.lower() in names, "bsa": bsa.lower() in arcs, "required": req})
        elif p.is_dir():
            data = _ci(p, "Data Files") or p
            if _ci(data, "Morrowind.esm") is None and _ci(p, "Data Files") is None:
                return InstallReport("unknown", str(p), False, problems=["brak Morrowind.esm i katalogu „Data Files”"])
            kind = "morrowind" if _ci(p, "Data Files") else "data"
            cfg = from_morrowind_dir(p)
            rep = InstallReport(kind, str(p), False, data_dir=str(data), config=cfg)
            for n, esm, bsa, req in COMPONENTS:
                rep.components.append({"name": n, "esm": _ci(data, esm) is not None, "bsa": _ci(data, bsa) is not None,
                                       "required": req})
        else:
            return InstallReport("unknown", str(p), False, problems=["ścieżka nie istnieje"])
    except (OSError, ValueError) as e:
        return InstallReport("unknown", str(p), False, problems=[f"błąd odczytu: {e}"])
    for c in rep.components:
        if c["required"] and not c["esm"]:
            rep.problems.append(f"brak {c['name']}.esm")
        if c["esm"] and not c["bsa"]:
            rep.problems.append(f"brak archiwum {c['name']}.bsa (modele/tekstury mogą być niekompletne)")
    if rep.config is not None and not rep.config.content:
        rep.problems.append("nie znaleziono plików ESM do wczytania")
    rep.ok = any(c["required"] and c["esm"] for c in rep.components) and bool(rep.config and rep.config.content)
    return rep


def detect() -> list[InstallReport]:
    seen, out = set(), []
    for _kind, path in candidates():
        if path.exists() and str(path) not in seen:
            seen.add(str(path))
            r = inspect(path)
            if r.ok:
                out.append(r)
    return out
