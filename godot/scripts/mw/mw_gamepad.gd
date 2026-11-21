extends Node
## Pad jak OpenMW 0.51 (apps/openmw/mwinput/controllermanager.cpp, bindingsmanager.cpp loadControllerDefaults,
## mousemanager.cpp update; [Input] enable controller, joystick dead zone 0.1, gamepad cursor speed 1.0;
## [GUI] controller menus = false – menu sterowane jak klawiaturą):
##  - w grze: lewa gałka – ruch (A_MoveForwardBackward / A_MoveLeftRight), prawa – rozglądanie
##    (obrót = oś × dt × 1000 × camera sensitivity / 256 rad, odwrócenie osi X/Y, camera y multiplier), przyciski
##    domyślne: A aktywacja, X broń, Y magia, B ekwipunek (tryb menu), Start menu gry, Guide szybki zapis, LB dziennik,
##    RB odpoczynek, lewa gałka (wciśnięcie) skradanie, prawy spust atak/użycie, lewy spust skok;
##  - w trybie GUI (gamepadToGuiControl): krzyżak = strzałki, A = Spacja (albo kliknięcie, gdy kursor pada
##    włączony), B = wyjście z okna modalnego / trybu (exitCurrentModal / exitCurrentGuiMode), LB = Shift+Tab,
##    RB = Tab, wciśnięcie lewej gałki – kursor pada wł./wył.; lewa gałka przesuwa kursor (oś × dt × 1500 / skala
##    interfejsu × gamepad cursor speed, wolniej z prawym spustem: × (1,5 − spust)), prawa gałka (Y) – kółko myszy;
##  - przyciski pada w trybie GUI nie trafiają do akcji gry (BindingsManager dostaje je tylko poza GUI).
## Bez „controller menus” (domyślnie wyłączone w OpenMW); przypisania pada zmienia okno opcji (tryb Controller).

const DEAD_ZONE := 0.1               # [Input] joystick dead zone

## loadControllerDefaults: akcja → przycisk (JoyButton) albo oś (["axis", oś, kierunek]).
const DEFAULT_BUTTONS := {
	"activate": JOY_BUTTON_A, "ready_weapon": JOY_BUTTON_X, "ready_magic": JOY_BUTTON_Y,
	"sneak": JOY_BUTTON_LEFT_STICK, "journal": JOY_BUTTON_LEFT_SHOULDER, "rest": JOY_BUTTON_RIGHT_SHOULDER,
	"menu_mode": JOY_BUTTON_B, "menu": JOY_BUTTON_START, "quick_save": JOY_BUTTON_GUIDE,
}
const DEFAULT_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "jump": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

var main
var enabled := true                  # [Input] enable controller
var gui_cursor := true               # mGamepadGuiCursorEnabled
var cursor_speed := 1.0              # [Input] gamepad cursor speed
var camera_y_multiplier := 1.0       # [Input] camera y multiplier
var device := 0
var last_look := Vector2.ZERO        # testy: ostatni obrót z prawej gałki (rad)
var last_look_dt := 0.0              # testy: dt klatki, z której pochodzi last_look
var _cursor := Vector2(-1, -1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Domyślne przypisania pada dodawane do akcji (bez usuwania klawiszy).
## loadControllerDefaults(force = false): domyślne tylko dla akcji bez przypisania pada i tylko gdy przycisk/oś nie
## jest już przypisany innej akcji (isJoystickButtonBound / isJoystickAxisBound).
static func _pad_events(act: String) -> Array:
	return InputMap.action_get_events(act).filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)

## Akcje gry z przypisaniami pada (wbudowane ui_* Godota się nie liczą – w OpenMW ich nie ma).
static func _game_actions() -> Array:
	var MWInput = load("res://scripts/mw/mw_input.gd")
	return (MWInput.CONTROLLER_SORTING + ["menu"]).filter(func(a): return InputMap.has_action(a))

static func _button_bound(b: int) -> bool:
	for a in _game_actions():
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton and int((e as InputEventJoypadButton).button_index) == b:
				return true
	return false

static func _axis_bound(ax: int) -> bool:
	for a in _game_actions():
		if String(a).begins_with("move_"):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadMotion and int((e as InputEventJoypadMotion).axis) == ax:
				return true
	return false

static func register_defaults() -> void:
	for act in DEFAULT_BUTTONS:
		if not InputMap.has_action(act) or not _pad_events(act).is_empty() or _button_bound(DEFAULT_BUTTONS[act]):
			continue
		var e := InputEventJoypadButton.new()
		e.button_index = DEFAULT_BUTTONS[act]
		e.device = -1
		InputMap.action_add_event(act, e)
	for act in DEFAULT_AXES:
		if not InputMap.has_action(act):
			continue
		var move := String(act).begins_with("move_")
		if not move and (not _pad_events(act).is_empty() or _axis_bound(DEFAULT_AXES[act][0])):
			continue
		var m := InputEventJoypadMotion.new()
		m.axis = DEFAULT_AXES[act][0]
		m.axis_value = DEFAULT_AXES[act][1]
		m.device = -1
		if not InputMap.action_has_event(act, m):
			InputMap.action_add_event(act, m)
		if move:
			InputMap.action_set_deadzone(act, DEAD_ZONE)

func _gui_mode() -> bool:
	var nav = main.get("keyboard_nav") if main != null else null
	return nav != null and nav._gui_mode()

static func dead(v: float) -> float:
	return 0.0 if absf(v) < DEAD_ZONE else v

