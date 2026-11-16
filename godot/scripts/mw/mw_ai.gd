extends RefCounted
## AI aktorów (etap 8) – OpenMW 0.51 apps/openmw/mwmechanics: AiSequence (kolejka pakietów z rekordu AI_W/T/E/F/A
## i ze skryptów, powtarzanie, „done”, GetCurrentAIPackage), AiWander (wybór bezczynności wg szans idle2…idle9 ×
## fIdleChanceMultiplier, dozwolone punkty siatki ścieżek w promieniu od miejsca startu i w tej samej składowej,
## spacer wokół startu bez siatki, czas trwania w godzinach gry), AiTravel (zasięg 7168, tolerancja końca),
## AiEscort (czekanie na podążającego: 450/250 + połowa aktora), AiFollow (dystans podążania, bieg > 450), AiActivate,
## AiPackage::pathTo (ścieżka po siatce PGRD, punkty pośrednie, wykrywanie utknięcia i omijanie – obstacle.cpp),
## powitanie (Actors::updateGreetingState: iGreetDistanceMultiplier × Hello, odwrócenie do gracza na
## iGreetDuration, reset po fGreetDistanceReset), prędkości chodu/biegu NPC i stworzeń (getWalkSpeed/getRunSpeed).
##
## Stan trwały (zapis gry): GameState.actors[sid]["ai"] = {"packages": [{"type", …, "remaining", "repeat"}],
## "done", "last", "start": [x, y, z] MW}; pozycja aktora przesuniętego przez AI – GameState.refs[sid].mw.

const PathgridScript := preload("res://scripts/mw/mw_pathgrid.gd")
const TYPE_ID := {"wander": 0, "travel": 1, "escort": 2, "follow": 3, "activate": 4, "combat": 5, "pursue": 6}
const REACTION := 0.25                  # AiReactionTimer (s)
const DESTINATION_TOLERANCE := 64.0     # AiWander
const MIN_WANDER := 128.0               # minimumWanderDistance
const TRAVEL_FINISH := 2.0
const MAX_TRAVEL := 7168.0
const IDLE_CHECK := 1.5
const STUCK_TIME := 0.5                 # ObstacleCheck: czas do uznania utknięcia
const EVADE_TIME := 0.5
const COUNT_BEFORE_RESET := 10
const UNITS := MWCoords.UNITS_PER_METER

var main
var rng := RandomNumberGenerator.new()
var graphs := {}                        # klucz komórki → MWPathgrid
var rt := {}                            # sid → stan chwilowy (węzeł, ścieżka, liczniki)
var enabled := true

func _init(game_main) -> void:
	main = game_main

func _gmst(id: String, def) -> Variant:
	var g: Dictionary = main.builder.actors.record("gmst", id.to_lower())
	return g.get("value", def) if not g.is_empty() else def

# --- siatki ścieżek ----------------------------------------------------------------------------------------

func cell_key_at(mw: Vector3) -> String:
	if not main.interior.is_empty():
		return "int:" + main.interior.to_lower()
	return main.db.exterior_key(Vector2i(floori(mw.x / 8192.0), floori(mw.y / 8192.0)))

func graph(key: String):
	if not graphs.has(key):
		graphs[key] = PathgridScript.from_cell(main.db.get_cell(key))
	return graphs[key]

# --- aktorzy -----------------------------------------------------------------------------------------------

static func mw_pos(n: Node3D) -> Vector3:
	return MWCoords.godot_to_mw(n.global_position)

func actor_nodes() -> Array:
	var out := []
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if n.has_meta("mw_actor") and not n.get_meta("mw_disabled", false) and n is CharacterBody3D:
				out.append(n)
	return out

func _record(n: Node) -> Dictionary:
	var base := String(n.get_meta("mw_base", "")).to_lower()
	var r: Dictionary = main.builder.actors.record("npc", base)
	return r if not r.is_empty() else main.builder.actors.record("creature", base)

