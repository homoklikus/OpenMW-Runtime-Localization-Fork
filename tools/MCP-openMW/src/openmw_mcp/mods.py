"""Identyfikacja modów po zawartości: odciski SHA-256 katalogów, katalog wariantów, nakładki, konflikty nazw."""

from __future__ import annotations

import itertools
import os
from pathlib import Path
from typing import Optional

from .environment import Env
from .util import stable_hash, vfs_key


def dir_manifest(env: Env, root: Path, max_files: Optional[int] = None) -> dict:
    """Odcisk katalogu moda: klucz VFS -> sha256 (z cache). Pomija pliki ukryte metadanych narzędzi."""
    files: dict[str, str] = {}
    exact: list[tuple[str, str]] = []           # prawdziwe ścieżki (z wielkością liter) — do odcisku
    seen: dict[str, list[str]] = {}
    sizes = 0
    truncated = False
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".filegraph"))
        for f in sorted(filenames):
            full = Path(dirpath) / f
            if max_files is not None and len(exact) >= max_files:
                truncated = True
                break
            try:
                rel = os.path.relpath(full, root).replace(os.sep, "/")
                sha = env.cache.sha256(full)
                sizes += full.stat().st_size
            except OSError:
                continue
            exact.append((rel, sha))
            seen.setdefault(vfs_key(rel), []).append(rel)
            files[vfs_key(rel)] = sha
    env.cache.save()
    collisions = {k: v for k, v in seen.items() if len(v) > 1}
    return {"root": str(root), "name": root.name, "files": files, "file_count": len(exact), "bytes": sizes,
            "fingerprint": stable_hash(exact), "truncated": truncated,
            "case_collisions": collisions}


def load_catalogs(env: Env) -> dict[str, dict[str, str]]:
    """Pliki *.sha256 w formacie sha256sum, ścieżki './<Wariant>/<ścieżka>' → {wariant: {klucz: sha}}."""
    variants: dict[str, dict[str, str]] = {}
    for spec in env.cfg.get("catalogs", []):
        path = env.p(spec["file"])
        prefix = spec.get("name", path.stem if path else "?")
        if not path or not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            if "  " not in line:
                continue
            sha, rel = line.split("  ", 1)
            rel = rel[2:] if rel.startswith("./") else rel
            if "/" not in rel:
                continue
            var, inner = rel.split("/", 1)
            variants.setdefault(f"{prefix} :: {var}", {})[vfs_key(inner)] = sha
    return variants


def _overlay(variants: dict[str, dict[str, str]], order: tuple[str, ...]) -> dict[str, str]:
    out: dict[str, str] = {}
    for v in order:
        out.update(variants[v])
    return out


def identify(files: dict[str, str], variants: dict[str, dict[str, str]], max_combo: int = 3,
             ignore: tuple[str, ...] = ("meta.ini",)) -> dict:
    """Najlepsze dopasowanie zestawu wariantów (z kolejnością nakładania) do zawartości katalogu."""
    target = {k: v for k, v in files.items() if k not in ignore and not k.startswith(".")}
    if not target or not variants:
        return {"match": None, "candidates": []}
    # tylko warianty mające wspólne pliki z celem
    relevant = [v for v, fs in variants.items() if any(target.get(k) == s for k, s in fs.items())]
    cands = []
    for n in range(1, min(max_combo, len(relevant)) + 1):
        for order in itertools.permutations(relevant, n):
            eff = _overlay(variants, order)
            same = sum(1 for k, s in target.items() if eff.get(k) == s)
            diff = sorted(k for k, s in target.items() if k in eff and eff[k] != s)
            missing = sorted(k for k in target if k not in eff)
            extra = sorted(k for k in eff if k not in target)
            cands.append({"order": list(order), "matching": same, "total": len(target), "different": diff,
                          "not_in_variants": missing, "extra_in_variants": len(extra),
                          "exact": not diff and not missing and not extra})
    cands.sort(key=lambda c: (not c["exact"], -c["matching"], len(c["different"]), c["extra_in_variants"], len(c["order"])))
    exact = [c for c in cands if c["exact"]]
    best = exact[0] if exact else (cands[0] if cands else None)
    # dla każdego pliku: wszystkie warianty o tych samych bajtach
    sources = {}
    for k, s in target.items():
        sources[k] = [v for v, fs in variants.items() if fs.get(k) == s]
    ambiguous = sorted(k for k, v in sources.items() if len(v) > 1)
    return {"match": best, "exact_matches": [c["order"] for c in exact][:5], "candidates": cands[:5],
            "files_with_multiple_sources": len(ambiguous), "files_without_source": sorted(k for k, v in sources.items() if not v)}


