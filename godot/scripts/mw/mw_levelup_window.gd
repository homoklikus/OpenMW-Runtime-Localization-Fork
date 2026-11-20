extends CanvasLayer
## Okno awansu jak OpenMW 0.51 (MWGui::LevelupDialog, files/data/mygui/openmw_levelup_dialog.layout):
## VBox w skórce MW_Dialog z AutoResize, Padding 10, Spacing 8 (rozmiar okna z zawartości, na środku):
##   MW_Box 391 × 198 z obrazem klasy (4, 4, 383, 190) – getLevelupClassImage z przyrostów specjalizacji;
##   LevelText „sLevelUpMenu1 N”; LevelDescription (AutoSizedEditBox 391, zawijany) – fallback
##   Level_Up_LevelN albo Level_Up_Default; Coins (150 × 16, HStretch) – monety tx_goldicon co 33 px,
##   wyśrodkowane; AssignWidget (ScrollView 420 × 84): 8 atrybutów w 2 kolumnach (x 32 / 218, wiersz 20 px)
##   – mnożnik „xN” (SandTextVCenter 100 × 20) i HBox (x + 20, 200 × 20) z przyciskiem SandTextButton
##   (TextPadding 0 0) i wartością SandText; HBox ze Spacerem i przyciskiem OK (Interface:OK).
## Kliknięcie atrybutu: ponownie – zdjęcie monety, przy komplecie – zamiana ostatniego; moneta przy
## przycisku (x − 22 − 20 przy mnożniku). OK: za mało – sNotifyMessage36; inaczej atrybuty + mnożnik (do 100)
## i NpcStats::levelUp (mw_character.gd: level_up). Muzyka triumfu przy otwarciu.

