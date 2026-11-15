import hashlib
import os
import shutil
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "launcher"))
sys.path.insert(0, str(ROOT / "converter"))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication  # noqa: E402

FAKE_GODOT = str(Path(__file__).with_name("fake_godot.py"))


@pytest.fixture(scope="session")
def qapp():
    app = QApplication.instance() or QApplication([])
    app.setProperty("headless_test", True)
    from openmwgodot_launcher import theme
    app.setStyleSheet(theme.QSS)
    return app


@pytest.fixture
def env(tmp_path, monkeypatch, qapp):
    for k, sub in (("XDG_CONFIG_HOME", "cfg"), ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"),
                   ("XDG_STATE_HOME", "state")):
        monkeypatch.setenv(k, str(tmp_path / sub))
    monkeypatch.delenv("XDG_RUNTIME_DIR", raising=False)
    monkeypatch.delenv("OPENMWGODOT_PORTABLE", raising=False)
    monkeypatch.setenv("FAKE_GODOT_LOG", str(tmp_path / "godot_calls.jsonl"))
    monkeypatch.setenv("MWGODOT_GODOT", FAKE_GODOT)
    qapp.setProperty("auto_confirm", True)
    qapp.setProperty("test_user_args", None)
    return tmp_path


@pytest.fixture(scope="session")
def synth_dir(tmp_path_factory):
    from mwconv.synthetic_world import write_world
    d = tmp_path_factory.mktemp("synth") / "Data Files"
    write_world(d)
    return d


@pytest.fixture
def fake_game(tmp_path, synth_dir):
    """Układ katalogów jak w grze: Morrowind/Data Files/Morrowind.esm + Morrowind.bsa + Morrowind.ini (dane syntetyczne)."""
    g = tmp_path / "Morrowind"
    shutil.copytree(synth_dir, g / "Data Files")
    (g / "Data Files" / "mwg_synthtown.esm").rename(g / "Data Files" / "Morrowind.esm")
    for p in (g / "Data Files").glob("mwg_synthtown_patch*.esp"):
        p.unlink()
    shutil.copy(g / "Data Files" / "synth.bsa", g / "Data Files" / "Morrowind.bsa")
    (g / "Morrowind.ini").write_text("[Archives]\n[Game Files]\nGameFile0=Morrowind.esm\n")
    return g


def tree_hash(root: Path) -> dict:
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob("*")) if p.is_file()}


def wait_until(app, cond, timeout=180.0):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        app.processEvents()
        if cond():
            return True
        time.sleep(0.02)
    return False
