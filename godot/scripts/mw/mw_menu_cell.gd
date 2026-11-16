extends Control
## Komórka siatki ekwipunku w trybie menu (mw_menu_mode.gd): przeciąganie przedmiotu (ikona pod kursorem),
## dwuklik – użyj/załóż.

var menu
var item_id := ""

func _get_drag_data(_at: Vector2) -> Variant:
	var prev := TextureRect.new()
	for c in get_children():
		if c is TextureRect and (c as TextureRect).texture != null and c.size.x < size.x:
			prev.texture = (c as TextureRect).texture
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.size = size * 0.8
	prev.modulate.a = 0.85
	set_drag_preview(prev)
	return {"mw_item": item_id}

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
		menu.use_item(item_id)
		accept_event()
