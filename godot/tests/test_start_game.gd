extends SceneTree
## Pełny start gry jak OpenMW (dane syntetyczne, --menu=1):
## Engine::go (logo firmy → menu główne + muzyka tytułowa → logo Morrowinda), pomijanie filmu Esc, menu główne
## (przyciski wg stanu), nowa gra (ekran ładowania z tapetą Splash/, film Movies_New_Game, fadeScreenOut(0) +
## fadeScreenIn(1)), menu w grze (Esc), okno zapisu (postać, slot, nadpisanie z potwierdzeniem, pusta nazwa),
## wczytanie z menu (potwierdzenie porzucenia gry), szybki zapis/odczyt, usuwanie z potwierdzeniem, zapis
## uszkodzony (pominięty na liście, błąd wczytania → menu i komunikat), zapis sprzed etapu (katalog główny),
## śmierć (endGame → askLoadRecent), FadeIn/FadeOut/FadeTo i PlayBink ze skryptu, ekran ładowania w grze.
## godot --headless --path godot -s res://tests/test_start_game.gd -- --data=WYNIKI(aktorzy) --saves=KATALOG --menu=1

const GS := preload("res://scripts/mw/mw_game_state.gd")

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

func _until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await process_frame
	return -1

func _wait_s(sec: float) -> void:
	await create_timer(sec, true).timeout

func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventKey.new()
	r.keycode = KEY_ESCAPE
	r.physical_keycode = KEY_ESCAPE
	r.pressed = false
	Input.parse_input_event(r)

func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return ""