## Stan AI aktora w GameState (tworzony z rekordu przy pierwszym użyciu – AiSequence::fill).
func ai_state(n: Node) -> Dictionary:
	var sid := String(n.get_meta("mw_sid", ""))
	var a: Dictionary = main.combat._actor_state({"sid": sid})
	if not a.get("ai") is Dictionary:
		var pk := []
		for p in (_record(n).get("ai", {}) as Dictionary).get("packages", []):
			pk.append(_package_from_record(p))
		a["ai"] = {"packages": pk, "done": false, "last": -1}
	return a.ai

func _package_from_record(p: Dictionary) -> Dictionary:
	var d: Dictionary = p.duplicate(true)
	match String(p.get("type", "")):
		"wander":
			d["remaining"] = float(p.get("duration", 0))
		"escort", "follow":
			d["remaining"] = float(p.get("duration", 0))
			d["max_dist"] = 450.0
	return d

func current_package(n: Node) -> Dictionary:
	var pk: Array = ai_state(n).packages
	return pk[0] if not pk.is_empty() else {}

## GetCurrentAIPackage (bez walki/pościgu – jak OpenMW dla skryptów): −1 brak.
func current_type(n: Node) -> int:
	var st := ai_state(n)
	for p in st.packages:
		var t := int(TYPE_ID.get(String(p.get("type", "")), -1))
		if t >= 0 and t <= 4:
			return t
	return int(st.get("last", -1))

## AiSequence::stack z poziomu skryptu (AiWander, AiTravel, …): pakiety „właściwe” są zastępowane.
func stack(n: Node, pkg: Dictionary, cancel_other := true) -> void:
	var st := ai_state(n)
	var p := _package_from_record(pkg)
	if cancel_other:
		st.packages = (st.packages as Array).filter(func(x): return int(TYPE_ID.get(String(x.get("type", "")), 9)) > 4)
	var pri := int(p.get("priority", 0))
	var inserted := false
	for i in (st.packages as Array).size():
		if int(st.packages[i].get("priority", 0)) <= pri:
			st.packages.insert(i, p)
			inserted = true
			break
	if not inserted:
		st.packages.append(p)
	st.done = false
	var r := _rt(n)
	r.path = []
	r.wstate = "choose"
	if String(p.get("type", "")) == "wander":
		ai_state(n).erase("start")

func _rt(n: Node) -> Dictionary:
	var sid := String(n.get_meta("mw_sid", ""))
	if not rt.has(sid) or rt[sid].node != n:
		rt[sid] = {"node": n, "path": [], "dest": Vector3.INF, "reaction": rng.randf() * REACTION, "wstate": "choose",
			"idle_t": 0.0, "idle_anim": "", "check_idle": 0.0, "allowed": null, "stuck_t": 0.0, "evade_t": 0.0,
			"stuck_count": 0, "last_pos": mw_pos(n), "moving": false, "greet": "none", "greet_timer": 0,
			"greet_t": 0.0, "follow_moving": false, "travel_t": TRAVEL_FINISH, "anim": "", "run": false}
	return rt[sid]

# --- ruch --------------------------------------------------------------------------------------------------

## Prędkość chodu/biegu (jedn. MW/s): Npc::getWalkSpeed (fMinWalkSpeed…fMaxWalkSpeed wg szybkości),
## bieg × (0,01 × atletyka × fAthleticsRunBonus + fBaseRunMultiplier); stworzenia – fMin/MaxWalkSpeedCreature.
func speeds(n: Node) -> Vector2:
	var f: Dictionary = main.combat.fighter_of(n)
	var at: Array = main.combat.attributes(f)
	var spd := float(at[4]) if at.size() > 4 else 50.0
	var creature: bool = f.get("kind", "") == "creature"
	var mn := float(_gmst("fMinWalkSpeedCreature" if creature else "fMinWalkSpeed", 5.0 if creature else 100.0))
	var mx := float(_gmst("fMaxWalkSpeedCreature" if creature else "fMaxWalkSpeed", 300.0 if creature else 200.0))
	var walk := mn + 0.01 * spd * (mx - mn)
	var run := walk * (0.01 * float(main.combat.skill(f, 8)) * float(_gmst("fAthleticsRunBonus", 1.0)) + float(_gmst("fBaseRunMultiplier", 1.75)))
	return Vector2(walk, run)

