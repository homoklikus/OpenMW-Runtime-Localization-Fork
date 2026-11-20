extends CanvasLayer
## Okno naprawy jak OpenMW 0.51 (MWGui::Repair, files/data/mygui/openmw_repair.layout): VBox w skórce MW_Dialog
## 330 × 385, Padding 8, Spacing 8 – napis sRepairServiceTitle, lista ItemChargeView (MW_ItemChargeView: MW_Box,
## widok od 3 px; wiersz: nazwa SandText (8, y, szer. − 8, 18), ikona MW_ItemIconSmall (16, y + 19, 32, 32), pasek
## MW_ChargeBar (72, y + 21, max(199, szer. − 110), 20) „bieżący/największy”; co 19 + 36 px; kolejność wg nazwy),
## u dołu HBox: ikona narzędzia MW_ItemIconBox 44 × 44 (klik – ItemSelectionDialog z narzędziami), sUses N
## i sQuality Q (ToolBox ukryty, gdy narzędzia brak), odstęp, Cancel. Klik ikony przedmiotu – Repair::repair.

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")

var main
var tool_id := ""
var panel: PanelContainer = null
var lines: Array = []                # testy: [{"id", "text", "charge", "max"}]
var _s := 1.0
var _canvas: Control = null
var _scroll: ScrollContainer = null
var _tool_icon: Control = null
var _tool_box: Control = null
var _uses: Label = null
var _quality: Label = null
var _select: Control = null          # ItemSelectionDialog

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func is_open() -> bool:
	return visible

## ActionRepair: w walce sInventoryMessage2; inaczej okno z narzędziem (dźwięk „Item Repair Up”).
func open(tid: String) -> bool:
	if main.has_method("_player_in_combat") and main._player_in_combat():
		main._toast(_t("sInventoryMessage2", "You cannot do that while in combat."))
		return false
	_s = UI.ui_scale()
	_build()
	visible = true
	_set_tool(tid, "Item Repair Up")
	main.gui.push("repair", [self])                # pushGuiMode(GM_...)
	return true

func close() -> void:
	visible = false
	if _select != null:
		_select.queue_free()
		_select = null
	main.gui.remove("repair")                       # removeGuiMode – powrót do poprzedniego trybu

func _build() -> void:
	if panel != null:
		panel.queue_free()
	panel = PanelContainer.new()
	panel.name = "RepairWindow"
	panel.theme = UI.theme(_s)
	var sb: StyleBox = UI.window_box().duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, (4 + 8) * _s)           # Client MW_Dialog (4) + Padding 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(330, 385) * _s
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(8 * _s))
	panel.add_child(box)
	var label := Label.new()
	label.name = "Label"
	label.text = _t("sRepairServiceTitle", "")
	UI.text_skin(label, "SandText", _s)
	box.add_child(label)
	# RepairBox: MW_ItemChargeView – ramka MW_Box, ScrollView od 3 px
	var rb := PanelContainer.new()
	rb.name = "RepairBox"
	var rsb: StyleBox = UI.inner_box().duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		rsb.set_content_margin(side, 3 * _s)
	rb.add_theme_stylebox_override("panel", rsb)
	rb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(rb)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rb.add_child(_scroll)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_canvas)
	_scroll.resized.connect(_layout_lines)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_tool_icon = Control.new()
	_tool_icon.name = "ToolIcon"
	_tool_icon.custom_minimum_size = Vector2(44, 44) * _s
	_tool_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_tool_icon.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_tool_selection())
	bottom.add_child(_tool_icon)
	_tool_box = VBoxContainer.new()
	_tool_box.name = "ToolBox"
	_tool_box.add_theme_constant_override("separation", 0)
	_tool_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_tool_box)
	_uses = Label.new()
	_uses.name = "UsesLabel"
	_tool_box.add_child(_uses)
	_quality = Label.new()
	_quality.name = "QualityLabel"
	_tool_box.add_child(_quality)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	var cb := Button.new()
	cb.name = "CancelButton"
	cb.text = L10n.ctx_text("Interface", "Cancel", "Cancel")
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb.pressed.connect(close)
	bottom.add_child(cb)

