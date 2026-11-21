extends CanvasLayer
## MessageBoxManager z OpenMW 0.51 (apps/openmw/mwgui/messagebox.cpp):
##  - MessageBox (openmw_messagebox.layout): VBox w skórce HUD_Box z AutoResize, Padding 10, tekst
##    AutoSizedEditBox szerokości 300, wyśrodkowany, zawijany; okno na środku w poziomie, 48 px nad dolną
##    krawędzią; najstarszy na dole, kolejne wyżej co wysokość + 4; najwyżej 3 (czwarty usuwa najstarszy);
##    czas życia = liczba znaków × fMessageTimePerChar (liczony także w trybie GUI).
##  - InteractiveMessageBox (openmw_interactive_messagebox[_notransp].layout, MW_Dialog / MW_DialogNoTransp
##    w trybie GUI): tekst zawijany do 400, przyciski MW_Button (tekst + 2 × 12, + 2 × 4), w jednym wierszu,
##    gdy suma szerokości przycisków < szerokość tekstu, inaczej jeden pod drugim; odstępy 10 px;
##    położenie wg wzorów OpenMW (w układzie pionowym środek liczony bez ramek – jak w OpenMW).

const UI := preload("res://scripts/mw/mw_ui.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const Box := preload("res://scripts/mw/mw_box_layout.gd")

const BOTTOM_PADDING := 48
const NEXT_BOX_PADDING := 4
const MAX_BOXES := 3

var main
var boxes: Array = []            # [{"panel": Control, "time": float, "max": float, "text": String, "h": int}]
var interactive: Control = null  # okno InteractiveMessageBox (warstwa modalna)
var interactive_buttons: Array = []
var _s := 1.0

func _ready() -> void:
	layer = 40                       # warstwa Notification nad oknami
	process_mode = Node.PROCESS_MODE_ALWAYS

func _time_per_char() -> float:
	if main != null and main.get("dialogue") != null and main.dialogue != null:
		return float(main.dialogue._gmst("fMessageTimePerChar", 0.1))
	return 0.1

func count() -> int:
	return boxes.size()

func texts() -> Array:
	return boxes.map(func(b): return String(b.text))

## createMessageBox(message, stat): stały komunikat (staticMessageBox) – bez czasu życia, jeden naraz, usuwany
## przez remove_static (removeStaticMessageBox).
func create(message: String, static_box := false) -> void:
	if static_box:
		remove_static()
	_s = UI.ui_scale()
	var bl := Box.new(_s)
	var lines := bl.wrap_lines(message, 300)
	var text_h := 16 * lines.size()
	var size := Vector2(300 + 20, text_h + 20)
	var p := Panel.new()
	p.name = "MessageBox"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UI.inner_box(UI.WINDOW_BG))      # HUD_Box: BlackBG + MW_Box
	p.size = size * _s
	var l := Label.new()
	l.name = "message"
	l.text = "\n".join(lines)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.add_theme_color_override("font_color", UI.color("normal"))
	l.add_theme_constant_override("line_spacing", roundi(16 * _s - UI.font().get_height(roundi(16 * _s))))
	l.position = Vector2(10, 10) * _s
	l.size = Vector2(300, text_h) * _s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	add_child(p)
	boxes.append({"panel": p, "time": 0.0, "max": INF if static_box else message.length() * _time_per_char(),
		"text": message, "h": int(size.y), "static": static_box})
	if boxes.size() > MAX_BOXES:
		var old: Dictionary = boxes.pop_front()
		(old.panel as Node).queue_free()
	_update_positions()

## MessageBox::update – od dołu ekranu, najstarszy najniżej.
func _update_positions() -> void:
	var vp := get_viewport().get_visible_rect().size / _s
	var height := 0
	for b in boxes:
		var p: Control = b.panel
		var sz := p.size / _s
		p.position = Vector2(floorf((vp.x - sz.x) / 2.0), vp.y - sz.y - height - BOTTOM_PADDING).floor() * _s
		height += int(b.h) + NEXT_BOX_PADDING

func _process(delta: float) -> void:
	if boxes.is_empty():
		return
	var changed := false
	for b in boxes.duplicate():
		b.time = float(b.time) + delta
		if float(b.time) >= float(b.max):
			boxes.erase(b)
			(b.panel as Node).queue_free()
			changed = true
	if changed:
		_update_positions()

func remove_static() -> void:
	for b in boxes.duplicate():
		if bool(b.get("static", false)):
			boxes.erase(b)
			(b.panel as Node).queue_free()
	_update_positions()

func has_static() -> bool:
	return boxes.any(func(b): return bool(b.get("static", false)))

func clear() -> void:
	for b in boxes:
		(b.panel as Node).queue_free()
	boxes = []
	close_interactive()

# --- InteractiveMessageBox --------------------------------------------------------------------------------

