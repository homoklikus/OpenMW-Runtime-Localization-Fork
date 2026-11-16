"""Etap 1: rekordy postaci, przedmiotów i ustawień – dekodowanie, scalanie wg kolejności ładowania, eksport."""
import json
import struct

from mwconv import records as R
from mwconv.esm import writer as W
from mwconv.world import load_world, write_json


def z32(s):
    return s.encode().ljust(32, b"\0")


def npc():
    npdt = struct.pack("<h", 7) + bytes(range(30, 38)) + bytes(range(10, 37)) + b"\0" + struct.pack("<HHH", 55, 66, 77) \
        + bytes([40, 2, 3]) + b"\0" + struct.pack("<i", 123)
    assert len(npdt) == 52
    aidt = struct.pack("<HBBB", 30, 10, 20, 0) + b"\0\0\0" + struct.pack("<i", 0x4000 | 0x1)
    aiw = struct.pack("<hhB", 512, 5, 0) + bytes([60, 20, 10, 0, 0, 0, 0, 0]) + b"\x01"
    return W.record("NPC_", [W.sub("NAME", W.zs("fargoth")), W.sub("FNAM", W.zs("Fargoth")),
                             W.sub("MODL", W.zs("base_anim.nif")), W.sub("RNAM", W.zs("Wood Elf")),
                             W.sub("CNAM", W.zs("Commoner")), W.sub("ANAM", W.zs("")),
                             W.sub("BNAM", W.zs("b_n_wood elf_m_head_06")), W.sub("KNAM", W.zs("b_n_wood elf_m_hair_02")),
                             W.sub("NPDT", npdt), W.sub("FLAG", struct.pack("<i", 0x02 | 0x08 | (2 << 2 << 8))),
                             W.sub("NPCO", struct.pack("<i", 2) + z32("common_ring_01")),
                             W.sub("NPCS", z32("hearth heal")), W.sub("AIDT", aidt), W.sub("AI_W", aiw)])


def creature():
    v = [3, 5] + list(range(40, 48)) + [30, 10, 50, 100, 20, 30, 40, 1, 4, 2, 6, 3, 9, 15]
    return W.record("CREA", [W.sub("NAME", W.zs("mudcrab")), W.sub("FNAM", W.zs("Mudcrab")),
                             W.sub("MODL", W.zs("r\\mudcrab.nif")), W.sub("NPDT", struct.pack("<24i", *v)),
                             W.sub("FLAG", struct.pack("<i", 0x10 | 0x40 | 0x08)), W.sub("XSCL", struct.pack("<f", 1.5))])


def race():
    bon = []
    for i in range(7):
        bon += [i if i < 3 else -1, 5 * (i + 1) if i < 3 else 0]
    attrs = []
    for i in range(8):
        attrs += [40 + i, 30 + i]
    radt = struct.pack("<14i", *bon) + struct.pack("<16i", *attrs) + struct.pack("<4f", 1.0, 0.95, 1.0, 0.9) \
        + struct.pack("<i", 1)
    return W.record("RACE", [W.sub("NAME", W.zs("Dark Elf")), W.sub("FNAM", W.zs("Dark Elf")), W.sub("RADT", radt),
                             W.sub("NPCS", z32("ancestor guardian")), W.sub("DESC", W.zs("Dunmer"))])


def klass():
    v = [0, 5, 2] + [i for p in zip(range(10, 15), range(20, 25)) for i in p] + [1, 0x800]
    return W.record("CLAS", [W.sub("NAME", W.zs("Spellsword")), W.sub("FNAM", W.zs("Spellsword")),
                             W.sub("CLDT", struct.pack("<15i", *v))])


def faction():
    v = [0, 2]
    for r in range(10):
        v += [30 + r, 31 + r, 10 + r, 5 + r, r * 10]
    v += [1, 2, 3, 4, 5, 6, -1, 0]
    subs = [W.sub("NAME", W.zs("Fighters Guild")), W.sub("FNAM", W.zs("Fighters Guild"))]
    subs += [W.sub("RNAM", z32(f"Rank{r}")) for r in range(10)]
    subs += [W.sub("FADT", struct.pack("<60i", *v)), W.sub("ANAM", W.zs("Thieves Guild")),
             W.sub("INTV", struct.pack("<i", -2)), W.sub("ANAM", W.zs("thieves guild")),
             W.sub("INTV", struct.pack("<i", -1)), W.sub("ANAM", W.zs("Ashlanders")), W.sub("INTV", struct.pack("<i", -1)),
             W.sub("ANAM", W.zs("Ashlanders")), W.sub("INTV", struct.pack("<i", -3))]
    return W.record("FACT", subs)


