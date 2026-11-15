"""ESM/ESP, LAND, BSA, kolejność ładowania i stabilne identyfikatory."""

import json

import numpy as np
import pytest

from mwconv.esm.reader import decode_heights, encode_heights, read_esm, transpose_vtex, untranspose_vtex
from mwconv.synthetic_world import heights_for
from mwconv.vfs import BsaArchive, Vfs, tes3_hash, write_bsa
from mwconv.world import cell_to_json, load_world, select_cells


def test_heights_roundtrip():
    h = heights_for((0, 0))
    assert decode_heights(encode_heights(h)) == pytest.approx(h)


def test_vtex_transpose_roundtrip():
    g = np.arange(256, dtype=np.uint16).reshape(16, 16)
    assert (transpose_vtex(untranspose_vtex(g)) == g).all()
    raw = np.arange(256, dtype=np.uint16)
    t = transpose_vtex(raw)
    # pierwszy blok 4×4 surowych danych to lewy dolny róg siatki
    assert t[0, :4].tolist() == [0, 1, 2, 3] and t[1, :4].tolist() == [4, 5, 6, 7] and t[0, 4] == 16


def test_bsa_roundtrip(tmp_path):
    p = tmp_path / "a.bsa"
    write_bsa(p, {"meshes\\a\\b.nif": b"abc", "textures\\t.dds": b"x" * 100})
    arc = BsaArchive(p)
    assert arc.read("meshes/a/b.nif") == b"abc"
    assert arc.read("TEXTURES\\T.DDS") == b"x" * 100
    assert tes3_hash("meshes\\a\\b.nif") == tes3_hash("MESHES/A/B.NIF")


def test_load_order_merge(synth_data):
    d = synth_data["dir"]
    w = load_world([d / "mwg_synthtown.esm", d / "mwg_synthtown_patch.esp"])
    lay = synth_data["layout"]
    c01 = w.cells["ext:0,1"]
    hut0 = c01.refs[f"mwg_synthtown.esm#{lay['hut0']}"]
    assert hut0.source == "mwg_synthtown_patch.esp"           # nadpisana przez plugin
    assert hut0.ref.pos[0] == pytest.approx(1400)
    assert hut0.ref.scale == pytest.approx(1.2)
    assert "mwg_synthtown_patch.esp#1" in c01.refs              # nowa referencja pluginu
    assert f"mwg_synthtown.esm#{lay['crate2']}" not in w.cells["ext:0,0"].refs  # usunięta
    sid5 = f"mwg_synthtown.esm#{lay['crate5']}"
    assert sid5 not in w.cells["ext:1,0"].refs and sid5 in w.cells["ext:1,1"].refs  # przeniesiona
    ld, _ltex, src = w.lands[(1, 1)]
    assert src == "mwg_synthtown_patch.esp"
    assert ld.heights[32, 32] > heights_for((1, 1))[32, 32]


def test_master_only_and_selection(synth_data):
    d = synth_data["dir"]
    w = load_world([d / "mwg_synthtown.esm"])
    keys = select_cells(w, ["Synthville"])
    assert "int:synthville, test house" in keys and len(keys) == 5
    j = cell_to_json(w.cells["ext:0,1"], w)
    door = [r for r in j["refs"] if r["base"] == "synth_door"][0]
    assert door["extra"]["door_dest_cell"] == "Synthville, Test House"
    assert "godot" in door["extra"]["door_dest"]


def test_vfs_priority_and_texture_resolution(synth_data, tmp_path):
    d = synth_data["dir"]
    v = Vfs.from_install([str(d)], [str(d / "synth.bsa")])
    assert v.info("meshes/synth/bsa_crate.nif").kind == "bsa"
    assert v.resolve_texture("tx_synth_planks.tga") == "textures/tx_synth_planks.dds"
    assert v.resolve_texture("Textures\\TX_SYNTH_PLANKS.TGA") == "textures/tx_synth_planks.dds"
    # luźny plik ma pierwszeństwo przed BSA
    (d / "meshes" / "synth" / "bsa_crate.nif").write_bytes(b"loose")
    v2 = Vfs.from_install([str(d)], [str(d / "synth.bsa")])
    assert v2.info("meshes/synth/bsa_crate.nif").kind == "dir"
    (d / "meshes" / "synth" / "bsa_crate.nif").unlink()
