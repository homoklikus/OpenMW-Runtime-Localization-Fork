extends SceneTree
## Etap 3: interakcje – podpowiedzi, podnoszenie, pojemnik (okno), przenoszenie, zamek, pułapka, odkładanie,
## zapis i odczyt (scenariusz odbioru: podnieś → do pojemnika → zapis → odczyt → przedmiot na miejscu).
## godot --headless --path godot -s res://tests/test_interaction.gd -- --data=WYNIKI(aktorzy)

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	var it = main.interaction
	check(it != null and main.item_window != null, "interakcje i okno przedmiotów utworzone")
	var spoon := _ref(main, "misc_synth_spoon")
	var chest := _ref(main, "synth_chest")
	var npc := _ref(main, "synth_villager")
	check(spoon != null and chest != null and npc != null, "łyżka, skrzynia i NPC wczytani")
	if spoon == null or chest == null:
		_finish()
		return
	check(it.kind_of(spoon) == "item" and it.hint(spoon).contains("Lyzka"), "podpowiedź przedmiotu (%s)" % it.hint(spoon))
	check(it.kind_of(chest) == "container" and it.hint(chest).contains("Skrzynia"), "podpowiedź pojemnika")
	check(it.kind_of(npc) == "" and it.hint(npc) == "", "NPC bez podpowiedzi (dialogi – etap 6)")
	check(it.normalize_gold("Gold_025", 2) == ["gold_001", 50], "złoto jak w OpenMW: gold_025 × 2 → 50 × gold_001")
	var spoon_sid := String(spoon.get_meta("mw_sid"))
	var chest_sid := String(chest.get_meta("mw_sid"))
	var crec: Dictionary = it.container_record("synth_chest")
	var in_chest0: int = it.inventory.count_of(chest_sid, crec, "misc_synth_spoon")
	# podnieś
	check(main.activate(spoon), "aktywacja przedmiotu")
	var s2 := _ref(main, "misc_synth_spoon")
	check(s2 != null and s2.get_meta("mw_disabled", false) and s2.get_node_or_null("Model") == null, "podniesiony przedmiot znika ze świata")
	check(it.inventory.count_of("player", {}, "misc_synth_spoon") == 1, "łyżka w ekwipunku gracza")
	check(main.audio.last_played == "Item Misc Up" and main.audio.stream("Item Misc Up") != null,
			"dźwięk podniesienia (Item Misc Up) z pliku WAV skopiowanego przez konwerter (%s)" % main.audio.last_played)
	check(main.audio.stream("Missing Sound") == null and main.audio.stream("nie_ma_rekordu") == null, "brak pliku/rekordu – bez błędu")
	check(String(it.item_sound("synth_helm", false)).begins_with("Item Armor ") and it.item_sound("synth_helm", false).ends_with(" Down")
			and it.item_sound("misc_synth_spoon", true) == "Item Misc Up"
			and it.item_sound("synth_sword", true) == "Item Weapon Longblade Up", "dźwięki przedmiotów wg klasy (OpenMW): %s" % [[it.item_sound("synth_helm", false), it.item_sound("misc_synth_spoon", true), it.item_sound("synth_sword", true)]])
	# pojemnik: okno + przeniesienie
	var mm = main.menu_mode
	check(main.activate(chest) and mm.visible and mm.cont_sid == chest_sid and mm.windows.has("container") and mm.windows.has("inventory"),
			"aktywacja skrzyni otwiera okno pojemnika i ekwipunku")
	check(mm.item_ids.has("misc_synth_spoon") and mm.cont_ids.size() > 0, "okno: obie siatki wypełnione")
	var gp: Control = mm.windows["container"].find_child("GridPanel", true, false)
	check(gp._can_drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "inventory"}) and not gp._can_drop_data(Vector2.ZERO, {"mw_item": "x", "source": "container"}),
			"pojemnik przyjmuje przedmioty z ekwipunku")
	gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "inventory"})
	check(it.inventory.count_of(chest_sid, crec, "misc_synth_spoon") == in_chest0 + 1 and it.inventory.count_of("player", {}, "misc_synth_spoon") == 0,
			"łyżka przeniesiona do skrzyni")
	mm.activate_item("misc_synth_spoon", "container")
	check(it.inventory.count_of("player", {}, "misc_synth_spoon") == in_chest0 + 1, "dwuklik w pojemniku – cały stos do gracza")
	mm.put_item("misc_synth_spoon")
	mm.close()
	check(not mm.visible and not paused, "zamknięcie okna wznawia grę")
	# zapis → zmiany → odczyt
	var path := ProjectSettings.globalize_path("user://test_saves/interakcje.mwsave")
	check(main.save_game(path) == "", "zapis")
	it.inventory.transfer(chest_sid, crec, "player", {}, "misc_synth_spoon", 99)
	main.state.set_enabled(spoon_sid, true)
	var w: Array = main.load_game(path)
	check(not str(w).contains("BŁĄD"), "odczyt (%s)" % [w])
	check(it.inventory.count_of(chest_sid, crec, "misc_synth_spoon") == in_chest0 + 1 and it.inventory.count_of("player", {}, "misc_synth_spoon") == 0,
			"po odczycie: łyżka w skrzyni, nie u gracza")
	var s3 := _ref(main, "misc_synth_spoon")
	check(s3 != null and s3.get_meta("mw_disabled", false), "po odczycie: łyżki nie ma w świecie")
	# zamek i pułapka (stan gry)
	chest = _ref(main, "synth_chest")
	main.state.set_lock(chest_sid, 25)
	chest = _ref(main, "synth_chest")
	var r: Dictionary = it.activate(chest)
	check(r.action == "locked" and String(r.message).contains("Zamknięte") and r.get("sound") == "LockedChest"
			and it.hint(chest).contains("poziom 25"), "zamknięty pojemnik bez klucza")
	main.state.set_lock(chest_sid, 0)
	main.state.set_trap(chest_sid, "trap_fire00")
	chest = _ref(main, "synth_chest")
	r = it.activate(chest)
	check(r.action == "open_container" and String(r.message).contains("pułapkę") and it.trap(_ref(main, "synth_chest")) == "",
			"pułapka uruchomiona i rozbrojona")
	# odłóż na ziemię → referencja dynamiczna, podniesienie jej z powrotem
	it.inventory.add("player", {}, "misc_synth_spoon", 2)
	var dsid: String = main.drop_item("misc_synth_spoon", 2)
	var dn: Node3D = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_sid", "")) == dsid:
				dn = n
	check(dsid.begins_with("dyn#") and dn != null and dn.get_node_or_null("Model") != null, "odłożony przedmiot w świecie (%s)" % dsid)
	check(dn != null and it.hint(dn).contains("(2)"), "podpowiedź z liczbą sztuk")
	if dn:
		main.activate(dn)
	check(not main.state.dynamic.has(dsid) and it.inventory.count_of("player", {}, "misc_synth_spoon") == 2, "podniesienie odłożonego stosu")
	await _test_movement(main)
	_finish()

