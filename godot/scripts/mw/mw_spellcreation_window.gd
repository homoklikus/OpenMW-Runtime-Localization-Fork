extends CanvasLayer
## Okno tworzenia czarów jak OpenMW 0.51 (MWGui::SpellCreationDialog, openmw_spellcreation_dialog.layout):
## MW_Dialog 560 × 394 na środku: HBox (12, 12, 250, 30) sName + pole nazwy; sEnchantmentMenu4 i koszt
## many (280, 0), sSpellmakingMenu1 i szansa (280, 24) – wartości do prawej w 258 px; sMagicEffects (12, 48)
## + znane efekty MW_SimpleList (12, 76, 202, 269); sEffects (226, 48) + MW_Box (226, 76, 316, 269) z efektami;
## HBox (0, 336, 558, 60), Padding 16: sGold + złoto gracza, Spacer, sBarterDialog7 + cena, sBuy, Cancel.
## notifyEffectsChanged: y += max(1, calcEffectCost(PlayerSpell)), cel – y × 1,5 (narastająco); koszt int(y);
## cena max(1, int(y × fSpellMakingValueMult)) → oferta targowa; szansa min(100, calcSpellBaseSuccessChance).
## onBuyButtonClicked: sNotifyMessage30 (brak efektów), sNotifyMessage10 (nazwa), sEnchantmentMenu8 (koszt 0),
## sNotifyMessage18 (złoto); zapłata do puli kupca, „Mysticism Hit”, nowy czar gracza (ESMStore::insert).

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const MWList := preload("res://scripts/mw/mw_list.gd")
const Box := preload("res://scripts/mw/mw_box_layout.gd")
const Editor := preload("res://scripts/mw/mw_effect_editor.gd")

var main
var ui = null
var win: Control = null
var editor = null
var actor: Dictionary = {}
var name_edit: LineEdit = null
var labels := {}                 # MagickaCost, SuccessChance, PriceLabel, PlayerGold
var spell := {}                  # mSpell
var _s := 1.0
var _was_paused := false
var _mouse := Input.MOUSE_MODE_VISIBLE
var _layout := {}

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func _magic():
	return main.magic

func _msg(text: String) -> void:
	main._toast(text)

func is_open() -> bool:
	return visible

func open(a: Dictionary) -> void:
	_s = UI.ui_scale()
	ui = CU.new(main, _s)
	_build()
	visible = true
	set_ptr(a)
	_was_paused = get_tree().paused
	_mouse = Input.mouse_mode
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	name_edit.grab_focus()

func close() -> void:
	visible = false
	if editor != null:
		editor.close_all()
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = null
	# powrót do poprzedniego trybu GUI (rozmowa / ekwipunek) – stan pauzy i myszy sprzed otwarcia
	get_tree().paused = _was_paused
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse
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

func _build() -> void:
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = ui.modal(self, 560, 394, false)
	win.name = "SpellCreationDialog"
	var c: Control = win.get_meta("client")
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.text_submitted.connect(func(_t2): buy())
	c.add_child(name_edit)
	var name_row := {"type": "hbox", "children": [_text(c, _t("sName", "Name")),
		{"type": "widget", "control": name_edit, "size": Vector2(30, 30), "hstretch": true},
		{"type": "widget", "size": Vector2.ZERO}]}
	# koszt i szansa: TextBox 300 × 24 (Left) i wartość 258 × 24 (Right) – wyśrodkowane w pionie
	for spec in [[0, "sEnchantmentMenu4", "Magicka Cost", "MagickaCost"], [24, "sSpellmakingMenu1", "Chance", "SuccessChance"]]:
		var l: Label = ui.label(c, 280, spec[0], 300, 24, _t(spec[1], spec[2]), "header")
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var v: Label = ui.label(c, 280, spec[0], 258, 24, "", "sand", HORIZONTAL_ALIGNMENT_RIGHT)
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.name = String(spec[3])
		labels[spec[3]] = v
	ui.label(c, 12, 48, 300, 24, _t("sMagicEffects", "Magic Effects"), "header")
	var avail = MWList.new(_s)
	avail.name = "AvailableEffects"
	ui.at(avail, c, 12, 76, 202, 269)
	ui.label(c, 226, 48, 300, 24, _t("sEffects", "Effects"), "header")
	var ub: Control = ui.box(c, 226, 76, 316, 269)
	var sv := ScrollContainer.new()
	sv.name = "UsedEffects"
	ui.at(sv, ub, 4, 4, 308, 261)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(canvas)
	editor = Editor.new(main, ui, self, "spellmaking")
	editor.setup(avail, canvas)
	editor.on_changed = notify_effects_changed
	var gold_t := _text(c, _t("sGold", "Gold"))
	(gold_t.control as Label).name = "PlayerGoldTextBox"
	var gold := _text(c, "", "sand")
	(gold.control as Label).name = "PlayerGold"
	labels["PlayerGold"] = gold.control
	var price_t := _text(c, _t("sBarterDialog7", "Total Cost"))
	var price := _text(c, "", "sand")
	(price.control as Label).name = "PriceLabel"
	labels["PriceLabel"] = price.control
	var buy_b: Button = ui.button(_t("sBuy", "Buy"), buy)
	buy_b.name = "BuyButton"
	c.add_child(buy_b)
	var cancel: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), close)
	cancel.name = "CancelButton"
	c.add_child(cancel)
	var bottom := {"type": "hbox", "padding": 16, "children": [gold_t, gold, {"type": "spacer"}, price_t, price,
		{"type": "button", "control": buy_b}, {"type": "button", "control": cancel}]}
	_layout = {"name": [name_row, Rect2(12, 12, 250, 30)], "bottom": [bottom, Rect2(0, 336, 558, 60)]}
	relayout()

