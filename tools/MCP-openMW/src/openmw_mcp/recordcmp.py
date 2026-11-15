"""Porównanie rekordów: dane OpenMWGodot (world/records/, etap 1 planu) vs rekordy widziane przez silnik OpenMW
(API Lua: types.*.records, core.factions, core.stats.Skill, core.getGMST, world.mwscript.getGlobalVariables).

Silnik uruchamiany jest w tle w izolowanym profilu (jak zrzuty: Raporty/mcp/rekordy/<przebieg>/), skrypt Lua
wypisuje żądane rekordy do openmw.log ("RLF_REC <rodzaj> <id> <json>"), MCP porównuje pole po polu.
Próbka: wszystkie rekordy nadpisane przez późniejsze wtyczki (przypadki graniczne, do `overridden_limit`) +
losowe (`sample`, stałe ziarno), osobno dla każdego typu.
"""
from __future__ import annotations

import json
import math
import random
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional

from . import capture

LUA_DIR = capture.LUA_DIR
ATTRS = ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
SKILLS = ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear", "athletics",
          "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration", "alchemy",
          "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman", "mercantile",
          "speechcraft", "handtohand"]
SPECS = ["combat", "magic", "stealth"]


def _id(v):
    return None if v in (None, "") else str(v).lower()


def _path(v):
    """Ścieżka VFS bez katalogu głównego, rozszerzenia i wielkości liter (OpenMW: 'meshes/w/x.nif', ESM: 'w\\x.nif')."""
    if v in (None, ""):
        return None
    s = str(v).replace("\\", "/").lower().lstrip("/")
    for pre in ("meshes/", "icons/", "textures/", "bookart/"):
        if s.startswith(pre):
            s = s[len(pre):]
    return s.rsplit(".", 1)[0]


def _skill(i):
    return SKILLS[i] if isinstance(i, int) and 0 <= i < len(SKILLS) else None


def _ids(lst, names):
    return [names[i] for i in lst if isinstance(i, int) and 0 <= i < len(names)]


# rodzaj Lua → (plik naszych rekordów, [(pole Lua, funkcja naszych danych → wartość, rodzaj porównania)])
def _g(k, f=None):
    return lambda o: (f(o.get(k)) if f else o.get(k))


COMMON_ITEM = [("name", _g("name"), "s"), ("model", _g("model", _path), "s"), ("mwscript", _g("script", _id), "id"),
               ("icon", _g("icon", _path), "s"), ("weight", _g("weight"), "f"), ("value", _g("value"), "n")]
