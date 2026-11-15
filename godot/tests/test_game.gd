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
	check(main.loaded.size() == 4, "4 komórki zewnętrzne wczytane wokół gracza (%d)" % main.loaded.size())
	var waters := main.find_children("Water", "MeshInstance3D", true, false)
	check(waters.size() == 4, "woda w każdej komórce zewnętrznej (%d)" % waters.size())
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
