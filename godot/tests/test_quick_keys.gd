extends SceneTree
## Etap 10: szybkie klawisze (QuickKeysMenu, QuickKeysMenuAssign, MagicSelectionDialog, activateQuickKey) jak
## OpenMW 0.51 – układ okien, przypisanie przedmiotu / przedmiotu magicznego / czaru, usunięcie, pole 10 (walka
## wręcz), działanie klawiszy (użycie, dobycie broni, wybór magii), brak przedmiotu (sQuickMenu5), zastępstwo
## (findReplacement), odroczenie w trakcie ataku, blokady (tryb GUI, tworzenie postaci, wilkołak), zapis i odczyt.
## godot --headless --path godot -s res://tests/test_quick_keys.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

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

func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	main.scripts.set_global("chargenstate", -1.0)
	var qk = main.quick_keys
	var inv = main.interaction.inventory
	var st: Dictionary = main.player_stats()
	var T := func(gm: String, fb: String) -> String: return main.dialogue.gmst_text(gm, fb)
	var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	check(qk != null, "QuickKeysMenu utworzone")
	inv.add("player", {}, "synth_potion", 3)
	inv.add("player", {}, "synth_sword", 1)
	inv.add("player", {}, "synth_ring", 1)
	inv.add("player", {}, "misc_synth_spoon", 1)
	var spells: Array = st.get("spells", [])
	if not "synth_bolt" in spells:
		spells.append("synth_bolt")
	st["spells"] = spells
	# 1. F1 – tryb GM_QuickKeysMenu, układ okna
	_press("quick_keys_menu")
	await _frames(2)
	check(qk.is_open() and main.gui.get_mode() == "quickkeys" and main.get_tree().paused, "F1: okno szybkich klawiszy (tryb GUI, pauza)")
	var w: Control = qk.win
	var th: float = qk.ui.wrapped_height(qk.instruction.text, 354)
	var dh := roundf(th) - 18.0
	check(is_equal_approx(w.size.x, 380 * s) and is_equal_approx(w.size.y, (224 + dh) * s),
		"okno 380 × (224 + przyrost instrukcji %.0f): %s" % [dh, w.size])
	var vp: Vector2 = w.get_viewport_rect().size
	check(absf(w.position.x - floorf((vp.x - w.size.x) / 2.0)) <= 1.0, "okno wyśrodkowane (center)")
	check(qk.buttons.size() == 10 and is_equal_approx(qk.buttons[6].position.x, 68 * s) and is_equal_approx(qk.buttons[6].position.y, 68 * s)
		and is_equal_approx(qk.buttons[0].size.x, 60 * s), "10 pól 60 × 60 co 68 px (2 × 5)")
	var num: Label = qk.buttons[2].get_node_or_null("Number")
	check(num != null and num.text == "3", "pole nieprzypisane – numer")
	check(qk.buttons[9].get_node_or_null("Item") != null and qk.key_data(9).type == "hand_to_hand", "pole 10 – walka wręcz")
	check(is_equal_approx(qk.ok_button.position.x + qk.ok_button.size.x, 362 * s), "OK przy prawej krawędzi (ExpandDirection Left)")
	# 2. pole 10 nie otwiera okna przypisania; pole 1 – QuickKeysMenuAssign
	qk._on_key_clicked(9)
	check(qk.assign_win == null, "pole 10 bez okna przypisania")
	qk._on_key_clicked(0)
	check(qk.assign_win != null and is_instance_valid(qk.assign_win), "okno przypisania")
	var aw: Control = qk.assign_win
	check(is_equal_approx(aw.size.y, 154 * s) and aw.find_child("ItemButton", true, false) != null
		and aw.find_child("MagicButton", true, false) != null and aw.find_child("UnassignButton", true, false) != null,
		"QuickKeysMenuAssign: 154 px, przyciski przedmiot/magia/usuń/anuluj")
	var ib: Button = aw.find_child("ItemButton", true, false)
	var lab: Label = aw.find_child("Label", true, false)
	check(absf((ib.position.x + ib.size.x / 2.0) - (lab.position.x + lab.size.x / 2.0)) <= 1.0 * s, "przyciski wyśrodkowane pod napisem")
	# Esc – najpierw okno modalne
	main.gui.exit_current()
	check(qk.assign_win == null and qk.is_open(), "Esc zamyka okno przypisania, menu zostaje")
	# 3. przypisanie przedmiotu: ItemSelectionDialog (sQuickMenu6), tylko rzeczy do użycia
	qk._on_key_clicked(0)
	qk.assign_item_clicked()
	check(qk.selection.is_open(), "okno wyboru przedmiotu")
	var ids: Array = qk.selection.entries.map(func(e): return String(e.id))
	check("synth_potion" in ids and "synth_sword" in ids and "synth_ring" in ids and not "misc_synth_spoon" in ids,
		"Filter_OnlyUsableItems: mikstura, broń, pierścień – bez łyżki (%s)" % [ids])
	qk.selection.select("synth_potion")
	check(not qk.selection.is_open() and qk.key_data(0).type == "item" and qk.key_data(0).id == "synth_potion", "pole 1: mikstura")
	check(qk.buttons[0].get_node_or_null("Item") != null and qk.buttons[0].get_node_or_null("Number") == null, "pole 1: ikona zamiast numeru")
	qk._on_key_clicked(1)
	qk.assign_item_clicked()
	qk.selection.select("synth_sword")
	# 4. przedmiot magiczny i czar: MagicSelectionDialog
	qk._on_key_clicked(2)
	qk.assign_magic_clicked()
	check(qk.magic_win != null and is_equal_approx(qk.magic_win.size.x, 330 * s) and is_equal_approx(qk.magic_win.size.y, 370 * s),
		"MagicSelectionDialog 330 × 370")
	var kinds: Array = qk.magic_rows.map(func(r): return "%s:%s" % [r[0], r[1]])
	check("spell:synth_bolt" in kinds and "item:synth_ring" in kinds, "lista: czar i przedmiot magiczny (%s)" % [kinds])
	qk.magic_selected("item", "synth_ring")
	check(qk.magic_win == null and qk.key_data(2).type == "magic_item", "pole 3: przedmiot magiczny")
	qk._on_key_clicked(3)
	qk.assign_magic_clicked()
	qk.magic_selected("spell", "synth_bolt")
	check(qk.key_data(3).type == "magic" and qk.key_data(3).id == "synth_bolt" and qk.buttons[3].get_node_or_null("Frame") != null,
		"pole 4: czar z ramką menu_icon_select_magic")
	# usunięcie
	qk._on_key_clicked(4)
	qk.assign_item_clicked()
	qk.selection.select("synth_potion")
	qk._on_key_clicked(4)
	qk.unassign_clicked()
	check(qk.key_data(4).type == "unassigned" and qk.buttons[4].get_node_or_null("Number") != null, "usunięcie przypisania (sQuickMenu4)")
	# 5. klawisze nie działają w trybie GUI; OK zamyka
	qk.quick_key(1)
	check(inv.count_of("player", {}, "synth_potion") == 3, "w trybie GUI klawisz nic nie robi")
	qk.ok_button.pressed.emit()
	await _frames(1)
	check(not qk.is_open() and not main.gui.is_gui_mode(), "OK – koniec trybu")
	# 6. działanie: mikstura (useItem – wypicie), broń (założenie i dobycie), przedmiot magiczny, czar, walka wręcz
	qk.quick_key(1)
	check(inv.count_of("player", {}, "synth_potion") == 2, "klawisz 1: wypita mikstura (%d)" % inv.count_of("player", {}, "synth_potion"))
	main.weapon_drawn = false
	qk.quick_key(2)
	check(main.equipped_slot_of("synth_sword") == 16 and main.weapon_drawn and not main.magic_ready, "klawisz 2: miecz w prawej ręce, broń dobyta")
	qk.quick_key(3)
	check(main.equipped_slot_of("synth_ring") >= 0 and main.selected_magic() == {"kind": "item", "id": "synth_ring"} and main.magic_ready,
		"klawisz 3: pierścień założony, wybrany jako magia, magia przygotowana (%s)" % [main.selected_magic()])
	qk.quick_key(4)
	check(main.selected_magic() == {"kind": "spell", "id": "synth_bolt"} and main.magic_ready, "klawisz 4: czar wybrany")
	qk.quick_key(10)
	check(main.equipped_slot_of("synth_sword") < 0 and main.weapon_drawn, "klawisz 0: walka wręcz – miecz zdjęty, pięści")
	qk.quick_key(5)
	check(true, "nieprzypisany klawisz – bez błędu")
	# 7. brak przedmiotu: sQuickMenu5 + nazwa; zastępstwo stanu (findReplacement – najmniejszy stan)
	inv.remove("player", {}, "synth_sword", 1)
	main._check_equipment()
	qk.quick_key(2)
	check(qk.history.back()[0] == "missing", "brak miecza – komunikat sQuickMenu5 (%s)" % [qk.history.back()])
	inv.add("player", {}, "synth_sword#c:40", 1)
	inv.add("player", {}, "synth_sword#c:10", 1)
	check(qk.find_replacement("synth_sword") == "synth_sword#c:10", "findReplacement: stos o najmniejszym stanie")
	qk.quick_key(2)
	check(qk.key_data(1).id == "synth_sword#c:10" and main.equipped_slot_of("synth_sword#c:10") == 16, "zastępstwo założone")
	# 8. odroczenie w trakcie ataku (isAttackingOrSpell) – wykonanie po zakończeniu
	main._attack_hold = 0.1
	qk.quick_key(10)
	check(qk.activated == 9 and main.equipped_slot_of("synth_sword#c:10") == 16, "w trakcie ataku – odroczone")
	main._attack_hold = -1.0
	await _frames(2)
	check(qk.activated == -1 and main.equipped_slot_of("synth_sword#c:10") < 0, "po ataku – wykonane (updateActivatedQuickKey)")
	# 9. blokady: tworzenie postaci, wilkołak
	main.scripts.set_global("chargenstate", 1.0)
	var n0: int = inv.count_of("player", {}, "synth_potion")
	qk.quick_key(1)
	check(inv.count_of("player", {}, "synth_potion") == n0, "w trakcie tworzenia postaci – nic")
	main.scripts.set_global("chargenstate", -1.0)
	st["werewolf"] = true
	qk.quick_key(1)
	qk.toggle()
	check(inv.count_of("player", {}, "synth_potion") == n0 and not qk.is_open(), "wilkołak – bez klawiszy i menu (sWerewolfRefusal)")
	st["werewolf"] = false
	# 10. zapis i odczyt (REC_KEYS): 9 pól, pole 10 zawsze walka wręcz
	var path := ProjectSettings.globalize_path("user://test_saves/quickkeys.mwsave")
	check(main.save_game(path) == "", "zapis")
	qk._set_key(0, "unassigned", "")
	qk._set_key(3, "unassigned", "")
	var wl: Array = main.load_game(path)
	check(not str(wl).contains("BŁĄD"), "odczyt (%s)" % [wl])
	await _frames(2)
	qk = main.quick_keys
	check(qk.key_data(0).id == "synth_potion" and qk.key_data(3).type == "magic" and qk.key_data(2).type == "magic_item"
		and qk.key_data(9).type == "hand_to_hand" and (main.state.player.quick_keys as Array).size() == 9,
		"po odczycie: przypisania przywrócone (%s)" % [main.state.player.get("quick_keys")])
	# 11. klawisz 1 z klawiatury (akcja quick_key_1)
	var n1: int = inv.count_of("player", {}, "synth_potion")
	_press("quick_key_1")
	await _frames(2)
	check(inv.count_of("player", {}, "synth_potion") == n1 - 1, "klawisz 1 z klawiatury")
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
