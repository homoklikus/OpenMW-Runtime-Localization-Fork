extends SceneTree
## Geometria klasycznego interfejsu w kilku rozdzielczościach – wartości z układów OpenMW 0.51 (files/data/mygui):
##   skala GUI niezależna od rozdzielczości (WindowManager: [GUI] scaling factor × HiDPI), czcionka 16 px;
##   HUD (openmw_hud.layout, 300 × 200 przypięte do lewego/prawego dolnego rogu): paski 65 × 12 w (12, 147/162/177),
##   pole broni (81, 147) 36 × 36 + pasek 36 × 6, pole czaru (121, 147), minimapa 65 × 65 w (223, 124), efekty
##   prawym dolnym rogiem w (219, 189);
##   dziennik (openmw_journal.layout 565 × 390 na ScalingLayer 600 × 520): skala min(szer./600, wys./520), środek ekranu;
##   skala gui_scaling_factor powiększa wszystko proporcjonalnie.
## godot --headless --path godot -s res://tests/test_ui_geometry.gd -- --data=WYNIKI(aktorzy) --scripts=0

const UI := preload("res://scripts/mw/mw_ui.gd")
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

static func near_v(a: Vector2, b: Vector2, eps := 0.6) -> bool:
	return absf(a.x - b.x) <= eps and absf(a.y - b.y) <= eps

## Pozycja z układu 300 × 200 (OpenMW) dla elementu przypiętego do lewego dolnego rogu.
static func lb(vp: Vector2, x: float, y: float, s: float) -> Vector2:
	return Vector2(x * s, vp.y - (200.0 - y) * s)

