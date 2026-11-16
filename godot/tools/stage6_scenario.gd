extends SceneTree
## Odbiór etapu 6 na danych z gry (komórka „Balmora, Caius Cosades' House”): zadanie A1_1 po rozmowie z kapitanem
## (A1_1_FindSpymaster = 1, paczka), rozmowa z Caiusem – powitanie, „report to caius cosades” z pytaniami (odpowiedź pierwsza),
## oddanie paczki, Blades, „orders” (złoto, zadanie zakończone), ponownie „orders” → nowe zadanie A1_2;
## zapis i odczyt. Raport tylko z id i liczbami (bez tekstów gry).
## godot --headless --path godot -s res://tools/stage6_scenario.gd -- --data=DANE
##     --cell="Balmora, Caius Cosades' House" --out=wynik.json --scripts=1

var report := {"steps": []}

func _init() -> void:
	_run.call_deferred()

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def

func _step(name: String, ok: bool, data := {}) -> void:
	report.steps.append({"step": name, "ok": ok, "data": data})
	print("STEP %s %s %s" % ["OK " if ok else "BŁĄD", name, JSON.stringify(data)])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Temat i pytania: zawsze pierwsza odpowiedź (w tym zadaniu „tak”).
func _talk(dl, topic: String) -> Array:
	var answers := []
	dl.select_topic(topic)
	var guard := 0
	while dl.in_choice and guard < 8:
		var c: Array = dl.choices[0]
		answers.append(int(c[1]))
		dl.answer(int(c[1]))
		guard += 1
	return answers

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(20)
	var dl = main.dialogue
	var inv = main.interaction.inventory
	var caius: Node = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == "caius cosades":
				caius = n
	_step("Caius w komórce", caius != null and dl.available(), {"cell": main.interior})
	if caius == null:
		_save()
		return
	# stan po rozmowie z kapitanem w Seyda Neen (wynik „duties”): wpis A1_1 = 1, paczka, temat
	dl.add_entry("a1_1_findspymaster", 1)
	inv.add("player", {}, "bk_a1_1_caiuspackage", 1)
	dl.add_topic("report to caius cosades")
	var gold0: int = inv.count_of("player", {}, "gold_001")
	var ok_greet: bool = dl.start(caius)
	_step("powitanie", ok_greet and dl.history.size() > 0, {"talked_before": dl.talked, "topics": dl.available_topics().size()})
	var a1 := _talk(dl, "report to caius cosades")
	var j1 := int(main.state.journal.get("a1_1_findspymaster", 0))
	_step("raport u Caiusa (pytania, oddanie paczki)", j1 >= 14 and inv.count_of("player", {}, "bk_a1_1_caiuspackage") == 0,
		{"answers": a1, "a1_1_findspymaster": j1, "blades": dl.in_faction("blades"), "blades_rank": dl.player_rank("blades")})
	var a2 := _talk(dl, "orders")
	var j2 := int(main.state.journal.get("a1_1_findspymaster", 0))
	var gold1: int = inv.count_of("player", {}, "gold_001")
	_step("rozkazy: złoto i koniec zadania", j2 == 18 and gold1 - gold0 == 200, {"answers": a2, "a1_1_findspymaster": j2, "gold": gold1 - gold0})
	var a3 := _talk(dl, "orders")
	var j3 := int(main.state.journal.get("a1_2_antabolisinformant", 0))
	_step("nowe zadanie A1_2", j3 == 1, {"answers": a3, "a1_2_antabolisinformant": j3, "journal_entries": dl.quests_view().size()})
	dl.end()
	if main.dialogue_window != null and main.dialogue_window.visible:
		main.dialogue_window.close(true)
	await _frames(3)
	var path := ProjectSettings.globalize_path("user://stage6/odbior.mwsave")
	var e: String = main.save_game(path)
	main.state.journal.erase("a1_2_antabolisinformant")
	var lw: Array = main.load_game(path)
	await _frames(10)
	_step("zapis i odczyt", e == "" and int(main.state.journal.get("a1_2_antabolisinformant", 0)) == 1 and int(main.state.journal.get("a1_1_findspymaster", 0)) == 18
		and dl.in_faction("blades"), {"warnings": lw.size()})
	_save()

func _save() -> void:
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	quit(0)
