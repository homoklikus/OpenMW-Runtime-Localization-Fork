extends SceneTree
## Etap 10 – stworzenia wodne w grze (dane syntetyczne aktorów; rekord stworzenia z flagami jak Slaughterfish:
## Swims, bez Walks/Flies/Bipedal):
## * wczytanie komórki z rekordu: brak zwolnienia z grawitacji (World::isFlying tylko dla Flies),
##   Class::isPureWaterCreature, poziom pływania z wymiarów kapsuły,
## * stworzenie poza wodą (dane/skrypt) stoi na ziemi – nie unosi się,
## * zalanie komórki (SetWaterLevel) → pływa; walka z graczem pływającym nad nim: płynie ku górze, ale nie ponad
##   poziom pływania (MovementSolver), atakuje,
## * opadnięcie wody → stworzenie wraca na dno (grawitacja), nie wisi w powietrzu,
## * zapis/odczyt i ponowne wczytanie komórki: te same zasady, pozycja zachowana,
## * stworzenie latające (Flies): bez grawitacji; martwe → spada na ziemię (World::isFlying).
## godot --headless --path godot -s res://tests/test_water_game.gd -- --data=WYNIKI(aktorzy) --scripts=0

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
		await physics_frame

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _cell_of(main, n: Node) -> String:
	for key in main.loaded:
		if n.get_parent() == main.loaded[key].get_node("Refs"):
			return key
	return ""

