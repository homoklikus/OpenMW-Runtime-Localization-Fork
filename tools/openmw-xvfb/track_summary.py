"""Podsumowanie próbek położenia (track) przypadków porównawczych: prędkość pozioma między dwiema chwilami,
największa wysokość i położenie końcowe dla OpenMW i Godota (przebieg z efektem i bazowy).
Użycie: python3 track_summary.py KATALOG_WYNIKÓW PRZYPADEK [t0 t1]"""
import json
import math
import sys
from pathlib import Path


def summary(track, t0, t1):
    pts = {round(p[0], 3): p for p in track}
    a = min(pts.values(), key=lambda p: abs(p[0] - t0))
    b = min(pts.values(), key=lambda p: abs(p[0] - t1))
    dt = max(b[0] - a[0], 1e-6)
    v = math.hypot(b[1] - a[1], b[2] - a[2]) / dt
    return {"v_xy": round(v, 1), "z_max": round(max(p[3] for p in track), 1), "end": [round(x) for x in track[-1][1:]]}


def main(argv):
    out, case = Path(argv[0]), argv[1]
    t0 = float(argv[2]) if len(argv) > 2 else 1.0
    t1 = float(argv[3]) if len(argv) > 3 else 2.5
    for n in ["omw", "base.omw", "gd", "base.gd"]:
        f = out / f"{case}.{n}.json"
        if not f.exists():
            print(f"{n:9} brak")
            continue
        tr = json.loads(f.read_text()).get("track", {}).get("player", [])
        print(f"{n:9}", summary(tr, t0, t1) if tr else "brak próbek")


if __name__ == "__main__":
    main(sys.argv[1:])