SPEC = {
    "Weapon": ("weapon", COMMON_ITEM + [
        ("enchant", _g("enchant", _id), "id"), ("type", _g("weapon_type"), "n"), ("health", _g("health"), "n"),
        ("speed", _g("speed"), "f"), ("reach", _g("reach"), "f"), ("enchantCapacity", _g("enchant_capacity"), "ench"),
        ("chopMinDamage", lambda o: o.get("chop", [None])[0], "n"), ("chopMaxDamage", lambda o: o.get("chop", [0, None])[1], "n"),
        ("slashMinDamage", lambda o: o.get("slash", [None])[0], "n"), ("slashMaxDamage", lambda o: o.get("slash", [0, None])[1], "n"),
        ("thrustMinDamage", lambda o: o.get("thrust", [None])[0], "n"), ("thrustMaxDamage", lambda o: o.get("thrust", [0, None])[1], "n"),
        ("isMagical", _g("magical"), "b"), ("isSilver", _g("silver"), "b")]),
    "Armor": ("armor", COMMON_ITEM + [
        ("enchant", _g("enchant", _id), "id"), ("type", _g("armor_type"), "n"), ("health", _g("health"), "n"),
        ("baseArmor", _g("armor"), "n"), ("enchantCapacity", _g("enchant_capacity"), "ench")]),
    "Clothing": ("clothing", COMMON_ITEM + [
        ("enchant", _g("enchant", _id), "id"), ("type", _g("clothing_type"), "n"),
        ("enchantCapacity", _g("enchant_capacity"), "ench")]),
    "Book": ("book", COMMON_ITEM + [
        ("enchant", _g("enchant", _id), "id"), ("isScroll", _g("scroll"), "b"), ("skill", _g("skill", _skill), "id"),
        ("enchantCapacity", _g("enchant_capacity"), "ench"), ("text", _g("text"), "s")]),
    "Miscellaneous": ("misc", COMMON_ITEM + [("isKey", _g("key"), "b")]),
    "Apparatus": ("apparatus", COMMON_ITEM + [("type", _g("apparatus_type"), "n"), ("quality", _g("quality"), "f")]),
    "Lockpick": ("lockpick", COMMON_ITEM + [("maxCondition", _g("uses"), "n"), ("quality", _g("quality"), "f")]),
    "Probe": ("probe", COMMON_ITEM + [("maxCondition", _g("uses"), "n"), ("quality", _g("quality"), "f")]),
    "Repair": ("repair", COMMON_ITEM + [("maxCondition", _g("uses"), "n"), ("quality", _g("quality"), "f")]),
    "Light": ("light", COMMON_ITEM + [
        ("sound", _g("sound", _id), "id"), ("duration", _g("time"), "n"), ("radius", _g("radius"), "n"),
        ("isCarriable", _g("carry"), "b"), ("isNegative", _g("negative"), "b"), ("isOffByDefault", _g("off_default"), "b")]),
    "NPC": ("npc", [
        ("name", _g("name"), "s"), ("race", _g("race", _id), "id"), ("class", _g("class", _id), "id"),
        ("model", _g("model", _path), "s"), ("mwscript", _g("script", _id), "id"), ("hair", _g("hair", _id), "id"),
        ("head", _g("head", _id), "id"), ("baseGold", _g("gold"), "n"), ("baseDisposition", _g("disposition"), "n"),
        ("isMale", lambda o: not o.get("female", False), "b"), ("isEssential", _g("essential"), "b"),
        ("isRespawning", _g("respawn"), "b"), ("bloodType", _g("blood"), "n")]),
    "Creature": ("creature", [
        ("name", _g("name"), "s"), ("model", _g("model", _path), "s"), ("mwscript", _g("script", _id), "id"),
        ("baseCreature", _g("original", _id), "id"), ("soulValue", _g("soul"), "n"), ("type", _g("creature_type"), "n"),
        ("baseGold", _g("gold"), "n"), ("combatSkill", _g("combat"), "n"), ("magicSkill", _g("magic"), "n"),
        ("stealthSkill", _g("stealth"), "n"), ("canFly", _g("flies"), "b"), ("canSwim", _g("swims"), "b"),
        ("canWalk", _g("walks"), "b"), ("canUseWeapons", _g("weapon_and_shield"), "b"), ("isBiped", _g("bipedal"), "b"),
        ("isEssential", _g("essential"), "b"), ("isRespawning", _g("respawn"), "b"), ("bloodType", _g("blood"), "n")]),
    "Race": ("race", [
        ("name", _g("name"), "s"), ("description", _g("description"), "s"), ("isPlayable", _g("playable"), "b"),
        ("isBeast", _g("beast"), "b"),
        ("heightM", lambda o: o.get("height", {}).get("male"), "f"), ("heightF", lambda o: o.get("height", {}).get("female"), "f"),
        ("weightM", lambda o: o.get("weight", {}).get("male"), "f"), ("weightF", lambda o: o.get("weight", {}).get("female"), "f"),
        ("attrs", lambda o: {ATTRS[i]: {"male": o["attributes"]["male"][i], "female": o["attributes"]["female"][i]}
                             for i in range(8)} if "attributes" in o else None, "j"),
        ("skillBonus", lambda o: {SKILLS[b["skill"]]: b["bonus"] for b in o.get("skill_bonuses", [])
                                  if 0 <= b["skill"] < 27 and b["bonus"]}, "j")]),
    "Class": ("class", [
        ("name", _g("name"), "s"), ("description", _g("description"), "s"), ("isPlayable", _g("playable"), "b"),
        ("specialization", lambda o: SPECS[o["specialization"]] if 0 <= o.get("specialization", -1) < 3 else None, "id"),
        ("majorSkills", lambda o: sorted(_ids(o.get("major_skills", []), SKILLS)), "set"),
        ("minorSkills", lambda o: sorted(_ids(o.get("minor_skills", []), SKILLS)), "set"),
        ("attributes", lambda o: sorted(_ids(o.get("attributes", []), ATTRS)), "set")]),
    "BirthSign": ("birthsign", [
        ("name", _g("name"), "s"), ("description", _g("description"), "s"), ("texture", _g("texture", _path), "s"),
        ("spells", lambda o: sorted(_id(s) for s in o.get("spells", [])), "set")]),
    "Faction": ("faction", [
        ("name", _g("name"), "s"), ("hidden", _g("hidden"), "b"),
        ("attributes", lambda o: sorted(_ids(o.get("attributes", []), ATTRS)), "set"),
        ("skills", lambda o: sorted(_ids(o.get("skills", []), SKILLS)), "set"),
        ("reactions", lambda o: {k.lower(): v for k, v in o.get("reactions", {}).items()}, "jlower"),
        ("rankList", lambda o: [r for r in o.get("ranks", []) if r], "ranks")]),
    "Skill": ("skill", [
        ("attribute", lambda o: ATTRS[o["attribute"]] if 0 <= o.get("attribute", -1) < 8 else None, "id"),
        ("specialization", lambda o: SPECS[o["specialization"]] if 0 <= o.get("specialization", -1) < 3 else None, "id"),
        ("description", _g("description"), "s")]),
}
FILES = {k: v[0] for k, v in SPEC.items()}


