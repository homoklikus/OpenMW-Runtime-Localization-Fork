#!/usr/bin/env python3
"""Zrzuty ekranu launchera na danych syntetycznych (Qt offscreen): python3 tools/screenshots.py KATALOG_WYJŚCIOWY [pl|en]

Tworzy tymczasowe katalogi XDG i „instalację” o układzie jak w grze (syntetyczny ESM pod nazwą Morrowind.esm),
wykonuje konwersję, instaluje dwa mody i zapisuje zrzuty kolejnych ekranów jako PNG.
"""
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "converter"))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
out = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
tmp = Path(tempfile.mkdtemp(prefix="omwg-shots-"))
for k, sub in (("XDG_CONFIG_HOME", "cfg"), ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"),
               ("XDG_STATE_HOME", "state")):
    os.environ[k] = str(tmp / sub)
os.environ.pop("XDG_RUNTIME_DIR", None)

from PySide6.QtWidgets import QApplication  # noqa: E402

app = QApplication([])
app.setProperty("headless_test", True)
app.setProperty("auto_confirm", True)
from openmwgodot_launcher import theme  # noqa: E402

app.setStyleSheet(theme.QSS)
from mwconv.esm import writer as W  # noqa: E402
from mwconv.synthetic_world import write_world  # noqa: E402
from openmwgodot_launcher.app import MainWindow  # noqa: E402
from openmwgodot_launcher.core import LauncherCore  # noqa: E402
from openmwgodot_launcher.wizard import FirstRunWizard  # noqa: E402


def wait(cond, timeout=300):
    import time
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout and not cond():
        app.processEvents()
        time.sleep(0.02)


src = tmp / "synth" / "Data Files"
write_world(src)
g = tmp / "Morrowind"
shutil.copytree(src, g / "Data Files")
(g / "Data Files" / "mwg_synthtown.esm").rename(g / "Data Files" / "Morrowind.esm")
for p in (g / "Data Files").glob("mwg_synthtown_patch*.esp"):
    p.unlink()
shutil.copy(g / "Data Files" / "synth.bsa", g / "Data Files" / "Morrowind.bsa")
(g / "Morrowind.ini").write_text("[Archives]\n[Game Files]\nGameFile0=Morrowind.esm\n")
out.mkdir(parents=True, exist_ok=True)
core = LauncherCore()
core.config["bake"] = False
core.config["language"] = sys.argv[2] if len(sys.argv) > 2 else "pl"     # język launchera (pl | en)
core.config.save()
wz = FirstRunWizard(core)
wz.show()
wz.next()
wz.src.setText(str(g))
app.processEvents()
wz.grab().save(str(out / "launcher_02_kreator.png"))
wz.close()
w = MainWindow(core)
w.show()
page = w.pages["conversion"]
w.show_page("conversion")
page.src.setText(str(g))
page._apply_src()
shot = {}


def prog(stage, d, t, e):
    if stage == "models" and d >= max(1, t // 2) and "mid" not in shot:
        shot["mid"] = 1
        app.processEvents()
        w.grab().save(str(out / "launcher_03_konwersja_w_toku.png"))


w.conv_runner.progress.connect(prog)
res = {}
w.conv_runner.finished.connect(lambda s, c: res.update(s=s))
page.start()
wait(lambda: "s" in res)
app.processEvents()
w.grab().save(str(out / "launcher_04_konwersja_gotowa.png"))


def modzip(name, tex):
    z = tmp / f"{name}.zip"
    root = f"{name}/Data Files/"
    recs = [W.stat(f"{name}_x", f"{name}\\x.nif")]
    with zipfile.ZipFile(z, "w") as zf:
        zf.writestr(root + "textures/tx_synth_planks.dds", (src / "textures" / tex).read_bytes())
        zf.writestr(root + f"meshes/{name}/x.nif", (src / "meshes" / "synth" / "test_crate.nif").read_bytes())
        zf.writestr(root + f"{name}.esp", W.header([("Morrowind.esm", 0)], 1, is_master=False) + b"".join(recs))
    return z


mp = w.pages["mods"]
w.show_page("mods")
mp.install_archive(str(modzip("Lepsze Drewno", "tx_synth_roof.dds")))
mp.install_archive(str(modzip("Nowe Szyldy", "tx_synth_sign.dds")))
mp.list.setCurrentRow(1)
app.processEvents()
w.grab().save(str(out / "launcher_05_mody.png"))
res.clear()
mp.apply()
wait(lambda: "s" in res)
w.show_page("settings")
app.processEvents()
w.grab().save(str(out / "launcher_06_ustawienia.png"))
w.pages["settings"].tabs.setCurrentIndex(4)
app.processEvents()
w.grab().save(str(out / "launcher_07_zaawansowane.png"))
w.show_page("home")
app.processEvents()
w.grab().save(str(out / "launcher_01_ekran_glowny.png"))
shutil.rmtree(tmp, ignore_errors=True)
print("zrzuty:", out)