func _hud_case(main, vp: Vector2, s: float, tag: String) -> void:
	root.size = Vector2i(vp)
	await _frames(2)
	var hud = main.mw_hud
	hud.build()
	await _frames(1)
	check(is_equal_approx(hud.scale_ui, s), "%s: skala HUD %s (oczekiwana %s)" % [tag, hud.scale_ui, s])
	var kinds := ["health", "magic", "fatigue"]
	for i in 3:
		var b: Control = hud.bars[kinds[i]]
		check(near_v(b.position, lb(vp, 12, 147 + 15 * i, s)) and near_v(b.size, Vector2(65, 12) * s),
			"%s: pasek %s %s %s" % [tag, kinds[i], b.position, b.size])
	check(near_v(hud.weap_box.position, lb(vp, 81, 147, s)) and near_v(hud.weap_box.size, Vector2(36, 36) * s),
		"%s: pole broni %s" % [tag, hud.weap_box.position])
	check(near_v(hud.weap_bar.position, lb(vp, 81, 183, s)) and near_v(hud.weap_bar.size, Vector2(36, 6) * s),
		"%s: pasek broni %s %s" % [tag, hud.weap_bar.position, hud.weap_bar.size])
	check(near_v(hud.spell_box.position, lb(vp, 121, 147, s)), "%s: pole czaru %s" % [tag, hud.spell_box.position])
	check(near_v(hud.minimap.position, Vector2(vp.x - 77.0 * s, vp.y - 76.0 * s)) and near_v(hud.minimap.size, Vector2(65, 65) * s),
		"%s: minimapa %s" % [tag, hud.minimap.position])
	check(is_equal_approx(hud._effects_right, vp.x - 81.0 * s) and is_equal_approx(hud._effects_y, vp.y - 31.0 * s),
		"%s: pole efektów (prawy dolny róg)" % tag)
	# czcionka motywu: 16 px × skala GUI
	check(UI.theme(s).default_font_size == roundi(16 * s), "%s: czcionka %d" % [tag, UI.theme(s).default_font_size])

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	# okna budowane w main._ready mają ramki z tekstur danych (menu_thin_border_* / menu_thick_border_*), nie zapasowe
	# płaskie: UI.setup przed budową okien (wcześniej texture() zapamiętywał brak pliku przy pustym data_root)
	if FileAccess.file_exists(main.data_dir.path_join("textures/menu_thin_border_top.png")):
		var hb: Control = main.dialogue_window.find_child("DialogueHistoryBox", true, false)
		check(hb != null and hb.get_theme_stylebox("panel") is StyleBoxTexture,
			"ramka historii rozmowy z tekstur menu_thin_border_* (%s)" % [hb.get_theme_stylebox("panel") if hb != null else null])
		check(main.dialogue_window.panel.get_theme_stylebox("panel") is StyleBoxTexture,
			"ramka okna rozmowy z tekstur menu_thick_border_*")
	else:
		check(false, "dane testowe bez tekstur ramek interfejsu (mwconv synth: menu_thin_border_*)")
	# skórka MW_Window: Caption (4, 4, szer. − 8, 20), Client od (8, 28); openmw_dialogue_window: MW_Box w (8, 8)
	var dw = main.dialogue_window
	dw.panel.visible = true
	dw.visible = true
	await _frames(2)
	var s1 := UI.ui_scale()
	var pr: Rect2 = dw.panel.get_global_rect()
	var cap: Control = dw.panel.find_child("CaptionArea", true, false).get_child(0)
	var hb2: Control = dw.panel.find_child("DialogueHistoryBox", true, false)
	check(near_v(cap.global_position - pr.position, Vector2(4, 4) * s1) and absf(cap.size.x - (pr.size.x - 8 * s1)) < 0.6
			and absf(cap.size.y - 20 * s1) < 0.6, "pasek tytułu MW_Window (%s %s)" % [cap.global_position - pr.position, cap.size])
	check(near_v(hb2.global_position - pr.position, Vector2(16, 36) * s1),
		"ramka historii rozmowy w (16, 36) jak OpenMW (%s)" % [hb2.global_position - pr.position])
	dw.visible = false
	# skala niezależna od rozdzielczości
	UI.gui_scaling = 1.0
	var base := UI.ui_scale()
	check(base >= 1.0, "skala GUI ≥ 1 (%s)" % base)
	for vp in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3840, 2160)]:
		await _hud_case(main, vp, base, "%dx%d" % [vp.x, vp.y])
	# ustawienie skali GUI
	UI.gui_scaling = 2.0
	await _hud_case(main, Vector2(3840, 2160), 2.0 * base, "3840x2160 skala 2")
	UI.gui_scaling = 1.0
	# dziennik: ScalingLayer 600 × 520
	for vp in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(3840, 2160)]:
		root.size = Vector2i(vp)
		await _frames(2)
		var jw = main.journal_window
		jw.open()
		var k: float = minf(vp.x / 600.0, vp.y / 520.0)
		check(is_equal_approx(jw.scale_ui, k), "dziennik %dx%d: skala %s (oczekiwana %s)" % [vp.x, vp.y, jw.scale_ui, k])
		check(near_v(jw.panel.size, (Vector2(565, 390) * k).floor(), 1.0), "dziennik: rozmiar %s" % jw.panel.size)
		check(near_v(jw.panel.position + jw.panel.size / 2.0, vp / 2.0, 1.5), "dziennik: środek ekranu")
		jw.close()
	# okna trybu menu: położenie i rozmiar z ustawień OpenMW ([Windows] x, y, w, h – ułamki ekranu); zawartość
	# (napisy, paski, siatka) nie może rozpychać okna ponad rozmiar z ustawień
	for vp in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(3840, 2160)]:
		root.size = Vector2i(vp)
		await _frames(2)
		var mm = main.menu_mode
		main.window_store("ui_windows").clear()      # bez układu zapamiętanego przy innej rozdzielczości
		mm.open()
		await _frames(3)
		for wn in mm.DEFAULT_RECTS:
			var wr: Rect2 = mm.DEFAULT_RECTS[wn]
			var wc: Control = mm.windows.get(wn)
			if wc == null:
				continue
			check(near_v(wc.position, wr.position * vp, 2.5) and near_v(wc.size, wr.size * vp, 2.5),
				"%dx%d: okno %s %s %s (OpenMW %s %s)" % [vp.x, vp.y, wn, wc.position, wc.size, wr.position * vp, wr.size * vp])
		# InventoryWindow::adjustPanes: lewa część (H − 68) × 0,5, pola 12 px węższe
		var inv_h: float = (mm.windows["inventory"] as Control).size.y
		var enc: Control = mm.windows["inventory"].find_child("EncumbranceBar", true, false)
		check(enc != null and absf(enc.size.x - ((inv_h - 68.0) * 0.5 - 12.0)) < 1.5,
			"%dx%d: lewa część ekwipunku %s (OpenMW %.1f)" % [vp.x, vp.y, enc.size.x if enc else -1.0, (inv_h - 68.0) * 0.5 - 12.0])
		mm.close()
		await _frames(1)
	# MW_VScroll: 14 px, pola strzałek 14 × 15, krok 36, MoveToClick, suwak ≥ 14 px
	for sc_s in [1.0, 2.0]:
		UI.gui_scaling = sc_s / maxf(1.0, DisplayServer.screen_get_scale())
		root.size = Vector2i(1920, 1080)
		var holder := Control.new()
		holder.theme = UI.theme(sc_s)
		holder.size = Vector2(300, 300)
		root.add_child(holder)
		var sc := ScrollContainer.new()
		sc.size = Vector2(200, 180) * sc_s
		holder.add_child(sc)
		var content := Control.new()
		content.custom_minimum_size = Vector2(100, 2000)
		sc.add_child(content)
		await _frames(3)
		var vb: VScrollBar = sc.get_v_scroll_bar()
		check(absf(vb.get_combined_minimum_size().x - 14.0 * sc_s) < 0.6, "MW_VScroll skala %s: szerokość %s" % [sc_s, vb.get_combined_minimum_size().x])
		var dec: Texture2D = vb.get_theme_icon("decrement")
		check(dec != null and dec.get_size().is_equal_approx(Vector2(14, 15) * sc_s), "MW_VScroll: pole strzałki %s" % [dec.get_size() if dec else null])
		check(is_equal_approx(sc.scroll_vertical_custom_step, 36.0 * sc_s) and is_equal_approx(vb.custom_step, 36.0 * sc_s), "MW_VScroll: krok kółka i strzałek 36 × skala")
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = Vector2(7 * sc_s, vb.size.y - 25 * sc_s)
		UI._scroll_move_to_click(ev, vb)
		check(vb.value > (vb.max_value - vb.page) * 0.85, "MoveToClick: klik przy dole tła przenosi suwak (%.0f / %.0f)" % [vb.value, vb.max_value - vb.page])
		vb.value = 0.0
		var wh := InputEventMouseButton.new()
		wh.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wh.pressed = true
		wh.factor = 1.0
		wh.position = sc.get_global_rect().get_center()
		wh.global_position = wh.position
		root.push_input(wh)
		await _frames(1)
		check(absf(vb.value - 36.0 * sc_s) < 1.0, "WheelPage: kółko przewija o 36 × skala (%.1f)" % vb.value)
		var gmin: float = vb.get_theme_stylebox("grabber").get_minimum_size().y
		check(absf(gmin - 14.0 * sc_s) < 0.6, "MinTrackSize 14 (%s)" % gmin)
		holder.queue_free()
		await _frames(1)
	UI.gui_scaling = 1.0
	# okna etapu 10 – układy porównane ze zrzutami OpenMW 0.51 (tools/openmw-xvfb/ui_cases/ui_stage10_*)
	for vp in [Vector2(1280, 720), Vector2(3840, 2160)]:
		root.size = Vector2i(vp)
		await _frames(2)
		await _stage10_case(main, vp)
	# teksty silnika z l10n OpenMW (OMWEngine, Calendar) wg preferred locales
	var L10n = load("res://scripts/mw/mw_l10n.gd")
	L10n.set_locales("en")
	check(L10n.text("QuitGameConfirmation") == "Quit the game?", "l10n en: %s" % L10n.text("QuitGameConfirmation"))
	check(L10n.time_of_day(13.5) == "1 p.m." and L10n.time_of_day(0.2) == "12 a.m.", "l10n: godzina jak formatTimeOfDay (%s)" % L10n.time_of_day(13.5))
	L10n.set_locales("pl")
	check(L10n.text("DeleteGameConfirmation") == "Czy na pewno chcesz usunąć ten zapis gry?", "l10n pl: %s" % L10n.text("DeleteGameConfirmation"))
	check(L10n.ctx_text("Calendar", "day") == "Dzień" and L10n.time_of_day(13.5) == "1 po poł.", "l10n pl: Calendar (am/pm z pl, timeFormat z en) – %s" % L10n.time_of_day(13.5))
	check(L10n.text("MissingContentFilesConfirmation").count("\n") == 2, "l10n: blok |- wielowierszowy")
	L10n.set_locales("en")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)

