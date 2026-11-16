"""Porównanie wzorów RPG (etap 7 planu): te same wejścia w silniku OpenMW (skrypt Lua na graczu) i w OpenMWGodot
(godot/tools/mech_compare.gd), wyniki porównywane liczba po liczbie.

Silnik: izolowany profil jak przy porównaniu rekordów; scenariusz `lua/scripts/rlf_mech/player.lua` z żądaniem
`request.lua` (generowanym tu z danych OpenMWGodot); wynik w openmw.log ("RLF_MECH <rodzaj> <id> <json>").
Testy: statystyki pochodne, wymagania postępu umiejętności, postęp za użycie, awans, pancerz (Lua OpenMW:
I.Combat), ładunek przedmiotów zaklętych, mikstury (aktywne czary) – w trakcie i po wygaśnięciu.

Uruchomienie: `openmw_mechanics_compare_start` (MCP) albo – bez restartu serwera MCP – plik
`Raporty/mcp/mechanika/pending/request.json` + `openmw_record_compare_start` (przebieg rekordów wykona wtedy
scenariusz mechaniki; recordcmp.run_all).
"""
from __future__ import annotations

import json
import math
import random
import shutil
import subprocess
import time
from pathlib import Path

from . import capture

LUA_DIR = capture.LUA_DIR
ATTRS = ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
SKILLS = ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear", "athletics",
          "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration", "alchemy",
          "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman", "mercantile",
          "speechcraft", "handtohand"]
ARMOR_SLOTS = {0: "Helmet", 1: "Cuirass", 2: "LeftPauldron", 3: "RightPauldron", 4: "Greaves", 5: "Boots",
               6: "LeftGauntlet", 7: "RightGauntlet", 8: "CarriedLeft", 9: "LeftGauntlet", 10: "RightGauntlet"}
ARMOR_PREFIXES = ["iron_", "netch_leather_", "chitin_", "steel_", "dwemer_", "glass_", "bonemold_", "ebony_"]
# efekty mikstur porównywane deterministycznie (bez losowania i odporności): przywrócenie, wzmocnienie
POTION_EFFECTS = {75, 76, 77, 79, 80, 81, 82, 83}


def _load(rd: Path, name: str) -> dict:
    f = rd / f"{name}.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.is_file() else {}


def build_request(records_dir: Path, seed: int = 7, enchanted: int = 40, potions: int = 12) -> dict:
    """Wejścia testów z danych OpenMWGodot (te same id po obu stronach)."""
    rng = random.Random(seed)
    rd = Path(records_dir)
    inp = {"attributes": [50, 45, 40, 55, 50, 45, 40, 35], "level": 5,
           "skills": [10 + (i * 7) % 60 for i in range(27)]}
    uses = []
    for k in ["longblade", "destruction", "athletics", "alchemy", "block", "mercantile", "speechcraft", "sneak",
              "restoration", "acrobatics", "armorer", "security"]:
        for u in (0, 1):
            uses.append({"skill": k, "index": SKILLS.index(k) + 1, "use": u, "scale": 1.0})
    levelups = ["longblade", "longblade", "destruction", "athletics", "alchemy", "block", "sneak", "mercantile",
                "armorer", "speechcraft", "restoration", "heavyarmor"]
    armor = _load(rd, "armor")
    sets = []
    for pre in ARMOR_PREFIXES:
        by_type = {}
        for aid in sorted(armor):
            a = armor[aid]
            t = a.get("armor_type")
            if aid.startswith(pre) and t in ARMOR_SLOTS and t not in by_type and t not in (9, 10):
                by_type[t] = aid
        if by_type:
            sets.append({"name": pre.rstrip("_"), "items": [{"id": i, "slot": ARMOR_SLOTS[t]} for t, i in sorted(by_type.items())]})
    ench = []
    for f in ("weapon", "armor", "clothing", "book"):
        d = _load(rd, f)
        ench += [k for k in sorted(d) if d[k].get("enchant")]
    ench = sorted(rng.sample(ench, min(enchanted, len(ench))))
    pot = _load(rd, "potion")
    mgef = _load(rd, "magiceffect")
    cand = []
    for pid in sorted(pot):
        effs = pot[pid].get("effects", [])
        if not effs or any(e.get("effect") not in POTION_EFFECTS or e.get("min") != e.get("max") for e in effs):
            continue
        dur = max(int(e.get("duration", 0)) for e in effs)
        if 0 < dur <= 40 and all(str(e.get("effect")) in mgef for e in effs):
            cand.append({"id": pid, "effects": len(effs), "duration": dur})
    pots = sorted(rng.sample(cand, min(potions, len(cand))), key=lambda p: p["id"])
    create = sorted({i["id"] for s in sets for i in s["items"]} | set(ench))
    return {"input": inp, "attributes": ATTRS, "skills": SKILLS, "skill_uses": uses, "levelups": levelups,
            "armor_sets": sets, "damages": [5, 20, 50], "enchanted": ench, "potions": pots, "create": create}