def data_dir_report(env: Env, eff: dict, hash_files: bool = True, identify_variants: bool = True,
                    max_files: Optional[int] = None) -> list[dict]:
    variants = load_catalogs(env) if identify_variants else {}
    out = []
    for d in eff["data_dirs"]:
        entry = {"path": d["path"], "name": Path(d["path"]).name, "exists": d["exists"], "source": d["source"]}
        if d["exists"] and hash_files:
            m = dir_manifest(env, Path(d["host_path"]), max_files)
            entry.update({"file_count": m["file_count"], "bytes": m["bytes"], "fingerprint": m["fingerprint"],
                          "truncated": m["truncated"]})
            if m["case_collisions"]:
                entry["case_collisions"] = m["case_collisions"]
                eff.setdefault("warnings", []).append(
                    f"{d['path']}: {len(m['case_collisions'])} ścieżek różni się tylko wielkością liter — "
                    "niejednoznaczne w VFS OpenMW")
            meta = Path(d["host_path"]) / "meta.ini"
            if meta.is_file():
                entry["meta_ini"] = _meta_ini(meta)
            if variants:
                ident = identify(m["files"], variants)
                if ident["match"] and ident["match"]["matching"] > 0:
                    entry["variant"] = ident
            entry["_files"] = m["files"]
        out.append(entry)
    return out


def _meta_ini(path: Path) -> dict:
    keep = ("modid", "version", "installationfile", "fileid", "nexusname", "installed", "latestversion")
    res = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k.strip().lower() in keep:
                res[k.strip().lower()] = v.strip()
    return res


def name_conflicts(dirs: list[dict]) -> list[dict]:
    """Katalogi o tej samej nazwie w jednym profilu (różne ścieżki) — z porównaniem zawartości."""
    by = {}
    for d in dirs:
        by.setdefault(d["name"].lower(), []).append(d)
    out = []
    for name, ds in by.items():
        if len(ds) > 1:
            fps = {d.get("fingerprint") for d in ds}
            out.append({"name": ds[0]["name"], "paths": [d["path"] for d in ds],
                        "same_content": len(fps) == 1 and None not in fps})
    return out


def overrides(vfs: dict, prefix: str = "", limit: int = 200, only_differing: bool = True, env: Optional[Env] = None) -> dict:
    """Ścieżki dostarczane przez >1 warstwę: kto wygrywa (ostatni) i czy bajty się różnią."""
    rows = []
    total = 0
    for key, prov in vfs["index"].items():
        if len(prov) < 2 or (prefix and not key.startswith(vfs_key(prefix))):
            continue
        shas = None
        if env is not None and all(p["file"] for p in prov):
            shas = [env.cache.sha256(Path(p["file"])) for p in prov]
            if only_differing and len(set(shas)) == 1:
                continue
        total += 1
        if len(rows) < limit:
            rows.append({"path": key, "winner": prov[-1]["root"], "providers": [p["root"] for p in prov],
                         "identical_bytes": None if shas is None else len(set(shas)) == 1})
    if env is not None:
        env.cache.save()
    return {"count": total, "shown": len(rows), "rows": rows}
