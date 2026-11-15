"""Testy etapu 1 MCP-openMW (tylko odczyt)."""

from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

from openmw_mcp import cfgparse, environment, esp, flora, manifest, mods, profiles
from openmw_mcp.bsa import BsaError, build_tes3_bsa, list_tes3_bsa
from openmw_mcp.util import map_path, vfs_key

from conftest import SRC_COMMIT, PKG_COMMIT, CORE, THICK, NOMUSH, esp_bytes, w


# --- parsery ---------------------------------------------------------------------

def test_cfg_quotes_escapes_comments():
    c = cfgparse.parse_openmw_cfg('# k\ndata="/a b/&"x&&y"\ncontent=Morrowind.esm\nbroken line\n')
    assert c.values("data") == ['/a b/"x&y']
    assert c.values("content") == ["Morrowind.esm"]
    assert c.errors and "bez '='" in c.errors[0]


def test_world_cfg_semantics_and_clamp():
    wc = cfgparse.parse_world_cfg("[Flora]\nenabled=yes\nsource=HYBRID\ndensity=5\nexclusion_distance=-3\n[World]\nversion=0\n")
    assert wc["flora"] == {"enabled": True, "source": "hybrid", "density": 2.0, "exclusion_distance": 0.0}
    assert wc["version"] == 1
    assert cfgparse.parse_world_cfg("[Flora]\nsource=weird\n")["warnings"]
    assert cfgparse.parse_world_cfg(None)["present"] is False


def test_bsa_roundtrip_and_error(tmp_path):
    p = w(tmp_path / "a.bsa", build_tes3_bsa({"Meshes\\F\\X.nif": b"1", "textures/y.dds": b"22"}))
    assert sorted(list_tes3_bsa(p)) == ["meshes/f/x.nif", "textures/y.dds"]
    bad = w(tmp_path / "b.bsa", b"\x00\x02\x00\x00" + b"\0" * 20)
    with pytest.raises(BsaError):
        list_tes3_bsa(bad)


def test_hash_cache_racy_same_size_rewrite(tmp_path):
    from openmw_mcp.util import HashCache
    c = HashCache(tmp_path / "c.json")
    f = w(tmp_path / "x.bin", b"aaaa")
    h1 = c.sha256(f)
    f.write_bytes(b"bbbb")                      # ten sam rozmiar, natychmiast
    assert c.sha256(f) != h1
    old = 1_000_000_000_000_000_000
    os.utime(f, ns=(old, old))
    h2 = c.sha256(f); c.save()
    assert HashCache(tmp_path / "c.json").sha256(f) == h2


def test_path_map(monkeypatch):
    monkeypatch.setenv("OPENMW_MCP_PATH_MAP", "/media/x=/mnt/x;/media/x/sub=/other")
    assert map_path("/media/x/a b/c") == Path("/mnt/x/a b/c")
    assert map_path("/media/x/sub/f") == Path("/other/f")
    assert map_path("/elsewhere") == Path("/elsewhere")


# --- instalacje --------------------------------------------------------------------

def test_detect_fork_ok(project):
    d = environment.detect_fork(project["env"])
    assert d["status"] == "ok", d["issues"]
    assert d["binary_commit"] == project["head"]
    assert d["binary"]["elf_build_id"] == "12345678" * 5
    assert d["binary"]["markers"] == {"runtime_localization": True, "world_flora_renderer": True,
                                      "experiment_azuras_coast": False}
    assert d["repo"]["branch"] == "0.5-world"
    assert d["experiments"][0]["state"] == "nieobecny w repo i binarce"


def test_detect_fork_missing_binary(project):
    (project["inst"] / "bin/openmw").unlink()
    d = environment.detect_fork(project["env"])
    assert d["status"] == "missing"
    assert any("brak binarki" in i for i in d["issues"])


def test_detect_fork_binary_older_than_head_docs_only_vs_code(project):
    repo = project["repo"]
    from conftest import git
    w(repo / "Raporty/x.md", "doc"); git(repo, "add", "-A"); git(repo, "commit", "-q", "-m", "docs")
    d = environment.detect_fork(project["env"])
    assert d["binary_vs_head"]["code"] == [] and d["status"] == "ok"
    w(repo / "apps/new.cpp", "x"); git(repo, "add", "-A"); git(repo, "commit", "-q", "-m", "code")
    d = environment.detect_fork(project["env"])
    assert d["binary_vs_head"]["code"] == ["apps/new.cpp"]
    assert any("różnice w kodzie" in i for i in d["issues"])


