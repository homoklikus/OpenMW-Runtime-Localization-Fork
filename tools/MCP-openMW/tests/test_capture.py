"""Etap 3: przygotowanie ujęć porównawczych, przebieg z atrapą procesu, porównanie obrazów."""

from __future__ import annotations

import json
import math
import struct
import threading
import time
from pathlib import Path

import pytest

from conftest import esp_bytes, rec, w
from openmw_mcp import capture
from openmw_mcp.land import LandIndex


def flat_land(tmp_path, height=200.0):
    body = b""
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            body += rec("LAND", [("INTV", struct.pack("<ii", dx, dy)), ("DATA", struct.pack("<I", 9)),
                                 ("VHGT", struct.pack("<f", height / 8) + bytes(65 * 65) + b"\0\0\0")])
    return LandIndex.load([w(tmp_path / "L.esm", esp_bytes() + body)])


def test_lua_values_and_scenario():
    assert capture._lua_value('a"b\\c') == '"a\\"b\\\\c"'
    assert capture._lua_value([1, 2.5, None, True]) == "{ 1, 2.5, nil, true }"
    s = capture.Shot("x1", [0, 0], [1.0, 2.0, 3.0], [0.0, 0.0, 0.0], 0.5, 0.1)
    text = capture.scenario_lua([s], capture.DEFAULT_TIMING)
    assert text.startswith("-- Wygenerowano") and 'id = "x1"' in text and "settleSeconds = 5.0" in text
    assert "note" not in text


