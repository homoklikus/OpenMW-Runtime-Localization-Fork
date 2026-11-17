extends SceneTree
## Sonda first-fish na prawdziwych danych: gra w Seyda Neen (bez kreatora), mod z katalogu mods/, rybki przy
## pomoście. Sprawdza: 3 rybki w świecie, w wodzie (pod lustrem, nad dnem terenu), w obszarze, ruch przez
## PROBE_SECONDS (domyślnie 60 s), animacja gra, brak błędów modu i skryptów. Zrzut (tylko lokalnie,
## obraz gry): PROBE_SHOTS=katalog.
##   godot [--rendering-method gl_compatibility] --path godot -s res://tests/probe_first_fish.gd --
##       --data=WYNIKI --project=KATALOG --start="Seyda Neen" --scripts=0
var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 20:
		await process_frame
	var nm = main.native_mods
	check(nm != null and not nm.mods.is_empty(), "mody natywne wczytane (%s)" % [nm.root_dir if nm else ""])
	# kamera nad pomostem, widok na płyciznę z rybkami (zrzut)
	var cam_mw := Vector3(-9200, -73120, 90)
	main.player.fly = true
	main.player.global_position = MWCoords.mw_to_godot(cam_mw) - Vector3(0, 1.6, 0)
	main.player.rotation.y = 0.0
	var cam := main.player.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.rotation.x = -0.75
	for i in 30:
		await process_frame
	var fish: Array = nm.spawned.filter(func(f): return is_instance_valid(f) and f.is_inside_tree())
	check(fish.size() == 3, "3 rybki w świecie (%d)" % fish.size())
	if fish.is_empty():
		_done()
		return
	var start := []
	for f in fish:
		start.append(f.global_position)
	var secs := float(OS.get_environment("PROBE_SECONDS")) if OS.get_environment("PROBE_SECONDS") != "" else 60.0
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var band_ok := true
	var max_off := 0.0
	var frames := 0
	while Time.get_ticks_msec() < t_end:
		await process_frame
		frames += 1
		for f in fish:
			var p: Vector3 = f.global_position
			var g: float = nm.ground_height(p.x, p.z)
			if p.y > float(f.water_y) - 0.2 or p.y < g + 0.15:
				band_ok = false
			max_off = maxf(max_off, Vector2(p.x - f.home.x, p.z - f.home.z).length())
	var moved := 0.0
	for i in fish.size():
		moved += fish[i].global_position.distance_to(start[i])
	var trav := 0.0
	for f in fish:
		trav += float(f.travelled)
	var playing := fish.all(func(f): return f.find_children("*", "AnimationPlayer", true, false)[0].is_playing())
	print("PROBE fish=%d frames=%d travelled=%.1fm max_off=%.2fm water=%.2f ground=%s" % [fish.size(), frames, trav,
			max_off, float(fish[0].water_y), [snappedf(nm.ground_height(fish[0].global_position.x, fish[0].global_position.z), 0.01)]])
	check(band_ok, "przez %.0f s pod lustrem wody i nad dnem" % secs)
	check(max_off <= float(fish[0].radius) * 1.25, "w obszarze pływania (maks. %.2f m)" % max_off)
	check(trav > secs * 0.1 and moved > 0.2, "pływają (droga %.1f m)" % trav)
	check(playing, "animacja swim_idle gra")
	check(nm.errors.is_empty(), "bez błędów modu (%s)" % [nm.errors])
	check(main.scripts == null or main.scripts.report().errors.is_empty(), "bez błędów skryptów")
	var shots := OS.get_environment("PROBE_SHOTS")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(shots)
		# zbliżenie na pierwszą rybkę
		var f0: Node3D = fish[0]
		main.player.global_position = f0.global_position + Vector3(0.0, 0.5, 0.9) - Vector3(0, 1.6, 0)
		if cam != null:
			cam.rotation.x = -0.45
		for i in 20:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(shots.path_join("first_fish_closeup.png"))
	_done()

func _done() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