def test_experiment_detection(project):
    gc = project["repo"] / "apps/openmw/mwrender/groundcover.cpp"
    gc.write_text("// base\n// AC experiment\n")
    d = environment.detect_fork(project["env"])
    assert "ZASTOSOWANY" in d["experiments"][0]["state"]
    b = project["inst"] / "bin/openmw"
    b.write_bytes(b.read_bytes() + b"Rem_AC diagnostic: cell=(15,-9)")
    d = environment.detect_fork(project["env"])
    assert "WKOMPILOWANY" in d["experiments"][0]["state"]


def test_detect_official_ok_distinguishes_commits(project):
    d = environment.detect_official(project["env"])
    # syntetyczne OpenMW/repo nie jest na f4bec414 — jedyny (poprawnie wykryty) problem
    assert len(d["issues"]) == 1 and "≠ źródła Flatpaka" in d["issues"][0]
    assert d["version"] == "0.51.0"
    assert d["source_commit"] == SRC_COMMIT
    assert d["flatpak"]["package_commit"] == PKG_COMMIT
    assert d["source_commit"] != d["flatpak"]["package_commit"]
    assert not any(c[:2] == ["flatpak", "run"] for c in project["flatpak"].calls)


def test_official_flatpak_missing(project):
    project["flatpak"].mode = "missing"
    d = environment.detect_official(project["env"])
    assert d["status"] == "missing" and "nie jest dostępne" in d["issues"][0]


def test_official_not_installed(project):
    project["flatpak"].mode = "notinstalled"
    d = environment.detect_official(project["env"])
    assert d["status"] == "missing" and "nie powiodło się" in d["issues"][0]


def test_official_version_fallback_and_mismatch(project):
    fp = project["flatpak"]
    fp.mode = "noversion"
    d = environment.detect_official(project["env"])
    assert d["version"] == "0.51.0" and d["version_sources"]["flatpak_info"] is None
    fp.mode, fp.version = "ok", "0.52.0"
    d = environment.detect_official(project["env"])
    assert any("niespójna wersja" in i for i in d["issues"])
    assert any("oczekiwano wersji 0.51.0" in i for i in d["issues"])


def test_official_wrong_source_commit(project):
    mf = project["loc"] / "files/manifest.json"
    mf.write_text(mf.read_text().replace(SRC_COMMIT, "0" * 40))
    d = environment.detect_official(project["env"])
    assert any("zbudowany ze źródeł" in i for i in d["issues"])


def test_missing_mcp_config(tmp_path):
    with pytest.raises(FileNotFoundError):
        environment.load_env(tmp_path / "nope.json")


# --- profile ------------------------------------------------------------------------

def test_fork_profile_chain_and_order(project):
    eff = profiles.effective(project["env"], "fork-test")
    assert [Path(d).name for d in eff["active_config_dirs"]] == ["bin", "openmw-test"]
    names = [Path(d["path"]).name for d in eff["data_dirs"]]
    assert names == ["vfs", "vfs-mw", "Data Files", "Remiros", "Tekstury", "data"]
    assert eff["data_dirs"][-1]["source"].startswith("data-local")
    assert eff["encoding"] == "win1250"
    assert eff["content"][0]["file"].endswith("Morrowind.esm")
    assert eff["isolation"]["isolated"] is True
    assert eff["world_cfg"]["flora"]["enabled"] is True
    assert cfgparse.setting(eff["settings"]["merged"], "Groundcover", "rendering distance") == "4000"
    assert cfgparse.setting(eff["settings"]["merged"], "Camera", "viewing distance") == "7168.0"


def test_fork_falls_back_to_global_config_and_breaks_isolation(project):
    (project["inst"] / "bin/openmw.cfg").unlink()
    eff = profiles.effective(project["env"], "fork-test")
    assert eff["active_config_dirs"][0].endswith("etc/openmw")
    assert eff["isolation"]["isolated"] is False   # ?userconfig? = ~/.config/openmw


def test_official_replace_config_isolation(project):
    eff = profiles.effective(project["env"], "official-ref")
    assert eff["active_config_dirs"][0] == "/app/etc/openmw"
    assert eff["active_config_dirs"][1].endswith("OpenMW/config/openmw-ref")
    assert len(eff["active_config_dirs"]) == 2       # ?userconfig? pominięty dzięki --replace=config
    assert eff["isolation"]["isolated"] is True
    assert eff["data_dirs"][-1]["path"].endswith("openmw-ref-userdata/data")
    assert [g["name"] for g in eff["groundcover"]] == ["Rem_AC.esp"]
    assert eff["data_dirs"][0]["host_path"].startswith(str(project["loc"]))


