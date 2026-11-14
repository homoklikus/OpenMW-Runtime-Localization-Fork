"""Manifest testu (etykieta stanu) i diagnostyka różnic między profilami."""

from __future__ import annotations

import datetime as _dt
import json
import re
from pathlib import Path
from typing import Optional

from . import environment, esp, flora, mods, profiles
from .environment import Env
from .util import stable_hash, vfs_key

RELEVANT_SETTINGS = [
    ("Groundcover", "enabled"), ("Groundcover", "density"), ("Groundcover", "rendering distance"),
    ("Groundcover", "stomp mode"), ("Groundcover", "stomp intensity"), ("Camera", "viewing distance"),
    ("Camera", "field of view"), ("Terrain", "distant terrain"), ("Terrain", "object paging"),
    ("Video", "resolution x"), ("Video", "resolution y"), ("General", "preferred locales"),
    ("Shaders", "lighting method"), ("Post Processing", "enabled"),
]


def _engine(env: Env, target: str, hash_binary: bool) -> dict:
    d = environment.detect_fork(env, hash_binary) if target == "fork" else environment.detect_official(env, hash_binary)
    repo = d.get("repo") or {}
    b = d.get("binary") or {}
    eng = {"target": target, "status": d.get("status"), "issues": d.get("issues", []),
           "repo_head": repo.get("head"), "repo_branch": repo.get("branch"), "repo_tag": repo.get("tag"),
           "repo_tracked_changes": repo.get("tracked_changes"),
           "binary_path": b.get("path"), "binary_sha256": b.get("sha256"), "binary_build_id": b.get("elf_build_id"),
           "binary_markers": b.get("markers")}
    if target == "fork":
        eng["binary_commit"] = d.get("binary_commit")
        eng["build"] = d.get("build")
        eng["experiments"] = d.get("experiments")
    else:
        eng.update({"version": d.get("version"), "source_commit": d.get("source_commit"),
                    "flatpak_package_commit": (d.get("flatpak") or {}).get("package_commit"),
                    "flatpak_location": d.get("location")})
    return eng


def pool_for(env: Env, profile: str, variant: Optional[str]) -> tuple[Optional[list[str]], str]:
    prof = env.cfg["profiles"][profile]
    if variant == "none":
        return None, "brak (bez OPENMW_FLORA_TEST_ASSET)"
    if variant and variant.startswith("list:"):
        return [x for x in variant[5:].split(",") if x], "parametr"
    script = env.p(prof.get("flora_pool_script")) if prof.get("flora_pool_script") else None
    if not script:
        return None, ""
    pools = flora.parse_pool_script(script)
    v = variant or prof.get("flora_pool_variant", "all")
    if v not in pools:
        return None, f"brak puli '{v}' w {script}"
    return pools[v], f"{env.rel(script)} (RLF_FLORA_POOL={v})"


