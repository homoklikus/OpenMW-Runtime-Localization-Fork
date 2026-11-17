extends SceneTree
## Etap 8c: wykrywanie (awarenessCheck: niewidzialność, skradanie, przód/tył), agresja (getFightTerm ≥ 100 →
## walka), NPC atakuje gracza wręcz, stworzenie atakiem z rekordu, odpowiedź na atak gracza, ucieczka (Flee),
## NPC rzuca czar „cel” (pocisk trafia gracza).
## godot --headless --path godot -s res://tests/test_combat_ai.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _near(main, n: Node3D, units: float) -> void:
	var dir := -Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))   # przed aktorem
	main.player.global_position = n.global_position + dir * (units / MWCoords.UNITS_PER_METER)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var ai = main.ai
	var cb = main.combat
	var dl = main.dialogue
	var st: Dictionary = main.player_stats()
	st.health_base = 500.0
	st.health = 500.0
	var v := _ref(main, "synth_villager")
	# wykrywanie
	_near(main, v, 150.0)
	await _frames(2)
	check(ai.awareness(main.player, v, 99), "widoczny gracz – zauważony (rzut 99)")
	main.magic.inflict(cb.player_fighter(), {}, {"id": "inv", "name": "inv", "kind": "potion"}, [{"effect": 39, "min": 1, "max": 1, "duration": 60}])
	# OpenMW applyMagicEffect: Niewidzialność działa od pierwszej klatki po nałożeniu (nie przy dt = 0)
	check(main.magic.magnitude_of(cb.player_fighter(), 39) == 0.0 or main.builder.actors.record("magiceffect", "39").is_empty(), "niewidzialność nie działa w chwili nałożenia (dt = 0)")
	await _frames(1)
	check(main.magic.magnitude_of(cb.player_fighter(), 39) > 0.0 or main.builder.actors.record("magiceffect", "39").is_empty(), "niewidzialność (albo brak MGEF 39 w danych)")
	if main.magic.magnitude_of(cb.player_fighter(), 39) > 0.0:
		check(not ai.awareness(main.player, v, 0), "niewidzialny – niezauważony przy rzucie 0")
	main.magic.active(cb.player_fighter()).clear()
	main.player.want_sneak = true
	var seen_front := 0
	var seen_back := 0
	for r in 100:
		if ai.awareness(main.player, v, r):
			seen_front += 1
	v.rotation.y += PI
	for r in 100:
		if ai.awareness(main.player, v, r):
			seen_back += 1
	v.rotation.y -= PI
	main.player.want_sneak = false
	check(seen_back <= seen_front, "skradanie: od tyłu trudniej zauważyć (%d ≤ %d)" % [seen_back, seen_front])
	# agresja: Fight 100 → walka i atak wręcz (kondycja/zdrowie gracza spada)
	var a: Dictionary = dl.make_actor(v)
	check(ai.fight_term(v, main.player) < 100.0, "spokojny NPC (Fight %.0f)" % ai.fight_term(v, main.player))
	dl.set_ai_setting(a, "fight", 100)
	ai.test_roll = 99
	cb.test_roll = 0                     # trafienia pewne (szansa trafienia NPC/stworzeń bywa niska)
	Engine.time_scale = 3.0
	var eng := await _until(func(): return ai.in_combat(v), 200)
	check(eng >= 0, "NPC z Fight 100 rozpoczyna walkę")
	var hits0: int = cb.hits
	var hit := await _until(func(): return cb.hits > hits0, 900)
	check(hit >= 0, "NPC atakuje gracza wręcz (trafienia %d → %d)" % [hits0, cb.hits])
	ai.stop_combat(v)
	dl.set_ai_setting(a, "fight", 0)
	# odpowiedź na atak gracza
	var vf := _ref(main, "synth_villager_f")
	var vff: Dictionary = cb.fighter_of(vf)
	_near(main, vf, 80.0)
	await _frames(2)
	cb.on_hit(vff, cb.player_fighter(), {}, false)
	check(ai.in_combat(vf), "zaatakowany NPC odpowiada walką")
	ai.stop_combat(vf)
	# ucieczka: Flee 100
	var g := _ref(main, "synth_guard")
	dl.set_ai_setting(dl.make_actor(g), "flee", 100)
	_near(main, g, 200.0)
	await _frames(2)
	ai.start_combat(g, main.player)
	var d0: float = ai.mw_pos(g).distance_to(ai.mw_pos(main.player))
	await _frames(240)
	check(bool(ai._rt(g).get("flee", false)), "Flee 100 – ucieczka")
	check(ai.mw_pos(g).distance_to(ai.mw_pos(main.player)) > d0 + 100.0, "uciekający oddala się (%.0f → %.0f)" % [d0, ai.mw_pos(g).distance_to(ai.mw_pos(main.player))])
	ai.stop_combat(g)
	# stworzenie: atak z rekordu (zdrowie)
	var c := _ref(main, "synth_creature")
	_near(main, c, 120.0)
	await _frames(2)
	ai.start_combat(c, main.player)
	var hc: float = cb.health(cb.player_fighter())
	var bit := await _until(func(): return cb.health(cb.player_fighter()) < hc - 0.1, 900)
	check(bit >= 0, "stworzenie rani gracza (%.1f → %.1f)" % [hc, cb.health(cb.player_fighter())])
	ai.stop_combat(c)
	# czar NPC: kupiec zna „synth_bolt” (ogień, cel)
	var t := _ref(main, "synth_trader")
	var tf: Dictionary = cb.fighter_of(t)
	main.magic.set_magicka(tf, 200.0)
	var act: Dictionary = ai._choose_action(t, main.player)
	check(String(act.get("kind", "")) == "spell" and String(act.get("spell", "")) == "synth_bolt", "wybór akcji: czar na odległość (%s)" % [act])
	_near(main, t, 400.0)
	await _frames(2)
	main.magic.test_roll = 0
	ai.start_combat(t, main.player)
	var hb: float = cb.health(cb.player_fighter())
	var burned := await _until(func(): return cb.health(cb.player_fighter()) < hb - 1.0, 900)
	check(burned >= 0, "pocisk ognia NPC trafia gracza (%.1f → %.1f)" % [hb, cb.health(cb.player_fighter())])
	main.magic.test_roll = -1
	Engine.time_scale = 1.0
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
