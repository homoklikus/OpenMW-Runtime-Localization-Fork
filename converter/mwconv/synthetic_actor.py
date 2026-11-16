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
    ("Shield Bone", "Bip01 L Hand", (5, 0, 0)),
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
    # etap 10: klucze dźwięku w grupie (kroki NPC wg butów, dźwięk nazwany)
    tk = nb.add("NiTextKeyExtraData", keys=[(0.0, "Idle: Start"), (0.5, "SoundGen: Left"),
                                           (1.0, "Sound: Item Misc Up"), (1.5, "SoundGen: Right 0.5 1.2"),
                                           (2.0, "Idle: Stop")])
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
    # ekwipunek (etap 2c)
    "meshes/a/a_synth_helm.nif": lambda: make_rigid("A_Synth_Helm", (26, 26, 14), (0, 0, 22)),
    "meshes/a/a_synth_cuirass.nif": lambda: make_rigid("A_Synth_Cuirass", (46, 30, 50), (0, 0, 0)),
    "meshes/a/a_synth_shield.nif": lambda: make_rigid("A_Synth_Shield", (4, 50, 60), (0, 0, 0)),
    "meshes/a/a_synth_greaves.nif": lambda: make_rigid("A_Synth_Greaves", (20, 20, 40), (0, 0, -20)),
    "meshes/c/c_synth_shirt_cheap.nif": lambda: make_rigid("C_Synth_Shirt_Cheap", (44, 28, 46), (0, 0, 0)),
    "meshes/c/c_synth_shirt_fine.nif": lambda: make_rigid("C_Synth_Shirt_Fine", (44, 28, 46), (0, 0, 0)),
    "meshes/w/w_synth_sword.nif": lambda: make_rigid("W_Synth_Sword", (4, 4, 90), (0, 0, 45)),
    # etap 3: pochodnia, skrzynia, przedmioty
    "meshes/l/l_synth_torch.nif": lambda: make_rigid("L_Synth_Torch", (4, 4, 40), (0, 0, 20)),
    "meshes/o/synth_chest.nif": lambda: make_rigid("Synth_Chest", (60, 40, 40), (0, 0, 20)),
    "meshes/m/misc_synth_spoon.nif": lambda: make_rigid("Misc_Synth_Spoon", (4, 16, 2), (0, 0, 1)),
    # etap 5: obiekty ze skryptami
    "meshes/x/synth_banner.nif": lambda: make_rigid("Synth_Banner", (10, 60, 120), (0, 0, 60)),
    "meshes/x/synth_lever.nif": lambda: make_rigid("Synth_Lever", (10, 10, 60), (0, 0, 30)),
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
# części ciała przedmiotów: id → (MP_*, model, typ 1 ubranie / 2 zbroja)
ITEM_BODYPARTS = {
    "a_synth_helm": (1, "a\\a_synth_helm.nif", 2),
    "a_synth_cuirass": (3, "a\\a_synth_cuirass.nif", 2),
    "a_synth_greaves": (12, "a\\a_synth_greaves.nif", 2),
    "c_synth_shirt_cheap": (3, "c\\c_synth_shirt_cheap.nif", 1),
    "c_synth_shirt_fine": (3, "c\\c_synth_shirt_fine.nif", 1),
}
# zbroje: id → (typ, waga, wartość, wytrzymałość, pancerz, model, [(PRT, część męska)])
ARMORS = {
    "synth_helm": (0, 3.0, 50, 100, 10, "a\\a_synth_helm.nif", [(1, "a_synth_helm")]),
    "synth_cuirass": (1, 18.0, 80, 200, 12, "a\\a_synth_cuirass.nif", [(3, "a_synth_cuirass")]),
    "synth_shield": (8, 6.0, 40, 100, 8, "a\\a_synth_shield.nif", []),                 # bez części: model przedmiotu
    "synth_greaves_weak": (4, 5.0, 5, 100, 0, "a\\a_synth_greaves.nif", [(21, "a_synth_greaves")]),  # gorsze niż bez zbroi
}
# ubrania: id → (typ, wartość, model, [(PRT, część męska)])
CLOTHES = {
    "synth_shirt_cheap": (2, 2, "c\\c_synth_shirt_cheap.nif", [(3, "c_synth_shirt_cheap")]),
    "synth_shirt_fine": (2, 30, "c\\c_synth_shirt_fine.nif", [(3, "c_synth_shirt_fine")]),
    "synth_shirt_rag": (2, 1, "c\\c_synth_shirt_cheap.nif", [(3, "c_synth_shirt_cheap")]),
}
GUARD_INVENTORY = ["synth_shirt_cheap", "synth_shirt_fine", "synth_shirt_rag", "synth_greaves_weak", "synth_sword",
                   "l_synth_helm", "synth_cuirass", "synth_shield", "synth_torch"]
# listy poziomowane: id → (flagi, szansa „brak”, [(id, poziom)])  (flagi LEVI: 1 każdy, 2 wszystkie poziomy)
LEVELED = {
    "l_synth_helm": (0, 0, [("synth_helm", 1), ("synth_cuirass", 30)]),          # na poz. 1 tylko hełm
    "l_synth_loot": (1 | 2, 0, [("misc_synth_spoon", 1), ("l_synth_nested", 1)]),
    "l_synth_nested": (0, 0, [("synth_shirt_fine", 1)]),
    "l_synth_never": (0, 100, [("synth_sword", 1)]),
}
CHEST_INVENTORY = [(2, "misc_synth_spoon"), (3, "l_synth_loot"), (1, "l_synth_never"), (1, "no_such_item")]


def _race() -> bytes:
    bon = [5, 10]                                    # długie ostrza +10
    for i in range(6):
        bon += [-1, 0]
    attrs = [40, 40] * 8
    radt = struct.pack("<14i", *bon) + struct.pack("<16i", *attrs) + struct.pack("<4f", 1.0, 1.0, 1.0, 1.0) \
        + struct.pack("<i", 1)
    return W.record("RACE", [W.sub("NAME", W.zs(RACE)), W.sub("FNAM", W.zs(RACE)), W.sub("RADT", radt)])


def _body(bid, part, model, female) -> bytes:
    return W.record("BODY", [W.sub("NAME", W.zs(bid)), W.sub("MODL", W.zs(model)), W.sub("FNAM", W.zs(RACE)),
                             W.sub("BYDT", bytes([part, 0, 1 if female else 0, 0]))])


