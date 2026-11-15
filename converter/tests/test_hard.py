"""Trudne przypadki NIF, uszkodzone pliki, kontrolery, cząsteczki, morfy, .kf, skan."""

import json

import numpy as np
import pytest

from mwconv.gltf import accessor_array, read_glb
from mwconv.kf2anim import convert_kf, parse_text_keys
from mwconv.nif.reader import NifError, parse
from mwconv.nif2gltf import NifToGltf, TextureRef
from mwconv.synthetic_hard import HARD_MODELS, corrupt_variants


def conv(key):
    nif = parse(HARD_MODELS[key](), key)
    glb, rep = NifToGltf(nif, key, lambda n: None if "missing" in n else TextureRef("../textures/" + n.lower(), source_path=n)).convert()
    doc, binc = read_glb(glb)
    return nif, doc, binc, rep


def node(doc, name):
    for n in doc["nodes"]:
        if n.get("extras", {}).get("mw_name") == name:
            return n
    raise KeyError(name)


@pytest.mark.parametrize("key", sorted(HARD_MODELS))
def test_hard_parse_byte_exact(key):
    nif = parse(HARD_MODELS[key](), key)
    assert nif.trailing == 0


@pytest.mark.parametrize("name,data", sorted(corrupt_variants().items()))
def test_corrupt_files_give_nif_error(name, data):
    with pytest.raises(NifError) as ei:
        parse(data, name)
    assert name in str(ei.value)


def test_corrupt_diagnostics_location():
    data = corrupt_variants()["corrupt_truncated.nif"]
    with pytest.raises(NifError) as ei:
        parse(data, "t.nif")
    e = ei.value
    assert e.block_type == "NiTriShapeData" and e.block_index is not None and e.offset > e.block_start
    assert len(e.partial) == e.block_index


def test_hard_nodes_conversion():
    nif, doc, binc, rep = conv("meshes/synth/hard_nodes.nif")
    assert node(doc, "Switch")["extras"]["mw_switch_initial"] == 1
    assert node(doc, "tri switch0")["extras"].get("mw_hidden") is True
    assert len(node(doc, "LOD")["extras"]["mw_lod_levels"]) == 2
    assert node(doc, "Billboard")["extras"]["mw_billboard"] is True
    assert "matrix" in node(doc, "Shear")
    # tekstura wewnętrzna osadzona, dwa zestawy UV
    assert any("bufferView" in im for im in doc["images"])
    m = node(doc, "tri multitex")
    prim = doc["meshes"][m["mesh"]]["primitives"][0]
    assert "TEXCOORD_1" in prim["attributes"]
    mat = doc["materials"][prim["material"]]
    assert set(mat["extras"]["mw_extra_textures"]) >= {"dark", "detail", "gloss"}
    assert "emissiveTexture" in mat
    # mieszanie addytywne opisane w extras
    bb = node(doc, "tri billboard")
    bm = doc["materials"][doc["meshes"][bb["mesh"]]["primitives"][0]["material"]]
    assert bm["extras"]["mw_blend_mode"] == "SRC_ALPHA/ONE"
    assert "tx_missing_texture.tga" in rep.missing_textures
    assert any("indeksem poza zakresem" in x for x in rep.lossy)


