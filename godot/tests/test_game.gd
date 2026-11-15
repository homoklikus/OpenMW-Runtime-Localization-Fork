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
	# start „w mieście”: punkt wyjścia z budynku (cel drzwi wnętrza „Synthville, …” prowadzących na ulicę)
	var st = main._named_start("Synthville")
	var exit_pos := MWCoords.mw_to_godot(Vector3(1200, 8150, 0))
	check(st != null and Vector2(st.origin.x - exit_pos.x, st.origin.z - exit_pos.z).length() < 0.05,
			"start w mieście = wyjście z budynku (%s)" % [st.origin if st != null else null])
	check(main._named_start("Nieistniejące Miasto") == null, "nieznane miasto → brak nazwanego startu")
	# współrzędne testowe w pasku (komórka + pozycja MW), F3 ukrywa
	var ct: String = main.coords_text()
	var ps: String = main.position_string()
	var pos_back := MWCoords.mw_to_godot(Vector3(float(ps.get_slice(",", 0)), float(ps.get_slice(",", 1)), float(ps.get_slice(",", 2))))
	check(ct.contains("komórka") and ct.contains(ps), "pasek: komórka i pozycja (%s)" % ct.strip_edges())
	check(pos_back.distance_to(main.player.global_position) < 0.05, "pozycja z paska wraca w to samo miejsce (--pos)")
	main.show_coords = false
	check(main.coords_text() == "", "F3: współrzędne ukryte")
	main.show_coords = true
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
	check(code.contains("MODEL_MATRIX") and code.contains("world_xz"), "woda: falowanie we współrzędnych świata")
	# pora dnia
	var env: MWEnvironment = main.envr
	env.time_running = false
	env.game_hour = 12.0
	env.apply()
	var noon: float = env.sun.light_energy
	env.game_hour = 0.5
	env.apply()
	report["sun_noon_midnight"] = [noon, env.sun.light_energy, env.sun.visible]
	check(noon > 0.4 and (env.sun.light_energy < 0.05 or not env.sun.visible), "słońce: jasno w południe, ciemno w nocy")
	check(absf(MWEnvironment.sun_elevation_deg(12.0) - 70.0) < 1e-3, "wysokość słońca w południe 70°")
	await process_frame
	check(main.current_region.to_lower() == "synthetic region", "region z komórki (%s)" % main.current_region)
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
	check(env.interior and not env.sun.visible, "środowisko wnętrza (bez słońca, AMBI)")
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