def _npc(nid, female, inventory=(), faction="", rank=0, script="", ai=(), cls="Commoner") -> bytes:
    npdt = struct.pack("<h", 3) + bytes([50, 0, rank]) + b"\0\0\0" + struct.pack("<i", 10)
    subs = [W.sub("NAME", W.zs(nid)), W.sub("FNAM", W.zs("Syntetyczna" if female else "Syntetyczny")),
            W.sub("RNAM", W.zs(RACE)), W.sub("CNAM", W.zs(cls))]
    if faction:
        subs.append(W.sub("ANAM", W.zs(faction)))
    if script:
        subs.append(W.sub("SCRI", W.zs(script)))
    subs += [
            W.sub("BNAM", W.zs("b_n_synth_m_head_01")), W.sub("KNAM", W.zs("b_n_synth_m_hair_01")),
            W.sub("NPDT", npdt), W.sub("FLAG", struct.pack("<i", (0x01 if female else 0) | 0x08 | 0x10))]
    for it in inventory:
        subs.append(W.sub("NPCO", struct.pack("<i", 1) + it.encode("latin-1").ljust(32, b"\0")))
    subs += list(ai)
    return W.record("NPC_", subs)


def _aidt(hello=0, fight=30, flee=30, alarm=0, services=0) -> bytes:
    return W.sub("AIDT", struct.pack("<HBBB", hello, fight, flee, alarm) + b"\0\0\0" + struct.pack("<i", services))


def _ai_wander(dist, dur, tod=0, idle=(0,) * 8, repeat=1) -> bytes:
    return W.sub("AI_W", struct.pack("<hhB", dist, dur, tod) + bytes(idle) + bytes([repeat]))


def _ai_travel(x, y, z, repeat=0) -> bytes:
    return W.sub("AI_T", struct.pack("<fff", x, y, z) + bytes([repeat, 0, 0, 0]))


def _item_body(bid, part, model, typ) -> bytes:
    return W.record("BODY", [W.sub("NAME", W.zs(bid)), W.sub("MODL", W.zs(model)), W.sub("FNAM", W.zs("")),
                             W.sub("BYDT", bytes([part, 0, 0, typ]))])


def _parts_subs(parts) -> list:
    out = []
    for prt, male in parts:
        out += [W.sub("INDX", bytes([prt])), W.sub("BNAM", W.zs(male))]
    return out


def _armor(aid, typ, w, val, hp, ar, model, parts) -> bytes:
    return W.record("ARMO", [W.sub("NAME", W.zs(aid)), W.sub("MODL", W.zs(model)), W.sub("FNAM", W.zs(aid)),
                             W.sub("AODT", struct.pack("<ifiiii", typ, w, val, hp, 50, ar))] + _parts_subs(parts))


def _clothing(cid, typ, val, model, parts) -> bytes:
    return W.record("CLOT", [W.sub("NAME", W.zs(cid)), W.sub("MODL", W.zs(model)), W.sub("FNAM", W.zs(cid)),
                             W.sub("CTDT", struct.pack("<ifHH", typ, 1.0, val, 10))] + _parts_subs(parts))


def _leveled(lid, flags, none, items) -> bytes:
    subs = [W.sub("NAME", W.zs(lid)), W.sub("DATA", struct.pack("<i", flags)), W.sub("NNAM", bytes([none])),
            W.sub("INDX", struct.pack("<i", len(items)))]
    for iid, lv in items:
        subs += [W.sub("INAM", W.zs(iid)), W.sub("INTV", struct.pack("<h", lv))]
    return W.record("LEVI", subs)


def _wav(path: Path, freq: float = 440.0, seconds: float = 0.1) -> None:
    import wave
    n = int(22050 * seconds)
    frames = b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * freq * i / 22050))) for i in range(n))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(frames)


# dźwięki: id SOUN → plik w Sound/
SOUNDS = {"Item Misc Up": "Fx\\item\\synth_up.wav", "Item Misc Down": "Fx\\item\\synth_down.wav",
          "LockedChest": "Fx\\trans\\synth_locked.wav", "FootBareLeft": "Fx\\foot\\synth_step.wav",
          "FootBareRight": "Fx\\foot\\synth_step.wav", "Missing Sound": "Fx\\nie_ma.wav"}


def _sound(sid, f) -> bytes:
    return W.record("SOUN", [W.sub("NAME", W.zs(sid)), W.sub("FNAM", W.zs(f)), W.sub("DATA", bytes([255, 0, 255]))])


def _stage4_records() -> list:
    """Postać gracza: rekord „player”, klasa, znak z zdolnością, umiejętności (specjalizacje)."""
    cldt = struct.pack("<15i", 0, 5, 0, 16, 5, 8, 6, 9, 7, 10, 0, 11, 1, 1, 0)
    cls = W.record("CLAS", [W.sub("NAME", W.zs("Synth Warrior")), W.sub("FNAM", W.zs("Wojownik testowy")),
                            W.sub("CLDT", cldt)])
    spell = W.record("SPEL", [W.sub("NAME", W.zs("synth_ability")), W.sub("FNAM", W.zs("Dar testowy")),
                              W.sub("SPDT", struct.pack("<iii", 1, 0, 0)),
                              W.sub("ENAM", struct.pack("<hbbiiiii", 79, -1, 7, 0, 0, 0, 25, 25)),
                              W.sub("ENAM", struct.pack("<hbbiiiii", 84, -1, -1, 0, 0, 0, 10, 10))])
    power = W.record("SPEL", [W.sub("NAME", W.zs("synth_power")), W.sub("FNAM", W.zs("Moc testowa")),
                              W.sub("SPDT", struct.pack("<iii", 5, 0, 0)),
                              W.sub("ENAM", struct.pack("<hbbiiiii", 79, -1, 0, 0, 0, 0, 50, 50))])   # moc – nie stała
    sign = W.record("BSGN", [W.sub("NAME", W.zs("Synth Sign")), W.sub("FNAM", W.zs("Znak testowy")),
                             W.sub("NPCS", b"synth_ability".ljust(32, b"\0")), W.sub("NPCS", b"synth_power".ljust(32, b"\0"))])
    skills = [W.record("SKIL", [W.sub("INDX", struct.pack("<i", i)),
                                W.sub("SKDT", struct.pack("<ii4f", attr, spec, 1, 1, 1, 1))])
              for i, attr, spec in ((5, 0, 0), (16, 1, 1), (20, 4, 2))]
    npdt = struct.pack("<h", 1) + bytes([30] * 8) + bytes([5] * 27) + b"\0" + struct.pack("<HHH", 10, 10, 10) \
        + bytes([50, 0, 0]) + b"\0" + struct.pack("<i", 0)
    player = W.record("NPC_", [W.sub("NAME", W.zs("player")), W.sub("FNAM", W.zs("Gracz")), W.sub("RNAM", W.zs(RACE)),
                               W.sub("CNAM", W.zs("Synth Warrior")), W.sub("BNAM", W.zs("b_n_synth_m_head_01")),
                               W.sub("KNAM", W.zs("b_n_synth_m_hair_01")), W.sub("NPDT", npdt),
                               W.sub("FLAG", struct.pack("<i", 0x08))])
    return [cls, spell, power, sign, player] + skills


