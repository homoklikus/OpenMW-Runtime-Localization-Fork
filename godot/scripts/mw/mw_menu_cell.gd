extends Control
## Komórka siatki przedmiotów w trybie menu (mw_menu_mode.gd): przeciąganie przedmiotu (ikona pod kursorem),
## dwuklik – użyj/załóż albo przełóż (pojemnik). Stan Shift/Ctrl/Alt w chwili chwycenia przedmiotu trafia do
## danych przeciągania (okno ilości: Ctrl – 1 sztuka, Shift – cały stos bez pytania).

var menu
var item_id := ""
var source := "inventory"
var stack := {}                        # stos (ItemStack): {count, worn} – kilka komórek może mieć ten sam przedmiot

func _note_stack() -> void:
	if menu != null and "pressed_stack" in menu:
		menu.pressed_stack = stack

func _get_drag_data(_at: Vector2) -> Variant:
	if menu != null and menu.has_method("cell_pressed"):
		return null                    # tryb menu: DragAndDrop OpenMW (kliknięcie podnosi, kliknięcie odkłada)
	var prev := TextureRect.new()
	var ic := get_node_or_null("Icon") as TextureRect
	if ic != null:
		prev.texture = ic.texture
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.size = size * 0.8
	prev.modulate.a = 0.85
	set_drag_preview(prev)
	_note_stack()
	return {"mw_item": item_id, "source": source, "stack": stack, "shift": Input.is_key_pressed(KEY_SHIFT),
		"ctrl": Input.is_key_pressed(KEY_CTRL), "alt": Input.is_key_pressed(KEY_ALT)}

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var mods := {"shift": e.shift_pressed, "ctrl": e.ctrl_pressed, "alt": e.alt_pressed}
		_note_stack()
		if menu.has_method("cell_pressed"):
			# InventoryWindow/ContainerWindow::onItemSelected: kliknięcie podnosi przedmiot (okno ilości przy stosie,
			# Ctrl – 1 sztuka, Shift – cały stos, Alt – przełożenie), z przedmiotem przy kursorze – odkłada tutaj
			menu.cell_pressed(item_id, source, mods)
			accept_event()
		elif e.double_click:
			menu.activate_item(item_id, source, mods)
			accept_event()
		elif menu.has_method("click_item"):
			menu.click_item(item_id, source, mods)
			accept_event()
		if menu != null and "pressed_stack" in menu:
			menu.pressed_stack = {}
