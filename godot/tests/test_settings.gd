extends SceneTree
## Etap 10 – okno opcji jak OpenMW 0.51 SettingsWindow: tryb GM_Settings, układ i zakładki, suwaki (pozycja ↔
## wartość, nagłówki z wartością), przełączniki On/Off, zmiany od razu (głośności, trudność, przezroczystość menu,
## opóźnienie podpowiedzi, celownik, czułość i odwrócenie osi, pole widzenia, odległość widzenia, shader wody,
## tryb okna, VSync), przypisywanie klawiszy (None, komunikat stały, Esc, klawisze zastrzeżone, zabranie klawisza
## innej akcji, przywrócenie domyślnych, zapis), autozapis przed odpoczynkiem, „Always Use Best Attack”, OK/Esc
## i zapis ingame_settings.json; napisy i komunikaty nad oknami.
## godot --headless --path godot -s res://tests/test_settings.gd -- --data=WYNIKI(aktorzy) --settings=PLIK --saves=KATALOG --pos=… --scripts=0

const MWInput := preload("res://scripts/mw/mw_input.gd")
const SW := preload("res://scripts/mw/mw_settings_window.gd")
const UI := preload("res://scripts/mw/mw_ui.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e

func _run() -> void:
	# formatowanie i nazwy rozdzielczości (bez okna)
	check(SW.format_icu("Difficulty ({value})", {"value": 20}) == "Difficulty (20)", "ICU {value}")
	check(SW.format_icu("Field of View ({value, number, ::.00})", {"value": 75.0}) == "Field of View (75.00)", "ICU ::.00")
	check(SW.format_icu("Range ({value, number, :: group-off})", {"value": 7168}) == "Range (7168)", "ICU group-off")
	check(SW.resolution_text(1920, 1080) == "1920 × 1080 (16:9)" and SW.resolution_text(1440, 900) == "1440 × 900 (16:10)"
		and SW.resolution_text(1366, 768) == "1366 × 768 (16:9)" and SW.resolution_text(3440, 1440) == "3440 × 1440 (21:9)",
		"getResolutionText: proporcje")
	var sp := arg("settings")
	DirAccess.make_dir_recursive_absolute(sp.get_base_dir())
	var f := FileAccess.open(sp, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "mwgodot-runtime-settings", "version": 1, "music_volume": 0.5, "fov": 60}))
	f.close()
	var ing := sp.get_base_dir().path_join("ingame_settings.json")
	if FileAccess.file_exists(ing):
		DirAccess.remove_absolute(ing)
	MWInput.bindings_path = sp.get_base_dir().path_join("input_bindings.json")
	if FileAccess.file_exists(MWInput.bindings_path):
		DirAccess.remove_absolute(MWInput.bindings_path)
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(6)
	var cam := main.player.get_node_or_null("Camera3D") as Camera3D
	check(cam != null and is_equal_approx(cam.fov, 60.0), "pole widzenia z ustawień (60° jak OpenMW)")
	# 1. okno: GM_Settings, układ
	main.open_settings()
	await _frames(3)
	var w = main.settings_window
	var s: float = UI.ui_scale()
	var vp: Vector2 = w.get_viewport().get_visible_rect().size
	var want: Vector2 = (vp * 0.8).max(Vector2(640, 550) * s).min(vp).floor()
	check(w.visible and main.gui.contains("settings"), "okno opcji w trybie GM_Settings")
	check(w.win.size.is_equal_approx(want) and w.win.position.is_equal_approx(((vp - want) / 2.0).floor()), "okno 0,8 × 0,8 ekranu, wyśrodkowane")
	check(w.title.text == "Options", "tytuł #{OMWEngine:SettingsWindow}")
	var tabs: Array = w.tab_buttons.map(func(b): return String(b.text).strip_edges())
	check(tabs == ["Prefs", "Audio", "Controls", "Video", "Language"], "zakładki (%s)" % [tabs])
	var vtabs: Array = w.video_tab_buttons.map(func(b): return String(b.text).strip_edges())
	check(vtabs == ["Video", "Detail Level", "Water"], "zakładki wideo (%s)" % [vtabs])
	check(w.ok_button.text == "OK" and w.ok_button.has_focus(), "OK z fokusem (onOpen)")
	check(w.current_page == 0 and w.pages[0].visible and not w.pages[1].visible, "pierwsza zakładka widoczna")
	# 2. Audio: pozycja suwaka → wartość, od razu
	w.show_page(1)
	check(w.pages[1].visible and w.tab_buttons[1].button_pressed, "zakładka Audio")
	w.set_slider_position("music_volume", 2500)
	check(absf(main.music.volume - 2500.0 / 9999.0) < 0.001, "głośność muzyki od razu (%.4f)" % main.music.volume)
	w.set_slider_position("master_volume", 5000)
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(5000.0 / 9999.0)) < 0.01, "głośność ogólna – szyna Master")
	w.set_slider_position("voice_volume", 4000)
	check(absf(main.audio.voice_volume - 4000.0 / 9999.0) < 0.001, "głośność głosów")
	check(w.slider_labels["voice_volume"].text == "Voice", "nagłówek suwaka bez wartości (AudioVoice)")
	# 3. Prefs
	w.show_page(0)
	w.set_slider_position("difficulty", 150)
	check(int(main.settings.difficulty) == 50 and main.combat.difficulty == 50, "trudność 50 (pozycja 150 z 201)")
	check(w.slider_labels["difficulty"].text == "Difficulty (50)", "nagłówek z wartością (%s)" % w.slider_labels["difficulty"].text)
	w.set_slider_position("actors_processing_range", 0)
	check(int(main.settings.actors_processing_range) == 3584 and w.slider_labels["actors_processing_range"].text.ends_with("(3584)"), "zasięg przetwarzania aktorów 3584")
	w.set_slider_position("menu_transparency", 5000)
	check(absf(UI.WINDOW_BG.a - 5000.0 / 9999.0) < 0.001, "przezroczystość menu – tło okien od razu (%.3f)" % UI.WINDOW_BG.a)
	var tex_before = (UI.window_box() as StyleBoxTexture).texture if UI.window_box() is StyleBoxTexture else null
	w.set_slider_position("menu_transparency", 9999)
	check(is_equal_approx(UI.WINDOW_BG.a, 1.0), "przezroczystość 1,0 (None)")
	if tex_before != null:
		check((UI.window_box() as StyleBoxTexture).texture != tex_before, "skórka okien przebudowana")
	w.set_slider_position("menu_transparency", roundi(0.84 * 9999))
	w.set_slider_position("tooltip_delay", 9999)
	check(is_equal_approx(main.tooltips.delay, 1.0), "opóźnienie podpowiedzi 1 s")
	w.set_slider_position("tooltip_delay", 0)
	var low: Label = w.find_child("Slider_menu_transparency", true, false).find_child("Low", true, false)
	check(low != null and low.text == "Full", "podpis skrajny TransparencyFull")
	check(w.checks["autosave"].text == "On" and w.checks["best_attack"].text == "Off", "przełączniki z ustawień (On/Off)")
	w.toggle_check("crosshair")
	await _frames(2)
	check(w.checks["crosshair"].text == "Off" and main.settings.crosshair == false and (main.mw_hud == null or not main.mw_hud.crosshair.visible), "celownik wyłączony")
	w.toggle_check("crosshair")
	await _frames(2)
	check(main.mw_hud == null or main.mw_hud.crosshair.visible, "celownik z powrotem")
	# „Always Use Best Attack”: getBestAttack
	check(main.best_attack_type({"rec": {"slash": [1, 5], "chop": [1, 5], "thrust": [1, 5]}}) == 1, "równe obrażenia – cięcie")
	check(main.best_attack_type({"rec": {"slash": [1, 5], "chop": [2, 9], "thrust": [1, 9]}}) == 0, "największe rąbanie")
	check(main.best_attack_type({"rec": {"slash": [1, 9], "chop": [2, 9], "thrust": [2, 9]}}) == 2, "pchnięcie przy remisie z rąbaniem")
	# 4. Controls: lista, przypisanie
	w.show_page(2)
	await _frames(1)
	var rows: Array = w.controls_box.get_children()
	check(rows.size() >= 20 and String(rows[0].name) == "Row_move_forward", "lista akcji w kolejności OpenMW (%d)" % rows.size())
	check(w.binding_buttons["move_forward"].text == "W" and w.binding_buttons["attack"].text.ends_with(" 1")
		and w.binding_buttons["menu_mode"].text.ends_with(" 3"), "nazwy przypisań: klawisz, przycisk myszy (numeracja SDL)")
	w.start_rebind("jump")
	check(w.binding_buttons["jump"].text == "None" and main.message_boxes.has_static(), "przypisywanie: „None” i komunikat stały")
	check(w.handle_rebind_event(_key(KEY_F3)) == "ignored" and w.rebinding == "jump", "F3 zastrzeżony")
	check(w.handle_rebind_event(_key(KEY_ESCAPE)) == "cancel" and MWInput.binding_code("jump") == KEY_E and not main.message_boxes.has_static(), "Esc anuluje (bez zmiany)")
	w.start_rebind("jump")
	check(w.handle_rebind_event(_key(KEY_K)) == "bound" and MWInput.binding_code("jump") == KEY_K and w.binding_buttons["jump"].text == "K", "przypisanie K")
	w.start_rebind("jump")
	w.handle_rebind_event(_key(KEY_W))
	check(MWInput.binding_code("jump") == KEY_W and MWInput.binding_code("move_forward") == 0 and w.binding_buttons["move_forward"].text == "None", "klawisz zabrany innej akcji")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.pressed = true
	w.start_rebind("activate")
	w.handle_rebind_event(mb)
	check(MWInput.binding_code("activate") == -MOUSE_BUTTON_MIDDLE and w.binding_buttons["activate"].text.ends_with(" 2"), "przycisk myszy (środkowy = 2)")
	check(FileAccess.file_exists(MWInput.bindings_path), "przypisania zapisane (input_bindings.json)")
	var saved_b = JSON.parse_string(FileAccess.get_file_as_string(MWInput.bindings_path))
	check(saved_b is Dictionary and int(saved_b.bindings.jump) == KEY_W, "zapis: jump = W")
	w.find_child("ResetControlsButton", true, false).pressed.emit()
	await _frames(1)
	check(main.confirm.is_open() and main.confirm.text() == "Reset all controls to the default?", "pytanie ConfirmResetBindings")
	main.confirm.press(true)
	await _frames(1)
	check(MWInput.binding_code("jump") == KEY_E and MWInput.binding_code("move_forward") == KEY_W and MWInput.binding_code("activate") == KEY_SPACE, "przywrócone domyślne")
	# 4a. przełącznik Mouse/Keyboard – Controller: lista getActionControllerSorting, nazwy SDL, przypisywanie pada
	check(w.keyboard_switch.button_pressed and not w.controller_switch.button_pressed, "tryb klawiatury wybrany")
	w.controller_switch.pressed.emit()
	await _frames(1)
	rows = w.controls_box.get_children()
	check(not w.keyboard_mode and w.controller_switch.button_pressed and String(rows[0].name) == "Row_move_forward"
		and not w.binding_buttons.has("console"), "tryb pada: lista pada (bez konsoli) (%d)" % rows.size())
	check(w.binding_buttons["move_forward"].text == "None" and w.binding_buttons["activate"].text == "A Button"
		and w.binding_buttons["attack"].text == "Right Trigger" and w.binding_buttons["menu_mode"].text == "B Button",
		"nazwy pada: ruch z osi (None), A Button, Right Trigger, B Button")
	w.start_rebind("activate")
	check(w.handle_rebind_event(_key(KEY_K)) == "ignored" and w.rebinding == "activate", "tryb pada: klawiatura pomijana")
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_Y
	jb.pressed = true
	check(w.handle_rebind_event(jb) == "bound" and w.binding_buttons["activate"].text == "Y Button"
		and w.binding_buttons["ready_magic"].text == "None" and MWInput.binding_code("activate") == KEY_SPACE,
		"tryb pada: Y przypisany, zabrany magii, klawisz aktywacji bez zmian")
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 1.0
	w.start_rebind("jump")
	check(w.handle_rebind_event(jm) == "ignored", "tryb pada: gałka nie (tylko spusty)")
	jm.axis = JOY_AXIS_TRIGGER_RIGHT
	check(w.handle_rebind_event(jm) == "bound" and w.binding_buttons["jump"].text == "Right Trigger" and w.binding_buttons["attack"].text == "None",
		"tryb pada: prawy spust na skok, atak bez przypisania")
	saved_b = JSON.parse_string(FileAccess.get_file_as_string(MWInput.bindings_path))
	check(int(saved_b.controller.activate.get("button", -1)) == JOY_BUTTON_Y, "zapis przypisań pada (%s)" % str(saved_b.get("controller", {})).left(120))
	w.start_rebind("ready_weapon")
	check(w.handle_rebind_event(_key(KEY_ESCAPE)) == "cancel" and w.binding_buttons["ready_weapon"].text == "X Button", "tryb pada: Esc anuluje")
	w.find_child("ResetControlsButton", true, false).pressed.emit()
	await _frames(1)
	main.confirm.press(true)
	await _frames(1)
	check(w.binding_buttons["activate"].text == "A Button" and w.binding_buttons["ready_magic"].text == "Y Button"
		and w.binding_buttons["attack"].text == "Right Trigger" and w.binding_buttons["jump"].text == "Left Trigger"
		and MWInput.binding_code("jump") == KEY_E, "tryb pada: domyślne przypisania pada (klawisze bez zmian)")
	w.keyboard_switch.pressed.emit()
	await _frames(1)
	check(w.keyboard_mode and w.binding_buttons.has("console"), "powrót do listy klawiatury")
	w.toggle_check("invert_x")
	check(main.player.controller.invert_x and w.checks["invert_x"].text == "On", "odwrócenie osi X")
	w.toggle_check("invert_x")
	w.set_slider_position("mouse_sensitivity", 0)
	check(is_equal_approx(main.player.mouse_sens, 0.2 * SW.SENS_BASE), "czułość kamery 0,2")
	w.set_slider_position("mouse_sensitivity", roundi((1.0 - 0.2) / 4.8 * 9999))
	check(absf(main.player.mouse_sens - SW.SENS_BASE) < 0.00001, "czułość kamery 1,0")
	# 5. Video
	w.show_page(3)
	w.show_video_page(0)
	var rl: ItemList = w.resolution_list
	check(rl.item_count >= 3 and rl.get_item_text(0).begins_with("3840 × 2160"), "lista rozdzielczości malejąco (%s)" % rl.get_item_text(0))
	w.window_mode_list.select(1)
	w._on_window_mode(1)
	check(String(main.settings.window_mode) == "fullscreen" and rl.is_item_disabled(0) and w.window_mode_hint.visible and w.window_border_button.disabled, "Windowed Fullscreen: lista wyłączona, podpowiedź, bez ramki")
	w._on_window_mode(2)
	check(String(main.settings.window_mode) == "windowed" and not rl.is_item_disabled(0) and not w.window_border_button.disabled, "Windowed: lista i ramka dostępne")
	w._on_vsync(2)
	check(main.settings.vsync == true and main.settings.vsync_adaptive == true and main.vsync_mode_value() == DisplayServer.VSYNC_ADAPTIVE, "VSync adaptacyjny")
	w._on_vsync(0)
	check(main.vsync_mode_value() == DisplayServer.VSYNC_DISABLED, "VSync wyłączony")
	w._on_vsync(1)
	var idx := -1
	for i in w.resolutions.size():
		if w.resolutions[i] == Vector2i(1920, 1080):
			idx = i
	w._on_resolution_selected(idx)
	await _frames(1)
	check(main.confirm.is_open() and main.confirm.text().begins_with("New resolution"), "pytanie ConfirmResolution")
	main.confirm.press(true)
	await _frames(1)
	check(String(main.settings.resolution) == "1920x1080", "rozdzielczość po potwierdzeniu")
	w.set_slider_position("fov", 45)
	check(int(main.settings.fov) == 75 and is_equal_approx(cam.fov, 75.0), "pole widzenia 75 (pozycja 45 z 81)")
	check(w.slider_labels["fov"].text == "Field of View (75.00)", "nagłówek FieldOfViewValue (%s)" % w.slider_labels["fov"].text)
	w.show_video_page(1)
	check(int(w.sliders["view_distance"].value) == 79420, "1500 m > 81920 j. – suwak na końcu")
	w.set_slider_position("view_distance", 0)
	check(int(main.settings.view_distance) == roundi(2500.0 / MWCoords.UNITS_PER_METER), "odległość widzenia 2500 j.")
	w.set_slider_position("view_distance", 79420)
	check(int(main.settings.view_distance) == roundi(81920.0 / MWCoords.UNITS_PER_METER) and is_equal_approx(cam.far, float(main.settings.view_distance)), "odległość widzenia 81920 j. (%d m)" % int(main.settings.view_distance))
	check(w.slider_labels["view_distance"].text == "View Distance (×10.00)", "nagłówek w komórkach (%s)" % w.slider_labels["view_distance"].text)
	w.show_video_page(2)
	var wm0: String = main.envr.water_mode
	w.toggle_check("water_shader")
	check(main.envr.water_mode != wm0, "shader wody przełączony od razu (%s)" % main.envr.water_mode)
	w.toggle_check("water_shader")
	# 5a. Language: języki z plików l10n, zmiana wymaga ponownego uruchomienia (bez zmiany tekstów od razu)
	w.show_page(4)
	check(w.languages.has("en") and w.languages.has("pl") and not w.languages.has("gmst"), "Language: języki l10n bez „gmst” (%s)" % [w.languages])
	check(w.primary_language.get_item_text(w.primary_language.selected) == "English" and w.secondary_language.selected == 0,
		"Language: en wybrany, drugi „None”")
	var pl_i: int = w.languages.find("pl")
	var en_i: int = w.languages.find("en")
	w.primary_language.select(pl_i)
	w._on_language(0, pl_i)
	await _frames(1)
	check(String(main.settings.preferred_locales) == "pl" and main.message_boxes.interactive != null, "Language: główny pl + komunikat ChangeRequiresRestart")
	check(w.title.text == "Options" or w.title.text == main.dialogue.gmst_text("sOptions", ""), "Language: teksty bez zmiany do ponownego uruchomienia")
	main.message_boxes.interactive_buttons[0].pressed.emit()
	await _frames(1)
	w._on_language(1, en_i + 1)
	check(String(main.settings.preferred_locales) == "pl,en", "Language: drugi en (%s)" % main.settings.preferred_locales)
	main.message_boxes.interactive_buttons[0].pressed.emit()
	await _frames(1)
	w._on_language(1, 0)
	check(String(main.settings.preferred_locales) == "pl", "Language: drugi None – tylko pierwszy")
	main.message_boxes.interactive_buttons[0].pressed.emit()
	await _frames(1)
	w._on_language(0, en_i)
	main.message_boxes.interactive_buttons[0].pressed.emit()
	await _frames(1)
	w.checks["gmst_overrides_l10n"].pressed.emit()
	await _frames(1)
	check(main.settings.gmst_overrides_l10n == false and main.message_boxes.interactive != null, "Language: gmst overrides l10n – przełącznik i komunikat")
	main.message_boxes.interactive_buttons[0].pressed.emit()
	await _frames(1)
	# 6. OK – zamknięcie, zapis
	w.ok_button.pressed.emit()
	await _frames(1)
	check(not w.visible and not main.gui.contains("settings"), "OK zamyka okno (tryb zdjęty)")
	check(FileAccess.file_exists(ing), "zapis ingame_settings.json obok ustawień launchera")
	var saved: Dictionary = main._load_ingame_settings()
	check(int(saved.get("difficulty", 0)) == 50 and int(saved.get("fov", 0)) == 75 and String(saved.get("resolution", "")) == "1920x1080", "zapisane wartości (%s)" % str(saved).left(200))
	check(String(saved.get("preferred_locales", "")) == "en" and saved.get("gmst_overrides_l10n", true) == false, "zapisane: preferred locales, gmst overrides l10n")
	main.open_settings()
	await _frames(2)
	check(w.checks.size() > 0 and int(w.sliders["difficulty"].value) == 150, "ponowne otwarcie – suwak z zapisanej wartości")
	var esc := InputEventAction.new()
	esc.action = "menu"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(3)
	check(not w.visible and not main.gui.contains("settings"), "Esc zamyka okno opcji")
	# 7. autozapis przed odpoczynkiem
	main.settings["autosave"] = true
	var saved_names := []
	main.events.game_saved.connect(func(p): saved_names.append(p))
	if main.rest_window.open():
		await _frames(2)
		main.rest_window.rest(1)
		await _frames(60)
	check(saved_names.size() == 1, "autozapis przed odpoczynkiem (%d)" % saved_names.size())
	if main.saves != null and main.saves.current != null:
		var desc := []
		for sl in main.saves.current.slots:
			desc.append(String(sl.header.get("description", "")))
		check("Autosave" in desc, "opis zapisu „Autosave” (%s)" % [desc])
	main.settings["autosave"] = false
	if main.rest_window.open():
		await _frames(2)
		main.rest_window.rest(1)
		await _frames(60)
	check(saved_names.size() == 1, "autozapis wyłączony – bez zapisu")
	# napisy wyłączone – brak napisu; napisy i komunikaty na warstwie nad oknami
	# napisy jak OpenMW: [GUI] subtitles (domyślnie wyłączone) – zwykły komunikat z samym tekstem kwestii
	main.settings["subtitles"] = true
	main.subtitle("Test napisu", 2.0)
	check(main.message_boxes != null and "Test napisu" in main.message_boxes.texts(), "napisy – komunikat WindowManager::messageBox")
	main.settings["subtitles"] = false
	main.apply_live_settings()
	main.subtitle("Drugi napis", 2.0)
	check(not ("Drugi napis" in main.message_boxes.texts()), "napisy wyłączone w ustawieniach – bez komunikatu")
	main._toast("Komunikat")
	check(main.message_boxes != null and main.message_boxes.layer > 24 and "Komunikat" in main.message_boxes.texts(),
		"komunikat (MessageBoxManager) na warstwie nad oknami")
	DirAccess.remove_absolute(MWInput.bindings_path)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
