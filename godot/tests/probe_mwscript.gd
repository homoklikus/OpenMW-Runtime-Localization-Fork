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
	# pełna mapa efektów (jak Lua pairs(activeEffects)): klucze bez argumentu tylko dla efektów bez argumentu
	s["fx"] = {}
	var fx: Dictionary = main.magic.effects(f)
	for k in fx:
		var ks := String(k)
		if ks.begins_with("_"):
			continue
		if not ks.contains(":") and (int(ks) in main.character.ARG_ATTRIBUTE_EFFECTS or int(ks) in main.character.ARG_SKILL_EFFECTS):
			continue
		var v := floori(float(fx[k]))
		if v != 0:
			s.fx[ks] = v
	s["equipment"] = {}
	var eqd: Dictionary = main.combat.equipment(f)
	s["condition"] = {}
	for sl in eqd:
		s.equipment[str(sl)] = String(eqd[sl].id)
		if String(eqd[sl].kind) in ["weapon", "armor"] and float(eqd[sl].rec.get("health", 0)) > 0.0:
			s.condition[str(sl)] = int(floor(main.combat.item_health(eqd[sl])))
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
	var o := {"pos": [ax.call("getpos", "x"), ax.call("getpos", "y"), ax.call("getpos", "z")],
		"rotz": deg_to_rad(ax.call("getangle", "z")), "scale": _q(id, "getscale"),
		"enabled": _q(id, "getdisabled") == 0.0}
	var n = vm.resolve(id).get("node")
	if n != null and is_instance_valid(n) and String(main.interaction.kind_of(n)) in ["door", "container"]:
		o["lock"] = main.interaction.lock_level(n)          # Lockable: poziom zamka, gdy zamknięty, inaczej 0
	return o

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
	out["track"] = _track
	return out

var _track := {}
var _spells_done := {}
var _case: Dictionary = {}

## Czar nakładany bezpośrednio (para do Lua ActiveSpells:add): wszystkie efekty rekordu na cel.
func _apply_spell(sp: Array) -> void:
	var t: Dictionary = vm._fighter(vm._target(String(sp[1]), _ctx()))
	var rec: Dictionary = main.builder.actors.record("spell", String(sp[2]).to_lower())
	if t.is_empty() or rec.is_empty():
		printerr("PROBE: brak celu/czaru ", sp)
		return
	var c: Dictionary = {}
	if sp.size() > 3 and String(sp[3]) != "":
		c = vm._fighter(vm._target(String(sp[3]), _ctx()))
	main.magic.inflict(t, c, {"id": String(sp[2]).to_lower(), "name": String(rec.get("name", "")), "kind": "spell",
		"stackable": bool(_case.get("stackable", false))}, rec.get("effects", []), rec)

## Sterowanie graczem jak skrypt PLAYER sondy OpenMW: odcinki [t0, t1, {forward, back, left, right, run, jump,
## sneak, yaw, pitch}] (sekundy od poleceń) → akcje wejścia kontrolera gracza.
var _jumped := {}
var _pressed := {}

## Wycelowanie kamery gracza w punkt MW (x, y, z) – jak MWCAM/LOOK w sondzie OpenMW.
func _look_at(p: Array) -> void:
	if p.size() < 3 or main.player == null:
		return
	var cam := main.player.get_node_or_null("PlayerController/Camera3D") as Camera3D
	if cam == null:
		cam = main.player.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		return
	var d: Vector3 = MWCoords.mw_to_godot(Vector3(float(p[0]), float(p[1]), float(p[2]))) - cam.global_position
	main.player.rotation.y = atan2(-d.x, -d.z)
	cam.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())

## Rzucenie czaru gracza [[t, id]] – jak w sondzie OpenMW: wybór i gotowa magia w t, rzut (lewy przycisk) w t+1 s.
var _cast_done := {}