func _center() -> void:
	if panel == null:
		return
	panel.reset_size()
	panel.position = ((get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0).floor()

## Repair::setPtr / onItemSelected: narzędzie, sUses / sQuality, ToolBox widoczny tylko z narzędziem.
func _set_tool(tid: String, sound := "") -> void:
	tool_id = tid
	if not sound.is_empty() and main.get("audio") != null and main.audio != null:
		main.audio.play(sound)
	refresh()

func refresh() -> void:
	if panel == null:
		return
	var inv = main.interaction.inventory
	var has_tool: bool = not tool_id.is_empty() and inv.count_of("player", {}, tool_id) > 0
	for c in _tool_icon.get_children():
		c.queue_free()
	_tool_box.visible = has_tool
	if has_tool:
		var it: Dictionary = inv.item(tool_id)
		_icon_box(_tool_icon, String(it.rec.get("icon", "")))
		main.menu_mode.set_item_tip(_tool_icon, tool_id)
		_uses.text = "%s %d" % [_t("sUses", "Uses"), int(inv.item_charge(tool_id))]
		_quality.text = "%s %s" % [_t("sQuality", "Quality"), String.num(float(it.rec.get("quality", 0.0)), 3).rstrip("0").rstrip(".")]
	else:
		_tool_icon.tooltip_text = ""
	lines = main.repair.repairable()
	for c in _canvas.get_children():
		c.queue_free()
	for l in lines:
		var t := Label.new()
		t.text = String(l.name)
		UI.text_skin(t, "SandText", _s)
		t.clip_text = true
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(t)
		var ic := Control.new()
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		main.menu_mode.set_item_tip(ic, String(l.id))
		var lid := String(l.id)
		ic.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				repair_item(lid))
		_icon_small(ic, String(inv.item(lid).rec.get("icon", "")))
		_canvas.add_child(ic)
		var bar := Control.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pb: ProgressBar = UI.progress_bar("health", _s)      # MW_Progress_Red
		pb.max_value = maxf(1.0, float(l.max))
		pb.value = float(l.charge)
		pb.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.add_child(pb)
		var bt := Label.new()                                    # ProgressText (0, 0, szer., 14)
		bt.text = "%d/%d" % [int(l.charge), int(l.max)]
		bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bt.add_theme_color_override("font_color", UI.color("normal_pressed"))
		bt.set_anchors_preset(Control.PRESET_TOP_WIDE)
		bt.offset_bottom = 14 * _s
		bar.add_child(bt)
		_canvas.add_child(bar)
	_layout_lines()
	_center()

## ItemChargeView::layoutWidgets.
func _layout_lines() -> void:
	if _canvas == null or _scroll == null:
		return
	var w := _scroll.size.x
	var y := 0.0
	var kids := _canvas.get_children().filter(func(c): return not c.is_queued_for_deletion())
	var i := 0
	while i + 2 < kids.size():
		var t: Control = kids[i]
		var ic: Control = kids[i + 1]
		var bar: Control = kids[i + 2]
		t.position = Vector2(8 * _s, y)
		t.size = Vector2(maxf(0.0, w - 8 * _s), 18 * _s)
		y += 19 * _s
		ic.position = Vector2(16 * _s, y)
		ic.size = Vector2(32, 32) * _s
		bar.position = Vector2(72 * _s, y + 2 * _s)
		bar.size = Vector2(maxf(199 * _s, w - 110 * _s), 20 * _s)
		y += (32 + 4) * _s
		i += 3
	_canvas.custom_minimum_size = Vector2(0, maxf(_scroll.size.y, y))

func repair_item(item_id: String) -> void:
	if tool_id.is_empty() or main.interaction.inventory.count_of("player", {}, tool_id) <= 0:
		return
	var r: Dictionary = main.repair.repair(tool_id, item_id)
	for m in r.messages:
		main._toast(String(m))
	if main.get("audio") != null and main.audio != null:
		for snd in r.sounds:
			main.audio.play(String(snd))
	tool_id = String(r.tool)
	refresh()

# --- ikony (MW_ItemIconSmall, MW_ItemIconBox) ----------------------------------------------------------------

