"""Roślinność przeniesiona z forka OpenMW RLF: wtyczki groundcover oraz trawa Remirosa generowana BEZ jego ESP
(tabela reguł i liczników wkompilowana jak w forku; z moda tylko modele meshes/grass/)."""
import json
import shutil
from pathlib import Path

import numpy as np
import pytest

from mwconv import flora
from mwconv.install import InstallConfig
from mwconv.pipeline import Options, run
from mwconv.synthetic_world import write_flora


@pytest.fixture(scope="module")
def flora_dir(tmp_path_factory):
    d = tmp_path_factory.mktemp("flora") / "Flora"
    info = write_flora(d)
    # „Remiros bez ESP”: katalog z samymi modelami meshes/grass (jak paczka modeli i tekstur)
    m = d.parent / "RemirosModels"
    (m / "meshes" / "grass").mkdir(parents=True)
    for f in ("rem_sy_grass_01.nif", "rem_sy_grass_02.nif"):
        shutil.copy(d / "meshes" / "grass" / f, m / "meshes" / "grass" / f)
    info["models_only"] = str(m)
    return info


def synth_table(synth_dir, counts_cell=(0, 0)):
    """Mała tabela w formacie forka: reguła dla tx_synth_grass + liczniki dla jednej komórki."""
    from mwconv.world import load_world
    terrain = flora.Terrain(load_world([str(Path(synth_dir) / "mwg_synthtown.esm")]).lands)
    keys = terrain.texel_keys(*counts_cell)
    names = ["tx_synth_grass", "tx_synth_dirt"]
    entries, groups = [], []
    for ty in range(16):
        for tx in range(16):
            k = keys[ty][tx]
            if k not in names:
                continue
            gs = [(sub, sub % 2, 3) for sub in range(16)] if k == "tx_synth_grass" else []   # dirt: wycięcie autora
            entries.append((ty * 16 + tx) | (names.index(k) << 8) | (len(gs) << 16))
            groups += [sub | (st << 4) | (n << 12) for sub, st, n in gs]
    lh = terrain.land_hash(*counts_cell)
    return {"source_info": "synthetic test table", "spread_texels": 0.3, "underwater_max_height": -23.0,
            "retries": 4, "subdivisions": 4,
            "statics": [[0.7, "rem_sy_grass_01.nif", 0.9, 1.3, 23.0], [0.3, "rem_sy_grass_02.nif", 0.9, 1.3, 23.0],
                        [1.0, "brak_modelu.nif", 1.0, 1.0, 23.0]],
            "textures": [["tx_synth_grass", 6.0, 0, 2], ["tx_synth_stone", 4.0, 2, 1]],
            "texture_names": names, "cells": [[counts_cell[0], counts_cell[1], lh, 0, len(entries), 0]],
            "entries": entries, "groups": groups}, terrain


def _cfg(synth, data_dirs, groundcover=()):
    return InstallConfig(data_dirs=[str(synth["dir"]), *map(str, data_dirs)], archives=[str(synth["dir"] / "synth.bsa")],
                         content=[str(synth["dir"] / "mwg_synthtown.esm"), str(synth["dir"] / "mwg_synthtown_patch.esp")],
                         groundcover=list(groundcover))


def _all(out):
    idx = json.loads((out / "world" / "flora" / "index.json").read_text())
    rows = []
    for k, c in idx["cells"].items():
        r = flora.read_cell(out / "world" / "flora" / c["file"])
        for i in range(len(r["model"])):
            rows.append((k, idx["models"][r["model"][i]]["vfs"], r["x"][i], r["y"][i], r["z"][i], r["source"][i],
                         r["scale"][i] / 10000, r["rx"][i] / 10000, r["ry"][i] / 10000))
    return idx, rows


def test_settings_modes_like_fork():
    S = flora.Settings
    assert S().modes() == (False, False, 1.0)
    assert S(groundcover_enabled=True, groundcover_density=0.5).modes() == (True, False, 0.5)      # „legacy”
    assert S(enabled=True, source="automatic").modes()[:2] == (False, True)
    assert S(enabled=True, source="groundcover", density=0.5).modes() == (True, False, 0.5)
    assert S(enabled=True, source="hybrid").modes()[:2] == (True, True)
    assert S(density=9, exclusion_distance=-1).normalized().density == 2.0


def test_embedded_fork_table():
    t = flora.remiros_table()
    assert len(t.statics) == 102 and len(t.textures) == 39 and len(t.cells) == 715
    assert t.entries.size == 90210 and t.groups.size == 626204
    assert all(s[1].startswith("rem_") and s[1].endswith(".nif") for s in t.statics)
    assert flora.hash32(1) == int(flora.hash32_np(np.array([1], np.uint32))[0])


