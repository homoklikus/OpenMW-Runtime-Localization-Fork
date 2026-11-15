"""NIF → glTF: odczyt, geometria, skala, orientacja, materiały, transformacje, skin, animacje."""

import math

import numpy as np
import pytest

from mwconv import coords
from mwconv.gltf import accessor_array, read_glb
from mwconv.nif.reader import parse
from mwconv.nif2gltf import NifToGltf, TextureRef
from mwconv.synthetic import MODELS, make_hut, make_skinned, make_windmill

U = coords.UNITS_PER_METER


def conv(data, name="m.nif"):
    nif = parse(data, name)
    glb, rep = NifToGltf(nif, name, lambda n: TextureRef("../textures/" + n.lower(), source_path=n)).convert()
    doc, binc = read_glb(glb)
    return nif, doc, binc, rep


def node_by_name(doc, name):
    for i, n in enumerate(doc["nodes"]):
        if n.get("extras", {}).get("mw_name") == name:
            return i, n
    raise KeyError(name)


def world_matrices(doc):
    """Macierze świata węzłów glTF (4×4)."""
    parent = {}
    for i, n in enumerate(doc["nodes"]):
        for c in n.get("children", []):
            parent[c] = i

    def local(n):
        if "matrix" in n:
            return np.array(n["matrix"]).reshape(4, 4).T
        m = np.eye(4)
        q = n.get("rotation", [0, 0, 0, 1])
        s = n.get("scale", [1, 1, 1])
        m[:3, :3] = coords.quat_to_mat(q) @ np.diag(s)
        m[:3, 3] = n.get("translation", [0, 0, 0])
        return m

    out = {}

    def w(i):
        if i not in out:
            out[i] = (w(parent[i]) if i in parent else np.eye(4)) @ local(doc["nodes"][i])
        return out[i]

    for i in range(len(doc["nodes"])):
        w(i)
    return out


@pytest.mark.parametrize("model", sorted(MODELS))
def test_parse_byte_exact(model):
    data = MODELS[model]()
    nif = parse(data, model)
    assert nif.trailing == 0
    assert nif.blocks[0].type == "NiNode"


def test_hut_scale_orientation_and_bounds():
    nif, doc, binc, rep = conv(make_hut(), "test_hut.nif")
    # ściany 256 jedn. → 3.6576 m; dach z okapem ±144 jedn.; wysokość 192 + 96 = 288 jedn.
    assert rep.aabb_min[1] == pytest.approx(0.0, abs=1e-6)
    assert rep.aabb_max[1] == pytest.approx(288 / U, abs=1e-5)
    assert rep.aabb_max[0] == pytest.approx(144 / U, abs=1e-5)
    # ściany: dokładnie 3.6576 m szerokości
    i, n = node_by_name(doc, "tri walls")
    pos = accessor_array(doc, binc, doc["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"])
    assert pos[:, 0].max() - pos[:, 0].min() == pytest.approx(256 / U, abs=1e-5)
    assert pos[:, 1].max() == pytest.approx(192 / U, abs=1e-5)  # Z (góra) MW → Y Godota


def test_axis_mapping_north_is_minus_z():
    # wierzchołek na północ (+Y MW) musi trafić na -Z w Godocie
    p = coords.pos_to_godot([0, 100, 0])
    assert p == pytest.approx([0, 0, -100 / U])
    p = coords.pos_to_godot([0, 0, 70])
    assert p[1] == pytest.approx(70 / U)


def test_normals_and_winding_consistent():
    nif, doc, binc, rep = conv(make_hut(), "test_hut.nif")
    i, n = node_by_name(doc, "tri walls")
    prim = doc["meshes"][n["mesh"]]["primitives"][0]
    pos = accessor_array(doc, binc, prim["attributes"]["POSITION"])
    nrm = accessor_array(doc, binc, prim["attributes"]["NORMAL"])
    idx = accessor_array(doc, binc, prim["indices"]).reshape(-1, 3)
    for a, b, c in idx:
        fn = np.cross(pos[b] - pos[a], pos[c] - pos[a])
        assert np.dot(fn, nrm[a]) > 0, "nawinięcie CCW musi zgadzać się z normalną"


def test_node_transform_converted():
    nif, doc, binc, rep = conv(make_hut(), "test_hut.nif")
    i, n = node_by_name(doc, "SignNode")
    assert n["translation"] == pytest.approx([100 / U, 150 / U, 160 / U], abs=1e-6)
    assert n["scale"] == pytest.approx([1.5] * 3)
    # 30° wokół Z (MW) = 30° wokół Y (Godot), ten sam zwrot
    q = n["rotation"]
    assert q == pytest.approx([0, math.sin(math.radians(15)), 0, math.cos(math.radians(15))], abs=1e-6)


