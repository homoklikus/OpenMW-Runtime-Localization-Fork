extends SceneTree
## Etap 10: nawigacja klawiaturą jak OpenMW 0.51 KeyboardNavigation – Tab/Shift+Tab (z zawinięciem, pierwsza
## kontrolka bez fokusu, AcceptTab w polach filtra i konsoli), strzałki tylko na przyciskach i tylko w danym
## kierunku, Enter/Spacja klikają przycisk z fokusem (bez powtórzeń), poza trybem GUI fokus zdjęty, domyślny fokus
## okna z pytaniem (#{sOk}/#{sYes}) i potwierdzenia (OK), zapamiętanie fokusu trybu przy przykryciu innym trybem.
## godot --headless --path godot -s res://tests/test_keyboard_nav.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

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

func _key(k: Key, shift := false, echo := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	e.shift_pressed = shift
	e.echo = echo
	Input.parse_input_event(e)
	var r := e.duplicate()
	r.pressed = false
	r.echo = false
	Input.parse_input_event(r)

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	var nav = main.keyboard_nav
	var vp := main.get_viewport()
	check(nav != null, "KeyboardNavigation")
	# poza trybem GUI: brak fokusu
	var probe := Button.new()
	main.overlay().add_child(probe)
	probe.focus_mode = Control.FOCUS_ALL
	probe.grab_focus()
	await _frames(2)
	check(vp.gui_get_focus_owner() == null, "poza trybem GUI fokus zdjęty (onFrame)")
	probe.queue_free()
	# okno opcji: domyślny fokus OK, Tab z zawinięciem, Shift+Tab, strzałki
	main.open_settings()
	await _frames(3)
	var w = main.settings_window
	check(vp.gui_get_focus_owner() == w.ok_button, "fokus na OK")
	_key(KEY_TAB)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[0], "Tab z ostatniej kontrolki – zawinięcie do pierwszej (%s)" % vp.gui_get_focus_owner())
	_key(KEY_TAB, true)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.ok_button, "Shift+Tab – poprzednia (OK)")
	_key(KEY_TAB)
	await _frames(1)
	_key(KEY_RIGHT)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[1], "strzałka w prawo – sąsiedni przycisk w prawo")
	_key(KEY_UP)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[1], "strzałka w górę – nic (następny nie leży wyżej)")
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	await _frames(1)
	check(vp.gui_get_focus_owner() == w.tab_buttons[0], "strzałka w lewo – bez zawinięcia")
	_key(KEY_ENTER)
	await _frames(1)
	check(w.current_page == 0, "Enter na zakładce Prefs")
	_key(KEY_RIGHT)
	_key(KEY_SPACE)
	await _frames(1)
	check(w.current_page == 1 and vp.gui_get_focus_owner() == w.tab_buttons[1], "Spacja klika zakładkę Audio")
	_key(KEY_LEFT)
	_key(KEY_ENTER)
	await _frames(1)
	# Prefs: przełącznik przez Tab i Spację
	var cb: Button = w.checks["autosave"]
	var lst := []
	nav.focus_list(nav.window_of(cb), lst)
	var steps := lst.find(cb) - lst.find(w.tab_buttons[0])
	for i in steps:
		_key(KEY_TAB)
	await _frames(1)
	check(vp.gui_get_focus_owner() == cb, "Tab do przełącznika autozapisu (%d kroków)" % steps)
	var before := String(cb.text)
	_key(KEY_SPACE)
	await _frames(1)
	check(String(cb.text) != before, "Spacja przełącza On/Off")
	_key(KEY_SPACE, false, true)
	await _frames(1)
	check(String(cb.text) != before, "powtórzenie klawisza nie klika ponownie")
	_key(KEY_SPACE)
	await _frames(1)
	check(String(cb.text) == before, "ponownie – z powrotem")
	# zapamiętanie fokusu trybu: okno potwierdzenia (domyślnie OK), powrót
	main.gui.push("test_mode", [])
	main.gui.pop()
	await _frames(2)
	check(vp.gui_get_focus_owner() == cb, "restoreFocus po zdjęciu trybu przykrywającego")
	main.confirm.ask("Question?")
	await _frames(2)
	var ok: Button = main.confirm.find_child("OkButton", true, false)
	check(ok != null and vp.gui_get_focus_owner() == ok, "okno potwierdzenia: fokus na OK")
	_key(KEY_TAB)
	await _frames(1)
	check(vp.gui_get_focus_owner() != null and String(vp.gui_get_focus_owner().name) == "CancelButton", "Tab – Cancel w oknie modalnym")
	var answered := []
	main.confirm.answered.connect(func(v): answered.append(v), CONNECT_ONE_SHOT)
	_key(KEY_ENTER)
	await _frames(1)
	check(answered == [false], "Enter klika przycisk z fokusem (Cancel), nie domyślny OK")
	w.close()
	await _frames(2)
	# okno z pytaniem: domyślny fokus #{sOk}/#{sYes}
	var pressed := []
	main.show_message_box("Proceed?", ["No", "Yes"], func(i): pressed.append(i))
	await _frames(2)
	check(vp.gui_get_focus_owner() != null and String((vp.gui_get_focus_owner() as Button).text) == "Yes", "okno z pytaniem: fokus na „Yes”")
	_key(KEY_ENTER)
	await _frames(2)
	check(pressed == [1], "Enter – „Yes” (%s)" % [pressed])
	main.show_message_box("Choose", ["A", "B"], func(i): pressed.append(i))
	await _frames(2)
	check(vp.gui_get_focus_owner() == null, "bez „OK”/„Yes” – bez fokusu")
	_key(KEY_TAB)
	await _frames(1)
	check(vp.gui_get_focus_owner() != null and String((vp.gui_get_focus_owner() as Button).text) == "A", "Tab bez fokusu – pierwsza kontrolka okna modalnego")
	_key(KEY_DOWN)
	_key(KEY_RIGHT)
	await _frames(1)
	var cur := String((vp.gui_get_focus_owner() as Button).text)
	_key(KEY_SPACE)
	await _frames(2)
	check(pressed.size() == 2 and pressed[1] == (0 if cur == "A" else 1), "Spacja klika (%s)" % cur)
	# konsola: Tab w wierszu poleceń – uzupełnianie (AcceptTab), fokus zostaje
	main.console.open()
	await _frames(2)
	main.console.command.text = "getpcce"
	main.console.command.caret_column = 7
	_key(KEY_TAB)
	await _frames(1)
	check(vp.gui_get_focus_owner() == main.console.command and main.console.command.text == "getpccell ", "konsola: Tab uzupełnia, fokus w wierszu (%s)" % main.console.command.text)
	main.console.close()
	await _frames(2)
	check(vp.gui_get_focus_owner() == null, "po zamknięciu konsoli (poza trybem GUI) bez fokusu")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
