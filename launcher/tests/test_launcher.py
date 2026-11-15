"""Testy launchera (Qt offscreen) – scenariusze z wymagań: start bez Godota, instalacja, konwersja z postępem,
przerwanie i wznowienie, uszkodzony cache, mody (archiwum, konflikty, kolejność), profile, ustawienia,
„Graj”, błędny kod wyjścia, Construction Set, brak modyfikacji plików gry."""

import json
import os
import resource
import subprocess
import sys
import time
import zipfile
from pathlib import Path

import pytest
from conftest import FAKE_GODOT, ROOT, tree_hash, wait_until

from mwcore import conversion


def make_window():
    from openmwgodot_launcher.app import MainWindow
    from openmwgodot_launcher.core import LauncherCore
    core = LauncherCore()
    w = MainWindow(core)
    w.show()
    return w


def convert_gui(app, w, scope="balmora"):
    page = w.pages["conversion"]
    w.show_page("conversion")
    page.scope.setCurrentIndex(0 if scope == "full" else 1)
    res = {}
    w.conv_runner.finished.connect(lambda st, code: res.update(status=st, code=code))
    page.start()
    assert wait_until(app, lambda: "status" in res, 300), page.log.toPlainText()[-2000:]
    return res, page


def godot_calls(env):
    f = env / "godot_calls.jsonl"
    return [json.loads(x) for x in f.read_text().splitlines()] if f.exists() else []


# ------------------------------------------------------------------------------------------------

def test_launcher_starts_without_godot(env, tmp_path):
    """Proces launchera startuje i kończy się bez uruchamiania Godota (atrapa zapisałaby wywołanie)."""
    cfg = tmp_path / "cfg" / "openmwgodot"
    cfg.mkdir(parents=True)
    (cfg / "launcher.json").write_text(json.dumps({"wizard_done": True}))
    t0 = time.monotonic()
    r = subprocess.run([sys.executable, "-m", "openmwgodot_launcher"], cwd=ROOT / "launcher",
                       env={**os.environ, "OPENMWGODOT_AUTOQUIT_MS": "800"}, capture_output=True, text=True, timeout=60)
    took = time.monotonic() - t0
    assert r.returncode == 0, r.stderr[-1500:]
    assert godot_calls(env) == []  # Godot nie był uruchamiany (ani --version)
    assert took < 15
    rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024
    print(f"start+zamknięcie: {took:.2f} s (w tym 0.8 s autoquit), RSS ≤ {rss:.0f} MB")


def test_missing_installation_blocks_play(env, qapp):
    w = make_window()
    assert not w.play()
    assert "instalacji" in w.last_message and w.stack.currentWidget() is w.pages["conversion"]
    assert godot_calls(env) == []


def test_valid_installation_conversion_and_play(env, qapp, fake_game):
    before = tree_hash(fake_game)
    w = make_window()
    page = w.pages["conversion"]
    page.src.setText(str(fake_game))
    assert page._apply_src()
    assert "Morrowind" in page.src_info.text()
    st = w.core.check_play()
    assert not st.ok and st.problems[0][0] == "conversion"
    stages, progress = [], []
    w.conv_runner.stage.connect(lambda step, s: stages.append((step, s)))
    w.conv_runner.progress.connect(lambda s, d, t, e: progress.append((s, d, t)))
    res, _ = convert_gui(qapp, w, "full")
    assert res["status"] == "done"
    assert {"vfs", "world", "models", "textures"} <= {s for _, s in stages}
    models = [p for p in progress if p[0] == "models"]
    assert models and models[-1][1] == models[-1][2] > 0  # rzeczywisty postęp do końca
    assert w.core.status().state == conversion.READY
    w.core.config["launch_args"] = "--verbose"
    w.core.config.save()
    assert w.play()
    assert wait_until(qapp, lambda: not w.game.is_running(), 30)
    calls = godot_calls(env)
    call = [c for c in calls if "res://main.tscn" in c][-1]
    assert call[0] == "--path" and "--verbose" in call
    assert calls[-1] == ["--version", "--headless"]  # wersja Godota zapamiętana dopiero po grze
    assert w.core.config["godot_version"] == "4.7.1.stable.fake"
    ua = call[call.index("--") + 1:]
    assert any(a.startswith("--data=") for a in ua) and any(a.startswith("--settings=") for a in ua)
    assert getattr(w, "last_exit", None) == 0
    assert tree_hash(fake_game) == before  # oryginalne pliki gry nietknięte


