extends SceneTree
## Etap 8d: przestępstwa, świadkowie i strażnicy – własność, kradzież niezauważona/zauważona (grzywna tylko, gdy
## świadek ma Alarm ≥ 100), strażnik ściga i zagaduje gracza, grzywna i konfiskata, napaść, wytrych i sonda
## (Security, wtargnięcie), więzienie (znacznik, dni, czas), próg iCrimeThreshold (pościg / walka).
## godot --headless --path godot -s res://tests/test_crime.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await process_frame
	return -1

## Referencja o danej bazie; with_key – tylko z tym kluczem w extra (np. „owner”, „lock_level”).
func _ref(main, base: String, with_key := "") -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() != base:
				continue
			if with_key.is_empty() or main.interaction.snapshot(n).extra.has(with_key):
				return n
	return null

func _face(n: Node3D, target: Node3D) -> void:
	var d := target.global_position - n.global_position
	n.rotation.y = atan2(-d.x, -d.z)

func _place(main, n: Node3D, units: float) -> void:
	var dir := -Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
	main.player.global_position = n.global_position + dir * (units / MWCoords.UNITS_PER_METER)

func _has_pursue(ai, n) -> bool:
	for p in ai.ai_state(n).packages:
		if String(p.get("type", "")) == "pursue":
			return true
	return false

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc   # postać po kreatorze (buildPlayer z rasą i klasą) – testy formuł zależnych od umiejętności klasy
	var ai = main.ai
	var cr = main.crime
	var inv = main.interaction.inventory
	var st: Dictionary = main.player_stats()
	st.health_base = 500.0
	st.health = 500.0
	var trader := _ref(main, "synth_trader")
	var spoon := _ref(main, "misc_synth_spoon", "owner")
	var chest := _ref(main, "synth_chest", "lock_level")
	var watch := _ref(main, "synth_watchman")
	var vill := _ref(main, "synth_villager")
	check(trader != null and spoon != null and chest != null and watch != null and vill != null, "dane testowe (kupiec, łyżka, skrzynia, strażnik)")
	if failures.size() > 0:
		print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
		quit(1)
		return
	# własność
	var o: Dictionary = cr.ownership(main.interaction.snapshot(spoon).extra)
	check(bool(o.owned) and o.victim == trader, "łyżka należy do kupca")
	check(not bool(cr.ownership({"owner": "player"}).owned) and not bool(cr.ownership({}).owned), "własna/niczyja – nie kradzież")
	# niezauważona kradzież (niewidzialność, rzut 0)
	_place(main, trader, 200.0)
	await _frames(2)
	main.magic.inflict(main.combat.player_fighter(), {}, {"id": "inv", "name": "inv", "kind": "potion"}, [{"effect": 39, "min": 1, "max": 1, "duration": 60}])
	cr.test_roll = 0
	main.interaction.take_ref(main.interaction.snapshot(spoon))
	check(inv.count_of("player", {}, "misc_synth_spoon") == 1, "łyżka w ekwipunku")
	check(cr.bounty() == 0, "niewidzialny złodziej – bez grzywny (%d)" % cr.bounty())
	check((st.get("stolen", {}) as Dictionary).has("misc_synth_spoon"), "łyżka oznaczona jako skradziona")
	main.magic.active(main.combat.player_fighter()).clear()
	# zauważona, ale bez świadka z Alarm ≥ 100 (kupiec: Alarm 0) – brak zgłoszenia
	cr.test_roll = 99
	check(cr.item_taken({"owner": "synth_trader"}, "misc_synth_spoon", 1), "kradzież na oczach kupca – zauważona")
	inv.add("player", {}, "misc_synth_spoon", 1)
	check(cr.bounty() == 0, "Alarm 0 – kupiec nie zgłasza (%d)" % cr.bounty())
	# strażnik w pobliżu: zgłoszenie, grzywna, pościg
	watch.global_position = trader.global_position + Vector3(3.0, 0, 0)
	_face(watch, main.player)
	await _frames(3)
	cr.item_taken({"owner": "synth_trader"}, "misc_synth_spoon", 1)
	inv.add("player", {}, "misc_synth_spoon", 1)
	var b1: int = cr.bounty()
	check(b1 >= 1, "strażnik widzi – grzywna %d" % b1)
	check(_has_pursue(ai, watch), "strażnik dostaje pakiet pościgu")
	check(bool(main.combat._actor_state(main.combat.fighter_of(watch)).get("alarmed", false)), "strażnik zaalarmowany")
	Engine.time_scale = 3.0
	var talk := await _until(func(): return main.dialogue_window != null and main.dialogue_window.visible, 900)
	check(talk >= 0, "strażnik podbiega i zagaduje gracza")
	if main.dialogue_window != null and main.dialogue_window.visible:
		main.dialogue_window.close(true)
	await _frames(2)
	# grzywna: złoto i konfiskata
	inv.add("player", {}, "gold_001", 500)
	var gold0: int = inv.count_of("player", {}, "gold_001")
	var b2: int = cr.bounty()
	cr.pay_fine()
	check(cr.bounty() == 0 and inv.count_of("player", {}, "gold_001") == gold0 - b2, "zapłacono grzywnę %d" % b2)
	check(inv.count_of("player", {}, "misc_synth_spoon") == 0, "skradzione łyżki zabrane")
	await _frames(30)
	check(not _has_pursue(ai, watch), "po zapłacie pościg kończy się")
	# sonda i wytrych (cudza skrzynia – wtargnięcie)
	inv.add("player", {}, "synth_probe", 1)
	inv.add("player", {}, "synth_lockpick", 1)
	_place(main, chest, 80.0)
	watch.global_position = chest.global_position + Vector3(2.5, 0, 0)
	_face(watch, main.player)
	await _frames(3)
	var csid: String = main.interaction.sid_of(chest)
	var r1: Dictionary = cr.use_tool(chest, "synth_probe", "probe", 0)
	await _frames(2)
	chest = _ref(main, "synth_chest", "lock_level")
	check(bool(r1.ok) and String(main.interaction.trap(chest)).is_empty(), "sonda rozbraja pułapkę (%s)" % [r1])
	check(cr.bounty() == 5, "próba przy cudzej skrzyni – wtargnięcie (grzywna %d)" % cr.bounty())
	var r2: Dictionary = cr.use_tool(chest, "synth_lockpick", "lockpick", 99)
	await _frames(2)
	chest = _ref(main, "synth_chest", "lock_level")
	check(not bool(r2.ok) and main.interaction.lock_level(chest) == 20, "nieudany wytrych – zamek bez zmian (%s)" % [r2])
	var r3: Dictionary = cr.use_tool(chest, "synth_lockpick", "lockpick", 0)
	await _frames(2)
	chest = _ref(main, "synth_chest", "lock_level")
	check(bool(r3.ok) and main.interaction.lock_level(chest) == 0, "wytrych otwiera zamek (%s)" % [r3])
	# czar na zamek (applyMagicEffect): Zamknięcie 30 → poziom 30; Otwarcie 20 – bez zmian; Otwarcie 40 – otwiera;
	# Zamknięcie 10 nie obniża poziomu 30
	check(main._lock_effect(chest, {"effect": 12, "min": 30, "max": 30}, false), "Zamknięcie działa na skrzynię")
	chest = _ref(main, "synth_chest", "lock_level")
	check(main.interaction.lock_level(chest) == 30, "Zamknięcie 30 (%d)" % main.interaction.lock_level(chest))
	main._lock_effect(chest, {"effect": 12, "min": 10, "max": 10}, false)
	main._lock_effect(chest, {"effect": 13, "min": 20, "max": 20}, false)
	chest = _ref(main, "synth_chest", "lock_level")
	check(main.interaction.lock_level(chest) == 30, "Zamknięcie 10 i Otwarcie 20 – poziom 30 bez zmian")
	main._lock_effect(chest, {"effect": 13, "min": 40, "max": 40}, false)
	chest = _ref(main, "synth_chest", "lock_level")
	check(main.interaction.lock_level(chest) == 0, "Otwarcie 40 otwiera zamek 30")
	check(not main._lock_effect(vill, {"effect": 12, "min": 30, "max": 30}, false), "Zamknięcie na aktorze – efekt nieprawidłowy")
	cr.pay_fine(false)
	await _frames(30)
	# napaść: strażnik widzi – grzywna iCrimeAttack, ofiara walczy
	_place(main, vill, 120.0)
	watch.global_position = vill.global_position + Vector3(2.5, 0, 0)
	_face(watch, main.player)
	await _frames(3)
	cr.on_assault(vill)
	check(cr.bounty() == 40, "napaść – grzywna 40 (%d)" % cr.bounty())
	check(ai.in_combat(vill), "napadnięty broni się")
	ai.stop_combat(vill)
	main.dialogue.set_ai_setting(main.dialogue.make_actor(vill), "fight", 0)
	await _frames(2)
	# więzienie: 250 → 2 dni, znacznik więzienia, czas
	ai.stop_combat(watch)
	for p in ai.ai_state(watch).packages.duplicate():
		if String(p.get("type", "")) == "pursue":
			ai.ai_state(watch).packages.erase(p)
	cr.set_bounty(250)
	var h0: float = main.envr.hours_total() if main.envr.has_method("hours_total") else 0.0
	var p_before: Vector3 = ai.mw_pos(main.player)
	var j: Dictionary = cr.go_to_jail()
	check(int(j.days) == 2 and cr.bounty() == 0 and bool(main.state.player.get("in_jail", false))
		and ai.mw_pos(main.player).distance_to(p_before) < 1.0, "GoToJail: 2 dni, grzywna 0, GetPCInJail, gracz jeszcze na miejscu (World::goToJail)")
	# GM_Jail: zaciemnienie 0,5 s, przeniesienie, okno sInPrisonTitle z paskiem, koniec – okno z pytaniem
	var js = main.jail_screen
	# okno rozmowy zostaje (World::goToJail) – przeniesienie po jego zamknięciu (pierwsza klatka bez pauzy)
	# gra wstrzymana (np. rozmowa ze strażnikiem) – przeniesienie czeka; wcześniej warunek zależał od tego, czy
	# strażnik zdążył zagadać (wyścig w teście), teraz pauza ustawiona jawnie
	var was_paused: bool = main.get_tree().paused
	main.get_tree().paused = true
	await _frames(5)
	check(main.state.player.has("go_to_jail"), "przeniesienie czeka, póki gra stoi (rozmowa)")
	main.get_tree().paused = was_paused
	if main.dialogue_window != null and main.dialogue_window.visible:
		main.dialogue_window.close(true)
	var got := await _until(func(): return main.gui.contains("jail"), 30)
	check(got >= 0 and not js.visible and js.fade_remaining > 0.0, "tryb GM_Jail, najpierw zaciemnienie (okno ukryte)")
	var shown := await _until(func(): return js.visible, 120)
	check(shown >= 0 and js.history.has("teleport") and js.title.text == main.dialogue.gmst_text("sInPrisonTitle", "In prison"),
		"po 0,5 s: przeniesienie i okno więzienia (%s)" % [js.history])
	var done := await _until(func(): return js.history.has("finished"), 400)
	check(done >= 0 and not main.gui.contains("jail"), "koniec odsiadki – tryb zdjęty")
	check(main.msgbox != null and is_instance_valid(main.msgbox), "okno z pytaniem: zwolnienie z więzienia (ReleasedFromPrison)")
	main.press_message_button(0)
	await _frames(5)
	check(not bool(main.state.player.get("in_jail", false)), "GetPCInJail = 0 po wyjściu z trybu GM_Jail")
	var pp: Vector3 = ai.mw_pos(main.player)
	check(Vector2(pp.x, pp.y).distance_to(Vector2(5400, 5200)) < 150.0, "gracz przy znaczniku więzienia (%.0f, %.0f)" % [pp.x, pp.y])
	if main.envr.has_method("hours_total"):
		check(main.envr.hours_total() - h0 >= 47.9, "minęły 2 doby")
	# próg iCrimeThreshold: strażnik widzi gracza z grzywną 1000 – pościg; ×10 – walka
	watch = _ref(main, "synth_watchman")
	watch.global_position = main.player.global_position + Vector3(4.0, 0, 0)
	_face(watch, main.player)
	await _frames(3)
	cr.set_bounty(1000)
	var pur := await _until(func(): return _has_pursue(ai, watch) or (main.dialogue_window != null and main.dialogue_window.visible), 120)
	check(pur >= 0, "grzywna 1000 – strażnik rusza w pościg")
	if main.dialogue_window != null and main.dialogue_window.visible:
		main.dialogue_window.close(true)
	cr.pay_fine(false)
	await _frames(30)
	cr.set_bounty(10000)
	var war := await _until(func(): return ai.in_combat(watch), 120)
	check(war >= 0, "grzywna 10000 – strażnik atakuje")
	ai.stop_combat(watch)
	cr.set_bounty(0)
	Engine.time_scale = 1.0
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
