extends PanelContainer
## Obszar przyjmujący upuszczone przedmioty w trybie menu: postać („avatar” – użyj/załóż, InventoryWindow::
## onAvatarClicked), siatka ekwipunku („inventory”) albo pojemnika („container”) – przełożenie.

var menu
var target := "avatar"

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item") and String(data.get("source", "inventory")) != target

func _drop_data(_at: Vector2, data: Variant) -> void:
	menu.dropped_on(target, data)
