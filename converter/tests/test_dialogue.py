"""Etap 6: DIAL/INFO – kolejność odpowiedzi (PNAM), scalanie plików, warunki SCVR, skrypty wyniku."""
from mwconv.dialogue import DialogueStore, parse_condition
from mwconv.esm import writer as W
from mwconv.esm.header import iter_records


def _feed(store, blobs, source):
    store.cur = None
    for r in iter_records(b"".join(blobs), source):
        store.feed(r, source)


def _ids(res, key):
    return [i["id"] for i in res["dialogues"][key]["infos"]]


def test_order_merge_and_delete():
    s = DialogueStore()
    _feed(s, [W.dial("Background", 0),
              W.info("1", "", "2", "pierwsza"), W.info("2", "1", "3", "druga"), W.info("3", "2", "", "trzecia"),
              W.dial("Greeting 0", 2), W.info("g1", "", "", "Witaj"),
              W.stat("x", "x.nif"),
              W.info("sierota", "", "", "bez dialogu")], "A.esm")
    # plugin: nowa odpowiedź za „1”, podmiana „3” w miejscu, usunięcie „2”, nowy dialog, odpowiedź na początek
    _feed(s, [W.dial("BACKGROUND", 0),
              W.info("p1", "1", "2", "z pluginu"), W.info("3", "2", "", "trzecia zmieniona"),
              W.info("2", "p1", "3", deleted=True), W.info("p0", "", "1", "na poczatek"),
              W.dial("Usuniety", 0), W.dial("Usuniety", 0, deleted=True)], "B.esp")
    res = s.finish()
    assert _ids(res, "background") == ["p0", "1", "p1", "3"]
    bg = res["dialogues"]["background"]
    assert bg["id"] == "Background" and bg["type"] == "topic" and bg["sources"] == ["A.esm", "B.esp"]
    assert bg["infos"][3]["text"] == "trzecia zmieniona" and bg["infos"][3]["source"] == "B.esp"
    assert res["dialogues"]["greeting 0"]["type"] == "greeting"
    assert "usuniety" not in res["dialogues"]
    assert s.orphan_infos == 1
    assert res["order"] == sorted(res["order"])


def test_info_fields_conditions_result():
    s = DialogueStore()
    _feed(s, [W.dial("A1_1_FindSpymaster", 4),
              W.info("j10", "", "", "Mam zglosic sie do Caiusa.", disposition=10, quest="name"),
              W.dial("latest rumors", 0),
              W.info("r1", "", "", "Plotka.", disposition=30, rank=2, gender=1, pcrank=0, actor="caius cosades",
                     race="Imperial", cls="Monk", faction="Blades", cell="Balmora", pcfaction="Blades",
                     conditions=[("01000", 0), ("01500", 1), ("12sX2SynthState", 3), ("14JX0A1_1_FindSpymaster", 10),
                                 ("23fX5pcvar", 1.5), ("37XX0fargoth", 0), ("4BLX0Seyda", 0), ("5ZZZZ", 1), ("6", 0)],
                     result="Journal A1_1_FindSpymaster 10\nAddTopic \"Blades\"\nChoice \"Tak\" 1 \"Nie\" 2"),
              W.info("r2", "r1", "", "Brak frakcji.", faction="FFFF")], "M.esm")
    res = s.finish()
    j = res["dialogues"]["a1_1_findspymaster"]
    assert j["type"] == "journal" and j["infos"][0]["quest"] == "name" and j["infos"][0]["disposition"] == 10
    r1, r2 = res["dialogues"]["latest rumors"]["infos"]
    assert (r1["disposition"], r1["rank"], r1["gender"], r1["pcrank"]) == (30, 2, 1, 0)
    assert r1["actor"] == "caius cosades" and r1["cell"] == "Balmora" and r1["pcfaction"] == "Blades"
    c = r1["conditions"]
    assert c[0] == {"index": 0, "func": "facreactionlowest", "cmp": "==", "value": 0}
    assert c[1]["func"] == "choice" and c[1]["cmp"] == "=="
    assert c[2] == {"index": 1, "func": "global", "cmp": ">", "value": 3, "name": "SynthState", "vtype": "s"}
    assert c[3]["func"] == "journal" and c[3]["cmp"] == "==" and c[3]["name"] == "A1_1_FindSpymaster"
    assert c[4]["func"] == "local" and c[4]["cmp"] == "<=" and c[4]["value"] == 1.5 and c[4]["float"]
    assert c[5]["func"] == "notid" and c[5]["cmp"] == "==" and c[5]["name"] == "fargoth"
    assert c[6]["func"] == "notcell" and c[6]["name"] == "Seyda"
    assert len(c) == 7 and r1["bad_conditions"] == 2          # „5ZZZZ” (zły operator) i za krótka reguła
    body = r1["result_body"]
    assert body[0] == ["call", None, "journal", [["id", "a1_1_findspymaster"], ["num", 10.0]]] or body[0][2] == "journal"
    assert "choice" in r1["result_functions"] and "addtopic" in r1["result_functions"]
    assert r2.get("factionless") and r2["faction"] == "FFFF"


def test_parse_condition_rejects():
    assert parse_condition("0", 1) is None
    assert parse_condition("01999", 1) is None            # funkcja spoza 0..73
    assert parse_condition("02sX0", 1) is None            # brak nazwy zmiennej
    assert parse_condition("0Z000", 1) is None
    assert parse_condition("01730", 4)["func"] == "pcwerewolfkills"
