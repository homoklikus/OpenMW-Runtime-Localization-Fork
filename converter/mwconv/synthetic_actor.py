"""Syntetyczni aktorzy do testów etapu 2 (własne pliki, budowa jak w grze – NIE zasoby Morrowinda).

  meshes/base_anim.nif, base_anim_female.nif   szkielet Bip01 z węzłami mocowania („Head”, „Chest”, „Left Hand”…)
                                               i „manekinem” (kształt w szkielecie – w grze niewidoczny)
  meshes/xbase_anim.kf, xbase_anim_female.kf   animacje (klucze tekstowe Idle; żeńska: Idle z inną amplitudą)
  meshes/b/b_n_synth_m_skins.nif               części ze skinningiem: „Tri Chest”, „Tri Left Hand 0”, „Tri Right Hand 0”
  meshes/b/b_n_synth_m_forearm.nif             część sztywna (lewa strona – lustrzanie, jak OpenMW)
  meshes/b/b_n_synth_m_head_01.nif, _hair_01   głowa i włosy (sztywne, węzeł „Head”)
  meshes/b/b_n_synth_f_chest.nif               żeńska część tułowia (reszta – męskie jako zastępcze, jak OpenMW)
  mwg_actors.esp                               RACE, BODY, NPC_ (mężczyzna, kobieta), CREA + referencje w (0,0)
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

import numpy as np

from .esm import writer as W
from .nif.writer import NifBuilder
from .synthetic import box, quat_wxyz_axis
from .synthetic_world import height_at

# kość: (nazwa, rodzic, przesunięcie względem rodzica) – układ MW (Z w górę), jednostki gry
BONES = [
    ("Bip01", None, (0, 0, 0)),
    ("Bip01 Pelvis", "Bip01", (0, 0, 70)),
    ("Groin", "Bip01 Pelvis", (0, 0, 0)),
    ("Bip01 Spine", "Bip01 Pelvis", (0, 0, 10)),
    ("Chest", "Bip01 Spine", (0, 0, 20)),
    ("Bip01 Neck", "Bip01 Spine", (0, 0, 40)),
    ("Neck", "Bip01 Neck", (0, 0, 0)),
    ("Bip01 Head", "Bip01 Neck", (0, 0, 10)),
    ("Head", "Bip01 Head", (0, 0, 0)),
    ("Bip01 L Clavicle", "Bip01 Spine", (8, 0, 35)),
    ("Bip01 L UpperArm", "Bip01 L Clavicle", (10, 0, 0)),
    ("Left Upper Arm", "Bip01 L UpperArm", (0, 0, 0)),
    ("Bip01 L Forearm", "Bip01 L UpperArm", (25, 0, 0)),
    ("Left Forearm", "Bip01 L Forearm", (0, 0, 0)),
    ("Bip01 L Hand", "Bip01 L Forearm", (25, 0, 0)),
    ("Left Hand", "Bip01 L Hand", (0, 0, 0)),
    ("Bip01 R Clavicle", "Bip01 Spine", (-8, 0, 35)),
    ("Bip01 R UpperArm", "Bip01 R Clavicle", (-10, 0, 0)),
    ("Right Upper Arm", "Bip01 R UpperArm", (0, 0, 0)),
    ("Bip01 R Forearm", "Bip01 R UpperArm", (-25, 0, 0)),
    ("Right Forearm", "Bip01 R Forearm", (0, 0, 0)),
    ("Bip01 R Hand", "Bip01 R Forearm", (-25, 0, 0)),
    ("Right Hand", "Bip01 R Hand", (0, 0, 0)),
    ("Bip01 L Thigh", "Bip01 Pelvis", (6, 0, 0)),
    ("Bip01 R Thigh", "Bip01 Pelvis", (-6, 0, 0)),
]


def world_pos(name: str) -> np.ndarray:
    d = {b[0]: b for b in BONES}
    p = np.zeros(3)
    while name is not None:
        _n, parent, off = d[name]
        p += np.array(off, float)
        name = parent
    return p


def _bones(nb: NifBuilder, only=None) -> dict:
    idx = {}
    for name, parent, off in BONES:
        if only is not None and name not in only:
            continue
        idx[name] = nb.add("NiNode", name=name, translation=off)
    for name, parent, _off in BONES:
        if name in idx and parent in idx:
            kids = nb.blocks[idx[parent]][1].setdefault("children", [])
            kids.append(idx[name])
    return idx


def _shape(nb, name, size, center, props=None):
    V, N, UV, T = box(size, center)
    sd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    return nb.add("NiTriShape", name=name, data=sd, properties=props or [])


def make_skeleton(female: bool = False) -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name="base_anim_female.NIF" if female else "base_anim.NIF")
    idx = _bones(nb)
    man = _shape(nb, "Tri Mannequin", (40, 20, 150), (0, 0, 75))      # „manekin” – w grze ukryty
    tk = nb.add("NiTextKeyExtraData", keys=[(0.0, "Idle: Start"), (2.0, "Idle: Stop")])
    nb.set(root, children=[idx["Bip01"], man], extra=tk)
    return nb.to_bytes()


def make_kf(female: bool = False) -> bytes:
    """Idle 0–2 s: kręgosłup kołysze się (±8°), ramiona opuszczają się z pozy T (−70° wokół Y)."""
    nb = NifBuilder()
    root = nb.add("NiSequenceStreamHelper", name="")
    tk = nb.add("NiTextKeyExtraData", keys=[(0.0, "Idle: Start"), (2.0, "Idle: Stop")])
    names = ["Bip01 Spine", "Bip01 L UpperArm", "Bip01 R UpperArm"]
    strs = [nb.add("NiStringExtraData", string=n) for n in names]
    nb.set(tk, next=strs[0])
    for a, b in zip(strs, strs[1:]):
        nb.set(a, next=b)
    nb.set(root, extra=tk)
    amp = 12 if female else 8
    keys = [
        {"interp": 1, "times": [0.0, 1.0, 2.0], "values": [quat_wxyz_axis((1, 0, 0), a) for a in (-amp, amp, -amp)]},
        {"interp": 1, "times": [0.0, 2.0], "values": [quat_wxyz_axis((0, 1, 0), 70)] * 2},
        {"interp": 1, "times": [0.0, 2.0], "values": [quat_wxyz_axis((0, 1, 0), -70)] * 2},
    ]
    ctls = []
    for k in keys:
        d = nb.add("NiKeyframeData", rotations=k)
        ctls.append(nb.add("NiKeyframeController", target=-1, data=d, start=0.0, stop=2.0))
    for a, b in zip(ctls, ctls[1:]):
        nb.set(a, next=b)
    nb.set(root, controller=ctls[0])
    return nb.to_bytes()


def make_skins(female: bool = False) -> bytes:
    """Części ze skinningiem; każdy kształt w 100% na jednej kości (dane skóry: odwrotność pozy kości)."""
    nb = NifBuilder()
    root = nb.add("NiNode", name="skins")
    idx = _bones(nb)
    shapes = []
    parts = [("Tri Chest", "Bip01 Spine", (34 if female else 30, 16, 40), "Chest")]
    if not female:
        parts += [("Tri Left Hand 0", "Bip01 L Hand", (10, 8, 6), "Left Hand"),
                  ("Tri Right Hand 0", "Bip01 R Hand", (10, 8, 6), "Right Hand")]
    for name, bone, size, parent in parts:
        bp = world_pos(bone)
        center = tuple(bp + (np.array([5 if "Left" in name else -5, 0, 0]) if "Hand" in name else np.array([0, 0, 20])))
        V, N, UV, T = box(size, center)
        sd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
        skd = nb.add("NiSkinData", transform={}, bones=[{"transform": {"translation": tuple(-bp)},
                                                          "indices": np.arange(len(V)),
                                                          "weights": np.ones(len(V), np.float32)}])
        ski = nb.add("NiSkinInstance", data=skd, root=root, bones=[idx[bone]])
        sh = nb.add("NiTriShape", name=name, data=sd, skin=ski)
        nb.blocks[idx[parent]][1].setdefault("children", []).append(sh)
        shapes.append(sh)
    nb.set(root, children=[idx["Bip01"]])
    return nb.to_bytes()


def make_rigid(name: str, size, center) -> bytes:
    nb = NifBuilder()
    root = nb.add("NiNode", name=name)
    sh = _shape(nb, "Tri " + name, size, center)
    nb.set(root, children=[sh])
    return nb.to_bytes()


MODELS = {
    "meshes/base_anim.nif": lambda: make_skeleton(False),
    "meshes/base_anim_female.nif": lambda: make_skeleton(True),
    "meshes/xbase_anim.kf": lambda: make_kf(False),
    "meshes/xbase_anim_female.kf": lambda: make_kf(True),
    "meshes/b/b_n_synth_m_skins.nif": lambda: make_skins(False),
    "meshes/b/b_n_synth_f_chest.nif": lambda: make_skins(True),
    "meshes/b/b_n_synth_m_forearm.nif": lambda: make_rigid("B_N_Synth_M_Forearm", (25, 8, 8), (12.5, 0, 0)),
    "meshes/b/b_n_synth_m_head_01.nif": lambda: make_rigid("B_N_Synth_M_Head_01", (18, 18, 22), (0, 0, 11)),
    "meshes/b/b_n_synth_m_hair_01.nif": lambda: make_rigid("B_N_Synth_M_Hair_01", (20, 20, 6), (0, 0, 24)),
}

RACE = "Synth Elf"
# id części: (część MP_*, model, płeć żeńska)
BODYPARTS = {
    "b_n_synth_m_chest": (3, "b\\b_n_synth_m_skins.nif", False),
    "b_n_synth_m_hand": (5, "b\\b_n_synth_m_skins.nif", False),
    "b_n_synth_m_forearm": (7, "b\\b_n_synth_m_forearm.nif", False),
    "b_n_synth_m_head_01": (0, "b\\b_n_synth_m_head_01.nif", False),
    "b_n_synth_m_hair_01": (1, "b\\b_n_synth_m_hair_01.nif", False),
    "b_n_synth_m_hand.1st": (5, "b\\b_n_synth_m_forearm.nif", False),   # 1. osoba – w 3. osobie pomijana
    "b_n_synth_f_chest": (3, "b\\b_n_synth_f_chest.nif", True),
}


def _race() -> bytes:
    bon = []
    for i in range(7):
        bon += [-1, 0]
    attrs = [40, 40] * 8
    radt = struct.pack("<14i", *bon) + struct.pack("<16i", *attrs) + struct.pack("<4f", 1.0, 1.0, 1.0, 1.0) \
        + struct.pack("<i", 1)
    return W.record("RACE", [W.sub("NAME", W.zs(RACE)), W.sub("FNAM", W.zs(RACE)), W.sub("RADT", radt)])


def _body(bid, part, model, female) -> bytes:
    return W.record("BODY", [W.sub("NAME", W.zs(bid)), W.sub("MODL", W.zs(model)), W.sub("FNAM", W.zs(RACE)),
                             W.sub("BYDT", bytes([part, 0, 1 if female else 0, 0]))])


def _npc(nid, female) -> bytes:
    npdt = struct.pack("<h", 3) + bytes([50, 0, 0]) + b"\0\0\0" + struct.pack("<i", 10)
    return W.record("NPC_", [W.sub("NAME", W.zs(nid)), W.sub("FNAM", W.zs("Syntetyczna" if female else "Syntetyczny")),
                             W.sub("RNAM", W.zs(RACE)), W.sub("CNAM", W.zs("Commoner")),
                             W.sub("BNAM", W.zs("b_n_synth_m_head_01")), W.sub("KNAM", W.zs("b_n_synth_m_hair_01")),
                             W.sub("NPDT", npdt), W.sub("FLAG", struct.pack("<i", (0x01 if female else 0) | 0x08 | 0x10))])


def _creature() -> bytes:
    v = [0, 1] + [30] * 8 + [10, 0, 10, 5, 10, 0, 10, 1, 2, 1, 2, 1, 2, 0]
    return W.record("CREA", [W.sub("NAME", W.zs("synth_creature")), W.sub("FNAM", W.zs("Stworzenie testowe")),
                             W.sub("MODL", W.zs("synth\\test_skinned.nif")), W.sub("NPDT", struct.pack("<24i", *v)),
                             W.sub("FLAG", struct.pack("<i", 0x40 | 0x08))])


ACTOR_REFS = {  # refnum: (rekord, x, y, obrót z w stopniach)
    9001: ("synth_villager", 2200.0, 2400.0, 30.0),
    9002: ("synth_villager_f", 2500.0, 2400.0, -20.0),
    9003: ("synth_creature", 2800.0, 2200.0, 0.0),
}


def write_actors(data_dir: Path) -> dict:
    """Zasoby + mwg_actors.esp w katalogu danych świata syntetycznego (po write_world)."""
    data_dir = Path(data_dir)
    for rel, fn in MODELS.items():
        p = data_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(fn())
    recs = [_race()] + [_body(k, *v) for k, v in BODYPARTS.items()]
    recs += [_npc("synth_villager", False), _npc("synth_villager_f", True), _creature()]
    refs = []
    for rn, (base, x, y, rz) in ACTOR_REFS.items():
        refs.append(W.ref_subs(rn, base, (x, y, height_at(x, y)), (0, 0, math.radians(rz))))
    recs.append(W.cell("Synthville", (0, 0), False, refs, region="Synthetic Region"))
    esp = data_dir / "mwg_actors.esp"
    esp.write_bytes(W.header([("mwg_synthtown.esm", 0)], len(recs), desc="synthetic actors", is_master=False)
                    + b"".join(recs))
    return {"esp": esp, "refs": ACTOR_REFS}