def request_lua(req: dict) -> str:
    return "-- Wygenerowano przez MCP-openMW (mechcmp.py).\nreturn " + _lua(req) + "\n"


def _lua(v) -> str:
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {_lua(x)}" for k, x in v.items()) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(_lua(x) for x in v) + " }"
    return capture._lua_value(v)


def prepare_from_plan(plan: dict, req: dict) -> dict:
    """Dopisuje scenariusz mechaniki do profilu przygotowanego przez recordcmp.prepare (ta sama komenda silnika)."""
    base = Path(plan["run_dir"])
    data, cfg = base / "data", base / "cfg"
    (data / "scripts/rlf_mech").mkdir(parents=True, exist_ok=True)
    shutil.copy2(LUA_DIR / "rlf_mech.omwscripts", data / "rlf_mech.omwscripts")
    for n in ("global.lua", "player.lua"):
        shutil.copy2(LUA_DIR / "scripts/rlf_mech" / n, data / "scripts/rlf_mech" / n)
    (data / "scripts/rlf_mech/request.lua").write_text(request_lua(req), encoding="utf-8")
    (base / "mech_request.json").write_text(json.dumps(req, ensure_ascii=False, indent=1), encoding="utf-8")
    (cfg / "openmw.cfg").write_text(f'data="{data}"\ncontent=rlf_mech.omwscripts\n', encoding="utf-8")
    return plan


def run(plan: dict, timeout: float = 600.0, popen=subprocess.Popen) -> dict:
    import os
    log = Path(plan["log"])
    log.unlink(missing_ok=True)
    out = open(Path(plan["run_dir"]) / "stdout.log", "w", encoding="utf-8")
    proc = popen(plan["cmd"], cwd=plan["cwd"], env={**os.environ, **plan["env"]}, stdout=out, stderr=subprocess.STDOUT)
    status, end = "timeout", time.time() + timeout
    try:
        while time.time() < end:
            if log.is_file() and "RLF_MECH DONE" in log.read_text(encoding="utf-8", errors="replace"):
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
    return {"status": status, "results": parse_log(log) if log.is_file() else [], "log": str(log)}


def parse_log(log: Path) -> list:
    res = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "RLF_MECH " not in line:
            continue
        rest = line.split("RLF_MECH ", 1)[1]
        kind, _, rest = rest.partition(" ")
        if kind in ("DONE",):
            continue
        if kind in ("ERROR", "WARN"):
            res.append({"kind": kind, "id": None, "data": rest})
            continue
        try:
            dec = json.JSONDecoder()
            rid, idx = dec.raw_decode(rest)
            body = json.loads(rest[idx:].strip())
        except ValueError:
            continue
        res.append({"kind": kind, "id": rid, "data": body})
    return res


# --- porównanie (wynik silnika vs wynik godot/tools/mech_compare.gd) -------------------------------------

def _close(a, b, tol=1e-3) -> bool:
    if a is None or b is None:
        return a is b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(float(a), float(b), rel_tol=1e-4, abs_tol=tol)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(_close(x, y, tol) for x, y in zip(a, b))
    return a == b


