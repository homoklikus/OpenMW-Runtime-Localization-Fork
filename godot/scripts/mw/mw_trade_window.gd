extends CanvasLayer
## Okna usług (etap 7, prosty interfejs – wygląd w etapie 10) nad oknem rozmowy, jak w OpenMW:
##   handel – towar kupca (cena kupna) i rzeczy gracza (cena sprzedaży); kliknięcie przenosi 1 sztukę do
##            koszyka (ponownie – z powrotem), suma, własna oferta (targowanie), złoto obu stron, „Oferta”;
##   zaklęcia – lista z cenami; trening – 3 umiejętności z cenami; podróż – cele z cenami.
## Logika w mw_trade.gd.

const Loc := preload("res://scripts/mw/mw_localization.gd")

const UI := preload("res://scripts/mw/mw_ui.gd")
var main
var trade
var mode := ""
var actor := {}
var panel: PanelContainer
var title: Label
var left: ItemList
var right: ItemList
var basket_label: Label
var offer_spin: SpinBox
var gold_label: Label
var offer_btn: Button
var buy := {}
var sell := {}
var sell_worn := {}                             # id → sztuki sprzedawane z założonego stosu
var _left_ids: Array = []
var _right_ids: Array = []
var _merchant: Array = []
var _player: Array = []
var grids_row: HBoxContainer
var merchant_head: Label
var player_head: Label
var merchant_grid: Control = null
var player_grid: Control = null
var _grid_parents: Array = []
var grid_merchant_ids: Array = []     # testy
var merchant_category := "all"         # kategoria okna kupca (SortFilterItemModel)
var merchant_filter := ""
var grid_player_ids: Array = []

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "TradeWindow"
	panel.custom_minimum_size = Vector2(980, 560)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.add_head(box, title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	left = _list(row)
	right = _list(row)
	# handel jak OpenMW: siatki ikon – towar kupca i rzeczy gracza; kliknięcie przenosi sztukę na drugą stronę
	# (tło menu_icon_barter), ponowne kliknięcie – cofa
	grids_row = HBoxContainer.new()
	grids_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grids_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grids_row.visible = false
	row.add_child(grids_row)
	var lbox := VBoxContainer.new()
	lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grids_row.add_child(lbox)
	merchant_head = UI.header("")
	lbox.add_child(merchant_head)
	var rbox := VBoxContainer.new()
	rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grids_row.add_child(rbox)
	player_head = UI.header("")
	rbox.add_child(player_head)
	_grid_parents = [lbox, rbox]
	left.item_clicked.connect(func(i, _p, _b): _click_left(i))
	right.item_clicked.connect(func(i, _p, _b): _click_right(i))
	basket_label = Label.new()
	basket_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(basket_label)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom)
	gold_label = Label.new()
	bottom.add_child(gold_label)
	offer_spin = SpinBox.new()
	offer_spin.min_value = -1000000
	offer_spin.max_value = 1000000
	offer_spin.allow_greater = true
	offer_spin.allow_lesser = true
	bottom.add_child(offer_spin)
	offer_btn = Button.new()
	offer_btn.pressed.connect(func(): make_offer())
	bottom.add_child(offer_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Cancel"
	clear_btn.name = "Clear"
	clear_btn.pressed.connect(func(): buy = {}; sell = {}; sell_worn = {}; refresh())
	bottom.add_child(clear_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)
	visible = false

func _list(parent: Control) -> ItemList:
	var l := ItemList.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func _name(id: String) -> String:
	var it: Dictionary = main.interaction.inventory.item(id)
	return main.interaction.item_name(String(it.get("kind", "")), id, it.get("rec", {})) if not it.is_empty() else id

## Otwiera usługę; Service Refusal (odmowa wg postawy) – odpowiedź w oknie rozmowy, okno usługi się nie otwiera.
func open(service: String) -> bool:
	actor = main.dialogue.actor
	if actor.is_empty() or trade.refused(service):
		main.dialogue_window.refresh()
		return false
	if service == "enchanting":                       # GM_Enchanting (EnchantingDialog::setPtr z NPC)
		main.enchanting_window.open_for(actor)
		return true
	if service == "spellmaking":                      # GM_SpellCreation (SpellCreationDialog::setPtr)
		main.spellcreation_window.open(actor)
		return true
	if service in ["spells", "travel", "training", "repair"] and main.get("service_window") != null:
		main.service_window.open(service, actor)        # SpellBuyingWindow / TravelWindow / TrainingWindow
		return true
	mode = service
	buy = {}
	sell = {}
	sell_worn = {}
	merchant_category = "all"
	merchant_filter = ""
	trade.restock(actor)
	visible = true
	if service == "barter" and main.get("menu_mode") != null:
		# GM_Barter (updateVisible): okno ekwipunku gracza i okno kupca, okno rozmowy ukryte
		panel.visible = false
		merchant_grid = null
		player_grid = null
		main.menu_mode.open_barter(self)            # GM_Barter nad GM_Dialogue (rozmowa ukryta przez stos trybów)
		return true
	panel.visible = true
	refresh()
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	return true

func refresh() -> void:
	left.clear()
	right.clear()
	_left_ids = []
	_right_ids = []
	var pg: int = trade.player_gold()
	right.visible = false
	left.visible = mode != "barter"
	grids_row.visible = mode == "barter"
	offer_spin.visible = mode == "barter"
	offer_btn.visible = mode == "barter"
	(panel.find_child("Clear", true, false) as Button).visible = mode == "barter"
	match mode:
		"barter":
			title.text = "%s – %s" % [_t("sBarter", "Barter"), main.dialogue.actor_name(actor)]
			_merchant = trade.merchant_items(actor)
			_player = trade.player_items(actor)
			for it in _merchant:
				var left_n := int(it.count) - int(buy.get(it.id, 0))
				if left_n <= 0:
					continue
				var price: int = trade.barter_offer(actor, trade.item_value(it.id, true), true)
				left.add_item("%s%s – %d" % [_name(it.id), (" (%d)" % left_n) if left_n > 1 else "", price])
				_left_ids.append(it.id)
			for it in _player:
				var left_p := int(it.count) - int(sell.get(it.id, 0))
				if left_p <= 0:
					continue
				var p2: int = trade.barter_offer(actor, trade.item_value(it.id, true), false)
				right.add_item("%s%s – %d" % [_name(it.id), (" (%d)" % left_p) if left_p > 1 else "", p2])
				_right_ids.append(it.id)
			_fill_barter_grids()
			var mo: int = trade.merchant_offer(actor, buy, sell)
			offer_spin.set_value_no_signal(mo)          # TradeWindow::updateOffer: saldo = oferta kupca
			_barter_labels()
			var lines := []
			for id in buy:
				lines.append("buying: %s × %d" % [_name(id), int(buy[id])])
			for id in sell:
				lines.append("selling: %s × %d" % [_name(id), int(sell[id])])
			basket_label.text = ("\n".join(lines) + "\n" if not lines.is_empty() else "") + \
				"%s: %d (negative – you pay). You can change the amount and haggle." % [_t("sTotalCost", "Total"), mo]
			offer_btn.text = _t("sBarterDialog8", "Offer")
			gold_label.text = "%s %d   %s %d" % [_t("sYourGold", "Your gold:"), pg, _t("sSellerGold", "Seller gold:"), trade.merchant_gold(actor)]
		"spells":
			title.text = "%s – %s" % [_t("sSpells", "Spells"), main.dialogue.actor_name(actor)]
			for s in trade.spells_for_sale(actor):
				left.add_item("%s – %d" % [s.name, int(s.price)])
				left.set_item_disabled(left.item_count - 1, int(s.price) > pg)
				_left_ids.append(s.id)
			basket_label.text = "Click a spell to buy it."
			gold_label.text = "%s %d" % [_t("sGold", "Gold:"), pg]
		"training":
			title.text = "%s – %s" % [_t("sServiceTrainingTitle", "Training"), main.dialogue.actor_name(actor)]
			var names: Array = main.character.skill_names()
			for o in trade.training_offers(actor):
				var sid := String(names[int(o.skill)])
				left.add_item("%s – %d" % [_t("sSkill" + sid.capitalize().replace(" ", ""), sid), int(o.price)])
				left.set_item_disabled(left.item_count - 1, int(o.price) > pg)
				_left_ids.append(int(o.skill))
			basket_label.text = "Training takes 2 hours."
			gold_label.text = "%s %d" % [_t("sGold", "Gold:"), pg]
		"travel":
			title.text = "%s – %s" % [_t("sTravel", "Travel"), main.dialogue.actor_name(actor)]
			for o in trade.travel_offers(actor):
				left.add_item("%s – %d" % [String(o.name), int(o.price)])
				left.set_item_disabled(left.item_count - 1, int(o.price) > pg)
				_left_ids.append(int(o.index))
			basket_label.text = ""
			gold_label.text = "%s %d" % [_t("sGold", "Gold:"), pg]

## Wpis siatki z kluczami SortFilterItemModel (Type_Barter – przedmioty w koszyku, Type_Equipped – założone
## przez gracza, Type_Normal – reszta).
func _entry(it: Dictionary, count: int, src: String, merchant_side: bool, state := "", stack := {}) -> Dictionary:
	var item: Dictionary = main.interaction.inventory.item(String(it.id))
	var price: int = trade.barter_offer(actor, trade.item_value(String(it.id), true), merchant_side)
	var worn: bool = src == "player" and main.has_method("equipped_slot_of") and main.equipped_slot_of(String(it.id)) >= 0
	if stack.has("worn"):
		worn = src == "player" and bool(stack.worn)
	var e := {"id": String(it.id), "count": count, "rec": item.get("rec", {}), "worn": worn, "kind": String(item.get("kind", "")),
		"name": main.interaction.item_name(String(item.get("kind", "")), String(it.id), item.get("rec", {})),
		"magic": not String(item.get("rec", {}).get("enchant", "")).is_empty(), "state": state, "source": src,
		"tip": "%s: %d" % [_t("sBarterDialog7", "Price"), price]}
	if not stack.is_empty():
		e["stack"] = {"count": count, "worn": worn}
	var stype := 0 if state == "barter" else (1 if worn else 2)
	return main.menu_mode.sort_keys(e, stype, "player" if src in ["player", "sold"] else "")

## Stosy (ItemStack) wpisu towaru po odjęciu sztuk w koszyku: [{count, worn}]. Koszyk zabiera sztuki od ostatnich
## niezałożonych stosów (kupiec – stosy przedmiotów ze skryptem; gracz – także założony egzemplarz osobno).
static func split_stacks(it: Dictionary, remaining: int, worn_cut := 0) -> Array:
	var st := []
	for x in it.get("stacks", []):
		st.append({"count": int(x.count), "worn": bool(x.get("worn", false))} if x is Dictionary else {"count": int(x), "worn": false})
	if st.is_empty():
		st = [{"count": int(it.count), "worn": false}]
	var cut := 0
	for x in st:
		cut += int(x.count)
	cut -= maxi(0, remaining)
	var wcut := mini(worn_cut, cut)
	for i in range(st.size() - 1, -1, -1):          # sztuki z założonego stosu w koszyku (sellItem ze stosu Equipped)
		if wcut <= 0:
			break
		if bool(st[i].worn):
			var m := mini(wcut, int(st[i].count))
			st[i].count = int(st[i].count) - m
			wcut -= m
			cut -= m
	for worn_pass in [false, true]:
		for i in range(st.size() - 1, -1, -1):
			if cut <= 0:
				break
			if bool(st[i].worn) != worn_pass:
				continue
			var n := mini(cut, int(st[i].count))
			st[i].count = int(st[i].count) - n
			cut -= n
	return st.filter(func(x): return int(x.count) > 0)

func _fill_barter_grids() -> void:
	var mm = main.menu_mode
	if merchant_grid == null or not is_instance_valid(merchant_grid):
		if mm.barter == self:
			return                                 # okna handlu jeszcze budowane
		mm.scale_ui = UI.ui_scale()
		merchant_grid = mm._make_grid(_grid_parents[0], "merchant", self)
		player_grid = mm._make_grid(_grid_parents[1], "player", self)
	merchant_head.text = main.dialogue.actor_name(actor)
	player_head.text = _t("sInventory", "Inventory")
	if mm.barter == self:
		mm._title("barter", main.dialogue.actor_name(actor))
	var me := []
	var flt := merchant_filter.strip_edges().to_lower()
	for it in _merchant:
		var n := int(it.count) - int(buy.get(it.id, 0))
		if n > 0 and _merchant_shown(String(it.id), flt):
			for st in split_stacks(it, n):
				me.append(_entry(it, int(st.count), "merchant", true, "", st))
	for it in _player:                             # sprzedawane – po stronie kupca, z tłem „barter”
		if int(sell.get(it.id, 0)) > 0 and _merchant_shown(String(it.id), flt):
			me.append(_entry(it, int(sell[it.id]), "sold", false, "barter"))
	var pe := []
	for it in _player:
		var n2 := int(it.count) - int(sell.get(it.id, 0))
		if n2 > 0:
			for st in split_stacks(it, n2, int(sell_worn.get(it.id, 0))):
				pe.append(_entry(it, int(st.count), "player", false, "", st))
	for it in _merchant:                           # kupowane – po stronie gracza
		if int(buy.get(it.id, 0)) > 0:
			pe.append(_entry(it, int(buy[it.id]), "bought", true, "barter"))
	me.sort_custom(mm.item_less)                   # SortFilterItemModel::Compare
	pe.sort_custom(mm.item_less)
	grid_merchant_ids = mm._fill_grid(merchant_grid, me, "merchant", self)
	grid_player_ids = mm._fill_grid(player_grid, pe, "player", self)

## Kategoria i filtr nazw okna kupca (jak w ekwipunku).
func _merchant_shown(id: String, flt: String) -> bool:
	var it: Dictionary = main.interaction.inventory.item(id)
	if it.is_empty():
		return false
	var mm = main.menu_mode
	if not mm.in_category(String(it.kind), not String(it.rec.get("enchant", "")).is_empty(), merchant_category):
		return false
	return flt.is_empty() or _name(id).to_lower().contains(flt)

func _barter_labels() -> void:
	if main.menu_mode.barter == self:
		main.menu_mode.barter_labels(int(offer_spin.value), trade.player_gold(), trade.merchant_gold(actor))

## TradeWindow::onIncrease/DecreaseButtonTriggered: zwiększa / zmniejsza wartość bezwzględną salda o 1
## (przy zerze – od zera, znak zostaje).
func change_balance(d: int) -> void:
	var b := int(offer_spin.value)
	if b < 0:
		b -= d
	else:
		b += d
	offer_spin.set_value_no_signal(b)
	_barter_labels()

## TradeWindow::onBalanceValueChanged: wpisana kwota ze znakiem bieżącego salda (0 – bez zmiany znaku).
func set_balance_abs(v: int) -> void:
	var b := int(offer_spin.value)
	var sign := -1 if b < 0 else 1
	if v == 0:
		return
	offer_spin.set_value_no_signal(sign * absi(v))
	_barter_labels()

## TradeWindow::onMaxSaleButtonClicked: saldo = złoto kupca.
func max_sale() -> void:
	offer_spin.set_value_no_signal(trade.merchant_gold(actor))
	_barter_labels()

## Kliknięcie ikony w siatce handlu (TradeWindow::onItemSelected / InventoryWindow::onItemSelected przy handlu):
## towar kupca → koszyk zakupu, rzecz gracza → sprzedaż, z tłem „barter” – cofnięcie. Stos > 1 bez Shift –
## okno ilości (okno kupca: sQuanityMenuMessage02, ekwipunek: sQuanityMenuMessage01), domyślnie cały stos;
## Ctrl – 1 sztuka.
var pressed_stack := {}                        # stos klikniętej komórki ({count, worn}) – ItemStack::mCount

func click_item(id: String, source: String, mods := {}) -> void:
	var avail := _available(id, source)
	if source in ["merchant", "player"] and pressed_stack.has("count"):
		avail = mini(avail, int(pressed_stack.count))
	var from_worn := source == "player" and bool(pressed_stack.get("worn", false))
	if avail <= 0:
		return
	if source == "player" and not trade.can_sell(id, trade.services(actor)):
		# InventoryWindow::onItemSelectedFromSourceModel: kupiec tego nie przyjmuje – dźwięk odłożenia i komunikat
		if main != null and main.get("audio") != null and main.get("interaction") != null:
			main.audio.play(main.interaction.item_sound(id, false))
		if main != null and main.has_method("_toast"):
			main._toast(_t("sBarterDialog4", "The merchant does not want that item."))
		return
	var msg := "sQuanityMenuMessage02" if source in ["merchant", "sold"] else "sQuanityMenuMessage01"
	if main != null and main.get("menu_mode") != null:
		main.menu_mode.ask_count(id, avail, msg, mods, func(n: int): move_item(id, source, n, from_worn))
	else:
		move_item(id, source, 1 if bool(mods.get("ctrl", false)) else avail, from_worn)

## Liczba sztuk stosu widocznego w danej siatce.
func _available(id: String, source: String) -> int:
	match source:
		"merchant":
			for it in trade.merchant_items(actor):
				if String(it.id) == id:
					return int(it.count) - int(buy.get(id, 0))
		"player":
			for it in trade.player_items(actor):
				if String(it.id) == id:
					return int(it.count) - int(sell.get(id, 0))
		"bought":
			return int(buy.get(id, 0))
		"sold":
			return int(sell.get(id, 0))
	return 0

## sellItem/borrowItem/returnItem: przeniesienie n sztuk między stronami handlu (dźwięk podniesienia).
func move_item(id: String, source: String, n: int, from_worn := false) -> void:
	n = mini(n, _available(id, source))
	if n <= 0:
		return
	match source:
		"merchant": buy[id] = int(buy.get(id, 0)) + n
		"player":
			sell[id] = int(sell.get(id, 0)) + n
			if from_worn:
				sell_worn[id] = int(sell_worn.get(id, 0)) + n
		"bought":
			buy[id] = int(buy.get(id, 0)) - n
			if int(buy[id]) <= 0:
				buy.erase(id)
		"sold":
			sell[id] = int(sell.get(id, 0)) - n
			if int(sell_worn.get(id, 0)) > int(sell.get(id, 0)):     # cofnięte najpierw sztuki niezałożone
				sell_worn[id] = maxi(0, int(sell.get(id, 0)))
			if int(sell[id]) <= 0:
				sell.erase(id)
				sell_worn.erase(id)
	if main != null and main.get("audio") != null and main.get("interaction") != null:
		main.audio.play(main.interaction.item_sound(id, true))       # getUpSoundId
	refresh()

func activate_item(_id: String, _source: String, _mods := {}) -> void:
	pass                                           # OpenMW nie ma dwukliku – pierwsze kliknięcie otwiera okno ilości

## Przeciągnięcie na drugą siatkę – jak kliknięcie przedmiotu (z oknem ilości).
func dropped_on(target: String, data: Dictionary) -> void:
	var src := String(data.get("source", ""))
	if (target == "merchant" and src in ["player", "bought"]) or (target == "player" and src in ["merchant", "sold"]):
		pressed_stack = data.get("stack", {}) if data.get("stack") is Dictionary else {}
		click_item(String(data.get("mw_item", "")), src, data)
		pressed_stack = {}

func _click_left(i: int) -> void:
	if i < 0 or i >= _left_ids.size():
		return
	match mode:
		"barter":
			var id: String = _left_ids[i]
			buy[id] = int(buy.get(id, 0)) + 1
			refresh()
		"spells":
			if trade.buy_spell(actor, _left_ids[i]):
				refresh()
		"training":
			var r: Dictionary = trade.train(actor, int(_left_ids[i]))
			if not String(r.message).is_empty():
				main._toast(String(r.message))
			if bool(r.ok):
				close()
				main.dialogue_window.close(true)        # po treningu – powrót do gry (exitCurrentGuiMode)
		"travel":
			var idx := int(_left_ids[i])
			close()
			main.dialogue_window.close(true)
			trade.travel(actor, idx)

func _click_right(i: int) -> void:
	if mode != "barter" or i < 0 or i >= _right_ids.size():
		return
	var id: String = _right_ids[i]
	sell[id] = int(sell.get(id, 0)) + 1
	refresh()

## „Oferta”: kwota z pola (dodatnia – kupiec płaci). roll – test.
func make_offer(roll := -1) -> Dictionary:
	var r: Dictionary = trade.offer(actor, buy, sell, int(offer_spin.value), roll, sell_worn)
	if not String(r.message).is_empty():
		main._toast(String(r.message))
	if bool(r.ok):
		close()
	else:
		refresh()
	main.dialogue_window.refresh()
	return r

func close() -> void:
	var was_barter: bool = main != null and main.get("menu_mode") != null and main.menu_mode.barter == self
	visible = false
	buy = {}
	sell = {}
	sell_worn = {}
	if was_barter:
		main.menu_mode.close()
		merchant_grid = null
		player_grid = null
