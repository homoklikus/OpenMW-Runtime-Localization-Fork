"""Fikstury: syntetyczny projekt OpenMW RLF (fork + oficjalny Flatpak) bez prawdziwych zasobów gry."""

from __future__ import annotations

import json
import struct
import subprocess
from pathlib import Path

import pytest

from openmw_mcp import environment
from openmw_mcp.bsa import build_tes3_bsa
from openmw_mcp.util import CmdResult, run_command

REAL_CONFIG = Path(__file__).resolve().parents[1] / "openmw-mcp.json"
SRC_COMMIT = "f4bec41444214a7903bebd178389ca22ca13f646"
PKG_COMMIT = "18f04802c908d2ade02eaeafbdff49a5de95561665db45c9fa5600f8a2b886ad"


# --- budowanie plików binarnych -------------------------------------------------

def fake_elf(build_id: bytes, extra: bytes = b"") -> bytes:
    name = b"GNU\0"
    note = struct.pack("<III", 4, len(build_id), 3) + name + build_id
    ehdr_size, ph_size = 64, 56
    note_off = ehdr_size + ph_size
    ehdr = b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\0" * 8
    ehdr += struct.pack("<HHIQQQIHHHHHH", 2, 62, 1, 0, ehdr_size, 0, 0, ehdr_size, ph_size, 1, 0, 0, 0)
    ph = struct.pack("<IIQQQQQQ", 4, 4, note_off, 0, 0, len(note), len(note), 4)
    return ehdr + ph + note + extra


def rec(rtype: str, subs: list[tuple[str, bytes]]) -> bytes:
    payload = b"".join(t.encode() + struct.pack("<I", len(d)) + d for t, d in subs)
    return rtype.encode() + struct.pack("<III", len(payload), 0, 0) + payload


def esp_bytes(masters=(), statics=(), cells=(), interiors=()) -> bytes:
    hedr = struct.pack("<fI", 1.3, 0) + b"author".ljust(32, b"\0") + b"desc".ljust(256, b"\0") + struct.pack("<I", 0)
    subs = [("HEDR", hedr)]
    for m in masters:
        subs += [("MAST", m.encode() + b"\0"), ("DATA", struct.pack("<Q", 0))]
    out = rec("TES3", subs)
    for sid, model in statics:
        out += rec("STAT", [("NAME", sid.encode() + b"\0"), ("MODL", model.encode() + b"\0")])
    for (x, y), refs in cells:
        s = [("NAME", b"\0"), ("DATA", struct.pack("<Iii", 0, x, y))]
        for i, (rid, px, py) in enumerate(refs):
            s += [("FRMR", struct.pack("<I", i + 1)), ("NAME", rid.encode() + b"\0"),
                  ("DATA", struct.pack("<6f", px, py, 0, 0, 0, 0))]
        out += rec("CELL", s)
    for name in interiors:
        out += rec("CELL", [("NAME", name.encode() + b"\0"), ("DATA", struct.pack("<Iii", 1, 0, 0))])
    return out


def w(path: Path, data: bytes | str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        path.write_text(data, encoding="utf-8")
    else:
        path.write_bytes(data)
    return path


def git(repo: Path, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True,
                   env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                        "GIT_COMMITTER_EMAIL": "t@t", "PATH": "/usr/bin:/bin", "HOME": str(repo)})


# --- warianty moda (syntetyczne „Remiros”) ---------------------------------------

CORE = {"rem_ac.esp": b"ESP-AC", "meshes/grass/rem_ac_grass_01.nif": b"core-ac01",
        "meshes/grass/rem_ac_grass_03.nif": b"core-ac03-mushroom", "meshes/grass/rem_ai_grass_01b.nif": b"core-ai01b",
        "textures/rem/grass/tx_ac_grass_01.dds": b"tex-ac01"}
THICK = {"meshes/grass/rem_ac_grass_03.nif": b"thick-ac03"}
NOMUSH = {"meshes/grass/rem_ac_grass_03.nif": b"nomush-ac03", "meshes/grass/rem_ai_grass_01b.nif": b"nomush-ai01b"}
MGE = {**CORE, "meshes/grass/rem_ac_grass_01.nif": b"mge-ac01"}


def write_variant(root: Path, files: dict[str, bytes]):
    for rel, data in files.items():
        w(root / rel, data)


def catalog_text(variants: dict[str, dict[str, bytes]]) -> str:
    import hashlib
    lines = []
    for var, files in variants.items():
        for rel, data in sorted(files.items()):
            lines.append(f"{hashlib.sha256(data).hexdigest()}  ./{var}/{rel}")
    return "\n".join(lines) + "\n"


