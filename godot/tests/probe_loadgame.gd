extends SceneTree
## Sonda wczytywania zapisu (etap 10, P0 „glitche podczas wczytywania gry”): zapis każdej narysowanej klatki od
## rozpoczęcia wczytania do ustalenia się obrazu – także klatek rysowanych przez ekran ładowania w trakcie
## synchronicznego ładowania. Klatka jest „pokazana graczowi”, gdy ekran ładowania jej nie zasłaniał.
## Błąd (klatka z niekompletnym światem):
##  * pokazana klatka po ekranie ładowania różni się od obrazu ustalonego (> DIFF_BAD) albo ma inną kamerę,
##    inną liczbę komórek niż stan ustalony, gracza w powietrzu (fizyka nie postawiła go jeszcze na podłożu);
##  * pokazana klatka między początkiem wczytania a ekranem ładowania pokazuje coś innego niż obraz sprzed wczytania
##    (np. stary świat już usunięty);
##  * w drzewie zostały węzły komórek spoza `main.loaded` (zdublowana geometria – migotanie z-fighting).
## Wymaga renderera (Xvfb + lavapipe albo GPU). Wynik: <out>/loadgame.json; PNG klatek (--png=1) zostają lokalnie.
## godot --path godot -s res://tests/probe_loadgame.gd -- --data=… --pos=… --out=/tmp/lg [--png=1] [--size=3440x1440]
##   [--cases=prepare,ingame_ext,ingame_int,same,other,menu_int,menu_ext,after_travel]
## Tryb startu z zapisem (jak `--load`): -- --data=… --load=<plik> --out=… --mode=start (pomiar od pierwszej klatki).

const SETTLE := 90
const DIFF_BAD := 0.06
const CAM_BAD := 0.05                # m – kamera pokazanej klatki dalej od ustalonej
const AIR_BAD := 0.25                # m – stopy gracza nad ustaloną pozycją (spadanie po odsłonięciu)

var main
var out_dir := ""
var save_png := false
var frames: Array = []
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

## Węzły komórek w drzewie (dzieci main z węzłem „Refs”) – porównanie z main.loaded wykrywa duplikaty.
func _cell_nodes() -> int:
	var n := 0
	for c in main.get_children():
		if c.get_node_or_null("Refs") != null and not c.is_queued_for_deletion():
			n += 1
	return n

func _on_post_draw() -> void:
	if not _capturing or main == null or not is_instance_valid(main):
		return
	var vt := root.get_viewport().get_texture()
	var img: Image = vt.get_image() if vt != null else null
	if img == null or img.is_empty():
		return
	img.resize(160, int(160.0 * img.get_height() / maxf(1.0, img.get_width())), Image.INTERPOLATE_BILINEAR)
	var ld = main.get("loading")
	var pl = main.get("player")
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var menu = main.get("main_menu")
	frames.append({"i": _i, "t": Time.get_ticks_msec(), "loading": ld != null and ld.visible,
		"wallpaper": ld != null and ld.visible and bool(ld.show_wallpaper),
		"menu": menu != null and menu.has_method("is_open") and menu.is_open(),
		"cells": (main.loaded as Dictionary).size() if main.get("loaded") != null else 0,
		"cell_nodes": _cell_nodes(),
		"pos": pl.global_position if pl != null else Vector3.ZERO,
		"cam": cam.global_position if cam != null else Vector3.ZERO,
		"cam_rot": cam.global_rotation if cam != null else Vector3.ZERO,
		"state": String(main.get("game_state")),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"pipelines": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)
			+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE)
			+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
			+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
		"fade": main.fader.alpha if main.get("fader") != null else 0.0,
		"vis": _visible_counts(),
		"hud": main.get("mw_hud") != null and main.mw_hud.root != null and main.mw_hud.root.is_visible_in_tree(),
		"weather": [String(main.envr.weather), int(main.envr.wm.current), int(main.envr.wm.next_w)] if main.get("envr") != null else [],
		"img": img})
	_i += 1

## Widoczne w drzewie: siatki (statyczne / aktorów), cząsteczki, światła – co zmienia się po odsłonięciu.
func _visible_counts() -> Dictionary:
	var c := {"mesh": 0, "actor_mesh": 0, "particles": 0, "lights": 0, "actors_hidden": 0}
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for r in refs.get_children():
			var actor: bool = r.has_meta("mw_actor")
			if actor and r is Node3D and not (r as Node3D).is_visible_in_tree():
				c.actors_hidden += 1
			for n in r.find_children("*", "VisualInstance3D", true, false):
				if not (n as Node3D).is_visible_in_tree():
					continue
				if n is MeshInstance3D:
					c["actor_mesh" if actor else "mesh"] += 1
				elif n is GPUParticles3D or n is CPUParticles3D:
					c.particles += 1
				elif n is Light3D:
					c.lights += 1
	return c

