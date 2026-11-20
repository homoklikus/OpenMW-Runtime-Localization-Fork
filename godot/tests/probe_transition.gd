extends SceneTree
## Sonda przejść między komórkami (etap 10, P0 „glitche przy wyjściu ze statku”): zapis każdej narysowanej klatki
## (także rysowanych w trakcie synchronicznego ładowania przez ekran ładowania) od rozpoczęcia przejścia do
## ustalenia się obrazu. Dla każdej klatki: czy ekran ładowania zasłaniał obraz, wczytane komórki, liczba
## widocznych instancji siatek (RenderingServer), różnica od obrazu ustalonego (po SETTLE klatkach). Klatka
## pokazana graczowi (bez ekranu ładowania) z dużą różnicą od ustalonego obrazu = niekompletna scena.
##
## Wymaga renderera (np. Xvfb + lavapipe). Wynik: <out>/transition.json (+ PNG klatek z --png=1). Obrazy z danych
## gry zostają lokalnie (katalog --out poza repozytorium).
## godot --path godot -s res://tests/probe_transition.gd -- --data=… --pos=… --out=/tmp/trans [--png=1]
##   [--cases=int,ext,ext_far,int2] [--settle=90] [--load-cpu=1]
## Przypadki: int (wejście do wnętrza), ext (wyjście na zewnątrz), ext_far (teleport na zewnątrz w inne miejsce),
## int2 (wnętrze → to samo wnętrze ponownie), neighbor (przejście do sąsiedniej komórki).

const SETTLE := 90
const DIFF_BAD := 0.06               # średnia różnica |Δ| (0..1) klatki widocznej od ustalonej – niekompletna scena

var main
var out_dir := ""
var save_png := false
var frames: Array = []               # {i, t, loading, cells, draws, img}
var _capturing := false
var _i := 0
var report := {"cases": []}

func _init() -> void:
	_run.call_deferred()

func _arg(n: String, d := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _frames(n: int) -> void:
	for k in n:
		await process_frame

func _on_post_draw() -> void:
	if not _capturing:
		return
	var vt := root.get_viewport().get_texture()
	var img: Image = vt.get_image() if vt != null else null
	if img == null or img.is_empty():
		return
	img.resize(160, 90, Image.INTERPOLATE_BILINEAR)    # do porównań wystarczy miniatura
	var ld = main.loading
	frames.append({"i": _i, "t": Time.get_ticks_msec(), "loading": ld != null and ld.visible,
		"cells": main.loaded.size(), "interior": String(main.interior),
		"pos": main.player.global_position if main.player != null else Vector3.ZERO,
		"cam": (main.player.get_viewport().get_camera_3d().global_position if main.player.get_viewport().get_camera_3d() != null else Vector3.ZERO),
		"phys": main.player.is_physics_processing(), "paused": paused,
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"pipelines": [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)],
		"fade": main.fader.alpha if main.get("fader") != null else 0.0,
		"img": img})
	_i += 1

## Różnica od obrazu ustalonego przyciemnionego o bieżące zaciemnienie (ScreenFader – zamierzone).
static func _diff_faded(a: Image, b: Image, fade: float) -> float:
	var s := 0.0
	var n := 0
	var k := 1.0 - fade
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			s += (absf(ca.r - cb.r * k) + absf(ca.g - cb.g * k) + absf(ca.b - cb.b * k)) / 3.0
			n += 1
	return s / maxf(1.0, n)

