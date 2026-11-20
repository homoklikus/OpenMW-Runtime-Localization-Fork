extends SceneTree
## Etap 10: towarzysz (CompanionWindow, CompanionItemModel) jak OpenMW 0.51 – sCompanionShare w rozmowie, gdy
## skrypt aktora ma „companion” ≠ 0; okno towarzysza z ekwipunkiem, przekładanie (okno ilości), pasek obciążenia,
## zysk (minimumprofit ± wartość × liczba, sProfitValue), ostrzeżenie przy ujemnym zysku, brak kradzieży; bez
## powitania – od razu okno towarzysza.
## godot --headless --path godot -s res://tests/test_companion.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

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

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var sc = main.scripts
	sc._scripts["synth_companion_test"] = {"id": "synth_companion_test", "locals": {"companion": "short", "minimumprofit": "long"}, "body": []}
	var npc := _ref(main, "synth_trader")
	check(npc != null, "NPC")
	var rec: Dictionary = main.builder.actors.record("npc", "synth_trader")
	var old_script = rec.get("script", "")
	rec["script"] = "synth_companion_test"
	check(main.open_dialogue(npc), "rozmowa")
	var a: Dictionary = main.dialogue.actor
	var dw = main.dialogue_window
	check(String(a.script) == "synth_companion_test" and not dw._topic_ids.has("#companion"), "companion = 0 – bez sCompanionShare")
	dw.close(true)
	sc.set_local_value(String(a.sid), "companion", 1)
	main.open_dialogue(npc)
	a = main.dialogue.actor
	var idx: int = dw._topic_ids.find("#companion")
	var svc_last := -1
	for i in dw._topic_ids.size():
		if String(dw._topic_ids[i]).begins_with("#svc:"):
			svc_last = i
	check(idx > svc_last and idx >= 0, "sCompanionShare po usługach (updateTopicsPane)")
	var mm = main.menu_mode
	dw._on_topic(idx)
	check(mm.visible and main.gui.modes() == ["dialogue", "companion"] and mm.windows.has("container") and mm.windows.has("inventory"),
		"GM_Companion nad rozmową: okno towarzysza i ekwipunek (%s)" % [main.gui.modes()])
	var cw: Control = mm.windows["container"]
	var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	check(cw.position == Vector2(200, 0) * s and cw.size == Vector2(600, 300) * s, "setCoord(200, 0, 600, 300): %s %s" % [cw.position, cw.size])
	check(cw.find_child("FilterEdit", true, false) != null and cw.find_child("EncumbranceBar", true, false) != null
		and cw.find_child("CloseButton", true, false) != null, "filtr, pasek obciążenia, Close")
	check(mm.comp_profit_label.text.begins_with(main.dialogue.gmst_text("sProfitValue", "Profit:")) and mm.comp_profit_label.text.ends_with(" 0"),
		"sProfitValue 0 (%s)" % mm.comp_profit_label.text)
	# przełożenie od gracza do towarzysza: zysk + wartość × liczba, bez okna ilości przy 1 sztuce
	var inv = main.interaction.inventory
	inv.add("player", {}, "misc_synth_spoon", 3)
	var val: int = main.trade.item_value("misc_synth_spoon")
	var b0: int = main.crime.bounty()
	mm.put_item("misc_synth_spoon", 3)
	check(inv.count_of(a.sid, a.rec, "misc_synth_spoon") >= 3 and mm.companion_profit() == 3 * val, "do towarzysza: zysk +3 × %d (%d)" % [val, mm.companion_profit()])
	# od towarzysza: zysk −, bez kradzieży
	mm.take_item("misc_synth_spoon", 2)
	check(mm.companion_profit() == val and main.crime.bounty() == b0, "od towarzysza: zysk −2 × wartość, bez grzywny")
	var bar: ProgressBar = mm._comp_bar
	check(bar != null and bar.max_value >= 1.0, "pasek obciążenia: udźwig (%s)" % [mm._comp_bar_text.text])
	# filtr nazw
	mm.comp_filter.text = "zzz_nic"
	mm._refresh_container()
	check(mm.cont_ids.is_empty(), "filtr nazw")
	mm.comp_filter.text = ""
	mm._refresh_container()
	# ujemny zysk: ostrzeżenie zamiast zamknięcia; przycisk 1 – zostaje, 0 – zamknięcie i koniec rozmowy
	sc.set_local_value(String(a.sid), "minimumprofit", -10)
	mm.companion_close_clicked()
	check(mm.visible and main.msgbox != null, "zysk < 0: sCompanionWarningMessage")
	main.press_message_button(1)
	check(mm.visible and main.gui.contains("companion"), "„zostań” – okno otwarte")
	main.gui.exit_current()
	check(main.msgbox != null, "Esc też ostrzega")
	main.press_message_button(0)
	await _frames(2)
	check(not mm.visible and not dw.visible and main.gui.modes().is_empty(), "pierwszy przycisk: koniec okna i rozmowy (%s)" % [main.gui.modes()])
	# zysk ≥ 0: Close zamyka, wraca rozmowa
	sc.set_local_value(String(a.sid), "minimumprofit", 0)
	main.open_dialogue(npc)
	mm.open_companion(main.dialogue.actor)
	mm.companion_close_clicked()
	check(not mm.visible and dw.visible and main.gui.modes() == ["dialogue"], "Close – powrót do rozmowy")
	dw.close(true)
	rec["script"] = old_script
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
