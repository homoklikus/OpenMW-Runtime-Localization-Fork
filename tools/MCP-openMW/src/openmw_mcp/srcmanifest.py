"""Wersja kodu MCP-openMW: manifest SHA-256 plików źródłowych i hash całego drzewa (uzupełnia commit Git).

    python -m openmw_mcp.srcmanifest            # wypisuje hash, nic nie zapisuje
    python -m openmw_mcp.srcmanifest --write    # zapisuje SOURCE-MANIFEST.sha256 w katalogu MCP-openMW
    python -m openmw_mcp.srcmanifest --check    # porównuje bieżące pliki z SOURCE-MANIFEST.sha256

Hash drzewa = SHA-256 z tekstu manifestu (posortowane linie '<sha256>  <ścieżka>'), więc można go
odtworzyć poleceniem: sha256sum SOURCE-MANIFEST.sha256
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

from . import __version__

ROOT = Path(__file__).resolve().parents[2]
INCLUDE = ("src/openmw_mcp/*.py", "tests/*.py", "scripts/*.py", "scripts/*.sh", "pyproject.toml", "openmw-mcp.json", "catalog/*.sha256",
           "claude/*", "README.md", ".gitignore")
MANIFEST = "SOURCE-MANIFEST.sha256"


def manifest_text(root: Path = ROOT) -> str:
    files = sorted({p for pat in INCLUDE for p in root.glob(pat) if p.is_file()})
    lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root).as_posix()}" for p in files]
    return "\n".join(lines) + "\n"


def tree_hash(root: Path = ROOT) -> str:
    return hashlib.sha256(manifest_text(root).encode("utf-8")).hexdigest()


def git_state(root: Path = ROOT) -> dict:
    """Commit Git, w którym ostatnio zmieniono katalog MCP, i czy drzewo robocze MCP ma niezacommitowane zmiany."""
    def g(*a):
        r = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *a], capture_output=True, text=True,
                           env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"})
        return r.stdout.strip() if r.returncode == 0 else None
    top = g("rev-parse", "--show-toplevel")
    if not top:
        return {"in_git": False}
    rel = Path(root).resolve().relative_to(Path(top).resolve()).as_posix()
    status = g("status", "--porcelain", "--untracked-files=all", "--", ".")
    return {"in_git": True, "repo": top, "path_in_repo": rel, "head": g("rev-parse", "HEAD"),
            "last_commit_for_mcp": g("log", "-1", "--format=%H", "--", ".") or None,
            "dirty": bool(status), "changed_files": len(status.splitlines()) if status else 0}


def info(root: Path = ROOT) -> dict:
    stored = root / MANIFEST
    current = manifest_text(root)
    return {"version": __version__, "tree_sha256": hashlib.sha256(current.encode()).hexdigest(),
            "matches_stored_manifest": stored.is_file() and stored.read_text(encoding="utf-8") == current,
            "git": git_state(root)}


def main(argv: list[str]) -> int:
    text = manifest_text()
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    if "--write" in argv:
        (ROOT / MANIFEST).write_text(text, encoding="utf-8")
        print(f"zapisano {ROOT / MANIFEST}")
    if "--check" in argv:
        stored = ROOT / MANIFEST
        if not stored.is_file():
            print("brak SOURCE-MANIFEST.sha256"); return 2
        if stored.read_text(encoding="utf-8") != text:
            print("RÓŻNICA względem SOURCE-MANIFEST.sha256"); return 1
        print("zgodne z SOURCE-MANIFEST.sha256")
    print(f"openmw-mcp {__version__} tree_sha256={h}")
    gs = git_state()
    if gs.get("in_git"):
        print(f"git: {gs['path_in_repo']} ostatni commit MCP={gs['last_commit_for_mcp'] or '(brak — nie zacommitowano)'} "
              f"zmiany_robocze={'tak' if gs['dirty'] else 'nie'}")
    else:
        print("git: katalog MCP poza repozytorium")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
