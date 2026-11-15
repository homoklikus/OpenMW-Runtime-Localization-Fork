"""tools/capture_godot.py – zrzuty OpenMWGodot dla ujęć MCP-openMW (atrapa Godota zamiast gry)."""
import json
import subprocess
import sys
from pathlib import Path

TOOL = Path(__file__).resolve().parents[2] / "tools" / "capture_godot.py"

FAKE = r'''#!/usr/bin/env python3
import sys, json
args = sys.argv[1:]
user = args[args.index("--") + 1:]
kv = dict(a[2:].split("=", 1) for a in user if a.startswith("--") and "=" in a)
open(kv["screenshot"].replace(".png", ".args.json"), "w").write(json.dumps(kv))
if "bad" not in kv["screenshot"]:
    open(kv["screenshot"], "wb").write(b"\x89PNG\r\n\x1a\nfake")
'''


def test_capture_godot_runs_each_shot(tmp_path):
    fake = tmp_path / "godot"
    fake.write_text(FAKE)
    fake.chmod(0o755)
    shots = [{"id": "c-2_-2", "camera": [-9206.2, -11273.8, 710.2], "yaw": 5.49779, "pitch": 0.08, "hour": 12.0,
              "weather": "Clear"},
             {"id": "bad", "camera": [0, 0, 0], "yaw": 0, "pitch": 0}]
    (tmp_path / "shots.json").write_text(json.dumps({"shots": shots}))
    out = tmp_path / "out"
    r = subprocess.run([sys.executable, str(TOOL), "--shots", str(tmp_path / "shots.json"), "--out", str(out),
                        "--godot", str(fake), "--project", "/p", "--data", "/d"], capture_output=True, text=True)
    assert r.returncode == 1, r.stderr                       # drugie ujęcie bez pliku
    res = json.loads((out / "result.json").read_text())
    assert [s["id"] for s in res["shots"]] == ["c-2_-2", "bad"]
    assert res["shots"][0]["file"].endswith("shot-c-2_-2.png") and res["shots"][1]["file"] is None
    kv = json.loads((out / "shot-c-2_-2.args.json").read_text())
    assert kv["camera"] == "-9206.20,-11273.80,710.20" and kv["look"] == "5.49779,0.08000"
    assert kv["weather"] == "clear" and kv["fov"] == "60" and kv["data"] == "/d" and kv["quit"] == "1"
    assert json.loads(Path(kv["settings"]).read_text())["resolution"] == "1920x1080"