def test_official_without_replace_reads_user_profile(project):
    prof = project["env"].cfg["profiles"]["official-ref"]
    prof["cli"] = {k: v for k, v in prof["cli"].items() if k not in ("replace", "data-local")}
    eff = profiles.effective(project["env"], "official-ref")
    assert any(".var/app/org.openmw.OpenMW/config/openmw" in d for d in eff["active_config_dirs"])
    assert eff["isolation"]["isolated"] is False
    assert any("data-local" in v for v in eff["isolation"]["violations"])


def test_missing_configuration(project):
    (project["inst"] / "bin/openmw.cfg").unlink()
    (project["inst"] / "etc/openmw/openmw.cfg").unlink()
    with pytest.raises(profiles.ProfileError):
        profiles.effective(project["env"], "fork-test")


def test_unknown_profile(project):
    with pytest.raises(profiles.ProfileError):
        profiles.effective(project["env"], "nie-ma")


def test_invalid_paths_reported(project):
    cfg = project["cfgdir"] / "openmw.cfg"
    cfg.write_text(cfg.read_text() + 'data="/nie/istnieje/mod"\ncontent=Brak.esp\nfallback-archive=Brak.bsa\n')
    eff = profiles.effective(project["env"], "fork-test")
    joined = "\n".join(eff["issues"])
    assert "nieistniejący katalog danych" in joined
    assert "content=Brak.esp" in joined
    assert "Brak.bsa" in joined


def test_replace_in_later_config_drops_earlier_data(project):
    cfg = project["cfgdir"] / "openmw.cfg"
    cfg.write_text("replace=data\n" + cfg.read_text())
    eff = profiles.effective(project["env"], "fork-test")
    assert "vfs-mw" not in [Path(d["path"]).name for d in eff["data_dirs"]]


# --- VFS, nadpisywanie, mody ------------------------------------------------------

def test_vfs_override_order_and_bsa_lowest(project):
    eff = profiles.effective(project["env"], "fork-test")
    idx = profiles.vfs_index(eff)
    prov = idx["index"][vfs_key("Textures/Rem/Grass/TX_AC_GRASS_01.dds")]
    assert [Path(p["root"]).name for p in prov] == ["Remiros", "Tekstury"]
    prov = idx["index"]["meshes/grass/rem_ac_grass_01.nif"]
    assert prov[0]["kind"] == "bsa" and Path(prov[-1]["root"]).name == "Remiros"
    ov = mods.overrides(idx, "textures/", env=project["env"])
    assert ov["count"] == 1 and ov["rows"][0]["identical_bytes"] is False


def test_identify_variant_core_plus_thick(project):
    e = project["env"]
    m = mods.dir_manifest(e, project["mods"] / "Remiros", )
    files = {k: v for k, v in m["files"].items() if not k.startswith("meshes/omwpl/")}
    ident = mods.identify(files, mods.load_catalogs(e))
    assert ident["match"]["exact"] is True
    assert [o.split(" :: ")[1] for o in ident["match"]["order"]] == ["00 Core OpenMW", "01b Thicker Grass OpenMW"]


def test_identify_variant_no_mushrooms_and_modified(project, tmp_path):
    e = project["env"]
    d = tmp_path / "nm"
    for rel, data in {**CORE, **NOMUSH}.items():
        w(d / rel, data)
    ident = mods.identify(mods.dir_manifest(e, d)["files"], mods.load_catalogs(e))
    assert [o.split(" :: ")[1] for o in ident["match"]["order"]] == ["00 Core OpenMW", "01a No Mushrooms OpenMW"]
    w(d / "meshes/grass/rem_ac_grass_01.nif", b"zmieniony")
    ident = mods.identify(mods.dir_manifest(e, d)["files"], mods.load_catalogs(e))
    assert ident["match"]["exact"] is False
    assert "meshes/grass/rem_ac_grass_01.nif" in ident["match"]["different"]


def test_plugin_case_ambiguity_is_deterministic_and_reported(project):
    # 00 Core OpenMW zawiera 'Rem_AC.esp' i 'rem_ac.esp' (różne bajty) — OpenMW wybrałby wg kolejności FS
    eff = profiles.effective(project["env"], "official-ref")
    g = eff["groundcover"][0]
    assert Path(g["file"]).name == "Rem_AC.esp"                 # dokładna nazwa z groundcover=
    assert [Path(c).name for c in g["case_ambiguous"][0]["candidates"]] == ["Rem_AC.esp", "rem_ac.esp"]
    assert any("różniące się tylko wielkością liter" in i for i in eff["issues"])


