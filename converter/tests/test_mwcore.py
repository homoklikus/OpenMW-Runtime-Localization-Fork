"""Wspólna warstwa danych (mwcore): katalogi, konfiguracja, profile, archiwa, mody, instalacja, stan konwersji."""

import io
import json
import os
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

from mwcore import archive, conversion, install, launch, mods
from mwcore.jsonio import read_json, write_json
from mwcore.paths import AppPaths
from mwcore.profiles import ProfileStore
from mwcore.settings import LauncherConfig, validate_game

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def paths(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "cfg"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.delenv("XDG_RUNTIME_DIR", raising=False)
    monkeypatch.delenv("OPENMWGODOT_PORTABLE", raising=False)
    return AppPaths.detect().ensure()


def fake_game(tmp_path, synth_data) -> Path:
    """Układ jak w prawdziwej grze: Morrowind/Data Files/Morrowind.esm + Morrowind.bsa + Morrowind.ini."""
    g = tmp_path / "Morrowind"
    shutil.copytree(synth_data["dir"], g / "Data Files")
    (g / "Data Files" / "mwg_synthtown.esm").rename(g / "Data Files" / "Morrowind.esm")
    for p in (g / "Data Files").glob("mwg_synthtown_patch*.esp"):
        p.unlink()
    shutil.copy(g / "Data Files" / "synth.bsa", g / "Data Files" / "Morrowind.bsa")
    (g / "Morrowind.ini").write_text("[Archives]\n[Game Files]\nGameFile0=Morrowind.esm\n")
    return g


def tree_hash(root: Path) -> dict:
    import hashlib
    return {str(p.relative_to(root)): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime)
            for p in sorted(root.rglob("*")) if p.is_file()}


# --- katalogi i JSON -------------------------------------------------------------------------------

def test_xdg_and_portable(paths, tmp_path, monkeypatch):
    assert paths.config == tmp_path / "cfg" / "openmwgodot" and not paths.portable
    assert paths.saves("x") != paths.profile_data("x")
    app = tmp_path / "app"
    app.mkdir()
    (app / "portable.txt").write_text("")
    p = AppPaths.detect(app)
    assert p.portable and p.config == app / "userdata" / "config"


def test_atomic_json_and_corruption(tmp_path):
    f = tmp_path / "a.json"
    write_json(f, {"x": 1})
    assert read_json(f) == {"x": 1} and not list(tmp_path.glob("*.tmp"))
    f.write_text("{zepsute")
    assert read_json(f, {"d": 1}) == {"d": 1}
    assert list(tmp_path.glob("a.json.bad-*"))


def test_settings_validation_and_config(paths):
    v = validate_game({"max_fps": 99999, "shadows": "ultra", "vsync": 0, "nieznane": 1})
    assert v["max_fps"] == 360 and v["shadows"] == "medium" and v["vsync"] is False and "nieznane" not in v
    c = LauncherConfig.load(paths.launcher_config)
    c["language"] = "en"
    c.save()
    assert LauncherConfig.load(paths.launcher_config)["language"] == "en"


# --- profile ---------------------------------------------------------------------------------------

def test_profiles_crud_keeps_saves(paths):
    st = ProfileStore(paths)
    assert [p.id for p in st.list()] == ["default"]
    a = st.create("Mój Profil")
    a.mods = [{"id": "m1", "enabled": True}]
    a.settings["shadows"] = "high"
    st.save(a)
    b = st.create("Kopia", copy_from=a.id)
    assert b.mods == a.mods and b.settings["shadows"] == "high" and b.id != a.id
    st.rename(b.id, "Nowa nazwa")
    assert st.get(b.id).name == "Nowa nazwa"
    saves = paths.saves(b.id)
    saves.mkdir(parents=True)
    (saves / "save1.json").write_text("{}")
    paths.profile_data(b.id).mkdir(parents=True)
    st.delete(b.id)
    assert st.get(b.id) is None and (saves / "save1.json").exists() and not paths.profile_data(b.id).exists()
    with pytest.raises(ValueError):
        st._file("../zly")


# --- archiwa ---------------------------------------------------------------------------------------

