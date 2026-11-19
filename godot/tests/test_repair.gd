extends SceneTree
## Etap 9: stan przedmiotów (CellRef::charge – stos „id#c:N”) i naprawa jak OpenMW 0.51:
##   uszkodzenie zostaje po zdjęciu i ponownym założeniu, podpowiedź „sCondition: bieżący/największy”,
##   cena w handlu × stan (getEffectiveValue); Repair::repair (sukces, porażka, zużycie narzędzia);
##   MerchantRepair (cena, pełny stan, złoto do puli kupca); okno naprawy (ItemChargeView) i okno usługi.
## godot --headless --path godot -s res://tests/test_repair.gd -- --data=WYNIKI(aktorzy) --scripts=0

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
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc
	var inv = main.interaction.inventory
	var cb = main.combat
	var me: Dictionary = cb.player_fighter()
	# --- stan przedmiotu w ekwipunku
	inv.add("player", {}, "synth_sword", 2)
	check(main.equip_item("synth_sword") == "", "założenie miecza")
	var slot: int = main.equipped_slot_of("synth_sword")
	var mx: float = inv.max_charge(inv.item("synth_sword").rec)
	check(slot >= 0 and mx > 100.0, "miecz w ręce, wytrzymałość z rekordu (%s)" % mx)
	cb._set_item_health(me, slot, 100.0)
	var eq_id := String(main._equipment()[str(slot)].id)
	check(eq_id == "synth_sword#c:100" and inv.count_of("player", {}, "synth_sword#c:100") == 1
			and inv.count_of("player", {}, "synth_sword") == 1,
		"uszkodzony egzemplarz to osobny stos (%s, pełne: %d)" % [eq_id, inv.count_of("player", {}, "synth_sword")])
	check(int(cb.item_health(cb.equipment(me)[slot])) == 100, "stan założonej broni 100")
	main.unequip_slot(slot)
	check(main.equip_item("synth_sword#c:100") == "" and int(cb.item_health(cb.equipment(me)[main.equipped_slot_of("synth_sword#c:100")])) == 100,
		"po zdjęciu i ponownym założeniu uszkodzenie zostaje")
	var tip: String = main.menu_mode.item_tooltip("synth_sword#c:100")
	check(tip.contains("100/%d" % int(mx)), "podpowiedź: stan bieżący/największy (%s)" % tip.replace("\n", " | "))
	var full_v: int = main.trade.item_value("synth_sword", true)
	var dmg_v: int = main.trade.item_value("synth_sword#c:100", true)
	check(dmg_v == int(float(full_v) * 100.0 / mx) and main.trade.item_value("synth_sword#c:100") == full_v,
		"cena w handlu × stan (%d z %d), wartość przestępstwa bez stanu" % [dmg_v, full_v])
	check(main.interaction.item_name("weapon", "synth_sword#c:100", inv.item("synth_sword").rec) == String(inv.item("synth_sword").rec.name),
		"nazwa egzemplarza bez przyrostka stanu")
	# --- naprawa narzędziem (Repair::repair)
	var rp = main.repair
	inv.add("player", {}, "synth_repair_hammer", 1)
	var rl: Array = rp.repairable()
	check(rl.size() == 1 and String(rl[0].id) == "synth_sword#c:100", "do naprawy tylko uszkodzony miecz (%s)" % [rl.map(func(x): return x.id)])
	var r1: Dictionary = rp.repair("synth_repair_hammer", "synth_sword#c:100", 0)
	# roll 0 ≤ x: naprawa o max(1, int(fRepairAmountMult 3 × jakość 1,2 × 0)) = 1
	check(bool(r1.ok) and String(r1.item) == "synth_sword#c:101" and String(r1.tool) == "synth_repair_hammer#c:4"
			and inv.count_of("player", {}, "synth_sword#c:101") == 1 and "Repair" in r1.sounds,
		"udana naprawa: +1, narzędzie 4 użycia (%s)" % [r1])
	check(String(main._equipment()[str(main.equipped_slot_of("synth_sword#c:101"))].id) == "synth_sword#c:101",
		"założony egzemplarz zmienia stan razem ze stosem")
	var r2: Dictionary = rp.repair(String(r1.tool), "synth_sword#c:101", 30)
	var at: Array = cb.attributes(me)
	var x := (0.1 * float(at[0]) + 0.1 * float(at[7]) + float(cb.skill(me, 1))) * float(cb.fatigue_term(me))
	# jakość z rekordu (float32: 1,2000000477) – int(3 × q × 30) = 108 jak w OpenMW
	var y := maxi(1, int(3.0 * float(inv.item("synth_repair_hammer").rec.quality) * 30))
	if 30.0 <= x:
		check(bool(r2.ok) and String(r2.item) == "synth_sword#c:%d" % (101 + y), "naprawa o int(3 × jakość × 30) = %d (x %.1f, %s)" % [y, x, r2])
	else:
		check(not bool(r2.ok) and "Repair Fail" in r2.sounds and String(r2.item) == "synth_sword#c:101",
			"porażka przy roll 30 > x %.1f (%s)" % [x, r2])
	var tool := String(r2.tool)
	check(tool == "synth_repair_hammer#c:3", "narzędzie traci użycie także przy porażce (%s)" % tool)
	var last := {}
	for i in 3:
		last = rp.repair(tool, String(rp.repairable()[0].id) if not rp.repairable().is_empty() else "", 99)
		tool = String(last.tool)
	check(tool == "" and inv.count_of("player", {}, "synth_repair_hammer#c:0") == 0
			and (last.messages as Array).size() == 2, "zużyte narzędzie znika z komunikatem sNotifyMessage51 (%s)" % [last])
	# --- naprawa u NPC (MerchantRepair)
	var trader := _ref(main, "synth_trader")
	check(trader != null and main.open_dialogue(trader), "rozmowa z kupcem")
	var a: Dictionary = main.dialogue.actor
	check(main.dialogue_window._topic_ids.has("#svc:repair"), "pozycja „Naprawa” (sRepair) na liście tematów")
	inv.add("player", {}, "gold_001", 1000)
	var dmg_id := String(rp.repairable()[0].id)
	var cur: float = inv.item_charge(dmg_id)
	var offers: Array = rp.merchant_offers(a)
	var p := float(maxi(1, int(inv.item("synth_sword").rec.get("value", 0))))
	var rr := float(maxi(1, int(mx / p)))
	var xp := maxi(1, int(1.0 * int((mx - cur) / rr)))
	var exp_price: int = main.trade.barter_offer(a, xp, true)
	check(offers.size() == 1 and int(offers[0].price) == exp_price and String(offers[0].text).ends_with("  - %d%s" % [exp_price, main.dialogue.gmst_text("sgp", "gp")]),
		"cena naprawy u kupca (%s, oczekiwana %d)" % [offers, exp_price])
	var gold0: int = main.trade.player_gold()
	var mg0: int = main.trade.merchant_gold(a)
	check(main.trade_window.open("repair") and main.service_window.visible and main.service_window.rows.size() == 1,
		"okno usługi naprawy (openmw_merchantrepair)")
	var sp: Control = main.service_window.panel
	check(sp != null and sp.size.is_equal_approx(Vector2(420, 250) * preload("res://scripts/mw/mw_ui.gd").ui_scale()), "okno 420 × 250")
	main.service_window.choose(dmg_id)
	check(inv.count_of("player", {}, dmg_id) == 0 and inv.count_of("player", {}, "synth_sword") == 2
			and main.trade.player_gold() == gold0 - exp_price and main.trade.merchant_gold(a) == mg0 + exp_price
			and main.service_window.rows.is_empty(),
		"naprawa u kupca: pełny stan, złoto do puli kupca")
	main.service_window.close()
	main.dialogue_window.close(true)
	# --- okno naprawy narzędziem
	cb._set_item_health(me, main.equipped_slot_of("synth_sword"), 50.0)
	inv.add("player", {}, "synth_repair_hammer", 2)
	check(main.repair_window.open("synth_repair_hammer") and main.repair_window.visible, "okno naprawy (GM_Repair)")
	await _frames(2)
	var rw = main.repair_window
	var s1: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	check(rw.panel.size.is_equal_approx(Vector2(330, 385) * s1), "okno 330 × 385 (%s)" % rw.panel.size)
	check(rw.lines.size() == 1 and rw._uses.text.ends_with(" 5") and rw._tool_box.visible, "lista ItemChargeView i narzędzie (sUses 5)")
	rw.repair_item(String(rw.lines[0].id))
	check(inv.count_of("player", {}, "synth_repair_hammer#c:4") == 1 and rw._uses.text.ends_with(" 4"), "naprawa z okna zużywa narzędzie")
	rw.close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
