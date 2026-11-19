extends SceneTree
## Etap 9: zaklinanie, tworzenie czarów i ładowanie przedmiotów jak OpenMW 0.51:
##   Enchanting (nextCastStyle dla ubrania/broni/zwoju, punkty narastające, szansa, cena u zaklinacza, pojemność,
##   create: rekord zaklęcia i nowego przedmiotu, kamień zużyty, porażka), EnchantingDialog (setPtr z NPC
##   i z kamieniem, ItemSelectionDialog, kolejność komunikatów onBuyButtonClicked, kradzione od zaklinacza),
##   EffectEditorBase/EditEffectDialog (znane efekty, 8 efektów, powtórzenia, zasięgi, suwaki, Anuluj/Usuń,
##   stały efekt → Self), SpellCreationDialog (koszt narastający, cena, szansa, zakup), Recharge (rechargeItem),
##   SoulgemDialog, usługi tworzenia czarów i zaklinania w rozmowie.
## godot --headless --path godot -s res://tests/test_enchanting.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc
	var st: Dictionary = main.player_stats()
	st.fatigue = main.character.derived(st).fatigue.modified
	var inv = main.interaction.inventory
	var mg = main.magic
	var me: Dictionary = main.combat.player_fighter()
	mg.test_roll = -1
	# dusze: słaba (synth_creature, 5) i silna (stworzenie dynamiczne, 500)
	if not main.state.created.has("creature"):
		main.state.created["creature"] = {}
	main.state.created["creature"]["mwg_test_big_soul"] = {"id": "mwg_test_big_soul", "name": "Duza dusza", "soul": 500}
	var weak := "misc_soulgem_synth@synth_creature"
	var big := "misc_soulgem_synth@mwg_test_big_soul"
	check(mg.gem_charge(weak) == 5 and mg.gem_charge(big) == 500, "ładunki dusz 5 i 500")
	# --- nextCastStyle
	var ns = func(item: String, gem: String, start: int, n: int) -> Array:
		var s := {"item": item, "gem": gem, "cast": start, "effects": [], "self": true}
		var out := []
		for i in n:
			s.cast = mg.ench_next_cast_style(s)
			out.append(int(s.cast))
		return out
	inv.add("player", {}, "synth_plain_ring", 3)
	check(ns.call("synth_plain_ring", weak, 0, 3) == [2, 2, 2], "ubranie, słaba dusza: po użyciu (%s)" % [ns.call("synth_plain_ring", weak, 0, 3)])
	check(ns.call("synth_plain_ring", big, 0, 3) == [2, 3, 2], "ubranie, silna dusza: po użyciu ↔ stały (%s)" % [ns.call("synth_plain_ring", big, 0, 3)])
	inv.add("player", {}, "synth_sword", 1)
	check(ns.call("synth_sword", big, 0, 4) == [1, 2, 3, 1], "broń biała: przy uderzeniu → po użyciu → stały → (domyślnie) przy uderzeniu (%s)" % [ns.call("synth_sword", big, 0, 4)])
	check(ns.call("synth_sword", weak, 0, 3) == [1, 2, 1], "broń biała, słaba dusza: uderzenie ↔ użycie (%s)" % [ns.call("synth_sword", weak, 0, 3)])
	inv.add("player", {}, "synth_bow", 1)
	check(ns.call("synth_bow", big, 0, 3) == [2, 3, 2], "łuk: po użyciu ↔ stały, bez „przy uderzeniu” (%s)" % [ns.call("synth_bow", big, 0, 3)])
	inv.add("player", {}, "synth_arrow", 20)
	check(ns.call("synth_arrow", big, 0, 3) == [1, 1, 1], "strzała: tylko przy uderzeniu (%s)" % [ns.call("synth_arrow", big, 0, 3)])
	check(ns.call("", big, 3, 1) == [3], "bez przedmiotu – bez zmiany")
	# --- koszty, pojemność, cena
	var fx := [{"effect": 75, "skill": -1, "attribute": -1, "range": 0, "area": 0, "duration": 10, "min": 5, "max": 5}]
	var es := {"item": "synth_plain_ring", "gem": weak, "cast": 2, "effects": fx, "self": true}
	check(near(mg.ench_points(es), 2.525) and int(mg.ench_points(es, false)) == 2 and mg.ench_max_value(es) == 50,
		"punkty 2,525 (int 2), pojemność 500 × 0,1 = 50")
	var exp_cc: int = mg.effective_cast_cost({"cost": 2}, me)
	check(mg.ench_effective_cast_cost(es) == exp_cc and mg.ench_price(es) == 0, "koszt rzucenia (%d), samodzielnie – bez ceny" % exp_cc)
	var ce := es.duplicate()
	ce.cast = 3
	ce.gem = big
	check(mg.ench_base_cast_cost(ce) == 0 and mg.ench_effective_cast_cost(ce) == 1, "stały efekt: koszt 0, efektywny 1 (minimum)")
	check(near(mg.ench_points(ce), ((5 + 5) * 100.0 + 1) * 1.0 * 0.5 * 0.05), "stały efekt: czas × fEnchantmentConstantDurationMult")
	var trader := _ref(main, "synth_trader")
	check(trader != null and main.open_dialogue(trader), "rozmowa z kupcem")
	var a: Dictionary = main.dialogue.actor
	var svc: Array = main.trade.service_entries(a).map(func(e): return e[0])
	check("spellmaking" in svc and "enchanting" in svc and svc.find("spellmaking") < svc.find("enchanting"),
		"usługi sSpellmakingMenuTitle i sEnchanting w rozmowie (%s)" % [svc])
	var ns2 := es.duplicate()
	ns2.self = false
	ns2.enchanter = a
	var exp_price: int = maxi(1, main.trade.barter_offer(a, int(2.525 * 10.0), true))
	check(mg.ench_price(ns2) == exp_price, "cena u zaklinacza: koszt ostatniego efektu × fEnchantmentValueMult → oferta (%d / %d)" % [mg.ench_price(ns2), exp_price])
	# --- okno zaklinania u NPC
	var ew = main.enchanting_window
	check(main.trade_window.open("enchanting") and ew.visible and not ew.self_enchanting, "usługa zaklinacza otwiera EnchantingDialog")
	check(ew.buy_button.text == main.dialogue.gmst_text("sBuy", "Buy") and ew._price_nodes[0].visible and not ew._chance_nodes[0].visible
		and ew.gem_id == "", "z NPC: sBuy, cena widoczna, szansa ukryta, bez kamienia")
	st["spells"] = ["synth_heal", "synth_touch", "synth_strength", "synth_open"]
	ew.set_ptr(a)
	var known_names: Array = ew.editor.known.map(func(i): return ew.editor.effect_name(i))
	var sorted_names := known_names.duplicate()
	sorted_names.sort()
	check(ew.editor.known.size() == 4 and known_names == sorted_names, "znane efekty z czarów gracza, posortowane po nazwie (%s)" % [known_names])
	var r: Dictionary = ew.buy()
	check(r.message == "sEnchantmentMenu11", "bez efektów – sEnchantmentMenu11 (%s)" % [r])
	var heal_i: int = ew.editor.known.find(75)
	ew.editor.available_clicked(heal_i)
	check(ew.editor.is_dialog_open() and ew.editor.effects.size() == 1, "klik efektu: EditEffectDialog, efekt od razu na liście")
	check(int(ew.editor.effects[0].range) == 1, "nowy efekt: Self → (onRangeButtonClicked) Touch (%s)" % [ew.editor.effects[0]])
	ew.editor.range_clicked()
	ew.editor.range_clicked()
	check(int(ew.editor.effects[0].range) == 0 and not ew.editor._w.area_box.visible, "zasięg Self – obszar ukryty i 0")
	ew.editor.set_slider("mag_min", 4)
	ew.editor.set_slider("mag_max", 2)
	ew.editor.set_slider("dur", 9)
	var e0: Dictionary = ew.editor.effects[0]
	check(int(e0.min) == 5 and int(e0.max) == 5 and int(e0.duration) == 10, "suwaki: min 5, max nie mniejsze niż min, czas 10 (%s)" % [e0])
	check(ew.editor._w.mag_max_val.text == main.dialogue.gmst_text("sTo", "-") + " 5", "etykieta „sTo 5”")
	ew.editor.ok_clicked()
	check(not ew.editor.is_dialog_open() and ew.labels.Enchantment.text == "2 / 0", "OK: zostaje, „2 / 0” bez przedmiotu (%s)" % ew.labels.Enchantment.text)
	ew.editor.available_clicked(heal_i)
	check(ew.editor.effects.size() == 1, "ten sam efekt drugi raz – sOnetypeEffectMessage")
	ew.editor.available_clicked(ew.editor.known.find(79))
	check(ew.editor.sub != null and ew.editor.sub.name == "SelectAttributeDialog", "efekt z atrybutem – SelectAttributeDialog")
	ew.editor._close_sub()
	ew.editor.new_effect(79, -1, 0)
	check(ew.editor.effects.size() == 2 and int(ew.editor.effects[1].attribute) == 0, "efekt z wybranym atrybutem")
	ew.editor.cancel_clicked()
	check(ew.editor.effects.size() == 1, "Anuluj nowego efektu – usunięty")
	ew.editor.edit_effect(0)
	ew.editor.set_slider("dur", 19)
	ew.editor.cancel_clicked()
	check(int(ew.editor.effects[0].duration) == 10, "Anuluj edycji – przywrócony")
	r = ew.buy()
	check(r.message == "sNotifyMessage10", "pusta nazwa – sNotifyMessage10 (%s)" % [r])
	ew.name_edit.text = "Pierscien X"
	r = ew.buy()
	check(r.message == "sNotifyMessage52", "bez kamienia – sNotifyMessage52 (%s)" % [r])
	inv.add("player", {}, weak, 1)
	ew.select_soul()
	check(ew.selection.is_open() and ew.selection.entries.size() >= 1, "ItemSelectionDialog z kamieniami z duszą")
	ew.soul_selected(weak)
	check(not ew.selection.is_open() and ew.gem_id == weak and ew.labels.Charge.text == "5", "kamień wybrany, ładunek 5")
	r = ew.buy()
	check(r.message == "sNotifyMessage11", "bez przedmiotu – sNotifyMessage11 (%s)" % [r])
	ew.select_item()
	var names: Array = ew.selection.entries.map(func(e): return String(e.id))
	check("synth_plain_ring" in names and "synth_sword" in names and not "synth_ring" in names and not weak in names,
		"Filter_OnlyEnchantable: bez zaklętych i kamieni (%s)" % [names])
	ew.item_selected("synth_plain_ring")
	check(ew.item_id == "synth_plain_ring" and ew.cast_style == 2 and ew.name_edit.text == String(inv.item("synth_plain_ring").rec.get("name", "")),
		"przedmiot: nazwa z przedmiotu, sposób „po użyciu”")
	ew.name_edit.text = "Pierscien X"
	check(ew.labels.Enchantment.text == "2 / 50", "„2 / 50” (%s)" % ew.labels.Enchantment.text)
	# kradziony kamień od zaklinacza
	main.crime.st()["stolen"] = {"misc_soulgem_synth": {"synth_trader": 1}}
	check(main.crime.is_item_stolen_from(weak, a), "kamień skradziony kupcowi (isItemStolenFrom)")
	main.crime.st()["stolen"] = {}
	inv.add("player", {}, "gold_001", 5000)
	var gold0: int = main.trade.player_gold()
	var mgold0: int = main.trade.merchant_gold(a)
	var price: int = int(ew.labels.PriceLabel.text)
	r = ew.buy()
	var nid := String(r.get("item", ""))
	var nit: Dictionary = inv.item(nid)
	var nen: Dictionary = mg.item_enchantment(nit)
	check(bool(r.get("ok", false)) and not ew.visible and inv.count_of("player", {}, nid) == 1 and inv.count_of("player", {}, "synth_plain_ring") == 2
		and inv.count_of("player", {}, weak) == 0, "zakup: nowy przedmiot, stary i kamień zużyte (%s)" % [r])
	check(main.trade.player_gold() == gold0 - price and main.trade.merchant_gold(a) == mgold0 + price, "zapłata %d do puli kupca" % price)
	check(String(nit.rec.get("name", "")) == "Pierscien X" and int(nit.rec.get("enchant_capacity", 0)) == 5 and int(nen.get("type", -1)) == 2
		and int(nen.get("cost", 0)) == 2 and int(nen.get("charge", 0)) == 5, "rekordy: nazwa, pojemność = ładunek kamienia, zaklęcie (%s, %s)" % [nit.rec, nen])
	check(int(mg.item_charge(me, nid, nen)) == 5, "nowy przedmiot z pełnym ładunkiem (−1 = pełny)")
	# drugi przedmiot o tych samych danych: ten sam rekord zaklęcia, nowy rekord przedmiotu (ESMStore::insert)
	inv.add("player", {}, weak, 1)
	var r2: Dictionary = mg.enchant(me, "synth_plain_ring", weak, fx, 2, "Pierscien X", a)
	check(bool(r2.success) and String(r2.item) != nid and mg.item_enchantment(inv.item(String(r2.item))).get("id") == nen.get("id"),
		"to samo zaklęcie użyte ponownie (getRecord), przedmiot – nowy rekord (%s)" % [r2])
	# --- samodzielne zaklinanie (kamień gracza), porażka i sukces
	inv.add("player", {}, big, 2)
	main.enchanting_window.open_for({}, big)
	check(ew.self_enchanting and ew.gem_id == big and ew.buy_button.text == main.dialogue.gmst_text("sCreate", "Create")
		and not ew._price_nodes[0].visible, "z kamieniem: samodzielnie, sCreate, cena ukryta")
	ew.item_selected("synth_plain_ring")
	ew.type_clicked()
	check(ew.cast_style == 3 and ew.editor.constant, "silna dusza: stały efekt (setConstantEffect)")
	ew.editor.new_effect(23)
	check(int(ew.editor.effects[0].range) == 0, "stały efekt: tylko zasięg Self (%s)" % [ew.editor.effects[0]])
	ew.editor.ok_clicked()
	ew.type_clicked()
	ew.editor.new_effect(75)
	ew.editor.ok_clicked()
	check(int(ew.editor.effects[0].range) == 0, "po zmianie ze stałego zasięg zostaje Self")
	ew.type_clicked()
	check(ew.cast_style == 3 and ew.editor.effects.all(func(e): return int(e.range) == 0), "ponownie stały – wszystkie Self")
	var sst: Dictionary = ew._state()
	var ch: int = mg.ench_chance(sst)
	var at: Array = main.combat.attributes(me)
	var exp_ch := int((float(main.combat.skill(me, mg.SK_ENCHANT)) - mg.ench_points(sst) * 3.0 + 0.2 * float(at[1]) + 0.1 * float(at[7]))
		* float(main.combat.fatigue_term(me)) * 0.5)
	check(ch == exp_ch, "szansa samodzielna (stały × 0,5): %d / %d" % [ch, exp_ch])
	ew.name_edit.text = "Moj stały"
	sst["name"] = "Moj stały"
	var fail: Dictionary = mg.ench_create(me, sst.duplicate(true), 99)
	check(not bool(fail.ok) and inv.count_of("player", {}, big) == 1 and inv.count_of("player", {}, "synth_plain_ring") == 1,
		"porażka (rzut 99 ≥ szansa): kamień zużyty, przedmiot zostaje (%s)" % [fail])
	ew.close()
	# --- tworzenie czarów
	var sw = main.spellcreation_window
	check(main.trade_window.open("spellmaking") and sw.visible, "usługa tworzenia czarów otwiera SpellCreationDialog")
	check(sw.labels.PlayerGold.text == str(main.trade.player_gold()) and sw.labels.MagickaCost.text == "0", "złoto gracza, koszt 0")
	r = sw.buy()
	check(r.message == "sNotifyMessage30", "bez efektów – sNotifyMessage30")
	sw.editor.new_effect(23)
	sw.editor.set_slider("mag_min", 9)
	sw.editor.set_slider("mag_max", 19)
	sw.editor.set_slider("dur", 4)
	sw.editor.ok_clicked()
	var e1: Dictionary = sw.editor.effects[0]
	var y := maxf(1.0, mg.effect_cost(e1, mg.COST_PLAYER_SPELL))
	if int(e1.range) == mg.RT_TARGET:
		y *= 1.5
	check(sw.labels.MagickaCost.text == str(int(y)), "koszt many: calcEffectCost(PlayerSpell) (%s / %d)" % [sw.labels.MagickaCost.text, int(y)])
	var sp_price: int = main.trade.barter_offer(a, maxi(1, int(y * 7.0)), true)
	check(sw.labels.PriceLabel.text == str(sp_price), "cena: y × fSpellMakingValueMult → oferta (%s / %d)" % [sw.labels.PriceLabel.text, sp_price])
	var chance: float = mg.spell_base_chance(sw.spell, me).chance
	check(sw.labels.SuccessChance.text == str(mini(100, int(chance))), "szansa: calcSpellBaseSuccessChance")
	sw.editor.new_effect(75)
	sw.editor.range_clicked()
	sw.editor.ok_clicked()
	var y2 := maxf(1.0, mg.effect_cost(e1, mg.COST_PLAYER_SPELL))
	if int(e1.range) == mg.RT_TARGET:
		y2 *= 1.5
	var e2: Dictionary = sw.editor.effects[1]
	y2 += maxf(1.0, mg.effect_cost(e2, mg.COST_PLAYER_SPELL))
	if int(e2.range) == mg.RT_TARGET:
		y2 *= 1.5
	check(sw.labels.MagickaCost.text == str(int(y2)), "koszt narastający (cel × 1,5 całości): %s / %d" % [sw.labels.MagickaCost.text, int(y2)])
	sw.name_edit.text = "Moj czar"
	gold0 = main.trade.player_gold()
	var sp_p := int(sw.labels.PriceLabel.text)
	r = sw.buy()
	var sid := String(r.get("spell", ""))
	var srec: Dictionary = mg.records.record("spell", sid)
	check(bool(r.get("ok", false)) and sid in main.player_stats().spells and String(srec.get("name", "")) == "Moj czar"
		and int(srec.get("cost", 0)) == int(y2) and int(srec.get("spell_type", -1)) == 0 and (srec.effects as Array).size() == 2,
		"zakup czaru: nowy czar gracza (%s)" % [srec])
	check(main.trade.player_gold() == gold0 - sp_p and not sw.visible, "zapłata za czar, okno zamknięte")
	# 8 efektów
	sw.open(a)
	for i in 8:
		sw.editor.effects.append({"effect": 75, "skill": -1, "attribute": -1, "range": 0, "area": 0, "duration": 1, "min": 1, "max": 1})
	sw.editor.available_clicked(0)
	check(not sw.editor.is_dialog_open() and sw.editor.effects.size() == 8, "dziewiąty efekt – sNotifyMessage28")
	sw.close()
	# --- PersuasionDialog (okno modalne z rozmowy)
	var dw = main.dialogue_window
	check(dw.visible and dw._topic_ids.has("#persuasion"), "pozycja sPersuasion na liście tematów")
	dw._on_topic(dw._topic_ids.find("#persuasion"))
	var pd = dw.persuasion
	check(pd.is_open() and pd.win.name == "PersuasionDialog" and pd.buttons.size() == 6, "klik sPersuasion: okno perswazji z 6 akcjami")
	var sc: float = pd.ui.sc
	check(pd.win.size.y == 192 * sc and (pd.buttons.admire as Control).position.y == 3 * sc and (pd.buttons.bribe1000 as Control).position.y == 93 * sc,
		"adjustAction: wiersze 18 px od 3, okno 192 px")
	var g_now: int = main.trade.player_gold()
	check(pd.buttons.bribe10.disabled == (g_now < 10) and pd.buttons.bribe1000.disabled == (g_now < 1000)
		and pd.gold_label.text.ends_with(": %d" % g_now), "łapówki wg złota, „sGold: N”")
	var disp0: int = main.dialogue.derived_disposition(a)
	pd.persuade("admire", 0)
	check(not pd.is_open() and main.dialogue.derived_disposition(a) >= disp0, "podziw (rzut 0): okno zamknięte, nastawienie nie spada")
	main.dialogue_window._open_persuasion()
	pd.close()
	check(not pd.is_open() and dw.visible, "Anuluj: tylko okno perswazji")
	# --- ładowanie (Recharge)
	_set_charge(mg, me, nid, 1.0)
	inv.add("player", {}, weak, 2)
	var rw = main.recharge_window
	rw.open(weak)
	check(rw.visible and rw.lines.size() == 1 and String(rw.lines[0].id) == nid, "Filter_OnlyRechargable: rozładowany przedmiot (%s)" % [rw.lines])
	var x: float = (float(main.combat.skill(me, mg.SK_ENCHANT)) + clampf(0.2 * float(at[1]), 1.0, 20.0)
		+ (0.1 * float(at[7]) if 0.1 * float(at[7]) >= 1.0 and 0.1 * float(at[7]) <= 10.0 else 1.0)) * float(main.combat.fatigue_term(me))
	var rr: Dictionary = mg.recharge_item(nid, weak, 0)
	check(bool(rr.success) and near(mg.item_charge(me, nid, nen), 1.0, 0.001) and inv.count_of("player", {}, weak) == 1,
		"rzut 0: przywrócono 5 × 0 / x = 0, kamień zużyty (%s)" % [rr])
	var roll := int(x) - 1 if x >= 2.0 else 0
	rr = mg.recharge_item(nid, weak, roll)
	check(bool(rr.success) == (float(roll) < x) and near(mg.item_charge(me, nid, nen), minf(5.0, 1.0 + 5.0 * float(roll) / x), 0.01)
		and inv.count_of("player", {}, weak) == 0 and (rr.messages as Array).size() == 1,
		"ładowanie: + dusza × rzut / x, ostatni kamień – sNotifyMessage51 (%s)" % [rr])
	rw.refresh()
	check(not rw._tool_box.visible, "po zużyciu kamienia GemBox ukryty")
	rw.close()
	# SoulgemDialog
	inv.add("player", {}, weak, 1)
	main.item_window.use_soul_gem(weak)
	check(main.msgbox != null and is_instance_valid(main.msgbox), "SoulgemDialog: pytanie sDoYouWantTo")
	main.press_message_button(1)
	check(ew.visible and ew.self_enchanting and ew.gem_id == weak, "„sMake Enchantment” → okno zaklinania z kamieniem")
	ew.close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)

func _set_charge(mg, me: Dictionary, id: String, v: float) -> void:
	mg._set_item_charge(me, id, v)
