"""Porównanie wzorów RPG (etap 7): żądanie z danych, Lua, odczyt logu i porównanie."""
import json
from pathlib import Path

from openmw_mcp import mechcmp


def _records(tmp: Path) -> Path:
    rd = tmp / "records"
    rd.mkdir()
    (rd / "armor.json").write_text(json.dumps({"iron_helmet": {"armor_type": 0}, "iron_cuirass": {"armor_type": 1},
                                               "glass_boots": {"armor_type": 5}}))
    (rd / "weapon.json").write_text(json.dumps({"w1": {"enchant": "e1"}, "w2": {}}))
    (rd / "potion.json").write_text(json.dumps({
        "p_ok": {"effects": [{"effect": 79, "min": 5, "max": 5, "duration": 10}]},
        "p_rand": {"effects": [{"effect": 75, "min": 1, "max": 5, "duration": 10}]},
        "p_harm": {"effects": [{"effect": 23, "min": 5, "max": 5, "duration": 10}]}}))
    (rd / "magiceffect.json").write_text(json.dumps({"79": {}, "75": {}, "23": {}}))
    return rd


def test_build_request(tmp_path):
    req = mechcmp.build_request(_records(tmp_path))
    assert [p["id"] for p in req["potions"]] == ["p_ok"]          # losowe i szkodliwe pominięte
    assert req["enchanted"] == ["w1"]
    names = [s["name"] for s in req["armor_sets"]]
    assert names == ["iron", "glass"] and req["armor_sets"][0]["items"][0] == {"id": "iron_helmet", "slot": "Helmet"}
    assert "iron_cuirass" in req["create"] and "w1" in req["create"]
    lua = mechcmp.request_lua(req)
    assert lua.startswith("-- ") and "skill_uses = {" in lua and 'slot = "Helmet"' in lua


def test_parse_and_compare(tmp_path):
    log = tmp_path / "openmw.log"
    log.write_text('x RLF_MECH charge "w1" {"charge":50}\nRLF_MECH armor 1 {"rating":12.5,"items":[["a",3]],'
                   '"adjusted":[4.0]}\nRLF_MECH ERROR boom\nRLF_MECH DONE\n')
    eng = mechcmp.parse_log(log)
    assert [e["kind"] for e in eng] == ["charge", "armor", "ERROR"]
    ours = [{"kind": "charge", "id": "w1", "data": {"charge": 50}},
            {"kind": "armor", "id": 1, "data": {"rating": 12.5, "items": [["a", 3.5]], "adjusted": [4.0]}}]
    rep = mechcmp.compare(eng, ours)
    assert rep["summary"]["cases"] == 2 and rep["summary"]["mismatched"] == 1
    assert rep["mismatches"][0]["field"] == "items" and len(rep["errors"]) == 1


def test_pending_request(tmp_path):
    run_dir = tmp_path / "Raporty/mcp/rekordy/2026-01-01"
    run_dir.mkdir(parents=True)
    assert mechcmp.pending_request(run_dir) is None
    pend = tmp_path / "Raporty/mcp/mechanika/pending"
    pend.mkdir(parents=True)
    (pend / "request.json").write_text('{"a": 1}')
    assert mechcmp.pending_request(run_dir) == {"a": 1}
    assert not (pend / "request.json").exists() and (run_dir / "mech_pending_used.json").exists()
