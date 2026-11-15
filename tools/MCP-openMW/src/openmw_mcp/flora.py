"""Klasyfikacja mechanizmu roślinności: oficjalny Groundcover (pluginy ESP), proceduralna flora forka, eksperymenty.

Semantyka forka (0.5-world, apps/openmw/mwrender/renderingmanager.cpp::getWorldspaceChunkMgr):
  floraConfigured = world.cfg [Flora] enabled
  procedural      = floraConfigured && source in {automatic, hybrid}
  plugins         = (floraConfigured && source in {groundcover, hybrid}) || (!floraConfigured && [Groundcover] enabled)
  gęstość pluginów = [Groundcover] density (× flora.density, clamp 0..1 gdy floraConfigured)
Oficjalne 0.51.0: plugins = [Groundcover] enabled; brak flory proceduralnej.
Profile Remirosa (groundcover.cpp, hasRemiros*TestPool): aktywny, gdy pula zawiera komplet modeli rodziny.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

from . import cfgparse
from .util import vfs_key

REMIROS_FAMILIES = {
    "AI": ["rem_ai_grass_01.nif", "rem_ai_grass_01b.nif", "rem_ai_grass_01c.nif", "rem_ai_grass_02.nif"],
    "AL": ["rem_al_grass.nif", "rem_al_grass_b.nif", "rem_al_rock.nif"],
    "BC": ["rem_bc_grass_01.nif", "rem_bc_grass_02.nif", "rem_bc_grass_03.nif"],
    "GL": ["rem_gl_grass_01.nif", "rem_gl_grass_01b.nif", "rem_gl_grass_01c.nif"],
    "WG": ["rem_wg_grass_01.nif", "rem_wg_grass_01b.nif", "rem_wg_grass_02.nif", "rem_wg_grass_02b.nif",
           "rem_wg_grass_03.nif", "rem_wg_grass_04.nif"],
}
FAMILY_CANDIDATES = {"AI": 4096, "AL": 8192, "BC": 8192, "GL": 8192, "WG": 8192}
GENERIC_CANDIDATES = 32768
VANILLA_POOL = [f"meshes/f/flora_grass_0{i}.nif" for i in range(1, 8)] + [
    "meshes/f/flora_bc_grass_01.nif", "meshes/f/flora_bc_grass_02.nif", "meshes/f/flora_ash_grass_b_01.nif",
    "meshes/f/flora_ash_grass_r_01.nif", "meshes/f/flora_ash_grass_w_01.nif"] + [
    f"meshes/f/flora_bm_grass_0{i}.nif" for i in range(1, 7)]


def parse_pool_script(path: Path) -> dict[str, list[str]]:
    """Domyślne pule OPENMW_FLORA_TEST_ASSET z Fork/scripts/run-flora-test.sh (gałęzie case: 'ac', '*')."""
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace").replace("\\\n", "")
    g = re.search(r'^\s*G="([^"]+)"', text, re.M)
    gval = g.group(1) if g else ""
    pools = {}
    for m in re.finditer(r'^\s*(\S+)\)\s*POOL="([^"]+)"', text, re.M):
        label = {"*": "all"}.get(m.group(1), m.group(1))
        pools[label] = [x.strip().replace("$G", gval) for x in m.group(2).split(",") if x.strip()]
    return pools


def _families(pool_keys: list[str]) -> dict:
    names = {k.rsplit("/", 1)[-1] for k in pool_keys}
    out = {}
    for fam, need in REMIROS_FAMILIES.items():
        missing = [n for n in need if n not in names]
        out[fam] = {"active": not missing, "missing_models": missing}
    return out


def classify(eff: dict, engine: str, vfs: Optional[dict] = None, pool: Optional[list[str]] = None,
             pool_source: str = "", experiments: Optional[list[dict]] = None) -> dict:
    st = eff["settings"]["merged"]
    gc_enabled = cfgparse.parse_bool(cfgparse.setting(st, "Groundcover", "enabled"), False)
    gc_density = cfgparse._float(cfgparse.setting(st, "Groundcover", "density"), 1.0)
    gc_distance = cfgparse._float(cfgparse.setting(st, "Groundcover", "rendering distance"), 6144.0)
    plugins = [g["name"] for g in eff["groundcover"]]
    res = {"engine": engine, "settings_groundcover": {"enabled": gc_enabled, "density": gc_density,
                                                      "rendering_distance": gc_distance},
           "groundcover_plugins": plugins, "notes": []}
    if engine == "official":
        res["mechanism"] = "oficjalny Groundcover (pluginy ESP)" if gc_enabled and plugins else "brak"
        res["plugins_rendered"] = bool(gc_enabled and plugins)
        res["plugin_density"] = gc_density
        res["procedural"] = False
        if plugins and not gc_enabled:
            res["notes"].append("wpisy groundcover= są, ale [Groundcover] enabled=false — nic nie jest renderowane")
        return res

    world = eff.get("world_cfg") or cfgparse.parse_world_cfg(None)
    fl = world["flora"]
    configured = fl["enabled"]
    procedural = configured and fl["source"] in ("automatic", "hybrid")
    plugin_on = (configured and fl["source"] in ("groundcover", "hybrid")) or (not configured and gc_enabled)
    density = gc_density
    if configured and plugin_on:
        density = min(1.0, max(0.0, gc_density * fl["density"]))
    res.update({"world_cfg": {"present": world["present"], **fl}, "procedural": procedural,
                "plugins_rendered": bool(plugin_on and plugins), "plugin_density": density})
    if configured and not plugin_on and plugins:
        res["notes"].append(f"world.cfg source={fl['source']}: wpisy groundcover= są IGNOROWANE")
    if configured and gc_enabled and not plugin_on:
        res["notes"].append("[Groundcover] enabled=true nie ma wpływu, bo world.cfg [Flora] przejmuje sterowanie")
    mech = []
    if res["plugins_rendered"]:
        mech.append("pluginy ESP (mechanizm oficjalny)")
    if procedural:
        mech.append("proceduralna flora forka")
    res["mechanism"] = " + ".join(mech) or "brak"

    if procedural:
        if pool:
            keys = [vfs_key(p) for p in pool]
            source = pool_source or "parametr"
        else:
            keys, source = [vfs_key(p) for p in VANILLA_POOL], "wbudowana pula vanilla (brak OPENMW_FLORA_TEST_ASSET)"
        found, missing = [], []
        for k in keys:
            (found if vfs is None or k in vfs["index"] else missing).append(k)
        if pool and not found:
            res["notes"].append("żaden model z OPENMW_FLORA_TEST_ASSET nie istnieje w VFS — silnik wróci do puli vanilla")
            found = [vfs_key(p) for p in VANILLA_POOL if vfs is None or vfs_key(p) in vfs["index"]]
        fams = _families(found) if pool else {f: {"active": False, "missing_models": []} for f in REMIROS_FAMILIES}
        active = [f for f, v in fams.items() if v["active"]]
        unused = []
        if active:
            fam_names = {n for f in active for n in REMIROS_FAMILIES[f]}
            unused = [k for k in found if k.rsplit("/", 1)[-1] not in fam_names]
        res["procedural_profile"] = {
            "pool_source": source, "pool_models": len(keys), "pool_found_in_vfs": len(found),
            "pool_missing_in_vfs": missing, "remiros_families": fams, "active_profiles": active,
            "mode": "regionalne profile Remirosa (komórki spoza profili bez roślinności)" if active
            else f"ogólny ({GENERIC_CANDIDATES} kandydatów × density na komórkę)",
            "candidates_per_cell": {f: FAMILY_CANDIDATES[f] for f in active} or {"*": GENERIC_CANDIDATES},
            "pool_models_unused_by_active_profiles": unused,
            "density": fl["density"], "exclusion_distance_m": fl["exclusion_distance"],
        }
        if "AC" not in active:
            res["notes"].append("zatwierdzony fork nie ma profilu Azura's Coast ani Solstheim")
    if experiments:
        res["experiments"] = [{"name": e["name"], "state": e["state"]} for e in experiments]
    return res
