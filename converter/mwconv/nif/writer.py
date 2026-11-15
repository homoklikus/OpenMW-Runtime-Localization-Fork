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
    if not rot or rot.get("times") is None:
        w.u32(0)
    else:
        times = np.asarray(rot["times"], np.float32)
        q = np.asarray(rot["values"], np.float32).reshape(-1, 4)
        w.u32(len(times))
        w.u32(rot.get("interp", 1))
        for i, t in enumerate(times):
            w.f32(float(t))
            w.floats(q[i].tolist())
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
}