def _zip(path: Path, entries: dict, symlink: str | None = None):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, d in entries.items():
            z.writestr(n, d)
        if symlink:
            zi = zipfile.ZipInfo(symlink)
            zi.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(zi, "/etc/passwd")


@pytest.mark.parametrize("name,entries,sym,msg", [
    ("trav", {"../../evil.txt": "x"}, None, ".."),
    ("abs", {"/tmp/evil.txt": "x"}, None, "bezwzględna"),
    ("drive", {"C:/evil.txt": "x"}, None, "bezwzględna"),
    ("sym", {"Data Files/meshes/a.nif": "x"}, "Data Files/link", "dowiązanie"),
    ("bomb", {"big.bin": b"\0" * (64 << 20)}, None, "kompresji"),
])
def test_archive_attacks_rejected(tmp_path, name, entries, sym, msg):
    z = tmp_path / f"{name}.zip"
    _zip(z, entries, sym)
    dest = tmp_path / "out"
    with pytest.raises(archive.ArchiveError, match=msg):
        archive.extract(z, dest)
    assert not (tmp_path / "evil.txt").exists() and not Path("/tmp/evil.txt").exists() or name != "abs"


def test_archive_size_limit_counts_real_bytes(tmp_path):
    z = tmp_path / "l.zip"
    _zip(z, {"a.bin": os.urandom(3 << 20)})
    with pytest.raises(archive.ArchiveError, match="limit"):
        archive.extract(z, tmp_path / "o", archive.Limits(max_total_bytes=1 << 20))


# --- mody ------------------------------------------------------------------------------------------

def make_mod_zip(tmp_path, synth_data, name="mod_a", nested=True, with_tex=True, esp_masters=("Morrowind.esm",)):
    from mwconv.esm import writer as W
    root = "MyMod/Data Files/" if nested else ""
    entries = {}
    if with_tex:
        entries[root + "textures/tx_synth_planks.dds"] = (synth_data["dir"] / "textures" / "tx_synth_roof.dds").read_bytes()
    entries[root + "meshes/mymod/thing.nif"] = (synth_data["dir"] / "meshes" / "synth" / "test_crate.nif").read_bytes()
    recs = [W.stat(f"{name}_thing", "mymod\\thing.nif")]
    entries[root + f"{name}.esp"] = W.header([(m, 0) for m in esp_masters], len(recs), is_master=False) + b"".join(recs)
    entries[root + "readme.txt"] = "opis"
    z = tmp_path / f"{name}.zip"
    _zip(z, entries)
    return z


def test_mod_install_zip_and_7z(paths, tmp_path, synth_data):
    store = mods.ModStore(paths)
    m = store.install(make_mod_zip(tmp_path, synth_data))
    assert m.id == "mod-a" and m.data_root.endswith("Data Files")
    assert m.plugins == [{"file": "mod_a.esp", "masters": ["Morrowind.esm"], "is_master": False, "groundcover": False}]
    assert "textures/tx_synth_planks.dds" in store.file_list(m)
    import py7zr
    src = tmp_path / "src7"
    (src / "textures").mkdir(parents=True)
    (src / "textures" / "x.dds").write_bytes(b"dds")
    with py7zr.SevenZipFile(tmp_path / "m.7z", "w") as z:
        z.writeall(src, arcname="")
    m2 = store.install(tmp_path / "m.7z", name="Mod 7z")
    assert m2.id == "mod-7z" and store.file_list(m2) == ["textures/x.dds"]
    assert {x.id for x in store.list()} == {"mod-a", "mod-7z"}
    store.remove("mod-7z")
    assert {x.id for x in store.list()} == {"mod-a"}
    assert not list(paths.staging.iterdir())  # brak pozostałości


def test_bad_manifest_cannot_escape(paths, tmp_path, synth_data):
    store = mods.ModStore(paths)
    m = store.install(make_mod_zip(tmp_path, synth_data))
    mf = paths.mods_dir / m.id / "mod.json"
    d = json.loads(mf.read_text())
    d["data_root"] = "../../../../etc"
    mf.write_text(json.dumps(d))
    with pytest.raises(mods.ModError):
        store.data_path(store.get(m.id))


