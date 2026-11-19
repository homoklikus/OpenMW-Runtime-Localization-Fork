extends PanelContainer
## MWList (components/widgets/list.cpp) w skórce MW_SimpleList: ramka MW_Box, obszar Client od 3 px, przewijana
## kolumna przycisków MW_ListLine (tekst od x = 2, wyśrodkowany w pionie, zawijany) o wysokości tekstu + 2 px;
## pozycja może mieć odstęp pionowy (verticalPadding – nad i pod), separator to MW_HLine o wysokości 18 px
## (linia menu_thin_border_top 2 px przy dolnej krawędzi skórki 10 px, czyli 8 px od góry pozycji).
## Podzbiór API ItemList używany przez okna: clear, add_item, add_separator, item_count, set_item_disabled,
## get_item_text, deselect_all, sygnał item_clicked(indeks).

const UI := preload("res://scripts/mw/mw_ui.gd")

signal item_clicked(index: int)

var item_count: int:
	get:
		return _items.size()

var _s := 1.0
var _scroll: ScrollContainer
var _col: VBoxContainer
var _items: Array = []          # [{"text", "button" | null}]

func _init(s := -1.0) -> void:
	_s = s if s > 0.0 else UI.ui_scale()
	var sb: StyleBox = UI.inner_box().duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, 3 * _s)
	add_theme_stylebox_override("panel", sb)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 0)
	_scroll.add_child(_col)

func clear() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_items = []

func add_item(text: String, vertical_padding := 0) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", roundi(vertical_padding * _s))
	m.add_theme_constant_override("margin_bottom", roundi(vertical_padding * _s))
	# szerokość pozycji: obszar przewijania − 2 px
	m.add_theme_constant_override("margin_right", roundi(2 * _s))
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var eb := StyleBoxEmpty.new()
	eb.content_margin_left = 2 * _s
	eb.content_margin_top = 1 * _s
	eb.content_margin_bottom = 1 * _s
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, eb)
	b.add_theme_color_override("font_color", UI.color("normal"))
	b.add_theme_color_override("font_hover_color", UI.color("normal_over"))
	b.add_theme_color_override("font_pressed_color", UI.color("normal_pressed"))
	b.add_theme_color_override("font_disabled_color", UI.color("disabled"))
	var i := _items.size()
	b.pressed.connect(func(): item_clicked.emit(i))
	m.add_child(b)
	_col.add_child(m)
	_items.append({"text": text, "button": b})

func add_separator() -> void:
	_col.add_child(hline(_s))
	_items.append({"text": "", "button": null})

func set_item_disabled(i: int, disabled: bool) -> void:
	var b = _items[i].button if i >= 0 and i < _items.size() else null
	if b != null:
		(b as Button).disabled = disabled

func is_item_disabled(i: int) -> bool:
	var b = _items[i].button if i >= 0 and i < _items.size() else null
	return b == null or (b as Button).disabled

func get_item_text(i: int) -> String:
	return String(_items[i].text) if i >= 0 and i < _items.size() else ""

func deselect_all() -> void:
	pass

## MW_HLine: menu_thin_border_top (2 px) od x = left do right px przed prawą krawędzią, 8 px od góry pozycji 18 px.

static func hline(s: float, left := 2.0, right := 4.0) -> Control:
	var line := _HLine.new()
	line.s = s
	line.left = left
	line.right = right
	line.custom_minimum_size.y = 18 * s
	return line

class _HLine extends Control:
	var s := 1.0
	var left := 2.0                  # x linii w pozycji (MWList: 2, lista umiejętności: 10)
	var right := 4.0                 # odstęp od prawej krawędzi
	func _draw() -> void:
		var t: Texture2D = preload("res://scripts/mw/mw_ui.gd").texture("textures/menu_thin_border_top")
		var r := Rect2(Vector2(left * s, 8 * s), Vector2(maxf(0.0, size.x - (left + right) * s), 2 * s))
		if t != null:                      # SubSkin: górne 2 px tekstury, rozciągnięte w poziomie
			draw_texture_rect_region(t, r, Rect2(0, 0, t.get_width(), mini(2, t.get_height())))
		else:
			draw_rect(r, preload("res://scripts/mw/mw_ui.gd").color("normal") * Color(1, 1, 1, 0.6))
