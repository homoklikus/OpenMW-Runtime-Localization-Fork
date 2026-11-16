extends CanvasLayer
## Okna usług (etap 7, prosty interfejs – wygląd w etapie 10) nad oknem rozmowy, jak w OpenMW:
##   handel – towar kupca (cena kupna) i rzeczy gracza (cena sprzedaży); kliknięcie przenosi 1 sztukę do
##            koszyka (ponownie – z powrotem), suma, własna oferta (targowanie), złoto obu stron, „Oferta”;
##   zaklęcia – lista z cenami; trening – 3 umiejętności z cenami; podróż – cele z cenami.
## Logika w mw_trade.gd.

const Loc := preload("res://scripts/mw/mw_localization.gd")

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
var _left_ids: Array = []
var _right_ids: Array = []
var _merchant: Array = []
var _player: Array = []

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
	box.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	left = _list(row)
	right = _list(row)
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
	clear_btn.text = "Wyczyść koszyk"
	clear_btn.name = "Clear"
	clear_btn.pressed.connect(func(): buy = {}; sell = {}; refresh())
	bottom.add_child(clear_btn)
	var close_btn := Button.new()
	close_btn.text = "Zamknij"
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
	mode = service
	buy = {}
	sell = {}
	trade.restock(actor)
	visible = true
	refresh()
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	return true

func refresh() -> void:
	left.clear()
	right.clear()
	_left_ids = []
	_right_ids = []
	var pg: int = trade.player_gold()
	right.visible = mode == "barter"
	offer_spin.visible = mode == "barter"
	offer_btn.visible = mode == "barter"
	(panel.find_child("Clear", true, false) as Button).visible = mode == "barter"
	match mode:
		"barter":
			title.text = "%s – %s" % [_t("sBarter", "Handel"), main.dialogue.actor_name(actor)]
			_merchant = trade.merchant_items(actor)
			_player = trade.player_items(actor)
			for it in _merchant:
				var left_n := int(it.count) - int(buy.get(it.id, 0))
				if left_n <= 0:
					continue
				var price: int = trade.barter_offer(actor, trade.item_value(it.id), true)
				left.add_item("%s%s – %d" % [_name(it.id), (" (%d)" % left_n) if left_n > 1 else "", price])
				_left_ids.append(it.id)
			for it in _player:
				var left_p := int(it.count) - int(sell.get(it.id, 0))
				if left_p <= 0:
					continue
				var p2: int = trade.barter_offer(actor, trade.item_value(it.id), false)
				right.add_item("%s%s – %d" % [_name(it.id), (" (%d)" % left_p) if left_p > 1 else "", p2])
				_right_ids.append(it.id)
			var mo: int = trade.merchant_offer(actor, buy, sell)
			offer_spin.set_value_no_signal(mo)
			var lines := []
			for id in buy:
				lines.append("kupujesz: %s × %d" % [_name(id), int(buy[id])])
			for id in sell:
				lines.append("sprzedajesz: %s × %d" % [_name(id), int(sell[id])])
			basket_label.text = ("\n".join(lines) + "\n" if not lines.is_empty() else "") + \
				"%s: %d (ujemna – płacisz). Możesz zmienić kwotę i się targować." % [_t("sTotalCost", "Suma"), mo]
			offer_btn.text = _t("sBarterDialog8", "Oferta")
			gold_label.text = "%s %d   %s %d" % [_t("sYourGold", "Twoje złoto:"), pg, _t("sSellerGold", "Złoto kupca:"), trade.merchant_gold(actor)]
		"spells":
			title.text = "%s – %s" % [_t("sSpells", "Zaklęcia"), main.dialogue.actor_name(actor)]
			for s in trade.spells_for_sale(actor):
				left.add_item("%s – %d" % [s.name, int(s.price)])
				left.set_item_disabled(left.item_count - 1, int(s.price) > pg)
				_left_ids.append(s.id)
			basket_label.text = "Kliknij zaklęcie, aby je kupić."
			gold_label.text = "%s %d" % [_t("sGold", "Złoto:"), pg]
		"training":
			title.text = "%s – %s" % [_t("sServiceTrainingTitle", "Trening"), main.dialogue.actor_name(actor)]
			var names: Array = main.character.skill_names()
			for o in trade.training_offers(actor):
				var sid := String(names[int(o.skill)])
				left.add_item("%s – %d" % [_t("sSkill" + sid.capitalize().replace(" ", ""), sid), int(o.price)])
				left.set_item_disabled(left.item_count - 1, int(o.price) > pg)
				_left_ids.append(int(o.skill))
			basket_label.text = "Trening trwa 2 godziny."
			gold_label.text = "%s %d" % [_t("sGold", "Złoto:"), pg]
		"travel":
			title.text = "%s – %s" % [_t("sTravel", "Podróż"), main.dialogue.actor_name(actor)]
			for o in trade.travel_offers(actor):
				left.add_item("%s – %d" % [String(o.name), int(o.price)])
				left.set_item_disabled(left.item_count - 1, int(o.price) > pg)
				_left_ids.append(int(o.index))
			basket_label.text = ""
			gold_label.text = "%s %d" % [_t("sGold", "Złoto:"), pg]

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
	var r: Dictionary = trade.offer(actor, buy, sell, int(offer_spin.value), roll)
	if not String(r.message).is_empty():
		main._toast(String(r.message))
	if bool(r.ok):
		close()
	else:
		refresh()
	main.dialogue_window.refresh()
	return r

func close() -> void:
	visible = false
	buy = {}
	sell = {}
