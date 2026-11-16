"""Etap 2: modele aktorów w konwersji – szkielety, części ciała ras, głowy/włosy, animacje, ścieżki GLB w BODY."""
import json

import pytest

from mwconv.install import InstallConfig
from mwconv.pipeline import Options, run
from mwconv.synthetic_actor import write_actors
from mwconv.synthetic_world import write_world


@pytest.fixture(scope="module")
def actor_world(tmp_path_factory):
    d = tmp_path_factory.mktemp("actors") / "Data Files"
    d.mkdir()
    info = write_world(d)
    write_actors(d)
    return d


def test_actor_conversion(actor_world, tmp_path):
    d = actor_world
    cfg = InstallConfig(data_dirs=[str(d)], archives=[str(d / "synth.bsa")],
                        content=[str(d / "mwg_synthtown.esm"), str(d / "mwg_synthtown_patch.esp"), str(d / "mwg_actors.esp")])
    out = tmp_path / "out"
    s = run(cfg, Options(out=out, cells=["Synthville"], jobs=1), log=lambda _m: None)
    for glb in ("meshes/base_anim.glb", "meshes/base_anim_female.glb", "meshes/b/b_n_synth_m_skins.glb",
                "meshes/b/b_n_synth_f_chest.glb", "meshes/b/b_n_synth_m_forearm.glb",
                "meshes/b/b_n_synth_m_head_01.glb", "meshes/b/b_n_synth_m_hair_01.glb", "meshes/synth/test_skinned.glb"):
        assert (out / glb).exists(), glb
    anim = json.loads((out / "meshes/xbase_anim.anim.json").read_text())
    assert "idle" in anim["clips"] and {t["node"] for t in anim["tracks"]} >= {"Bip01 Spine", "Bip01 L UpperArm"}
    assert (out / "meshes/xbase_anim_female.anim.json").exists()
    idx = json.loads((out / "world/records/index.json").read_text())
    assert idx["actor"]["skeletons"] == {"male": "meshes/base_anim.glb", "female": "meshes/base_anim_female.glb"}
    assert idx["actor"]["anims"]["base"] == "meshes/xbase_anim.anim.json"
    body = json.loads((out / "world/records/bodypart.json").read_text())
    assert body["b_n_synth_m_hand"]["glb"] == "meshes/b/b_n_synth_m_skins.glb" and body["b_n_synth_f_chest"]["female"]
    npc = json.loads((out / "world/records/npc.json").read_text())
    assert npc["synth_villager_f"]["female"] and npc["synth_villager"]["head"] == "b_n_synth_m_head_01"
    cell = json.loads((out / "world/cells/ext/0_0.json").read_text())
    assert {r["sid"] for r in cell["refs"]} >= {"mwg_actors.esp#9001", "mwg_actors.esp#9002", "mwg_actors.esp#9003"}