func _stop(n: CharacterBody3D) -> void:
	n.move_input = Vector2.ZERO
	n.want_run = false
	_rt(n).moving = false

## Obrót w osi Z (zTurn): kąt MW (0 = +Y, zgodnie z ruchem wskazówek), szybkość ograniczona; → true po obrocie.
func _turn_to(n: Node3D, mw_target: Vector3, dt: float, eps := 0.05) -> bool:
	var here := mw_pos(n)
	var d := Vector2(mw_target.x - here.x, mw_target.y - here.y)
	if d.length() < 1.0:
		return true
	var want := -atan2(d.x, d.y)                       # Godot: obrót wokół +Y, przód = −Z = MW +Y
	var diff := wrapf(want - n.rotation.y, -PI, PI)
	var step := 8.0 * dt                               # ~460°/s
	if absf(diff) <= step:
		n.rotation.y = want
	else:
		n.rotation.y += signf(diff) * step
	return absf(wrapf(want - n.rotation.y, -PI, PI)) < eps

## AiPackage::pathTo: ścieżka po siatce (przebudowa, gdy cel się zmienił), punkty pośrednie, utknięcie
## i omijanie. → true, gdy cel osiągnięty (odległość ≤ tolerance).
func path_to(n: CharacterBody3D, dest: Vector3, dt: float, tolerance := DESTINATION_TOLERANCE, run := false) -> bool:
	var r := _rt(n)
	var here := mw_pos(n)
	if Vector2(dest.x - here.x, dest.y - here.y).length() <= tolerance:
		r.path = []
		_stop(n)
		return true
	if (r.path as Array).is_empty() or (r.dest as Vector3).distance_to(dest) > 32.0:
		r.path = graph(cell_key_at(here)).build_path(here, dest)
		r.dest = dest
	var sp := speeds(n)
	var speed: float = sp.y if run else sp.x
	var tol := maxf(32.0, speed * dt * 1.5)
	while (r.path as Array).size() > 1 and Vector2((r.path[0] as Vector3).x - here.x, (r.path[0] as Vector3).y - here.y).length() <= tol:
		r.path.pop_front()
	var wp: Vector3 = r.path[0] if not (r.path as Array).is_empty() else dest
	_turn_to(n, wp, dt)
	n.walk_speed = sp.x / UNITS
	n.run_speed = sp.y / UNITS
	n.want_run = run
	r.moving = true
	# ObstacleCheck: ruch < 10 % oczekiwanego przez STUCK_TIME → omijanie w bok przez EVADE_TIME
	if float(r.evade_t) > 0.0:
		r.evade_t = float(r.evade_t) - dt
		n.move_input = Vector2(1.0, -0.5)
	else:
		n.move_input = Vector2(0.0, -1.0)
		var moved := Vector2(here.x - (r.last_pos as Vector3).x, here.y - (r.last_pos as Vector3).y).length()
		if moved < speed * dt * 0.1:
			r.stuck_t = float(r.stuck_t) + dt
			if float(r.stuck_t) >= STUCK_TIME:
				r.evade_t = EVADE_TIME
				r.stuck_t = 0.0
				r.stuck_count = int(r.stuck_count) + 1
		else:
			r.stuck_t = 0.0
	r.last_pos = here
	return false

func is_evading(n: Node) -> bool:
	return float(_rt(n).evade_t) > 0.0

# --- pętla -------------------------------------------------------------------------------------------------

## Co klatkę (main._process, poza pauzą): aktorzy we wczytanych komórkach.
func tick(dt: float) -> void:
	if not enabled or main.player == null:
		return
	for n in actor_nodes():
		update_actor(n, dt)