def test_plugin_groundcover_and_density(synth_data, flora_dir, tmp_path):
    out = tmp_path / "out"
    cfg = _cfg(synth_data, [flora_dir["dir"]], [flora_dir["groundcover"]])
    s = run(cfg, Options(out=out, cells=["Synthville"], jobs=1, flora={"groundcover_enabled": True}), log=lambda _m: None)
    assert s["flora"]["mode"] == "plugins" and s["flora"]["by_source"] == {"plugin": 60}
    idx, rows = _all(out)
    assert {r[1] for r in rows} == {"meshes/grass/synth_gc_01.nif"} and all(r[0] == "ext:0,0" for r in rows)
    assert (out / "meshes/grass/synth_gc_01.glb").exists()
    s = run(cfg, Options(out=tmp_path / "o2", cells=["Synthville"], jobs=1,
            flora={"groundcover_enabled": True, "groundcover_density": 0.5}), log=lambda _m: None)
    assert s["flora"]["by_source"]["plugin"] == 30                  # DensityCalculator: co druga referencja


def test_remiros_without_esp(synth_data, flora_dir, tmp_path, monkeypatch):
    table, terrain = synth_table(synth_data["dir"])
    monkeypatch.setattr(flora, "_TABLE", flora.RemirosTable(data=table))
    out = tmp_path / "out"
    cfg = _cfg(synth_data, [flora_dir["models_only"]])               # żadnego ESP Remirosa, tylko modele
    s = run(cfg, Options(out=out, cells=["Synthville"], jobs=1, flora={"enabled": True}), log=lambda _m: None)
    f = s["flora"]
    assert f["mode"] == "remiros" and set(f["by_source"]) == {"remiros"} and f["count_cell_matched" if False else
                                                                                "count_cells_matched"] == 1, f
    idx, rows = _all(out)
    assert {r[1] for r in rows} == {"meshes/grass/rem_sy_grass_01.nif", "meshes/grass/rem_sy_grass_02.nif"}
    assert (out / "meshes/grass/rem_sy_grass_01.glb").exists()
    # komórka z licznikami: dokładnie 3 rośliny na pole 128 j. trawy (16 pól × 3 = 48 na teksel trawy), ±próby pod wodą
    grass_texels = sum(1 for row in terrain.texel_keys(0, 0) for k in row if k == "tx_synth_grass")
    n00 = sum(1 for r in rows if r[0] == "ext:0,0")
    assert abs(n00 - grass_texels * 48) <= 5, (n00, grass_texels * 48)
    # liczniki: na tekselu „dirt” wycięcie autora (0 roślin) – reguła tekstury dirt nie istnieje, więc 0
    keys = [terrain.texture_key_at(r[2], r[3]) for r in rows if r[0] == "ext:0,0"]
    assert sum(k == "tx_synth_grass" for k in keys) / len(keys) > 0.97
    # komórki bez liczników: reguły tekstur (trawa 6/teksel, kamień 4/teksel z modelem → tylko statyki z modelem)
    other = [r for r in rows if r[0] != "ext:0,0"]
    assert other and {terrain.texture_key_at(r[2], r[3]) for r in other} >= {"tx_synth_grass"}
    for r in rows[::41]:
        assert abs(r[4] - terrain.height_at(r[2], r[3]) - 23) < 1.5 and 0.85 < r[6] < 1.35
    assert any(abs(r[7]) > 0.01 or abs(r[8]) > 0.01 for r in rows)   # obrót wg normalnej terenu
    # bez modeli Remirosa (synt. tabela, dołączone modele nie pasują do nazw) → brak trawy, bez wyjątku
    s2 = run(_cfg(synth_data, []), Options(out=tmp_path / "o3", cells=["Synthville"], jobs=1, flora={"enabled": True}),
             log=lambda _m: None)
    assert s2["flora"]["mode"] == "none" and s2["flora"]["instances"] == 0


def test_groundcover_plugin_detection(flora_dir, synth_data):
    assert flora.is_groundcover_plugin(flora_dir["groundcover"]) and flora.is_groundcover_plugin(flora_dir["remiros"])
    assert not flora.is_groundcover_plugin(synth_data["dir"] / "mwg_synthtown_patch.esp")


def test_bundled_remiros_assets():
    """Modele i tekstury Remirosa są dołączone do programu: każda statyka tabeli forka ma model, każdy model teksturę."""
    import re
    from mwconv.vfs import Vfs
    v = Vfs.from_install([str(flora.BUNDLED_GRASS)], [])
    models = flora.remiros_models(v)
    assert len(models) == 26 == len({s[1] for s in flora.remiros_table().statics})
    for m in models:
        for t in re.findall(rb"textures[\\/][\w\\/]+\.dds", v.read(m), re.I):
            assert v.exists(t.decode()), (m, t)
    credits = (flora.BUNDLED_GRASS / "CREDITS.md").read_text()
    assert "Remiros" in credits and "46733" in credits