SCRIPTS = {
    # jak skrypty Raven Rock (Colony_*): obiekt wyłączony, dopóki zmienna globalna nie osiągnie etapu
    "synth_colony": """Begin synth_colony
if ( SynthState >= 3 )
    if ( GetDisabled == 1 )
        Enable
    endif
elseif ( GetDisabled == 0 )
    Disable
endif
End""",
    "synth_lever": """Begin synth_lever
short uses
if ( OnActivate == 1 )
    set uses to uses + 1
    set SynthState to 3
    MessageBox "Dzwignia przestawiona %.0f raz" uses
    Journal synth_q 20
endif
End""",
    "synth_start": """Begin synth_start
short ran
float timer
if ( ran == 0 )
    set ran to 1
    player->AddItem misc_synth_spoon 2
    Journal synth_q 10
    SynthUnknownFunction 5
endif
set timer to timer + GetSecondsPassed
if ( timer > 1000 )
    StopScript synth_start
endif
End""",
    "main": """Begin Main
set SynthTicks to SynthTicks + 1
End""",
}


def _script_rec(name, src) -> bytes:
    schd = name.encode().ljust(32, b"\0") + struct.pack("<5i", 1, 0, 1, 0, 0)
    return W.record("SCPT", [W.sub("SCHD", schd), W.sub("SCTX", src.replace("\n", "\r\n").encode("cp1252"))])


def _stage5_records() -> list:
    recs = [_script_rec(k, v) for k, v in SCRIPTS.items()]
    for gid, typ in (("SynthState", b"s"), ("SynthTicks", b"l")):
        recs.append(W.record("GLOB", [W.sub("NAME", W.zs(gid)), W.sub("FNAM", typ), W.sub("FLTV", struct.pack("<f", 0.0))]))
    recs.append(W.record("SSCR", [W.sub("DATA", b"123456"), W.sub("NAME", W.zs("synth_start"))]))
    for aid, model, scr in (("synth_banner", "x\\synth_banner.nif", "synth_colony"),
                            ("synth_lever", "x\\synth_lever.nif", "synth_lever")):
        recs.append(W.record("ACTI", [W.sub("NAME", W.zs(aid)), W.sub("MODL", W.zs(model)), W.sub("FNAM", W.zs(aid)),
                                      W.sub("SCRI", W.zs(scr))]))
    return recs


DIALOGUE_TEXT = {
    "greet_first": "Witaj, %PCName. Pytaj o Synth Lore, jesli chcesz.",
    "greet_again": "Znowu ty, %PCName? Jestem %Name.",
    "guard_greet": "Strazniku %Rank z %Faction, czego chcesz?",
    "lore_done": "Juz wszystko wiesz.",
    "lore_ask": "Czy pomozesz mi z dzwignia?",
    "lore_yes": "Dziekuje. Opowiem ci o @Synth Secret#.",
    "lore_no": "Szkoda.",
    "secret": "To tajemnica gildii Synth Guild.",
    "secret_wait": "Najpierw mi pomoz.",
    "guild_member": "Witaj w gildii, %PCRank.",
    "guild_join": "Przyjmuje cie do gildii.",
    "picky": "Odpowiem tylko przyjaciolom.",
    "refusal": "Nie mam ochoty z toba rozmawiac.",
    "admire_ok": "Milo to slyszec.",
    "admire_fail": "Nie przekonales mnie.",
    "q_name": "Zadanie testowe",
    "q10": "Zaczalem zadanie testowe w %Cell.",
    "q20": "Przestawilem dzwignie.",
    "q30": "%Name poprosil o pomoc. Zadanie zakonczone.",
}


def _stage6_records() -> list:
    """Dialogi (etap 6): powitania, tematy z pytaniami, odmowa wg postawy, perswazja, zadanie i frakcja."""
    T = DIALOGUE_TEXT
    fadt = struct.pack("<2i", 6, 7) + b"".join(struct.pack("<5i", 30, 30, 10 * i, 5 * i, 10 * i) for i in range(10)) \
        + struct.pack("<7i", 25, 24, -1, -1, -1, -1, -1) + struct.pack("<i", 0)
    fact = W.record("FACT", [W.sub("NAME", W.zs("Synth Guild")), W.sub("FNAM", W.zs("Gildia Testowa"))]
                    + [W.sub("RNAM", W.zs(r).ljust(32, b"\0")) for r in ("Nowicjusz", "Czeladnik", "Mistrz")]
                    + [W.sub("FADT", fadt)])
    v = "synth_villager"
    return [
        fact,
        _script_rec("synth_talker", "Begin synth_talker\nshort helped\nEnd"),
        W.dial("Greeting 5", 2),
        W.info("g1", "", "g2", T["greet_first"], actor=v, conditions=[("01630", 0)]),          # TalkedToPc == 0
        W.info("g2", "g1", "g3", T["greet_again"], actor=v),
        W.info("g3", "g2", "", T["guard_greet"], faction="Synth Guild"),
        W.dial("Synth Lore", 0),
        W.info("l1", "", "l2", T["lore_done"], actor=v, conditions=[("04JX3synth_q", 30)]),   # zadanie >= 30
        W.info("l2", "l1", "l3", T["lore_yes"], actor=v, conditions=[("01500", 1)],          # Choice == 1
               result='Journal synth_q 30\nset helped to 1\nModDisposition 10'),
        W.info("l3", "l2", "l4", T["lore_no"], actor=v, conditions=[("01500", 2)],
               result="ModDisposition -10\nGoodbye"),
        W.info("l4", "l3", "", T["lore_ask"], actor=v, result='Choice "Tak" 1 "Nie" 2'),
        W.dial("Synth Secret", 0),
        W.info("s0", "", "s1", T["secret"], actor=v, conditions=[("03sX0helped", 1)]),      # zmienna lokalna == 1
        W.info("s1", "s0", "", T["secret_wait"], actor=v),
        W.dial("Synth Guild", 0),
        W.info("f1", "", "f2", T["guild_member"], pcfaction="Synth Guild"),
        W.info("f2", "f1", "", T["guild_join"], faction="Synth Guild", result='PCJoinFaction "Synth Guild"'),
        W.dial("Picky", 0),
        W.info("p1", "", "", T["picky"], actor=v, disposition=90),
        W.dial("Info Refusal", 0),
        W.info("r1", "", "", T["refusal"]),
        W.dial("Admire Success", 3), W.info("a1", "", "", T["admire_ok"]),
        W.dial("Admire Fail", 3), W.info("a2", "", "", T["admire_fail"]),
        W.dial("synth_q", 4),
        W.info("q0", "", "q10", T["q_name"], quest="name"),
        W.info("q10", "q0", "q20", T["q10"], disposition=10),
        W.info("q20", "q10", "q30", T["q20"], disposition=20),
        W.info("q30", "q20", "", T["q30"], disposition=30, quest="finished"),
    ]