class FakeFlatpak:
    def __init__(self, location: Path):
        self.location = location
        self.mode = "ok"
        self.version = "0.51.0"
        self.calls: list[list[str]] = []

    def __call__(self, cmd, env_extra=None):
        self.calls.append(cmd)
        if cmd[0] != "flatpak":
            return run_command(cmd, env_extra)
        if self.mode == "missing":
            return CmdResult(127, "", "nie znaleziono polecenia: flatpak")
        if cmd[1] == "run":
            raise AssertionError("MCP etapu 1 nie może uruchamiać flatpak run")
        if self.mode == "notinstalled":
            return CmdResult(1, "", f"error: {cmd[-1]} not installed")
        if "--show-location" in cmd:
            return CmdResult(0, str(self.location) + "\n", "")
        if "--show-commit" in cmd:
            return CmdResult(0, PKG_COMMIT + "\n", "")
        if self.mode == "noversion":
            return CmdResult(0, "          ID: org.openmw.OpenMW\n", "")
        return CmdResult(0, f"\nOpenMW\n\n          ID: org.openmw.OpenMW\n         Ref: app/org.openmw.OpenMW/x86_64/stable\n"
                            f"     Version: {self.version}\n      Branch: stable\n      Commit: {PKG_COMMIT}\n", "")


