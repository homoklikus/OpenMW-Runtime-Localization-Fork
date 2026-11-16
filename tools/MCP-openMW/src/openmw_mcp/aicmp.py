"""Porównanie zachowań AI (etap 8 planu): ten sam punkt startu w OpenMW (skrypt Lua globalny + skrypt aktorów)
i w OpenMWGodot (godot/tools/ai_compare.gd). Losowość wędrówki jest różna po obu stronach, więc porównujemy
zachowanie, nie trasy: pakiet AI aktora (typ, promień wędrówki), czy się poruszał, czy został w promieniu
wędrówki, oraz reakcję na napaść gracza przy strażniku (zauważona, grzywna, pościg strażnika, walka ofiary).

Silnik: izolowany profil jak przy porównaniu rekordów (recordcmp.prepare), start w komórce z żądania;
wynik w openmw.log ("RLF_AI <rodzaj> <id> <json>"). Uruchomienie bez restartu serwera MCP: plik
`Raporty/mcp/ai/pending/request.json` + `openmw_record_compare_start` (recordcmp.run_all).
Żądanie: {"cell": "", "start_cell": "Seyda Neen", "pos": [x, y, z], "settle": 3, "duration": 30, "step": 1,
          "crime": {"victim": "<recordId>", "guard": "<recordId>", "distance": 100, "guard_distance": 400}}
"""
from __future__ import annotations

import json
import math
import shutil
import subprocess
import time
from pathlib import Path

from . import capture

LUA_DIR = capture.LUA_DIR
MOVED = 32.0            # jednostki MW: przesunięcie uznawane za ruch
RANGE_TOL = 400.0       # tolerancja promienia wędrówki (punkty siatki ścieżek leżą do kilkuset jednostek dalej)
MATCH_DIST = 150.0      # dopasowanie aktorów: ten sam recordId i pozycja z pierwszej klatki (przed ruchem AI)


def request_lua(req: dict) -> str:
    return "-- Wygenerowano przez MCP-openMW (aicmp.py).\nreturn " + _lua(req) + "\n"


def _lua(v) -> str:
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {_lua(x)}" for k, x in v.items()) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(_lua(x) for x in v) + " }"
    return capture._lua_value(v)


def prepare_from_plan(plan: dict, req: dict) -> dict:
    """Dopisuje scenariusz AI do profilu przygotowanego przez recordcmp.prepare; start w komórce z żądania."""
    base = Path(plan["run_dir"])
    data, cfg = base / "data", base / "cfg"
    (data / "scripts/rlf_ai").mkdir(parents=True, exist_ok=True)
    shutil.copy2(LUA_DIR / "rlf_ai.omwscripts", data / "rlf_ai.omwscripts")
    for n in ("global.lua", "actor.lua"):
        shutil.copy2(LUA_DIR / "scripts/rlf_ai" / n, data / "scripts/rlf_ai" / n)
    lreq = {k: v for k, v in req.items() if k != "start_cell"}
    (data / "scripts/rlf_ai/request.lua").write_text(request_lua(lreq), encoding="utf-8")
    (base / "ai_request.json").write_text(json.dumps(req, ensure_ascii=False, indent=1), encoding="utf-8")
    (cfg / "openmw.cfg").write_text(f'data="{data}"\ncontent=rlf_ai.omwscripts\n', encoding="utf-8")
    start = req.get("start_cell")
    if start:
        plan = dict(plan)
        plan["cmd"] = [f"--start={start}" if str(c).startswith("--start=") else c for c in plan["cmd"]]
    return plan


def run(plan: dict, timeout: float = 300.0, popen=subprocess.Popen) -> dict:
    import os
    log = Path(plan["log"])
    log.unlink(missing_ok=True)
    out = open(Path(plan["run_dir"]) / "stdout.log", "w", encoding="utf-8")
    proc = popen(plan["cmd"], cwd=plan["cwd"], env={**os.environ, **plan["env"]}, stdout=out, stderr=subprocess.STDOUT)
    status, end = "timeout", time.time() + timeout
    try:
        while time.time() < end:
            if log.is_file() and "RLF_AI DONE" in log.read_text(encoding="utf-8", errors="replace"):
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
        if "RLF_AI " not in line or "RLF_AI DONE" in line or "RLF_AI PHASE" in line:
            continue
        rest = line.split("RLF_AI ", 1)[1]
        kind, _, rest = rest.partition(" ")
        try:
            dec = json.JSONDecoder()
            rid, idx = dec.raw_decode(rest)
            body = json.loads(rest[idx:].strip())
        except ValueError:
            continue
        res.append({"kind": kind, "id": rid, "data": body})
    return res


# --- porównanie -------------------------------------------------------------------------------------------

def _ptype(p) -> str:
    t = str((p or {}).get("type", "none") or "none").lower()
    return {"unknown": "none", "": "none"}.get(t, t)


def summarize(e: dict) -> dict:
    """Aktor → {recordId, start, package, distance, moved, max_disp, in_range, types}."""
    d = e["data"]
    s = [tuple(map(float, p)) for p in d.get("samples", [])]
    first = tuple(map(float, d.get("start", s[0] if s else [0, 0, 0])))   # pozycja przed ruchem – dopasowanie
    st = s[0] if s else first
    disp = max((math.hypot(p[0] - st[0], p[1] - st[1]) for p in s), default=0.0)
    pk = d.get("package") or {}
    dist = float(pk.get("distance") or 0.0)
    t = _ptype(pk)
    return {"recordId": str(d.get("recordId", "")).lower(), "start": first, "package": t, "distance": dist,
            "moved": disp > MOVED, "max_disp": round(disp, 1),
            "in_range": t != "wander" or disp <= dist + RANGE_TOL,
            "types": sorted({_ptype({"type": x}) for x in d.get("packages", [])})}