# etap 7: ustawienia rozwoju postaci (wartości jak w Morrowind.esm – testy nie zależą od domyślnych w kodzie)
GMST_STAGE7 = {"fMajorSkillBonus": 0.75, "fMinorSkillBonus": 1.0, "fMiscSkillBonus": 1.25, "fSpecialSkillBonus": 0.8,
               "iLevelUpTotal": 10, "iLevelUpMajorMult": 1, "iLevelUpMinorMult": 1, "iLevelupMajorMultAttribute": 1,
               "iLevelupMinorMultAttribute": 1, "iLevelupMiscMultAttriubte": 1, "iLevelupSpecialization": 1,
               "iLevelUp01Mult": 2, "iLevelUp02Mult": 2, "iLevelUp03Mult": 2, "iLevelUp04Mult": 2, "iLevelUp05Mult": 3,
               "fLevelUpHealthEndMult": 0.1, "fRestMagicMult": 0.15, "fMinWalkSpeed": 100.0, "fMaxWalkSpeed": 200.0,
               "fAthleticsRunBonus": 1.0, "fBaseRunMultiplier": 1.75, "fEncumbranceStrMult": 5.0,
               "fEncumberedMoveEffect": 0.3, "fJumpAcrobaticsBase": 128.0, "fJumpAcroMultiplier": 4.0,
               "fJumpEncumbranceBase": 0.5, "fJumpEncumbranceMultiplier": 0.5, "fJumpRunMultiplier": 1.0,
               "fFatigueRunBase": 5.0, "fFatigueRunMult": 2.0, "fFatigueJumpBase": 5.0, "fFatigueJumpMult": 5.0,
               "fFatigueReturnBase": 2.5, "fFatigueReturnMult": 0.02, "fEndFatigueMult": 0.04,
               "fFatigueBase": 1.25, "fFatigueMult": 0.5}


def _gmst(name, v) -> bytes:
    sub = W.sub("FLTV", struct.pack("<f", v)) if isinstance(v, float) else W.sub("INTV", struct.pack("<i", v))
    return W.record("GMST", [W.sub("NAME", W.zs(name)), sub])


GMST_TRADE = {"fDispositionMod": 1.0, "fBargainOfferBase": 50.0, "fBargainOfferMulti": -4.0,
              "iBarterSuccessDisposition": 1, "iBarterFailDisposition": -1, "fBarterGoldResetDelay": 24.0,
              "fSpellValueMult": 10.0, "fEffectCostMult": 0.5, "iTrainingMod": 10, "fTravelMult": 4000.0,
              "fTravelTimeMult": 16000.0, "fMagesGuildTravel": 30,
              # walka
              "fDamageStrengthBase": 0.5, "fDamageStrengthMult": 0.1, "fCombatArmorMinMult": 0.25,
              "fUnarmoredBase1": 0.1, "fUnarmoredBase2": 0.065, "iBaseArmorSkill": 30, "fCombatInvisoMult": 0.2,
              "fMinHandToHandMult": 0.1, "fMaxHandToHandMult": 0.5, "fHandtoHandHealthPer": 0.1,
              "fCombatDistance": 128.0, "fHandToHandReach": 1.0, "fFatigueAttackBase": 2.0,
              "fFatigueAttackMult": 0.0, "fWeaponFatigueMult": 0.25, "fWeaponDamageMult": 0.1,
              "fCombatKODamageMult": 1.5, "fKnockDownMult": 0.5, "iKnockDownOddsMult": 50, "iKnockDownOddsBase": 50,
              "fProjectileMinSpeed": 400.0, "fProjectileMaxSpeed": 3000.0, "fCombatAngleXY": 60.0,
              "fCombatAngleZ": 60.0, "fLightMaxMod": 0.6, "fMedMaxMod": 0.9, "iCuirassWeight": 30}
TRADER_INVENTORY = [(5, "misc_synth_spoon"), (1, "synth_sword"), (50, "gold_001")]
TRADER_SPELLS = ["synth_bolt", "synth_ability"]


def _trader() -> bytes:
    """Kupiec: handel wszystkim, zaklęcia, trening (AIDT), podróż do miejsca w Synthville, 500 sztuk złota."""
    npdt = struct.pack("<h", 5) + bytes([50, 0, 0]) + b"\0\0\0" + struct.pack("<i", 500)
    services = 0x2000 | 0x7FF | 0x800 | 0x4000
    aidt = struct.pack("<HBBB", 30, 0, 0, 0) + b"\0\0\0" + struct.pack("<i", services)
    subs = [W.sub("NAME", W.zs("synth_trader")), W.sub("FNAM", W.zs("Kupiec testowy")), W.sub("RNAM", W.zs(RACE)),
            W.sub("CNAM", W.zs("Synth Warrior")), W.sub("BNAM", W.zs("b_n_synth_m_head_01")),
            W.sub("KNAM", W.zs("b_n_synth_m_hair_01")), W.sub("NPDT", npdt),
            W.sub("FLAG", struct.pack("<i", 0x08))]          # bez flagi autoobliczania usług – usługi z AIDT
    subs += [W.sub("NPCO", struct.pack("<i", n) + iid.encode().ljust(32, b"\0")) for n, iid in TRADER_INVENTORY]
    subs += [W.sub("NPCS", s.encode().ljust(32, b"\0")) for s in TRADER_SPELLS]
    subs.append(W.sub("AIDT", aidt))
    subs.append(W.sub("DODT", struct.pack("<6f", 3000.0, 3000.0, 900.0, 0.0, 0.0, 1.5)))
    return W.record("NPC_", subs)


