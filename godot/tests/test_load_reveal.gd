extends SceneTree
## Etap 10, P0 „glitche podczas wczytywania zapisu” – test regresyjny cyklu życia sceny przy wczytaniu:
## * StateManager::loadGame: cleanup() (State_NoGame) przed ekranem ładowania – w trakcie gry i z menu ekran
##   ładowania z tapetą (nie zamrożona klatka poprzedniej gry), świat odsłaniany po gotowości (is_revealing);
## * start z `--load` (Engine::go): ta sama ścieżka – ekran ładowania i odsłanianie; komórka wnętrza wczytana raz
##   (wcześniej drugie _load tej samej komórki – zdublowana geometria i aktorzy, migotanie z-fighting);
## * HUD w tej samej klatce, w której znika ekran ładowania (WindowManager::updateVisible przy GM_Loading) – wcześniej
##   pierwsza klatka po wczytaniu była bez HUD (HUD sprawdzał widoczność przed zdjęciem ekranu ładowania);
## * WeatherManager::write/readRecord: pogoda (bieżąca, przejście, czas do zmiany) z zapisu – wcześniej po wczytaniu
##   trwało przejście od pogody poprzedniej sesji; zapis bez stanu pogody – pogoda regionu od razu, bez przejścia.
## godot --headless --path godot -s res://tests/test_load_reveal.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

const GameStateScript := preload("res://scripts/mw/mw_game_state.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _cell_nodes(main) -> int:
	var n := 0
	for c in main.get_children():
		if c.get_node_or_null("Refs") != null and not c.is_queued_for_deletion():
			n += 1
	return n

## Do końca odsłaniania; w każdej klatce: gdy ekran ładowania zniknął – HUD już widoczny (stan po _process klatki).
func _until_revealed(main, tag: String) -> void:
	var hud_bad := 0
	for i in 600:
		await process_frame
		if not main.loading.visible and main.game_state == "running" and main.mw_hud.hud_visible \
				and not main.mw_hud.root.visible:
			hud_bad += 1
		if not main.is_revealing() and not main.loading.visible:
			break
	await process_frame
	check(not main.is_revealing(), "%s: świat odsłonięty" % tag)
	check(hud_bad == 0, "%s: HUD widoczny w klatce zdjęcia ekranu ładowania (%d klatek bez HUD)" % [tag, hud_bad])
	check(main.mw_hud.root.visible, "%s: HUD po wczytaniu" % tag)

func _load(main, path: String, tag: String) -> void:
	var w: Array = main.load_slot(null, path)
	check(w.is_empty() or not String(w[0]).begins_with("BŁĄD"), "%s: wczytanie (%s)" % [tag, w])
	# zaraz po wczytaniu (ta sama klatka): ekran ładowania z tapetą zasłania świat do gotowości pierwszej klatki
	check(main.loading.nested > 0 and main.loading.show_wallpaper, "%s: ekran ładowania z tapetą (cleanup → bez gry)" % tag)
	check(main.is_revealing(), "%s: odsłanianie po gotowości" % tag)
	check(main.game_state == "running", "%s: stan gry po wczytaniu" % tag)
	check(_cell_nodes(main) == main.loaded.size(), "%s: bez zdublowanych komórek (%d/%d)" % [tag, _cell_nodes(main), main.loaded.size()])
	await _until_revealed(main, tag)
	check(_cell_nodes(main) == main.loaded.size(), "%s: bez zdublowanych komórek po odsłonięciu" % tag)

func _run() -> void:
	var dir := ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(dir)
	var p_ext := dir.path_join("reveal_ext.mwsave")
	var p_int := dir.path_join("reveal_int.mwsave")
	var p_old := dir.path_join("reveal_old.mwsave")
	var main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var wm = main.envr.wm
	# zapis w świecie w trakcie przejścia pogody (deszcz → mgła, 40% przejścia)
	main.envr.weather = "foggy"
	wm.force(wm.idx("rain"))
	wm.add_transition(wm.idx("foggy"))
	wm.transition = 0.6
	wm.update_time = 7.5
	var want := {"current": wm.current, "next": wm.next_w, "update": wm.update_time}
	main.envr.set_process(false)                 # bez upływu przejścia między ustawieniem a zapisem
	check(main.save_game(p_ext) == "", "zapis w świecie")
	main.envr.set_process(true)
	var raw := GameStateScript.read_file(p_ext)
	check(raw.get("time", {}).has("weather"), "stan pogody w zapisie (WeatherManager::write)")
	# zapis sprzed zmiany: bez stanu pogody
	var old: Dictionary = raw.duplicate(true)
	(old["time"] as Dictionary).erase("weather")
	check(GameStateScript.write_file(p_old, old) == OK, "zapis bez stanu pogody")
	main.travel_to_cell("Synthville, Test House", Vector3(0, 0, 300), 0.0)
	while main.is_revealing():
		await process_frame
	check(main.save_game(p_int) == "", "zapis we wnętrzu")
	# inna pogoda w bieżącej sesji – po wczytaniu nie może zostać przejście od niej
	wm.force(wm.idx("clear"))
	main.envr.weather = "clear"
	await _load(main, p_ext, "w grze: zapis w świecie")
	check(wm.current == int(want.current) and wm.next_w == int(want.next) and absf(wm.transition - 0.6) < 0.05
		and absf(wm.update_time - float(want.update)) < 0.01 and main.envr.weather == "foggy",
		"pogoda z zapisu (bieżąca %d→%d, przejście %.2f)" % [wm.current, wm.next_w, wm.transition])
	await _load(main, p_int, "w grze: zapis we wnętrzu")
	check(not main.interior.is_empty(), "wnętrze po wczytaniu")
	await _load(main, p_int, "ten sam zapis ponownie")
	wm.force(wm.idx("thunder"))
	await _load(main, p_old, "zapis bez stanu pogody")
	check(wm.next_w == -1 and wm.current == wm.idx(main.envr.weather), "bez stanu pogody: pogoda regionu od razu, bez przejścia (%d→%d)" % [wm.current, wm.next_w])
	# menu główne bez gry (start do menu) → Wczytaj
	main.cleanup()
	main._enter_nogame()
	main.open_main_menu()
	await process_frame
	main.close_main_menu()
	await _load(main, p_int, "menu główne bez gry")
	main.queue_free()
	await process_frame
	await process_frame
	# start z `--load` (wnętrze): ekran ładowania z tapetą, jedna kopia komórki
	ProjectSettings.set_setting("mwgodot/cli/load", p_int)
	var m2 = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m2)
	ProjectSettings.set_setting("mwgodot/cli/load", null)
	check(not m2.interior.is_empty(), "--load: wnętrze z zapisu")
	check(m2.loading.nested > 0 and m2.loading.show_wallpaper and m2.is_revealing(), "--load: ekran ładowania z tapetą i odsłanianie")
	check(_cell_nodes(m2) == 1 and m2.loaded.size() == 1, "--load: komórka wnętrza wczytana raz (%d węzłów)" % _cell_nodes(m2))
	await _until_revealed(m2, "--load")
	check(_cell_nodes(m2) == 1, "--load: jedna kopia komórki po odsłonięciu")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)