static func _diff(a: Image, b: Image, fade := 0.0) -> float:
	if a.get_size() != b.get_size():
		return 1.0
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

func _analyse(name: String, pre: Image, t0: int) -> void:
	var final: Dictionary = frames.back() if not frames.is_empty() else {}
	var rows := []
	var bad := []
	var first_cover := -1
	var last_cover := -1
	for f in frames:
		if bool(f.loading):
			if first_cover < 0:
				first_cover = int(f.i)
			last_cover = int(f.i)
	var first_visible_after := -1
	for f in frames:
		var shown := not bool(f.loading)
		var why := []
		var d := 0.0
		if shown and last_cover >= 0 and int(f.i) > last_cover:
			if first_visible_after < 0:
				first_visible_after = int(f.i)
			d = _diff(f.img, final.img, float(f.fade))
			if d > DIFF_BAD:
				why.append("obraz")
			if (f.cam as Vector3).distance_to(final.cam) > CAM_BAD:
				why.append("kamera")
			if bool(f.hud) != bool(final.hud):
				why.append("HUD")
			if str(f.weather) != str(final.weather):
				why.append("pogoda")
			if int(f.cells) != int(final.cells):
				why.append("komórki")
			if float((f.pos as Vector3).y) - float((final.pos as Vector3).y) > AIR_BAD:
				why.append("w powietrzu")
		elif shown and (first_cover < 0 or int(f.i) < first_cover) and pre != null:
			d = _diff(f.img, pre)              # przed zasłonięciem: ten sam obraz co przed wczytaniem
			if d > DIFF_BAD and first_cover >= 0:
				why.append("przed zasłonięciem")
			elif first_cover < 0:
				why.append("brak ekranu ładowania")
		if int(f.cell_nodes) != int(f.cells) and not bool(f.loading):
			why.append("duplikat komórek %d/%d" % [f.cell_nodes, f.cells])
		if not why.is_empty():
			bad.append({"i": f.i, "why": why})
		rows.append({"i": f.i, "ms": int(f.t) - t0, "loading": f.loading, "wallpaper": f.wallpaper, "menu": f.menu,
			"cells": f.cells, "cell_nodes": f.cell_nodes, "diff": snappedf(d, 0.0001), "objects": f.objects,
			"pipelines": f.pipelines, "vis": f.vis, "hud": f.hud, "weather": f.weather, "fade": snappedf(float(f.fade), 0.01), "pos": str(f.pos), "cam": str(f.cam),
			"state": f.state})
		if save_png:
			f.img.save_png(out_dir.path_join("%s_%03d%s.png" % [name, int(f.i), "_L" if f.loading else ""]))
	var wall := frames.filter(func(f): return bool(f.wallpaper)).size()
	report.cases.append({"name": name, "frames": rows.size(), "first_cover": first_cover, "last_cover": last_cover,
		"first_visible_after": first_visible_after, "wallpaper_frames": wall,
		"reveal_frames": int(main.get("reveal_frames_last")), "bad": bad, "rows": rows})
	print("CASE %s frames=%d cover=%d..%d wallpaper=%d first_visible=%d bad=%s" % [name, rows.size(), first_cover,
		last_cover, wall, first_visible_after, JSON.stringify(bad)])

func _case(name: String, action: Callable, settle: int) -> void:
	await _frames(3)
	var vt := root.get_viewport().get_texture()
	var pre: Image = vt.get_image() if vt != null else null
	if pre != null and not pre.is_empty():
		pre.resize(160, int(160.0 * pre.get_height() / maxf(1.0, pre.get_width())), Image.INTERPOLATE_BILINEAR)
	frames.clear()
	_i = 0
	_capturing = true
	var t0 := Time.get_ticks_msec()
	action.call()
	for k in main.loaded:
		_freeze_cell(k)
	if _arg("noshadow") == "1":                 # diagnostyka: bez cieni świateł (czy różnica pierwszej klatki to cienie)
		for n in main.find_children("*", "Light3D", true, false):
			(n as Light3D).shadow_enabled = false
	await _frames(settle)
	while main.is_revealing():
		await process_frame
	await _frames(20)
	_capturing = false
	_analyse(name, pre, t0)

