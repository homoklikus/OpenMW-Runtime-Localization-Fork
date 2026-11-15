"""Lokalizacja runtime (przeniesione z forka OpenMW RLF – components/translation, apps/openmw/engine.cpp).

Dla każdego aktywnego pliku treści (w kolejności ładowania) szukamy w VFS pliku-towarzysza:

    Morrowind.esm       → localization/language/Morrowind.yaml
    Moj Mod.esp         → localization/language/Moj Mod.yaml

Format YAML (jak w forku, `docs/runtime-localization-*.md`):

    meta: {module: ..., source_language: en}
    strings:
      'CLOT|ring_keley|FNAM': {EN: '...', PL: '...'}
      'INFO|Topic|info_id|NAME': {PL: {default: .., npc: {male: .., female: ..}, player: {...}, npc_player: {...}}}
    fallbacks:              # tłumaczenia wartości z Morrowind.ini (sekcja → klucz → języki)
      Question 1: {Question: {EN: .., PL: ..}}

Późniejszy plik nadpisuje wartość wcześniejszego dla każdego języka osobno (także znaczniki formatowania) –
jak w forku, gdzie każdy plik jest stosowany po kolei z wyborem języka; brak języka w późniejszym pliku
zostawia wartość z wcześniejszego.
Pliki ESM/ESP nie są zmieniane: wynik to osobne pliki JSON na język, wybierane przez grę w trakcie działania
(lista preferowanych języków, np. „pl,en”). Klucze mają ID rekordu małymi literami (wyszukiwanie bez
rozróżniania wielkości liter, jak RefId w OpenMW).

Wynik (katalog wyników konwersji):
    world/localization/index.json                  języki, źródła (moduły), liczby wpisów
    world/localization/<LANG>/names.json           nazwy: FNAM, CELL/DIAL NAME, REGN, GMST – wczytywane od razu
    world/localization/<LANG>/texts.json           pozostałe (INFO, BOOK TEXT, opisy, skrypty) – na żądanie
    world/localization/<LANG>/fallbacks.json       wartości Morrowind.ini
Każdy wpis: [tekst ze znacznikami, indeks źródła]; INFO z wariantami: [słownik wariantów, indeks źródła].
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path

CONTENT_EXT = (".esm", ".esp", ".omwaddon", ".omwgame")
NAME_FIELDS = {"FNAM", "STRV"}
NAME_TYPES_NAME_FIELD = {"CELL", "DIAL"}
INFO_VARIANT_KEYS = {"default", "npc", "player", "npc_player"}


def sidecar_stem(content_name: str) -> str | None:
    base = os.path.basename(content_name)
    low = base.lower()
    for ext in CONTENT_EXT:
        if low.endswith(ext):
            return base[: -len(ext)]
    return None  # np. .omwscripts – nie jest źródłem lokalizacji


def find_sidecars(vfs, content: list) -> list:
    """[(nazwa pliku treści, klucz VFS YAML)] w kolejności ładowania; brakujące pomijane."""
    out = []
    for c in content:
        stem = sidecar_stem(c)
        if stem is None:
            continue
        key = f"localization/language/{stem}.yaml"
        if vfs.exists(key):
            out.append((os.path.basename(c), key))
    return out


def _yaml_load(data: bytes):
    import yaml
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
    return yaml.load(data.decode("utf-8-sig"), Loader=loader)


def norm_key(key: str) -> str | None:
    """'CLOT|Ring_Keley|FNAM' → 'CLOT|ring_keley|FNAM'; INFO: 'INFO|topic|info|NAME' (topic i info małymi)."""
    parts = str(key).split("|")
    if len(parts) < 3 or not parts[0]:
        return None
    rtype = parts[0].upper()
    if rtype == "INFO":
        if len(parts) != 4:
            return None
        return f"INFO|{parts[1].lower()}|{parts[2].lower()}|{parts[3].upper()}"
    return f"{rtype}|{'|'.join(p.lower() for p in parts[1:-1])}|{parts[-1].upper()}"


def is_name_key(nk: str) -> bool:
    rtype, field = nk.split("|", 1)[0], nk.rsplit("|", 1)[-1]
    if rtype == "INFO":
        return False
    base_field = field.split("[", 1)[0]
    return base_field in NAME_FIELDS or (rtype in NAME_TYPES_NAME_FIELD and base_field == "NAME")


def _lang_key(k) -> str:
    return str(k).upper().replace("-", "_")


def check_markup(text: str) -> bool:
    """Znaczniki [c=#RRGGBB] [b] [i] muszą być poprawnie zamknięte i zagnieżdżone (jak w forku)."""
    import re
    stack = []
    for m in re.finditer(r"\[(/?)(c|b|i)(=#[0-9A-Fa-f]{6})?\]", text):
        closing, tag, arg = m.group(1), m.group(2), m.group(3)
        if closing:
            if arg or not stack or stack[-1] != tag:
                return False
            stack.pop()
        else:
            if (tag == "c") != bool(arg):
                return False
            stack.append(tag)
    return not stack


def export(vfs, content: list, out: Path, log=print, warn=None) -> dict:
    """Scala pliki-towarzysze i zapisuje world/localization/. Pomija pracę, gdy pliki się nie zmieniły."""
    t0 = time.perf_counter()
    _warn = warn or (lambda m: log("Lokalizacja: " + m))
    nwarn = [0]

    def warn(m):  # duży plik z błędami nie może zalać dziennika
        nwarn[0] += 1
        if nwarn[0] <= 20:
            _warn(m)
        elif nwarn[0] == 21:
            _warn("kolejne ostrzeżenia pominięte (liczba w raporcie)")
    out = Path(out)
    ldir = out / "world" / "localization"
    sides = find_sidecars(vfs, content)
    fp = []
    for cname, key in sides:
        f = vfs.info(key)
        fp.append([cname, key, f.size, f.mtime])
    state_file = out / ".mwconv" / "localization_state.json"
    fp_key = hashlib.sha256(json.dumps(fp, sort_keys=True).encode()).hexdigest()
    if state_file.exists() and (ldir / "index.json").exists():
        try:
            if json.loads(state_file.read_text()).get("key") == fp_key:
                return {"skipped": True, "sidecars": len(sides)}
        except (OSError, ValueError):
            pass

    sources: list[str] = []
    merged: dict[str, dict] = {}          # klucz → {język: (wartość, indeks źródła)}
    fallbacks: dict[str, tuple] = {}      # "sekcja|klucz" → (języki, źródło)
    bad_markup = 0
    for cname, key in sides:
        module = os.path.splitext(cname)[0]
        try:
            doc = _yaml_load(vfs.read(key))
        except Exception as e:  # noqa: BLE001 – błędny plik nie przerywa konwersji
            warn(f"nie można wczytać {key}: {type(e).__name__}: {e}")
            continue
        if not isinstance(doc, dict):
            warn(f"pusty lub niepoprawny {key}")
            continue
        src = len(sources)
        sources.append(module)
        n = 0
        for k, v in (doc.get("strings") or {}).items():
            nk = norm_key(k)
            if nk is None or not isinstance(v, dict):
                warn(f"pominięty klucz {k!r} w {key}")
                continue
            langs = {}
            for lk, lv in v.items():
                L = _lang_key(lk)
                if isinstance(lv, (str, int, float)):
                    langs[L] = str(lv)
                elif isinstance(lv, dict) and nk.startswith("INFO|") and set(lv) <= INFO_VARIANT_KEYS:
                    langs[L] = lv
                else:
                    warn(f"{k}.{lk}: wartość musi być tekstem" + (" lub wariantami INFO" if nk.startswith("INFO|") else ""))
            if langs:
                slot = merged.setdefault(nk, {})
                for L, val in langs.items():
                    slot[L] = (val, src)    # późniejszy plik nadpisuje ten język
                n += 1
        for sect, items in (doc.get("fallbacks") or {}).items():
            if not isinstance(items, dict):
                continue
            for fk, fv in items.items():
                if isinstance(fv, dict):
                    fallbacks[f"{sect}|{fk}"] = ({_lang_key(a): str(b) for a, b in fv.items()
                                                  if isinstance(b, (str, int, float))}, src)
        log(f"Lokalizacja: {key} – {n} wpisów")

    # rozdział na języki
    per_lang: dict[str, dict[str, dict]] = {}
    for nk, langs in merged.items():
        part = "names" if is_name_key(nk) else "texts"
        for L, (val, src) in langs.items():
            if isinstance(val, str) and "[" in val and not check_markup(val):
                bad_markup += 1
                warn(f"błędne znaczniki formatowania w {nk} ({L}) – tekst bez formatowania")
            per_lang.setdefault(L, {"names": {}, "texts": {}, "fallbacks": {}})[part][nk] = [val, src]
    for fk, (langs, src) in fallbacks.items():
        for L, val in langs.items():
            per_lang.setdefault(L, {"names": {}, "texts": {}, "fallbacks": {}})["fallbacks"][fk] = [val, src]

    from .world import write_json
    if ldir.exists():
        import shutil
        shutil.rmtree(ldir)
    counts = {}
    for L, parts in sorted(per_lang.items()):
        for part, data in parts.items():
            write_json(ldir / L / f"{part}.json", {"sources": sources, "strings": data}, compact=True)
        counts[L] = {p: len(d) for p, d in parts.items()}
    index = {"format": "mwgodot-localization", "version": 1, "languages": sorted(per_lang),
             "sources": sources, "sidecars": [k for _, k in sides], "counts": counts, "malformed_markup": bad_markup}
    write_json(ldir / "index.json", index)
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps({"key": fp_key}))
    return {"sidecars": len(sides), "languages": index["languages"], "entries": len(merged),
            "fallbacks": len(fallbacks), "malformed_markup": bad_markup, "warnings": nwarn[0],
            "seconds": round(time.perf_counter() - t0, 3)}
