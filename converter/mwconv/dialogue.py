"""Dialogi, zadania i dziennik (etap 6): rekordy DIAL + INFO → world/records/dialogue.json.

Układ pól i scalanie wg OpenMW 0.51 (components/esm3/loaddial.cpp, loadinfo.cpp, infoorder.hpp,
dialoguecondition.cpp; apps/openmw/mwworld/esmstore.cpp, store.cpp) – własna implementacja:
- INFO należy do ostatniego wczytanego DIAL (każdy inny rekord zeruje bieżący dialog);
- kolejność odpowiedzi to lista z PNAM (poprzednik): wstawienie za poprzednikiem, nieznany poprzednik → koniec,
  pusty → początek; ta sama pozycja i ten sam poprzednik → podmiana w miejscu, inny → przeniesienie;
- INFO z DELE trzymane do końca wczytywania (lista musi pozostać spójna), potem usuwane;
- DIAL z DELE usuwa dialog; ponowny DIAL w późniejszym pliku dopisuje odpowiedzi do istniejącego
  (identyfikator i pisownia z pierwszego);
- warunki SCVR (+ INTV/FLTV) dekodowane do nazw funkcji; skrypt wyniku (BNAM) kompilowany jak skrypty (mwscript).
"""
from __future__ import annotations

import struct
from typing import Optional

SCHEMA_VERSION = 1
DIAL_TYPES = ["topic", "voice", "greeting", "persuasion", "journal"]

# kody funkcji warunków (ESM::DialogueCondition::Function, 0..73) – nazwy jak w OpenMW, małymi literami
FUNCTIONS = [
    "facreactionlowest", "facreactionhighest", "rankrequirement", "reputation", "health_percent", "pcreputation",
    "pclevel", "pchealthpercent", "pcmagicka", "pcfatigue", "pcstrength", "pcblock", "pcarmorer", "pcmediumarmor",
    "pcheavyarmor", "pcbluntweapon", "pclongblade", "pcaxe", "pcspear", "pcathletics", "pcenchant",
    "pcdestruction", "pcalteration", "pcillusion", "pcconjuration", "pcmysticism", "pcrestoration", "pcalchemy",
    "pcunarmored", "pcsecurity", "pcsneak", "pcacrobatics", "pclightarmor", "pcshortblade", "pcmarksman",
    "pcmercantile", "pcspeechcraft", "pchandtohand", "pcgender", "pcexpelled", "pccommondisease",
    "pcblightdisease", "pcclothingmodifier", "pccrimelevel", "samesex", "samerace", "samefaction",
    "factionrankdifference", "detected", "alarmed", "choice", "pcintelligence", "pcwillpower", "pcagility",
    "pcspeed", "pcendurance", "pcpersonality", "pcluck", "pccorprus", "weather", "pcvampire", "level", "attacked",
    "talkedtopc", "pchealth", "creaturetarget", "friendhit", "fight", "hello", "alarm", "flee", "shouldattack",
    "werewolf", "pcwerewolfkills"]
# typ zmiennej (znak 2) → funkcja
VAR_FUNCTIONS = {"2": "global", "3": "local", "4": "journal", "5": "item", "6": "dead", "7": "notid",
                 "8": "notfaction", "9": "notclass", "A": "notrace", "B": "notcell", "C": "notlocal"}
COMPARISONS = ["==", "!=", ">", ">=", "<", "<="]


def _zs(b: Optional[bytes]) -> str:
    if not b:
        return ""
    return b.split(b"\0", 1)[0].decode("cp1252", "replace")


def _text(b: Optional[bytes]) -> str:
    """Tekst odpowiedzi (NAME, BNAM): bez kończącego zera, CP1252."""
    if not b:
        return ""
    return b.rstrip(b"\0").decode("cp1252", "replace")


def parse_condition(rule: str, value) -> Optional[dict]:
    """SCVR → warunek lub None (nieprawidłowy – pomijany jak w OpenMW, z ostrzeżeniem)."""
    if len(rule) < 5 or not ("0" <= rule[4] <= "5") or value is None:
        return None
    index = int(rule[0]) if rule[0].isdigit() else 0
    kind = rule[1]
    if kind == "1":
        try:
            code = int(rule[2:4])
        except ValueError:
            return None
        if not 0 <= code < len(FUNCTIONS):
            return None
        func = FUNCTIONS[code]
    elif kind in VAR_FUNCTIONS:
        if len(rule) == 5:
            return None
        func = VAR_FUNCTIONS[kind]
    else:
        return None
    o = {"index": index, "func": func, "cmp": COMPARISONS[int(rule[4])], "value": value}
    if kind != "1":
        o["name"] = rule[5:]
        o["vtype"] = rule[2]
    return o


