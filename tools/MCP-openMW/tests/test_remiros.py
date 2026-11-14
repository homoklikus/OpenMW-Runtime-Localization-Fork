"""Etap 2c: reguły Remirosa, mapa liczników, generator (Python) i zgodność z rdzeniem C++ — dane syntetyczne."""

from __future__ import annotations

import shutil
import struct
import subprocess
from pathlib import Path

import pytest

from conftest import esp_bytes, rec, w
from openmw_mcp import gcbaseline, land, remirosrules as RR
from openmw_mcp.land import LandIndex

N = 65
CPP = Path(__file__).resolve().parents[1] / "cpp"


def vhgt(height: float, bump: tuple[int, int, int] | None = None) -> bytes:
    deltas = bytearray(N * N)
    if bump:
        x, y, d = bump
        deltas[y * N + x] = d & 0xFF
        if x + 1 < N:
            deltas[y * N + x + 1] = (-d) & 0xFF
    return struct.pack("<f", height / 8.0) + bytes(deltas) + b"\0\0\0"


def vtex(grid: list[int]) -> bytes:
    raw = []
    for y1 in range(4):
        for x1 in range(4):
            for y2 in range(4):
                for x2 in range(4):
                    raw.append(grid[(y1 * 4 + y2) * 16 + x1 * 4 + x2])
    return struct.pack("<256H", *raw)


def make_world(tmp_path: Path, height=100.0, center_grid=None, bump=None) -> Path:
    """3×3 komórek; środkowa: lewa połowa tekseli = trawa (LTEX 0), prawa = skała (LTEX 1); pozostałe = skała."""
    body = rec("LTEX", [("NAME", b"g\0"), ("INTV", struct.pack("<I", 0)), ("DATA", b"Tx_Grass_A.tga\0")])
    body += rec("LTEX", [("NAME", b"r\0"), ("INTV", struct.pack("<I", 1)), ("DATA", b"tx_rock_b.tga\0")])
    grass_left = center_grid or [1 if (i % 16) < 8 else 2 for i in range(256)]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            grid = grass_left if (dx, dy) == (0, 0) else [2] * 256
            body += rec("LAND", [("INTV", struct.pack("<ii", dx, dy)), ("DATA", struct.pack("<I", 9)),
                                 ("VHGT", vhgt(height, bump if (dx, dy) == (0, 0) else None)), ("VTEX", vtex(grid))])
    return w(tmp_path / "W.esm", esp_bytes() + body)


def remiros_plugin(tmp_path: Path, per_texel: int = 4, skip_texels=(), height=100.0) -> Path:
    """Plugin groundcover: per_texel referencji na każdym tekselu trawy środkowej komórki (pozycje w tekselu)."""
    s = [("NAME", b"\0"), ("DATA", struct.pack("<Iii", 0, 0, 0))]
    refnum = 0
    for ty in range(16):
        for tx in range(8):
            if (tx, ty) in skip_texels:
                continue
            for k in range(per_texel):
                refnum += 1
                x = (tx + 0.2 + 0.15 * k) * 512.0
                y = (ty + 0.3 + 0.1 * k) * 512.0
                s += [("FRMR", struct.pack("<I", refnum)), ("NAME", b"grs_tx_grass_a.tga0\0"),
                      ("XSCL", struct.pack("<f", 1.2 + 0.05 * k)),
                      ("DATA", struct.pack("<6f", x, y, height + 23.0, 0, 0, 0))]
    body = rec("STAT", [("NAME", b"grs_tx_grass_a.tga0\0"), ("MODL", b"grass\\rem_a.nif\0")])
    return w(tmp_path / "Rem_X.esp", esp_bytes() + body + rec("CELL", s))


def load(tmp_path, **kw):
    li = LandIndex.load([make_world(tmp_path, **{k: v for k, v in kw.items() if k in ("height", "center_grid", "bump")})])
    gc = gcbaseline.GroundcoverIndex.load([remiros_plugin(tmp_path, **{k: v for k, v in kw.items()
                                                                        if k in ("per_texel", "skip_texels")})])
    return li, gc


