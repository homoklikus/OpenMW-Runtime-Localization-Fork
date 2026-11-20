extends CanvasLayer
## Okno zaklinania jak OpenMW 0.51 (MWGui::EnchantingDialog, files/data/mygui/openmw_enchanting_dialog.layout):
## MW_Dialog 560 × 448 na środku ekranu, układ Gui::HBox/VBox (mw_box_layout.gd):
##   HBox (12, 9, 273, 30), odstęp 8: sName, pole nazwy (HStretch);
##   HBox (12, 48, 265, 59), odstęp 8: sItem + ItemBox 50 × 50, Spacer, sSoulGem + SoulBox 50 × 50;
##   VBox (320, 7, 222, 96): sEnchantmentMenu3 („a / b”), sCastCost, sCharges, sEnchantmentMenu6 (ChanceLayout);
##   sMagicEffects (12, 109) + lista znanych efektów MW_SimpleList (12, 136, 202, 269);
##   sEffects (226, 109) + MW_Box (226, 136, 316, 269) z listą efektów (ScrollView 4, 4, 308, 261);
##   HBox (0, 392, 558, 60), Padding 16: TypeButton, Spacer, sBarterDialog7 + cena, Buy/Create, Cancel.
## setPtr: zaklinacz (NPC) – sBuy, cena widoczna, szansa ukryta, bez kamienia; kamień dusz gracza –
## samodzielne zaklinanie, sCreate, szansa wg [Game] show enchant chance, kamień w SoulBox, cena ukryta.
## Mechanika – MWMechanics::Enchanting (mw_magic.gd: ench_*).

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const MWList := preload("res://scripts/mw/mw_list.gd")
const Box := preload("res://scripts/mw/mw_box_layout.gd")
const Editor := preload("res://scripts/mw/mw_effect_editor.gd")
const Selection := preload("res://scripts/mw/mw_item_selection.gd")

var main
var ui = null
var win: Control = null
var editor = null
var selection = null
var enchanter: Dictionary = {}        # aktor rozmowy (NPC) albo {} – gracz (samodzielne)
var self_enchanting := false
var item_id := ""                     # mOldItemPtr
var gem_id := ""                      # mSoulGemPtr (Enchanting)
var soul_box_id := ""                 # przedmiot pokazany w SoulBox
var cast_style := 0                   # ESM::Enchantment::CastOnce
var name_edit: LineEdit = null
var labels := {}                      # Enchantment, CastCost, Charge, SuccessChance, PriceLabel
var type_button: Button = null
var buy_button: Button = null
var _s := 1.0
var _layout := {}
var _item_box: Control = null
var _soul_box: Control = null
var _chance_nodes: Array = []
var _price_nodes: Array = []

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func _me() -> Dictionary:
	return main.combat.player_fighter()

func _magic():
	return main.magic

func _msg(text: String) -> void:
	main._toast(text)

func is_open() -> bool:
	return visible

## GM_Enchanting z usługi zaklinacza (a – aktor rozmowy) albo z użycia kamienia dusz (gem – stos z duszą).
func open_for(a: Dictionary, gem := "") -> void:
	_s = UI.ui_scale()
	ui = CU.new(main, _s)
	_build()
	visible = true
	set_ptr(a, gem)
	main.gui.push("enchanting", [self], escape)
	name_edit.grab_focus()

func close() -> void:
	visible = false
	if editor != null:
		editor.close_all()
	if selection != null:
		selection.close()
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = null
	main.gui.remove("enchanting")                       # powrót do poprzedniego trybu GUI
	if main.get("dialogue_window") != null and main.dialogue_window != null and main.dialogue_window.visible:
		main.dialogue_window.refresh()

func _text(parent: Control, text: String, kind := "header") -> Dictionary:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UI.color("header") if kind == "header" else UI.color("normal"))
	parent.add_child(l)
	return {"type": "text", "control": l}

func _tip(n: Dictionary, help: String) -> Dictionary:
	# TextToolTip (Layout) z tekstem pomocy
	(n.control as Control).set_meta("mw_tip", {"type": "layout", "layout": "text", "description": _t(help, "")})
	return n

