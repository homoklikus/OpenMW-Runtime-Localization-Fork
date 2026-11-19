extends SceneTree
## Gra: start w świecie, woda, pora dnia/pogoda wg regionu, drzwi do wnętrza i z powrotem.
## godot --headless --path godot -s res://tests/test_game.gd -- --data=WYNIKI --project=KATALOG

var failures: Array[String] = []
var checks := 0
var report := {}

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	check(main.player != null, "gracz utworzony")
	# World::startNewGame(bypass): nowa gra bez skryptowego kreatora – CharGenState = −1, zapis dozwolony
	check(main.scripts == null or (main.scripts.get_global("chargenstate") == -1.0 and main.saving_allowed()),
		"nowa gra bez kreatora: CharGenState −1 i zapis dozwolony (%s)" % [main.scripts.get_global("chargenstate") if main.scripts != null else "-"])
	# start „w mieście”: punkt wyjścia z budynku (cel drzwi wnętrza „Synthville, …” prowadzących na ulicę)
	var st = main._named_start("Synthville")
	var exit_pos := MWCoords.mw_to_godot(Vector3(1200, 8150, 0))
	check(st != null and Vector2(st.origin.x - exit_pos.x, st.origin.z - exit_pos.z).length() < 0.05,
			"start w mieście = wyjście z budynku (%s)" % [st.origin if st != null else null])
	check(main._named_start("Nieistniejące Miasto") == null, "nieznane miasto → brak nazwanego startu")
	# współrzędne testowe w pasku (komórka + pozycja MW), F3 ukrywa
	main.show_coords = true                  # pasek informacji (F3) – domyślnie ukryty
	var ct: String = main.coords_text()
	var ps: String = main.position_string()
	var pos_back := MWCoords.mw_to_godot(Vector3(float(ps.get_slice(",", 0)), float(ps.get_slice(",", 1)), float(ps.get_slice(",", 2))))
	check(ct.contains("komórka") and ct.contains(ps), "pasek: komórka i pozycja (%s)" % ct.strip_edges())
	check(pos_back.distance_to(main.player.global_position) < 0.05, "pozycja z paska wraca w to samo miejsce (--pos)")
	main.show_coords = false
	check(main.coords_text() == "", "F3: współrzędne ukryte")
	main.show_coords = true
	_test_capture(main)
	_test_save(main)
	await _test_actor(main)
	_test_localization(main)
	check(main.loaded.size() == 4, "4 komórki zewnętrzne wczytane wokół gracza (%d)" % main.loaded.size())
	var waters := main.find_children("Water", "MeshInstance3D", true, false)
	check(waters.size() == 4, "woda w każdej komórce zewnętrznej (%d)" % waters.size())
	# łączenia: sąsiednie płaszczyzny stykają się dokładnie, a falowanie zależy od współrzędnych świata (bez szczelin)
	var xs := []
	for wn in waters:
		xs.append(snappedf((wn as Node3D).global_position.x, 0.001))
	xs.sort()
	var size: float = (waters[0].mesh as PlaneMesh).size.x
	check(absf((xs[2] - xs[0]) - size) < 0.01, "woda: sąsiednie komórki stykają się bez przerwy (%s, %.3f)" % [xs, size])
	var code: String = (waters[0].mesh.material as ShaderMaterial).shader.code
	check(code.contains("MODEL_MATRIX") and code.contains("wpos"), "woda: fale we współrzędnych świata")
	# pora dnia
	var env: MWEnvironment = main.envr
	env.time_running = false
	env.forced_weather = "clear"          # kolory słońca zależą od pogody (Weather_*_Sun_*_Color)
	env.pick_weather()
	env.game_hour = 12.0
	env.apply()
	var noon: float = env.sun.light_energy
	var noon_col: Color = env.sun.light_color
	env.game_hour = 0.5
	env.apply()
	report["sun_noon_midnight"] = [noon, env.sun.light_energy, env.sun.visible, noon_col.to_html(), env.sun.light_color.to_html(), env.weather]
	check(noon > 0.4 and (env.sun.light_energy < 0.05 or not env.sun.visible or env.sun.light_color.get_luminance() < noon_col.get_luminance() * 0.6), "słońce: jasno w południe, ciemno w nocy (księżyc)")
	check(absf(MWEnvironment.sun_elevation_deg(13.0) - rad_to_deg(atan(100.0 / 75.0))) < 1e-3, "najwyżej słońce o 13:00 jak w Morrowindzie (53,13°)")
	await process_frame
	check(main.current_region.to_lower() == "synthetic region", "region z komórki (%s)" % main.current_region)
	env.forced_weather = ""
	env.pick_weather()
	var w1: String = env.weather
	env.pick_weather()
	check(env.weather == w1 and env.weather in ["clear", "cloudy", "foggy", "rain"], "pogoda deterministyczna z szans REGN (%s)" % env.weather)
	env.advance(24.0 * 5)
	check(env.day == 5, "upływ 5 dób")
	# drzwi → wnętrze
	var door: Node = null
	for n in main.find_children("*", "Node3D", true, false):
		if n.get_meta("mw_base", "") == "synth_door":
			door = n
	check(door != null, "drzwi w świecie")
	var dest := MWTravel.door_destination(door)
	check(dest.get("cell_key", "") == "int:synthville, test house", "cel drzwi: wnętrze Test House")
	check(main.activate(door), "aktywacja drzwi")
	for i in 3:
		await physics_frame
	check(main.interior == "Synthville, Test House" and main.loaded.has("int:synthville, test house") and main.loaded.size() == 1, "wnętrze wczytane, świat zwolniony")
	check(env.interior and env.env.background_mode == Environment.BG_COLOR, "środowisko wnętrza (bez nieba, AMBI)")
	report["interior_ambient"] = env.env.ambient_light_color
	check(env.env.ambient_light_color.is_equal_approx(Color8(0x40, 0x40, 0x40)), "kolor otoczenia z AMBI")
	var t: Transform3D = dest["transform"]
	check(main.player.global_position.distance_to(t.origin) < 0.5, "gracz w punkcie docelowym drzwi")
	# powrót na zewnątrz (cel bez komórki = świat zewnętrzny)
	var back := {"cell_key": "", "cell_name": "", "transform": Transform3D(Basis(), MWCoords.mw_to_godot(Vector3(4000, 4000, 1500)))}
	main.travel(back)
	for i in 3:
		await physics_frame
	check(main.interior == "" and main.loaded.size() == 4 and not env.interior, "powrót do świata zewnętrznego")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)