def decode_info(rec) -> dict:
    o: dict = {"id": _zs(rec.get("INAM")), "prev": _zs(rec.get("PNAM")), "next": _zs(rec.get("NNAM"))}
    conds: list = []
    bad = 0
    pending = None
    for s in rec.subs:
        n, d = s.name, s.data
        if pending is not None and n not in ("INTV", "FLTV"):
            bad += 1                                     # SCVR bez wartości
            pending = None
        if n == "DATA" and len(d) >= 12:
            typ, disp, rank, gender, pcrank = struct.unpack_from("<iibbb", d, 0)
            o.update(type=typ, disposition=disp, rank=rank, gender=gender, pcrank=pcrank)
        elif n == "ONAM":
            o["actor"] = _zs(d)
        elif n == "RNAM":
            o["race"] = _zs(d)
        elif n == "CNAM":
            o["class"] = _zs(d)
        elif n == "FNAM":
            f = _zs(d)
            if f == "FFFF":
                o["factionless"] = True
            o["faction"] = f
        elif n == "ANAM":
            o["cell"] = _zs(d)
        elif n == "DNAM":
            o["pcfaction"] = _zs(d)
        elif n == "SNAM":
            o["sound"] = _zs(d)
        elif n == "NAME":
            o["text"] = _text(d)
        elif n == "SCVR":
            pending = _text(d)
        elif n in ("INTV", "FLTV") and pending is not None:
            if len(d) >= 4:
                v = struct.unpack_from("<i" if n == "INTV" else "<f", d, 0)[0]
                c = parse_condition(pending, v)
                if c is not None:
                    if n == "FLTV":
                        c["float"] = True
                    conds.append(c)
                else:
                    bad += 1
            pending = None
        elif n == "BNAM":
            o["result"] = _text(d)
        elif n == "QSTN":
            o["quest"] = "name"
        elif n == "QSTF":
            o["quest"] = "finished"
        elif n == "QSTR":
            o["quest"] = "restart"
    if pending is not None:
        bad += 1
    o.setdefault("type", 0)
    o.setdefault("disposition", 0)
    o.setdefault("rank", -1)
    o.setdefault("gender", -1)
    o.setdefault("pcrank", -1)
    if conds:
        o["conditions"] = conds
    if bad:
        o["bad_conditions"] = bad
    return o


class InfoOrder:
    """Port ESM::InfoOrder: lista odpowiedzi uporządkowana wg PNAM."""

    def __init__(self):
        self.items: list = []       # [info]
        self.deleted: dict = {}     # id_lower → bool

    def _pos(self, key: str) -> int:
        for i, it in enumerate(self.items):
            if it["id"].lower() == key:
                return i
        return -1

    def insert(self, info: dict, deleted: bool) -> None:
        key = info["id"].lower()
        cur = self._pos(key)
        prev = info.get("prev", "").lower()
        if cur >= 0 and self.items[cur].get("prev", "").lower() == prev:
            self.items[cur] = info
            self.deleted[key] = deleted
            return
        if cur >= 0:                                     # przeniesienie: najpierw wyjmij
            self.items.pop(cur)
        if not prev:
            before = 0
        else:
            p = self._pos(prev)
            before = p + 1 if p >= 0 else len(self.items)
        self.items.insert(before, info)
        self.deleted[key] = deleted

    def finish(self) -> list:
        return [it for it in self.items if not self.deleted.get(it["id"].lower(), False)]


class DialogueStore:
    """Zbiera DIAL/INFO w kolejności ładowania. `feed(rec, source)` dla każdego rekordu pliku."""

    def __init__(self):
        self.dialogues: dict = {}   # id_lower → {"id", "type", "order": InfoOrder, "source", "sources"}
        self.cur: Optional[dict] = None
        self.orphan_infos = 0
        self.compile_errors = 0

    def feed(self, rec, source: str) -> None:
        if rec.type == "DIAL":
            name = _zs(rec.get("NAME"))
            key = name.lower()
            if rec.deleted:
                self.dialogues.pop(key, None)
                self.cur = None
                return
            d = rec.get("DATA")
            typ = d[0] if d is not None and len(d) == 1 else -1
            dial = self.dialogues.get(key)
            if dial is None:
                dial = {"id": name, "type": typ, "order": InfoOrder(), "source": source, "sources": [source]}
                self.dialogues[key] = dial
            else:
                dial["type"] = typ
                if source not in dial["sources"]:
                    dial["sources"].append(source)
            self.cur = dial
        elif rec.type == "INFO":
            if self.cur is None:
                self.orphan_infos += 1
                return
            info = decode_info(rec)
            info["source"] = source
            self.cur["order"].insert(info, bool(rec.deleted))
        else:
            self.cur = None

    def finish(self) -> dict:
        """→ {"dialogues": {id_lower: {...}}, "order": [id_lower posortowane]} (skrypty wyniku skompilowane)."""
        from .mwscript import compile_script
        out: dict = {}
        for key, d in self.dialogues.items():
            infos = d["order"].finish()
            for info in infos:
                src = info.get("result", "")
                if src.strip():
                    c = compile_script(src, f"dialog:{d['id']}:{info['id']}")
                    info["result_body"] = c["body"]
                    if c["functions"]:
                        info["result_functions"] = c["functions"]
                    if c["errors"]:
                        info["result_errors"] = c["errors"]
                        self.compile_errors += 1
            t = d["type"]
            out[key] = {"id": d["id"], "type": DIAL_TYPES[t] if 0 <= t < len(DIAL_TYPES) else "unknown",
                        "source": d["source"], "sources": d["sources"], "infos": infos}
        return {"dialogues": out, "order": sorted(out)}


def export(result: dict, wdir, write_json) -> dict:
    dials = result["dialogues"]
    counts: dict = {"DIAL": len(dials), "INFO": sum(len(d["infos"]) for d in dials.values())}
    by_type: dict = {}
    for d in dials.values():
        by_type[d["type"]] = by_type.get(d["type"], 0) + 1
    counts["by_type"] = by_type
    write_json(wdir / "records" / "dialogue.json", {
        "format": "mwgodot-dialogue", "version": SCHEMA_VERSION, "order": result["order"],
        "dialogues": {k: dials[k] for k in result["order"]}})
    return counts