def test_resolution_order_conflicts_and_missing_masters(paths, tmp_path, synth_data):
    g = fake_game(tmp_path, synth_data)
    rep = install.inspect(g)
    store = mods.ModStore(paths)
    a = store.install(make_mod_zip(tmp_path, synth_data, "mod_a"))
    b = store.install(make_mod_zip(tmp_path, synth_data, "mod_b", esp_masters=("Morrowind.esm", "mod_c.esp")))
    base_files = {"textures/tx_synth_planks.dds", "meshes/synth/test_hut.nif"}
    r = mods.resolve(rep.config, [a.id, b.id], store, base_files)
    assert r.content == ["Morrowind.esm", "mod_a.esp", "mod_b.esp"]
    assert r.missing_masters == [{"plugin": "mod_b.esp", "mod": "mod-b", "missing": ["mod_c.esp"]}]
    c = {x["file"]: x for x in r.conflicts}
    assert c["textures/tx_synth_planks.dds"]["providers"] == ["(gra)", "mod-a", "mod-b"]
    assert c["textures/tx_synth_planks.dds"]["winner"] == "mod-b"
    r2 = mods.resolve(rep.config, [b.id, a.id], store, base_files)
    assert r2.signature != r.signature and {x["file"]: x for x in r2.conflicts}["textures/tx_synth_planks.dds"]["winner"] == "mod-a"
    assert mods.resolve(rep.config, ["nie-ma"], store).missing_mods == ["nie-ma"]


# --- instalacja ------------------------------------------------------------------------------------

def test_install_inspect(tmp_path, synth_data):
    g = fake_game(tmp_path, synth_data)
    r = install.inspect(g)
    assert r.ok and r.kind == "morrowind"
    comp = {c["name"]: c for c in r.components}
    assert comp["Morrowind"]["esm"] and comp["Morrowind"]["bsa"] and not comp["Tribunal"]["esm"]
    assert install.inspect(tmp_path / "brak").ok is False
    empty = tmp_path / "empty"
    empty.mkdir()
    assert not install.inspect(empty).ok
    assert install.inspect(g / "Data Files").kind == "data"


# --- stan konwersji i plan -------------------------------------------------------------------------

def run_steps(st):
    for s in st:
        r = subprocess.run([sys.executable, *s["args"]], cwd=ROOT, capture_output=True, text=True, timeout=300)
        assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]


def test_plan_status_and_overlay(paths, tmp_path, synth_data):
    g = fake_game(tmp_path, synth_data)
    before = tree_hash(g)
    rep = install.inspect(g)
    store = mods.ModStore(paths)
    conv = paths.default_converted
    r0 = mods.resolve(rep.config, [], store)
    plan0 = conversion.make_plan(conv, paths.profile_data("default"), rep.config, r0)
    assert plan0.profile_out is None
    assert conversion.play_status(plan0).state == conversion.MISSING
    st = conversion.steps(plan0, "balmora")
    assert len(st) == 1 and "--cell" in st[0]["args"]
    st = conversion.steps(plan0, "full")
    run_steps(st)
    assert conversion.play_status(plan0).state == conversion.OUTDATED  # brak zapisu konwersji
    conversion.write_record(plan0, "full")
    assert conversion.play_status(plan0).state == conversion.READY
    # profil z modem: tylko nakładka
    m = store.install(make_mod_zip(tmp_path, synth_data))
    r1 = mods.resolve(rep.config, [m.id], store)
    plan1 = conversion.make_plan(conv, paths.profile_data("p1"), rep.config, r1)
    assert plan1.profile_out is not None
    assert conversion.play_status(plan1).state == conversion.MISSING
    st1 = conversion.steps(plan1, "full")
    assert len(st1) == 2 and "--base-out" in st1[1]["args"]
    run_steps(st1)
    conversion.write_record(plan1, "full")
    assert conversion.play_status(plan1).state == conversion.READY
    stats = json.loads((plan1.profile_out / "reports" / "conversion.json").read_text())["stats"]
    assert stats["models"]["converted"] == 1  # tylko nowy model moda
    assert stats["textures"]["converted"] == 1  # tylko podmieniona tekstura
    # zmiana zestawu modów → OUTDATED
    plan2 = conversion.make_plan(conv, paths.profile_data("p1"), rep.config, mods.resolve(rep.config, [], store))
    assert conversion.play_status(plan2).state == conversion.READY  # bez modów: baza
    r3 = mods.resolve(rep.config, [m.id], store)
    r3.signature = "inny"
    plan3 = conversion.make_plan(conv, paths.profile_data("p1"), rep.config, r3)
    assert conversion.play_status(plan3).state == conversion.OUTDATED
    # uszkodzony manifest → BROKEN
    (plan0.base_out / "world" / "objects.json").write_text("{x")
    assert conversion.play_status(plan0).state == conversion.BROKEN
    # oryginalna instalacja nietknięta
    assert tree_hash(g) == before