@pytest.fixture
def project(tmp_path, monkeypatch):
    root = tmp_path / "OpenMW RLF"          # spacja w ścieżce — celowo
    monkeypatch.setenv("OPENMW_MCP_CACHE", "off")
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    # --- fork: repo
    repo = root / "Fork/repo"
    w(repo / "apps/openmw/mwrender/groundcover.cpp", "// base\n")
    w(repo / "files/settings-default.cfg", "[Groundcover]\nenabled = false\ndensity = 1.0\nrendering distance = 6144.0\n"
                                           "[Camera]\nviewing distance = 7168.0\n[General]\npreferred locales = en\n")
    git(repo, "init", "-q", "-b", "0.5-world"); git(repo, "add", "-A"); git(repo, "commit", "-q", "-m", "base")
    head = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    # --- fork: install
    inst = root / "Fork/install"
    w(inst / "bin/openmw", fake_elf(b"\x12\x34\x56\x78" * 5, b"Runtime localization: native loading complete\0World flora renderer\0"))
    res = inst / "share/games/openmw/resources"
    w(res / "version", f"0.51.0\n{head}\n\n")
    w(res / "vfs/builtin.omwscripts", "")
    w(res / "vfs-mw/scripts/omw/x.lua", "")
    gog = tmp_path / "GOG/Data Files"
    w(gog / "Morrowind.esm", esp_bytes())
    w(gog / "Morrowind.bsa", build_tes3_bsa({"meshes/f/flora_grass_01.nif": b"bsa-grass", "meshes/grass/rem_ac_grass_01.nif": b"bsa-version"}))
    mods = root / "Fork/mods"
    write_variant(mods / "Remiros", {**CORE, **THICK})
    w(mods / "Tekstury/textures/rem/grass/tx_ac_grass_01.dds", b"tex-override")
    cfgdir = root / "Fork/config/openmw-test"
    w(inst / "bin/openmw.cfg", f'resources="{res}"\ndata="{res}/vfs-mw"\n'
                               f'data-local="{root}/Fork/config/openmw-test-userdata/data"\n'
                               f'user-data="{root}/Fork/config/openmw-test-userdata"\nconfig="{cfgdir}"\n')
    w(inst / "etc/openmw/openmw.cfg", f'resources="{res}"\ndata="{res}/vfs-mw"\nuser-data="?userdata?"\nconfig="?userconfig?"\n')
    (root / "Fork/config/openmw-test-userdata/data").mkdir(parents=True)
    w(cfgdir / "openmw.cfg", f'fallback-archive=Morrowind.bsa\nencoding=win1250\ndata="{gog}"\n'
                             f'data="{mods}/Remiros"\ndata="{mods}/Tekstury"\ncontent=Morrowind.esm\n')
    w(cfgdir / "settings.cfg", "[Groundcover]\nenabled = true\nrendering distance = 4000\n[General]\npreferred locales = pl,en\n")
    w(cfgdir / "world.cfg", "[Flora]\nenabled=true\nsource=automatic\ndensity=1\n")
    w(root / "Fork/scripts/run-flora-test.sh",
      'G="meshes/omwpl/grass"\ncase "${RLF_FLORA_POOL:-all}" in\n'
      '  ac)  POOL="$G/rem_ac_grass_01.nif,$G/rem_ac_grass_03.nif" ;;\n'
      '  *)   POOL="$G/rem_ac_grass_01.nif,\\\n$G/rem_al_grass.nif,$G/rem_al_grass_b.nif,$G/rem_al_rock.nif" ;;\nesac\n')
    for n in ("rem_ac_grass_01", "rem_ac_grass_03", "rem_al_grass", "rem_al_grass_b", "rem_al_rock"):
        w(mods / f"Remiros/meshes/omwpl/grass/{n}.nif", n.encode())
    w(root / "Fork/build/CMakeCache.txt", f"CMAKE_HOME_DIRECTORY:INTERNAL={repo}\nCMAKE_BUILD_TYPE:STRING=RelWithDebInfo\n")
    exp = root / "Fork/experiments/azuras-coast-2026-09-18"
    w(exp / "groundcover.cpp.with-azuras-coast", "// base\n// AC experiment\n")
    # --- oficjalne: repo + Flatpak
    orepo = root / "OpenMW/repo"
    w(orepo / "files/settings-default.cfg", "[Groundcover]\nenabled = false\ndensity = 1.0\nrendering distance = 6144.0\n")
    git(orepo, "init", "-q"); git(orepo, "add", "-A"); git(orepo, "commit", "-q", "-m", "official")
    loc = tmp_path / "flatpak/app/org.openmw.OpenMW/x86_64/stable/active"
    files = loc / "files"
    w(files / "etc/openmw/openmw.cfg", 'data-local="?userdata?data"\nuser-data="?userdata?"\nconfig="?userconfig?"\n'
                                      'resources=/app/share/games/openmw/resources\ndata=/app/share/games/openmw/resources/vfs-mw\n')
    w(files / "share/games/openmw/resources/vfs/builtin.omwscripts", "")
    w(files / "share/games/openmw/resources/vfs-mw/scripts/omw/x.lua", "")
    w(files / "share/games/openmw/resources/version", f"0.51.0\n{SRC_COMMIT}\n{SRC_COMMIT}\n")
    w(files / "bin/openmw", fake_elf(b"\xab" * 20))
    w(files / "manifest.json", json.dumps({"modules": [{"name": "boost", "sources": [{"url": "x"}]},
                                                        {"name": "openmw", "sources": [{"commit": SRC_COMMIT}]}]}))
    w(files / "share/metainfo/org.openmw.OpenMW.metainfo.xml", '<component><releases><release version="0.51.0" date="2026-05-27"/></releases></component>')
    ref = root / "OpenMW/config/openmw-ref"
    omods = root / "OpenMW/mods/Remiros Groundcover 4.1"
    write_variant(omods / "00 Core OpenMW", CORE)
    write_variant(omods / "01b Thicker Grass OpenMW", THICK)
    w(omods / "00 Core OpenMW/Rem_AC.esp", esp_bytes(statics=[("grs_ac_0", "grass\\rem_ac_grass_01.nif")],
                                                     cells=[((15, -9), [("grs_ac_0", 15 * 8192 + 10, -9 * 8192 + 10),
                                                                        ("grs_ac_0", 16 * 8192 + 5, -9 * 8192 + 5)])]))
    w(ref / "openmw.cfg", f'encoding=win1252\ndata="{gog}"\ndata="{omods}/00 Core OpenMW"\n'
                          f'data="{omods}/01b Thicker Grass OpenMW"\nfallback-archive=Morrowind.bsa\n'
                          f'content=Morrowind.esm\ngroundcover=Rem_AC.esp\n')
    w(ref / "settings.cfg", "[Groundcover]\nenabled = true\nrendering distance = 4000\n")
    (root / "OpenMW/config/openmw-ref-userdata/data").mkdir(parents=True)
    # --- konfiguracja MCP + katalog wariantów
    mcpdir = root / "MCP-openMW"
    w(mcpdir / "catalog/remiros-4.1.sha256", catalog_text({"00 Core OpenMW": CORE, "01b Thicker Grass OpenMW": THICK,
                                                            "01a No Mushrooms OpenMW": NOMUSH, "00 Core MGE XE": MGE}))
    cfg = json.loads(REAL_CONFIG.read_text(encoding="utf-8"))
    w(mcpdir / "openmw-mcp.json", json.dumps(cfg))
    fake = FakeFlatpak(loc)
    e = environment.load_env(mcpdir / "openmw-mcp.json", runner=fake, use_cache=False)
    return {"root": root, "env": e, "flatpak": fake, "head": head, "repo": repo, "gog": gog, "mods": mods,
            "omods": omods, "cfgdir": cfgdir, "ref": ref, "inst": inst, "loc": loc}
