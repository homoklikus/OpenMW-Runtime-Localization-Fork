extends RefCounted
## Akcje wejścia gry (etap 0): kod reaguje na akcje, nie na klawisze. Domyślne klawisze dodawane w trakcie
## działania, jeśli akcji nie ma w InputMap (później: zmiana klawiszy w launcherze/ustawieniach).

const DEFAULTS := {
	"menu": KEY_ESCAPE,
	"quick_save": KEY_F5,
	"quick_load": KEY_F9,
	"toggle_coords": KEY_F3,
	"copy_position": KEY_F4,
	"inventory": KEY_I,
	"journal": KEY_J,
}

static func register_defaults() -> void:
	for action in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = DEFAULTS[action]
		InputMap.action_add_event(action, ev)