static func _diff(a: Image, b: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			s += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return s / maxf(1.0, n)

func _case(name: String, action: Callable, settle: int) -> void:
	frames.clear()
	_i = 0
	_capturing = true
	var t0 := Time.get_ticks_msec()
	action.call()
	await _frames(settle)
	_capturing = false
	var final: Image = frames.back().img if not frames.is_empty() else null
	var bad := []
	var rows := []
	var first_visible := -1
	for f in frames:
		var d := _diff_faded(f.img, final, float(f.fade)) if final != null else 0.0
		var shown: bool = not bool(f.loading)
		if shown and first_visible < 0:
			first_visible = int(f.i)
		rows.append({"i": f.i, "ms": int(f.t) - t0, "loading": f.loading, "cells": f.cells, "diff": snappedf(d, 0.0001),
			"draws": f.draws, "objects": f.objects, "pipelines": f.pipelines,
			"fade": snappedf(float(f.fade), 0.01), "pos": str(f.pos), "cam": str(f.cam), "phys": f.phys, "paused": f.paused})
		if shown and d > DIFF_BAD:
			bad.append(int(f.i))
		if save_png:
			f.img.save_png(out_dir.path_join("%s_%03d%s.png" % [name, int(f.i), "_L" if f.loading else ""]))
	report.cases.append({"reveal_frames": main.reveal_frames_last if "reveal_frames_last" in main else -1, "name": name, "frames": rows.size(), "first_visible": first_visible,
		"bad_visible_frames": bad, "loading_frames": rows.filter(func(r): return r.loading).size(), "rows": rows})
	print("CASE %s frames=%d loading=%d first_visible=%d bad=%s" % [name, rows.size(),
		rows.filter(func(r): return r.loading).size(), first_visible, str(bad)])

## Drzwi z celem we wnętrzu („int:”) albo w świecie („”) w aktualnie wczytanych komórkach.
func _door_to(kind: String) -> Node:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			var d: Dictionary = MWTravel.door_destination(n)
			if d.is_empty():
				continue
			var ck := String(d.get("cell_key", ""))
			if kind == "int:" and ck.begins_with("int:") and not main.db.find_cell(ck).is_empty():
				return n                            # tylko cel obecny w danych (konwersja części świata)
			if kind == "" and ck == "":
				return n
	return null

## Wysokość terenu z danych komórki (bez wczytanej kolizji) – -INF poza terenem.
func _terrain_h(p: Vector3) -> float:
	var cell: Dictionary = main.db.get_cell(main.db.exterior_key(MWCoords.cell_of(p)))
	if cell.is_empty() or cell.get("terrain") == null:
		return -INF
	var t: Dictionary = main.db.get_terrain(cell["terrain"])
	var o: Array = t["origin_godot"]
	return MWTerrain.height_at(t, p - Vector3(o[0], o[1], o[2]))

## Punkt na lądzie (teren ≥ 1 m nad wodą) w innej komórce niż start, w odległości d komórek – cel przejścia
## (sonda mierzy obraz po przejściu, nie upadek do morza).
func _land_point(from: Vector3, cells: float) -> Variant:
	var cs := MWCoords.CELL_SIZE / MWCoords.UNITS_PER_METER
	var c0 := MWCoords.cell_of(from)
	for k in [1.0, 1.25, 1.5, 0.75, 2.0]:
		for a in range(0, 360, 30):
			var p: Vector3 = from + Vector3(cos(deg_to_rad(float(a))), 0, sin(deg_to_rad(float(a)))) * cs * cells * float(k)
			if MWCoords.cell_of(p) == c0:
				continue
			var h := _terrain_h(p)
			if h > 1.0 and not main.db.get_cell(main.db.exterior_key(MWCoords.cell_of(p))).is_empty():
				return Vector3(p.x, h + 0.05, p.z)
	return null

func _run() -> void:
	out_dir = _arg("out", "/tmp/trans")
	save_png = _arg("png", "0") == "1"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var settle := int(_arg("settle", str(SETTLE)))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	await _frames(120)
	var ext_pos: Vector3 = main.player.global_position
	var ext_rot: float = main.player.rotation.y
	var cases := _arg("cases", "int,ext_door,int,ext,ext_far,neighbor").split(",")
	var int_name := _arg("interior", "Synthville, Test House")
	var int_pos = main.find_interior_position(int_name) if main.has_method("find_interior_position") else null
	var ip: Vector3 = int_pos if int_pos is Vector3 else Vector3.ZERO
	for c in cases:
		match c:
			"int":
				var d_ext := _door_to("int:")
				if d_ext != null:                       # drzwi świata → wnętrze (ActionTeleport jak w grze)
					await _case("int", func(): main.activate(d_ext), settle)
				else:
					await _case("int", func(): main.travel_to_cell(int_name, ip, 0.0), settle)
			"ext_door":
				var d_int := _door_to("")
				if d_int != null:                       # drzwi wnętrza → świat (wyjście ze statku)
					await _case("ext_door", func(): main.activate(d_int), settle)
			"int2":
				await _case("int2", func(): main.travel_to_cell(int_name, ip + Vector3(50, 0, 0), 90.0), settle)
			"ext":
				await _case("ext", func(): main.travel({"cell_key": "", "cell_name": "",
					"transform": Transform3D(Basis(Vector3.UP, ext_rot), ext_pos)}), settle)
			"ext_far":                                  # teleport (podróż, Interwencja, COC) na ląd 1–2 komórki dalej
				var far = _land_point(main.player.global_position, 1.0)
				if far == null:
					print("CASE ext_far: brak lądu w danych")
					continue
				await _case("ext_far", func(): main.travel({"cell_key": "", "cell_name": "",
					"transform": Transform3D(Basis(Vector3.UP, ext_rot), far)}), settle)
			"neighbor":                                 # przekroczenie granicy komórki (doczytanie siatki komórek)
				var nb = _land_point(main.player.global_position, 0.55)
				if nb == null:
					print("CASE neighbor: brak lądu w danych")
					continue
				await _case("neighbor", func(): main.player.global_position = nb, settle)
	var f := FileAccess.open(out_dir.path_join("transition.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
	var bad := 0
	for c in report.cases:
		bad += (c.bad_visible_frames as Array).size()
	print("RESULT ", JSON.stringify({"cases": report.cases.size(), "bad_visible_frames": bad}))
	quit(0)
