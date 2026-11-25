extends SceneTree
## Etap 10 (zgłoszenie): po wczytaniu gry postać się nie rusza, dopiero po dwóch Esc. Wczytanie przez interfejs
## jak gracz: menu główne → Wczytaj → SaveGameDialog::accept (w grze – z potwierdzeniem), z menu bez gry i w trakcie
## gry; po odsłonięciu świata: bez trybów GUI na stosie, bez pauzy, ruch gracza.
## godot --headless --path godot -s res://tests/test_load_ui.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --saves=KATALOG

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

func _state(main) -> String:
	return "paused=%s stack=%s menu=%s dialog=%s confirm=%s state=%s phys=%s reveal=%s allowed=%s" % [main.get_tree().paused,
		main.gui.stack.map(func(m): return m.mode), main.main_menu.is_open(), main.save_dialog.visible, main.confirm.is_open(),
		main.game_state, main.player.is_physics_processing(), main.is_revealing(), main._movement_allowed()]

func _settle(main) -> void:
	for i in 60:
		await process_frame
		if not main.is_revealing() and main.player.is_physics_processing():
			break
	for i in 10:
		await process_frame

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	check(main.save_to_slot("ui load test") == "", "zapis do slotu")
	for i in 5:
		await process_frame
	# --- w trakcie gry: Esc → menu → Wczytaj → slot → OK → potwierdzenie ---
	main.toggle_pause_menu()
	await process_frame
	check(main.main_menu.is_open() and main.get_tree().paused, "menu w grze otwarte, pauza")
	main.save_dialog.open(true)
	for i in 3:
		await process_frame
	check(main.save_dialog.current_slot != null, "slot wybrany")
	main.save_dialog.accept()
	await process_frame
	check(main.confirm.is_open(), "pytanie o wczytanie w trakcie gry")
	main.confirm.press(true)
	await _settle(main)
	print("STATE ingame ", _state(main))
	check(not main.get_tree().paused and main.gui.stack.is_empty() and not main.main_menu.is_open() and main._movement_allowed(),
		"po wczytaniu w grze: bez pauzy, bez trybów GUI (%s)" % _state(main))
	var d1: float = await _move(main)
	check(d1 > 0.5, "po wczytaniu w grze gracz się porusza (%.2f m)" % d1)
	# --- bez gry: menu główne → Wczytaj → slot → OK ---
	main.cleanup()
	main._enter_nogame()
	main.gui.cursor = ""
	main.open_main_menu()
	for i in 5:
		await process_frame
	main.save_dialog.open(true)
	for i in 3:
		await process_frame
	main.save_dialog.accept()
	await _settle(main)
	print("STATE menu ", _state(main))
	check(not main.get_tree().paused and main.gui.stack.is_empty() and not main.main_menu.is_open() and main._movement_allowed(),
		"po wczytaniu z menu: bez pauzy, bez trybów GUI (%s)" % _state(main))
	check(main.gui.cursor == "captured" and main.get_viewport().gui_get_focus_owner() == null,
		"po wczytaniu z menu: kursor przechwycony (updateVisible), bez fokusu okna zapisów (%s)" % main.gui.cursor)
	var d2: float = await _move(main)
	check(d2 > 0.5, "po wczytaniu z menu gracz się porusza (%.2f m)" % d2)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