func _apply_cast(casts: Array, t: float) -> void:
	for i in casts.size():
		var c: Array = casts[i]
		if t >= float(c[0]) and not _cast_done.has(i):
			_cast_done[i] = 1
			main.select_magic("spell", String(c[1]))
			main.magic_ready = true
			main.weapon_drawn = false
		if t >= float(c[0]) + 1.0 and int(_cast_done.get(i, 0)) == 1:
			_cast_done[i] = 2
			main.player_cast()

## Odpoczynek [[t, godziny]] – w OpenMW klawisze okna odpoczynku (T, Enter) przez XTest; tu okno i rest(godziny).
var _rest_done := {}

func _apply_rest(rests: Array, t: float) -> void:
	if bool(_case.get("debug", false)) and not rests.is_empty() and t >= float(rests[0][0]) and t < float(rests[0][0]) + 1.0 \
			and Engine.get_process_frames() % 6 == 0:
		print("MWDBG t=%.3f rest=%s hour=%.2f vis=%s" % [t, str(main.rest_window._rest), float(main.envr.game_hour), main.rest_window.visible])
	for i in rests.size():
		var r: Array = rests[i]
		if t >= float(r[0]) and not _rest_done.has(i) and main.rest_window != null:
			_rest_done[i] = true
			var ok: bool = main.rest_window.open()
			# godziny < 0: „Do wyleczenia” (domyślny przycisk okna OpenMW pod Enterem, gdy można spać)
			var h: int = int(r[1]) if int(r[1]) > 0 else main.rest_window.hours_until_healed()
			if bool(_case.get("debug", false)):
				print("MWDBG rest open=%s sleep=%s hours=%d" % [ok, main.rest_window.sleeping, h])
			if ok:
				main.rest_window.rest(h)

## Klawisze [[t, keysym X]] – jak naciśnięcia XTest w OpenMW: akcja wejścia przez 3 klatki.
const KEY_ACTIONS := {"space": "activate"}
var _keyed := {}
var _key_release := {}

func _apply_keys(keys: Array, t: float) -> void:
	for a in _key_release.keys():
		_key_release[a] = int(_key_release[a]) - 1
		if int(_key_release[a]) <= 0:
			_key_event(a, false)
			_key_release.erase(a)
	for i in keys.size():
		var k: Array = keys[i]
		var a := String(KEY_ACTIONS.get(String(k[1]).to_lower(), ""))
		if t >= float(k[0]) and not _keyed.has(i) and InputMap.has_action(a):
			_keyed[i] = true
			_key_event(a, true)
			_key_release[a] = 3

