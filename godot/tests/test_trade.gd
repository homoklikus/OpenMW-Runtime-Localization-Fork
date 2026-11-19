extends SceneTree
## Etap 7b: handel i usługi NPC – ceny (getBarterOffer), towar kupca (inwentarz bez założonej broni + skrzynia,
## której jest właścicielem), transakcja i targowanie (haggle), złoto kupca, zaklęcia (koszt autoobliczany),
## trening, podróż, odmowa usługi (Service Refusal).
## godot --headless --path godot -s res://tests/test_trade.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc   # postać po kreatorze (buildPlayer z rasą i klasą) – testy formuł zależnych od umiejętności klasy
	var tr = main.trade
	var tw = main.trade_window
	var inv = main.interaction.inventory
	inv.add("player", {}, "gold_001", 1000)
	var trader := _ref(main, "synth_trader")
	check(trader != null and main.open_dialogue(trader), "rozmowa z kupcem")
	var a: Dictionary = main.dialogue.actor
	var svc: Array = tr.service_entries(a).map(func(e): return e[0])
	# kolejność DialogueWindow::updateTopicsPane: handel, zaklęcia, podróż, …, trening, naprawa
	check(svc == ["barter", "spells", "travel", "training", "repair"], "usługi kupca w oknie rozmowy (%s)" % [svc])
	check(main.dialogue_window._topic_ids.has("#svc:barter"), "pozycja „Handel” na liście tematów")
	# ceny: postawa 50; gracz: handel 5, szczęście 40, osobowość 40, zmęczenie 1,25 → 21,25;
	# kupiec (poziom 5, autoobliczanie): handel 5, szczęście 40, osobowość 41 → 21,5
	check(tr.barter_offer(a, 40, true) == 40 and tr.barter_offer(a, 40, false) == 19, "ceny kupna i sprzedaży (%d, %d)" % [tr.barter_offer(a, 40, true), tr.barter_offer(a, 40, false)])
	check(tr.barter_offer(a, 0, true) == 0, "cena 0 pozostaje 0")
	# towar
	var items: Array = tr.merchant_items(a)
	var ids: Array = items.map(func(x): return x.id)
	var spoons := 0
	for it in items:
		if it.id == "misc_synth_spoon":
			spoons = int(it.count)
	check(not "synth_sword" in ids and not "gold_001" in ids, "bez założonej broni i złota (%s)" % [ids])
	check(spoons >= 7, "łyżki kupca i z jego skrzyni (%d)" % spoons)
	# kupno 6 łyżek po cenie kupca
	check(tw.open("barter") and tw.visible, "okno handlu")
	# GM_Barter: okno ekwipunku gracza i okno kupca (0,6; 0,27; 0,38 × 0,63), okno rozmowy ukryte
	var mm = main.menu_mode
	check(mm.visible and mm.barter == tw and mm.windows.has("inventory") and mm.windows.has("barter") and not main.dialogue_window.visible,
		"handel: okna ekwipunku i kupca, bez okna rozmowy")
	check(tw.grid_merchant_ids.has("misc_synth_spoon") and tw.grid_player_ids.size() > 0, "siatki kupca i gracza (%s)" % [tw.grid_merchant_ids])
	for i in 6:
		tw._click_left(tw._left_ids.find("misc_synth_spoon"))
	# TradeWindow::updateLabels i przyciski +/−/Max Sale
	var bal0 := int(tw.offer_spin.value)
	check(mm.barter_total_label.text == main.dialogue.gmst_text("sTotalCost", "Total Cost") and int(mm.barter_total.value) == absi(bal0),
		"saldo ujemne: sTotalCost i kwota bez znaku (%s %s)" % [mm.barter_total_label.text, mm.barter_total.value])
	tw.change_balance(1)
	check(int(tw.offer_spin.value) == bal0 - 1, "„+” zwiększa wartość bezwzględną salda")
	tw.change_balance(-1)
	check(int(tw.offer_spin.value) == bal0, "„−” zmniejsza wartość bezwzględną salda")
	var mo: int = tr.merchant_offer(a, tw.buy, tw.sell)
	var mg0: int = tr.merchant_gold(a)
	var pg0: int = tr.player_gold()
	check(mo < 0 and int(tw.offer_spin.value) == mo, "oferta kupca w polu oferty (%d)" % mo)
	var r: Dictionary = tw.make_offer(1)
	check(bool(r.ok) and inv.count_of("player", {}, "misc_synth_spoon") == 6, "transakcja: 6 łyżek u gracza")
	check(tr.player_gold() == pg0 + mo and tr.merchant_gold(a) == mg0 - mo, "złoto gracza i kupca (%d, %d)" % [tr.player_gold(), tr.merchant_gold(a)])
	check(inv.count_of(a.sid, a.rec, "misc_synth_spoon") == 0, "najpierw z kieszeni kupca (5), potem ze skrzyni")
	# targowanie: zawyżona cena sprzedaży – odmowa, postawa −1
	var d0: int = main.dialogue.base_disposition(a)
	tw.open("barter")
	tw._click_right(tw._right_ids.find("misc_synth_spoon"))
	tw.offer_spin.value = 100
	var r2: Dictionary = tw.make_offer(1)
	check(not bool(r2.ok) and main.dialogue.base_disposition(a) == d0 - 1, "zawyżona oferta odrzucona, postawa −1 (%d → %d)" % [d0, main.dialogue.base_disposition(a)])
	var h: Dictionary = tr.haggle(a, -9, -10, 1)
	check(bool(h.ok) and h.gain == 10.0, "haggle: d = 10 → x = −40 + 50 = 10, rzut 1 – zgoda, przyrost 10 (%s)" % [h])
	check(not bool(tr.haggle(a, -9, -10, 11).ok), "rzut 11 > 10 – odmowa")
	check(not bool(tr.haggle(a, 5, -10, 1).ok), "kupno z zarobkiem – zawsze odmowa")
	tw.max_sale()
	check(int(tw.offer_spin.value) == tr.merchant_gold(a), "Max Sale: saldo = złoto kupca")
	tw.close()
	check(not mm.visible and main.dialogue_window.visible, "Cancel: koniec handlu, powrót do rozmowy")
	# okna usług w układach OpenMW (SpellBuyingWindow, TrainingWindow, TravelWindow)
	var sw = main.service_window
	check(tw.open("spells") and sw.visible and sw.mode == "spells" and sw.panel.size.is_equal_approx(Vector2(450, 290) * preload("res://scripts/mw/mw_ui.gd").ui_scale()),
		"okno zakupu zaklęć 450 × 290")
	check(sw.rows.size() == 1 and String(sw.rows[0][0]) == "synth_bolt" and String(sw.rows[0][1]).ends_with("  - 60" + main.dialogue.gmst_text("sgp", "gp")),
		"wiersz „nazwa  - cena” + sgp (%s)" % [sw.rows])
	sw.close()
	check(tw.open("training") and sw.rows.size() == 3, "okno treningu: 3 umiejętności (%s)" % [sw.rows])
	sw.close()
	check(tw.open("travel") and sw.rows.size() == 1, "okno podróży: cel (%s)" % [sw.rows])
	sw.close()
	# zaklęcia: synth_bolt autoobliczany: (15 × 0,5 × 1 + 0) × 0,5 × 1,5 = 5,6 → 6 × 10 = 60
	var sp: Array = tr.spells_for_sale(a)
	check(sp.size() == 1 and sp[0].id == "synth_bolt" and int(sp[0].price) == 60, "zaklęcia na sprzedaż, cena 60 (%s)" % [sp])
	var g1: int = tr.player_gold()
	check(tr.buy_spell(a, "synth_bolt") and "synth_bolt" in main.player_stats().spells and tr.player_gold() == g1 - 60, "kupno zaklęcia")
	check(tr.spells_for_sale(a).is_empty(), "znane zaklęcie znika z listy")
	# trening
	var st: Dictionary = main.player_stats()
	var offers: Array = tr.training_offers(a)
	check(offers.size() == 3 and int(offers[0].skill) == 5, "trening: 3 najlepsze umiejętności, pierwsza – długie ostrza (%s)" % [offers])
	var lb0 := float(st.skills[5])
	var h0: float = main.envr.game_hour
	var tres: Dictionary = tr.train(a, 5)
	check(bool(tres.ok) and float(st.skills[5]) == lb0 + 1.0 and is_equal_approx(fposmod(main.envr.game_hour - h0, 24.0), 2.0),
			"trening: +1 i 2 godziny (%s)" % [tres])
	# podróż
	var to: Array = tr.travel_offers(a)
	check(to.size() == 1 and int(to[0].price) >= 1, "cel podróży z ceną (%s)" % [to])
	# odmowa usługi
	main.dialogue.set_base_disposition(a, 0)
	check(not tw.open("barter") and String(main.dialogue.history[-1].text).begins_with("Nie handluje"), "Service Refusal przy niskiej postawie")
	main.dialogue.set_base_disposition(a, 50)
	main.dialogue_window.close(true)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