def test_name_conflict_same_name_different_content(project, tmp_path):
    other = tmp_path / "inne/Remiros"
    w(other / "rem_ac.esp", b"inna wersja")
    cfg = project["cfgdir"] / "openmw.cfg"
    cfg.write_text(cfg.read_text() + f'data="{other}"\n')
    eff = profiles.effective(project["env"], "fork-test")
    dd = mods.data_dir_report(project["env"], eff)
    conf = mods.name_conflicts(dd)
    assert conf and conf[0]["name"] == "Remiros" and conf[0]["same_content"] is False


# --- flora ----------------------------------------------------------------------------

def test_fork_flora_modes(project):
    e = project["env"]
    wc = project["cfgdir"] / "world.cfg"
    cases = [("[Flora]\nenabled=true\nsource=automatic\n", False, True),
             ("[Flora]\nenabled=true\nsource=groundcover\n", True, False),
             ("[Flora]\nenabled=true\nsource=hybrid\n", True, True),
             ("[Flora]\nenabled=false\n", True, False)]
    cfg = project["cfgdir"] / "openmw.cfg"
    cfg.write_text(cfg.read_text() + "groundcover=Rem_AC.esp\n")   # plik rem_ac.esp jest w Remiros (VFS bez wielkości liter)
    for text, plugins, procedural in cases:
        wc.write_text(text)
        eff = profiles.effective(e, "fork-test")
        r = flora.classify(eff, "fork", profiles.vfs_index(eff), None)
        assert (r["plugins_rendered"], r["procedural"]) == (plugins, procedural), text
    wc.write_text("[Flora]\nenabled=true\nsource=automatic\n")
    r = flora.classify(profiles.effective(e, "fork-test"), "fork")
    assert any("IGNOROWANE" in n for n in r["notes"])


def test_fork_pool_profiles(project):
    e = project["env"]
    eff = profiles.effective(e, "fork-test")
    vfs = profiles.vfs_index(eff)
    pool, src = manifest.pool_for(e, "fork-test", None)
    r = flora.classify(eff, "fork", vfs, pool, src)
    pp = r["procedural_profile"]
    assert pp["active_profiles"] == ["AL"]
    assert pp["pool_models_unused_by_active_profiles"] == ["meshes/omwpl/grass/rem_ac_grass_01.nif"]
    pool, src = manifest.pool_for(e, "fork-test", "ac")
    pp = flora.classify(eff, "fork", vfs, pool, src)["procedural_profile"]
    assert pp["active_profiles"] == [] and pp["mode"].startswith("ogólny")
    pool, src = manifest.pool_for(e, "fork-test", "list:meshes/brak/x.nif")
    r = flora.classify(eff, "fork", vfs, pool, src)
    assert r["procedural_profile"]["pool_missing_in_vfs"] == ["meshes/brak/x.nif"]
    assert any("puli vanilla" in n for n in r["notes"])


def test_official_flora_and_stats(project):
    e = project["env"]
    eff = profiles.effective(e, "official-ref")
    r = flora.classify(eff, "official")
    assert r["mechanism"].startswith("oficjalny") and r["plugins_rendered"] and not r["procedural"]
    files = [Path(g["file"]) for g in eff["groundcover"]]
    st = esp.groundcover_stats(files)
    assert st["cells"] == 1 and st["exterior_cells"] == 1 and st["statics"] == 1 and st["files"][0]["references"] == 2
    p = w(project["omods"].parent / "x.esp", esp_bytes(cells=[((1, 1), [])], interiors=["Balmora, Dom"]))
    st2 = esp.groundcover_stats([files[0], p])
    assert (st2["cells"], st2["exterior_cells"]) == (3, 2)   # jak silnik: wnętrze też liczone
    c = esp.cell_references(files[0], (15, -9))
    assert c == {"file": "Rem_AC.esp", "cell": [15, -9], "assigned": 2, "position_inside": 1}


# --- manifest i różnice ------------------------------------------------------------