## Aktorzy zamrożeni w pozycjach z zapisu (jak tryb zrzutu porównawczego) – ruch NPC po odsłonięciu nie jest
## błędem wczytania, a zaciemniałby porównanie z obrazem ustalonym.
func _freeze_cell(key: String) -> void:
	if not main.loaded.has(key):
		return
	for a in main.loaded[key].get_node("Refs").get_children():
		if a.has_meta("mw_actor"):
			a.set_physics_process(false)
			a.set_process(false)

func _set_size() -> void:
	var s := _arg("size", "1280x720").split("x")
	var sz := Vector2i(int(s[0]), int(s[1]))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(sz)
	root.size = sz

func _write() -> int:
	var f := FileAccess.open(out_dir.path_join("loadgame.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
	var bad := 0
	for c in report.cases:
		bad += (c.bad as Array).size()
	print("RESULT ", JSON.stringify({"cases": report.cases.size(), "bad_visible_frames": bad}))
	return bad

func _run() -> void:
	out_dir = _arg("out", "/tmp/lg")
	save_png = _arg("png", "0") == "1"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_set_size()
	var settle := int(_arg("settle", str(SETTLE)))
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.ready.connect(func(): main.events.cell_loaded.connect(_freeze_cell))
	if _arg("mode") == "start":
		# start z `--load`: pierwsza narysowana klatka już po _ready (wczytanie w trakcie startu)
		frames.clear()
		_capturing = true
		var t0 := Time.get_ticks_msec()
		root.add_child(main)
		for k in main.loaded:
			_freeze_cell(k)
		await _frames(settle)
		while main.is_revealing():
			await process_frame
		await _frames(20)
		_capturing = false
		_analyse("start_load", null, t0)
		quit(1 if _write() > 0 else 0)
		return
	root.add_child(main)
	await _frames(120)
	var sv := _arg("saves", ProjectSettings.globalize_path("user://probe_loadgame"))
	DirAccess.make_dir_recursive_absolute(sv)
	var p_ext := sv.path_join("ext.mwsave")
	var p_int := sv.path_join("int.mwsave")
	var int_name := _arg("interior", "Synthville, Test House")
	var int_pos = main.find_interior_position(int_name)
	var ip: Vector3 = int_pos if int_pos is Vector3 else Vector3(0, 0, 300)
	# --reuse=1: zapisy z wcześniejszego uruchomienia (przypadki w osobnych procesach – limit czasu VM)
	if not (_arg("reuse") == "1" and FileAccess.file_exists(p_ext) and FileAccess.file_exists(p_int)):
		main.save_game(p_ext)
		main.travel_to_cell(int_name, ip, 0.0)
		while main.is_revealing():
			await process_frame
		await _frames(30)
		main.save_game(p_int)
	print("SAVES ", p_ext, " ", p_int, " interior=", main.interior, " cells=", main.loaded.size())
	var cases := _arg("cases", "ingame_ext,ingame_int,same,other,menu_int,menu_ext,nogame,after_travel").split(",")
	for c in cases:
		match c:
			"ingame_ext":
				await _case(c, func(): main.load_slot(null, p_ext), settle)
			"ingame_int":
				await _case(c, func(): main.load_slot(null, p_int), settle)
			"same":
				await _case(c, func(): main.load_slot(null, p_int), settle)
			"other":
				await _case(c, func(): main.load_slot(null, p_ext), settle)
			"menu_int", "menu_ext":
				main.open_main_menu()             # Esc → menu główne → Wczytaj (load_slot po zamknięciu menu)
				await _frames(5)
				var p := p_int if c == "menu_int" else p_ext
				await _case(c, func():
					main.close_main_menu()
					main.load_slot(null, p), settle)
			"nogame":                              # menu główne bez gry (start do menu) → Wczytaj
				main.cleanup()
				main._enter_nogame()
				main.open_main_menu()
				await _frames(10)
				await _case(c, func():
					main.close_main_menu()
					main.load_slot(null, p_int), settle)
			"prepare":
				pass
			"after_travel":
				main.travel_to_cell(int_name, ip + Vector3(80, 0, 0), 45.0)
				while main.is_revealing():
					await process_frame
				await _frames(10)
				await _case(c, func(): main.load_slot(null, p_ext), settle)
	quit(1 if _write() > 0 else 0)
