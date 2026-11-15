"""Etap 2c: emulacja proceduralnej flory forka — dane syntetyczne."""

from __future__ import annotations

import struct

import pytest

from conftest import esp_bytes, rec, w
from openmw_mcp import fflora
from openmw_mcp.fflora import ForkFloraParams
from openmw_mcp.land import LandIndex

N = 65
WG_POOL = [f"meshes/omwpl/grass/{m}" for m in fflora.POOL_REQUIREMENTS["WG"]]
AI_POOL = [f"meshes/omwpl/grass/{m}" for m in fflora.POOL_REQUIREMENTS["AI"]]


def vtex_all(v: int) -> bytes:
    return struct.pack("<256H", *([v] * 256))


def flat_vhgt(height: float) -> bytes:
    return struct.pack("<f", height / 8.0) + bytes(N * N) + b"\0\0\0"


def cell_rec(x: int, y: int, region: str | None) -> bytes:
    s = [("NAME", b"\0"), ("DATA", struct.pack("<Iii", 0, x, y))]
    if region:
        s.append(("RGNN", region.encode() + b"\0"))
    return rec("CELL", s)


def world(tmp_path, texture="tx_wg_grass_01.dds", height=100.0, region="West Gash Region", center=(0, 0)):
    """Płaski teren 3×3 komórki wokół center, jedna tekstura, rekord CELL z regionem tylko dla center."""
    body = rec("LTEX", [("NAME", b"t\0"), ("INTV", struct.pack("<I", 0)), ("DATA", texture.encode() + b"\0")])
    cx, cy = center
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            body += rec("LAND", [("INTV", struct.pack("<ii", cx + dx, cy + dy)), ("DATA", struct.pack("<I", 9)),
                                 ("VHGT", flat_vhgt(height)), ("VTEX", vtex_all(1))])
    body += cell_rec(cx, cy, region)
    return LandIndex.load([w(tmp_path / "W.esm", esp_bytes() + body)])


def test_hash_and_seed_match_c_reference():
    # wartości z programu w C skompilowanego z lambd hash32/random01 i wzoru ziarna z groundcover.cpp forka
    assert [fflora.hash32(v) for v in (0, 1, 0x12345678, 0xFFFFFFFF)] == [0, 1753845952, 4125564054, 1734902346]
    assert f"{fflora.random01(1):.10f}" == "0.5373649597"
    cx, cy, idx = -7, 13, 4095
    base = ((cx & fflora.M32) * 0x9E3779B9 & fflora.M32) ^ ((cy & fflora.M32) * 0x85EBCA6B & fflora.M32) \
        ^ ((idx * 0xC2B2AE35) & fflora.M32)
    assert base == 145902933
    assert f"{fflora.f32(fflora.f32(63 + fflora.random01(base ^ 0x68BC21EB)) / 64.0):.9f}" == "0.985453725"
    assert fflora.lround(2.5) == 3 and fflora.lround(-2.5) == -3


@pytest.mark.parametrize("tex,weight", [
    ("", 0.0), ("_land_default.dds", 0.0), ("tx_ac_rock_01.dds", 0.0), ("tx_road.dds", 0.0),
    ("tx_grass_dirt.dds", 0.5), ("tx_wg_grass_01.dds", 1.0), ("tx_moss.dds", 1.0),
    ("tx_bc_mud.dds", fflora.f32(0.55)), ("tx_dirt.dds", fflora.f32(0.35)), ("tx_sand.dds", fflora.f32(0.2)),
    ("tx_ash_01.dds", fflora.f32(0.15)), ("tx_other.dds", fflora.f32(0.4))])
def test_generic_surface_weight(tex, weight):
    assert fflora.generic_surface_weight(tex) == weight