def test_manifest_build_write_and_stable_label(project):
    e = project["env"]
    m1 = manifest.build(e, "official-ref")
    m2 = manifest.build(e, "official-ref")
    assert m1["label"] == m2["label"]
    assert m1["engine"]["source_commit"] == SRC_COMMIT
    core = [d for d in m1["data_dirs"] if d["name"] == "00 Core OpenMW"][0]
    assert core["variant"]["exact"] is True
    p = manifest.write(e, m1, "test ref")
    assert p.parent == project["root"] / "Raporty/mcp/manifesty" and json.loads(p.read_text())["label"] == m1["label"]
    (project["omods"] / "01b Thicker Grass OpenMW/meshes/grass/rem_ac_grass_03.nif").write_bytes(b"zmiana")
    assert manifest.build(e, "official-ref")["label"] != m1["label"]


def test_profile_diff_and_vfs_compare(project):
    e = project["env"]
    d = manifest.diff(manifest.build(e, "fork-test"), manifest.build(e, "official-ref"))
    assert d["engine"]["target"] == ["fork", "official"]
    assert "Remiros" in d["data_dirs"]["only_in_a"]
    assert d["plugins"]["groundcover"]["only_in_b"] == ["rem_ac.esp"]
    assert d["settings"]["General/preferred locales"] == ["pl,en", None]
    assert any("mechanizmy" in x for x in d["comparability_warnings"])
    v = manifest.vfs_compare(e, "fork-test", "official-ref", "textures/rem/")
    assert v["different_sha256"][0]["path"] == "textures/rem/grass/tx_ac_grass_01.dds"


def test_diff_same_mod_name_different_sha(project):
    e = project["env"]
    a = manifest.build(e, "official-ref")
    (project["omods"] / "00 Core OpenMW/Rem_AC.esp").write_bytes(esp_bytes())
    b = manifest.build(e, "official-ref")
    d = manifest.diff(a, b)
    core = [x for x in b["data_dirs"] if x["name"] == "00 Core OpenMW"][0]
    assert core["case_collisions"] == {"rem_ac.esp": ["Rem_AC.esp", "rem_ac.esp"]}
    assert any("wielkością liter" in x for x in b["warnings"])
    assert "00 Core OpenMW" in d["data_dirs"]["same_name_different_content"]
    assert d["plugins"]["groundcover"]["same_name_different_sha256"] == ["rem_ac.esp"]
    assert len(d["comparability_warnings"]) >= 2


def test_source_manifest_hash(tmp_path):
    from openmw_mcp import srcmanifest
    w(tmp_path / "src/openmw_mcp/a.py", "x = 1\n"); w(tmp_path / "README.md", "r\n")
    t1 = srcmanifest.manifest_text(tmp_path)
    assert "src/openmw_mcp/a.py" in t1 and srcmanifest.tree_hash(tmp_path) == __import__("hashlib").sha256(t1.encode()).hexdigest()
    w(tmp_path / "src/openmw_mcp/a.py", "x = 2\n")
    assert srcmanifest.manifest_text(tmp_path) != t1


# --- serwer MCP (jeśli SDK zainstalowane) -------------------------------------------

def test_server_tools_registered(project, monkeypatch):
    pytest.importorskip("mcp")
    from openmw_mcp import server
    monkeypatch.setattr(server, "_ENV", project["env"])
    import asyncio, inspect
    lt = server.mcp.list_tools()
    tools = asyncio.run(lt) if inspect.iscoroutine(lt) else lt
    names = {t.name for t in tools}
    assert {"openmw_env_status", "openmw_profile_effective", "openmw_manifest_write", "openmw_profile_diff",
            "openmw_vfs_resolve", "openmw_groundcover_mode"} <= names
    r = server.openmw_profile_effective("nie-ma")
    assert "error" in r
    r = server.openmw_vfs_resolve("official-ref", "meshes/grass/rem_ac_grass_03.nif")
    assert r["winner"]["root"].endswith("01b Thicker Grass OpenMW")


def test_project_root_sibling_of_openmwgodot(tmp_path):
    """MCP w repozytorium OpenMWGodot: projekt OpenMW RLF to folder obok (OpenMWGoDot/tools/MCP-openMW)."""
    from openmw_mcp.environment import _project_root
    proj = tmp_path / "OpenMW RLF"
    (proj / "Fork").mkdir(parents=True)
    (proj / "OpenMW").mkdir()
    cfg = tmp_path / "OpenMWGoDot" / "tools" / "MCP-openMW" / "openmw-mcp.json"
    cfg.parent.mkdir(parents=True)
    cfg.write_text("{}")
    assert _project_root(cfg, "auto") == proj
