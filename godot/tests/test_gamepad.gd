extends SceneTree
## Etap 10: pad jak OpenMW 0.51 ControllerManager – domyślne przypisania (loadControllerDefaults), ruch lewą gałką
## (strefa martwa 0,1), rozglądanie prawą (oś × dt × 1000 × czułość / 256), w trybie GUI: krzyżak = strzałki,
## LB/RB = Shift+Tab/Tab, A = Spacja (kursor pada wył.) albo kliknięcie, B = wyjście z trybu, kursor z lewej gałki,
## pad nie steruje akcjami gry w trybie GUI; „Enable Controller” wyłącza pad; przypisanie klawisza nie usuwa pada.
## godot --headless --path godot -s res://tests/test_gamepad.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

const MWInput := preload("res://scripts/mw/mw_input.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _btn(b: JoyButton, pressed := true) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = pressed
	e.device = 0
	Input.parse_input_event(e)

func _tap(b: JoyButton) -> void:
	_btn(b, true)
	_btn(b, false)

func _axis(a: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = 0
	Input.parse_input_event(e)

static func _has_joy(action: String, kind: String, idx: int) -> bool:
	for e in InputMap.action_get_events(action):
		if kind == "button" and e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == idx:
			return true
		if kind == "axis" and e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == idx:
			return true
	return false

static func _devices_of(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			if not out.has(e.device):
				out.append(e.device)
	return out

func _run() -> void:
	MWInput.bindings_path = "user://test_gamepad_bindings.json"
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	var gp = main.gamepad
	check(gp != null and gp.enabled, "ControllerManager, pad włączony")
	# bez rozpoznanego pada (headless): zdarzenia pada w akcjach przypisane do żadnego urządzenia
	check(gp.device == gp.NO_DEVICE and _devices_of("activate") == [gp.NO_DEVICE], "bez kontrolera gry – pad nie steruje akcjami")
	check(gp.pick_device([0, 1, 2], func(id): return id == 1) == 1 and gp.pick_device([0], func(_id): return false) == gp.NO_DEVICE,
		"wybór pada: pierwszy rozpoznany kontroler gry (SDL_IsGameController)")
	# dalej jak z podłączonym rozpoznanym padem nr 0
	gp.set_meta("test_device", 0)
	gp.refresh_device()
	check(gp.device == 0 and _devices_of("activate") == [0], "pad 0 – zdarzenia akcji z tego urządzenia")
	# 1. domyślne przypisania
	check(_has_joy("activate", "button", JOY_BUTTON_A) and _has_joy("ready_weapon", "button", JOY_BUTTON_X)
		and _has_joy("ready_magic", "button", JOY_BUTTON_Y) and _has_joy("menu_mode", "button", JOY_BUTTON_B)
		and _has_joy("menu", "button", JOY_BUTTON_START) and _has_joy("journal", "button", JOY_BUTTON_LEFT_SHOULDER)
		and _has_joy("rest", "button", JOY_BUTTON_RIGHT_SHOULDER) and _has_joy("sneak", "button", JOY_BUTTON_LEFT_STICK)
		and _has_joy("quick_save", "button", JOY_BUTTON_GUIDE), "przyciski domyślne (loadControllerDefaults)")
	check(_has_joy("move_forward", "axis", JOY_AXIS_LEFT_Y) and _has_joy("move_right", "axis", JOY_AXIS_LEFT_X)
		and _has_joy("attack", "axis", JOY_AXIS_TRIGGER_RIGHT) and _has_joy("jump", "axis", JOY_AXIS_TRIGGER_LEFT), "osie domyślne")
	MWInput.set_binding("jump", KEY_K)
	check(MWInput.binding_code("jump") == KEY_K and _has_joy("jump", "axis", JOY_AXIS_TRIGGER_LEFT), "przypisanie klawisza nie usuwa pada")
	MWInput.reset_defaults()
	check(_has_joy("jump", "axis", JOY_AXIS_TRIGGER_LEFT) and MWInput.binding_code("jump") == KEY_E, "przywrócenie domyślnych – pad zostaje")
	# 2. w grze: ruch lewą gałką (strefa martwa), akcja z przycisku
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(2)
	check(Input.get_action_strength("move_forward") > 0.9 and main.player.move_input.y < -0.9, "lewa gałka – ruch do przodu (%s)" % main.player.move_input)
	_axis(JOY_AXIS_LEFT_Y, -0.05)
	await _frames(2)
	check(is_zero_approx(Input.get_action_strength("move_forward")), "strefa martwa 0,1")
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_btn(JOY_BUTTON_X)
	await _frames(1)
	check(Input.is_action_pressed("ready_weapon"), "X – akcja „broń” w grze")
	_btn(JOY_BUTTON_X, false)
	# 3. rozglądanie prawą gałką
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 1.0})
	var y0: float = main.player.rotation.y
	await _frames(3)
	check(main.player.rotation.y < y0 and gp.last_look.x > 0.0, "prawa gałka w prawo – obrót w prawo")
	var sens := float(main.settings.get("mouse_sensitivity", 0.0025)) / 0.0025
	check(gp.last_look_dt > 0.0 and absf(gp.last_look.x - gp.last_look_dt * 1000.0 * sens / 256.0) < 1e-5, "obrót = dt × 1000 / 256 na klatkę (%.4f, dt %.4f)" % [gp.last_look.x, gp.last_look_dt])
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 0.05})
	await _frames(2)
	var y1: float = main.player.rotation.y
	await _frames(2)
	check(is_equal_approx(main.player.rotation.y, y1), "prawa gałka w strefie martwej – bez obrotu")
	main.settings["invert_x"] = true
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 1.0})
	var y2: float = main.player.rotation.y
	await _frames(2)
	check(main.player.rotation.y > y2, "odwrócenie osi X dotyczy pada")
	main.settings["invert_x"] = false
	gp.set_meta("test_axes", {})
	# 4. tryb GUI: Tab/strzałki/Spacja, B, kursor
	main.open_settings()
	await _frames(3)
	var w = main.settings_window
	var vp := main.get_viewport()
	check(vp.gui_get_focus_owner() == w.ok_button, "okno opcji – fokus OK")
	_tap(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[0], "RB = Tab")
	_tap(JOY_BUTTON_DPAD_RIGHT)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[1], "krzyżak w prawo = strzałka")
	_tap(JOY_BUTTON_LEFT_SHOULDER)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[0], "LB = Shift+Tab")
	_tap(JOY_BUTTON_DPAD_RIGHT)
	gp.gui_cursor = false
	_tap(JOY_BUTTON_A)
	await _frames(1)
	check(w.current_page == 1, "A = Spacja (kursor pada wyłączony) – zakładka Audio")
	_tap(JOY_BUTTON_LEFT_STICK)
	await _frames(1)
	check(gp.gui_cursor, "wciśnięcie lewej gałki – kursor pada")
	gp.set_meta("test_axes", {JOY_AXIS_LEFT_X: 1.0})
	await _frames(3)
	check(gp._cursor.x > 0.0, "lewa gałka przesuwa kursor (%s)" % gp._cursor)
	gp.set_meta("test_axes", {})
	var menu_before: bool = main.menu_mode != null and main.menu_mode.visible
	_tap(JOY_BUTTON_B)
	await _frames(2)
	check(not w.visible and not main.gui.contains("settings"), "B – wyjście z trybu (okno opcji zamknięte)")
	check((main.menu_mode != null and main.menu_mode.visible) == menu_before, "B w trybie GUI nie otwiera ekwipunku (akcja gry)")
	# 5. Enable Controller = Off
	main.settings["enable_controller"] = false
	main.apply_live_settings()
	check(not gp.enabled, "Enable Controller wyłączony")
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 1.0})
	var y3: float = main.player.rotation.y
	await _frames(2)
	check(is_equal_approx(main.player.rotation.y, y3), "pad wyłączony – bez obrotu")
	gp.set_meta("test_axes", {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MWInput.bindings_path))
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