def _stage7_records() -> list:
    athletics = W.record("SKIL", [W.sub("INDX", struct.pack("<i", 8)),
                                  W.sub("SKDT", struct.pack("<ii4f", 4, 2, 1.0, 0.5, 0.0, 0.0))])
    merc = W.record("SKIL", [W.sub("INDX", struct.pack("<i", 24)),
                             W.sub("SKDT", struct.pack("<ii4f", 6, 2, 1.0, 0.0, 0.0, 0.0))])
    # MGEF 14 (obrażenia od ognia: zniszczenie, koszt 5) i zaklęcie z autoobliczanym kosztem
    fire = W.record("MGEF", [W.sub("INDX", struct.pack("<i", 14)),
                             W.sub("MEDT", struct.pack("<ifiiiifff", 2, 5.0, 0, 255, 0, 0, 1.0, 1.0, 1.0))])
    bolt = W.record("SPEL", [W.sub("NAME", W.zs("synth_bolt")), W.sub("FNAM", W.zs("Ognisty pocisk")),
                             W.sub("SPDT", struct.pack("<iii", 0, 999, 1)),
                             W.sub("ENAM", struct.pack("<hbbiiiii", 14, -1, -1, 2, 0, 1, 10, 20))])
    refusal = [W.dial("Service Refusal", 0),
               W.info("sr1", "", "", "Nie handluje z takimi jak ty.", actor="synth_trader", disposition=20),
               W.dial("Greeting 5", 2), W.info("gt", "", "gw", "Czego potrzebujesz?", actor="synth_trader"),
               W.info("gw", "gt", "", "Stoj! Zlamales prawo.", actor="synth_watchman")]
    bow = W.record("WEAP", [W.sub("NAME", W.zs("synth_bow")), W.sub("FNAM", W.zs("Luk testowy")),
                            W.sub("WPDT", struct.pack("<fiHHffH", 5.0, 50, 9, 200, 1.0, 1.0, 10) + bytes([1, 10, 0, 0, 0, 0]) + struct.pack("<i", 0))])
    arrow = W.record("WEAP", [W.sub("NAME", W.zs("synth_arrow")), W.sub("FNAM", W.zs("Strzala testowa")),
                              W.sub("WPDT", struct.pack("<fiHHffH", 0.1, 1, 12, 0, 1.0, 1.0, 0) + bytes([2, 6, 0, 0, 0, 0]) + struct.pack("<i", 0))])
    return [athletics, merc, fire, bolt, bow, arrow, _trader()] + refusal + [_gmst(k, v) for k, v in {**GMST_STAGE7, **GMST_TRADE}.items()]


GMST_MAGIC = {"fPotionStrengthMult": 0.5, "fPotionT1MagMult": 1.5, "fPotionT1DurMult": 0.5, "iAlchemyMod": 2,
              "fEnchantmentMult": 0.1, "fEnchantmentChanceMult": 3.0, "fEnchantmentConstantChanceMult": 0.5,
              "fEnchantmentConstantDurationMult": 100.0, "fEnchantmentValueMult": 10.0, "iMagicItemChargeOnce": 1,
              "iMagicItemChargeStrike": 10, "iMagicItemChargeUse": 5, "iMagicItemChargeConst": 10,
              "fMagicItemRechargePerSecond": 0.05, "fSoulGemMult": 3.0, "iSoulAmountForConstantEffect": 400,
              "fNPCbaseMagickaMult": 2.0, "fTargetSpellMaxSpeed": 1000.0}


def _mgef(idx, school, cost, flags=0x600) -> bytes:
    """MGEF: szkoła, koszt bazowy, flagi z pliku (tylko modyfikowalne: 0x200 tworzenie czarów, 0x400 zaklinanie)."""
    return W.record("MGEF", [W.sub("INDX", struct.pack("<i", idx)),
                             W.sub("MEDT", struct.pack("<ifiiiifff", school, cost, flags, 200, 120, 60, 1.0, 1.0, 1.0))])


def _enam(eff, rng, mn, mx, dur, skill=-1, attr=-1, area=0) -> bytes:
    return W.sub("ENAM", struct.pack("<hbbiiiii", eff, skill, attr, rng, area, dur, mn, mx))


def _stage7d_records() -> list:
    """Magia: efekty (MGEF), zaklęcia gracza, mikstura, składniki, aparaty, zaklęcia przedmiotów, kamień dusz."""
    recs = [_mgef(23, 2, 4.0), _mgef(75, 5, 1.0), _mgef(79, 5, 1.0), _mgef(90, 5, 2.0), _mgef(58, 4, 2.0),
            _mgef(13, 0, 6.0), _mgef(39, 3, 40.0)]
    skills = [W.record("SKIL", [W.sub("INDX", struct.pack("<i", i)),
                                W.sub("SKDT", struct.pack("<ii4f", attr, 1, 1.0, 1.0, 1.0, 1.0))])
              for i, attr in ((9, 1), (10, 2), (14, 1), (15, 2))]
    spells = [("synth_heal", "Leczenie testowe", [_enam(75, 0, 5, 5, 4)]),
              ("synth_touch", "Dotyk testowy", [_enam(23, 1, 10, 10, 0)]),
              ("synth_soultrap", "Pulapka testowa", [_enam(58, 1, 0, 0, 30)]),
              ("synth_open", "Otwarcie testowe", [_enam(13, 1, 20, 20, 0)]),
              ("synth_strength", "Sila testowa", [_enam(79, 0, 10, 10, 5, attr=0)])]
    for sid, name, enams in spells:
        recs.append(W.record("SPEL", [W.sub("NAME", W.zs(sid)), W.sub("FNAM", W.zs(name)),
                                      W.sub("SPDT", struct.pack("<iii", 0, 0, 1))] + enams))
    recs.append(W.record("ALCH", [W.sub("NAME", W.zs("synth_potion")), W.sub("FNAM", W.zs("Mikstura testowa")),
                                  W.sub("MODL", W.zs("m\\misc_synth_spoon.nif")),
                                  W.sub("ALDT", struct.pack("<fii", 0.5, 15, 0)),
                                  _enam(75, 0, 10, 10, 2), _enam(79, 0, 10, 10, 5, attr=0)]))
    for iid, w, effs in (("synth_ing_a", 0.5, [(75, -1, -1), (79, -1, 0)]), ("synth_ing_b", 1.0, [(75, -1, -1), (90, -1, -1)]),
                         ("synth_ing_c", 1.5, [(23, -1, -1), (79, -1, 0)])):
        e = [x[0] for x in effs] + [-1] * (4 - len(effs))
        sk = [x[1] for x in effs] + [-1] * (4 - len(effs))
        at = [x[2] for x in effs] + [-1] * (4 - len(effs))
        recs.append(W.record("INGR", [W.sub("NAME", W.zs(iid)), W.sub("FNAM", W.zs(iid)),
                                      W.sub("IRDT", struct.pack("<fi4i4i4i", w, 1, *e, *sk, *at))]))
    for aid, typ, q in (("synth_mortar", 0, 1.0), ("synth_retort", 3, 0.5), ("synth_alembic", 1, 0.5)):
        recs.append(W.record("APPA", [W.sub("NAME", W.zs(aid)), W.sub("FNAM", W.zs(aid)),
                                      W.sub("AADT", struct.pack("<iffi", typ, q, 1.0, 10))]))
    for eid, typ, cost, charge, enams in (("synth_ench_ring", 2, 5, 50, [_enam(75, 0, 5, 5, 2)]),
                                          ("synth_ench_amulet", 3, 0, 0, [_enam(79, 0, 10, 10, 0, attr=3)]),
                                          ("synth_ench_dagger", 1, 10, 100, [_enam(23, 1, 5, 5, 0)]),
                                          ("synth_ench_scroll", 0, 0, 0, [_enam(75, 0, 30, 30, 0)])):
        recs.append(W.record("ENCH", [W.sub("NAME", W.zs(eid)), W.sub("ENDT", struct.pack("<iiii", typ, cost, charge, 0))] + enams))
    for cid, typ, ench, cap in (("synth_ring", 8, "synth_ench_ring", 0), ("synth_amulet", 9, "synth_ench_amulet", 0),
                                ("synth_plain_ring", 8, "", 500)):
        subs = [W.sub("NAME", W.zs(cid)), W.sub("FNAM", W.zs(cid)), W.sub("CTDT", struct.pack("<ifHH", typ, 0.1, 30, cap))]
        if ench:
            subs.append(W.sub("ENAM", W.zs(ench)))
        recs.append(W.record("CLOT", subs))
    wpdt = struct.pack("<fiHHffH", 3.0, 40, 0, 200, 1.0, 1.0, 10) + bytes([2, 4, 2, 4, 2, 4]) + struct.pack("<i", 0)
    recs.append(W.record("WEAP", [W.sub("NAME", W.zs("synth_dagger_fire")), W.sub("FNAM", W.zs("Sztylet testowy")),
                                  W.sub("WPDT", wpdt), W.sub("ENAM", W.zs("synth_ench_dagger"))]))
    recs.append(W.record("BOOK", [W.sub("NAME", W.zs("synth_scroll")), W.sub("FNAM", W.zs("Zwoj testowy")),
                                  W.sub("BKDT", struct.pack("<fiiii", 0.1, 20, 1, -1, 0)), W.sub("ENAM", W.zs("synth_ench_scroll"))]))
    recs.append(W.record("MISC", [W.sub("NAME", W.zs("misc_soulgem_synth")), W.sub("FNAM", W.zs("Kamien dusz testowy")),
                                  W.sub("MCDT", struct.pack("<fii", 1.0, 20, 0))]))
    return recs + skills + [_gmst(k, v) for k, v in GMST_MAGIC.items()]


