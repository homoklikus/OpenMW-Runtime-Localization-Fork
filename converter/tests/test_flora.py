"""Roślinność przeniesiona z forka OpenMW RLF: wtyczki groundcover, flora proceduralna, reguły Remirosa."""
import json
import math
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
    return write_flora(d)


def _cfg(synth, fl, with_remiros=True, groundcover=True):
    d = Path(fl["dir"])
    if not with_remiros:
        d2 = d.parent / "FloraNoRem"
        if not d2.exists():
            shutil.copytree(d, d2)
            (d2 / "Rem_SY.esp").unlink()
        d = d2
    return InstallConfig(data_dirs=[str(synth["dir"]), str(d)], archives=[str(synth["dir"] / "synth.bsa")],
                         content=[str(synth["dir"] / "mwg_synthtown.esm"), str(synth["dir"] / "mwg_synthtown_patch.esp")],
                         groundcover=[str(d / "mwg_grass.esp")] if groundcover else [])


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


def test_helpers_match_fork():
    assert flora.surface_weight("tx_ai_grass_dirt_01") == 0.5 and flora.surface_weight("tx_rock_01") == 0.0
    assert flora.surface_weight("tx_bc_mud_01") == 0.55 and flora.surface_weight("_land_default") == 0.0
    assert flora.uses_pathgrid_exclusion("tx_road_01") and not flora.uses_pathgrid_exclusion("tx_gl_dirt_grass_01")
    assert flora.region_family("tx_bc_mud_01") == "bc" and flora.region_family("tx_rm_ash_01") == "ash"
    assert flora.hash32(1) == int(flora.hash32_np(np.array([1], np.uint32))[0])
    assert flora.texture_key("Textures\\Tx_BC_Mud_01.DDS") == "tx_bc_mud_01"


def test_plugin_groundcover_and_density(synth_data, flora_dir, tmp_path):
    out = tmp_path / "out"
    s = run(_cfg(synth_data, flora_dir), Options(out=out, cells=["Synthville"], jobs=1,
            flora={"groundcover_enabled": True}), log=lambda _m: None)
    assert s["flora"]["mode"] == "plugins" and s["flora"]["by_source"] == {"plugin": 60}
    idx, rows = _all(out)
    assert {r[1] for r in rows} == {"meshes/grass/synth_gc_01.nif"} and all(r[0] == "ext:0,0" for r in rows)
    assert (out / "meshes/grass/synth_gc_01.glb").exists()          # model skonwertowany na potrzeby roślinności
    out2 = tmp_path / "out2"
    s = run(_cfg(synth_data, flora_dir), Options(out=out2, cells=["Synthville"], jobs=1,
            flora={"groundcover_enabled": True, "groundcover_density": 0.5}), log=lambda _m: None)
    assert s["flora"]["by_source"]["plugin"] == 30                  # DensityCalculator: co druga referencja


def test_procedural_generic(synth_data, flora_dir, tmp_path):
    out = tmp_path / "out"
    cfg = _cfg(synth_data, flora_dir, with_remiros=False, groundcover=False)
    s = run(cfg, Options(out=out, cells=["Synthville"], jobs=1, flora={"enabled": True, "density": 0.25}),
            log=lambda _m: None)
    f = s["flora"]
    assert f["mode"] == "generic" and f["instances"] > 1000, f
    idx, rows = _all(out)
    models = {r[1] for r in rows}
    assert "meshes/f/flora_grass_05.nif" not in models               # > 200 j. – odrzucony jak w forku
    assert models <= {"meshes/f/flora_grass_01.nif", "meshes/f/flora_bc_grass_01.nif"}
    from mwconv.world import load_world
    terrain = flora.Terrain(load_world(cfg.content).lands)
    for _k, _m, x, y, z, src, *_ in rows[::97]:
        key = terrain.texture_key_at(x, y)
        assert flora.surface_weight(key) > 0, key                    # nigdy na kamieniu/drodze/domyślnej
        assert abs(z - terrain.height_at(x, y)) < 1.0                # na terenie (diament)
        sl = terrain.slope_np(np.array([x]), np.array([y]))[0]
        assert np.isnan(sl) or sl <= flora.MAX_SLOPE + 1e-6     # NaN: brzeg świata (brak sąsiedniego LAND)
    # wykluczenie przy obiektach: żadna roślina w promieniu chaty (synth_hut) + 3 m
    world = load_world(cfg.content)
    huts = [mr.ref.pos for k, mc in world.cells.items() for mr in mc.refs.values() if mr.ref.base.lower() == "synth_hut"]
    for hx, hy, _hz in huts:
        near = [r for r in rows if math.hypot(r[2] - hx, r[3] - hy) < 150]
        assert not near, (hx, hy, len(near))
    # ponownie bez zmian → pominięte; gęstość 2× → ok. 2× więcej roślin
    s2 = run(cfg, Options(out=out, cells=["Synthville"], jobs=1, flora={"enabled": True, "density": 0.25}),
             log=lambda _m: None)
    assert s2.get("flora", {}).get("skipped") or s2["world_load"].get("skipped")
    s3 = run(cfg, Options(out=out, cells=["Synthville"], jobs=1, flora={"enabled": True, "density": 0.5}),
             log=lambda _m: None)
    assert 1.6 < s3["flora"]["instances"] / f["instances"] < 2.4


def test_remiros_rules_from_local_plugins(synth_data, flora_dir, tmp_path):
    out = tmp_path / "out"
    s = run(_cfg(synth_data, flora_dir, groundcover=False), Options(out=out, cells=["Synthville"], jobs=1,
            flora={"enabled": True}), log=lambda _m: None)
    f = s["flora"]
    assert f["mode"] == "remiros" and set(f["by_source"]) == {"remiros"}, f
    idx, rows = _all(out)
    assert {r[1] for r in rows} == {"meshes/grass/rem_sy_grass_01.nif", "meshes/grass/rem_sy_grass_02.nif"}
    from mwconv.world import load_world
    terrain = flora.Terrain(load_world(_cfg(synth_data, flora_dir).content).lands)
    # komórki z licznikami (0,0),(1,0): ok. tyle roślin, ile autor; tylko na trawie; z = teren + 23
    n00 = sum(1 for r in rows if r[0] == "ext:0,0")
    src = flora.GroundcoverIndex.load([flora_dir["remiros"]])
    author = len(src.instances(0, 0))
    assert abs(n00 - author) <= max(3, author * 0.02), (n00, author)
    keys = [terrain.texture_key_at(r[2], r[3]) for r in rows]
    on_grass = sum(k in ("tx_synth_grass", "_land_default") for k in keys) / len(keys)
    assert on_grass > 0.85, on_grass          # reszta ≤ 0,3 teksela od krawędzi (jak u autora moda)
    for r in rows[::53]:
        h = terrain.height_at(r[2], r[3])
        assert abs(r[4] - h - 23) < 1.5
        assert 0.85 < r[6] < 1.35                                    # skala z zakresu statyki
    # komórki bez licznika (0,1),(1,1): reguły tekstur – też rośliny (tylko na trawie)
    assert any(r[0] in ("ext:0,1", "ext:1,1") for r in rows)
    # obrót wg normalnej terenu (rx/ry niezerowe na zboczach)
    assert any(abs(r[7]) > 0.01 or abs(r[8]) > 0.01 for r in rows)


def test_groundcover_plugin_detection(flora_dir, synth_data):
    assert flora.is_groundcover_plugin(flora_dir["groundcover"]) and flora.is_groundcover_plugin(flora_dir["remiros"])
    assert not flora.is_groundcover_plugin(synth_data["dir"] / "mwg_synthtown_patch.esp")
