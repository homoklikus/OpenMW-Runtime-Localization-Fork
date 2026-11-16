extends SceneTree
## Odbiór etapu 7 na danych z gry: w bieżącej komórce (--cell) – handel (kupno i sprzedaż z targowaniem),
## zakup i rzucenie zaklęcia, trening, walka (trafienie, śmierć, przeszukanie), awans, mikstura, zapis/odczyt.
## Raport tylko liczbowy i z id (bez tekstów gry). Wynik: --out=plik.json
## godot --headless --path godot -s res://tools/stage7_scenario.gd -- --data=DANE --cell="Balmora, Guild of Mages"
##     --out=wynik.json --scripts=0

var report := {"steps": []}

func _init() -> void:
	_run.call_deferred()

func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return ""

func _step(name: String, ok: bool, data := {}) -> void:
	report.steps.append({"step": name, "ok": ok, "data": data})
	print("STEP %s %s %s" % ["OK " if ok else "BŁĄD", name, JSON.stringify(data)])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _actors(main) -> Array:
	var out := []
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if n.has_meta("mw_actor") and not n.get_meta("mw_disabled", false):
				out.append(n)
	return out

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	var tr = main.trade
	var mg = main.magic
	var cb = main.combat
	var inv = main.interaction.inventory
	var st: Dictionary = main.player_stats()
	var me: Dictionary = cb.player_fighter()
	inv.add("player", {}, "gold_001", 5000)
	var t0 := Time.get_ticks_msec()
	var npcs := _actors(main)
	_step("komórka i aktorzy", not npcs.is_empty(), {"cell": main.interior, "actors": npcs.map(func(n): return String(n.get_meta("mw_base", "")))})
	for n in npcs:
		var a: Dictionary = main.dialogue.make_actor(n)
		if not a.npc:
			continue
		var svc: Array = tr.service_entries(a).map(func(e): return e[0])
		if svc.is_empty():
			continue
		main.dialogue.actor = a
		tr.restock(a)
		var info := {"npc": a.base, "services": svc}
		if "barter" in svc:
			var items: Array = tr.merchant_items(a)
			if not items.is_empty():
				var it: Dictionary = items[0]
				var buy := {String(it.id): 1}
				var price: int = tr.merchant_offer(a, buy, {})
				var g0: int = tr.player_gold()
				var r: Dictionary = tr.offer(a, buy, {}, price, 1)
				info["buy"] = {"id": it.id, "base_value": tr.item_value(String(it.id)), "offer": price, "ok": r.get("ok", false),
					"gold_change": tr.player_gold() - g0, "have": inv.count_of("player", {}, String(it.id))}
				var sell := {String(it.id): 1}
				var sp: int = tr.merchant_offer(a, {}, sell)
				var r2: Dictionary = tr.offer(a, {}, sell, sp, 1)
				info["sell"] = {"offer": sp, "ok": r2.get("ok", false)}
		if "spells" in svc:
			var sale: Array = tr.spells_for_sale(a)
			if not sale.is_empty():
				var cheapest: Dictionary = sale[0]
				for s in sale:
					if int(s.price) < int(cheapest.price):
						cheapest = s
				var ok: bool = tr.buy_spell(a, String(cheapest.id))
				info["spell"] = {"id": cheapest.id, "price": cheapest.price, "bought": ok, "for_sale": sale.size()}
		if "training" in svc:
			var offers: Array = tr.training_offers(a)
			if not offers.is_empty():
				var sk := int(offers[0].skill)
				var before := float(st.skills[sk])
				var r3: Dictionary = tr.train(a, sk)
				info["training"] = {"skill": sk, "price": offers[0].price, "ok": r3.get("ok", false), "from": before, "to": float(st.skills[sk])}
		if "travel" in svc:
			info["travel"] = tr.travel_offers(a).map(func(o): return {"cell": o.cell, "price": o.price})
		_step("usługi NPC", true, info)
	# zaklęcia gracza: każde kupione/znane zaklęcie „na siebie” i „dotyk” – rzucenie (rzut 0) na pierwszego NPC
	var target: Dictionary = {}
	for n in npcs:
		var f: Dictionary = cb.fighter_of(n)
		if not f.is_empty() and not cb.is_dead(f):
			target = f
			break
	st.magicka = mg.max_magicka(me) + 200.0
	for sid in (st.spells as Array).duplicate():
		var sp: Dictionary = mg.records.record("spell", String(sid))
		if int(sp.get("spell_type", -1)) != 0:
			continue
		var h0: float = cb.health(target) if not target.is_empty() else 0.0
		var m0: float = mg.magicka(me)
		var r4: Dictionary = mg.cast_spell(me, String(sid), target, 0)
		mg.tick(me, 1.0)
		if not target.is_empty():
			mg.tick(target, 1.0)
		_step("rzucenie zaklęcia", bool(r4.get("success", false)), {"spell": sid, "cost": r4.get("cost"), "chance": r4.get("chance"),
			"magicka_used": m0 - mg.magicka(me), "target": target.get("base", ""), "target_health_change": (cb.health(target) - h0) if not target.is_empty() else 0.0,
			"bolt_effects": (r4.get("bolt", []) as Array).size()})
	# walka: sztylet, trafienie (rzut 0), śmierć i przeszukanie
	if not target.is_empty():
		inv.add("player", {}, "iron dagger", 1)
		main.equip_item("iron dagger")
		cb.test_roll = 50
		var h1: float = cb.health(target)
		var r5: Dictionary = cb.melee(me, target, 2, 1.0, 0)
		_step("trafienie bronią", bool(r5.get("success", false)) and cb.health(target) < h1, {"target": target.base, "chance": r5.get("chance"), "damage": r5.get("damage")})
		cb.set_health(target, 1.0)
		var r6: Dictionary = cb.melee(me, target, 2, 1.0, 0)
		cb.test_roll = -1
		var loot: Array = inv.contents(target.sid, target.rec)
		_step("śmierć i przeszukanie", bool(r6.get("victim_dead", false)) and cb.is_dead(target), {"items_on_body": loot.size()})
	# mikstura z danych
	inv.add("player", {}, "p_restore_health_s", 1)
	st.health = 5.0
	var dr: Dictionary = mg.drink(me, "p_restore_health_s")
	for i in 120:
		mg.tick(me, 0.5)
	_step("mikstura", bool(dr.get("success", false)) and float(st.health) > 5.0, {"health": st.health})
	# awans: 10 podniesień umiejętności głównych → odpoczynek → 3 atrybuty
	var cls: Dictionary = mg.records.record("class", String(st.get("class", "")))
	var majors: Array = cls.get("major_skills", [])
	var lv0 := int(st.level)
	var hb0: float = float(main.character.derived(st).health.base)
	for i in 10:
		main.character.skill_level_up(st, int(majors[i % majors.size()]), "usage")
	var can: bool = main.character.can_level_up(st)
	var chosen := [0, 5, 2]
	var mult := chosen.map(func(a): return main.character.levelup_multiplier(st, a))
	main.character.level_up(st, chosen)
	_step("awans", can and int(st.level) == lv0 + 1, {"level": st.level, "multipliers": mult,
		"health_gain": float(main.character.derived(st).health.base) - hb0})
	# zapis/odczyt
	var path := ProjectSettings.globalize_path("user://stage7/odbior.mwsave")
	var e: String = main.save_game(path)
	var lw: Array = main.load_game(path)
	await _frames(3)
	_step("zapis i odczyt", e == "" and int(main.player_stats().level) == lv0 + 1, {"warnings": lw.size()})
	report["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	report["unsupported_effects"] = mg.unsupported
	var f2 := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f2.store_string(JSON.stringify(report, " "))
	f2.close()
	quit(0)
