extends SceneTree
## Etap 10: notatki na mapie jak OpenMW 0.51 (MapWindow::onMapDoubleClicked / onCustomMarkerDoubleClicked,
## EditNoteDialog, CustomMarkerCollection, LocalMapBase::updateCustomMarkers, ToolTipInfo::notes): dwuklik na mapie
## lokalnej – nowa notatka, układ okna, OK/Cancel/Esc, edycja i usuwanie z potwierdzeniem, położenie znacznika,
## podpowiedzi (TextToolTipOneLine, notatki celu drzwi i komórki mapy świata), minimapa HUD, wnętrze, zapis i odczyt.
## godot --headless --path godot -s res://tests/test_map_notes.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

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

func _dbl(c: Control, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = true
	e.position = pos
	c.gui_input.emit(e)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	var cm = main.custom_markers
	var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	check(cm != null and cm.size() == 0, "kolekcja znaczników pusta")
	var mwin = main.map_window
	mwin.open()
	await _frames(3)
	check(mwin.visible and not mwin.world_mode, "okno mapy – mapa lokalna")
	# 1. dwuklik – nowa notatka
	var click: Vector2 = mwin._center + Vector2(40, -25) * s
	_dbl(mwin._view, click)
	await _frames(1)
	var dlg = main.get_edit_note_dialog()
	check(dlg.is_open() and not dlg.delete_button_shown() and not dlg.delete_button.visible, "dwuklik: okno notatki bez przycisku usuwania")
	check(dlg.get_text() == "" and dlg.text_edit.has_focus(), "pusty tekst, fokus w polu")
	var vp: Vector2 = dlg.get_viewport().get_visible_rect().size
	check(dlg.win.size.is_equal_approx(Vector2(336, 242) * s) and dlg.win.position.is_equal_approx(((vp - dlg.win.size) / 2.0).floor()), "okno 336 × 242 na środku")
	check(dlg.text_edit.position.is_equal_approx(Vector2(13, 38) * s) and dlg.text_edit.size.is_equal_approx(Vector2(303, 150) * s), "pole tekstu 13, 38, 303 × 150")
	check(dlg.text_edit.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY, "zawijanie wierszy")
	check(dlg.win.find_child("Caption", true, false).text == "Edit Note", "napis sEditNote")
	check(dlg.ok_button.text == "OK" and dlg.cancel_button.text == "Cancel", "przyciski OK/Cancel")
	check(dlg.layer > mwin.layer, "okno modalne nad mapą")
	dlg.text_edit.text = "First line of the note\nsecond"
	dlg.ok_button.pressed.emit()
	await _frames(1)
	check(not dlg.is_open() and cm.size() == 1, "OK: znacznik dodany, okno zamknięte")
	var mk: Dictionary = cm.all()[0]
	var w: Vector3 = mwin.view_to_world(click)
	var g := MWCoords.cell_of(w)
	check(String(mk.cell) == "ext:%d,%d" % [g.x, g.y], "komórka klikniętego miejsca (%s)" % mk.cell)
	var mwp := MWCoords.godot_to_mw(w)
	check(absf(float(mk.x) - mwp.x) < 0.5 and absf(float(mk.y) - mwp.y) < 0.5, "położenie w świecie (jednostki MW)")
	check(String(mk.note) == "First line of the note\nsecond", "treść notatki")
	check(mwin.world_to_view(float(mk.x), float(mk.y)).distance_to(click) < 0.5, "świat → widok = kliknięte miejsce")
	check(mwin.custom_marker_nodes.size() == 1, "znacznik na mapie lokalnej")
	var node: Control = mwin.custom_marker_nodes[0]
	check(node.size.is_equal_approx(Vector2(16, 16) * s) and (node.position + node.size / 2.0).distance_to(click) <= 1.0, "znacznik 16 × 16 w klikniętym miejscu")
	check(node.modulate.is_equal_approx(Color(0.6, 0.6, 0.6)), "kolor 0,6 (normalny)")
	node.mouse_entered.emit()
	check(node.modulate.is_equal_approx(Color(1, 1, 1)), "kolor 1,0 pod kursorem")
	node.mouse_exited.emit()
	var tip: Dictionary = node.get_meta("mw_tip")
	check(String(tip.get("layout", "")) == "text_one_line" and String(tip.description) == String(mk.note), "podpowiedź TextToolTipOneLine z notatką")
	var tsz: Vector2 = main.tooltips.create_tooltip(tip)
	check(tsz.x > 0 and tsz.y > 0, "podpowiedź notatki zbudowana")
	# 2. Cancel i Esc – bez zmian
	_dbl(mwin._view, click + Vector2(60, 0) * s)
	await _frames(1)
	dlg.text_edit.text = "discarded"
	dlg.cancel_button.pressed.emit()
	check(not dlg.is_open() and cm.size() == 1, "Cancel: bez nowego znacznika")
	_dbl(mwin._view, click + Vector2(60, 0) * s)
	await _frames(1)
	_key(KEY_ESCAPE)
	await _frames(2)
	check(not dlg.is_open() and cm.size() == 1 and mwin.visible, "Esc zamyka okno notatki, mapa zostaje")
	# 3. dwuklik na znaczniku – edycja
	node = mwin.custom_marker_nodes[0]
	_dbl(node, Vector2(4, 4))
	await _frames(1)
	check(dlg.is_open() and dlg.delete_button_shown() and dlg.delete_button.visible and dlg.get_text() == String(mk.note), "dwuklik na znaczniku: edycja z przyciskiem usuwania")
	check(dlg.delete_button.text == "Delete", "przycisk sDelete")
	dlg.text_edit.text = "Edited"
	dlg.ok_button.pressed.emit()
	await _frames(1)
	check(cm.size() == 1 and String(cm.all()[0].note) == "Edited", "OK: notatka zmieniona (updateMarker)")
	check(mwin.custom_marker_nodes.size() == 1 and String(mwin.custom_marker_nodes[0].get_meta("mw_tip").description) == "Edited", "znacznik odświeżony")
	# 4. usuwanie z potwierdzeniem
	_dbl(mwin.custom_marker_nodes[0], Vector2(4, 4))
	await _frames(1)
	dlg.delete_button.pressed.emit()
	await _frames(2)
	check(main.confirm.is_open() and main.confirm.text() == "Delete Note?" and main.confirm.layer > dlg.layer, "usuwanie: potwierdzenie sDeleteNote nad oknem")
	main.confirm.press(false)
	await _frames(1)
	check(dlg.is_open() and cm.size() == 1, "anulowanie potwierdzenia – notatka zostaje, okno otwarte")
	dlg.delete_button.pressed.emit()
	await _frames(2)
	main.confirm.press(true)
	await _frames(1)
	check(cm.size() == 0 and not dlg.is_open() and mwin.custom_marker_nodes.is_empty(), "potwierdzenie: znacznik usunięty, okno zamknięte")
	# 5. podpowiedź z notatkami (znacznik drzwi / komórka mapy świata)
	var long := "This is a rather long note that certainly exceeds sixty characters in total"
	main.tooltips.create_tooltip({"type": "info", "text": "Seyda", "notes": [long, "a\nb", "short"]})
	var labels: Array = main.tooltips.box.find_children("ToolTipNote*", "Label", true, false)
	var texts: Array = labels.map(func(l): return l.text)
	check(texts.size() == 3, "trzy wiersze notatek (%d)" % texts.size())
	if texts.size() == 3:
		check(texts[0] == long.substr(0, 60) + " ...", "długa notatka skrócona do 60 znaków")
		check(texts[1] == "a ...", "notatka do pierwszego wiersza")
		check(texts[2] == "short", "krótka notatka bez zmian")
	var icons: Array = main.tooltips.box.find_children("ToolTipNoteIcon*", "", true, false)
	check(icons.size() == 3 and (icons[0] as Control).modulate.is_equal_approx(Color(1.0, 0.3, 0.3)), "ikony notatek (1; 0,3; 0,3)")
	cm.add(cm.make("int:synthville, test house", 10.0, 20.0, "inside"))
	check(mwin.notes_for_dest({"cell_name": "Synthville, Test House"}) == ["inside"], "notatki komórki docelowej drzwi")
	cm.add(cm.make("ext:0,0", 100.0, 100.0, "ext note"))
	check(mwin.notes_for_dest({"cell_key": "", "cell_name": "", "transform": Transform3D(Basis(), MWCoords.mw_to_godot(Vector3(4000, 4000, 0)))}) == ["ext note"], "notatki komórki zewnętrznej celu")
	mwin.set_world(true)
	await _frames(2)
	var found := false
	for c in mwin._world_rect.get_children():
		if c.has_meta("mw_tip") and (c.get_meta("mw_tip") as Dictionary).get("notes", []) == ["ext note"]:
			found = true
	check(found, "mapa świata: notatki w podpowiedzi znacznika komórki")
	mwin.set_world(false)
	mwin.close()
	await _frames(2)
	# 6. minimapa HUD
	cm.clear()
	var pg := MWCoords.cell_of(main.player.global_position)
	var pm := MWCoords.godot_to_mw(main.player.global_position)
	cm.add(cm.make("ext:%d,%d" % [pg.x, pg.y], pm.x + 300.0, pm.y, "near"))
	cm.add(cm.make("ext:%d,%d" % [pg.x + 5, pg.y], pm.x + 5 * 8192.0, pm.y, "far"))
	if main.mw_hud != null:
		main.mw_hud.update_minimap()
		check(main.mw_hud.minimap_markers.size() == 1, "minimapa: znacznik komórki siatki (bez dalekiej)")
	# 7. zapis i odczyt
	var path := "user://test_map_notes.sav"
	check(main.save_game(path) == "", "zapis")
	cm.clear()
	check(cm.size() == 0, "po wyczyszczeniu brak znaczników")
	main.load_game(path)
	await _frames(5)
	check(cm.size() == 2 and String(cm.all()[0].note) == "near", "odczyt: znaczniki z zapisu (%d)" % cm.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 8. wnętrze: komórka „int:nazwa”
	main.center_on_cell("Synthville, Test House")
	await _frames(30)
	mwin.open()
	await _frames(3)
	_dbl(mwin._view, mwin._center + Vector2(10, 10) * s)
	await _frames(1)
	dlg.text_edit.text = "room"
	dlg.ok_button.pressed.emit()
	await _frames(1)
	check(cm.in_cell("int:synthville, test house").size() == 1, "wnętrze: znacznik w komórce wnętrza")
	check(mwin.custom_marker_nodes.size() == 1, "wnętrze: znacznik na mapie")
	mwin.close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
