extends CanvasLayer
## Okno zapisu/wczytania jak OpenMW SaveGameDialog (mwgui/savegamedialog.cpp, openmw_savegame_dialog.layout,
## 600×400): wybór postaci (tylko wczytywanie; „Wybierz postać…”), lista zapisów od najnowszego, zrzut 259×133,
## nazwa komórki, opis (imię, gdy inne niż postaci, poziom, dzień, zdrowie, data w grze, czas gry, data pliku),
## „Usuń zapis gry” (tylko wczytywanie; Shift+klik i Delete), pole nazwy (tylko zapis), OK, Anuluj.
## Zapis na istniejący slot – potwierdzenie nadpisania; wczytanie w trakcie gry – potwierdzenie porzucenia gry;
## pusta nazwa – komunikat. Wczytywanie: automatycznie zaznaczony najnowszy zapis.

const L10n := preload("res://scripts/mw/mw_l10n.gd")
const UI := preload("res://scripts/mw/mw_ui.gd")

var main = null
var saving := true
var current_character = null       # słownik postaci z MWSaves
var current_slot = null            # słownik slotu
var _root: Control = null
var _panel: PanelContainer = null
var character_select: OptionButton = null
var save_list: ItemList = null
var name_edit: LineEdit = null
var screenshot: TextureRect = null
var cell_label: Label = null
var info_label: Label = null
var ok_button: Button = null
var delete_button: Button = null
var _chars: Array = []              # pozycje listy postaci → słowniki postaci

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

## setLoadOrSave + onOpen.
func open(load: bool) -> void:
	saving = not load
	_build()
	visible = true
	var mgr = main.saves
	mgr.refresh()
	current_character = mgr.current if saving else null
	current_slot = null
	_chars.clear()
	character_select.clear()
	var selected := -1
	for c in mgr.characters:
		if (c.slots as Array).is_empty():
			continue
		var sig: Dictionary = mgr.signature(c)
		var cls := String(sig.get("player_class_name", ""))
		var title := "%s (Poziom %d %s)" % [String(sig.get("player_name", "?")), int(sig.get("player_level", 1)), cls]
		character_select.add_item(title.replace(" )", ")"))
		_chars.append(c)
		if current_character == c or (current_character == null and not saving \
				and String(c.get("dir", "")) == String(main.settings.get("saves_character", ""))):
			current_character = c
			selected = _chars.size() - 1
	if selected < 0 and not saving and not _chars.is_empty():
		selected = 0
		current_character = _chars[0]
	if selected >= 0:
		character_select.select(selected)
	else:
		character_select.select(-1)
		character_select.text = L10n.text("SelectCharacter", "Select Character...")
	_fill()
	await get_tree().process_frame
	if is_instance_valid(_panel):
		_panel.position = ((get_viewport().get_visible_rect().size - _panel.size) / 2.0).floor()
	if saving:
		name_edit.grab_focus()
	else:
		save_list.grab_focus()

func close() -> void:
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null

func _build() -> void:
	if _root != null:
		_root.queue_free()
	var sc := UI.ui_scale()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UI.theme(sc)
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.dialog_box_opaque())     # MW_DialogNoTransp
	_panel.custom_minimum_size = Vector2(600, 400) * sc
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", roundi(8 * sc))
	_panel.add_child(v)
	character_select = OptionButton.new()
	character_select.name = "SelectCharacter"
	character_select.visible = not saving
	character_select.item_selected.connect(_on_character_selected)
	v.add_child(character_select)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", roundi(8 * sc))
	v.add_child(h)
	save_list = ItemList.new()
	save_list.name = "SaveList"
	save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_list.item_selected.connect(_on_slot_selected)
	save_list.item_activated.connect(func(i):
		_on_slot_selected(i)
		accept())
	save_list.item_clicked.connect(func(i, _pos, _btn):
		if Input.is_key_pressed(KEY_SHIFT) and not saving:
			_on_slot_selected(i)
			confirm_delete())
	save_list.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_DELETE and current_slot != null and not saving:
			confirm_delete())
	h.add_child(save_list)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(263, 0) * sc
	h.add_child(right)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 1)))
	right.add_child(frame)
	screenshot = TextureRect.new()
	screenshot.name = "Screenshot"
	screenshot.custom_minimum_size = Vector2(259, 133) * sc
	screenshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screenshot.stretch_mode = TextureRect.STRETCH_SCALE
	frame.add_child(screenshot)
	cell_label = Label.new()
	cell_label.name = "CellName"
	cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell_label.custom_minimum_size = Vector2(263, 0) * sc
	right.add_child(cell_label)
	info_label = Label.new()
	info_label.name = "InfoText"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(263, 0) * sc
	info_label.add_theme_color_override("font_color", UI.color("normal").lightened(0.15))
	right.add_child(info_label)
	var row := HBoxContainer.new()
	v.add_child(row)
	delete_button = Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = L10n.text("DeleteGame", "Delete Game")
	delete_button.visible = not saving
	delete_button.focus_mode = Control.FOCUS_NONE        # „To avoid accidental deletions”
	delete_button.pressed.connect(func():
		if current_slot != null:
			confirm_delete())
	row.add_child(delete_button)
	name_edit = LineEdit.new()
	name_edit.name = "SaveNameEdit"
	name_edit.visible = saving
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(_t):
		save_list.deselect_all()
		_on_slot_selected(-1))
	name_edit.text_submitted.connect(func(_t): accept())
	row.add_child(name_edit)
	if not saving:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	ok_button = Button.new()
	ok_button.name = "OkButton"
	ok_button.text = "OK"
	ok_button.pressed.connect(func(): accept())
	row.add_child(ok_button)
	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = "Anuluj"
	cancel.pressed.connect(close)
	row.add_child(cancel)

