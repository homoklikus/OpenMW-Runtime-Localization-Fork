extends CanvasLayer
## Okno ilości jak OpenMW 0.51 CountDialog (apps/openmw/mwgui/countdialog.cpp, openmw_count_window.layout):
## okno modalne (warstwa Modal) w skórce MW_DialogNoTransp, wysokość 128, szerokość max(szerokość nazwy + 160, 320),
## na środku ekranu. U góry komunikat (LabelText, wyśrodkowany: sTake, sQuanityMenuMessage01/02, sDrop),
## pod nim nazwa przedmiotu (ItemText, z duszą – ToolTips::getSoulString) i pole liczby (ItemEdit, NumericEditBox
## 1…max, strzałki góra/dół ±1), pasek MW_HScroll (CountSlider: zakres max, pozycja = liczba − 1, MoveToClick,
## kółko o 1), przyciski OK i Cancel (#{Interface:OK}/#{Interface:Cancel}) na środku dolnego wiersza.
## Domyślnie – cały stos (setScrollPosition(max − 1)); Enter w polu = OK, Esc = Cancel (WindowModal::exit).
## Pole liczby ma fokus klawiatury (setKeyFocusWidget). OK najpierw zamyka okno, potem wywołuje eventOkClicked.

signal answered(count: int)       # 0 – anulowano

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")

var main = null
var _root: Control = null
var _win: Control = null
var label_text: Label = null       # LabelText
var item_text: Label = null        # ItemText
var item_edit: LineEdit = null     # ItemEdit
var slider: HScrollBar = null      # CountSlider
var ok_button: Button = null
var cancel_button: Button = null
var max_count := 1
var _value := 1
var _on_ok := Callable()
var _on_cancel := Callable()
var history: Array = []            # testy: [komunikat, nazwa, max, wynik]

func _ready() -> void:
	layer = 61                     # Modal – nad oknami gry i potwierdzeniem
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func is_open() -> bool:
	return visible

func value() -> int:
	return _value

