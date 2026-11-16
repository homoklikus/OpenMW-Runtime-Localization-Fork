extends SceneTree
## Etap 9: przejście fragmentu początku Morrowinda na danych z gry – nowa gra ze skryptami CharGen (statek, Seyda
## Neen, urząd celny), potem cele z --goals. Obsługa okien jak gracz: MessageBox – pierwszy przycisk, menu
## tworzenia postaci – wartości domyślne (imię z --name), rozmowa – pytania (pierwsza odpowiedź) i tematy celu,
## podążanie za eskortującym NPC (AiEscort/AiFollow gracza). Dziennik zdarzeń tylko z id i liczbami.
## godot --headless --path godot -s res://tools/stage9_playthrough.gd -- --data=DANE --newgame=morrowind
##     --scripts=1 --seconds=240 --out=wynik.json [--load=zapis] [--save=zapis]

var log_events := []
var t0 := 0
var main

func _init() -> void:
	_run.call_deferred()

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def

func _ev(kind: String, data := {}) -> void:
	var e := {"t": snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), "kind": kind}
	e.merge(data)
	log_events.append(e)
	print("EV ", JSON.stringify(e))

func _escort_leader() -> Node3D:
	for n in main.ai.actor_nodes():
		var p: Dictionary = main.ai.current_package(n)
		if String(p.get("type", "")) in ["escort", "follow"] and String(p.get("target", "player")).to_lower() == "player":
			return n
	return null

func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	var last := {"cell": "", "cgs": -999.0, "journal": {}, "menus": {}, "controls": {}}
	var secs := float(_arg("seconds", "240"))
	var dl = main.dialogue
	var name := _arg("name", "Testowy")
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await process_frame
		# okna
		if main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible:
			_ev("messagebox", {"buttons": main.msgbox.find_children("*", "Button", true, false).size()})
			main.press_message_button(0)
		if main.chargen != null and main.chargen.visible:
			var st: String = main.chargen.step
			if st == "name":
				main.chargen.name_edit.text = name
			_ev("chargen_menu", {"step": st})
			main.chargen._create()
		if main.dialogue_window != null and main.dialogue_window.visible:
			if dl.in_choice and not dl.choices.is_empty():
				_ev("dialogue_choice", {"actor": dl.actor.get("base", ""), "n": int(dl.choices[0][1])})
				dl.answer(int(dl.choices[0][1]))
			else:
				_ev("dialogue_end", {"actor": dl.actor.get("base", ""), "topics": dl.available_topics().size()})
				main.dialogue_window.close(true)
		# podążanie za eskortą
		var lead := _escort_leader()
		if lead != null and main.ai.mw_pos(lead).distance_to(main.ai.mw_pos(main.player)) > 260.0:
			var back := Vector3(sin(lead.rotation.y), 0, cos(lead.rotation.y)) * 1.5
			main.player.global_position = lead.global_position + back + Vector3(0, 0.2, 0)
		# zmiany stanu
		var cell: String = main.interior if not main.interior.is_empty() else "ext:" + str(MWCoords.cell_of(main.player.global_position))
		if cell != last.cell:
			_ev("cell", {"cell": cell})
			last.cell = cell
		var cgs := float(main.state.globals.get("chargenstate", -1))
		if cgs != last.cgs:
			_ev("chargenstate", {"value": cgs})
			last.cgs = cgs
		if JSON.stringify(main.state.journal) != JSON.stringify(last.journal):
			_ev("journal", {"journal": main.state.journal.duplicate()})
			last.journal = main.state.journal.duplicate()
		var menus: Dictionary = main.state.player.get("menus", {})
		if JSON.stringify(menus) != JSON.stringify(last.menus):
			_ev("menus", {"menus": menus.duplicate()})
			last.menus = menus.duplicate()
		var ctl: Dictionary = main.state.player.get("controls", {})
		if JSON.stringify(ctl) != JSON.stringify(last.controls):
			_ev("controls", {"controls": ctl.duplicate()})
			last.controls = ctl.duplicate()
	var rep: Dictionary = main.scripts.report()
	var out := {"events": log_events, "player": {"cell": last.cell, "pos": main.ai.mw_pos(main.player).round(),
		"character": {"name": main.player_stats().get("name", ""), "race": main.player_stats().get("race", ""),
		"class": main.player_stats().get("class", ""), "birthsign": main.player_stats().get("birthsign", "")}},
		"scripts": {"unsupported": rep.get("unsupported"), "errors": rep.get("errors"), "partial": rep.get("partial")}}
	print("END ", JSON.stringify(out.player), " ", JSON.stringify(out.scripts))
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	quit(0)
