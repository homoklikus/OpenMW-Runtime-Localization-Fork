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
		if main.get("rest_window") != null and main.rest_window.visible and not main.rest_window.levelup.visible:
			main.rest_window.close()
			get_viewport().set_input_as_handled()
			return
		for wn in ["enchanting_window", "spellcreation_window"]:
			var w = main.get(wn)
			if w != null and w.visible:
				w.escape()
				get_viewport().set_input_as_handled()
				return
		if main.get("recharge_window") != null and main.recharge_window.visible:
			main.recharge_window.close()
			get_viewport().set_input_as_handled()
			return
		if main.get("journal_window") != null and main.journal_window.visible:
			main.journal_window.close()
			get_viewport().set_input_as_handled()
			return
		if main.get("trade_window") != null and main.trade_window.visible:
			main.trade_window.close()
			get_viewport().set_input_as_handled()
			return
		if main.get("dialogue_window") != null and main.dialogue_window.visible:
			main.dialogue_window.close()      # Esc = „Żegnaj” (nie w trakcie pytania)
			get_viewport().set_input_as_handled()
			return
		if main.get("item_window") != null and main.item_window.visible:
			main.item_window.close()          # Esc zamyka najpierw okno przedmiotów
			get_viewport().set_input_as_handled()
			return
		main.toggle_pause_menu()
		get_viewport().set_input_as_handled()
