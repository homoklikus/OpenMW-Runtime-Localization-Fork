"""Czytnik plików NIF w wersji NetImmerse 4.0.0.2 (Morrowind) oraz 4.0.0.0.

Implementacja własna projektu (licencja GPL-3.0-or-later), napisana na podstawie publicznej specyfikacji formatu
`nif.xml` projektu NifTools (licencja BSD). Nie zawiera kodu OpenMW.

Format 4.0.0.2 nie zapisuje rozmiarów bloków, więc każdy blok trzeba odczytać w całości. Nieznany
typ bloku przerywa odczyt (`NifError`) — nie zgadujemy rozmiaru.

Konwencja macierzy: obrót zapisany jest 9 liczbami wierszami, punkt w układzie rodzica
p_rodzic = t + s · R · p (wektory kolumnowe).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

import numpy as np

from ..binio import FormatError, Reader

VER_4000 = 0x04000000
VER_4002 = 0x04000002


class NifError(Exception):
    """Błąd odczytu NIF. Atrybuty diagnostyczne: offset, block_index, block_type, block_start, partial
    (bloki odczytane poprawnie przed błędem) – używane przez `mwconv inspect`."""

    def __init__(self, msg, **diag):
        super().__init__(msg)
        self.offset = diag.get("offset")
        self.block_index = diag.get("block_index")
        self.block_type = diag.get("block_type")
        self.block_start = diag.get("block_start")
        self.partial = diag.get("partial", [])


@dataclass
class Block:
    index: int
    type: str
    f: dict = field(default_factory=dict)  # pola specyficzne dla typu

    def __getitem__(self, k):
        return self.f[k]

    def get(self, k, d=None):
        return self.f.get(k, d)


@dataclass
class NifFile:
    version: int
    header: str
    blocks: list[Block]
    roots: list[int]
    trailing: int = 0

    def block(self, ref: int) -> Optional[Block]:
        if ref is None or ref < 0 or ref >= len(self.blocks):
            return None
        return self.blocks[ref]


# ---------------------------------------------------------------------------------------------------
# elementy wspólne
# ---------------------------------------------------------------------------------------------------

class _R(Reader):
    def boolean(self) -> bool:  # < 4.1.0.0 bool zapisany jako int32
        return self.u32() != 0

    def string(self) -> str:
        n = self.count(self.u32())
        return bytes(self.take(n)).decode("cp1252", "replace")

    def ref(self) -> int:
        return self.i32()

    def reflist(self) -> list[int]:
        return [self.i32() for _ in range(self.count(self.u32()))]

    def vec3(self) -> tuple:
        return self.floats(3)

    def mat3(self) -> np.ndarray:
        return np.array(self.floats(9), dtype=np.float64).reshape(3, 3)

    def arr(self, n: int, dtype=np.float32, cols: int = 1) -> np.ndarray:
        size = np.dtype(dtype).itemsize * n * cols
        a = np.frombuffer(self.take(size), dtype=np.dtype(dtype).newbyteorder("<")).astype(dtype)
        return a.reshape(n, cols) if cols > 1 else a


def _objnet(r: _R, f: dict):
    f["name"] = r.string()
    f["extra"] = r.ref()
    f["controller"] = r.ref()


def _bounding_volume(r: _R) -> dict:
    t = r.u32()
    if t == 0xFFFFFFFF:
        return {"type": "base"}
    if t == 0:
        return {"type": "sphere", "center": r.vec3(), "radius": r.f32()}
    if t == 1:
        return {"type": "box", "center": r.vec3(), "axes": r.mat3().tolist(), "extents": r.vec3()}
    if t == 2:
        return {"type": "capsule", "center": r.vec3(), "axis": r.vec3(), "extent": r.f32(), "radius": r.f32()}
    if t == 3:
        return {"type": "lozenge", "radius": r.f32(), "center": r.vec3(), "axis0": r.vec3(), "axis1": r.vec3()}
    if t == 4:
        return {"type": "union", "children": [_bounding_volume(r) for _ in range(r.count(r.u32()))]}
    if t == 5:
        return {"type": "halfspace", "plane": r.floats(4)}
    raise NifError(f"nieobsługiwany typ BoundingVolume {t}")


def _avobject(r: _R, f: dict):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["translation"] = r.vec3()
    f["rotation"] = r.mat3()
    f["scale"] = r.f32()
    f["velocity"] = r.vec3()
    f["properties"] = r.reflist()
    f["bounds"] = _bounding_volume(r) if r.boolean() else None


def _node(r: _R, f: dict):
    _avobject(r, f)
    f["children"] = r.reflist()
    f["effects"] = r.reflist()


def _geometry(r: _R, f: dict):
    _avobject(r, f)
    f["data"] = r.ref()
    f["skin"] = r.ref()


def _geomdata(r: _R, f: dict) -> int:
    n = r.count(r.u16())
    f["num_vertices"] = n
    f["vertices"] = r.arr(n, np.float32, 3) if r.boolean() else None
    f["normals"] = r.arr(n, np.float32, 3) if r.boolean() else None
    f["center"] = r.vec3()
    f["radius"] = r.f32()
    f["colors"] = r.arr(n, np.float32, 4) if r.boolean() else None
    num_uv = r.u16() & 0x3F  # 4.0.0.2: pole "Data Flags" = liczba zestawów UV
    has_uv = r.boolean()
    uvs = []
    if has_uv:
        for _ in range(num_uv):
            uvs.append(r.arr(n, np.float32, 2))
    f["uvs"] = uvs
    return n


def _keygroup(r: _R, ncomp: int, always_interp: bool = False) -> dict:
    """KeyGroup<T>: liczba kluczy, typ interpolacji, klucze (czas, wartość, [styczne|TBC])."""
    count = r.count(r.u32())
    g = {"interp": 0, "times": None, "values": None, "in": None, "out": None, "tbc": None}
    if count == 0 and not always_interp:
        return g
    interp = r.u32()
    g["interp"] = interp
    if count == 0:
        return g
    if interp in (1, 5):  # liniowa, stała
        width = 1 + ncomp
    elif interp == 2:  # kwadratowa (Hermite)
        width = 1 + 3 * ncomp
    elif interp == 3:  # TBC
        width = 1 + ncomp + 3
    else:
        raise NifError(f"nieobsługiwany typ interpolacji {interp} w KeyGroup")
    a = r.arr(count * width, np.float32).reshape(count, width)
    g["times"] = a[:, 0].copy()
    g["values"] = a[:, 1:1 + ncomp].copy()
    if interp == 2:
        # pierwsza styczna używana na wejściu do klucza (przedział k-1→k), druga na wyjściu (k→k+1);
        # styczne odnoszą się do znormalizowanego czasu przedziału [0, 1]
        g["in"] = a[:, 1 + ncomp:1 + 2 * ncomp].copy()
        g["out"] = a[:, 1 + 2 * ncomp:1 + 3 * ncomp].copy()
    if interp == 3:
        g["tbc"] = a[:, 1 + ncomp:].copy()
    return g


def _quatkeys(r: _R) -> dict:
    count = r.count(r.u32())
    g = {"interp": 0, "times": None, "values": None, "xyz": None, "tbc": None}
    if count == 0:
        return g
    interp = r.u32()
    g["interp"] = interp
    if interp == 4:  # XYZ: trzy osobne krzywe kątów
        g["order"] = r.u32()
        g["xyz"] = [_keygroup(r, 1) for _ in range(3)]
        return g
    if interp in (1, 2, 5):
        width = 5
    elif interp == 3:
        width = 8
    else:
        raise NifError(f"nieobsługiwany typ interpolacji obrotu {interp}")
    a = r.arr(count * width, np.float32).reshape(count, width)
    g["times"] = a[:, 0].copy()
    g["values"] = a[:, 1:5].copy()  # w, x, y, z
    if interp == 3:
        g["tbc"] = a[:, 5:8].copy()
    return g


def _timecontroller(r: _R, f: dict):
    f["next"] = r.ref()
    f["flags"] = r.u16()
    f["frequency"] = r.f32()
    f["phase"] = r.f32()
    f["start"] = r.f32()
    f["stop"] = r.f32()
    f["target"] = r.ref()


def _extra(r: _R, f: dict) -> int:
    f["next"] = r.ref()
    return r.u32()  # rozmiar bajtów rekordu (bez pól bazowych)


def _modifier(r: _R, f: dict):
    f["next"] = r.ref()
    f["controller"] = r.ref()


# ---------------------------------------------------------------------------------------------------
# rekordy
# ---------------------------------------------------------------------------------------------------

def _r_node(r, f):
    _node(r, f)


def _r_switch(r, f):
    _node(r, f)
    f["initial_index"] = r.u32()


def _r_lod(r, f):
    _r_switch(r, f)
    f["lod_center"] = r.vec3()
    f["lod_levels"] = [(r.f32(), r.f32()) for _ in range(r.count(r.u32()))]


def _r_flt_anim(r, f):
    _r_switch(r, f)
    f["duration"] = r.f32()


def _r_sort_adjust(r, f):
    _node(r, f)
    f["sorting_mode"] = r.u32()
    f["accumulator"] = r.ref()


def _r_camera(r, f):
    _avobject(r, f)
    f["frustum"] = r.floats(6)
    f["viewport"] = r.floats(4)
    f["lod_adjust"] = r.f32()
    f["scene"] = r.ref()
    f["screen_polygons"] = r.u32()


def _r_geometry(r, f):
    _geometry(r, f)


def _r_trishape_data(r, f):
    _geomdata(r, f)
    f["num_triangles"] = r.u16()
    k = r.count(r.u32())
    idx = r.arr(k, np.uint16)
    f["triangles"] = idx[: len(idx) // 3 * 3].reshape(-1, 3)
    groups = []
    for _ in range(r.count(r.u16())):
        groups.append(r.arr(r.count(r.u16()), np.uint16))
    f["match_groups"] = groups


def _r_tristrips_data(r, f):
    _geomdata(r, f)
    f["num_triangles"] = r.u16()
    ns = r.count(r.u16())
    lengths = [r.u16() for _ in range(ns)]
    f["strips"] = [r.arr(k, np.uint16) for k in lengths]


def _r_lines_data(r, f):
    n = _geomdata(r, f)
    f["connect"] = bytes(r.take(n))


def _r_particles_data(r, f):
    n = _geomdata(r, f)
    f["num_particles"] = r.u16()
    f["particle_radius"] = r.f32()
    f["num_active"] = r.u16()
    f["sizes"] = r.arr(n, np.float32) if r.boolean() else None


def _r_rot_particles_data(r, f):
    _r_particles_data(r, f)
    n = f["num_vertices"]
    f["rotations"] = r.arr(n, np.float32, 4) if r.boolean() else None


def _r_skin_instance(r, f):
    f["data"] = r.ref()
    f["root"] = r.ref()
    f["bones"] = r.reflist()


def _transform(r: _R) -> dict:
    rot = r.mat3()
    trans = r.vec3()
    scale = r.f32()
    return {"rotation": rot, "translation": trans, "scale": scale}


def _r_skin_data(r, f):
    f["transform"] = _transform(r)
    nb = r.count(r.u32())
    f["partition"] = r.ref()
    bones = []
    for _ in range(nb):
        b = {"transform": _transform(r), "sphere_center": r.vec3(), "sphere_radius": r.f32()}
        nv = r.count(r.u16())
        if nv:
            raw = bytes(r.take(6 * nv))
            dt = np.dtype([("index", "<u2"), ("weight", "<f4")])
            w = np.frombuffer(raw, dtype=dt)
            b["indices"] = w["index"].astype(np.int64)
            b["weights"] = w["weight"].astype(np.float32)
        else:
            b["indices"] = np.zeros(0, np.int64)
            b["weights"] = np.zeros(0, np.float32)
        bones.append(b)
    f["bones"] = bones


def _r_skin_partition(r, f):
    parts = []
    for _ in range(r.count(r.u32())):
        nv, nt, nb, ns, bpv = (r.u16() for _ in range(5))
        p = {"bones": r.u16s(nb), "vertex_map": r.u16s(nv)}
        r.skip(4 * nv * bpv)
        lengths = [r.u16() for _ in range(ns)]
        if ns:
            r.skip(2 * sum(lengths))
        else:
            r.skip(6 * nt)
        if r.u8():
            r.skip(nv * bpv)
        parts.append(p)
    f["partitions"] = parts


def _r_flags_prop(r, f):  # Dither, Shade, Specular, Wireframe, ZBuffer
    _objnet(r, f)
    f["flags"] = r.u16()


def _r_alpha(r, f):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["threshold"] = r.u8()


def _r_fog(r, f):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["depth"] = r.f32()
    f["color"] = r.vec3()


def _r_material(r, f):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["ambient"] = r.vec3()
    f["diffuse"] = r.vec3()
    f["specular"] = r.vec3()
    f["emissive"] = r.vec3()
    f["glossiness"] = r.f32()
    f["alpha"] = r.f32()


def _r_stencil(r, f):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["enabled"] = r.u8()
    f["function"] = r.u32()
    f["ref"] = r.u32()
    f["mask"] = r.u32()
    f["fail"] = r.u32()
    f["zfail"] = r.u32()
    f["pass"] = r.u32()
    f["draw_mode"] = r.u32()


TEX_SLOTS = ("base", "dark", "detail", "gloss", "glow", "bump", "decal0", "decal1", "decal2", "decal3")


def _r_texturing(r, f):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["apply_mode"] = r.u32()
    textures = {}
    for i in range(r.count(r.u32())):
        if not r.boolean():
            continue
        t = {"source": r.ref(), "clamp": r.u32(), "filter": r.u32(), "uv_set": r.u32()}
        r.i16()  # PS2 L
        r.i16()  # PS2 K
        r.u16()  # nieznane (≤ 4.1.0.12)
        if i == 5:
            t["luma_scale"] = r.f32()
            t["luma_offset"] = r.f32()
            t["bump_matrix"] = r.floats(4)
        textures[TEX_SLOTS[i] if i < len(TEX_SLOTS) else f"slot{i}"] = t
    f["textures"] = textures


def _r_vertex_color(r, f):
    _objnet(r, f)
    f["flags"] = r.u16()
    f["vertex_mode"] = r.u32()   # 0 ignoruj, 1 emisja, 2 ambient+diffuse
    f["lighting_mode"] = r.u32()  # 0 emisja, 1 emisja+ambient+diffuse


def _r_source_texture(r, f):
    _objnet(r, f)
    f["external"] = r.u8() != 0
    f["file"] = None
    f["pixel_data"] = -1
    if f["external"]:
        f["file"] = r.string()
    else:
        if r.u8():  # "Use Internal"
            f["pixel_data"] = r.ref()
    f["pixel_layout"] = r.u32()
    f["use_mipmaps"] = r.u32()
    f["alpha_format"] = r.u32()
    f["is_static"] = r.u8()


def _r_pixel_data(r, f):
    f["format"] = r.u32()
    f["masks"] = (r.u32(), r.u32(), r.u32(), r.u32())
    f["bpp"] = r.u32()
    r.skip(8)  # fast compare bits
    f["palette"] = r.ref()
    nm = r.count(r.u32())
    f["bytes_per_pixel"] = r.u32()
    f["mipmaps"] = [(r.u32(), r.u32(), r.u32()) for _ in range(nm)]
    n = r.count(r.u32())
    f["pixels"] = bytes(r.take(n))


def _r_palette(r, f):
    f["has_alpha"] = r.u8()
    n = r.count(r.u32())
    f["palette"] = bytes(r.take(4 * n))


def _r_extra_data(r, f):
    n = _extra(r, f)
    f["bytes"] = bytes(r.take(n))


def _r_string_extra(r, f):
    _extra(r, f)
    f["string"] = r.string()


def _r_textkey_extra(r, f):
    _extra(r, f)
    f["keys"] = [(r.f32(), r.string()) for _ in range(r.count(r.u32()))]


def _r_vertweights_extra(r, f):
    _extra(r, f)
    n = r.u16()
    f["weights"] = r.floats(n)


def _dyn_effect(r, f):
    _avobject(r, f)
    f["affected"] = r.reflist()


def _r_light(r, f):
    _dyn_effect(r, f)
    f["dimmer"] = r.f32()
    f["ambient"] = r.vec3()
    f["diffuse"] = r.vec3()
    f["specular"] = r.vec3()


def _r_point_light(r, f):
    _r_light(r, f)
    f["attenuation"] = r.floats(3)


def _r_spot_light(r, f):
    _r_point_light(r, f)
    f["cutoff"] = r.f32()
    f["exponent"] = r.f32()


def _r_texture_effect(r, f):
    _dyn_effect(r, f)
    f["model_projection_matrix"] = r.floats(9)
    f["model_projection_translation"] = r.vec3()
    f["filter"] = r.u32()
    f["clamp"] = r.u32()
    f["effect_type"] = r.u32()
    f["coord_gen"] = r.u32()
    f["source"] = r.ref()
    f["clipping_plane"] = r.u8()
    f["plane"] = r.floats(4)
    f["ps2"] = (r.i16(), r.i16())
    r.u16()


def _r_ctrl_data(r, f):
    _timecontroller(r, f)
    f["data"] = r.ref()


def _r_uv_ctrl(r, f):
    _timecontroller(r, f)
    f["uv_set"] = r.u16()
    f["data"] = r.ref()


def _r_path_ctrl(r, f):
    _timecontroller(r, f)
    f["bank_dir"] = r.i32()
    f["max_bank"] = r.f32()
    f["smoothing"] = r.f32()
    f["follow_axis"] = r.u16()
    f["path_data"] = r.ref()
    f["percent_data"] = r.ref()


def _r_lookat_ctrl(r, f):
    _timecontroller(r, f)
    f["lookat"] = r.ref()


def _r_morpher_ctrl(r, f):
    _timecontroller(r, f)
    f["data"] = r.ref()
    f["always_update"] = r.u8()


def _r_flip_ctrl(r, f):
    _timecontroller(r, f)
    f["texture_slot"] = r.u32()
    f["start_time"] = r.f32()
    f["delta"] = r.f32()
    f["sources"] = r.reflist()


def _r_particle_ctrl(r, f):
    """NiParticleSystemController / NiBSPArrayController (4.0.0.2). Nazwy pól wg nif.xml."""
    _timecontroller(r, f)
    f["speed"] = r.f32()
    f["speed_random"] = r.f32()
    f["vertical_direction"] = r.f32()
    f["vertical_angle"] = r.f32()
    f["horizontal_direction"] = r.f32()
    f["horizontal_angle"] = r.f32()
    f["normal"] = r.vec3()
    f["color"] = r.floats(4)
    f["size"] = r.f32()
    f["emit_start"] = r.f32()
    f["emit_stop"] = r.f32()
    f["unknown_byte"] = r.u8()
    f["emit_rate"] = r.f32()
    f["lifetime"] = r.f32()
    f["lifetime_random"] = r.f32()
    f["emit_flags"] = r.u16()      # bit 0: używaj emit_rate (inaczej liczba cząsteczek / czas)
    f["start_random"] = r.vec3()
    f["emitter"] = r.ref()
    f["unknown_short2"] = r.u16()
    f["unknown_float13"] = r.f32()
    f["unknown_short3"] = r.u16()
    f["unknown_float14"] = r.f32()
    f["unknown_float15"] = r.f32()
    n = r.count(r.u16())
    f["num_particles"] = n
    f["num_valid"] = r.u16()
    r.skip(n * 40)                  # stan cząsteczek (prędkość, czasy, wierzchołek) – nieistotny przy imporcie
    f["unknown_ref"] = r.ref()
    f["particle_modifier"] = r.ref()
    f["particle_collider"] = r.ref()
    f["static_target_bound"] = r.u8()


def _r_keyframe_data(r, f):
    f["rotations"] = _quatkeys(r)
    f["translations"] = _keygroup(r, 3)
    f["scales"] = _keygroup(r, 1)


def _r_float_data(r, f):
    f["keys"] = _keygroup(r, 1)


def _r_pos_data(r, f):
    f["keys"] = _keygroup(r, 3)


def _r_color_data(r, f):
    f["keys"] = _keygroup(r, 4)


def _r_uv_data(r, f):
    f["groups"] = [_keygroup(r, 1) for _ in range(4)]


def _r_vis_data(r, f):
    n = r.count(r.u32())
    f["keys"] = [(r.f32(), r.u8()) for _ in range(n)]


def _r_morph_data(r, f):
    nm = r.count(r.u32())
    nv = r.count(r.u32())
    f["relative"] = r.u8()
    morphs = []
    for _ in range(nm):
        keys = _keygroup(r, 1, always_interp=True)
        verts = r.arr(nv, np.float32, 3)
        morphs.append({"keys": keys, "vertices": verts})
    f["morphs"] = morphs


def _r_grow_fade(r, f):
    _modifier(r, f)
    f["grow"] = r.f32()
    f["fade"] = r.f32()


def _r_color_modifier(r, f):
    _modifier(r, f)
    f["data"] = r.ref()


def _r_gravity(r, f):
    _modifier(r, f)
    f["decay"] = r.f32()
    f["force"] = r.f32()
    f["type"] = r.u32()      # 0 = kierunkowa (wiatr), 1 = punktowa
    f["position"] = r.vec3()
    f["direction"] = r.vec3()


def _r_bomb(r, f):
    _modifier(r, f)
    r.skip(16 + 8 + 24)


def _r_planar_collider(r, f):
    _modifier(r, f)
    r.f32()
    r.skip(8 + 4 * 12 + 4)


def _r_spherical_collider(r, f):
    _modifier(r, f)
    r.f32()
    r.skip(4 + 12)


def _r_rotation_modifier(r, f):
    _modifier(r, f)
    f["random_initial_axis"] = r.u8()
    f["initial_axis"] = r.vec3()
    f["rotation_speed"] = r.f32()


def _r_nothing(r, f):
    pass


def _r_objnet(r, f):
    _objnet(r, f)


READERS = {
    "NiNode": _r_node, "AvoidNode": _r_node, "NiBillboardNode": _r_node, "NiBSAnimationNode": _r_node,
    "NiBSParticleNode": _r_node, "NiCollisionSwitch": _r_node, "RootCollisionNode": _r_node,
    "NiSortAdjustNode": _r_sort_adjust, "NiSwitchNode": _r_switch, "NiFltAnimationNode": _r_flt_anim,
    "NiLODNode": _r_lod, "NiSequenceStreamHelper": _r_objnet, "NiCamera": _r_camera,
    "NiAlphaAccumulator": _r_nothing, "NiClusterAccumulator": _r_nothing,
    "NiAlphaController": _r_ctrl_data, "NiBSPArrayController": _r_particle_ctrl, "NiFlipController": _r_flip_ctrl,
    "NiGeomMorpherController": _r_morpher_ctrl, "NiKeyframeController": _r_ctrl_data,
    "NiLookAtController": _r_lookat_ctrl, "NiLightColorController": _r_ctrl_data,
    "NiMaterialColorController": _r_ctrl_data, "NiPathController": _r_path_ctrl, "NiRollController": _r_ctrl_data,
    "NiUVController": _r_uv_ctrl, "NiVisController": _r_ctrl_data, "NiParticleSystemController": _r_particle_ctrl,
    "NiColorData": _r_color_data, "NiFloatData": _r_float_data, "NiKeyframeData": _r_keyframe_data,
    "NiMorphData": _r_morph_data, "NiPalette": _r_palette, "NiPixelData": _r_pixel_data, "NiPosData": _r_pos_data,
    "NiSourceTexture": _r_source_texture, "NiUVData": _r_uv_data, "NiVisData": _r_vis_data,
    "NiAmbientLight": _r_light, "NiDirectionalLight": _r_light, "NiPointLight": _r_point_light,
    "NiSpotLight": _r_spot_light, "NiTextureEffect": _r_texture_effect,
    "NiExtraData": _r_extra_data, "NiStringExtraData": _r_string_extra, "NiTextKeyExtraData": _r_textkey_extra,
    "NiVertWeightsExtraData": _r_vertweights_extra,
    "NiLines": _r_geometry, "NiLinesData": _r_lines_data, "NiSkinData": _r_skin_data,
    "NiSkinInstance": _r_skin_instance, "NiSkinPartition": _r_skin_partition,
    "NiTriShape": _r_geometry, "NiTriShapeData": _r_trishape_data, "NiTriStrips": _r_geometry,
    "NiTriStripsData": _r_tristrips_data,
    "NiAutoNormalParticles": _r_geometry, "NiAutoNormalParticlesData": _r_particles_data,
    "NiParticles": _r_geometry, "NiParticlesData": _r_particles_data, "NiRotatingParticles": _r_geometry,
    "NiRotatingParticlesData": _r_rot_particles_data,
    "NiGravity": _r_gravity, "NiParticleBomb": _r_bomb, "NiParticleColorModifier": _r_color_modifier,
    "NiParticleGrowFade": _r_grow_fade, "NiParticleRotation": _r_rotation_modifier,
    "NiPlanarCollider": _r_planar_collider, "NiSphericalCollider": _r_spherical_collider,
    "NiAlphaProperty": _r_alpha, "NiDitherProperty": _r_flags_prop, "NiFogProperty": _r_fog,
    "NiMaterialProperty": _r_material, "NiShadeProperty": _r_flags_prop,
    "NiSpecularProperty": _r_flags_prop, "NiStencilProperty": _r_stencil, "NiTexturingProperty": _r_texturing,
    "NiVertexColorProperty": _r_vertex_color, "NiWireframeProperty": _r_flags_prop,
    "NiZBufferProperty": _r_flags_prop,
}

NODE_TYPES = {"NiNode", "AvoidNode", "NiBillboardNode", "NiBSAnimationNode", "NiBSParticleNode",
              "NiCollisionSwitch", "RootCollisionNode", "NiSortAdjustNode", "NiSwitchNode",
              "NiFltAnimationNode", "NiLODNode"}
TRI_TYPES = {"NiTriShape", "NiTriStrips"}
PARTICLE_TYPES = {"NiAutoNormalParticles", "NiParticles", "NiRotatingParticles"}
AV_TYPES = NODE_TYPES | TRI_TYPES | PARTICLE_TYPES | {"NiLines", "NiCamera", "NiAmbientLight",
                                                      "NiDirectionalLight", "NiPointLight", "NiSpotLight",
                                                      "NiTextureEffect"}


def parse(data: bytes, name: str = "<nif>") -> NifFile:
    """Pełny odczyt pliku NIF 4.0.0.x. Błąd formatu ⇒ NifError z nazwą pliku i numerem bloku."""
    if not data:
        raise NifError(f"{name}: pusty plik")
    nl = bytes(data[:128]).find(b"\n")
    head = bytes(data[:max(nl, 0)]).decode("latin-1", "replace")
    if nl < 0 or not (head.startswith("NetImmerse File Format") or head.startswith("Gamebryo File Format")):
        raise NifError(f"{name}: brak nagłówka NIF")
    r = _R(data, name, nl + 1)
    blocks: list[Block] = []
    cur = {"i": None, "t": None, "start": None}

    def fail(msg):
        return NifError(f"{name}: {msg}", offset=r.pos, block_index=cur["i"], block_type=cur["t"],
                        block_start=cur["start"], partial=blocks)
    try:
        version = r.u32()
        if version not in (VER_4002, VER_4000):
            raise NifError(f"nieobsługiwana wersja NIF 0x{version:08x} (obsługiwane: 4.0.0.2, 4.0.0.0)")
        n = r.count(r.u32())
        for i in range(n):
            start = r.pos
            cur.update(i=i, t=None, start=start)
            t = r.string()
            cur["t"] = t
            fn = READERS.get(t)
            if fn is None:
                if not (t.isprintable() and t.startswith(("Ni", "Root", "Avoid", "BS"))):
                    raise NifError(f"śmieci zamiast nazwy typu bloku {i} na offsecie {start} "
                                   f"(poprzedni blok {blocks[-1].type if blocks else '-'} odczytany za krótko/za długo?)")
                raise NifError(f"nieznany typ bloku {t!r} (blok {i}, offset {start})")
            b = Block(i, t)
            try:
                fn(r, b.f)
            except (FormatError, NifError) as e:
                raise NifError(f"blok {i} {t}: {e}") from None
            blocks.append(b)
        cur.update(i=None, t="(lista korzeni)", start=r.pos)
        roots = [r.i32() for _ in range(r.count(r.u32()))]
        trailing = r.remaining()
    except (FormatError, NifError) as e:
        raise fail(str(e).replace(name + ": ", "")) from None
    return NifFile(version, head, blocks, [i for i in roots if 0 <= i < len(blocks)], trailing)


def read_file(path) -> NifFile:
    with open(path, "rb") as fh:
        return parse(fh.read(), str(path))


def strips_to_triangles(strips) -> np.ndarray:
    out = []
    for s in strips:
        s = [int(x) for x in s]
        for i in range(2, len(s)):
            a, b, c = s[i - 2], s[i - 1], s[i]
            if a == b or b == c or a == c:
                continue
            out.append((a, b, c) if i % 2 == 0 else (a, c, b))
    return np.array(out, dtype=np.uint32).reshape(-1, 3)


def extra_chain(nf: NifFile, ref: int) -> list[Block]:
    out, seen = [], set()
    while ref is not None and ref >= 0 and ref not in seen:
        seen.add(ref)
        b = nf.block(ref)
        if b is None:
            break
        out.append(b)
        ref = b.get("next", -1)
    return out


def controller_chain(nf: NifFile, ref: int) -> list[Block]:
    return extra_chain(nf, ref)
