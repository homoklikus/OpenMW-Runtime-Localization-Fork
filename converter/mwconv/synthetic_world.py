"""Syntetyczny świat testowy „Synthville” (2×2 komórki zewnętrzne + wnętrze) – NIE jest to Balmora.

Pliki:
  mwg_synthtown.esm        – master: LTEX, obiekty, komórki (0,0)…(1,1), teren, wnętrze, drzwi
  mwg_synthtown_patch.esp  – plugin: przesuwa/obraca referencję mastera, usuwa referencję, dodaje nową,
                             przenosi referencję do innej komórki (MVRF/CNDT), podmienia teren jednej komórki
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from .esm import writer as W
from .synthetic import write_assets

GRIDS = [(0, 0), (1, 0), (0, 1), (1, 1)]
CELL = 8192


def height_at(x: float, y: float) -> float:
    """Wysokość terenu (jednostki gry) – łagodne wzgórza + dolina rzeki wzdłuż y ≈ 6000."""
    h = 600 + 350 * math.sin(x / 2600.0) * math.cos(y / 3100.0) + 0.04 * x
    h -= 500 * math.exp(-((y - 6000) / 900.0) ** 2)
    return round(h / 8) * 8


def heights_for(grid, bump: float = 0.0) -> np.ndarray:
    gx, gy = grid
    h = np.zeros((65, 65))
    for j in range(65):
        for i in range(65):
            x = gx * CELL + i * 128
            y = gy * CELL + j * 128
            h[j, i] = height_at(x, y)
            if bump:
                # centralny pagórek tylko wewnątrz komórki (krawędzie bez zmian ⇒ brak szczelin)
                d = math.hypot(i - 32, j - 32)
                h[j, i] += round(bump * max(0.0, 1 - d / 20.0) ** 2 / 8) * 8
    return h


def vtex_for(grid) -> np.ndarray:
    gx, gy = grid
    v = np.zeros((16, 16), np.uint16)
    for j in range(16):
        for i in range(16):
            x = gx * CELL + (i + 0.5) * 512
            y = gy * CELL + (j + 0.5) * 512
            h = height_at(x, y)
            if abs(y - 6000) < 700:
                v[j, i] = 2  # dirt (LTEX 1)
            elif h > 900:
                v[j, i] = 3  # stone (LTEX 2)
            else:
                v[j, i] = 1  # grass (LTEX 0)
    v[0, 0] = 0  # jedna komórka z teksturą domyślną (test indeksu 0)
    return v


def colors_for(grid) -> np.ndarray:
    c = np.full((65, 65, 3), 255, np.uint8)
    c[:, :, 2] = np.linspace(200, 255, 65, dtype=np.uint8)[None, :]
    return c


def write_world(data_dir: Path) -> dict:
    data_dir = Path(data_dir)
    write_assets(data_dir)
    from .synthetic_hard import write_hard
    write_hard(data_dir)
    recs = []
    recs.append(W.region("Synthetic Region", "Kraina Syntetyczna", {"clear": 50, "cloudy": 30, "foggy": 10, "rain": 10}))
    recs.append(W.ltex("synth_grass", 0, "tx_synth_grass.tga"))
    recs.append(W.ltex("synth_dirt", 1, "tx_synth_dirt.tga"))
    recs.append(W.ltex("synth_stone", 2, "tx_synth_stone.tga"))
    recs.append(W.stat("synth_hut", "synth\\test_hut.nif"))
    recs.append(W.stat("synth_crate", "synth\\test_crate.nif", "MISC", "Skrzynka testowa"))
    recs.append(W.stat("synth_windmill", "synth\\test_windmill.nif", "ACTI", "Wiatrak testowy"))
    recs.append(W.stat("synth_tube", "synth\\test_skinned.nif", "ACTI", "Rura (skin)"))
    recs.append(W.stat("synth_bsa_crate", "synth\\bsa_crate.nif"))
    recs.append(W.stat("synth_door", "synth\\test_crate.nif", "DOOR", "Drzwi testowe"))
    recs.append(W.light("synth_lamp", None, 512, (255, 190, 120)))
    recs.append(W.stat("synth_hard_nodes", "synth\\hard_nodes.nif"))
    recs.append(W.stat("synth_hard_ctrl", "synth\\hard_controllers.nif", "ACTI"))
    recs.append(W.stat("synth_fire", "synth\\hard_particles.nif", "ACTI"))

    refnum = [0]

    def nref(base, x, y, zoff=0.0, rz_deg=0.0, scale=1.0, extra=None, z=None):
        refnum[0] += 1
        zz = height_at(x, y) + zoff if z is None else z
        return refnum[0], W.ref_subs(refnum[0], base, (x, y, zz), (0, 0, math.radians(rz_deg)), scale, extra=extra)

    cell_refs = {g: [] for g in GRIDS}
    layout = {}
    # chaty wzdłuż „ulicy” (oś X) po północnej stronie rzeki
    for k in range(6):
        x = 1200 + k * 2300
        y = 8600 + (k % 2) * 700
        g = (int(x // CELL), int(y // CELL))
        rn, r = nref("synth_hut", x, y, rz_deg=15 * k, scale=1.0 + 0.1 * (k % 3))
        cell_refs[g].append(r)
        layout[f"hut{k}"] = rn
    # skrzynki
    for k in range(8):
        x = 900 + k * 1700
        y = 3000 + (k % 3) * 400
        g = (int(x // CELL), int(y // CELL))
        rn, r = nref("synth_crate", x, y, rz_deg=37 * k)
        cell_refs[g].append(r)
        layout[f"crate{k}"] = rn
    rn, r = nref("synth_windmill", 12000, 12500)
    cell_refs[(1, 1)].append(r)
    layout["windmill"] = rn
    rn, r = nref("synth_tube", 5000, 9900, rz_deg=0)
    cell_refs[(0, 1)].append(r)
    layout["tube"] = rn
    rn, r = nref("synth_bsa_crate", 3000, 1500)
    cell_refs[(0, 0)].append(r)
    layout["bsa_crate"] = rn
    rn, r = nref("synth_lamp", 1500, 9300, zoff=200)
    cell_refs[(0, 1)].append(r)
    layout["lamp"] = rn
    rn, r = nref("synth_door", 1200, 8400, extra={"door_dest": {"pos": [0, -300, 0], "rot": [0, 0, 0]},
                                                    "door_dest_cell": "Synthville, Test House"})
    cell_refs[(0, 1)].append(r)
    layout["door"] = rn

    for g in GRIDS:
        recs.append(W.cell("Synthville", g, False, cell_refs[g], region="Synthetic Region"))
        recs.append(W.land(g, heights_for(g), vtex_for(g), colors_for(g)))

    # wnętrze
    irefs = []
    for k in range(3):
        refnum[0] += 1
        irefs.append(W.ref_subs(refnum[0], "synth_crate", (k * 100 - 100, 0, 0), (0, 0, math.radians(20 * k))))
    refnum[0] += 1
    irefs.append(W.ref_subs(refnum[0], "synth_lamp", (0, 0, 180)))
    for k, base in enumerate(("synth_hard_nodes", "synth_hard_ctrl", "synth_fire")):
        refnum[0] += 1
        irefs.append(W.ref_subs(refnum[0], base, (-600 + 600 * k, 600, 0)))
    # drzwi wyjściowe na ulicę (cel bez nazwy komórki = świat zewnętrzny) – punkt startu gry „w mieście”
    refnum[0] += 1
    irefs.append(W.ref_subs(refnum[0], "synth_door", (0, -700, 0), (0, 0, 0),
                            extra={"door_dest": {"pos": [1200, 8150, height_at(1200, 8150)], "rot": [0, 0, math.pi]}}))
    recs.append(W.cell("Synthville, Test House", (0, 0), True, irefs, water=-1000.0,
                       ambient=(0x00404040, 0x00808080, 0x00202020, 0.5)))

    esm = W.header([], len(recs), desc="Synthetic test world (not Bethesda data)") + b"".join(recs)
    esm_path = data_dir / "mwg_synthtown.esm"
    esm_path.write_bytes(esm)

    # plugin
    prec = []
    hut0 = layout["hut0"]
    crate2 = layout["crate2"]
    crate5 = layout["crate5"]
    g_hut0 = (0, 1)
    master_ix = 1 << 24
    moved = W.ref_subs(master_ix | hut0, "synth_hut", (1400, 8600, height_at(1400, 8600)), (0, 0, math.radians(90)), 1.2)
    deleted = W.ref_subs(master_ix | crate2, "synth_crate", (0, 0, 0), deleted=True)
    added = W.ref_subs(1, "synth_windmill", (2500, 12000, height_at(2500, 12000)))
    # przeniesienie skrzynki 5 (x = 9400 → komórka (1,0)) do komórki (1,1)
    mv = [(master_ix | crate5, (1, 1), W.ref_subs(master_ix | crate5, "synth_crate", (9600, 12500, height_at(9600, 12500))))]
    g_crate2 = (int((900 + 2 * 1700) // CELL), 0)
    prec.append(W.stat("synth_crate", "synth\\test_crate.nif", "MISC", "Skrzynka (zmieniona przez plugin)"))
    prec.append(W.cell("Synthville", g_hut0, False, [moved, added]))
    prec.append(W.cell("Synthville", g_crate2, False, [deleted]))
    prec.append(W.cell("Synthville", (1, 0), False, [], moved=mv))
    prec.append(W.land((1, 1), heights_for((1, 1), bump=400), vtex_for((1, 1)), colors_for((1, 1))))
    esp = W.header([("mwg_synthtown.esm", len(esm))], len(prec), desc="Synthetic patch", is_master=False) + b"".join(prec)
    esp_path = data_dir / "mwg_synthtown_patch.esp"
    esp_path.write_bytes(esp)
    return {"esm": str(esm_path), "esp": str(esp_path), "layout": layout}


def write_patch2(data_dir: Path) -> str:
    """Druga „aktualizacja modów”: przesuwa chatę #2 i dodaje skrzynkę w komórce (0,1).
    Służy do testu ponownego importu z zachowaniem nadpisań projektu CS 2.0."""
    data_dir = Path(data_dir)
    esm_size = (data_dir / "mwg_synthtown.esm").stat().st_size
    refs = [W.ref_subs((1 << 24) | 2, "synth_hut", (3600, 9300, height_at(3600, 9300))),
            W.ref_subs(1, "synth_crate", (2000, 9000, height_at(2000, 9000)))]
    recs = [W.cell("Synthville", (0, 1), False, refs)]
    p = data_dir / "mwg_synthtown_patch2.esp"
    p.write_bytes(W.header([("mwg_synthtown.esm", esm_size)], len(recs), desc="Synthetic patch 2", is_master=False)
                  + b"".join(recs))
    return str(p)
