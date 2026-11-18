extends SceneTree
## Etap 7d: magia – szansa i koszt zaklęć, rzucanie (magia, postęp umiejętności), efekty ciągłe i jednorazowe,
## dotyk i pocisk, odporność, moce raz na dobę, mikstury, składniki, alchemia (aparaty, wartość, rekord
## dynamiczny), przedmioty zaklęte (użycie, ładunek, ładowanie, zwój, stały efekt, przy uderzeniu), pułapka dusz,
## zaklinanie (koszty narastające, szansa, nowy przedmiot), zapis v5 (rekordy utworzone w grze).
## godot --headless --path godot -s res://tests/test_magic.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

static func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var mg = main.magic
	var cb = main.combat
	var inv = main.interaction.inventory
	var st: Dictionary = main.player_stats()
	var me: Dictionary = cb.player_fighter()
	st.attributes = [40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0]
	for i in 27:
		st.skills[i] = 50.0
	st.skills[15] = 10.0                                   # przywracanie
	st.health_base = 100.0
	st.health = 10.0
	var d: Dictionary = main.character.derived(st)
	st.fatigue = d.fatigue.modified
	st.magicka = 50.0
	for s in ["synth_heal", "synth_touch", "synth_soultrap", "synth_open", "synth_strength", "synth_bolt"]:
		st.spells.append(s)
	mg.test_roll = 99                                     # odporność: rzut 99 – bez częściowego oporu
	check(near(float(main.character.derived(st).attributes[7]), 40.0), "szczęście 40")
	# koszt i szansa: przywracanie 10 → 2×10 − 1 + 0,2×40 + 0,1×40 = 31 × 1,25 = 38,75
	var heal: Dictionary = mg.records.record("spell", "synth_heal")
	check(mg.spell_cost(heal) == 1, "koszt leczenia 5 pkt × 4 s = 1 (%d)" % mg.spell_cost(heal))
	check(near(mg.spell_chance(heal, me), 38.75), "szansa 38,75 (%s)" % mg.spell_chance(heal, me))
	var r: Dictionary = mg.cast_spell(me, "synth_heal", {}, 39)
	check(not bool(r.success) and near(float(st.magicka), 49.0), "rzut 39 ≥ 38,75 – porażka, magia pobrana")
	r = mg.cast_spell(me, "synth_heal", {}, 38)
	check(bool(r.success) and near(float(st.magicka), 48.0), "rzut 38 – sukces")
	check(float(st.get("skill_progress", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])[15]) > 0.0, "postęp przywracania za rzucenie")
	check(mg.active(me).size() == 1 and near(float(st.health), 10.0), "efekt ciągły – nic w chwili rzucenia")
	mg.tick(me, 1.0)
	check(near(float(st.health), 15.0), "1 s: +5 zdrowia (%s)" % st.health)
	mg.tick(me, 10.0)
	check(near(float(st.health), 30.0) and mg.active(me).is_empty(), "razem 5 × 4 s = +20, czar wygasł (%s)" % st.health)
	# dotyk: obrażenia 10 (natychmiast), odporność na magię 0
	var vic: Dictionary = cb.fighter_of(_ref(main, "synth_villager"))
	var h0: float = cb.health(vic)
	r = mg.cast_spell(me, "synth_touch", vic, 0)
	check(bool(r.success) and near(cb.health(vic), h0 - 10.0) and bool(main.state.actors[vic.sid].get("attacked", false)), "dotyk: −10 zdrowia NPC, NPC zaatakowany")
	# pocisk ognia 10..20 (losowanie: min), czas 1 s
	var bolt: Dictionary = mg.records.record("spell", "synth_bolt")
	check(mg.spell_cost(bolt) == 6, "koszt pocisku: 15 × 0,1 × 5 × 0,5 × 1,5 = 5,625 → 6")
	r = mg.cast_spell(me, "synth_bolt", {}, 0)
	check(bool(r.success) and (r.bolt as Array).size() == 1, "pocisk: efekty „cel” do wystrzelenia")
	mg.test_magnitude = 0
	mg.bolt_hit(me, vic, r.source, r.bolt, r.spell)
	mg.tick(vic, 1.0)
	check(near(cb.health(vic), h0 - 20.0), "ogień 10 × 1 s (%s)" % (h0 - cb.health(vic)))
	# odporność na ogień 50 → mnożnik 0,5
	mg.inflict(vic, {}, {"id": "t", "name": "t", "kind": "potion"}, [{"effect": 90, "min": 50, "max": 50, "duration": 30}])
	check(near(mg.effect_resistance(14, vic, me, bolt, 99), 50.0), "odporność na ogień 50 (%s)" % mg.effect_resistance(14, vic, me, bolt, 99))
	# wzmocnienie siły NPC (atrybuty NPC z efektami)
	var s0: float = float(cb.attributes(vic)[0])
	mg.inflict(vic, {}, {"id": "t2", "name": "t2", "kind": "potion"}, [{"effect": 79, "attribute": 0, "min": 10, "max": 10, "duration": 5}])
	check(near(float(cb.attributes(vic)[0]), s0 + 10.0), "NPC: siła +10")
	mg.tick(vic, 6.0)
	check(near(float(cb.attributes(vic)[0]), s0), "po wygaśnięciu siła wraca")
	# zmiana maksimum kondycji zachowuje stosunek (setAttribute): pełna kondycja zostaje pełna
	var fm0: float = main.character.derived(st).fatigue.modified
	st.fatigue = fm0
	mg.inflict(me, {}, {"id": "agi", "name": "agi", "kind": "potion"}, [{"effect": 79, "attribute": 3, "min": 20, "max": 20, "duration": 1}])
	check(near(float(st.fatigue), fm0 + 20.0), "kondycja rośnie z maksimum (%s)" % st.fatigue)
	mg.tick(me, 2.0)
	check(near(float(st.fatigue), fm0), "po wygaśnięciu – z powrotem do maksimum (%s)" % st.fatigue)
	# moc raz na dobę
	r = mg.cast_spell(me, "synth_power", {}, 0)
	check(bool(r.success), "moc – użycie")
	r = mg.cast_spell(me, "synth_power", {}, 0)
	check(not bool(r.success) and not mg.can_use_power(me, "synth_power"), "moc – drugi raz tego dnia nie")
	main.envr.advance(25.0)
	check(mg.can_use_power(me, "synth_power"), "moc po 24 h znów dostępna")
	# mikstura: +10 zdrowia/s × 2 s, siła +10 × 5 s
	inv.add("player", {}, "synth_potion", 1)
	st.health = 10.0
	var str0: float = float(main.character.derived(st).attributes[0])
	check(bool(mg.drink(me, "synth_potion").success) and inv.count_of("player", {}, "synth_potion") == 0, "wypicie mikstury")
	check(near(float(main.character.derived(st).attributes[0]), str0 + 10.0), "mikstura: siła +10 od razu")
	mg.tick(me, 1.0)
	mg.tick(me, 5.0)
	check(near(float(st.health), 30.0) and near(float(main.character.derived(st).attributes[0]), str0), "mikstura: +20 zdrowia, siła wróciła (%s)" % st.health)
	# składnik: x = (50 + 8 + 4) × 1,25 = 77,5; rzut 40 → czas 10 s, wielkość ⌊0,05 × 10 / 0,1⌋ = 5
	inv.add("player", {}, "synth_ing_a", 3)
	var ie: Dictionary = mg.ingredient_effect(me, mg.records.record("ingredient", "synth_ing_a"), 40)
	check(int(ie.get("effect", -1)) == 75 and int(ie.duration) == 10 and int(ie.min) == 5, "efekt składnika (%s)" % [ie])
	check(mg.ingredient_effect(me, mg.records.record("ingredient", "synth_ing_a"), 90).is_empty(), "rzut 90 > x – bez efektu")
	var er: Dictionary = mg.eat(me, "synth_ing_a", 40)
	check(bool(er.success) and inv.count_of("player", {}, "synth_ing_a") == 2 and float(st.skill_progress[16]) > 0.0, "zjedzenie: składnik zużyty, postęp alchemii")
	# alchemia: czynnik 50 + 4 + 4 = 58; × moździerz 1,0 × 0,5 = 29; wartość 58;
	# wielkość 29/1,5 + retorta 0,5 = 19,83 → 20; czas 29/0,5 + 0,5 = 58,5 → 59
	for a in ["synth_mortar", "synth_retort", "synth_alembic"]:
		inv.add("player", {}, a, 1)
	inv.add("player", {}, "synth_ing_b", 3)
	inv.add("player", {}, "synth_ing_c", 1)
	var ar: Dictionary = mg.alchemy_result(me, ["synth_ing_a", "synth_ing_b"])
	check(int(ar.value) == 58 and (ar.effects as Array).size() == 1, "alchemia: wartość 58, 1 wspólny efekt (%s)" % [ar])
	var pe: Dictionary = (ar.effects as Array)[0] if not (ar.effects as Array).is_empty() else {}
	check(int(pe.get("effect", -1)) == 75 and int(pe.get("min", 0)) == 20 and int(pe.get("duration", 0)) == 59, "alchemia: leczenie 20 pkt × 59 s (%s)" % [pe])
	var ar2: Dictionary = mg.alchemy_result(me, ["synth_ing_a", "synth_ing_c"])
	check(not (ar2.effects as Array).is_empty() and int(ar2.effects[0].effect) == 79 and int(ar2.effects[0].attribute) == 0, "wspólne wzmocnienie siły (atrybut 0)")
	var br: Dictionary = mg.brew(me, ["synth_ing_a", "synth_ing_b"], "Moja mikstura", 0)
	var pid := String(br.get("potion", ""))
	check(br.result == "success" and inv.count_of("player", {}, pid) == 1 and inv.count_of("player", {}, "synth_ing_a") == 1, "mikstura stworzona, składniki zużyte (%s)" % [br])
	var prec: Dictionary = inv.item(pid).get("rec", {})
	check(String(prec.get("name", "")) == "Moja mikstura" and int(prec.get("value", 0)) == 58 and near(float(prec.get("weight", 0)), 0.75), "rekord mikstury: nazwa, wartość, waga średnia")
	check(float(st.skill_progress[16]) > 0.0 and not main.db.get_object(pid).is_empty(), "postęp alchemii; obiekt do położenia w świecie")
	var br2: Dictionary = mg.brew(me, ["synth_ing_a", "synth_ing_b"], "Moja mikstura", 0)
	check(String(br2.get("potion", "")) == pid and inv.count_of("player", {}, pid) == 2, "ta sama mikstura – ten sam rekord")
	check(mg.brew(me, ["synth_ing_b", "synth_ing_c"], "X", 99).result == "failure" and inv.count_of("player", {}, "synth_ing_c") == 0, "porażka (rzut 99 > 58) – składniki przepadają")
	# przedmiot zaklęty po użyciu: koszt 5 − 5/100 × (50 − 10) = 3; ładunek 50 → 47; ładowanie 0,05/s
	inv.add("player", {}, "synth_ring", 1)
	r = mg.use_item(me, "synth_ring")
	var ring_en: Dictionary = mg.item_enchantment(inv.item("synth_ring"))
	check(bool(r.success) and near(mg.item_charge(me, "synth_ring", ring_en), 47.0), "pierścień: ładunek 50 − 3 (%s)" % mg.item_charge(me, "synth_ring", ring_en))
	check(float(st.skill_progress[9]) > 0.0, "postęp zaklinania za użycie")
	mg.recharge(st, 20.0)
	check(near(mg.item_charge(me, "synth_ring", ring_en), 48.0), "ładowanie 20 s × 0,05")
	inv.add("player", {}, "synth_scroll", 1)
	st.health = 10.0
	r = mg.use_item(me, "synth_scroll")
	check(bool(r.success) and inv.count_of("player", {}, "synth_scroll") == 0 and near(float(st.health), 40.0), "zwój: zużyty, +30 zdrowia")
	# stały efekt: amulet zręczność +10
	inv.add("player", {}, "synth_amulet", 1)
	var ag0: float = float(main.character.derived(st).attributes[3])
	main.equip_item("synth_amulet")
	check(near(float(main.character.derived(st).attributes[3]), ag0 + 10.0), "amulet: zręczność +10")
	main.unequip_slot(main.equipped_slot_of("synth_amulet"))
	check(near(float(main.character.derived(st).attributes[3]), ag0), "zdjęty amulet – bez efektu")
	# przy uderzeniu: −5 zdrowia (dotyk), ładunek 100 − (10 − 4) = 94
	inv.add("player", {}, "synth_dagger_fire", 1)
	main.equip_item("synth_dagger_fire")
	cb.test_roll = 50
	var mr: Dictionary = cb.melee(me, vic, 0, 1.0, 0)
	var den: Dictionary = mg.item_enchantment(inv.item("synth_dagger_fire"))
	check(bool(mr.success) and bool(mr.get("enchanted", false)) and near(mg.item_charge(me, "synth_dagger_fire", den), 94.0), "zaklęcie przy uderzeniu (%s)" % [mr])
	cb.test_roll = -1
	main.unequip_slot(16)
	# pułapka dusz: stworzenie (dusza 5) → kamień o pojemności 20 × 3
	inv.add("player", {}, "misc_soulgem_synth", 1)
	var cr: Dictionary = cb.fighter_of(_ref(main, "synth_creature"))
	r = mg.cast_spell(me, "synth_soultrap", cr, 0)
	check(bool(r.success) and mg.magnitude_of(cr, 58) > 0.0, "pułapka dusz na stworzeniu")
	cb.set_health(cr, 0.0)
	main.on_actor_died(cr, me)
	var gem := "misc_soulgem_synth@synth_creature"
	check(inv.count_of("player", {}, gem) == 1 and inv.count_of("player", {}, "misc_soulgem_synth") == 0 and mg.gem_charge(gem) == 5, "dusza w kamieniu (ładunek 5)")
	check(main.interaction.item_name("misc", gem, inv.item(gem).rec).contains("("), "nazwa kamienia z duszą")
	# GetItemCount po RefId (ContainerStore::count): kamień z duszą liczony jako ten sam przedmiot co pusty
	var vctx = main.scripts.Ctx.new()
	vctx.scr = "console"
	var gic = main.scripts._call("player", "getitemcount", [["str", "misc_soulgem_synth"]], vctx)
	check(float(gic) == 1.0, "GetItemCount liczy kamień z duszą (%s)" % [gic])
	# zaklinanie: ((5+5) × 10 + 1) × 1 × 0,5 × 0,05 = 2,525; szansa (50 − 7,575 + 8 + 4) × 1,25 = 68
	st.fatigue = main.character.derived(st).fatigue.modified
	var fx := [{"effect": 75, "skill": -1, "attribute": -1, "range": 0, "area": 0, "duration": 10, "min": 5, "max": 5}]
	check(near(mg.enchant_points(fx, 2), 2.525, 0.001) and mg.enchant_cast_cost(fx, 2) == 2, "punkty zaklęcia 2,525, koszt 2")
	check(near(mg.enchant_points(fx + fx, 2), 7.575, 0.001), "koszty narastające: 2,525 + 5,05")
	check(mg.enchant_chance(me, fx, 2) == 68, "szansa zaklinania 68 (%d)" % mg.enchant_chance(me, fx, 2))
	inv.add("player", {}, "synth_plain_ring", 1)
	check(mg.cast_types_for(inv.item("synth_plain_ring"), gem) == [2], "pierścień: tylko „po użyciu” (słaba dusza)")
	check(mg.max_enchant_value(inv.item("synth_plain_ring")) == 50, "pojemność 500 × 0,1")
	var en: Dictionary = mg.enchant(me, "synth_plain_ring", gem, fx, 2, "Mój pierścień", {}, 0)
	var nid := String(en.get("item", ""))
	var nit: Dictionary = inv.item(nid)
	check(bool(en.success) and inv.count_of("player", {}, nid) == 1 and inv.count_of("player", {}, "synth_plain_ring") == 0
		and inv.count_of("player", {}, gem) == 0, "zaklęty pierścień: nowy przedmiot, stary i kamień zużyte (%s)" % [en])
	var nen: Dictionary = mg.item_enchantment(nit)
	check(String(nit.rec.get("name", "")) == "Mój pierścień" and int(nen.get("charge", 0)) == 5 and int(nen.get("cost", 0)) == 2, "rekord: nazwa, ładunek 5, koszt 2")
	r = mg.use_item(me, nid)
	check(bool(r.success) and near(mg.item_charge(me, nid, nen), 4.0), "użycie: koszt 2 − 2/100 × 40 = 1,2 → 1")
	check(not bool(mg.enchant(me, nid, gem, fx, 2, "X", {}, 0).success), "bez kamienia/z zaklętym – odmowa")
	# okna (dym): magia, alchemia, zaklinanie
	main.magic_window.open_spells()
	check(main.magic_window.visible and main.magic_window.left.item_count >= 6 and main.magic_window.right.item_count >= 1, "okno magii: zaklęcia i przedmioty")
	main.magic_window._click_left(0)
	check(not main.selected_magic().is_empty(), "wybór magii z okna")
	main.magic_window.close()
	inv.add("player", {}, "synth_ing_b", 1)
	main.magic_window.open_alchemy()
	check(main.magic_window.left.item_count >= 1 and main.magic_window.info.text.contains("synth_mortar"), "okno alchemii")
	main.magic_window.close()
	main.magic_window.open_enchant()
	check(main.magic_window.right.item_count >= 2, "okno zaklinania: znane efekty")
	main.magic_window.close()
	# rzucenie przez gracza (wybrana magia)
	main.select_magic("spell", "synth_heal")
	st.magicka = 20.0
	r = main.player_cast(0)
	check(bool(r.get("success", false)) and near(float(st.magicka), 19.0), "player_cast: zaklęcie wybrane")
	# zapis v5: rekordy utworzone w grze, działające czary
	mg.inflict(me, me, {"id": "zz", "name": "zz", "kind": "spell"}, [{"effect": 79, "attribute": 0, "min": 5, "max": 5, "duration": 100}])
	var path := ProjectSettings.globalize_path("user://test_saves/magia.mwsave")
	check(main.save_game(path) == "", "zapis")
	main.state.created = {}
	main.load_game(path)
	await _frames(3)
	check(not inv.item(pid).is_empty() and not inv.item(nid).is_empty() and String(inv.item(nid).rec.get("enchant", "")) != "", "odczyt: mikstura i pierścień z zapisu")
	check(mg.active(cb.player_fighter()).size() >= 1, "odczyt: działające czary gracza")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "unsupported": mg.unsupported}))
	quit(1 if failures.size() > 0 else 0)
