extends RefCounted
## Wygląd interfejsu w stylu Morrowinda (etap 10) jak skórki OpenMW (files/data/mygui/openmw_*.skin.xml):
## ramki okien z tekstur gry gracza (textures/menu_thick_border_*, menu_thin_border_*, menu_button_frame_*,
## menu_head_block_* – z instalacji, konwerter je kopiuje), paski energii (menu_bar_gray barwione kolorami
## FontColor_color_health/magic/fatigue), kolory tekstu z Fallback „FontColor_*” (Morrowind.ini, domyślne OpenMW),
## czcionka MysticCards (domyślna OpenMW). Gdy tekstur brak (dane syntetyczne) – ramki rysowane kolorem.
## Ikony przedmiotów i efektów: icons/<ścieżka z rekordu>.png; tła ikon: textures/menu_icon[_magic][_equip|_barter].

const WeatherScript := preload("res://scripts/mw/mw_weather.gd")

static var data_root := ""
static var _fb = null                     # MWWeather (dostęp do fallbacków)
static var _tex := {}
static var _themes := {}
## Skala klasycznego interfejsu jak w OpenMW (WindowManager: mScalingFactor = [GUI] scaling factor × stosunek
## rozmiaru bufora do rozmiaru okna, czyli HiDPI). Układy w pikselach – niezależnie od rozdzielczości: większy ekran
## mieści więcej, elementy się nie powiększają. Ustawienie gry „gui_scaling_factor” (domyślnie 1,0).
static var gui_scaling := 1.0

static func ui_scale() -> float:
	return gui_scaling * maxf(1.0, DisplayServer.screen_get_scale())

## Warstwa ScalingLayer „JournalBooks” (openmw_layers.xml, Size 600 520): książki i zwoje skalowane tak, żeby obszar
## 600 × 520 mieścił się na ekranie – min(szerokość/600, wysokość/520), bez skali GUI.
static func book_scale(vp: Vector2) -> float:
	return minf(vp.x / 600.0, vp.y / 520.0)

## Lewy górny róg okna wyśrodkowanego na ScalingLayer „JournalBooks” (600 × 520): WindowBase::center liczy w
## jednostkach warstwy liczbami całkowitymi ((600 − szer.) / 2, (520 − wys.) / 2), a ProxyRenderTarget przenosi je na
## ekran: przesunięcie (ekran − 600 × skala) / 2 i skala ekran / int(ekran / skala) w każdej osi. Wcześniej środek
## liczony w pikselach – na 3440 × 1440 księga 1 px w prawo.
static func book_origin(vp: Vector2, size_units: Vector2) -> Vector2:
	var s := book_scale(vp)
	var view := Vector2(floorf(vp.x / s), floorf(vp.y / s))
	var px := Vector2(vp.x / maxf(view.x, 1.0), vp.y / maxf(view.y, 1.0))
	var off := (vp - Vector2(600.0, 520.0) * s) / 2.0
	var left := floorf((600.0 - size_units.x) / 2.0)
	var top := floorf((520.0 - size_units.y) / 2.0)
	return (off + Vector2(left * px.x, top * px.y)).floor()

static var _font: Font = null

static func setup(root: String) -> void:
	if root != data_root:
		data_root = root
		_tex.clear()
		_themes.clear()
		_fb = null

static func _fallbacks():
	if _fb == null:
		_fb = WeatherScript.new()
		_fb.load(data_root)
	return _fb

## Kolor z FontColor_color_<name> (np. „normal”, „normal_over”, „header”, „health”).
static func color(name: String) -> Color:
	var fb = _fallbacks()
	var k := "FontColor_color_" + name
	if not fb.fb.has(k):
		return Color(0.79, 0.65, 0.38)
	return fb.colour(k)

static func font() -> Font:
	if _font == null:
		var ff := FontFile.new()
		if ff.load_dynamic_font("res://fonts/MysticCards.ttf") == OK:
			# MysticCards.omwfont (OpenMW 0.51): Antialias false – glify jednobitowe z pełnym hintingiem FreeType
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NORMAL
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			# metryki linii jak MyGUI (Resolution 70: 16 × 70/72 px – wznoszenie 13, zstępowanie 3, linia 16 px);
			# Godot przy 16 px daje wznoszenie 14 i linię 17 – tekst w polach o stałej wysokości był 1–4 px za wysoko
			var fv := FontVariation.new()
			fv.base_font = ff
			fv.spacing_top = -1
			_font = fv
		else:
			_font = ThemeDB.fallback_font
	return _font

