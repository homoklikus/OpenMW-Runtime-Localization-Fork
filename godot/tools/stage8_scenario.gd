extends SceneTree
## Odbiór etapu 8 na danych z gry: siatki ścieżek wczytanych komórek, ruch NPC wg pakietów (wander/travel…),
## powitanie, napaść przy strażniku (grzywna, pościg, rozmowa), kradzież cudzego przedmiotu, walka (Fight 100),
## stan aktorów po zmianie komórki oraz po zapisie i odczycie. Raport tylko liczbowy i z id (bez tekstów gry).
## godot --headless --path godot -s res://tools/stage8_scenario.gd -- --data=DANE [--cell=WNĘTRZE | --pos=x,y,z]
##     [--other=INNA_KOMÓRKA] --out=wynik.json --scripts=0 [--seconds=40]

var report := {"steps": []}

func _init() -> void:
	_run.call_deferred()

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def

func _step(name: String, ok: bool, data := {}) -> void:
	report.steps.append({"step": name, "ok": ok, "data": data})
	print("STEP %s %s %s" % ["OK " if ok else "BŁĄD", name, JSON.stringify(data)])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(s * 1000.0):
		await process_frame

func _until(cond: Callable, seconds: float) -> float:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(seconds * 1000.0):
		if cond.call():
			return (Time.get_ticks_msec() - t) / 1000.0
		await process_frame
	return -1.0

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 1.0), snappedf(p.y, 1.0), snappedf(p.z, 1.0)]

func _base(n: Node) -> String:
	return String(n.get_meta("mw_base", "")).to_lower()

func _is_npc(n: Node) -> bool:
	return String(n.get_meta("mw_actor", "")) == "npc"

func _class(main, n: Node) -> String:
	return String(main.builder.actors.record("npc", _base(n)).get("class", "")).to_lower()

func _face(n: Node3D, target: Node3D) -> void:
	var d := target.global_position - n.global_position
	n.rotation.y = atan2(-d.x, -d.z)

func _before(main, n: Node3D, units: float) -> void:
	var dir := -Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
	main.player.global_position = n.global_position + dir * (units / MWCoords.UNITS_PER_METER) + Vector3(0, 0.3, 0)

