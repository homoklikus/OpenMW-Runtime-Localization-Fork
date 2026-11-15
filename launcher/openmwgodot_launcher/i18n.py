"""Tłumaczenia interfejsu launchera (pl, en). Język gry nie jest jeszcze obsługiwany przez Runtime."""

LANG = "pl"

T = {
    "subtitle": ("Morrowind na silniku Godot", "Morrowind on the Godot engine"),
    "install": ("Instalacja", "Installation"),
    "conversion": ("Konwersja", "Conversion"),
    "profile": ("Profil", "Profile"),
    "play": ("Graj", "Play"),
    "mods": ("Mody", "Mods"),
    "settings": ("Ustawienia", "Settings"),
    "cs": ("Construction Set", "Construction Set"),
    "back": ("← Wstecz", "← Back"),
    "not_set": ("nie wskazano", "not set"),
    "st_ready": ("gotowa", "ready"),
    "st_missing": ("brak – uruchom konwersję", "missing – run conversion"),
    "st_incomplete": ("niekompletna – wznów lub napraw", "incomplete – resume or repair"),
    "st_running": ("w toku", "in progress"),
    "st_outdated": ("wymaga aktualizacji", "needs update"),
    "st_broken": ("uszkodzona – napraw", "damaged – repair"),
    "game_running": ("Gra działa", "Game running"),
    "manage_profiles": ("Profile…", "Profiles…"),
}


def tr(key: str) -> str:
    v = T.get(key)
    if v is None:
        return key
    return v[1] if LANG == "en" else v[0]


def set_lang(lang: str) -> None:
    global LANG
    LANG = "en" if lang == "en" else "pl"
