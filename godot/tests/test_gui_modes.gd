extends SceneTree
## Etap 10: stos trybów GUI jak WindowManager OpenMW 0.51 (pushGuiMode / popGuiMode / removeGuiMode / containsMode,
## exitCurrentGuiMode): zagnieżdżone tryby wracają do poprzedniego okna zamiast do świata.
##  1. ekwipunek → alchemia → zamknięcie → ekwipunek;  2. ekwipunek → kamień dusz → zaklinanie / ładowanie → ekwipunek;
##  3. rozmowa → handel → rozmowa;  4. rozmowa → trening → rozmowa;  5. rozmowa → podróż (anuluj) → rozmowa;
##  6. ekwipunek → naprawa → ekwipunek;  7. okno z pytaniem nad trybem – po wyborze tryb bez zmian;
##  Esc (exitCurrentGuiMode) na każdym poziomie, pauza i stan „ukrycia” okien pod wierzchnim trybem.
## godot --headless --path godot -s res://tests/test_gui_modes.gd -- --data=WYNIKI(aktorzy) --scripts=0

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
	var g = main.gui
	var inv = main.interaction.inventory
	var mm = main.menu_mode
	check(not g.is_gui_mode() and not main.get_tree().paused, "start: tryb rozgrywki")
	# 1. ekwipunek → alchemia
	inv.add("player", {}, "synth_mortar", 1)
	mm.open()
	check(g.modes() == ["inventory"] and main.get_tree().paused, "GM_Inventory na stosie, pauza")
	mm.use_item("synth_mortar")
	check(g.modes() == ["inventory", "alchemy"] and main.alchemy_window.visible and mm.visible and g.is_suspended(mm),
		"ekwipunek → alchemia: ekwipunek ukryty pod GM_Alchemy (%s)" % [g.modes()])
	main.alchemy_window.close()
	check(g.modes() == ["inventory"] and mm.visible and not g.is_suspended(mm) and main.get_tree().paused,
		"zamknięcie alchemii – powrót do ekwipunku (%s)" % [g.modes()])
	# Esc w alchemii (exitCurrentGuiMode)
	mm.use_item("synth_mortar")
	g.exit_current()
	check(g.modes() == ["inventory"] and not main.alchemy_window.visible, "Esc w alchemii – ekwipunek")
	# 6. ekwipunek → naprawa
	inv.add("player", {}, "synth_repair_hammer", 1)
	mm.use_item("synth_repair_hammer")
	check(g.modes() == ["inventory", "repair"] and main.repair_window.visible, "ekwipunek → naprawa (%s)" % [g.modes()])
	g.exit_current()
	check(g.modes() == ["inventory"] and not main.repair_window.visible and not g.is_suspended(mm), "Esc w naprawie – ekwipunek")
	# 2. ekwipunek → kamień dusz → pytanie → zaklinanie / ładowanie
	var gem := "misc_soulgem_synth@synth_creature"
	inv.add("player", {}, gem, 2)
	mm.use_item(gem)
	check(main.msgbox != null and g.modes() == ["inventory"], "kamień dusz: pytanie sDoYouWantTo nad ekwipunkiem")
	main.press_message_button(1)
	check(g.modes() == ["inventory", "enchanting"] and main.enchanting_window.visible and main.get_tree().paused,
		"„Make Enchantment” → zaklinanie nad ekwipunkiem (%s)" % [g.modes()])
	main.enchanting_window.close()
	check(g.modes() == ["inventory"] and not g.is_suspended(mm), "zamknięcie zaklinania – ekwipunek")
	mm.use_item(gem)
	main.press_message_button(0)
	check(g.modes() == ["inventory", "recharge"] and main.recharge_window.visible, "„Recharge” → ładowanie nad ekwipunkiem (%s)" % [g.modes()])
	g.exit_current()
	check(g.modes() == ["inventory"], "Esc w ładowaniu – ekwipunek")
	# 7. okno z pytaniem nad trybem: wybór nie zmienia trybu ani pauzy
	main.show_message_box("Pytanie?", ["Tak", "Nie"], Callable(), true)
	main.press_message_button(1)
	check(g.modes() == ["inventory"] and main.get_tree().paused and mm.visible, "okno z pytaniem: po wyborze tryb ekwipunku bez zmian")
	# zamknięcie ekwipunku – tryb rozgrywki
	g.exit_current()
	check(not g.is_gui_mode() and not mm.visible and not main.get_tree().paused, "Esc w ekwipunku – świat, bez pauzy")
	# 3–5. rozmowa i usługi
	var trader := _ref(main, "synth_trader")
	check(trader != null and main.open_dialogue(trader) and g.modes() == ["dialogue"], "GM_Dialogue")
	var tw = main.trade_window
	tw.open("barter")
	check(g.modes() == ["dialogue", "barter"] and g.is_suspended(main.dialogue_window), "rozmowa → handel")
	g.exit_current()
	check(g.modes() == ["dialogue"] and not g.is_suspended(main.dialogue_window) and main.dialogue_window.visible, "Esc w handlu – rozmowa")
	tw.open("training")
	check(g.modes() == ["dialogue", "training"] and main.service_window.visible, "rozmowa → trening (%s)" % [g.modes()])
	main.service_window.close()
	check(g.modes() == ["dialogue"] and not g.is_suspended(main.dialogue_window), "zamknięcie treningu – rozmowa")
	tw.open("travel")
	check(g.modes() == ["dialogue", "travel"], "rozmowa → podróż")
	g.exit_current()
	check(g.modes() == ["dialogue"] and not main.service_window.visible, "anulowanie podróży – rozmowa")
	# pushGuiMode: tryb już na stosie przenoszony na wierzch
	g.push("journal", [main.journal_window])
	g.push("dialogue", [main.dialogue_window])
	check(g.modes() == ["journal", "dialogue"], "tryb obecny na stosie – przeniesiony na wierzch (%s)" % [g.modes()])
	g.remove("journal")
	check(g.modes() == ["dialogue"] and g.contains("dialogue") and not g.contains("journal"), "removeGuiMode ze środka stosu")
	# „Żegnaj” – świat
	main.dialogue_window.close(true)
	check(not g.is_gui_mode() and not main.get_tree().paused, "Żegnaj – tryb rozgrywki")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "history": g.history.slice(-6)}))
	quit(1 if failures.size() > 0 else 0)
