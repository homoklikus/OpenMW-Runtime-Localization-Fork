"""Wartości „fallback” z instalacji gracza (etap 10): pytania o klasę i komunikaty awansu – w OpenMW
Fallback::Map ("Question_1_Question", "Level_Up_Level2"…), pochodzące z Morrowind.ini (sekcje [Question 1],
[Level Up]) albo z openmw.cfg (fallback=Klucz,Wartość). Zapis: world/fallbacks.json (tylko lokalnie – teksty gry)."""

from __future__ import annotations

import configparser
from pathlib import Path

PREFIXES = ("Question_", "Level_Up_")


def _from_openmw_cfg(path: Path) -> dict:
    out = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("fallback="):
            continue
        kv = line[len("fallback="):]
        if "," not in kv:
            continue
        k, v = kv.split(",", 1)
        if k.startswith(PREFIXES):
            out[k] = v
    return out


def _from_ini(path: Path) -> dict:
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read_string(path.read_bytes().decode("cp1252", errors="replace"))
    except configparser.Error:
        return {}
    out = {}
    for sect in cp.sections():
        if not (sect.startswith("Question ") or sect == "Level Up"):
            continue
        prefix = sect.replace(" ", "_") + "_"
        for k, v in cp.items(sect):
            out[prefix + k] = v
    return out


def find_values(cfg) -> dict:
    """openmw.cfg (gdy konwersja z niego) albo Morrowind.ini obok katalogu danych."""
    origin = Path(cfg.origin) if getattr(cfg, "origin", "") else None
    if origin is not None and origin.is_file() and origin.name.lower() == "openmw.cfg":
        vals = _from_openmw_cfg(origin)
        if vals:
            return vals
    cands = []
    if origin is not None:
        cands += [origin / "Morrowind.ini", origin.parent / "Morrowind.ini"]
    for d in cfg.data_dirs:
        p = Path(d)
        cands += [p.parent / "Morrowind.ini", p / "Morrowind.ini"]
    for c in cands:
        if c.is_file():
            return _from_ini(c)
    return {}


def export(cfg, wdir: Path, write_json) -> dict:
    vals = find_values(cfg)
    write_json(wdir / "fallbacks.json", {"format": "mwgodot-fallbacks", "version": 1, "values": vals})
    return {"values": len(vals)}
