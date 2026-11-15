"""Etap 2b: parser NIF, BSA/VFS, obiekty w komórkach, transformacje, widoczność i wybór kamery (dane syntetyczne).

Zgodność parsera z rzeczywistym formatem sprawdzają osobno: odczyt wszystkich modeli Morrowinda co do bajtu
(raport etapu 2b) i porównanie z silnikiem (openmw_geometry_verify). Tu — logika: transformacje, reguły
widoczności nifloader.cpp, nadpisania pluginów i VFS, zasłanianie.
"""

from __future__ import annotations

import math
import struct
from pathlib import Path

import numpy as np
import pytest

from conftest import rec, w
from openmw_mcp import bsa, capture, geomverify, nif, objects, scene, visibility
from openmw_mcp.land import LandIndex

# --- generator NIF 4.0.0.2 (układ jak components/nif) --------------------------------------------------------


def _s(t: str) -> bytes:
    b = t.encode("latin-1")
    return struct.pack("<I", len(b)) + b


def _objnet(name, extra=-1, ctrl=-1):
    return _s(name) + struct.pack("<ii", extra, ctrl)


def _av(name, flags=0, trans=(0, 0, 0), rot=None, scale=1.0, props=(), extra=-1, ctrl=-1):
    rot = rot if rot is not None else (1, 0, 0, 0, 1, 0, 0, 0, 1)
    return (_objnet(name, extra, ctrl) + struct.pack("<H", flags) + struct.pack("<3f", *trans)
            + struct.pack("<9f", *rot) + struct.pack("<f", scale) + struct.pack("<3f", 0, 0, 0)
            + struct.pack("<I", len(props)) + b"".join(struct.pack("<i", p) for p in props) + struct.pack("<i", 0))


def node(name, children, rtype="NiNode", **kw):
    body = _av(name, **kw) + struct.pack("<I", len(children)) + b"".join(struct.pack("<i", c) for c in children)
    return rtype, body + struct.pack("<I", 0)


def switch(name, children, index, **kw):
    t, body = node(name, children, "NiSwitchNode", **kw)
    return t, body + struct.pack("<I", index)


def trishape(name, data, **kw):
    return "NiTriShape", _av(name, **kw) + struct.pack("<ii", data, -1)