func _icon_image(parent: Control, path: String, at: Vector2) -> void:
	var tex: Texture2D = UI.icon(path)
	if tex == null:
		return
	var sh := TextureRect.new()                    # ItemShadow: przesunięty o 4 px, czarny, alfa 0,5
	sh.texture = tex
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.modulate = Color(0, 0, 0, 0.5)
	sh.position = at + Vector2(4, 4) * _s
	sh.size = Vector2(32, 32) * _s
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sh)
	var ic := TextureRect.new()
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.position = at
	ic.size = Vector2(32, 32) * _s
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ic)

func _icon_small(parent: Control, path: String) -> void:
	_icon_image(parent, path, Vector2.ZERO)

## MW_ItemIconBox w polu 44 × 44: tło ikony 42 × 42 (z korzenia 50 × 50 wyśrodkowane – od 1, 1; dla zwykłego
## przedmiotu bez tekstury), ikona od 5, 5 tła, na wierzchu ramka MW_Box_Overlay całego pola.
func _icon_box(parent: Control, path: String) -> void:
	var fr: Texture2D = UI.icon_frame(false, "")
	if fr != null:
		var fb := TextureRect.new()
		fb.texture = fr
		fb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fb.position = Vector2(1, 1) * _s
		fb.size = Vector2(42, 42) * _s
		fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(fb)
	_icon_image(parent, path, Vector2(6, 6) * _s)
	var ov := Panel.new()                          # MW_Box_Overlay na całym polu (0, 0, 50, 50 → Stretch)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_theme_stylebox_override("panel", UI.inner_box())
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ov)

# --- ItemSelectionDialog (openmw_itemselection_dialog.layout) -------------------------------------------------

## MW_DialogNoTransp 380 × 285: napis sRepair (8, 8), ItemView z narzędziami (8, 34, 355, 200), Cancel przy prawej.
func open_tool_selection() -> void:
	if _select != null:
		_select.queue_free()
	var dlg := Panel.new()
	dlg.name = "ItemSelectionDialog"
	dlg.theme = UI.theme(_s)
	dlg.add_theme_stylebox_override("panel", UI.dialog_box_opaque())
	dlg.size = Vector2(380, 285) * _s
	dlg.position = ((get_viewport().get_visible_rect().size - dlg.size) / 2.0).floor()
	add_child(dlg)
	_select = dlg
	var client := Control.new()
	client.position = Vector2(4, 4) * _s
	client.size = dlg.size - Vector2(8, 8) * _s
	dlg.add_child(client)
	var lab := Label.new()
	lab.text = _t("sRepair", "Repair")
	UI.text_skin(lab, "SandText", _s)
	lab.position = Vector2(8, 8) * _s
	lab.size = Vector2(300, 18) * _s
	client.add_child(lab)
	var view := PanelContainer.new()
	view.add_theme_stylebox_override("panel", UI.inner_box())
	view.position = Vector2(8, 34) * _s
	view.size = Vector2(355, 200) * _s
	client.add_child(view)
	var grid := HFlowContainer.new()
	view.add_child(grid)
	for tid in main.repair.tools():
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(42, 42) * _s
		main.menu_mode.set_item_tip(cell, tid)
		var fr: Texture2D = UI.icon_frame(false, "")
		if fr != null:
			var fb := TextureRect.new()
			fb.texture = fr
			fb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fb.set_anchors_preset(Control.PRESET_FULL_RECT)
			fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(fb)
		_icon_image(cell, String(main.interaction.inventory.item(tid).rec.get("icon", "")), Vector2(5, 5) * _s)
		var tid2: String = tid
		cell.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				select_tool(tid2))
		grid.add_child(cell)
	var cb := Button.new()
	cb.text = L10n.ctx_text("Interface", "Cancel", "Cancel")
	client.add_child(cb)
	cb.pressed.connect(func():
		dlg.queue_free()
		_select = null)
	await get_tree().process_frame
	if is_instance_valid(cb):
		var bw := maxf(24 * _s, cb.get_combined_minimum_size().x)          # ExpandDirection Left od 364
		cb.position = Vector2(364 * _s - bw, 240 * _s)
		cb.size = Vector2(bw, 24 * _s)

## Repair::onItemSelected: nowe narzędzie, dźwięk odkładania przedmiotu.
func select_tool(tid: String) -> void:
	if _select != null:
		_select.queue_free()
		_select = null
	var snd := ""
	if main.get("interaction") != null:
		snd = String(main.interaction.item_sound(tid, false))
	_set_tool(tid, snd)