func is_interactive() -> bool:
	return interactive != null and is_instance_valid(interactive)

func close_interactive() -> void:
	if is_interactive():
		CU.close(interactive)
	interactive = null
	interactive_buttons = []

## createInteractiveMessageBox: on_pressed(indeks) po kliknięciu (okno znika).
func create_interactive(message: String, buttons: Array, on_pressed: Callable, gui_mode := false) -> Control:
	close_interactive()
	_s = UI.ui_scale()
	var ui = CU.new(main, _s)
	var bl := Box.new(_s)
	var text_pad := 10
	var text_button_pad := 10
	var button_left_pad := 10
	var button_top_pad := 10
	var label_left_pad := 12
	var label_top_pad := 4
	var main_pad := 10
	var lines := bl.wrap_lines(message, 400)
	var tw := 0.0
	for ln in lines:
		tw = maxf(tw, bl.text_size(ln).x)
	var text_size := Vector2(tw, 16 * lines.size())
	var biggest := 0.0
	var buttons_w := 0.0
	var buttons_h := 0.0
	var button_h := 0.0
	var widths := []
	for b in buttons:
		if buttons_w != 0.0:
			buttons_w += button_left_pad
		var w: float = bl.text_size(String(b)).x + 2 * label_left_pad
		widths.append(w)
		buttons_w += w
		button_h = 16 + 2 * label_top_pad
		if buttons_h != 0.0:
			buttons_h += button_top_pad
		buttons_h += button_h
		biggest = maxf(biggest, w)
	var vp := get_viewport().get_visible_rect().size / _s
	var main_size := Vector2.ZERO
	var win_pos := Vector2.ZERO
	var msg_pos := Vector2.ZERO
	var btn_rects := []
	var borders := Vector2(8, 8)                          # MW_Dialog: obszar Client 4 px od krawędzi
	if buttons_w < text_size.x:
		main_size = Vector2(text_size.x + 3 * text_pad, text_pad + text_size.y + text_button_pad + button_h + main_pad)
		var real := main_size + borders
		win_pos = Vector2(int(vp.x - real.x) / 2, int(vp.y - real.y) / 2)
		msg_pos = Vector2(int(main_size.x - text_size.x) / 2, text_pad)
		var left := float(int(main_size.x - buttons_w) / 2)
		for w in widths:
			btn_rects.append(Rect2(left, msg_pos.y + text_size.y + text_button_pad, w, button_h))
			left += w + button_left_pad
	else:
		main_size.x = biggest + button_top_pad * 2 if biggest > text_size.x else text_size.x + 3 * text_pad
		var top := text_pad + text_size.y + text_button_pad
		for w in widths:
			btn_rects.append(Rect2(int(main_size.x - w) / 2, top, w, button_h))
			top += button_h + button_top_pad
		main_size.y = text_pad + text_size.y + text_button_pad + buttons_h + main_pad
		win_pos = Vector2(int(vp.x - main_size.x) / 2, int(vp.y - main_size.y) / 2)
		msg_pos = Vector2(int(main_size.x - text_size.x) / 2, text_pad)
	interactive = ui.modal(self, main_size.x + borders.x, main_size.y + borders.y, gui_mode)
	interactive.name = "InteractiveMessageBox"
	interactive.position = win_pos * _s
	var c: Control = interactive.get_meta("client")
	var l := Label.new()
	l.name = "message"
	l.text = "\n".join(lines)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UI.color("normal"))
	l.add_theme_constant_override("line_spacing", roundi(16 * _s - UI.font().get_height(roundi(16 * _s))))
	l.position = msg_pos * _s
	l.size = text_size * _s
	c.add_child(l)
	interactive_buttons = []
	for i in buttons.size():
		var k := i
		var b: Button = ui.button(String(buttons[i]), func():
			close_interactive()
			if on_pressed.is_valid():
				on_pressed.call(k))
		b.name = "Button%d" % i
		var r: Rect2 = btn_rects[i]
		b.position = r.position * _s
		b.size = r.size * _s
		c.add_child(b)
		interactive_buttons.append(b)
	# getDefaultKeyFocus: przycisk #{sOk} albo #{sYes} (bez rozróżniania wielkości liter); inaczej bez fokusu
	var kws := []
	if main != null and main.get("dialogue") != null and main.dialogue != null:
		kws = [main.dialogue.gmst_text("sOk", "OK").to_lower(), main.dialogue.gmst_text("sYes", "Yes").to_lower()]
	for b2 in interactive_buttons:
		if String(b2.text).to_lower() in kws:
			b2.focus_mode = Control.FOCUS_CLICK
			b2.grab_focus.call_deferred()
			break
	return interactive

func press(i: int) -> bool:
	if not is_interactive() or i < 0 or i >= interactive_buttons.size():
		return false
	(interactive_buttons[i] as Button).pressed.emit()
	return true
