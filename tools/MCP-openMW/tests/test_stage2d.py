"""Etap 2d portu (NPC): ujęcia NPC z przodu, zamrażanie aktorów w OpenMW, kolejka ujęć."""

from __future__ import annotations

import json
import math
from pathlib import Path

from openmw_mcp import capture


def test_npc_shot_faces_actor():
    ref = {"id": "fargoth", "pos": [100.0, 200.0, 50.0], "rotz": math.pi / 2, "cell": [0, 0]}   # patrzy w +X
    s = capture.npc_shot(ref, "npc-fargoth", distance=230.0, eye=105.0, look=85.0)
    assert abs(s.camera[0] - 330.0) < 0.2 and abs(s.camera[1] - 200.0) < 0.2 and s.camera[2] == 155.0
    assert abs(s.yaw - (-math.pi / 2)) < 1e-4                      # kamera patrzy w −X, na NPC
    assert 0.0 < s.pitch < 0.2 and s.player[0] > s.camera[0]       # gracz za kamerą
    assert s.actors == [{"id": "fargoth", "pos": [100.0, 200.0, 50.0], "rotz": math.pi / 2}]
    lua = capture.scenario_lua([s], capture.DEFAULT_TIMING)
    assert 'actors = { { id = "fargoth"' in lua and "fov = 55.0" in lua and "visibility" not in lua
    plain = capture.scenario_lua([capture.Shot("x", [0, 0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 0.0, 0.0)],
                                 capture.DEFAULT_TIMING)
    assert "actors" not in plain and "fov" not in plain


def test_capture_lua_freezes_actors():
    root = Path(capture.LUA_DIR)
    assert "CUSTOM: scripts/rlf_capture/actor.lua" in (root / "rlf_capture.omwscripts").read_text()
    g = (root / "scripts/rlf_capture/global.lua").read_text()
    assert "freezeActors" in g and "addScript('scripts/rlf_capture/actor.lua')" in g
    assert "removePackages" in (root / "scripts/rlf_capture/actor.lua").read_text()
    assert "math.rad(shot.fov)" in (root / "scripts/rlf_capture/player.lua").read_text()


def test_queue_replaces_shots(tmp_path):
    class E:
        cfg = {"profiles": {"ext": {"target": "external", "paths": {}, "command": ["true", "{shots}", "{out}"]}}}

        def p(self, rel):
            return Path(rel)

    zr = tmp_path / "zrzuty"
    run_dir = zr / "2026-01-01-porownanie"
    capture.prepare(E(), "ext", [capture.Shot("c0_0", [0, 0], [0.0] * 3, [0.0] * 3, 0.0, 0.0)], run_dir)
    s = capture.npc_shot({"id": "a", "pos": [0.0, 0.0, 0.0], "rotz": 0.0}, "npc-a")
    from dataclasses import asdict
    (zr / capture.QUEUE_NAME).write_text(json.dumps({"shots": [asdict(s)]}))
    q = capture.apply_queue(run_dir, E())
    assert q == {"shots": ["npc-a"], "profiles": ["ext"]}
    sj = json.loads((run_dir / "ext/shots.json").read_text())
    assert [x["id"] for x in sj["shots"]] == ["npc-a"] and sj["shots"][0]["actors"][0]["id"] == "a"
    assert not (zr / capture.QUEUE_NAME).exists() and (run_dir / capture.QUEUE_NAME).is_file()
    assert capture.apply_queue(run_dir, E()) is None