## Lokalizacja runtime (fork OpenMW RLF): język wybierany w grze, kolejność plików, znaczniki, warianty INFO, QA.
const Loc := preload("res://scripts/mw/mw_localization.gd")

func _test_localization(main) -> void:
	var data: String = main.db.data_root
	var off = Loc.create(data, [], "original")
	check(not off.is_active() and off.available.has("PL"), "lokalizacja: „original” wyłącza tłumaczenia (%s)" % [off.available])
	var pl = Loc.create(data, [], "auto", "pl", "mwg_synthtown_patch.esp")
	check(pl.is_active() and pl.languages == PackedStringArray(["PL"]), "„auto” = język launchera (%s)" % [pl.languages])
	var door: Dictionary = main.db.get_object("synth_door")
	check(pl.object_name(door) == "Drzwi (łatka)", "nazwa drzwi z późniejszego pliku (%s)" % pl.object_name(door))
	check(pl.object_name_bbcode(door).begins_with("[color=#ff40ff]QA:[/color] "), "QA: znacznik dla modułu łatki")
	var pl_noqa = Loc.create(data, [], "pl")
	check(pl_noqa.bbcode(Loc.key("DOOR", "synth_door", "FNAM"), "") == "Drzwi (łatka)", "bez QA – czysty tekst")
	check(Loc.to_bbcode("[b][c=#ffd060]Drzwi[/c][/b] do") == "[b][color=#ffd060]Drzwi[/color][/b] do", "znaczniki → BBCode")
	check(Loc.strip_markup("[c=#ffd060]Drzwi[/c] do domu") == "Drzwi do domu", "plain bez znaczników")
	var bad = pl_noqa.lookup(Loc.key("ACTI", "synth_windmill", "FNAM"))
	check(not bad.is_empty() and Loc.to_bbcode(bad[0]) == "[lb]b]Wiatrak[lb]/i]", "błędne znaczniki → tekst bez formatowania")
	var de = Loc.create(data, [], "de,pl")
	check(de.object_name(door) == "Testtür", "kolejność języków: DE przed PL (%s)" % de.object_name(door))
	check(de.object_name(main.db.get_object("synth_crate")) == "Skrzynka (łatka)", "brak DE → następny język (PL)")
	check(pl_noqa.info_text("Greeting 0", "SYNTH_INFO_1", "Hello.", true) == "Witaj, wędrowczyni.", "INFO: wariant płci NPC")
	check(pl_noqa.info_text("Greeting 0", "synth_info_1", "Hello.", false, true) == "Witaj, wędrowcze.", "INFO: wariant NPC przed domyślnym")
	check(pl_noqa.info_text("Brak", "x", "Oryginał") == "Oryginał", "INFO: brak tłumaczenia → oryginał")
	check(pl_noqa.fallback_value("Question 1", "Question", "?") == "Pytanie?", "wartości Morrowind.ini (fallbacks)")
	# pasek gry: region przetłumaczony, po wyłączeniu – oryginał z ESM
	main.loc = pl_noqa
	check(main.display_location() == "Kraina Syntetyczna (PL)", "pasek: region po polsku (%s)" % main.display_location())
	main.loc = off
	check(main.display_location() == "Kraina Syntetyczna", "pasek: region oryginalny (%s)" % main.display_location())



