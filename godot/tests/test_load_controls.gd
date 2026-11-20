extends SceneTree
## Etap 10 (zgłoszenie): po wczytaniu zapisu z menu głównego gracz mógł obracać kamerą, ale nie mógł się ruszać
## (_enter_nogame wyłączało fizykę gracza, a wczytanie przywracało tylko process_mode). Także: MenuMode skryptów =
## WindowManager::isGuiMode – film (GM_Video), menu główne i tryby GUI na stosie (kwestie Say na początku gry nie
## mogą lecieć pod filmem wprowadzającym).
## godot --headless --path godot -s res://tests/test_load_controls.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _move(main) -> float:
	var p0: Vector3 = main.player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	for i in 5:
		await physics_frame
	return (main.player.global_position - p0).length()

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var d0: float = await _move(main)
	check(d0 > 0.5, "ruch przed zapisem (%.2f m)" % d0)
	var path := ProjectSettings.globalize_path("user://test_saves/load_controls.mwsave")
	check(main.save_game(path) == "", "zapis")
	# powrót do menu głównego (brak gry), potem wczytanie z menu
	main.cleanup()
	main._enter_nogame()
	for i in 5:
		await process_frame
	check(main.game_state == "nogame" and not main.player.is_physics_processing(), "brak gry: fizyka gracza wyłączona")
	var w: Array = main.load_slot(null, path)
	check(not str(w).contains("BŁĄD"), "wczytanie z menu głównego (%s)" % [w])
	for i in 40:
		await process_frame
	check(main.player.is_physics_processing() and not main.is_revealing(), "po wczytaniu: fizyka gracza włączona")
	var d1: float = await _move(main)
	check(d1 > 0.5, "po wczytaniu z menu głównego gracz się porusza (%.2f m)" % d1)
	# MenuMode
	var sh = main.script_host
	check(not sh.menu_mode(), "w grze MenuMode = 0")
	main.gui.push("probe", [])
	check(sh.menu_mode(), "tryb GUI na stosie – MenuMode = 1")
	main.gui.pop()
	main.video.playing = true
	check(sh.menu_mode(), "film (GM_Video) – MenuMode = 1")
	main.video.playing = false
	check(not sh.menu_mode(), "po filmie MenuMode = 0")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
