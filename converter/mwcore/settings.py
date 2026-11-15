"""Ustawienia: konfiguracja launchera (globalna) i ustawienia gry (per profil) ze schematem.

W schemacie są wyłącznie opcje, które Runtime faktycznie obsługuje (scripts/main.gd → _apply_settings).
Dźwięk: Runtime nie ma jeszcze dźwięku – sekcja jest pusta i GUI to komunikuje.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .jsonio import read_json, write_json


@dataclass
class Opt:
    key: str
    section: str
    kind: str              # bool | int | float | choice | str
    default: Any
    label_pl: str
    label_en: str
    choices: tuple = ()
    lo: float | None = None
    hi: float | None = None


GAME_SCHEMA: list[Opt] = [
    Opt("window_mode", "graphics", "choice", "windowed", "Tryb okna", "Window mode",
        ("windowed", "fullscreen", "exclusive")),
    Opt("resolution", "graphics", "choice", "1280x720", "Rozdzielczość (okno)", "Resolution (window)",
        ("1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160")),
    Opt("scale_3d", "graphics", "float", 1.0, "Skala renderowania 3D", "3D render scale", lo=0.5, hi=1.0),
    Opt("vsync", "graphics", "bool", True, "Synchronizacja pionowa", "V-Sync"),
    Opt("max_fps", "graphics", "int", 0, "Limit FPS (0 = brak)", "FPS limit (0 = none)", lo=0, hi=360),
    Opt("shadows", "graphics", "choice", "medium", "Jakość cieni", "Shadow quality", ("off", "low", "medium", "high")),
    Opt("load_radius", "graphics", "int", 1, "Komórki wokół gracza", "Cells around player", lo=1, hi=3),
    Opt("view_distance", "graphics", "int", 1500, "Odległość widzenia [m]", "View distance [m]", lo=200, hi=6000),
    Opt("water", "graphics", "bool", True, "Woda", "Water"),
    Opt("fog", "graphics", "bool", True, "Mgła i pogoda (postprocessing)", "Fog and weather"),
    # roślinność wyliczona przez konwerter (Ustawienia → Świat): rysowanie w grze
    Opt("grass", "graphics", "bool", True, "Roślinność (trawa)", "Groundcover (grass)"),
    Opt("grass_distance", "graphics", "int", 90, "Zasięg roślinności [m]", "Groundcover distance [m]", lo=20, hi=400),
    Opt("grass_density", "graphics", "float", 1.0, "Gęstość roślinności w grze", "Groundcover density in game",
        lo=0.1, hi=1.0),
    Opt("mouse_sensitivity", "controls", "float", 0.0025, "Czułość myszy", "Mouse sensitivity", lo=0.0005, hi=0.01),
    Opt("invert_y", "controls", "bool", False, "Odwróć oś Y", "Invert Y axis"),
    # lokalizacja runtime (fork OpenMW RLF): „auto” = język launchera, „original” = bez tłumaczenia,
    # albo kod/lista kodów („pl” lub „pl,en”) – tłumaczenia z world/localization, bez ponownej konwersji
    Opt("game_language", "language", "str", "auto", "Język gry", "Game language"),
    Opt("qa_source", "language", "str", "", "QA: wyróżnij tłumaczenia z modułu (np. MojMod)",
        "QA: highlight translations from module"),
]

LAUNCHER_DEFAULTS: dict[str, Any] = {
    "version": 1,
    "language": "pl",               # język interfejsu launchera
    "install": None,                # {"kind": "morrowind|openmw_cfg|data", "path": ...}
    "converted_dir": None,          # katalog przekonwertowanych danych (domyślnie XDG data/converted)
    "conversion_scope": "full",     # full | balmora
    "active_profile": "default",
    "godot_path": "",               # puste = wykrywanie (MWGODOT_GODOT, PATH, obok aplikacji)
    "python_path": "",              # puste = interpreter launchera
    "project_dir": "",              # projekt Godota (puste = wykrywanie)
    "minimize_on_play": True,
    "bake": True,                   # wypiekanie scen z teksturami VRAM po konwersji
    "launch_args": "",              # dodatkowe parametry Godota (dzielone bezpiecznie, bez powłoki)
    "godot_version": "",            # zapamiętana wersja (sprawdzana tylko na żądanie lub po grze – nie przy starcie)
    "wizard_done": False,
    # roślinność (odpowiednik world.cfg forka OpenMW RLF: [flora] i [Groundcover]) – wpływa na konwersję
    "flora": {"enabled": False, "source": "automatic", "density": 1.0, "exclusion_distance": 3.0,
              "groundcover_enabled": False, "groundcover_density": 1.0},
    "wizard_step": 0,
}


def validate_game(values: dict) -> dict:
    """Uzupełnia brakujące wartości domyślnymi i odrzuca niepoprawne (bez wyjątków)."""
    out = {}
    for o in GAME_SCHEMA:
        v = values.get(o.key, o.default)
        try:
            if o.kind == "bool":
                v = bool(v)
            elif o.kind == "int":
                v = int(v)
                v = int(max(o.lo, min(o.hi, v))) if o.lo is not None else v
            elif o.kind == "float":
                v = float(v)
                v = max(o.lo, min(o.hi, v)) if o.lo is not None else v
            elif o.kind == "choice":
                v = v if v in o.choices else o.default
            else:
                v = str(v)
        except (TypeError, ValueError):
            v = o.default
        out[o.key] = v
    return out


def game_defaults() -> dict:
    return {o.key: o.default for o in GAME_SCHEMA}


@dataclass
class LauncherConfig:
    path: Path
    values: dict = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path) -> "LauncherConfig":
        v = dict(LAUNCHER_DEFAULTS)
        v.update(read_json(path, {}) or {})
        return cls(Path(path), v)

    def save(self) -> None:
        write_json(self.path, self.values)

    def __getitem__(self, k):
        return self.values.get(k, LAUNCHER_DEFAULTS.get(k))

    def __setitem__(self, k, v):
        self.values[k] = v