def per_texel(instances):
    out = {}
    for i in instances:
        k = (int(i["x"] // 512), int(i["y"] // 512))
        out[k] = out.get(k, 0) + 1
    return out


def test_heights_and_land_hash(tmp_path):
    raw = vhgt(100.0, (5, 7, 3))
    assert RR.heights_f32(raw) == pytest.approx(land.decode_vhgt(raw))
    h1 = RR.land_hash(RR.heights_f32(raw))
    assert h1 == RR.land_hash(RR.heights_f32(raw))
    assert h1 != RR.land_hash(RR.heights_f32(vhgt(100.0, (5, 7, 4))))
    assert RR.texture_key("Textures\\Tx_Grass_A.TGA") == "tx_grass_a" and RR.texture_key(None) == ""


def test_derive_rules(tmp_path):
    li, gc = load(tmp_path)
    rules = RR.derive(gc, li)
    assert rules["textures"] == 1 and rules["refs"] == 128 * 4
    r = rules["rules"][0]
    assert r["texture"] == "tx_grass_a" and r["texels_above_water"] == 128 and r["density_per_texel"] == 4.0
    st = r["statics"][0]
    assert st["model"] == "rem_a.nif" and st["share"] == 1.0 and st["z_offset"] == 23.0
    assert st["scale_min"] == pytest.approx(1.2) and st["scale_max"] == pytest.approx(1.35)


def test_counts_reproduce_texels_and_cutouts(tmp_path):
    cut = {(2, 3), (2, 4), (5, 9)}
    li, gc = load(tmp_path, skip_texels=cut)
    rules = RR.derive(gc, li)
    counts = RR.build_counts(gc, li, rules)
    m = RR.Model(rules, counts)
    r = RR.generate_cell(li, m, 0, 0, 1.0, None, True)
    assert r["mode"] == "counts" and r["instances"] == 4 * (128 - len(cut))
    got = per_texel(r["instance_list"])
    assert all(got.get(t, 0) == 0 for t in cut)
    assert all(got.get((tx, ty), 0) == 4 for tx in range(8) for ty in range(16) if (tx, ty) not in cut)
    assert not any(tx >= 8 for tx, _ in got)                      # skała: 0
    assert {i["model"] for i in r["instance_list"]} == {"rem_a.nif"}
    assert all(abs(i["z"] - 123.0) < 1e-3 for i in r["instance_list"])
    # gęstość 0.5 ⇒ połowa (deterministycznie: 2 na teksel)
    assert RR.generate_cell(li, m, 0, 0, 0.5)["instances"] == 2 * (128 - len(cut))
    # same reguły: wycięcia znikają (≈ 4 na teksel trawy, z rozrzutem ±0,3 teksela)
    rr = RR.generate_cell(li, m, 0, 0, 1.0, None, False, use_counts=False)
    assert rr["mode"] == "rules" and rr["instances"] > 4 * (128 - len(cut))


def test_fallback_on_modified_terrain_and_texture(tmp_path):
    li, gc = load(tmp_path)
    rules = RR.derive(gc, li)
    counts = RR.build_counts(gc, li, rules)
    # teren zmieniony (inny odcisk wysokości) ⇒ cała komórka na regułach
    li2 = LandIndex.load([make_world(tmp_path / "m", bump=(10, 10, 2))])
    r = RR.generate_cell(li2, RR.Model(rules, counts), 0, 0)
    assert r["mode"] == "rules (inny teren)" and r["texel_sources"].get("counts", 0) == 0
    # jeden teksel z inną teksturą (trawa → skała) ⇒ ten teksel bez roślin z liczników, reszta liczniki
    grid = [1 if (i % 16) < 8 else 2 for i in range(256)]
    grid[3 * 16 + 1] = 2
    li3 = LandIndex.load([make_world(tmp_path / "t", center_grid=grid)])
    r3 = RR.generate_cell(li3, RR.Model(rules, counts), 0, 0, 1.0, None, True)
    assert r3["mode"] == "counts" and r3["texel_sources"]["counts"] == 127
    assert per_texel(r3["instance_list"]).get((1, 3), 0) == 0


def test_underwater_and_missing_models(tmp_path):
    li, gc = load(tmp_path)
    rules = RR.derive(gc, li)
    counts = RR.build_counts(gc, li, rules)
    wet = LandIndex.load([make_world(tmp_path / "w", height=-100.0)])
    assert RR.generate_cell(wet, RR.Model(rules, None), 0, 0)["instances"] == 0
    assert RR.Model(rules, counts, pool=["meshes/grass/inny.nif"]).rules == {}
    assert RR.Model(rules, counts, pool=["meshes/grass/rem_a.nif"]).rules["tx_grass_a"][1][0][1] == "meshes/grass/rem_a.nif"


@pytest.mark.skipif(shutil.which("g++") is None, reason="brak g++")
def test_cpp_core_matches_python(tmp_path):
    li, gc = load(tmp_path, skip_texels={(1, 1)})
    rules = RR.derive(gc, li)
    counts = RR.build_counts(gc, li, rules)
    for name, text in RR.emit_cpp_files(rules, counts, {"version": "test", "tree_sha256": "test"}).items():
        (tmp_path / name).write_text(text, encoding="utf-8")
    cells = [(x, y) for x in (-1, 0, 1) for y in (-1, 0, 1)]
    (tmp_path / "teren.txt").write_text(RR.terrain_dump(li, cells))
    exe = tmp_path / "harness"
    subprocess.run(["g++", "-std=c++20", "-O1", "-Wall", "-Wextra", "-Werror", f"-I{CPP}", f"-I{tmp_path}",
                    str(CPP / "remiros_harness.cpp"), str(tmp_path / "remirosgroundcoverdata.cpp"), "-o", str(exe)],
                   check=True, capture_output=True)
    out = subprocess.run([str(exe), str(tmp_path / "teren.txt"), "1.0", "0,0", "-1,0"],
                         check=True, capture_output=True, text=True).stdout
    m = RR.Model(rules, counts)
    lines = []
    for x, y in ((0, 0), (-1, 0)):
        r = RR.generate_cell(li, m, x, y, 1.0, (x * 8192.0, y * 8192.0, (x + 1) * 8192.0, (y + 1) * 8192.0), True)
        lines += [f'{x} {y} {i["model"]} {i["x"]:.9g} {i["y"]:.9g} {i["z"]:.9g} {i["scale"]:.9g} {i["rot_z"]:.9g}'
                  for i in r.get("instance_list", [])]
    assert out == "\n".join(lines) + "\n" and len(lines) == 4 * 127


def test_server_remiros_tools(project, monkeypatch):
    import asyncio
    import inspect
    from openmw_mcp import server
    monkeypatch.setattr(server, "_ENV", project["env"])
    server._WORLD_CACHE.clear()
    lt = server.mcp.list_tools()
    names = {t.name for t in (asyncio.run(lt) if inspect.iscoroutine(lt) else lt)}
    assert {"openmw_remiros_rules", "openmw_remiros_compare", "openmw_remiros_export"} <= names
    assert server._pach75_state() == {"in_source": False, "in_binary": False}
    r = server.openmw_remiros_rules()
    assert "error" not in r and r["counts"]["cells"] == 0          # syntetyczny projekt: brak LAND
    gm = server.openmw_groundcover_mode("fork-test")
    assert gm["remiros_texture_rules"] == {"in_source": False, "in_binary": False}
