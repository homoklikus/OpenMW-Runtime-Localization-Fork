"""Konfiguracja MCP, wykrywanie instalacji (fork natywny, oficjalny Flatpak), Git, binaria, eksperymenty."""

from __future__ import annotations

import json
import mmap
import os
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from .util import CmdResult, HashCache, Runner, map_path, run_command

PACKAGE_ROOT = Path(__file__).resolve().parents[2]          # .../Fork/repo/tools/MCP-openMW (lub MCP-openMW)
DEFAULT_CONFIG = PACKAGE_ROOT / "openmw-mcp.json"


@dataclass
class Env:
    config_path: Path
    project_root: Path
    cfg: dict
    runner: Runner = field(default=run_command)
    cache: HashCache = field(default_factory=lambda: HashCache(None))

    def p(self, rel: str | None) -> Optional[Path]:
        if rel is None:
            return None
        if rel.startswith("@mcp/"):                   # plik należący do samego MCP (np. katalog sum)
            return self.config_path.parent / rel[5:]
        rel = os.path.expanduser(rel)
        path = Path(rel)
        if not path.is_absolute():
            path = self.project_root / path
        return map_path(path)

    def rel(self, path: Path) -> str:
        try:
            return str(Path(path).relative_to(self.project_root))
        except ValueError:
            return str(path)

    def target(self, name: str) -> dict:
        t = self.cfg.get("targets", {}).get(name)
        if t is None:
            raise KeyError(f"nieznany cel '{name}'; dostępne: {sorted(self.cfg.get('targets', {}))}")
        return t


def load_env(config_path: Optional[str | Path] = None, runner: Optional[Runner] = None,
             use_cache: bool = True) -> Env:
    path = Path(config_path or os.environ.get("OPENMW_MCP_CONFIG") or DEFAULT_CONFIG)
    if not path.is_file():
        raise FileNotFoundError(f"brak pliku konfiguracji MCP: {path}")
    cfg = json.loads(path.read_text(encoding="utf-8"))
    root = _project_root(path, cfg.get("project_root", "auto"))
    root = map_path(root)
    cache = HashCache(None)
    if use_cache and os.environ.get("OPENMW_MCP_CACHE", "on") != "off":
        cache = HashCache(path.parent / ".cache" / "sha256.json")
    return Env(path, root, cfg, runner or run_command, cache)


def _is_project(d: Path) -> bool:
    return (d / "Fork").is_dir() and (d / "OpenMW").is_dir()


def _project_root(config_path: Path, spec: str) -> Path:
    """Katalog projektu OpenMW RLF. 'auto': pierwszy przodek pliku konfiguracji zawierający Fork/ i OpenMW/ —
    najpierw po ścieżce takiej, jak ją podano (dowiązanie MCP-openMW → Fork/repo/tools/MCP-openMW),
    potem po ścieżce rzeczywistej. OPENMW_MCP_PROJECT_ROOT ma pierwszeństwo."""
    env_root = os.environ.get("OPENMW_MCP_PROJECT_ROOT")
    if env_root:
        return Path(env_root)
    if spec != "auto":
        root = Path(spec)
        return root if root.is_absolute() else (config_path.parent / root).resolve()
    for start in (Path(os.path.abspath(config_path)).parent, config_path.resolve().parent):
        for d in (start, *start.parents):
            if _is_project(d):
                return d
    raise FileNotFoundError(f"nie znaleziono katalogu projektu (Fork/ + OpenMW/) nad {config_path}; "
                            "ustaw project_root w openmw-mcp.json albo OPENMW_MCP_PROJECT_ROOT")


# --- Git ---------------------------------------------------------------------

def _git(env: Env, repo: Path, *args: str) -> CmdResult:
    return env.runner(["git", "--no-optional-locks", "-C", str(repo), *args], None)


