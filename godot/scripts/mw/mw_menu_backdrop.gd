extends Control
## Tło trybu menu (cały ekran za oknami): przedmiot z ekwipunku upuszczony poza oknami – na ziemię przed graczem
## (jak upuszczenie w świat w OpenMW).

var menu

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item") and String(data.get("source", "inventory")) == "inventory"

func _drop_data(_at: Vector2, data: Variant) -> void:
	menu.drop_to_world(String(data["mw_item"]), String(data.get("source", "inventory")), data)

## Kliknięcie w trybie Interface: elementy HUD pod tłem przełączają okna (HUD::on*Clicked).
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and menu != null:
		if menu.hud_click(get_global_transform() * e.position):
			accept_event()
