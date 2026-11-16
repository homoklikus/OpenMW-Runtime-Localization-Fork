extends Control
## Komórka siatki przedmiotów w trybie menu (mw_menu_mode.gd): przeciąganie przedmiotu (ikona pod kursorem),
## dwuklik – użyj/załóż albo przełóż (pojemnik).

var menu
var item_id := ""
var source := "inventory"

func _get_drag_data(_at: Vector2) -> Variant:
	var prev := TextureRect.new()
	var ic := get_node_or_null("Icon") as TextureRect
	if ic != null:
		prev.texture = ic.texture
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.size = size * 0.8
	prev.modulate.a = 0.85
	set_drag_preview(prev)
	return {"mw_item": item_id, "source": source}

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
		menu.activate_item(item_id, source)
		accept_event()
