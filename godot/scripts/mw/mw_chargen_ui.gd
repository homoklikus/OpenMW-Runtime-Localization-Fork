extends RefCounted
## Elementy okien tworzenia postaci odwzorowujące układy MyGUI OpenMW (files/data/mygui/openmw_chargen_*.layout):
## pozycje i rozmiary z plików układu (piksele przy skali interfejsu 1,0) mnożone przez skalę interfejsu, skórki
## MW_Dialog / MW_DialogNoTransp (ramka okna, obszar klienta odsunięty o 4 px), MW_Box (cienka ramka),
## MW_List (lista z linią MW_ListLine: kolor zwykły, podświetlony, zaznaczony = „active”), HeaderText, SandText,
## SandBrightText, SandTextButton, MW_StatName/MW_StatNameValue, MW_Button (AutoSizedButton: tekst + 24 × 8 px),
## HBox przycisków (odstęp 4 px, wyrównanie do prawej przez Spacer), strzałki MW_ArrowLeft/Right
## (tekstury OpenMW omw_menu_scroll_*), MW_EffectImage (ikona 16 × 16 w (4, 4), tekst od 24 px, wysokość 24).

const UI := preload("res://scripts/mw/mw_ui.gd")

const ATTR_GMST := ["sAttributeStrength", "sAttributeIntelligence", "sAttributeWillpower", "sAttributeAgility",
	"sAttributeSpeed", "sAttributeEndurance", "sAttributePersonality", "sAttributeLuck"]
const ATTR_PL := ["Siła", "Inteligencja", "Siła woli", "Zręczność", "Szybkość", "Wytrzymałość", "Osobowość", "Szczęście"]
const SKILL_PL := {"block": "Blok", "armorer": "Płatnerstwo", "mediumarmor": "Średni pancerz",
	"heavyarmor": "Ciężki pancerz", "bluntweapon": "Broń obuchowa", "longblade": "Długie ostrza", "axe": "Topory",
	"spear": "Włócznie", "athletics": "Atletyka", "enchant": "Zaklinanie", "destruction": "Zniszczenie",
	"alteration": "Przemiana", "illusion": "Iluzja", "conjuration": "Przywołanie", "mysticism": "Mistycyzm",
	"restoration": "Odnowienie", "alchemy": "Alchemia", "unarmored": "Walka bez pancerza", "security": "Zabezpieczenia",
	"sneak": "Skradanie się", "acrobatics": "Akrobatyka", "lightarmor": "Lekki pancerz", "shortblade": "Krótkie ostrza",
	"marksman": "Strzelectwo", "mercantile": "Handel", "speechcraft": "Retoryka", "handtohand": "Walka wręcz"}
const SPEC_GMST := ["sSpecializationCombat", "sSpecializationMagic", "sSpecializationStealth"]
const SPEC_PL := ["Walka", "Magia", "Skradanie"]

var sc := 1.0                 # skala interfejsu (wysokość okna / 720, co najmniej 1 – jak inne okna)
var main = null               # main.gd (GMST przez dialogue.gmst_text, lokalizacja nazw rekordów)
var font_size := 16

func _init(game_main = null, scale := 1.0) -> void:
	main = game_main
	sc = scale
	font_size = roundi(16 * sc)

# --- teksty ---------------------------------------------------------------------------------------------

func t(gm: String, def: String) -> String:
	if main != null and main.get("dialogue") != null:
		var v: String = main.dialogue.gmst_text(gm, def)
		return v if not v.is_empty() else def
	return def

func attr_name(i: int) -> String:
	return t(ATTR_GMST[i], ATTR_PL[i]) if i >= 0 and i < 8 else ""

func skill_ids() -> Array:
	if main != null and main.get("character") != null:
		return main.character.skill_names()
	return []

## Nazwa umiejętności jak ESM::Skill::mName (GMST sSkill<Nazwa>).
func skill_name(i: int) -> String:
	var ids := skill_ids()
	if i < 0 or i >= ids.size():
		return ""
	var sid := String(ids[i])
	return t("sSkill" + sid.capitalize().replace(" ", ""), String(SKILL_PL.get(sid, sid.capitalize())))

func spec_name(i: int) -> String:
	return t(SPEC_GMST[i], SPEC_PL[i]) if i >= 0 and i < 3 else ""

## Nazwa rekordu z lokalizacją (FNAM), jak w pozostałych oknach.
func rec_name(file: String, rtype: String, id: String) -> String:
	if main == null or main.get("character") == null:
		return id
	var r: Dictionary = main.character.records.record(file, id)
	var fb := String(r.get("name", id))
	var loc = main.get("loc")
	if loc != null and loc.has_method("is_active") and loc.is_active():
		return loc.plain(loc.key(rtype, id, "FNAM"), fb)
	return fb

