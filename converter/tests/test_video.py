"""Filmy (start gry): Video/*.bik → video/*.ogv przez ffmpeg gracza – ścieżka aktualizacji, błędy, brak ffmpeg.
Zamiast prawdziwego ffmpeg – atrapa uruchamiająca (bez Binka z gry w repozytorium)."""

import json
import subprocess
from pathlib import Path

from mwconv import video
from mwconv.vfs import Vfs


class Fake:
    """Atrapa ffmpeg: -encoders → lista koderów; kodowanie → plik wyjściowy (albo błąd dla 'zly')."""
    def __init__(self, encoders=("libtheora", "libvorbis")):
        self.calls = []
        self.encoders = encoders

    def __call__(self, cmd, capture_output=True, text=True, timeout=None):
        self.calls.append(cmd)
        if "-encoders" in cmd:
            out = "\n".join(f" V..... {e}  opis" for e in self.encoders)
            return subprocess.CompletedProcess(cmd, 0, out, "")
        if cmd[-1].endswith(".ogv"):
            src = cmd[cmd.index("-i") + 1]
            if "zly" in src:
                return subprocess.CompletedProcess(cmd, 1, "", "Invalid data found when processing input")
            Path(cmd[-1]).write_bytes(b"OggS-fake")
            return subprocess.CompletedProcess(cmd, 0, "", "")
        return subprocess.CompletedProcess(cmd, 1, "", "  Stream #0:1: Audio: binkaudio_rdft, 44100 Hz")


def _data(tmp_path):
    d = tmp_path / "Data Files"
    (d / "Video").mkdir(parents=True)
    (d / "Video" / "mw_logo.bik").write_bytes(b"BIKi" + b"\0" * 64)
    (d / "Video" / "zly.bik").write_bytes(b"BIKi")
    return Vfs.from_install([str(d)], [])


def test_encode_update_and_errors(tmp_path, monkeypatch):
    vfs = _data(tmp_path)
    out = tmp_path / "out"
    fake = Fake()
    monkeypatch.setattr(video, "_encoders", lambda f: set(fake.encoders))
    r = video.convert_all(vfs, out, log=lambda m: None, ffmpeg="ffmpeg", runner=fake)
    assert r["found"] == 2 and r["encoded"] == 1 and len(r["failed"]) == 1
    assert (out / "video" / "mw_logo.ogv").read_bytes() == b"OggS-fake"
    assert not list((out / "video").glob("*.tmp.ogv"))            # zapis atomowy – bez resztek
    idx = json.loads((out / "video" / "index.json").read_text())
    assert idx["videos"]["video/mw_logo.bik"]["audio"] is True
    assert "error" in idx["videos"]["video/zly.bik"]
    # bez zmian w źródle – brak kodowania; błędny film próbowany ponownie
    fake.calls.clear()
    r2 = video.convert_all(vfs, out, log=lambda m: None, ffmpeg="ffmpeg", runner=fake)
    assert r2["unchanged"] == 1 and r2["encoded"] == 0
    assert not any("mw_logo.bik" in " ".join(c) and c[-1].endswith(".ogv") for c in fake.calls)
    # usunięty wynik → ponowne kodowanie
    (out / "video" / "mw_logo.ogv").unlink()
    r3 = video.convert_all(vfs, out, log=lambda m: None, ffmpeg="ffmpeg", runner=fake)
    assert r3["encoded"] == 1


def test_missing_ffmpeg_or_encoders(tmp_path, monkeypatch):
    vfs = _data(tmp_path)
    out = tmp_path / "out"
    monkeypatch.setattr(video, "find_ffmpeg", lambda: None)
    r = video.convert_all(vfs, out, log=lambda m: None)
    assert "ffmpeg" in r["error"] and r["encoded"] == 0
    assert "error" in json.loads((out / "video" / "index.json").read_text())
    monkeypatch.setattr(video, "_encoders", lambda f: {"libvorbis"})
    r = video.convert_all(vfs, out, log=lambda m: None, ffmpeg="ffmpeg", runner=Fake())
    assert "libtheora" in r["error"]


def test_out_name():
    assert video.out_name("video/Bethesda Logo.bik") == "video/bethesda logo.ogv"
