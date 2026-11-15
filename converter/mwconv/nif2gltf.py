"""Konwersja modelu NIF (Morrowind, 4.0.0.2) → glTF 2.0 (GLB).

Zasady (zgodne z tym, jak silnik gry interpretuje NIF-y):
* hierarchia węzłów zostaje zachowana 1:1 (każdy NiAVObject → węzeł glTF); oryginalna nazwa i numer
  bloku trafiają do `extras` (`mw_name`, `mw_block`), bo Godot może zmieniać nazwy duplikatów;
* współrzędne: Z-up/jednostki gry → Y-up/metry (coords.py) – przeliczane są wierzchołki, normalne,
  transformacje węzłów, macierze skinu i klatki kluczowe, a NIE dodawany jest węzeł-korzeń z obrotem;
* transformacja bloku-korzenia jest zerowana (tak robi silnik), chyba że korzeń nazywa się „Bip01”;
* właściwości (materiał, tekstury, alfa, stencil, kolor wierzchołków) są dziedziczone w dół drzewa;
* poddrzewo RootCollisionNode → węzły z `extras.mw_collision = true` (siatki bez materiału);
* wszystko, czego nie dało się bezstratnie przenieść, ląduje w raporcie diagnostycznym.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from typing import Callable, Optional

import numpy as np

from . import coords
from .gltf import ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER, FLOAT, UBYTE, UINT, USHORT, GltfBuilder
from .nif.reader import (NODE_TYPES, PARTICLE_TYPES, TRI_TYPES, Block, NifFile, controller_chain, extra_chain,
                         strips_to_triangles)

# NiAlphaProperty – funkcje mieszania (nif.xml AlphaFunction)
BLEND_NAMES = ["ONE", "ZERO", "SRC_COLOR", "INV_SRC_COLOR", "DEST_COLOR", "INV_DEST_COLOR", "SRC_ALPHA",
               "INV_SRC_ALPHA", "DEST_ALPHA", "INV_DEST_ALPHA", "SRC_ALPHA_SATURATE"]
TEST_NAMES = ["ALWAYS", "LESS", "EQUAL", "LEQUAL", "GREATER", "NOTEQUAL", "GEQUAL", "NEVER"]

GL_NEAREST, GL_LINEAR = 9728, 9729
GL_LINEAR_MIPMAP_LINEAR, GL_NEAREST_MIPMAP_NEAREST = 9987, 9984
GL_LINEAR_MIPMAP_NEAREST, GL_NEAREST_MIPMAP_LINEAR = 9985, 9986
GL_REPEAT, GL_CLAMP = 10497, 33071

C4 = np.eye(4)
C4[:3, :3] = coords.M * coords.SCALE
C4_INV = np.linalg.inv(C4)


@dataclass
class TextureRef:
    uri: str              # ścieżka względem pliku GLB (np. "../textures/tx_wood.png")
    has_alpha: bool = False
    source_path: str = ""  # ścieżka w VFS gry


TextureResolver = Callable[[str], Optional[TextureRef]]


@dataclass
class Report:
    model: str
    ok: bool = True
    nodes: int = 0
    meshes: int = 0
    triangles: int = 0
    vertices: int = 0
    collision_meshes: int = 0
    materials: int = 0
    textures: list = field(default_factory=list)
    missing_textures: list = field(default_factory=list)
    animations: int = 0
    skins: int = 0
    aabb_min: Optional[list] = None
    aabb_max: Optional[list] = None
    aabb_mw_units: Optional[dict] = None
    lossy: list = field(default_factory=list)       # elementy przeniesione w przybliżeniu
    unsupported: list = field(default_factory=list)  # elementy pominięte
    skipped_shapes: list = field(default_factory=list)
    text_keys: list = field(default_factory=list)

    def note(self, kind: str, msg: str):
        lst = self.lossy if kind == "lossy" else self.unsupported
        if msg not in lst:
            lst.append(msg)

    def to_dict(self) -> dict:
        return dict(self.__dict__)


def _local_matrix_nif(b: Block, is_root: bool) -> np.ndarray:
    if is_root and b.get("name", "").lower() != "bip01":
        return np.eye(4)
    return coords.trs_matrix(b["translation"], b["rotation"], b["scale"])


def _to_g4(m_nif: np.ndarray) -> np.ndarray:
    return C4 @ m_nif @ C4_INV


class NifToGltf:
    def __init__(self, nif: NifFile, name: str, resolve_texture: Optional[TextureResolver] = None,
                 embed_name_extras: bool = True):
        self.nif = nif
        self.name = name
        self.resolve = resolve_texture or (lambda _n: None)
        self.g = GltfBuilder("mwconv (Morrowind NIF → glTF)")
        self.rep = Report(model=name)
        self.node_of_block: dict[int, int] = {}
        self.world_nif: dict[int, np.ndarray] = {}   # macierz świata węzła w układzie NIF (poza)
        self.material_cache: dict[str, int] = {}
        self.pending_skins: list[tuple[int, Block, Block, int]] = []  # (gltf mesh node, shape, skininst, nvert)
        self.markers = False
        self.aabb = [np.full(3, np.inf), np.full(3, -np.inf)]

    # ------------------------------------------------------------------------------------------
    def convert(self) -> tuple[bytes, Report]:
        nif = self.nif
        roots = nif.roots or ([0] if nif.blocks else [])
        if not roots:
            self.rep.ok = False
            self.rep.note("unsupported", "plik bez bloków")
            return self.g.to_glb(), self.rep
        root_block = nif.block(roots[0])
        # znacznik MRK w korzeniu ⇒ pomijamy siatki „tri editormarker*”
        if root_block is not None and root_block.type in NODE_TYPES:
            for e in extra_chain(nif, root_block.get("extra", -1)):
                if e.type == "NiStringExtraData" and e.get("string", "").upper().startswith("MRK"):
                    self.markers = True
                if e.type == "NiTextKeyExtraData":
                    self.rep.text_keys = [[float(t), s] for t, s in e.get("keys", [])]

        for ri, r in enumerate(roots):
            b = nif.block(r)
            if b is None or b.type not in NODE_TYPES | TRI_TYPES:
                if b is not None:
                    self.rep.note("unsupported", f"korzeń typu {b.type} pominięty")
                continue
            idx = self._visit(r, np.eye(4), {}, is_root=(ri == 0 and r == roots[0]), collision=False)
            if idx is not None:
                self.g.add_root(idx)

        self._build_skins()
        self._build_animations()
        if np.all(np.isfinite(self.aabb[0])):
            self.rep.aabb_min = [round(float(x), 6) for x in self.aabb[0]]
            self.rep.aabb_max = [round(float(x), 6) for x in self.aabb[1]]
            mn = coords.pos_from_godot(self.aabb[0])
            mx = coords.pos_from_godot(self.aabb[1])
            lo, hi = np.minimum(mn, mx), np.maximum(mn, mx)
            self.rep.aabb_mw_units = {"min": [round(float(x), 3) for x in lo], "max": [round(float(x), 3) for x in hi]}
        self.g.doc["scenes"][0]["name"] = self.name
        self.g.doc["scenes"][0]["extras"] = {
            "mw_source": self.name,
            "mw_text_keys": self.rep.text_keys,
            "mw_units_per_meter": coords.UNITS_PER_METER,
            "mw_aabb_min": self.rep.aabb_min, "mw_aabb_max": self.rep.aabb_max,
        }
        self.rep.materials = len(self.g.doc.get("materials", []))
        return self.g.to_glb(), self.rep

    # ------------------------------------------------------------------------------------------
    def _visit(self, bi: int, parent_world: np.ndarray, props: dict, is_root: bool, collision: bool,
               hidden: bool = False) -> Optional[int]:
        b = self.nif.block(bi)
        if b is None:
            return None
        if bi in self.node_of_block:
            self.rep.note("lossy", f"blok {bi} ma wielu rodziców – użyto pierwszego wystąpienia")
            return None
        t = b.type
        local = _local_matrix_nif(b, is_root)
        if is_root and b.get("name", "").lower() != "bip01":
            if not np.allclose(coords.trs_matrix(b["translation"], b["rotation"], b["scale"]), np.eye(4), atol=1e-6):
                self.rep.note("lossy", "transformacja korzenia wyzerowana (zgodnie z silnikiem gry)")
        world = parent_world @ local
        self.world_nif[bi] = world

        # właściwości dziedziczone
        props = dict(props)
        for pr in b.get("properties", []):
            pb = self.nif.block(pr)
            if pb is not None:
                props[pb.type] = pb

        extras = {"mw_name": b.get("name", ""), "mw_block": bi, "mw_type": t}
        flags = b.get("flags", 0)
        if flags & 1:
            extras["mw_hidden"] = True
        if t == "RootCollisionNode":
            collision = True
        if collision:
            extras["mw_collision"] = True
        if t == "NiBillboardNode":
            extras["mw_billboard"] = True
            self.rep.note("lossy", "NiBillboardNode – obrót do kamery realizuje loader Godota (extras.mw_billboard)")
        if t == "NiSwitchNode":
            extras["mw_switch_initial"] = b.get("initial_index", 0)
        if t == "NiLODNode":
            extras["mw_lod_levels"] = [[float(a) * coords.SCALE, float(c) * coords.SCALE] for a, c in b.get("lod_levels", [])]
        if t in ("NiBSAnimationNode", "NiBSParticleNode"):
            extras["mw_bs_flags"] = flags
        for e in extra_chain(self.nif, b.get("extra", -1)):
            if e.type == "NiStringExtraData":
                extras.setdefault("mw_strings", []).append(e.get("string", ""))

        node_kw = {"name": self._unique_name(b.get("name", "") or f"{t}_{bi}")}
        self._set_trs(node_kw, local, b, is_root)
        gi = self.g.node(**node_kw, extras=extras)
        self.node_of_block[bi] = gi
        self.rep.nodes += 1

        if t in TRI_TYPES:
            self._shape(b, gi, world, props, collision, hidden or bool(flags & 1))
        elif t in PARTICLE_TYPES:
            self.rep.note("unsupported", f"system cząsteczek {t} ({b.get('name', '')}) – pominięty (planowane: GPUParticles3D)")
        elif t == "NiLines":
            self.rep.note("unsupported", "NiLines – pominięte")

        if t in NODE_TYPES:
            children = []
            for ci, c in enumerate(b.get("children", [])):
                if c < 0:
                    continue
                cb = self.nif.block(c)
                if cb is None:
                    continue
                if cb.type in ("NiCamera",) or "Light" in cb.type or cb.type == "NiTextureEffect":
                    self.rep.note("unsupported", f"{cb.type} w drzewie – pominięty")
                    continue
                child_hidden = hidden
                if t == "NiSwitchNode" and ci != b.get("initial_index", 0):
                    child_hidden = True
                cg = self._visit(c, world, props, False, collision, child_hidden)
                if cg is not None:
                    if t == "NiSwitchNode" and ci != b.get("initial_index", 0):
                        self.g.doc["nodes"][cg].setdefault("extras", {})["mw_hidden"] = True
                    children.append(cg)
            if children:
                self.g.doc["nodes"][gi]["children"] = children
            if b.get("effects"):
                self.rep.note("unsupported", "efekty dynamiczne (NiTextureEffect/światła) przypięte do węzła – pominięte")
        return gi

    _names: set

    def _unique_name(self, n: str) -> str:
        if not hasattr(self, "_names"):
            self._names = set()
        base, k = n, 1
        while n in self._names:
            k += 1
            n = f"{base}.{k:03d}"
        self._names.add(n)
        return n

    def _set_trs(self, kw: dict, local_nif: np.ndarray, b: Block, is_root: bool):
        if np.allclose(local_nif, np.eye(4), atol=1e-9):
            return
        R = local_nif[:3, :3]
        s = float(np.cbrt(abs(np.linalg.det(R)))) if np.linalg.det(R) != 0 else 0.0
        Rn = R / s if s else R
        if s and coords.is_orthonormal(Rn, 1e-4):
            t = coords.pos_to_godot(local_nif[:3, 3])
            if not np.allclose(t, 0):
                kw["translation"] = [float(x) for x in t]
            q = coords.mat_to_quat(coords.rot_to_godot(Rn))
            if not np.allclose(q, [0, 0, 0, 1]):
                kw["rotation"] = [float(x) for x in q]
            if abs(s - 1) > 1e-9:
                kw["scale"] = [s, s, s]
        else:
            g = _to_g4(local_nif)
            kw["matrix"] = [float(x) for x in g.T.reshape(16)]
            self.rep.note("lossy", f"węzeł {b.get('name', '')}: macierz nieortonormalna – zapisana jako matrix")

    # ------------------------------------------------------------------------------------------
    def _shape(self, b: Block, gi: int, world: np.ndarray, props: dict, collision: bool, hidden: bool):
        name = b.get("name", "")
        lname = name.lower()
        if self.markers and lname.startswith("tri editormarker"):
            self.rep.skipped_shapes.append({"name": name, "reason": "editor marker (MRK)"})
            return
        if lname.startswith("shadow") or lname.startswith("tri shadow"):
            self.rep.skipped_shapes.append({"name": name, "reason": "cień (shadow*)"})
            return
        d = self.nif.block(b.get("data", -1))
        if d is None or d.get("vertices") is None:
            self.rep.skipped_shapes.append({"name": name, "reason": "brak danych geometrii"})
            return
        if b.type == "NiTriShape":
            if d.type != "NiTriShapeData":
                self.rep.note("unsupported", f"{name}: niezgodny typ danych {d.type}")
                return
            tris = np.asarray(d["triangles"], dtype=np.uint32)
        else:
            if d.type != "NiTriStripsData":
                self.rep.note("unsupported", f"{name}: niezgodny typ danych {d.type}")
                return
            tris = strips_to_triangles(d["strips"])
        n = d["num_vertices"]
        if len(tris) == 0 or n == 0:
            self.rep.skipped_shapes.append({"name": name, "reason": "brak trójkątów"})
            return
        if tris.max() >= n:
            bad = int((tris >= n).any(axis=1).sum())
            self.rep.note("lossy", f"{name}: {bad} trójkątów z indeksem poza zakresem – usunięte")
            tris = tris[(tris < n).all(axis=1)]

        pos = coords.pos_to_godot(d["vertices"]).astype(np.float32)
        attrs = {"POSITION": self.g.accessor(pos, FLOAT, ARRAY_BUFFER, minmax=True)}
        if d.get("normals") is not None:
            nrm = coords.dir_to_godot(d["normals"]).astype(np.float32)
            ln = np.linalg.norm(nrm, axis=1, keepdims=True)
            bad = ln[:, 0] < 1e-8
            nrm = np.where(bad[:, None], np.array([0, 1, 0], np.float32), nrm / np.maximum(ln, 1e-8))
            if bad.any():
                self.rep.note("lossy", f"{name}: {int(bad.sum())} zerowych normalnych zastąpiono (0,1,0)")
            attrs["NORMAL"] = self.g.accessor(nrm.astype(np.float32), FLOAT, ARRAY_BUFFER)
        for k, uv in enumerate(d.get("uvs", [])[:2]):
            attrs[f"TEXCOORD_{k}"] = self.g.accessor(np.asarray(uv, np.float32), FLOAT, ARRAY_BUFFER)
        if len(d.get("uvs", [])) > 2:
            self.rep.note("lossy", f"{name}: więcej niż 2 zestawy UV – zachowano 2")

        material = None
        if not collision:
            vc_prop = props.get("NiVertexColorProperty")
            vmode = vc_prop["vertex_mode"] if vc_prop is not None else 2
            if d.get("colors") is not None:
                if vmode == 2:
                    attrs["COLOR_0"] = self.g.accessor(np.clip(d["colors"], 0, 1).astype(np.float32), FLOAT, ARRAY_BUFFER)
                elif vmode == 1:
                    self.rep.note("lossy", f"{name}: kolory wierzchołków w trybie emisji – pominięte w glTF")
            material = self._material(props, name, has_vc="COLOR_0" in attrs)

        skin_inst = self.nif.block(b.get("skin", -1))
        if skin_inst is not None and not collision:
            joints, weights = self._skin_weights(skin_inst, n, name)
            if joints is not None:
                attrs["JOINTS_0"] = self.g.accessor(joints.astype(np.uint16), USHORT, ARRAY_BUFFER)
                attrs["WEIGHTS_0"] = self.g.accessor(weights.astype(np.float32), FLOAT, ARRAY_BUFFER)

        ind = self.g.accessor(tris.reshape(-1).astype(np.uint32 if n > 65535 else np.uint16),
                              UINT if n > 65535 else USHORT, ELEMENT_ARRAY_BUFFER)
        prim = {"attributes": attrs, "indices": ind, "mode": 4}
        if material is not None:
            prim["material"] = material
        mextras = {"mw_shape": name}
        if collision:
            mextras["mw_collision"] = True
        mi = self.g.mesh(name or f"mesh_{b.index}", [prim], mextras)
        self.g.doc["nodes"][gi]["mesh"] = mi
        if skin_inst is not None and "JOINTS_0" in attrs:
            self.pending_skins.append((gi, b, skin_inst, n))
        if collision:
            self.rep.collision_meshes += 1
        else:
            self.rep.meshes += 1
            self.rep.triangles += int(len(tris))
            self.rep.vertices += int(n)
            if not hidden and not (skin_inst is not None):
                wv = (np.c_[d["vertices"], np.ones(n)] @ world.T)[:, :3]
                wg = coords.pos_to_godot(wv)
                self.aabb[0] = np.minimum(self.aabb[0], wg.min(axis=0))
                self.aabb[1] = np.maximum(self.aabb[1], wg.max(axis=0))
            elif skin_inst is not None:
                # w pozie wiązania skin = geometria w układzie kształtu
                wv = (np.c_[d["vertices"], np.ones(n)] @ world.T)[:, :3]
                wg = coords.pos_to_godot(wv)
                self.aabb[0] = np.minimum(self.aabb[0], wg.min(axis=0))
                self.aabb[1] = np.maximum(self.aabb[1], wg.max(axis=0))

    # ------------------------------------------------------------------------------------------
    def _tex(self, slot: dict, slot_name: str, shape: str) -> Optional[dict]:
        src = self.nif.block(slot.get("source", -1))
        if src is None:
            return None
        if not src.get("external"):
            self.rep.note("unsupported", f"{shape}: tekstura wewnętrzna (NiPixelData) w slocie {slot_name} – pominięta")
            return None
        fname = src.get("file") or ""
        tr = self.resolve(fname)
        if tr is None:
            if fname not in self.rep.missing_textures:
                self.rep.missing_textures.append(fname)
            return None
        if tr.source_path and tr.source_path not in self.rep.textures:
            self.rep.textures.append(tr.source_path)
        clamp = slot.get("clamp", 3)
        filt = slot.get("filter", 2)
        mag, minf = {0: (GL_NEAREST, GL_NEAREST), 1: (GL_LINEAR, GL_LINEAR),
                     2: (GL_LINEAR, GL_LINEAR_MIPMAP_LINEAR), 3: (GL_NEAREST, GL_NEAREST_MIPMAP_NEAREST),
                     4: (GL_NEAREST, GL_NEAREST_MIPMAP_LINEAR), 5: (GL_LINEAR, GL_LINEAR_MIPMAP_NEAREST)}.get(
            filt, (GL_LINEAR, GL_LINEAR_MIPMAP_LINEAR))
        smp = self.g.sampler({"magFilter": mag, "minFilter": minf,
                              "wrapS": GL_CLAMP if clamp in (0, 1) else GL_REPEAT,
                              "wrapT": GL_CLAMP if clamp in (0, 2) else GL_REPEAT})
        img = self.g.image_uri(tr.uri, fname)
        tex = self.g.texture(img, smp)
        info = {"index": tex}
        if slot.get("uv_set", 0):
            info["texCoord"] = int(min(slot["uv_set"], 1))
        return {"info": info, "ref": tr, "file": fname}

    def _material(self, props: dict, shape: str, has_vc: bool) -> int:
        mat = props.get("NiMaterialProperty")
        texp = props.get("NiTexturingProperty")
        alpha = props.get("NiAlphaProperty")
        stencil = props.get("NiStencilProperty")
        spec = props.get("NiSpecularProperty")
        wire = props.get("NiWireframeProperty")
        zbuf = props.get("NiZBufferProperty")

        pbr = {"metallicFactor": 0.0, "roughnessFactor": 1.0}
        m = {"pbrMetallicRoughness": pbr}
        ex = {}
        name_parts = []
        if mat is not None:
            dif = [float(x) for x in mat["diffuse"]]
            a = float(mat["alpha"])
            pbr["baseColorFactor"] = [min(1, max(0, c)) for c in dif] + [min(1, max(0, a))]
            em = [float(x) for x in mat["emissive"]]
            if any(c > 0 for c in em):
                m["emissiveFactor"] = [min(1, max(0, c)) for c in em]
            ex["mw_material"] = {"name": mat.get("name", ""), "ambient": list(mat["ambient"]), "diffuse": dif,
                                 "specular": list(mat["specular"]), "emissive": em,
                                 "glossiness": float(mat["glossiness"]), "alpha": a}
            name_parts.append(mat.get("name", ""))
        if texp is not None:
            slots = texp.get("textures", {})
            if "base" in slots:
                t = self._tex(slots["base"], "base", shape)
                if t:
                    pbr["baseColorTexture"] = t["info"]
                    name_parts.append(t["file"])
            if "glow" in slots:
                t = self._tex(slots["glow"], "glow", shape)
                if t:
                    m["emissiveTexture"] = t["info"]
                    m["emissiveFactor"] = [1.0, 1.0, 1.0]
            extra_slots = {}
            for sname in ("dark", "detail", "gloss", "bump", "decal0", "decal1", "decal2", "decal3"):
                if sname in slots:
                    t = self._tex(slots[sname], sname, shape)
                    if t:
                        extra_slots[sname] = {"uri": t["ref"].uri, "texCoord": t["info"].get("texCoord", 0)}
                        self.rep.note("lossy", f"slot tekstury {sname} – zapisany w extras (wymaga własnego shadera)")
            if extra_slots:
                ex["mw_extra_textures"] = extra_slots
            ex["mw_apply_mode"] = texp.get("apply_mode", 2)
        if alpha is not None:
            fl = alpha["flags"]
            blend = bool(fl & 1)
            src = BLEND_NAMES[(fl >> 1) & 0xF] if ((fl >> 1) & 0xF) < len(BLEND_NAMES) else "?"
            dst = BLEND_NAMES[(fl >> 5) & 0xF] if ((fl >> 5) & 0xF) < len(BLEND_NAMES) else "?"
            test = bool(fl & (1 << 9))
            func = TEST_NAMES[(fl >> 10) & 0x7]
            thr = alpha["threshold"]
            ex["mw_alpha"] = {"blend": blend, "src": src, "dst": dst, "test": test, "func": func,
                              "threshold": thr, "no_sort": bool(fl & (1 << 13))}
            if test:
                m["alphaMode"] = "MASK"
                m["alphaCutoff"] = round(thr / 255.0, 6)
                if func not in ("GREATER", "GEQUAL"):
                    self.rep.note("lossy", f"test alfa {func} przybliżony jako MASK (≥ próg)")
            elif blend:
                m["alphaMode"] = "BLEND"
                if not (src == "SRC_ALPHA" and dst == "INV_SRC_ALPHA"):
                    ex["mw_blend_mode"] = f"{src}/{dst}"
                    self.rep.note("lossy", f"mieszanie {src}/{dst} – glTF zna tylko BLEND; loader ustawia tryb wg extras")
        if stencil is not None:
            dm = stencil.get("draw_mode", 0)
            if dm == 3:
                m["doubleSided"] = True
            elif dm == 2:
                ex["mw_cull"] = "front"
                self.rep.note("lossy", "NiStencilProperty DRAW_CW – odwrócone nawinięcie obsługiwane przez extras")
            if stencil.get("enabled"):
                self.rep.note("unsupported", "test stencil – pominięty")
        if spec is not None:
            ex["mw_specular_enabled"] = bool(spec["flags"] & 1)
        if wire is not None and wire["flags"] & 1:
            ex["mw_wireframe"] = True
        if zbuf is not None:
            ex["mw_zbuffer"] = {"test": bool(zbuf["flags"] & 1), "write": bool(zbuf["flags"] & 2)}
        ex["mw_vertex_colors"] = has_vc
        if ex:
            m["extras"] = ex
        key = json.dumps(m, sort_keys=True)
        if key in self.material_cache:
            return self.material_cache[key]
        m["name"] = "|".join(p for p in name_parts if p) or f"mat_{len(self.material_cache)}"
        idx = self.g.material(m)
        self.material_cache[key] = idx
        return idx

    # ------------------------------------------------------------------------------------------
    def _skin_weights(self, inst: Block, n: int, shape: str):
        data = self.nif.block(inst.get("data", -1))
        if data is None or data.type != "NiSkinData":
            self.rep.note("unsupported", f"{shape}: NiSkinInstance bez NiSkinData")
            return None, None
        per_vertex: list[list[tuple[float, int]]] = [[] for _ in range(n)]
        for bi, bone in enumerate(data["bones"]):
            for vi, w in zip(bone["indices"], bone["weights"]):
                if 0 <= vi < n and w > 0:
                    per_vertex[vi].append((float(w), bi))
        joints = np.zeros((n, 4), np.uint16)
        weights = np.zeros((n, 4), np.float32)
        over = 0
        unweighted = 0
        for vi, infl in enumerate(per_vertex):
            if len(infl) > 4:
                over += 1
            infl.sort(reverse=True)
            infl = infl[:4]
            s = sum(w for w, _ in infl)
            if s <= 0:
                unweighted += 1
                joints[vi, 0] = 0
                weights[vi, 0] = 1.0
                continue
            for k, (w, j) in enumerate(infl):
                joints[vi, k] = j
                weights[vi, k] = w / s
        if over:
            self.rep.note("lossy", f"{shape}: {over} wierzchołków z >4 wpływami kości – zachowano 4 najsilniejsze")
        if unweighted:
            self.rep.note("lossy", f"{shape}: {unweighted} wierzchołków bez wag – przypisano do pierwszej kości")
        return joints, weights

    def _build_skins(self):
        for gi, shape, inst, n in self.pending_skins:
            data = self.nif.block(inst["data"])
            bones = inst.get("bones", [])
            joints = []
            ibms = []
            T = data["transform"]
            T_skin = coords.trs_matrix(T["translation"], T["rotation"], T["scale"])
            W_geom = self.world_nif.get(shape.index, np.eye(4))
            L = W_geom @ T_skin @ np.linalg.inv(W_geom)
            approx = not np.allclose(T_skin, np.eye(4), atol=1e-5)
            ok = True
            for k, bref in enumerate(bones):
                if bref not in self.node_of_block:
                    self.rep.note("unsupported", f"{shape.get('name', '')}: kość (blok {bref}) poza drzewem – skin pominięty")
                    ok = False
                    break
                joints.append(self.node_of_block[bref])
                bt = data["bones"][k]["transform"]
                IB = coords.trs_matrix(bt["translation"], bt["rotation"], bt["scale"])
                J = self.world_nif[bref]
                ibm_nif = np.linalg.inv(J) @ L @ J @ IB if approx else IB
                ibms.append(_to_g4(ibm_nif))
            if not ok or not joints:
                prim = self.g.doc["meshes"][self.g.doc["nodes"][gi]["mesh"]]["primitives"][0]
                prim["attributes"].pop("JOINTS_0", None)
                prim["attributes"].pop("WEIGHTS_0", None)
                continue
            if approx:
                self.rep.note("lossy", "NiSkinData z nietrywialną transformacją całego skinu – przeliczono w pozie wiązania")
            arr = np.array([m.T.reshape(16) for m in ibms], dtype=np.float32)
            acc = self.g.accessor(arr, FLOAT)
            root = inst.get("root", -1)
            skin = {"joints": joints, "inverseBindMatrices": acc, "name": f"skin_{shape.get('name', '')}"}
            if root in self.node_of_block:
                skin["skeleton"] = self.node_of_block[root]
            si = self.g.skin(skin)
            self.g.doc["nodes"][gi]["skin"] = si
            self.rep.skins += 1

    # ------------------------------------------------------------------------------------------
    def _build_animations(self):
        channels, samplers = [], []
        tmin, tmax = math.inf, -math.inf
        for bi, gi in self.node_of_block.items():
            b = self.nif.block(bi)
            for c in controller_chain(self.nif, b.get("controller", -1)):
                if c.type == "NiKeyframeController":
                    d = self.nif.block(c.get("data", -1))
                    if d is None:
                        continue
                    if abs(c.get("frequency", 1.0) - 1.0) > 1e-6 or abs(c.get("phase", 0.0)) > 1e-6:
                        self.rep.note("lossy", "kontroler z częstotliwością/fazą ≠ 1/0 – czas przeskalowany")
                    for path, arr_t, arr_v, interp in self._kf_tracks(d, b):
                        if arr_t is None or len(arr_t) == 0:
                            continue
                        ttimes = (arr_t * c.get("frequency", 1.0) + c.get("phase", 0.0)).astype(np.float32)
                        tmin, tmax = min(tmin, float(ttimes.min())), max(tmax, float(ttimes.max()))
                        ia = self.g.accessor(ttimes, FLOAT, minmax=True)
                        oa = self.g.accessor(arr_v.astype(np.float32), FLOAT)
                        samplers.append({"input": ia, "output": oa, "interpolation": interp})
                        channels.append({"sampler": len(samplers) - 1, "target": {"node": gi, "path": path}})
                elif c.type in ("NiVisController", "NiUVController", "NiAlphaController", "NiMaterialColorController",
                                "NiGeomMorpherController", "NiFlipController", "NiPathController", "NiLookAtController",
                                "NiRollController", "NiParticleSystemController", "NiBSPArrayController",
                                "NiLightColorController"):
                    self.rep.note("unsupported", f"kontroler {c.type} – jeszcze nie konwertowany")
            # kontrolery na właściwościach (np. NiMaterialColorController, NiFlipController)
            for pr in b.get("properties", []):
                pb = self.nif.block(pr)
                if pb is not None:
                    for c in controller_chain(self.nif, pb.get("controller", -1)):
                        self.rep.note("unsupported", f"kontroler {c.type} na {pb.type} – jeszcze nie konwertowany")
        if channels:
            anim = {"name": "default", "channels": channels, "samplers": samplers,
                    "extras": {"mw_text_keys": self.rep.text_keys, "mw_time_range": [tmin, tmax]}}
            self.g.animation(anim)
            self.rep.animations = 1

    def _kf_tracks(self, d: Block, node: Block):
        out = []
        rot = d["rotations"]
        if rot.get("interp") == 4 and rot.get("xyz"):
            # XYZ: próbkowanie na wspólnej osi czasu → kwaterniony (LINEAR)
            groups = rot["xyz"]
            ts = sorted({float(t) for g in groups if g["times"] is not None for t in g["times"]})
            if ts:
                q = []
                for t in ts:
                    ang = [float(_sample_scalar(g, t)) for g in groups]
                    # najpierw obrót wokół X, potem Y, potem Z (wektory kolumnowe: R = Rz·Ry·Rx)
                    R = coords._rz(ang[2]) @ coords._ry(ang[1]) @ coords._rx(ang[0])
                    q.append(coords.mat_to_quat(coords.rot_to_godot(R)))
                q = _fix_quat_signs(np.array(q))
                out.append(("rotation", np.array(ts, np.float32), q, "LINEAR"))
                self.rep.note("lossy", "obroty XYZ (Euler) zamienione na kwaterniony próbkowane w kluczach")
        elif rot.get("times") is not None:
            q = np.array([coords.nif_quat_to_godot(v) for v in rot["values"]])
            q = _fix_quat_signs(q)
            interp = "STEP" if rot["interp"] == 5 else "LINEAR"
            if rot["interp"] == 3:
                self.rep.note("lossy", "obroty TBC – interpolowane liniowo (slerp)")
            out.append(("rotation", rot["times"], q, interp))
        tr = d["translations"]
        if tr.get("times") is not None:
            vals = coords.pos_to_godot(tr["values"])
            out.append(_hermite_track("translation", tr, vals, lambda v: coords.pos_to_godot(v), self.rep))
        sc = d["scales"]
        if sc.get("times") is not None:
            s = np.repeat(sc["values"].reshape(-1, 1), 3, axis=1)
            out.append(_hermite_track("scale", sc, s, lambda v: np.repeat(np.asarray(v).reshape(-1, 1), 3, axis=1), self.rep))
        return out


def _fix_quat_signs(q: np.ndarray) -> np.ndarray:
    q = q.copy()
    for i in range(1, len(q)):
        if np.dot(q[i], q[i - 1]) < 0:
            q[i] = -q[i]
    return q


def _sample_scalar(g: dict, t: float) -> float:
    times = g["times"]
    vals = g["values"].reshape(-1)
    if times is None or len(times) == 0:
        return 0.0
    if t <= times[0]:
        return float(vals[0])
    if t >= times[-1]:
        return float(vals[-1])
    i = int(np.searchsorted(times, t) - 1)
    t0, t1 = times[i], times[i + 1]
    x = (t - t0) / (t1 - t0) if t1 > t0 else 0
    if g["interp"] == 5:
        return float(vals[i])
    if g["interp"] == 2:
        a, b = vals[i], vals[i + 1]
        m0, m1 = g["out"].reshape(-1)[i], g["in"].reshape(-1)[i + 1]
        x2, x3 = x * x, x * x * x
        return float((2 * x3 - 3 * x2 + 1) * a + (x3 - 2 * x2 + x) * m0 + (-2 * x3 + 3 * x2) * b + (x3 - x2) * m1)
    return float(vals[i] + (vals[i + 1] - vals[i]) * x)


def _hermite_track(path: str, g: dict, vals: np.ndarray, conv, rep: Report):
    times = g["times"]
    interp = g["interp"]
    if interp == 5:
        return (path, times, vals, "STEP")
    if interp in (2, 3) and len(times) >= 2:
        n = len(times)
        if interp == 2:
            tin, tout = conv(g["in"]), conv(g["out"])
        else:
            tin, tout = _tbc_tangents(times, vals, g["tbc"])
            tin, tout = np.asarray(tin), np.asarray(tout)
            rep.note("lossy", f"klucze TBC ({path}) zamienione na CUBICSPLINE")
        # styczne NIF odnoszą się do znormalizowanego przedziału; glTF: na sekundę (mnożone przez Δt)
        dt_prev = np.r_[times[1] - times[0], np.diff(times)]
        dt_next = np.r_[np.diff(times), times[-1] - times[-2]]
        dt_prev = np.where(dt_prev > 0, dt_prev, 1)
        dt_next = np.where(dt_next > 0, dt_next, 1)
        a = np.asarray(tin) / dt_prev[:, None]
        b = np.asarray(tout) / dt_next[:, None]
        out = np.stack([a, vals, b], axis=1).reshape(n * 3, -1)
        return (path, times, out, "CUBICSPLINE")
    return (path, times, vals, "LINEAR")


def _tbc_tangents(times, vals, tbc):
    """Styczne Kochanka–Bartelsa (w jednostkach znormalizowanego przedziału)."""
    n = len(times)
    tin = np.zeros_like(vals)
    tout = np.zeros_like(vals)
    for i in range(n):
        T, C, B = (float(x) for x in tbc[i])
        p = vals[i]
        pm = vals[i - 1] if i > 0 else p
        pp = vals[i + 1] if i < n - 1 else p
        d0 = p - pm
        d1 = pp - p
        tout[i] = 0.5 * ((1 - T) * (1 + B) * (1 + C) * d0 + (1 - T) * (1 - B) * (1 - C) * d1)
        tin[i] = 0.5 * ((1 - T) * (1 + B) * (1 - C) * d0 + (1 - T) * (1 - B) * (1 + C) * d1)
    return tin, tout


def convert_nif_bytes(data: bytes, name: str, resolve_texture: Optional[TextureResolver] = None):
    from .nif.reader import parse
    nif = parse(data, name)
    return NifToGltf(nif, name, resolve_texture).convert()
