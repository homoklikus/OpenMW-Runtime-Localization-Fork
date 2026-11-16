extends SceneTree
## Porównanie wzorów RPG z OpenMW (etap 7): te same wejścia co scenariusz Lua MCP-openMW
## (tools/MCP-openMW/lua/scripts/rlf_mech/player.lua) – wynik w tym samym formacie ("results": [{kind, id, data}]).
## godot --headless --path godot -s res://tools/mech_compare.gd -- --data=DANE --request=mech_request.json
##     --engine=mech_engine.json --out=wynik.json --scripts=0
## Z wyniku silnika brane są tylko dane postaci (klasa, rasa, znak, czary, zdrowie bazowe) i zmierzony czas
## działania mikstur – reszta liczona tutaj.

var results := []

func _init() -> void:
	_run.call_deferred()

func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return ""

func _out(kind: String, id, data: Dictionary) -> void:
	results.append({"kind": kind, "id": id, "data": data})

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var req: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_arg("request")))
	var eng = JSON.parse_string(FileAccess.get_file_as_string(_arg("engine")))
	var eres: Array = eng.get("results", []) if eng is Dictionary else eng
	var by := {}
	for e in eres:
		by["%s|%s" % [e.kind, str(e.id)]] = e.data
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var ch = main.character
	var cb = main.combat
	var mg = main.magic
	var inv = main.interaction.inventory
	var es: Dictionary = by.get("stats|player", {})
	var st: Dictionary = ch.build({"name": "Test", "race": String(es.get("race", "")).to_lower(),
		"class": String(es.get("class", "")).to_lower(), "birthsign": String(es.get("birthsign", "")).to_lower(),
		"female": bool(es.get("female", false))})
	main.state.player["character"] = st
	var inp: Dictionary = req.input
	var base_attr := []
	for v in inp.attributes:
		base_attr.append(float(v))
	var base_sk := []
	for v in inp.skills:
		base_sk.append(float(v))
	st.attributes = base_attr.duplicate()
	st.skills = base_sk.duplicate()
	st.level = int(inp.level)
	st.spells = (es.get("spells", []) as Array).map(func(x): return String(x).to_lower())
	var edyn: Dictionary = es.get("dynamic", {})
	if edyn.has("health"):
		st.health_base = float(edyn.health[0])
	var me: Dictionary = cb.player_fighter()
	var reset := func():
		var d0: Dictionary = ch.derived(st)
		st.health = d0.health.modified
		st.magicka = d0.magicka.modified
		st.fatigue = d0.fatigue.modified
	reset.call()
	_out("stats", "player", _snapshot(main, st, {"requirement": range(27).map(func(i): return ch.skill_requirement(st, i))}))
	# postęp za użycie
	var i := 0
	for u in req.skill_uses:
		i += 1
		var si := int(u.index) - 1
		ch._ensure_progress(st)
		st.skill_progress[si] = 0.0
		ch.use_skill(st, si, int(u.use), float(u.scale))
		_out("skill_use", i, {"skill": u.skill, "use": u.use, "scale": u.scale, "progress": float(st.skill_progress[si]),
			"base": float(st.skills[si])})
		st.skills = base_sk.duplicate()
		st.skill_progress[si] = 0.0
	# awans
	ch._ensure_progress(st)
	st.level_progress = 0
	st.skill_increases = [0, 0, 0, 0, 0, 0, 0, 0]
	st.spec_increases = [0, 0, 0]
	var names: Array = req.skills
	for k in req.levelups:
		ch.skill_level_up(st, names.find(String(k)), "usage")
	var after := []
	for j in 27:
		after.append([float(st.skills[j]), 0.0, 0.0])
	_out("levelup", "sequence", {"skills": req.levelups, "progress": int(st.level_progress), "attribute": st.skill_increases.duplicate(),
		"specialization": st.spec_increases.duplicate(), "after": after})
	st.skills = base_sk.duplicate()
	# pancerz
	for c in req.create:
		inv.add("player", {}, String(c), 1)
	var n := 0
	for s in req.armor_sets:
		n += 1
		st.equipment = {}
		for it in s.items:
			main.equip_item(String(it.id))
		var items := []
		var eq: Dictionary = cb.equipment(me)
		for it in s.items:
			var v = null
			for slot in eq:
				if String(eq[slot].id) == String(it.id):
					v = cb.effective_armor(eq[slot], me)
			items.append([it.id, v])
		var adj := []
		for dmg in req.damages:
			adj.append(cb.adjust_for_armor(float(dmg), me))
		_out("armor", n, {"items": items, "rating": cb.armor_rating(me), "adjusted": adj, "damages": req.damages})
		st.equipment = {}
	# ładunek
	for id in req.enchanted:
		var en: Dictionary = mg.item_enchantment(inv.item(String(id)))
		_out("charge", id, {"charge": mg.enchantment_charge(en) if not en.is_empty() else null})
	# mikstury: wartości początkowe i czas – jak zmierzone w silniku
	for p in req.potions:
		var pid := String(p.id)
		reset.call()
		var before: Dictionary = by.get("potion_before|" + pid, {}).get("dynamic", {})
		if before.has("health"):
			st.health = float(before.health[1])
			st.magicka = float(before.magicka[1])
			st.fatigue = float(before.fatigue[1])
		var prec: Dictionary = mg.records.record("potion", pid)
		mg.inflict(me, {}, {"id": pid, "name": String(prec.get("name", pid)), "kind": "potion"}, prec.get("effects", []))
		var t_during := float(by.get("potion_during|" + pid, {}).get("elapsed", 0.05))
		var t_after := float(by.get("potion_after|" + pid, {}).get("elapsed", float(p.duration) + 1.0))
		var t := 0.0
		var dt := 1.0 / 60.0
		while t + dt <= t_during:
			mg.tick(me, dt)
			ch.restore_fatigue(st, dt)
			t += dt
		_out("potion_during", pid, _snapshot(main, st, {"elapsed": t}))
		while t + dt <= t_after:
			mg.tick(me, dt)
			ch.restore_fatigue(st, dt)
			t += dt
		_out("potion_after", pid, _snapshot(main, st, {"elapsed": t}))
		st.active_spells = []
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results}, " "))
	f.close()
	print("MECH_DONE ", results.size())
	quit(0)

func _snapshot(main, st: Dictionary, extra: Dictionary) -> Dictionary:
	var d: Dictionary = main.character.derived(st)
	var at := []
	for i in 8:
		at.append([float(st.attributes[i]), float(d.attributes[i])])
	var sk := []
	var pr: Array = st.get("skill_progress", [])
	for i in 27:
		sk.append([float(st.skills[i]), float(d.skills[i]), float(pr[i]) if i < pr.size() else 0.0])
	var out := {"attributes": at, "skills": sk, "dynamic": {
		"health": [float(d.health.base), float(st.health), float(d.health.modified)],
		"magicka": [float(d.magicka.base), float(st.magicka), float(d.magicka.modified)],
		"fatigue": [float(d.fatigue.base), float(st.fatigue), float(d.fatigue.modified)]}}
	out.merge(extra)
	return out
