extends SceneTree
## Etap 9: MessageBoxManager jak OpenMW 0.51 – MessageBox (HUD_Box, szerokość 300 + 2 × 10, 48 px nad dołem,
## najstarszy najniżej, odstęp 4, najwyżej 3, czas = znaki × fMessageTimePerChar, także w trybie GUI)
## i InteractiveMessageBox (tekst do 400, przyciski tekst + 24 × 8, jeden wiersz albo kolumna, odstępy 10).
## godot --headless --path godot -s res://tests/test_messagebox.gd -- --data=WYNIKI --scripts=0

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

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	main._toast("Pierwszy")
	var mb = main.message_boxes
	var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	var vp: Vector2 = main.get_viewport().get_visible_rect().size / s
	var b0: Dictionary = mb.boxes[0]
	var p0: Control = b0.panel
	check(p0.size == Vector2(320, 36) * s, "jeden wiersz: 300 + 20 × 16 + 20 (%s)" % [p0.size / s])
	check(p0.position / s == Vector2(floorf((vp.x - 320) / 2.0), vp.y - 36 - 48), "na środku, 48 px nad dołem (%s)" % [p0.position / s])
	var tpc: float = float(main.dialogue._gmst("fMessageTimePerChar", 0.1))
	check(absf(float(b0.max) - 8 * tpc) < 0.0001, "czas życia = 8 znaków × fMessageTimePerChar")
	main._toast("Drugi")
	main._toast("Trzeci")
	check(mb.texts() == ["Pierwszy", "Drugi", "Trzeci"], "trzy komunikaty")
	var p1: Control = mb.boxes[1].panel
	check(p1.position.y / s == vp.y - 36 - 48 - (36 + 4), "kolejny wyżej o wysokość + 4 (%s)" % [p1.position / s])
	main._toast("Czwarty")
	check(mb.texts() == ["Drugi", "Trzeci", "Czwarty"], "czwarty usuwa najstarszy (%s)" % [mb.texts()])
	var long := "slowo ".repeat(40).strip_edges()
	main._toast(long)
	var last: Dictionary = mb.boxes.back()
	check(int(last.h) > 36 and int(last.h - 20) % 16 == 0, "długi tekst zawinięty do 300 px (wysokość %d)" % int(last.h))
	main.get_tree().paused = true
	for i in 200:
		await process_frame
		if mb.count() == 0:
			break
	check(mb.count() < 3, "komunikaty wygasają także w trybie GUI (zostało %d)" % mb.count())
	main.get_tree().paused = false
	mb.clear()
	# InteractiveMessageBox
	var pressed := [-1]
	main.show_message_box("Krotkie pytanie o cos waznego?", ["Tak", "Nie"], func(i): pressed[0] = i, true)
	var w: Control = mb.interactive
	check(mb.is_interactive() and main.msgbox != null and main.get_tree().paused, "okno z pytaniem, gra wstrzymana")
	var btns: Array = mb.interactive_buttons
	check(btns.size() == 2 and (btns[0] as Control).position.y == (btns[1] as Control).position.y, "przyciski w jednym wierszu (krótkie)")
	var bw0: float = (btns[0] as Control).size.x / s
	check((btns[0] as Control).size.y == 24 * s and (btns[1] as Control).position.x / s == (btns[0] as Control).position.x / s + bw0 + 10,
		"przyciski: wysokość 16 + 8, odstęp 10")
	main.press_message_button(1)
	check(pressed[0] == 1 and not mb.is_interactive() and not main.get_tree().paused, "wybór przycisku, okno znika, gra wznowiona")
	main.show_message_box("Tak?", ["Pierwsza dluga odpowiedz", "Druga"], Callable(), true)
	btns = mb.interactive_buttons
	check((btns[1] as Control).position.y > (btns[0] as Control).position.y, "przyciski szersze niż tekst – jeden pod drugim")
	main.press_message_button(0)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