## CountDialog::openCountDialog(item, message, maxCount); on_ok(count) po OK/Enter, on_cancel() po Cancel/Esc.
func open_count(item: String, message: String, count: int, on_ok := Callable(), on_cancel := Callable()) -> void:
	if visible:
		_close(0)
	_on_ok = on_ok
	_on_cancel = on_cancel
	max_count = maxi(1, count)
	var s: float = UI.ui_scale()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "CountDialogRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP           # okno modalne – reszta GUI nie dostaje myszy
	_root.theme = UI.theme(s)
	add_child(_root)
	var font: Font = UI.font()
	var fs := roundi(16 * s)
	# szerokość z nazwy (getTextSize().width + 160, co najmniej 320), wysokość okna z układu (128)
	var w := maxf(ceilf(font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 160.0 * s, 320.0 * s)
	var h := 128.0 * s
	var vp := get_viewport().get_visible_rect().size
	_win = Panel.new()
	_win.name = "CountDialog"
	_win.add_theme_stylebox_override("panel", UI.dialog_box_opaque())
	_win.size = Vector2(roundf(w), roundf(h))
	_win.position = Vector2(floorf(vp.x / 2.0 - roundf(w) / 2.0), floorf(vp.y / 2.0 - roundf(h) / 2.0))
	_root.add_child(_win)
	var client := Control.new()                               # Client skórki MW_Dialog: 4 px od krawędzi
	client.name = "Client"
	client.position = Vector2(4, 4) * s
	client.size = _win.size - Vector2(8, 8) * s
	_win.add_child(client)
	var cw: float = client.size.x
	label_text = Label.new()
	label_text.name = "LabelText"
	label_text.text = message
	label_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_text.position = Vector2(0, 4 * s)
	label_text.size = Vector2(cw, 24 * s)
	client.add_child(label_text)
	item_text = Label.new()
	item_text.name = "ItemText"
	item_text.text = item
	item_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_text.clip_text = true
	item_text.position = Vector2(12, 36) * s
	item_text.size = Vector2(cw - 121 * s, 24 * s)              # 471 przy kliencie 592 (HStretch)
	client.add_child(item_text)
	item_edit = LineEdit.new()
	item_edit.name = "ItemEdit"
	item_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_edit.position = Vector2(cw - 107 * s, 36 * s)          # 485 przy 592 (Right Top)
	item_edit.size = Vector2(100, 24) * s
	item_edit.custom_minimum_size = item_edit.size
	item_edit.add_theme_stylebox_override("normal", UI.inner_box(Color(0, 0, 0, 0)))
	item_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	item_edit.text_changed.connect(_on_edit_changed)
	item_edit.focus_exited.connect(func(): if item_edit != null: item_edit.text = str(_value))
	client.add_child(item_edit)
	slider = HScrollBar.new()
	slider.name = "CountSlider"
	slider.min_value = 0
	slider.max_value = max_count               # setScrollRange(max): pozycje 0…max − 1
	slider.page = 1
	slider.step = 1
	slider.position = Vector2(7, 67) * s
	slider.size = Vector2(cw - 14 * s, 18 * s)
	UI.setup_scroll_bar(slider, s)
	slider.custom_step = 1                     # WheelPage 1
	slider.value_changed.connect(_on_slider_moved)
	client.add_child(slider)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(0, 91 * s)
	row.size = Vector2(cw, 28 * s)
	client.add_child(row)
	ok_button = Button.new()
	ok_button.name = "OkButton"
	ok_button.text = L10n.ctx_text("Interface", "OK", "OK")
	ok_button.focus_mode = Control.FOCUS_NONE
	ok_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # HBox::align – AutoSizedButton 24 px w wierszu 28 px
	ok_button.custom_minimum_size.y = 24 * s
	ok_button.pressed.connect(press_ok)
	row.add_child(ok_button)
	cancel_button = Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = L10n.ctx_text("Interface", "Cancel", "Cancel")
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_button.custom_minimum_size.y = 24 * s
	cancel_button.pressed.connect(press_cancel)
	row.add_child(cancel_button)
	visible = true
	_value = max_count
	slider.set_value_no_signal(max_count - 1)
	item_edit.text = str(max_count)
	item_edit.grab_focus()
	item_edit.select_all()

## CountDialog::setCount (pad: LB – 1, RB – max).
func set_count(n: int) -> void:
	_value = clampi(n, 1, max_count)
	if slider != null:
		slider.set_value_no_signal(_value - 1)
	if item_edit != null and item_edit.text != str(_value):
		item_edit.text = str(_value)

## NumericEditBox::onEditTextChange: puste – bez zmiany, liczba – przycięta do 1…max, inny tekst – poprzednia wartość.
func _on_edit_changed(t: String) -> void:
	if t.is_empty():
		return
	if t.is_valid_int():
		var v := int(t)
		var c := clampi(v, 1, max_count)
		_value = c
		if c != v or str(c) != t:
			item_edit.text = str(c)
			item_edit.caret_column = item_edit.text.length()
	else:
		item_edit.text = str(_value)
		item_edit.caret_column = item_edit.text.length()
	slider.set_value_no_signal(_value - 1)        # onEditValueChanged

func _on_slider_moved(pos: float) -> void:
	_value = clampi(int(roundf(pos)) + 1, 1, max_count)
	item_edit.text = str(_value)                  # onSliderMoved

func press_ok() -> void:
	if visible:
		_close(_value)

func press_cancel() -> void:
	if visible:
		_close(0)

func _close(result: int) -> void:
	visible = false
	history.append([label_text.text if label_text != null else "", item_text.text if item_text != null else "",
		max_count, result])
	if _root != null:
		_root.queue_free()
		_root = null
		label_text = null
		item_text = null
		item_edit = null
		slider = null
		ok_button = null
		cancel_button = null
	var cb := _on_ok if result > 0 else _on_cancel
	_on_ok = Callable()
	_on_cancel = Callable()
	answered.emit(result)
	if cb.is_valid():
		if result > 0:
			cb.call(result)
		else:
			cb.call()

## Klawisze przed resztą GUI: okno modalne przejmuje klawiaturę (Esc nie zamyka okien pod spodem).
func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	var k := (e as InputEventKey).keycode
	match k:
		KEY_ESCAPE:
			press_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			press_ok()                            # eventEditSelectAccept
		KEY_UP:
			set_count(_value + 1)                 # NumericEditBox: ArrowUp
		KEY_DOWN:
			set_count(_value - 1)
		_:
			var digit := (k >= KEY_0 and k <= KEY_9) or (k >= KEY_KP_0 and k <= KEY_KP_9)
			if digit or k in [KEY_BACKSPACE, KEY_DELETE, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END]:
				return                            # do pola liczby
			if (e as InputEventKey).ctrl_pressed and k in [KEY_A, KEY_C, KEY_V, KEY_X]:
				return
	get_viewport().set_input_as_handled()