def git_info(env: Env, repo: Path) -> dict:
    if not (repo / ".git").exists():
        return {"path": str(repo), "status": "missing", "error": "brak repozytorium Git"}
    r = _git(env, repo, "rev-parse", "HEAD")
    if r.rc != 0:
        return {"path": str(repo), "status": "error", "error": (r.err or r.out).strip()}
    info = {"path": str(repo), "status": "ok", "head": r.out.strip()}
    br = _git(env, repo, "rev-parse", "--abbrev-ref", "HEAD").out.strip()
    info["branch"] = None if br == "HEAD" else br
    info["detached"] = br == "HEAD"
    tag = _git(env, repo, "describe", "--tags", "--exact-match", "HEAD")
    info["tag"] = tag.out.strip() if tag.rc == 0 else None
    st = _git(env, repo, "status", "--porcelain", "--untracked-files=normal")
    lines = [l for l in st.out.splitlines() if l.strip()]
    info["tracked_changes"] = [l[3:] for l in lines if not l.startswith("??")]
    info["untracked"] = [l[3:] for l in lines if l.startswith("??")]
    up = _git(env, repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    if up.rc == 0:
        info["upstream"] = up.out.strip()
        info["upstream_head"] = _git(env, repo, "rev-parse", "@{u}").out.strip()
        cnt = _git(env, repo, "rev-list", "--left-right", "--count", "HEAD...@{u}").out.split()
        if len(cnt) == 2:
            info["ahead"], info["behind"] = int(cnt[0]), int(cnt[1])
        info["note"] = "ahead/behind wg lokalnych refów (bez fetch)"
    remotes = {}
    for line in _git(env, repo, "remote", "-v").out.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            remotes.setdefault(parts[0], {})[parts[2].strip("()")] = parts[1]
    info["remotes"] = remotes
    return info


def git_changed_paths(env: Env, repo: Path, a: str, b: str) -> Optional[list[str]]:
    r = _git(env, repo, "diff", "--name-only", f"{a}..{b}")
    return None if r.rc != 0 else [l for l in r.out.splitlines() if l]


NON_CODE_PREFIXES = ("Raporty/", "docs/", ".github/", "CI/", "README", "CHANGELOG", "AUTHORS")


def classify_paths(paths: list[str]) -> dict:
    code = [p for p in paths if not (p.startswith(NON_CODE_PREFIXES) or p.lower().endswith((".md", ".png", ".txt")))]
    return {"total": len(paths), "code": code, "non_code": len(paths) - len(code)}


# --- binaria -------------------------------------------------------------------

def elf_build_id(path: Path) -> Optional[str]:
    try:
        with open(path, "rb") as f:
            ident = f.read(64)
            if ident[:4] != b"\x7fELF" or ident[4] != 2:
                return None
            endian = "<" if ident[5] == 1 else ">"
            phoff = struct.unpack_from(endian + "Q", ident, 32)[0]
            phentsize, phnum = struct.unpack_from(endian + "HH", ident, 54)
            for i in range(phnum):
                f.seek(phoff + i * phentsize)
                ph = f.read(phentsize)
                ptype = struct.unpack_from(endian + "I", ph, 0)[0]
                if ptype != 4:  # PT_NOTE
                    continue
                offset, _, _, filesz = struct.unpack_from(endian + "QQQQ", ph, 8)
                f.seek(offset)
                notes = f.read(filesz)
                o = 0
                while o + 12 <= len(notes):
                    namesz, descsz, ntype = struct.unpack_from(endian + "III", notes, o)
                    name = notes[o + 12:o + 12 + namesz]
                    dstart = o + 12 + ((namesz + 3) & ~3)
                    if ntype == 3 and name.rstrip(b"\0") == b"GNU":
                        return notes[dstart:dstart + descsz].hex()
                    o = dstart + ((descsz + 3) & ~3)
    except OSError:
        return None
    return None


def binary_markers(path: Path, markers: dict[str, str]) -> dict[str, bool]:
    res = {}
    try:
        with open(path, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
            for name, text in markers.items():
                res[name] = m.find(text.encode("utf-8")) != -1
    except (OSError, ValueError):
        return {k: None for k in markers}
    return res


def binary_info(env: Env, path: Path, markers: dict[str, str] | None = None, hash_binary: bool = True) -> dict:
    if not path.is_file():
        return {"path": str(path), "status": "missing"}
    st = path.stat()
    info = {"path": str(path), "status": "ok", "size": st.st_size, "mtime_ns": st.st_mtime_ns,
            "elf_build_id": elf_build_id(path)}
    if hash_binary:
        info["sha256"] = env.cache.sha256(path)
    if markers:
        info["markers"] = binary_markers(path, markers)
    return info


def read_version_file(path: Path) -> Optional[dict]:
    if not path.is_file():
        return None
    lines = [l.strip() for l in path.read_text(encoding="utf-8", errors="replace").splitlines()]
    return {"path": str(path), "version": lines[0] if lines else None,
            "commit": lines[1] if len(lines) > 1 and lines[1] else None,
            "tag_commit": lines[2] if len(lines) > 2 and lines[2] else None}


def cmake_cache(path: Path) -> Optional[dict]:
    f = path / "CMakeCache.txt"
    if not f.is_file():
        return None
    keys = {"CMAKE_HOME_DIRECTORY", "CMAKE_CACHEFILE_DIR", "CMAKE_INSTALL_PREFIX", "CMAKE_BUILD_TYPE",
            "CMAKE_GENERATOR", "CMAKE_CXX_COMPILER"}
    out = {}
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^([A-Za-z0-9_]+):[A-Z]+=(.*)$", line)
        if m and m.group(1) in keys:
            out[m.group(1)] = m.group(2)
    return out


# --- eksperymenty ---------------------------------------------------------------

def experiments_status(env: Env, repo: Path, binary: Optional[Path]) -> list[dict]:
    res = []
    for name, ex in env.cfg.get("experiments", {}).items():
        d = env.p(ex.get("dir"))
        item = {"name": name, "dir": str(d), "present": bool(d and d.is_dir()), "committed": False}
        mod_file = ex.get("modified_file")
        result_file = ex.get("result_file")
        if mod_file and (repo / mod_file).is_file():
            wt = env.cache.sha256(repo / mod_file)
            item["working_tree_sha256"] = wt
            if d and result_file and (d / result_file).is_file():
                item["result_sha256"] = env.cache.sha256(d / result_file)
                item["applied_in_working_tree"] = wt == item["result_sha256"]
            r = _git(env, repo, "diff", "--quiet", "HEAD", "--", mod_file)
            item["working_tree_modified"] = r.rc == 1
        marker = ex.get("binary_marker")
        if marker and binary and binary.is_file():
            item["compiled_into_binary"] = binary_markers(binary, {"m": marker})["m"]
        state = "nieobecny w repo i binarce"
        if item.get("applied_in_working_tree") or item.get("working_tree_modified"):
            state = "ZASTOSOWANY w drzewie roboczym (niezatwierdzony)"
        if item.get("compiled_into_binary"):
            state += "; WKOMPILOWANY w binarkę"
        item["state"] = state
        res.append(item)
    return res


# --- instalacje -----------------------------------------------------------------

def detect_fork(env: Env, hash_binary: bool = True) -> dict:
    t = env.target("fork")
    repo, binary = env.p(t["repo"]), env.p(t["binary"])
    out = {"target": "fork", "kind": "native", "issues": []}
    out["repo"] = git_info(env, repo)
    out["binary"] = binary_info(env, binary, t.get("binary_markers"), hash_binary)
    out["version_file"] = read_version_file(env.p(t["version_file"])) if t.get("version_file") else None
    out["build"] = cmake_cache(env.p(t["build_dir"])) if t.get("build_dir") else None
    out["experiments"] = experiments_status(env, repo, binary)
    if out["repo"].get("status") != "ok":
        out["issues"].append("repozytorium forka niedostępne")
    if out["binary"]["status"] != "ok":
        out["issues"].append(f"brak binarki forka: {binary}")
    vf = out["version_file"]
    head = out["repo"].get("head")
    if vf and vf.get("commit") and head:
        out["binary_commit"] = vf["commit"]
        if vf["commit"] != head:
            changed = git_changed_paths(env, repo, vf["commit"], head)
            out["binary_vs_head"] = classify_paths(changed) if changed is not None else {"error": "nie można porównać"}
            if changed is None or out["binary_vs_head"]["code"]:
                out["issues"].append(f"binarka zbudowana z {vf['commit'][:10]}, HEAD {head[:10]} — różnice w kodzie")
    elif out["binary"]["status"] == "ok":
        out["issues"].append("brak resources/version — nie można ustalić commita binarki")
    if out["build"] and repo and out["build"].get("CMAKE_HOME_DIRECTORY"):
        if map_path(out["build"]["CMAKE_HOME_DIRECTORY"]) != repo:
            out["issues"].append("CMakeCache wskazuje inne źródła niż repo forka")
    out["status"] = "ok" if not out["issues"] else "warning"
    if out["binary"]["status"] != "ok" or out["repo"].get("status") != "ok":
        out["status"] = "missing" if out["binary"]["status"] == "missing" else "error"
    return out


def parse_flatpak_info(text: str) -> dict:
    res = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([A-Za-z][A-Za-z ]*?):\s*(.*)$", line)
        if m:
            res[m.group(1).strip().lower()] = m.group(2).strip()
    return res


def flatpak_location(env: Env, app_id: str) -> tuple[Optional[Path], Optional[str]]:
    r = env.runner(["flatpak", "info", "--show-location", app_id], None)
    if r.rc == 127:
        return None, "polecenie 'flatpak' nie jest dostępne"
    if r.rc != 0 or not r.out.strip():
        return None, f"'flatpak info --show-location {app_id}' nie powiodło się: {(r.err or r.out).strip()}"
    return map_path(r.out.strip()), None


def detect_official(env: Env, hash_binary: bool = True) -> dict:
    t = env.target("official")
    app = t["app_id"]
    out = {"target": "official", "kind": "flatpak", "app_id": app, "issues": []}
    out["repo"] = git_info(env, env.p(t["repo"])) if t.get("repo") else None
    loc, err = flatpak_location(env, app)
    if err:
        out["status"] = "missing"
        out["issues"].append(err)
        return out
    out["location"] = str(loc)
    if not (loc / "files").is_dir():
        out["status"] = "error"
        out["issues"].append(f"nieprawidłowa lokalizacja wdrożenia: {loc}")
        return out
    info = env.runner(["flatpak", "info", app], None)
    fields = parse_flatpak_info(info.out) if info.rc == 0 else {}
    if info.rc != 0:
        out["issues"].append(f"'flatpak info {app}' nie powiodło się: {(info.err or info.out).strip()}")
    commit = env.runner(["flatpak", "info", "--show-commit", app], None)
    out["flatpak"] = {k: fields.get(k) for k in ("ref", "arch", "branch", "origin", "installation", "runtime")}
    out["flatpak"]["package_commit"] = commit.out.strip() if commit.rc == 0 else fields.get("commit")
    version = fields.get("version")
    meta = loc / "files" / "share" / "metainfo" / f"{app}.metainfo.xml"
    meta_ver = None
    if meta.is_file():
        m = re.search(r'<release [^>]*version="([^"]+)"', meta.read_text(encoding="utf-8", errors="replace"))
        meta_ver = m.group(1) if m else None
    out["version"] = version or meta_ver
    out["version_sources"] = {"flatpak_info": version, "metainfo": meta_ver}
    if not out["version"]:
        out["issues"].append("nie ustalono wersji (brak 'Version:' i <release version>)")
    elif version and meta_ver and version != meta_ver:
        out["issues"].append(f"niespójna wersja: flatpak info={version}, metainfo={meta_ver}")
    src_commit = None
    manifest = loc / "files" / "manifest.json"
    if manifest.is_file():
        try:
            mf = json.loads(manifest.read_text(encoding="utf-8"))
            for mod in mf.get("modules", []):
                if isinstance(mod, dict) and mod.get("name") == "openmw":
                    for s in mod.get("sources", []):
                        if isinstance(s, dict) and s.get("commit"):
                            src_commit = s["commit"]
        except ValueError:
            out["issues"].append("manifest.json uszkodzony")
    else:
        out["issues"].append("brak files/manifest.json — commit źródeł nieznany")
    out["source_commit"] = src_commit
    out["version_file"] = read_version_file(loc / "files" / "share" / "games" / "openmw" / "resources" / "version")
    out["binary"] = binary_info(env, loc / "files" / "bin" / "openmw", None, hash_binary)
    exp_v, exp_c = t.get("expected_version"), t.get("expected_source_commit")
    if exp_v and out["version"] and out["version"] != exp_v:
        out["issues"].append(f"oczekiwano wersji {exp_v}, wykryto {out['version']}")
    if exp_c and src_commit and src_commit != exp_c:
        out["issues"].append(f"Flatpak zbudowany ze źródeł {src_commit}, oczekiwano {exp_c}")
    repo = out.get("repo") or {}
    if src_commit and repo.get("head") and repo["head"] != src_commit:
        out["issues"].append(f"OpenMW/repo HEAD {repo['head'][:10]} ≠ źródła Flatpaka {src_commit[:10]}")
    out["status"] = "ok" if not out["issues"] else "warning"
    return out