def test_profile_surface_weights_and_pathgrid():
    assert fflora.ai_surface_weight("tx_ai_rock_grass.dds", 0.0) == fflora.f32(0.65)
    assert fflora.ai_surface_weight("tx_ai_grass.dds", 1.0) == 1.0
    assert fflora.al_surface_weight("tx_al_lava_01.dds", 0.4) == 0.0
    assert fflora.al_surface_weight("tx_al_rock_01.dds", 0.0) == 0.25
    assert fflora.al_surface_weight("tx_ashlands_01.dds", 0.15) == 1.0
    assert fflora.al_surface_weight("tx_al_ash_01.dds", 0.15) == fflora.f32(0.35)
    assert fflora.al_surface_weight("tx_wg_grass.dds", 1.0) == 1.0
    assert fflora.uses_pathgrid_exclusion("tx_road_01.dds")
    assert fflora.uses_pathgrid_exclusion("tx_dirt_01.dds")
    assert not fflora.uses_pathgrid_exclusion("tx_grass_dirt.dds")


def test_model_choice_boundaries():
    g01, g01b, g01c, g02 = AI_POOL
    assert fflora.choose_ai(AI_POOL, "tx_ai_clover.dds", 0) == g02
    assert fflora.choose_ai(AI_POOL, "tx_ai_grass_dirt.dds", 6078) == g01
    assert fflora.choose_ai(AI_POOL, "tx_ai_grass_dirt.dds", 6079) == g01c
    assert fflora.choose_ai(AI_POOL, "tx_ai_grass_dirt.dds", 10867) == g01b
    assert fflora.choose_ai(AI_POOL, "tx_ai_grass.dds", 45650) == g01
    assert fflora.choose_ai(AI_POOL, "tx_ai_grass.dds", 61648 + 55460) == g01b
    assert fflora.choose_ai(AI_POOL[:3], "tx_ai_grass.dds", 1) is None
    assert fflora.choose_wg(WG_POOL, 7) == WG_POOL[1]
    assert fflora.pool_profiles(WG_POOL + AI_POOL) == {"AI": True, "AL": False, "BC": False, "GL": False, "WG": True}
    assert fflora.choose_generic(["meshes/a/01_x.nif", "meshes/a/09_y.nif"], "", 88) == "meshes/a/09_y.nif"
    assert fflora.choose_generic(["meshes/f/flora_grass_01.nif", "meshes/f/flora_bc_grass_01.nif"],
                                 "tx_bc_mud.dds", 5) == "meshes/f/flora_bc_grass_01.nif"


def test_flat_grass_accepts_every_candidate(tmp_path):
    li = world(tmp_path)
    r = fflora.generate_cell(li, ForkFloraParams(1.0, 3.0, WG_POOL), 0, 0)
    assert r["profiles"] == ["WG"] and r["candidates"] == 8192 and r["grid_side"] == 91
    assert r["instances"] == 8192 and r["rejected"] == {} and r["max_slope_deg"] == 28.0
    assert set(r["by_model"]) == set(WG_POOL)
    assert 0.8 <= r["scale"]["min"] and r["scale"]["max"] <= 1.15 + 1e-6
    half = fflora.generate_cell(li, ForkFloraParams(0.5, 3.0, WG_POOL), 0, 0)
    assert half["candidates"] == 4096 and half["instances"] == 4096


def test_rejections_height_texture_and_region(tmp_path):
    assert fflora.generate_cell(world(tmp_path / "a", height=0.0), ForkFloraParams(1.0, 0, WG_POOL), 0, 0)["rejected"] \
        == {"height_le_1": 8192}
    r = fflora.generate_cell(world(tmp_path / "b", texture="tx_wg_rock_01.dds"), ForkFloraParams(1.0, 0, WG_POOL), 0, 0)
    assert r["instances"] == 0 and r["rejected"] == {"surface_weight_0": 8192}
    r = fflora.generate_cell(world(tmp_path / "c", texture="tx_wg_dirt.dds"), ForkFloraParams(1.0, 0, WG_POOL), 0, 0)
    # waga 0.35 losowana dwa razy (miejsce bazowe i klaster) ⇒ ok. 0.35² ≈ 12%; ścieżki liczone osobno
    assert 0.09 < r["instances"] / 8192 < 0.16 and r["pathgrid_check_candidates"] == r["instances"]
    li = world(tmp_path / "d", region="Azura's Coast Region")
    r = fflora.generate_cell(li, ForkFloraParams(1.0, 0, WG_POOL), 0, 0)
    assert r["generated"] is False and r["instances"] == 0 and "profilu" in r["reason"]
    assert fflora.generate_cell(li, ForkFloraParams(1.0, 0, WG_POOL), 1, 0)["generated"] is False   # brak CELL
    # pula bez kompletnych profili ⇒ tryb ogólny, generuje także poza regionami
    r = fflora.generate_cell(li, ForkFloraParams(1.0, 0, ["meshes/f/flora_grass_01.nif"]), 0, 0)
    assert r["generated"] and r["candidates"] == 32768 and r["instances"] == 32768


