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
	print("MWGODOT_LOADDIAG ", JSON.stringify(row))
	var shot := (cover and _covered < 4) or (_after >= 0 and _after < SHOT_FIRST) or (_after > 0 and _after % 15 == 0)
	if cover:
		_covered += 1
	if shot:
		_save_shot("%03d_%s" % [_i, "covered" if cover else "after%03d" % _after], null)
	_prev_cover = cover
	_i += 1
	if _after >= FRAMES:
		active = false
		print("MWGODOT_LOADDIAG end ", _tag, " klatek=", _i)

func _save_shot(name: String, img: Image) -> void:
	if img == null:
		var vt := get_viewport().get_texture()
		img = vt.get_image() if vt != null else null
	if img == null or img.is_empty():
		return
	img.save_png(_dir.path_join(name + ".png"))