def _cells(ours: list):
    m = next((e["data"] for e in ours if e["kind"] == "meta"), None)
    return {tuple(c) for c in m.get("grids", [])} if m and m.get("grids") else None


def match(engine: list, ours: list) -> tuple[list, list, list]:
    a = [summarize(e) for e in engine if e["kind"] == "actor"]
    cells = _cells(ours)            # tylko aktorzy z komórek wczytanych w OpenMWGodot (przekonwertowany fragment)
    if cells is not None:
        a = [x for x in a if (math.floor(x["start"][0] / 8192.0), math.floor(x["start"][1] / 8192.0)) in cells]
    b = [summarize(e) for e in ours if e["kind"] == "actor"]
    used, pairs, miss = set(), [], []
    for x in a:
        best, bd = None, MATCH_DIST
        for i, y in enumerate(b):
            if i in used or y["recordId"] != x["recordId"]:
                continue
            dd = math.dist(x["start"][:2], y["start"][:2])
            if dd <= bd:
                best, bd = i, dd
        if best is None:
            miss.append(x["recordId"])
        else:
            used.add(best)
            pairs.append((x, b[best]))
    extra = [y["recordId"] for i, y in enumerate(b) if i not in used]
    return pairs, miss, extra


def compare(engine: list, ours: list) -> dict:
    pairs, miss, extra = match(engine, ours)
    rep = {"actors": {"matched": len(pairs), "missing_in_ours": miss, "extra_in_ours": extra},
           "checks": {}, "actors_detail": [], "crime": {}}
    chk = {"package_type": [0, 0], "wander_distance": [0, 0], "moved": [0, 0], "in_range_openmw": [0, 0],
           "in_range_ours": [0, 0]}
    for x, y in pairs:
        row = {"recordId": x["recordId"], "openmw": {k: x[k] for k in ("package", "distance", "moved", "max_disp", "in_range")},
               "ours": {k: y[k] for k in ("package", "distance", "moved", "max_disp", "in_range")}}
        rep["actors_detail"].append(row)
        chk["package_type"][1] += 1
        chk["package_type"][0] += x["package"] == y["package"]
        if x["package"] == "wander":
            chk["wander_distance"][1] += 1
            chk["wander_distance"][0] += math.isclose(x["distance"], y["distance"], abs_tol=0.5)
        chk["moved"][1] += 1
        chk["moved"][0] += x["moved"] == y["moved"]
        chk["in_range_openmw"][1] += 1
        chk["in_range_openmw"][0] += x["in_range"]
        chk["in_range_ours"][1] += 1
        chk["in_range_ours"][0] += y["in_range"]
    rep["checks"] = {k: {"agree": v[0], "of": v[1]} for k, v in chk.items()}
    ec = next((e["data"] for e in engine if e["kind"] == "crime"), None)
    oc = next((e["data"] for e in ours if e["kind"] == "crime"), None)
    if ec is not None and oc is not None:
        fields = ["seen", "bounty", "guard_pursue", "victim_combat"]
        rep["crime"] = {f: {"openmw": ec.get(f), "ours": oc.get(f),
                            "agree": str(ec.get(f)).lower() == str(oc.get(f)).lower()} for f in fields}
    # zgodność wymagana: pakiety i promienie, aktorzy w promieniu, reakcja na przestępstwo; ruch – informacyjnie
    req = ["package_type", "wander_distance", "in_range_ours"]
    ok = all(rep["checks"][k]["agree"] == rep["checks"][k]["of"] for k in req) and not miss
    if rep["crime"]:
        ok = ok and all(v["agree"] for v in rep["crime"].values())
    rep["summary"] = {"ok": ok, "matched": len(pairs), "moved_agree": rep["checks"]["moved"],
                      "crime_agree": all(v["agree"] for v in rep["crime"].values()) if rep["crime"] else None}
    return rep


def run_from_record_run(run_dir: Path, plan: dict, req: dict, timeout: float = 300.0) -> dict:
    plan = prepare_from_plan(plan, req)
    (run_dir / "progress.json").write_text(json.dumps({"running": True, "mode": "ai"}), encoding="utf-8")
    res = run(plan, timeout)
    (run_dir / "ai_engine.json").write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    rep = {"mode": "ai", "status": res["status"], "engine_results": len(res["results"]),
           "finished": time.strftime("%Y-%m-%dT%H:%M:%S"), "engine_file": str(run_dir / "ai_engine.json")}
    (run_dir / "report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    (run_dir / "progress.json").write_text(json.dumps({"running": False, "mode": "ai"}), encoding="utf-8")
    return rep


def pending_request(run_dir: Path):
    """Żądanie czekające w <projekt>/Raporty/mcp/ai/pending/request.json (przebieg rekordów)."""
    try:
        root = Path(run_dir).resolve().parents[3]
    except IndexError:
        return None
    f = root / "Raporty/mcp/ai/pending/request.json"
    if not f.is_file():
        return None
    req = json.loads(f.read_text(encoding="utf-8"))
    f.rename(Path(run_dir) / "ai_pending_used.json")
    return req


if __name__ == "__main__":
    import sys
    if sys.argv[1] == "compare":               # python -m openmw_mcp.aicmp compare <engine.json> <ours.json> <out>
        eng = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
        ours = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
        rep = compare(eng["results"] if isinstance(eng, dict) else eng, ours["results"] if isinstance(ours, dict) else ours)
        Path(sys.argv[4]).write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
        print(json.dumps(rep["summary"]))
