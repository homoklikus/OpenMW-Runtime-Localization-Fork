extends SceneTree
## Sonda porównawcza MWScript (para do tools/openmw-xvfb/mwscript_compare.py): na RZECZYWISTYCH danych wykonuje
## polecenia konsoli skompilowane kompilatorem konwertera (plik --case=… z polem "compiled") w kontekście konsoli
## i po N klatkach zapisuje migawkę stanu w tym samym układzie co skrypt Lua po stronie OpenMW.
##   godot --headless --path godot -s res://tests/probe_mwscript.gd -- --data=WYNIKI --project=KATALOG
##       --start="Seyda Neen" --case=PLIK.json --out=MIGAWKA.json
## Migawka: tylko liczby i identyfikatory (bez tekstów gry).
const ATTRS := ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
const SKILLS := ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear",
	"athletics", "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration",
	"alchemy", "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman",
	"mercantile", "speechcraft", "handtohand"]
const EFFECTS := ["resistmagicka", "resistfire", "resistfrost", "resistshock", "resistdisease", "resistblight",
	"resistcorprus", "resistpoison", "resistparalysis", "resistnormalweapons", "waterbreathing", "chameleon",
	"waterwalking", "swimspeed", "superjump", "flying", "armorbonus", "castpenalty", "silence", "blindness",
	"paralysis", "invisible", "attackbonus", "defendbonus"]
var main
var vm

func _init() -> void:
	_run.call_deferred()

func _arg(n: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % n):
			return a.split("=", true, 1)[1]
	return def

func _ctx():
	var c = vm.Ctx.new()
	c.scr = "console"
	return c

func _q(id: String, fname: String, args := []) -> float:
	var v = vm._call(id, fname, args, _ctx())
	return float(v) if (v is float or v is int) else 0.0

func _actor(id: String) -> Dictionary:
	var S = vm.stats()
	var f: Dictionary = vm._fighter(vm._target(id, _ctx()))
	if not S.is_actor(f):
		return {}
	var s := {"level": S.get_level(f), "dead": main.combat.is_dead(f) if f.kind != "player" else false}
	s["attributes"] = {}
	for i in ATTRS.size():
		s.attributes[ATTRS[i]] = [S.base_value(f, "attributes", i), S.modified_value(f, "attributes", i)]
	if S.is_npc(f):
		s["skills"] = {}
		for i in SKILLS.size():
			s.skills[SKILLS[i]] = [S.base_value(f, "skills", i), S.modified_value(f, "skills", i)]
		s["werewolf"] = _q(id, "iswerewolf") != 0.0
	s["dynamic"] = {}
	for k in 3:
		s.dynamic[["health", "magicka", "fatigue"][k]] = [S.dyn_base(f, k), S.dyn_current(f, k), S.dyn_modified(f, k)]
	s["effects"] = {}
	for e in EFFECTS:
		s.effects[e] = S.effect_value(f, e)
	s["equipment"] = {}
	var eqd: Dictionary = main.combat.equipment(f)
	for sl in eqd:
		s.equipment[str(sl)] = String(eqd[sl].id)
	s["ai"] = [_q(id, "getfight"), _q(id, "gethello"), _q(id, "getflee"), _q(id, "getalarm")]
	if f.kind == "npc":
		var d = main.dialogue
		var a: Dictionary = d.make_actor(f.node) if f.get("node") != null else {"sid": f.sid, "rec": f.rec, "npc": true}
		s["factions"] = {}
		if not d.faction_of(a).is_empty():
			s.factions[d.faction_of(a)] = d.faction_rank_of(a) + 1     # jak Lua getFactionRank (od 1)
	return s

func _object(id: String) -> Dictionary:
	var ax := func(fn: String, a: String) -> float: return _q(id, fn, [["str", a]])
	return {"pos": [ax.call("getpos", "x"), ax.call("getpos", "y"), ax.call("getpos", "z")],
		"rotz": deg_to_rad(ax.call("getangle", "z")), "scale": _q(id, "getscale"),
		"enabled": _q(id, "getdisabled") == 0.0}

func _snapshot(case: Dictionary) -> Dictionary:
	var out := {"actors": {}, "objects": {}, "items": {}, "globals": {}, "locals": {}, "player": {}}
	for id in case.get("actors", []):
		if vm.resolve(id).is_empty():
			continue
		out.actors[id] = _actor(id)
		out.objects[id] = _object(id)
	for id in case.get("objects", []):
		if not vm.resolve(id).is_empty():
			out.objects[id] = _object(id)
	for id in case.get("items", []):
		out.items[id] = _q("player", "getitemcount", [["str", String(id).to_lower()]])
	out["npc_items"] = {}
	for p in case.get("npc_items", []):
		if not vm.resolve(String(p[0])).is_empty():
			out.npc_items["%s.%s" % [p[0], p[1]]] = _q(String(p[0]), "getitemcount", [["str", String(p[1]).to_lower()]])
	for g in case.get("globals", []):
		out.globals[g] = vm.get_global(g)
	for p in case.get("locals", []):
		var r: Dictionary = vm.resolve(String(p[0]))
		var loc: Dictionary = main.state.scripts.locals.get(String(r.get("sid", "")), {}) if not r.is_empty() else {}
		out.locals["%s.%s" % [p[0], p[1]]] = loc.get(String(p[1]).to_lower())
	out["vars"] = {}
	var gl: Dictionary = main.state.scripts.locals.get("global:mwprobe_run", {})
	for v in case.get("vars", []):
		out.vars[String(v[1])] = gl.get(String(v[1]).to_lower(), 0.0)      # niezainicjowana zmienna = 0
	out.player["crime"] = _q("player", "getpccrimelevel")
	out.player["teleporting"] = bool(main.state.player.get("teleport_enabled", true))
	out.player["cell"] = vm.game.player_cell_name()
	out.player["water"] = _q("player", "getwaterlevel")
	return out

func _run() -> void:
	var case = JSON.parse_string(FileAccess.get_file_as_string(_arg("case")))
	if not case is Dictionary:
		printerr("brak przypadku --case")
		quit(2)
		return
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 2:
		await process_frame
	vm = main.scripts
	# skrypt globalny sondy (jak mwprobe.esp po stronie OpenMW): polecenia w klatce „delay” od startu skryptu
	vm._scripts["mwprobe_run"] = case.get("script", {})
	vm.start("mwprobe_run")
	for i in int(case.get("delay", 30)) + int(case.get("frames", 10)):
		await process_frame
	var snap := _snapshot(case)
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap, " ", true))
	f.close()
	print("RESULT ", JSON.stringify({"actors": snap.actors.size(), "unsupported": vm.unsupported, "errors": vm.report().errors.keys().slice(0, 5)}))
	quit(0)