func _run() -> void:
	var saves_dir := _arg("saves")
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(2)
	var have_video: bool = not main.video.resolve("synth_logo.bik").is_empty()
	report["video_files"] = have_video
	# --- Engine::go ---
	check(main.game_state == "nogame", "start przez menu: stan bez gry (%s)" % main.game_state)
	check(main.player != null and not main.player.visible and main.loaded.is_empty(), "bez gry: świat pusty, gracz ukryty")
	if have_video:
		var f := await _until(func(): return main.video.playing, 30)
		check(f >= 0 and main.video.current == "synth_logo.bik", "logo firmy (Movies_Company_Logo) jako pierwsze")
		check(not main.main_menu.is_open(), "menu główne dopiero po logo firmy")
		check(get_root().get_tree().paused, "w trakcie filmu świat stoi (pauza)")
		var ok := await _until(func(): return main.video.played.size() >= 1, 600)
		check(ok >= 0, "logo firmy dobiega końca")
		var t: float = main.video.played[0][2] if main.video.played.size() > 0 else 0.0
		report["company_logo_seconds"] = t
		check(t > 0.6 and t < 3.0, "film odtwarzany w czasie rzeczywistym (%.2f s, plik 1 s)" % t)
	await _until(func(): return main.main_menu.is_open(), 120)
	check(main.main_menu.is_open(), "menu główne otwarte")
	check(main.startup_log.has("main_menu") and main.startup_log[0].begins_with("company_logo:"), "kolejność startu (%s)" % [main.startup_log])
	if have_video:
		var m2 := await _until(func(): return main.video.playing and main.video.current == "synth_mwlogo.bik", 60)
		check(m2 >= 0, "logo Morrowinda po otwarciu menu (Movies_Morrowind_Logo): %s" % [main.video.played])
		await _frames(5)
		_esc()                               # allowSkipping: Esc przerywa film
		var sk := await _until(func(): return not main.video.playing, 60)
		check(sk >= 0 and bool(main.video.played.back()[1]), "Esc pomija film (pominięty=%s)" % [main.video.played.back()[1] if main.video.played.size() > 0 else null])
	await _frames(3)
	check(main.main_menu.shown == ["newgame", "options", "credits", "exitgame"], "menu bez gry i bez zapisów (%s)" % [main.main_menu.shown])
	check(main.main_menu.background_kind() == "image", "tło menu: obraz (brak video/menu_background) – %s" % main.main_menu.background_kind())
	# Esc w menu bez gry nic nie zamyka
	_esc()
	await _frames(3)
	check(main.main_menu.is_open(), "Esc nie zamyka menu bez gry")
	# --- nowa gra ---
	main.main_menu.on_button("newgame")
	if have_video:
		var iv := await _until(func(): return main.video.playing, 60)
		check(iv >= 0 and main.video.current == "synth_intro.bik", "film nowej gry (Movies_New_Game)")
		check(main.loading.shown_count > 0 and not main.loading.last_splash.is_empty(), "ekran ładowania z tapetą Splash/ przy nowej grze z menu (%d, %s)" % [main.loading.shown_count, main.loading.last_splash.get_file()])
		await _until(func(): return not main.video.playing, 600)
	await _frames(2)
	check(main.game_state == "running" and main.player.visible and not main.loaded.is_empty(), "nowa gra: świat wczytany")
	check(main.fader.alpha > 0.8, "po nowej grze ekran zaciemniony (fadeScreenOut(0): %.2f)" % main.fader.alpha)
	await _wait_s(0.5)
	var half: float = main.fader.alpha
	await _wait_s(0.7)
	check(half > 0.2 and half < 0.8 and main.fader.alpha < 0.01, "fadeScreenIn(1): w połowie %.2f, po sekundzie %.2f" % [half, main.fader.alpha])
	if main.chargen.visible:
		main.chargen._create()
		await _frames(3)
	main.scripts.set_global("chargenstate", -1.0)
	await _frames(5)
	# HUD wg dozwolonych okien (WindowManager::updateVisible): paski – statystyki, minimapa – mapa
	var menus: Dictionary = main.state.player.get("menus", {})
	main.state.player["menus"] = {"stats": false, "map": false, "inventory": true, "magic": true}
	await _frames(3)
	check(not main.mw_hud.bars.health.visible and not main.mw_hud.minimap.visible and main.mw_hud.weap_box.visible, "HUD: paski i minimapa ukryte bez okien statystyk i mapy")
	main.state.player["menus"] = menus
	await _frames(3)
	check(main.mw_hud.bars.health.visible and main.mw_hud.minimap.visible, "HUD: po odblokowaniu widoczny")
	# --- menu w grze ---
	main.toggle_pause_menu()
	await _frames(2)
	check(main.main_menu.is_open() and get_root().get_tree().paused, "Esc w grze: menu główne, gra wstrzymana")
	check(main.main_menu.shown == ["return", "newgame", "savegame", "options", "exitgame"], "menu w grze (%s)" % [main.main_menu.shown])
	check(main.main_menu.background_kind() == "", "menu w grze bez tła")
	await _frames(2)
	check(main.mw_hud.root.visible, "HUD widoczny pod menu w grze (jak OpenMW)")
	# --- okno zapisu ---
	main.main_menu.on_button("savegame")
	await _frames(3)
	var sd = main.save_dialog
	check(sd.visible and sd.saving and sd.name_edit.visible and not sd.character_select.visible and not sd.delete_button.visible, "okno zapisu: pole nazwy, bez wyboru postaci i usuwania")
	sd.name_edit.text = ""
	sd.accept()
	await _frames(2)
	check(main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible, "pusta nazwa – komunikat")
	main.press_message_button(0)
	await _frames(2)
	sd.name_edit.text = "Pierwszy zapis"
	sd.accept()
	await _frames(3)
	check(not sd.visible and not main.main_menu.is_open() and not get_root().get_tree().paused, "po zapisie okno i menu zamknięte, gra trwa")
	check(main.saves.current != null and (main.saves.current.slots as Array).size() == 1, "postać utworzona przy pierwszym zapisie, 1 slot")
	var slot_path := String(main.saves.current.slots[0].path) if main.saves.current != null else ""
	check(slot_path.get_file() == "Pierwszy_zapis.mwsave" and slot_path.get_base_dir().get_base_dir() == saves_dir, "plik slotu z opisu w katalogu postaci (%s)" % slot_path)
	var h: Dictionary = main.saves.current.slots[0].header if main.saves.current != null else {}
	check(String(h.get("description", "")) == "Pierwszy zapis" and int(h.get("player_level", 0)) >= 1 and h.has("time_played") \
		and not String(h.get("cell_name", "")).is_empty() and h.has("game_time") and h.has("max_health"), "nagłówek zapisu: opis, poziom, komórka, czas (%s)" % [h.keys()])
	check(float(h.get("time_played", 0)) > 0.5, "czas gry liczony (%.1f s)" % float(h.get("time_played", 0)))
	# nadpisanie istniejącego slotu: potwierdzenie
	main.open_main_menu()
	main.main_menu.on_button("savegame")
	await _frames(3)
	sd.save_list.select(0)
	sd._on_slot_selected(0)
	check(sd.name_edit.text == "Pierwszy zapis", "wybór slotu wpisuje jego nazwę")
	sd.accept()
	await _frames(2)
	check(main.confirm.is_open() and main.confirm.text().contains("nadpisać"), "nadpisanie wymaga potwierdzenia")
	main.confirm.press(true)
	await _frames(3)
	check((main.saves.current.slots as Array).size() == 1, "nadpisany ten sam slot (bez nowego pliku)")
	# zmiana stanu i wczytanie z menu (potwierdzenie porzucenia gry)
	var gold0: int = main.interaction.inventory.count_of("player", {}, "gold_001")
	main.interaction.inventory.add("player", {}, "gold_001", 123)
	main.open_main_menu()
	await _frames(2)
	check(main.main_menu.shown.has("loadgame"), "„Wczytaj” widoczne, gdy są zapisy")
	main.main_menu.on_button("loadgame")
	await _frames(3)
	check(sd.visible and not sd.saving and sd.character_select.visible and sd.delete_button.visible and sd.current_slot != null, "okno wczytania: postać, usuwanie, zaznaczony najnowszy zapis")
	check(sd.info_label.text.contains("Poziom") and not sd.cell_label.text.is_empty(), "opis slotu: poziom, komórka")
	sd.accept()
	await _frames(2)
	check(main.confirm.is_open() and main.confirm.text().contains("porzucić"), "wczytanie w trakcie gry wymaga potwierdzenia")
	main.confirm.press(true)
	await _frames(5)
	check(main.interaction.inventory.count_of("player", {}, "gold_001") == gold0, "wczytany stan sprzed zmiany (złoto %d)" % main.interaction.inventory.count_of("player", {}, "gold_001"))
	check(main.game_state == "running" and main.last_savegame == slot_path, "po wczytaniu gra trwa, ostatni zapis = slot")
	# szybki zapis i odczyt
	main.quick_save()
	await _frames(2)
	var qs = main.saves.quick_slot(main.saves.current, "Quicksave")
	check(qs != null and String(qs.header.get("description", "")) == "Quicksave", "szybki zapis: slot „Quicksave”")
	main.interaction.inventory.add("player", {}, "gold_001", 7)
	main.quick_save()
	await _frames(2)
	var nq := (main.saves.current.slots as Array).filter(func(s): return String(s.header.description) == "Quicksave").size()
	check(nq == 1, "drugi szybki zapis nadpisuje (max quicksaves 1): %d" % nq)
	main.interaction.inventory.add("player", {}, "gold_001", 50)
	main.quick_load()
	await _frames(3)
	check(main.interaction.inventory.count_of("player", {}, "gold_001") == gold0 + 7, "szybki odczyt: najnowszy zapis postaci")
	# --- zapis uszkodzony i zapis sprzed etapu ---
	var char_dir := String(main.saves.current.path)
	var bad := FileAccess.open(char_dir.path_join("uszkodzony.mwsave"), FileAccess.WRITE)
	bad.store_string("to nie jest zapis")
	bad.close()
	# zapis sprzed etapu: prawdziwy zapis z nagłówkiem w dawnej postaci (bez opisu slotu i metadanych), wersja 4,
	# w katalogu głównym zapisów jak dawny quicksave.mwsave
	var legacy: Dictionary = GS.read_file(slot_path)
	var old_header := {}
	for k in ["profile", "character", "content", "base_fingerprint", "world_format", "created", "game"]:
		if (legacy.header as Dictionary).has(k):
			old_header[k] = legacy.header[k]
	legacy["header"] = old_header
	legacy["version"] = 4
	legacy.erase("created")
	legacy.erase("created_next")
	(legacy.player.character as Dictionary)["name"] = "Dawny"
	GS.write_file(saves_dir.path_join("quicksave.mwsave"), legacy)
	main.saves.refresh()
	var listed := []
	for c in main.saves.characters:
		for s in c.slots:
			listed.append(String(s.path).get_file())
	check(not listed.has("uszkodzony.mwsave"), "uszkodzony plik pominięty na liście zapisów")
	var leg = null
	for c in main.saves.characters:
		if bool(c.legacy):
			leg = c
	check(leg != null and String(leg.slots[0].header.description) == "quicksave" and String(main.saves.signature(leg).get("player_name", "")) == "Dawny",
		"zapis sprzed etapu: osobna postać z imienia w zapisie, opis z nazwy pliku")
	var lw: Array = main.load_slot(leg, String(leg.slots[0].path)) if leg != null else ["BŁĄD"]
	await _frames(3)
	check(not (lw.size() > 0 and String(lw[0]).begins_with("BŁĄD")) and main.game_state == "running", "zapis sprzed etapu wczytany (migracja): %s" % [lw])
	var ew: Array = main.load_slot(null, char_dir.path_join("uszkodzony.mwsave"))
	await _frames(3)
	check(ew.size() > 0 and String(ew[0]).begins_with("BŁĄD") and main.game_state == "nogame" and main.main_menu.is_open() \
		and main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible, "uszkodzony zapis: błąd, menu główne i komunikat")
	check(FileAccess.file_exists(char_dir.path_join("uszkodzony.mwsave")), "oryginał uszkodzonego pliku nietknięty")
	main.press_message_button(0)
	await _frames(2)
	# --- usuwanie z potwierdzeniem (okno wczytania) ---
	main.main_menu.on_button("loadgame")
	await _frames(3)
	var ci := -1
	for i in sd._chars.size():
		if not bool(sd._chars[i].legacy):
			ci = i
	sd.character_select.select(ci)
	sd._on_character_selected(ci)
	var n0: int = sd.save_list.item_count
	var del_path := String(sd.current_slot.path)
	sd.confirm_delete()
	await _frames(2)
	check(main.confirm.is_open() and main.confirm.text().contains("usunąć"), "usuwanie wymaga potwierdzenia")
	main.confirm.press(false)
	await _frames(2)
	check(FileAccess.file_exists(del_path), "Anuluj – zapis zostaje")
	sd.confirm_delete()
	await _frames(2)
	main.confirm.press(true)
	await _frames(2)
	check(not FileAccess.file_exists(del_path) and sd.save_list.item_count == n0 - 1, "potwierdzone usunięcie: plik i pozycja usunięte")
	# wczytanie z menu bez gry (bez potwierdzenia)
	sd.save_list.select(0)
	sd._on_slot_selected(0)
	sd.accept()
	await _frames(5)
	check(not main.confirm.is_open() and main.game_state == "running" and not main.main_menu.is_open(), "wczytanie z menu bez gry – bez potwierdzenia")
	# --- skrypty: FadeOut/FadeIn/FadeTo, PlayBink ---
	main.fader.clear()
	main.script_host.fade("out", 1.0)
	await _wait_s(0.5)
	var mid: float = main.fader.alpha
	await _wait_s(0.7)
	check(mid > 0.2 and mid < 0.8 and main.fader.alpha > 0.99, "FadeOut 1 s: liniowo do czerni (%.2f → %.2f)" % [mid, main.fader.alpha])
	main.script_host.fade("to", 0.0, 50.0)
	await _frames(1)
	check(absf(main.fader.alpha - 0.5) < 0.01, "FadeTo 50 0 – natychmiast 50%%")
	main.script_host.fade("in", 0.5)
	await _wait_s(0.7)
	check(main.fader.alpha < 0.01, "FadeIn 0,5 s")
	main.scripts._call(null, "playbink", [["str", "synth_intro.bik"], ["num", 1.0]], preload("res://scripts/mw/mw_scripts.gd").Ctx.new())
	if have_video:
		var pb := await _until(func(): return main.video.playing, 10)
		check(pb >= 0, "PlayBink odtwarza film")
		_esc()
		await _until(func(): return not main.video.playing, 60)
	# --- ekran ładowania w grze ---
	var shown0: int = main.loading.shown_count
	var interior_key := ""
	for c in main.db.cell_index():
		if c.get("interior", false):
			interior_key = String(c["key"])
			break
	if not interior_key.is_empty():
		var cell: Dictionary = main.db.get_cell(interior_key)
		main.travel({"cell_key": interior_key, "cell_name": String(cell.get("name", "")), "transform": Transform3D()})
		await _frames(3)
		check(main.loading.nested == 0 and not main.loading.visible and main.loading.label == "Wczytywanie obszaru wewnętrznego", "ekran ładowania przy przejściu do wnętrza (etykieta, zamknięty po)")
		check(not main.loading.show_wallpaper, "w grze bez tapety (zamrożona klatka)")
	report["loading_draws_in_game"] = main.loading.shown_count - shown0
	# --- śmierć: endGame → askLoadRecent ---
	main._player_died()
	check(main.game_state == "ended", "śmierć: stan „Ended”")
	await _wait_s(main.DEATH_ANIM_SECONDS + 0.3)
	var asked := await _until(func(): return main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible, 30)
	check(asked >= 0 and main.msgbox.find_children("*", "Label", true, false)[0].text.contains("Ostatni zapis"), "po animacji śmierci pytanie o wczytanie ostatniego zapisu")
	main.press_message_button(1)
	await _frames(3)
	check(main.main_menu.is_open() and main.main_menu.shown == ["newgame", "loadgame", "options", "exitgame"], "„Nie” – menu główne w stanie Ended (%s)" % [main.main_menu.shown])
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(1 if failures.size() > 0 else 0)
