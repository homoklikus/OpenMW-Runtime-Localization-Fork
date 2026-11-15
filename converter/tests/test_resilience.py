"""Odporność konwersji: anulowanie i wznowienie, blokada, uszkodzony cache, weryfikacja/naprawa, czyszczenie,
nakładka profilu na współdzieloną bazę."""

import json
import os
import shutil
import signal
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

import pytest

from mwconv.install import InstallConfig
from mwconv.maintenance import clean, verify
from mwconv.pipeline import ConversionLocked, Options, acquire_lock, run
from mwconv.synthetic import make_crate, make_hut, make_windmill

ROOT = Path(__file__).resolve().parents[1]


def _cfg(d, extra_dirs=()):
    return InstallConfig(data_dirs=[str(d), *map(str, extra_dirs)], archives=[str(d / "synth.bsa")],
                         content=[str(d / "mwg_synthtown.esm"), str(d / "mwg_synthtown_patch.esp")])


def _many_models(d: Path, n: int):
    blobs = [make_hut(), make_windmill(), make_crate()]
    for i in range(n):
        p = d / "meshes" / "many" / f"m{i:04d}.nif"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(blobs[i % 3])


def test_cancel_and_resume(synth_data, tmp_path):
    src = tmp_path / "Data Files"
    shutil.copytree(synth_data["dir"], src)
    _many_models(src, 600)
    out = tmp_path / "out"
    cmd = [sys.executable, "-m", "mwconv", "convert", "--data", str(src), "--archive", str(src / "synth.bsa"),
           "--content", "mwg_synthtown.esm", "--cell", "Synthville", "--all-models", "--jobs", "2",
           "--out", str(out), "--progress-json"]
    p = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sent = False
    events = []
    for line in p.stdout:
        if line.startswith("MWPROGRESS "):
            ev = json.loads(line[11:])
            events.append(ev)
            if not sent and ev.get("event") == "progress" and ev.get("stage") == "models" and ev["done"] >= 20:
                p.send_signal(signal.SIGTERM)
                sent = True
    code = p.wait(60)
    assert sent and code == 130
    assert any(e["event"] == "cancelled" for e in events)
    assert not (out / ".mwconv" / "convert.lock").exists()
    assert not (out / ".mwconv" / "export_state.json").exists()
    db = sqlite3.connect(out / ".mwconv" / "cache.sqlite")
    done = db.execute("SELECT count(*) FROM assets WHERE kind='model' AND status='ok'").fetchone()[0]
    db.close()
    assert 20 <= done < 609
    assert not list(out.rglob("*.tmp"))  # brak częściowych plików
    # wznowienie: konwertuje tylko resztę
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=300)
    assert r.returncode == 0, r.stdout[-2000:]
    stats = json.loads((out / "reports" / "conversion.json").read_text())["stats"]
    assert stats["models"]["converted"] == stats["models"]["needed"] - done
    assert stats["models"]["skipped_unchanged"] == done
    assert verify(out, deep=True)["ok"]


def test_lock_prevents_parallel_runs(tmp_path):
    out = tmp_path / "o"
    lock = out / ".mwconv" / "convert.lock"
    lock.parent.mkdir(parents=True)
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        lock.write_text(json.dumps({"pid": child.pid, "started": time.time()}))
        with pytest.raises(ConversionLocked):
            acquire_lock(out)
    finally:
        child.kill()
        child.wait()
    acquire_lock(out)  # martwa blokada przejęta
    assert json.loads(lock.read_text())["pid"] == os.getpid()


def test_corrupt_cache_and_outputs_repair(synth_data, tmp_path):
    src = synth_data["dir"]
    out = tmp_path / "out"
    opts = Options(out=out, cells=["Synthville"], jobs=1)
    run(_cfg(src), opts, log=lambda _m: None)
    # uszkodzony plik wynikowy → verify wykrywa i oznacza, convert naprawia tylko ten zasób
    glb = out / "meshes" / "synth" / "test_hut.glb"
    glb.write_bytes(glb.read_bytes()[:100])
    v = verify(out, deep=True)
    assert not v["ok"] and [b["key"] for b in v["bad"]] == ["meshes/synth/test_hut.nif"]
    s = run(_cfg(src), opts, log=lambda _m: None)
    assert s["models"]["converted"] == 1
    assert verify(out, deep=True)["ok"]
    # uszkodzona baza cache → odtworzona, wszystko zweryfikowane ponownie, bez wyjątku
    db = out / ".mwconv" / "cache.sqlite"
    for side in ("-wal", "-shm"):
        Path(str(db) + side).unlink(missing_ok=True)
    db.write_bytes(b"to nie jest baza sqlite" * 100)
    s = run(_cfg(src), opts, log=lambda _m: None)
    assert s["models"]["ok"] == s["models"]["needed"]
    assert list((out / ".mwconv").glob("cache.sqlite.corrupt-*"))
    # uszkodzony eksport świata → verify unieważnia stan, convert eksportuje ponownie
    (out / "world" / "index.json").write_text("{zepsute")
    assert not verify(out)["world_ok"]
    s = run(_cfg(src), opts, log=lambda _m: None)
    assert not s["world_load"].get("skipped")
    assert verify(out, deep=True)["ok"]


