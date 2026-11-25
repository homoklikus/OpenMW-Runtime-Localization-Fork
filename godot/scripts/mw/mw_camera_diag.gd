extends Node
## Diagnostyka kamery trzeciej osoby na sprzęcie użytkownika (--camera-diag): po wczytaniu sekwencja jak gracz –
## TogglePOV krótko (trzecia osoba), oddalenie kółkiem, podgląd z obrotem, ruch do przodu, powrót do pierwszej osoby;
## z --diag-death na końcu śmierć gracza (kamera śmierci, grupa animacji, czas do askLoadRecent). Wiersze
## `MWGODOT_CAMDIAG` – tylko tryby, liczby i nazwy grup animacji (bez tekstów i zasobów gry). --diag-seconds=N – koniec.

var main
var death := false
var water := false                       # --water-diag: wysokości terenu wokół gracza względem poziomu wody
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
		"body": b != null and b.model != null, "shown": b != null and b.shown, "anim": b.current if b != null else "", "rebuilds": b.rebuilds if b != null else 0,
		"changes": b.changes if b != null else 0, "last": b.last_changes if b != null else [],
		"pos": ap.current_animation_position if ap != null else 0.0, "speed": ap.speed_scale if ap != null else 0.0,
		"floor": main.player.is_on_floor(),
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
		if water:
			_water_report()
	var e := _t - _start
	_tick += dt
	if _tick >= (0.2 if _step == 7 else 1.0):
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
				Input.action_press("run")
				_step = 7
		7:
			if e > 10.0:
				_log(_state("walking"))
				Input.action_release("move_forward")
				Input.action_release("run")
				_step = 8
		8:
			if e > 11.0:
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
			if e > 14.0:
				_log(_state("end"))
				_step = 10

## Teren wokół gracza (promień 50 m, co 0,5 m – promienie w dół) względem poziomu wody komórki: ile punktów leży
## blisko płaszczyzny wody (ryzyko migotania głębi), ile bez terenu (dziury – widać płaszczyznę wody).
func _water_report() -> void:
	var pl: CharacterBody3D = main.player
	var wl := float(pl.get("water_level"))
	var space := pl.get_world_3d().direct_space_state
	var c := pl.global_position
	var hist := {"lt_1cm": 0, "lt_5cm": 0, "lt_20cm": 0, "below": 0, "above": 0, "miss": 0, "n": 0}
	var mn := INF
	var mx := -INF
	var near_pts := []
	var x := -50.0
	while x <= 50.0:
		var z := -50.0
		while z <= 50.0:
			var from := c + Vector3(x, 60.0, z)
			var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 200.0, 0))
			q.exclude = [pl.get_rid()]
			var hit := space.intersect_ray(q)
			hist.n += 1
			if hit.is_empty():
				hist.miss += 1
			else:
				var col: Object = hit.collider
				var is_terrain: bool = col is Node and String((col as Node).get_parent().name).begins_with("Terrain")
				if not is_terrain:
					# pod obiektem – drugi promień tylko po teren nie jest potrzebny do statystyki: pomiń
					pass
				else:
					var h: float = (hit.position as Vector3).y
					mn = minf(mn, h)
					mx = maxf(mx, h)
					var d := absf(h - wl)
					if d < 0.01:
						hist.lt_1cm += 1
					if d < 0.05:
						hist.lt_5cm += 1
						if near_pts.size() < 12:
							near_pts.append([snappedf(x, 0.5), snappedf(z, 0.5), snappedf(h - wl, 0.001)])
					if d < 0.2:
						hist.lt_20cm += 1
					if h < wl:
						hist.below += 1
					else:
						hist.above += 1
			z += 0.5
		x += 0.5
	var cam: Camera3D = main.view_camera()
	_log({"ev": "water", "water_level": wl, "player_y": snappedf(c.y, 0.01), "terrain_min": snappedf(mn, 0.01),
		"terrain_max": snappedf(mx, 0.01), "hist": hist, "near_pts": near_pts, "near": cam.near, "far": cam.far,
		"interior": main.get("interior"), "waters": _water_planes()})

func _water_planes() -> Array:
	var out := []
	for w in main.get_tree().root.find_children("Water", "MeshInstance3D", true, false):
		if w.has_meta("mw_water") and (w as Node3D).is_visible_in_tree():
			var mi := w as MeshInstance3D
			out.append([snappedf(mi.global_position.x, 0.1), snappedf(mi.global_position.y, 0.001), snappedf(mi.global_position.z, 0.1),
				(mi.mesh as PlaneMesh).size.x if mi.mesh is PlaneMesh else 0.0])
	return out
