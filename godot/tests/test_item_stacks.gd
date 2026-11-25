extends SceneTree
## Etap 10 cz. 32: stosy przedmiotów jak ItemStack OpenMW 0.51 – ContainerStore::stacks (przedmioty ze skryptem nigdy
## nie łączą się w stos, różny stan – osobne stosy), InventoryStore::stacks (założony egzemplarz osobno, amunicja
## i broń miotana łączą się także założone), InventoryItemModel (Type_Equipped), TradeItemModel (założone u kupca
## niewidoczne), podniesienie niezałożonego stosu bez zdejmowania założonego egzemplarza.
## godot --headless --path godot -s res://tests/test_item_stacks.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _entries(mm, id: String) -> Array:
	return mm.sorted_items("player").filter(func(e): return String(e.id) == id)

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
	var inv = main.interaction.inventory
	var mm = main.menu_mode
	const PAPERS := "synth_papers"                  # drobiazg ze skryptem (synth_paper)
	const SWORD := "synth_sword"
	const ARROW := "synth_arrow"
	# --- przedmioty ze skryptem: każda porcja osobnym stosem ---
	check(inv.is_scripted(PAPERS) and not inv.is_scripted(SWORD), "is_scripted wg pola script rekordu")
	var p0: int = inv.count_of("player", {}, PAPERS)
	if p0 > 0:
		inv.remove("player", {}, PAPERS, p0)
	inv.add("player", {}, PAPERS, 1)
	inv.add("player", {}, PAPERS, 2)
	var pe := _entries(mm, PAPERS)
	check(inv.count_of("player", {}, PAPERS) == 3, "liczba sztuk przedmiotu ze skryptem (%d)" % inv.count_of("player", {}, PAPERS))
	check(pe.size() == 2 and pe.map(func(e): return int(e.count)).has(1) and pe.map(func(e): return int(e.count)).has(2),
		"przedmiot ze skryptem: dwa osobne stosy 1 + 2 (%s)" % [pe.map(func(e): return e.count)])
	inv.remove("player", {}, PAPERS, 2)                 # ubywa od ostatniego stosu
	pe = _entries(mm, PAPERS)
	check(pe.size() == 1 and int(pe[0].count) == 1, "po zabraniu 2 sztuk – jeden stos 1 (%s)" % [pe.map(func(e): return e.count)])
	inv.add("player", {}, PAPERS, 4)
	var saved: Dictionary = main.state.to_dict({})
	var copy = main.state.get_script().new()
	copy.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var ent: Array = (copy.inventory("player") as Array).filter(func(e): return String(e.id) == PAPERS)
	check(ent.size() == 1 and inv.stacks_of(ent[0]) == [1, 4], "stosy przedmiotu ze skryptem w zapisie gry (%s)" % [ent])
	# --- stan z referencji (INTV) i dusza: identyfikator stosu ---
	check(inv.ref_stack_id(SWORD, {"health": 100}) == SWORD + "#c:100", "uszkodzona broń z referencji – osobny stos #c:N")
	check(inv.ref_stack_id(SWORD, {"health": 300}) == SWORD and inv.ref_stack_id(SWORD, {"health": -1}) == SWORD,
		"pełny stan / brak stanu – stos bez przyrostka")
	check(inv.ref_stack_id(ARROW, {"health": 1}) == ARROW, "amunicja bez wytrzymałości (WeaponType bez HasHealth)")
	# --- założony egzemplarz osobnym stosem (Type_Equipped) ---
	var s0: int = inv.count_of("player", {}, SWORD)
	inv.add("player", {}, SWORD, 3 - s0 if s0 < 3 else 0)
	main.equip_item(SWORD, false)
	var se := _entries(mm, SWORD)
	var worn := se.filter(func(e): return bool(e.worn))
	var loose := se.filter(func(e): return not bool(e.worn))
	check(worn.size() == 1 and int(worn[0].count) == 1 and loose.size() == 1 and int(loose[0].count) == inv.count_of("player", {}, SWORD) - 1,
		"założony miecz: stos założony 1 + niezałożone (%s)" % [se.map(func(e): return [e.count, e.worn])])
	check(int(worn[0].stype) == 1 and int(loose[0].stype) == 2, "SortFilterItemModel: założony (Type_Equipped) przed zwykłym")
	# podniesienie niezałożonego stosu – założony egzemplarz zostaje (ensureSelectedItemUnequipped tylko dla założonego)
	mm.pressed_stack = loose[0].stack
	mm.cell_pressed(SWORD, "inventory", {"shift": true})
	mm.pressed_stack = {}
	check(mm.is_holding() and int(mm.held.count) == int(loose[0].count), "podniesione tylko sztuki niezałożone (%s)" % [mm.held])
	check(main.equipped_slot_of(SWORD) >= 0, "założony miecz nadal założony po podniesieniu niezałożonych")
	mm.held_drop("inventory")
	# podniesienie założonego stosu – zdjęcie
	worn = _entries(mm, SWORD).filter(func(e): return bool(e.worn))
	mm.pressed_stack = worn[0].stack
	mm.cell_pressed(SWORD, "inventory", {"shift": true})
	mm.pressed_stack = {}
	check(mm.is_holding() and int(mm.held.count) == 1 and main.equipped_slot_of(SWORD) < 0, "podniesiony założony egzemplarz – zdjęty (%s)" % [mm.held])
	mm.held_drop("inventory")
	# amunicja: założony cały stos (getEquipmentSlots().second)
	var a0: int = inv.count_of("player", {}, ARROW)
	if a0 < 20:
		inv.add("player", {}, ARROW, 20 - a0)
	main.equip_item(ARROW, false)
	var ae := _entries(mm, ARROW)
	if main.equipped_slot_of(ARROW) >= 0:
		check(ae.size() == 1 and bool(ae[0].worn) and int(ae[0].count) == inv.count_of("player", {}, ARROW), "amunicja: jeden założony stos (%s)" % [ae.map(func(e): return [e.count, e.worn])])
	else:
		check(ae.size() == 1, "amunicja niezałożona – jeden stos")
	# --- handel: stosy po odjęciu koszyka, gracz z założonym egzemplarzem ---
	var TW = main.trade_window.get_script()
	var sp: Array = TW.split_stacks({"count": 5, "stacks": [{"count": 1, "worn": true}, {"count": 4, "worn": false}]}, 3)
	check(sp.size() == 2 and bool(sp[0].worn) and int(sp[0].count) == 1 and int(sp[1].count) == 2,
		"koszyk zabiera najpierw sztuki niezałożone (%s)" % [sp])
	sp = TW.split_stacks({"count": 3, "stacks": [1, 2]}, 2)
	check(sp.size() == 2 and int(sp[0].count) == 1 and int(sp[1].count) == 1, "stosy kupca (przedmiot ze skryptem) po koszyku (%s)" % [sp])
	var into := []
	main.trade._merge_stacks(into, [2], true)
	main.trade._merge_stacks(into, [1], true)
	var into2 := []
	main.trade._merge_stacks(into2, [2], false)
	main.trade._merge_stacks(into2, [1], false)
	check(into == [2, 1] and into2 == [3], "ContainerItemModel: ze skryptem osobno, inne w jednym stosie (%s %s)" % [into, into2])
	var trader := _ref(main, "synth_trader")
	if trader != null and main.open_dialogue(trader):
		var a: Dictionary = main.dialogue.actor
		main.equip_item(SWORD, false)
		var pi: Array = main.trade.player_items(a).filter(func(x): return String(x.id) == SWORD)
		check(pi.size() == 1 and (pi[0].stacks as Array).size() == 2, "ekwipunek gracza w handlu: założony stos osobno (%s)" % [pi])
		# zwłoki / towarzysz: InventoryItemModel aktora – założone egzemplarze NPC osobnym stosem Type_Equipped
		var own: Array = inv.contents(String(a.sid), a.rec)
		var aw: Dictionary = mm.actor_worn(String(a.sid), a.rec, own)
		var ce: Array = mm.sorted_items(String(a.sid), a.rec)
		var ok_worn := not aw.is_empty()
		for id in aw:
			var w := ce.filter(func(e): return String(e.id) == id and bool(e.worn))
			ok_worn = ok_worn and w.size() == mini(int(aw[id]), inv.count_of(String(a.sid), a.rec, id)) and int(w[0].stype) == 1
		check(ok_worn, "założone przedmioty NPC w oknie pojemnika osobno, przed zwykłymi (%s)" % [aw])
		# sprzedaż sztuki z założonego stosu – zdjęcie (InventoryStore::remove), niezałożone zostają
		var c0: int = inv.count_of("player", {}, SWORD)
		main.equip_item(SWORD, false)
		var mo: int = main.trade.merchant_offer(a, {}, {SWORD: 1})
		var r: Dictionary = main.trade.offer(a, {}, {SWORD: 1}, mo, 1, {SWORD: 1})
		check(bool(r.ok) and inv.count_of("player", {}, SWORD) == c0 - 1 and main.equipped_slot_of(SWORD) < 0,
			"sprzedany założony egzemplarz zdjęty (%s, %d)" % [r, inv.count_of("player", {}, SWORD)])
		main.equip_item(SWORD, false)
		mo = main.trade.merchant_offer(a, {}, {SWORD: 1})
		r = main.trade.offer(a, {}, {SWORD: 1}, mo, 1, {})
		check(bool(r.ok) and main.equipped_slot_of(SWORD) >= 0, "sprzedana sztuka niezałożona – założony egzemplarz zostaje")
		var sw: Array = TW.split_stacks({"count": 3, "stacks": [{"count": 1, "worn": true}, {"count": 2, "worn": false}]}, 2, 1)
		check(sw.size() == 1 and not bool(sw[0].worn) and int(sw[0].count) == 2, "koszyk ze sztuką z założonego stosu (%s)" % [sw])
		for it in main.trade.merchant_items(a):
			var tot := 0
			for p in it.stacks:
				tot += int(p)
			if tot != int(it.count):
				check(false, "stosy kupca sumują się do liczby sztuk (%s)" % [it])
				break
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
