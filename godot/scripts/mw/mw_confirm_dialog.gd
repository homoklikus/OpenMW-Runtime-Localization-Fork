extends CanvasLayer
## Okno potwierdzenia jak OpenMW ConfirmationDialog (openmw_confirmation_dialog.layout): tekst, „OK” i „Anuluj”;
## Esc = Anuluj, Enter = OK. Modalne – nad menu głównym i oknem zapisów.

signal answered(ok: bool)

const UI := preload("res://scripts/mw/mw_ui.gd")

var main = null
var _root: Control = null
var _label: Label = null
var _ok_cb := Callable()
var _cancel_cb := Callable()

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func ask(text: String, on_ok := Callable(), on_cancel := Callable()) -> void:
	_ok_cb = on_ok
	_cancel_cb = on_cancel
	if _root != null:
		_root.queue_free()
	var sc := clampf(get_viewport().get_visible_rect().size.y / 720.0, 1.0, 3.0)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UI.theme(sc)
	add_child(_root)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.dialog_box_opaque())
	panel.custom_minimum_size = Vector2(360, 0) * sc
	_root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_label = Label.new()
	_label.text = text
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(340, 0) * sc
	box.add_child(_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var ok := Button.new()
	ok.name = "OkButton"
	ok.text = "OK"
	ok.pressed.connect(func(): _answer(true))
	row.add_child(ok)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "Anuluj"
	cancel.pressed.connect(func(): _answer(false))
	row.add_child(cancel)
	visible = true
	await get_tree().process_frame
	if is_instance_valid(panel):
		panel.position = ((get_viewport().get_visible_rect().size - panel.size) / 2.0).floor()
		ok.grab_focus()

func is_open() -> bool:
	return visible

func text() -> String:
	return _label.text if _label != null and visible else ""

func _answer(ok: bool) -> void:
	if not visible:
		return
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	var cb := _ok_cb if ok else _cancel_cb
	_ok_cb = Callable()
	_cancel_cb = Callable()
	answered.emit(ok)
	if cb.is_valid():
		cb.call()

func press(ok: bool) -> void:
	_answer(ok)

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if (e as InputEventKey).keycode == KEY_ESCAPE:
			_answer(false)
			get_viewport().set_input_as_handled()
		elif (e as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_answer(true)
			get_viewport().set_input_as_handled()