def items():
    out = []
    wpdt = struct.pack("<fiHHffH", 12.5, 40, 1, 500, 1.25, 1.0, 50) + bytes([2, 10, 3, 12, 1, 8]) + struct.pack("<i", 2)
    out.append(W.record("WEAP", [W.sub("NAME", W.zs("iron longsword")), W.sub("FNAM", W.zs("Iron Longsword")),
                                 W.sub("MODL", W.zs("w\\iron_longsword.nif")), W.sub("ITEX", W.zs("w\\iron.dds")),
                                 W.sub("WPDT", wpdt)]))
    out.append(W.record("ARMO", [W.sub("NAME", W.zs("iron_cuirass")), W.sub("AODT", struct.pack("<ifiiii", 1, 30.0, 50, 300, 20, 15)),
                                 W.sub("INDX", b"\x03"), W.sub("BNAM", W.zs("a_iron_chest")), W.sub("CNAM", W.zs("a_iron_chest_f"))]))
    out.append(W.record("CLOT", [W.sub("NAME", W.zs("common_shirt_01")), W.sub("CTDT", struct.pack("<ifHH", 2, 1.0, 5, 10)),
                                 W.sub("INDX", b"\x03"), W.sub("BNAM", W.zs("c_m_shirt_common01"))]))
    out.append(W.record("BOOK", [W.sub("NAME", W.zs("bk_test")), W.sub("BKDT", struct.pack("<fiiii", 1.0, 10, 0, 8, 0)),
                                 W.sub("TEXT", W.zs("<DIV>Hello</DIV>"))]))
    out.append(W.record("MISC", [W.sub("NAME", W.zs("key_test")), W.sub("MCDT", struct.pack("<fii", 0.1, 0, 1))]))
    out.append(W.record("APPA", [W.sub("NAME", W.zs("apparatus_a_mortar_01")), W.sub("AADT", struct.pack("<iffi", 0, 0.5, 2.0, 20))]))
    out.append(W.record("LOCK", [W.sub("NAME", W.zs("pick_apprentice_01")), W.sub("LKDT", struct.pack("<fifi", 0.25, 20, 1.0, 25))]))
    out.append(W.record("PROB", [W.sub("NAME", W.zs("probe_apprentice_01")), W.sub("PBDT", struct.pack("<fifi", 0.25, 20, 1.0, 25))]))
    out.append(W.record("REPA", [W.sub("NAME", W.zs("hammer_repair")), W.sub("RIDT", struct.pack("<fiif", 3.0, 10, 20, 1.0))]))
    out.append(W.record("BODY", [W.sub("NAME", W.zs("b_n_dark elf_m_head_01")), W.sub("MODL", W.zs("b\\head.nif")),
                                 W.sub("FNAM", W.zs("Dark Elf")), W.sub("BYDT", bytes([0, 0, 0, 0]))]))
    out.append(W.record("BSGN", [W.sub("NAME", W.zs("Lady's Favor")), W.sub("FNAM", W.zs("The Lady")),
                                 W.sub("TNAM", W.zs("birthsigns\\lady.tga")), W.sub("NPCS", z32("lady's favor"))]))
    out.append(W.record("SKIL", [W.sub("INDX", struct.pack("<i", 5)), W.sub("SKDT", struct.pack("<ii4f", 0, 0, 1.0, 0, 0, 0)),
                                 W.sub("DESC", W.zs("Long blade"))]))
    out.append(W.record("GMST", [W.sub("NAME", W.zs("fJumpAcrobaticsBase")), W.sub("FLTV", struct.pack("<f", 128.0))]))
    out.append(W.record("GMST", [W.sub("NAME", W.zs("iLevelupTotal")), W.sub("INTV", struct.pack("<i", 10))]))
    out.append(W.record("GMST", [W.sub("NAME", W.zs("sTest")), W.sub("STRV", b"Test")]))
    out.append(W.record("GLOB", [W.sub("NAME", W.zs("PCRace")), W.sub("FNAM", b"s"), W.sub("FLTV", struct.pack("<f", 3.0))]))
    return out


def write(path, recs, masters=()):
    path.write_bytes(W.header(list(masters), len(recs)) + b"".join(recs))
    return str(path)


