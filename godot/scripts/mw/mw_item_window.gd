extends CanvasLayer
## Okna przedmiotów (etap 3, prosty interfejs – pełne okna w stylu Morrowinda w etapie 10):
##   pojemnik – lewa lista: zawartość pojemnika, prawa: inwentarz gracza; dwuklik/Enter przenosi stos,
##             „Weź wszystko”; okno ekwipunku – inwentarz gracza, „Odłóż” kładzie przedmiot przed graczem.
## Gra jest wstrzymana, gdy okno jest otwarte.

signal closed

const UI := preload("res://scripts/mw/mw_ui.gd")
var interaction            # MWInteraction
var main                   # main.gd (pozycja gracza, komórka, komunikaty)
var mode := ""             # "container" | "inventory"
var cont_sid := ""
var cont_rec := {}
var cont_name := ""
var left: ItemList
var right: ItemList
var title: Label
var info: Label
var take_all_btn: Button
var drop_btn: Button
var equip_btn: Button
var _left_ids := []
var _right_ids := []

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.name = "ItemWindow"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 520)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.add_head(box, title)
	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(lists)
	left = _list(lists)
	right = _list(lists)
	left.item_activated.connect(func(i): _move_from_left(i))
	right.item_activated.connect(func(i): _move_from_right(i))
	info = Label.new()
	box.add_child(info)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	take_all_btn = _button(buttons, "Weź wszystko", _take_all)
	drop_btn = _button(buttons, "Odłóż na ziemię", func(): _move_from_right(_selected(right)))
	equip_btn = _button(buttons, "Użyj / załóż", func(): use_item(_selected(right)))
	_button(buttons, "Zamknij (Esc)", close)
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	visible = false

func _list(parent: Control) -> ItemList:
	var l := ItemList.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

static func _selected(l: ItemList) -> int:
	var s := l.get_selected_items()
	return s[0] if s.size() > 0 else -1

func open_container(sid: String, rec: Dictionary, name: String) -> void:
	mode = "container"
	cont_sid = sid
	cont_rec = rec
	cont_name = name
	left.visible = true
	take_all_btn.visible = true
	drop_btn.visible = false
	equip_btn.visible = false
	_show()

func open_inventory() -> void:
	mode = "inventory"
	left.visible = false
	take_all_btn.visible = false
	drop_btn.visible = true
	equip_btn.visible = main != null and main.has_method("equip_item")
	_show()

func _show() -> void:
	refresh()
	visible = true
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if visible and (e.is_action_pressed("menu") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()

func _fill(l: ItemList, items: Array) -> Array:
	l.clear()
	var ids := []
	for e in interaction.inventory.ordered(items):
		var name: String = interaction.item_name(e.kind, e.id, e.rec)
		var worn: bool = l == right and main != null and main.has_method("equipped_slot_of") and main.equipped_slot_of(e.id) >= 0
		l.add_item("%s%s%s" % [name, (" × %d" % e.count) if e.count > 1 else "", "  [założone]" if worn else ""])
		ids.append(e.id)
	return ids

func refresh() -> void:
	var inv = interaction.inventory
	var mine: Array = inv.contents(interaction.PLAYER, {})
	_right_ids = _fill(right, mine)
	if mode == "container":
		var theirs: Array = inv.contents(cont_sid, cont_rec)
		_left_ids = _fill(left, theirs)
		title.text = "%s  ⟷  Ekwipunek" % cont_name
		var cap := float(cont_rec.get("capacity", 0.0))
		info.text = "Waga w pojemniku: %.1f / %.0f   |   Twój ekwipunek: %.1f   |   dwuklik – przenieś stos" % [
				inv.total_weight(theirs), cap, inv.total_weight(mine)]
	else:
		title.text = "Ekwipunek"
		info.text = "Waga: %.1f   |   „Odłóż na ziemię” – zaznaczony stos" % inv.total_weight(mine)

func _count_in(items: Array, id: String) -> int:
	for e in items:
		if e.id == id:
			return int(e.count)
	return 0

func _move_from_left(i: int) -> void:
	if i < 0 or i >= _left_ids.size():
		return
	var id: String = _left_ids[i]
	var n := _count_in(interaction.inventory.contents(cont_sid, cont_rec), id)
	interaction.move(cont_sid, cont_rec, interaction.PLAYER, {}, id, n)
	_sound(id, true)
	refresh()

func _move_from_right(i: int) -> void:
	if i < 0 or i >= _right_ids.size():
		return
	var id: String = _right_ids[i]
	var n := _count_in(interaction.inventory.contents(interaction.PLAYER, {}), id)
	if mode == "container":
		interaction.move(interaction.PLAYER, {}, cont_sid, cont_rec, id, n)
	elif main != null and main.has_method("drop_item"):
		main.drop_item(id, n)
	_sound(id, false)
	refresh()

## Użycie przedmiotu (InventoryWindow::useItem, etap 7d): mikstura – wypicie, składnik – zjedzenie, aparat –
## alchemia, kamień dusz z duszą – zaklinanie, zwój – wybór jako magia; inne – załóż/zdejmij.
func use_item(i: int) -> void:
	if i < 0 or i >= _right_ids.size() or main == null or mode != "inventory" or main.get("magic") == null:
		toggle_equip(i)
		return
	var id: String = _right_ids[i]
	var it: Dictionary = interaction.inventory.item(id)
	var me: Dictionary = main.combat.player_fighter()
	match String(it.get("kind", "")):
		"potion":
			main.magic.drink(me, id)
			info.text = "Wypito: " + interaction.item_name("potion", id, it.rec)
		"ingredient":
			var r: Dictionary = main.magic.eat(me, id)
			info.text = String(r.get("message", "")) if not String(r.get("message", "")).is_empty() else "Zjedzono: " + interaction.item_name("ingredient", id, it.rec)
		"apparatus":
			close()
			main.magic_window.open_alchemy()
			return
		"misc":
			if main.magic.is_soul_gem(id) and main.magic.gem_charge(id) > 0:
				close()
				main.magic_window.open_enchant({}, id)
				return
			toggle_equip(i)
			return
		"book":
			# ActionRead jak w OpenMW (także zwoje z zaklęciem – rzuca się je z okna magii M)
			main.read_book(id)
			return
		_:
			toggle_equip(i)
			return
	refresh()

## Załóż albo zdejmij zaznaczony przedmiot gracza (etap 7).
func toggle_equip(i: int) -> void:
	if i < 0 or i >= _right_ids.size() or main == null:
		return
	var id: String = _right_ids[i]
	var slot: int = main.equipped_slot_of(id)
	if slot >= 0:
		main.unequip_slot(slot)
	else:
		var msg: String = main.equip_item(id)
		if not msg.is_empty():
			info.text = msg
			return
	if main.get("audio") != null:
		main.audio.play("Item Armor Light Up" if slot < 0 else "Item Armor Light Down")
	refresh()

func _sound(id: String, up: bool) -> void:
	if main != null and main.get("audio") != null:
		main.audio.play(interaction.item_sound(id, up))

func _take_all() -> void:
	interaction.take_all(cont_sid, cont_rec)
	refresh()
