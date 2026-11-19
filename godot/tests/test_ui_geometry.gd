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
		main.state.player.erase("ui_windows")      # bez układu zapamiętanego przy innej rozdzielczości
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