const UI := preload("res://scripts/mw/mw_ui.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const Box := preload("res://scripts/mw/mw_box_layout.gd")

const COLUMN_OFFSETS := [32, 218]
const MAX_COINS := 3

var main
var character
var ui = null
var win: Control = null
var spent: Array = []                 # mSpentAttributes (indeksy atrybutów)
var coin_count := MAX_COINS
var level_text: Label = null
var description: Label = null
var class_image: TextureRect = null
var class_image_id := ""
var ok_button: Button = null
var widgets: Array = []               # [{"mult": Label, "button": Button, "value": Label, "hbox": Control}]
var coins: Array = []                 # TextureRect × 3
var _coin_box: Control = null
var _assign: Control = null
var _s := 1.0
var _desc_text := ""

signal closed

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func _st() -> Dictionary:
	return main.player_stats()

func is_open() -> bool:
	return visible

## getLevelupClassImage (przyrosty umiejętności walki / magii / skradania od ostatniego awansu).
static func class_image_for(combat: int, magic: int, stealth: int) -> String:
	var ret := "acrobat"
	var total := combat + magic + stealth
	if total == 0:
		return ret
	var cf := int(float(combat) / total * 10.0)
	var mf := int(float(magic) / total * 10.0)
	var sf := int(float(stealth) / total * 10.0)
	if cf > 7:
		ret = "warrior"
	elif mf > 7:
		ret = "mage"
	elif sf > 7:
		ret = "thief"
	match cf:
		7:
			ret = "warrior"
		6:
			if sf == 1:
				ret = "barbarian"
			elif sf == 3:
				ret = "crusader"
			else:
				ret = "knight"
		5:
			if sf == 3:
				ret = "scout"
			else:
				ret = "archer"
		4:
			ret = "rogue"
		_:
			pass
	match mf:
		7:
			ret = "mage"
		6:
			if cf == 2:
				ret = "sorcerer"
			elif combat == 3:                  # jak w OpenMW: liczba przyrostów, nie ułamek
				ret = "healer"
			else:
				ret = "battlemage"
		5:
			ret = "witchhunter"
		4:
			ret = "spellsword"
		_:
			pass
	match sf:
		7:
			ret = "thief"
		6:
			if mf == 1:
				ret = "agent"
			elif magic == 3:
				ret = "assassin"
			else:
				ret = "acrobat"
		5:
			if magic == 3:
				ret = "monk"
			else:
				ret = "pilgrim"
		3:
			if mf == 3:
				ret = "bard"
		_:
			pass
	return ret

func _build() -> void:
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = ui.modal(self, 448, 400, false)
	win.name = "LevelupDialog"
	var c: Control = win.get_meta("client")
	var img_box: Control = ui.box(c, 0, 0, 391, 198)
	class_image = TextureRect.new()
	class_image.name = "ClassImage"
	class_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	class_image.stretch_mode = TextureRect.STRETCH_SCALE
	ui.at(class_image, img_box, 4, 4, 383, 190)
	level_text = Label.new()
	level_text.name = "LevelText"
	level_text.add_theme_color_override("font_color", UI.color("normal"))
	level_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(level_text)
	description = Label.new()
	description.name = "LevelDescription"
	description.add_theme_color_override("font_color", UI.color("normal"))
	# wysokość wiersza MyGUI = 16 px (domyślna wysokość czcionki), niezależnie od metryk TTF
	description.add_theme_constant_override("line_spacing", roundi(16 * _s - UI.font().get_height(roundi(16 * _s))))
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	c.add_child(description)
	_coin_box = Control.new()
	_coin_box.name = "Coins"
	_coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_coin_box)
	_assign = Control.new()
	_assign.name = "AssignWidget"
	_assign.clip_contents = true
	_assign.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(_assign)
	ok_button = ui.button(L10n.ctx_text("Interface", "OK", "OK"), ok_clicked)     # sDone tylko w trybie kontrolera
	ok_button.name = "OkButton"
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(ok_button)
	c.add_child(row)
	# atrybuty: kolumny po ceil(8 / 2) = 4
	widgets = []
	var per_col := 4
	for i in 8:
		var off: int = COLUMN_OFFSETS[i / per_col]
		var r := i % per_col
		var mult: Label = ui.label(_assign, off, 20 * r, 100, 20, "")
		mult.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var hb := Control.new()
		hb.mouse_filter = Control.MOUSE_FILTER_PASS
		ui.at(hb, _assign, off + 20, 20 * r, 200, 20)
		var b := Button.new()
		b.name = "Attribute%d" % i
		b.text = ui.attr_name(i)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for stn in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", UI.color("normal"))
		b.add_theme_color_override("font_hover_color", UI.color("normal_over"))
		b.add_theme_color_override("font_pressed_color", UI.color("normal_pressed"))
		b.add_theme_color_override("font_hover_pressed_color", UI.color("normal_pressed"))
		b.add_theme_color_override("font_disabled_color", UI.color("disabled"))
		var k := i
		b.pressed.connect(func(): attribute_clicked(k))
		hb.add_child(b)
		var v := Label.new()
		v.add_theme_color_override("font_color", UI.color("normal"))
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(v)
		widgets.append({"mult": mult, "button": b, "value": v, "hbox": hb})
	coins = []
	for i in MAX_COINS:
		var ci := TextureRect.new()
		ci.texture = UI.icon("tx_goldicon.dds")
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ci.size = Vector2(16, 16) * _s
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_coin_box.add_child(ci)
		coins.append(ci)

func _hbox(w: Dictionary) -> Dictionary:
	return {"type": "hbox", "control": w.hbox, "children": [{"type": "button", "control": w.button, "text_padding": Vector2.ZERO},
		{"type": "text", "control": w.value}]}

## VBox::align z AutoResize: rozmiar okna z zawartości, potem rozmieszczenie (wyśrodkowanie w poziomie).
func relayout() -> void:
	var bl := Box.new(_s)
	for w in widgets:
		bl.place(_hbox(w), Rect2((w.hbox as Control).position / _s, Vector2(200, 20)))
	# AutoSizedEditBox (MultiLine, WordWrap): wiersze jak MyGUI::TextView, wysokość = wiersze × 16
	var lines: PackedStringArray = bl.wrap_lines(_desc_text, 391) if not _desc_text.is_empty() else PackedStringArray()
	description.text = "\n".join(lines)
	var desc_h := 16.0 * lines.size()
	var c: Control = win.get_meta("client")
	var img_box: Control = class_image.get_parent()
	var vb := {"type": "vbox", "padding": 10, "spacing": 8, "children": [
		{"type": "widget", "control": img_box, "size": Vector2(391, 198)},
		{"type": "text", "control": level_text},
		{"type": "widget", "control": description, "size": Vector2(391, desc_h), "auto": true},
		{"type": "widget", "control": _coin_box, "size": Vector2(150, 16), "hstretch": true},
		{"type": "widget", "control": _assign, "size": Vector2(420, 84)},
		{"type": "hbox", "control": ok_button.get_parent(), "hstretch": true, "children": [{"type": "spacer"},
			{"type": "button", "control": ok_button}]}]}
	var tot: Vector2 = bl.totals(vb)
	var size := tot + Vector2(20, 20)
	# center() w onOpen widzi jeszcze wysokość opisu 0 (rozmiar tekstu EditBox liczony przy odświeżeniu widoku),
	# a AutoResize powiększa potem okno w dół – górna krawędź jak dla okna bez opisu
	ui.resize(win, size.x + 8, size.y + 8 - desc_h)
	win.size = Vector2(size.x + 8, size.y + 8) * _s
	(win.get_meta("client") as Control).size = size * _s
	bl.place(vb, Rect2(Vector2.ZERO, size))
	_layout_coins()

