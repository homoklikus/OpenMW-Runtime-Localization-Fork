extends SceneTree
## Etap 10 – ustawienia w grze: zmiany działają od razu (głośności, pole widzenia, mysz, napisy), „Zapisz” zapisuje
## ingame_settings.json obok ustawień z launchera (wczytywany przy starcie), „Anuluj” przywraca; komunikaty
## i napisy nad oknami (warstwa Overlay).
## godot --headless --path godot -s res://tests/test_settings.gd -- --data=WYNIKI(aktorzy) --settings=PLIK --pos=… --scripts=0

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var sp := arg("settings")
	DirAccess.make_dir_recursive_absolute(sp.get_base_dir())
	var f := FileAccess.open(sp, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "mwgodot-runtime-settings", "version": 1, "music_volume": 0.5, "fov": 60}))
	f.close()
	var ing := sp.get_base_dir().path_join("ingame_settings.json")
	if FileAccess.file_exists(ing):
		DirAccess.remove_absolute(ing)
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(6)
	var cam := main.player.get_node_or_null("Camera3D") as Camera3D
	check(cam != null and is_equal_approx(cam.fov, 60.0), "pole widzenia z ustawień (60° jak OpenMW)")
	main.open_settings()
	await _frames(2)
	var w = main.settings_window
	check(w.visible, "okno ustawień")
	w.set_value("music_volume", 0.25)
	w.set_value("voice_volume", 0.4)
	w.set_value("master_volume", 0.5)
	w.set_value("fov", 75)
	w.set_value("mouse_sensitivity", 0.005)
	check(is_equal_approx(main.music.volume, 0.25) and is_equal_approx(main.audio.voice_volume, 0.4), "głośności od razu")
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "głośność ogólna – szyna Master")
	check(is_equal_approx(cam.fov, 75.0) and is_equal_approx(main.player.mouse_sens, 0.005), "pole widzenia i mysz od razu")
	w.save_and_close()
	check(FileAccess.file_exists(ing), "zapis ingame_settings.json obok ustawień launchera")
	var saved: Dictionary = main._load_ingame_settings()
	check(is_equal_approx(float(saved.get("music_volume", 0)), 0.25) and int(saved.get("fov", 0)) == 75, "zapisane wartości (%s)" % str(saved))
	# anulowanie przywraca
	main.open_settings()
	await _frames(1)
	w.set_value("fov", 100)
	w.cancel_changes()
	check(is_equal_approx(cam.fov, 75.0), "„Anuluj” przywraca poprzednie wartości")
	# napisy wyłączone – brak napisu; napisy i komunikaty na warstwie nad oknami
	main.settings["subtitles"] = true
	main.subtitle("Test napisu", 2.0)
	check(main._subtitle != null and main._subtitle.get_parent() == main.overlay() and main.overlay().layer > 24,
			"napisy nad oknami (warstwa %d)" % main.overlay().layer)
	main.settings["subtitles"] = false
	main.apply_live_settings()
	check(not main._subtitle.visible, "napisy wyłączone w ustawieniach")
	main._toast("Komunikat")
	check(main.overlay().get_children().any(func(c): return c is Label and c.text == "Komunikat"), "komunikat na warstwie nad oknami")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