def test_game_error_exit_code_reported(env, qapp, fake_game, monkeypatch):
    w = make_window()
    w.core.set_install(str(fake_game))
    convert_gui(qapp, w)
    monkeypatch.setenv("FAKE_GODOT_EXIT", "7")
    assert w.play()
    assert wait_until(qapp, lambda: not w.game.is_running(), 30)
    assert w.last_exit == 7 and "Kod wyjścia: 7" in w.last_message and "fake godot" in w.last_message
    assert w.core.lock("game").holder() is None


def test_single_instance_per_profile(env, qapp, fake_game, monkeypatch):
    w = make_window()
    w.core.set_install(str(fake_game))
    convert_gui(qapp, w)
    monkeypatch.setenv("FAKE_GODOT_SLEEP", "5")
    assert w.play()
    assert not w.play() and "już działa" in w.last_message
    # obca instancja (blokada z żywym PID) → bez zgody użytkownika nie startujemy drugiej
    w.game.terminate()
    wait_until(qapp, lambda: not w.game.is_running(), 10)
    other = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
    try:
        w.core.lock("game").acquire(other.pid)
        qapp.setProperty("auto_confirm", False)
        assert not w.play()
    finally:
        other.kill()
        other.wait()


def test_editor_launch(env, qapp, fake_game):
    w = make_window()
    w.core.set_install(str(fake_game))
    convert_gui(qapp, w)
    assert w.launch_editor()
    assert wait_until(qapp, lambda: not w.editor.is_running(), 30)
    call = [c for c in godot_calls(env) if c and c[0] == "-e"][-1]
    assert call[0] == "-e" and "--path" in call and any(a.startswith("--project=") for a in call)
    assert w.last_editor_exit == 0


def _many_models(d: Path, n: int):
    from mwconv.synthetic import make_crate, make_hut, make_windmill
    blobs = [make_hut(), make_windmill(), make_crate()]
    for i in range(n):
        p = d / "Data Files" / "meshes" / "many" / f"m{i:04d}.nif"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(blobs[i % 3])


def test_cancel_resume_and_damaged_cache(env, qapp, fake_game):
    _many_models(fake_game, 500)
    before = tree_hash(fake_game)
    w = make_window()
    w.core.set_install(str(fake_game))
    page = w.pages["conversion"]
    w.show_page("conversion")
    page.scope.setCurrentIndex(0)
    res = {}
    w.conv_runner.finished.connect(lambda st, code: res.update(status=st, code=code))
    seen = {"n": 0}

    def on_prog(stage, done, total, eta):
        if stage == "models" and done >= 30 and not seen["n"]:
            seen["n"] = done
            page.cancel()
    w.conv_runner.progress.connect(on_prog)
    page.start()
    assert wait_until(qapp, lambda: "status" in res, 120)
    assert res["status"] == "cancelled"
    assert w.core.status().state in (conversion.INCOMPLETE, conversion.MISSING)
    assert not w.core.check_play().ok
    # wznowienie
    w.conv_runner.progress.disconnect(on_prog)
    res.clear()
    page.start()
    assert wait_until(qapp, lambda: "status" in res, 300)
    assert res["status"] == "done" and w.core.status().state == conversion.READY
    stats = json.loads((w.core.plan().base_out / "reports" / "conversion.json").read_text())["stats"]
    assert stats["models"]["skipped_unchanged"] >= 30  # ukończone przed przerwaniem nie są konwertowane ponownie
    # uszkodzony cache / dane → wykrycie przed „Graj” i naprawa
    base = w.core.plan().base_out
    (base / "world" / "objects.json").write_text("{zepsute")
    glb = next((base / "meshes" / "many").glob("*.glb"))
    glb.write_bytes(b"xx")
    chk = w.core.check_play()
    assert not chk.ok and "Uszkodzone" in chk.problems[0][1]
    res.clear()
    page.verify(repair=True)
    assert wait_until(qapp, lambda: "status" in res, 300)
    assert res["status"] == "done" and w.core.status().state == conversion.READY
    page.verify(repair=False)
    assert w.last_message == "weryfikacja ok"
    # czyszczenie nieużywanych plików (z potwierdzeniem)
    junk = base / "meshes" / "junk.glb"
    junk.write_bytes(b"x")
    page.clean()
    assert not junk.exists() and w.last_message.startswith("usunięto")
    assert tree_hash(fake_game) == before