func _alive(n: Node) -> bool:
	var f: Dictionary = main.combat.fighter_of(n)
	return not f.is_empty() and not main.combat.is_dead(f)

func update_actor(n: CharacterBody3D, dt: float) -> void:
	if not _alive(n):
		_stop(n)
		return
	var r := _rt(n)
	var st := ai_state(n)
	if main.magic != null and main.magic.magnitude_of(main.combat.fighter_of(n), main.magic.FX_PARALYZE) > 0.0:
		_stop(n)
		return
	r.reaction = float(r.reaction) - dt
	var react: bool = float(r.reaction) <= 0.0
	if react:
		r.reaction = REACTION
	var pk: Array = st.packages
	var p: Dictionary = pk[0] if not pk.is_empty() else {}
	_update_greeting(n, r, p, dt, react)
	if p.is_empty():
		st.last = -1
		_stop(n)
		_animate(n, r)
		return
	var t := String(p.get("type", ""))
	if TYPE_ID.get(t, 9) <= 4:
		st.last = TYPE_ID[t]
	var finished := false
	if r.greet == "progress" and t in ["wander", "travel"]:
		_stop(n)
	else:
		match t:
			"wander": finished = _wander(n, r, st, p, dt, react)
			"travel": finished = _travel(n, r, p, dt)
			"escort": finished = _escort(n, r, p, dt)
			"follow": finished = _follow(n, r, p, dt, react)
			"activate": finished = _activate(n, r, p, dt)
			_:
				if main.has_method("ai_package") :
					finished = main.ai_package(n, p, dt)
	if finished:
		pk.erase(p)
		if bool(p.get("repeat", false)) and TYPE_ID.get(t, 9) <= 4:
			var again := _package_from_record(p)
			again.erase("allowed")
			pk.append(again)
		st.done = TYPE_ID.get(t, 9) <= 4
		r.path = []
		r.wstate = "choose"
		_stop(n)
	elif TYPE_ID.get(t, 9) <= 4:
		st.done = false
	_animate(n, r)

# --- powitanie ---------------------------------------------------------------------------------------------

func _update_greeting(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float, react: bool) -> void:
	var t := String(p.get("type", "none")) if not p.is_empty() else "none"
	if t not in ["wander", "travel", "none"] or n.swimming:
		r.greet = "none"
		r.greet_timer = 0
		return
	var pp := mw_pos(main.player)
	var here := mw_pos(n)
	if r.greet == "progress":
		_turn_to(n, pp, dt, 0.087)
	if not react:
		return
	var hello := float((_record(n).get("ai", {}) as Dictionary).get("hello", 0))
	var dist := here.distance_to(pp)
	if r.greet == "none":
		var hd := hello * float(_gmst("iGreetDistanceMultiplier", 6))
		if hello > 0.0 and dist <= hd and main.combat.health(main.combat.player_fighter()) > 0.0 \
				and _los(n, main.player) and awareness(main.player, n):
			r.greet_timer = int(r.greet_timer) + 1
		if int(r.greet_timer) >= 2:
			r.greet = "progress"
			r.greet_timer = 0
	elif r.greet == "progress":
		r.greet_timer = int(r.greet_timer) + 1
		if int(r.greet_timer) > int(float(_gmst("iGreetDuration", 4)) / REACTION):
			r.greet = "done"
			r.greet_timer = 0
	if r.greet != "none" and dist >= float(_gmst("fGreetDistanceReset", 512.0)):
		r.greet = "none"
		r.greet_timer = 0

## Wykrywanie (awarenessCheck) – etap 8c; do tego czasu NPC zawsze widzi gracza.
func awareness(_observer: Node, _actor: Node) -> bool:
	if main.has_method("awareness_check"):
		return main.awareness_check(_observer, _actor)
	return true