func text_width(s: String) -> float:
	return UI.font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func line_h() -> float:
	return (16 + 2) * sc          # Settings::gui().mFontSize + 2

# --- okna -----------------------------------------------------------------------------------------------

## Warstwa modalna na całe okno (blokuje kliknięcia poza oknem jak WindowModal) z oknem w środku.
## Zwraca okno (Control); obszar klienta – okno.get_meta("client").
func modal(parent: Node, w: float, h: float, opaque := false) -> Control:
	var layer := Control.new()
	layer.name = "Modal"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.theme = UI.theme(sc)
	parent.add_child(layer)
	var win := Control.new()
	win.name = "Window"
	win.size = Vector2(w, h) * sc
	layer.add_child(win)
	var bg := Panel.new()
	bg.name = "Frame"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UI.dialog_box_opaque() if opaque else UI.window_box())
	win.add_child(bg)
	var client := Control.new()
	client.name = "Client"
	client.position = Vector2(4, 4) * sc
	client.size = Vector2(w - 8, h - 8) * sc
	win.add_child(client)
	win.set_meta("client", client)
	win.set_meta("layer", layer)
	center(win)
	return win

## WindowBase::center – środek ekranu (zaokrąglony w dół).
func center(win: Control) -> void:
	var vp := win.get_viewport_rect().size if win.is_inside_tree() else Vector2(1280, 720)
	win.position = ((vp - win.size) / 2.0).floor()

func resize(win: Control, w: float, h: float) -> void:
	win.size = Vector2(w, h) * sc
	var client: Control = win.get_meta("client")
	client.size = Vector2(w - 8, h - 8) * sc
	center(win)

static func close(win: Control) -> void:
	if win != null and is_instance_valid(win):
		var layer: Control = win.get_meta("layer")
		layer.queue_free()

## Umieszcza kontrolkę w rodzicu w położeniu z pliku układu.
func at(c: Control, parent: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y) * sc
	c.size = Vector2(w, h) * sc
	parent.add_child(c)
	return c