## Tekstura z danych gracza (ścieżka względna bez rozszerzenia albo z .dds/.tga) → Texture2D albo null.
static func texture(rel: String) -> Texture2D:
	if rel.is_empty():
		return null
	var k := rel.replace("\\", "/").to_lower().get_basename() + ".png"
	if _tex.has(k):
		return _tex[k]
	var t: Texture2D = null
	var p := data_root.path_join(k)
	if not data_root.is_empty() and FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_tex[k] = t
	return t

static func _image(rel: String) -> Image:
	var t := texture(rel)
	return t.get_image() if t != null else null

## Ikona przedmiotu/efektu z rekordu (ITEX/„icon”): icons/<ścieżka>.
static func icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return texture("icons/" + path.replace("\\", "/"))

## Tło ikony jak ItemWidget::setItem: menu_icon[_magic][_equip|_barter]; zwykły przedmiot bez stanu – brak tła.
static func icon_frame(magic: bool, state: String) -> Texture2D:
	var name := "textures/menu_icon" + ("_magic" if magic else "")
	if state == "equip":
		name += "_equip"
	elif state == "barter":
		name += "_barter"
	elif not magic:
		return null
	if _tex.has(name + "|42"):
		return _tex[name + "|42"]
	var t := texture(name)
	if t != null:
		# ItemWidget: tło używa części 42 × 42 obrazu 64 × 64 (inne rozmiary – proporcjonalnie)
		var a := AtlasTexture.new()
		a.atlas = t
		var k := t.get_width() / 64.0
		a.region = Rect2(0, 0, 42.0 * k, 42.0 * k)
		t = a
	_tex[name + "|42"] = t
	return t

## Ramka z 8 tekstur (narożniki i krawędzie) złożona w jeden obraz 9-częściowy → StyleBoxTexture.
## bg – wypełnienie środka (np. półprzezroczysta czerń okien OpenMW).
static func _frame_box(prefix: String, bg: Color, corner_suffix := "_corner") -> StyleBox:
	var key := prefix + "|" + str(bg) + ("" if corner_suffix == "_corner" else "|" + corner_suffix)
	if _themes.has(key):
		return _themes[key]
	var sb := _build_frame_box(prefix, bg, corner_suffix)
	_themes[key] = sb
	return sb

static func _build_frame_box(prefix: String, bg: Color, corner_suffix := "_corner") -> StyleBox:
	var names := {"t": "top", "b": "bottom", "l": "left", "r": "right",
		"tl": "top_left" + corner_suffix, "tr": "top_right" + corner_suffix,
		"bl": "bottom_left" + corner_suffix, "br": "bottom_right" + corner_suffix}
	var im := {}
	for k in names:
		var i := _image("textures/%s_%s" % [prefix, names[k]])
		if i == null:
			im = {}
			break
		i.convert(Image.FORMAT_RGBA8)
		im[k] = i
	var sb: StyleBox
	if im.is_empty():
		var f := StyleBoxFlat.new()
		f.bg_color = bg
		f.border_color = Color(0.55, 0.45, 0.26) if prefix.contains("thick") else Color(0.42, 0.34, 0.2)
		f.set_border_width_all(3 if prefix.contains("thick") else 2)
		f.set_content_margin_all(6 if prefix.contains("thick") else 4)
		sb = f
	else:
		var cw: int = maxi(im.tl.get_width(), im.bl.get_width())
		var ch: int = maxi(im.tl.get_height(), im.tr.get_height())
		var ew: int = maxi(1, im.t.get_width())
		var eh: int = maxi(1, im.l.get_height())
		var lw: int = im.l.get_width()
		var rw: int = im.r.get_width()
		var th: int = im.t.get_height()
		var bh: int = im.b.get_height()
		var W := cw * 2 + ew
		var H := ch * 2 + eh
		var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
		out.fill(bg)
		var put := func(src: Image, at: Vector2i) -> void:
			out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)
		put.call(im.t, Vector2i(cw, 0))
		put.call(im.b, Vector2i(cw, H - bh))
		put.call(im.l, Vector2i(0, ch))
		put.call(im.r, Vector2i(W - rw, ch))
		put.call(im.tl, Vector2i(0, 0))
		put.call(im.tr, Vector2i(W - im.tr.get_width(), 0))
		put.call(im.bl, Vector2i(0, H - im.bl.get_height()))
		put.call(im.br, Vector2i(W - im.br.get_width(), H - im.br.get_height()))
		var st := StyleBoxTexture.new()
		st.texture = ImageTexture.create_from_image(out)
		st.texture_margin_left = cw
		st.texture_margin_right = cw
		st.texture_margin_top = ch
		st.texture_margin_bottom = ch
		st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		st.content_margin_left = lw + 3
		st.content_margin_right = rw + 3
		st.content_margin_top = th + 3
		st.content_margin_bottom = bh + 3
		sb = st
	return sb

