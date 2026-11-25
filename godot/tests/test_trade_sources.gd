extends SceneTree
## Etap 10 cz. 25: towar kupca jak TradeWindow::setPtr + TradeItemModel::update (OpenMW 0.51): źródła (kupiec,
## jego pojemniki o pojemności > 0), przedmioty w świecie należące do kupca (World::getItemsOwnedBy) złączone
## w stosy, `return` na pierwszym świetle bez flagi Carry, kupno z referencji w świecie (setCount / deleteObject),
## kolejność siatki kupca (SortFilterItemModel: przedmioty w koszyku najpierw, potem rodzaj, nazwa, …).
## godot --headless --path godot -s res://tests/test_trade_sources.gd -- --data=WYNIKI(aktorzy) --scripts=0

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _node_by_sid(main, sid: String) -> Node:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				return n
	return null

func _count(items: Array, id: String) -> int:
	for it in items:
		if String(it.id) == id:
			return int(it.count)
	return 0

## Przedmiot o typie dalekim w kolejności (drobiazg) – sprawdzenie, że Type_Barter wyprzedza rodzaj.
func TYPE_LAST(mm, id: String) -> bool:
	var it: Dictionary = mm.main.interaction.inventory.item(id)
	return int(mm.TYPE_ORDER.get(String(it.get("kind", "")), 0)) >= 8

