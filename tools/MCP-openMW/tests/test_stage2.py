"""Etap 2: teren (LAND/LTEX) i offline emulacja oficjalnego Groundcover — dane syntetyczne."""

from __future__ import annotations

import math
import struct

import pytest

from conftest import esp_bytes, rec, w
from openmw_mcp import gcbaseline, land
from openmw_mcp.land import LandIndex, _Land

N = land.LAND_SIZE


def vhgt(offset: float, deltas: list[int]) -> bytes:
    return struct.pack("<f", offset) + struct.pack(f"<{N * N}b", *deltas) + b"\0\0\0"


def raw_from_grid(grid: list[int]) -> bytes:
    """Odwrotność transpose_vtex: siatka [ty*16+tx] → zapis blokami 4×4 jak w ESM."""
    raw = []
    for y1 in range(4):
        for x1 in range(4):
            for y2 in range(4):
                for x2 in range(4):
                    raw.append(grid[(y1 * 4 + y2) * 16 + x1 * 4 + x2])
    return struct.pack("<256H", *raw)


def ltex(lid: str, index: int, tex: str) -> bytes:
    return rec("LTEX", [("NAME", lid.encode() + b"\0"), ("INTV", struct.pack("<I", index)), ("DATA", tex.encode() + b"\0")])


def land_rec(x: int, y: int, heights: bytes | None = None, vtex: bytes | None = None) -> bytes:
    s = [("INTV", struct.pack("<ii", x, y)), ("DATA", struct.pack("<I", 9))]
    if heights is not None:
        s.append(("VHGT", heights))
    if vtex is not None:
        s.append(("VTEX", vtex))
    return rec("LAND", s)


def linear_deltas() -> list[int]:
    # offset 10, każda delta 1 ⇒ h(x, y) = (11 + x + y) · 8
    return [1] * (N * N)


def test_decode_vhgt_accumulation():
    h = land.decode_vhgt(vhgt(10.0, linear_deltas()))
    assert h[0] == 88.0
    assert h[5 * N + 7] == (11 + 7 + 5) * 8
    assert h[N * N - 1] == (11 + 64 + 64) * 8


def test_transpose_vtex_blocks():
    out = land.transpose_vtex(tuple(range(256)))
    assert out[0] == 0
    assert out[4] == 16          # (x=4, y=0): blok x1=1
    assert out[16] == 4          # (x=0, y=1): y2=1 w pierwszym bloku
    assert sorted(out) == list(range(256))
    grid = [(i * 7) % 256 for i in range(256)]
    assert land.transpose_vtex(struct.unpack("<256H", raw_from_grid(grid))) == grid


def test_ltex_per_plugin_and_land_override(tmp_path):
    a = w(tmp_path / "A.esm", esp_bytes() + ltex("a", 0, "a.dds") + land_rec(0, 0, vtex=raw_from_grid([1] * 256)))
    b = w(tmp_path / "B.esp", esp_bytes() + ltex("b", 0, "b.dds") + land_rec(1, 0, vtex=raw_from_grid([1] * 256)))
    c = w(tmp_path / "C.esp", esp_bytes() + ltex("a", 5, "a_new.dds") + land_rec(0, 1, vtex=raw_from_grid([0] * 256)))
    li = LandIndex.load([a, b, c])
    # ten sam indeks 0 w różnych pluginach → różne tekstury
    assert li.texture_at(100, 100) == "a_new.dds"       # ID 'a' nadpisane przez C.esp (później wygrywa)
    assert li.texture_at(8192 + 100, 100) == "b.dds"
    assert li.texture_at(100, 8192 + 100) == land.DEFAULT_TEXTURE
    d = w(tmp_path / "D.esp", esp_bytes() + land_rec(0, 0, vtex=raw_from_grid([0] * 256)))
    li2 = LandIndex.load([a, b, c, d])
    assert li2.texture_at(100, 100) == land.DEFAULT_TEXTURE
    assert li2.cell_summary(0, 0)["overridden_by_load_order"] == ["A.esm", "D.esp"]
    assert li2.cell_summary(0, 0)["file"] == "D.esp"


def test_height_and_slope_on_plane(tmp_path):
    f = w(tmp_path / "A.esm", esp_bytes() + land_rec(0, 0, heights=vhgt(10.0, linear_deltas())))
    li = LandIndex.load([f])
    for wx, wy in ((0.0, 0.0), (1000.5, 333.25), (5000.0, 7000.0)):
        assert li.height_at(wx, wy) == pytest.approx((11 + wx / 128 + wy / 128) * 8)
    s = li.slope_at(4000, 4000)
    assert s == pytest.approx(math.degrees(math.atan(math.hypot(1 / 16, 1 / 16))))
    assert li.height_at(-10, 0) is None


def _single_bump(ix: int, iy: int, value: float) -> LandIndex:
    hs = [0.0] * (N * N)
    hs[iy * N + ix] = value
    li = LandIndex()
    li.lands[(0, 0)] = _Land(0, "X.esm", None, None, _heights=hs)
    return li