## Tło okien: czerń z przezroczystością OpenMW ([GUI] menu transparency, domyślnie 0,84; zmiana w ustawieniach –
## set_window_alpha, jak WindowManager::setMenuTransparency – od razu we wszystkich oknach).
static var WINDOW_BG := Color(0, 0, 0, 0.84)

static func set_window_alpha(a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	if is_equal_approx(a, WINDOW_BG.a):
		return
	var old := WINDOW_BG
	WINDOW_BG = Color(0, 0, 0, a)
	var tag := "|" + str(old)
	for key in _themes.keys():
		var k := String(key)
		if not k.ends_with(tag):
			continue
		var parts := k.split("|")
		var fresh := _build_frame_box(parts[0], WINDOW_BG, parts[2] if parts.size() > 2 else "_corner")
		var sb: StyleBox = _themes[key]
		if sb is StyleBoxTexture and fresh is StyleBoxTexture:
			(sb as StyleBoxTexture).texture = (fresh as StyleBoxTexture).texture
		elif sb is StyleBoxFlat and fresh is StyleBoxFlat:
			(sb as StyleBoxFlat).bg_color = WINDOW_BG
		_themes.erase(key)
		_themes[parts[0] + "|" + str(WINDOW_BG) + ("|" + parts[2] if parts.size() > 2 else "")] = sb
	for key in _themes.keys():               # kopie skórki MW_Window (window_box_mw) – od nowa przy następnym użyciu
		if String(key).begins_with("mw_window|"):
			var sb2: StyleBox = _themes[key]
			var base: StyleBox = window_box()
			if sb2 is StyleBoxTexture and base is StyleBoxTexture:
				(sb2 as StyleBoxTexture).texture = (base as StyleBoxTexture).texture
			elif sb2 is StyleBoxFlat:
				(sb2 as StyleBoxFlat).bg_color = WINDOW_BG

static func window_box() -> StyleBox:
	return _frame_box("menu_thick_border", WINDOW_BG)

## Skórka MW_DialogNoTransp (okna modalne: zapis/wczytanie, potwierdzenie) – nieprzezroczyste tło.
static func dialog_box_opaque() -> StyleBox:
	return _frame_box("menu_thick_border", Color(0, 0, 0, 1))

## Wewnętrzna ramka skórki MW_Window (menu_thick_border bez tła) – rysowana od (4, 24) do (szer. − 4, wys. − 4).
static func inner_frame_thick() -> StyleBox:
	return _frame_box("menu_thick_border", Color(0, 0, 0, 0))

static func inner_box(bg := Color(0, 0, 0, 0.0)) -> StyleBox:
	return _frame_box("menu_thin_border", bg)

## Wiersz HBox z AutoSizedButton (components/widgets/box.cpp): przycisk ma tekst + (24, 8) = 24 px wysokości
## i jest wyśrodkowany w pionie w wierszu (HBox::align: top = (wys. − h) / 2) – w wierszach 28 px 2 px od góry.
static func auto_button_row(row: Container, s: float) -> void:
	for c in row.get_children():
		if c is Button and not (c is CheckBox):
			(c as Control).custom_minimum_size.y = 24.0 * s
			(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER

static func button_box() -> StyleBox:
	return _frame_box("menu_button_frame", Color(0, 0, 0, 0.0))

## Pasek tytułu okna (menu_head_block_*): złożony jak ramka, środek – menu_head_block_middle.
static func head_box() -> StyleBox:
	if _themes.has("head"):
		return _themes["head"]
	var sb := _frame_box("menu_head_block", Color(0, 0, 0, 0.0))
	var mid := texture("textures/menu_head_block_middle")
	if sb is StyleBoxTexture and mid != null:
		# środek: kafel z menu_head_block_middle w miejscu przezroczystości
		var st := sb as StyleBoxTexture
		var img: Image = st.texture.get_image()
		var m := mid.get_image()
		m.convert(Image.FORMAT_RGBA8)
		var x0 := int(st.texture_margin_left)
		var y0 := int(st.texture_margin_top)
		var w := img.get_width() - 2 * x0
		var h := img.get_height() - 2 * y0
		if w > 0 and h > 0:
			m.resize(w, h)
			img.blend_rect(m, Rect2i(0, 0, w, h), Vector2i(x0, y0))
			var st2 := st.duplicate() as StyleBoxTexture
			st2.texture = ImageTexture.create_from_image(img)
			sb = st2
	_themes["head"] = sb
	return sb

## Pasek energii (MW_Progress_*): wypełnienie menu_bar_gray w kolorze FontColor_color_<kind>, ramka cienka.
## Wypełnienie paska (MW_BarTrack_*, openmw_hud_energybar.skin.xml): menu_bar_gray – tylko obszar 16 × 8 (paski
## zdrowia/magii/kondycji) albo 16 × 2 (stan broni, szansa czaru), rozciągnięty i barwiony kolorem FontColor_color_<kind>;
## rysowany w obszarze „Client” wsuniętym o 2 px w ramkę (inset × skala).
static func bar_fill(kind: String, inset := 0.0) -> StyleBox:
	var key := "bar|%s|%.2f" % [kind, inset]
	if _themes.has(key):
		return _themes[key]
	var c := Color(1.0, 0.729, 0.0) if kind == "enemy" else color(kind)     # MW_BarTrack_Yellow: Colour 1 0.729 0
	var t := texture("textures/menu_bar_gray")
	var sb: StyleBox
	if t != null:
		var st := StyleBoxTexture.new()
		st.texture = t
		st.region_rect = Rect2(0, 0, 16, 2 if kind in ["weapon_fill", "magic_fill"] else 8)
		st.modulate_color = c
		sb = st
	else:
		var f := StyleBoxFlat.new()
		f.bg_color = c
		sb = f
	sb.expand_margin_left = -inset
	sb.expand_margin_right = -inset
	sb.expand_margin_top = -inset
	sb.expand_margin_bottom = -inset
	_themes[key] = sb
	return sb

## Pasek energii (MW_EnergyBar_*): ramka MW_Box (menu_thin_border, 2 px), czarne tło (BlackBG), wypełnienie wsunięte
## o 2 px (Client 2 2 w–4 h–4).
static func progress_bar(kind: String, scale := 1.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12 * scale)
	pb.add_theme_stylebox_override("fill", bar_fill(kind, 2.0 * scale))
	pb.add_theme_stylebox_override("background", bar_back())
	return pb

## Tło paska: ramka MW_Box z czarnym wnętrzem, bez marginesów zawartości (pasek 36 × 6 jak stan broni w HUD).
static func bar_back() -> StyleBox:
	if _themes.has("bar_back"):
		return _themes["bar_back"]
	var sb: StyleBox = inner_box(Color(0, 0, 0, 1)).duplicate()
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_themes["bar_back"] = sb
	return sb

## Motyw Godota dla okien w stylu Morrowinda (rozmiar czcionki wg skali interfejsu).
static func theme(scale := 1.0) -> Theme:
	var key := "theme|%.2f" % scale
	if _themes.has(key):
		return _themes[key]
	var th := Theme.new()
	th.default_font = font()
	th.default_font_size = roundi(16 * scale)
	var normal := color("normal")
	var over := color("normal_over")
	var pressed := color("normal_pressed")
	var disabled := color("disabled")
	for cls in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "ItemList", "RichTextLabel", "TooltipLabel", "CheckButton", "SpinBox", "Tree", "TabBar"]:
		th.set_color("font_color", cls, normal)
	th.set_color("default_color", "RichTextLabel", normal)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		th.set_color("font_hover_color", cls, over)
		th.set_color("font_pressed_color", cls, pressed)
		th.set_color("font_focus_color", cls, over)
		th.set_color("font_hover_pressed_color", cls, pressed)
		th.set_color("font_disabled_color", cls, disabled)
	th.set_color("font_selected_color", "ItemList", pressed)
	th.set_color("font_hovered_color", "ItemList", over)
	var empty := StyleBoxEmpty.new()
	th.set_stylebox("panel", "PanelContainer", window_box())
	th.set_stylebox("panel", "Panel", window_box())
	th.set_stylebox("panel", "TooltipPanel", inner_box(WINDOW_BG))
	th.set_color("font_color", "TooltipLabel", normal)
	# MW_Button: ramka 4 px, przycisk 23 px przy czcionce 16 (layouty OpenMW), AutoSizedButton: tekst + 24 px
	var bb: StyleBox = button_box().duplicate()
	var fh := float(font().get_height(roundi(16 * scale)))
	bb.content_margin_top = floorf((23.0 * scale - fh) / 2.0)
	bb.content_margin_bottom = ceilf((23.0 * scale - fh) / 2.0)
	bb.content_margin_left = 12.0 * scale
	bb.content_margin_right = 12.0 * scale
	for st_name in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		th.set_stylebox(st_name, "Button", bb)
	th.set_stylebox("focus", "Button", empty)
	# MW_ComboBox (openmw_resources.xml): MW_Box, tekst SandText od (6, 3) do lewej, strzałka MW_ArrowDown
	# (omw_menu_scroll_down) 14 × 11 przy prawej krawędzi (7 px)
	var cb: StyleBox = inner_box().duplicate()
	cb.content_margin_left = 6.0 * scale
	cb.content_margin_right = 7.0 * scale
	cb.content_margin_top = floorf((24.0 * scale - fh) / 2.0)
	cb.content_margin_bottom = ceilf((24.0 * scale - fh) / 2.0)
	for st_name in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		th.set_stylebox(st_name, "OptionButton", cb)
	th.set_stylebox("focus", "OptionButton", empty)
	th.set_constant("arrow_margin", "OptionButton", roundi(7.0 * scale))
	th.set_constant("h_separation", "OptionButton", roundi(4.0 * scale))
	var adown := _omw_image("omw_menu_scroll_down")
	if adown != null:
		adown.resize(maxi(1, roundi(14 * scale)), maxi(1, roundi(11 * scale)), Image.INTERPOLATE_NEAREST)
		th.set_icon("arrow", "OptionButton", ImageTexture.create_from_image(adown))
	th.set_stylebox("panel", "ItemList", inner_box())
	th.set_stylebox("focus", "ItemList", empty)
	# MWList (components/widgets/list.cpp): wiersz = wysokość tekstu + 2 px (18 przy czcionce 16)
	th.set_constant("v_separation", "ItemList", roundi(maxf(0.0, 18.0 * scale - float(font().get_height(roundi(16 * scale))))))
	th.set_constant("line_separation", "ItemList", 0)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(1, 1, 1, 0.08)
	th.set_stylebox("selected", "ItemList", sel)
	th.set_stylebox("selected_focus", "ItemList", sel)
	th.set_stylebox("hovered", "ItemList", sel)
	# MW_TextBoxEditWithBorder: pole 23 px (FilterEdit w ekwipunku i handlu) – marginesy jak przycisku
	var le: StyleBox = inner_box(Color(0, 0, 0, 0.6)).duplicate()
	le.content_margin_top = floorf((23.0 * scale - fh) / 2.0)
	le.content_margin_bottom = ceilf((23.0 * scale - fh) / 2.0)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("read_only", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", empty)
	th.set_stylebox("panel", "ScrollContainer", empty)
	_apply_scroll_theme(th, scale)
	th.set_constant("separation", "VBoxContainer", roundi(2 * scale))
	th.set_constant("separation", "HBoxContainer", roundi(4 * scale))
	_themes[key] = th
	return th

# --- paski przewijania: MW_VScroll / MW_HScroll (files/data/mygui/openmw_list.skin.xml) -----------------
# Pasek 14 px: strzałki w polach MW_Box 14 × 15 (strzałka 10 × 10 od 2, 2), tło MW_Box 3 px od strzałek,
# suwak MW_ScrollTrackV – kafelkowana omw_menu_scroll_center_v, 9 px od x = 2, zakres TrackRangeMargins 20/19,
# MinTrackSize 14; WheelPage = Page = 36; MoveToClick – klik w tło przenosi suwak.
const SCROLL_W := 14.0
const SCROLL_PAGE := 36.0

## Ramka MW_Box (menu_thin_border_*) dowolnego rozmiaru jako obraz (narożniki, krawędzie kafelkowane).
static func _box_image(w: int, h: int) -> Image:
	var out := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var names := {"t": "top", "b": "bottom", "l": "left", "r": "right", "tl": "top_left_corner",
		"tr": "top_right_corner", "bl": "bottom_left_corner", "br": "bottom_right_corner"}
	var im := {}
	for k in names:
		var i := _image("textures/menu_thin_border_" + names[k])
		if i == null:
			return out
		i = i.duplicate()
		i.convert(Image.FORMAT_RGBA8)
		im[k] = i
	var put := func(src: Image, at: Vector2i) -> void:
		out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)
	var tl: Image = im.tl
	var x := tl.get_width()
	while x < w - (im.tr as Image).get_width():
		put.call(im.t, Vector2i(x, 0))
		put.call(im.b, Vector2i(x, h - (im.b as Image).get_height()))
		x += maxi(1, (im.t as Image).get_width())
	var y := tl.get_height()
	while y < h - (im.bl as Image).get_height():
		put.call(im.l, Vector2i(0, y))
		put.call(im.r, Vector2i(w - (im.r as Image).get_width(), y))
		y += maxi(1, (im.l as Image).get_height())
	put.call(im.tl, Vector2i(0, 0))
	put.call(im.tr, Vector2i(w - (im.tr as Image).get_width(), 0))
	put.call(im.bl, Vector2i(0, h - (im.bl as Image).get_height()))
	put.call(im.br, Vector2i(w - (im.br as Image).get_width(), h - (im.br as Image).get_height()))
	return out

static func _omw_image(name: String) -> Image:
	var p := ProjectSettings.globalize_path("res://ui/omw/%s.png" % name)
	var img := Image.load_from_file(p) if FileAccess.file_exists(p) else null
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img

## Pole strzałki: MW_Box 14 × 15 (dla poziomego 15 × 14) ze strzałką 10 × 10 od (2, 2), przeskalowane o s.
static func _arrow_icon(dir: String, s: float) -> Texture2D:
	var horiz := dir in ["left", "right"]
	var w := 15 if horiz else 14
	var h := 14 if horiz else 15
	var img := _box_image(w, h)
	var arrow := _omw_image("omw_menu_scroll_" + dir)
	if arrow != null:
		arrow.resize(10, 10, Image.INTERPOLATE_BILINEAR)
		img.blend_rect(arrow, Rect2i(0, 0, 10, 10), Vector2i(2, 2))
	if not is_equal_approx(s, 1.0):
		img.resize(maxi(1, roundi(w * s)), maxi(1, roundi(h * s)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)

static func _apply_scroll_theme(th: Theme, s: float) -> void:
	var box := inner_box()
	for vertical in [true, false]:
		var cls := "VScrollBar" if vertical else "HScrollBar"
		# tło (Background MW_Box): 3 px od pól strzałek; marginesy treści wyznaczają zakres suwaka i jego 9 px
		var bg: StyleBox = box.duplicate()
		var along_a := 3.0 * s
		if vertical:
			bg.expand_margin_top = -along_a
			bg.expand_margin_bottom = -along_a
			bg.content_margin_top = 5.0 * s      # TrackRangeMargins 20 − pole strzałki 15
			bg.content_margin_bottom = 4.0 * s   # 19 − 15
			bg.content_margin_left = 2.0 * s
			bg.content_margin_right = 3.0 * s
		else:
			bg.expand_margin_left = -along_a
			bg.expand_margin_right = -along_a
			bg.content_margin_left = 5.0 * s
			bg.content_margin_right = 4.0 * s
			bg.content_margin_top = 2.0 * s
			bg.content_margin_bottom = 3.0 * s
		var grab := StyleBoxTexture.new()
		var timg := _omw_image("omw_menu_scroll_center_" + ("v" if vertical else "h"))
		if timg != null:
			if not is_equal_approx(s, 1.0):
				timg.resize(maxi(1, roundi(timg.get_width() * s)), maxi(1, roundi(timg.get_height() * s)), Image.INTERPOLATE_BILINEAR)
			grab.texture = ImageTexture.create_from_image(timg)
		grab.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		grab.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		# suwak 9 px (od 2 px), minimum 14 px (MinTrackSize)
		if vertical:
			grab.expand_margin_left = -2.0 * s
			grab.expand_margin_right = -3.0 * s
			grab.content_margin_top = 7.0 * s
			grab.content_margin_bottom = 7.0 * s
		else:
			grab.expand_margin_top = -2.0 * s
			grab.expand_margin_bottom = -3.0 * s
			grab.content_margin_left = 7.0 * s
			grab.content_margin_right = 7.0 * s
		th.set_stylebox("scroll", cls, bg)
		th.set_stylebox("scroll_focus", cls, bg)
		for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
			th.set_stylebox(st, cls, grab)
		var dec := _arrow_icon("up" if vertical else "left", s)
		var inc := _arrow_icon("down" if vertical else "right", s)
		for suf in ["", "_highlight", "_pressed"]:
			th.set_icon("decrement" + suf, cls, dec)
			th.set_icon("increment" + suf, cls, inc)

## ScrollContainer w oknach: krok kółka i strzałek 36 px (WheelPage, Page) × skala, MoveToClick na tle paska.
static func setup_scroll(sc: ScrollContainer, s := -1.0) -> void:
	if sc.has_meta("mw_scroll"):
		return
	sc.set_meta("mw_scroll", true)
	if s <= 0.0:
		s = ui_scale()
	sc.scroll_vertical_custom_step = SCROLL_PAGE * s
	sc.scroll_horizontal_custom_step = SCROLL_PAGE * s
	for bar in [sc.get_v_scroll_bar(), sc.get_h_scroll_bar()]:
		setup_scroll_bar(bar, s)
	sc.gui_input.connect(_scroll_wheel.bind(sc, s))

## Skórka MW_ScrollView (openmw_scroll.skin.xml): VScroll w (szer. − 18, 3) – pasek 4 px od prawej krawędzi
## widoku (Godot kładzie go przy samej krawędzi). Górne 3 px paska – bez odwzorowania (Godot przesunąłby też treść).
static func mw_scroll_view(sc: ScrollContainer, s := -1.0) -> void:
	if s <= 0.0:
		s = ui_scale()
	var sb := StyleBoxEmpty.new()
	sb.content_margin_right = 4.0 * s
	sc.add_theme_stylebox_override("panel", sb)

## WheelPage 36: kółko myszy przesuwa o 36 px × skala (Godot domyślnie o 1/8 strony).
static func _scroll_wheel(e: InputEvent, sc: ScrollContainer, s: float) -> void:
	if not (e is InputEventMouseButton) or not e.pressed:
		return
	var mb := e as InputEventMouseButton
	var f := mb.factor if mb.factor > 0.0 else 1.0
	var step := SCROLL_PAGE * s * f
	var vb := sc.get_v_scroll_bar()
	var hb := sc.get_h_scroll_bar()
	var vertical_ok := vb != null and vb.max_value - vb.page > vb.min_value and sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			var sign := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if vertical_ok and not mb.shift_pressed:
				vb.value += sign * step
			elif hb != null:
				hb.value += sign * step
			else:
				return
		MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
			if hb == null:
				return
			hb.value += (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT else 1.0) * step
		_:
			return
	sc.accept_event()

static func setup_scroll_bar(bar: ScrollBar, s := -1.0) -> void:
	if bar == null or bar.has_meta("mw_scroll"):
		return
	bar.set_meta("mw_scroll", true)
	if s <= 0.0:
		s = ui_scale()
	bar.custom_step = SCROLL_PAGE * s
	bar.gui_input.connect(_scroll_move_to_click.bind(bar))

## MyGUI ScrollBar z MoveToClick: kliknięcie w pustą część paska ustawia środek suwaka w miejscu kliknięcia
## (zamiast przewijania o stronę), dalsze przeciąganie przesuwa suwak.
static func _scroll_move_to_click(e: InputEvent, bar: ScrollBar) -> void:
	if not (e is InputEventMouseButton) or (e as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT or not e.pressed:
		return
	var vertical := bar is VScrollBar
	var dec: Texture2D = bar.get_theme_icon("decrement")
	var inc: Texture2D = bar.get_theme_icon("increment")
	var bg: StyleBox = bar.get_theme_stylebox("scroll")
	var pos: float = e.position.y if vertical else e.position.x
	var total: float = bar.size.y if vertical else bar.size.x
	var a: float = (dec.get_height() if vertical else dec.get_width()) + (bg.content_margin_top if vertical else bg.content_margin_left)
	var b: float = total - (inc.get_height() if vertical else inc.get_width()) - (bg.content_margin_bottom if vertical else bg.content_margin_right)
	if pos < (dec.get_height() if vertical else dec.get_width()) or pos > total - (inc.get_height() if vertical else inc.get_width()):
		return                          # strzałki – zwykły krok
	var span := b - a
	var rng: float = bar.max_value - bar.min_value
	if span <= 0.0 or rng <= 0.0:
		return
	var grab_len := clampf(span * bar.page / rng, 14.0, span)
	var cur_start := a + (bar.value - bar.min_value) / maxf(rng - bar.page, 0.0001) * (span - grab_len)
	if pos >= cur_start and pos <= cur_start + grab_len:
		return                          # na suwaku – zwykłe przeciąganie
	var t := clampf((pos - a - grab_len * 0.5) / maxf(span - grab_len, 0.0001), 0.0, 1.0)
	bar.value = bar.min_value + t * (rng - bar.page)
	bar.accept_event()

## Przycisk pinezki okna (skórki PinUp / PinDown, 19 × 19: ramka menu_rightbutton{up,down}_* i środek 15 × 15
## od 2, 2). Zwraca kontrolkę; stan zmienia set_pin_skin.
static func pin_button(s: float, pinned: bool) -> Control:
	var b := Control.new()
	b.name = "Pin"
	b.custom_minimum_size = Vector2(19, 19) * s
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(frame)
	var c := TextureRect.new()
	c.name = "Center"
	c.position = Vector2(2, 2) * s
	c.size = Vector2(15, 15) * s
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_SCALE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	set_pin_skin(b, pinned)
	return b

static func set_pin_skin(b: Control, pinned: bool) -> void:
	var prefix := "menu_rightbutton" + ("down" if pinned else "up")
	(b.get_node("Frame") as Panel).add_theme_stylebox_override("panel", _frame_box(prefix, Color(0, 0, 0, 0), ""))
	(b.get_node("Center") as TextureRect).texture = texture("textures/%s_center" % prefix)
	b.set_meta("pinned", pinned)

## Etykieta nagłówka (FontColor_color_header).
## Skórki tekstu z openmw_text.skin.xml: NormalText, SandText, SandTextRight, SandBrightText, SandTextButton –
## TextAlign „Left/Right Bottom” – linia przy dolnej krawędzi pola. Przesunięcie −1 skórki SandText przy
## wyrównaniu do dołu nie zmienia położenia linii (zmierzone na zrzutach OpenMW 0.51); przy wyśrodkowaniu w pionie
## (TextAlign „Left”/„Center” w układzie) – tak, uwzględniają je okna wołające.
static func text_skin(l: Label, skin: String, _s := -1.0) -> Label:
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if skin == "SandTextRight":
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

static func header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color("header"))
	return l

## Pasek tytułu okna – skórka MW_Caption i WindowCaption::align (OpenMW): pasek 20 px, tekst (SandText) w przerwie
## o szerokości tekstu + 24 px, po obu stronach równe bloki HB_ALL (menu_head_block). Zwraca kontener „Head”
## (HBox: lewy blok, etykieta z marginesem 12 px, prawy blok); s – skala GUI.
static func make_head(title: Label, s := -1.0) -> HBoxContainer:
	if s <= 0.0:
		s = ui_scale()
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 0)
	head.custom_minimum_size.y = 20 * s
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	for side in 2:
		var bar := Panel.new()
		bar.name = "Left" if side == 0 else "Right"
		bar.add_theme_stylebox_override("panel", head_box())
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(4, 20) * s
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		if side == 1:
			var m := MarginContainer.new()
			m.name = "Client"
			m.add_theme_constant_override("margin_left", roundi(12 * s))
			m.add_theme_constant_override("margin_right", roundi(12 * s))
			m.mouse_filter = Control.MOUSE_FILTER_PASS
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title.add_theme_color_override("font_color", color("normal"))
			title.mouse_filter = Control.MOUSE_FILTER_PASS
			m.add_child(title)
			head.add_child(m)
		head.add_child(bar)
	return head

## Skórka MW_Window (openmw_windows.skin.xml, okna z paskiem tytułu): zewnętrzna ramka menu_thick_border, pasek
## tytułu Caption w (4, 4, szer. − 8, 20), wewnętrzna ramka menu_thick_border od (4, 24) do (szer. − 4, wys. − 4),
## obszar Client w (8, 28, szer. − 16, wys. − 36). Styl panelu ma marginesy Client (8, 4, 8, 8); pasek tytułu siedzi
## w opakowaniu wysuniętym o 4 px na boki (jak Caption szerszy od Client), a pod nim 4 px wewnętrznej ramki.
static func window_box_mw(s := 1.0) -> StyleBox:
	var key := "mw_window|%.2f" % s
	if _themes.has(key):
		return _themes[key]
	var sb: StyleBox = window_box().duplicate()
	sb.content_margin_left = 8 * s
	sb.content_margin_right = 8 * s
	sb.content_margin_top = 4 * s
	sb.content_margin_bottom = 8 * s
	_themes[key] = sb
	return sb

## Pasek tytułu okna MW_Window dodany do kolumny „box” (dziecko panelu okna); zwraca pasek (HBoxContainer) jak
## make_head. Ustawia panelowi skórkę MW_Window i rysuje jej wewnętrzną ramkę.
static func add_head(box: VBoxContainer, title: Label, s := -1.0) -> HBoxContainer:
	if s <= 0.0:
		s = ui_scale()
	var head := make_head(title, s)
	var area := Control.new()
	area.name = "CaptionArea"
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 20 px paska + 4 px wewnętrznej ramki; odstęp kolumny (separation) dolicza się osobno
	var sep: int = box.get_theme_constant("separation") if box.has_theme_constant_override("separation") else roundi(2 * s)
	area.custom_minimum_size.y = maxf(20.0 * s, 24.0 * s - sep)
	area.custom_minimum_size.x = head.get_combined_minimum_size().x - 8.0 * s
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = -4.0 * s
	head.offset_right = 4.0 * s
	head.offset_top = 0
	head.offset_bottom = 20.0 * s
	area.add_child(head)
	box.add_child(area)
	var panel := box.get_parent() as Control
	if panel != null:
		panel.add_theme_stylebox_override("panel", window_box_mw(s))
		var inner: StyleBox = inner_frame_thick()
		panel.draw.connect(func():
			panel.draw_style_box(inner, Rect2(Vector2(4, 24) * s, panel.size - Vector2(8, 28) * s)))
	return head

## Ramka wewnętrzna (menu_thin_border) wokół kontrolki – zwraca opakowanie do wstawienia w miejsce kontrolki.
static func framed(c: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", inner_box())
	p.size_flags_horizontal = c.size_flags_horizontal
	p.size_flags_vertical = c.size_flags_vertical
	p.size_flags_stretch_ratio = c.size_flags_stretch_ratio
	p.add_child(c)
	return p
