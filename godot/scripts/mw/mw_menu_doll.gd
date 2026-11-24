extends PanelContainer
## Obszar przyjmujący upuszczone przedmioty w trybie menu: postać („avatar” – użyj/załóż, InventoryWindow::
## onAvatarClicked), siatka ekwipunku („inventory”) albo pojemnika („container”) – przełożenie.

var menu
var target := "avatar"

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("mw_item") and String(data.get("source", "inventory")) != target

func _drop_data(_at: Vector2, data: Variant) -> void:
	menu.dropped_on(target, data)

## Kliknięcie z przedmiotem przy kursorze (DragAndDrop): odłożenie na postać (InventoryWindow::onAvatarClicked)
## albo w puste miejsce siatki (ItemView::onSelectedBackground).
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and menu != null \
			and menu.has_method("held_drop") and menu.is_holding():
		menu.held_drop(target)
		accept_event()