GMST_STAGE8 = {"iCrimeThreshold": 1000, "iCrimeThresholdMultiplier": 10, "iCrimeAttack": 40, "iCrimeKilling": 1000,
               "fCrimeStealing": 0.5, "iCrimeTresspass": 5, "iDaysinPrisonMod": 100, "fAlarmRadius": 2000.0,
               "fPickLockMult": -1.0, "fTrapCostMult": 0.0, "iFightAttacking": 50, "iFightAttack": 100,
               "iFightKilling": 50, "fFightStealing": 50, "iFightTrespass": 30, "iGreetDistanceMultiplier": 6,
               "iGreetDuration": 4, "fGreetDistanceReset": 512.0, "fIdleChanceMultiplier": 0.75}


STAGE9_SCRIPTS = {
    "synth_cg": """Begin synth_cg
short state
float timer
if ( MenuMode == 1 )
  return
endif
if ( state == 0 )
  DisablePlayerControls
  DisablePlayerFighting
  "synth_villager"->Say "vo\\synth.wav" "Kim jestes?"
  set state to 10
elseif ( state == 10 )
  if ( "synth_villager"->SayDone == 1 )
    EnableNameMenu
    set state to 20
  endif
elseif ( state == 20 )
  EnableRaceMenu
  set state to 30
elseif ( state == 30 )
  EnableClassMenu
  set state to 40
elseif ( state == 40 )
  EnableBirthMenu
  set state to 50
elseif ( state == 50 )
  EnableStatReviewMenu
  set state to 60
elseif ( state == 60 )
  EnablePlayerControls
  EnableInventoryMenu
  ChangeWeather "Synthetic Region" 4
  if ( player->GetRace "Synth Elf" == 1 )
    set SynthState to 77
  endif
  set state to 70
endif
End""",
    "synth_paper": """Begin synth_paper
short state
short OnPCEquip
if ( OnPCAdd == 1 )
  set state to state + 1
endif
if ( OnPCEquip == 1 )
  set state to 10
  set OnPCEquip to 0
endif
End""",
}


def _stage9_records() -> list:
    """Etap 9: skrypt w stylu CharGen (menu tworzenia postaci, blokady, Say/SayDone, pogoda, GetRace) i skrypt
    przedmiotu w ekwipunku (OnPCAdd, OnPCEquip)."""
    recs = [_script_rec(k, v) for k, v in STAGE9_SCRIPTS.items()]
    recs.append(W.record("MISC", [W.sub("NAME", W.zs("synth_papers")), W.sub("FNAM", W.zs("Papiery testowe")),
                                  W.sub("MCDT", struct.pack("<fii", 0.1, 1, 0)), W.sub("SCRI", W.zs("synth_paper"))]))
    wpdt = struct.pack("<fiHHffH", 3.0, 5, 0, 300, 2.5, 1.0, 10) + bytes([1, 4, 1, 4, 1, 4]) + struct.pack("<i", 0)
    recs.append(W.record("WEAP", [W.sub("NAME", W.zs("synth_cg_dagger")), W.sub("FNAM", W.zs("Sztylet CharGen")),
                                  W.sub("WPDT", wpdt), W.sub("SCRI", W.zs("synth_paper"))]))
    return recs


# etap 10: głosy, muzyka, dźwięki otoczenia regionu (pliki WAV tworzone w write_actors)
STAGE10_FILES = {"Sound/Vo/synth/hello.wav": 0.6, "Sound/Vo/synth.wav": 0.8, "Sound/Fx/envrn/synth_wind.wav": 0.3,
                 "Music/Explore/synth_explore_a.wav": 0.5, "Music/Explore/synth_explore_b.wav": 0.5,
                 "Music/Battle/synth_battle.wav": 0.5}


BOOK_TEXT = ('<DIV ALIGN="CENTER"><FONT COLOR="000000" SIZE="3" FACE="Magic Cards">KSIEGA TESTOWA<BR><BR>'
             '<DIV ALIGN="LEFT">'
             + "".join(f"Akapit {i}: " + "slowo " * 40 + "<BR><BR>" for i in range(12))
             + '<IMG SRC="synth_pic.tga" WIDTH="64" HEIGHT="32"><BR>Koniec ksiegi.<BR>UKRYTY OGON')