func _on_character_selected(i: int) -> void:
	if i < 0 or i >= _chars.size():
		return
	current_character = _chars[i]
	current_slot = null
	_fill()

## fillSaveList.
func _fill() -> void:
	save_list.clear()
	if current_character == null:
		_on_slot_selected(-1)
		return
	for s in current_character.slots:
		save_list.add_item(String(s.header.get("description", "")))
	if save_list.item_count > 0 and not saving:
		save_list.select(0)
		_on_slot_selected(0)
	else:
		_on_slot_selected(-1)

## onSlotSelected: opis slotu i zrzut.
func _on_slot_selected(pos: int) -> void:
	ok_button.disabled = not (pos >= 0 or saving)
	delete_button.disabled = pos < 0
	if pos < 0 or current_character == null:
		current_slot = null
		cell_label.text = ""
		info_label.text = ""
		screenshot.texture = null
		return
	current_slot = current_character.slots[pos]
	if saving:
		name_edit.set_block_signals(true)
		name_edit.text = save_list.get_item_text(pos)
		name_edit.set_block_signals(false)
	var h: Dictionary = current_slot.header
	var lines := []
	var sig: Dictionary = main.saves.signature(current_character)
	if String(h.get("player_name", "")) != String(sig.get("player_name", "")):
		lines.append(String(h.get("player_name", "")))
	lines.append("%s %d" % [L10n.text("Level", "Level"), int(h.get("player_level", 1))])
	if int(h.get("current_day", 0)) > 0:
		lines.append("%s %d" % [L10n.ctx_text("Calendar", "day", "Day"), int(h.get("current_day", 0))])
	if float(h.get("max_health", 0)) > 0:
		lines.append("%s %d/%d" % [L10n.text("Health", "Health"), int(h.get("health", 0)), int(h.get("max_health", 0))])
	var t: Dictionary = h.get("game_time", {})
	if not t.is_empty():
		lines.append("%d %s %s" % [int(t.get("day", 1)), main.month_name(int(t.get("month", 0))), L10n.time_of_day(float(t.get("hour", 0)))])
	if float(h.get("time_played", 0)) > 0:
		lines.append(L10n.text("TimePlayed", "Time Played") + ": " + format_time_played(float(h.get("time_played", 0))))
	lines.append(Time.get_datetime_string_from_unix_time(int(current_slot.mtime) + _tz_offset(), true).replace("-", "."))
	cell_label.text = String(h.get("cell_name", ""))
	info_label.text = "\n".join(lines)
	screenshot.texture = null
	var b64 := String(h.get("screenshot", ""))
	if not b64.is_empty():
		var img := Image.new()
		if img.load_jpg_from_buffer(Marshalls.base64_to_raw(b64)) == OK:
			screenshot.texture = ImageTexture.create_from_image(img)

static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

## formatTimeplayed (Interface: DurationHour/Minute/Second).
static func format_time_played(secs: float) -> String:
	var d := int(secs)
	if d <= 0:
		return "0 s"
	var out := ""
	var hrs := d / 3600
	var mins := (d / 60) % 60
	var s := d % 60
	if hrs:
		out += "%d godz. " % hrs
	if mins:
		out += "%d min " % mins
	if s:
		out += "%d s " % s
	return out.strip_edges()

func confirm_delete() -> void:
	main.confirm.ask(L10n.text("DeleteGameConfirmation"), _on_delete_confirmed, func(): save_list.grab_focus())

## onDeleteSlotConfirmed.
func _on_delete_confirmed() -> void:
	if current_slot == null or current_character == null:
		return
	var sel := save_list.get_selected_items()
	var idx: int = sel[0] if not sel.is_empty() else -1
	main.delete_save(current_character, current_slot)
	if idx >= 0:
		save_list.remove_item(idx)
	var next := mini(idx, save_list.item_count - 1)
	if save_list.item_count > 0 and next >= 0:
		save_list.select(next)
		_on_slot_selected(next)
	else:
		_on_slot_selected(-1)
	if save_list.item_count == 0:
		var prev := character_select.selected
		current_character = null
		if prev >= 0:
			character_select.remove_item(prev)
			_chars.remove_at(prev)
		if character_select.item_count > 0:
			var n := mini(maxi(prev, 0), character_select.item_count - 1)
			character_select.select(n)
			_on_character_selected(n)
		else:
			character_select.select(-1)
			character_select.text = L10n.text("SelectCharacter", "Select Character...")

## SaveGameDialog::accept.
func accept(really_sure := false) -> void:
	if saving:
		if current_slot != null and not really_sure:
			main.confirm.ask(L10n.text("OverwriteGameConfirmation"), func(): accept(true), func(): save_list.grab_focus())
			return
		if name_edit.text.is_empty():
			main.message_box(L10n.text("EmptySaveNameError"))
			return
	else:
		if current_slot == null:
			return
		if main.game_state == "running" and not really_sure:
			main.confirm.ask(L10n.text("LoadGameConfirmation"), func(): accept(true), func(): save_list.grab_focus())
			return
	var slot = current_slot
	var ch = current_character
	var desc := name_edit.text
	close()
	main.close_main_menu()
	if saving:
		main.save_to_slot(desc, slot)
	else:
		main.load_slot(ch, String(slot.path))

func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_ESCAPE \
			and not main.confirm.is_open():
		close()
		get_viewport().set_input_as_handled()
