extends SceneTree
## Etap 10 (zgłoszenie): po wczytaniu zapisu kamera samoczynnie się obracała. Bez ruchu myszy i gałki kamera ma
## zachować zapisaną orientację (odchylenie gracza i pochylenie kamery) i stać w miejscu – przy wczytaniu z menu
## głównego i w trakcie gry, zapisu we wnętrzu i na zewnątrz, z padem (rozpoznany kontroler gry, gałki w spoczynku
## i w strefie martwej) i bez niego, z urządzeniem spoza kontrolerów gry (osie w spoczynku ≠ 0, jak nierozpoznane
## pady i czujniki), przy włączonym i wyłączonym „Enable Controller”, po wyjściu z GUI. Źródło obrotu – mw_look_diag.gd.
## godot --headless --path godot -s res://tests/test_look_stability.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _orient(main) -> Vector2:
	var cam: Node3D = main.player.get_node("Camera3D")
	return Vector2(main.player.rotation.y, cam.rotation.x)

func _set_orient(main, yaw: float, pitch: float) -> void:
	main.player.rotation.y = yaw
	(main.player.get_node("Camera3D") as Node3D).rotation.x = pitch

## Po wczytaniu: N klatek bez wejścia – orientacja równa zapisanej, diagnostyka bez obrotu.
func _still(main, want: Vector2, tag: String, frames := 90) -> void:
	for i in 20:
		await process_frame
	var o0 := _orient(main)
	check(absf(wrapf(o0.x - want.x, -PI, PI)) < 1e-3 and absf(o0.y - want.y) < 1e-3,
		"%s: orientacja z zapisu (%s / %s)" % [tag, o0, want])
	main.look_diag.reset()
	for i in frames:
		await physics_frame
	var o1 := _orient(main)
	check(o1.is_equal_approx(o0) and main.look_diag.frames_moving == 0,
		"%s: kamera nieruchoma bez wejścia (%s → %s; źródła %s)" % [tag, o0, o1, main.look_diag.totals])

func _save(main, path: String, yaw: float, pitch: float) -> void:
	_set_orient(main, yaw, pitch)
	for i in 3:
		await physics_frame
	check(main.save_game(path) == "", "zapis " + path.get_file())

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var gp = main.gamepad
	var dir := ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(dir)
	var ext_path := dir.path_join("look_ext.mwsave")
	var int_path := dir.path_join("look_int.mwsave")
	var want_ext := Vector2(1.1, -0.3)
	var want_int := Vector2(-2.0, 0.25)
	# zapis na zewnątrz
	await _save(main, ext_path, want_ext.x, want_ext.y)
	# zapis we wnętrzu
	main.travel_to_cell("Synthville, Test House", Vector3.ZERO, 0.0)
	for i in 40:
		await process_frame
	check(not String(main.interior).is_empty(), "we wnętrzu (%s)" % main.interior)
	await _save(main, int_path, want_int.x, want_int.y)
	# 1. wczytanie w trakcie gry (bez pada – headless), zewnątrz i wnętrze
	check(gp.device == gp.NO_DEVICE, "bez podłączonego pada")
	main.load_game(ext_path)
	await _still(main, want_ext, "w grze, zewnątrz, bez pada")
	main.load_game(int_path)
	await _still(main, want_int, "w grze, wnętrze, bez pada")
	# 2. z menu głównego (brak gry → wczytanie)
	main.cleanup()
	main._enter_nogame()
	for i in 5:
		await process_frame
	main.load_slot(null, ext_path)
	await _still(main, want_ext, "z menu głównego, zewnątrz")
	main.cleanup()
	main._enter_nogame()
	for i in 5:
		await process_frame
	main.load_slot(null, int_path)
	await _still(main, want_int, "z menu głównego, wnętrze")
	# 3. urządzenie spoza kontrolerów gry z osiami w spoczynku ≠ 0 (np. spust −1 na osi prawej gałki): bez wpływu
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: -1.0, JOY_AXIS_RIGHT_Y: -1.0, JOY_AXIS_LEFT_Y: -1.0})
	gp.remove_meta("test_device")
	gp.refresh_device()
	var mv := InputEventJoypadMotion.new()
	mv.device = 0
	mv.axis = JOY_AXIS_LEFT_Y
	mv.axis_value = -1.0
	Input.parse_input_event(mv)
	main.load_game(ext_path)
	await _still(main, want_ext, "urządzenie nierozpoznane, osie ≠ 0")
	check(not Input.is_action_pressed("move_forward"), "urządzenie nierozpoznane nie porusza graczem")
	mv.axis_value = 0.0
	Input.parse_input_event(mv)
	# 4. rozpoznany pad: gałki w spoczynku i w strefie martwej (0,05 < 0,1)
	gp.set_meta("test_device", 0)
	gp.refresh_device()
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 0.0, JOY_AXIS_RIGHT_Y: 0.0})
	main.load_game(int_path)
	await _still(main, want_int, "pad podłączony, gałki w spoczynku")
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 0.05, JOY_AXIS_RIGHT_Y: -0.08, JOY_AXIS_LEFT_X: 0.07})
	main.load_game(ext_path)
	await _still(main, want_ext, "pad podłączony, gałki w strefie martwej")
	# 5. „Enable Controller” wyłączone – nawet wychylona gałka nie obraca kamery
	main.settings["enable_controller"] = false
	main.apply_live_settings()
	gp.set_meta("test_axes", {JOY_AXIS_RIGHT_X: 0.9})
	main.load_game(int_path)
	await _still(main, want_int, "Enable Controller wyłączone, gałka wychylona")
	main.settings["enable_controller"] = true
	main.apply_live_settings()
	# kontrola: wychylona gałka rozpoznanego pada obraca kamerę i diagnostyka wskazuje pad
	main.look_diag.reset()
	for i in 10:
		await physics_frame
	await process_frame
	check(main.look_diag.totals.has("pad") and main.look_diag.frames_other == 0, "diagnostyka: obrót z pada przypisany do „pad” (%s)" % main.look_diag.totals)
	gp.set_meta("test_axes", {})
	# 6. wejście i wyjście z GUI (menu główne w trakcie gry) po wczytaniu
	main.load_game(ext_path)
	for i in 10:
		await process_frame
	main.open_main_menu()
	for i in 10:
		await process_frame
	main.close_main_menu()
	await _still(main, want_ext, "po powrocie z GUI")
	# diagnostyka: ręczny obrót bez zgłoszonego źródła trafia do „other”
	main.look_diag.reset()
	await physics_frame
	main.player.rotation.y += 0.2
	await physics_frame
	await physics_frame
	check(main.look_diag.frames_other == 1 and main.look_diag.totals.has("other"), "diagnostyka: obrót bez źródła – „other” (%s)" % main.look_diag.totals)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