def test_texture_fallback_for_grazelands(tmp_path):
    gl_pool = [f"meshes/g/{m}" for m in fflora.POOL_REQUIREMENTS["GL"]]
    li = world(tmp_path, texture="tx_gl_grass_01.dds", region="Azura's Coast Region")
    cp = fflora.cell_profile(li, ForkFloraParams(1.0, 0, gl_pool), 0, 0)
    assert cp["profiles"] == ["GL"] and cp["profiles_via_texture_fallback"] == ["GL"]
    r = fflora.generate_cell(li, ForkFloraParams(1.0, 0, gl_pool), 0, 0)
    assert r["max_slope_deg"] == 45.0 and r["instances"] == 8192


def test_region_split_is_additive(tmp_path):
    li = world(tmp_path)
    p = ForkFloraParams(1.0, 0, WG_POOL)
    full = fflora.generate_region(li, p, 0, 0, 8192, 8192)
    a = fflora.generate_region(li, p, 0, 0, 4096, 8192)
    b = fflora.generate_region(li, p, 4096, 0, 8192, 8192)
    assert full["instances"] == 8192 == a["instances"] + b["instances"]
    assert 3900 < a["instances"] < 4300
    with pytest.raises(ValueError):
        fflora.generate_region(li, p, 0, 0, 0, 10)


def test_server_stage2c_tools(project, monkeypatch):
    import asyncio, inspect
    from openmw_mcp import server
    monkeypatch.setattr(server, "_ENV", project["env"])
    server._WORLD_CACHE.clear()
    lt = server.mcp.list_tools()
    names = {t.name for t in (asyncio.run(lt) if inspect.iscoroutine(lt) else lt)}
    assert {"openmw_fork_flora_cell", "openmw_fork_flora_region", "openmw_flora_compare",
            "openmw_flora_coverage"} <= names
    r = server.openmw_fork_flora_cell("fork-test", 15, -9)
    # pula 'all' z fikstury: rem_ac_grass_01 + komplet AL ⇒ tryb regionalny z profilem AL
    assert r["generator"]["pool_models"] == 4 and r["generator"]["active_profiles"] == ["AL"]
    assert r["procedural_enabled_in_profile"] is True
    assert r["generated"] is False and r["instances"] == 0     # syntetyczny Morrowind.esm bez CELL/LAND
    c = server.openmw_flora_compare(15, -9)
    assert c["official"]["instances"] == 1 and c["remiros_plugins_assigned"] == {"Rem_AC.esp": 2}
    assert "error" in server.openmw_fork_flora_cell("official-ref", 0, 0)
    cov = server.openmw_flora_coverage()
    assert cov["totals"]["cells"] == 1


def test_srcmanifest_reports_source_files_ignored_by_git(tmp_path):
    import subprocess
    from openmw_mcp import srcmanifest
    repo = tmp_path / "repo"
    mcp = repo / "tools/MCP"
    w(repo / ".gitignore", "*__*\n")                       # jak linia 80 głównego .gitignore forka
    w(mcp / "src/openmw_mcp/__init__.py", "")
    w(mcp / "src/openmw_mcp/a.py", "")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    st = srcmanifest.git_state(mcp)
    assert st["in_git"] and st["ignored_source_files"] == ["src/openmw_mcp/__init__.py"]
    w(mcp / ".gitignore", "__pycache__/\n!__init__.py\n")
    assert srcmanifest.git_state(mcp)["ignored_source_files"] == []