func _los(a: Node3D, b: Node3D) -> bool:
	var from := a.global_position + Vector3(0, 1.5, 0)
	var to := b.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array = []
	for x in [a, b]:
		if x is CollisionObject3D:
			ex.append((x as CollisionObject3D).get_rid())
	q.exclude = ex
	return a.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# --- AiWander ----------------------------------------------------------------------------------------------

func _wander(n: CharacterBody3D, r: Dictionary, st: Dictionary, p: Dictionary, dt: float, react: bool) -> bool:
	var dist := float(p.get("distance", 0))
	var duration := float(p.get("duration", 0))
	p.remaining = float(p.get("remaining", duration)) - _game_hours(dt)
	if not st.has("start"):
		var hp := mw_pos(n)
		st["start"] = [hp.x, hp.y, hp.z]
	var start := Vector3(float(st.start[0]), float(st.start[1]), float(st.start[2]))
	if react and duration > 0.0 and float(p.remaining) <= 0.0:
		p.remaining = duration
		return true
	if r.allowed == null:
		r.allowed = _allowed_positions(n, start, dist)
	match String(r.wstate):
		"choose":
			if n.velocity.length() > 0.01 and r.moving:
				return false
			var idle := _random_idle(p)
			if idle.is_empty() and dist > 0.0:
				r.wstate = "move"
			else:
				r.idle_anim = idle
				r.idle_t = _anim_length(n, idle) if not idle.is_empty() else 0.0
				r.wstate = "idle"
		"idle":
			_stop(n)
			r.idle_t = float(r.idle_t) - dt
			r.check_idle = float(r.check_idle) + dt
			if float(r.check_idle) >= IDLE_CHECK and dist > 0.0:
				r.check_idle = 0.0
				if not _near_allowed(n, r, float(_gmst("iMaxActivateDist", 192)) * 1.6):
					r.wstate = "move"
					return false
			if float(r.idle_t) <= 0.0:
				r.idle_anim = ""
				r.wstate = "choose" if (r.path as Array).is_empty() else "walk"
		"move":
			if not react:
				return false
			var allowed: Array = r.allowed
			if not allowed.is_empty():
				var i := rng.randi() % allowed.size()
				var dest: Vector3 = allowed[i]
				allowed.remove_at(i)
				if r.has("current"):
					allowed.append(r.current)
				r.current = dest
				r.path = graph(cell_key_at(mw_pos(n))).build_path(mw_pos(n), dest)
				r.dest = dest
				r.wstate = "walk"
				r.stuck_count = 0
			elif dist > 0.0 and rng.randi() % 100 >= 96:
				r.dest = _random_point_around(start, (0.2 + rng.randf() * 0.8) * dist)
				r.path = [r.dest]
				r.wstate = "walk"
				r.stuck_count = 0
			else:
				r.wstate = "idle"
				r.idle_t = 1.0
		"walk":
			if (r.path as Array).is_empty() or path_to(n, r.dest, dt, DESTINATION_TOLERANCE):
				r.path = []
				_stop(n)
				r.wstate = "choose"
			elif int(r.stuck_count) >= COUNT_BEFORE_RESET:
				r.path = []
				_stop(n)
				r.wstate = "choose"
				r.stuck_count = 0
	return false

## fillAllowedPositions: punkty siatki w promieniu wędrówki od startu, osiągalne z punktu najbliższego startowi;
## jeden punkt – plus start i punkty na krawędziach (addNonPathGridAllowedPoints).
func _allowed_positions(n: Node, start: Vector3, dist: float) -> Array:
	var out := []
	if dist <= 0.0:
		return out
	var g = graph(cell_key_at(start))
	if g.size() < 2:
		return out
	var c: int = g.closest(start)
	var last := -1
	for i in g.size():
		if (g.points[i] as Vector3).distance_squared_to(start) <= dist * dist and g.connected(c, i):
			out.append(g.points[i])
			last = i
	if out.size() == 1:
		out.append(start)
		for e in g.edges[last]:
			var a: Vector3 = g.points[last]
			var b: Vector3 = g.points[int(e[0])]
			var dd := minf(maxf(dist / 2.0, MIN_WANDER), a.distance_to(b))
			out.append(a + (b - a).normalized() * dd)
	if not out.is_empty():                     # setCurrentPositionToClosestAllowedPosition
		var bi := 0
		for i in out.size():
			if (out[i] as Vector3).distance_squared_to(start) < (out[bi] as Vector3).distance_squared_to(start):
				bi = i
		_rt(n).current = out[bi]
		out.remove_at(bi)
	return out

