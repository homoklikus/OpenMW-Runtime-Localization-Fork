extends CanvasLayer
## Okno notatki jak OpenMW 0.51 EditNoteDialog (mapwindow.cpp, openmw_edit_note.layout): okno modalne
## MW_DialogNoTransp 336 × 242 na środku ekranu, napis #{sEditNote} (13, 13), pole tekstu MW_TextBoxEditWithBorder
## (13, 38, 303 × 150; wielowierszowe, zawijanie, pionowy pasek przewijania) z fokusem klawiatury, w dolnym wierszu
## (13, 200, 303 × 24; wyrównanie do prawej, odstęp 6) przyciski #{sDelete} (tylko przy edycji istniejącej notatki),
## #{Interface:OK}, #{Interface:Cancel}. Enter w polu – nowy wiersz (MultiLine); Esc = Cancel (WindowModal::exit).

signal ok_clicked
signal delete_clicked

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")

var main = null
var _root: Control = null
var win: Control = null
var text_edit: TextEdit = null
var delete_button: Button = null
var ok_button: Button = null
var cancel_button: Button = null
var _delete_shown := false

func _ready() -> void:
	layer = 61                     # Modal
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb) if main != null and main.get("dialogue") != null and main.dialogue != null else fb

func is_open() -> bool:
	return visible

## setVisible(true) + showDeleteButton + setText (MapWindow::onMapDoubleClicked / onCustomMarkerDoubleClicked).
func open(text: String, show_delete: bool) -> void:
	_delete_shown = show_delete
	var s: float = UI.ui_scale()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "EditNoteRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UI.theme(s)
	add_child(_root)
	var vp := get_viewport().get_visible_rect().size
	win = Panel.new()
	win.name = "EditNoteDialog"
	win.add_theme_stylebox_override("panel", UI.dialog_box_opaque())
	win.size = Vector2(336, 242) * s
	win.position = ((vp - win.size) / 2.0).floor()       # center()
	_root.add_child(win)
	var client := Control.new()                          # Client skórki MW_Dialog: 4 px od krawędzi
	client.position = Vector2(4, 4) * s
	client.size = win.size - Vector2(8, 8) * s
	win.add_child(client)
	var cap := Label.new()
	cap.name = "Caption"
	cap.text = _t("sEditNote", "Edit Note")
	cap.position = Vector2(13, 13) * s
	cap.size = Vector2(200, 16) * s
	cap.add_theme_color_override("font_color", UI.color("normal"))
	client.add_child(cap)
	text_edit = TextEdit.new()
	text_edit.name = "TextEdit"
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.position = Vector2(13, 38) * s
	text_edit.size = Vector2(303, 150) * s
	text_edit.add_theme_stylebox_override("normal", UI.inner_box(Color(0, 0, 0, 0.6)))
	text_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	text_edit.add_theme_color_override("font_color", UI.color("normal"))
	text_edit.text = text
	client.add_child(text_edit)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", roundi(6 * s))
	row.position = Vector2(13, 200) * s
	row.size = Vector2(303, 24) * s
	client.add_child(row)
	delete_button = _button("DeleteButton", _t("sDelete", "Delete"), func(): delete_clicked.emit())
	delete_button.visible = show_delete
	row.add_child(delete_button)
	ok_button = _button("OkButton", L10n.ctx_text("Interface", "OK", "OK"), func(): ok_clicked.emit())
	row.add_child(ok_button)
	cancel_button = _button("CancelButton", L10n.ctx_text("Interface", "Cancel", "Cancel"), close)
	row.add_child(cancel_button)
	visible = true
	text_edit.grab_focus()                               # setKeyFocusWidget(mTextEdit)
	text_edit.set_caret_line(text_edit.get_line_count() - 1)
	text_edit.set_caret_column(text_edit.get_line(text_edit.get_line_count() - 1).length())

func _button(n: String, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size.y = 24 * UI.ui_scale()           # AutoSizedButton: tekst + 8
	b.pressed.connect(cb)
	return b

func get_text() -> String:
	return text_edit.text if text_edit != null else ""

func delete_button_shown() -> bool:
	return _delete_shown

func close() -> void:
	if not visible:
		return
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	text_edit = null
	delete_button = null
	ok_button = null
	cancel_button = null

## Okno modalne przejmuje Esc przed oknami pod spodem.
func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	if (e as InputEventKey).keycode == KEY_ESCAPE:
		var c = main.get("confirm") if main != null else null
		if c != null and c.is_open():
			return                                       # najpierw okno potwierdzenia usunięcia
		close()
		get_viewport().set_input_as_handled()