## Zdarzenie akcji (jak z klawiatury – _unhandled_input, nie tylko stan Input).
func _key_event(a: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _apply_controls(ctrl: Array, t: float) -> void:
	if ctrl.is_empty():
		return
	var want := {"move_forward": false, "move_back": false, "move_left": false, "move_right": false, "run": false,
		"sneak": false, "jump": false}
	var dt: float = main.get_process_delta_time()
	for i in ctrl.size():
		var c: Array = ctrl[i]
		if t < float(c[0]) or t >= float(c[1]):
			continue
		var o: Dictionary = c[2]
		if float(o.get("forward", 0)) > 0: want.move_forward = true
		if float(o.get("back", 0)) > 0: want.move_back = true
		if float(o.get("left", 0)) > 0: want.move_left = true
		if float(o.get("right", 0)) > 0: want.move_right = true
		if bool(o.get("run", false)): want.run = true
		if bool(o.get("sneak", false)): want.sneak = true
		if bool(o.get("jump", false)) and not _jumped.has(i):
			_jumped[i] = true
			want.jump = true
		if o.has("yaw") and main.player != null:
			main.player.rotate_y(-float(o.yaw) * dt)
		if o.has("pitch") and main.player != null:
			var cam := main.player.get_node_or_null("Camera3D") as Camera3D
			if cam != null:
				cam.rotation.x = clampf(cam.rotation.x - float(o.pitch) * dt, -1.5, 1.5)
	for a in want:
		if not InputMap.has_action(a):
			continue
		if bool(want[a]) and not _pressed.get(a, false):
			Input.action_press(a)
			_pressed[a] = true
		elif not bool(want[a]) and _pressed.get(a, false):
			Input.action_release(a)
			_pressed[a] = false

func _sample(case: Dictionary, t: float) -> void:
	for id in case.get("track", []):
		if vm.resolve(String(id)).is_empty():
			continue
		var o := _object(String(id))
		if not _track.has(id):
			_track[id] = []
		_track[id].append([t, o.pos[0], o.pos[1], o.pos[2]])
	if (bool(case.get("debug", false)) or bool(case.get("framelog", false))) and main.player != null:
		var st: Dictionary = main.player_stats()
		var mv: Dictionary = main.character.movement(st, main.player_weight(), main.player.want_run)
		print("MWDBG t=%.2f jump=%.1f walk=%.1f run=%.1f acro=%s fat=%s vel=%s" % [t, mv.jump, mv.walk, mv.run,
			str(main.character.derived(st).skills[main.character.SK_ACROBATICS]), str(st.get("fatigue")), str(main.player.velocity)])

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
	_case = case
	var delay := int(case.get("delay", 30))
	var secs := float(case.get("seconds", 0.0))
	var samples: Array = case.get("samples", [])
	var done := {}
	var t_after := -1.0
	var frame := 0
	while true:
		frame += 1
		var spl: Array = case.get("spells", [])
		for si in spl.size():
			var sp: Array = spl[si]
			var due: bool = (t_after >= 0.0 and t_after >= float(sp[4]) and not _spells_done.has(si)) if sp.size() > 4 \
				else frame == delay + int(sp[0])
			if due:
				_spells_done[si] = true
				_apply_spell(sp)
		_apply_controls(case.get("controls", []), t_after)
		_apply_keys(case.get("keys", []), t_after)
		_look_at(case.get("look_at", []))
		_apply_cast(case.get("cast", []), t_after)
		_apply_rest(case.get("rest", []), t_after)
		if bool(case.get("disable_creatures", false)) and frame == delay:
			for an in main.ai.actor_nodes():
				if String(an.get_meta("mw_actor", "")) == "creature":
					main.state.set_enabled(String(an.get_meta("mw_sid", "")), false)
		for tp in case.get("teleport", []):
			if frame == delay + int(tp[0]):
				var tn = vm._target(String(tp[1]), _ctx()).get("node")
				if tn != null:
					tn.global_position = MWCoords.mw_to_godot(Vector3(float(tp[2]), float(tp[3]), float(tp[4])))
					tn.velocity = Vector3.ZERO
					tn.set("_fall_start", NAN)
		for rm in case.get("remove", []):
			if frame == delay + int(rm[0]):
				var tf: Dictionary = vm._fighter(vm._target(String(rm[1]), _ctx()))
				if not tf.is_empty():
					for a in main.magic.active(tf):
						if String(a.get("id", "")) == String(rm[2]).to_lower():
							for x in a.effects:
								x.time_left = 0.0
					main.magic.tick(tf, 0.0)
		await process_frame
		if frame == delay:
			t_after = 0.0
		elif t_after >= 0.0:
			t_after += main.get_process_delta_time()
		for i in samples.size():
			if t_after >= float(samples[i]) and not done.has(i):
				done[i] = true
				_sample(case, float(samples[i]))
		if (secs > 0.0 and t_after >= secs) or (secs <= 0.0 and frame >= delay + int(case.get("frames", 10))):
			break
	var snap := _snapshot(case)
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap, " ", true))
	f.close()
	print("RESULT ", JSON.stringify({"actors": snap.actors.size(), "unsupported": vm.unsupported, "errors": vm.report().errors.keys().slice(0, 5)}))
	quit(0)