func _near_allowed(n: Node, r: Dictionary, d: float) -> bool:
	var here := mw_pos(n)
	var lst: Array = (r.allowed as Array).duplicate()
	if r.has("current"):
		lst.append(r.current)
	for v in lst:
		if (v as Vector3).distance_to(here) < d:
			return true
	return lst.is_empty()

func _random_point_around(c: Vector3, d: float) -> Vector3:
	var a := rng.randf() * TAU
	return c + Vector3(cos(a) * d, sin(a) * d, 0.0)

## getRandomIdle: rzut > fIdleChanceMultiplier → brak; inaczej największy rzut ≤ szansa grupy (idle2…idle9).
func _random_idle(p: Dictionary) -> String:
	if rng.randf() > float(_gmst("fIdleChanceMultiplier", 0.75)):
		return ""
	var idle: Array = p.get("idle", [])
	var best := ""
	var max_roll := 0.0
	for i in mini(idle.size(), 8):
		var roll := rng.randf() * 100.0
		if roll <= float(idle[i]) and roll > max_roll:
			best = "idle%d" % (i + 2)
			max_roll = roll
	return best

# --- AiTravel, AiEscort, AiFollow, AiActivate -------------------------------------------------------------

static func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO

func _travel(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float) -> bool:
	var dest := _vec(p.get("pos"))
	var here := mw_pos(n)
	if here.distance_squared_to(dest) > MAX_TRAVEL * MAX_TRAVEL:
		_stop(n)
		return false
	if path_to(n, dest, dt):
		return true
	var end_tol := maxf(64.0, speeds(n).x * dt)
	if Vector2(here.x - dest.x, here.y - dest.y).length() - 64.0 > end_tol:
		r.travel_t = TRAVEL_FINISH
		return false
	r.travel_t = float(r.travel_t) - dt
	return float(r.travel_t) <= 0.0

func _target_node(id: String) -> Node3D:
	if id.to_lower() == "player":
		return main.player
	return main.script_host.find_ref_by_base(id) if main.script_host != null else null

## Upływ czasu gry (getGameTimeScale: TIMESCALE godzin gry na godzinę rzeczywistą).
func _game_hours(dt: float) -> float:
	return dt * (float(main.envr.TIMESCALE) if main.envr != null else 30.0) / 3600.0

func _escort(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float) -> bool:
	if float(p.get("duration", 0)) > 0.0:
		p.remaining = float(p.get("remaining", 0)) - _game_hours(dt)
		if float(p.remaining) <= 0.0:
			p.remaining = float(p.duration)
			return true
	var t := _target_node(String(p.get("target", "")))
	var half := 64.0
	if t != null and mw_pos(t).distance_to(mw_pos(n)) <= float(p.get("max_dist", 450.0)):
		var dest := _vec(p.get("pos"))
		if path_to(n, dest, dt, half):
			return true
		p.max_dist = half + 450.0
	else:
		_stop(n)
		if t != null:
			_turn_to(n, mw_pos(t), dt)
		p.max_dist = half + 250.0
	return false

