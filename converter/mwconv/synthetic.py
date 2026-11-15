"""Własne, syntetyczne zasoby testowe (licencja MIT/CC0 – wygenerowane kodem, bez danych Bethesdy).

Tworzy w katalogu docelowym strukturę „Data Files”:
  meshes/synth/test_hut.nif        – domek: ściany (NiTriShape), dach (NiTriStrips + kolory wierzchołków),
                                     przesunięty/obrócony/przeskalowany szyld z alfa-testem i dwustronnością,
                                     RootCollisionNode z uproszczoną bryłą kolizji, marker edytora (MRK)
  meshes/synth/test_windmill.nif   – wiatrak: łopaty obracane NiKeyframeController (LINEAR),
                                     piasta z translacją kwadratową (Hermite), klucze tekstowe
  meshes/synth/test_skinned.nif    – rura z 2 kośćmi (NiSkinInstance/NiSkinData) i animacją kości
  meshes/synth/test_crate.nif      – skrzynka 64³ jednostek (proste odniesienie skali)
  textures/tx_synth_*.dds          – tekstury proceduralne DXT1/DXT5
  synth.bsa (opcjonalnie)          – archiwum BSA TES3 z częścią plików
"""

from __future__ import annotations

import io
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from .nif.writer import NifBuilder

# ------------------------------------------------------------------------------------------------
# geometria pomocnicza (układ Morrowinda: Z w górę, jednostki gry)
# ------------------------------------------------------------------------------------------------


def box(size, center=(0, 0, 0), uv_scale=1.0):
    """Prostopadłościan z osobnymi wierzchołkami na ścianę (płaskie normalne, UV 0..1)."""
    sx, sy, sz = (s / 2 for s in size)
    cx, cy, cz = center
    faces = [  # normalna, osie u, v
        ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
        ((-1, 0, 0), (0, -1, 0), (0, 0, 1)),
        ((0, 1, 0), (-1, 0, 0), (0, 0, 1)),
        ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
        ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        ((0, 0, -1), (1, 0, 0), (0, -1, 0)),
    ]
    half = np.array([sx, sy, sz])
    V, N, UV, T = [], [], [], []
    for n, u, v in faces:
        n, u, v = np.array(n, float), np.array(u, float), np.array(v, float)
        c = n * half
        hu = np.abs(u) @ half
        hv = np.abs(v) @ half
        base = len(V)
        for du, dv, tu, tv in ((-1, -1, 0, 1), (1, -1, 1, 1), (1, 1, 1, 0), (-1, 1, 0, 0)):
            p = c + u * hu * du + v * hv * dv + np.array([cx, cy, cz])
            V.append(p)
            N.append(n)
            UV.append((tu * uv_scale, tv * uv_scale))
        T += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return np.array(V, np.float32), np.array(N, np.float32), np.array(UV, np.float32), np.array(T, np.uint16)


def _grid_strip(nx, ny, w, h, z_of, origin=(0, 0, 0)):
    """Siatka jako paski trójkątów (NiTriStrips)."""
    V, UV = [], []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = origin[0] + w * i / nx
            y = origin[1] + h * j / ny
            V.append((x, y, origin[2] + z_of(x, y)))
            UV.append((i / nx, 1 - j / ny))
    strips = []
    for j in range(ny):
        s = []
        for i in range(nx + 1):
            s += [(j + 1) * (nx + 1) + i, j * (nx + 1) + i]
        strips.append(s)
    return np.array(V, np.float32), np.array(UV, np.float32), strips


def _normals_from(V, tris):
    N = np.zeros_like(V, dtype=np.float64)
    for a, b, c in tris:
        n = np.cross(V[b] - V[a], V[c] - V[a])
        N[a] += n
        N[b] += n
        N[c] += n
    ln = np.linalg.norm(N, axis=1, keepdims=True)
    return (N / np.maximum(ln, 1e-9)).astype(np.float32)


def _strip_tris(strips):
    out = []
    for s in strips:
        for i in range(2, len(s)):
            a, b, c = s[i - 2], s[i - 1], s[i]
            out.append((a, b, c) if i % 2 == 0 else (a, c, b))
    return out


