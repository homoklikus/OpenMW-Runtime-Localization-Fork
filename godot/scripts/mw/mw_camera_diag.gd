extends Node
## Diagnostyka kamery trzeciej osoby na sprzęcie użytkownika (--camera-diag): po wczytaniu sekwencja jak gracz –
## TogglePOV krótko (trzecia osoba), oddalenie kółkiem, podgląd z obrotem, ruch do przodu, powrót do pierwszej osoby;
## z --diag-death na końcu śmierć gracza (kamera śmierci, grupa animacji, czas do askLoadRecent). Wiersze
## `MWGODOT_CAMDIAG` – tylko tryby, liczby i nazwy grup animacji (bez tekstów i zasobów gry). --diag-seconds=N – koniec.

var main
var death := false
var seconds := 0.0
var _t := 0.0
var _start := -1.0
var _step := 0
var _tick := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log({"ev": "start", "death": death})

func _log(row: Dictionary) -> void:
	row["t"] = snappedf(_t, 0.01)
	print("MWGODOT_CAMDIAG ", JSON.stringify(row))

func _state(ev: String) -> Dictionary:
	var pc = main.player_camera()
	var b = main.player_body
	var ap: AnimationPlayer = b.player() if b != null else null
	var groups := {"death": 0, "walk": 0, "run": 0, "sneak": 0, "swim": 0, "jump": 0, "total": 0}
	if ap != null:
		for n in ap.get_animation_list():
			var s := String(n)
			groups.total += 1
			for k in ["death", "walk", "run", "sneak", "swim", "jump"]:
				if s.begins_with(k):
					groups[k] += 1
	return {"ev": ev, "mode": pc.mode, "primary": pc.primary, "queued": pc.queued, "base": pc.base_distance,
		"dist": snappedf(pc.camera_distance, 0.1), "view_current": pc.view.current, "eye_current": pc.eye.current,
		"body": b != null and b.model != null, "shown": b != null and b.shown, "anim": b.current if b != null else "",
		"groups": groups, "crosshair": main.mw_hud.crosshair.visible if main.mw_hud != null else null,
		"listener": pc.listener.is_current(), "fps": Engine.get_frames_per_second(), "state": main.game_state}

func _process(dt: float) -> void:
	_t += dt
	if seconds > 0.0 and _t >= seconds:
		_log({"ev": "quit"})
		get_tree().quit()
		return
	if main.player == null or main.game_state != "running" and _step < 9 or main.is_revealing() \
			or (main.loading != null and main.loading.visible):
		return
	if _start < 0.0:
		_start = _t
		_log(_state("loaded"))
	var e := _t - _start
	_tick += dt
	if _tick >= 1.0:
		_tick = 0.0
		_log(_state("tick"))
	var pc = main.player_camera()
	match _step:
		0:
			if e > 2.0:
				Input.action_press("toggle_pov")
				_step = 1
		1:
			if e > 2.1:
				Input.action_release("toggle_pov")
				_step = 2
		2:
			if e > 3.0:
				_log(_state("after_tap"))
				for i in 5:
					pc.add_zoom(-1.0)
				_step = 3
		3:
			if e > 4.0:
				_log(_state("after_zoom_out"))
				Input.action_press("toggle_pov")
				_step = 4
		4:
			if e > 4.5:
				main.player.controller.look(0.8, 0.0)
				_log(_state("preview"))
				_step = 5
		5:
			if e > 5.0:
				Input.action_release("toggle_pov")
				_step = 6
		6:
			if e > 6.5:
				_log(_state("after_preview"))
				Input.action_press("move_forward")
				_step = 7
		7:
			if e > 8.0:
				_log(_state("walking"))
				Input.action_release("move_forward")
				_step = 8
		8:
			if e > 9.0:
				if death:
					main._player_died()
					var b = main.player_body
					var ap: AnimationPlayer = b.player()
					_log({"ev": "death", "group": b.death_group, "len": ap.get_animation(b.death_group).length if ap != null and ap.has_animation(b.death_group) else 0.0, "mode": pc.mode})
				else:
					pc.zoom(-10.0)
					for i in 100:
						pc.zoom(10.0)
					_log(_state("zoomed_to_first"))
				_step = 9
		9:
			if e > 12.0:
				_log(_state("end"))
				_step = 10
