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
}

## Klawisze akcji z project.godot (do przywracania domyślnych).
const PROJECT_DEFAULTS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"jump": KEY_SPACE, "run": KEY_SHIFT, "activate": KEY_E,
}

## Akcje konfigurowalne w kolejności BindingsManager::getActionKeySorting (tylko te, które ma port) i ich opisy
## (GMST „#{s…}” albo OMWEngine:…).
const CONFIGURABLE := [
	["move_forward", "sForward"], ["move_back", "sBack"], ["move_left", "sLeft"], ["move_right", "sRight"],
	["run", "sRun"], ["sneak", "sCrouch_Sneak"], ["activate", "sActivate"], ["attack", "sUse"],
	["ready_weapon", "sReady_Weapon"], ["ready_magic", "sReady_Magic"], ["jump", "sJump"],
	["menu_mode", "sInventory"], ["journal", "sJournal"], ["rest", "sRestKey"],
	["console", "OMWEngine:ConsoleWindow"], ["quick_save", "sQuickSaveCmd"], ["quick_load", "sQuickLoadCmd"],
	["toggle_hud", "OMWEngine:ToggleHUD"], ["quick_keys_menu", "sQuickMenu"],
	["quick_key_1", "sQuick1Cmd"], ["quick_key_2", "sQuick2Cmd"], ["quick_key_3", "sQuick3Cmd"],
	["quick_key_4", "sQuick4Cmd"], ["quick_key_5", "sQuick5Cmd"], ["quick_key_6", "sQuick6Cmd"],
	["quick_key_7", "sQuick7Cmd"], ["quick_key_8", "sQuick8Cmd"], ["quick_key_9", "sQuick9Cmd"],
	["quick_key_10", "sQuick10Cmd"],
]
const RESERVED := [KEY_F3, KEY_F4, KEY_F10, KEY_META]
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
	var tmp := bindings_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"format": "mwgodot-input-bindings", "version": 1, "bindings": d}, " "))
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
