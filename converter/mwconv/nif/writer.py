"""Zapis plików NIF 4.0.0.2 — wyłącznie do tworzenia własnych, syntetycznych modeli testowych.

Obsługuje podzbiór bloków używany przez testy (węzły, geometria, właściwości, kontrolery klatek
kluczowych, skin, dane dodatkowe). Układ pól jest lustrzanym odbiciem `reader.py`.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from ..binio import Writer

HEADER = b"NetImmerse File Format, Version 4.0.0.2\n"
VERSION = 0x04000002


class NifBuilder:
    def __init__(self):
        self.blocks: list[tuple[str, dict]] = []
        self.roots: list[int] = []

    def add(self, type_: str, **fields) -> int:
        self.blocks.append((type_, fields))
        return len(self.blocks) - 1

    def set(self, idx: int, **fields):
        self.blocks[idx][1].update(fields)

    def to_bytes(self) -> bytes:
        w = Writer()
        w.raw(HEADER)
        w.u32(VERSION)
        w.u32(len(self.blocks))
        for t, f in self.blocks:
            _str(w, t)
            fn = WRITERS[t]
            fn(w, f)
        roots = self.roots or [0]
        w.u32(len(roots))
        for r in roots:
            w.i32(r)
        return w.getvalue()

    def save(self, path):
        with open(path, "wb") as fh:
            fh.write(self.to_bytes())


# --- elementy ------------------------------------------------------------------------------------

def _str(w: Writer, s: str):
    b = s.encode("cp1252")
    w.u32(len(b)).raw(b)


def _reflist(w: Writer, refs):
    refs = list(refs or [])
    w.u32(len(refs))
    for r in refs:
        w.i32(r)


def _bool(w: Writer, v: bool):
    w.u32(1 if v else 0)


def _objnet(w: Writer, f: dict):
    _str(w, f.get("name", ""))
    w.i32(f.get("extra", -1))
    w.i32(f.get("controller", -1))


def _mat3(w: Writer, m):
    m = np.eye(3) if m is None else np.asarray(m, dtype=np.float64)
    w.floats(m.reshape(9).tolist())


def _avobject(w: Writer, f: dict):
    _objnet(w, f)
    w.u16(f.get("flags", 0x0C))
    w.floats(f.get("translation", (0, 0, 0)))
    _mat3(w, f.get("rotation"))
    w.f32(f.get("scale", 1.0))
    w.floats(f.get("velocity", (0, 0, 0)))
    _reflist(w, f.get("properties"))
    bounds = f.get("bounds")
    if bounds is None:
        _bool(w, False)
    else:  # tylko box
        _bool(w, True)
        w.u32(1)
        w.floats(bounds["center"])
        _mat3(w, bounds.get("axes"))
        w.floats(bounds["extents"])


def _w_node(w, f):
    _avobject(w, f)
    _reflist(w, f.get("children"))
    _reflist(w, f.get("effects"))


def _w_geometry(w, f):
    _avobject(w, f)
    w.i32(f.get("data", -1))
    w.i32(f.get("skin", -1))


def _geomdata(w: Writer, f: dict):
    v = np.asarray(f["vertices"], dtype=np.float32)
    n = len(v)
    w.u16(n)
    _bool(w, True)
    w.raw(v.astype("<f4").tobytes())
    nrm = f.get("normals")
    _bool(w, nrm is not None)
    if nrm is not None:
        w.raw(np.asarray(nrm, dtype="<f4").tobytes())
    c = v.mean(axis=0) if n else np.zeros(3)
    rad = float(np.max(np.linalg.norm(v - c, axis=1))) if n else 0.0
    w.floats(c.tolist())
    w.f32(rad)
    col = f.get("colors")
    _bool(w, col is not None)
    if col is not None:
        w.raw(np.asarray(col, dtype="<f4").tobytes())
    uvs = f.get("uvs") or []
    w.u16(len(uvs))
    _bool(w, len(uvs) > 0)
    for uv in uvs:
        w.raw(np.asarray(uv, dtype="<f4").tobytes())


def _w_trishape_data(w, f):
    _geomdata(w, f)
    tris = np.asarray(f["triangles"], dtype="<u2").reshape(-1, 3)
    w.u16(len(tris))
    w.u32(tris.size)
    w.raw(tris.tobytes())
    w.u16(0)  # grupy dopasowań


def _w_tristrips_data(w, f):
    _geomdata(w, f)
    strips = [np.asarray(s, dtype="<u2") for s in f["strips"]]
    w.u16(sum(max(0, len(s) - 2) for s in strips))
    w.u16(len(strips))
    for s in strips:
        w.u16(len(s))
    for s in strips:
        w.raw(s.tobytes())


def _w_texturing(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 0))
    w.u32(f.get("apply_mode", 2))
    slots = f.get("textures", {})
    order = ("base", "dark", "detail", "gloss", "glow", "bump", "decal0")
    w.u32(7)
    for i, name in enumerate(order):
        t = slots.get(name)
        _bool(w, t is not None)
        if t is None:
            continue
        w.i32(t["source"])
        w.u32(t.get("clamp", 3))
        w.u32(t.get("filter", 2))
        w.u32(t.get("uv_set", 0))
        w.i16(0)
        w.i16(0)
        w.u16(0)
        if i == 5:
            w.f32(1.0)
            w.f32(0.0)
            w.floats((1, 0, 0, 1))


def _w_source_texture(w, f):
    _objnet(w, f)
    if f.get("pixel_data", -1) >= 0:
        w.u8(0)
        w.u8(1)
        w.i32(f["pixel_data"])
    else:
        w.u8(1)
        _str(w, f["file"])
    w.u32(f.get("pixel_layout", 5))
    w.u32(f.get("use_mipmaps", 2))
    w.u32(f.get("alpha_format", 3))
    w.u8(1)


def _w_material(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 1))
    w.floats(f.get("ambient", (1, 1, 1)))
    w.floats(f.get("diffuse", (1, 1, 1)))
    w.floats(f.get("specular", (0, 0, 0)))
    w.floats(f.get("emissive", (0, 0, 0)))
    w.f32(f.get("glossiness", 10.0))
    w.f32(f.get("alpha", 1.0))


def _w_alpha(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 0x12ED))
    w.u8(f.get("threshold", 128))


def _w_stencil(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 0))
    w.u8(f.get("enabled", 0))
    for k, d in (("function", 0), ("ref", 0), ("mask", 0xFFFFFFFF), ("fail", 0), ("zfail", 0), ("pass", 0)):
        w.u32(f.get(k, d))
    w.u32(f.get("draw_mode", 3))


def _w_vertex_color(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 0))
    w.u32(f.get("vertex_mode", 2))
    w.u32(f.get("lighting_mode", 1))


def _w_flags_prop(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 0))


def _timecontroller(w: Writer, f: dict):
    w.i32(f.get("next", -1))
    w.u16(f.get("flags", 0x08))
    w.f32(f.get("frequency", 1.0))
    w.f32(f.get("phase", 0.0))
    w.f32(f.get("start", 0.0))
    w.f32(f.get("stop", 1.0))
    w.i32(f["target"])


def _w_ctrl_data(w, f):
    _timecontroller(w, f)
    w.i32(f.get("data", -1))


def _keygroup(w: Writer, g: dict | None, ncomp: int):
    if not g or g.get("times") is None or len(g["times"]) == 0:
        w.u32(0)
        return
    times = np.asarray(g["times"], dtype=np.float32)
    vals = np.asarray(g["values"], dtype=np.float32).reshape(len(times), ncomp)
    interp = g.get("interp", 1)
    w.u32(len(times))
    w.u32(interp)
    for i, t in enumerate(times):
        w.f32(float(t))
        w.floats(vals[i].tolist())
        if interp == 2:
            w.floats(np.asarray(g["in"], np.float32).reshape(-1, ncomp)[i].tolist())
            w.floats(np.asarray(g["out"], np.float32).reshape(-1, ncomp)[i].tolist())
        elif interp == 3:
            w.floats(np.asarray(g["tbc"], np.float32).reshape(-1, 3)[i].tolist())


def _w_keyframe_data(w, f):
    rot = f.get("rotations")
    if rot and rot.get("interp") == 4:
        w.u32(1)  # liczba kluczy ≠ 0 (w trybie XYZ wartość nieużywana)
        w.u32(4)
        w.u32(rot.get("order", 0))
        for g in rot["xyz"]:
            _keygroup(w, g, 1)
    elif not rot or rot.get("times") is None:
        w.u32(0)
    else:
        times = np.asarray(rot["times"], np.float32)
        q = np.asarray(rot["values"], np.float32).reshape(-1, 4)
        w.u32(len(times))
        w.u32(rot.get("interp", 1))
        for i, t in enumerate(times):
            w.f32(float(t))
            w.floats(q[i].tolist())
            if rot.get("interp", 1) == 3:
                w.floats(np.asarray(rot["tbc"], np.float32).reshape(-1, 3)[i].tolist())
    _keygroup(w, f.get("translations"), 3)
    _keygroup(w, f.get("scales"), 1)


def _w_vis_data(w, f):
    keys = f.get("keys", [])
    w.u32(len(keys))
    for t, v in keys:
        w.f32(t)
        w.u8(v)


def _w_string_extra(w, f):
    w.i32(f.get("next", -1))
    s = f["string"].encode("cp1252")
    w.u32(4 + len(s))
    w.u32(len(s)).raw(s)


def _w_textkey_extra(w, f):
    w.i32(f.get("next", -1))
    w.u32(0)
    keys = f.get("keys", [])
    w.u32(len(keys))
    for t, s in keys:
        w.f32(t)
        _str(w, s)


def _transform(w: Writer, t: dict):
    _mat3(w, t.get("rotation"))
    w.floats(t.get("translation", (0, 0, 0)))
    w.f32(t.get("scale", 1.0))


def _w_skin_instance(w, f):
    w.i32(f["data"])
    w.i32(f["root"])
    _reflist(w, f["bones"])


def _w_skin_data(w, f):
    _transform(w, f.get("transform", {}))
    bones = f["bones"]
    w.u32(len(bones))
    w.i32(-1)  # partycja
    for b in bones:
        _transform(w, b["transform"])
        w.floats(b.get("sphere_center", (0, 0, 0)))
        w.f32(b.get("sphere_radius", 1.0))
        idx = list(b["indices"])
        wt = list(b["weights"])
        w.u16(len(idx))
        for i, x in zip(idx, wt):
            w.u16(int(i))
            w.f32(float(x))


def _w_switch(w, f):
    _w_node(w, f)
    w.u32(f.get("initial_index", 0))


def _w_lod(w, f):
    _w_switch(w, f)
    w.floats(f.get("lod_center", (0, 0, 0)))
    lv = f.get("lod_levels", [])
    w.u32(len(lv))
    for a, b in lv:
        w.f32(a)
        w.f32(b)


def _w_flt_anim(w, f):
    _w_switch(w, f)
    w.f32(f.get("duration", 1.0))


def _w_sort_adjust(w, f):
    _w_node(w, f)
    w.u32(f.get("sorting_mode", 0))
    w.i32(f.get("accumulator", -1))


def _w_camera(w, f):
    _avobject(w, f)
    w.floats(f.get("frustum", (-1, 1, 1, -1, 1, 1000)))
    w.floats(f.get("viewport", (0, 1, 1, 0)))
    w.f32(1.0)
    w.i32(-1)
    w.u32(0)


def _w_particles_data(w, f, rotating=False):
    _geomdata(w, f)
    n = len(f["vertices"])
    w.u16(f.get("num_particles", n))
    w.f32(f.get("particle_radius", 8.0))
    w.u16(f.get("num_active", n))
    sizes = f.get("sizes")
    _bool(w, sizes is not None)
    if sizes is not None:
        w.floats(sizes)
    if rotating:
        _bool(w, False)


def _w_rot_particles_data(w, f):
    _w_particles_data(w, f, rotating=True)


def _w_particle_ctrl(w, f):
    _timecontroller(w, f)
    for k, d in (("speed", 50.0), ("speed_random", 10.0), ("vertical_direction", 0.0), ("vertical_angle", 0.3),
                 ("horizontal_direction", 0.0), ("horizontal_angle", 3.14159)):
        w.f32(f.get(k, d))
    w.floats(f.get("normal", (0, 0, 1)))
    w.floats(f.get("color", (1, 1, 1, 1)))
    w.f32(f.get("size", 10.0))
    w.f32(f.get("emit_start", 0.0))
    w.f32(f.get("emit_stop", 10.0))
    w.u8(0)
    w.f32(f.get("emit_rate", 20.0))
    w.f32(f.get("lifetime", 2.0))
    w.f32(f.get("lifetime_random", 0.5))
    w.u16(f.get("emit_flags", 1))
    w.floats(f.get("start_random", (4, 4, 0)))
    w.i32(f.get("emitter", -1))
    w.u16(0)
    w.f32(0.0)
    w.u16(0)
    w.f32(0.0)
    w.f32(0.0)
    n = f.get("num_particles", 3)
    w.u16(n)
    w.u16(n)
    w.raw(b"\0" * (40 * n))
    w.i32(-1)
    w.i32(f.get("particle_modifier", -1))
    w.i32(f.get("particle_collider", -1))
    w.u8(0)


def _modifier_w(w, f):
    w.i32(f.get("next", -1))
    w.i32(f.get("controller", -1))


def _w_gravity(w, f):
    _modifier_w(w, f)
    w.f32(f.get("decay", 0.0))
    w.f32(f.get("force", 1.0))
    w.u32(f.get("type", 0))
    w.floats(f.get("position", (0, 0, 0)))
    w.floats(f.get("direction", (0, 0, -1)))


def _w_grow_fade(w, f):
    _modifier_w(w, f)
    w.f32(f.get("grow", 0.2))
    w.f32(f.get("fade", 0.5))


def _w_color_modifier(w, f):
    _modifier_w(w, f)
    w.i32(f.get("data", -1))


def _w_rotation_modifier(w, f):
    _modifier_w(w, f)
    w.u8(0)
    w.floats((0, 0, 1))
    w.f32(f.get("rotation_speed", 1.0))


def _w_planar_collider(w, f):
    _modifier_w(w, f)
    w.f32(0.5)
    w.raw(b"\0" * (8 + 4 * 12 + 4))


def _w_spherical_collider(w, f):
    _modifier_w(w, f)
    w.f32(0.5)
    w.raw(b"\0" * 16)


def _w_bomb(w, f):
    _modifier_w(w, f)
    w.raw(b"\0" * (16 + 8 + 24))


def _w_keys_data(ncomp):
    def fn(w, f):
        _keygroup(w, f.get("keys"), ncomp)
    return fn


def _w_uv_data(w, f):
    groups = f.get("groups", [None] * 4)
    for g in groups:
        _keygroup(w, g, 1)


def _w_uv_ctrl(w, f):
    _timecontroller(w, f)
    w.u16(f.get("uv_set", 0))
    w.i32(f.get("data", -1))


def _w_flip_ctrl(w, f):
    _timecontroller(w, f)
    w.u32(f.get("texture_slot", 0))
    w.f32(f.get("start_time", 0.0))
    w.f32(f.get("delta", 0.25))
    _reflist(w, f.get("sources", []))


def _w_morpher_ctrl(w, f):
    _timecontroller(w, f)
    w.i32(f.get("data", -1))
    w.u8(0)


def _w_morph_data(w, f):
    morphs = f["morphs"]
    nv = len(morphs[0]["vertices"]) if morphs else 0
    w.u32(len(morphs))
    w.u32(nv)
    w.u8(f.get("relative", 1))
    for m in morphs:
        k = m.get("keys") or {}
        if not k or k.get("times") is None:
            w.u32(0)
            w.u32(1)
        else:
            _keygroup(w, k, 1)
        w.raw(np.asarray(m["vertices"], "<f4").tobytes())


def _w_path_ctrl(w, f):
    _timecontroller(w, f)
    w.i32(0)
    w.f32(0.0)
    w.f32(0.0)
    w.u16(0)
    w.i32(f.get("path_data", -1))
    w.i32(f.get("percent_data", -1))


def _w_lookat_ctrl(w, f):
    _timecontroller(w, f)
    w.i32(f.get("lookat", -1))


def _dyn_effect_w(w, f):
    _avobject(w, f)
    _reflist(w, f.get("affected", []))


def _w_light(w, f):
    _dyn_effect_w(w, f)
    w.f32(f.get("dimmer", 1.0))
    w.floats(f.get("ambient", (0, 0, 0)))
    w.floats(f.get("diffuse", (1, 0.8, 0.5)))
    w.floats(f.get("specular", (0, 0, 0)))


def _w_point_light(w, f):
    _w_light(w, f)
    w.floats(f.get("attenuation", (0, 1, 0)))


def _w_spot_light(w, f):
    _w_point_light(w, f)
    w.f32(f.get("cutoff", 45.0))
    w.f32(f.get("exponent", 1.0))


def _w_texture_effect(w, f):
    _dyn_effect_w(w, f)
    _mat3(w, None)
    w.floats((0, 0, 0))
    w.u32(2)
    w.u32(3)
    w.u32(0)
    w.u32(0)
    w.i32(f.get("source", -1))
    w.u8(0)
    w.floats((0, 0, 1, 0))
    w.i16(0)
    w.i16(0)
    w.u16(0)


def _w_objnet_only(w, f):
    _objnet(w, f)


def _w_extra_data(w, f):
    w.i32(f.get("next", -1))
    b = f.get("bytes", b"")
    w.u32(len(b)).raw(b)


def _w_vertweights_extra(w, f):
    w.i32(f.get("next", -1))
    wt = list(f.get("weights", []))
    w.u32(2 + 4 * len(wt))
    w.u16(len(wt))
    w.floats(wt)


def _w_fog(w, f):
    _objnet(w, f)
    w.u16(f.get("flags", 1))
    w.f32(f.get("depth", 1.0))
    w.floats(f.get("color", (0.5, 0.5, 0.5)))


def _w_pixel_data(w, f):
    pix = f["pixels"]
    w.u32(f.get("format", 1))  # RGBA
    w.u32(0x000000FF).u32(0x0000FF00).u32(0x00FF0000).u32(0xFF000000)
    w.u32(32)
    w.raw(b"\0" * 8)
    w.i32(-1)
    mips = f.get("mipmaps", [(f["width"], f["height"], 0)])
    w.u32(len(mips))
    w.u32(4)
    for m in mips:
        w.u32(m[0]).u32(m[1]).u32(m[2])
    w.u32(len(pix)).raw(pix)


def _w_lines_data(w, f):
    _geomdata(w, f)
    w.raw(bytes([1] * len(f["vertices"])))


def _w_nothing(w, f):
    pass


WRITERS: dict[str, Any] = {
    "NiNode": _w_node, "RootCollisionNode": _w_node, "NiBSAnimationNode": _w_node, "AvoidNode": _w_node,
    "NiBillboardNode": _w_node,
    "NiTriShape": _w_geometry, "NiTriStrips": _w_geometry,
    "NiTriShapeData": _w_trishape_data, "NiTriStripsData": _w_tristrips_data,
    "NiTexturingProperty": _w_texturing, "NiSourceTexture": _w_source_texture,
    "NiMaterialProperty": _w_material, "NiAlphaProperty": _w_alpha, "NiStencilProperty": _w_stencil,
    "NiVertexColorProperty": _w_vertex_color, "NiZBufferProperty": _w_flags_prop,
    "NiKeyframeController": _w_ctrl_data, "NiKeyframeData": _w_keyframe_data,
    "NiVisController": _w_ctrl_data, "NiVisData": _w_vis_data,
    "NiStringExtraData": _w_string_extra, "NiTextKeyExtraData": _w_textkey_extra,
    "NiSkinInstance": _w_skin_instance, "NiSkinData": _w_skin_data,
    "NiSwitchNode": _w_switch, "NiLODNode": _w_lod, "NiFltAnimationNode": _w_flt_anim,
    "NiSortAdjustNode": _w_sort_adjust, "NiCollisionSwitch": _w_node, "NiBSParticleNode": _w_node,
    "NiCamera": _w_camera,
    "NiAutoNormalParticles": _w_geometry, "NiRotatingParticles": _w_geometry, "NiParticles": _w_geometry,
    "NiAutoNormalParticlesData": _w_particles_data, "NiParticlesData": _w_particles_data,
    "NiRotatingParticlesData": _w_rot_particles_data,
    "NiParticleSystemController": _w_particle_ctrl, "NiBSPArrayController": _w_particle_ctrl,
    "NiGravity": _w_gravity, "NiParticleGrowFade": _w_grow_fade, "NiParticleColorModifier": _w_color_modifier,
    "NiParticleRotation": _w_rotation_modifier, "NiPlanarCollider": _w_planar_collider,
    "NiSphericalCollider": _w_spherical_collider, "NiParticleBomb": _w_bomb,
    "NiColorData": _w_keys_data(4), "NiFloatData": _w_keys_data(1), "NiPosData": _w_keys_data(3),
    "NiUVData": _w_uv_data, "NiUVController": _w_uv_ctrl,
    "NiAlphaController": _w_ctrl_data, "NiMaterialColorController": _w_ctrl_data, "NiRollController": _w_ctrl_data,
    "NiLightColorController": _w_ctrl_data, "NiFlipController": _w_flip_ctrl,
    "NiGeomMorpherController": _w_morpher_ctrl, "NiMorphData": _w_morph_data,
    "NiPathController": _w_path_ctrl, "NiLookAtController": _w_lookat_ctrl,
    "NiPointLight": _w_point_light, "NiSpotLight": _w_spot_light, "NiAmbientLight": _w_light,
    "NiDirectionalLight": _w_light, "NiTextureEffect": _w_texture_effect,
    "NiSequenceStreamHelper": _w_objnet_only, "NiExtraData": _w_extra_data,
    "NiVertWeightsExtraData": _w_vertweights_extra,
    "NiSpecularProperty": _w_flags_prop, "NiWireframeProperty": _w_flags_prop, "NiDitherProperty": _w_flags_prop,
    "NiShadeProperty": _w_flags_prop, "NiFogProperty": _w_fog, "NiPixelData": _w_pixel_data,
    "NiLines": _w_geometry, "NiLinesData": _w_lines_data,
    "NiAlphaAccumulator": _w_nothing, "NiClusterAccumulator": _w_nothing,
}