def test_records_decode_merge_export(tmp_path):
    base = write(tmp_path / "base.esm", [npc(), creature(), race(), klass(), faction(), *items()])
    # plugin: nadpisuje broń, usuwa książkę
    wp2 = struct.pack("<fiHHffH", 13.0, 45, 1, 500, 1.25, 1.0, 50) + bytes(6) + struct.pack("<i", 0)
    patch = write(tmp_path / "patch.esp", [
        W.record("WEAP", [W.sub("NAME", W.zs("iron longsword")), W.sub("WPDT", wp2)]),
        W.record("BOOK", [W.sub("NAME", W.zs("bk_test")), W.sub("DELE", b"\0\0\0\0")], flags=0x20)],
        masters=[("base.esm", 0)])
    w = load_world([base, patch])
    r = w.records
    n = r["NPC_"]["fargoth"]
    assert n["race"] == "Wood Elf" and n["level"] == 7 and n["attributes"] == list(range(30, 38))
    assert n["skills"] == list(range(10, 37)) and (n["health"], n["magicka"], n["fatigue"]) == (55, 66, 77)
    assert n["disposition"] == 40 and n["gold"] == 123 and n["essential"] and not n["female"] and n["blood"] == 2
    assert n["inventory"] == [{"count": 2, "item": "common_ring_01"}] and n["spells"] == ["hearth heal"]
    assert n["ai"]["hello"] == 30 and n["ai"]["services"] == 0x4001 and n["ai"]["packages"][0]["distance"] == 512
    c = r["CREA"]["mudcrab"]
    assert c["level"] == 5 and c["soul"] == 100 and c["attack"][0] == [1, 4] and c["gold"] == 15 and c["scale"] == 1.5
    assert c["swims"] and c["walks"] and not c["flies"]
    ra = r["RACE"]["dark elf"]
    assert ra["skill_bonuses"] == [{"skill": 0, "bonus": 5}, {"skill": 1, "bonus": 10}, {"skill": 2, "bonus": 15}]
    assert ra["attributes"]["male"][0] == 40 and ra["attributes"]["female"][7] == 37 and ra["playable"] and not ra["beast"]
    cl = r["CLAS"]["spellsword"]
    assert cl["minor_skills"] == [10, 11, 12, 13, 14] and cl["major_skills"] == [20, 21, 22, 23, 24] and cl["playable"]
    f = r["FACT"]["fighters guild"]
    assert f["ranks"][9] == "Rank9" and f["rank_requirements"][2]["reputation"] == 20 and f["skills"] == [1, 2, 3, 4, 5, 6]
    assert f["reactions"] == {"Thieves Guild": -2, "Ashlanders": -3}   # powtórzona frakcja: najniższa (jak OpenMW)
    wpn = r["WEAP"]["iron longsword"]
    assert wpn["weight"] == 13.0 and wpn["value"] == 45 and wpn["source"] == "patch.esp" and wpn["overridden"] == ["base.esm"]
    assert "bk_test" not in r.get("BOOK", {})
    a = r["ARMO"]["iron_cuirass"]
    assert a["armor"] == 15 and a["parts"] == [{"part": 3, "male": "a_iron_chest", "female": "a_iron_chest_f"}]
    assert r["REPA"]["hammer_repair"]["uses"] == 20 and r["REPA"]["hammer_repair"]["quality"] == 1.0
    assert r["LOCK"]["pick_apprentice_01"]["uses"] == 25 and r["MISC"]["key_test"]["key"]
    assert r["BODY"]["b_n_dark elf_m_head_01"]["race"] == "Dark Elf" and r["SKIL"]["longblade"]["attribute"] == 0
    assert r["GMST"]["fjumpacrobaticsbase"]["value"] == 128.0 and r["GMST"]["ilevelupttotal".replace("tt", "t")]["value"] == 10
    assert r["GMST"]["stest"] == {"id": "sTest", "type": "string", "value": "Test", "source": "base.esm"}
    assert r["GLOB"]["pcrace"]["type"] == "short" and r["GLOB"]["pcrace"]["value"] == 3
    counts = R.export(r, tmp_path / "w", write_json)
    idx = json.loads((tmp_path / "w/records/index.json").read_text())
    assert idx["format"] == "mwgodot-records" and idx["types"]["NPC_"]["count"] == 1 and len(idx["skills"]) == 27
    assert json.loads((tmp_path / "w/records/weapon.json").read_text())["iron longsword"]["value"] == 45
    assert counts["BOOK"] == 0 and (tmp_path / "w/records/book.json").exists()


def test_global_nan_like_openmw():
    """GLOB short/long z NaN lub spoza zakresu: jak floatCast w OpenMW (short → 0, long → INT32_MIN)."""
    assert R._float_cast(float("nan"), 16) == 0 and R._float_cast(float("nan"), 32) == -2 ** 31
    assert R._float_cast(1e20, 32) == -2 ** 31 and R._float_cast(70000.0, 16) == 70000 - 65536
    assert R._float_cast(-3.7, 16) == -3
    bad = []
    assert R._finite({"a": [1.0, float("inf")], "b": float("nan")}, bad) == {"a": [1.0, None], "b": None} and len(bad) == 2


