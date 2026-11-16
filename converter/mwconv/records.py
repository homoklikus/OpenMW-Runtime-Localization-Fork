"""Rekordy postaci, przedmiotów i ustawień (etap 1 planu): dekodery TES3 → słowniki JSON.

Układ pól wg definicji w kodzie OpenMW 0.51 (components/esm3/load*.hpp/.cpp) – własna implementacja.
Scalanie wg kolejności ładowania jak dla obiektów: późniejszy plik wygrywa, DELE usuwa, `overridden` = historia.
Wynik: world/records/<typ>.json + world/records/index.json („mwgodot-records” v1). Istniejące pliki świata
(objects.json itd.) się nie zmieniają – to nowe dane obok nich.
"""
from __future__ import annotations

import struct
from typing import Callable, Optional

ATTRIBUTES = ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
SKILLS = ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear", "athletics",
          "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration", "alchemy",
          "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman", "mercantile",
          "speechcraft", "handtohand"]
SPECIALIZATIONS = ["combat", "magic", "stealth"]
SCHEMA_VERSION = 1

# plik wyjściowy dla typu rekordu
FILES = {"NPC_": "npc", "CREA": "creature", "RACE": "race", "CLAS": "class", "FACT": "faction", "BODY": "bodypart",
         "BSGN": "birthsign", "SKIL": "skill", "WEAP": "weapon", "ARMO": "armor", "CLOT": "clothing", "BOOK": "book",
         "MISC": "misc", "APPA": "apparatus", "LOCK": "lockpick", "PROB": "probe", "REPA": "repair",
         "LIGH": "light", "GMST": "gmst", "GLOB": "global",
         # etap 3: pojemniki, listy poziomowane, pozostałe przedmioty, drzwi/aktywatory, dźwięki
         "CONT": "container", "LEVI": "leveleditem", "LEVC": "leveledcreature", "ALCH": "potion",
         "INGR": "ingredient", "DOOR": "door", "ACTI": "activator", "SOUN": "sound",
         # etap 4: czary (zdolności ras i znaków, moce, czary startowe)
         "SPEL": "spell",
         # etap 5: skrypty (drzewo składni z kompilatora mwscript) i skrypty startowe
         "SCPT": "script", "SSCR": "startscript",
         # etap 7: efekty magiczne i zaklęcia przedmiotów
         "MGEF": "magiceffect", "ENCH": "enchantment"}


def _zs(b: bytes) -> str:
    return b.split(b"\0", 1)[0].decode("cp1252", "replace")


def _common(rec, o: dict) -> dict:
    for tag, key in (("MODL", "model"), ("FNAM", "name"), ("ITEX", "icon"), ("SCRI", "script"), ("ENAM", "enchant")):
        v = rec.zstr(tag)
        if v:
            o[key] = v
    return o


def _subs(rec, name: str) -> list:
    return [s.data for s in rec.subs if s.name == name]


def _ai(rec) -> dict:
    out: dict = {}
    d = rec.get("AIDT")
    if d and len(d) >= 12:
        hello, fight, flee, alarm = struct.unpack_from("<HBBB", d, 0)
        services = struct.unpack_from("<i", d, 8)[0]
        out.update(hello=hello, fight=fight, flee=flee, alarm=alarm, services=services)
    packages = []
    for s in rec.subs:
        n, b = s.name, s.data
        if n == "AI_W" and len(b) >= 14:
            dist, dur, tod = struct.unpack_from("<hhB", b, 0)
            packages.append({"type": "wander", "distance": dist, "duration": dur, "time_of_day": tod,
                             "idle": list(b[5:13]), "repeat": bool(b[13])})
        elif n == "AI_T" and len(b) >= 13:
            x, y, z = struct.unpack_from("<fff", b, 0)
            packages.append({"type": "travel", "pos": [x, y, z], "repeat": bool(b[12])})
        elif n in ("AI_E", "AI_F") and len(b) >= 47:
            x, y, z, dur = struct.unpack_from("<fffh", b, 0)
            packages.append({"type": "escort" if n == "AI_E" else "follow", "pos": [x, y, z], "duration": dur,
                             "target": _zs(b[14:46]), "repeat": bool(b[46])})
        elif n == "AI_A" and len(b) >= 33:
            packages.append({"type": "activate", "target": _zs(b[:32]), "repeat": bool(b[32])})
        elif n == "CNDT" and packages:
            packages[-1]["cell"] = _zs(b)
    if packages:
        out["packages"] = packages
    return out