def test_viewpoint_geometry(tmp_path):
    li = flat_land(tmp_path)
    sh = capture.viewpoint(li, 0, 0, target=(4096.0, 4096.0), distance=700.0)
    ne = capture.viewpoint(flat_land(tmp_path / "n"), 0, 0, target=(4096.0, 4096.0), distance=700.0)
    assert ne.camera == sh.camera
    cx, cy, cz = sh.camera
    assert math.isclose(math.hypot(4096 - cx, 4096 - cy), 700.0, rel_tol=1e-3)
    assert math.isclose(cz, 200.0 + 128.0, abs_tol=0.5)
    # konwencja API Lua openmw.camera (camerabindings.cpp neguje kąty): yaw = kurs (0 = +Y, w stronę +X), pitch > 0 = w dół
    assert math.isclose(math.sin(sh.yaw), (4096 - cx) / 700.0, abs_tol=1e-3)
    assert math.isclose(math.cos(sh.yaw), (4096 - cy) / 700.0, abs_tol=1e-3)
    assert sh.pitch > 0
    px, py, _ = sh.player
    assert math.hypot(4096 - px, 4096 - py) > 700.0              # gracz za kamerą
    dens = lambda x, y: 10.0 if (x // 512, y // 512) == (3, 12) else 0.0   # noqa: E731
    sd = capture.viewpoint(li, 0, 0, density=dens)
    assert "1792" in sd.note and "6400" in sd.note                # środek teksela (3,12)


def test_viewpoint_prefers_camera_above_target(tmp_path):
    body = b""
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            d = bytearray(65 * 65)
            for y in range(65):
                d[y * 65] = 1                                   # teren rośnie na północ (+Y): 8 j. na wierzchołek
            body += rec("LAND", [("INTV", struct.pack("<ii", dx, dy)), ("DATA", struct.pack("<I", 9)),
                                 ("VHGT", struct.pack("<f", 100 + dy * 65) + bytes(d) + b"\0\0\0")])
    li = LandIndex.load([w(tmp_path / "S.esm", esp_bytes() + body)])
    sh = capture.viewpoint(li, 0, 0, target=(4096.0, 4096.0))
    # kamera nie stoi poniżej celu (nie na południu, skąd patrzyłaby w zbocze) i zawsze patrzy lekko w dół
    assert sh.camera[1] >= 4096.0 and li.height_at(*sh.camera[:2]) >= li.height_at(4096.0, 4096.0) - 1e-6
    assert sh.pitch >= 0.08


def test_prepare_both_profiles(project, tmp_path):
    e = project["env"]
    shots = [capture.Shot("a", [15, -9], [0.0, 0.0, 300.0], [0.0, -250.0, 210.0], 0.0, 0.2)]
    run_dir = tmp_path / "run"
    fp = capture.prepare(e, "fork-test", shots, run_dir)
    cfg = run_dir / "fork-test/cfg"
    assert (cfg / "openmw.cfg").read_text().endswith("content=rlf_capture.omwscripts\n")
    assert "resolution x = 1920" in (cfg / "settings.cfg").read_text()
    assert (cfg / "world.cfg").is_file() and "world.cfg" in fp["copied_user_files"]
    assert fp["cmd"][1] == "--replace=config" and fp["cmd"].index(f"--config={cfg}") > fp["cmd"].index("--replace=config")
    assert [a for a in fp["cmd"] if a.startswith("--config=")][-1] == f"--config={cfg}"
    assert "--skip-menu" in fp["cmd"] and fp["env"]["SDL_VIDEODRIVER"] == "x11"
    data = run_dir / "fork-test/data"
    assert (data / "rlf_capture.omwscripts").is_file() and (data / "scripts/rlf_capture/global.lua").is_file()
    assert 'id = "a"' in (data / "scripts/rlf_capture/scenario.lua").read_text()
    op = capture.prepare(e, "official-ref", shots, run_dir)
    assert op["cmd"][:6] == ["flatpak", "run", "--nosocket=wayland", "--nosocket=fallback-x11", "--socket=x11",
                             "--env=SDL_VIDEODRIVER=x11"]
    confs = [a for a in op["cmd"] if a.startswith("--config=")]
    assert confs[0].endswith("OpenMW/config/openmw-ref") and confs[-1] == f"--config={run_dir / 'official-ref/cfg'}"
    assert any(a.startswith("--data-local=") for a in op["cmd"])
    assert json.loads((run_dir / "official-ref/plan.json").read_text())["target"] == "official"


class FakeProc:
    def __init__(self, log: Path, lines: list[str]):
        self.returncode = None
        self._t = threading.Thread(target=self._write, args=(log, lines), daemon=True)
        self._t.start()

    def _write(self, log, lines):
        for line in lines:
            time.sleep(0.1)
            with open(log, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        time.sleep(0.2)
        self.returncode = 0

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self._t.join(timeout)
        return 0

    def terminate(self):
        self.returncode = -15


def test_run_with_fake_engine(project, tmp_path):
    e = project["env"]
    shots = [capture.Shot("a", [0, 0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 0.0, 0.0),
             capture.Shot("b", [0, 0], [0.0, 0.0, 1.0], [0.0, 0.0, 0.0], 0.0, 0.0)]
    plan = capture.prepare(e, "fork-test", shots, tmp_path / "run")
    lines = ["[0 I] RLF_CAPTURE START 2", "[1 I] RLF_CAPTURE SHOT a", "[2 I] RLF_CAPTURE READY a",
             "[3 I] RLF_CAPTURE SHOT b", "[4 I] RLF_CAPTURE READY b", "[5 E] Lua error: test", "[6 I] RLF_CAPTURE DONE"]
    grabbed = []

    def grabber(window, shots_dir, dest):
        grabbed.append((window, dest.name))
        dest.write_bytes(b"png")
        return "engine-F12"

    res = capture.run(plan, timeout=10, popen=lambda *a, **k: FakeProc(Path(plan["log"]), lines),
                      grabber=grabber, window_finder=lambda: "0x123")
    assert res["status"] == "done" and [s["id"] for s in res["shots"]] == ["a", "b"]
    assert grabbed == [("0x123", "shot-a.png"), ("0x123", "shot-b.png")]
    assert any("Lua error" in x for x in res["errors"])
    assert json.loads((tmp_path / "run/fork-test/result.json").read_text())["status"] == "done"


def test_compare_images(tmp_path):
    PIL = pytest.importorskip("PIL.Image")
    a = PIL.new("RGB", (60, 30), (90, 90, 90))
    b = PIL.new("RGB", (60, 30), (90, 90, 90))
    for x in range(60):
        for y in range(10, 30):
            b.putpixel((x, y), (40, 120, 30))                  # zieleń w dolnej części
    a.save(tmp_path / "a.png")
    b.save(tmp_path / "b.png")
    r = capture.compare(tmp_path / "a.png", tmp_path / "b.png", tmp_path / "s.png")
    assert r["vegetation_ratio"]["official"] == 0.0 and r["vegetation_ratio"]["fork"] > 0.9
    assert (tmp_path / "s.png").is_file() and r["size"] == [60, 30]


def test_server_capture_plan(project, monkeypatch):
    import asyncio
    import inspect
    from openmw_mcp import server
    monkeypatch.setattr(server, "_ENV", project["env"])
    server._WORLD_CACHE.clear()
    lt = server.mcp.list_tools()
    names = {t.name for t in (asyncio.run(lt) if inspect.iscoroutine(lt) else lt)}
    assert {"openmw_capture_plan", "openmw_capture_start", "openmw_capture_status"} <= names
    r = server.openmw_capture_plan(["15,-9"])
    assert "error" not in r and set(r["commands"]) == {"official-ref", "fork-test"}
    assert r["shots"][0]["cell"] == [15, -9]
    st = server.openmw_capture_status(r["run_dir"])
    assert st["run_dir"] == r["run_dir"]
    # z mapą liczników (format pach76: wpis = teksel, nazwa, suma, grupy) — regresja 0.6.0-dev: pętla nadpisywała env
    counts = {"texture_names": ["t"], "cells": [{"cell": [15, -9], "land_hash": 0,
                                                 "entries": [(17, 0, 30, [(0, 0, 30)])]}]}
    monkeypatch.setattr(server, "_remiros_model", lambda *a, **k: (None, counts, None))
    r2 = server.openmw_capture_plan(["15,-9"], repeat=2, settle_seconds=12.0)
    assert "error" not in r2 and [s["id"] for s in r2["shots"]] == ["c15_-9", "c15_-9-r2"]


def test_repeat_shots_and_timing_override(tmp_path):
    from openmw_mcp import capture
    s = capture.Shot("c1_2", [1, 2], [0.0, 0.0, 100.0], [0.0, -250.0, 0.0], 0.0, -0.1)
    out = capture.repeat_shots([s], 3)
    assert [x.id for x in out] == ["c1_2", "c1_2-r2", "c1_2-r3"]
    assert out[2].camera == s.camera and out[0] is s
    lua = capture.scenario_lua(out, {**capture.DEFAULT_TIMING, "settleSeconds": 20.0})
    assert "settleSeconds = 20.0" in lua and "c1_2-r3" in lua
    import pytest
    with pytest.raises(ValueError):
        capture.repeat_shots([s], 9)


def test_viewpoint_avoids_terrain_occlusion(tmp_path):
    from openmw_mcp import capture

    class Ridge:
        """Płaski teren 100 z grzbietem 600 j. na południe od celu (w połowie drogi kamery z kursu 0)."""
        def height_at(self, x, y):
            return 900.0 if abs(x - 4096.0) < 120 and 3600 < y < 3800 else 100.0

    sh = capture.viewpoint(Ridge(), 0, 0, target=(4096.0, 4096.0), distance=700.0)
    assert capture._occlusion(Ridge(), 4096.0, 3396.0, 228.0, 4096.0, 4096.0, 130.0) > 0
    cx, cy, cz = sh.camera
    assert capture._occlusion(Ridge(), cx, cy, cz, 4096.0, 4096.0, 130.0) == 0