func _reload(main, tag: String) -> void:
	var path_s := ProjectSettings.globalize_path("user://test_saves/water_%s.mwsave" % tag)
	check(main.save_game(path_s) == "", "zapis (%s)" % tag)
	main.load_game(path_s)
	await _frames(5)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var ai = main.ai
	var st: Dictionary = main.player_stats()
	st.health_base = 5000.0
	st.health = 5000.0
	var rec: Dictionary = main.builder.actors.record("creature", "synth_creature")
	check(not rec.is_empty(), "rekord stworzenia syntetycznego")
	var saved_flags := {}
	for k in ["swims", "walks", "flies", "bipedal"]:
		saved_flags[k] = rec.get(k, false)
	rec.swims = true
	rec.walks = false
	rec.flies = false
	rec.bipedal = false
	await _reload(main, "fish")                 # ponowne wczytanie komórki z nowymi flagami rekordu
	var c := _ref(main, "synth_creature")
	check(c != null, "stworzenie po wczytaniu")
	if c == null:
		_finish()
		return
	check(not c.no_gravity and not c.can_fly, "Swims: bez zwolnienia z grawitacji (no_gravity %s)" % c.no_gravity)
	check(ai.is_pure_water_creature(c) and not ai.is_pure_flying_creature(c), "isPureWaterCreature")
	check(absf(c.height - maxf(c.capsule_height, c.capsule_radius * 2.0)) < 0.001, "poziom pływania z wymiarów kapsuły (%.2f)" % c.height)
	var key := _cell_of(main, c)
	# poza wodą: ustawione 3 m nad ziemią (skrypt/dane) → spada i stoi
	await _frames(60)
	var ground: float = c.global_position.y
	c.global_position.y = ground + 3.0
	c.velocity = Vector3.ZERO
	await _frames(150)
	check(not c.swimming and absf(c.global_position.y - ground) < 0.1, "stworzenie wodne poza wodą spada na ziemię (%.2f, ziemia %.2f)" % [c.global_position.y, ground])
	# zalanie: woda 8 m nad ziemią
	var wl_m := ground + 8.0
	main.set_cell_water(key, wl_m * MWCoords.UNITS_PER_METER)
	await _frames(5)
	check(absf(c.water_level - wl_m) < 0.01 and c.swimming, "po podniesieniu wody stworzenie pływa (woda %.2f, y %.2f)" % [c.water_level, c.global_position.y])
	# gracz pływa przy powierzchni nad nim; walka
	main.player.global_position = c.global_position + Vector3(6.0, 7.5, 0.0)   # poza zasięgiem z dna
	main.player.velocity = Vector3.ZERO
	ai.start_combat(c, main.player)
	var max_y: float = wl_m - c.height * c.swim_height_scale
	var top := -INF
	var hp0: float = st.health
	var py := max_y + 1.0                       # gracz pod wodą, metr nad najwyższym punktem pływania stworzenia
	check(py - ground > 3.0, "scena: cel ponad 3 m nad dnem (%.2f)" % (py - ground))
	for i in 2400:
		main.player.global_position = Vector3(main.player.global_position.x, py, main.player.global_position.z)
		await physics_frame
		top = maxf(top, c.global_position.y)
		if float(main.player_stats().health) < hp0 and i > 60:
			break
	check(top <= max_y + 0.03, "w walce stworzenie nie wypływa ponad poziom pływania (maks. %.2f, granica %.2f)" % [top, max_y])
	check(top > ground + 3.0, "stworzenie płynie ku graczowi w górę (pochylenie AI; maks. %.2f, dno %.2f)" % [top, ground])
	check(float(main.player_stats().health) < hp0, "stworzenie atakuje gracza w wodzie (zdrowie %.0f → %.0f)" % [hp0, float(main.player_stats().health)])
	ai.stop_combat(c)
	main.player.global_position = c.global_position + Vector3(20.0, 10.0, 0.0)
	# opadnięcie wody pod ziemię → stworzenie wraca na dno, nie wisi
	main.set_cell_water(key, (ground - 5.0) * MWCoords.UNITS_PER_METER)
	await _frames(200)
	check(not c.swimming and c.global_position.y < ground + 0.3, "po opadnięciu wody stworzenie na ziemi (y %.2f, ziemia %.2f)" % [c.global_position.y, ground])
	# zapis/odczyt
	var pos_s: Vector3 = c.global_position
	await _reload(main, "fish2")
	var c2 := _ref(main, "synth_creature")
	check(c2 != null and c2.global_position.distance_to(pos_s) < 0.3 and not c2.no_gravity, "odczyt: pozycja i grawitacja stworzenia wodnego")
	if c2 != null:
		await _frames(120)
		check(c2.global_position.y < ground + 0.3, "odczyt: stworzenie nie unosi się (y %.2f)" % c2.global_position.y)
	# latające: Flies → bez grawitacji; Paraliż → spada
	rec.flies = true
	rec.swims = false
	await _reload(main, "fly")
	var f := _ref(main, "synth_creature")
	if f != null:
		check(f.can_fly and f.no_gravity and ai.is_pure_flying_creature(f), "Flies: lot bez grawitacji")
		ai.enabled = false
		# podłoże pod latającym (adjustPosition: latający nie jest stawiany na ziemi – z + 20 j.)
		var q := PhysicsRayQueryParameters3D.create(f.global_position + Vector3.UP, f.global_position + Vector3.DOWN * 50.0)
		q.exclude = [f.get_rid()]
		var gh: Dictionary = f.get_world_3d().direct_space_state.intersect_ray(q)
		var gy: float = float(gh.position.y) if not gh.is_empty() else f.global_position.y
		f.global_position.y = gy + 3.0
		await _frames(60)
		check(f.global_position.y > gy + 2.9, "latające nie spada (y %.2f)" % f.global_position.y)
		# World::isFlying: martwy nie leci – ciało spada na ziemię (nie przez nią)
		main.on_actor_died(main.combat.fighter_of(f), {})
		await _frames(150)
		check(not f.no_gravity and f.global_position.y < gy + 0.6 and f.global_position.y > gy - 0.3,
			"martwe latające spada na ziemię (y %.2f, ziemia %.2f)" % [f.global_position.y, gy])
		ai.enabled = true
	for k in saved_flags:
		rec[k] = saved_flags[k]
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)
