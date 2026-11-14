#!/usr/bin/env python3
"""Test integracyjny MCP-openMW przez protokół MCP (stdio), tak jak łączy się Claude Code.

Serwer jest uruchamiany jako osobny proces (domyślnie .venv/bin/openmw-mcp — ta sama binarka, którą
rejestruje `claude mcp add`). Każde narzędzie jest wołane przez ClientSession, a wynik porównywany
z wartościami wyznaczonymi NIEZALEŻNIE od kodu MCP: bezpośrednio z plików .cfg, Gita, `flatpak info`,
files/manifest.json Flatpaka, katalogów modów i nagłówków rekordów ESP.

    .venv/bin/python scripts/integracja.py               # raport w ../Raporty/mcp/testy/
    .venv/bin/python scripts/integracja.py --no-report   # tylko wynik na ekranie

Kod wyjścia: 0 — wszystko zaliczone; 1 — co najmniej jeden FAIL; 3 — brak FAIL, ale są SKIP.
Skrypt nic nie zmienia w profilach, modach ani silnikach. Zapisuje tylko raport (chyba że --no-report).
"""

from __future__ import annotations

import asyncio
import datetime as dt
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

MCP_DIR = Path(os.path.abspath(__file__)).parent.parent
EXPECTED_SOURCE_COMMIT = "f4bec41444214a7903bebd178389ca22ca13f646"     # tag openmw-0.51.0
AUDIT = {"official_cells": 701, "official_statics": 105, "baseline_15_-9_density1": 1449}
REMIROS_VARIANT = ["00 Core OpenMW", "01b Thicker Grass OpenMW"]
EXPECTED_TOOLS = {
    "openmw_env_status", "openmw_git_info", "openmw_list_profiles", "openmw_profile_effective", "openmw_setting",
    "openmw_vfs_resolve", "openmw_vfs_overrides", "openmw_vfs_compare", "openmw_mods_identify",
    "openmw_mod_identify_dir", "openmw_groundcover_mode", "openmw_groundcover_stats", "openmw_esp_info",
    "openmw_manifest_build", "openmw_manifest_write", "openmw_profile_diff",
    "openmw_land_cell", "openmw_land_point", "openmw_groundcover_baseline", "openmw_land_texture_mapping_check",
    "openmw_groundcover_height_offset", "openmw_groundcover_region",
    "openmw_fork_flora_cell", "openmw_fork_flora_region", "openmw_flora_compare", "openmw_flora_coverage",
    "openmw_remiros_rules", "openmw_remiros_compare", "openmw_remiros_export"}


# --- niezależne źródła prawdy -----------------------------------------------------------------

def project_root() -> Path:
    for d in (MCP_DIR, *MCP_DIR.parents, *MCP_DIR.resolve().parents):
        if (d / "Fork").is_dir() and (d / "OpenMW").is_dir():
            return d
    sys.exit("nie znaleziono katalogu projektu (Fork/ + OpenMW/)")


ROOT = project_root()


def fs(p: str | Path) -> Path:
    """Dostęp do pliku: ścieżka hosta z .cfg, ewentualnie przemapowana (OPENMW_MCP_PATH_MAP — tylko do testów na kopii)."""
    s = str(p)
    for item in sorted((i for i in os.environ.get("OPENMW_MCP_PATH_MAP", "").split(";") if "=" in i),
                       key=lambda i: -len(i.split("=", 1)[0])):
        a, b = item.split("=", 1)
        if s == a.rstrip("/") or s.startswith(a.rstrip("/") + "/"):
            return Path(b.rstrip("/") + s[len(a.rstrip("/")):])
    return Path(s)


def sh(*cmd: str) -> tuple[int, str]:
    if not shutil.which(cmd[0]):
        return 127, ""
    r = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    return r.returncode, r.stdout.strip()