## Pływanie (punkt na 0,9 wzrostu pod wodą), nie wyżej niż powierzchnia; upadek – sygnał z wysokością.
func _test_movement(main) -> void:
	var p = main.player
	p.fly = false
	var y0: float = p.global_position.y
	main.set_process(false)              # bez nadpisywania poziomu wody z komórki
	p.water_level = y0 + 4.0
	p.move_input = Vector2.ZERO
	for i in 3:
		await physics_frame
	check(p.swimming, "pływanie, gdy woda sięga ponad 0,9 wzrostu")
	var yb: float = p.global_position.y
	for i in 10:
		await physics_frame
	check(absf(p.global_position.y - yb) < 0.05, "w wodzie bez opadania (bez grawitacji)")
	p.want_jump = true
	for i in 120:
		p.want_jump = true
		await physics_frame
	check(p.global_position.y <= p.water_level - p.height * p.swim_height_scale + 0.05, "wynurzanie tylko do powierzchni")
	p.water_level = -INF
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 60, 0), p.global_position - Vector3(0, 60, 0))
	q.exclude = [p.get_rid()]
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	var ground: float = hit["position"].y if not hit.is_empty() else y0
	var falls := []
	p.landed.connect(func(h): falls.append(h))
	p.global_position.y = ground + 6.0
	p.velocity = Vector3.ZERO
	for i in 180:
		await physics_frame
		if falls.size() > 0:
			break
	check(falls.size() == 1 and falls[0] > 200.0, "upadek: sygnał z wysokością w jednostkach MW (%s)" % [falls])
	main.set_process(true)

func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