## LevelupDialog::onOpen.
func open() -> void:
	_s = UI.ui_scale()
	ui = CU.new(main, _s)
	_build()
	var st := _st()
	var si: Array = st.get("spec_increases", [0, 0, 0])
	class_image_id = class_image_for(int(si[0]), int(si[1]), int(si[2]))
	var tex := UI.texture("textures/levelup/" + class_image_id)
	if tex == null:
		tex = UI.texture("textures/levelup/warrior")
	class_image.texture = tex
	var level := int(st.get("level", 1)) + 1
	level_text.text = "%s %d" % [_t("sLevelUpMenu1", "You have reached Level"), level]
	var fb: Dictionary = UI._fallbacks().fb
	var d := String(fb.get("Level_Up_Level%d" % level, ""))
	if d.is_empty():
		d = String(fb.get("Level_Up_Default", ""))
	_desc_text = d
	var available := 0
	for i in 8:
		var w: Dictionary = widgets[i]
		var base := float(st.attributes[i])
		if base < 100.0:
			(w.button as Button).disabled = false
			available += 1
			var m: int = mini(character.levelup_multiplier(st, i), int(100.0 - base))
			(w.mult as Label).text = "" if m <= 1 else "x%d" % m
		else:
			(w.button as Button).disabled = true
			(w.mult as Label).text = ""
	coin_count = mini(MAX_COINS, available)
	spent = []
	_set_values()
	visible = true
	relayout()
	main.gui.push("levelup", [self], func(): pass)
	if main.get("music") != null and main.music != null and main.music.enabled:
		main.music.play_triumph()

func close() -> void:
	visible = false
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = null
	main.gui.remove("levelup")
	closed.emit()

## setAttributeValues: baza (+ mnożnik dla wybranych), najwyżej 100.
func _set_values() -> void:
	var st := _st()
	for i in 8:
		var val := int(float(st.attributes[i]))
		if i in spent:
			val += character.levelup_multiplier(st, i)
		(widgets[i].value as Label).text = str(mini(val, 100))

## resetCoins + assignCoins.
func _layout_coins() -> void:
	var cw := _coin_box.size.x / _s
	var cur_x := floorf(cw / 2.0) - floorf((33 * (coin_count - 1) + 16 * coin_count) / 2.0)
	for i in MAX_COINS:
		var ci: TextureRect = coins[i]
		if ci.get_parent() != _coin_box:
			ci.get_parent().remove_child(ci)
			_coin_box.add_child(ci)
		ci.visible = i < coin_count
		if i < coin_count:
			ci.position = Vector2(cur_x, 0) * _s
			cur_x += 16 + 33
	for i in spent.size():
		var ci: TextureRect = coins[i]
		_coin_box.remove_child(ci)
		_assign.add_child(ci)
		var w: Dictionary = widgets[int(spent[i])]
		var xdiff := 0 if (w.mult as Label).text.is_empty() else 20
		var hp: Vector2 = (w.hbox as Control).position / _s
		ci.position = Vector2(hp.x - 22 - xdiff, hp.y + floorf((20 - 16) / 2.0)) * _s

func attribute_clicked(i: int) -> void:
	if i in spent:
		spent.erase(i)
	elif spent.size() == coin_count:
		spent[coin_count - 1] = i
	else:
		spent.append(i)
	_layout_coins()
	_set_values()

## onOkButtonClicked.
func ok_clicked() -> bool:
	if spent.size() < coin_count:
		main._toast(_t("sNotifyMessage36", "You must select more attributes."))
		return false
	character.level_up(_st(), spent)
	close()
	return true
