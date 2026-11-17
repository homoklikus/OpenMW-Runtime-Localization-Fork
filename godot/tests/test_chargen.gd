extends SceneTree
## Etap 9: tworzenie postaci przez skrypty (jak CharGen Morrowinda) – blokady sterowania i walki, Say + SayDone
## (funkcja bez nawiasów), kolejne menu (imię, rasa, klasa, znak, przegląd) z trybem menu wstrzymującym skrypt,
## odblokowanie ekwipunku, ChangeWeather, GetRace; skrypt przedmiotu w ekwipunku gracza (OnPCAdd, OnPCEquip,
## zmienne idą z przedmiotem); nowa gra ze skryptami (CharGenState, okna zablokowane); zapis i odczyt.
## godot --headless --path godot -s res://tests/test_chargen.gd -- --data=WYNIKI(aktorzy) --pos=… --scripts=1

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

func _until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await process_frame
	return -1

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var sc = main.scripts
	var cg = main.chargen
	# nowa gra „jak w Morrowindzie” niedostępna bez skryptów CharGen w danych – szybki tryb jak dotąd
	check(not main._scripted_chargen_wanted(), "bez skryptu CharGen w danych – brak nowej gry ze skryptami")
	main.state.player["menus"] = {"inventory": false, "magic": false, "map": false, "stats": false, "rest": false}
	var cg0: float = sc.get_global("chargenstate")
	sc.set_global("chargenstate", 10.0)
	check(not main.menu_allowed("inventory") and not main.menu_allowed("rest"), "okna i odpoczynek zablokowane jak przy nowej grze (disallowAll)")
	# BookWindow::setInventoryAllowed: bez ekwipunku przycisk „Weź” ukryty, odblokowanie ekwipunku go pokazuje
	main.book_window.open("synth_book", main.interaction.records.record("book", "synth_book"), true)
	check(main.book_window._take != null and not main.book_window._take.visible, "książka w czasie tworzenia postaci: bez „Weź”")
	main.script_host.enable_menu("inventory")
	check(main.book_window._take.visible, "EnableInventoryMenu przy otwartej książce pokazuje „Weź”")
	main.book_window.close()
	main.state.player["menus"]["inventory"] = false
	sc.set_global("chargenstate", -1.0)
	check(main.menu_allowed("rest"), "getRestEnabled: odpoczynek po zakończeniu tworzenia postaci (CharGenState −1)")
	sc.set_global("chargenstate", cg0)
	sc.start("synth_cg")
	await _frames(3)
	check(not main.control_allowed("controls") and not main.control_allowed("fighting"), "DisablePlayerControls / DisablePlayerFighting")
	check(main.control_allowed("magic"), "blokada tylko wskazanych czynności")
	Engine.time_scale = 4.0
	var nm := await _until(func(): return cg.visible and cg.step == "name", 600)
	check(nm >= 0, "po kwestii (SayDone) menu imienia")
	check(sc.game.menu_mode(), "menu tworzenia postaci = tryb menu (MenuMode)")
	await _frames(5)
	check(int(sc._locals("global:synth_cg").get("state", 0)) == 20, "skrypt wstrzymany w trybie menu")
	cg.name_edit.text = "Testowa"
	cg._create()
	var steps := ["race", "class", "birth", "statreview"]
	var seen := []
	for st in steps:
		var ok := await _until(func(): return cg.visible and cg.step == st, 200)
		if ok >= 0:
			seen.append(st)
			if st == "race":
				cg.choose("race", "synth elf")
			cg._create()
	check(seen == steps, "kolejne menu: rasa, klasa, znak, przegląd (%s)" % [seen])
	await _until(func(): return int(sc._locals("global:synth_cg").get("state", 0)) == 70, 200)
	var st: Dictionary = main.player_stats()
	check(String(st.get("name", "")) == "Testowa" and String(st.get("race", "")) == "synth elf", "postać z menu: imię i rasa")
	check(main.control_allowed("controls") and main.menu_allowed("inventory"), "EnablePlayerControls, EnableInventoryMenu")
	check(String(main.envr.weather) == "rain", "ChangeWeather region 4 → deszcz (%s)" % main.envr.weather)
	check(sc.get_global("synthstate") == 77.0, "GetRace „Synth Elf” = 1")
	Engine.time_scale = 1.0
	# skrypt przedmiotu w ekwipunku
	var inv = main.interaction.inventory
	inv.add("player", {}, "synth_papers", 1)
	await _frames(3)
	check(int(sc._locals("inv:synth_papers").get("state", 0)) == 1, "OnPCAdd przy przybyciu przedmiotu")
	await _frames(3)
	check(int(sc._locals("inv:synth_papers").get("state", 0)) == 1, "OnPCAdd tylko raz")
	inv.add("player", {}, "synth_cg_dagger", 1)
	await _frames(2)
	main.equip_item("synth_cg_dagger")
	await _frames(3)
	check(int(sc._locals("inv:synth_cg_dagger").get("state", 0)) == 10, "OnPCEquip po założeniu")
	# zapis i odczyt
	var path := ProjectSettings.globalize_path("user://chargen/test.mwsave")
	check(main.save_game(path) == "", "zapis")
	main.state.player["controls"] = {"controls": false}
	main.load_game(path)
	await _frames(5)
	check(main.control_allowed("controls") and main.menu_allowed("inventory") and String(main.player_stats().get("name", "")) == "Testowa",
		"odczyt: blokady, okna i postać")
	check(int(sc._locals("inv:synth_cg_dagger").get("state", 0)) == 10, "odczyt: zmienne skryptu przedmiotu")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