def _eq(kind, ours, theirs) -> bool:
    if kind == "f":
        if ours is None or theirs is None:
            return ours == theirs
        return math.isclose(float(ours), float(theirs), rel_tol=1e-5, abs_tol=1e-4)
    if kind == "n":
        return (ours is None and theirs in (None, 0)) or (theirs is not None and ours is not None and int(ours) == int(theirs))
    if kind == "ench":            # OpenMW może skalować pojemność zaklęcia (mEnchant/10) – akceptujemy obie postaci
        if ours is None or theirs is None:
            return ours == theirs
        return any(math.isclose(float(ours) * s, float(theirs), abs_tol=1e-3) for s in (1.0, 0.1))
    if kind == "b":
        return bool(ours) == bool(theirs)
    if kind == "id":
        return _id(ours) == _id(theirs)
    if kind == "s":
        a = "" if ours is None else str(ours)
        b = "" if theirs is None else str(theirs)
        return a == b or _path(a) == _path(b) and ("/" in a or "\\" in a or "." in a)
    if kind == "set":
        return sorted(_id(x) for x in (ours or [])) == sorted(_id(x) for x in (theirs or []))
    if kind == "j":
        return json.dumps(ours or {}, sort_keys=True) == json.dumps(theirs or {}, sort_keys=True)
    if kind == "jlower":
        t = {str(k).lower(): v for k, v in (theirs or {}).items()} if isinstance(theirs, dict) else theirs
        return json.dumps(ours or {}, sort_keys=True) == json.dumps(t or {}, sort_keys=True)
    if kind == "ranks":
        names = [r.get("name") for r in (theirs or []) if isinstance(r, dict)]
        return [n for n in names if n] == [n for n in (ours or []) if n]
    return ours == theirs


def sample(records_dir: Path, kinds: list[str], n: int, overridden_limit: int = 50, seed: int = 1) -> dict:
    rng = random.Random(seed)
    out = {}
    for kind in kinds:
        f = records_dir / f"{FILES[kind]}.json"
        if not f.is_file():
            continue
        data = json.loads(f.read_text(encoding="utf-8"))
        keys = sorted(data)
        over = [k for k in keys if data[k].get("overridden")][:overridden_limit]
        rest = [k for k in keys if k not in set(over)]
        out[kind] = over + rng.sample(rest, min(n, len(rest)))
    return out