## Tryb zrzutu: kamera i kierunek jak ujęcie OpenMW (yaw 0 = +Y MW, pitch > 0 = w dół), stała pora i pogoda.
func _test_capture(main) -> void:
	var saved_pos: Vector3 = main.player.global_position
	var saved_rot: float = main.player.rotation.y
	var saved_hour: float = main.envr.game_hour
	for kv in [["camera", "1000,2000,700"], ["look", "%f,0.2" % (PI / 2.0)], ["hour", "12"], ["weather", "foggy"], ["fov", "60"]]:
		ProjectSettings.set_setting("mwgodot/cli/" + kv[0], kv[1])
	main._apply_capture()
	var cam: Camera3D = main.player.get_node("Camera3D")
	var want := MWCoords.mw_to_godot(Vector3(1000, 2000, 700))
	check(cam.global_position.distance_to(want) < 0.01, "zrzut: kamera w punkcie MW (%s / %s)" % [cam.global_position, want])
	var fwd := -cam.global_transform.basis.z
	var mw_fwd := Vector3(fwd.x, -fwd.z, fwd.y)   # Godot → MW (x, y, z)
	check(mw_fwd.x > 0.9 and absf(mw_fwd.y) < 0.05 and mw_fwd.z < -0.1, "zrzut: yaw π/2 = wschód (+X MW), pitch w dół (%s)" % mw_fwd)
	check(main.envr.game_hour == 12.0 and not main.envr.time_running and main.envr.weather == "foggy", "zrzut: pora i pogoda stałe")
	check(is_equal_approx(cam.fov, 60.0) and main.player.fly, "zrzut: FOV 60 i kamera nieruchoma")
	for k in ["camera", "look", "hour", "weather", "fov"]:
		ProjectSettings.set_setting("mwgodot/cli/" + k, null)
	main.envr.forced_weather = ""
	main.envr.time_running = true
	main.envr.game_hour = saved_hour
	main.envr.pick_weather()
	main.player.fly = false
	cam.rotation.x = 0
	cam.fov = 75
	main.player.global_position = saved_pos
	main.player.rotation.y = saved_rot


