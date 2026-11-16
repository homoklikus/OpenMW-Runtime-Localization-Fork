"""Etap 1 OpenMWGodot: porównanie rekordów world/records/ z rekordami silnika OpenMW (atrapa logu silnika)."""
import json
from pathlib import Path

from openmw_mcp import recordcmp as RC


def records_dir(tmp_path):
    d = tmp_path / "records"
    d.mkdir()
    for f in RC.FILES.values():
        (d / f"{f}.json").write_text("{}")
    (d / "weapon.json").write_text(json.dumps({
        "iron longsword": {"id": "iron longsword", "name": "Iron Longsword", "model": "w\\W_Longsword_Iron.NIF",
                           "icon": "w\\Tx_longsword_iron.tga", "weight": 20.0, "value": 40, "weapon_type": 1,
                           "health": 800, "speed": 1.35, "reach": 1.0, "enchant_capacity": 60, "chop": [2, 13],
                           "slash": [1, 18], "thrust": [4, 16], "magical": False, "silver": False,
                           "source": "Morrowind.esm"},
        "x": {"id": "x", "name": "X", "weight": 1.0, "value": 1, "source": "b.esp", "overridden": ["a.esm"]}}))
    (d / "class.json").write_text(json.dumps({"spellsword": {"id": "Spellsword", "name": "Spellsword", "playable": True,
        "specialization": 0, "major_skills": [5, 10], "minor_skills": [0], "attributes": [0, 5]}}))
    (d / "gmst.json").write_text(json.dumps({"ileveluptotal": {"id": "iLevelupTotal", "type": "int", "value": 10}}))
    (d / "global.json").write_text(json.dumps({"pcrace": {"id": "PCRace", "type": "short", "value": 0}}))
    (d / "index.json").write_text("{}")
    return d


def test_sample_overridden_first(tmp_path):
    d = records_dir(tmp_path)
    s = RC.sample(d, ["Weapon"], 5)
    assert s["Weapon"][0] == "x" and set(s["Weapon"]) == {"x", "iron longsword"}


def test_request_and_compare(tmp_path):
    d = records_dir(tmp_path)
    lua = RC.request_lua({"Weapon": ["iron longsword"]}, ["iLevelupTotal"], ["PCRace"])
    assert 'kind = "Weapon"' in lua and '"chopMinDamage"' in lua and 'gmst = { "iLevelupTotal" }' in lua
    log = tmp_path / "openmw.log"
    log.write_text("\n".join([
        '[12:00:00.000 I] RLF_REC Weapon "iron longsword" {"name":"Iron Longsword","model":"meshes/w/w_longsword_iron.nif",'
        '"icon":"icons/w/tx_longsword_iron.dds","weight":20,"value":40,"type":1,"health":800,"speed":1.35000002,"reach":1,'
        '"enchantCapacity":6,"chopMinDamage":2,"chopMaxDamage":13,"slashMinDamage":1,"slashMaxDamage":18,'
        '"thrustMinDamage":4,"thrustMaxDamage":17,"isMagical":false,"isSilver":false}',
        'RLF_REC Class "spellsword" {"name":"Spellsword","isPlayable":true,"specialization":"combat",'
        '"majorSkills":["destruction","longblade"],"minorSkills":["block"],"attributes":["endurance","strength"]}',
        'RLF_REC Weapon "nie_ma" null',
        'RLF_REC GMST "iLevelupTotal" {"value":10}',
        'RLF_REC GLOB "PCRace" {"value":0}',
        'RLF_REC DONE']))
    eng = RC.parse_log(log)
    assert eng[("Weapon", "iron longsword")]["value"] == 40 and eng[("Weapon", "nie_ma")] is None
    rep = RC.compare(d, eng, ["iLevelupTotal"], ["PCRace"])
    assert rep["types"]["Weapon"]["records"] == 1 and rep["types"]["Class"]["mismatched_fields"] == 0
    # jedyna niezgodność: thrustMax 16 vs 17 (ścieżki, wielkość liter, rozszerzenia ikon i skala zaklęcia OK)
    assert [(m["field"], m["ours"], m["openmw"]) for m in rep["mismatches"]] == [("thrustMaxDamage", 16, 17)]
    assert rep["missing_in_engine"] == ["Weapon:nie_ma"] and rep["types"]["GMST"]["mismatched_fields"] == 0
    assert rep["by_field"] == {"Weapon.thrustMaxDamage": 1}


def test_text_sum_and_empty_paths():
    assert RC.text_sum("ab") == [2, (97 * 31 + 98)] and RC.text_sum("ż")[0] == 2
    assert RC._eq("s", None, "meshes/") and RC._eq("s", None, "icons/") and not RC._eq("s", "x.nif", "meshes/")