func _build() -> void:
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = ui.modal(self, 560, 448, false)
	win.name = "EnchantingDialog"
	var c: Control = win.get_meta("client")
	# nazwa
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.text_submitted.connect(func(_t2): buy())
	c.add_child(name_edit)
	var name_row := {"type": "hbox", "spacing": 8, "children": [
		_tip(_text(c, _t("sName", "Name")), "sEnchantmentHelp8"),
		{"type": "widget", "control": name_edit, "size": Vector2(30, 30), "hstretch": true},
		{"type": "widget", "size": Vector2.ZERO}]}
	# przedmiot i kamień
	_item_box = _icon_box(c, "ItemBox", select_item)
	_soul_box = _icon_box(c, "SoulBox", select_soul)
	var item_row := {"type": "hbox", "spacing": 8, "children": [
		_tip(_text(c, _t("sItem", "Item")), "sEnchantmentHelp1"),
		{"type": "widget", "control": _item_box, "size": Vector2(50, 50)},
		{"type": "spacer"},
		_tip(_text(c, _t("sSoulGem", "Soul Gem")), "sEnchantmentHelp2"),
		{"type": "widget", "control": _soul_box, "size": Vector2(50, 50)}]}
	# wartości
	var rows := []
	for spec in [["Enchantment", _t("sEnchantmentMenu3", "Enchantment") + ":", "sEnchantmentHelp3"],
			["CastCost", _t("sCastCost", "Cast Cost") + ":", "sEnchantmentHelp4"],
			["Charge", _t("sCharges", "Charges"), "sEnchantmentHelp5"],
			["SuccessChance", _t("sEnchantmentMenu6", "Chance") + ":", ""]]:
		var lab := _text(c, String(spec[1]))
		if not String(spec[2]).is_empty():
			_tip(lab, String(spec[2]))
		var val := _text(c, "", "sand")
		(val.control as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		(val.control as Label).name = String(spec[0])
		val["hstretch"] = true
		labels[spec[0]] = val.control
		rows.append({"type": "hbox", "hstretch": true, "children": [lab, val]})
		if spec[0] == "SuccessChance":
			_chance_nodes = [lab.control, val.control]
	var values := {"type": "vbox", "children": rows}
	# listy efektów
	_tip({"control": ui.label(c, 12, 109, 300, 24, _t("sMagicEffects", "Magic Effects"), "header")}, "sEnchantmentHelp9")
	var avail = MWList.new(_s)
	avail.name = "AvailableEffects"
	ui.at(avail, c, 12, 136, 202, 269)
	_tip({"control": ui.label(c, 226, 109, 300, 24, _t("sEffects", "Effects"), "header")}, "sEnchantmentHelp10")
	var ub: Control = ui.box(c, 226, 136, 316, 269)
	var sv := ScrollContainer.new()
	sv.name = "UsedEffects"
	sv.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ui.at(sv, ub, 4, 4, 308, 261)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(canvas)
	editor = Editor.new(main, ui, self, "enchanting")
	editor.setup(avail, canvas)
	editor.on_changed = notify_effects_changed
	selection = Selection.new(main, ui)
	# przyciski
	type_button = ui.button("Constant effect", type_clicked)
	type_button.name = "TypeButton"
	type_button.set_meta("mw_tip", {"type": "layout", "layout": "text", "description": _t("sEnchantmentHelp7", "")})
	c.add_child(type_button)
	var price_text := _tip(_text(c, _t("sBarterDialog7", "Total Cost")), "sEnchantmentHelp6")
	(price_text.control as Label).name = "PriceTextLabel"
	var price := _text(c, "0", "sand")
	(price.control as Label).name = "PriceLabel"
	labels["PriceLabel"] = price.control
	_price_nodes = [price_text.control, price.control]
	buy_button = ui.button(_t("sBuy", "Buy"), buy)
	buy_button.name = "BuyButton"
	c.add_child(buy_button)
	var cancel: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), close)
	cancel.name = "CancelButton"
	c.add_child(cancel)
	var bottom := {"type": "hbox", "padding": 16, "children": [
		{"type": "button", "control": type_button}, {"type": "spacer"}, price_text, price,
		{"type": "button", "control": buy_button}, {"type": "button", "control": cancel}]}
	_layout = {"name": [name_row, Rect2(12, 9, 273, 30)], "item": [item_row, Rect2(12, 48, 265, 59)],
		"values": [values, Rect2(320, 7, 222, 96)], "bottom": [bottom, Rect2(0, 392, 558, 60)]}
	relayout()

## Box::notifyChildrenSizeChanged po zmianie napisów (AutoSizedTextBox/AutoSizedButton).
func relayout() -> void:
	var bl := Box.new(_s)
	for k in _layout:
		bl.place(_layout[k][0], _layout[k][1])

func _icon_box(parent: Control, nm: String, cb: Callable) -> Control:
	var b := Control.new()
	b.name = nm
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cb.call())
	parent.add_child(b)
	return b