def test_diamond_triangulation_even_and_odd_quads():
    # parzysty kwadrat (0,0): przekątna v0–v2; punkt (0.75, 0.25) leży w trójkącie (v0, v1, v2) ⇒ 100·(x−y) = 50
    li = _single_bump(1, 0, 100.0)
    assert li.height_at(0.75 * 128, 0.25 * 128) == pytest.approx(50.0)
    # nieparzysty kwadrat (1,0): przekątna v1–v3; bump w v1=(2,0); punkt (0.75, 0.25) ⇒ trójkąt (v1, v2, v3) ⇒ 75
    li = _single_bump(2, 0, 100.0)
    assert li.height_at(1.75 * 128, 0.25 * 128) == pytest.approx(75.0)
    # ten sam punkt przy jednej przekątnej v0–v2 dałby 50 — rozróżnienie jest mierzalne
    assert li.height_at(1.25 * 128, 0.75 * 128) == pytest.approx(25.0)


def test_texture_modes_and_wrap(tmp_path):
    texs = b"".join(ltex(f"t{i}", i, f"t{i}.dds") for i in range(16))
    grid = [(i % 16) + 1 for i in range(256)]           # kolumna tx → t{tx}
    f = w(tmp_path / "A.esm", esp_bytes() + texs + land_rec(0, 0, vtex=raw_from_grid(grid)))
    li = LandIndex.load([f])
    texel = 8192 / 16
    assert li.texture_at(4.1 * texel, 100, "fork") == "t4.dds"
    assert li.texture_at(4.1 * texel, 100, "render") == "t3.dds"
    assert li.texture_at(4.3 * texel, 100, "render") == "t4.dds"
    assert li.texture_at(0.1 * texel, 100, "render") is None   # przechodzi do komórki (−1,0), której brak
    assert li.texture_grid(0, 0)[0][15] == "t15.dds"
    with pytest.raises(ValueError):
        li.texture_at(1, 1, "inne")


def test_density_calculator_float32():
    c = gcbaseline.DensityCalculator(0.5)
    assert [c.enabled() for _ in range(6)] == [False, True, False, True, False, True]
    c = gcbaseline.DensityCalculator(0.25)
    assert sum(c.enabled() for _ in range(100)) == 25
    c = gcbaseline.DensityCalculator(1.0)
    assert all(c.enabled() for _ in range(10))
    assert gcbaseline._f32(0.1) != 0.1


def _gc_plugin(statics, refs, deleted=()):
    """refs: (refnum, id, x, y); deleted: zbiór refnum z DELE."""
    s = [("NAME", b"\0"), ("DATA", struct.pack("<Iii", 0, 15, -9))]
    for refnum, rid, x, y in refs:
        s += [("FRMR", struct.pack("<I", refnum)), ("NAME", rid.encode() + b"\0"),
              ("XSCL", struct.pack("<f", 1.5)), ("DATA", struct.pack("<6f", x, y, 0, 0, 0, 0))]
        if refnum in deleted:
            s.append(("DELE", struct.pack("<I", 0)))
    out = esp_bytes()
    for sid, model in statics:
        out += rec("STAT", [("NAME", sid.encode() + b"\0"), ("MODL", model.encode() + b"\0")])
    return out + rec("CELL", s)


def test_groundcover_instances_like_engine(tmp_path):
    x0, y0 = 15 * 8192, -9 * 8192
    a = w(tmp_path / "Rem_AC.esp", _gc_plugin([("g1", "Grass\\A.nif")],
                                              [(1, "g1", x0 + 10, y0 + 10), (2, "g1", x0 + 8200, y0 + 10),
                                               (3, "g1", x0 + 20, y0 + 20), (4, "nieznany", x0 + 30, y0 + 30)],
                                              deleted={3}))
    b = w(tmp_path / "Rem_WG.esp", _gc_plugin([("g2", "grass\\b.nif")], [(1, "g2", x0 + 40, y0 + 40)]))
    gc = gcbaseline.GroundcoverIndex.load([a, b])
    inst = gc.instances(15, -9, 1.0)
    # refnum 1 w dwóch plikach nie koliduje; usunięty (3) i bez modelu (4) pominięte; poza komórką (2) liczony
    assert len(inst) == 3
    assert {i["model"] for i in inst} == {"grass/a.nif", "grass/b.nif"}
    res = gcbaseline.baseline_cell(gc, None, 15, -9, 1.0)
    assert res["instances"] == 3 and res["position_outside_cell"] == 1
    assert res["by_plugin"] == {"Rem_AC.esp": 2, "Rem_WG.esp": 1}
    assert res["scale"]["mean"] == 1.5
    # gęstość 0.5: kalkulator pomija usunięte, ale liczy referencje bez modelu (jak silnik):
    # kolejność 1a(F) 2a(T) 4a(F, bez modelu) 1b(T) ⇒ zostają 2a i 1b
    half = gc.instances(15, -9, 0.5)
    assert [(i["file"], i["x"]) for i in half] == [("Rem_AC.esp", x0 + 8200), ("Rem_WG.esp", x0 + 40)] or \
        sorted((i["file"], i["x"]) for i in half) == [("Rem_AC.esp", x0 + 8200), ("Rem_WG.esp", x0 + 40)]
    assert gc.instances(0, 0) == []
    # region = granice komórki (15,−9): ref 2 leży w (16,−9) — poza obszarem; region przesunięty łapie tylko ją
    r = gcbaseline.region_count(gc, x0, y0, x0 + 8192, y0 + 8192)
    assert r["instances"] == 2 and r["by_assigned_cell"] == {"15,-9": 2}
    r = gcbaseline.region_count(gc, x0 + 8192, y0, x0 + 2 * 8192, y0 + 8192)
    assert r["instances"] == 1 and r["by_assigned_cell"] == {"15,-9": 1}
    with pytest.raises(ValueError):
        gcbaseline.region_count(gc, 10, 10, 5, 20)