func relayout() -> void:
	var bl := Box.new(_s)
	for k in _layout:
		bl.place(_layout[k][0], _layout[k][1])

## setPtr: pusta nazwa, złoto gracza, startEditing.
func set_ptr(a: Dictionary) -> void:
	actor = a
	name_edit.text = ""
	(labels.PlayerGold as Label).text = str(main.trade.player_gold())
	editor.start_editing()

## notifyEffectsChanged.
func notify_effects_changed() -> void:
	var fx: Array = editor.effects
	if fx.is_empty():
		for k in ["MagickaCost", "PriceLabel", "SuccessChance"]:
			(labels[k] as Label).text = "0"
		relayout()
		return
	var m = _magic()
	var y := 0.0
	for e in fx:
		y += maxf(1.0, m.effect_cost(e, m.COST_PLAYER_SPELL))
		if int(e.get("range", 0)) == m.RT_TARGET:
			y *= 1.5
	spell = {"name": "", "spell_type": 0, "type_name": "spell", "cost": int(y), "flags": 0, "autocalc": false,
		"pc_start": false, "always_succeeds": false, "effects": fx.duplicate(true)}
	(labels.MagickaCost as Label).text = str(int(y))
	var price := maxi(1, int(y * m._gmst("fSpellMakingValueMult", 7.0)))
	price = main.trade.barter_offer(actor, price, true)
	(labels.PriceLabel as Label).text = str(price)
	var chance: float = m.spell_base_chance(spell, main.combat.player_fighter()).chance
	(labels.SuccessChance as Label).text = str(mini(100, int(chance)))
	relayout()

func buy() -> Dictionary:
	if editor.effects.is_empty():
		_msg(_t("sNotifyMessage30", "You must select at least one effect."))
		return {"ok": false, "message": "sNotifyMessage30"}
	if name_edit.text.is_empty():
		_msg(_t("sNotifyMessage10", "Please enter a name."))
		return {"ok": false, "message": "sNotifyMessage10"}
	if (labels.MagickaCost as Label).text == "0":
		_msg(_t("sEnchantmentMenu8", "This spell costs no magicka."))
		return {"ok": false, "message": "sEnchantmentMenu8"}
	var price := int((labels.PriceLabel as Label).text)
	if price > main.trade.player_gold():
		_msg(_t("sNotifyMessage18", "You do not have enough gold."))
		return {"ok": false, "message": "sNotifyMessage18"}
	spell["name"] = name_edit.text
	main.interaction.inventory.remove("player", {}, "gold_001", price)
	main.trade.set_merchant_gold(actor, main.trade.merchant_gold(actor) + price)
	if main.get("audio") != null and main.audio != null:
		main.audio.play("Mysticism Hit")
	var sid: String = _magic().create_record("spell", spell)
	_magic().add_spell(main.combat.player_fighter(), sid)
	close()
	return {"ok": true, "spell": sid, "price": price}

## Escape (WindowBase::exit): zamyka kolejno okna podrzędne, na końcu okno.
func escape() -> void:
	if editor != null and editor.sub != null and is_instance_valid(editor.sub):
		editor._close_sub()
	elif editor != null and editor.is_dialog_open():
		editor.cancel_clicked()
	else:
		close()