def _inventory_spells_travel(rec, o: dict) -> None:
    inv = []
    for b in _subs(rec, "NPCO"):
        if len(b) >= 36:
            inv.append({"count": struct.unpack_from("<i", b, 0)[0], "item": _zs(b[4:36])})
    if inv:
        o["inventory"] = inv
    spells = [_zs(b[:32]) for b in _subs(rec, "NPCS")]
    if spells:
        o["spells"] = spells
    travel = []
    for s in rec.subs:
        if s.name == "DODT" and len(s.data) >= 24:
            travel.append({"pos": list(struct.unpack_from("<fff", s.data, 0)),
                           "rot": list(struct.unpack_from("<fff", s.data, 12))})
        elif s.name == "DNAM" and travel:
            travel[-1]["cell"] = _zs(s.data)
    if travel:
        o["travel"] = travel


def _flags(rec, o: dict, names: dict) -> None:
    d = rec.get("FLAG")
    if d and len(d) >= 4:
        v = struct.unpack_from("<i", d, 0)[0]
        o["flags"] = v & 0xFF
        o["blood"] = ((v >> 8) & 0xFF) >> 2
        for bit, name in names.items():
            o[name] = bool(o["flags"] & bit)


def decode_npc(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    for tag, key in (("RNAM", "race"), ("CNAM", "class"), ("ANAM", "faction"), ("BNAM", "head"), ("KNAM", "hair")):
        v = rec.zstr(tag)
        if v:
            o[key] = v
    d = rec.get("NPDT")
    if d is not None and len(d) == 52:
        lvl = struct.unpack_from("<h", d, 0)[0]
        hp, mp, fat = struct.unpack_from("<HHH", d, 38)
        disp, rep, rank = d[44], d[45], d[46]
        o.update(level=lvl, attributes=list(d[2:10]), skills=list(d[10:37]), health=hp, magicka=mp, fatigue=fat,
                 disposition=disp, reputation=rep, rank=rank, gold=struct.unpack_from("<i", d, 48)[0],
                 autocalc=False)
    elif d is not None and len(d) == 12:
        lvl = struct.unpack_from("<h", d, 0)[0]
        o.update(level=lvl, disposition=d[2], reputation=d[3], rank=d[4], gold=struct.unpack_from("<i", d, 8)[0],
                 autocalc=True)
    _flags(rec, o, {0x01: "female", 0x02: "essential", 0x04: "respawn", 0x10: "autocalc_flag"})
    o["ai"] = _ai(rec)
    _inventory_spells_travel(rec, o)
    return o


def decode_creature(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    orig = rec.zstr("CNAM")
    if orig:
        o["original"] = orig
    d = rec.get("NPDT")
    if d is not None and len(d) >= 96:
        v = struct.unpack_from("<24i", d, 0)
        o.update(creature_type=v[0], level=v[1], attributes=list(v[2:10]), health=v[10], magicka=v[11],
                 fatigue=v[12], soul=v[13], combat=v[14], magic=v[15], stealth=v[16],
                 attack=[[v[17], v[18]], [v[19], v[20]], [v[21], v[22]]], gold=v[23])
    _flags(rec, o, {0x01: "bipedal", 0x02: "respawn", 0x04: "weapon_and_shield", 0x10: "swims", 0x20: "flies",
                    0x40: "walks", 0x80: "essential"})
    sc = rec.get("XSCL")
    o["scale"] = struct.unpack_from("<f", sc, 0)[0] if sc and len(sc) >= 4 else 1.0
    o["ai"] = _ai(rec)
    _inventory_spells_travel(rec, o)
    return o


def decode_race(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    desc = rec.zstr("DESC")
    if desc:
        o["description"] = desc
    d = rec.get("RADT")
    if d is not None and len(d) >= 140:
        b = struct.unpack_from("<14i", d, 0)
        o["skill_bonuses"] = [{"skill": b[2 * i], "bonus": b[2 * i + 1]} for i in range(7) if b[2 * i] >= 0]
        a = struct.unpack_from("<16i", d, 56)
        o["attributes"] = {"male": [a[2 * i] for i in range(8)], "female": [a[2 * i + 1] for i in range(8)]}
        mh, fh, mw, fw = struct.unpack_from("<4f", d, 120)
        o["height"] = {"male": mh, "female": fh}
        o["weight"] = {"male": mw, "female": fw}
        fl = struct.unpack_from("<i", d, 136)[0]
        o.update(flags=fl, playable=bool(fl & 1), beast=bool(fl & 2))
    sp = [_zs(b[:32]) for b in _subs(rec, "NPCS")]
    if sp:
        o["powers"] = sp
    return o


def decode_class(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    desc = rec.zstr("DESC")
    if desc:
        o["description"] = desc
    d = rec.get("CLDT")
    if d is not None and len(d) >= 60:
        v = struct.unpack_from("<15i", d, 0)
        o.update(attributes=[v[0], v[1]], specialization=v[2],
                 minor_skills=[v[3 + 2 * i] for i in range(5)], major_skills=[v[4 + 2 * i] for i in range(5)],
                 playable=bool(v[13] & 1), services=v[14])
    return o


def decode_faction(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    o["ranks"] = [_zs(b[:32]) for b in _subs(rec, "RNAM")]
    d = rec.get("FADT")
    if d is not None and len(d) >= 240:
        v = struct.unpack_from("<60i", d, 0)
        o["attributes"] = [v[0], v[1]]
        o["rank_requirements"] = [{"attributes": [v[2 + 5 * i], v[3 + 5 * i]], "primary_skill": v[4 + 5 * i],
                                   "favoured_skill": v[5 + 5 * i], "reputation": v[6 + 5 * i]} for i in range(10)]
        o["skills"] = [s for s in v[52:59] if s >= 0]
        o["hidden"] = bool(v[59] & 1)
    reactions = {}
    pending = None
    for s in rec.subs:
        if s.name == "ANAM":
            pending = _zs(s.data)
        elif s.name == "INTV" and pending is not None and len(s.data) >= 4:
            v = struct.unpack_from("<i", s.data, 0)[0]
            key = next((k for k in reactions if k.lower() == pending.lower()), pending)
            # frakcja wymieniona kilka razy: najniższa reakcja (jak OpenMW, loadfact.cpp)
            reactions[key] = min(v, reactions[key]) if key in reactions else v
            pending = None
    if reactions:
        o["reactions"] = reactions
    return o


def decode_bodypart(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    if "name" in o:
        o["race"] = o.pop("name")          # FNAM części ciała = rasa
    d = rec.get("BYDT")
    if d is not None and len(d) >= 4:
        o.update(part=d[0], vampire=bool(d[1]), flags=d[2], female=bool(d[2] & 1), playable=not bool(d[2] & 2),
                 mesh_type=d[3])
    return o


def decode_birthsign(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    for tag, key in (("DESC", "description"), ("TNAM", "texture")):
        v = rec.zstr(tag)
        if v:
            o[key] = v
    o["spells"] = [_zs(b[:32]) for b in _subs(rec, "NPCS")]
    return o


def decode_skill(rec, rid: str) -> dict:
    o = {"id": rid}
    d = rec.get("SKDT")
    if d is not None and len(d) >= 24:
        attr, spec = struct.unpack_from("<ii", d, 0)
        o.update(attribute=attr, specialization=spec, use_values=list(struct.unpack_from("<4f", d, 8)))
    desc = rec.zstr("DESC")
    if desc:
        o["description"] = desc
    return o


def _parts(rec) -> list:
    out = []
    for s in rec.subs:
        if s.name == "INDX" and len(s.data) >= 1:
            out.append({"part": s.data[0]})
        elif s.name == "BNAM" and out:
            out[-1]["male"] = _zs(s.data)
        elif s.name == "CNAM" and out:
            out[-1]["female"] = _zs(s.data)
    return out


def decode_weapon(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("WPDT")
    if d is not None and len(d) >= 32:
        w, val, typ, hp, spd, reach, ench = struct.unpack_from("<fiHHffH", d, 0)
        o.update(weight=w, value=val, weapon_type=struct.unpack_from("<h", d, 8)[0], health=hp, speed=spd,
                 reach=reach, enchant_capacity=ench, chop=list(d[22:24]), slash=list(d[24:26]),
                 thrust=list(d[26:28]), flags=struct.unpack_from("<i", d, 28)[0])
        o["magical"] = bool(o["flags"] & 1)
        o["silver"] = bool(o["flags"] & 2)
    return o


def decode_armor(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("AODT")
    if d is not None and len(d) >= 24:
        typ, w, val, hp, ench, ar = struct.unpack_from("<ifiiii", d, 0)
        o.update(armor_type=typ, weight=w, value=val, health=hp, enchant_capacity=ench, armor=ar)
    o["parts"] = _parts(rec)
    return o


def decode_clothing(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("CTDT")
    if d is not None and len(d) >= 12:
        typ, w, val, ench = struct.unpack_from("<ifHH", d, 0)
        o.update(clothing_type=typ, weight=w, value=val, enchant_capacity=ench)
    o["parts"] = _parts(rec)
    return o


def decode_book(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("BKDT")
    if d is not None and len(d) >= 20:
        w, val, scroll, skill, ench = struct.unpack_from("<fiiii", d, 0)
        o.update(weight=w, value=val, scroll=bool(scroll), skill=skill, enchant_capacity=ench)
    t = rec.get("TEXT")
    if t:
        o["text"] = _zs(t)
    return o


def decode_misc(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("MCDT")
    if d is not None and len(d) >= 12:
        w, val, fl = struct.unpack_from("<fii", d, 0)
        o.update(weight=w, value=val, flags=fl, key=bool(fl & 1))
    return o


def decode_apparatus(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("AADT")
    if d is not None and len(d) >= 16:
        typ, q, w, val = struct.unpack_from("<iffi", d, 0)
        o.update(apparatus_type=typ, quality=q, weight=w, value=val)
    return o


def _tool(tag: str, repair: bool = False):
    def dec(rec, rid: str) -> dict:
        o = _common(rec, {"id": rid})
        d = rec.get(tag)
        if d is not None and len(d) >= 16:
            if repair:                                   # RIDT: waga, wartość, użycia (int), jakość (float)
                w, val, uses, q = struct.unpack_from("<fiif", d, 0)
            else:                                        # LKDT/PBDT: waga, wartość, jakość (float), użycia (int)
                w, val, q, uses = struct.unpack_from("<fifi", d, 0)
            o.update(weight=w, value=val, quality=q, uses=uses)
        return o
    return dec


def decode_light(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("LHDT")
    if d is not None and len(d) >= 24:
        w, val, time, radius = struct.unpack_from("<fiii", d, 0)
        fl = struct.unpack_from("<i", d, 20)[0]
        o.update(weight=w, value=val, time=time, radius=radius, color=list(d[16:20]), flags=fl,
                 carry=bool(fl & 0x2), negative=bool(fl & 0x4), off_default=bool(fl & 0x20))
    snd = rec.zstr("SNAM")
    if snd:
        o["sound"] = snd
    return o


def decode_container(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("CNDT")
    if d is not None and len(d) >= 4:
        o["capacity"] = struct.unpack_from("<f", d, 0)[0]
    fl = rec.get("FLAG")
    if fl is not None and len(fl) >= 4:
        v = struct.unpack_from("<i", fl, 0)[0]
        o.update(flags=v, organic=bool(v & 1), respawn=bool(v & 2))
    _inventory_spells_travel(rec, o)
    return o


def _leveled(item_tag: str):
    def dec(rec, rid: str) -> dict:
        o = {"id": rid}
        d = rec.get("DATA")
        o["flags"] = struct.unpack_from("<i", d, 0)[0] if d is not None and len(d) >= 4 else 0
        n = rec.get("NNAM")
        o["chance_none"] = n[0] if n else 0
        items = []
        for s in rec.subs:
            if s.name == item_tag:
                items.append({"id": _zs(s.data), "level": 0})
            elif s.name == "INTV" and items and len(s.data) >= 2:
                items[-1]["level"] = struct.unpack_from("<h", s.data, 0)[0]
        o["items"] = items
        return o
    return dec


def _effects(rec) -> list:
    out = []
    for s in rec.subs:
        if s.name == "ENAM" and len(s.data) >= 24:
            eff, skill, attr, rng, area, dur, mn, mx = struct.unpack_from("<hbbiiiii", s.data, 0)
            out.append({"effect": eff, "skill": skill, "attribute": attr, "range": rng, "area": area,
                        "duration": dur, "min": mn, "max": mx})
    return out


def decode_potion(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    o.pop("enchant", None)                       # ENAM w ALCH to efekty, nie zaklęcie
    for tag, key in (("TEXT", "icon"),):         # ALCH: ikona w TEXT
        v = rec.zstr(tag)
        if v:
            o[key] = v
    d = rec.get("ALDT")
    if d is not None and len(d) >= 12:
        w, val, auto = struct.unpack_from("<fii", d, 0)
        o.update(weight=w, value=val, autocalc=bool(auto & 1))
    o["effects"] = _effects(rec)
    return o


def decode_ingredient(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    d = rec.get("IRDT")
    if d is not None and len(d) >= 56:
        w, val = struct.unpack_from("<fi", d, 0)
        eff = struct.unpack_from("<4i", d, 8)
        sk = struct.unpack_from("<4i", d, 24)
        at = struct.unpack_from("<4i", d, 40)
        o.update(weight=w, value=val, effects=[{"effect": eff[i], "skill": sk[i], "attribute": at[i]}
                                                for i in range(4) if eff[i] >= 0])
    return o


def decode_door(rec, rid: str) -> dict:
    o = _common(rec, {"id": rid})
    for tag, key in (("SNAM", "open_sound"), ("ANAM", "close_sound")):
        v = rec.zstr(tag)
        if v:
            o[key] = v
    return o


def decode_activator(rec, rid: str) -> dict:
    return _common(rec, {"id": rid})


def decode_sound(rec, rid: str) -> dict:
    o = {"id": rid}
    f = rec.zstr("FNAM")
    if f:
        o["file"] = f
    d = rec.get("DATA")
    if d is not None and len(d) >= 3:
        o.update(volume=d[0], min_range=d[1], max_range=d[2])
    return o


SPELL_TYPES = ["spell", "ability", "blight", "disease", "curse", "power"]


def decode_spell(rec, rid: str) -> dict:
    o = {"id": rid}
    n = rec.zstr("FNAM")
    if n:
        o["name"] = n
    d = rec.get("SPDT")
    if d is not None and len(d) >= 12:
        typ, cost, fl = struct.unpack_from("<iii", d, 0)
        o.update(spell_type=typ, type_name=SPELL_TYPES[typ] if 0 <= typ < len(SPELL_TYPES) else str(typ), cost=cost,
                 flags=fl, autocalc=bool(fl & 1), pc_start=bool(fl & 2), always_succeeds=bool(fl & 4))
    o["effects"] = _effects(rec)
    return o


def decode_script(rec, rid: str) -> dict:
    from .mwscript import compile_script
    src = (rec.get("SCTX") or b"").decode("cp1252", "replace")
    c = compile_script(src, rid)
    o = {"id": rid, "locals": c["locals"], "body": c["body"], "functions": c["functions"]}
    if c["errors"]:
        o["errors"] = c["errors"]
    if c["warnings"]:
        o["warnings"] = c["warnings"]
    return o


def decode_startscript(rec, rid: str) -> dict:
    return {"id": rid, "script": rid}


def decode_mgef(rec, rid: str) -> dict:
    """MGEF jak ESM::MagicEffect::load: id = indeks efektu; flagi stałe z tabeli OpenMW (format TES3)."""
    from .mgef import EFFECT_NAMES, HARDCODED_FLAGS, MODIFIABLE, FLAG_NAMES, SCHOOL_SKILLS
    idx = int(rid)
    o: dict = {"id": rid, "index": idx, "name": EFFECT_NAMES[idx] if 0 <= idx < len(EFFECT_NAMES) else rid}
    d = rec.get("MEDT")
    if d is not None and len(d) >= 36:
        school, cost, fl, r, g, b, sx, speed, cap = struct.unpack_from("<ifiiiifff", d, 0)
        fl &= MODIFIABLE
        if 0 <= idx < len(HARDCODED_FLAGS):
            fl |= HARDCODED_FLAGS[idx]
        o.update(school=school, school_skill=SCHOOL_SKILLS[school] if 0 <= school < 6 else -1, base_cost=cost,
                 flags=fl, color=[r, g, b], size_x=sx, speed=speed, size_cap=cap)
        for bit, nm in FLAG_NAMES.items():
            o[nm] = bool(fl & bit)
    for tag, key in (("ITEX", "icon"), ("PTEX", "particle"), ("BSND", "bolt_sound"), ("CSND", "cast_sound"),
                     ("HSND", "hit_sound"), ("ASND", "area_sound"), ("CVFX", "cast_vfx"), ("BVFX", "bolt_vfx"),
                     ("HVFX", "hit_vfx"), ("AVFX", "area_vfx"), ("DESC", "description")):
        v = rec.zstr(tag)
        if v:
            o[key] = v
    return o


def decode_enchantment(rec, rid: str) -> dict:
    o: dict = {"id": rid}
    d = rec.get("ENDT")
    if d is not None and len(d) >= 16:
        typ, cost, charge, fl = struct.unpack_from("<iiii", d, 0)
        o.update(type=typ, type_name=["cast_once", "when_strikes", "when_used", "constant"][typ] if 0 <= typ < 4 else str(typ),
                 cost=cost, charge=charge, autocalc=bool(fl & 1), flags=fl)
    o["effects"] = _effects(rec)
    return o


def decode_gmst(rec, rid: str) -> dict:
    o: dict = {"id": rid}
    if rec.get("STRV") is not None:
        o.update(type="string", value=_zs(rec.get("STRV")))
    elif rec.get("INTV") is not None and len(rec.get("INTV")) >= 4:
        o.update(type="int", value=struct.unpack_from("<i", rec.get("INTV"), 0)[0])
    elif rec.get("FLTV") is not None and len(rec.get("FLTV")) >= 4:
        o.update(type="float", value=struct.unpack_from("<f", rec.get("FLTV"), 0)[0])
    else:                                                # brak wartości: typ z prefiksu nazwy (s/i/f)
        o.update(type={"s": "string", "i": "int", "f": "float"}.get(rid[:1].lower(), "string"),
                 value="" if rid[:1].lower() == "s" else 0)
    return o


def _float_cast(value: float, bits: int) -> int:
    """Jak floatCast w OpenMW (variantimp.cpp): NaN i wartości spoza int32 → INT32_MIN, potem obcięcie do typu."""
    import math
    i = -2 ** 31 if (math.isnan(value) or value < -2 ** 31 or value > 2 ** 31 - 1) else int(value)
    if bits == 16:
        i &= 0xFFFF
        i = i - 0x10000 if i >= 0x8000 else i
    return i


def decode_global(rec, rid: str) -> dict:
    t = rec.zstr("FNAM") or "f"
    v = rec.get("FLTV")
    val = struct.unpack_from("<f", v, 0)[0] if v and len(v) >= 4 else 0.0
    typ = {"s": "short", "l": "long", "f": "float"}.get(t[:1].lower(), "float")
    if typ == "short":
        return {"id": rid, "type": typ, "value": _float_cast(val, 16)}
    if typ == "long":
        return {"id": rid, "type": typ, "value": _float_cast(val, 32)}
    return {"id": rid, "type": typ, "value": val}


def _finite(o, bad: list):
    """JSON nie zna NaN/nieskończoności – zamiana na null (liczone w raporcie)."""
    import math
    if isinstance(o, float) and not math.isfinite(o):
        bad.append(1)
        return None
    if isinstance(o, dict):
        return {k: _finite(v, bad) for k, v in o.items()}
    if isinstance(o, list):
        return [_finite(v, bad) for v in o]
    return o


DECODERS: dict[str, Callable] = {
    "NPC_": decode_npc, "CREA": decode_creature, "RACE": decode_race, "CLAS": decode_class, "FACT": decode_faction,
    "BODY": decode_bodypart, "BSGN": decode_birthsign, "SKIL": decode_skill, "WEAP": decode_weapon,
    "ARMO": decode_armor, "CLOT": decode_clothing, "BOOK": decode_book, "MISC": decode_misc,
    "APPA": decode_apparatus, "LOCK": _tool("LKDT"), "PROB": _tool("PBDT"), "REPA": _tool("RIDT", repair=True),
    "LIGH": decode_light, "GMST": decode_gmst, "GLOB": decode_global,
    "CONT": decode_container, "LEVI": _leveled("INAM"), "LEVC": _leveled("CNAM"), "ALCH": decode_potion,
    "INGR": decode_ingredient, "DOOR": decode_door, "ACTI": decode_activator, "SOUN": decode_sound,
    "SPEL": decode_spell, "SCPT": decode_script, "SSCR": decode_startscript,
    "MGEF": decode_mgef, "ENCH": decode_enchantment,
}


def record_id(rec) -> Optional[str]:
    if rec.type == "MGEF":
        d = rec.get("INDX")
        if d is None or len(d) < 4:
            return None
        i = struct.unpack_from("<i", d, 0)[0]
        return str(i) if 0 <= i < 143 else None
    if rec.type == "SCPT":
        d = rec.get("SCHD")
        return _zs(d[:32]) if d else None
    if rec.type == "SKIL":
        d = rec.get("INDX")
        if d is None or len(d) < 4:
            return None
        i = struct.unpack_from("<i", d, 0)[0]
        return SKILLS[i] if 0 <= i < len(SKILLS) else f"skill{i}"
    return rec.zstr("NAME")


def decode(rec) -> Optional[dict]:
    dec = DECODERS.get(rec.type)
    if dec is None:
        return None
    rid = record_id(rec)
    if not rid:
        return None
    return dec(rec, rid)


def merge(store: dict, rec, source: str) -> None:
    """Dołącza rekord do magazynu {typ: {id_lower: dict}} wg zasad kolejności ładowania."""
    o = decode(rec)
    if o is None:
        return
    bucket = store.setdefault(rec.type, {})
    k = o["id"].lower()
    if rec.deleted:
        bucket.pop(k, None)
        return
    o["source"] = source
    prev = bucket.get(k)
    if prev is not None:
        o["overridden"] = prev.get("overridden", []) + [prev["source"]]
    bucket[k] = o


def export(store: dict, wdir, write_json, extra_index: Optional[dict] = None) -> dict:
    """world/records/<plik>.json (id_lower → rekord) + index.json. Zwraca liczności."""
    counts = {}
    types = {}
    bad: list = []
    for typ, fname in FILES.items():
        bucket = store.get(typ, {})
        write_json(wdir / "records" / f"{fname}.json", _finite({k: bucket[k] for k in sorted(bucket)}, bad))
        counts[typ] = len(bucket)
        types[typ] = {"file": f"{fname}.json", "count": len(bucket), "schema": SCHEMA_VERSION}
    write_json(wdir / "records" / "index.json", {
        "format": "mwgodot-records", "version": 1, "types": types,
        "attributes": ATTRIBUTES, "skills": SKILLS, "specializations": SPECIALIZATIONS,
        "non_finite_floats": len(bad), **(extra_index or {})})
    counts["non_finite_floats"] = len(bad)
    return counts