def compare(engine: list, ours: list) -> dict:
    """Porównuje wpisy o tym samym (rodzaj, id); pola z listy CHECK. → raport z liczbą zgodnych i różnicami."""
    CHECK = {"stats": [("attributes", 1e-3), ("skills_mod", 1e-3), ("dyn_max", 1e-3), ("requirement", 1e-3)],
             "skill_use": [("progress", 1e-4)], "levelup": [("progress", 0), ("attribute", 0), ("specialization", 0),
                                                              ("after_base", 0)],
             "armor": [("rating", 1e-3), ("items", 1e-3), ("adjusted", 1e-3)], "charge": [("charge", 1e-3)],
             "potion_during": [("attributes", 1e-3), ("skills_mod", 1e-3), ("dyn_max", 1e-3)],
             "potion_after": [("dyn_cur", 0.05), ("attributes", 1e-3)]}
    eng = {(e["kind"], str(e["id"])): normalize(e) for e in engine if e["kind"] in CHECK}
    our = {(e["kind"], str(e["id"])): normalize(e) for e in ours if e["kind"] in CHECK}
    rep = {"by_kind": {}, "mismatches": [], "missing_in_ours": [], "errors": [e for e in engine if e["kind"] in ("ERROR", "WARN")]}
    for key, ev in sorted(eng.items()):
        kind = key[0]
        st = rep["by_kind"].setdefault(kind, {"cases": 0, "values": 0, "mismatched": 0})
        ov = our.get(key)
        if ov is None:
            rep["missing_in_ours"].append(list(key))
            continue
        st["cases"] += 1
        for field, tol in CHECK[kind]:
            a, b = ev.get(field), ov.get(field)
            st["values"] += 1
            if not _close(b, a, tol):
                st["mismatched"] += 1
                if len(rep["mismatches"]) < 80:
                    rep["mismatches"].append({"kind": kind, "id": key[1], "field": field, "openmw": a, "ours": b})
    rep["summary"] = {k: sum(v[k] for v in rep["by_kind"].values()) for k in ("cases", "values", "mismatched")}
    return rep


def normalize(e: dict) -> dict:
    """Wspólna postać obu stron: modyfikowane atrybuty/umiejętności, maksima i bieżące wartości dynamiczne."""
    d = dict(e["data"])
    if "attributes" in d and d["attributes"] and isinstance(d["attributes"][0], list):
        d["attributes"] = [round(float(x[1]), 3) for x in d["attributes"]]
    if "skills" in d and d["skills"] and isinstance(d["skills"][0], list):
        d["skills_mod"] = [round(float(x[1]), 3) for x in d["skills"]]
    if "after" in d and d["after"] and isinstance(d["after"][0], list):
        d["after_base"] = [int(x[0]) for x in d["after"]]
    if isinstance(d.get("dynamic"), dict):
        dd = d["dynamic"]
        d["dyn_max"] = [float(dd[n][2] if len(dd[n]) > 2 else dd[n][0]) for n in ("health", "magicka", "fatigue") if n in dd]
        d["dyn_cur"] = [float(dd[n][1]) for n in ("health", "magicka", "fatigue") if n in dd]
    if isinstance(d.get("items"), list):
        d["items"] = [x[1] for x in d["items"]]
    return d


def run_from_record_run(run_dir: Path, plan: dict, req: dict, timeout: float = 600.0) -> dict:
    prepare_from_plan(plan, req)
    (run_dir / "progress.json").write_text(json.dumps({"running": True, "mode": "mechanics"}), encoding="utf-8")
    res = run(plan, timeout)
    (run_dir / "mech_engine.json").write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    rep = {"mode": "mechanics", "status": res["status"], "engine_results": len(res["results"]),
           "finished": time.strftime("%Y-%m-%dT%H:%M:%S"), "engine_file": str(run_dir / "mech_engine.json")}
    (run_dir / "report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    (run_dir / "progress.json").write_text(json.dumps({"running": False, "mode": "mechanics"}), encoding="utf-8")
    return rep


def pending_request(run_dir: Path):
    """Żądanie mechaniki czekające w <projekt>/Raporty/mcp/mechanika/pending/request.json (przebieg rekordów)."""
    try:
        root = Path(run_dir).resolve().parents[3]
    except IndexError:
        return None
    f = root / "Raporty/mcp/mechanika/pending/request.json"
    if not f.is_file():
        return None
    req = json.loads(f.read_text(encoding="utf-8"))
    f.rename(Path(run_dir) / "mech_pending_used.json")
    return req


if __name__ == "__main__":
    import sys
    if sys.argv[1] == "request":                 # python -m openmw_mcp.mechcmp request <records_dir> <out.json>
        Path(sys.argv[3]).write_text(json.dumps(build_request(Path(sys.argv[2])), ensure_ascii=False, indent=1), encoding="utf-8")
    elif sys.argv[1] == "compare":               # python -m openmw_mcp.mechcmp compare <engine.json> <ours.json> <out>
        eng = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
        ours = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
        rep = compare(eng["results"] if isinstance(eng, dict) else eng, ours["results"] if isinstance(ours, dict) else ours)
        Path(sys.argv[4]).write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
        print(json.dumps(rep["summary"]))
