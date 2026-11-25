extends RefCounted
## Akcje wejścia gry (etap 0): kod reaguje na akcje, nie na klawisze. Domyślne klawisze dodawane w trakcie
## działania, jeśli akcji nie ma w InputMap. Zmiana klawiszy w oknie opcji (etap 10) jak OpenMW BindingsManager:
## lista akcji w kolejności getActionKeySorting z opisami getActionDescription, nazwa przypisania
## (getActionKeyBindingName: klawisz, „#{sMouse} N”, kółko), przypisanie (keyBindingDetected: Esc anuluje, F3/F4/F10
## i klawisze Win zastrzeżone, klawisz zabrany innej akcji – jedna akcja na klawisz), przywrócenie domyślnych,
## zapis w user://input_bindings.json (odpowiednik input_v3.xml; zapis atomowy).

const DEFAULTS := {
	"menu": KEY_ESCAPE,
	"quick_save": KEY_F5,
	"quick_load": KEY_F9,
	"toggle_coords": KEY_F3,
	"copy_position": KEY_F4,
	"inventory": KEY_I,
	"journal": KEY_J,
	"rest": KEY_T,
	"ready_weapon": KEY_F,
	"attack": -MOUSE_BUTTON_LEFT,          # wartość ujemna – przycisk myszy
	"ready_magic": KEY_R,                  # OpenMW: „Przygotuj magię”
	"magic_menu": KEY_M,                   # okno magii (w OpenMW część trybu ekwipunku)
	"map_menu": KEY_N,                     # okno mapy (lokalna/świat; w OpenMW część trybu ekwipunku)
	"sneak": KEY_CTRL,                     # skradanie (przytrzymaj)
	"menu_mode": -MOUSE_BUTTON_RIGHT,      # tryb menu: statystyki, ekwipunek, magia, mapa (OpenMW A_Inventory)
	"toggle_hud": KEY_F11,                 # pokaż/ukryj HUD (OpenMW A_ToggleHUD)
	"console": KEY_QUOTELEFT,              # konsola (OpenMW A_Console, klawisz „`”)
	"quick_keys_menu": KEY_F1,             # menu szybkich klawiszy (OpenMW A_QuickKeysMenu)
	"quick_key_1": KEY_1,                  # szybkie klawisze 1–9 i 0 (A_QuickKey1…10)
	"quick_key_2": KEY_2,
	"quick_key_3": KEY_3,
	"quick_key_4": KEY_4,
	"quick_key_5": KEY_5,
	"quick_key_6": KEY_6,
	"quick_key_7": KEY_7,
	"quick_key_8": KEY_8,
	"quick_key_9": KEY_9,
	"quick_key_10": KEY_0,
	# BindingsManager::loadKeyDefaults (OpenMW 0.51)
	"always_run": KEY_CAPSLOCK,            # A_AlwaysRun – przełącznik [Input] always run
	"auto_move": KEY_Q,                    # A_AutoMove
	"cycle_spell_left": KEY_MINUS,         # A_CycleSpellLeft
	"cycle_spell_right": KEY_EQUAL,        # A_CycleSpellRight
	"cycle_weapon_left": KEY_BRACKETLEFT,  # A_CycleWeaponLeft
	"cycle_weapon_right": KEY_BRACKETRIGHT,  # A_CycleWeaponRight
	"screenshot": KEY_F12,                 # A_Screenshot
}

## Klawisze akcji z project.godot (do przywracania domyślnych).
const PROJECT_DEFAULTS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"jump": KEY_E, "run": KEY_SHIFT, "activate": KEY_SPACE,     # OpenMW 0.51: A_Activate – Spacja, A_Jump – E
}

