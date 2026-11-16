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
	# pojemnik: okno + przeniesienie
	check(main.activate(chest) and main.item_window.visible and main.item_window.mode == "container", "aktywacja skrzyni otwiera okno")
	check(main.item_window._right_ids.has("misc_synth_spoon") and main.item_window._left_ids.size() > 0, "okno: obie listy wypełnione")
	main.item_window._move_from_right(main.item_window._right_ids.find("misc_synth_spoon"))
	check(it.inventory.count_of(chest_sid, crec, "misc_synth_spoon") == in_chest0 + 1 and it.inventory.count_of("player", {}, "misc_synth_spoon") == 0,
			"łyżka przeniesiona do skrzyni")
	main.item_window.close()
	check(not main.item_window.visible and not paused, "zamknięcie okna wznawia grę")
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
	check(r.action == "locked" and String(r.message).contains("Zamknięte") and it.hint(chest).contains("poziom 25"), "zamknięty pojemnik bez klucza")
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
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