def test_materials_alpha_doublesided_vertex_colors_and_collision():
    nif, doc, binc, rep = conv(make_hut(), "test_hut.nif")
    mats = doc["materials"]
    i, sign = node_by_name(doc, "tri sign")
    m = mats[doc["meshes"][sign["mesh"]]["primitives"][0]["material"]]
    assert m["alphaMode"] == "MASK" and m["alphaCutoff"] == pytest.approx(128 / 255, abs=1e-6)
    assert m.get("doubleSided") is True
    assert "baseColorTexture" in m["pbrMetallicRoughness"]
    i, roof = node_by_name(doc, "tri roof")
    prim = doc["meshes"][roof["mesh"]]["primitives"][0]
    assert "COLOR_0" in prim["attributes"]
    assert mats[prim["material"]].get("doubleSided") is True
    # marker edytora pominięty, kolizja oznaczona i bez materiału
    assert any(s["reason"].startswith("editor marker") for s in rep.skipped_shapes)
    i, col = node_by_name(doc, "tri collision")
    assert col["extras"]["mw_collision"] is True
    assert "material" not in doc["meshes"][col["mesh"]]["primitives"][0]
    assert rep.collision_meshes == 1
    uris = {im["uri"] for im in doc["images"]}
    assert "../textures/tx_synth_sign.tga" in uris


def test_skin_bind_pose_matches_rigid():
    nif, doc, binc, rep = conv(make_skinned(), "test_skinned.nif")
    assert rep.skins == 1
    wm = world_matrices(doc)
    i, tube = node_by_name(doc, "tri tube")
    prim = doc["meshes"][tube["mesh"]]["primitives"][0]
    pos = accessor_array(doc, binc, prim["attributes"]["POSITION"]).astype(np.float64)
    J = accessor_array(doc, binc, prim["attributes"]["JOINTS_0"])
    Wt = accessor_array(doc, binc, prim["attributes"]["WEIGHTS_0"])
    skin = doc["skins"][tube["skin"]]
    ibm = accessor_array(doc, binc, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    joint_mats = [wm[j] @ ibm[k] for k, j in enumerate(skin["joints"])]
    for v, jj, ww in zip(pos, J, Wt):
        p = sum(w * (joint_mats[j] @ np.r_[v, 1])[:3] for j, w in zip(jj, ww))
        # geometria rury jest w korzeniu bez transformacji ⇒ wynik = pozycja w GLB
        assert p == pytest.approx(v, abs=1e-5)
    assert np.allclose(Wt.sum(axis=1), 1.0, atol=1e-6)


def test_animation_rotation_axis_converted():
    nif, doc, binc, rep = conv(make_windmill(), "test_windmill.nif")
    assert rep.animations == 1
    anim = doc["animations"][0]
    i, blades = node_by_name(doc, "Blades")
    rot = [c for c in anim["channels"] if c["target"]["node"] == i and c["target"]["path"] == "rotation"][0]
    smp = anim["samplers"][rot["sampler"]]
    q = accessor_array(doc, binc, smp["output"])
    # 90° wokół +Y MW = 90° wokół -Z Godota
    s = math.sin(math.radians(45))
    assert q[1] == pytest.approx([0, 0, -s, s], abs=1e-6)
    tr = [c for c in anim["channels"] if c["target"]["node"] == i and c["target"]["path"] == "translation"][0]
    smp = anim["samplers"][tr["sampler"]]
    assert smp["interpolation"] == "CUBICSPLINE"
    out = accessor_array(doc, binc, smp["output"]).reshape(-1, 3, 3)
    assert out[1, 1] == pytest.approx(coords.pos_to_godot([0, -64, 360]), abs=1e-6)
    assert anim["extras"]["mw_text_keys"][0] == [0.0, "Idle: Start"]


def test_ref_rotation_roundtrip_and_sign():
    rng = np.random.default_rng(3)
    for _ in range(50):
        rot = tuple(rng.uniform(-1.4, 1.4, 3))
        R = coords.mw_ref_rotation(rot)
        assert coords.mw_ref_rotation(coords.mw_ref_rotation_inverse(R)) == pytest.approx(R, abs=1e-9)
    # rz = +90°: obrót zgodny z ruchem wskazówek zegara widziany z góry: +X → -Y
    R = coords.mw_ref_rotation((0, 0, math.pi / 2))
    assert R @ [1, 0, 0] == pytest.approx([0, -1, 0], abs=1e-12)