## Etap 0: GameState i zapis v1 – stan referencji, pozycja, czas; migracje; zgodność wtyczek; nieznane sekcje.
func _test_save(main) -> void:
	var GS = main.GameStateScript
	var dir := ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var path := dir.path_join("t1.mwsave")
	# referencja z modelem w jednej z wczytanych komórek
	var target: Node3D = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if n.get_node_or_null("Model") != null:
				target = n
				break
		if target:
			break
	check(target != null, "zapis: jest referencja z modelem")
	if target == null:
		return
	var sid := String(target.get_meta("mw_sid"))
	main.state.set_enabled(sid, false)
	var node := _find_ref(main, sid)
	check(node != null and node.get_meta("mw_disabled", false) and node.get_node_or_null("Model") == null,
			"GameState: wyłączona referencja przebudowana bez modelu (%s)" % sid)
	var pos0: Vector3 = main.player.global_position + Vector3(3, 0, -2)
	main.player.global_position = pos0
	main.player.rotation.y = 1.25
	main.envr.game_hour = 17.5
	main.envr.day = 3
	# v2 (etap 3): inwentarz gracza i przedmiot położony w świecie
	main.state.set_inventory("player", [{"id": "Misc_Spoon", "count": 2}, {"id": "zero", "count": 0}])
	var cell_key: String = main.loaded.keys()[0]
	var p_mw: Vector3 = MWCoords.godot_to_mw(main.player.global_position)
	var dsid: String = main.state.add_dynamic("misc_spoon", cell_key, p_mw + Vector3(50, 0, 0), Vector3.ZERO, 1)
	check(dsid.begins_with("dyn#") and _find_ref(main, dsid) != null, "przedmiot położony w świecie: węzeł w komórce (%s)" % dsid)
	check(main.state.inventory("player") == [{"id": "misc_spoon", "count": 2}], "inwentarz: id małymi literami, bez zerowych")
	check(main.save_game(path) == "", "zapis gry")
	var raw: Dictionary = GS.read_file(path)
	check(raw.get("format") == "mwgodot-save" and int(raw.get("version")) == GS.VERSION and raw["refs"].has(sid)
			and raw["header"]["content"].size() >= 2, "plik zapisu: format, wersja, stan referencji, lista wtyczek (%s)"
			% [JSON.stringify(raw).left(300)])
	# zmiany po zapisie…
	main.state.set_enabled(sid, true)
	check(_find_ref(main, sid).get_node_or_null("Model") != null, "GameState: ponowne włączenie przywraca model")
	main.player.global_position += Vector3(40, 0, 40)
	main.envr.game_hour = 8.0
	# …i odczyt
	var w: Array = main.load_game(path)
	check(w.is_empty(), "odczyt bez ostrzeżeń dla tych samych danych (%s)" % [w])
	check(main.player.global_position.distance_to(pos0) < 0.01 and absf(main.player.rotation.y - 1.25) < 1e-4,
			"odczyt: pozycja i kierunek gracza")
	check(is_equal_approx(main.envr.game_hour, 17.5) and main.envr.day == 3, "odczyt: czas gry")
	check(not main.state.is_enabled(sid) and _find_ref(main, sid).get_meta("mw_disabled", false),
			"odczyt: stan referencji odtworzony w świecie")
	check(main.loaded.size() == 4, "odczyt: komórki wokół gracza wczytane (%d)" % main.loaded.size())
	check(main.state.inventory("player") == [{"id": "misc_spoon", "count": 2}] and _find_ref(main, dsid) != null,
			"odczyt v2: inwentarz gracza i przedmiot w świecie")
	main.state.remove_dynamic(dsid)
	check(_find_ref(main, dsid) == null, "podniesienie przedmiotu dynamicznego usuwa węzeł")
	main.load_game(path)
	# atomowość: poprzednia wersja jako .bak
	main.save_game(path)
	check(FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"), "zapis atomowy z kopią .bak")
	# zgodność: brak wtyczki, zmieniona wtyczka, nowa wtyczka – ostrzeżenia, obiekty w zapisie zostają
	var h: Dictionary = main.save_header()
	var h2 := h.duplicate(true)
	h2["content"][1]["sha256"] = "x"
	h2["content"].append({"name": "Brakujacy.esp", "sha256": "y"})
	var ws: Array = GS.compatibility(h2, h)
	check(ws.size() == 2 and String(ws[0]).contains("zmieniła") and String(ws[1]).contains("brak wtyczki"),
			"zgodność: zmieniona i brakująca wtyczka (%s)" % [ws])
	var h3 := h.duplicate(true)
	h3["content"].reverse()
	check(str(GS.compatibility(h3, h)).contains("kolejność"), "zgodność: zmiana kolejności ładowania")
	# nieznana sekcja (z nowszej gry tej samej wersji formatu) i wpis dla brakującej wtyczki – zachowane
	raw = GS.read_file(path)
	raw["ai_future"] = {"x": 1}
	raw["refs"]["brakujacy.esp#7"] = {"enabled": false}
	GS.write_file(path, raw)
	w = main.load_game(path)
	check(str(w).contains("ai_future"), "odczyt: ostrzeżenie o nieznanej sekcji")
	main.save_game(path)
	raw = GS.read_file(path)
	check(raw.has("ai_future") and raw["refs"].has("brakujacy.esp#7"), "ponowny zapis zachowuje nieznane sekcje i wpisy brakujących wtyczek")
	# migracje: nowsza wersja – błąd i oryginał nietknięty; stara wersja – kopia przed migracją
	raw["version"] = 99
	GS.write_file(dir.path_join("future.mwsave"), raw)
	w = main.load_game(dir.path_join("future.mwsave"))
	check(w.size() == 1 and String(w[0]).begins_with("BŁĄD") and int(GS.read_file(dir.path_join("future.mwsave"))["version"]) == 99,
			"zapis z nowszej wersji: błąd, plik bez zmian")
	raw["version"] = 0
	GS.write_file(dir.path_join("old.mwsave"), raw)
	w = main.load_game(dir.path_join("old.mwsave"))
	check(not str(w).contains("BŁĄD") and FileAccess.file_exists(dir.path_join("old.mwsave.v0.bak")),
			"migracja v0 → v4 z kopią bezpieczeństwa")
	var v1 := {"format": "mwgodot-save", "version": 1, "refs": {}, "player": {"interior": ""}}
	var mig: Dictionary = GS.migrate(v1)
	check(mig.get("migrated", false) and mig["data"]["version"] == 5 and mig["data"]["actors"] == {} and mig["data"]["created"] == {} and mig["data"]["inventories"] == {}
			and mig["data"]["dynamic"] == {} and mig["data"]["player"]["level"] == 1 and mig["data"]["dialogue"] == {},
			"migracja v1 → v4: nowe sekcje puste (dialogi, aktorzy), poziom 1")
	check(main.load_game(dir.path_join("nie_ma.mwsave"))[0].begins_with("BŁĄD"), "brak pliku: czytelny błąd")
	# sprzątanie stanu dla dalszych testów
	main.state.from_dict({})
	main._apply_state()

func _find_ref(main, sid: String) -> Node:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				return n
	return null


## Etap 0: MWActor (wspólny aktor), kontrolery, szyna zdarzeń, akcje wejścia.
func _test_actor(main) -> void:
	var p = main.player
	check(p.kind == "player" and p.controller != null and p.controller.has_method("control")
			and p.get_node_or_null("Camera3D") != null, "gracz to MWActor z kontrolerem gracza i kamerą")
	for a in ["menu", "quick_save", "quick_load", "toggle_coords", "copy_position", "activate", "jump"]:
		check(InputMap.has_action(a), "akcja wejścia %s" % a)
	# NPC: ten sam aktor, inny kontroler (tu: stały ruch do przodu) – ta sama fizyka ruchu
	var ctl_src := GDScript.new()
	ctl_src.source_code = "extends Node\nfunc control(a, _d):\n\ta.move_input = Vector2(0, -1)\n"
	ctl_src.reload()
	var npc = preload("res://scripts/mw/mw_actor.gd").new()
	npc.kind = "npc"
	npc.record_id = "test_npc"
	var ctl: Node = ctl_src.new()
	npc.add_child(ctl)
	npc.controller = ctl
	npc.fly = true
	main.add_child(npc)
	var start: Vector3 = p.global_position + Vector3(0, 30, 0)
	npc.global_position = start
	for i in 30:
		await physics_frame
	var moved: Vector3 = npc.global_position - start
	check(moved.z < -5.0 and absf(moved.x) < 0.01, "NPC (MWActor + własny kontroler) porusza się wg intencji (%s)" % moved)
	npc.queue_free()
	# zdarzenia: przeładowanie świata emituje cell_unloaded/cell_loaded, aktywacja – activated(sid, base)
	var got := {"loaded": 0, "unloaded": 0, "act": []}
	var on_l := func(_k): got["loaded"] += 1
	var on_u := func(_k): got["unloaded"] += 1
	var on_a := func(sid, base, kind): got["act"].append([sid, base, kind])
	main.events.cell_loaded.connect(on_l)
	main.events.cell_unloaded.connect(on_u)
	main.events.activated.connect(on_a)
	main._apply_state()
	check(got["unloaded"] == 4 and got["loaded"] == 4, "zdarzenia komórek (%s)" % got)
	var any_ref: Node = main.loaded.values()[0].get_node("Refs").get_child(0)
	var any_sid := String(any_ref.get_meta("mw_sid"))
	main.activate(any_ref)
	if main.menu_mode.visible:
		main.menu_mode.close()
	check(got["act"].size() == 1 and got["act"][0][0] == any_sid and got["act"][0][2] == "player",
			"zdarzenie aktywacji ze stabilnym sid (%s)" % [got["act"]])
	main.events.cell_loaded.disconnect(on_l)
	main.events.cell_unloaded.disconnect(on_u)
	main.events.activated.disconnect(on_a)
