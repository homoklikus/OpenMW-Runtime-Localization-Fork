extends Node
## Odbiera akcję „menu” także podczas pauzy (PROCESS_MODE_ALWAYS) i przełącza menu pauzy w main.gd.

var main: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("menu") and main:
		if main.get("item_window") != null and main.item_window.visible:
			main.item_window.close()          # Esc zamyka najpierw okno przedmiotów
			get_viewport().set_input_as_handled()
			return
		main.toggle_pause_menu()
		get_viewport().set_input_as_handled()