NOTE_TEXT = ('<DIV ALIGN="LEFT"><FONT COLOR="000000" SIZE="3" FACE="Magic Cards">Notatka testowa %PCName.<BR>'
             '<FONT FACE="Daedric">ALMSIVI<BR>')


def _stage10_records() -> list:
    """Etap 10: kwestia głosowa „Hello” wędrowca z plikiem Vo, dźwięk otoczenia regionu (szansa 100), muzyka;
    książka z umiejętnością (wiele stron, ilustracja z BookArt) i zwój z czcionką daedryjską."""
    from .synthetic_world import REGION_WEATHER
    book = W.record("BOOK", [W.sub("NAME", W.zs("synth_book")), W.sub("MODL", W.zs("m\\misc_synth_spoon.nif")),
                             W.sub("FNAM", W.zs("Ksiega testowa")), W.sub("BKDT", struct.pack("<fiiii", 1.0, 10, 0, 8, 0)),
                             W.sub("TEXT", W.zs(BOOK_TEXT))])
    note = W.record("BOOK", [W.sub("NAME", W.zs("synth_note")), W.sub("MODL", W.zs("m\\misc_synth_spoon.nif")),
                             W.sub("FNAM", W.zs("Notatka testowa")), W.sub("BKDT", struct.pack("<fiiii", 0.1, 1, 1, -1, 0)),
                             W.sub("TEXT", W.zs(NOTE_TEXT))])
    # klasa „Warrior” (wynik pytań) – niegrywalna na liście, żeby nie zmieniać list wyboru innych testów
    warrior = W.record("CLAS", [W.sub("NAME", W.zs("Warrior")), W.sub("FNAM", W.zs("Wojownik")),
                                W.sub("CLDT", struct.pack("<15i", 0, 5, 0, 16, 5, 8, 6, 9, 7, 10, 0, 11, 1, 0, 0)),
                                W.sub("DESC", W.zs("Klasa z pytan (test)."))])
    return [book, note, warrior,W.record("SOUN", [W.sub("NAME", W.zs("Synth Wind")), W.sub("FNAM", W.zs("Fx\\envrn\\synth_wind.wav")),
                              W.sub("DATA", bytes([200, 0, 0]))]),
            W.region("Synthetic Region", "Kraina Syntetyczna", REGION_WEATHER, sounds=[("Synth Wind", 100)]),
            _script_rec("synth_music", """Begin synth_music
StreamMusic "Battle\\synth_battle.wav"
StopScript synth_music
End"""),
            W.record("SNDG", [W.sub("NAME", W.zs("synth_creature_moan")), W.sub("DATA", struct.pack("<i", 4)),
                              W.sub("CNAM", W.zs("synth_creature")), W.sub("SNAM", W.zs("Item Misc Down"))]),
            W.record("SNDG", [W.sub("NAME", W.zs("generic_left")), W.sub("DATA", struct.pack("<i", 0)),
                              W.sub("SNAM", W.zs("FootBareLeft"))]),
            W.dial("Hello", 1),
            W.info("hello_walker", "", "", "Witaj, wedrowcze.", actor="synth_walker", sound="Vo\\synth\\hello.wav")]


def _stage8_records() -> list:
    """Przestępstwa i Security: wytrych, sonda, znacznik więzienia, GMST."""
    pick = W.record("LOCK", [W.sub("NAME", W.zs("synth_lockpick")), W.sub("FNAM", W.zs("Wytrych testowy")),
                             W.sub("LKDT", struct.pack("<fifi", 0.25, 10, 1.5, 3))])
    probe = W.record("PROB", [W.sub("NAME", W.zs("synth_probe")), W.sub("FNAM", W.zs("Sonda testowa")),
                              W.sub("PBDT", struct.pack("<fifi", 0.25, 10, 1.5, 3))])
    marker = W.record("STAT", [W.sub("NAME", W.zs("PrisonMarker")), W.sub("MODL", W.zs("marker_prison.nif"))])
    levc = W.record("LEVC", [W.sub("NAME", W.zs("synth_lev_creature")), W.sub("DATA", struct.pack("<i", 0)),
                             W.sub("NNAM", bytes([0])), W.sub("INDX", struct.pack("<i", 1)),
                             W.sub("CNAM", W.zs("synth_creature")), W.sub("INTV", struct.pack("<h", 1))])
    return [pick, probe, marker, levc] + [_gmst(k, v) for k, v in GMST_STAGE8.items()]


def _stage3_records() -> list:
    torch = W.record("LIGH", [W.sub("NAME", W.zs("synth_torch")), W.sub("MODL", W.zs("l\\l_synth_torch.nif")),
                              W.sub("FNAM", W.zs("Pochodnia")),
                              W.sub("LHDT", struct.pack("<fiii", 4.0, 2, 600, 256) + bytes([255, 180, 90, 0])
                                    + struct.pack("<i", 0x2 | 0x80))])
    spoon = W.record("MISC", [W.sub("NAME", W.zs("misc_synth_spoon")), W.sub("MODL", W.zs("m\\misc_synth_spoon.nif")),
                              W.sub("FNAM", W.zs("Lyzka")), W.sub("MCDT", struct.pack("<fii", 0.5, 2, 0))])
    chest_inv = [W.sub("NPCO", struct.pack("<i", n) + iid.encode().ljust(32, b"\0")) for n, iid in CHEST_INVENTORY]
    chest = W.record("CONT", [W.sub("NAME", W.zs("synth_chest")), W.sub("MODL", W.zs("o\\synth_chest.nif")),
                              W.sub("FNAM", W.zs("Skrzynia")), W.sub("CNDT", struct.pack("<f", 100.0)),
                              W.sub("FLAG", struct.pack("<i", 0x08))] + chest_inv)
    return [torch, spoon, chest] + [_leveled(k, *v) for k, v in LEVELED.items()] + [_sound(k, v) for k, v in SOUNDS.items()]


def _weapon() -> bytes:
    wpdt = struct.pack("<fiHHffH", 10.0, 40, 1, 300, 1.0, 1.0, 10) + bytes([2, 8, 2, 9, 1, 4]) + struct.pack("<i", 0)
    return W.record("WEAP", [W.sub("NAME", W.zs("synth_sword")), W.sub("MODL", W.zs("w\\w_synth_sword.nif")),
                             W.sub("FNAM", W.zs("Miecz")), W.sub("WPDT", wpdt)])


