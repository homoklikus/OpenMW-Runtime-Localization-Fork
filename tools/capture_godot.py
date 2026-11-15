#!/usr/bin/env python3
"""Zrzuty porównawcze OpenMWGodot dla ujęć MCP-openMW (profil „openmwgodot”, rodzaj „external”).

Wejście: shots.json z MCP (lista ujęć: id, camera [x,y,z] w jednostkach MW, yaw/pitch w konwencji Lua OpenMW:
yaw = kurs (0 = +Y), pitch > 0 = w dół, hour, weather). Dla każdego ujęcia uruchamia grę w trybie zrzutu
(main.gd: --camera/--look/--hour/--weather/--fov/--screenshot) i zapisuje <out>/shot-<id>.png oraz
<out>/result.json: {"shots": [{"id", "file", "method"}], "errors": [...]} – format oczekiwany przez MCP.

Bez zależności poza biblioteką standardową; procesy uruchamiane z listą argumentów (bez powłoki).
Zrzuty z prawdziwych danych zostają lokalnie (katalog --out), nigdy w repozytorium.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

SETTINGS = {"window_mode": "windowed", "resolution": "1920x1080", "vsync": True, "scale_3d": 1.0,
            "shadows": "medium", "load_radius": 1, "view_distance": 1500, "water": True, "grass": True,
            "grass_distance": 90, "grass_density": 1.0}


def godot_args(shot: dict, a, settings: Path, out: Path) -> list[str]:
    cam = ",".join(f"{float(v):.2f}" for v in shot["camera"])
    w = (shot.get("weather") or "clear").lower()
    args = [a.godot, "--path", a.project, "--", f"--data={a.data}", f"--settings={settings}",
            f"--camera={cam}", f"--look={float(shot['yaw']):.5f},{float(shot['pitch']):.5f}",
            f"--hour={float(shot.get('hour', 12.0))}", f"--weather={w}", f"--fov={a.fov}",
            f"--screenshot={out / ('shot-' + shot['id'] + '.png')}", f"--shot-frames={a.frames}", "--quit=1"]
    if a.base:
        args.insert(args.index("--") + 1, f"--base={a.base}")
    return args


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--shots", required=True, help="shots.json z MCP-openMW")
    p.add_argument("--out", required=True, help="katalog wyników profilu")
    p.add_argument("--godot", required=True)
    p.add_argument("--project", required=True, help="katalog projektu Godota (godot/)")
    p.add_argument("--data", required=True, help="katalog przekonwertowanych danych (np. MorrowindGoDot/base)")
    p.add_argument("--base", default="", help="opcjonalny katalog bazy (profil z modami)")
    p.add_argument("--fov", default="60", help="pionowe pole widzenia (OpenMW: 60)")
    p.add_argument("--frames", default="240", help="klatki przed zrzutem")
    p.add_argument("--timeout", type=float, default=180.0, help="limit na jedno ujęcie [s]")
    a = p.parse_args(argv)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    shots = json.loads(Path(a.shots).read_text(encoding="utf-8"))
    shots = shots.get("shots", shots) if isinstance(shots, dict) else shots
    settings = out / "settings.json"
    settings.write_text(json.dumps(SETTINGS), encoding="utf-8")
    results, errors = [], []
    log = open(out / "stdout.log", "w", encoding="utf-8")
    progress = out / "progress.json"
    for i, shot in enumerate(shots):
        progress.write_text(json.dumps({"shot": shot["id"], "index": i, "total": len(shots)}), encoding="utf-8")
        dest = out / f"shot-{shot['id']}.png"
        dest.unlink(missing_ok=True)
        cmd = godot_args(shot, a, settings, out)
        log.write("$ " + " ".join(cmd) + "\n")
        log.flush()
        t0 = time.time()
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout)
            log.write(r.stdout + r.stderr)
            if r.returncode != 0:
                errors.append(f"{shot['id']}: kod wyjścia {r.returncode}")
            errors += [f"{shot['id']}: {l.strip()}" for l in (r.stdout + r.stderr).splitlines()
                       if "SCRIPT ERROR" in l or "MWGODOT_ERROR" in l][:5]
        except subprocess.TimeoutExpired:
            errors.append(f"{shot['id']}: przekroczony czas {a.timeout:.0f} s")
        except OSError as e:
            errors.append(f"{shot['id']}: nie można uruchomić Godota: {e}")
        results.append({"id": shot["id"], "file": str(dest) if dest.is_file() else None,
                        "method": "godot-viewport" if dest.is_file() else "failed",
                        "seconds": round(time.time() - t0, 1)})
    log.close()
    (out / "result.json").write_text(json.dumps({"shots": results, "errors": errors[:40]}, ensure_ascii=False,
                                                indent=1), encoding="utf-8")
    progress.write_text(json.dumps({"done": True, "total": len(shots)}), encoding="utf-8")
    return 0 if all(r["file"] for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