def trishape_data(verts, tris):
    v = np.asarray(verts, dtype="<f4")
    c = v.mean(axis=0)
    r = float(np.sqrt(((v - c) ** 2).sum(axis=1)).max())
    idx = np.asarray(tris, dtype="<u2").ravel()
    body = (struct.pack("<H", len(v)) + struct.pack("<i", 1) + v.tobytes() + struct.pack("<i", 0)
            + struct.pack("<4f", *c, r) + struct.pack("<i", 0) + struct.pack("<H", 0) + struct.pack("<i", 0)
            + struct.pack("<H", len(idx) // 3) + struct.pack("<I", len(idx)) + idx.tobytes() + struct.pack("<H", 0))
    return "NiTriShapeData", body


def tristrips(name, data, **kw):
    return "NiTriStrips", _av(name, **kw) + struct.pack("<ii", data, -1)


def tristrips_data(verts, strips):
    v = np.asarray(verts, dtype="<f4")
    body = (struct.pack("<H", len(v)) + struct.pack("<i", 1) + v.tobytes() + struct.pack("<i", 0)
            + struct.pack("<4f", 0, 0, 0, 1) + struct.pack("<i", 0) + struct.pack("<H", 0) + struct.pack("<i", 0)
            + struct.pack("<H", 0) + struct.pack("<H", len(strips)) + b"".join(struct.pack("<H", len(s)) for s in strips)
            + b"".join(np.asarray(s, dtype="<u2").tobytes() for s in strips))
    return "NiTriStripsData", body


def alpha_prop(flags):
    return "NiAlphaProperty", _objnet("") + struct.pack("<HB", flags, 128)


def string_extra(text):
    return "NiStringExtraData", struct.pack("<iI", -1, len(text) + 4) + _s(text)


def vis_controller(target):
    return "NiVisController", struct.pack("<iH4fi", -1, 8, 1, 0, 0, 1, target) + struct.pack("<i", -1)


def nif_bytes(records, roots=(0,)):
    out = b"NetImmerse File Format, Version 4.0.0.2\n" + struct.pack("<II", nif.VER_MW, len(records))
    for t, body in records:
        out += _s(t) + body
    return out + struct.pack("<I", len(roots)) + b"".join(struct.pack("<i", r) for r in roots)


def box(hx, hy, hz, c=(0, 0, 0)):
    cx, cy, cz = c
    v = [(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    f = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6),
         (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
    return v, f


def box_nif(hx, hy, hz, alpha=False):
    v, f = box(hx, hy, hz)
    recs = [node("Root", [1]), trishape("Tri Box", 2, props=[3] if alpha else []), trishape_data(v, f)]
    if alpha:
        recs.append(alpha_prop(0x200))
    return nif_bytes(recs)


# --- NIF ------------------------------------------------------------------------------------------------------

def test_nif_transforms_rotation_and_nonuniform_scale():
    v, f = box(10, 10, 10)
    rz90 = (0, -1, 0, 1, 0, 0, 0, 0, 1)                   # wiersze R: obrót +90° wokół Z
    nonuni = (2, 0, 0, 0, 1, 0, 0, 0, 0.5)                # skala niejednorodna w macierzy (dozwolone w NIF)
    recs = [node("Root", [1], trans=(999, 999, 999), scale=5.0),   # korzeń: transformacja zerowana (node.cpp)
            node("Mid", [2], trans=(100, 0, 0), rot=rz90, scale=2.0),
            trishape("Tri A", 3, rot=nonuni, trans=(0, 50, 0)), trishape_data(v, f)]
    nf = nif.parse(nif_bytes(recs), "t.nif")
    assert nf.trailing == 0 and len(nf.records) == 4
    g = nif.model_geometry(nf)
    lo, hi = g.aabb
    # p = (100,0,0) + 2·Rz90·((0,50,0) + diag(2,1,0.5)·p) ⇒ x ∈ 100 + 2·(−50 ± 10) = [−20, 20]; y ∈ ±40; z ∈ ±10
    assert np.allclose(lo, [-20, -40, -10]) and np.allclose(hi, [20, 40, 10])
    assert g.engine_aabb is not None and np.allclose(g.engine_aabb[0], lo)


def test_nif_bip01_root_keeps_transform():
    v, f = box(1, 1, 1)
    nf = nif.parse(nif_bytes([node("Bip01", [1], trans=(0, 0, 100)), trishape("Tri", 2), trishape_data(v, f)]))
    assert np.allclose(nif.model_geometry(nf).aabb[0], [-1, -1, 99])


def test_nif_render_rules_collision_hidden_switch_markers_alpha():
    v, f = box(1, 1, 1)
    big_v, big_f = box(50, 50, 50)
    recs = [
        node("Root", [1, 3, 5, 7, 11, 13], extra=15),                         # 0
        trishape("Tri Visible", 2, props=[16]), trishape_data(v, f),          # 1, 2 (alfa test)
        node("Collision", [4], rtype="RootCollisionNode"),                    # 3
        trishape("Tri Coll", 17),                                             # 4
        node("Hidden", [6], flags=1),                                         # 5
        trishape("Tri Hid", 17),                                              # 6
        switch("Sw", [8, 9], 1),                                              # 7
        trishape("Tri Off", 17), trishape("Tri On", 2),                       # 8, 9
        trishape("Tri Unused", 2),                                            # 10 (nie podpięty)
        node("HiddenAnimated", [12], flags=1, ctrl=14),                       # 11
        trishape("Tri VisCtrl", 2),                                           # 12
        trishape("tri editormarker", 17),                                     # 13
        vis_controller(11),                                                   # 14
        string_extra("MRK"),                                                  # 15
        alpha_prop(0x200),                                                    # 16
        trishape_data(big_v, big_f),                                          # 17
    ]
    assert len(recs) == 18
    nf = nif.parse(nif_bytes(recs))
    by = {s.name: s for s in nif.shapes(nf)}
    assert by["Tri Visible"].rendered and by["Tri Visible"].alpha == "test"
    assert not by["Tri Coll"].rendered and by["Tri Coll"].collision and by["Tri Coll"].reason == "kolizja"
    assert not by["Tri Hid"].rendered and by["Tri Hid"].reason == "ukryty"
    assert not by["Tri Off"].rendered and by["Tri Off"].reason == "switch" and by["Tri On"].rendered
    assert by["Tri VisCtrl"].rendered                                          # ukryty, ale z NiVisController
    assert not by["tri editormarker"].rendered                                # MRK w korzeniu
    assert "Tri Unused" not in by
    g = nif.model_geometry(nf)
    assert np.allclose(g.aabb[1], [1, 1, 1])                                  # duże kształty pominięte
    assert np.allclose(g.collision_aabb[1], [50, 50, 50])
    assert g.stats["alpha_triangles"] > 0


def test_nif_strips_and_declared_sphere_check():
    verts = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (1, 1, 1)]
    nf = nif.parse(nif_bytes([node("Root", [1]), tristrips("Strip", 2), tristrips_data(verts, [[0, 1, 2, 3, 3, 4]])]))
    s = nif.shapes(nf)[0]
    assert s.rendered and len(s.triangles) == 2            # zdegenerowane pominięte (stripsToBtTriangleMesh)
    chk = nif.declared_sphere_check(nif.model_geometry(nf))
    assert chk["spheres_too_small"] == 1                   # zadeklarowana sfera r=1 w (0,0,0) nie obejmuje (1,1,1)


@pytest.mark.parametrize("data,msg", [
    (b"", "pusty"), (b"not a nif\n\0\0", "nagłówka"),
    (b"NetImmerse File Format, Version 20.0.0.5\n" + struct.pack("<I", 0x14000005), "wersja"),
])
def test_nif_rejects_empty_or_foreign(data, msg):
    with pytest.raises(nif.NifError, match=msg):
        nif.parse(data, "x.nif")


def test_nif_truncated_and_unknown_record():
    good = box_nif(1, 1, 1)
    with pytest.raises(nif.NifError, match="koniec danych"):
        nif.parse(good[:-30], "cut.nif")
    bad = b"NetImmerse File Format, Version 4.0.0.2\n" + struct.pack("<II", nif.VER_MW, 1) + _s("NiFancyNewThing")
    with pytest.raises(nif.NifError, match="nieznany typ rekordu"):
        nif.parse(bad, "u.nif")


# --- BSA i VFS ------------------------------------------------------------------------------------------------

def test_bsa_read_and_vfs_override(tmp_path):
    a = box_nif(1, 1, 1)
    b = box_nif(5, 5, 5)
    arc = w(tmp_path / "Base.bsa", bsa.build_tes3_bsa({"meshes\\x\\rock.nif": a, "meshes\\x\\only_bsa.nif": a}))
    t = bsa.Tes3Bsa(arc)
    assert t.read("Meshes/X/Rock.nif") == a
    d1 = w(tmp_path / "mod1/Meshes/x/rock.nif", b)
    vfs = {"layers": [], "index": {
        "meshes/x/rock.nif": [{"layer": 0, "kind": "bsa", "root": str(arc), "file": None},
                              {"layer": 1, "kind": "dir", "root": str(tmp_path / "mod1"), "file": str(d1)}],
        "meshes/x/only_bsa.nif": [{"layer": 0, "kind": "bsa", "root": str(arc), "file": None}]}}
    r = bsa.VfsReader(vfs)
    assert r.provider("meshes/x/rock.nif")["kind"] == "dir" and r.read("meshes/x/rock.nif") == b
    assert r.read("MESHES\\x\\only_bsa.nif") == a
    with pytest.raises(FileNotFoundError):
        r.read("meshes/x/none.nif")


# --- ESM: referencje, nadpisania, przeniesienia ------------------------------------------------------------------

def _hedr():
    return struct.pack("<fI", 1.3, 0) + b"a".ljust(32, b"\0") + b"d".ljust(256, b"\0") + struct.pack("<I", 0)


def _ref(frmr, rid, pos, rot=(0, 0, 0), scale=None, dele=False, moved_to=None):
    subs = []
    if moved_to is not None:
        subs += [("MVRF", struct.pack("<I", frmr)), ("CNDT", struct.pack("<ii", *moved_to))]
    subs += [("FRMR", struct.pack("<I", frmr)), ("NAME", rid.encode() + b"\0")]
    if scale is not None:
        subs.append(("XSCL", struct.pack("<f", scale)))
    subs.append(("DATA", struct.pack("<6f", *pos, *rot)))
    if dele:
        subs.append(("DELE", struct.pack("<I", 0)))
    return subs


def esm(masters, statics, cells):
    subs = [("HEDR", _hedr())]
    for m in masters:
        subs += [("MAST", m.encode() + b"\0"), ("DATA", struct.pack("<Q", 0))]
    out = rec("TES3", subs)
    for sid, model, rtype in statics:
        out += rec(rtype, [("NAME", sid.encode() + b"\0"), ("MODL", model.encode() + b"\0")])
    for (x, y), refs in cells:
        s = [("NAME", b"\0"), ("DATA", struct.pack("<Iii", 0, x, y))]
        s += list(refs)
        out += rec("CELL", s)
    return out


def test_refs_override_delete_move_and_scale_clamp(tmp_path):
    m = w(tmp_path / "M.esm", esm([], [("rock", "x\\rock.nif", "STAT"), ("door", "x\\door.nif", "DOOR")],
                                  [((0, 0), [*_ref(1, "rock", (100, 100, 0)), *_ref(2, "rock", (200, 100, 0)),
                                             *_ref(3, "door", (300, 100, 0), scale=5.0),
                                             *_ref(4, "rock", (400, 100, 0))])]))
    p = w(tmp_path / "P.esp", esm(["M.esm"], [("rock", "x\\rock2.nif", "STAT")],
                                  [((0, 0), [*_ref((1 << 24) | 1, "rock", (150, 150, 0), rot=(0, 0, 1.0)),
                                             *_ref((1 << 24) | 2, "rock", (200, 100, 0), dele=True),
                                             *_ref(7, "rock", (500, 500, 0)),
                                             *_ref((1 << 24) | 4, "rock", (8200, 100, 0), moved_to=(1, 0))])]))
    wo = objects.WorldObjects.load([m, p])
    c00 = {r.refnum: r for r in wo.refs(0, 0)}
    assert set(c00) == {(1, 0), (3, 0), (7, 1)}                        # 2 usunięty, 4 przeniesiony
    assert c00[(1, 0)].pos == (150, 150, 0) and c00[(1, 0)].file == 1  # nadpisanie z pluginu (górny bajt = MAST 1)
    assert c00[(3, 0)].scale == 2.0                                     # XSCL obcięte do 2,0
    assert wo.base("ROCK")[1] == "x\\rock2.nif"                         # rekord bazowy: późniejszy wygrywa
    moved = wo.refs(1, 0)
    assert len(moved) == 1 and moved[0].refnum == (4, 0) and moved[0].moved_from == (0, 0)
    assert wo.deleted == 1 and wo.moved == 1


def test_world_rotation_convention_and_orders():
    r = objects.Ref((1, 0), "x", (0, 0, 0), (0.0, 0.0, math.pi / 2), 1.0, 0, (0, 0))
    p = objects.transform(np.array([[0.0, 100.0, 0.0]]), objects.world_matrix(r))[0]
    assert np.allclose(p, [100, 0, 0], atol=1e-9)                       # kurs 90°: +Y modelu → +X świata
    r2 = objects.Ref((1, 0), "x", (0, 0, 0), (0.3, 0.2, 0.5), 1.0, 0, (0, 0))
    d, i = objects.rotation_matrix(r2.rot), objects.rotation_matrix(r2.rot, "inverse")
    assert np.allclose(d @ d.T, np.eye(3)) and not np.allclose(d, i)    # kolejność ma znaczenie przy X/Y


# --- scena i widoczność -----------------------------------------------------------------------------------

def _vhgt(height=100.0, hill=None):
    deltas = bytearray(65 * 65)
    if hill:
        x, y, dz = hill
        deltas[y * 65 + x] = dz & 0xFF
    return struct.pack("<f", height / 8.0) + bytes(deltas) + b"\0\0\0"


def _world(tmp_path, statics, refs, hill=None):
    body = b""
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            body += rec("LAND", [("INTV", struct.pack("<ii", dx, dy)), ("DATA", struct.pack("<I", 1)),
                                 ("VHGT", _vhgt(100.0, hill if (dx, dy) == (0, 0) else None))])
    data = esm([], statics, [((0, 0), refs)]) + body
    path = w(tmp_path / "W.esm", data)
    return LandIndex.load([path]), objects.WorldObjects.load([path])


class _Vfs:
    def __init__(self, files):
        self.files = files

    def provider(self, key):
        return {"kind": "dir", "root": "mem"} if key in self.files else None

    def read(self, key):
        if key not in self.files:
            raise FileNotFoundError(key)
        return self.files[key]


def test_heightgrid_matches_land_height(tmp_path):
    li, _ = _world(tmp_path, [], [], hill=(20, 30, 40))
    g = scene.HeightGrid(li, -1, -1, 1, 1)
    rng = np.random.default_rng(1)
    xs, ys = rng.uniform(-8000, 16000, 400), rng.uniform(-8000, 16000, 400)
    hz = g.height(xs, ys)
    ref = np.array([li.height_at(x, y) for x, y in zip(xs, ys)])
    assert np.allclose(hz, ref, atol=1e-6)


def _scene_with_wall(tmp_path, alpha=False, wall_y=4096.0 - 300, half_x=400.0):
    statics = [("wall", "x\\wall.nif", "STAT")]
    li, wo = _world(tmp_path, statics, [*_ref(1, "wall", (4096.0, wall_y, 100.0))])
    sc = scene.Scene(li, wo, _Vfs({"meshes/x/wall.nif": box_nif(half_x, 20, 300, alpha=alpha)}))
    return sc, sc.height_grid(0, 0, 1), sc.objects([(0, 0)], objects.STATIC_TYPES)


def test_target_fully_blocked_by_wall_then_visible_from_side(tmp_path):
    sc, grid, objs = _scene_with_wall(tmp_path)
    assert objs[0].aabb is not None and np.allclose(objs[0].aabb[1], [4496, 3816, 400])
    pts = visibility.target_points(grid, 4096.0, 4096.0, radius=150)
    behind = visibility.Camera(4096.0, 4096.0 - 800, 228.0, 0.0, 0.1)      # mur między kamerą a celem
    tv = visibility.target_visibility(behind, grid, objs, pts)
    assert tv["in_frame"] == tv["points"] and tv["visible"] == 0 and "wall [STAT]" in next(iter(tv["blockers"]))
    side = visibility.Camera(4096.0 + 800, 4096.0, 228.0, -math.pi / 2, 0.1)  # z boku — mur nie zasłania
    assert visibility.target_visibility(side, grid, objs, pts)["visible_fraction"] == 1.0
    away = visibility.Camera(4096.0, 4096.0 - 800, 228.0, math.pi, 0.1)      # tyłem do celu
    assert visibility.target_visibility(away, grid, objs, pts)["in_frame"] == 0


def test_partial_and_alpha_occlusion_and_frame(tmp_path):
    sc, grid, objs = _scene_with_wall(tmp_path, half_x=80.0, wall_y=4096.0 - 400)
    pts = visibility.target_points(grid, 4096.0, 4096.0, radius=300)
    cam = visibility.Camera(4096.0, 4096.0 - 1000, 228.0, 0.0, 0.12)
    tv = visibility.target_visibility(cam, grid, objs, pts)
    assert 0.2 < tv["visible_fraction"] < 0.9
    fr = visibility.frame(cam, grid, objs)
    fs = visibility.frame_summary(fr, objs)
    assert fs["shares"]["obiekt"] > 0.02 and fs["shares"]["niebo/daleko"] > 0.3
    sc2, grid2, objs2 = _scene_with_wall(tmp_path / "a", alpha=True)
    cam2 = visibility.Camera(4096.0, 4096.0 - 800, 228.0, 0.0, 0.1)
    tv2 = visibility.target_visibility(cam2, grid2, objs2, visibility.target_points(grid2, 4096.0, 4096.0, 150))
    assert tv2["blocked_only_by_alpha"] == tv2["points"]
    fr2 = visibility.frame(cam2, grid2, objs2)
    assert (fr2["class"] == visibility.OBJECT_ALPHA).any()
    assert not (fr2["class_alpha_transparent"] == visibility.OBJECT_ALPHA).any()


def test_terrain_occlusion_hill(tmp_path):
    li, wo = _world(tmp_path, [], [], hill=(20, 26, 100))                   # grzbiet +800 j. (y = 3328) między kamerą a celem
    grid = scene.HeightGrid(li, -1, -1, 1, 1)
    pts = visibility.target_points(grid, 4096.0, 4096.0 + 600, radius=100)
    cam = visibility.Camera(4096.0, 2000.0, 228.0, 0.0, 0.0)
    tv = visibility.target_visibility(cam, grid, [], pts)
    assert tv["blocked_by_terrain"] > 0


def test_suggest_avoids_wall_and_cross_cell_objects(tmp_path):
    sc, grid, objs = _scene_with_wall(tmp_path, half_x=900.0, wall_y=4096.0 - 500)
    r = visibility.suggest(grid, objs, (4096.0, 4096.0), distances=(800.0,), headings=8)
    best = r["best"]
    assert best["target"]["visible_fraction"] == 1.0
    assert abs(math.cos(best["camera"].yaw) - 1.0) > 1e-6                   # nie z kursu 0 (zza muru)
    # obiekt przy granicy komórki: geometria wchodzi do sąsiedniej
    li, wo = _world(tmp_path / "b", [("wall", "x\\wall.nif", "STAT")], [*_ref(1, "wall", (8100.0, 4096.0, 100.0))])
    sc2 = scene.Scene(li, wo, _Vfs({"meshes/x/wall.nif": box_nif(400, 20, 300)}))
    rep = scene.object_report(sc2.objects([(0, 0)])[0], (0, 0))
    assert rep["crosses_cell_border"] is True


def test_capture_bounds_parsing_and_engine_compare(tmp_path):
    sc, grid, objs = _scene_with_wall(tmp_path)
    lo, hi = objs[0].engine_aabb
    c, h = (lo + hi) / 2, (hi - lo) / 2
    log = w(tmp_path / "openmw.log", "\n".join([
        "[10:00:00.000 I] Global[scripts/rlf_capture/global.lua]:\tRLF_BBOX c0_0 Static 0x1 wall "
        + " ".join(f"{v:.2f}" for v in (*c, *h, 4096, 3796, 100)),
        "[10:00:00.000 I] Global[...]:\tRLF_BBOX c0_0 Static @0x5 generated 0 0 0 1 1 1 0 0 0", "other line"]))
    b = capture.parse_bounds(log)
    assert len(b) == 2 and b[0]["record"] == "wall" and b[0]["id"] == "0x1"
    r = geomverify.compare_bounds(sc, b)
    assert r["compared"] == 1 and r["within_tol"] == 1 and r["missing_in_mcp"] == 1


def test_server_tools_registered(project, monkeypatch):
    import asyncio
    import inspect
    from openmw_mcp import server
    monkeypatch.setattr(server, "_ENV", project["env"])
    server._WORLD_CACHE.clear()
    lt = server.mcp.list_tools()
    names = {t.name for t in (asyncio.run(lt) if inspect.iscoroutine(lt) else lt)}
    assert {"openmw_nif_inspect", "openmw_cell_objects", "openmw_view_analyze", "openmw_view_suggest",
            "openmw_geometry_verify"} <= names
    r = server.openmw_view_analyze()
    assert "error" in r                                      # brak kamery ⇒ czytelny błąd zamiast wyjątku
    r = server.openmw_geometry_verify(str(project["env"].project_root))
    assert "bounds" in r and "error" in r["bounds"]
