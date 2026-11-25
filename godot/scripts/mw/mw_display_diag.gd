extends Node
## Diagnostyka trybów okna i rozdzielczości na sprzęcie użytkownika (`--diag-display`, etap 10 P3): po kolei
## okno 1280 × 720, 2560 × 1440, 3440 × 1440, 3840 × 2160 (o ile mieści się na ekranie), pełny ekran w oknie, pełny
## ekran wyłączny i powrót do okna – przez main.apply_display (ta sama ścieżka co okno opcji). Po każdym kroku
## (45 klatek) wiersz `MWGODOT_DISPLAYDIAG` z liczbami: tryb, rozmiar i położenie okna, ekran, obszar roboczy,
## rozmiar widoku, skala interfejsu, prostokąty HUD (paski, minimapa, celownik), wyśrodkowanie okna. Bez zrzutów.
## Na końcu przywraca ustawienia sprzed testu (bez zapisu do pliku).

const STEPS := [["windowed", "1280x720"], ["windowed", "2560x1440"], ["windowed", "3440x1440"],
	["windowed", "3840x2160"], ["fullscreen", ""], ["exclusive", ""], ["windowed", "1280x720"], ["fullscreen", ""]]
const WAIT := 45

var main
var quit_after := false
var _step := -1
var _frames := 0
var _saved := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_dt: float) -> void:
	if main == null or String(main.get("game_state")) != "running":
		return
	if _step < 0:
		_frames += 1
		if _frames < 120:
			return
		_saved = {"window_mode": main.settings.get("window_mode", "windowed"), "resolution": main.settings.get("resolution", "1280x720")}
		print("MWGODOT_DISPLAYDIAG begin ", JSON.stringify(_saved), " screens=", DisplayServer.get_screen_count(), " server=", DisplayServer.get_name())
		_next()
		return
	_frames += 1
	if _frames < WAIT:
		return
	_report()
	_next()

func _next() -> void:
	_step += 1
	_frames = 0
	if _step >= STEPS.size():
		main.settings["window_mode"] = _saved.get("window_mode", "windowed")
		main.settings["resolution"] = _saved.get("resolution", "1280x720")
		main.apply_display()
		print("MWGODOT_DISPLAYDIAG end")
		set_process(false)
		if quit_after:
			await get_tree().create_timer(1.0).timeout
			get_tree().quit()
		return
	var st: Array = STEPS[_step]
	main.settings["window_mode"] = st[0]
	if not String(st[1]).is_empty():
		main.settings["resolution"] = st[1]
	main.apply_display()

static func _r(c: Control) -> Array:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return []
	var r := c.get_global_rect()
	return [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]

func _report() -> void:
	var st: Array = STEPS[_step]
	var scr := DisplayServer.window_get_current_screen()
	var ws := DisplayServer.window_get_size()
	var wp := DisplayServer.window_get_position()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	var vs := get_viewport().get_visible_rect().size
	var row := {"step": _step, "want": st, "mode": DisplayServer.window_get_mode(), "win": [ws.x, ws.y], "pos": [wp.x, wp.y],
		"screen": [DisplayServer.screen_get_size(scr).x, DisplayServer.screen_get_size(scr).y],
		"usable": [usable.position.x, usable.position.y, usable.size.x, usable.size.y], "vp": [roundi(vs.x), roundi(vs.y)],
		"ui_scale": preload("res://scripts/mw/mw_ui.gd").ui_scale(), "screen_scale": DisplayServer.screen_get_scale(scr)}
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and usable.size.x > 0:
		var c := Vector2i(usable.position + (usable.size - ws).max(Vector2i.ZERO) / 2)
		row["center_err"] = [wp.x - c.x, wp.y - c.y]
	var hud = main.get("mw_hud")
	if hud != null and hud.root != null:
		var h := {}
		for n in ["Bar_health", "Bar_magicka", "Bar_fatigue", "MiniMap", "EffectBox"]:
			var c := hud.root.find_child(n, true, false) as Control
			if c != null:
				h[n] = _r(c)
		if hud.get("crosshair") != null and hud.crosshair is Control:
			h["crosshair"] = _r(hud.crosshair)
		row["hud"] = h
	print("MWGODOT_DISPLAYDIAG ", JSON.stringify(row))