func _fake(main, sid: String, base: String, owner: String, count := 1) -> Node3D:
	var n := Node3D.new()
	n.set_meta("mw_sid", sid)
	n.set_meta("mw_base", base)
	n.set_meta("mw_extra", {"owner": owner, "count": count})
	var refs: Node = main.loaded[main.loaded.keys()[0]].get_node("Refs")
	refs.add_child(n)
	return n

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var tr = main.trade
	var inv = main.interaction.inventory
	inv.add("player", {}, "gold_001", 5000)
	var trader := _ref(main, "synth_trader")
	check(trader != null and main.open_dialogue(trader), "rozmowa z kupcem")
	var a: Dictionary = main.dialogue.actor
	const SPOON := "misc_synth_spoon"
	const WSID := "mwg_actors.esp#9014"            # łyżka na ziemi, właściciel synth_trader
	# --- źródła ---
	var srcs: Array = tr.sources(a)
	check(srcs.size() == 3 and bool(srcs[0].merchant), "źródła: kupiec + 2 skrzynie, których jest właścicielem (%d)" % srcs.size())
	var in_containers := 0
	for s in srcs:
		in_containers += inv.count_of(String(s.sid), s.rec, SPOON)
	var w: Array = tr.world_items(a)
	var wids: Array = w.map(func(x): return String(x.sid))
	check(wids.has(WSID), "World::getItemsOwnedBy: łyżka kupca leżąca w świecie (%s)" % [wids])
	check(not wids.has("mwg_actors.esp#9006"), "przedmiot bez właściciela nie należy do towaru")
	var items: Array = tr.merchant_items(a)
	# getItemsOwnedBy zwraca też pojemniki (forEach po wszystkich listach) – odpada je canSell (Class::canSell = false)
	check(wids.has("mwg_actors.esp#9010") and _count(items, "synth_chest") == 0, "pojemnik kupca: źródło towaru, nie towar")
	check(_count(items, SPOON) == in_containers + 1, "stos łyżek = kieszeń/skrzynie + łyżka ze świata (%d, %d)" % [_count(items, SPOON), in_containers])
	# pojemność 0 – GetContainersOwnedByVisitor pomija pojemnik
	var crec: Dictionary = main.interaction.container_record("synth_chest")
	var cap0 = crec.get("capacity", 0.0)
	crec["capacity"] = 0.0
	check(tr.sources(a).size() == 1, "pojemnik o pojemności 0 nie jest źródłem towaru")
	crec["capacity"] = cap0
	# wyłączona referencja w świecie (Disable) – bez węzła sceny, poza towarem
	main.state.set_enabled(WSID, false)
	check(not tr.world_items(a).map(func(x): return String(x.sid)).has(WSID), "wyłączony przedmiot w świecie poza towarem")
	main.state.set_enabled(WSID, true)
	# --- setCount: liczba sztuk referencji z GameState (zapis), węzeł przebudowany ---
	main.state.set_ref_count(WSID, 3)
	var nd := _node_by_sid(main, WSID)
	check(nd != null and main.interaction.count_of_ref(nd) == 3, "liczba sztuk referencji z GameState po przebudowie węzła")
	check(_count(tr.merchant_items(a), SPOON) == in_containers + 3, "stos łyżek uwzględnia 3 sztuki ze świata")
	# --- Flag_Bound: przedmioty o identyfikatorze z GMST sMagicBound* nie są na sprzedaż (TradeItemModel::update) ---
	var gm: Dictionary = tr.records._all("gmst")
	var had: bool = gm.has("smagicbounddaggerid")
	var prev = gm.get("smagicbounddaggerid")
	gm["smagicbounddaggerid"] = {"id": "smagicbounddaggerid", "value": SPOON}
	tr._bound_ids = null
	check(tr.is_bound_item(SPOON) and _count(tr.merchant_items(a), SPOON) == 0, "przedmiot przywołany (sMagicBound*) poza towarem kupca")
	if had:
		gm["smagicbounddaggerid"] = prev
	else:
		gm.erase("smagicbounddaggerid")
	tr._bound_ids = null
	check(not tr.is_bound_item(SPOON) and _count(tr.merchant_items(a), SPOON) == in_containers + 3, "bez GMST łyżki wracają do towaru")
	var saved: Dictionary = main.state.to_dict({})
	check(int(((saved.refs as Dictionary).get(WSID, {}) as Dictionary).get("count", 0)) == 3, "liczba sztuk w zapisie gry")
	# --- kupno: najpierw źródła, potem świat; część stosu → setCount, reszta → deleteObject ---
	var p0: int = inv.count_of("player", {}, SPOON)
	var r: Dictionary = tr.offer(a, {SPOON: in_containers + 1}, {}, -100000, 1)
	if not bool(r.ok):        # targowanie: oferta zawyżona na korzyść kupca (−100000) – gracz ma za mało złota
		r = tr.offer(a, {SPOON: in_containers + 1}, {}, tr.merchant_offer(a, {SPOON: in_containers + 1}, {}), 1)
	check(bool(r.ok), "transakcja (%s)" % [r])
	check(inv.count_of("player", {}, SPOON) == p0 + in_containers + 1, "gracz dostał wszystkie łyżki (%d)" % inv.count_of("player", {}, SPOON))
	check(main.state.is_enabled(WSID) and main.state.ref_count_of(WSID, 1) == 2, "część stosu w świecie: zostały 2 sztuki (%d)" % main.state.ref_count_of(WSID, 1))
	r = tr.offer(a, {SPOON: 2}, {}, tr.merchant_offer(a, {SPOON: 2}, {}), 1)
	check(bool(r.ok) and not main.state.is_enabled(WSID), "cały stos ze świata kupiony – referencja usunięta (deleteObject)")
	check(_count(tr.merchant_items(a), SPOON) == 0, "łyżek nie ma już w towarze")
	# --- światło bez Carry: `return` w TradeItemModel::update – dalsze przedmioty ze świata nie trafiają na listę ---
	check(not tr.shows_in_inventory("synth_lamp") and tr.shows_in_inventory("synth_torch") and not tr.shows_in_inventory("werewolfrobe"),
		"Class::showsInInventory: lampa bez Carry i szata wilkołaka")
	var papers := _fake(main, "test#papers", "synth_papers", "synth_trader")
	var with_papers: bool = _count(tr.merchant_items(a), "synth_papers") == 1
	var sells_misc: bool = tr.can_sell("synth_papers", tr.services(a))
	check(with_papers == sells_misc, "papiery kupca leżące w świecie na liście (gdy kupiec handluje drobiazgami)")
	var lamp := _fake(main, "test#lamp", "synth_lamp", "synth_trader")
	lamp.get_parent().move_child(lamp, papers.get_index())   # ta sama komórka; lista świateł przed drobiazgami
	var trunc: Array = tr.merchant_items(a)
	check(_count(trunc, "synth_papers") == 0 and _count(trunc, "synth_lamp") == 0,
		"lampa bez Carry przerywa listę (return) – papiery i lampa poza towarem (%s)" % [trunc.map(func(x): return x.id)])
	check(trunc.size() > 0 or tr.merchant_items(a).is_empty(), "przedmioty przed lampą zostają")
	lamp.queue_free()
	papers.queue_free()
	await _frames(1)
	# --- siatki handlu: SortFilterItemModel::Compare, koszyk (Type_Barter) najpierw, ekwipunek gracza bez filtru usług ---
	var tw = main.trade_window
	var mm = main.menu_mode
	inv.add("player", {}, "synth_papers", 2)
	inv.add("player", {}, "synth_sword", 1)
	check(tw.open("barter") and tw.visible, "okno handlu")
	await _frames(2)
	var pids: Array = tw.grid_player_ids
	check(pids.has("gold_001") or not tr.shows_in_inventory("gold_001"), "ekwipunek gracza w handlu – także rzeczy, których kupiec nie kupi (%s)" % [pids])
	var entries: Array = pids.map(func(id): return tw._entry({"id": id}, 1, "player", false))
	var sorted := entries.duplicate()
	sorted.sort_custom(mm.item_less)
	check(entries.map(func(e): return e.id) == sorted.map(func(e): return e.id), "siatka gracza w kolejności SortFilterItemModel (%s)" % [pids])
	var mids: Array = tw.grid_merchant_ids
	var ment: Array = mids.map(func(id): return tw._entry({"id": id}, 1, "merchant", true))
	var msorted := ment.duplicate()
	msorted.sort_custom(mm.item_less)
	check(ment.map(func(e): return e.id) == msorted.map(func(e): return e.id), "siatka kupca w kolejności SortFilterItemModel (%s)" % [mids])
	# sprzedawany przedmiot (Type_Barter) na początku siatki kupca, przed bronią
	var sellable := ""
	for id in pids:
		if tr.can_sell(String(id), tr.services(a)) and TYPE_LAST(mm, String(id)):
			sellable = String(id)
	if sellable.is_empty():
		for id in pids:
			if tr.can_sell(String(id), tr.services(a)):
				sellable = String(id)
	tw.move_item(sellable, "player", 1)
	await _frames(1)
	check(not tw.grid_merchant_ids.is_empty() and String(tw.grid_merchant_ids[0]) == sellable, "sprzedawane (Type_Barter) pierwsze w siatce kupca (%s, %s)" % [sellable, tw.grid_merchant_ids])
	# rzecz, której kupiec nie przyjmuje (sBarterDialog4) – nie trafia do koszyka
	var refused := ""
	for id in pids:
		if not tr.can_sell(String(id), tr.services(a)):
			refused = String(id)
	if not refused.is_empty():
		tw.click_item(refused, "player", {"shift": true})
		check(not tw.sell.has(refused), "kupiec nie przyjmuje %s – bez sprzedaży" % refused)
	tw.close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