func _key_event(k: Key, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	e.shift_pressed = shift
	return e

## gamepadToGuiControl(przycisk) → obsłużony.
func gui_button(b: int) -> bool:
	var nav = main.keyboard_nav
	match b:
		JOY_BUTTON_DPAD_UP:
			nav.inject_key(_key_event(KEY_UP))
		JOY_BUTTON_DPAD_DOWN:
			nav.inject_key(_key_event(KEY_DOWN))
		JOY_BUTTON_DPAD_LEFT:
			nav.inject_key(_key_event(KEY_LEFT))
		JOY_BUTTON_DPAD_RIGHT:
			nav.inject_key(_key_event(KEY_RIGHT))
		JOY_BUTTON_A:
			if gui_cursor:
				_click()                                # A jak przycisk myszy przy kursorze pada
			else:
				nav.inject_key(_key_event(KEY_SPACE))
		JOY_BUTTON_B:
			_exit_gui()
		JOY_BUTTON_LEFT_SHOULDER:
			nav.inject_key(_key_event(KEY_TAB, true))
		JOY_BUTTON_RIGHT_SHOULDER:
			nav.inject_key(_key_event(KEY_TAB))
		JOY_BUTTON_LEFT_STICK:
			gui_cursor = not gui_cursor
		_:
			return false
	return true

## B: okno modalne (exitCurrentModal) albo tryb GUI (exitCurrentGuiMode); bez trybu – jak Esc.
func _exit_gui() -> void:
	if main.confirm != null and main.confirm.is_open():
		main.confirm.press(false)
		return
	var cd = main.get("count_dialog")
	if cd != null and is_instance_valid(cd) and cd.is_open():
		cd.press_cancel()
		return
	var en = main.get("edit_note")
	if en != null and is_instance_valid(en) and en.is_open():
		en.close()
		return
	if main.get("console") != null and main.console != null and main.console.is_open():
		main.console.close()
		return
	if main.gui.exit_current():
		return
	var esc := InputEventAction.new()
	esc.action = "menu"
	esc.pressed = true
	Input.parse_input_event(esc)

func _click() -> void:
	var vp := get_viewport()
	var pos := vp.get_mouse_position()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		vp.push_input(e)

func _input(e: InputEvent) -> void:
	if not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	if not enabled:
		get_viewport().set_input_as_handled()       # [Input] enable controller = false – pad ignorowany
		return
	var sw = main.get("settings_window") if main != null else null
	if sw != null and sw.visible and not String(sw.rebinding).is_empty():
		get_viewport().set_input_as_handled()        # przypisywanie w oknie opcji (BindingsListener) ma pierwszeństwo
		sw.handle_rebind_event(e)
		return
	if not _gui_mode():
		return                                       # w grze – akcje z InputMap
	if e is InputEventJoypadButton and (e as InputEventJoypadButton).pressed:
		gui_button((e as InputEventJoypadButton).button_index)
	get_viewport().set_input_as_handled()            # w trybie GUI pad nie steruje akcjami gry

func _process(dt: float) -> void:
	if main == null or not enabled or Input.get_connected_joypads().is_empty() and not has_meta("test_axes"):
		return
	var lx := dead(_axis(JOY_AXIS_LEFT_X))
	var ly := dead(_axis(JOY_AXIS_LEFT_Y))
	var rx := dead(_axis(JOY_AXIS_RIGHT_X))
	var ry := dead(_axis(JOY_AXIS_RIGHT_Y))
	if _gui_mode():
		if not gui_cursor:
			return
		# ControllerManager::update: kursor z lewej gałki (wolniej z prawym spustem), kółko z prawej
		var slow := 1.5 - clampf(_axis(JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
		var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
		var mv := Vector2(lx, ly) * slow * dt * 1500.0 / s * cursor_speed
		var vp := get_viewport()
		if mv != Vector2.ZERO:
			var p := vp.get_mouse_position() + mv
			p = p.clamp(Vector2.ZERO, vp.get_visible_rect().size - Vector2.ONE)
			vp.warp_mouse(p)
			_cursor = p
		if ry != 0.0:
			var w := InputEventMouseButton.new()
			w.button_index = MOUSE_BUTTON_WHEEL_UP if ry < 0.0 else MOUSE_BUTTON_WHEEL_DOWN
			w.pressed = true
			w.factor = absf(ry) * dt * 1500.0 / 120.0
			w.position = vp.get_mouse_position()
			vp.push_input(w)
		return
	# MouseManager::update: rozglądanie prawą gałką
	if rx == 0.0 and ry == 0.0:
		last_look = Vector2.ZERO
		return
	var pl = main.player
	if pl == null or pl.controller == null or not pl.controller._ok("looking"):
		return
	var sens := float(main.settings.get("mouse_sensitivity", 0.0025)) / 0.0025
	var yaw := rx * dt * 1000.0 * sens * (-1.0 if bool(main.settings.get("invert_x", false)) else 1.0) / 256.0
	var pitch := ry * dt * 1000.0 * sens * (-1.0 if bool(main.settings.get("invert_y", false)) else 1.0) * camera_y_multiplier / 256.0
	last_look = Vector2(yaw, pitch)
	last_look_dt = dt
	pl.rotate_y(-yaw)
	var cam: Camera3D = pl.controller.cam
	cam.rotation.x = clampf(cam.rotation.x - pitch, -1.5, 1.5)

func _axis(a: int) -> float:
	if has_meta("test_axes"):
		return float((get_meta("test_axes") as Dictionary).get(a, 0.0))
	return Input.get_joy_axis(device, a)
