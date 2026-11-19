extends SceneTree
## Etap 8a/8b: siatka ścieżek (składowe spójności, A*, ścieżka), aktorzy bez AI stoją w miejscu (koniec dryfu),
## AiTravel do celu (GetAIPackageDone), AiWander po punktach siatki w promieniu od startu, powitanie (odwrócenie
## do gracza), pakiety ze skryptu (AiTravel, AiFollow, GetCurrentAIPackage), zapis pozycji i stanu AI.
## godot --headless --path godot -s res://tests/test_ai.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await process_frame
	return -1

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var ai = main.ai
	# punkt pojawiania się stworzenia (LEVC): stworzenie z listy, sid punktu
	var spawned: Node3D = null
	for n in ai.actor_nodes():
		if String(n.get_meta("mw_sid", "")).ends_with("#9018"):
			spawned = n
	check(spawned != null and String(spawned.get_meta("mw_base", "")) == "synth_creature" and spawned.get_meta("mw_actor", "") == "creature",
		"LEVC: stworzenie z listy poziomowanej (%s)" % [spawned.get_meta("mw_base", "") if spawned else null])
	# NPC znają poziom wody komórki (pływanie zamiast tonięcia)
	var any_npc: Node3D = null
	for n in ai.actor_nodes():
		if n.get_meta("mw_actor", "") == "npc":
			any_npc = n
			break
	check(any_npc != null and is_equal_approx(float(any_npc.water_level), 0.0), "NPC: poziom wody komórki (%s)" % [any_npc.water_level if any_npc else null])
	# siatka ścieżek: 4 × 3 punkty + osobna para
	var g = ai.graph("ext:0,0")
	check(g.size() == 14, "14 punktów siatki (%d)" % g.size())
	check(g.connected(0, 11) and not g.connected(0, 12) and g.connected(12, 13), "składowe spójności: siatka i para")
	var path: Array = g.astar(0, 11)
	check(path.size() == 6 and path[0] == 0 and path[-1] == 11, "A*: róg–róg przez 6 punktów (%s)" % [path])
	check(g.astar(0, 12).is_empty(), "brak ścieżki między składowymi")
	var bp: Array = g.build_path(Vector3(1750, 1950, 850), Vector3(3050, 2850, 900))
	check(bp.size() == 7 and (bp[-1] as Vector3).is_equal_approx(Vector3(3050, 2850, 900)), "buildPath: punkty siatki + cel (%d)" % bp.size())
	var open_spot: Vector3 = main.player.global_position      # start gracza – otwarty teren (--pos)
	var tr := _ref(main, "synth_traveler")
	# typ pakietu sprawdzany od razu po wczytaniu – nie po liczbie klatek (pod obciążeniem klatka to więcej czasu gry)
	check(tr != null and ai.current_type(tr) == 1, "pakiet podróży z rekordu (GetCurrentAIPackage = 1) %s" % [JSON.stringify(ai.ai_state(tr)) if tr else "brak"])
	Engine.time_scale = 4.0
	# aktor bez AI stoi w miejscu (kolizje modelu usunięte)
	var v := _ref(main, "synth_villager")
	var v0 := v.global_position
	await _frames(120)
	check(v.global_position.distance_to(v0) < 0.05, "NPC bez AI nie dryfuje (%.3f m)" % v.global_position.distance_to(v0))
	# podróżny: AI_T do (3000, 2800)
	var dest := Vector3(3000, 2800, 0)
	var t0 := Time.get_ticks_msec()
	var f := await _until(func(): return bool(ai.ai_state(tr).get("done", false)), 3000)
	var tp: Vector3 = ai.mw_pos(tr)
	check(f >= 0 and Vector2(tp.x - dest.x, tp.y - dest.y).length() < 140.0, "podróżny dotarł (%s, %d klatek)" % [tp, f])
	# AiSequence::execute: po zakończeniu pusta sekwencja, a przy następnym kroku mLastAiPackage = None (−1)
	await _frames(3)
	check(ai.ai_state(tr).packages.is_empty() and bool(ai.ai_state(tr).done) and ai.current_type(tr) == -1,
		"pakiet zakończony (done; pusta sekwencja → GetCurrentAIPackage −1) %s" % JSON.stringify(ai.ai_state(tr)))
	# wędrowiec: idzie do punktów siatki w promieniu 1000 od startu
	var w := _ref(main, "synth_walker")
	var ws: Vector3 = ai.mw_pos(w)
	var moved := await _until(func(): return ai.mw_pos(w).distance_to(ws) > 150.0, 2000)
	check(moved >= 0, "wędrowiec ruszył")
	var walked := 0.0
	for i in 400:
		await process_frame
		walked = maxf(walked, Vector3(float(ai.ai_state(w).start[0]), float(ai.ai_state(w).start[1]), 0).distance_to(Vector3(ai.mw_pos(w).x, ai.mw_pos(w).y, 0)))
	check(walked < 1000.0 + 200.0, "wędrówka w promieniu (max %.0f)" % walked)
	# powitanie: gracz 100 jednostek od wędrowca – zatrzymanie i odwrócenie
	main.player.global_position = w.global_position + Vector3(1500.0 / MWCoords.UNITS_PER_METER, 0, 0)
	await _until(func(): return String(ai._rt(w).greet) == "none", 120)   # wcześniejsze powitanie (fGreetDistanceReset)
	# etap 10: gdy wędrowiec jeszcze mówi (głos poprzedniego powitania), DialogueManager::say odmawia i powitanie
	# kończy się od razu (jak w OpenMW) – czekamy na koniec kwestii
	var wsid := String(w.get_meta("mw_sid", ""))
	await _until(func(): return main.audio == null or not main.audio.say_active(wsid), 300)
	main.player.global_position = w.global_position + Vector3(100.0 / MWCoords.UNITS_PER_METER, 0, 0)
	var greeted := await _until(func():
		if String(ai._rt(w).greet) != "progress":        # wędrowiec może iść dalej – gracz trzyma się obok
			main.player.global_position = w.global_position + Vector3(100.0 / MWCoords.UNITS_PER_METER, 0, 0)
		return String(ai._rt(w).greet) == "progress", 300)
	check(greeted >= 0, "powitanie gracza (Hello 30 × iGreetDistanceMultiplier)")
	await _frames(20)
	var wp: Vector3 = ai.mw_pos(w)
	var pp: Vector3 = ai.mw_pos(main.player)
	var face := Vector2(-sin(w.rotation.y), cos(w.rotation.y))
	check(face.dot(Vector2(pp.x - wp.x, pp.y - wp.y).normalized()) > 0.9, "wędrowiec patrzy na gracza")
	main.player.global_position += Vector3(30.0, 0, 0)
	# pakiety ze skryptu: AiTravel i AiFollow
	main.scripts._ai_function("aitravel", {"node": tr}, [["num", 2200.0], ["num", 2000.0], ["num", 900.0]], null)
	check(ai.current_type(tr) == 1 and not bool(ai.ai_state(tr).done), "AiTravel ze skryptu")
	# regresja (strażnik ze statku): nowy pakiet ma własny PathFinder – stan drogi zakończonego pakietu nie
	# może sprawić, że następny od razu uzna cel za osiągnięty
	check((ai._rt(tr).path as Array).is_empty() and not bool(ai._rt(tr).get("path_built", false)), "nowy pakiet: wyczyszczona droga")
	await _frames(30)
	# niezmiennik zamiast liczby klatek: zakończony tylko u celu (pod obciążeniem 30 klatek to więcej czasu gry)
	var trp: Vector3 = ai.mw_pos(tr)
	var at_dest := Vector2(trp.x - 2200.0, trp.y - 2000.0).length() < 140.0
	check((not bool(ai.ai_state(tr).done) and ai.current_type(tr) == 1) or at_dest,
		"AiTravel ze skryptu nie kończy się przed dotarciem (%s, done=%s)" % [trp, ai.ai_state(tr).done])
	main.scripts._ai_function("aifollow", {"node": tr}, [["id", "player"], ["num", 0.0], ["num", 0.0], ["num", 0.0], ["num", 0.0]], null)
	check(main.scripts._ai_function("getcurrentaipackage", {"node": tr}, [], null) == 3.0, "AiFollow zastępuje AiTravel (GetCurrentAIPackage = 3)")
	# znane, otwarte pozycje (nie tam, gdzie podróżny akurat doszedł – pod obciążeniem bywało to w ścianie chaty)
	tr.global_position = open_spot + Vector3(0, 0.3, 0)
	tr.velocity = Vector3.ZERO
	main.player.global_position = open_spot + Vector3(420.0 / MWCoords.UNITS_PER_METER, 0.3, 0)
	main.player.velocity = Vector3.ZERO
	# getLOS (maska World | HeightMap | Door): inny aktor między nimi nie zasłania widoczności
	var vv := _ref(main, "synth_villager")
	var v_back: Vector3 = vv.global_position
	vv.global_position = open_spot + Vector3(210.0 / MWCoords.UNITS_PER_METER, 0.3, 0)
	await physics_frame
	await physics_frame
	check(ai._los(tr, main.player), "widoczność: aktor między NPC a graczem nie zasłania (getLOS bez aktorów)")
	vv.global_position = v_back
	await _frames(2)
	var d0: float = ai.mw_pos(tr).distance_to(ai.mw_pos(main.player))
	var fol := await _until(func(): return ai.mw_pos(tr).distance_to(ai.mw_pos(main.player)) < 260.0, 1500)
	check(fol >= 0 and d0 > 260.0 and d0 < 535.0, "podąża za graczem (%.0f → blisko; teraz %.0f, %s)" % [d0, ai.mw_pos(tr).distance_to(ai.mw_pos(main.player)), JSON.stringify(ai.ai_state(tr))])
	# zapis: pozycja i stan AI
	Engine.time_scale = 1.0
	var saved: Vector3 = ai.mw_pos(tr)
	var path_s := ProjectSettings.globalize_path("user://test_saves/ai.mwsave")
	check(main.save_game(path_s) == "", "zapis")
	ai.enabled = false            # sprawdzamy samo przywrócenie pozycji – bez dalszego ruchu podążającego NPC
	main.load_game(path_s)
	await _frames(3)
	var tr2 := _ref(main, "synth_traveler")
	ai.enabled = true
	check(tr2 != null and ai.mw_pos(tr2).distance_to(saved) < 40.0, "odczyt: pozycja podróżnego (%s vs %s)" % [ai.mw_pos(tr2) if tr2 else null, saved])
	check(tr2 != null and ai.current_type(tr2) == 3, "odczyt: pakiet podążania")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
