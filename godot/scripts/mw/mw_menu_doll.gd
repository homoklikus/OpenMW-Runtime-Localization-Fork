extends PanelContainer
## Podgląd postaci w ekwipunku (tryb menu): upuszczony przedmiot – użyj/załóż (InventoryWindow::onAvatarClicked).

var menu

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item")

func _drop_data(_at: Vector2, data: Variant) -> void:
	menu.use_item(String(data["mw_item"]))
