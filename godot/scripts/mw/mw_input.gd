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
	"rest": KEY_T,
	"ready_weapon": KEY_F,
	"attack": -MOUSE_BUTTON_LEFT,          # wartość ujemna – przycisk myszy
	"ready_magic": KEY_R,                  # OpenMW: „Przygotuj magię”
	"magic_menu": KEY_M,                   # okno magii (w OpenMW część trybu ekwipunku)
	"map_menu": KEY_N,                     # okno mapy (lokalna/świat; w OpenMW część trybu ekwipunku)
	"sneak": KEY_CTRL,                     # skradanie (przytrzymaj)
	"menu_mode": -MOUSE_BUTTON_RIGHT,      # tryb menu: statystyki, ekwipunek, magia, mapa (OpenMW A_Inventory)
	"toggle_hud": KEY_F11,                 # pokaż/ukryj HUD (OpenMW A_ToggleHUD)
}

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