## Okno opcji (openmw_settings_window.layout + TabControl z openmw_resources.xml), konsola (openmw_console.layout),
## szybkie klawisze (MW_ItemIconBox z MW_Box_Overlay) i kolejność warstw (openmw_layers.xml).
func _stage10_case(main, vp: Vector2) -> void:
	var tag := "%dx%d" % [vp.x, vp.y]
	var s := UI.ui_scale()
	main.open_main_menu()
	await _frames(1)
	main.open_settings()
	await _frames(3)
	var w = main.settings_window
	var wr: Rect2 = w.win.get_global_rect()
	var W := wr.size.x / s
	var H := wr.size.y / s
	var rel := func(c: Control) -> Vector2: return (c.global_position - wr.position) / s
	# nagłówek: przyciski od (16, 36), wysokość 24, kolejne o 4 px za ramką (MW_Button_RightPadding)
	var tb: Array = w.tab_buttons
	check(near_v(rel.call(tb[0]), Vector2(16, 36)) and absf(tb[0].size.y / s - 24.0) < 0.6, "%s: opcje – pierwsza zakładka w (16, 36) (%s)" % [tag, rel.call(tb[0])])
	var gaps_ok := true
	for i in range(1, tb.size()):
		gaps_ok = gaps_ok and absf(rel.call(tb[i]).x - (rel.call(tb[i - 1]).x + tb[i - 1].size.x / s + 4.0)) < 1.1
	check(gaps_ok, "%s: opcje – zakładki co szerokość + 4" % tag)
	var frame: Control = w.win.find_child("TabPages", true, false)
	check(near_v(rel.call(frame), Vector2(16, 66)) and near_v(frame.size / s, Vector2(W - 32, H - 112), 1.1),
		"%s: opcje – MW_Box stron w (16, 66), %s (OpenMW %s)" % [tag, frame.size / s, Vector2(W - 32, H - 112)])
	var pg: Control = w.pages[0]
	var pr: Vector2 = rel.call(pg)
	check(near_v(pr, Vector2(20, 70)), "%s: opcje – TabItem z wcięciem 4 (%s)" % [tag, pr])
	var ok := true
	var k := 0
	for key in ["menu_transparency", "tooltip_delay", "difficulty", "actors_processing_range"]:
		var sb: Control = w.sliders[key]
		ok = ok and near_v(rel.call(sb) - pr, Vector2(4, 24 + 60 * k)) and absf(sb.size.y / s - 14.0) < 0.6 and absf(sb.size.x / s - (W - 48)) < 1.1
		k += 1
	check(ok, "%s: opcje – suwaki preferencji w (4, 24 + 60k), 14 px" % tag)
	var chk: Control = w.checks["autosave"]
	check(near_v(rel.call(chk) - pr, Vector2(4, 250)) and absf(chk.size.y / s - 24.0) < 0.6,
		"%s: opcje – przełącznik autozapisu w (4, 250) (%s %s)" % [tag, rel.call(chk) - pr, chk.size / s])
	# OkButton: AutoSizedButton (napis + 24) z ExpandDirection Left – prawa krawędź 8 px przed klientem, dół 5 px
	var okr := Rect2(rel.call(w.ok_button), w.ok_button.size / s)
	var okw: float = ceilf(w.ok_button.get_theme_font("font").get_string_size(w.ok_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		w.ok_button.get_theme_font_size("font_size")).x / s) + 24.0
	check(absf(okr.end.x - (W - 16)) < 1.1 and absf(okr.end.y - (H - 13)) < 1.1 and absf(okr.size.x - okw) < 1.1,
		"%s: opcje – OK przy (W − 16, H − 13), szer. napis + 24 (%s)" % [tag, okr])
	var ap: Vector2 = rel.call(w.pages[1])
	ok = true
	k = 0
	for key in ["master_volume", "voice_volume", "sfx_volume", "footsteps_volume", "music_volume"]:
		var sb2: Control = w.sliders[key]
		ok = ok and near_v(rel.call(sb2) - ap, Vector2(4, 28 + 50 * k)) and absf(sb2.size.y / s - 18.0) < 0.6
		k += 1
	check(ok, "%s: opcje – suwaki dźwięku w (4, 28 + 50k), 18 px" % tag)
	var d: float = (H - 116) - 369.0
	var cbox: Control = w.win.find_child("ControlsBox", true, false)
	var cp: Vector2 = rel.call(w.pages[2])
	check(near_v(rel.call(cbox) - cp, Vector2(8, 42)) and absf(cbox.size.y / s - (146.0 + d)) < 1.1,
		"%s: opcje – ControlsBox w MW_Box (4, 38), wys. 146 + Δ (%s %s)" % [tag, rel.call(cbox) - cp, cbox.size.y / s])
	var rb: Control = w.win.find_child("ResetControlsButton", true, false)
	check(near_v(rel.call(rb) - cp, Vector2(4, 198 + d)), "%s: opcje – Reset Controls przy dolnej krawędzi (%s)" % [tag, rel.call(rb) - cp])
	check(near_v(rel.call(w.resolution_list) - rel.call(w.pages[3]), Vector2(4, 36)) and near_v(w.resolution_list.size / s, Vector2(195, 225)),
		"%s: opcje – lista rozdzielczości (0, 4, 195, 225) w stronie TabControlInner" % tag)
	# warstwy: MainMenu < Settings < Notification
	main.static_message_box("x")
	main.remove_static_message_box()
	check(w.layer > main.main_menu.layer and main.message_boxes.layer > w.layer and main.overlay().layer > w.layer,
		"%s: warstwy menu %d < opcje %d < komunikaty %d / napisy %d" % [tag, main.main_menu.layer, w.layer, main.message_boxes.layer, main.overlay().layer])
	w.close()
	main.close_main_menu()
	await _frames(1)
	# konsola: HBox wyszukiwania (1, 0) w kliencie, przyciski 28 × 28 co 4; historia od y = 30 klienta bez ramki;
	# wiersz poleceń: MW_Box 26 px przy dolnej krawędzi
	var c = main.console
	c.open()
	await _frames(3)
	var cr: Rect2 = c.win.get_global_rect()
	var crel := func(n: String) -> Rect2:
		var x: Control = c.win.find_child(n, true, false)
		return Rect2((x.global_position - cr.position) / s, x.size / s)
	var bar: Rect2 = crel.call("SearchBar")
	var prev: Rect2 = crel.call("button_Previous")
	var nxt: Rect2 = crel.call("button_Next")
	check(near_v(bar.position, Vector2(9, 28)) and absf(bar.size.y - 28) < 0.6 and absf(bar.end.x - (cr.size.x / s - 12)) < 1.1,
		"%s: konsola – pasek wyszukiwania (1, 0, szer. − 5, 28) w kliencie (%s)" % [tag, bar])
	check(near_v(prev.size, Vector2(28, 28)) and absf(nxt.position.x - prev.end.x - 4) < 0.6, "%s: konsola – przyciski 28 × 28 co 4 (%s %s)" % [tag, prev, nxt])
	var hist: Rect2 = crel.call("list_History")
	var cmd: Rect2 = crel.call("edit_Command")
	check(near_v(hist.position, Vector2(8, 58)) and c.win.find_child("HistoryFrame", true, false) == null,
		"%s: konsola – historia w (5, 30) klienta, bez ramki MW_Box (%s)" % [tag, hist.position])
	check(absf(cmd.size.y - 26) < 0.6 and absf(cmd.end.y - (cr.size.y / s - 8)) < 1.1, "%s: konsola – wiersz poleceń 26 px przy dole (%s)" % [tag, cmd])
	c.close()
	await _frames(1)
	# szybkie klawisze: każde pole z nakładką MW_Box_Overlay
	main.quick_keys.open()
	await _frames(2)
	var slots: Array = main.quick_keys.find_children("BoxOverlay", "Panel", true, false)
	check(slots.size() == 10, "%s: szybkie klawisze – 10 nakładek MW_Box_Overlay (%d)" % [tag, slots.size()])
	main.quick_keys.close()
	await _frames(1)
