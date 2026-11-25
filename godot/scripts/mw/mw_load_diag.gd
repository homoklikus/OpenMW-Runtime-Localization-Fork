extends Node
## Diagnostyka wczytania zapisu / przejścia na sprzęcie użytkownika (`--load-diag`): od rozpoczęcia wczytania przez
## FRAMES klatek po zdjęciu ekranu ładowania zapisuje co klatkę liczby (czas klatki, kompilacje potoków shaderów wg
## rodzaju, obiekty/wywołania rysowania, pamięć wideo, zasłona ekranu ładowania, zaciemnienie, komórki, kamera, HUD)
## jako wiersze `MWGODOT_LOADDIAG` w logu gry. Zrzuty wybranych klatek (4 pierwsze zasłonięte, 12 pierwszych
## odsłoniętych, potem co 15.) – tylko lokalnie w user://load_diag/<czas>/ (obraz gry nie opuszcza komputera).
## Nie zmienia przebiegu gry.

const FRAMES := 180                 # klatek po odsłonięciu
const SHOT_FIRST := 12

var main
var active := false
var _tag := ""
var _t0 := 0
var _last_us := 0
var _after := -1                    # klatki od odsłonięcia (−1 – jeszcze zasłonięte)
var _i := 0
var _dir := ""
var _prev_cover := false
var _covered := 0
var menu_load := ""                 # --diag-menu-load=<zapis>: wczytanie jak kliknięcie zapisu w menu głównym (MCP)
var quit_after := false
var shots := false                  # --load-diag-shots: zapis zrzutów PNG (lokalnie; spowalnia klatki)             # --diag-quit: zamknięcie gry po zakończeniu pomiaru
var _menu_frames := 0

func begin(tag: String) -> void:
	_tag = tag
	_t0 = Time.get_ticks_msec()
	_last_us = Time.get_ticks_usec()
	_after = -1
	_i = 0
	_prev_cover = true
	_covered = 0
	_dir = ProjectSettings.globalize_path("user://load_diag").path_join(
		Time.get_datetime_string_from_system().replace(":", "-") + "_" + tag)
	DirAccess.make_dir_recursive_absolute(_dir)
	if not active:
		active = true
		if not RenderingServer.frame_post_draw.is_connected(_on_post_draw):
			RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("MWGODOT_LOADDIAG begin ", tag, " renderer=", RenderingServer.get_current_rendering_driver_name(), "/",
		RenderingServer.get_current_rendering_method(), " gpu=", RenderingServer.get_video_adapter_name(),
		" size=", get_viewport().get_visible_rect().size, " zrzuty=", _dir)

## Samodzielny test bez klikania (MCP): po 120 klatkach otwartego menu głównego bez gry – ta sama ścieżka co
## wybór zapisu w oknie wczytywania (mw_save_dialog → main.load_slot).
func _process(_dt: float) -> void:
	if menu_load.is_empty() or main == null:
		return
	if String(main.get("game_state")) != "nogame" or main.main_menu == null or not main.main_menu.is_open():
		_menu_frames = 0
		return
	_menu_frames += 1
	if _menu_frames >= 120:
		var p := menu_load
		menu_load = ""
		main.close_main_menu()               # SaveGameDialog::accept: zamknięcie okien menu, potem loadGame
		main.load_slot(null, p)

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)

static func _ri(k: int) -> int:
	return RenderingServer.get_rendering_info(k)

