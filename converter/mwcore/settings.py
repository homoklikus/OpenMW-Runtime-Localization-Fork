"""Ustawienia: konfiguracja launchera (globalna) i ustawienia gry (per profil) ze schematem.

W schemacie są wyłącznie opcje, które Runtime faktycznie obsługuje (scripts/main.gd → _apply_settings).
Część opcji (dźwięk, napisy, mysz, pole widzenia, grafika) można też zmienić w grze (Esc → Ustawienia) – gra zapisuje
je do ingame_settings.json, a launcher scala je z profilem przy następnym uruchomieniu (launch.merge_ingame).
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
        ("1280x720", "1600x900", "1920x1080", "2560x1080", "2560x1440", "3440x1440", "3840x1600", "3840x2160",
         "5120x1440")),
    Opt("scale_3d", "graphics", "float", 1.0, "Skala renderowania 3D", "3D render scale", lo=0.5, hi=1.0),
    Opt("vsync", "graphics", "bool", True, "Synchronizacja pionowa", "V-Sync"),
    Opt("vsync_adaptive", "graphics", "bool", False, "Synchronizacja adaptacyjna", "Adaptive V-Sync"),
    Opt("window_border", "graphics", "bool", True, "Ramka okna", "Window border"),
    Opt("max_fps", "graphics", "int", 0, "Limit FPS (0 = brak)", "FPS limit (0 = none)", lo=0, hi=360),
    Opt("shadows", "graphics", "choice", "medium", "Jakość cieni", "Shadow quality", ("off", "low", "medium", "high")),
    Opt("load_radius", "graphics", "int", 1, "Komórki wokół gracza", "Cells around player", lo=1, hi=3),
    Opt("view_distance", "graphics", "int", 1500, "Odległość widzenia [m]", "View distance [m]", lo=200, hi=6000),
    Opt("water", "graphics", "bool", True, "Woda", "Water"),
    Opt("water_shader", "graphics", "bool", True, "Woda z falami i załamaniem (shader OpenMW)",
        "Shader water (OpenMW waves, refraction)"),
    Opt("fog", "graphics", "bool", True, "Mgła i pogoda (postprocessing)", "Fog and weather"),
    # roślinność wyliczona przez konwerter (Ustawienia → Świat): rysowanie w grze
    Opt("grass", "graphics", "bool", True, "Roślinność (trawa)", "Groundcover (grass)"),
    Opt("grass_distance", "graphics", "int", 90, "Zasięg roślinności [m]", "Groundcover distance [m]", lo=20, hi=400),
    Opt("grass_density", "graphics", "float", 1.0, "Gęstość roślinności w grze", "Groundcover density in game",
        lo=0.1, hi=1.0),
    # dźwięk (etap 10) – domyślne jak OpenMW [Sound]
    Opt("master_volume", "audio", "float", 1.0, "Głośność ogólna", "Master volume", lo=0.0, hi=1.0),
    Opt("music_volume", "audio", "float", 0.5, "Muzyka", "Music volume", lo=0.0, hi=1.0),
    Opt("voice_volume", "audio", "float", 0.8, "Głosy", "Voice volume", lo=0.0, hi=1.0),
    Opt("sfx_volume", "audio", "float", 1.0, "Efekty", "Effects volume", lo=0.0, hi=1.0),
    Opt("footsteps_volume", "audio", "float", 0.2, "Kroki", "Footsteps volume", lo=0.0, hi=1.0),
    Opt("subtitles", "audio", "bool", True, "Napisy kwestii", "Subtitles"),
    Opt("fov", "controls", "int", 60, "Pole widzenia (pionowe) [°]", "Field of view (vertical) [°]", lo=40, hi=110),
    Opt("mouse_sensitivity", "controls", "float", 0.0025, "Czułość myszy", "Mouse sensitivity", lo=0.0005, hi=0.0125),
    Opt("invert_x", "controls", "bool", False, "Odwróć oś X", "Invert X axis"),
    Opt("invert_y", "controls", "bool", False, "Odwróć oś Y", "Invert Y axis"),
    Opt("enable_controller", "controls", "bool", True, "Pad", "Enable controller"),
    # okno opcji w grze (zakładka Prefs) – domyślne jak OpenMW settings-default.cfg
    Opt("menu_transparency", "game", "float", 0.84, "Przezroczystość menu", "Menu transparency", lo=0.0, hi=1.0),
    Opt("tooltip_delay", "game", "float", 0.0, "Opóźnienie podpowiedzi [s]", "Menu help delay [s]", lo=0.0, hi=1.0),
    Opt("difficulty", "game", "int", 0, "Poziom trudności", "Difficulty", lo=-100, hi=100),
    Opt("actors_processing_range", "game", "int", 7168, "Zasięg przetwarzania aktorów", "Actors processing range",
        lo=3584, hi=7168),
    Opt("autosave", "game", "bool", True, "Autozapis przed odpoczynkiem", "Auto-save on resting"),
    Opt("best_attack", "game", "bool", False, "Zawsze najlepszy atak", "Always use best attack"),
    Opt("crosshair", "game", "bool", True, "Celownik", "Crosshair"),
    # lokalizacja runtime (fork OpenMW RLF): „auto” = język launchera, „original” = bez tłumaczenia,
    # albo kod/lista kodów („pl” lub „pl,en”) – tłumaczenia z world/localization, bez ponownej konwersji
    Opt("game_language", "language", "str", "auto", "Język gry", "Game language"),
    # [General] preferred locales i gmst overrides l10n (OpenMW) – zakładka Language okna opcji w grze; teksty
    # silnika (l10n) niezależne od tłumaczeń danych gry
    Opt("preferred_locales", "language", "str", "en", "Języki tekstów silnika (l10n)", "Engine text languages (l10n)"),
    Opt("gmst_overrides_l10n", "language", "bool", True, "Teksty z plików ESM mają pierwszeństwo",
        "Strings from ESM files have priority"),
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
    "flora": {"enabled": True, "source": "automatic", "density": 1.0, "exclusion_distance": 3.0,
              "groundcover_enabled": False, "groundcover_density": 1.0},
    "wizard_step": 0,
}


def normalize_resolution(v) -> str | None:
    """„SZERxWYS” w rozsądnych granicach (640×360 … 15360×8640) albo None."""
    import re
    m = re.fullmatch(r"\s*(\d{3,5})\s*[x×]\s*(\d{3,5})\s*", str(v))
    if not m:
        return None
    w, h = int(m.group(1)), int(m.group(2))
    return f"{w}x{h}" if 640 <= w <= 15360 and 360 <= h <= 8640 else None


def resolution_choices(screens: list[tuple[int, int]] = (), current: str = "") -> list[str]:
    """Lista dla launchera: standardowe + natywne rozdzielczości podłączonych ekranów + bieżąca, posortowane."""
    opt = next(o for o in GAME_SCHEMA if o.key == "resolution")
    vals = set(opt.choices) | {f"{w}x{h}" for w, h in screens if normalize_resolution(f"{w}x{h}")}
    if normalize_resolution(current):
        vals.add(normalize_resolution(current))
    return sorted(vals, key=lambda r: tuple(int(x) for x in r.split("x")))


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
            elif o.key == "resolution":
                v = normalize_resolution(v) or o.default   # także rozdzielczość wykryta z ekranu (spoza listy)
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