def test_controllers_to_extras_and_channels():
    nif, doc, binc, rep = conv("meshes/synth/hard_controllers.nif")
    assert rep.unsupported == []
    vis = node(doc, "VisNode")["extras"]["mw_controllers"][0]
    assert vis["type"] == "vis" and vis["values"] == [1, 0, 1]
    uv = node(doc, "tri uvscroll")["extras"]["mw_controllers"][0]
    assert uv["type"] == "uv" and uv["u_offset"]["values"][-1] == [1.0]
    mats = [m for m in doc["materials"] if "mw_mat_controllers" in m.get("extras", {})]
    types = {c["type"] for m in mats for c in m["extras"]["mw_mat_controllers"]}
    assert types == {"alpha", "color", "flip"}
    flip = [c for m in mats for c in m["extras"]["mw_mat_controllers"] if c["type"] == "flip"][0]
    assert len(flip["textures"]) == 3 and flip["delta"] == pytest.approx(0.25)
    # morfy → targets + kanał weights
    mn = node(doc, "tri morph")
    mesh = doc["meshes"][mn["mesh"]]
    assert len(mesh["primitives"][0]["targets"]) == 1 and mesh["weights"] == [0.0]
    anim = doc["animations"][0]
    paths = {c["target"]["path"] for c in anim["channels"]}
    assert {"weights", "translation", "rotation"} <= paths
    # częstotliwość 2 skraca oś czasu XYZ o połowę
    xyz = doc["nodes"].index(node(doc, "XYZNode"))
    ch = [c for c in anim["channels"] if c["target"]["node"] == xyz and c["target"]["path"] == "rotation"][0]
    t = accessor_array(doc, binc, anim["samplers"][ch["sampler"]]["input"])
    assert t[-1] == pytest.approx(0.5)


def test_particles_extras():
    nif, doc, binc, rep = conv("meshes/synth/hard_particles.nif")
    p = node(doc, "Particles")["extras"]["mw_particles"]
    assert p["emitter"] == "Emitter" and p["blend"] == "add"
    assert p["lifetime"] == pytest.approx(1.5) and p["emit_rate"] == pytest.approx(12.0)
    assert p["color_keys"]["values"][-1][3] == pytest.approx(0.0)
    kinds = {m["type"] for m in p["modifiers"]}
    assert {"gravity", "growfade", "color", "rotation"} <= kinds
    assert node(doc, "RotParticles")["extras"]["mw_particles"]["amount"] == 3


def test_skin_more_than_four_influences():
    nif, doc, binc, rep = conv("meshes/synth/hard_skin5.nif")
    n = node(doc, "tri skin5")
    w = accessor_array(doc, binc, doc["meshes"][n["mesh"]]["primitives"][0]["attributes"]["WEIGHTS_0"])
    assert np.allclose(w.sum(axis=1), 1.0, atol=1e-6)
    assert any(">4 wpływami" in x for x in rep.lossy)


def test_kf_conversion_and_clips():
    nif = parse(HARD_MODELS["meshes/synth/xtest_skinned.kf"](), "x.kf")
    doc, rep = convert_kf(nif, "x.kf")
    assert set(doc["clips"]) == {"idle", "bend"}
    assert doc["clips"]["bend"] == {"start": 2.0, "stop": 4.0, "loop_start": 2.0, "loop_stop": 4.0}
    names = {t["node"] for t in doc["tracks"]}
    assert names == {"Bone1", "Bone2"}
    b2 = [t for t in doc["tracks"] if t["node"] == "Bone2"][0]
    s = np.sin(np.radians(45))
    assert b2["rotation"]["values"][1] == pytest.approx([s, 0, 0, s], abs=1e-6)  # +X MW = +X Godot


def test_text_keys_multiline():
    clips, flat = parse_text_keys([(0.0, "Walk: Start\r\nSound: FootLeft"), (1.0, "Walk: Stop")])
    assert clips["walk"]["start"] == 0.0 and clips["walk"]["stop"] == 1.0 and len(flat) == 3


def test_scan_reports_groups(tmp_path):
    from mwconv.scan import scan
    from mwconv.synthetic import write_assets
    from mwconv.synthetic_hard import write_hard
    d = tmp_path / "Data Files"
    write_assets(d, make_bsa=False)
    write_hard(d)
    for k, v in corrupt_variants().items():
        (d / "meshes" / "synth" / k).write_bytes(v)
    r = scan([str(d)], [], jobs=1)
    assert r["failed"] == 6 and r["ok"] == r["files"] - 6
    assert any(g.startswith("NiTriShapeData") for g in r["error_groups"])
    assert r["block_types"]["NiTriShape"] > 10
