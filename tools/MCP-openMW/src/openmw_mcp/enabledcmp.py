"""Etap 5 (regresja): porównanie stanu włączenia obiektów ze skryptami – RLF_ENABLED z openmw.log (ujęcie
z dump_enabled) i godot/tools/enabled_dump.gd. Dopasowanie po recordId i pozycji (do 2 jednostek).
python -m openmw_mcp.enabledcmp <openmw.log> <godot.json> <wynik.json>"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path


def parse_log(log: Path) -> list:
    out = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "RLF_ENABLED " not in line:
            continue
        p = line.split("RLF_ENABLED ", 1)[1].split()
        if len(p) < 7:
            continue
        out.append({"shot": p[0], "base": p[1].replace("_", " ").lower(), "script": p[2].lower(),
                    "pos": [float(p[3]), float(p[4]), float(p[5])], "enabled": p[6] == "1"})
    return out


def compare(eng: list, ours: dict) -> dict:
    cells = {tuple(int(v) for v in c[4:].split(",")) for c in ours["cells"] if c.startswith("ext:")}
    eng_in = [e for e in eng if (math.floor(e["pos"][0] / 8192), math.floor(e["pos"][1] / 8192)) in cells]
    used, same, diff, missing = set(), 0, [], []
    objs = ours["objects"]
    for e in eng_in:
        best = None
        for i, o in enumerate(objs):
            if i in used or o["base"].replace("_", " ") != e["base"]:
                continue
            if math.dist(o["pos"][:2], e["pos"][:2]) <= 2.0:
                best = i
                break
        if best is None:      # aktor mógł się przemieścić (AI) – ten sam rekord bez pary, najbliższy
            cand = [i for i, o in enumerate(objs) if i not in used and o["base"].replace("_", " ") == e["base"]]
            best = min(cand, key=lambda i: math.dist(objs[i]["pos"][:2], e["pos"][:2])) if cand else None
        if best is None:
            missing.append(e["base"])
            continue
        used.add(best)
        if objs[best]["enabled"] == e["enabled"]:
            same += 1
        else:
            diff.append({"base": e["base"], "script": e["script"], "openmw": e["enabled"], "ours": objs[best]["enabled"]})
    extra = [o["base"] for i, o in enumerate(objs) if i not in used]
    return {"cells": sorted(ours["cells"]), "openmw_in_cells": len(eng_in), "ours": len(objs), "same": same,
            "diff": len(diff), "diffs": diff[:50], "missing_in_ours": missing, "extra_in_ours": extra[:50],
            "disabled_openmw": sum(1 for e in eng_in if not e["enabled"])}


if __name__ == "__main__":
    rep = compare(parse_log(Path(sys.argv[1])), json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
    Path(sys.argv[3]).write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({k: rep[k] for k in ("openmw_in_cells", "ours", "same", "diff", "disabled_openmw")}),
          "missing:", rep["missing_in_ours"][:10])