def build(env: Env, profile: str, hash_mods: bool = True, pool_variant: Optional[str] = None,
          hash_binary: bool = True, max_files: Optional[int] = None) -> dict:
    eff = profiles.effective(env, profile)
    target = eff["target"]
    eng = _engine(env, target, hash_binary)
    cfg_files = [{"path": f, "sha256": env.cache.sha256(Path(f))} for f in eff["config_files"]]
    for name in ("settings.cfg", "world.cfg"):
        f = Path(eff["user_config_dir"]) / name
        if f.is_file():
            cfg_files.append({"path": str(f), "sha256": env.cache.sha256(f)})
    dd = mods.data_dir_report(env, eff, hash_files=hash_mods, max_files=max_files)
    conflicts = mods.name_conflicts(dd)
    data_dirs = []
    for d in dd:
        d = {k: v for k, v in d.items() if k != "_files"}
        if "variant" in d:
            m = d["variant"]["match"]
            d["variant"] = {"order": m["order"], "exact": m["exact"], "matching": m["matching"], "total": m["total"],
                            "different": m["different"][:20], "not_in_variants": m["not_in_variants"][:20],
                            "files_with_multiple_sources": d["variant"]["files_with_multiple_sources"]}
        data_dirs.append(d)

    def plug(lst):
        out = []
        for p in lst:
            ent = {"name": p["name"], "file": p["file"]}
            if p["file"]:
                ent["sha256"] = env.cache.sha256(Path(p["file"]))
                if p["name"].lower().endswith((".esm", ".esp", ".omwaddon", ".omwgame")):
                    try:
                        hi = esp.esp_info(Path(p["file"]), count_records=False)
                        ent["masters"] = hi.get("masters")
                    except OSError:
                        pass
            out.append(ent)
        return out

    st = eff["settings"]["merged"]
    from .cfgparse import setting
    rel_settings = {f"{s}/{k}": setting(st, s, k) for s, k in RELEVANT_SETTINGS}
    pool, pool_src = pool_for(env, profile, pool_variant) if target == "fork" else (None, "")
    vfs = profiles.vfs_index(eff) if target == "fork" and eff.get("world_cfg") else None
    fl = flora.classify(eff, target, vfs, pool, pool_src, eng.get("experiments"))
    from . import srcmanifest
    man = {
        "manifest_version": 1, "created": _dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "mcp": srcmanifest.info(),
        "profile": profile, "engine": eng, "config_files": cfg_files,
        "active_config_dirs": eff["active_config_dirs"], "encoding": eff["encoding"],
        "single_options": {k: v["value"] for k, v in eff["single"].items()},
        "data_dirs": data_dirs, "data_dir_name_conflicts": conflicts,
        "fallback_archives": [{"name": a["name"], "file": a["file"],
                               "sha256": env.cache.sha256(Path(a["file"])) if a["file"] and hash_mods else None}
                              for a in eff["fallback_archives"]],
        "content": plug(eff["content"]), "groundcover": plug(eff["groundcover"]),
        "settings_relevant": rel_settings, "settings_hash": stable_hash(st),
        "world_cfg": eff.get("world_cfg"), "flora": fl, "isolation": eff["isolation"],
        "issues": eff["issues"], "warnings": eff["warnings"],
    }
    env.cache.save()
    man["label"] = stable_hash({
        "engine": [eng.get("target"), eng.get("repo_head"), eng.get("binary_sha256"), eng.get("binary_commit"),
                   eng.get("source_commit")],
        "data": [(d["name"], d.get("fingerprint")) for d in data_dirs],
        "content": [(c["name"], c.get("sha256")) for c in man["content"]],
        "groundcover": [(c["name"], c.get("sha256")) for c in man["groundcover"]],
        "settings": man["settings_hash"], "world": eff.get("world_cfg"), "pool": pool,
    })[:16]
    return man


def write(env: Env, man: dict, name: Optional[str] = None) -> Path:
    out_dir = env.p(env.cfg.get("manifest_dir", "Raporty/mcp/manifesty"))
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", name or man["profile"])
    path = out_dir / f"{stamp}-{safe}-{man['label']}.json"
    path.write_text(json.dumps(man, indent=1, ensure_ascii=False), encoding="utf-8")
    return path


