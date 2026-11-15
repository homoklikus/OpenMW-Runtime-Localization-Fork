"""Konwersja przyrostowa, wznowienie, raport."""

import json
import os
import shutil

from mwconv.install import InstallConfig
from mwconv.pipeline import Options, run


def _cfg(d):
    return InstallConfig(data_dirs=[str(d)], archives=[str(d / "synth.bsa")],
                         content=[str(d / "mwg_synthtown.esm"), str(d / "mwg_synthtown_patch.esp")])


def test_incremental_and_resume(synth_data, tmp_path):
    src = tmp_path / "Data Files"
    shutil.copytree(synth_data["dir"], src)
    out = tmp_path / "out"
    opts = Options(out=out, cells=["Synthville"], jobs=1)
    s1 = run(_cfg(src), opts, log=lambda _m: None)
    assert s1["models"]["ok"] == 9 and s1["models"]["errors"] == 0
    assert s1["textures"]["ok"] == 8
    # drugi przebieg: nic do zrobienia
    s2 = run(_cfg(src), opts, log=lambda _m: None)
    assert s2["models"]["skipped_unchanged"] == 9 and "converted" not in s2["models"]
    # zmiana mtime bez zmiany treści → SHA-256 potwierdza brak zmian
    nif = src / "meshes" / "synth" / "test_crate.nif"
    os.utime(nif, (1, 1))
    s3 = run(_cfg(src), opts, log=lambda _m: None)
    assert "converted" not in s3["models"]
    # zmiana treści → konwersja jednego modelu
    from mwconv.synthetic import make_windmill
    (src / "meshes" / "synth" / "test_crate.nif").write_bytes(make_windmill())
    s4 = run(_cfg(src), opts, log=lambda _m: None)
    assert s4["models"]["converted"] == 1
    # „przerwana” konwersja: brak pliku wynikowego → odtworzenie tylko jego
    (out / "meshes" / "synth" / "test_hut.glb").unlink()
    s5 = run(_cfg(src), opts, log=lambda _m: None)
    assert s5["models"]["converted"] == 1
    assert s5["world_load"].get("skipped") is True  # ESM/ESP bez zmian ⇒ bez ponownego eksportu świata
    rep = json.loads((out / "reports" / "conversion.json").read_text())
    assert rep["stats"]["world_export"]["cells"] == 5
    # zmiana pluginu ⇒ pełny eksport świata
    esp = src / "mwg_synthtown_patch.esp"
    esp.write_bytes(esp.read_bytes())  # ta sama treść: nadal bez zmian
    assert run(_cfg(src), opts, log=lambda _m: None)["world_load"].get("skipped") is True
    from mwconv.synthetic_world import write_patch2
    write_patch2(src)
    cfg = _cfg(src)
    cfg.content.append(str(src / "mwg_synthtown_patch2.esp"))
    s6 = run(cfg, opts, log=lambda _m: None)
    assert not s6["world_load"].get("skipped") and s6["world_export"]["cells"] == 5
    terrain = json.loads((out / "world" / "terrain" / "0_0.json").read_text())
    assert terrain["texture_palette"] and terrain["heights_f32_b64"]