func _follow(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float, react: bool) -> bool:
	var t := _target_node(String(p.get("target", "")))
	if t == null:
		_stop(n)
		return false
	var here := mw_pos(n)
	var tp := mw_pos(t)
	var follow_dist := 29.0 + 64.0 + 29.0 * 2.0
	if not bool(p.get("active", false)):
		if react and here.distance_to(tp) < follow_dist + 384.0 and _los(n, t):
			p["active"] = true
		if not bool(p.get("active", false)):
			_stop(n)
			return false
	var pos := _vec(p.get("pos"))
	var always := float(p.get("duration", 0)) <= 0.0 and pos == Vector3.ZERO
	if not always:
		if float(p.get("duration", 0)) > 0.0:
			p.remaining = float(p.get("remaining", 0)) - _game_hours(dt)
			if float(p.remaining) <= 0.0:
				p.remaining = float(p.duration)
				return true
		if pos != Vector3.ZERO and here.distance_to(pos) < follow_dist and String(p.get("cell", "")).is_empty():
			return true
	var fd := follow_dist - 30.0 if bool(r.follow_moving) else follow_dist + 30.0
	if here.distance_to(tp) <= fd:
		_stop(n)
		r.follow_moving = false
		_turn_to(n, tp, dt, 0.78)
		return false
	var d := here.distance_to(tp)
	if d > 450.0:
		r.run = true
	elif d < 325.0:
		r.run = false
	r.follow_moving = not path_to(n, tp, dt, follow_dist, bool(r.run))
	return false

func _activate(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float) -> bool:
	var t := _target_node(String(p.get("target", "")))
	if t == null:
		return true                       # cel nie istnieje – pakiet kończy się (AiActivate)
	var reach := float(_gmst("iMaxActivateDist", 192))
	if path_to(n, mw_pos(t), dt, reach):
		if main.scripts != null:
			main.scripts.activated[String(t.get_meta("mw_sid", ""))] = true
		return true
	return false

# --- animacje ----------------------------------------------------------------------------------------------

func _player_of(n: Node) -> AnimationPlayer:
	var ap := n.get_node_or_null("Model/MWAnimations") as AnimationPlayer
	if ap == null:
		var found := n.find_children("MWAnimations", "AnimationPlayer", true, false)
		ap = found[0] if not found.is_empty() else null
	return ap

func _anim_length(n: Node, group: String) -> float:
	var ap := _player_of(n)
	if ap == null or not ap.has_animation(group):
		return 2.0
	return ap.get_animation(group).length

## Chód/bieg – grupy walkforward/runforward z prędkością odtwarzania wg prędkości ruchu; bezczynność – idleN
## albo idle (OpenMW CharacterController; ruch korzenia usunięty w bibliotece animacji).
func _animate(n: CharacterBody3D, r: Dictionary) -> void:
	var ap := _player_of(n)
	if ap == null:
		return
	var want := "idle"
	var speed := 1.0
	var hv := Vector2(n.velocity.x, n.velocity.z).length()
	if bool(r.moving) and hv > 0.05:
		want = "runforward" if n.want_run else "walkforward"
		if not ap.has_animation(want):
			want = "walkforward"
		var a := ap.get_animation(want) if ap.has_animation(want) else null
		var anim_speed := float(a.get_meta("mw_speed", 0.0)) if a != null else 0.0
		if anim_speed > 0.01:
			speed = clampf(hv / anim_speed, 0.3, 3.0)
	elif not String(r.idle_anim).is_empty():
		want = String(r.idle_anim)
	if not ap.has_animation(want):
		want = "idle" if ap.has_animation("idle") else ""
	if want.is_empty():
		return
	if ap.current_animation != want:
		ap.play(want, 0.2)
	ap.speed_scale = speed
	r.anim = want

# --- zapis -------------------------------------------------------------------------------------------------

## Pozycje aktorów przesuniętych przez AI do GameState (bez przebudowy węzłów) – przed zapisem i wyładowaniem.
func store_positions(only_key := "") -> void:
	for key in main.loaded:
		if not only_key.is_empty() and key != only_key:
			continue
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.has_meta("mw_actor") or not n is CharacterBody3D:
				continue
			var sid := String(n.get_meta("mw_sid", ""))
			if not rt.has(sid) and not main.state.refs.has(sid):
				continue
			var mw := mw_pos(n)
			main.state.store_ref_mw(sid, mw, Vector3(0, 0, -(n as Node3D).rotation.y))