def diff(a: dict, b: dict) -> dict:
    """Różnice dwóch manifestów; ostrzeżenia o porównywalności."""
    out = {"a": a["profile"], "b": b["profile"], "label_a": a["label"], "label_b": b["label"],
           "identical_label": a["label"] == b["label"], "engine": {}, "data_dirs": {}, "plugins": {},
           "settings": {}, "flora": {}, "comparability_warnings": []}
    ea, eb = a["engine"], b["engine"]
    for k in ("target", "repo_head", "binary_commit", "source_commit", "binary_sha256", "version"):
        if ea.get(k) != eb.get(k):
            out["engine"][k] = [ea.get(k), eb.get(k)]

    da = {d["name"].lower(): d for d in a["data_dirs"]}
    db = {d["name"].lower(): d for d in b["data_dirs"]}
    fa = {d.get("fingerprint"): d["name"] for d in a["data_dirs"] if d.get("fingerprint")}
    fb = {d.get("fingerprint"): d["name"] for d in b["data_dirs"] if d.get("fingerprint")}
    same_name_diff = [n for n in da if n in db and da[n].get("fingerprint") and db[n].get("fingerprint")
                      and da[n]["fingerprint"] != db[n]["fingerprint"]]
    same_content_diff_name = [(fa[f], fb[f]) for f in fa if f in fb and fa[f].lower() != fb[f].lower()]
    out["data_dirs"] = {
        "only_in_a": [da[n]["name"] for n in da if n not in db and da[n].get("fingerprint") not in fb],
        "only_in_b": [db[n]["name"] for n in db if n not in da and db[n].get("fingerprint") not in fa],
        "same_name_different_content": [da[n]["name"] for n in same_name_diff],
        "same_content_different_name": same_content_diff_name,
        "order_a": [d["name"] for d in a["data_dirs"]], "order_b": [d["name"] for d in b["data_dirs"]],
    }
    if same_name_diff:
        out["comparability_warnings"].append(f"mody o tej samej nazwie, ale innej zawartości: {[da[n]['name'] for n in same_name_diff]}")
    for key in ("content", "groundcover"):
        la = [(p["name"].lower(), p.get("sha256")) for p in a[key]]
        lb = [(p["name"].lower(), p.get("sha256")) for p in b[key]]
        na, nb = [x[0] for x in la], [x[0] for x in lb]
        sha_diff = [n for n, s in la if n in dict(lb) and dict(lb)[n] != s]
        out["plugins"][key] = {"only_in_a": [n for n in na if n not in nb], "only_in_b": [n for n in nb if n not in na],
                               "same_name_different_sha256": sha_diff,
                               "order_differs": [n for n in na if n in nb] != [n for n in nb if n in na]}
        if sha_diff:
            out["comparability_warnings"].append(f"{key}: te same nazwy, różne SHA-256: {sha_diff}")
    for k in set(a["settings_relevant"]) | set(b["settings_relevant"]):
        va, vb = a["settings_relevant"].get(k), b["settings_relevant"].get(k)
        if va != vb:
            out["settings"][k] = [va, vb]
    if any(k.startswith(("Groundcover/", "Camera/viewing")) for k in out["settings"]):
        out["comparability_warnings"].append("różne ustawienia Groundcover/widoczności — liczby i obraz nieporównywalne 1:1")
    fla, flb = a["flora"], b["flora"]
    out["flora"] = {"mechanism": [fla.get("mechanism"), flb.get("mechanism")]}
    if fla.get("mechanism") != flb.get("mechanism"):
        out["comparability_warnings"].append(f"różne mechanizmy roślinności: {fla.get('mechanism')} ↔ {flb.get('mechanism')}")
    for side, m in (("a", a), ("b", b)):
        for e in (m["engine"].get("experiments") or []):
            if "ZASTOSOWANY" in e.get("state", "") or "WKOMPILOWANY" in e.get("state", ""):
                out["comparability_warnings"].append(f"{side}: aktywny eksperyment {e['name']} ({e['state']})")
        if not m["isolation"]["isolated"]:
            out["comparability_warnings"].append(f"{side}: profil nieizolowany")
    return out


def vfs_compare(env: Env, profile_a: str, profile_b: str, prefix: str, limit: int = 200) -> dict:
    """Efektywne pliki (zwycięzcy VFS) pod prefiksem w dwóch profilach: ta sama ścieżka, różne SHA-256."""
    res = {}
    for name in (profile_a, profile_b):
        eff = profiles.effective(env, name)
        idx = profiles.vfs_index(eff)["index"]
        pre = vfs_key(prefix)
        res[name] = {k: v[-1] for k, v in idx.items() if k.startswith(pre)}
    A, B = res[profile_a], res[profile_b]
    rows = {"only_in_a": sorted(set(A) - set(B))[:limit], "only_in_b": sorted(set(B) - set(A))[:limit],
            "different_sha256": [], "identical": 0, "not_comparable_bsa": 0}
    for k in sorted(set(A) & set(B)):
        pa, pb = A[k], B[k]
        if not pa["file"] or not pb["file"]:
            rows["not_comparable_bsa"] += 1
            continue
        sa, sb = env.cache.sha256(Path(pa["file"])), env.cache.sha256(Path(pb["file"]))
        if sa == sb:
            rows["identical"] += 1
        elif len(rows["different_sha256"]) < limit:
            rows["different_sha256"].append({"path": k, "a": pa["root"], "b": pb["root"], "sha_a": sa, "sha_b": sb})
    env.cache.save()
    rows["counts"] = {"a": len(A), "b": len(B)}
    return rows