def _mod_zip(tmp: Path, synth_dir: Path, name: str, tex_from: str):
    from mwconv.esm import writer as W
    root = f"{name}/Data Files/"
    recs = [W.stat(f"{name}_thing", f"{name}\\thing.nif")]
    entries = {
        root + "textures/tx_synth_planks.dds": (synth_dir / "textures" / tex_from).read_bytes(),
        root + f"meshes/{name}/thing.nif": (synth_dir / "meshes" / "synth" / "test_crate.nif").read_bytes(),
        root + f"{name}.esp": W.header([("Morrowind.esm", 0)], len(recs), is_master=False) + b"".join(recs),
    }
    z = tmp / f"{name}.zip"
    with zipfile.ZipFile(z, "w") as zf:
        for n, d in entries.items():
            zf.writestr(n, d)
    return z


def test_mods_install_conflicts_order_and_incremental_rebuild(env, qapp, fake_game, synth_dir, tmp_path):
    before = tree_hash(fake_game)
    w = make_window()
    w.core.set_install(str(fake_game))
    convert_gui(qapp, w, "full")
    base_out = w.core.plan().base_out
    page = w.pages["mods"]
    w.show_page("mods")
    assert page.install_archive(str(_mod_zip(tmp_path, synth_dir, "moda", "tx_synth_roof.dds")))
    assert page.install_archive(str(_mod_zip(tmp_path, synth_dir, "modb", "tx_synth_sign.dds")))
    # ścieżka ze złym archiwum (path traversal) – odrzucona bez śladu
    bad = tmp_path / "evil.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("../../evil.txt", "x")
    assert not page.install_archive(str(bad)) and "Nie zainstalowano" in w.last_message
    assert not (tmp_path / "evil.txt").exists()
    res = page.last_resolution
    c = {x["file"]: x for x in res.conflicts}["textures/tx_synth_planks.dds"]
    assert c["providers"] == ["(gra)", "moda", "modb"] and c["winner"] == "modb"
    assert res.content == ["Morrowind.esm", "moda.esp", "modb.esp"]
    # zmiana kolejności
    page.list.setCurrentRow(1)
    page.up()
    res2 = w.core.resolution(with_conflicts=True)
    assert {x["file"]: x for x in res2.conflicts}["textures/tx_synth_planks.dds"]["winner"] == "moda"
    assert w.core.status().state != conversion.READY  # zestaw modów zmieniony → wymaga przebudowy
    # zastosowanie: tylko zasoby zmienione przez mody (nakładka profilu), baza bez zmian
    done = {}
    w.conv_runner.finished.connect(lambda st, code: done.update(status=st))
    page.apply()
    assert wait_until(qapp, lambda: "status" in done, 300)
    assert done["status"] == "done" and w.core.status().state == conversion.READY
    prof_out = w.core.plan().profile_out
    stats = json.loads((prof_out / "reports" / "conversion.json").read_text())["stats"]
    assert stats["textures"]["converted"] == 1 and stats["models"]["from_base"] > 0
    assert not (prof_out / "meshes" / "synth" / "test_hut.glb").exists()  # brak duplikatu gry
    base_stats = json.loads((base_out / ".mwconv" / "export_state.json").read_text())
    assert base_stats["complete"]
    # wyłączenie moda i usunięcie z profilu
    page.list.setCurrentRow(0)
    page.list.item(0).setCheckState(page.list.item(0).checkState().__class__(0))
    assert len(w.core.profile.enabled_mods()) == 1
    page.remove_from_profile()
    assert tree_hash(fake_game) == before


def test_profiles_and_settings(env, qapp, fake_game):
    w = make_window()
    core = w.core
    p = core.profiles.create("Druga postać")
    w.pages["home"].refresh()
    box = w.pages["home"].profile_box
    idx = box.findData(p.id)
    box.setCurrentIndex(idx)
    assert core.profile.id == p.id
    sp = w.pages["settings"]
    w.show_page("settings")
    o, wdg = sp.widgets["max_fps"]
    wdg.setValue(75)
    sp.widgets["shadows"][1].setCurrentIndex(sp.widgets["shadows"][1].findData("high"))
    sp.lang.setCurrentIndex(1)
    sp.save()
    from openmwgodot_launcher.core import LauncherCore
    core2 = LauncherCore()
    assert core2.profile.id == p.id and core2.profile.settings["max_fps"] == 75
    assert core2.profile.settings["shadows"] == "high" and core2.config["language"] == "en"
    assert core2.profiles.get("default").settings["max_fps"] == 0  # inny profil nietknięty
    # plik ustawień dla Runtime
    core2.set_install(str(fake_game))
    args = core2.runtime_args()
    sf = Path(next(a for a in args if a.startswith("--settings=")).split("=", 1)[1])
    rs = json.loads(sf.read_text())
    assert rs["max_fps"] == 75 and rs["profile"] == p.id