def _lua_list(xs) -> str:
    return "{ " + ", ".join(capture._lua_value(x) for x in xs) + " }"


def request_lua(ids: dict, gmst: list, globals_: list) -> str:
    lines = ["-- Wygenerowano przez MCP-openMW (recordcmp.py).", "return {",
             f"    attributes = {_lua_list(ATTRS)},", f"    skills = {_lua_list(SKILLS)},", "    items = {"]
    for kind, lst in ids.items():
        fields = [f for f, _, _ in SPEC[kind][1] if f not in ("attrs", "skillBonus", "heightM", "heightF",
                                                                "weightM", "weightF", "rankList")]
        lines.append(f"        {{ kind = {capture._lua_value(kind)}, fields = {_lua_list(fields)}, ids = {_lua_list(lst)} }},")
    lines += ["    },", f"    gmst = {_lua_list(gmst)},", f"    globals = {_lua_list(globals_)},", "}", ""]
    return "\n".join(lines)


def prepare(env, profile: str, run_dir: Path, ids: dict, gmst: list, globals_: list) -> dict:
    base = run_dir / profile
    cfg, data, ud = base / "cfg", base / "data", base / "userdata"
    for d in (cfg, data / "scripts/rlf_records", ud / "data"):
        d.mkdir(parents=True, exist_ok=True)
    shutil.copy2(LUA_DIR / "rlf_records.omwscripts", data / "rlf_records.omwscripts")
    shutil.copy2(LUA_DIR / "scripts/rlf_records/global.lua", data / "scripts/rlf_records/global.lua")
    (data / "scripts/rlf_records/request.lua").write_text(request_lua(ids, gmst, globals_), encoding="utf-8")
    (cfg / "openmw.cfg").write_text(f'data="{data}"\ncontent=rlf_records.omwscripts\n', encoding="utf-8")
    capture._write_settings(cfg / "settings.cfg", capture.SETTINGS_OVERRIDES)
    cmd, cwd, run_env = capture.engine_command(env, profile, cfg, ud, base)
    plan = {"profile": profile, "cmd": cmd, "cwd": cwd, "env": run_env, "log": str(cfg / "openmw.log"),
            "run_dir": str(base)}
    (base / "plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
    return plan


def run(plan: dict, timeout: float = 240.0, popen=subprocess.Popen) -> dict:
    import os
    log = Path(plan["log"])
    log.unlink(missing_ok=True)
    out = open(Path(plan["run_dir"]) / "stdout.log", "w", encoding="utf-8")
    proc = popen(plan["cmd"], cwd=plan["cwd"], env={**os.environ, **plan["env"]}, stdout=out, stderr=subprocess.STDOUT)
    status, end = "timeout", time.time() + timeout
    try:
        while time.time() < end:
            if log.is_file() and "RLF_REC DONE" in log.read_text(encoding="utf-8", errors="replace"):
                status = "done"
                break
            if proc.poll() is not None:
                status = f"process exited ({proc.returncode})"
                break
            time.sleep(0.5)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
        out.close()
    return {"status": status, "records": parse_log(log) if log.is_file() else {}}


def parse_log(log: Path) -> dict:
    recs = {}
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "RLF_REC " not in line or "RLF_REC DONE" in line:
            continue
        rest = line.split("RLF_REC ", 1)[1]
        kind, _, rest = rest.partition(" ")
        try:
            dec = json.JSONDecoder()
            rid, idx = dec.raw_decode(rest)
            body = json.loads(rest[idx:].strip())
        except ValueError:
            continue
        recs[(kind, str(rid).lower())] = body
    return recs


def compare(records_dir: Path, engine: dict, gmst: list, globals_: list) -> dict:
    report = {"types": {}, "mismatches": [], "missing_in_engine": [], "missing_in_ours": []}
    for (kind, rid), body in sorted(engine.items()):
        if kind in ("GMST", "GLOB"):
            continue
        ours = json.loads((records_dir / f"{FILES[kind]}.json").read_text(encoding="utf-8")) if kind in FILES else {}
        st = report["types"].setdefault(kind, {"records": 0, "fields": 0, "mismatched_fields": 0})
        o = ours.get(rid)
        if body is None:
            report["missing_in_engine"].append(f"{kind}:{rid}")
            continue
        if o is None:
            report["missing_in_ours"].append(f"{kind}:{rid}")
            continue
        st["records"] += 1
        for field, getter, how in SPEC[kind][1]:
            try:
                mine = getter(o)
            except (KeyError, IndexError, TypeError):
                mine = None
            st["fields"] += 1
            if not _eq(how, mine, body.get(field)):
                st["mismatched_fields"] += 1
                if len(report["mismatches"]) < 60:
                    report["mismatches"].append({"type": kind, "id": rid, "field": field, "ours": mine,
                                                 "openmw": body.get(field)})
    for typ, names, fname in (("GMST", gmst, "gmst"), ("GLOB", globals_, "global")):
        ours = json.loads((records_dir / f"{fname}.json").read_text(encoding="utf-8"))
        st = report["types"].setdefault(typ, {"records": 0, "fields": 0, "mismatched_fields": 0})
        for n in names:
            body = engine.get((typ, n.lower()))
            o = ours.get(n.lower())
            if body is None or o is None:
                continue
            st["records"] += 1
            st["fields"] += 1
            a, b = o.get("value"), body.get("value")
            ok = (math.isclose(float(a), float(b), rel_tol=1e-5, abs_tol=1e-4)
                  if isinstance(a, (int, float)) and isinstance(b, (int, float)) else a == b)
            if not ok:
                st["mismatched_fields"] += 1
                if len(report["mismatches"]) < 60:
                    report["mismatches"].append({"type": typ, "id": n, "field": "value", "ours": a, "openmw": b})
    return report


def gmst_globals_sample(records_dir: Path, n: int, seed: int = 1) -> tuple[list, list]:
    rng = random.Random(seed)
    g = json.loads((records_dir / "gmst.json").read_text(encoding="utf-8"))
    gl = json.loads((records_dir / "global.json").read_text(encoding="utf-8"))
    gm = [g[k]["id"] for k in sorted(g)]
    gv = [gl[k]["id"] for k in sorted(gl)]
    return rng.sample(gm, min(n, len(gm))), gv


def run_all(run_dir: Path, timeout: float = 240.0) -> dict:
    """Przebieg w tle: python -m openmw_mcp.recordcmp <run_dir>. Wejście: run_dir/params.json."""
    p = json.loads((run_dir / "params.json").read_text(encoding="utf-8"))
    plan = json.loads((Path(p["plan"])).read_text(encoding="utf-8"))
    (run_dir / "progress.json").write_text(json.dumps({"running": True}), encoding="utf-8")
    res = run(plan, timeout)
    rep = compare(Path(p["records_dir"]), res["records"], p["gmst"], p["globals"])
    rep.update(status=res["status"], engine_records=len(res["records"]), records_dir=p["records_dir"],
               finished=time.strftime("%Y-%m-%dT%H:%M:%S"))
    rep["summary"] = {"records": sum(t["records"] for t in rep["types"].values()),
                      "fields": sum(t["fields"] for t in rep["types"].values()),
                      "mismatched_fields": sum(t["mismatched_fields"] for t in rep["types"].values())}
    (run_dir / "report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    (run_dir / "progress.json").write_text(json.dumps({"running": False}), encoding="utf-8")
    return rep


if __name__ == "__main__":
    import sys
    print(json.dumps(run_all(Path(sys.argv[1]), float(sys.argv[2]) if len(sys.argv) > 2 else 240.0),
                     ensure_ascii=False)[:2000])