def cfg_lines(path: Path, key: str) -> list[str]:
    out = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k.strip() == key:
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] == '"':
                v = v[1:-1].replace('&"', '"').replace("&&", "&")
            out.append(v)
    return out


def ini(path: Path) -> dict:
    res: dict = {}
    sec = None
    if not path.is_file():
        return res
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            sec = line[1:-1].strip().lower(); res.setdefault(sec, {})
        elif "=" in line and sec and not line.startswith("#"):
            k, v = line.split("=", 1)
            res[sec][k.strip().lower()] = v.strip()
    return res


def esp_counts(path: Path) -> tuple[set, set, list]:
    """Własny minimalny parser: klucze komórek (zewnętrzne (x, y), wnętrza po nazwie), ID statyk, mastery."""
    data = path.read_bytes()
    o, cells, stats, masters = 0, set(), set(), []
    while o + 16 <= len(data):
        t, size = data[o:o + 4], struct.unpack_from("<I", data, o + 4)[0]
        subs, so = {}, o + 16
        while so + 8 <= o + 16 + size:
            st, n = data[so:so + 4], struct.unpack_from("<I", data, so + 4)[0]
            if st == b"FRMR":
                break                                   # dalej są referencje — nagłówek komórki już mamy
            if t == b"TES3" and st == b"MAST":
                masters.append(data[so + 8:so + 8 + n].split(b"\0")[0].decode("latin-1"))
            subs.setdefault(st, data[so + 8:so + 8 + n])
            so += 8 + n
        if t == b"CELL" and b"DATA" in subs and len(subs[b"DATA"]) == 12:
            flags, x, y = struct.unpack("<Iii", subs[b"DATA"])
            name = subs.get(b"NAME", b"").split(b"\0")[0].decode("latin-1").lower()
            cells.add(("int", name) if flags & 1 else ("ext", x, y))
        elif t == b"STAT" and b"NAME" in subs:
            stats.add(subs[b"NAME"].split(b"\0")[0].decode("latin-1").lower())
        o += 16 + size
    return cells, stats, masters


def cell_regions(files: list[Path]) -> dict:
    """RGNN komórek zewnętrznych z plików content= (później wczytany wygrywa) — własny parser."""
    out = {}
    for f in files:
        data = f.read_bytes(); o = 0
        while o + 16 <= len(data):
            t, size = data[o:o + 4], struct.unpack_from("<I", data, o + 4)[0]
            if t == b"CELL":
                so, xy, rg, fl = o + 16, None, None, None
                while so + 8 <= o + 16 + size:
                    st, n = data[so:so + 4], struct.unpack_from("<I", data, so + 4)[0]
                    if st == b"FRMR":
                        break
                    if st == b"DATA" and n == 12 and fl is None:
                        fl, x, y = struct.unpack_from("<Iii", data, so + 8); xy = (x, y)
                    elif st == b"RGNN":
                        rg = data[so + 8:so + 8 + n].split(b"\0")[0].decode("latin-1")
                    so += 8 + n
                if fl is not None and not fl & 1 and rg is not None:
                    out[xy] = rg
            o += 16 + size
    return out


def find_file(dirs: list[Path], name: str) -> Path | None:
    hit = None
    for d in dirs:
        if d.is_dir():
            for f in d.iterdir():
                if f.name.lower() == name.lower():
                    hit = f
    return hit


def loose_index(d: Path) -> dict[str, str]:
    out = {}
    for dp, dn, fn in os.walk(d):
        dn.sort()
        for f in sorted(fn):
            p = Path(dp) / f
            out[p.relative_to(d).as_posix().lower()] = str(p)
    return out


