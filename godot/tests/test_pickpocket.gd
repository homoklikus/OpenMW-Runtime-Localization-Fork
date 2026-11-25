extends SceneTree
## Etap 10 cz. 33: kradzież kieszonkowa jak OpenMW 0.51 – Npc::activate (skradanie / powalony NPC → ActionOpen, walka
## z graczem → sActorInCombat), ContainerWindow z PickpocketItemModel (ukryte stosy: rzut > Skradanie, bez założonych
## i przywołanych, bez wkładania), Pickpocket::pick / finish (wykrycie → OT_Pickpocket, okno zamknięte), postęp
## Skradania, rejestr skradzionych.
## godot --headless --path godot -s res://tests/test_pickpocket.gd -- --data=WYNIKI(aktorzy) --scripts=0

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
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc   # postać po kreatorze (umiejętności klasy, postęp)
	var mm = main.menu_mode
	var cr = main.crime
	var inv = main.interaction.inventory
	var v := _ref(main, "synth_villager")
	var f: Dictionary = main.combat.fighter_of(v)
	check(v != null and not f.is_empty(), "NPC do okradania")
	var sid := String(f.sid)
	inv.add(sid, f.rec, "misc_synth_spoon", 2)
	# --- ukrywanie stosów przy otwarciu: rzut 0–99 > Skradanie ---
	cr.test_roll = 99
	mm.open_container(sid, f.rec, "Villager", false, v, false)
	await _frames(1)
	check(mm.visible and not mm.pickpocket.is_empty() and mm.pickpocket_items().is_empty(), "rzut 99 > Skradanie – wszystkie stosy ukryte")
	mm.pickpocket.detected = true                       # zamknięcie bez sprawdzania (test)
	mm.close()
	cr.test_roll = 0
	mm.open_container(sid, f.rec, "Villager", false, v, false)
	await _frames(1)
	var items: Array = mm.pickpocket_items()
	var worn_shown := items.filter(func(e): return bool(e.get("worn", false)))
	check(items.size() > 0 and worn_shown.is_empty(), "rzut 0 – stosy widoczne, bez założonych (Type_Equipped) (%d)" % items.size())
	check(mm.cont_ids.has("misc_synth_spoon"), "łyżki NPC w oknie kradzieży")
	# --- bez wkładania (onDropItem) ---
	inv.add("player", {}, "misc_synth_spoon", 1)
	var pc0: int = inv.count_of("player", {}, "misc_synth_spoon")
	var nc0: int = inv.count_of(sid, f.rec, "misc_synth_spoon")
	mm.put_item("misc_synth_spoon", 1)
	check(inv.count_of(sid, f.rec, "misc_synth_spoon") == nc0, "PickpocketItemModel::onDropItem – nie można włożyć")
	# --- udana kradzież: postęp Skradania, rejestr skradzionych, bez alarmu ---
	var b0: int = cr.bounty()
	cr.test_roll = 0                                     # rzut 0 – nie wykryto
	mm.take_item("misc_synth_spoon", 1)
	check(inv.count_of("player", {}, "misc_synth_spoon") == pc0 + 1 and cr.bounty() == b0, "kradzież udana – łyżka u gracza, bez grzywny")
	check(int(((cr.st().get("stolen", {}) as Dictionary).get("misc_synth_spoon", {}) as Dictionary).get("synth_villager", 0)) >= 1,
		"rejestr skradzionych: właściciel synth_villager")
	# --- wykrycie: OT_Pickpocket, okno zamknięte, przedmiot zostaje ---
	cr.test_roll = 99
	var nc1: int = inv.count_of(sid, f.rec, "misc_synth_spoon")
	var da: Dictionary = main.dialogue.make_actor(v)
	var d0: int = int(main.dialogue.base_disposition(da))
	mm.take_item("misc_synth_spoon", 1)
	check(not mm.visible and inv.count_of(sid, f.rec, "misc_synth_spoon") == nc1, "wykrycie – okno zamknięte, przedmiot u NPC")
	var d1: int = int(main.dialogue.base_disposition(da))
	check(d1 < d0, "wykrycie – reportCrime(OT_Pickpocket): ofiara traci postawę na stałe (%d → %d)" % [d0, d1])
	# --- Pickpocket::finish przy zamknięciu ---
	cr.test_roll = 0
	mm.open_container(sid, f.rec, "Villager", false, v, false)
	cr.test_roll = 99
	mm.close()
	var d2: int = int(main.dialogue.base_disposition(da))
	check(d2 < d1 or d1 == 0, "zamknięcie okna – Pickpocket::finish wykrywa przy rzucie 99 (%d → %d)" % [d1, d2])
	# --- Pickpocket: wzór getDetected ---
	cr.test_roll = 50
	var det_small: bool = cr.pick(v, "misc_synth_spoon", 1)
	check(det_small == (50 > int(minf(float(cr._gmst("iPickMaxChance", 75)), 2.0 * cr._pick_modifier(main.combat.player_fighter())
		- cr._pick_modifier(f, 10.0 * float(cr._gmst("fPickPocketMod", 0.3)) * float(main.trade.item_value("misc_synth_spoon")))))) \
		or 2.0 * cr._pick_modifier(main.combat.player_fighter()) - cr._pick_modifier(f) < main.combat.skill(main.combat.player_fighter(), 19) / 5.0,
		"getDetected: rzut > min(iPickMaxChance, 2x − y)")
	# --- Npc::activate: skradanie → okno kradzieży, walka → bez rozmowy ---
	main.player.want_sneak = true
	await _frames(3)
	if main.player_sneaking():
		cr.test_roll = 0
		main.activate(v)
		check(mm.visible and not mm.pickpocket.is_empty(), "aktywacja NPC skradając się – okno kradzieży")
		mm.pickpocket.detected = true
		mm.close()
	main.player.want_sneak = false
	# powalony NPC – przeszukanie bez ukrywania (PickpocketItemModel, hideItems = false)
	(main.ai.ai_state(v).packages as Array).clear()          # bez walki z graczem (inCombatWithActor blokuje)
	main.combat._actor_state(f)["knocked_down"] = true
	cr.test_roll = 99
	main.activate(v)
	check(mm.visible and bool(mm.pickpocket.get("knocked", false)) and (mm.pickpocket.hidden as Dictionary).is_empty(),
		"powalony NPC – okno bez ukrytych stosów")
	mm.pickpocket.detected = true
	mm.close()
	main.combat._actor_state(f)["knocked_down"] = false
	main.ai.start_combat(v, main.player)
	main.activate(v)
	check(not mm.visible and (main.dialogue == null or not main.dialogue.is_open()) if main.dialogue.has_method("is_open") else not mm.visible,
		"NPC walczący z graczem – bez rozmowy i okna")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