@pytest.mark.skipif(not (os.environ.get("MWGODOT_REAL_GODOT") and Path(os.environ["MWGODOT_REAL_GODOT"]).exists()),
                    reason="ustaw MWGODOT_REAL_GODOT=ścieżka do Godota 4")
def test_real_godot_game_and_editor(env, qapp, fake_game, synth_dir, tmp_path, monkeypatch):
    """Integracja: prawdziwy Godot uruchamiany przez launcher – gra (z nakładką modów) i Construction Set."""
    monkeypatch.setenv("MWGODOT_GODOT", os.environ["MWGODOT_REAL_GODOT"])
    w = make_window()
    w.core.set_install(str(fake_game))
    w.core.config["launch_args"] = "--headless"
    w.core.config["bake"] = False
    w.core.config.save()
    w.pages["mods"].install_archive(str(_mod_zip(tmp_path, synth_dir, "moda", "tx_synth_roof.dds")))
    res, _ = convert_gui(qapp, w, "full")
    assert res["status"] == "done", w.pages["conversion"].log.toPlainText()[-2000:]
    prof = w.core.profile
    prof.settings["max_fps"] = 33
    w.core.profiles.save(prof)
    qapp.setProperty("test_user_args", ["--autotest-frames=40"])
    assert w.play()
    assert wait_until(qapp, lambda: not w.game.is_running(), 120)
    log = Path(w.game.log_path).read_text()
    assert w.last_exit == 0, log[-3000:]
    stats = json.loads(next(l for l in log.splitlines() if l.startswith("MWGODOT_STATS "))[14:])
    assert stats["cells"] > 0 and stats["models"]["failed"] == 0 and stats["max_fps"] == 33
    assert stats["base_roots"], "gra korzysta z bazy + nakładki profilu"
    qapp.setProperty("test_user_args", None)
    w.core.config["launch_args"] = "--headless --quit-after 200"
    w.core.config.save()
    assert w.launch_editor()
    assert wait_until(qapp, lambda: not w.editor.is_running(), 180)
    elog = Path(w.editor.log_path).read_text()
    assert w.last_editor_exit == 0, elog[-3000:]
    assert "SCRIPT ERROR" not in elog


def test_first_run_wizard_and_resume(env, qapp, fake_game):
    from openmwgodot_launcher.core import LauncherCore
    from openmwgodot_launcher.wizard import FirstRunWizard
    core = LauncherCore()
    wz = FirstRunWizard(core)
    wz.show()
    wz.next()                                  # język → instalacja
    assert not wz.currentPage().isComplete()   # brak ścieżki
    wz.src.setText(str(fake_game))
    assert wz.currentPage().isComplete() and core.config["install"]["path"] == str(fake_game)
    wz.next()                                  # → katalog docelowy
    wz.scope.setCurrentIndex(1)
    wz.close()                                 # przerwanie kreatora po 3 krokach
    core2 = LauncherCore()
    assert core2.config["install"]["path"] == str(fake_game)  # nie trzeba wskazywać ponownie
    wz2 = FirstRunWizard(core2)
    wz2.show()
    assert wz2.currentId() >= 2                 # wznowienie od zapisanego kroku
    while wz2.currentId() < 3:
        wz2.next()
    res = {}
    wz2.runner.finished.connect(lambda st, c: res.update(status=st))
    wz2._start()
    assert wait_until(qapp, lambda: "status" in res, 300) and res["status"] == "done"
    assert wz2.currentPage().isComplete()
    wz2.next()
    wz2.accept()
    assert LauncherCore().config["wizard_done"] is True
    assert core2.status().state == conversion.READY


def test_home_screen_reference_layout(env, qapp, fake_game):
    """Ekran główny wg grafiki referencyjnej: stan komponentów, zasoby, profil, działania, podgląd z gry."""
    from PySide6.QtGui import QColor, QImage
    w = make_window()
    w.core.set_install(str(fake_game))
    convert_gui(qapp, w, "full")
    w.show_page("home")
    home = w.pages["home"]
    texts = [home.checks.itemAt(i).widget().text() for i in range(home.checks.count())
             if hasattr(home.checks.itemAt(i).widget(), "text")]
    joined = " ".join(texts)
    assert "Morrowind (gra podstawowa)" in joined and "Zasoby przekonwertowane" in joined
    assert "plik" in joined
    assert "Profil gotowy do gry" in home.pinfo["ready"][1].text()
    assert home.pinfo["last"][1].text().startswith("Ostatnia konwersja: dzisiaj")
    acts = [a["text"] for a in w.core.activity.recent(5)]
    assert any(a.startswith("Konwersja zakończona pomyślnie") for a in acts)
    assert any(a.startswith("Wykryto instalację Morrowinda") for a in acts)
    assert set(w.nav) >= {"home", "conversion", "mods", "profiles", "settings", "cs", "diagnostics", "help"}
    assert w.status_text.text() == "Gotowy"
    # podgląd: widok z ostatniej sesji gry (zapisany lokalnie przez Runtime) zastępuje ilustrację
    shot = w.core.paths.saves(w.core.profile.id) / "last_view.png"
    shot.parent.mkdir(parents=True, exist_ok=True)
    img = QImage(64, 36, QImage.Format_RGB32)
    img.fill(QColor(0, 255, 0))
    img.save(str(shot))
    home.refresh()
    c = home.preview.pixmap().toImage().pixelColor(10, 10)
    assert c.green() > 200 and c.red() < 50
    for k in ("profiles", "diagnostics", "help", "settings", "home"):
        w.show_page(k)
        assert w.nav[k].isChecked()


