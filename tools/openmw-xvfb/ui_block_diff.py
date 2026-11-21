#!/usr/bin/env python3
"""Różnice zawartości okien na zrzutach OpenMW i Godota (etap 10): w prostokącie okna obraz dzielony na bloki
B×B; dla każdego bloku – średnia jasność i gęstość krawędzi w obu silnikach. Bloki z dużą różnicą łączone w
prostokąty (składowe 4-spójne). Wynik: tylko liczby (prostokąty, różnice) – bez pikseli gry.

  python3 ui_block_diff.py OMW.png GODOT.png x0 y0 x1 y1 [--block 16]
"""
import argparse, json
import numpy as np
from PIL import Image

def load(p):
    return np.asarray(Image.open(p).convert("L"), dtype=np.float32)

def edges(a):
    gx = np.abs(np.diff(a, axis=1, prepend=a[:, :1]))
    gy = np.abs(np.diff(a, axis=0, prepend=a[:1, :]))
    return ((gx + gy) > 40).astype(np.float32)

ap = argparse.ArgumentParser()
ap.add_argument("omw"); ap.add_argument("godot"); ap.add_argument("rect", nargs=4, type=int)
ap.add_argument("--block", type=int, default=16)
a = ap.parse_args()
x0, y0, x1, y1 = a.rect
A, G = load(a.omw)[y0:y1, x0:x1], load(a.godot)[y0:y1, x0:x1]
EA, EG = edges(A), edges(G)
B = a.block
h, w = (A.shape[0] // B) * B, (A.shape[1] // B) * B
def blk(m):
    return m[:h, :w].reshape(h // B, B, w // B, B).mean(axis=(1, 3))
dl = np.abs(blk(A) - blk(G))
de = np.abs(blk(EA) - blk(EG))
bad = (dl > 25) | (de > 0.12)
lab = np.zeros(bad.shape, int); n = 0; boxes = []
for y in range(bad.shape[0]):
    for x in range(bad.shape[1]):
        if bad[y, x] and not lab[y, x]:
            n += 1; st = [(y, x)]; lab[y, x] = n; ys = [y]; xs = [x]
            while st:
                cy, cx = st.pop()
                for ny, nx in ((cy+1,cx),(cy-1,cx),(cy,cx+1),(cy,cx-1)):
                    if 0 <= ny < bad.shape[0] and 0 <= nx < bad.shape[1] and bad[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = n; st.append((ny, nx)); ys.append(ny); xs.append(nx)
            boxes.append([x0 + min(xs) * B, y0 + min(ys) * B, x0 + (max(xs) + 1) * B, y0 + (max(ys) + 1) * B, len(xs)])
boxes.sort(key=lambda b: -b[4])
print(json.dumps({"blocks": int(bad.size), "bad": int(bad.sum()), "share": round(float(bad.mean()), 3),
                  "edge_density": [round(float(EA.mean()), 3), round(float(EG.mean()), 3)],
                  "mean_luma": [round(float(A.mean()), 1), round(float(G.mean()), 1)], "regions": boxes[:12]}))
