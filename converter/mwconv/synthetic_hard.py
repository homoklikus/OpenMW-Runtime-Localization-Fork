"""Trudne przypadki NIF (własne dane syntetyczne) – przygotowanie na prawdziwe pliki gry.

Każdy model sprawdza bloki i sytuacje rzadkie w prostych modelach:
  hard_nodes.nif      – NiSwitchNode, NiLODNode, NiBillboardNode, NiSortAdjustNode, NiCollisionSwitch,
                        NiCamera, NiPointLight/NiSpotLight/NiAmbientLight + lista efektów, NiTextureEffect,
                        2 zestawy UV + sloty dark/detail/glow, tekstura wewnętrzna (NiPixelData), właściwości
                        Specular/Wireframe/Fog/ZBuffer/Dither/Shade, ukryty węzeł, macierz nieortonormalna,
                        indeks trójkąta poza zakresem, zerowe normalne, dodatkowe dane (NiExtraData,
                        NiVertWeightsExtraData), mieszanie addytywne
  hard_controllers.nif – NiVisController, NiUVController, NiAlphaController, NiMaterialColorController,
                        NiFlipController, NiGeomMorpherController, NiPathController, NiLookAtController,
                        NiRollController; klucze XYZ i TBC; kontroler z częstotliwością ≠ 1
  hard_particles.nif  – NiBSParticleNode, NiAutoNormalParticles + NiRotatingParticles, NiParticleSystemController,
                        NiBSPArrayController, NiGravity, NiParticleGrowFade, NiParticleColorModifier (NiColorData),
                        NiParticleRotation, kolidery, NiParticleBomb
  hard_skin5.nif      – skin z 5 kośćmi i wierzchołkami z > 4 wpływami
  xtest_skinned.kf    – plik animacji (NiSequenceStreamHelper) dla test_skinned.nif, klipy wg kluczy tekstowych
oraz pliki celowo uszkodzone (corrupt_*.nif) do testów odporności.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from .nif.writer import NifBuilder
from .synthetic import _normals_from, _textured, box, quat_wxyz_axis, rot_z


def _shape(nb, name, size, center, tex="tx_synth_checker.tga", props=(), uv2=False, **kw):
    V, N, UV, T = box(size, center)
    uvs = [UV, UV * 2.0] if uv2 else [UV]
    d = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=uvs, triangles=T)
    return nb.add("NiTriShape", name=name, data=d, properties=list(props) or _textured(nb, tex), **kw)


def make_hard_nodes() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="hard_nodes")
    ed = nb.add("NiExtraData", bytes=b"\x01\x02\x03\x04")
    nb.set(root, extra=ed)
    ch = []
    # przełącznik: widoczne tylko dziecko 1
    a = _shape(nb, "tri switch0", (32, 32, 32), (0, 0, 16))
    b = _shape(nb, "tri switch1", (32, 32, 64), (0, 0, 32))
    ch.append(nb.add("NiSwitchNode", name="Switch", translation=(-200, 0, 0), children=[a, b], initial_index=1))
    # LOD: dwa poziomy
    l0 = _shape(nb, "tri lod0", (48, 48, 48), (0, 0, 24))
    l1 = _shape(nb, "tri lod1", (48, 48, 8), (0, 0, 4))
    ch.append(nb.add("NiLODNode", name="LOD", translation=(-100, 0, 0), children=[l0, l1],
                     lod_levels=[(0.0, 1000.0), (1000.0, 5000.0)]))
    # billboard z mieszaniem addytywnym (SRC_ALPHA / ONE)
    alpha_add = nb.add("NiAlphaProperty", name="", flags=(1 | (6 << 1) | (0 << 5)), threshold=0)
    bb = _shape(nb, "tri billboard", (32, 1, 32), (0, 0, 16), props=_textured(nb, "tx_synth_sign.tga", extra_props=(alpha_add,)))
    ch.append(nb.add("NiBillboardNode", name="Billboard", translation=(0, 0, 100), children=[bb]))
    # sort adjust + collision switch + kamera
    sa = _shape(nb, "tri sortadjust", (16, 16, 16), (0, 0, 8))
    ch.append(nb.add("NiSortAdjustNode", name="SortAdjust", translation=(100, 0, 0), children=[sa], sorting_mode=1))
    cs = _shape(nb, "tri colswitch", (16, 16, 16), (0, 0, 8))
    ch.append(nb.add("NiCollisionSwitch", name="ColSwitch", translation=(150, 0, 0), children=[cs]))
    cam = nb.add("NiCamera", name="Camera")
    ch.append(cam)
    # światła i efekt teksturowy jako dzieci i efekty korzenia
    pl = nb.add("NiPointLight", name="PointLight", translation=(0, 0, 200))
    sl = nb.add("NiSpotLight", name="SpotLight", translation=(0, 50, 200))
    al = nb.add("NiAmbientLight", name="Ambient")
    te_src = nb.add("NiSourceTexture", name="", file="tx_synth_checker.tga")
    te = nb.add("NiTextureEffect", name="TexEffect", source=te_src)
    ch += [pl, sl, al, te]
    # 2 zestawy UV + sloty dark/detail/glow + tekstura wewnętrzna
    pix = np.zeros((8, 8, 4), np.uint8)
    pix[..., 0] = 255
    pix[..., 3] = 255
    pd = nb.add("NiPixelData", pixels=pix.tobytes(), width=8, height=8)
    s_base = nb.add("NiSourceTexture", name="", file="tx_synth_planks.tga")
    s_dark = nb.add("NiSourceTexture", name="", file="tx_synth_roof.tga")
    s_detail = nb.add("NiSourceTexture", name="", file="tx_synth_checker.tga")
    s_glow = nb.add("NiSourceTexture", name="", file="tx_synth_sign.tga")
    s_int = nb.add("NiSourceTexture", name="", pixel_data=pd)
    tp = nb.add("NiTexturingProperty", name="", textures={
        "base": {"source": s_base}, "dark": {"source": s_dark}, "detail": {"source": s_detail, "uv_set": 1},
        "glow": {"source": s_glow}, "gloss": {"source": s_int}})
    mp = nb.add("NiMaterialProperty", name="multi", emissive=(0.1, 0.1, 0.0))
    props = [tp, mp, nb.add("NiSpecularProperty", name="", flags=1), nb.add("NiWireframeProperty", name="", flags=0),
             nb.add("NiFogProperty", name=""), nb.add("NiZBufferProperty", name="", flags=1),
             nb.add("NiDitherProperty", name="", flags=1), nb.add("NiShadeProperty", name="", flags=1)]
    ch.append(_shape(nb, "tri multitex", (64, 64, 64), (0, 200, 32), props=props, uv2=True))
    # ukryty węzeł
    hid = _shape(nb, "tri hidden", (16, 16, 16), (0, 0, 8))
    ch.append(nb.add("NiNode", name="Hidden", flags=0x0D, translation=(0, -200, 0), children=[hid]))
    # macierz nieortonormalna (ścinanie)
    shear = np.array([[1.0, 0.3, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]])
    sh = _shape(nb, "tri shear", (32, 32, 32), (0, 0, 16))
    ch.append(nb.add("NiNode", name="Shear", rotation=shear, translation=(200, 200, 0), children=[sh]))
    # geometria z błędami: indeks poza zakresem, zerowe normalne, dodatkowe wagi wierzchołków
    V, N, UV, T = box((32, 32, 32), (0, 0, 16))
    N = N.copy()
    N[:4] = 0
    T = np.r_[T, [[0, 1, 99]]].astype(np.uint16)
    bd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    vw = nb.add("NiVertWeightsExtraData", weights=[1.0] * 4)
    ch.append(nb.add("NiTriShape", name="tri broken", data=bd, extra=vw, translation=(-200, 200, 0),
                     properties=_textured(nb, "tx_missing_texture.tga")))
    nb.set(root, children=ch, effects=[pl, te])
    return nb.to_bytes()


def make_hard_controllers() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="hard_controllers")
    ch = []
    # widoczność: miga co 0.5 s
    vis_shape = _shape(nb, "tri vis", (32, 32, 32), (0, 0, 16))
    vis_node = nb.add("NiNode", name="VisNode", translation=(-150, 0, 0), children=[vis_shape])
    vd = nb.add("NiVisData", keys=[(0.0, 1), (0.5, 0), (1.0, 1)])
    vc = nb.add("NiVisController", target=vis_node, data=vd, stop=1.0)
    nb.set(vis_node, controller=vc)
    ch.append(vis_node)
    # UV: przesuwanie (woda/lawa)
    uv_shape = _shape(nb, "tri uvscroll", (64, 64, 4), (0, 0, 2))
    uvd = nb.add("NiUVData", groups=[{"interp": 1, "times": [0.0, 2.0], "values": [[0.0], [1.0]]},
                                     {"interp": 1, "times": [0.0, 2.0], "values": [[0.0], [0.5]]}, None, None])
    uvc = nb.add("NiUVController", target=uv_shape, data=uvd, stop=2.0)
    nb.set(uv_shape, controller=uvc)
    ch.append(nb.add("NiNode", name="UVNode", translation=(-50, 0, 0), children=[uv_shape]))
    # alfa materiału + kolor materiału
    fd = nb.add("NiFloatData", keys={"interp": 1, "times": [0.0, 1.0, 2.0], "values": [[1.0], [0.2], [1.0]]})
    pdat = nb.add("NiPosData", keys={"interp": 1, "times": [0.0, 1.0], "values": [[1, 0, 0], [0, 0, 1]]})
    mat = nb.add("NiMaterialProperty", name="animated")
    ac = nb.add("NiAlphaController", target=mat, data=fd, stop=2.0)
    mc = nb.add("NiMaterialColorController", target=mat, data=pdat, stop=1.0, flags=0x08 | (1 << 4))  # bity 4-5: 1 = diffuse
    nb.set(ac, next=mc)
    nb.set(mat, controller=ac)
    src = nb.add("NiSourceTexture", name="", file="tx_synth_checker.tga")
    tp = nb.add("NiTexturingProperty", name="", textures={"base": {"source": src}})
    alpha = nb.add("NiAlphaProperty", name="", flags=0x12ED)
    mshape = _shape(nb, "tri matanim", (32, 32, 32), (0, 0, 16), props=[tp, mat, alpha])
    ch.append(nb.add("NiNode", name="MatNode", translation=(50, 0, 0), children=[mshape]))
    # flip: animacja tekstur
    f1 = nb.add("NiSourceTexture", name="", file="tx_synth_planks.tga")
    f2 = nb.add("NiSourceTexture", name="", file="tx_synth_roof.tga")
    f3 = nb.add("NiSourceTexture", name="", file="tx_synth_sign.tga")
    ftp = nb.add("NiTexturingProperty", name="", textures={"base": {"source": f1}})
    flc = nb.add("NiFlipController", target=ftp, sources=[f1, f2, f3], delta=0.25, stop=0.75)
    nb.set(ftp, controller=flc)
    fshape = _shape(nb, "tri flip", (32, 32, 32), (0, 0, 16), props=[ftp, nb.add("NiMaterialProperty", name="flip")])
    ch.append(nb.add("NiNode", name="FlipNode", translation=(150, 0, 0), children=[fshape]))
    # morfy
    V, N, UV, T = box((32, 32, 32), (0, 0, 16))
    md_ = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    morph_shape = nb.add("NiTriShape", name="tri morph", data=md_, properties=_textured(nb, "tx_synth_checker.tga"))
    delta = np.zeros_like(V)
    delta[:, 2] = np.where(V[:, 2] > 16, 32, 0)
    mdata = nb.add("NiMorphData", morphs=[
        {"keys": {"interp": 1, "times": [0.0], "values": [[1.0]]}, "vertices": V},
        {"keys": {"interp": 1, "times": [0.0, 1.0], "values": [[0.0], [1.0]]}, "vertices": delta}])
    gmc = nb.add("NiGeomMorpherController", target=morph_shape, data=mdata, stop=1.0)
    nb.set(morph_shape, controller=gmc)
    ch.append(nb.add("NiNode", name="MorphNode", translation=(0, 150, 0), children=[morph_shape]))
    # path / lookat / roll
    pathd = nb.add("NiPosData", keys={"interp": 1, "times": [0.0, 1.0], "values": [[0, 0, 0], [100, 0, 0]]})
    perc = nb.add("NiFloatData", keys={"interp": 1, "times": [0.0, 2.0], "values": [[0.0], [1.0]]})
    pn = nb.add("NiNode", name="PathNode", children=[_shape(nb, "tri path", (8, 8, 8), (0, 0, 4))])
    pc = nb.add("NiPathController", target=pn, path_data=pathd, percent_data=perc, stop=2.0)
    nb.set(pn, controller=pc)
    ch.append(pn)
    ln = nb.add("NiNode", name="LookNode", children=[_shape(nb, "tri look", (8, 8, 8), (0, 0, 4))])
    lc = nb.add("NiLookAtController", target=ln, lookat=pn)
    nb.set(ln, controller=lc)
    ch.append(ln)
    rn = nb.add("NiNode", name="RollNode", children=[_shape(nb, "tri roll", (8, 8, 8), (0, 0, 4))])
    rd = nb.add("NiFloatData", keys={"interp": 1, "times": [0.0, 1.0], "values": [[0.0], [3.14]]})
    rc = nb.add("NiRollController", target=rn, data=rd, stop=1.0)
    nb.set(rn, controller=rc)
    ch.append(rn)
    # klucze XYZ (obrót) i TBC (translacja), częstotliwość 2
    xyz_shape = _shape(nb, "tri xyz", (16, 64, 16), (0, 0, 0))
    xyz_node = nb.add("NiNode", name="XYZNode", translation=(0, -150, 100), children=[xyz_shape])
    kd = nb.add("NiKeyframeData",
                rotations={"interp": 4, "order": 0, "xyz": [
                    {"interp": 1, "times": [0.0, 1.0], "values": [[0.0], [0.0]]},
                    {"interp": 1, "times": [0.0, 1.0], "values": [[0.0], [0.0]]},
                    {"interp": 1, "times": [0.0, 0.5, 1.0], "values": [[0.0], [math.pi / 2], [math.pi]]}]},
                translations={"interp": 3, "times": [0.0, 0.5, 1.0],
                              "values": [(0, -150, 100), (0, -150, 150), (0, -150, 100)],
                              "tbc": [(0, 0, 0), (0, 0, 0), (0, 0, 0)]})
    kc = nb.add("NiKeyframeController", target=xyz_node, data=kd, stop=1.0, frequency=2.0)
    nb.set(xyz_node, controller=kc)
    ch.append(xyz_node)
    nb.set(root, children=ch)
    return nb.to_bytes()


def make_hard_particles() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiBSParticleNode", name="hard_particles")
    emitter = nb.add("NiNode", name="Emitter", translation=(0, 0, 50))
    n = 6
    pv = np.zeros((n, 3), np.float32)
    pdata = nb.add("NiAutoNormalParticlesData", vertices=pv, normals=None, uvs=[], sizes=[1.0] * n)
    src = nb.add("NiSourceTexture", name="", file="tx_synth_sign.tga")
    tp = nb.add("NiTexturingProperty", name="", textures={"base": {"source": src}})
    add = nb.add("NiAlphaProperty", name="", flags=(1 | (6 << 1) | (0 << 5)))
    zb = nb.add("NiZBufferProperty", name="", flags=1)
    vc = nb.add("NiVertexColorProperty", name="", vertex_mode=2, lighting_mode=0)
    parts = nb.add("NiAutoNormalParticles", name="Particles", data=pdata, properties=[tp, add, zb, vc])
    cdata = nb.add("NiColorData", keys={"interp": 1, "times": [0.0, 1.0],
                                        "values": [[1, 0.8, 0.3, 1], [1, 0.1, 0.0, 0]]})
    colmod = nb.add("NiParticleColorModifier", data=cdata)
    grow = nb.add("NiParticleGrowFade", grow=0.1, fade=0.4)
    grav = nb.add("NiGravity", force=0.5, type=0, direction=(0, 0, 1))
    rot = nb.add("NiParticleRotation", rotation_speed=2.0)
    nb.set(colmod, next=grow)
    nb.set(grow, next=grav)
    nb.set(grav, next=rot)
    plane = nb.add("NiPlanarCollider")
    sphere = nb.add("NiSphericalCollider")
    nb.set(plane, next=sphere)
    pc = nb.add("NiParticleSystemController", target=parts, emitter=emitter, particle_modifier=colmod,
                particle_collider=plane, num_particles=n, speed=30.0, emit_rate=12.0, lifetime=1.5, size=8.0,
                stop=1000.0)
    for m in (colmod, grow, grav, rot, plane, sphere):
        nb.set(m, controller=pc)
    nb.set(parts, controller=pc)
    # drugi system: NiRotatingParticles + NiBSPArrayController + bomba
    rv = np.zeros((3, 3), np.float32)
    rdata = nb.add("NiRotatingParticlesData", vertices=rv, normals=None, uvs=[], sizes=None)
    rparts = nb.add("NiRotatingParticles", name="RotParticles", data=rdata, properties=[tp])
    bomb = nb.add("NiParticleBomb")
    bc = nb.add("NiBSPArrayController", target=rparts, emitter=emitter, particle_modifier=bomb, num_particles=3)
    nb.set(bomb, controller=bc)
    nb.set(rparts, controller=bc)
    nb.set(root, children=[emitter, parts, rparts])
    return nb.to_bytes()


def make_hard_skin5() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="hard_skin5")
    bones = []
    parent = None
    for k in range(5):
        b = nb.add("NiNode", name=f"B{k}", translation=(0, 0, 0 if k == 0 else 40))
        if parent is not None:
            nb.set(parent, children=[b])
        bones.append(b)
        parent = b
    V, N, UV, T = box((32, 32, 200), (0, 0, 100))
    n = len(V)
    sk = []
    for k in range(5):
        w = np.full(n, 0.2, np.float32)  # każdy wierzchołek ma 5 wpływów
        sk.append({"transform": {"translation": (0, 0, -40.0 * k)}, "indices": np.arange(n), "weights": w})
    sd = nb.add("NiSkinData", transform={}, bones=sk)
    si = nb.add("NiSkinInstance", data=sd, root=root, bones=bones)
    d = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    sh = nb.add("NiTriShape", name="tri skin5", data=d, skin=si, properties=_textured(nb, "tx_synth_checker.tga"))
    nb.set(root, children=[bones[0], sh])
    return nb.to_bytes()


def make_kf_skinned() -> bytes:
    """Plik .kf dla test_skinned.nif: klipy „Idle” (0–2 s) i „Bend” (2–4 s)."""
    nb = NifBuilder()
    root = nb.add("NiSequenceStreamHelper", name="")
    tk = nb.add("NiTextKeyExtraData", keys=[(0.0, "Idle: Start"), (2.0, "Idle: Stop\r\nBend: Start"),
                                           (2.0, "Bend: Loop Start"), (4.0, "Bend: Loop Stop\r\nBend: Stop")])
    s1 = nb.add("NiStringExtraData", string="Bone1")
    s2 = nb.add("NiStringExtraData", string="Bone2")
    nb.set(tk, next=s1)
    nb.set(s1, next=s2)
    nb.set(root, extra=tk)
    k1 = nb.add("NiKeyframeData", translations={"interp": 1, "times": [0.0, 1.0, 2.0],
                                                "values": [(0, 0, 0), (0, 0, 8), (0, 0, 0)]})
    k2 = nb.add("NiKeyframeData", rotations={"interp": 1, "times": [2.0, 3.0, 4.0],
                                             "values": [quat_wxyz_axis((1, 0, 0), a) for a in (0, 90, 0)]})
    c1 = nb.add("NiKeyframeController", target=-1, data=k1, start=0.0, stop=4.0)
    c2 = nb.add("NiKeyframeController", target=-1, data=k2, start=0.0, stop=4.0)
    nb.set(c1, next=c2)
    nb.set(root, controller=c1)
    return nb.to_bytes()


HARD_MODELS = {
    "meshes/synth/hard_nodes.nif": make_hard_nodes,
    "meshes/synth/hard_controllers.nif": make_hard_controllers,
    "meshes/synth/hard_particles.nif": make_hard_particles,
    "meshes/synth/hard_skin5.nif": make_hard_skin5,
    "meshes/synth/xtest_skinned.kf": make_kf_skinned,
}


def corrupt_variants() -> dict[str, bytes]:
    """Celowo uszkodzone pliki: każdy musi dać czytelny NifError, nie wyjątek Pythona ani zawieszenie."""
    good = make_hard_nodes()
    head_end = good.find(b"\n") + 1
    out = {
        "corrupt_truncated.nif": good[: len(good) // 2],
        "corrupt_empty.nif": b"",
        "corrupt_header.nif": b"Not a NIF file\n" + good[head_end:],
        "corrupt_version.nif": good[:head_end] + (0x14000005).to_bytes(4, "little") + good[head_end + 4:],
    }
    # nieznany typ bloku: podmiana nazwy pierwszego bloku na nieistniejącą tej samej długości
    i = good.find(b"NiNode")
    out["corrupt_unknown_block.nif"] = good[:i] + b"NiNada" + good[i + 6:]
    # absurdalny licznik dzieci w korzeniu
    bad = bytearray(good)
    j = good.find(b"hard_nodes") + len(b"hard_nodes") + 4 + 4 + 2 + 12 + 36 + 4 + 12
    # pominięcie listy właściwości (licznik 0) i bool bounding volume → licznik dzieci
    j += 4 + 4
    bad[j:j + 4] = (0x7FFFFFFF).to_bytes(4, "little")
    out["corrupt_count.nif"] = bytes(bad)
    return out


def write_hard(data_dir: Path) -> list[str]:
    data_dir = Path(data_dir)
    out = []
    for rel, fn in HARD_MODELS.items():
        p = data_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(fn())
        out.append(rel)
    return out
