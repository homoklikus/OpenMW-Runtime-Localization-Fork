extends SceneTree
## Etap 7a: rozwój umiejętności i awans (OpenMW playerskillhandlers.lua, NpcStats::levelUp, LevelupDialog),
## odpoczynek (restoreDynamicStats), ruch wg statystyk (getWalkSpeed/getRunSpeed/getJump), kondycja za bieg,
## atletyka za sekundę biegu, zapis i odczyt postępu.
## godot --headless --path godot -s res://tests/test_progress.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

static func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc   # postać po kreatorze (buildPlayer z rasą i klasą) – testy formuł zależnych od umiejętności klasy
	var ch = main.character
	var st: Dictionary = main.player_stats()
	check(not st.is_empty(), "postać gracza")
	# wymaganie: długie ostrza 45 (główna, specjalizacja walki): 46 × 0,75 × 0,8 = 27,6
	check(near(ch.skill_requirement(st, 5), 27.6), "wymaganie umiejętności głównej ze specjalizacji (%s)" % ch.skill_requirement(st, 5))
	check(near(ch.skill_requirement(st, 20), 7.5), "akrobatyka (inna): 6 × 1,25 = 7,5 (%s)" % ch.skill_requirement(st, 20))
	check(near(ch.skill_requirement(st, 16), 16.0), "alchemia (drugorzędna, inna specjalizacja): 16 × 1,0 (%s)" % ch.skill_requirement(st, 16))
	var msgs := []
	for i in 40:
		msgs = ch.use_skill(st, 5, 0)
		if not msgs.is_empty():
			break
	check(st.skills[5] == 46.0 and float(st.skill_progress[5]) == 0.0 and msgs.size() == 1 and msgs[0].kind == "skill",
			"28 użyć (przyrost 1) → długie ostrza 46, postęp od zera (%s, %s)" % [st.skills[5], msgs])
	check(int(st.level_progress) == 1 and int(st.skill_increases[0]) == 1 and int(st.spec_increases[0]) == 1,
			"postęp awansu +1, punkt siły, punkt specjalizacji walki")
	ch.skill_level_up(st, 20, "trainer")
	check(st.skills[20] == 6.0 and int(st.level_progress) == 1 and int(st.skill_increases[4]) == 1,
			"umiejętność inna: bez postępu awansu, punkt atrybutu (szybkość wg SKIL)")
	var ath0 := float(st.skills[8])
	ch.skill_level_up(st, 8, "jail")
	check(st.skills[8] == ath0 - 1.0 and int(st.skill_increases[4]) == 1, "więzienie: −1 i bez punktów")
	for k in 4:
		ch.skill_level_up(st, 5, "book")
	for k in 4:
		ch.skill_level_up(st, 6, "trainer")
	check(not ch.can_level_up(st) and int(st.level_progress) == 9, "9 podniesień głównych – jeszcze bez awansu")
	var r: Array = ch.skill_level_up(st, 7, "usage")
	check(ch.can_level_up(st) and r.any(func(m): return m.kind == "levelup_ready"), "10. – gotowość do awansu (komunikat)")
	check(ch.levelup_multiplier(st, 0) == 3 and ch.levelup_multiplier(st, 4) == 2 and ch.levelup_multiplier(st, 1) == 1,
			"mnożniki: siła 5 pkt → ×3, szybkość 1 → ×2, inteligencja 0 → ×1 (%d)" % ch.levelup_multiplier(st, 0))
	# ruch wg statystyk: szybkość 40 → chód 140, bieg 140 × (0,01 × atletyka + 1,75) jedn./s; prędkość gracza
	# z obciążeniem (ubranie startowe z rekordu „player”)
	await _frames(30)
	var mv: Dictionary = ch.movement(st, 0.0, false)
	check(near(mv.walk, 140.0) and near(mv.run, 140.0 * (0.01 * float(st.skills[8]) + 1.75)) and near(main.player.walk_speed, float(ch.movement(st, main.player_weight(), false).walk) / MWCoords.UNITS_PER_METER),
			"prędkość chodu i biegu (%s, %s)" % [mv.walk, mv.run])
	var dd: Dictionary = ch.derived(st)
	var exp_jump: float = ((128.0 + pow(6.0 / 15.0, 4.0)) * 1.0 * ch.fatigue_term(st, dd) + 9.8 * 64.0) / 3.0
	check(near(mv.jump, exp_jump, 0.01), "prędkość skoku jak getJump (%s ≈ %s)" % [mv.jump, exp_jump])
	# Npc::getMaxSpeed: przeciążony (obciążenie > 1) stoi – chód, bieg, pływanie i skok = 0; tuż poniżej – rusza się
	var cap: float = ch.capacity(st)
	var ov: Dictionary = ch.movement(st, cap * 1.01, true)
	check(ov.overburdened and ov.walk == 0.0 and ov.run == 0.0 and ov.swim == 0.0 and ov.jump == 0.0,
			"przeciążony: bez ruchu i skoku (%s)" % [ov])
	var un: Dictionary = ch.movement(st, cap, true)
	check(not un.overburdened and un.walk > 0.0 and un.run > un.walk, "obciążenie = 1: ruch spowolniony, nie zatrzymany (%s)" % [un.walk])
	# kondycja: bieg 1 s zużywa 5 (bez obciążenia), odnowa 2,5 + 0,02 × wytrzymałość
	st["fatigue"] = 50.0
	main.player.move_input = Vector2(0, -1)
	main.player.want_run = true
	main._update_player_rpg(1.0)
	var end := float(dd.attributes[5])
	check(near(float(st.fatigue), 50.0 - 5.0 + 2.5 + 0.02 * end, 0.01), "bieg: kondycja −5 +odnowa (%s)" % st.fatigue)
	var p_before := float(st.skill_progress[8])
	main._update_player_rpg(0.6)
	check(float(st.skill_progress[8]) > p_before, "atletyka: postęp za sekundę biegu")
	main.player.move_input = Vector2.ZERO
	main.player.want_run = false
	# odpoczynek → awans
	for i in 60:
		if main.player.is_on_floor():
			break
		await physics_frame
	st["health"] = 10.0
	var hour0: float = main.envr.game_hour
	check(main.rest_window.open() and main.rest_window.sleeping, "okno odpoczynku (sen na zewnątrz)")
	var hb := float(st.health_base)
	main.rest_window.rest(2)
	for i in 120:
		if not main.rest_window.is_resting():
			break
		await process_frame
	check(near(fposmod(main.envr.game_hour - hour0, 24.0), 2.0), "upływ 2 godzin")
	check(near(float(st.health), minf(float(dd.health.modified), 10.0 + 2.0 * 0.1 * end), 0.01), "sen: zdrowie + 0,1 × wytrzymałość na godzinę (%s)" % st.health)
	var lw = main.levelup_window
	check(lw.visible and not main.rest_window.visible, "po śnie przy postępie ≥ 10 – okno awansu (LevelupDialog)")
	check(lw.level_text.text.ends_with(" 2") and lw.coin_count == 3 and lw.widgets[0].mult.text == "x3" and lw.widgets[1].mult.text == "",
		"„sLevelUpMenu1 2”, 3 monety, mnożnik x3 przy sile, bez mnożnika przy ×1")
	lw.attribute_clicked(0)
	lw.attribute_clicked(5)
	check(lw.widgets[0].value.text == str(int(st.attributes[0]) + 3), "wartość wybranego atrybutu z mnożnikiem")
	check(not lw.ok_clicked(), "za mało wyborów – brak awansu (sNotifyMessage36)")
	lw.attribute_clicked(4)
	var s0 := float(st.attributes[0])
	var e0 := float(st.attributes[5])
	var v0 := float(st.attributes[4])
	check(lw.ok_clicked() and int(st.level) == 2 and not lw.visible, "awans na poziom 2")
	check(st.attributes[0] == s0 + 3.0 and st.attributes[5] == e0 + 1.0 and st.attributes[4] == v0 + 2.0 and int(st.level_progress) == 0,
			"atrybuty z mnożnikami (siła +3, wytrzymałość +1, szybkość +2), postęp wyzerowany")
	check(near(float(st.health_base), hb + (e0 + 1.0) * 0.1), "zdrowie bazowe + wytrzymałość × 0,1")
	check(not main.rest_window.visible and not paused, "okna zamknięte, gra wznowiona")
	# WaitDialog: wrogowie w pobliżu, pasek postępu, przerwanie snu przez listę regionu (BNAM)
	var rw = main.rest_window
	check(not rw.enemies_nearby(), "brak wrogów w pobliżu")
	var reg: Dictionary = main.envr.regions.get(String(main.current_region).to_lower(), {})
	check(String(reg.get("sleep_list", "")) == "synth_lev_creature", "region z listą snu (BNAM) – %s" % [reg.get("sleep_list", "")])
	var dyn0: int = main.state.dynamic.size()
	var h1: float = main.envr.game_hour
	check(rw.open() and rw.sleeping, "ponowny sen")
	# przerwanie snu niezależne od autozapisu (autozapis – test_settings); długi zapis wydłuża klatkę, a TimeAdvancer
	# (jak w OpenMW) może wtedy przejść kilka godzin w jednej klatce i minąć godzinę przerwania
	main.settings["autosave"] = false
	rw.rest(10)
	rw._rest.interrupt = 3
	rw._rest.list = "synth_lev_creature"
	var saw_progress := false
	# klatki o stałym dt = 1/60 s (TimeAdvancer: godzina na krok) – wolna klatka testu w pełnym zestawie
	# nie przeskakuje godziny przerwania; logika okna bez zmian
	rw.set_process(false)
	for i in 400:
		if not rw.is_resting():
			break
		rw._process(1.0 / 60.0)
		if rw.progress_win != null and rw.progress_win.visible:
			saw_progress = true
		await process_frame
	rw.set_process(true)
	check(saw_progress and not rw.progress_win.visible, "pasek postępu w trakcie snu, ukryty po nim")
	check(near(fposmod(main.envr.game_hour - h1, 24.0), 3.0), "sen przerwany po 3 godzinach (%s)" % fposmod(main.envr.game_hour - h1, 24.0))
	check(main.message_boxes.texts().has(main.dialogue.gmst_text("sSleepInterrupt", "Your rest has been interrupted.")), "komunikat sSleepInterrupt")
	check(main.state.dynamic.size() > dyn0 and not main.levelup_window.visible, "stworzenia z listy snu pojawiają się, bez awansu (%d)" % (main.state.dynamic.size() - dyn0))
	check(rw.enemies_nearby() == (main.ai.actor_nodes().any(func(n): return main.ai.fight_term(n, main.player) >= 100.0)),
		"enemiesNearby zgodne z getFightTerm")
	# zapis i odczyt
	var path := ProjectSettings.globalize_path("user://test_saves/postep.mwsave")
	check(main.save_game(path) == "", "zapis")
	st["level"] = 1
	main.load_game(path)
	var b: Dictionary = main.player_stats()
	check(int(b.level) == 2 and near(float(b.health_base), hb + (e0 + 1.0) * 0.1) and b.skills[5] == 50.0,
			"odczyt: poziom, zdrowie bazowe, umiejętności")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
