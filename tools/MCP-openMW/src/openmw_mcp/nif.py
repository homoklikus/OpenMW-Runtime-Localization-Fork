"""Odczyt modeli NIF Morrowinda (NetImmerse 4.0.0.2 / 4.0.0.0) i geometria potrzebna do analizy widoczności.

Układ rekordów przeniesiony 1:1 z `components/nif/*.cpp` OpenMW 0.51.0 (gałąź wersji ≤ 4.0.0.2; pola nowszych
wersji pominięte). Format 4.0.0.2 nie zapisuje rozmiarów rekordów, więc każdy rekord musi być odczytany w całości —
nieznany typ kończy odczyt błędem `NifError` (bez zgadywania).

Reguły tego, co silnik rysuje (`components/nifosg/nifloader.cpp`):
* poddrzewo RootCollisionNode — tylko kolizja, bez siatek;
* węzeł z flagą Hidden (0x1) bez NiVisController — bez siatek w poddrzewie;
* NiStringExtraData "MRK" w korzeniu ⇒ pomijane siatki "tri editormarker*"; zawsze pomijane "shadow*", "tri shadow*";
* NiSwitchNode — widoczne tylko dziecko `initial index`; NiLODNode — do analizy pierwszy poziom (najbliższy);
* cząsteczki (NiParticles…) nie zasłaniają (silnik pomija je też w `getCullSafeBoundingBox`);
* transformacja korzenia (rekord 0, NiNode) jest zerowana, chyba że węzeł nazywa się "Bip01" (node.cpp).

Transformacja węzła: p_rodzic = t + s · R · p (R z 9 liczb wierszami — NiTransform::toMatrix).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

VER_MW = 0x04000002
VER_4000 = 0x04000000
MAX_COUNT = 5_000_000            # ochrona przed uszkodzonymi plikami (liczniki z kosmosu)


class NifError(Exception):
    pass


class _R:
    """Strumień little-endian z kontrolą końca danych."""

    __slots__ = ("b", "p", "n")

    def __init__(self, data: bytes):
        self.b = memoryview(data)
        self.p = 0
        self.n = len(data)

    def _take(self, k: int) -> memoryview:
        if k < 0 or self.p + k > self.n:
            raise NifError(f"koniec danych (pozycja {self.p}, potrzeba {k} B, rozmiar {self.n})")
        v = self.b[self.p:self.p + k]
        self.p += k
        return v

    def skip(self, k: int):
        self._take(k)

    def u8(self) -> int:
        return self._take(1)[0]

    def u16(self) -> int:
        return struct.unpack_from("<H", self._take(2))[0]

    def u32(self) -> int:
        return struct.unpack_from("<I", self._take(4))[0]

    def i32(self) -> int:
        return struct.unpack_from("<i", self._take(4))[0]

    def f32(self) -> float:
        return struct.unpack_from("<f", self._take(4))[0]

    def count(self, v: int) -> int:
        if v > MAX_COUNT:
            raise NifError(f"podejrzany licznik {v} (pozycja {self.p})")
        return v

    def floats(self, k: int) -> np.ndarray:
        return np.frombuffer(self._take(4 * k), dtype="<f4").astype(np.float64)

    def u16s(self, k: int) -> np.ndarray:
        return np.frombuffer(self._take(2 * k), dtype="<u2").astype(np.int64)

    def vec3(self) -> tuple[float, float, float]:
        return struct.unpack_from("<3f", self._take(12))

    def mat3(self) -> np.ndarray:
        return self.floats(9).reshape(3, 3)

    def boolean(self) -> bool:                 # wersja < 4.1.0.0: int32
        return self.i32() != 0

    def string(self) -> str:
        k = self.count(self.u32())
        raw = bytes(self._take(k))
        end = raw.find(b"\0")
        return (raw if end < 0 else raw[:end]).decode("latin-1")

    def ref(self) -> int:
        return self.i32()

    def reflist(self) -> list[int]:
        return [self.i32() for _ in range(self.count(self.u32()))]


@dataclass
class Rec:
    index: int
    type: str
    name: str = ""
    extra: int = -1
    controller: int = -1
    flags: int = 0
    trans: tuple = (0.0, 0.0, 0.0)
    rot: Optional[np.ndarray] = None
    scale: float = 1.0
    props: list = field(default_factory=list)
    bounds: Optional[dict] = None
    children: list = field(default_factory=list)
    data: int = -1
    skin: int = -1
    next: int = -1
    target: int = -1
    initial_index: int = 0
    lod_levels: list = field(default_factory=list)
    text: str = ""
    # dane geometrii
    vertices: Optional[np.ndarray] = None
    sphere: Optional[tuple] = None
    triangles: Optional[np.ndarray] = None
    strips: list = field(default_factory=list)
    # NiAlphaProperty
    alpha_flags: int = 0


# --- elementy wspólne -----------------------------------------------------------------------------------

def _objnet(r: _R, o: Rec):
    o.name = r.string()
    o.extra = r.ref()
    o.controller = r.ref()


def _bounding_volume(r: _R) -> dict:
    t = r.u32()
    if t == 0xFFFFFFFF:
        return {"type": "base"}
    if t == 0:
        c = r.vec3()
        return {"type": "sphere", "center": c, "radius": r.f32()}
    if t == 1:
        c = r.vec3()
        axes = r.mat3()
        ext = r.vec3()
        return {"type": "box", "center": c, "axes": axes.tolist(), "extents": ext}
    if t == 2:
        c, a = r.vec3(), r.vec3()
        return {"type": "capsule", "center": c, "axis": a, "extent": r.f32(), "radius": r.f32()}
    if t == 3:
        rad = r.f32()
        return {"type": "lozenge", "radius": rad, "center": r.vec3(), "axis0": r.vec3(), "axis1": r.vec3()}
    if t == 4:
        return {"type": "union", "children": [_bounding_volume(r) for _ in range(r.count(r.u32()))]}
    if t == 5:
        r.skip(16)
        return {"type": "halfspace"}
    raise NifError(f"nieobsługiwany typ BoundingVolume {t}")


def _avobject(r: _R, o: Rec):
    _objnet(r, o)
    o.flags = r.u16()
    o.trans = r.vec3()
    o.rot = r.mat3()
    o.scale = r.f32()
    r.skip(12)                                   # prędkość (≤ 4.2.2.0)
    o.props = r.reflist()
    if r.boolean():
        o.bounds = _bounding_volume(r)


def _node(r: _R, o: Rec):
    _avobject(r, o)
    o.children = r.reflist()
    r.reflist()                                  # efekty
    if o.index == 0 and o.name.lower() != "bip01":
        o.trans, o.rot, o.scale = (0.0, 0.0, 0.0), None, 1.0     # node.cpp: zerowanie transformacji korzenia


def _geometry(r: _R, o: Rec):
    _avobject(r, o)
    o.data = r.ref()
    o.skin = r.ref()


def _geomdata(r: _R, o: Rec) -> int:
    n = r.count(r.u16())
    if r.boolean():
        o.vertices = r.floats(3 * n).reshape(n, 3)
    if r.boolean():
        r.skip(12 * n)                           # normalne
    c = r.vec3()
    o.sphere = (c, r.f32())
    if r.boolean():
        r.skip(16 * n)                           # kolory
    num_uv = r.u16()                             # 4.0.0.2: pole flag = liczba zestawów UV
    if not r.boolean():
        num_uv = 0
    r.skip(8 * n * num_uv)
    return n


def _keymap(r: _R, value_size: int, quat: bool = False, morph: bool = False) -> int:
    count = r.count(r.u32())
    if count == 0 and not morph:
        return 0
    interp = r.u32()
    if interp in (1, 5):
        r.skip(count * (4 + value_size))
    elif interp == 2:
        r.skip(count * (4 + (value_size if quat else 3 * value_size)))
    elif interp == 3:
        r.skip(count * (4 + value_size + 12))
    elif interp == 4:
        pass
    elif count:
        raise NifError(f"nieobsługiwany typ interpolacji {interp}")
    return interp


def _timecontroller(r: _R, o: Rec):
    o.next = r.ref()
    o.flags = r.u16()
    r.skip(16)                                   # częstotliwość, faza, początek, koniec
    o.target = r.ref()


def _extra(r: _R, o: Rec) -> int:
    o.next = r.ref()
    return r.u32()                               # rozmiar rekordu


def _modifier(r: _R, o: Rec):
    o.next = r.ref()
    r.ref()                                      # kontroler


# --- rekordy ---------------------------------------------------------------------------------------------

def _r_node(r, o):
    _node(r, o)


def _r_switch(r, o):
    _node(r, o)
    o.initial_index = r.u32()


def _r_lod(r, o):
    _r_switch(r, o)
    r.vec3()                                     # środek LOD
    o.lod_levels = [(r.f32(), r.f32()) for _ in range(r.count(r.u32()))]


def _r_flt_anim(r, o):
    _r_switch(r, o)
    r.f32()


def _r_sort_adjust(r, o):
    _node(r, o)
    r.u32()
    r.ref()


def _r_camera(r, o):
    _avobject(r, o)
    r.skip(11 * 4)
    r.ref()
    r.skip(4)


def _r_geometry(r, o):
    _geometry(r, o)


def _r_trishape_data(r, o):
    _geomdata(r, o)
    r.u16()                                      # liczba trójkątów
    k = r.count(r.u32())
    idx = r.u16s(k)
    o.triangles = idx[: len(idx) // 3 * 3].reshape(-1, 3)
    for _ in range(r.count(r.u16())):            # grupy dopasowań
        r.skip(2 * r.count(r.u16()))


def _r_tristrips_data(r, o):
    _geomdata(r, o)
    r.u16()
    ns = r.count(r.u16())
    lengths = [r.u16() for _ in range(ns)]
    o.strips = [r.u16s(k) for k in lengths]


def _r_lines_data(r, o):
    n = _geomdata(r, o)
    r.skip(n)


def _r_particles_data(r, o):
    n = _geomdata(r, o)
    r.u16()                                      # liczba cząsteczek
    r.f32()                                      # promień (≤ 10.0.1.0: jedna wartość)
    r.u16()                                      # aktywne
    if r.boolean():
        r.skip(4 * n)


def _r_rot_particles_data(r, o):
    n = _geomdata(r, o)
    r.u16()
    r.f32()
    r.u16()
    if r.boolean():
        r.skip(4 * n)
    if r.boolean():
        r.skip(16 * n)


def _r_skin_instance(r, o):
    o.data = r.ref()
    r.ref()                                      # korzeń szkieletu
    r.reflist()                                  # kości


def _r_skin_data(r, o):
    r.skip(13 * 4)                               # transformacja
    nb = r.count(r.u32())
    r.ref()                                      # partycje (4.0.0.2 ≤ v ≤ 10.1)
    for _ in range(nb):
        r.skip(13 * 4 + 16)
        r.skip(6 * r.count(r.u16()))


def _r_skin_partition(r, o):
    for _ in range(r.count(r.u32())):
        nv, nt, nb, ns, bpv = (r.u16() for _ in range(5))
        r.skip(2 * nb + 2 * nv + 4 * nv * bpv)
        lengths = [r.u16() for _ in range(ns)]
        if ns:
            r.skip(2 * sum(lengths))
        else:
            r.skip(6 * nt)
        if r.u8():
            r.skip(nv * bpv)


def _r_property_flags(r, o):                     # Dither, Shade, Specular, Wireframe, ZBuffer (4.0.0.2)
    _objnet(r, o)
    o.flags = r.u16()


def _r_alpha(r, o):
    _objnet(r, o)
    o.alpha_flags = r.u16()
    r.u8()


def _r_fog(r, o):
    _objnet(r, o)
    r.u16()
    r.f32()
    r.vec3()


def _r_material(r, o):
    _objnet(r, o)
    r.u16()
    r.skip(4 * 12 + 8)


def _r_stencil(r, o):
    _objnet(r, o)
    r.u16()
    r.u8()
    r.skip(7 * 4)


def _r_texturing(r, o):
    _objnet(r, o)
    r.u16()
    r.u32()                                      # tryb nakładania
    for i in range(r.count(r.u32())):
        if not r.boolean():
            continue
        r.ref()
        r.skip(4 * 3 + 4 + 2)                    # clamp, filter, UV set, PS2, nieznane
        if i == 5:
            r.skip(8 + 16)                       # bump map: luma bias + macierz


def _r_vertex_color(r, o):
    _objnet(r, o)
    r.u16()
    r.skip(8)


def _r_source_texture(r, o):
    _objnet(r, o)
    external = r.u8()
    has_data = False
    if not external:
        has_data = r.u8() != 0
    if external:
        o.text = r.string()
    if has_data:
        o.data = r.ref()
    r.skip(12)
    r.u8()


def _r_pixel_data(r, o):
    r.skip(4 + 16 + 4 + 8)                       # format, maski, bpp, compare bits
    r.ref()
    nm = r.count(r.u32())
    r.u32()
    r.skip(12 * nm)
    r.skip(r.count(r.u32()))


def _r_palette(r, o):
    r.u8()
    r.skip(4 * r.count(r.u32()))


def _r_extra_data(r, o):
    r.skip(_extra(r, o))


def _r_string_extra(r, o):
    _extra(r, o)
    o.text = r.string()


def _r_textkey_extra(r, o):
    _extra(r, o)
    for _ in range(r.count(r.u32())):
        r.f32()
        r.string()


def _r_vertweights_extra(r, o):
    _extra(r, o)
    r.skip(4 * r.u16())


def _dyn_effect(r, o):
    _avobject(r, o)
    r.skip(4 * r.count(r.u32()))


def _r_light(r, o):
    _dyn_effect(r, o)
    r.skip(4 + 36)


def _r_point_light(r, o):
    _r_light(r, o)
    r.skip(12)


def _r_spot_light(r, o):
    _r_point_light(r, o)
    r.skip(8)


def _r_texture_effect(r, o):
    _dyn_effect(r, o)
    r.skip(36 + 12 + 16)                         # macierz, pozycja, filter, clamp, typ, generowanie
    r.ref()
    r.u8()
    r.skip(16 + 4 + 2)


def _r_ctrl_data(r, o):                          # kontrolery: TimeController + ref danych
    _timecontroller(r, o)
    o.data = r.ref()


def _r_uv_ctrl(r, o):
    _timecontroller(r, o)
    r.u16()
    o.data = r.ref()


def _r_path_ctrl(r, o):
    _timecontroller(r, o)
    r.i32()
    r.f32()
    r.f32()
    r.u16()
    r.ref()
    r.ref()


def _r_lookat_ctrl(r, o):
    _timecontroller(r, o)
    r.ref()


def _r_morpher_ctrl(r, o):
    _timecontroller(r, o)
    o.data = r.ref()
    r.u8()


def _r_flip_ctrl(r, o):
    _timecontroller(r, o)
    r.u32()
    r.f32()
    r.f32()
    r.reflist()


def _r_particle_ctrl(r, o):
    _timecontroller(r, o)
    r.skip(6 * 4 + 12 + 16 + 3 * 4)              # prędkości, kąty, normalna, kolor, rozmiar, emisja
    r.u8()
    r.skip(3 * 4)                                # birth rate, lifetime, lifetime variation
    r.u16()
    r.vec3()
    r.ref()                                      # emiter
    r.u16()
    r.f32()
    r.u16()
    r.f32()
    r.f32()
    n = r.count(r.u16())
    r.u16()
    r.skip(n * 40)
    r.skip(4)                                    # NiEmitterModifier
    r.ref()
    r.ref()
    r.u8()


def _r_keyframe_data(r, o):
    if _keymap(r, 16, quat=True) == 4:
        r.u32()                                  # kolejność osi
        for _ in range(3):
            _keymap(r, 4)
    _keymap(r, 12)
    _keymap(r, 4)


def _r_float_data(r, o):
    _keymap(r, 4)


def _r_pos_data(r, o):
    _keymap(r, 12)


def _r_color_data(r, o):
    _keymap(r, 16)


def _r_uv_data(r, o):
    for _ in range(4):
        _keymap(r, 4)


def _r_vis_data(r, o):
    r.skip(5 * r.count(r.u32()))


def _r_morph_data(r, o):
    nm = r.count(r.u32())
    nv = r.count(r.u32())
    r.u8()
    for _ in range(nm):
        _keymap(r, 4, morph=True)
        r.skip(12 * nv)


def _r_grow_fade(r, o):
    _modifier(r, o)
    r.skip(8)


def _r_color_modifier(r, o):
    _modifier(r, o)
    r.ref()


def _r_gravity(r, o):
    _modifier(r, o)
    r.skip(4 + 4 + 4 + 12 + 12)


def _r_bomb(r, o):
    _modifier(r, o)
    r.skip(16 + 8 + 24)


def _r_planar_collider(r, o):
    _modifier(r, o)
    r.f32()
    r.skip(8 + 4 * 12 + 4)


def _r_spherical_collider(r, o):
    _modifier(r, o)
    r.f32()
    r.skip(4 + 12)


def _r_rotation_modifier(r, o):
    _modifier(r, o)
    r.u8()
    r.skip(12 + 4)


def _r_nothing(r, o):
    pass


def _r_objnet(r, o):
    _objnet(r, o)


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
    "NiAlphaProperty": _r_alpha, "NiDitherProperty": _r_property_flags, "NiFogProperty": _r_fog,
    "NiMaterialProperty": _r_material, "NiShadeProperty": _r_property_flags,
    "NiSpecularProperty": _r_property_flags, "NiStencilProperty": _r_stencil, "NiTexturingProperty": _r_texturing,
    "NiVertexColorProperty": _r_vertex_color, "NiWireframeProperty": _r_property_flags,
    "NiZBufferProperty": _r_property_flags,
}
NODE_TYPES = {"NiNode", "AvoidNode", "NiBillboardNode", "NiBSAnimationNode", "NiBSParticleNode", "NiCollisionSwitch",
              "RootCollisionNode", "NiSortAdjustNode", "NiSwitchNode", "NiFltAnimationNode", "NiLODNode"}
TRI_TYPES = {"NiTriShape", "NiTriStrips"}
PARTICLE_TYPES = {"NiAutoNormalParticles", "NiParticles", "NiRotatingParticles"}


@dataclass
class NifFile:
    version: int
    records: list
    roots: list
    trailing: int = 0                            # bajty po liście korzeni (0 = odczyt zgodny co do bajtu)


def parse(data: bytes, name: str = "<nif>") -> NifFile:
    """Pełny odczyt pliku NIF 4.0.0.x. Błąd formatu ⇒ NifError (z nazwą pliku i rekordem)."""
    if not data:
        raise NifError(f"{name}: pusty plik")
    nl = bytes(data[:64]).find(b"\n")
    head = bytes(data[:max(nl, 0)]).decode("latin-1", "replace")
    if nl < 0 or not (head.startswith("NetImmerse File Format") or head.startswith("Gamebryo File Format")):
        raise NifError(f"{name}: brak nagłówka NIF")
    r = _R(data)
    r.p = nl + 1
    try:
        version = r.u32()
        if version not in (VER_MW, VER_4000):
            raise NifError(f"nieobsługiwana wersja NIF 0x{version:08x} (obsługiwane: 4.0.0.2, 4.0.0.0)")
        n = r.count(r.u32())
        records = []
        for i in range(n):
            t = r.string()
            fn = READERS.get(t)
            if fn is None:
                raise NifError(f"nieznany typ rekordu {t!r} (indeks {i})")
            o = Rec(index=i, type=t)
            try:
                fn(r, o)
            except NifError as e:
                raise NifError(f"rekord {i} {t}: {e}") from None
            records.append(o)
        roots = [r.i32() for _ in range(r.count(r.u32()))]
        trailing = r.n - r.p
    except NifError as e:
        raise NifError(f"{name}: {e}") from None
    return NifFile(version, records, [i for i in roots if 0 <= i < len(records)], trailing)


# --- geometria ------------------------------------------------------------------------------------------

@dataclass
class Shape:
    name: str
    record: int
    kind: str                                    # "tri" | "particles" | "lines"
    path: str                                    # ścieżka węzłów od korzenia
    matrix: np.ndarray                           # 4×4, kolumnowo: p_model = M · [p_lokalny, 1]
    local_vertices: np.ndarray                   # (N, 3) w układzie kształtu
    triangles: np.ndarray                        # (M, 3) indeksy
    rendered: bool                               # czy silnik tworzy siatkę (nifloader)
    reason: str = ""                             # dlaczego nie (kolizja, ukryty, znacznik, cień, switch, LOD)
    collision: bool = False                      # poddrzewo RootCollisionNode
    alpha: str = "opaque"                        # opaque | test | blend (NiAlphaProperty dziedziczona)
    billboard: bool = False
    skinned: bool = False
    animated: bool = False                       # kontroler na węźle lub przodku (pozycja może się zmieniać)
    data_record: int = -1
    declared_sphere: Optional[tuple] = None      # sfera zapisana w NiGeometryData (układ kształtu)

    def model_vertices(self) -> np.ndarray:
        if len(self.local_vertices) == 0:
            return np.zeros((0, 3))
        return self.local_vertices @ self.matrix[:3, :3].T + self.matrix[:3, 3]


def _local_matrix(o: Rec) -> np.ndarray:
    m = np.eye(4)
    rot = np.eye(3) if o.rot is None else o.rot
    m[:3, :3] = rot * o.scale
    m[:3, 3] = o.trans
    return m


def _strips_to_triangles(strips: list) -> np.ndarray:
    out = []
    for s in strips:                             # node.cpp: stripsToBtTriangleMesh (pomija zdegenerowane)
        s = [int(x) for x in s]
        for i in range(2, len(s)):
            a, b, c = s[i - 2], s[i - 1], s[i]
            if a == b or b == c or a == c:
                continue
            out.append((a, b, c) if i % 2 == 0 else (a, c, b))
    return np.array(out, dtype=np.int64).reshape(-1, 3)


def shapes(nf: NifFile) -> list[Shape]:
    """Wszystkie kształty z transformacją do układu modelu i oceną, czy silnik je rysuje."""
    recs = nf.records

    def get(i):
        return recs[i] if 0 <= i < len(recs) else None

    def has_vis_controller(o: Rec) -> bool:
        seen, c = set(), o.controller
        while c >= 0 and c not in seen:
            seen.add(c)
            ctrl = get(c)
            if ctrl is None:
                break
            if ctrl.type == "NiVisController":
                return True
            c = ctrl.next
        return False

    def extras(o: Rec):
        seen, e = set(), o.extra
        while e >= 0 and e not in seen:
            seen.add(e)
            x = get(e)
            if x is None:
                break
            yield x
            e = x.next

    out: list[Shape] = []
    visited = set()

    def walk(i, matrix, path, state):
        o = get(i)
        if o is None or i in visited:
            return
        visited.add(i)
        m = matrix @ _local_matrix(o)
        st = dict(state)
        if o.controller >= 0:
            st["animated"] = True
        for p in o.props:
            pr = get(p)
            if pr is not None and pr.type == "NiAlphaProperty":
                st["alpha"] = "blend" if pr.alpha_flags & 1 else ("test" if pr.alpha_flags & 0x200 else "opaque")
        if st["root"] is None:
            st["root"] = i
            st["markers"] = any(x.type == "NiStringExtraData" and x.text == "MRK" for x in extras(o))
        if o.type == "RootCollisionNode":
            st["collision"] = True
            st["skip"] = st["skip"] or "kolizja"
        if o.flags & 1 and not has_vis_controller(o):
            st["skip"] = st["skip"] or "ukryty"
        if o.type == "NiBillboardNode":
            st["billboard"] = True
        name = f"{path}/{o.name or o.type}"
        if o.type in NODE_TYPES:
            for k, c in enumerate(o.children):
                cst = st
                if o.type == "NiSwitchNode" and k != o.initial_index:
                    cst = dict(st, skip=st["skip"] or "switch")
                if o.type == "NiLODNode" and k > 0:
                    cst = dict(st, skip=st["skip"] or "lod")
                walk(c, m, name, cst)
            return
        if o.type in TRI_TYPES or o.type in PARTICLE_TYPES or o.type == "NiLines":
            d = get(o.data)
            verts = d.vertices if d is not None and d.vertices is not None else np.zeros((0, 3))
            if o.type == "NiTriShape" and d is not None and d.triangles is not None:
                tris = d.triangles
            elif o.type == "NiTriStrips" and d is not None:
                tris = _strips_to_triangles(d.strips)
            else:
                tris = np.zeros((0, 3), dtype=np.int64)
            if len(tris) and len(verts):
                tris = tris[(tris < len(verts)).all(axis=1)]
            kind = "tri" if o.type in TRI_TYPES else ("lines" if o.type == "NiLines" else "particles")
            reason = st["skip"]
            lname = o.name.lower()
            if not reason and kind == "tri":
                if (st["markers"] and lname.startswith("tri editormarker")) or lname.startswith("shadow") \
                        or lname.startswith("tri shadow"):
                    reason = "znacznik/cień"
            out.append(Shape(o.name, i, kind, name, m, verts, tris, rendered=not reason and kind != "particles",
                             reason=reason or ("cząsteczki" if kind == "particles" else ""),
                             collision=st["collision"], alpha=st["alpha"], billboard=st["billboard"],
                             skinned=o.skin >= 0, animated=st["animated"] or o.controller >= 0,
                             data_record=o.data, declared_sphere=None if d is None else d.sphere))

    base = {"root": None, "markers": False, "collision": False, "skip": "", "alpha": "opaque", "billboard": False,
            "animated": False}
    for root in nf.roots:
        walk(root, np.eye(4), "", base)
    return out


def _aabb(points: np.ndarray):
    if len(points) == 0:
        return None
    return points.min(axis=0), points.max(axis=0)


def _corners(lo, hi) -> np.ndarray:
    return np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])


@dataclass
class ModelGeometry:
    """Geometria modelu w jego układzie (przed transformacją referencji)."""
    shapes: list
    triangles: np.ndarray                        # (T, 3, 3) — rysowane trójkąty (do zasłaniania)
    triangle_alpha: np.ndarray                   # (T,) 0 = nieprzezroczysty, 1 = alpha test, 2 = blend
    aabb: Optional[tuple]                        # AABB wierzchołków rysowanych kształtów
    engine_aabb: Optional[tuple]                 # jak CullSafeBoundsVisitor: rogi AABB każdego kształtu
    collision_aabb: Optional[tuple]
    sphere: Optional[tuple]                      # sfera opisana (środek AABB, maks. odległość wierzchołka)
    declared: list                               # zadeklarowane granice z pliku (do porównania)
    stats: dict


def model_geometry(nf: NifFile) -> ModelGeometry:
    sh = shapes(nf)
    tri_list, alpha_list, pts, eng, col = [], [], [], [], []
    for s in sh:
        if len(s.local_vertices) == 0:
            continue
        mv = s.model_vertices()
        if s.collision:
            col.append(mv)
        if not s.rendered:
            continue
        pts.append(mv)
        lo, hi = s.local_vertices.min(axis=0), s.local_vertices.max(axis=0)
        c = _corners(lo, hi)
        eng.append(c @ s.matrix[:3, :3].T + s.matrix[:3, 3])
        if s.kind == "tri" and len(s.triangles):
            tri_list.append(mv[s.triangles])
            alpha_list.append(np.full(len(s.triangles), {"opaque": 0, "test": 1, "blend": 2}[s.alpha]))
    allp = np.vstack(pts) if pts else np.zeros((0, 3))
    aabb = _aabb(allp)
    sphere = None
    if aabb is not None:
        center = (aabb[0] + aabb[1]) / 2
        sphere = (center, float(np.sqrt(((allp - center) ** 2).sum(axis=1)).max()))
    declared = []
    for o in nf.records:
        if o.bounds and o.bounds.get("type") != "base":
            declared.append({"record": o.index, "node": o.name, **{k: v for k, v in o.bounds.items()}})
        if o.sphere is not None and o.vertices is not None:
            declared.append({"record": o.index, "type": "data_sphere", "center": o.sphere[0],
                             "radius": o.sphere[1]})
    tris = np.concatenate(tri_list) if tri_list else np.zeros((0, 3, 3))
    alphas = np.concatenate(alpha_list) if alpha_list else np.zeros(0, dtype=np.int64)
    return ModelGeometry(sh, tris, alphas,
                         aabb, _aabb(np.vstack(eng)) if eng else None, _aabb(np.vstack(col)) if col else None,
                         sphere, declared,
                         {"records": len(nf.records), "shapes": len(sh),
                          "rendered_shapes": sum(1 for s in sh if s.rendered),
                          "triangles": int(len(tris)), "alpha_triangles": int((alphas > 0).sum()),
                          "billboard_shapes": sum(1 for s in sh if s.billboard and s.rendered),
                          "skinned_shapes": sum(1 for s in sh if s.skinned and s.rendered),
                          "animated_shapes": sum(1 for s in sh if s.animated and s.rendered)})


def declared_sphere_check(geom: ModelGeometry, tol: float = 0.5) -> dict:
    """Czy sfery zapisane w pliku (NiGeometryData) obejmują wierzchołki — nie ufamy im bez sprawdzenia."""
    ok = too_small = loose = 0
    worst = []
    for s in geom.shapes:
        if s.declared_sphere is None or not len(s.local_vertices):
            continue
        c, r = np.array(s.declared_sphere[0]), float(s.declared_sphere[1])
        dmax = float(np.sqrt(((s.local_vertices - c) ** 2).sum(axis=1)).max())
        if dmax > r + tol:
            too_small += 1
            worst.append({"shape": s.name, "declared_radius": round(r, 2), "needed_radius": round(dmax, 2)})
        else:
            ok += 1
            if dmax < 0.5 * r:
                loose += 1
    return {"spheres_ok": ok, "spheres_too_small": too_small, "spheres_more_than_2x_too_big": loose,
            "worst": sorted(worst, key=lambda w: w["declared_radius"] - w["needed_radius"])[:5]}


def summary(geom: ModelGeometry) -> dict:
    def box(b):
        return None if b is None else {"min": [round(float(v), 2) for v in b[0]],
                                       "max": [round(float(v), 2) for v in b[1]],
                                       "size": [round(float(v), 2) for v in (b[1] - b[0])]}
    return {"aabb": box(geom.aabb), "engine_aabb": box(geom.engine_aabb), "collision_aabb": box(geom.collision_aabb),
            "sphere": None if geom.sphere is None else {"center": [round(float(v), 2) for v in geom.sphere[0]],
                                                        "radius": round(geom.sphere[1], 2)},
            "stats": geom.stats}