def test_stage3_records():
    """Etap 3: pojemnik z inwentarzem, listy poziomowane (przedmioty, stworzenia), mikstura, składnik, drzwi, dźwięk."""
    def rec(typ, subs):
        data = W.record(typ, subs)
        from mwconv.esm.header import iter_records
        return next(iter_records(data))
    cont = rec("CONT", [W.sub("NAME", W.zs("chest_small")), W.sub("FNAM", W.zs("Skrzynia")), W.sub("MODL", W.zs("c.nif")),
                        W.sub("CNDT", struct.pack("<f", 150.0)), W.sub("FLAG", struct.pack("<i", 0x08 | 0x02)),
                        W.sub("NPCO", struct.pack("<i", 3) + z32("misc_spoon")),
                        W.sub("NPCO", struct.pack("<i", 1) + z32("l_random_gold"))])
    o = R.decode(cont)
    assert o["capacity"] == 150.0 and o["respawn"] and not o["organic"]
    assert o["inventory"] == [{"count": 3, "item": "misc_spoon"}, {"count": 1, "item": "l_random_gold"}]
    levi = rec("LEVI", [W.sub("NAME", W.zs("l_random_gold")), W.sub("DATA", struct.pack("<i", 3)),
                        W.sub("NNAM", bytes([25])), W.sub("INDX", struct.pack("<i", 2)),
                        W.sub("INAM", W.zs("gold_005")), W.sub("INTV", struct.pack("<h", 1)),
                        W.sub("INAM", W.zs("gold_010")), W.sub("INTV", struct.pack("<h", 5))])
    o = R.decode(levi)
    assert o == {"id": "l_random_gold", "flags": 3, "chance_none": 25,
                 "items": [{"id": "gold_005", "level": 1}, {"id": "gold_010", "level": 5}]}
    levc = rec("LEVC", [W.sub("NAME", W.zs("in_cave")), W.sub("DATA", struct.pack("<i", 1)), W.sub("NNAM", bytes([0])),
                        W.sub("INDX", struct.pack("<i", 1)), W.sub("CNAM", W.zs("rat")), W.sub("INTV", struct.pack("<h", 2))])
    assert R.decode(levc)["items"] == [{"id": "rat", "level": 2}]
    alch = rec("ALCH", [W.sub("NAME", W.zs("p_heal")), W.sub("MODL", W.zs("p.nif")), W.sub("TEXT", W.zs("p.dds")),
                        W.sub("ALDT", struct.pack("<fii", 1.0, 20, 1)),
                        W.sub("ENAM", struct.pack("<hbbiiiii", 75, -1, -1, 0, 0, 5, 10, 10))])
    o = R.decode(alch)
    assert o["icon"] == "p.dds" and "enchant" not in o and o["autocalc"] and o["effects"][0]["effect"] == 75
    ingr = rec("INGR", [W.sub("NAME", W.zs("ingred_x")), W.sub("IRDT", struct.pack("<fi4i4i4i", 0.5, 3, 1, 2, -1, -1,
                                                                                  -1, -1, -1, -1, -1, -1, -1, -1))])
    assert [e["effect"] for e in R.decode(ingr)["effects"]] == [1, 2]
    door = rec("DOOR", [W.sub("NAME", W.zs("door_x")), W.sub("SNAM", W.zs("Door Open")), W.sub("ANAM", W.zs("Door Close"))])
    assert R.decode(door)["open_sound"] == "Door Open"
    soun = rec("SOUN", [W.sub("NAME", W.zs("Item Gold Up")), W.sub("FNAM", W.zs("Fx\\item\\gold.wav")),
                        W.sub("DATA", bytes([200, 0, 255]))])
    assert R.decode(soun) == {"id": "Item Gold Up", "file": "Fx\\item\\gold.wav", "volume": 200, "min_range": 0,
                              "max_range": 255}


def test_stage4_spell():
    from mwconv.esm.header import iter_records
    spel = W.record("SPEL", [W.sub("NAME", W.zs("fortify_luck_ab")), W.sub("FNAM", W.zs("Lady's Grace")),
                             W.sub("SPDT", struct.pack("<iii", 1, 0, 2)),
                             W.sub("ENAM", struct.pack("<hbbiiiii", 79, -1, 7, 0, 0, 0, 25, 25))])
    o = R.decode(next(iter_records(spel)))
    assert o["type_name"] == "ability" and o["pc_start"] and not o["autocalc"]
    assert o["effects"] == [{"effect": 79, "skill": -1, "attribute": 7, "range": 0, "area": 0, "duration": 0,
                             "min": 25, "max": 25}]
