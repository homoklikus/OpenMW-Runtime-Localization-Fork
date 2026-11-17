extends SceneTree
## Sonda startu gry na prawdziwych danych (Xvfb, renderer zgodności): logo firmy → menu główne + muzyka tytułowa →
## logo Morrowinda → Nowa gra (ekran ładowania, film wstępu) → gra → menu w grze → zapis → menu → wczytanie.
## Zrzuty (lokalnie, tylko do porównania – nie do repozytorium): PROBE_SHOTS=katalog. Tylko identyfikatory i liczby.
## godot [--rendering-method gl_compatibility] --path godot -s res://tests/probe_start.gd -- --data=WYNIKI --saves=KATALOG
##   --menu=1   (dane z filmami i fallbackami Movies_*). Wynik: RESULT {checks, failures}; kod 1 przy niezgodności.
var main
var shots := ""
var t0 := 0
var failures: Array[String] = []
var checks := 0
func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)
func _init():
	_run.call_deferred()
func _now() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0
func log_(s: String) -> void:
	print("PROBE t=%.1f %s" % [_now(), s])
func shot(name: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(shots.path_join(name + ".png"))
		log_("zrzut " + name)
func esc() -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.physical_keycode = KEY_ESCAPE
		e.pressed = p
		Input.parse_input_event(e)
func wait_s(s: float) -> void:
	await create_timer(s, true).timeout
func until(cond: Callable, secs: float) -> bool:
	var end := _now() + secs
	while _now() < end:
		if cond.call():
			return true
		await process_frame
	return false
func _run():
	t0 = Time.get_ticks_msec()
	shots = OS.get_environment("PROBE_SHOTS")
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shots)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	log_("stan=%s logo=%s" % [main.game_state, main.fallback("Movies_Company_Logo")])
	await until(func(): return main.video.playing, 5.0)
	log_("film %s gra; długość=%.2f" % [main.video.current, main.video._player.get_stream_length()])
	await wait_s(4.0)
	log_("pozycja filmu po 4 s: %.2f" % main.video._player.stream_position)
	check(main.video.current == "bethesda logo.bik" and absf(main.video._player.stream_position - 4.0) < 0.4, "logo firmy pierwsze, tempo odtwarzania (%.2f s po 4 s)" % main.video._player.stream_position)
	check(not main.main_menu.is_open(), "menu dopiero po logo firmy")
	var length: float = main.video._player.get_stream_length()
	await shot("01_logo_firmy")
	await until(func(): return main.video.played.size() >= 1, 20.0)
	log_("logo firmy: %s" % [main.video.played[0]])
	check(absf(float(main.video.played[0][2]) - length) < 1.0, "logo firmy odtworzone w całości w czasie rzeczywistym (%.2f / %.2f s)" % [main.video.played[0][2], length])
	await until(func(): return main.main_menu.is_open(), 5.0)
	log_("menu=%s muzyka=%s gra=%s" % [main.main_menu.is_open(), main.music.track, main.music.is_playing()])
	check(main.main_menu.is_open() and main.music.track == "music/special/morrowind title.mp3", "menu główne i muzyka tytułowa")
	await until(func(): return main.video.playing, 3.0)
	log_("drugi film %s" % main.video.current)
	await wait_s(3.0)
	await shot("02_logo_morrowinda")
	esc()
	await until(func(): return not main.video.playing, 3.0)
	log_("po Esc: grane=%s menu=%s muzyka=%s" % [main.video.played.back(), main.main_menu.is_open(), main.music.is_playing()])
	check(main.video.played.size() >= 2 and main.video.played[1][0] == "mw_logo.bik" and bool(main.video.played[1][1]), "logo Morrowinda drugie, pominięte Esc")
	await wait_s(0.5)
	log_("przyciski=%s tło=%s" % [main.main_menu.shown, main.main_menu.background_kind()])
	check(main.main_menu.shown == ["newgame", "options", "credits", "exitgame"] and main.main_menu.background_kind() == "image", "przyciski menu bez gry i obraz tła (jak OpenMW z danymi Morrowinda)")
	await shot("03_menu_glowne")
	# ekran ładowania z tapetą (bez gry)
	main.loading.loading_on()
	main.loading.set_label("Inicjalizacja...")
	main.loading.set_progress_range(10)
	for i in 4:
		main.loading.increase_progress()
	await shot("04_ekran_ladowania")
	log_("ekran ładowania: splash=%s rysowań=%d" % [main.loading.last_splash.get_file(), main.loading.shown_count])
	check(not main.loading.last_splash.is_empty(), "tapeta ekranu ładowania ze Splash/")
	main.loading.loading_off()
	# nowa gra
	main.main_menu.on_button("newgame")
	await until(func(): return main.video.playing, 30.0)
	log_("film nowej gry %s (długość %.1f s), stan=%s komórka=%s" % [main.video.current, main.video._player.get_stream_length(), main.game_state, main.interior])
	check(main.video.current == "mw_intro.bik" and main.interior == "Imperial Prison Ship", "film wstępu po wczytaniu statku")
	await wait_s(5.0)
	await shot("05_film_wstep")
	esc()
	await until(func(): return not main.video.playing, 3.0)
	await process_frame
	log_("po filmie: zaciemnienie=%.2f" % main.fader.alpha)
	await wait_s(0.5)
	await shot("06_poczatek_gry_fade")
	await wait_s(1.0)
	log_("po sekundzie: zaciemnienie=%.2f komórka=%s" % [main.fader.alpha, main.interior])
	check(main.fader.alpha < 0.05, "fadeScreenIn(1) po filmie")
	check(not main.mw_hud.bars.health.visible and not main.mw_hud.minimap.visible, "HUD bez pasków i minimapy na początku tworzenia postaci")
	await shot("07_statek")
	for i in 120:
		if main.chargen != null and main.chargen.visible:
			main.chargen._create()
		if main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible:
			main.press_message_button(0)
		if main.dialogue_window.visible:
			main.dialogue_window.close(true)
		await process_frame
	# zapis wymaga CharGenState −1 (OpenMW quickSave/saveGame) – w sondzie ustawiamy po pierwszych scenach
	main.scripts.set_global("chargenstate", -1.0)
	main.toggle_pause_menu()
	await wait_s(0.3)
	log_("menu w grze: %s" % [main.main_menu.shown])
	await shot("08_menu_w_grze")
	main.main_menu.on_button("savegame")
	await wait_s(0.3)
	main.save_dialog.name_edit.text = "Sonda startu"
	await shot("09_okno_zapisu")
	main.save_dialog.accept()
	await wait_s(0.5)
	log_("zapis: %s" % main.last_savegame.get_file())
	check(FileAccess.file_exists(main.last_savegame) and main.last_savegame.get_file() == "Sonda_startu.mwsave", "zapis w katalogu postaci")
	main.toggle_pause_menu()
	await wait_s(0.3)
	main.main_menu.on_button("loadgame")
	await wait_s(0.5)
	log_("okno wczytania: postacie=%d sloty=%d opis=[%s]" % [main.save_dialog._chars.size(), main.save_dialog.save_list.item_count, main.save_dialog.info_label.text.replace("\n", " | ")])
	await shot("10_okno_wczytania")
	main.save_dialog.accept()
	await wait_s(0.3)
	if main.confirm.is_open():
		main.confirm.press(true)
	await wait_s(1.0)
	log_("po wczytaniu: stan=%s komórka=%s ostatni=%s" % [main.game_state, main.interior, main.last_savegame.get_file()])
	check(main.game_state == "running" and main.interior == "Imperial Prison Ship", "wczytanie z menu: gra na statku")
	print("PROBE startup_log=%s" % [main.startup_log])
	print("PROBE filmy=%s" % [main.video.played])
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
