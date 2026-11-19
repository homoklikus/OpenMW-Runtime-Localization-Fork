extends SceneTree
## Etap 9: ustawienia okien trybu menu globalne jak [Windows] w settings.cfg OpenMW – poza zapisem gry:
##   plik --window-settings (zapis atomowy), przypięcie/ukrycie/maksymalizacja/prostokąt przetrwają nową grę
##   i wczytanie innego zapisu, zapis gry nie zawiera kluczy ui_*, dawne zapisy z ui_* – przejęcie do pliku,
##   gdy globalnych ustawień jeszcze nie ma (inaczej globalne mają pierwszeństwo).
## godot --headless --path godot -s res://tests/test_window_settings.gd -- --data=WYNIKI --window-settings=PLIK

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _read(p: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return d if d is Dictionary else {}

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var p: String = main.window_settings_path()
	check(not p.is_empty() and p == main.arg("window-settings"), "plik ustawień okien z --window-settings (%s)" % p)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	main.window_settings = {}
	main._window_settings_loaded = false
	var mm = main.menu_mode
	mm.toggle_pin("stats")
	var d := _read(p)
	check(bool(d.get("windows", {}).get("ui_pins", {}).get("stats", false)) and String(d.get("format", "")) == "mwgodot-window-settings",
		"przypięcie zapisane od razu w pliku (%s)" % [d])
	mm.open()
	await _frames(3)
	(mm.windows["inventory"] as Control).position += Vector2(40, 30)
	mm.close()
	var inv_rect: Array = main.window_store("ui_windows").get("inventory", [])
	d = _read(p)
	check(inv_rect.size() == 4 and d.windows.ui_windows.has("inventory"), "prostokąt okna po zamknięciu trybu menu w pliku")
	# zapis gry bez ustawień okien
	var sp := ProjectSettings.globalize_path("user://test_saves/okna.mwsave")
	DirAccess.make_dir_recursive_absolute(sp.get_base_dir())
	var err: String = main.save_game(sp)
	var raw: Dictionary = preload("res://scripts/mw/mw_game_state.gd").read_file(sp) if err.is_empty() else {}
	var txt := JSON.stringify(raw)
	check(err.is_empty() and not txt.contains("ui_pins") and not txt.contains("ui_windows"), "zapis gry nie zawiera ustawień okien (%s)" % err)
	# nowa gra / czyszczenie stanu – ustawienia zostają
	main.cleanup()
	check(mm.is_pinned("stats") and main.window_store("ui_windows").get("inventory", []) == inv_rect, "po cleanup() (nowa gra) ustawienia okien bez zmian")
	# ponowne wczytanie z pliku (jak nowe uruchomienie)
	main.window_settings = {}
	main._window_settings_loaded = false
	check(mm.is_pinned("stats") and main.window_store("ui_windows").get("inventory", []).size() == 4, "odczyt z pliku przy uruchomieniu")
	# zgodność: dawny zapis z ui_* w postaci, gdy globalne już są – globalne wygrywają, klucze usunięte
	main.state.player["ui_pins"] = {"map": true, "stats": false}
	main.migrate_window_settings_from_save()
	check(mm.is_pinned("stats") and not mm.is_pinned("map") and not main.state.player.has("ui_pins"),
		"dawny zapis przy istniejących ustawieniach globalnych: bez nadpisania, klucze z postaci usunięte")
	# zgodność: brak pliku – przejęcie z zapisu
	DirAccess.remove_absolute(p)
	main.window_settings = {}
	main._window_settings_loaded = false
	main.state.player["ui_pins"] = {"map": true}
	main.state.player["ui_hidden"] = {"inventory": true}
	main.state.player["ui_windows"] = {"stats": [0.1, 0.1, 0.3, 0.3]}
	main.migrate_window_settings_from_save()
	d = _read(p)
	check(mm.is_pinned("map") and mm.is_hidden("inventory") and d.windows.ui_windows.stats == [0.1, 0.1, 0.3, 0.3]
		and not main.state.player.has("ui_windows"), "dawny zapis bez pliku: ustawienia przejęte do pliku (%s)" % [d])
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
