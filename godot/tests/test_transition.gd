extends SceneTree
## Etap 10 – przejścia między komórkami jak Scene::changeToInteriorCell/changeToExteriorCell OpenMW 0.51:
## * ScreenFader w warstwie FadeToBlack (nad sceną, pod HUD-em, oknami i ekranem ładowania),
## * przejście z wczytanej komórki: fadeScreenOut(0.5) na początku, ekran ładowania (zamrożona klatka) od początku
##   przejścia do gotowości świata, potem loadingOff i fadeScreenIn(0.5); pierwsze wejście (bez komórki) – bez
##   zaciemnienia,
## * stara scena ukryta od razu (nie rysowana razem z nową), nowe komórki wczytane, gracz postawiony na podłożu
##   przed odsłonięciem (World::adjustPosition), ekran ładowania nie zostaje po odsłonięciu (zagnieżdżenie 0),
## * wczytanie zapisu: świat odsłaniany po gotowości, bez zaciemnienia,
## * przejścia: świat → wnętrze, wnętrze → świat (drzwi), wnętrze → to samo wnętrze, teleport w świecie,
##   COC przez MWScript (travel_to_cell), wczytanie zapisu we wnętrzu i w świecie.
## godot --headless --path godot -s res://tests/test_transition.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _door_to(main, kind: String) -> Node:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			var d: Dictionary = MWTravel.door_destination(n)
			if d.is_empty():
				continue
			var ck := String(d.get("cell_key", ""))
			if (kind == "int:" and ck.begins_with("int:")) or (kind == "" and ck == ""):
				return n
	return null

## Jedno przejście: stan zaraz po wywołaniu i po odsłonięciu.
func _transition(main, name: String, action: Callable, expect_fade: bool) -> void:
	var old_nodes: Array = []
	for k in main.loaded:
		old_nodes.append(main.loaded[k])
	action.call()
	check(main.is_revealing() and main.loading.visible and main.loading.nested >= 1,
		"%s: ekran ładowania (zamrożona klatka) do gotowości świata" % name)
	check(old_nodes.all(func(n): return not is_instance_valid(n) or not (n as Node3D).visible),
		"%s: stara scena ukryta od razu" % name)
	if expect_fade:
		check(not main.fader.is_empty() or main.fader.alpha > 0.0, "%s: fadeScreenOut(0.5) na początku przejścia" % name)
	var frames := 0
	while main.is_revealing() and frames < 300:
		await process_frame
		frames += 1
	check(not main.is_revealing() and not main.loading.visible and main.loading.nested == 0,
		"%s: odsłonięcie po gotowości (klatki %d, zagnieżdżenie %d)" % [name, frames, main.loading.nested])
	check(main.player.is_physics_processing(), "%s: gracz postawiony na podłożu przed odsłonięciem" % name)
	check(not main.loaded.is_empty(), "%s: nowe komórki wczytane" % name)
	if expect_fade:
		await _frames(2)
		check(main.fader.alpha < 1.0 and (main.fader.is_empty() or main.fader._queue[0].target == 0.0),
			"%s: fadeScreenIn(0.5) po odsłonięciu (alpha %.2f)" % [name, main.fader.alpha])
	await create_timer(0.8, true).timeout       # fadeScreenIn(0.5) – czas rzeczywisty
	check(main.fader.alpha < 0.01, "%s: obraz po zaciemnieniu w pełni widoczny" % name)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	# warstwy: FadeToBlack nad sceną, pod HUD-em i oknami, ekran ładowania nad wszystkim (poza filmami)
	check(main.fader.layer < main.mw_hud.layer and main.fader.layer < main.menu_mode.layer
		and main.fader.layer < main.loading.layer, "ScreenFader w warstwie FadeToBlack (pod HUD-em, oknami, ekranem ładowania)")
	var ext_pos: Vector3 = main.player.global_position
	var d_ext := _door_to(main, "int:")
	check(d_ext != null, "drzwi do wnętrza w świecie syntetycznym")
	if d_ext != null:
		await _transition(main, "świat → wnętrze (drzwi)", func(): main.activate(d_ext), true)
		check(not main.interior.is_empty(), "wnętrze")
		var d_int := _door_to(main, "")
		check(d_int != null, "drzwi na zewnątrz we wnętrzu")
		var inter: String = main.interior
		await _transition(main, "wnętrze → to samo wnętrze (COC)", func(): main.travel_to_cell(inter, Vector3(0, 0, 300), 0.0), true)
		if d_int != null:
			d_int = _door_to(main, "")
			await _transition(main, "wnętrze → świat (drzwi, jak wyjście ze statku)", func(): main.activate(d_int), true)
			check(main.interior.is_empty(), "świat zewnętrzny")
	var far := ext_pos + Vector3(MWCoords.CELL_SIZE / MWCoords.UNITS_PER_METER, 0, 0)
	await _transition(main, "teleport w świecie (inna komórka)", func(): main.travel({"cell_key": "", "cell_name": "",
		"transform": Transform3D(Basis(), far)}), true)
	# podróż w trakcie trybu GUI (pauza – jak usługa podróży w rozmowie): postawienie i odsłonięcie mimo pauzy
	main.get_tree().paused = true
	await _transition(main, "podróż w pauzie (usługa podróży)", func(): main.travel({"cell_key": "", "cell_name": "",
		"transform": Transform3D(Basis(), ext_pos)}), true)
	main.get_tree().paused = false
	await _frames(2)
	# zapis/odczyt w świecie i we wnętrzu: odsłonięcie bez zaciemnienia
	var path_e := ProjectSettings.globalize_path("user://test_saves/transition_ext.mwsave")
	check(main.save_game(path_e) == "", "zapis w świecie")
	await _transition(main, "wczytanie zapisu w świecie", func(): main.load_slot(null, path_e), false)
	if d_ext != null:
		main.travel_to_cell("Synthville, Test House", Vector3(0, 0, 300), 0.0)
		while main.is_revealing():
			await process_frame
		var path_i := ProjectSettings.globalize_path("user://test_saves/transition_int.mwsave")
		check(main.save_game(path_i) == "", "zapis we wnętrzu")
		await _transition(main, "wczytanie zapisu we wnętrzu", func(): main.load_slot(null, path_i), false)
		check(not main.interior.is_empty(), "po wczytaniu – wnętrze")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)