## Akcje konfigurowalne w kolejności BindingsManager::getActionKeySorting (tylko te, które ma port) i ich opisy
## (GMST „#{s…}” albo OMWEngine:…).
## TogglePOV, ZoomIn/ZoomOut (kamera trzecioosobowa – nieprzeniesiona) i TogglePostProcessorHUD (post-processing –
## nieprzeniesiony) pominięte: nie ma działającej funkcji, którą mogłyby wywołać.
const CONFIGURABLE := [
	["move_forward", "sForward"], ["move_back", "sBack"], ["move_left", "sLeft"], ["move_right", "sRight"],
	["run", "sRun"], ["always_run", "sAlways_Run"], ["sneak", "sCrouch_Sneak"], ["activate", "sActivate"],
	["attack", "sUse"], ["ready_weapon", "sReady_Weapon"], ["ready_magic", "sReady_Magic"],
	["cycle_spell_left", "sPrevSpell"], ["cycle_spell_right", "sNextSpell"], ["cycle_weapon_left", "sPrevWeapon"],
	["cycle_weapon_right", "sNextWeapon"], ["auto_move", "sAuto_Run"], ["jump", "sJump"],
	["menu_mode", "sInventory"], ["journal", "sJournal"], ["rest", "sRestKey"],
	["console", "OMWEngine:ConsoleWindow"], ["quick_save", "sQuickSaveCmd"], ["quick_load", "sQuickLoadCmd"],
	["toggle_hud", "OMWEngine:ToggleHUD"], ["screenshot", "OMWEngine:Screenshot"], ["quick_keys_menu", "sQuickMenu"],
	["quick_key_1", "sQuick1Cmd"], ["quick_key_2", "sQuick2Cmd"], ["quick_key_3", "sQuick3Cmd"],
	["quick_key_4", "sQuick4Cmd"], ["quick_key_5", "sQuick5Cmd"], ["quick_key_6", "sQuick6Cmd"],
	["quick_key_7", "sQuick7Cmd"], ["quick_key_8", "sQuick8Cmd"], ["quick_key_9", "sQuick9Cmd"],
	["quick_key_10", "sQuick10Cmd"],
]
const RESERVED := [KEY_F3, KEY_F4, KEY_F10, KEY_META]
## getActionControllerSorting (OpenMW 0.51) – akcje obsługiwane przez port, w tej kolejności (bez TogglePOV
## i ZoomIn/Out – kamera trzecioosobowa nieprzeniesiona).
const CONTROLLER_SORTING := ["move_forward", "move_back", "move_left", "move_right", "sneak", "activate", "attack",
	"ready_weapon", "ready_magic", "auto_move", "jump", "menu_mode", "journal", "rest", "quick_save", "quick_load",
	"toggle_hud", "screenshot", "quick_keys_menu", "quick_key_1", "quick_key_2", "quick_key_3", "quick_key_4",
	"quick_key_5", "quick_key_6", "quick_key_7", "quick_key_8", "quick_key_9", "quick_key_10", "cycle_spell_left",
	"cycle_spell_right", "cycle_weapon_left", "cycle_weapon_right"]
## Ruch z lewej gałki idzie przez A_MoveForwardBackward / A_MoveLeftRight (osie), więc A_MoveForward… na liście
## pada nie mają przypisania (#{Interface:None}) i nie da się ich przypisać przyciskiem.
const AXIS_MOVE := ["move_forward", "move_back", "move_left", "move_right"]
const SDL_BUTTON_NAMES := ["A Button", "B Button", "X Button", "Y Button", "Back Button", "Guide Button", "Start Button",
	"Left Stick Button", "Right Stick Button", "Left Shoulder", "Right Shoulder", "DPad Up", "DPad Down", "DPad Left",
	"DPad Right", "Misc 1", "Paddle 1", "Paddle 2", "Paddle 3", "Paddle 4", "Touchpad"]
const SDL_AXIS_NAMES := ["Left Stick X", "Left Stick Y", "Right Stick X", "Right Stick Y", "Left Trigger", "Right Trigger"]
static var bindings_path := "user://input_bindings.json"

static func default_code(action: String) -> int:
	if DEFAULTS.has(action):
		return int(DEFAULTS[action])
	return int(PROJECT_DEFAULTS.get(action, 0))

static func _event_for(code: int) -> InputEvent:
	if code < 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = -code
		return mb
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev

## Kod przypisania: klawisz (physical_keycode) albo −przycisk myszy; 0 – brak.
static func code_of(e: InputEvent) -> int:
	if e is InputEventKey:
		var k := e as InputEventKey
		return int(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	if e is InputEventMouseButton:
		return -int((e as InputEventMouseButton).button_index)
	return 0

## clearAllKeyBindings: tylko klawisze i przyciski myszy (przypisania pada zostają).
static func clear_key_bindings(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)

static func binding_code(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for e in InputMap.action_get_events(action):
		var c := code_of(e)
		if c != 0:
			return c
	return 0

## getActionKeyBindingName: nazwa klawisza, „#{sMouse} N” (numeracja SDL: 1 lewy, 2 środkowy, 3 prawy…),
## kółko – „Mouse Wheel Up/Down/Left/Right”, brak – #{Interface:None}.
static func binding_name(action: String, mouse_word := "Mouse", none_word := "None") -> String:
	var c := binding_code(action)
	if c == 0:
		return none_word
	if c > 0:
		return OS.get_keycode_string(c)
	match -c:
		MOUSE_BUTTON_WHEEL_UP:
			return "Mouse Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Mouse Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "Mouse Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "Mouse Wheel Right"
		MOUSE_BUTTON_LEFT:
			return "%s 1" % mouse_word
		MOUSE_BUTTON_MIDDLE:
			return "%s 2" % mouse_word
		MOUSE_BUTTON_RIGHT:
			return "%s 3" % mouse_word
		_:
			return "%s %d" % [mouse_word, -c]

# --- pad (przypisania w oknie opcji, tryb Controller) ----------------------------------------------------

## clearAllControllerBindings.
static func clear_controller_bindings(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			InputMap.action_erase_event(action, e)

## Przypisanie pada: {"button": n} albo {"axis": a} (Godot numeruje przyciski i osie jak SDL GameController);
## {} – brak.
static func controller_binding(action: String) -> Dictionary:
	if action in AXIS_MOVE or not InputMap.has_action(action):
		return {}
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			return {"axis": int((e as InputEventJoypadMotion).axis)}
		if e is InputEventJoypadButton:
			return {"button": int((e as InputEventJoypadButton).button_index)}
	return {}

## getActionControllerBindingName: sdlControllerAxisToString / sdlControllerButtonToString.
static func controller_binding_name(action: String, none_word := "None") -> String:
	var b := controller_binding(action)
	if b.has("axis"):
		var a := int(b.axis)
		return SDL_AXIS_NAMES[a] if a >= 0 and a < SDL_AXIS_NAMES.size() else "Axis %d" % a
	if b.has("button"):
		var n := int(b.button)
		return SDL_BUTTON_NAMES[n] if n >= 0 and n < SDL_BUTTON_NAMES.size() else "Button %d" % n
	return none_word

static func _controller_event(b: Dictionary) -> InputEvent:
	if b.has("axis"):
		var m := InputEventJoypadMotion.new()
		m.axis = int(b.axis)
		m.axis_value = 1.0
		m.device = -1
		return m
	var e := InputEventJoypadButton.new()
	e.button_index = int(b.button)
	e.device = -1
	return e

## Jedno przypisanie na przycisk/oś (ICS): zabierane innym akcjom z listy pada.
static func set_controller_binding(action: String, b: Dictionary) -> void:
	for other in CONTROLLER_SORTING:
		if other != action and controller_binding(other) == b:
			clear_controller_bindings(other)
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	clear_controller_bindings(action)
	if not b.is_empty():
		InputMap.action_add_event(action, _controller_event(b))
	load("res://scripts/mw/mw_gamepad.gd").retarget(load("res://scripts/mw/mw_gamepad.gd").active_device)

## joystickButtonBindingDetected / joystickAxisBindingDetected (tylko spusty, wychylenie > 0,5 jak ICS);
## klawiatura i mysz w tym trybie są pomijane → "ignored".
static func rebind_controller(action: String, e: InputEvent) -> String:
	var b := {}
	if e is InputEventJoypadButton and (e as InputEventJoypadButton).pressed:
		b = {"button": int((e as InputEventJoypadButton).button_index)}
	elif e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		if m.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and m.axis_value > 0.5:
			b = {"axis": int(m.axis)}
	if b.is_empty() or action in AXIS_MOVE:
		return "ignored"
	set_controller_binding(action, b)
	save_bindings()
	return "bound"

## resetToDefaultControllerBindings (loadControllerDefaults(true)).
static func reset_controller_defaults() -> void:
	var GP = load("res://scripts/mw/mw_gamepad.gd")
	for act in CONTROLLER_SORTING + ["menu"]:
		if InputMap.has_action(act) and not (act in AXIS_MOVE):
			clear_controller_bindings(act)
	GP.register_defaults()
	GP.retarget(GP.active_device)
	save_bindings()

## keyBindingDetected / mouseButtonBindingDetected: → "cancel" (Esc), "ignored" (zastrzeżony), "bound".
static func rebind(action: String, e: InputEvent) -> String:
	var c := code_of(e)
	if c == KEY_ESCAPE:
		return "cancel"
	if c == 0 or c in RESERVED:
		return "ignored"
	set_binding(action, c)
	save_bindings()
	return "bound"

## Jedna akcja na klawisz (ICS: mapa klawisz → kontrolka): klawisz zabierany innym akcjom konfigurowalnym.
static func set_binding(action: String, c: int) -> void:
	for a in CONFIGURABLE:
		var other := String(a[0])
		if other != action and InputMap.has_action(other) and binding_code(other) == c:
			clear_key_bindings(other)
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	clear_key_bindings(action)                           # clearAllKeyBindings
	InputMap.action_add_event(action, _event_for(c))

static func reset_defaults() -> void:
	for a in CONFIGURABLE:
		var act := String(a[0])
		if InputMap.has_action(act):
			clear_key_bindings(act)
	for a in CONFIGURABLE:
		var act := String(a[0])
		var c := default_code(act)
		if c != 0:
			if not InputMap.has_action(act):
				InputMap.add_action(act)
			InputMap.action_add_event(act, _event_for(c))
	save_bindings()

static func save_bindings() -> bool:
	var d := {}
	for a in CONFIGURABLE:
		d[String(a[0])] = binding_code(String(a[0]))
	var pad := {}
	for act in CONTROLLER_SORTING:
		if not (act in AXIS_MOVE) and InputMap.has_action(act):
			pad[act] = controller_binding(act)
	var tmp := bindings_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"format": "mwgodot-input-bindings", "version": 1, "bindings": d, "controller": pad}, " "))
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(bindings_path)) == OK

static func load_bindings() -> void:
	if not FileAccess.file_exists(bindings_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(bindings_path))
	if not (d is Dictionary) or not (d.get("bindings") is Dictionary):
		return
	for act in d.bindings:
		var c := int(d.bindings[act])
		if not InputMap.has_action(String(act)):
			continue
		clear_key_bindings(String(act))
		if c != 0:
			InputMap.action_add_event(String(act), _event_for(c))
	# przypisania pada (input_v3.xml: osie i przyciski); brak – loadControllerDefaults uzupełni domyślne
	if d.get("controller") is Dictionary:
		for act in d.controller:
			var b = d.controller[act]
			if not InputMap.has_action(String(act)) or String(act) in AXIS_MOVE or not (b is Dictionary):
				continue
			clear_controller_bindings(String(act))
			var bb := {}
			if b.has("axis"):
				bb = {"axis": int(b.axis)}
			elif b.has("button"):
				bb = {"button": int(b.button)}
			if not bb.is_empty():
				InputMap.action_add_event(String(act), _controller_event(bb))

static func register_defaults() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var code: int = DEFAULTS[action]
		if code < 0:
			var mb := InputEventMouseButton.new()
			mb.button_index = -code
			InputMap.action_add_event(action, mb)
		else:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