def test_clean_requires_confirmation(synth_data, tmp_path):
    out = tmp_path / "out"
    run(_cfg(synth_data["dir"]), Options(out=out, cells=["Synthville"], jobs=1), log=lambda _m: None)
    junk = out / "meshes" / "old" / "stary_model.glb"
    junk.parent.mkdir(parents=True)
    junk.write_bytes(b"x")
    (out / "textures" / "half.png.tmp").write_bytes(b"x")
    r = clean(out)
    assert "meshes/old/stary_model.glb" in r["orphans"] and junk.exists()  # bez --yes nic nie usuwa
    r = clean(out, yes=True)
    assert not junk.exists() and r["freed_bytes"] >= 2
    assert verify(out, deep=True)["ok"]  # używane pliki nietknięte


def test_profile_overlay_on_shared_base(synth_data, tmp_path):
    src = synth_data["dir"]
    base = tmp_path / "base"
    run(_cfg(src), Options(out=base, cells=["Synthville"], jobs=1), log=lambda _m: None)
    # „mod”: osobny katalog danych z podmienioną teksturą i nowym modelem skrzynki
    mod = tmp_path / "mod" / "Data Files"
    (mod / "textures").mkdir(parents=True)
    (mod / "meshes" / "synth").mkdir(parents=True)
    shutil.copy(src / "textures" / "tx_synth_roof.dds", mod / "textures" / "tx_synth_planks.dds")
    (mod / "meshes" / "synth" / "test_crate.nif").write_bytes(make_windmill())
    over = tmp_path / "profile"
    s = run(_cfg(src, [mod]), Options(out=over, cells=["Synthville"], jobs=1, base_out=base), log=lambda _m: None)
    assert s["models"]["converted"] == 1 and s["models"]["from_base"] >= 7  # tylko podmieniony model
    assert s["textures"]["converted"] == 1  # tylko podmieniona tekstura
    assert not (over / "meshes" / "synth" / "test_hut.glb").exists()  # brak kopii zasobów bazy
    # model z nakładki odwołuje się do tekstur bazy względną ścieżką, która istnieje
    from mwconv.gltf import read_glb
    doc, _ = read_glb((over / "meshes" / "synth" / "test_crate.glb").read_bytes())
    for im in doc["images"]:
        target = (over / "meshes" / "synth" / im["uri"]).resolve()
        assert target.exists(), im["uri"]
    assert (over / "world" / "index.json").exists()


def test_duplicate_texture_sources_and_png_crc(synth_data, tmp_path):
    """Regresja (pełna gra): tx.dds i tx.tga → ten sam tx.png pisany równolegle = sklejony PNG z błędem CRC."""
    from mwconv.textures import dedupe_textures
    keys = {"textures/tx_a.dds", "textures/tx_a.tga", "textures/TX_B.tga", "textures/tx_b.bmp", "textures/c.tga"}
    assert dedupe_textures(keys) == {"textures/tx_a.dds", "textures/TX_B.tga", "textures/c.tga"}
    src = synth_data["dir"]
    out = tmp_path / "out"
    opts = Options(out=out, cells=["Synthville"], jobs=1)
    run(_cfg(src), opts, log=lambda _m: None)
    png = next((out / "textures").rglob("*.png"))
    b = bytearray(png.read_bytes())
    b[len(b) // 2] ^= 0xFF  # uszkodzenie danych IDAT przy zachowanej długości i sygnaturze
    png.write_bytes(bytes(b))
    v = verify(out, deep=True)
    assert not v["ok"] and any("CRC" in x["problem"] for x in v["bad"])
    s = run(_cfg(src), opts, log=lambda _m: None)
    assert s["textures"]["converted"] == 1 and verify(out, deep=True)["ok"]
    assert not list(out.rglob("*.tmp.png"))


def test_glb_texture_refs_for_rebake(synth_data, tmp_path):
    """Wypiekanie musi się powtórzyć po naprawie tekstury – GLB zna swoje tekstury (images[].uri)."""
    from mwconv.pipeline import _glb_textures
    src = synth_data["dir"]
    out = tmp_path / "out"
    run(_cfg(src), Options(out=out, cells=["Synthville"], jobs=1), log=lambda _m: None)
    texs = _glb_textures(out / "meshes" / "synth" / "test_hut.glb")
    assert texs and all(t.exists() and t.suffix == ".png" and (out / "textures") in t.parents for t in texs)
