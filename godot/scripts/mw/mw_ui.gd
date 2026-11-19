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
			ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			_font = ff
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
	var key := prefix + "|" + str(bg)
	if _themes.has(key):
		return _themes[key]
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
		st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		st.content_margin_left = lw + 3
		st.content_margin_right = rw + 3
		st.content_margin_top = th + 3
		st.content_margin_bottom = bh + 3
		sb = st
	_themes[key] = sb
	return sb

## Tło okien: czerń z przezroczystością OpenMW („menu transparency” 0,84).
const WINDOW_BG := Color(0, 0, 0, 0.84)

static func window_box() -> StyleBox:
	return _frame_box("menu_thick_border", WINDOW_BG)

## Skórka MW_DialogNoTransp (okna modalne: zapis/wczytanie, potwierdzenie) – nieprzezroczyste tło.
static func dialog_box_opaque() -> StyleBox:
	return _frame_box("menu_thick_border", Color(0, 0, 0, 1))

static func inner_box(bg := Color(0, 0, 0, 0.0)) -> StyleBox:
	return _frame_box("menu_thin_border", bg)

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
	var c := color(kind)
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
	for st_name in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		th.set_stylebox(st_name, "Button", button_box())
		th.set_stylebox(st_name, "OptionButton", button_box())
	th.set_stylebox("focus", "Button", empty)
	th.set_stylebox("panel", "ItemList", inner_box())
	th.set_stylebox("focus", "ItemList", empty)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(1, 1, 1, 0.08)
	th.set_stylebox("selected", "ItemList", sel)
	th.set_stylebox("selected_focus", "ItemList", sel)
	th.set_stylebox("hovered", "ItemList", sel)
	th.set_stylebox("normal", "LineEdit", inner_box(Color(0, 0, 0, 0.6)))
	th.set_stylebox("focus", "LineEdit", empty)
	th.set_stylebox("panel", "ScrollContainer", empty)
	var grab := StyleBoxFlat.new()
	grab.bg_color = normal.darkened(0.35)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.5)
	track.border_color = normal.darkened(0.6)
	track.set_border_width_all(1)
	for sb_cls in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", sb_cls, track)
		th.set_stylebox("grabber", sb_cls, grab)
		th.set_stylebox("grabber_highlight", sb_cls, grab)
		th.set_stylebox("grabber_pressed", sb_cls, grab)
	th.set_constant("separation", "VBoxContainer", roundi(2 * scale))
	th.set_constant("separation", "HBoxContainer", roundi(4 * scale))
	_themes[key] = th
	return th

## Etykieta nagłówka (FontColor_color_header).
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

## Ramka wewnętrzna (menu_thin_border) wokół kontrolki – zwraca opakowanie do wstawienia w miejsce kontrolki.
static func framed(c: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", inner_box())
	p.size_flags_horizontal = c.size_flags_horizontal
	p.size_flags_vertical = c.size_flags_vertical
	p.size_flags_stretch_ratio = c.size_flags_stretch_ratio
	p.add_child(c)
	return p
