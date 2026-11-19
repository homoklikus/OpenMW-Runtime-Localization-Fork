extends RefCounted
## ItemSelectionDialog (apps/openmw/mwgui/itemselection.cpp, openmw_itemselection_dialog.layout):
## MW_DialogNoTransp 380 × 285, napis SandText (8, 8, 300, 18), ItemView z ekwipunkiem gracza przefiltrowanym
## (8, 34, 355, 200), przycisk Cancel (AutoSizedButton, ExpandDirection Left od 364, 240). Klik przedmiotu –
## eventItemSelected, Cancel – eventDialogCanceled. Okno modalne (warstwa Modal).

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")

var main
var ui = null
var win: Control = null
var on_selected: Callable
var on_cancel: Callable
var entries: Array = []           # testy: wyświetlone wpisy

func _init(game_main, chargen_ui) -> void:
	main = game_main
	ui = chargen_ui

func is_open() -> bool:
	return win != null and is_instance_valid(win)

## filter: Callable(wpis z menu_mode.sorted_items()) → bool.
func open(host: Node, title: String, filter: Callable, selected: Callable, cancel: Callable) -> void:
	close()
	on_selected = selected
	on_cancel = cancel
	win = ui.modal(host, 380, 285, true)
	win.name = "ItemSelectionDialog"
	var c: Control = win.get_meta("client")
	ui.label(c, 8, 8, 300, 18, title)
	var view := Control.new()
	view.name = "ItemView"
	ui.at(view, c, 8, 34, 355, 200)
	var owner := _Owner.new(self)
	var grid: Control = main.menu_mode._make_grid(view, "selection", owner)
	(grid.get_parent().get_parent() as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	entries = []
	for e in main.menu_mode.sorted_items():
		if filter.call(e):
			entries.append(e)
	main.menu_mode._fill_grid(grid, entries, "selection", owner)
	var cb: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), cancel_clicked)
	cb.name = "CancelButton"
	c.add_child(cb)
	var bw := maxf(24 * ui.sc, cb.size.x)                  # ExpandDirection Left: prawa krawędź 364
	cb.position = Vector2(364 * ui.sc - bw, 240 * ui.sc)
	cb.size = Vector2(bw, 24 * ui.sc)

func close() -> void:
	if is_open():
		CU.close(win)
	win = null

func select(id: String) -> void:
	if on_selected.is_valid():
		on_selected.call(id)

func cancel_clicked() -> void:
	if on_cancel.is_valid():
		on_cancel.call()
	else:
		close()

class _Owner:
	var d
	func _init(dialog) -> void:
		d = dialog
	func click_item(id: String, _s: String) -> void:
		d.select(id)
	func activate_item(id: String, _s: String) -> void:
		d.select(id)
	func dropped_on(_t: String, _d: Dictionary) -> void:
		pass
