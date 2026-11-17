extends SceneTree
## Etap 7c: walka – zakładanie broni, szansa trafienia (getHitChance), obrażenia broni (siła, stan broni),
## pancerz (bez pancerza), zużycie broni, chybienie, walka wręcz w kondycję, trafienie gracza, śmierć
## (licznik zabitych, OnDeath, ciało do przeszukania), łuk i strzały (lot pocisku), zapis stanu aktorów.
## godot --headless --path godot -s res://tests/test_combat.gd -- --data=WYNIKI(aktorzy) --scripts=0

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
	var cb = main.combat
	var inv = main.interaction.inventory
	inv.add("player", {}, "synth_sword", 1)
	check(main.equip_item("synth_sword") == "" and main.equipped_slot_of("synth_sword") == 16, "miecz w prawej ręce")
	var me: Dictionary = cb.player_fighter()
	var w: Dictionary = cb.weapon(me)
	check(not w.is_empty() and cb.weapon_skill(w) == 5, "broń: długie ostrze")
	var v := _ref(main, "synth_villager")
	var vic: Dictionary = cb.fighter_of(v)
	check(near(cb.max_health(vic), 46.0), "zdrowie NPC z autoobliczania 40 + 3 × 2 = 46 (%s)" % cb.max_health(vic))
	# szansa: (45 + 40/5 + 40/10) × 1,25 − (40/5 + 40/10) × 1,25 = 71,25 − 15 → 56
	check(cb.hit_chance(me, vic, cb.skill(me, 5)) == 56.0, "szansa trafienia 56 (%s)" % cb.hit_chance(me, vic, cb.skill(me, 5)))
	# obrażenia: cięcie 2..8 przy sile 1 → 8 × (0,5 + 50 × 0,1 × 0,1) = 8
	check(near(cb.weapon_damage(me, w, 0, 1.0), 8.0), "obrażenia broni (%s)" % cb.weapon_damage(me, w, 0, 1.0))
	check(near(cb.weapon_damage(me, w, 2, 0.5), 2.5), "pchnięcie 1..4 przy sile 0,5 → 2,5")
	# pancerz NPC: bez pancerza 5 → (0,1 × 5) × (0,065 × 5) = 0,1625
	check(near(cb.armor_rating(vic), 0.1625, 0.0001), "ocena pancerza bez zbroi (%s)" % cb.armor_rating(vic))
	var f0: float = cb.fatigue(me)
	cb.test_roll = 50                                        # stały rzut (miejsce pancerza, powalenie)
	var r: Dictionary = cb.melee(me, vic, 0, 1.0, 0)
	var expect := 8.0 * 8.0 / (8.0 + 0.1625)
	check(bool(r.success) and near(cb.health(vic), 46.0 - expect), "trafienie: zdrowie 46 − %.2f (%s)" % [expect, cb.health(vic)])
	check(near(cb.fatigue(me), f0 - (2.0 + 10.0 * 1.0 * 0.25)), "kondycja za atak: 2 + waga 10 × 0,25 (%s)" % (f0 - cb.fatigue(me)))
	check(near(cb.item_health(cb.weapon(me)), 299.0), "stan miecza 300 → 299")
	check(float(main.player_stats().skill_progress[5]) > 0.0, "postęp długich ostrzy za trafienie")
	var hv: float = cb.health(vic)
	check(not bool(cb.melee(me, vic, 0, 1.0, 99).success) and near(cb.health(vic), hv), "rzut 99 – chybienie")
	# wręcz: w kondycję (5 × (0,1 + 0,4 × 1) = 2,5)
	main.unequip_slot(16)
	var fv: float = cb.fatigue(vic)
	var r2: Dictionary = cb.melee(me, vic, 0, 1.0, 0)
	check(bool(r2.success) and not bool(r2.health) and near(fv - cb.fatigue(vic), 2.5) and near(cb.health(vic), hv), "walka wręcz – kondycja (%s)" % [r2])
	# trafienie gracza (bez pancerza, przez NPC)
	var hp0: float = cb.health(me)
	cb.on_hit(me, vic, {"health": 10.0}, true)
	check(cb.health(me) < hp0 and cb.health(me) > hp0 - 10.0, "gracz traci zdrowie (pancerz zmniejsza: %s)" % (hp0 - cb.health(me)))
	# śmierć
	main.equip_item("synth_sword")
	cb.set_health(vic, 1.0)
	var r3: Dictionary = cb.melee(me, vic, 0, 1.0, 0)
	check(bool(r3.victim_dead) and cb.is_dead(vic) and int(main.dialogue._ds().deaths.get("synth_villager", 0)) == 1, "śmierć NPC, licznik zabitych")
	var odc = main.scripts.Ctx.new()
	check(main.scripts._call("synth_villager", "ondeath", [], odc) == 1.0 and main.scripts._call("synth_villager", "ondeath", [], odc) == 0.0,
			"OnDeath: 1 do pierwszego odczytu, potem 0 (hasDied kasowane odczytem)")
	v = _ref(main, "synth_villager")
	check(v.get_meta("mw_dead", false), "ciało leży")
	check(main.activate(v) and main.menu_mode.visible and main.menu_mode.cont_sid == vic.sid, "przeszukanie ciała")
	main.menu_mode.close()
	check(not bool(cb.melee(me, vic, 0, 1.0, 0).get("success", false)), "martwego nie można trafić")
	# łuk i strzały – lot pocisku do NPC
	inv.add("player", {}, "synth_bow", 1)
	inv.add("player", {}, "synth_arrow", 5)
	main.equip_item("synth_bow")
	main.equip_item("synth_arrow")
	var g := _ref(main, "synth_villager_f")
	var gf: Dictionary = cb.fighter_of(g)
	var dmg: Dictionary = cb.projectile_hit(me, gf, cb.weapon(me), cb.equipment(me).get(18, {}), 1.0, 0)
	# łuk 1..10 + strzała 2..6 przy sile 1 = 16 × siła (1,0) × stan łuku → pancerz
	check(bool(dmg.success) and near(cb.max_health(gf) - cb.health(gf), 16.0 * 16.0 / (16.0 + 0.1625)), "łuk + strzała: 16 przed pancerzem (%s)" % [dmg])
	var hg: float = cb.health(gf)
	main.player.global_position = g.global_position + Vector3(2.0, 0.0, 0.0)
	main.player.rotation.y = PI / 2.0
	(main.player.get_node("Camera3D") as Camera3D).rotation.x = -0.25
	await physics_frame
	g.set_physics_process(false)          # NPC bez AI potrafi się zsunąć po zboczu (fizyka aktorów – etap 8)
	main.player.global_position = g.global_position + Vector3(2.0, 0.0, 0.0)
	main._attack_hold = main.ATTACK_WINDUP_SECONDS
	var shot: Dictionary = main.player_attack()
	check(bool(shot.get("shot", false)) and inv.count_of("player", {}, "synth_arrow") == 4, "strzał zużywa strzałę")
	cb.test_roll = 0
	for i in 30:
		await process_frame
		if main.projectiles.is_empty():
			break
	check(main.projectiles.is_empty() and cb.health(gf) < hg, "pocisk trafił NPC (%s → %s)" % [hg, cb.health(gf)])
	cb.test_roll = -1
	# zapis stanu aktorów
	var path := ProjectSettings.globalize_path("user://test_saves/walka.mwsave")
	check(main.save_game(path) == "", "zapis")
	main.state.actors = {}
	main.load_game(path)
	await _frames(3)
	var vd: Dictionary = cb.fighter_of(_ref(main, "synth_villager"))
	check(cb.is_dead(vd) and _ref(main, "synth_villager").get_meta("mw_dead", false), "odczyt: NPC martwy, ciało leży")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
