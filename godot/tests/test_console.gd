extends SceneTree
## Etap 10: konsola jak OpenMW 0.51 (Console, WindowManager::toggleConsole/isConsoleMode) – kompilator MWScript
## (wektory konwertera), otwieranie „`”, tryb GUI (pauza, MenuMode), układ okna, wykonanie poleceń (echo, wynik
## funkcji, błędy), zmienne lokalne wybranego obiektu, tytuł „(refid)”, historia (strzałki, plik), Tab, Ctrl+W/U,
## wyszukiwanie, polecenia tylko konsoli (tgm, tcl, tai, fillmap, coc, coe, sv, tm), Esc zamyka konsolę.
## godot --headless --path godot -s res://tests/test_console.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

const Compiler := preload("res://scripts/mw/mw_mwscript_compiler.gd")

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

func _key(c: Control, k: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	c.gui_input.emit(e)

static func _norm(v) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))

func _run() -> void:
	# 0. kompilator: te same drzewa składni co konwerter (tests/data/mwscript_vectors.json)
	var vec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/mwscript_vectors.json"))
	var comp := Compiler.new()
	for name in vec.sources:
		var exp: Dictionary = vec.compiled[name]
		var got: Dictionary = comp.compile(String(vec.sources[name]))
		check(_norm(got.body) == _norm(exp.body) and _norm(got.locals) == _norm(exp.locals)
			and got.errors.size() == exp.errors.size(), "kompilator = konwerter: %s" % name)

	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	main.scripts.set_global("chargenstate", -1.0)
	var con = main.console
	con.history_path = "user://test_console_history.txt"
	if FileAccess.file_exists(con.history_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(con.history_path))
	con._init_history()
	check(con != null and not con.is_open(), "konsola utworzona, zamknięta")
	# 1. „`” – otwarcie: isConsoleMode = tryb GUI (pauza, MenuMode), fokus w wierszu poleceń
	_press("console")
	await _frames(2)
	check(con.is_open() and main.gui.is_gui_mode() and main.get_tree().paused, "`: konsola otwarta, tryb GUI, pauza")
	check(main.script_host.menu_mode(), "MenuMode = 1 przy otwartej konsoli")
	check(con.command.has_focus(), "fokus w wierszu poleceń")
	var vp: Vector2 = con.get_viewport().get_visible_rect().size
	check(con.win.position.is_equal_approx((Vector2(0.255, 0.215) * vp).floor()), "położenie okna [Windows] console")
	check(con.win.size.x >= floorf(0.49 * vp.x) - 1, "szerokość okna 0,49 ekranu")
	check(con.title.text == "Console", "tytuł: Console (%s)" % con.title.text)
	for n in ["button_Previous", "button_Next", "edit_SearchTerm", "button_CaseSensitive", "button_RegExSearch", "list_History", "edit_Command"]:
		check(con.win.find_child(n, true, false) != null, "element okna %s" % n)
	# 2. polecenie: echo, wykonanie, wynik funkcji, błąd
	con.command.text = "set synthstate to 7"
	con.accept_command()
	check(is_equal_approx(float(main.scripts.get_global("synthstate")), 7.0), "Set na zmiennej globalnej")
	check("> set synthstate to 7\n" in con.plain_log, "echo „> polecenie”")
	check(con.command.text.is_empty(), "wiersz wyczyszczony")
	main.scripts.set_global("synthstate", 0.0)
	var b0: int = con.plain_log.length()
	con.execute("set nosuchglobal to 1")
	check("Error" in con.plain_log.substr(b0), "nieznana zmienna – błąd wykonania")
	var hp := float(main.player_stats().get("health", 0.0))
	con.execute("player->GetHealth")
	check(("%d\n" % int(hp)) in con.plain_log or (str(hp) + "\n") in con.plain_log, "wynik funkcji wypisany (%s)" % hp)
	check(con.text_log.find("[color=#FF00FF]") >= 0, "wynik na fioletowo (#FF00FF)")
	con.execute("qqqfoo 1 2")
	check(con.text_log.find("[color=#FF2222]") >= 0, "błąd kompilacji na czerwono (#FF2222)")
	var before: int = con.plain_log.length()
	con.execute("lua print(1)")
	check(con.plain_log.length() > before and "Error" in con.plain_log.substr(before), "lua – komunikat o błędzie")
	# 3. wybór obiektu: tytuł z refid, zmienne lokalne jego skryptu
	var npc: Node = main.script_host.find_ref_by_base("synth_villager")
	check(npc != null, "NPC synth_villager w świecie")
	if npc != null:
		con.set_selected(npc)
		check(con.title.text == "Console (synth_villager)", "tytuł z refid wybranego obiektu (%s)" % con.title.text)
		con.execute("set helped to 3")
		check(is_equal_approx(main.scripts.local_value(String(npc.get_meta("mw_sid")), "helped"), 3.0), "zmienna lokalna wybranego obiektu")
		before = con.plain_log.length()
		con.execute("sv")
		check("helped" in con.plain_log.substr(before) and "3" in con.plain_log.substr(before), "ShowVars: zmienne lokalne")
		con.set_selected(npc)
		check(con.selected == null and con.title.text == "Console", "ponowny wybór – odznaczenie")
	# 4. historia: strzałki, bez powtórzeń z rzędu, plik
	con.command.text = "tai"
	con.accept_command()
	con.command.text = "tai"
	con.accept_command()
	check(con.command_history.size() == 2, "historia bez powtórzeń z rzędu (%d)" % con.command_history.size())
	con.command.text = "abc"
	_key(con.command, KEY_UP)
	check(con.command.text == "tai", "strzałka w górę – ostatnie polecenie")
	_key(con.command, KEY_UP)
	check(con.command.text == "set synthstate to 7", "strzałka w górę – poprzednie")
	_key(con.command, KEY_DOWN)
	_key(con.command, KEY_DOWN)
	check(con.command.text == "abc", "strzałka w dół – przywrócony edytowany tekst")
	var lines: PackedStringArray = FileAccess.get_file_as_string(con.history_path).strip_edges().split("\n")
	check(lines.size() == 2 and lines[1] == "tai", "console_history.txt (%s)" % [lines])
	con._init_history()
	check(con.command_history.size() == 2, "historia wczytana z pliku")
	# 5. Tab, Ctrl+W, Ctrl+U; listNames obejmuje identyfikatory obiektów
	check("synth_villager" in con.list_names() and "getpccell" in con.list_names() and "endif" in con.list_names(), "listNames: obiekty, funkcje, słowa kluczowe")
	con.command.text = "player->getpcce"
	con.command.caret_column = con.command.text.length()
	_key(con.command, KEY_TAB)
	check(con.command.text == "player->getpccell ", "Tab: uzupełnienie jedynego kandydata (%s)" % con.command.text)
	con.command.text = "getpcc"
	_key(con.command, KEY_TAB)
	check(con.command.text == "getpcc", "Tab: wspólny przedrostek bez zmian")
	_key(con.command, KEY_TAB)
	check("getpccrimelevel" in con.plain_log, "Tab bez zmiany – lista kandydatów")
	con.command.text = "player->additem gold"
	con.command.caret_column = con.command.text.length()
	_key(con.command, KEY_W, true)
	check(con.command.text == "player->additem ", "Ctrl+W – usunięcie słowa (%s)" % con.command.text)
	con.command.text = "abc def"
	con.command.caret_column = 4
	_key(con.command, KEY_U, true)
	check(con.command.text == "def", "Ctrl+U – usunięcie do początku")
	con.command.text = ""
	# 6. wyszukiwanie w historii
	con.search.text = "AI ->"
	var p1: int = con.find_occurrence(1)
	var p2: int = con.find_occurrence(1)
	check(p1 >= 0 and p2 > p1, "wyszukiwanie – kolejne wystąpienie")
	check(con.find_occurrence(-1) == p1, "wyszukiwanie – poprzednie wystąpienie")
	con.search.text = "ai ->"
	con.toggle_case_sensitive()
	check(con.find_occurrence(1) < 0, "Aa: rozróżnianie wielkości liter")
	con.toggle_case_sensitive()
	con.toggle_regex()
	con.search.text = "AI -> O[nf]+"
	check(con.find_occurrence(1) >= 0, ".*: wyrażenie regularne")
	con.toggle_regex()
	# 7. polecenia tylko konsoli
	check(main.ai.enabled, "tai ×2: AI włączone z powrotem")
	con.execute("tgm")
	check(main.god_mode and "God Mode -> On" in con.plain_log, "tgm: God Mode -> On")
	var f := {"kind": "player"}
	var h0: float = main.combat.health(f)
	main.combat.set_health(f, h0 - 10.0)
	check(is_equal_approx(main.combat.health(f), h0), "tgm: brak obrażeń")
	var m0 := float(main.player_stats().get("magicka", 0.0))
	main.magic.set_magicka(f, m0 - 5.0)
	check(is_equal_approx(float(main.player_stats().get("magicka", 0.0)), m0), "tgm: brak kosztu magii")
	con.execute("togglegodmode")
	main.combat.set_health(f, h0 - 10.0)
	check(not main.god_mode and is_equal_approx(main.combat.health(f), h0 - 10.0), "tgm wyłączony: obrażenia")
	main.combat.set_health(f, h0)
	con.execute("tcl")
	check(main.player.fly and "Collision -> Off" in con.plain_log, "tcl: Collision -> Off")
	con.execute("tcl")
	check(not main.player.fly, "tcl: kolizja z powrotem")
	main.state.player["map_visited"] = {}
	con.execute("fillmap")
	var mv: Dictionary = main.state.player.get("map_visited", {})
	check(mv.has("0,0") and mv.has("1,1"), "fillmap: nazwane komórki znane (%d)" % mv.size())
	con.execute("tm")
	check(main.mw_hud == null or not main.mw_hud.hud_visible, "tm: HUD ukryty")
	con.execute("tm")
	check(main.mw_hud == null or main.mw_hud.hud_visible, "tm: HUD z powrotem")
	before = con.plain_log.length()
	con.execute("coc \"Synthville, Test House\"")
	await _frames(20)
	check(String(main.interior).to_lower() == "synthville, test house", "coc: wnętrze (%s)" % main.interior)
	con.execute("coc \"No Such Cell\"")
	check("Can't find cell" in con.plain_log.substr(before), "coc: nieznana komórka – błąd")
	con.execute("coe 1 1")
	await _frames(20)
	var g = MWCoords.cell_of(main.player.global_position)
	check(String(main.interior).is_empty() and g == Vector2i(1, 1), "coe 1 1: komórka zewnętrzna (%s)" % [g])
	con.execute("coc Synthville")
	await _frames(20)
	check(String(main.interior).is_empty(), "coc: nazwana komórka zewnętrzna")
	# 8. Esc zamyka konsolę, gra wznowiona
	_press("menu")
	await _frames(2)
	check(not con.is_open() and not main.get_tree().paused and not main.gui.is_gui_mode(), "Esc: konsola zamknięta, bez pauzy")
	check(main.pause_menu == null or not main.pause_menu.visible, "Esc nie otwiera menu przy zamykaniu konsoli")
	_press("console")
	await _frames(2)
	check(con.is_open(), "` ponownie otwiera konsolę")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_QUOTELEFT
	ev.keycode = KEY_QUOTELEFT
	ev.pressed = true
	con.command.gui_input.emit(ev)
	await _frames(2)
	check(not con.is_open(), "` w wierszu poleceń zamyka konsolę")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(con.history_path))
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
