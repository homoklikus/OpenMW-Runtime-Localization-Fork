extends SceneTree
## Porównanie zachowań AI z OpenMW (etap 8, MCP-openMW aicmp.py): ten sam scenariusz co lua/scripts/rlf_ai –
## po ustabilizowaniu co `step` s pozycje aktorów i aktywny pakiet AI przez `duration` s, potem napaść gracza na
## wskazanego NPC przy strażniku. Wynik (tylko id i liczby): --out=plik.json {"results": [{kind, id, data}]}.
## godot --headless --path godot -s res://tools/ai_compare.gd -- --data=DANE --pos=x,y,z --request=ai_request.json
##     --out=wynik.json --scripts=0

var results := []

func _init() -> void:
	_run.call_deferred()

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def

func _seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(s * 1000.0):
		await process_frame

func _v(p: Vector3) -> Array:
	return [roundi(p.x), roundi(p.y), roundi(p.z)]

func _out(kind: String, id: String, data: Dictionary) -> void:
	results.append({"kind": kind, "id": id, "data": data})

func _pkg(ai, n) -> Dictionary:
	var p: Dictionary = ai.current_package(n)
	if p.is_empty():
		return {"type": "none"}
	var t := {"type": String(p.get("type", "none"))}
	if p.has("distance"):
		t["distance"] = float(p.distance)
	if p.has("repeat"):
		t["isRepeat"] = bool(p.repeat)
	return t

func _nearest(ai, base: String, from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in ai.actor_nodes():
		if String(n.get_meta("mw_base", "")).to_lower() == base.to_lower():
			var d: float = ai.mw_pos(n).distance_to(from)
			if d < bd:
				best = n
				bd = d
	return best

func _run() -> void:
	var req := {}
	var rf := _arg("request")
	if not rf.is_empty():
		req = JSON.parse_string(FileAccess.get_file_as_string(rf))
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ai = main.ai
	var cr = main.crime
	var st: Dictionary = main.player_stats()
	st.health_base = 2000.0
	st.health = 2000.0
	var initial := {}                     # pozycje w pierwszych klatkach (przed ruchem AI) – do dopasowania aktorów
	for n in ai.actor_nodes():
		initial[String(n.get_meta("mw_sid", ""))] = _v(ai.mw_pos(n))
	var grids := []
	for key in main.loaded:
		var k := String(key)
		if k.begins_with("ext:"):
			var xy := k.substr(4).split(",")
			grids.append([int(xy[0]), int(xy[1])])
	_out("meta", "cells", {"grids": grids, "interior": main.interior})
	await _seconds(float(req.get("settle", 3)))
	var step := float(req.get("step", 1))
	var n_samples := int(float(req.get("duration", 30)) / step) + 1
	var acc := {}
	for i in n_samples:
		for n in ai.actor_nodes():
			var sid := String(n.get_meta("mw_sid", ""))
			if not acc.has(sid):
				acc[sid] = {"recordId": String(n.get_meta("mw_base", "")).to_lower(), "start": initial.get(sid, _v(ai.mw_pos(n))),
					"samples": [], "packages": [], "package": _pkg(ai, n)}
			acc[sid].samples.append(_v(ai.mw_pos(n)))
			acc[sid].packages.append(String(_pkg(ai, n).type))
		await _seconds(step)
	for sid in acc:
		_out("actor", sid, acc[sid])
	var c: Dictionary = req.get("crime", {})
	if not c.is_empty():
		var pp: Vector3 = ai.mw_pos(main.player)
		var v := _nearest(ai, String(c.victim), pp)
		var g := _nearest(ai, String(c.guard), pp)
		if v == null or g == null:
			_out("crime", "assault", {"error": "victim or guard missing", "victim": v != null, "guard": g != null})
		else:
			var fwd := Vector3(-sin(v.rotation.y), 0, cos(v.rotation.y))        # MW: przód aktora
			var at: Vector3 = ai.mw_pos(v) + Vector3(fwd.x, fwd.z, 0).normalized() * float(c.get("distance", 100))
			main.player.global_position = MWCoords.mw_to_godot(at + Vector3(0, 0, 20))
			var gd: Vector3 = (ai.mw_pos(g) - at)
			gd.z = 0
			g.global_position = MWCoords.mw_to_godot(at + gd.normalized() * float(c.get("guard_distance", 400)) + Vector3(0, 0, 20))
			await _seconds(1.0)
			var b0: int = cr.bounty()
			cr.on_assault(v)
			var seen: bool = cr.bounty() > b0 or bool(main.combat._actor_state(main.combat.fighter_of(g)).get("alarmed", false))
			var bounty: int = cr.bounty() - b0
			var gpur := false
			var vcom := false
			var gtypes := []
			for k in 12:                          # 3 s obserwacji co 0,25 s (jak w skrypcie OpenMW)
				await _seconds(0.25)
				var gt := String(_pkg(ai, g).type)
				gtypes.append(gt)
				gpur = gpur or gt == "pursue"
				vcom = vcom or String(_pkg(ai, v).type) == "combat"
			_out("crime", "assault", {"victim": String(v.get_meta("mw_base", "")).to_lower(), "guard": String(g.get_meta("mw_base", "")).to_lower(),
				"seen": seen, "bounty": bounty, "guard_pursue": gpur, "victim_combat": vcom, "guard_packages": gtypes})
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results}, " "))
	f.close()
	print("AI_COMPARE ", results.size())
	quit(0)