def test_instance_lock(tmp_path):
    lk = launch.InstanceLock(tmp_path, "game", "default")
    assert lk.holder() is None
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        lk.acquire(child.pid)
        assert lk.holder() == child.pid
    finally:
        child.kill()
        child.wait()
    assert lk.holder() is None  # martwa blokada


def test_commands_are_lists_without_shell(tmp_path):
    ua = launch.user_args(tmp_path / "d", tmp_path / "b", tmp_path / "p", tmp_path / "s.json", "default", tmp_path / "sv")
    cmd = launch.game_command("/usr/bin/godot", tmp_path, ua, extra="--verbose '; rm -rf /'")
    assert cmd[:3] == ["/usr/bin/godot", "--path", str(tmp_path)]
    assert "; rm -rf /" in cmd and "--" in cmd and any(a.startswith("--base=") for a in cmd)
    assert launch.editor_command("g", tmp_path, ua)[1] == "-e"


def test_game_command_window_args(tmp_path):
    ua = launch.user_args(tmp_path / "d", tmp_path / "d", tmp_path / "p", tmp_path / "s.json", "default", tmp_path / "sv")
    full = launch.game_command("g", tmp_path, ua, settings={"window_mode": "fullscreen", "resolution": "3440x1440"})
    assert "--fullscreen" in full and full.index("--fullscreen") < full.index("--")
    win = launch.game_command("g", tmp_path, ua, settings={"window_mode": "windowed", "resolution": "2560x1440"})
    i = win.index("--resolution")
    assert win[i + 1] == "2560x1440" and i < win.index("--")
    assert launch.window_args({"window_mode": "windowed", "resolution": "zly"}) == []
    assert launch.window_args(None) == []


def test_find_godot_official_binary_next_to_project(tmp_path, monkeypatch):
    from mwcore import launch
    monkeypatch.setenv("PATH", "")
    monkeypatch.delenv("MWGODOT_GODOT", raising=False)
    app = tmp_path / "launcher"
    app.mkdir()
    for name in ("Godot_v4.5.1-stable_linux.x86_64", "Godot_v4.7.2-stable_linux.x86_64"):
        f = tmp_path / name
        f.write_text("#!/bin/sh\n")
        f.chmod(0o755)
    (tmp_path / "Godot_v4.8-stable_linux.x86_64.zip").write_text("")
    assert launch.find_godot("", app) == str(tmp_path / "Godot_v4.7.2-stable_linux.x86_64")


def test_project_needs_import_after_script_update(tmp_path):
    """Gra uruchamiana bez edytora zna tylko klasy z cache importu – po aktualizacji skryptów import."""
    import os
    import time
    from mwcore import launch
    proj = tmp_path / "godot"
    (proj / "scripts").mkdir(parents=True)
    (proj / "scripts" / "a.gd").write_text("class_name A\n")
    assert launch.project_needs_import(proj)            # brak cache
    cache = proj / ".godot" / "global_script_class_cache.cfg"
    cache.parent.mkdir()
    cache.write_text("list=[]\n")
    assert not launch.project_needs_import(proj)
    future = time.time() + 5
    os.utime(proj / "scripts" / "a.gd", (future, future))   # skrypt nowszy niż cache (np. po git pull)
    assert launch.project_needs_import(proj)


