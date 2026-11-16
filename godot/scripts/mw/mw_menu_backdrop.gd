extends Control
## Tło trybu menu (cały ekran za oknami): przedmiot z ekwipunku upuszczony poza oknami – na ziemię przed graczem
## (jak upuszczenie w świat w OpenMW).

var menu

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item") and String(data.get("source", "inventory")) == "inventory"

func _drop_data(_at: Vector2, data: Variant) -> void:
	menu.drop_to_world(String(data["mw_item"]), String(data.get("source", "inventory")))