def test_converted_dir_never_relative_to_cwd_or_inside_repo(env, qapp, fake_game, monkeypatch):
    """Regresja: wpisanie samej nazwy („Balmora”) zapisało zasoby gry w launcher/Balmora (w repozytorium).
    Unikalna nazwa – test nie zależy od katalogów, które użytkownik ma już w projekcie."""
    name = f"omwg-test-{os.getpid()}"
    in_repo = [ROOT / "launcher" / name, ROOT / "converter" / name, ROOT / name]
    assert not any(p.exists() for p in in_repo)
    monkeypatch.chdir(ROOT / "launcher")
    w = make_window()
    page = w.pages["conversion"]
    page.src.setText(str(fake_game))
    assert page._apply_src()
    page.dst.setText(name)
    res, _ = convert_gui(qapp, w, "full")
    assert res["status"] == "done"
    out = Path(w.core.config["converted_dir"])
    assert out.is_absolute() and out == w.core.paths.data / name
    assert (out / "base" / ".gitignore").read_text().strip().endswith("*")
    assert not any(p.exists() for p in in_repo)
    # katalog w repozytorium i w instalacji gry – odrzucony, konwersja nie startuje
    for bad in (str(ROOT / "launcher" / name), str(ROOT), str(fake_game / "out")):
        page.dst.setText(bad)
        page.start()
        assert not w.conv_runner.is_running() and "Katalog" in w.last_message
        assert w.core.config["converted_dir"] == str(out)
    assert not any(p.exists() for p in in_repo)


def test_game_language_setting_from_conversion(env, qapp, fake_game):
    """Język gry: lista z world/localization/index.json bieżącej konwersji, zapis w ustawieniach profilu."""
    w = make_window()
    w.core.set_install(str(fake_game))
    plan = w.core.plan()
    idx = Path(plan.base_out) / "world" / "localization" / "index.json"
    idx.parent.mkdir(parents=True, exist_ok=True)
    idx.write_text(json.dumps({"languages": ["EN", "PL"]}))
    assert w.core.game_languages() == ["EN", "PL"]
    page = w.pages["settings"]
    w.show_page("settings")
    o, combo = page.widgets["game_language"]
    assert [combo.itemData(i) for i in range(combo.count())] == ["auto", "original", "en", "pl"]
    combo.setCurrentIndex(combo.findData("pl"))
    page.widgets["qa_source"][1].setText("MojMod.esp")
    page.save()
    rs = json.loads(Path(w.core.runtime_args()[2].split("=", 1)[1]).read_text())
    assert rs["game_language"] == "pl" and rs["qa_source"] == "MojMod.esp"


def test_world_tab_flora_settings_to_conversion(env, qapp, fake_game):
    """Świat (world.cfg forka): ustawienia roślinności zapisane w launcherze i przekazane do konwertera."""
    w = make_window()
    w.core.set_install(str(fake_game))
    page = w.pages["settings"]
    w.show_page("settings")
    assert not page.fl_source.isEnabled() and page.gc_legacy.isEnabled()
    page.fl_enabled.setChecked(True)
    assert page.fl_source.isEnabled() and not page.gc_legacy.isEnabled()
    page.fl_source.setCurrentIndex(page.fl_source.findData("hybrid"))
    page.fl_density.setValue(1.5)
    page.fl_excl.setValue(5)
    page.save()
    assert w.core.config["flora"]["source"] == "hybrid" and w.core.config["flora"]["density"] == 1.5
    args = w.core.conversion_steps()[0]["args"]
    assert args[args.index("--flora") + 1] == "hybrid" and args[args.index("--flora-exclusion") + 1] == "5"
