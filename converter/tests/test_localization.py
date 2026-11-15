"""Lokalizacja runtime przeniesiona z forka OpenMW RLF: pliki-towarzysze YAML → world/localization/."""
import json
from pathlib import Path

import pytest

from mwconv.localization import check_markup, norm_key, sidecar_stem
from mwconv.pipeline import Options, run

from test_resilience import _cfg


def test_helpers():
    assert sidecar_stem("Moj Mod.esp") == "Moj Mod" and sidecar_stem("x.omwaddon") == "x"
    assert sidecar_stem("skrypty.omwscripts") is None
    assert norm_key("CLOT|Ring_Keley|FNAM") == "CLOT|ring_keley|FNAM"
    assert norm_key("INFO|Greeting 0|ABC|name") == "INFO|greeting 0|abc|NAME"
    assert norm_key("INFO|za|malo") is None and norm_key("zly klucz") is None
    assert check_markup("[b][c=#ffd060]A[/c][/b]") and check_markup("bez znaczników")
    assert not check_markup("[b][i]A[/b][/i]") and not check_markup("[c=#ffd060]A") and not check_markup("[c]A[/c]")


def _strings(out, lang, part):
    j = json.loads((out / "world" / "localization" / lang / f"{part}.json").read_text())
    return {k: (v[0], j["sources"][v[1]]) for k, v in j["strings"].items()}


def test_sidecars_load_order_markup_and_variants(synth_data, tmp_path):
    import shutil
    d = tmp_path / "Data Files"
    shutil.copytree(synth_data["dir"], d)   # test zmienia plik YAML – kopia danych
    synth_data = {"dir": d}
    out = tmp_path / "out"
    s = run(_cfg(synth_data["dir"]), Options(out=out, cells=["Synthville"], jobs=1), log=lambda _m: None)
    loc = s["localization"]
    assert loc["sidecars"] == 2 and loc["languages"] == ["DE", "EN", "PL"] and loc["malformed_markup"] == 1
    idx = json.loads((out / "world" / "localization" / "index.json").read_text())
    assert idx["sources"] == ["mwg_synthtown", "mwg_synthtown_patch"]   # NieAktywny.yaml nie jest wczytany
    names = _strings(out, "PL", "names")
    assert names["DOOR|synth_door|FNAM"] == ("Drzwi (łatka)", "mwg_synthtown_patch")  # łatka nadpisuje (i znaczniki)
    assert names["MISC|synth_crate|FNAM"] == ("Skrzynka (łatka)", "mwg_synthtown_patch")  # wielkość liter ID bez znaczenia
    assert names["REGN|synthetic region|FNAM"][0] == "Kraina Syntetyczna (PL)"
    assert names["CELL|synthville, test house|NAME"][0] == "Synthville, Dom testowy"
    assert names["GMST|smonthmorningstar|STRV"][0] == "Gwiazda Poranna"
    texts = _strings(out, "PL", "texts")
    info = texts["INFO|greeting 0|synth_info_1|NAME"][0]
    assert info["default"] == "Witaj." and info["npc"]["female"] == "Witaj, wędrowczyni."
    assert "BOOK|synth_book|TEXT" in texts and "DOOR|synth_door|FNAM" not in texts
    # łatka nie ma DE → zostaje wartość z wcześniejszego pliku (jak w forku: każdy plik stosowany osobno)
    assert _strings(out, "DE", "names")["DOOR|synth_door|FNAM"] == ("Testtür", "mwg_synthtown")
    assert _strings(out, "PL", "fallbacks")["Question 1|Question"][0] == "Pytanie?"
    # bez zmian w plikach YAML → pominięte; zmiana tłumaczenia nie wymusza eksportu świata
    s2 = run(_cfg(synth_data["dir"]), Options(out=out, cells=["Synthville"], jobs=1), log=lambda _m: None)
    assert s2["localization"].get("skipped") and s2["world_load"].get("skipped")
    y = Path(synth_data["dir"]) / "localization" / "language" / "mwg_synthtown_patch.yaml"
    y.write_text(y.read_text(encoding="utf-8").replace("Drzwi (łatka)", "Drzwi (łatka 2)"), encoding="utf-8")
    s3 = run(_cfg(synth_data["dir"]), Options(out=out, cells=["Synthville"], jobs=1), log=lambda _m: None)
    assert s3["world_load"].get("skipped") and not s3["localization"].get("skipped")
    assert _strings(out, "PL", "names")["DOOR|synth_door|FNAM"][0] == "Drzwi (łatka 2)"
