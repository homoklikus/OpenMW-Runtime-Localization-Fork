extends Node
## Skrypty w trybie menu (Engine::frame): OpenMW wykonuje skrypty lokalne i globalne co klatkę także przy
## otwartym oknie (MenuMode = 1) – pomija je tylko przy menu głównym w pauzie. Główny węzeł gry stoi w pauzie
## drzewa, więc w tym czasie skrypty pompuje ten węzeł (PROCESS_MODE_ALWAYS).
var main

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(dt: float) -> void:
	if main == null or not get_tree().paused or main.game_state == "nogame":
		return
	if main.scripts == null or main.player == null or main.arg("scripts", "1") == "0":
		return
	for m in [main.pause_menu, main.main_menu]:
		if m != null and is_instance_valid(m) and m.visible:
			return
	main.scripts.tick(dt, main.script_host.scripted_refs())