## MW_ItemIconBox: tło menu_icon_magic dla zaklętych, cień i ikona 32 × 32 od (9, 9), ramka MW_Box_Overlay.
func _fill_box(b: Control, id: String) -> void:
	for ch in b.get_children():
		b.remove_child(ch)
		ch.queue_free()
	b.tooltip_text = ""
	if not id.is_empty():
		var it: Dictionary = main.interaction.inventory.item(id)
		if not it.is_empty():
			var fr := UI.icon_frame(not _magic().item_enchantment(it).is_empty(), "")
			if fr != null:
				var fb := TextureRect.new()
				fb.texture = fr
				fb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				fb.position = Vector2(4, 4) * _s
				fb.size = Vector2(42, 42) * _s
				fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(fb)
			var tex: Texture2D = UI.icon(String(it.rec.get("icon", "")))
			if tex != null:
				var sh := TextureRect.new()
				sh.texture = tex
				sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				sh.modulate = Color(0, 0, 0, 0.5)
				sh.position = Vector2(13, 13) * _s
				sh.size = Vector2(32, 32) * _s
				sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(sh)
				var ic := TextureRect.new()
				ic.texture = tex
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.position = Vector2(9, 9) * _s
				ic.size = Vector2(32, 32) * _s
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(ic)
			main.menu_mode.set_item_tip(b, id)
	var ov := Panel.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_theme_stylebox_override("panel", UI.inner_box())
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ov)

# --- EnchantingDialog --------------------------------------------------------------------------------------

## setPtr.
func set_ptr(a: Dictionary, gem := "") -> void:
	name_edit.text = ""
	if not a.is_empty():
		self_enchanting = false
		enchanter = a
		cast_style = _magic().ENCH_CAST_ONCE              # setEnchanter: reset sposobu
		buy_button.text = _t("sBuy", "Buy")
		for n in _chance_nodes:
			(n as Control).visible = false
		_set_soul_gem("")
		for n in _price_nodes:
			(n as Control).visible = true
	else:
		self_enchanting = true
		enchanter = {}
		cast_style = _magic().ENCH_CAST_ONCE
		buy_button.text = _t("sCreate", "Create")
		for n in _chance_nodes:
			(n as Control).visible = bool(main.settings.get("show_enchant_chance", false))
		_set_soul_gem(gem)
		for n in _price_nodes:
			(n as Control).visible = false
	_set_item("")
	editor.start_editing()
	update_labels()

func _set_soul_gem(id: String) -> void:
	soul_box_id = id
	gem_id = id
	_fill_box(_soul_box, id)

func _set_item(id: String) -> void:
	if not id.is_empty():
		var it: Dictionary = main.interaction.inventory.item(id)
		name_edit.text = main.interaction.item_name(String(it.get("kind", "")), id, it.get("rec", {}))
	item_id = id
	_fill_box(_item_box, id)

func _state() -> Dictionary:
	return {"item": item_id, "gem": gem_id, "cast": cast_style, "effects": editor.effects,
		"enchanter": enchanter, "self": self_enchanting}

## updateLabels.
func update_labels() -> void:
	var st := _state()
	var m = _magic()
	(labels.Enchantment as Label).text = "%d / %d" % [int(m.ench_points(st, false)), m.ench_max_value(st)]
	(labels.Charge as Label).text = str(m.gem_charge(gem_id) if not gem_id.is_empty() else 0)
	(labels.SuccessChance as Label).text = str(clampi(m.ench_chance(st), 0, 100))
	(labels.CastCost as Label).text = str(m.ench_effective_cast_cost(st))
	(labels.PriceLabel as Label).text = str(m.ench_price(st))
	var caps := [["sItemCastOnce", "Cast Once"], ["sItemCastWhenStrikes", "When Strikes"],
		["sItemCastWhenUsed", "When Used"], ["sItemCastConstant", "Cast Constant"]]
	var cap: Array = caps[clampi(cast_style, 0, 3)]
	type_button.text = _t(cap[0], cap[1])
	editor.set_constant(cast_style == m.ENCH_CONSTANT)
	_resize_buttons()
	relayout()

func _resize_buttons() -> void:
	for b in [type_button, buy_button]:
		(b as Button).size = Vector2(ui.text_width((b as Button).text) + 24 * _s, 24 * _s)

func notify_effects_changed() -> void:
	update_labels()

## onSelectItem: bez przedmiotu – ItemSelectionDialog (sEnchantItems, Filter_OnlyEnchantable); z przedmiotem – zdjęcie.
func select_item() -> void:
	if item_id.is_empty():
		selection.open(self, _t("sEnchantItems", "Enchant items"), _magic().ench_enchantable_entry,
			item_selected, func(): selection.close())
	else:
		_set_item("")
		update_labels()

## onItemSelected: dźwięk odkładania, nextCastStyle.
func item_selected(id: String) -> void:
	selection.close()
	_set_item(id)
	if main.get("audio") != null and main.audio != null:
		main.audio.play(main.interaction.item_sound(id, false))
	cast_style = _magic().ench_next_cast_style(_state())
	update_labels()

