extends Control
## Tło trybu menu (cały ekran za oknami): przedmiot upuszczony poza oknami – na ziemię przed graczem
## (jak upuszczenie w świat w OpenMW).

var menu

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item")

func _drop_data(_at: Vector2, data: Variant) -> void:
	menu.drop_to_world(String(data["mw_item"]))