def _creature() -> bytes:
    v = [0, 1] + [30] * 8 + [10, 0, 10, 5, 10, 0, 10, 1, 2, 1, 2, 1, 2, 0]
    return W.record("CREA", [W.sub("NAME", W.zs("synth_creature")), W.sub("FNAM", W.zs("Stworzenie testowe")),
                             W.sub("MODL", W.zs("synth\\test_skinned.nif")), W.sub("NPDT", struct.pack("<24i", *v)),
                             W.sub("FLAG", struct.pack("<i", 0x40 | 0x08))])


ACTOR_REFS = {  # refnum: (rekord, x, y, obrót z w stopniach)
    9001: ("synth_villager", 2200.0, 2400.0, 30.0),
    9002: ("synth_villager_f", 2500.0, 2400.0, -20.0),
    9003: ("synth_creature", 2800.0, 2200.0, 0.0),
    9004: ("synth_guard", 2350.0, 2700.0, 0.0),
    9005: ("synth_chest", 2000.0, 2600.0, 0.0),
    9006: ("misc_synth_spoon", 2050.0, 2500.0, 0.0),
    9007: ("synth_banner", 1900.0, 2300.0, 0.0),
    9008: ("synth_lever", 1950.0, 2250.0, 0.0),
    9009: ("synth_trader", 2400.0, 2200.0, 0.0),
    9010: ("synth_chest", 2450.0, 2150.0, 0.0),        # skrzynia kupca (właściciel synth_trader)
    9011: ("synth_walker", 2600.0, 2800.0, 0.0),       # etap 8: wędrowiec (AI_W, siatka ścieżek)
    9012: ("synth_traveler", 1800.0, 2000.0, 0.0),     # etap 8: podróżny (AI_T)
    9014: ("misc_synth_spoon", 2420.0, 2250.0, 0.0),   # etap 8: łyżka kupca (własność – kradzież)
    9015: ("synth_chest", 2500.0, 2100.0, 0.0),        # etap 8: zamknięta skrzynia kupca z pułapką
    9016: ("synth_watchman", 5200.0, 5000.0, 180.0),   # etap 8: strażnik (Guard, Alarm 100) – daleko od testów
    9017: ("prisonmarker", 5400.0, 5200.0, 90.0),      # etap 8: znacznik więzienia
    9018: ("synth_lev_creature", 5600.0, 4800.0, 0.0),  # etap 8: punkt pojawiania się stworzenia (LEVC)
    9020: ("synth_book", 2330.0, 2450.0, 0.0),        # etap 10: książka w świecie (czytanie, „Weź”)
}
REF_EXTRA = {9010: {"owner": "synth_trader"}, 9014: {"owner": "synth_trader"},
             9015: {"owner": "synth_trader", "lock_level": 20, "trap": "synth_bolt"}}


PATHGRID_XS = (1800, 2200, 2600, 3000)
PATHGRID_YS = (2000, 2400, 2800)


def pathgrid_points():
    """Siatka ścieżek Synthville (etap 8): 4 × 3 punkty połączone z sąsiadami w obie strony + osobna para
    (druga składowa spójności, jak kilka siatek w Seyda Neen)."""
    pts = [(x, y, int(height_at(x, y))) for y in PATHGRID_YS for x in PATHGRID_XS]
    edges = []
    nx = len(PATHGRID_XS)
    for j in range(len(PATHGRID_YS)):
        for i in range(nx):
            k = j * nx + i
            if i + 1 < nx:
                edges += [(k, k + 1), (k + 1, k)]
            if j + 1 < len(PATHGRID_YS):
                edges += [(k, k + nx), (k + nx, k)]
    n = len(pts)
    pts += [(5000, 5000, int(height_at(5000, 5000))), (5400, 5000, int(height_at(5400, 5000)))]
    edges += [(n, n + 1), (n + 1, n)]
    return pts, edges


def write_actors(data_dir: Path) -> dict:
    """Zasoby + mwg_actors.esp w katalogu danych świata syntetycznego (po write_world)."""
    data_dir = Path(data_dir)
    for rel, fn in MODELS.items():
        p = data_dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(fn())
    for f in set(SOUNDS.values()):
        if "nie_ma" not in f:
            _wav(data_dir / "Sound" / f.replace("\\", "/"))
    for rel, secs in STAGE10_FILES.items():
        _wav(data_dir / rel, 330.0, secs)
    # Morrowind.ini obok katalogu danych: 10 pytań o klasę (teksty testowe, nie z gry) – etap 10
    ini = ["[General]"] + [f"[Question {n}]\nQuestion=Pytanie testowe {n}?\nAnswerOne=Walka {n}\n"
                           f"AnswerTwo=Magia {n}\nAnswerThree=Skradanie {n}" for n in range(1, 11)]
    (data_dir.parent / "Morrowind.ini").write_text("\n".join(ini) + "\n", encoding="cp1252")
    from PIL import Image
    (data_dir / "BookArt").mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (64, 32), (120, 40, 40)).save(data_dir / "BookArt" / "synth_pic.tga")
    recs = [_race()] + [_body(k, *v) for k, v in BODYPARTS.items()]
    recs += [_item_body(k, *v) for k, v in ITEM_BODYPARTS.items()]
    recs += [_armor(k, *v) for k, v in ARMORS.items()] + [_clothing(k, *v) for k, v in CLOTHES.items()] + [_weapon()]
    recs += _stage3_records() + _stage4_records() + _stage5_records()
    recs += [_npc("synth_villager", False, script="synth_talker"), _npc("synth_villager_f", True), _creature(),
             _npc("synth_guard", False, GUARD_INVENTORY, faction="Synth Guild", rank=1),
             _npc("synth_walker", False, ai=[_aidt(hello=30), _ai_wander(1000, 0, idle=(0,) * 8)]),
             _npc("synth_traveler", True, ai=[_aidt(), _ai_travel(3000.0, 2800.0, height_at(3000, 2800))]),
             _npc("synth_watchman", False, ai=[_aidt(fight=30, alarm=100)], cls="Guard")]
    recs += _stage8_records()
    recs += _stage9_records() + _stage10_records()
    recs += _stage6_records() + _stage7_records() + _stage7d_records()
    refs = []
    for rn, (base, x, y, rz) in ACTOR_REFS.items():
        refs.append(W.ref_subs(rn, base, (x, y, height_at(x, y)), (0, 0, math.radians(rz)), extra=REF_EXTRA.get(rn)))
    recs.append(W.cell("Synthville", (0, 0), False, refs, region="Synthetic Region"))
    pts, edges = pathgrid_points()
    recs.append(W.pgrd("Synthville", (0, 0), pts, edges))
    esp = data_dir / "mwg_actors.esp"
    esp.write_bytes(W.header([("mwg_synthtown.esm", 0)], len(recs), desc="synthetic actors", is_master=False)
                    + b"".join(recs))
    return {"esp": esp, "refs": ACTOR_REFS}