func _on_post_draw() -> void:
	if not active or main == null or not is_instance_valid(main):
		return
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0
	_last_us = now
	var ld = main.get("loading")
	var cover: bool = ld != null and ld.visible
	if not cover and _after < 0:
		_after = 0
	elif _after >= 0:
		_after += 1
	var cam: Camera3D = get_viewport().get_camera_3d()
	var hud = main.get("mw_hud")
	var row := {
		"i": _i, "ms": Time.get_ticks_msec() - _t0, "dt": snappedf(dt_ms, 0.01), "after": _after, "cover": cover,
		"fade": snappedf(float(main.fader.alpha), 0.01) if main.get("fader") != null else 0.0,
		"pipe_canvas": _ri(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		"pipe_mesh": _ri(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"pipe_surface": _ri(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"pipe_draw": _ri(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"pipe_spec": _ri(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
		"objects": _ri(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"draws": _ri(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": _ri(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"vram_mb": snappedf(_ri(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"cells": (main.loaded as Dictionary).size() if main.get("loaded") != null else 0,
		"revealing": main.is_revealing() if main.has_method("is_revealing") else false,
		"hud": hud != null and hud.root != null and hud.root.is_visible_in_tree(),
		"cam": str(cam.global_position.snapped(Vector3.ONE * 0.01)) if cam != null else "",
		"state": String(main.get("game_state")),
		"wallpaper": ld != null and bool(ld.show_wallpaper),
		"splash": ld != null and ld._splash_rect != null and ld._splash_rect.visible and ld._splash_rect.texture != null,
		"nested": int(ld.nested) if ld != null else 0}
	# Statystyki obrazu (tylko liczby: średnia jasność i odchylenie pasów lewy 12% / środek / prawy 12% oraz udział
	# czarnych pikseli) – czy zasłona ekranu ładowania pokrywa cały ekran 21:9 i co faktycznie jest w klatce.
	var probe := cover or (_after >= 0 and _after < 4) or (_after > 0 and _after % 30 == 0)
	if probe:
		var vt := get_viewport().get_texture()
		var img: Image = vt.get_image() if vt != null else null
		if img != null and not img.is_empty():
			row["img"] = _stats(img)
			if shots and ((cover and _covered < 4) or (_after >= 0 and _after < SHOT_FIRST)):
				img.save_png(_dir.path_join("%03d_%s.png" % [_i, "covered" if cover else "after%03d" % _after]))
	if _after == 1 or _i == 0:
		row["covering"] = _full_screen_items()
	if cover:
		_covered += 1
	print("MWGODOT_LOADDIAG ", JSON.stringify(row))
	_prev_cover = cover
	_i += 1
	if _after >= FRAMES:
		active = false
		print("MWGODOT_LOADDIAG end ", _tag, " klatek=", _i)
		if quit_after:
			get_tree().quit()

## Widoczne kontrolki pokrywające ≥ 60% ekranu (ścieżki węzłów, warstwa) – co zasłania świat.
func _full_screen_items() -> Array:
	var out := []
	var vs := get_viewport().get_visible_rect().size
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		if n is CanvasLayer and not (n as CanvasLayer).visible:
			continue
		if n is Control:
			var r := (n as Control).get_global_rect()
			if r.size.x * r.size.y >= vs.x * vs.y * 0.6 and ((n is TextureRect and (n as TextureRect).texture != null) or n is ColorRect or n is Panel):
				var layer = (n as Control).get_canvas_layer_node()
				out.append("%s L%s a%.2f" % [str(n.get_path()).substr(0, 90), str(layer.layer) if layer != null else "-", (n as CanvasItem).modulate.a])
		for c in n.get_children():
			stack.push_back(c)
	return out

static func _stats(src: Image) -> Dictionary:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(172, 72, Image.INTERPOLATE_NEAREST)
	var w := img.get_width()
	var h := img.get_height()
	var band := int(w * 0.12)
	var out := {}
	for part in [["l", 0, band], ["c", band, w - band], ["r", w - band, w]]:
		var sum := 0.0
		var sq := 0.0
		var dark := 0
		var n := 0
		for y in range(0, h, 2):
			for x in range(int(part[1]), int(part[2]), 2):
				var c := img.get_pixel(x, y)
				var l := c.get_luminance() * 255.0
				sum += l
				sq += l * l
				if l < 6.0:
					dark += 1
				n += 1
		var m := sum / maxf(1.0, n)
		out[part[0]] = [snappedf(m, 0.1), snappedf(sqrt(maxf(0.0, sq / maxf(1.0, n) - m * m)), 0.1), snappedf(float(dark) / maxf(1.0, n), 0.01)]
	var sig := []                     # zgrubna sygnatura 8 × 4 (średnie jasności) – porównanie klatek między sobą
	for gy in 4:
		for gx in 8:
			var acc := 0.0
			var k := 0
			for y in range(gy * h / 4, (gy + 1) * h / 4, 3):
				for x in range(gx * w / 8, (gx + 1) * w / 8, 3):
					acc += img.get_pixel(x, y).get_luminance() * 255.0
					k += 1
			sig.append(int(acc / maxf(1.0, k)))
	out["sig"] = sig
	out["size"] = [src.get_width(), src.get_height()]
	out["drawn"] = Engine.get_frames_drawn()
	return out

func _save_shot(name: String, img: Image) -> void:
	if img == null:
		var vt := get_viewport().get_texture()
		img = vt.get_image() if vt != null else null
	if img == null or img.is_empty():
		return
	img.save_png(_dir.path_join(name + ".png"))