def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rot_x(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def quat_wxyz_axis(axis, deg):
    a = math.radians(deg) / 2
    ax = np.asarray(axis, float)
    ax /= np.linalg.norm(ax)
    return [math.cos(a), *(ax * math.sin(a))]


# ------------------------------------------------------------------------------------------------
# tekstury proceduralne
# ------------------------------------------------------------------------------------------------

def tex_planks(size=128):
    im = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(im)
    rng = np.random.default_rng(1)
    for k in range(8):
        y0 = k * size // 8
        base = (120 + int(rng.integers(-15, 15)), 80 + int(rng.integers(-10, 10)), 45)
        d.rectangle([0, y0, size, y0 + size // 8 - 2], fill=base)
        d.line([0, y0 + size // 8 - 1, size, y0 + size // 8 - 1], fill=(50, 30, 15))
    return im


def tex_roof(size=128):
    im = Image.new("RGB", (size, size), (150, 60, 40))
    d = ImageDraw.Draw(im)
    for j in range(0, size, 16):
        for i in range(-8 if (j // 16) % 2 else 0, size, 16):
            d.arc([i, j, i + 16, j + 16], 0, 180, fill=(90, 30, 20), width=2)
    return im


def tex_sign(size=128):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 8, size - 8, size - 8], fill=(230, 200, 60, 255), outline=(60, 40, 10, 255), width=6)
    d.rectangle([size // 2 - 6, 24, size // 2 + 6, size - 24], fill=(60, 40, 10, 255))
    return im


def tex_checker(size=64, a=(200, 200, 200), b=(60, 90, 160)):
    im = Image.new("RGB", (size, size), a)
    d = ImageDraw.Draw(im)
    s = size // 8
    for j in range(8):
        for i in range(8):
            if (i + j) % 2:
                d.rectangle([i * s, j * s, i * s + s - 1, j * s + s - 1], fill=b)
    return im


def tex_ground(color, size=64, seed=0):
    rng = np.random.default_rng(seed)
    a = np.clip(np.array(color)[None, None, :] + rng.normal(0, 12, (size, size, 3)), 0, 255).astype(np.uint8)
    return Image.fromarray(a)  # uint8 H×W×3 → RGB (parametr mode jest przestarzały w Pillow 11+)


def save_dds(im: Image.Image, path: Path, fmt: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.convert("RGBA").save(path, pixel_format=fmt)


# ------------------------------------------------------------------------------------------------
# modele NIF
# ------------------------------------------------------------------------------------------------

def _textured(nb: NifBuilder, tex_file: str, diffuse=(1, 1, 1), extra_props=()):
    src = nb.add("NiSourceTexture", name="", file=tex_file)
    tp = nb.add("NiTexturingProperty", name="", textures={"base": {"source": src, "clamp": 3, "filter": 2}})
    mp = nb.add("NiMaterialProperty", name="mat_" + tex_file.split(".")[0], diffuse=diffuse, ambient=diffuse)
    return [tp, mp, *extra_props]


def make_hut() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="test_hut")
    mrk = nb.add("NiStringExtraData", string="MRK")
    nb.set(root, extra=mrk)
    children = []

    # ściany: 256 × 256 × 192, podstawa na z = 0
    V, N, UV, T = box((256, 256, 192), (0, 0, 96))
    wd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    walls = nb.add("NiTriShape", name="tri walls", data=wd, properties=_textured(nb, "tx_synth_planks.tga"))
    children.append(walls)

    # dach: dwuspadowy z NiTriStrips, kolory wierzchołków
    def roof_z(x, y):
        return 96 - abs(x) * 0.75
    V2, UV2, strips = _grid_strip(8, 4, 288, 288, roof_z, origin=(-144, -144, 192))
    tris = _strip_tris(strips)
    N2 = _normals_from(V2, tris)
    col = np.ones((len(V2), 4), np.float32)
    col[:, 0] = np.linspace(0.6, 1.0, len(V2))
    rd = nb.add("NiTriStripsData", vertices=V2, normals=N2, uvs=[UV2], colors=col, strips=strips)
    stencil = nb.add("NiStencilProperty", name="", draw_mode=3)
    vcp = nb.add("NiVertexColorProperty", name="", vertex_mode=2, lighting_mode=1)
    roof = nb.add("NiTriStrips", name="tri roof", data=rd,
                  properties=_textured(nb, "tx_synth_roof.tga", extra_props=(stencil, vcp)))
    children.append(roof)

    # szyld: węzeł przesunięty, obrócony o 30° wokół Z i przeskalowany ×1.5
    sv = np.array([[-32, 0, -32], [32, 0, -32], [32, 0, 32], [-32, 0, 32]], np.float32)
    sn = np.tile(np.array([[0, -1, 0]], np.float32), (4, 1))
    suv = np.array([[0, 1], [1, 1], [1, 0], [0, 0]], np.float32)
    st = np.array([[0, 1, 2], [0, 2, 3]], np.uint16)
    sd = nb.add("NiTriShapeData", vertices=sv, normals=sn, uvs=[suv], triangles=st)
    alpha = nb.add("NiAlphaProperty", name="", flags=0x12EC | (1 << 9), threshold=128)  # test alfa, GREATER
    stencil2 = nb.add("NiStencilProperty", name="", draw_mode=3)
    sign_shape = nb.add("NiTriShape", name="tri sign", data=sd,
                        properties=_textured(nb, "tx_synth_sign.tga", extra_props=(alpha, stencil2)))
    sign_node = nb.add("NiNode", name="SignNode", translation=(100, -160, 150), rotation=rot_z(30), scale=1.5,
                       children=[sign_shape])
    children.append(sign_node)

    # marker edytora – ma być pominięty (MRK)
    mv, mn, muv, mt = box((16, 16, 16), (0, 0, 220))
    md = nb.add("NiTriShapeData", vertices=mv, normals=mn, uvs=[muv], triangles=mt)
    children.append(nb.add("NiTriShape", name="Tri EditorMarker", data=md))

    # kolizja: jeden prostopadłościan obejmujący ściany i dach
    cv, cn, cuv, ct = box((256, 256, 288), (0, 0, 144))
    cd = nb.add("NiTriShapeData", vertices=cv, normals=None, uvs=[], triangles=ct)
    col_shape = nb.add("NiTriShape", name="tri collision", data=cd)
    rc = nb.add("RootCollisionNode", name="", children=[col_shape])
    children.append(rc)
    nb.set(root, children=children)
    return nb.to_bytes()


def make_crate() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="test_crate")
    V, N, UV, T = box((64, 64, 64), (0, 0, 32))
    d = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    sh = nb.add("NiTriShape", name="tri crate", data=d, properties=_textured(nb, "tx_synth_checker.tga"))
    nb.set(root, children=[sh])
    return nb.to_bytes()


def make_windmill() -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="test_windmill")
    tk = nb.add("NiTextKeyExtraData", keys=[(0.0, "Idle: Start"), (4.0, "Idle: Stop")])
    nb.set(root, extra=tk)
    # wieża
    V, N, UV, T = box((64, 64, 384), (0, 0, 192))
    td = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    tower = nb.add("NiTriShape", name="tri tower", data=td, properties=_textured(nb, "tx_synth_planks.tga"))
    # łopaty: dwa płaskie prostopadłościany w płaszczyźnie XZ, obrót wokół osi Y (oś piasty)
    b1 = box((24, 8, 320), (0, 0, 0))
    b2 = box((320, 8, 24), (0, 0, 0))
    V = np.r_[b1[0], b2[0]]
    N = np.r_[b1[1], b2[1]]
    UV = np.r_[b1[2], b2[2]]
    T = np.r_[b1[3], b2[3] + len(b1[0])]
    bd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    blades = nb.add("NiTriShape", name="tri blades", data=bd, properties=_textured(nb, "tx_synth_checker.tga"))
    blade_node = nb.add("NiNode", name="Blades", translation=(0, -48, 360), children=[blades])
    times = [0.0, 1.0, 2.0, 3.0, 4.0]
    quats = [quat_wxyz_axis((0, 1, 0), a) for a in (0, 90, 180, 270, 360)]
    kd = nb.add("NiKeyframeData", rotations={"interp": 1, "times": times, "values": quats},
                translations={"interp": 2, "times": [0.0, 2.0, 4.0],
                              "values": [(0, -48, 360), (0, -64, 360), (0, -48, 360)],
                              "in": [(0, 0, 0), (0, 0, 0), (0, 0, 0)], "out": [(0, 0, 0), (0, 0, 0), (0, 0, 0)]})
    kc = nb.add("NiKeyframeController", target=blade_node, data=kd, start=0.0, stop=4.0, flags=0x08)
    nb.set(blade_node, controller=kc)
    nb.set(root, children=[tower, blade_node])
    return nb.to_bytes()


def make_skinned() -> bytes:
    """Rura wzdłuż Z (wysokość 256) z dwiema kośćmi: Bone1 (z 0–128) i Bone2 (z 128–256)."""
    nb = NifBuilder()
    root = nb.add("NiNode", name="test_skinned")
    bone1 = nb.add("NiNode", name="Bone1", translation=(0, 0, 0))
    bone2 = nb.add("NiNode", name="Bone2", translation=(0, 0, 128))
    nb.set(bone1, children=[bone2])
    seg, rings, radius = 12, 9, 24.0
    V, UV = [], []
    for j in range(rings):
        z = 256.0 * j / (rings - 1)
        for i in range(seg):
            a = 2 * math.pi * i / seg
            V.append((radius * math.cos(a), radius * math.sin(a), z))
            UV.append((i / seg, 1 - j / (rings - 1)))
    T = []
    for j in range(rings - 1):
        for i in range(seg):
            a, b = j * seg + i, j * seg + (i + 1) % seg
            c, d = a + seg, b + seg
            T += [(a, b, d), (a, d, c)]
    V = np.array(V, np.float32)
    N = _normals_from(V, T)
    sd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[np.array(UV, np.float32)], triangles=np.array(T, np.uint16))
    # wagi: liniowe przejście między kośćmi w okolicy z = 128
    w2 = np.clip((V[:, 2] - 96) / 64.0, 0, 1)
    w1 = 1 - w2
    idx = np.arange(len(V))
    # NiSkinData: transformacja skin→kość (odwrotność pozy wiązania kości w układzie skinu)
    bones = [
        {"transform": {"translation": (0, 0, 0)}, "indices": idx[w1 > 0], "weights": w1[w1 > 0]},
        {"transform": {"translation": (0, 0, -128)}, "indices": idx[w2 > 0], "weights": w2[w2 > 0]},
    ]
    skd = nb.add("NiSkinData", transform={}, bones=bones)
    ski = nb.add("NiSkinInstance", data=skd, root=root, bones=[bone1, bone2])
    shape = nb.add("NiTriShape", name="tri tube", data=sd, skin=ski, properties=_textured(nb, "tx_synth_checker.tga"))
    kd = nb.add("NiKeyframeData", rotations={"interp": 1, "times": [0.0, 1.0, 2.0],
                                             "values": [quat_wxyz_axis((1, 0, 0), a) for a in (0, 60, 0)]})
    kc = nb.add("NiKeyframeController", target=bone2, data=kd, start=0.0, stop=2.0)
    nb.set(bone2, controller=kc)
    nb.set(root, children=[bone1, shape])
    return nb.to_bytes()


MODELS = {
    "meshes/synth/test_hut.nif": make_hut,
    "meshes/synth/test_crate.nif": make_crate,
    "meshes/synth/test_windmill.nif": make_windmill,
    "meshes/synth/test_skinned.nif": make_skinned,
}

TEXTURES = {
    "textures/tx_synth_planks.dds": (tex_planks, "DXT1"),
    "textures/tx_synth_roof.dds": (tex_roof, "DXT1"),
    "textures/tx_synth_sign.dds": (tex_sign, "DXT5"),
    "textures/tx_synth_checker.dds": (tex_checker, "DXT1"),
    "textures/tx_synth_grass.dds": (lambda: tex_ground((70, 120, 50), seed=1), "DXT1"),
    "textures/tx_synth_dirt.dds": (lambda: tex_ground((120, 95, 60), seed=2), "DXT1"),
    "textures/tx_synth_stone.dds": (lambda: tex_ground((130, 130, 125), seed=3), "DXT1"),
    "textures/_land_default.dds": (lambda: tex_ground((100, 100, 80), seed=4), "DXT1"),
}


def write_assets(data_dir: Path, make_bsa: bool = True) -> list[str]:
    data_dir = Path(data_dir)
    written = []
    for rel, fn in MODELS.items():
        p = data_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(fn())
        written.append(rel)
    for rel, (fn, fmt) in TEXTURES.items():
        save_dds(fn(), data_dir / rel, fmt)
        written.append(rel)
    if make_bsa:
        from .vfs import write_bsa
        # do archiwum trafia kopia skrzynki pod inną nazwą – test odczytu z BSA
        write_bsa(data_dir / "synth.bsa", {"meshes\\synth\\bsa_crate.nif": make_crate()})
        written.append("synth.bsa")
    return written