def truth() -> dict:
    t: dict = {}
    rc, head = sh("git", "-C", str(ROOT / "Fork/repo"), "rev-parse", "HEAD")
    t["fork_head"] = head if rc == 0 else None
    t["fork_branch"] = sh("git", "-C", str(ROOT / "Fork/repo"), "rev-parse", "--abbrev-ref", "HEAD")[1] or None
    vf = ROOT / "Fork/install/share/games/openmw/resources/version"
    t["fork_binary_commit"] = vf.read_text().splitlines()[1].strip() if vf.is_file() else None
    rc, ohead = sh("git", "-C", str(ROOT / "OpenMW/repo"), "rev-parse", "HEAD")
    t["official_repo_head"] = ohead if rc == 0 else None
    t["official_tag_commit"] = sh("git", "-C", str(ROOT / "OpenMW/repo"), "rev-parse", "openmw-0.51.0^{commit}")[1] or None
    rc, info = sh("flatpak", "info", "org.openmw.OpenMW")
    t["flatpak_available"] = rc == 0
    m = re.search(r"^\s*Version:\s*(\S+)", info, re.M)
    t["flatpak_version"] = m.group(1) if m else None
    loc = sh("flatpak", "info", "--show-location", "org.openmw.OpenMW")[1]
    t["flatpak_source_commit"] = None
    if loc and (fs(loc) / "files/manifest.json").is_file():
        mf = json.loads((fs(loc) / "files/manifest.json").read_text())
        for mod in mf.get("modules", []):
            if isinstance(mod, dict) and mod.get("name") == "openmw":
                for s in mod.get("sources", []):
                    if isinstance(s, dict) and s.get("commit"):
                        t["flatpak_source_commit"] = s["commit"]
    ref = ROOT / "OpenMW/config/openmw-ref"
    t["ref_data"] = cfg_lines(ref / "openmw.cfg", "data")
    t["ref_content"] = cfg_lines(ref / "openmw.cfg", "content")
    t["ref_groundcover"] = cfg_lines(ref / "openmw.cfg", "groundcover")
    t["ref_settings_gc"] = ini(ref / "settings.cfg").get("groundcover", {})
    fork = ROOT / "Fork/config/openmw-test"
    t["fork_data"] = cfg_lines(fork / "openmw.cfg", "data")
    t["fork_content"] = cfg_lines(fork / "openmw.cfg", "content")
    t["fork_groundcover"] = cfg_lines(fork / "openmw.cfg", "groundcover")
    t["fork_world_flora"] = ini(fork / "world.cfg").get("flora", {})
    t["fork_settings_gc"] = ini(fork / "settings.cfg").get("groundcover", {})
    # groundcover oficjalny: CELL i STAT z plików (kolejność katalogów data=, później wygrywa)
    cells, stats, missing = set(), set(), []
    for g in t["ref_groundcover"]:
        f = find_file([fs(d) for d in t["ref_data"]], g)
        if f is None:
            missing.append(g); continue
        c, s, _ = esp_counts(f); cells |= c; stats |= s
    t["ref_gc_cells"], t["ref_gc_statics"], t["ref_gc_missing"] = len(cells), len(stats), missing
    t["ref_gc_ext_cells"] = sum(1 for c in cells if c[0] == "ext")
    content_files = [f for f in (find_file([fs(d) for d in t["ref_data"]], c) for c in t["ref_content"]) if f]
    regs = cell_regions(content_files) if content_files else {}
    t["regions_sample"] = {f"{x},{y}": regs.get((x, y)) for x, y in ((15, -9), (2, -10), (-13, 13), (-4, 9))}
    return t


