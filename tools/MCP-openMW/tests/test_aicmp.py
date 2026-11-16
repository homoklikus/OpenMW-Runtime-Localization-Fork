"""Porównanie zachowań AI (etap 8): parsowanie logu, dopasowanie aktorów, ocena zgodności."""
import json

from openmw_mcp import aicmp


def _actor(i, rec, start, samples, pkg, types=None):
    return {"kind": "actor", "id": i, "data": {"recordId": rec, "start": start, "samples": samples,
                                              "package": pkg, "packages": types or [pkg["type"]] * len(samples)}}


def test_parse_log(tmp_path):
    log = tmp_path / "openmw.log"
    log.write_text('x\n[Lua] RLF_AI actor "0x1" {"recordId":"fargoth","samples":[[0,0,0]]}\nRLF_AI DONE\n', encoding="utf-8")
    r = aicmp.parse_log(log)
    assert r == [{"kind": "actor", "id": "0x1", "data": {"recordId": "fargoth", "samples": [[0, 0, 0]]}}]


def test_request_lua():
    s = aicmp.request_lua({"pos": [1, 2, 3], "crime": {"victim": "a"}})
    assert s.startswith("--") and "pos = { 1, 2, 3 }" in s and 'victim = "a"' in s


def test_compare_agree_and_differ():
    eng = [_actor("e1", "Fargoth", [100, 100, 0], [[100, 100, 0], [400, 100, 0]], {"type": "Wander", "distance": 512}),
           _actor("e2", "guard", [-9000, -70000, 0], [[-9000, -70000, 0]], {"type": "Wander", "distance": 0}),
           _actor("e3", "far", [20000, 20000, 0], [[20000, 20000, 0]], {"type": "Wander", "distance": 0}),
           {"kind": "crime", "id": "assault", "data": {"seen": True, "bounty": 40, "guard_pursue": True, "victim_combat": True}}]
    ours = [{"kind": "meta", "id": "cells", "data": {"grids": [[0, 0], [-2, -9]]}},
            _actor("m#1", "fargoth", [110, 90, 0], [[110, 90, 0], [300, 300, 0]], {"type": "wander", "distance": 512}),
            _actor("m#2", "guard", [-9000, -70010, 0], [[-9000, -70010, 0]], {"type": "wander", "distance": 0}),
            {"kind": "crime", "id": "assault", "data": {"seen": True, "bounty": 40, "guard_pursue": True, "victim_combat": True}}]
    rep = aicmp.compare(eng, ours)
    assert rep["actors"]["matched"] == 2 and rep["actors"]["missing_in_ours"] == []   # „far” – poza komórkami
    assert rep["summary"]["ok"] and rep["summary"]["crime_agree"]
    ours[1]["data"]["package"]["distance"] = 256
    rep2 = aicmp.compare(eng, ours)
    assert not rep2["summary"]["ok"] and rep2["checks"]["wander_distance"] == {"agree": 1, "of": 2}
    json.dumps(rep2)