def test_translation_only_mod(paths, tmp_path):
    """Mod z samymi tłumaczeniami (localization/language/*.yaml, format forka RLF) – katalog danych rozpoznany."""
    import zipfile
    z = tmp_path / "Morrowind PL.zip"
    with zipfile.ZipFile(z, "w") as f:
        f.writestr("Morrowind PL/localization/language/Morrowind.yaml", "strings: {}\n")
    store = mods.ModStore(paths)
    m = store.install(z)
    assert m.data_root.endswith("Morrowind PL") and m.plugins == []
    assert "localization/language/morrowind.yaml" in {k.lower() for k in store.file_list(m)}


def test_groundcover_plugin_mod_goes_to_groundcover_list(paths, tmp_path, synth_data):
    """Mod z trawą (np. Remiros): wtyczka rozpoznana jako groundcover → osobna lista, nie content (jak openmw.cfg)."""
    import zipfile
    from mwconv.synthetic_world import write_flora
    fl = write_flora(tmp_path / "fl")
    z = tmp_path / "Grass.zip"
    with zipfile.ZipFile(z, "w") as f:
        f.write(fl["groundcover"], "Grass/mwg_grass.esp")
        f.write(Path(fl["dir"]) / "meshes/grass/synth_gc_01.nif", "Grass/meshes/grass/synth_gc_01.nif")
    store = mods.ModStore(paths)
    m = store.install(z)
    assert m.plugins[0]["groundcover"] is True
    from mwconv.install import InstallConfig
    base = InstallConfig(data_dirs=[str(synth_data["dir"])], content=[str(synth_data["dir"] / "mwg_synthtown.esm")])
    res = mods.resolve(base, [m.id], store)
    assert [Path(c).name for c in res.config.content] == ["mwg_synthtown.esm"]
    assert [Path(g).name for g in res.config.groundcover] == ["mwg_grass.esp"]
    args = conversion.convert_args(res.config, tmp_path / "o", flora={"enabled": True, "source": "hybrid",
                                                                      "density": 0.5})
    i = args.index("--groundcover")
    assert args[i + 1].endswith("mwg_grass.esp")
    assert args[args.index("--flora") + 1] == "hybrid" and args[args.index("--flora-density") + 1] == "0.5"
    assert conversion.convert_args(res.config, tmp_path / "o")[args.index("--flora") + 1] == "off"


def test_resolution_any_screen_size():
    """Rozdzielczość: natywna rozdzielczość ekranu spoza listy (np. ultrawide 3440x1440) jest akceptowana."""
    from mwcore import settings as S
    assert S.validate_game({"resolution": "3440x1440"})["resolution"] == "3440x1440"
    assert S.validate_game({"resolution": "2752x1152"})["resolution"] == "2752x1152"   # dowolny ekran
    assert S.validate_game({"resolution": "abc"})["resolution"] == "1280x720"
    assert S.validate_game({"resolution": "99999x10"})["resolution"] == "1280x720"
    ch = S.resolution_choices([(3440, 1440), (2752, 1152)], "1366x768")
    assert {"3440x1440", "2752x1152", "1366x768", "1920x1080"} <= set(ch)
    assert ch == sorted(ch, key=lambda r: tuple(map(int, r.split("x"))))


def test_merge_ingame_settings(tmp_path):
    """Etap 10: zmiany z ustawień w grze trafiają do profilu, a plik jest opróżniany (bez usuwania)."""
    from mwcore import launch
    from mwcore.jsonio import read_json, write_json
    from mwcore.settings import validate_game
    base = validate_game({"music_volume": 0.5, "fov": 60})
    merged, changed = launch.merge_ingame(tmp_path, base)
    assert not changed and merged == base
    write_json(tmp_path / launch.INGAME_FILE, {"values": {"music_volume": 0.2, "fov": 300, "nieznane": 1}})
    merged, changed = launch.merge_ingame(tmp_path, base)
    assert changed and merged["music_volume"] == 0.2
    assert merged["fov"] == 110 or merged["fov"] == 60, "wartość spoza zakresu przycięta albo odrzucona"
    assert "nieznane" not in merged
    assert (tmp_path / launch.INGAME_FILE).exists() and read_json(tmp_path / launch.INGAME_FILE)["values"] == {}
    merged2, changed2 = launch.merge_ingame(tmp_path, merged)
    assert not changed2
