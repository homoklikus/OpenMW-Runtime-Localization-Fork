#!/usr/bin/env python3
"""Programowe porównanie geometrii okien na zrzutach OpenMW i Godota (etap 7).

Ramki okien Morrowinda (menu_thick_border, menu_thin_border, paski tytułu) mają złoto-brązowy kolor. Na każdym
zrzucie szukamy długich, prostych odcinków w tym kolorze (poziomych i pionowych, co najmniej MIN_RUN pikseli
przeskalowanych do rozdzielczości), łączymy je w składowe spójne i bierzemy ich prostokąty otaczające. Prostokąty
z obu silników są parowane zachłannie wg IoU; raport podaje różnice położenia i rozmiaru w pikselach i ułamkach
ekranu. Tło sceny (świece, gobeliny) nie tworzy długich prostych odcinków, więc nie zakłóca wyniku.

  python3 ui_geom_compare.py OMW.png GODOT.png [--json WYNIK.json] [--min-area 0.002]

Tylko liczby i prostokąty – żadnych pikseli gry w wyniku.
"""
import argparse
import json
import sys

import numpy as np
from PIL import Image


def frame_mask(img: np.ndarray) -> np.ndarray:
    r, g, b = (img[..., i].astype(np.int16) for i in range(3))
    return (r > 80) & (g > 55) & (r - b > 45) & (g - b > 20) & (r >= g) & (r - g < 70)


def runs_mask(m: np.ndarray, min_run: int) -> np.ndarray:
    """Piksele należące do poziomych lub pionowych odcinków maski o długości ≥ min_run."""
    out = np.zeros_like(m)
    for axis in (1, 0):
        a = m if axis == 1 else m.T
        o = out if axis == 1 else out.T
        for y in range(a.shape[0]):
            row = a[y]
            if not row.any():
                continue
            d = np.diff(np.concatenate(([0], row.view(np.int8), [0])))
            starts = np.flatnonzero(d == 1)
            ends = np.flatnonzero(d == -1)
            for s, e in zip(starts, ends):
                if e - s >= min_run:
                    o[y, s:e] = True
    return out


def components(m: np.ndarray, step: int = 4) -> list:
    """Prostokąty składowych spójnych (na siatce zmniejszonej step×, z dylatacją o 1 komórkę)."""
    h, w = m.shape
    gh, gw = (h + step - 1) // step, (w + step - 1) // step
    pad = np.zeros((gh * step, gw * step), bool)
    pad[:h, :w] = m
    g = pad.reshape(gh, step, gw, step).any(axis=(1, 3))
    lab = np.zeros(g.shape, np.int32)
    boxes = []
    n = 0
    for y0, x0 in zip(*np.nonzero(g)):
        if lab[y0, x0]:
            continue
        n += 1
        stack = [(y0, x0)]
        lab[y0, x0] = n
        ys, xs = [y0], [x0]
        while stack:
            y, x = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < gh and 0 <= xx < gw and g[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
                        ys.append(yy)
                        xs.append(xx)
        boxes.append([int(min(xs)) * step, int(min(ys)) * step, (int(max(xs)) + 1) * step, (int(max(ys)) + 1) * step])
    return boxes


def detect(path: str, min_area: float) -> tuple:
    img = np.asarray(Image.open(path).convert("RGB"))
    h, w = img.shape[:2]
    min_run = max(24, int(round(48 * h / 1080.0)))
    boxes = components(runs_mask(frame_mask(img), min_run))
    boxes = [b for b in boxes if (b[2] - b[0]) * (b[3] - b[1]) >= min_area * w * h]
    return boxes, (w, h)


def iou(a, b) -> float:
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    u = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / u if u else 0.0


def compare(omw: str, gd: str, min_area: float) -> dict:
    a, sa = detect(omw, min_area)
    b, sb = detect(gd, min_area)
    pairs = []
    used = set()
    for i, ba in sorted(enumerate(a), key=lambda t: -(t[1][2] - t[1][0]) * (t[1][3] - t[1][1])):
        best, bj = 0.0, -1
        for j, bb in enumerate(b):
            if j not in used and iou(ba, bb) > best:
                best, bj = iou(ba, bb), j
        if bj >= 0 and best > 0.3:
            used.add(bj)
            bb = b[bj]
            pairs.append({"omw": ba, "godot": bb, "iou": round(best, 3),
                          "dpos": [bb[0] - ba[0], bb[1] - ba[1]],
                          "dsize": [(bb[2] - bb[0]) - (ba[2] - ba[0]), (bb[3] - bb[1]) - (ba[3] - ba[1])]})
        else:
            pairs.append({"omw": ba, "godot": None, "iou": 0.0})
    extra = [bb for j, bb in enumerate(b) if j not in used]
    ious = [p["iou"] for p in pairs]
    return {"size_omw": sa, "size_godot": sb, "pairs": pairs, "godot_only": extra,
            "mean_iou": round(sum(ious) / len(ious), 3) if ious else None,
            "max_dpos": max((max(abs(v) for v in p["dpos"]) for p in pairs if p.get("dpos")), default=None),
            "max_dsize": max((max(abs(v) for v in p["dsize"]) for p in pairs if p.get("dsize")), default=None)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("omw")
    ap.add_argument("godot")
    ap.add_argument("--json")
    ap.add_argument("--min-area", type=float, default=0.002)
    a = ap.parse_args()
    r = compare(a.omw, a.godot, a.min_area)
    if a.json:
        with open(a.json, "w") as f:
            json.dump(r, f, indent=1)
    print("okna: OpenMW %d, Godot %d (pary %d), średnie IoU %s, maks. przesunięcie %s px, maks. różnica rozmiaru %s px"
          % (len(r["pairs"]), len(r["pairs"]) - sum(1 for p in r["pairs"] if p["godot"] is None) + len(r["godot_only"]),
             sum(1 for p in r["pairs"] if p["godot"] is not None), r["mean_iou"], r["max_dpos"], r["max_dsize"]))
    for p in r["pairs"]:
        print("  OMW %-24s Godot %-24s IoU %.3f" % (p["omw"], p["godot"], p["iou"]))
    for bb in r["godot_only"]:
        print("  tylko Godot %s" % bb)
    return 0


if __name__ == "__main__":
    sys.exit(main())