def test_height_offset_and_mapping_check(tmp_path):
    f = w(tmp_path / "A.esm", esp_bytes() + ltex("a", 0, "a.dds") +
          land_rec(15, -9, heights=vhgt(0.0, [0] * (N * N)), vtex=raw_from_grid([1] * 256)))
    li = LandIndex.load([f])
    x0, y0 = 15 * 8192, -9 * 8192
    data = bytearray(_gc_plugin([("g1", "a.nif")], [(1, "g1", x0 + 100, y0 + 100), (2, "g1", x0 + 900, y0 + 900)]))
    # ustawiamy z = 23 w obu referencjach
    for idx in [i for i in range(len(data) - 4) if data[i:i + 4] == b"DATA"][-2:]:
        struct.pack_into("<f", data, idx + 16, 23.0)
    p = w(tmp_path / "Rem_AC.esp", bytes(data))
    gc = gcbaseline.GroundcoverIndex.load([p])
    r = gcbaseline.height_offset_check(gc, li)
    assert r["per_plugin"]["Rem_AC.esp"]["median_dz"] == 23.0
    m = gcbaseline.texture_mapping_check(gc, li)
    assert m["refs"] == 2 and m["weighted_top_share"]["fork"] == 1.0


def test_server_stage2_tools(project, monkeypatch):
    from openmw_mcp import server
    monkeypatch.setattr(server, "_ENV", project["env"])
    server._WORLD_CACHE.clear()
    names = {t.name for t in _tools(server)}
    assert {"openmw_land_cell", "openmw_land_point", "openmw_groundcover_baseline",
            "openmw_land_texture_mapping_check", "openmw_groundcover_height_offset", "openmw_groundcover_region"} <= names
    r = server.openmw_groundcover_baseline("official-ref", 15, -9)
    assert r["instances"] == 2 and r["position_outside_cell"] == 1 and r["density"] == 1.0
    r = server.openmw_land_cell("official-ref", 15, -9)
    assert "error" in r                                    # syntetyczny Morrowind.esm nie ma LAND
    assert server.openmw_land_point("official-ref", 0, 0)["height"] is None


def _tools(server):
    import asyncio
    lt = server.mcp.list_tools()
    return asyncio.run(lt) if asyncio.iscoroutine(lt) else lt


def test_project_root_auto_through_symlink_and_mcp_paths(tmp_path, monkeypatch):
    import json, os
    from openmw_mcp import environment
    monkeypatch.delenv("OPENMW_MCP_PROJECT_ROOT", raising=False)
    root = tmp_path / "Projekt RLF"
    real = root / "Fork/repo/tools/MCP-openMW"
    (root / "OpenMW").mkdir(parents=True)
    w(real / "catalog/x.sha256", "")
    w(real / "openmw-mcp.json", json.dumps({"project_root": "auto", "targets": {}}))
    link = root / "MCP-openMW"
    os.symlink(os.path.relpath(real, root), link)
    for cfg in (link / "openmw-mcp.json", real / "openmw-mcp.json"):
        e = environment.load_env(cfg, use_cache=False)
        assert e.project_root == root
        assert e.p("@mcp/catalog/x.sha256").is_file()
    monkeypatch.setenv("OPENMW_MCP_PROJECT_ROOT", str(tmp_path))
    assert environment.load_env(link / "openmw-mcp.json", use_cache=False).project_root == tmp_path
    lone = w(tmp_path / "sam/openmw-mcp.json", json.dumps({"project_root": "auto"}))
    monkeypatch.delenv("OPENMW_MCP_PROJECT_ROOT")
    with pytest.raises(FileNotFoundError):
        environment.load_env(lone, use_cache=False)


def test_srcmanifest_git_state_outside_repo(tmp_path):
    from openmw_mcp import srcmanifest
    assert srcmanifest.git_state(tmp_path) == {"in_git": False}