## onSelectSoul: bez kamienia – ItemSelectionDialog (sSoulGemsWithSouls, Filter_OnlyChargedSoulstones);
## z kamieniem – zdjęcie, nextCastStyle, odświeżenie efektów.
func select_soul() -> void:
	if gem_id.is_empty():
		selection.open(self, _t("sSoulGemsWithSouls", "Soul gems with souls"), _magic().ench_soulstone_entry,
			soul_selected, func(): selection.close())
	else:
		_set_soul_gem("")
		cast_style = _magic().ench_next_cast_style(_state())
		update_labels()
		editor.update_effects_view()

## onSoulSelected: kamień trafia do Enchanting; ładunek 0 – sNotifyMessage32 (SoulBox bez zmian).
func soul_selected(id: String) -> void:
	selection.close()
	gem_id = id
	if _magic().gem_charge(id) == 0:
		_msg(_t("sNotifyMessage32", "This soul gem is empty."))
		return
	_set_soul_gem(id)
	if main.get("audio") != null and main.audio != null:
		main.audio.play(main.interaction.item_sound(id, false))
	update_labels()

func type_clicked() -> void:
	cast_style = _magic().ench_next_cast_style(_state())
	update_labels()
	editor.update_effects_view()

## onBuyButtonClicked: kolejność komunikatów jak w OpenMW, kradzione od zaklinacza – sNotifyMessage49,
## konfiskata i zamknięcie; create(): sukces – „enchant success”, sEnchantmentMenu12, zamknięcie; porażka –
## „enchant fail”, sNotifyMessage34, zużyty kamień zdjęty (nextCastStyle).
func buy() -> Dictionary:
	if editor.effects.is_empty():
		_msg(_t("sEnchantmentMenu11", "You must select an effect."))
		return {"ok": false, "message": "sEnchantmentMenu11"}
	if name_edit.text.is_empty():
		_msg(_t("sNotifyMessage10", "Please enter a name."))
		return {"ok": false, "message": "sNotifyMessage10"}
	if gem_id.is_empty():
		_msg(_t("sNotifyMessage52", "Select a soul gem."))
		return {"ok": false, "message": "sNotifyMessage52"}
	if item_id.is_empty():
		_msg(_t("sNotifyMessage11", "Select an item."))
		return {"ok": false, "message": "sNotifyMessage11"}
	var st := _state()
	var m = _magic()
	if int(m.ench_points(st, false)) > m.ench_max_value(st):
		_msg(_t("sNotifyMessage29", "The enchantment is too powerful for this item."))
		return {"ok": false, "message": "sNotifyMessage29"}
	if not self_enchanting and m.ench_price(st) > main.trade.player_gold():
		_msg(_t("sNotifyMessage18", "You do not have enough gold."))
		return {"ok": false, "message": "sNotifyMessage18"}
	if not self_enchanting:
		for id in [item_id, gem_id]:
			if main.crime.is_item_stolen_from(String(id), enchanter):
				var it: Dictionary = main.interaction.inventory.item(String(id))
				var nm: String = main.interaction.item_name(String(it.get("kind", "")), String(id), it.get("rec", {}))
				_msg(_t("sNotifyMessage49", "%s").replace("%s", nm))
				main.crime.confiscate_to_owner(String(id), enchanter, 1)
				close()
				if main.get("dialogue_window") != null and main.dialogue_window.visible:
					main.dialogue_window.close()
				return {"ok": false, "message": "sNotifyMessage49"}
	st["name"] = name_edit.text
	var res: Dictionary = m.ench_create(_me(), st)
	if bool(res.get("ok", false)):
		if main.get("audio") != null and main.audio != null:
			main.audio.play("enchant success")
		_msg(_t("sEnchantmentMenu12", "You successfully enchanted the item."))
		close()
	else:
		if main.get("audio") != null and main.audio != null:
			main.audio.play("enchant fail")
		_msg(_t("sNotifyMessage34", "You failed to enchant the item."))
		if not gem_id.is_empty() and main.interaction.inventory.count_of("player", {}, gem_id) <= 0:
			_set_soul_gem("")
			cast_style = m.ench_next_cast_style(_state())
			update_labels()
			editor.update_effects_view()
	return res

## Escape (WindowBase::exit): zamyka kolejno okna podrzędne, na końcu okno.
func escape() -> void:
	if selection != null and selection.is_open():
		selection.close()
	elif editor != null and editor.sub != null and is_instance_valid(editor.sub):
		editor._close_sub()
	elif editor != null and editor.is_dialog_open():
		editor.cancel_clicked()
	else:
		close()