## Pusty kontener (Widget skin="") – układ podrzędny.
func group(parent: Control, x: float, y: float, w: float, h: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return at(c, parent, x, y, w, h)

## MW_Box: cienka ramka (menu_thin_border).
func box(parent: Control, x: float, y: float, w: float, h: float) -> Control:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", UI.inner_box())
	return at(p, parent, x, y, w, h)

## Etykiety: kind = "header" (HeaderText/SandBrightText/NormalText – kolor nagłówka), "sand" (SandText),
## "right" (SandTextRight). Domyślnie wyrównanie do lewej i do dołu jak skórki tekstu OpenMW.
func label(parent: Control, x: float, y: float, w: float, h: float, text: String, kind := "sand",
		halign := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if kind == "right" else halign
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.add_theme_color_override("font_color", UI.color("header") if kind == "header" else UI.color("normal"))
	l.add_theme_constant_override("line_spacing", 0)
	at(l, parent, x, y, w, h)
	return l

## Tekst wielowierszowy z zawijaniem (AutoSizedEditBox/TextBox z WordWrap).
func wrap_label(parent: Control, x: float, y: float, w: float, text: String, kind := "sand",
		halign := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = halign
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_color_override("font_color", UI.color("header") if kind == "header" else UI.color("normal"))
	l.add_theme_constant_override("line_spacing", 0)
	l.position = Vector2(x, y) * sc
	l.custom_minimum_size = Vector2(w * sc, 0)
	l.size = Vector2(w * sc, 0)
	parent.add_child(l)
	return l

## Wysokość tekstu zawiniętego do szerokości w (piksele układu).
func wrapped_height(text: String, w: float) -> float:
	if text.is_empty():
		return 0.0
	var f := UI.font()
	var sz := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w * sc, font_size,
		-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	return sz.y / sc

## Przycisk MW_Button (AutoSizedButton): szerokość = tekst + 24, wysokość = wiersz + 8 (bez skalowania wysokości wiersza).
func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("h_separation", 0)
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var sb: StyleBox = UI.button_box().duplicate()
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	b.size = Vector2(text_width(text) + 24 * sc, 24 * sc)
	return b

## HBox z przyciskami po prawej (Spacer + AutoSizedButton, odstęp 4) w prostokącie układu; zwraca przyciski.
func button_row(parent: Control, x: float, y: float, w: float, h: float, buttons: Array, align_right := true) -> Array:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	at(row, parent, x, y, w, h)
	var total := 0.0
	for b in buttons:
		total += (b as Button).size.x
	total += 4 * sc * maxi(0, buttons.size() - 1)
	var cx := (w * sc - total) if align_right else 0.0
	for b in buttons:
		var bb := b as Button
		bb.position = Vector2(cx, floorf((h * sc - bb.size.y) / 2.0))
		row.add_child(bb)
		cx += bb.size.x + 4 * sc
	return buttons

## Przycisk tekstowy SandTextButton / MW_StatNameButton: bez ramki, kolory normal / normal_over / normal_pressed.
func text_button(parent: Control, x: float, y: float, w: float, h: float, text: String, cb: Callable,
		halign := HORIZONTAL_ALIGNMENT_LEFT) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = halign
	b.clip_text = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_color_override("font_color", UI.color("normal"))
	b.add_theme_color_override("font_hover_color", UI.color("normal_over"))
	b.add_theme_color_override("font_pressed_color", UI.color("normal_pressed"))
	b.add_theme_color_override("font_hover_pressed_color", UI.color("normal_pressed"))
	b.add_theme_color_override("font_focus_color", UI.color("normal"))
	b.pressed.connect(cb)
	return at(b, parent, x, y, w, h) as Button

## MW_StatNameValue: nazwa po lewej, wartość po prawej (kolumna 32 px, stany kolorów increased/decreased).
func stat_row(parent: Control, x: float, y: float, w: float, name: String, value: String, state := "normal",
		tip := "") -> Control:
	var g := group(parent, x, y, w, 18)
	if not tip.is_empty():
		g.tooltip_text = tip
		g.mouse_filter = Control.MOUSE_FILTER_STOP
	var a := label(g, 0, 0, w - 32, 18, name)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := label(g, w - 32, 0, 32, 18, value, "right")
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.clip_text = false
	if state == "increased":
		b.add_theme_color_override("font_color", UI.color("positive"))
	elif state == "decreased":
		b.add_theme_color_override("font_color", UI.color("negative"))
	return g

## Lista MW_List (ItemList z ramką MW_Box i kolorami MW_ListLine).
func list(parent: Control, x: float, y: float, w: float, h: float) -> ItemList:
	var l := ItemList.new()
	l.focus_mode = Control.FOCUS_ALL
	l.select_mode = ItemList.SELECT_SINGLE
	l.allow_reselect = true
	l.add_theme_stylebox_override("panel", UI.inner_box())
	var empty := StyleBoxEmpty.new()
	for st in ["focus", "selected", "selected_focus", "hovered", "hovered_selected", "hovered_selected_focus", "cursor", "cursor_unfocused"]:
		l.add_theme_stylebox_override(st, empty)
	l.add_theme_color_override("font_color", UI.color("normal"))
	l.add_theme_color_override("font_hovered_color", UI.color("normal_over"))
	l.add_theme_color_override("font_selected_color", UI.color("active"))
	l.add_theme_color_override("font_hovered_selected_color", UI.color("active_over"))
	l.add_theme_constant_override("v_separation", roundi(maxf(0.0, line_h() - UI.font().get_height(font_size))))
	l.add_theme_constant_override("line_separation", 0)
	l.add_theme_constant_override("h_separation", 0)
	l.add_theme_color_override("guide_color", Color(0, 0, 0, 0))
	at(l, parent, x, y, w, h)
	style_vscroll(l.get_v_scroll_bar())
	return l

## Pasek przewijania MW_VScroll: strzałki w górę/w dół (tekstury OpenMW), tor w ramce MW_Box, suwak.
func style_vscroll(sb: ScrollBar) -> void:
	if sb == null:
		return
	sb.add_theme_stylebox_override("scroll", UI.inner_box(Color(0, 0, 0, 0)))
	sb.add_theme_stylebox_override("scroll_focus", UI.inner_box(Color(0, 0, 0, 0)))
	var g := StyleBoxFlat.new()
	g.bg_color = UI.color("normal").darkened(0.1)
	g.content_margin_top = 7 * sc
	g.content_margin_bottom = 7 * sc
	g.content_margin_left = 7 * sc
	g.content_margin_right = 7 * sc
	g.set_expand_margin_all(-2 * sc)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		sb.add_theme_stylebox_override(k, g)
	var vertical := sb is VScrollBar
	for pair in [["decrement", "up" if vertical else "left"], ["increment", "down" if vertical else "right"]]:
		var tex := scaled_arrow(pair[1], 14)
		sb.add_theme_icon_override(pair[0], tex)
		sb.add_theme_icon_override(pair[0] + "_highlight", tex)
		sb.add_theme_icon_override(pair[0] + "_pressed", tex)
	sb.custom_minimum_size = Vector2(14 * sc, 0) if vertical else Vector2(0, 14 * sc)

func scaled_arrow(dir: String, px: float) -> Texture2D:
	var t := arrow_texture(dir)
	if t == null:
		return null
	var img := t.get_image()
	img.resize(maxi(1, roundi(px * sc)), maxi(1, roundi(px * sc)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)

## ImageBox wewnątrz MW_Box (ramka x,y,w,h; obraz odsunięty o 2 px).
func image_box(parent: Control, x: float, y: float, w: float, h: float) -> TextureRect:
	box(parent, x, y, w, h)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(tr, parent, x + 2, y + 2, w - 4, h - 4)
	return tr

static var _arrows := {}

static func arrow_texture(dir: String) -> Texture2D:
	if _arrows.has(dir):
		return _arrows[dir]
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://ui/omw/omw_menu_scroll_%s.png" % dir))
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	_arrows[dir] = t
	return t

## MW_ComboBox (openmw_resources.xml): MW_Box 100×26, tekst SandText „Left VCenter” od (6,3),
## przycisk MW_ArrowDown 14×11 przy prawej krawędzi (79,7 z 100), lista MW_PopupListNoTransp.
func style_combo(ob: OptionButton) -> void:
	ob.focus_mode = Control.FOCUS_NONE
	ob.flat = false
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		var sb: StyleBox = UI.inner_box().duplicate()
		sb.content_margin_left = 6 * sc
		sb.content_margin_top = 3 * sc
		sb.content_margin_bottom = 3 * sc
		sb.content_margin_right = 23 * sc
		ob.add_theme_stylebox_override(st, sb if st != "focus" else StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		ob.add_theme_color_override(k, UI.color("normal"))
	var a := arrow_texture("down")
	if a != null:
		var img := a.get_image()
		img.resize(maxi(1, roundi(14 * sc)), maxi(1, roundi(11 * sc)), Image.INTERPOLATE_BILINEAR)
		ob.add_theme_icon_override("arrow", ImageTexture.create_from_image(img))
	ob.add_theme_constant_override("arrow_margin", roundi(7 * sc))
	var pm := ob.get_popup()
	var pb: StyleBox = UI.inner_box(Color(0, 0, 0, 1)).duplicate()
	pm.add_theme_stylebox_override("panel", pb)
	pm.add_theme_color_override("font_color", UI.color("normal"))
	pm.add_theme_color_override("font_hover_color", UI.color("normal_over"))
	pm.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	if UI.font() != null:
		pm.add_theme_font_override("font", UI.font())
		ob.add_theme_font_override("font", UI.font())
	ob.add_theme_font_size_override("font_size", font_size)
	pm.add_theme_font_size_override("font_size", font_size)

## Przycisk strzałki MW_ArrowLeft/Right (tekstura OpenMW, rozciągnięta do prostokąta).
func arrow(parent: Control, x: float, y: float, w: float, h: float, dir: String, cb: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = arrow_texture(dir)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	at(b, parent, x, y, w, h)
	return b

## Obszar przewijany (MW_ScrollView): zwraca płótno, na którym elementy umieszcza się absolutnie (współrzędne
## układu); po wypełnieniu wywołaj finish_canvas(płótno, wysokość).
func scroll_view(parent: Control, x: float, y: float, w: float, h: float) -> Control:
	var sv := ScrollContainer.new()
	sv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.mouse_filter = Control.MOUSE_FILTER_PASS
	at(sv, parent, x, y, w, h)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.custom_minimum_size = Vector2((w - 14) * sc, h * sc)
	sv.add_child(canvas)
	style_vscroll(sv.get_v_scroll_bar())
	return canvas

func finish_canvas(canvas: Control, height: float) -> void:
	var sv := canvas.get_parent() as ScrollContainer
	canvas.custom_minimum_size = Vector2(canvas.custom_minimum_size.x, maxf(height * sc, sv.size.y if sv != null else 0.0))
	if sv != null:
		sv.scroll_vertical = 0

## MW_EffectImage: ikona efektu 16 × 16 w (4, 4), tekst od 24 px; wysokość 24.
func effect_line(parent: Control, x: float, y: float, w: float, icon: String, text: String) -> Control:
	var g := group(parent, x, y, w, 24)
	var tr := TextureRect.new()
	tr.texture = UI.icon(icon) if not icon.is_empty() else null
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	at(tr, g, 4, 4, 16, 16)
	var l := label(g, 24, 0, w - 24, 20, text)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = false
	return g

# --- opis efektu czaru (MWSpellEffect::updateWidgets) ---------------------------------------------------

const ABSORB_ATTR := 85
const ABSORB_SKILL := 89
const DAMAGE_ATTR := 22
const DAMAGE_SKILL := 26
const DRAIN_ATTR := 17
const DRAIN_SKILL := 21
const FORTIFY_ATTR := 79
const FORTIFY_SKILL := 83
const RESTORE_ATTR := 74
const RESTORE_SKILL := 78

## getMagnitudeDisplayType (components/esm3/loadmgef.cpp).
static func magnitude_display(index: int, no_magnitude: bool) -> String:
	if no_magnitude:
		return "none"
	if index == 84:
		return "times_int"
	if index == 59 or (index >= 64 and index <= 66):
		return "feet"
	if index == 118 or index == 119:
		return "level"
	if (index >= 28 and index <= 36) or (index >= 90 and index <= 99) or index in [40, 47, 57, 68]:
		return "percent"
	return "points"

## Tekst linii efektu: nazwa (getMagicEffectString), wielkość, czas (bez – dla efektów stałych), obszar, zasięg.
func effect_text(e: Dictionary, constant: bool) -> String:
	var id := int(e.get("effect", -1))
	var mg: Dictionary = main.character.records.record("magiceffect", str(id)) if main != null else {}
	var name := String(mg.get("name", str(id)))
	var line := t("sEffect" + name.replace(" ", ""), name)
	var ta := bool(mg.get("target_attribute", false)) and int(e.get("attribute", -1)) >= 0
	var tsk := bool(mg.get("target_skill", false)) and int(e.get("skill", -1)) >= 0
	if ta or tsk:
		var pre := ""
		if id in [ABSORB_ATTR, ABSORB_SKILL]:
			pre = t("sAbsorb", "Pochłonięcie")
		elif id in [DAMAGE_ATTR, DAMAGE_SKILL]:
			pre = t("sDamage", "Uszkodzenie")
		elif id in [DRAIN_ATTR, DRAIN_SKILL]:
			pre = t("sDrain", "Osłabienie")
		elif id in [FORTIFY_ATTR, FORTIFY_SKILL]:
			pre = t("sFortify", "Wzmocnienie")
		elif id in [RESTORE_ATTR, RESTORE_SKILL]:
			pre = t("sRestore", "Przywrócenie")
		if not pre.is_empty():
			line = pre
		line += " " + (skill_name(int(e.skill)) if tsk else attr_name(int(e.attribute)))
	var mn := int(e.get("min", 0))
	var mx := int(e.get("max", 0))
	var to := " " + t("sTo", "do") + " "
	if (mn != 0 or mx != 0):
		var disp := magnitude_display(id, bool(mg.get("no_magnitude", false)))
		if disp == "times_int":
			line += " %.1f" % (mn / 10.0)
			if mn != mx:
				line += to + "%.1f" % (mx / 10.0)
			line += t("sXTimesINT", "x INT")
		elif disp != "none":
			line += " " + str(mn)
			if mn != mx:
				line += to + str(mx)
			if disp == "percent":
				line += t("spercent", "%")
			elif disp == "feet":
				line += " " + t("sfeet", "stóp")
			elif disp == "level":
				line += " " + (t("sLevel", "poziom") if mn == mx and absi(mn) == 1 else t("sLevels", "poziomów"))
			else:
				line += " " + (t("spoint", "pkt") if mn == mx and absi(mn) == 1 else t("spoints", "pkt"))
	if not constant:
		var dur := int(e.get("duration", 0))
		if not bool(mg.get("applied_once", false)):
			dur = maxi(1, dur)
		if dur > 0 and not bool(mg.get("no_duration", false)):
			line += " " + t("sfor", "przez") + " " + str(dur) + " " + (t("ssecond", "s") if dur == 1 else t("sseconds", "s"))
		if int(e.get("area", 0)) > 0:
			line += " " + t("sin", "w") + " " + str(int(e.area)) + " " + t("sfootarea", "stóp obszaru")
		line += " " + t("sonword", "na") + " "
		match int(e.get("range", 0)):
			0: line += t("sRangeSelf", "siebie")
			1: line += t("sRangeTouch", "dotyk")
			_: line += t("sRangeTarget", "cel")
	return line