func _snapshot(main) -> Dictionary:
	var out := {}
	for n in main.ai.actor_nodes():
		var sid := String(n.get_meta("mw_sid", ""))
		var pk: Array = main.ai.ai_state(n).packages
		out[sid] = {"base": _base(n), "pos": main.ai.mw_pos(n), "packages": pk.map(func(p): return String(p.get("type", "")))}
	return out

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(15)
	var ai = main.ai
	var cr = main.crime
	var cb = main.combat
	var dl = main.dialogue
	var st: Dictionary = main.player_stats()
	st.health_base = 2000.0
	st.health = 2000.0
	var t0 := Time.get_ticks_msec()
	var home: Vector3 = ai.mw_pos(main.player)
	var home_cell: String = main.interior
	# siatki ścieżek
	var grids := {}
	for key in main.loaded:
		var g = ai.graph(String(key))
		var ne := 0
		for e in g.edges:
			ne += (e as Array).size()
		grids[String(key)] = {"points": g.points.size(), "edges": ne / 2}
	var with_grid := grids.values().filter(func(x): return int(x.points) > 0).size()
	_step("siatki ścieżek", with_grid > 0, {"cells": grids.size(), "with_pathgrid": with_grid, "grids": grids})
	# ruch wg pakietów
	var actors: Array = ai.actor_nodes()
	var start := {}
	for n in actors:
		start[String(n.get_meta("mw_sid", ""))] = ai.mw_pos(n)
	var secs := float(_arg("seconds", "40"))
	await _seconds(secs)
	var moved := []
	var by_type := {}
	var fell := 0
	var outside := 0
	for n in ai.actor_nodes():
		var sid := String(n.get_meta("mw_sid", ""))
		if not start.has(sid):
			continue
		var p: Vector3 = ai.mw_pos(n)
		var d: float = Vector2(p.x, p.y).distance_to(Vector2(start[sid].x, start[sid].y))
		var pk: Dictionary = ai.current_package(n)
		var t := String(pk.get("type", "")) if not pk.is_empty() else "brak"
		var e: Dictionary = by_type.get(t, {"actors": 0, "moved": 0})
		e.actors += 1
		if d > 32.0:
			e.moved += 1
			moved.append(sid)
		by_type[t] = e
		if start[sid].z - p.z > 300.0:
			fell += 1
		if t == "wander":
			var anchor = ai.ai_state(n).get("start")
			var dist := float(pk.get("distance", 0))
			if anchor is Array and dist > 0.0:
				var a3 := Vector2(float(anchor[0]), float(anchor[1]))
				if Vector2(p.x, p.y).distance_to(a3) > dist + 400.0:
					outside += 1
	var wander: Dictionary = by_type.get("wander", {"actors": 0, "moved": 0})
	_step("ruch NPC wg pakietów (%.0f s)" % secs, fell == 0 and outside == 0 and (int(wander.actors) == 0 or int(wander.moved) > 0),
		{"actors": actors.size(), "by_package": by_type, "fell": fell, "wander_outside_range": outside})
	# powitanie
	var greeter: Node3D = null
	for n in ai.actor_nodes():
		if _is_npc(n) and int(dl.ai_setting(dl.make_actor(n), "hello")) > 0 and not ai.in_combat(n) and _class(main, n) != "guard":
			greeter = n
			break
	if greeter != null:
		_before(main, greeter, 120.0)
		var gt := await _until(func(): return String(ai._rt(greeter).get("greet", "none")) != "none", 6.0)
		_step("powitanie (Hello)", gt >= 0.0, {"npc": _base(greeter), "hello": dl.ai_setting(dl.make_actor(greeter), "hello"), "seconds": gt})
	else:
		_step("powitanie (Hello)", false, {"reason": "brak NPC z Hello > 0"})
	# kradzież: cudzy przedmiot (właściciel w komórce, widzi gracza)
	var theft := {}
	for key in main.loaded:
		for r in main.loaded[key].get_node("Refs").get_children():
			if r.has_meta("mw_actor"):
				continue
			var c: Dictionary = main.interaction.snapshot(r)
			if String(c.kind) != "item" or String(c.extra.get("owner", "")).is_empty():
				continue
			var o: Dictionary = cr.ownership(c.extra)
			if bool(o.owned) and o.victim != null:
				theft = {"node": r, "snap": c, "owner": o.victim}
				break
		if not theft.is_empty():
			break
	if not theft.is_empty():
		var owner: Node3D = theft.owner
		_before(main, owner, 150.0)
		_face(owner, main.player)
		await _frames(3)
		cr.test_roll = 99
		var b0: int = cr.bounty()
		main.interaction.take_ref(theft.snap)
		cr.test_roll = -1
		var alarm := int(dl.ai_setting(dl.make_actor(owner), "alarm"))
		_step("kradzież na oczach właściciela", ((cr.bounty() > b0) == (alarm >= 100)) and (st.get("stolen", {}) as Dictionary).has(String(theft.snap.base).to_lower()),
			{"item": theft.snap.base, "owner": _base(owner), "owner_alarm": alarm, "bounty": cr.bounty() - b0})
		cr.pay_fine()
		await _frames(5)
	else:
		_step("kradzież na oczach właściciela", true, {"skipped": "brak cudzego przedmiotu z właścicielem w komórce"})
	# napaść przy strażniku: grzywna, pościg, rozmowa strażnika
	var guard: Node3D = null
	var victim: Node3D = null
	for n in ai.actor_nodes():
		if _is_npc(n) and _class(main, n) == "guard" and guard == null:
			guard = n
	if guard != null:
		for n in ai.actor_nodes():
			if _is_npc(n) and n != guard and _class(main, n) != "guard":
				if victim == null or ai.mw_pos(n).distance_to(ai.mw_pos(guard)) < ai.mw_pos(victim).distance_to(ai.mw_pos(guard)):
					victim = n
	if guard != null and victim != null:
		_before(main, victim, 100.0)
		guard.global_position = main.player.global_position + (guard.global_position - main.player.global_position).normalized() * 6.0
		_face(guard, main.player)
		await _frames(5)
		cr.test_roll = 99
		cr.on_assault(victim)
		cr.test_roll = -1
		var pursue := false
		for p in ai.ai_state(guard).packages:
			pursue = pursue or String(p.get("type", "")) == "pursue"
		var b: int = cr.bounty()
		var talk := await _until(func(): return main.dialogue_window != null and main.dialogue_window.visible, 25.0)
		var who := _base(dl.actor.get("node")) if talk >= 0.0 and dl.actor.get("node") is Node else ""
		_step("napaść przy strażniku", b == int(cr._gmst("iCrimeAttack", 40)) and pursue and talk >= 0.0,
			{"guard": _base(guard), "victim": _base(victim), "bounty": b, "pursue": pursue, "dialogue_after_s": talk, "dialogue_with": who,
			"victim_in_combat": ai.in_combat(victim)})
		if main.dialogue_window != null and main.dialogue_window.visible:
			main.dialogue_window.close(true)
		cr.pay_fine(false)
		ai.stop_combat(victim)
		dl.set_ai_setting(dl.make_actor(victim), "fight", 0)
		await _frames(10)
	else:
		_step("napaść przy strażniku", true, {"skipped": "brak strażnika w komórce"})
	# walka: NPC z Fight 100 atakuje gracza
	var fighter: Node3D = null
	for n in ai.actor_nodes():
		if _is_npc(n) and n != guard and not cb.is_dead(cb.fighter_of(n)):
			fighter = n
			break
	if fighter != null:
		_before(main, fighter, 100.0)
		await _frames(3)
		dl.set_ai_setting(dl.make_actor(fighter), "fight", 100)
		ai.test_roll = 99
		cb.test_roll = 0                   # trafienie pewne – sprawdzamy, że NPC podchodzi i uderza
		var eng := await _until(func(): return ai.in_combat(fighter), 5.0)
		var h0: int = cb.hits
		var hit := await _until(func(): return cb.hits > h0, 20.0)
		ai.test_roll = -1
		cb.test_roll = -1
		_step("walka (Fight 100)", eng >= 0.0 and hit >= 0.0, {"npc": _base(fighter), "engage_s": eng, "first_hit_s": hit})
		ai.stop_combat(fighter)
		dl.set_ai_setting(dl.make_actor(fighter), "fight", 0)
		await _frames(5)
	# zmiana komórki i powrót
	var before := _snapshot(main)
	var other := _arg("other")
	if not other.is_empty():
		main.travel_to_cell(other, Vector3.ZERO, 0.0)
		await _frames(20)
		main.travel_to_cell(home_cell, home, 0.0)
		await _frames(20)
		var after := _snapshot(main)
		var diff := 0
		var pk_diff := 0
		for sid in before:
			if not after.has(sid):
				continue
			if Vector2(after[sid].pos.x, after[sid].pos.y).distance_to(Vector2(before[sid].pos.x, before[sid].pos.y)) > 60.0:
				diff += 1
			if after[sid].packages != before[sid].packages:
				pk_diff += 1
		_step("zmiana komórki i powrót", diff == 0 and pk_diff == 0, {"other": other, "actors": before.size(), "moved_more_than_60": diff, "packages_changed": pk_diff})
	# zapis i odczyt
	before = _snapshot(main)
	var path := ProjectSettings.globalize_path("user://stage8/odbior.mwsave")
	var e: String = main.save_game(path)
	var lw: Array = main.load_game(path)
	await _frames(10)
	var after2 := _snapshot(main)
	var diff2 := 0
	var pk2 := 0
	for sid in before:
		if not after2.has(sid):
			diff2 += 1
			continue
		if Vector2(after2[sid].pos.x, after2[sid].pos.y).distance_to(Vector2(before[sid].pos.x, before[sid].pos.y)) > 60.0:
			diff2 += 1
		if after2[sid].packages != before[sid].packages:
			pk2 += 1
	_step("zapis i odczyt", e == "" and diff2 == 0 and pk2 == 0, {"warnings": lw.size(), "actors": before.size(), "position_diff": diff2, "packages_changed": pk2})
	report["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	report["moved"] = moved.size()
	var f2 := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f2.store_string(JSON.stringify(report, " "))
	f2.close()
	quit(0)
