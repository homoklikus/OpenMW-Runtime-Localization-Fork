extends Control
## Tło trybu menu (cały ekran za oknami): przedmiot z ekwipunku upuszczony poza oknami – w świat (WorldItemModel:
## w punkcie kursora, gdy da się go tam postawić, inaczej pod nogi gracza); nad światem z przedmiotem przy kursorze
## – kursor drop_ground, gdy w punkcie kursora nie da się postawić przedmiotu (HUD::onWorldMouseOver).

var menu

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item") and String(data.get("source", "inventory")) == "inventory"

func _drop_data(at: Vector2, data: Variant) -> void:
	menu.drop_to_world(String(data["mw_item"]), String(data.get("source", "inventory")), data, get_global_transform() * at)

## Kliknięcie w trybie Interface: elementy HUD pod tłem przełączają okna (HUD::on*Clicked).
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and menu != null:
		update_pointer(get_global_transform() * e.position)
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and menu != null:
		if menu.has_method("is_holding") and menu.is_holding():
			menu.held_drop("world", get_global_transform() * e.position)   # HUD::onWorldClicked: przedmiot w świat
			mouse_default_cursor_shape = Control.CURSOR_ARROW                # changePointer("arrow")
			accept_event()
			return
		if menu.hud_click(get_global_transform() * e.position):
			accept_event()
			return
		var mods := {"alt": e.alt_pressed, "shift": e.shift_pressed, "ctrl": e.ctrl_pressed}
		if menu.has_method("world_pick") and menu.world_pick(get_global_transform() * e.position, mods):
			accept_event()

## HUD::onWorldMouseOver: z przedmiotem przy kursorze – drop_ground, gdy World::canPlaceObject jest fałszywe.
func update_pointer(screen: Vector2) -> void:
	var holding: bool = menu.has_method("is_holding") and menu.is_holding()
	var can: bool = not holding or menu.main == null or not menu.main.has_method("can_place_object") or menu.main.can_place_object(screen)
	mouse_default_cursor_shape = Control.CURSOR_ARROW if can else Control.CURSOR_CAN_DROP
