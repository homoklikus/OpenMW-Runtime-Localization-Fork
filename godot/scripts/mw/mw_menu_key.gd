extends Node
## Odbiera akcję „menu” także podczas pauzy (PROCESS_MODE_ALWAYS) i przełącza menu pauzy w main.gd.

var main: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("journal") and main and main.get("journal_window") != null:
		var dw = main.get("dialogue_window")
		if main.journal_window.visible or ((dw == null or not dw.visible) and not main.get_tree().paused):
			main.journal_window.toggle()     # J działa też przy pauzie (zamykanie dziennika)
			get_viewport().set_input_as_handled()
			return
	if e.is_action_pressed("menu") and main:
		get_viewport().set_input_as_handled()
		if main.get("main_menu") != null and main.main_menu != null and main.main_menu.is_open():
			main.toggle_pause_menu()
			return
		if main.get("dialogue_window") != null and main.dialogue_window.visible and main.dialogue_window.persuasion != null \
				and main.dialogue_window.persuasion.is_open() and main.gui.get_mode() == "dialogue":
			main.dialogue_window.persuasion.close()      # WindowModal::exit – najpierw okno perswazji
			return
		if main.get("item_window") != null and main.item_window.visible:
			main.item_window.close()
			return
		# WindowManager::exitCurrentGuiMode: wyjście z okna wierzchniego trybu GUI (powrót do poprzedniego)
		if main.gui.exit_current():
			return
		main.toggle_pause_menu()