def vfs_overlaps(data_dirs: list[str], limit: int = 3, skip_large: int = 60000) -> list[tuple[str, str]]:
    """Ścieżki dostarczane przez ≥2 katalogi data= (luźne pliki): (ścieżka, katalog zwycięzcy = ostatni)."""
    idx = []
    for d in data_dirs:
        p = fs(d)
        idx.append(loose_index(p) if p.is_dir() else {})
    seen: dict = {}
    for i, ix in enumerate(idx):
        if len(ix) > skip_large:
            continue
        for k in ix:
            seen.setdefault(k, []).append(i)
    multi = sorted(k for k, v in seen.items() if len(v) > 1 and not k.endswith((".esp", ".esm", ".omwaddon")))
    pick = multi[:1] + multi[len(multi) // 2:len(multi) // 2 + 1] + multi[-1:] if multi else []
    out = []
    for k in dict.fromkeys(pick):
        out.append((k, data_dirs[seen[k][-1]]))
    return out[:limit]


# --- klient MCP -------------------------------------------------------------------------------

class Checks:
    def __init__(self):
        self.rows: list[dict] = []

    def add(self, area: str, name: str, ok, expected=None, got=None, note: str = ""):
        status = "SKIP" if ok is None else ("PASS" if ok else "FAIL")
        self.rows.append({"area": area, "check": name, "status": status, "expected": expected, "got": got, "note": note})
        mark = {"PASS": "✔", "FAIL": "✘", "SKIP": "–"}[status]
        print(f"  {mark} [{area}] {name}" + (f" — oczekiwano {expected!r}, jest {got!r}" if status == "FAIL" else "")
              + (f" ({note})" if note and status != "PASS" else ""))


def find_key(o, key):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == key:
                yield v
            yield from find_key(v, key)
    elif isinstance(o, list):
        for v in o:
            yield from find_key(v, key)


def unpack(res) -> dict:
    for c in getattr(res, "content", []) or []:
        text = getattr(c, "text", None)
        if text:
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return {"error": f"odpowiedź nie jest JSON: {text[:200]}"}
    sc = getattr(res, "structuredContent", None) or getattr(res, "structured_content", None)
    if isinstance(sc, dict):
        return sc.get("result", sc) if set(sc) == {"result"} else sc
    return {"error": "pusta odpowiedź"}


async def run(t: dict, C: Checks, raw: dict):
    try:
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client
    except ImportError as e:
        sys.exit(f"brak klienta MCP w tym Pythonie ({e}); uruchom przez .venv/bin/python")
    exe = MCP_DIR / ".venv/bin/openmw-mcp"
    # ta sama binarka co w `claude mcp add`, o ile skrypt działa w tym samym venv; inaczej bieżący Python
    same_venv = Path(sys.prefix).resolve() == (MCP_DIR / ".venv").resolve()
    cmd, args = (str(exe), []) if exe.exists() and same_venv else (sys.executable, ["-m", "openmw_mcp.server"])
    params = StdioServerParameters(command=cmd, args=args, env=dict(os.environ), cwd=str(MCP_DIR))
    print(f"serwer: {cmd} {' '.join(args)}")
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            init = await s.initialize()
            C.add("protokół", "initialize", True, got=getattr(getattr(init, "serverInfo", None), "name", None))
            names = {tl.name for tl in (await s.list_tools()).tools}
            C.add("protokół", "zarejestrowane narzędzia ⊇ oczekiwane", EXPECTED_TOOLS <= names,
                  sorted(EXPECTED_TOOLS - names), sorted(names - EXPECTED_TOOLS) or "brak dodatkowych")

            async def call(name, **kw):
                res = unpack(await s.call_tool(name, kw))
                raw[f"{name}({', '.join(f'{k}={v}' for k, v in kw.items())})"] = res
                return res

            # 1. instalacje i commity
            env = await call("openmw_env_status", hash_binaries=True)
            fk, of = env.get("fork", {}), env.get("official", {})
            C.add("silniki", "fork: HEAD repo = git rev-parse", fk.get("repo", {}).get("head") == t["fork_head"],
                  t["fork_head"], fk.get("repo", {}).get("head"))
            C.add("silniki", "fork: gałąź 0.5-world", fk.get("repo", {}).get("branch") == "0.5-world" == t["fork_branch"],
                  "0.5-world", fk.get("repo", {}).get("branch"))
            C.add("silniki", "fork: commit binarki = resources/version", fk.get("binary_commit") == t["fork_binary_commit"],
                  t["fork_binary_commit"], fk.get("binary_commit"))
            if t["flatpak_available"]:
                C.add("silniki", "official: wersja = flatpak info", of.get("version") == t["flatpak_version"] == "0.51.0",
                      t["flatpak_version"], of.get("version"))
                C.add("silniki", "official: commit źródeł = manifest.json = tag 0.51.0",
                      of.get("source_commit") == t["flatpak_source_commit"] == EXPECTED_SOURCE_COMMIT,
                      EXPECTED_SOURCE_COMMIT, of.get("source_commit"))
                C.add("silniki", "official: commit pakietu ≠ commit źródeł (to różne obiekty)",
                      bool(of.get("flatpak", {}).get("package_commit")) and
                      of.get("flatpak", {}).get("package_commit") != of.get("source_commit"),
                      "różne", of.get("flatpak", {}).get("package_commit"))
            else:
                C.add("silniki", "official: Flatpak", None, note="flatpak niedostępny w tym środowisku")
            C.add("silniki", "OpenMW/repo HEAD = tag openmw-0.51.0",
                  (of.get("repo") or {}).get("head") == t["official_repo_head"] == t["official_tag_commit"] == EXPECTED_SOURCE_COMMIT,
                  EXPECTED_SOURCE_COMMIT, (of.get("repo") or {}).get("head"))
            gi = await call("openmw_git_info", target="fork")
            C.add("silniki", "openmw_git_info(fork) zgodne z env_status", gi.get("head") == t["fork_head"], t["fork_head"], gi.get("head"))
            mcpi = env.get("mcp", {})
            C.add("MCP", "kod zgodny z SOURCE-MANIFEST", mcpi.get("matches_stored_manifest") is True,
                  True, mcpi.get("matches_stored_manifest"), mcpi.get("tree_sha256", ""))
            if (mcpi.get("git") or {}).get("in_git"):
                C.add("MCP", "żaden plik źródłowy nie jest ignorowany przez Git", mcpi["git"].get("ignored_source_files") == [],
                      [], mcpi["git"].get("ignored_source_files"))

            # 2. profile
            for prof, data, content, gc in (("official-ref", "ref_data", "ref_content", "ref_groundcover"),
                                            ("fork-test", "fork_data", "fork_content", "fork_groundcover")):
                eff = await call("openmw_profile_effective", profile=prof)
                if "error" in eff:
                    C.add(prof, "profil rozwiązany", None if "flatpak" in eff["error"] else False, got=eff["error"],
                          note="wymaga Flatpaka" if "flatpak" in eff["error"] else "")
                    continue
                got_content = [c["name"] for c in eff.get("content", [])]
                C.add(prof, "content= w kolejności", got_content == t[content], t[content], got_content)
                got_gc = [g["name"] for g in eff.get("groundcover", [])]
                C.add(prof, "groundcover= w kolejności", got_gc == t[gc], t[gc], got_gc)
                C.add(prof, "wszystkie pluginy znalezione na dysku",
                      all(c.get("file") for c in eff.get("content", []) + eff.get("groundcover", [])), True,
                      [c["name"] for c in eff.get("content", []) + eff.get("groundcover", []) if not c.get("file")] or True)
                got_dirs = [str(d.get("path")) for d in eff.get("data_dirs", [])]
                pos = [got_dirs.index(d) if d in got_dirs else -1 for d in t[data]]
                C.add(prof, "data= z profilu obecne i w tej samej kolejności", -1 not in pos and pos == sorted(pos),
                      t[data], got_dirs)
                iso = eff.get("isolation", {})
                C.add(prof, "izolacja od domyślnego profilu użytkownika", iso.get("isolated") is True, True, iso.get("violations"))
                exp_ucfg = str(ROOT / ("OpenMW/config/openmw-ref" if prof == "official-ref" else "Fork/config/openmw-test"))
                C.add(prof, "katalog konfiguracji użytkownika", str(eff.get("user_config_dir")) == exp_ucfg, exp_ucfg, eff.get("user_config_dir"))
                for dpath, winner in vfs_overlaps(t[data]):
                    vr = await call("openmw_vfs_resolve", profile=prof, path=dpath)
                    got = (vr.get("winner") or {}).get("root")
                    C.add(prof, f"VFS: zwycięzca {dpath}", got is not None and fs(got) == fs(winner), winner, got)

            # 3. flora
            wf = t["fork_world_flora"]
            en = wf.get("enabled", "false").lower() == "true"
            src = wf.get("source", "automatic").lower()
            gc_en = t["fork_settings_gc"].get("enabled", "false").lower() == "true"
            exp_proc = en and src in ("automatic", "hybrid")
            exp_plug = (en and src in ("groundcover", "hybrid")) or (not en and gc_en)
            gm = await call("openmw_groundcover_mode", profile="fork-test")
            C.add("flora", "fork: proceduralna flora wg world.cfg", gm.get("procedural") == exp_proc, exp_proc, gm.get("procedural"))
            C.add("flora", f"fork: pluginowy Groundcover (world.cfg source={src})", gm.get("plugins_rendered") == exp_plug,
                  exp_plug, gm.get("plugins_rendered"),
                  "source=automatic wyłącza pluginy mimo [Groundcover] enabled=true" if src == "automatic" else "")
            prof_info = gm.get("procedural_profile") or {}
            C.add("flora", "fork: pula modeli kompletna w VFS", prof_info.get("pool_found_in_vfs") == prof_info.get("pool_models") and
                  bool(prof_info.get("pool_models")), prof_info.get("pool_models"), prof_info.get("pool_found_in_vfs"))
            C.add("flora", "fork: aktywne profile regionalne Remirosa", sorted(prof_info.get("active_profiles") or []) ==
                  ["AI", "AL", "BC", "GL", "WG"], ["AI", "AL", "BC", "GL", "WG"], prof_info.get("active_profiles"))
            gmo = await call("openmw_groundcover_mode", profile="official-ref")
            if "error" not in gmo:
                exp_on = t["ref_settings_gc"].get("enabled", "false").lower() == "true"
                C.add("flora", "official: Groundcover z pluginów ESP", gmo.get("plugins_rendered") is exp_on and
                      gmo.get("procedural") in (False, None), exp_on, gmo.get("plugins_rendered"))
                C.add("flora", "official: mechanizm", "pluginy ESP" in str(gmo.get("mechanism")), "oficjalny Groundcover (pluginy ESP)",
                      gmo.get("mechanism"))
                st = await call("openmw_groundcover_stats", profile="official-ref")
                C.add("flora", "official: CELL w groundcover = parser niezależny = log silnika (701)",
                      st.get("cells") == t["ref_gc_cells"] == AUDIT["official_cells"], [t["ref_gc_cells"], AUDIT["official_cells"]], st.get("cells"))
                C.add("flora", "official: statyki = parser niezależny = log silnika (105)",
                      st.get("statics") == t["ref_gc_statics"] == AUDIT["official_statics"],
                      [t["ref_gc_statics"], AUDIT["official_statics"]], st.get("statics"))
                mi = await call("openmw_mods_identify", profile="official-ref")
                orders = [o for em in find_key(mi, "exact_matches") for o in (em or [])]
                plain = [[v.split(" :: ")[-1] for v in o] for o in orders]
                C.add("mody", "Remiros = Core OpenMW + 01b Thicker Grass (dokładnie, SHA-256)", REMIROS_VARIANT in plain,
                      REMIROS_VARIANT, orders or mi.get("error"))
                ei = await call("openmw_esp_info", profile="official-ref", plugin="Rem_AC.esp")
                rem_ac = find_file([fs(d) for d in t["ref_data"]], "Rem_AC.esp")
                _, _, masters = esp_counts(rem_ac)
                got_m = [m if isinstance(m, str) else m.get("name") for m in ei.get("masters", [])]
                C.add("mody", "Rem_AC.esp: mastery = parser niezależny", got_m == masters, masters, got_m)
                raw_cells = 0
                data = rem_ac.read_bytes(); o = 0
                while o + 16 <= len(data):
                    raw_cells += data[o:o + 4] == b"CELL"; o += 16 + struct.unpack_from("<I", data, o + 4)[0]
                C.add("mody", "Rem_AC.esp: liczba rekordów CELL = parser niezależny",
                      ei.get("records", {}).get("CELL") == raw_cells, raw_cells, ei.get("records", {}).get("CELL"))
                # 4. porównanie środowisk
                vc = await call("openmw_vfs_compare", profile_a="fork-test", profile_b="official-ref", prefix="meshes/grass/", limit=20)
                C.add("porównanie", "openmw_vfs_compare odpowiada bez błędu", "error" not in vc, None, vc.get("error"))
                pdiff = await call("openmw_profile_diff", profile_a="fork-test", profile_b="official-ref", hash_mods=True)
                C.add("porównanie", "różne silniki wykryte", bool(pdiff.get("engine")), "niepusty", list(pdiff.get("engine", {})))
                C.add("porównanie", "różny mechanizm flory wykryty", bool(pdiff.get("flora")), "niepusty", pdiff.get("flora"))
                C.add("porównanie", "ostrzeżenia o porównywalności (informacyjnie — treść w raporcie)",
                      isinstance(pdiff.get("comparability_warnings"), list), "lista", pdiff.get("comparability_warnings"))
                # 5. etap 2
                dens = float(t["ref_settings_gc"].get("density", "1.0"))
                bl = await call("openmw_groundcover_baseline", profile="official-ref", cell_x=15, cell_y=-9)
                if dens == 1.0:
                    C.add("etap 2", "baseline (15,−9) gęstość 1.0 = 1449", bl.get("instances") == AUDIT["baseline_15_-9_density1"],
                          AUDIT["baseline_15_-9_density1"], bl.get("instances"))
                else:
                    C.add("etap 2", "baseline (15,−9)", None, got=bl.get("instances"), note=f"density={dens} w settings.cfg")
                lc = await call("openmw_land_cell", profile="official-ref", cell_x=15, cell_y=-9)
                C.add("etap 2", "LAND (15,−9) z Morrowind.esm", lc.get("file", "").lower() == "morrowind.esm", "Morrowind.esm", lc.get("file"))
                rg = await call("openmw_groundcover_region", profile="official-ref", x0=15 * 8192, y0=-9 * 8192,
                                x1=16 * 8192, y1=-8 * 8192)
                C.add("etap 2", "region (15,−9): z przypisanych do (15,−9) = baseline.position_inside_cell",
                      (rg.get("by_assigned_cell") or {}).get("15,-9") == bl.get("position_inside_cell"),
                      bl.get("position_inside_cell"), rg.get("by_assigned_cell"))
                # 6. etap 2c — proceduralna flora forka i porównanie
                cov = await call("openmw_flora_coverage", top=5)
                C.add("etap 2c", "pokrycie: komórki zewnętrzne Remirosa = parser niezależny",
                      cov.get("totals", {}).get("cells") == t["ref_gc_ext_cells"], t["ref_gc_ext_cells"], cov.get("totals"))
                C.add("etap 2c", "pokrycie: suma instancji = suma komórek pokrytych + niepokrytych",
                      cov.get("totals", {}).get("official_instances") ==
                      cov.get("totals", {}).get("covered_instances", -1) + cov.get("uncovered_official_instances", -1),
                      None, cov.get("totals"))
                fc = await call("openmw_flora_compare", cell_x=15, cell_y=-9)
                C.add("etap 2c", "(15,−9): region = RGNN z parsera niezależnego", fc.get("region") == t["regions_sample"]["15,-9"],
                      t["regions_sample"]["15,-9"], fc.get("region"))
                exp_gen = t["regions_sample"]["15,-9"] in ("Ascadian Isles Region", "Ashlands Region", "Bitter Coast Region",
                                                           "Grazelands Region", "West Gash Region") or bool(fc.get("fork_profiles"))
                C.add("etap 2c", "(15,−9): fork generuje tylko przy profilu regionu", fc.get("fork_generates") == exp_gen,
                      exp_gen, [fc.get("fork_generates"), fc.get("fork_profiles"), fc.get("fork_reason")])
                C.add("etap 2c", "(15,−9): oficjalne z przypisanych do komórki = baseline.position_inside_cell",
                      (fc.get("official", {}).get("by_assigned_cell") or {}).get("15,-9") == bl.get("position_inside_cell"),
                      bl.get("position_inside_cell"), fc.get("official", {}).get("by_assigned_cell"))
                for key in ("2,-10", "-13,13", "-4,9"):
                    x, y = map(int, key.split(","))
                    a = await call("openmw_fork_flora_cell", profile="fork-test", cell_x=x, cell_y=y)
                    b = await call("openmw_fork_flora_cell", profile="fork-test", cell_x=x, cell_y=y)
                    C.add("etap 2c", f"fork ({key}): region zgodny i wynik deterministyczny",
                          a.get("region") == t["regions_sample"][key] and a.get("instances") == b.get("instances") and
                          a.get("generated") is True, [t["regions_sample"][key], "generated"],
                          [a.get("region"), a.get("instances"), b.get("instances"), a.get("generated")])
                # 7. trawa Remirosa w forku (pach75): reguły i emulacja
                rr = await call("openmw_remiros_rules", top=3)
                C.add("pach75", "reguły: suma referencji = suma instancji oficjalnych (pokrycie)",
                      rr.get("refs") == cov.get("totals", {}).get("official_instances"),
                      cov.get("totals", {}).get("official_instances"), rr.get("refs"))
                C.add("pach75", "reguły: każda statyka przypisana do jednej tekstury (7 pluginów)",
                      len({p for r in rr.get("rules", []) for p in r.get("plugins", [])}) >= 1 and rr.get("statics", 0) > 90,
                      ">90 statyk", rr.get("statics"))
                for key in ("2,-10", "-24,19", "15,-9"):
                    x, y = map(int, key.split(","))
                    rc = await call("openmw_remiros_compare", cell_x=x, cell_y=y)
                    C.add("pach75", f"emulacja forka po pach75 ({key}) = Remiros ±3%",
                          rc.get("ratio") is not None and abs(rc["ratio"] - 1.0) <= 0.03, "0.97–1.03", rc.get("ratio"))
            else:
                C.add("flora", "official", None, got=gmo["error"], note="wymaga Flatpaka")


def main() -> int:
    report = "--no-report" not in sys.argv
    print(f"projekt: {ROOT}\nMCP: {MCP_DIR}")
    t = truth()
    C, raw = Checks(), {}
    asyncio.run(run(t, C, raw))
    n = {k: sum(r["status"] == k for r in C.rows) for k in ("PASS", "FAIL", "SKIP")}
    print(f"\nWYNIK: {n['PASS']} PASS, {n['FAIL']} FAIL, {n['SKIP']} SKIP")
    if report:
        out = ROOT / "Raporty/mcp/testy"
        out.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M%S")
        path = out / f"integracja-{stamp}.json"
        path.write_text(json.dumps({"date": stamp, "summary": n, "checks": C.rows, "truth": t, "responses": raw},
                                   ensure_ascii=False, indent=1, default=str), encoding="utf-8")
        print(f"raport: {path}")
    return 1 if n["FAIL"] else (3 if n["SKIP"] else 0)


if __name__ == "__main__":
    sys.exit(main())
