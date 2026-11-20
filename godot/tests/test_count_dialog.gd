extends SceneTree
## Etap 10: okno ilości (CountDialog, openmw_count_window.layout) – podział stosu przy przekładaniu do pojemnika
## i z pojemnika, upuszczaniu w świat i handlu; Shift (cały stos), Ctrl (1 sztuka), Alt (przełożenie),
## pole liczby (NumericEditBox: zakres, strzałki), suwak (pozycja = liczba − 1), Enter/Esc, okno modalne,
## stan przedmiotu (wytrzymałość, dusza) zachowany po podziale.
## godot --headless --path godot -s res://tests/test_count_dialog.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

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

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var it = main.interaction
	var inv = it.inventory
	var mm = main.menu_mode
	var chest := _ref(main, "synth_chest")
	check(chest != null, "skrzynia wczytana")
	if chest == null:
		_finish()
		return
	var csid := String(chest.get_meta("mw_sid"))
	var crec: Dictionary = it.container_record("synth_chest")
	var T := func(gm: String, fb: String) -> String: return main.dialogue.gmst_text(gm, fb)
	inv.add(csid, crec, "misc_synth_spoon", 5 - inv.count_of(csid, crec, "misc_synth_spoon"))
	var p0: int = inv.count_of("player", {}, "misc_synth_spoon")
	check(main.activate(chest) and mm.visible and mm.windows.has("container"), "okno pojemnika")
	var inv_gp: Control = mm.windows["inventory"].find_child("GridPanel", true, false)
	var cont_gp: Control = mm.windows["container"].find_child("GridPanel", true, false)
	# 1. stos 5 z pojemnika do ekwipunku – okno ilości (sTake), domyślnie cały stos
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "container"})
	var cd = main.count_dialog
	check(cd != null and cd.is_open(), "stos > 1: okno ilości otwarte")
	if cd == null or not cd.is_open():
		_finish()
		return
	await _frames(1)
	var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	var spoon_name: String = it.item_name("misc", "misc_synth_spoon", inv.item("misc_synth_spoon").rec)
	check(cd.label_text.text == T.call("sTake", "Take") and cd.item_text.text == spoon_name,
		"komunikat sTake i nazwa przedmiotu (%s / %s)" % [cd.label_text.text, cd.item_text.text])
	check(cd.max_count == 5 and cd.value() == 5 and cd.item_edit.text == "5" and int(cd.slider.value) == 4
		and int(cd.slider.max_value) == 5, "domyślnie cały stos: pole 5, suwak 4 z zakresu 5")
	check(inv.count_of("player", {}, "misc_synth_spoon") == p0, "przed OK nic nie przeniesiono")
	# układ: 128 wysokości, szerokość max(nazwa + 160, 320), środek ekranu, pole liczby przy prawej (485 z 592)
	var vp: Vector2 = cd.get_viewport().get_visible_rect().size
	var font: Font = preload("res://scripts/mw/mw_ui.gd").font()
	var want_w: float = roundf(maxf(ceilf(font.get_string_size(spoon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * s)).x) + 160.0 * s, 320.0 * s))
	check(is_equal_approx(cd._win.size.x, want_w) and is_equal_approx(cd._win.size.y, roundf(128 * s)),
		"rozmiar okna %s (oczekiwano %.0f × %.0f)" % [cd._win.size, want_w, roundf(128 * s)])
	check(absf(cd._win.position.x + cd._win.size.x / 2.0 - vp.x / 2.0) <= 1.0 and absf(cd._win.position.y + cd._win.size.y / 2.0 - vp.y / 2.0) <= 1.0,
		"okno na środku ekranu")
	var cw: float = cd._win.size.x - 8 * s
	check(is_equal_approx(cd.item_edit.position.x, cw - 107 * s) and is_equal_approx(cd.slider.size.x, cw - 14 * s)
		and is_equal_approx(cd.slider.position.y, 67 * s), "pole liczby i suwak wg układu (Right Top, HStretch)")
	check(cd.item_edit.has_focus(), "fokus klawiatury w polu liczby (setKeyFocusWidget)")
	# pole liczby ↔ suwak, zakres 1…max, niepoprawny tekst – poprzednia wartość
	cd.item_edit.text = "3"
	cd._on_edit_changed("3")
	check(cd.value() == 3 and int(cd.slider.value) == 2, "wpisanie 3 – suwak na 2")
	cd.item_edit.text = "99"
	cd._on_edit_changed("99")
	check(cd.value() == 5 and cd.item_edit.text == "5", "99 przycięte do 5")
	cd.item_edit.text = "0"
	cd._on_edit_changed("0")
	check(cd.value() == 1 and cd.item_edit.text == "1", "0 przycięte do 1")
	cd.item_edit.text = "x"
	cd._on_edit_changed("x")
	check(cd.value() == 1 and cd.item_edit.text == "1", "tekst nieliczbowy – poprzednia wartość")
	cd.slider.value = 3
	check(cd.value() == 4 and cd.item_edit.text == "4", "suwak 3 – pole 4 (onSliderMoved)")
	_key(KEY_UP)
	await _frames(2)
	check(cd.value() == 5, "strzałka w górę +1 (%d)" % cd.value())
	_key(KEY_DOWN)
	_key(KEY_DOWN)
	await _frames(2)
	check(cd.value() == 3 and int(cd.slider.value) == 2, "strzałka w dół −1 (%d)" % cd.value())
	cd.press_ok()
	check(not cd.is_open() and inv.count_of("player", {}, "misc_synth_spoon") == p0 + 3 and inv.count_of(csid, crec, "misc_synth_spoon") == 2,
		"OK: przeniesiono 3, w skrzyni 2 (%d, %d)" % [inv.count_of("player", {}, "misc_synth_spoon"), inv.count_of(csid, crec, "misc_synth_spoon")])
	# 2. Cancel – nic; Esc – nic i okno pojemnika zostaje (okno modalne przejmuje klawisz)
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "container"})
	check(cd.is_open() and cd.max_count == 2, "drugi raz: stos 2")
	cd.press_cancel()
	check(not cd.is_open() and inv.count_of(csid, crec, "misc_synth_spoon") == 2, "Cancel – bez zmian")
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "container"})
	_key(KEY_ESCAPE)
	await _frames(2)
	check(not cd.is_open() and mm.visible and inv.count_of(csid, crec, "misc_synth_spoon") == 2,
		"Esc zamyka tylko okno ilości (pojemnik otwarty, bez zmian)")
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "container"})
	_key(KEY_ENTER)
	await _frames(2)
	check(not cd.is_open() and inv.count_of(csid, crec, "misc_synth_spoon") == 0, "Enter = OK (cały stos)")
	# 3. Ctrl – 1 sztuka bez okna, Shift – cały stos bez okna
	cont_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "inventory", "ctrl": true})
	check(not cd.is_open() and inv.count_of(csid, crec, "misc_synth_spoon") == 1, "Ctrl: 1 sztuka bez okna ilości")
	var pn: int = inv.count_of("player", {}, "misc_synth_spoon")
	cont_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "inventory", "shift": true})
	check(not cd.is_open() and inv.count_of(csid, crec, "misc_synth_spoon") == 1 + pn and inv.count_of("player", {}, "misc_synth_spoon") == 0,
		"Shift: cały stos bez okna ilości")
	# 4. Alt + kliknięcie (transferItem) i dwuklik – przełożenie z oknem ilości; pojedyncza sztuka – bez okna
	mm.click_item("misc_synth_spoon", "container", {"alt": true})
	check(cd.is_open() and cd.label_text.text == T.call("sTake", "Take"), "Alt + kliknięcie: okno ilości")
	cd.set_count(2)
	cd.press_ok()
	check(inv.count_of("player", {}, "misc_synth_spoon") == 2, "Alt: przełożono 2")
	mm.click_item("misc_synth_spoon", "container", {})
	check(not cd.is_open() and inv.count_of("player", {}, "misc_synth_spoon") == 2, "kliknięcie bez Alt nie przekłada")
	inv.add(csid, crec, "synth_helm", 1)
	mm.activate_item("synth_helm", "container")
	check(not cd.is_open() and inv.count_of("player", {}, "synth_helm") >= 1, "pojedyncza sztuka – bez okna ilości")
	# 5. stan przedmiotu: stos „synth_sword#c:50” × 3 dzielony 2 + 1 – oba stosy z tym samym stanem
	var worn_id := "synth_sword#c:50"
	inv.add(csid, crec, worn_id, 3)
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": worn_id, "source": "container"})
	check(cd.is_open() and cd.max_count == 3, "stos uszkodzonej broni: okno ilości (3)")
	cd.set_count(2)
	cd.press_ok()
	check(inv.count_of("player", {}, worn_id) == 2 and inv.count_of(csid, crec, worn_id) == 1
		and inv.item_charge(worn_id) == 50.0, "wytrzymałość 50 zachowana w obu częściach stosu")
	var gem := "misc_soulgem_petty@synth_rat"
	if not inv.item(gem).is_empty():
		inv.add(csid, crec, gem, 2)
		inv_gp._drop_data(Vector2.ZERO, {"mw_item": gem, "source": "container"})
		check(cd.is_open() and cd.item_text.text.ends_with(")"), "kamień dusz: nazwa z duszą (getSoulString) – %s" % cd.item_text.text)
		cd.set_count(1)
		cd.press_ok()
		check(inv.count_of("player", {}, gem) == 1 and inv.count_of(csid, crec, gem) == 1, "dusza zachowana po podziale")
	# 6. zamknięcie okna pojemnika przy otwartym oknie ilości – okno ilości anulowane
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": worn_id, "source": "container"})
	check(not cd.is_open() and inv.count_of(csid, crec, worn_id) == 0, "stos 1 – bez okna ilości")
	inv.add(csid, crec, "misc_synth_spoon", 3)
	inv_gp._drop_data(Vector2.ZERO, {"mw_item": "misc_synth_spoon", "source": "container"})
	var before: int = inv.count_of("player", {}, "misc_synth_spoon")
	mm.close()
	check(not cd.is_open() and inv.count_of("player", {}, "misc_synth_spoon") == before, "zamknięcie pojemnika anuluje okno ilości")
	await _frames(2)
	# 7. upuszczenie w świat części stosu (InventoryWindow → HUD::dropDraggedItem z liczbą)
	mm.open()
	await _frames(2)
	inv.add("player", {}, "misc_synth_spoon", 3)
	var have: int = inv.count_of("player", {}, "misc_synth_spoon")
	check(have >= 3, "łyżki w ekwipunku (%d)" % have)
	var dyn0: int = main.state.dynamic.size()
	mm.drop_to_world("misc_synth_spoon", "inventory", {})
	check(cd.is_open(), "upuszczenie stosu w świat – okno ilości")
	cd.set_count(2)
	cd.press_ok()
	check(inv.count_of("player", {}, "misc_synth_spoon") == have - 2 and main.state.dynamic.size() == dyn0 + 1,
		"upuszczono 2, reszta w ekwipunku")
	mm.close()
	await _frames(2)
	# 8. handel: kliknięcie stosu kupca – sQuanityMenuMessage02, rzeczy gracza – sQuanityMenuMessage01, Ctrl – 1
	var trader := _ref(main, "synth_trader")
	if trader != null and main.open_dialogue(trader):
		var tw = main.trade_window
		check(tw.open("barter"), "okno handlu")
		await _frames(2)
		var mspoons: int = tw._available("misc_synth_spoon", "merchant")
		check(mspoons > 1, "łyżki u kupcy (%d)" % mspoons)
		tw.click_item("misc_synth_spoon", "merchant", {})
		check(cd.is_open() and cd.label_text.text == T.call("sQuanityMenuMessage02", "Buy how many?") and cd.max_count == mspoons,
			"zakup: sQuanityMenuMessage02, domyślnie cały stos (%s, %d)" % [cd.label_text.text, cd.max_count])
		cd.set_count(2)
		cd.press_ok()
		check(int(tw.buy.get("misc_synth_spoon", 0)) == 2 and tw._available("misc_synth_spoon", "merchant") == mspoons - 2,
			"koszyk zakupu: 2")
		tw.click_item("misc_synth_spoon", "bought", {})
		check(cd.is_open() and cd.label_text.text == T.call("sQuanityMenuMessage01", "Sell how many?") and cd.max_count == 2,
			"zwrot z ekwipunku: sQuanityMenuMessage01 (2)")
		cd.set_count(1)
		cd.press_ok()
		check(int(tw.buy.get("misc_synth_spoon", 0)) == 1, "zwrócono 1 – w koszyku 1")
		tw.click_item("misc_synth_spoon", "merchant", {"ctrl": true})
		check(not cd.is_open() and int(tw.buy.get("misc_synth_spoon", 0)) == 2, "Ctrl: 1 sztuka bez okna")
		var ps: int = tw._available("misc_synth_spoon", "player")
		if ps > 1:
			tw.dropped_on("merchant", {"mw_item": "misc_synth_spoon", "source": "player"})
			check(cd.is_open() and cd.label_text.text == T.call("sQuanityMenuMessage01", "Sell how many?"), "sprzedaż przeciągnięciem: sQuanityMenuMessage01")
			cd.press_ok()
			check(int(tw.sell.get("misc_synth_spoon", 0)) == ps, "sprzedaż całego stosu (%d)" % ps)
		tw.close()
	else:
		check(false, "kupiec i rozmowa")
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
