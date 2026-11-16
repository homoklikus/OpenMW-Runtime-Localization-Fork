extends SceneTree
## Etap 10 – tryb menu jak OpenMW: cztery okna naraz (statystyki, ekwipunek, magia, mapa) w położeniach domyślnych,
## wygląd Morrowinda (kolory FontColor, czcionka), kategorie i kolejność przedmiotów (SortFilterItemModel),
## siatka kolumnami 42 px, zakładanie przez upuszczenie na postać, upuszczanie na ziemię, podgląd postaci,
## statystyki (paski, atrybuty, umiejętności wg klasy), magia (wybór), zapamiętany układ okien.
## godot --headless --path godot -s res://tests/test_menu_mode.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

const UI := preload("res://scripts/mw/mw_ui.gd")

var failures: Array[String] = []
var checks := 0
var report := {}

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

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	get_root().get_tree().paused = false
	var mm = main.menu_mode
	check(mm != null and not mm.visible, "tryb menu gotowy")
	# kolory i czcionka jak OpenMW
	UI.setup(main.data_dir)
	check(UI.color("normal").is_equal_approx(Color8(202, 165, 96)), "FontColor_color_normal")
	check(UI.color("health").is_equal_approx(Color8(200, 60, 30)), "kolor zdrowia")
	check(UI.theme(1.0).default_font != null and UI.theme(1.0).default_font_size == 16, "czcionka MysticCards 16")
	var inv = main.interaction.inventory
	inv.add("player", {}, "synth_cuirass", 1)
	inv.add("player", {}, "synth_dagger_fire", 1)
	inv.add("player", {}, "synth_potion", 3)
	inv.add("player", {}, "misc_synth_spoon", 2)
	inv.add("player", {}, "synth_ring", 1)
	# otwarcie akcją (prawy przycisk myszy)
	var ev := InputEventAction.new()
	ev.action = "menu_mode"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	if not mm.visible:
		mm.open()
	await _frames(3)
	check(mm.visible and paused, "tryb menu otwarty, gra wstrzymana")
	check(mm.windows.has("stats") and mm.windows.has("inventory") and mm.windows.has("spells"), "okna: statystyki, ekwipunek, magia")
	check(main.map_window.visible and main.map_window.embedded, "mapa jako okno trybu menu")
	var vp: Vector2 = root.get_visible_rect().size
	var inv_w: Control = mm.windows["inventory"]
	check(absf(inv_w.position.x - 0.015 * vp.x) < 2.0 and absf(inv_w.position.y - 0.54 * vp.y) < 2.0, "ekwipunek w położeniu OpenMW (%s)" % inv_w.position)
	# kolejność i kategorie
	var ids: Array = mm.item_ids
	check(ids.has("synth_cuirass") and ids.has("synth_potion") and ids.has("misc_synth_spoon"), "przedmioty w siatce (%d)" % ids.size())
	check(ids.find("synth_dagger_fire") < ids.find("synth_cuirass") and ids.find("synth_cuirass") < ids.find("synth_potion")
		and ids.find("synth_potion") < ids.find("misc_synth_spoon"), "kolejność: broń, zbroja, mikstura, inne")
	mm.set_category("apparel")
	check(mm.item_ids.has("synth_cuirass") and mm.item_ids.has("synth_ring") and not mm.item_ids.has("synth_potion"), "kategoria Ubiór")
	mm.set_category("magic")
	check(mm.item_ids.has("synth_potion") and mm.item_ids.has("synth_dagger_fire") and mm.item_ids.has("synth_ring") and not mm.item_ids.has("synth_cuirass"),
		"kategoria Magia: mikstury i zaklęte przedmioty")
	mm.set_category("all")
	await _frames(2)
	# siatka kolumnami
	var cells: Array = mm._grid.get_children().filter(func(c): return not c.is_queued_for_deletion())
	var rows := maxi(1, int((mm._grid.get_parent() as Control).size.y / (42.0 * mm.scale_ui)))
	if cells.size() > rows:
		check(is_equal_approx(cells[rows].position.y, 0.0) and cells[rows].position.x > 0.0, "druga kolumna od góry (ItemView)")
	else:
		check(cells.size() > 0 and is_equal_approx(cells[0].position.x, 0.0), "pierwsza kolumna")
	report["rows"] = rows
	check(String(cells[0].tooltip_text).length() > 0 and mm.item_tooltip("synth_cuirass").contains("\n"), "podpowiedź przedmiotu")
	# zakładanie przez upuszczenie na postać
	var avatar: Control = inv_w.find_child("Avatar", true, false)
	check(avatar != null and avatar._can_drop_data(Vector2.ZERO, {"mw_item": "synth_cuirass"}), "postać przyjmuje przedmiot")
	avatar._drop_data(Vector2.ZERO, {"mw_item": "synth_cuirass"})
	await _frames(2)
	check(main.equipped_slot_of("synth_cuirass") >= 0, "napierśnik założony po upuszczeniu na postać")
	check(mm.item_ids[0] == "synth_cuirass", "założone przedmioty na początku")
	report["doll"] = mm._doll != null
	check(mm._doll_vp != null, "podgląd postaci (SubViewport)")
	check(mm._armor_label.text.contains(":") and mm._enc_label.text.contains("/"), "pancerz i obciążenie")
	# upuszczenie na ziemię (tło)
	var n0: int = inv.count_of("player", {}, "misc_synth_spoon")
	mm._root._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon"})
	check(inv.count_of("player", {}, "misc_synth_spoon") == 0 and n0 == 2, "upuszczenie poza okna – na ziemię")
	# statystyki
	var labels: Array = mm._stat_left.find_children("*", "Label", true, false)
	var texts := labels.map(func(l): return String(l.text))
	check(mm._stat_bars.has("health") and mm._stat_bars.has("magic") and mm._stat_bars.has("fatigue"), "paski zdrowia, magii, kondycji")
	var st: Dictionary = main.player_stats()
	check(texts.has(str(int(st.get("level", 1)))), "poziom w statystykach")
	var rtexts: Array = mm._stat_right.find_children("*", "Label", true, false).map(func(l): return String(l.text))
	var heads := 0
	for t in rtexts:
		if t in ["Umiejętności główne", "Umiejętności poboczne", "Pozostałe umiejętności"] or t.begins_with("Major") or t.begins_with("Minor") or t.begins_with("Misc"):
			heads += 1
	check(heads >= 3 or rtexts.size() > 27, "umiejętności w grupach wg klasy (%d)" % rtexts.size())
	# magia
	var spells_n: int = mm.spell_rows.size()
	report["spell_rows"] = spells_n
	if spells_n > 0:
		var r0: Array = mm.spell_rows[0]
		mm.select_spell(String(r0[0]), String(r0[1]))
		check(main.selected_magic().get("id") == r0[1], "wybór magii z listy")
	# przesunięcie okna i zapamiętanie układu
	inv_w.position = Vector2(100, 120)
	mm.close()
	await _frames(2)
	check(not mm.visible and not paused and not main.map_window.visible, "zamknięcie trybu menu (z mapą)")
	var saved: Array = main.state.player.get("ui_windows", {}).get("inventory", [])
	check(saved.size() == 4 and absf(float(saved[0]) * vp.x - 100.0) < 1.0, "układ okien zapamiętany")
	mm.open()
	await _frames(2)
	check(absf((mm.windows["inventory"] as Control).position.x - 100.0) < 1.5, "okno w zapamiętanym miejscu")
	mm.close()
	report["checks"] = checks
	print("RESULT ", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
