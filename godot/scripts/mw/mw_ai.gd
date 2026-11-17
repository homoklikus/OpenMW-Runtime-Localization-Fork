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
const TYPE_ID := {"wander": 0, "travel": 1, "escort": 2, "follow": 3, "activate": 4, "combat": 5, "pursue": 6,
	"avoiddoor": 7, "face": 8}
const REACTION := 0.25                  # AiReactionTimer (s)
const DESTINATION_TOLERANCE := 64.0     # AiWander
const DEFAULT_TOLERANCE := 32.0         # pathfinding.hpp: domyślna odległość osiągnięcia celu (3D)
const MIN_TOLERANCE := 1.0
const MIN_WANDER := 128.0               # minimumWanderDistance
const TRAVEL_FINISH := 2.0
const MAX_TRAVEL := 7168.0
const IDLE_CHECK := 1.5
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

var _doors := {}          # klucz komórki → [[sid, pozycja MW, obrót z]] drzwi (proximityToDoor)

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
		"face":
			d["priority"] = 2
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
	reset_path(r)
	if cancel_other:
		r.wstate = "choose"                 # mAiState.reset() tylko przy anulowaniu poprzednich
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
## AiPackage::pathTo: idzie do celu po drodze z siatki ścieżek; → true po dojściu.
## * cel osiągnięty, gdy odległość 3D ≤ tolerancji (DEFAULT_TOLERANCE 32 j.),
## * drogę liczy co reakcję (AI_REACTION_TIME), gdy brak drogi, jej koniec odbiega od celu o > 10 j. (w poziomie)
##   albo zmieniła się komórka; koniec drogi dalej niż 100 j. od celu → cel dopisany,
## * skrótu prosto do celu nie ma dla chodzących (OpenMW: tylko latające/pływające – canActorMoveByZAxis),
## * PathFinder::update: punkty zdejmowane po odległości w poziomie < tolerancji punktu
##   (2 × prędkość × dt + 1,2 × połowa szerokości), ostatni – < DEFAULT_TOLERANCE; pusta droga = koniec.
## Kolejność źródeł drogi jak PathFinder::buildPath: siatka nawigacji (mw_navmesh) → siatka ścieżek → prosto.
## Co reakcję: openDoors (drzwi na drodze otwierane przez NPC/stworzenia dwunożne, poza AiWander).
func path_to(n: CharacterBody3D, dest: Vector3, dt: float, tolerance := DEFAULT_TOLERANCE, run := false) -> bool:
	var r := _rt(n)
	var here := mw_pos(n)
	if here.distance_to(dest) <= tolerance:
		r.path = []
		r.path_built = false
		_stop(n)
		return true
	var key := cell_key_at(here)
	r.path_react = float(r.get("path_react", 0.0)) - dt
	if float(r.path_react) <= 0.0:
		r.path_react = REACTION
		if can_open_doors(n):
			open_doors(n, r)
		var p0: Array = r.path
		if p0.is_empty() or path_distance((p0.back() as Vector3), dest) > 10.0 \
				or String(r.get("path_cell", "")) != key or not bool(r.get("path_built", false)) \
				or (not bool(r.get("path_nav", false)) and main.navmesh != null and main.navmesh.has_cell(key)):
			build_path_for(r, here, dest, key)
	var sp := speeds(n)
	var speed: float = sp.y if run else sp.x
	var point_tol := maxf(MIN_TOLERANCE, 2.0 * speed * dt + 1.2 * half_width(n))
	while (r.path as Array).size() > 1 and _dist2d(r.path[0], here) < point_tol:
		r.path.pop_front()
	# UpdateFlag_RemoveLoops (co reakcję, droga z siatki nawigacji): pomija punkty, gdy aktor jest już przy
	# dalszym odcinku i ma do niego prostą drogę
	if bool(r.get("path_nav", false)) and float(r.path_react) == REACTION and (r.path as Array).size() > 1:
		var begin := 0
		for i in range(1, (r.path as Array).size()):
			var a2: Vector3 = r.path[i - 1]
			var b2: Vector3 = r.path[i]
			if _dist_to_segment(here, a2, b2) < point_tol and main.navmesh.valid_shortcut(key, here, b2):
				begin = i
		for i in begin:
			r.path.pop_front()
	if (r.path as Array).size() == 1 and _dist2d(r.path[0], here) < DEFAULT_TOLERANCE:
		r.path.pop_front()
	if (r.path as Array).is_empty() and bool(r.get("path_built", false)):
		r.path_built = false                         # checkPathCompleted
		_turn_to(n, dest, dt)
		_stop(n)
		return true
	if (r.path as Array).is_empty():
		_stop(n)
		return false
	var wp: Vector3 = r.path[0]
	_turn_to(n, wp, dt)
	n.walk_speed = sp.x / UNITS
	n.run_speed = sp.y / UNITS
	n.want_run = run
	r.moving = true
	n.move_input = Vector2(0.0, -1.0)
	obstacle_update(n, r, wp, dt, speed)
	if is_evading(n):                              # evadeObstacles: najpierw drzwi, potem unik
		var door := nearby_door(n, float(_gmst("iMaxActivateDist", 192)))
		if door != null and can_open_doors(n):
			open_doors(n, r)
		else:
			var d: Vector2 = EVADE_DIRS[int(r.ob_dir)]
			n.move_input = Vector2(d.x, -d.y)
	r.last_pos = here
	return false

## getPathDistance: w poziomie, chyba że różnica wysokości przekracza wzrost aktora (wtedy 3D).
static func path_distance(a: Vector3, b: Vector3, height := 128.0) -> float:
	return a.distance_to(b) if absf(a.z - b.z) > height else _dist2d(a, b)

## PathFinder::buildPath: siatka nawigacji (Success) → siatka ścieżek → (brak navmesh) prosto do celu;
## koniec drogi dalej niż 100 j. od celu → cel dopisany (AiPackage::pathTo).
func build_path_for(r: Dictionary, here: Vector3, dest: Vector3, key: String) -> void:
	var np: Array = []
	var status := "not_found"
	var nav = main.get("navmesh")
	if nav != null:
		var res: Dictionary = nav.find_path(key, here, dest)
		status = String(res.status)
		if status == "ok":
			np = res.path
	r.path_nav = not np.is_empty()
	if np.is_empty():
		np = graph(key).build_path(here, dest, _world_clear)
	if np.is_empty() and status == "not_found":
		np = [dest]
	if not np.is_empty() and (np.back() as Vector3).distance_to(dest) > 100.0:
		np.append(dest)
	r.path = np
	r.dest = dest
	r.path_cell = key
	r.path_built = not np.is_empty()

## Misc::getVectorToLine (długość) – odległość punktu od odcinka.
static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Nowa droga (PathFinder::clearPath, ObstacleCheck w stanie początkowym).
static func reset_path(r: Dictionary) -> void:
	r.path = []
	r.path_built = false
	r.path_react = 0.0
	r.path_cell = ""
	r.ob_state = "initial"
	r.evade_t = 0.0

static func _dist2d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

## Połowa szerokości aktora (getHalfExtents x/y) w jednostkach MW – promień walca kolizji.
func half_width(n: Node) -> float:
	var r = n.get("capsule_radius")
	return float(r) * UNITS if r != null else 29.0

## Promień świata bez aktorów i drzwi (CollisionType_World) między punktami MW → true, gdy nic nie zasłania.
func _world_clear(from_mw: Vector3, to_mw: Vector3) -> bool:
	if main.player == null:
		return true
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	var from := MWCoords.mw_to_godot(from_mw)
	var to := MWCoords.mw_to_godot(to_mw)
	var ex: Array = []
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = ex
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			return true
		var c = hit.collider
		var ref := MWTravel.ref_of(c)
		var skip: bool = c is CharacterBody3D or (ref != null and (ref.has_meta("mw_actor") or \
			String(main.db.get_object(String(ref.get_meta("mw_base", ""))).get("type", "")) == "DOOR"))
		if not skip:
			return false
		ex.append((c as CollisionObject3D).get_rid())
	return true

func is_evading(n: Node) -> bool:
	return String(_rt(n).get("ob_state", "")) == "evade"

## ObstacleCheck (obstacle.cpp): stan początkowy → normalny → sprawdzanie utknięcia (zbliżenie do punktu < 0,5 ×
## prędkość × dt przez 1,5 s) → omijanie przez 1 s w kolejnym z 7 kierunków (prawo-przód, prawo, prawo-tył, tył,
## lewo-tył, lewo, lewo-przód), potem znowu normalnie. destination – następny punkt drogi.
const EVADE_DIRS := [Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
const SAME_SPOT_DIST := 0.5
const SAME_SPOT_TIME := 1.5
const EVADE_DURATION := 1.0

func obstacle_update(n: Node, r: Dictionary, destination: Vector3, dt: float, speed: float) -> void:
	var pos := mw_pos(n)
	var st := String(r.get("ob_state", "initial"))
	if st == "initial":
		r.ob_state = "norm"
		r.ob_dur = 0.0
		r.ob_prev = pos
		r.ob_init = destination.distance_to(pos)
		r.ob_dest = destination
		r.evade_t = 0.0
		return
	if st != "evade":
		if (r.ob_dest as Vector3) != destination:
			r.ob_init = destination.distance_to(r.ob_prev)
			r.ob_dest = destination
		var same := SAME_SPOT_DIST * speed * dt
		var moved: float = destination.distance_to(r.ob_prev) - destination.distance_to(pos)
		var from_init: float = float(r.ob_init) - destination.distance_to(pos)
		r.ob_prev = pos
		if moved >= same and from_init >= same:
			r.ob_state = "norm"
			r.ob_dur = 0.0
			return
		if st == "norm":
			r.ob_state = "check"
			r.ob_dur = dt
			r.ob_init = destination.distance_to(pos)
			return
		r.ob_dur = float(r.ob_dur) + dt
		if float(r.ob_dur) < SAME_SPOT_TIME:
			return
		r.ob_state = "evade"
		r.ob_dur = 0.0
		r.ob_dir = (int(r.get("ob_dir", -1)) + 1) % EVADE_DIRS.size()
		r.evade_t = EVADE_DURATION
		return
	r.ob_dur = float(r.ob_dur) + dt
	r.evade_t = maxf(0.0, EVADE_DURATION - float(r.ob_dur))
	if float(r.ob_dur) >= EVADE_DURATION:
		r.ob_state = "norm"
		r.ob_dur = 0.0
		r.ob_prev = pos

# --- pętla -------------------------------------------------------------------------------------------------

## Co klatkę (main._process, poza pauzą): aktorzy we wczytanych komórkach.
func tick(dt: float) -> void:
	if not enabled or main.player == null:
		return
	var nodes := actor_nodes()
	for n in nodes:
		update_actor(n, dt)
	avoid_collisions(nodes, dt)

## Kąt Z w układzie MW (0 = +Y, zgodnie z ruchem wskazówek) z obrotu węzła Godota.
static func rot_z(n: Node3D) -> float:
	return -n.rotation.y

## Misc::rotateVec2f
static func rotate_vec(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))

## Zamierzony ruch aktora w układzie lokalnym MW (mPosition[0] = w prawo, [1] = do przodu) i prędkość maksymalna.
func _movement(n: Node3D) -> Vector2:
	if n == main.player:
		var v := MWCoords.godot_to_mw(main.player.global_position + main.player.velocity) - mw_pos(main.player)
		return rotate_vec(Vector2(v.x, v.y), rot_z(main.player))      # już z prędkością (j./s)
	var mi: Vector2 = n.get("move_input") if n.get("move_input") != null else Vector2.ZERO
	return Vector2(mi.x, -mi.y)

func _max_speed(n: Node3D) -> float:
	if n == main.player:
		return 1.0
	var w = n.get("run_speed") if bool(n.get("want_run")) else n.get("walk_speed")
	return float(w) * UNITS if w != null else speeds(n).x

## Actors::predictAndAvoidCollisions: idący NPC przewiduje zderzenie z innym aktorem (gracz też) w ciągu do 2 s
## (nie dalej niż do następnego punktu drogi), w promieniu 200 j. (100 j. stojąc) i z przodu, przy widoczności
## i świadomości – i koryguje kierunek w bok (nie do tyłu); stojący wędrujący ustępują drogi i odwracają się
## do nadchodzącego. Nie dotyczy gracza.
func avoid_collisions(nodes: Array, dt: float) -> void:
	const MIN_GAP := 10.0
	const PARTIAL := 200.0
	const STRICT := 100.0
	const MAX_T := 2.0
	var all: Array = nodes.duplicate()
	all.append(main.player)
	var cache := {}
	for a in all:
		var mv := _movement(a)
		var ms := _max_speed(a)
		cache[a] = {"mv": mv, "ms": ms, "pos": mw_pos(a), "rot": rot_z(a), "half": half_width(a),
			"hz": 64.0, "world": rotate_vec(mv * (1.0 if a == main.player else ms), -rot_z(a))}
	for n in nodes:
		var c: Dictionary = cache[n]
		var max_speed: float = c.ms
		if max_speed <= 0.0:
			continue
		var orig: Vector2 = c.mv
		var moving := orig.length_squared() > 0.01
		if orig.y < 0.0:
			continue
		var avoid := moving
		var give_way := false
		var turn_to := not moving
		var target: Node = null
		var pk: Array = ai_state(n).packages
		var active: Dictionary = pk[0] if not pk.is_empty() else {}
		match String(active.get("type", "")):
			"follow":
				avoid = true
			"wander":
				if float(active.get("distance", 0)) > 0.0:
					give_way = true
			"combat", "pursue":
				target = _target_node(String(active.get("target", "")))
				avoid = moving
				turn_to = false
		if not avoid and not give_way:
			continue
		var base_speed: Vector2 = orig * max_speed
		var base_pos: Vector3 = c.pos
		var base_rot: float = c.rot
		var max_dist := PARTIAL if moving else STRICT
		var time_check := MAX_T
		if not give_way and not pk.is_empty():
			var r := _rt(n)
			var nxt: Vector3 = (r.path[0] if not (r.path as Array).is_empty() else r.get("dest", base_pos)) if r.get("dest") != null else base_pos
			if not (nxt as Vector3).is_finite():
				nxt = base_pos
			var tol := maxf(MIN_TOLERANCE, 2.0 * max_speed * dt + 1.2 * float(c.half))
			time_check = minf(time_check, (nxt.distance_to(base_pos) - tol) / max_speed)
		var t_col := time_check
		var corr := Vector2.ZERO
		var angle_to := 0.0
		for o in all:
			if o == n or o == target:
				continue
			var oc: Dictionary = cache[o]
			var dpos: Vector3 = (oc.pos as Vector3) - base_pos
			var rel := rotate_vec(Vector2(dpos.x, dpos.y), base_rot)
			var dist := dpos.length()
			if dist > max_dist or rel.y < 0.0:
				continue
			if dpos.z > float(c.hz) * 2.0 or dpos.z < -float(oc.hz) * 2.0:
				continue
			var rel_speed := rotate_vec(oc.world, base_rot) - base_speed
			var col_dist := minf(MIN_GAP + float(c.half) + float(oc.half), rel.length())
			var vr := rel.dot(rel_speed)
			var v2 := rel_speed.length_squared()
			var dh := vr * vr - v2 * (rel.length_squared() - col_dist * col_dist)
			if dh <= 0.0 or v2 == 0.0:
				continue
			var t := (-vr - sqrt(dh)) / v2
			if t < 0.0 or t > t_col:
				continue
			if not _los(o, n) or not awareness(o, n):
				continue
			t_col = t
			angle_to = atan2(dpos.x, dpos.y)
			var at_t := rel + rel_speed * t
			var coef := at_t.dot(rel_speed) / (col_dist * col_dist * max_speed) * clampf((PARTIAL - dist) / (PARTIAL - STRICT), 0.0, 1.0)
			corr = at_t * coef
			var of: Dictionary = main.combat.fighter_of(o)
			if not of.is_empty() and main.combat.is_dead(of):
				corr.y *= 0.5
		if t_col < time_check:
			var nm := orig + corr
			nm.y = maxf(nm.y, 0.0)
			nm = nm.normalized()
			if moving:
				nm *= orig.length()
			n.move_input = Vector2(nm.x, -nm.y)
			if turn_to:
				n.rotation.y = -angle_to

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
	if react and not in_combat(n):
		_engage(n)
	var pk: Array = st.packages
	var p: Dictionary = pk[0] if not pk.is_empty() else {}
	_update_greeting(n, r, p, dt, react)
	_idle_voice(n, dt)
	if p.is_empty():
		st.last = -1
		_stop(n)
		_animate(n, r)
		return
	var t := String(p.get("type", ""))
	if TYPE_ID.get(t, 9) <= 4:
		st.last = TYPE_ID[t]
	# każdy pakiet ma własny PathFinder i ObstacleCheck (OpenMW): zmiana aktywnego pakietu = nowa droga
	if not is_same(r.get("pkg"), p):
		r.pkg = p
		reset_path(r)

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
			"combat": finished = _combat(n, r, p, dt, react)
			"avoiddoor": finished = _avoid_door(n, r, p, dt)
			"face":
				# AiFace (Face x y): obrót do punktu, koniec przy różnicy < 3° (zTurn); priorytet 2, bez anulowania
				_stop(n)
				finished = _turn_to(n, Vector3(float(p.x), float(p.y), 0.0), dt, deg_to_rad(3.0))
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
		reset_path(r)
		r.pkg = null
		r.wstate = "choose"
		_stop(n)
	elif TYPE_ID.get(t, 9) <= 4:
		st.done = false
	_animate(n, r)

# --- powitanie ---------------------------------------------------------------------------------------------

func _update_greeting(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float, react: bool) -> void:
	var t := String(p.get("type", "none")) if not p.is_empty() else "none"
	if in_combat(n):
		t = "combat"
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
			if main.dialogue != null and not main.dialogue.say_voice(n, "hello"):
				r.greet = "done"             # bez kwestii „Hello” – bez odwracania się (updateGreetingState)
	elif r.greet == "progress":
		r.greet_timer = int(r.greet_timer) + 1
		if int(r.greet_timer) > int(float(_gmst("iGreetDuration", 4)) / REACTION):
			r.greet = "done"
			r.greet_timer = 0
	if r.greet != "none" and dist >= float(_gmst("fGreetDistanceReset", 512.0)):
		r.greet = "none"
		r.greet_timer = 0


## playIdleDialogue: kwestia „Idle” – gdy Hello > 0, poza walką/eskortą/podążaniem, bliżej niż 3000 jedn.,
## nie pływa; szansa los × 10000 < fVoiceIdleOdds × (czas klatki × 6) i linia wzroku z graczem.
func _idle_voice(n: CharacterBody3D, dt: float) -> void:
	if main.dialogue == null or main.audio == null or main.player == null or n.swimming:
		return
	var a: Dictionary = main.dialogue.make_actor(n)
	if a.rec.is_empty() or main.audio.say_active(a.sid):
		return
	if float((a.rec.get("ai", {}) as Dictionary).get("hello", 0)) <= 0.0:
		return
	for p in ai_state(n).packages:
		if String(p.get("type", "")) in ["combat", "follow", "escort"]:
			return
	if mw_pos(n).distance_to(mw_pos(main.player)) >= 3000.0:
		return
	if rng.randf() * 10000.0 < float(_gmst("fVoiceIdleOdds", 0.0)) * dt * 6.0 and _los(main.player, n):
		main.dialogue.say_voice(n, "idle")

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
	# reactionTimeActions: bez punktów siatki w promieniu – co reakcję 4% szans na spacer w pobliżu startu
	# (wanderNearStart), inaczej bezczynność; spacer kończy się u celu albo na przeszkodzie (completeManualWalking)
	if react and dist > 0.0 and (r.allowed as Array).is_empty() and not bool(r.get("manual", false)):
		if rng.randi() % 100 >= 96:
			r.dest = _random_point_around(start, (0.2 + rng.randf() * 0.8) * dist)
			r.path = [r.dest]                       # buildStraightPath
			r.path_built = true
			r.path_cell = cell_key_at(mw_pos(n))
			r.manual = true
			r.wstate = "walk"
			r.stuck_count = 0
		elif String(r.wstate) in ["choose", "move"]:
			r.wstate = "idle"
			r.idle_t = 0.0 if String(r.idle_anim).is_empty() else float(r.idle_t)
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
				var near := float(_gmst("iMaxActivateDist", 192)) * 1.6
				if _near_door(n, near) or not _near_allowed(n, r, near):
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
				build_path_for(r, mw_pos(n), dest, cell_key_at(mw_pos(n)))
				if (r.path as Array).is_empty():
					r.path = [dest]
					r.path_built = true
				r.wstate = "walk"
				r.stuck_count = 0
			else:
				r.wstate = "idle"
				r.idle_t = 1.0
		"walk":
			if float(r.evade_t) > 0.0:
				r.stuck_count = int(r.stuck_count) + 1      # evadeObstacles: mStuckCount++ w każdej klatce omijania
			if (r.path as Array).is_empty() or path_to(n, r.dest, dt, DESTINATION_TOLERANCE):
				reset_path(r)
				_stop(n)
				r.wstate = "idle" if bool(r.get("manual", false)) else "choose"
				r.idle_t = 0.0
				r.manual = false
			elif int(r.stuck_count) >= COUNT_BEFORE_RESET or (bool(r.get("manual", false)) and float(r.evade_t) > 0.0):
				reset_path(r)
				_stop(n)
				r.wstate = "idle" if bool(r.get("manual", false)) else "choose"
				r.idle_t = 0.0
				r.manual = false
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

## isNearAllowedPosition: tylko punkty dozwolone – bieżący cel jest z nich usunięty (setPathToAnAllowedPosition),
## więc po dojściu do punktu bez innego w pobliżu NPC po chwili bezczynności rusza dalej.
func _near_allowed(n: Node, r: Dictionary, d: float) -> bool:
	var here := mw_pos(n)
	for v in (r.allowed as Array):
		if (v as Vector3).distance_to(here) < d:
			return true
	return false

## proximityToDoor (obstacle.cpp): zamknięte drzwi komórki aktora w odległości d (w poziomie) i w stożku ±60°
## przed nim – bezczynny NPC odchodzi spod drzwi.
func _near_door(n: Node3D, d: float) -> bool:
	return nearby_door(n, d) != null

## getNearbyDoor (GetNearbyDoorVisitor): włączone drzwi komórki aktora, nieruchome i zamknięte (obrót jak w
## danych), w odległości ≤ d w poziomie i w stożku ±60° od kierunku patrzenia.
func nearby_door(n: Node3D, d: float) -> Node3D:
	var key := cell_key_at(mw_pos(n))
	if not _doors.has(key):
		var lst := []
		for r in main.db.get_cell(key).get("refs", []):
			if String(main.db.get_object(String(r.get("base", ""))).get("type", "")) == "DOOR":
				var mw: Dictionary = r.get("mw", {})
				lst.append([String(r.get("sid", "")), _vec(mw.get("pos")), float((mw.get("rot", [0, 0, 0]) as Array)[2])])
		_doors[key] = lst
	var here := mw_pos(n)
	var fwd := Vector2(-sin(n.rotation.y), cos(n.rotation.y))
	for e in _doors[key]:
		var sid := String(e[0])
		if main.state != null and not main.state.is_enabled(sid):
			continue
		if main.doors != null and (main.doors.state_of(sid) != main.doors.IDLE or main.doors.is_open(sid)):
			continue
		var to := Vector2(e[1].x - here.x, e[1].y - here.y)
		if to.length() > d or to.length() < 0.001:
			continue
		if absf(fwd.angle_to(to.normalized())) <= PI / 3.0:
			return main.doors.node_of(sid) if main.doors != null else null
	return null

## canOpenDoors: dwunożni albo z ekwipunkiem (NPC; stworzenia z bronią).
func can_open_doors(n: Node) -> bool:
	var o: Dictionary = main.db.get_object(String(n.get_meta("mw_base", "")))
	if String(o.get("type", "")) == "NPC_":
		return true
	var c: Dictionary = _record(n)
	return bool(c.get("bipedal", false)) or bool(c.get("weapon_and_shield", false))

## AiPackage::openDoors: drzwi (bez teleportu, nieruchome) na odcinku do następnego punktu drogi – NPC je
## aktywuje, gdy nie są zamknięte na zamek ani zabezpieczone pułapką (albo gdy ma klucz). AiWander nie otwiera.
func open_doors(n: Node3D, r: Dictionary) -> void:
	var p = r.get("pkg")
	if p is Dictionary and String((p as Dictionary).get("type", "")) == "wander":
		return
	if (r.path as Array).is_empty() or main.doors == null:
		return
	var door := nearby_door(n, float(_gmst("iMaxActivateDist", 192)))
	if door == null:
		return
	var snap: Dictionary = main.interaction.snapshot(door)
	if not (snap.get("dest", {}) as Dictionary).is_empty():
		return
	var half_z := (float(n.capsule_height) * UNITS * 0.5) if n.get("capsule_height") != null else 64.0
	if not main.doors.on_the_way(door, mw_pos(n) + Vector3(0, 0, half_z), (r.path[0] as Vector3) + Vector3(0, 0, half_z)):
		return
	if String(snap.get("trap", "")).is_empty() and int(snap.get("lock", 0)) <= 0:
		main.doors.activate(door)
		return
	var key := String((snap.get("extra", {}) as Dictionary).get("key", "")).to_lower()
	if key.is_empty():
		return
	if main.interaction.inventory.count_of(String(n.get_meta("mw_sid", "")), main.combat.fighter_of(n).get("rec", {}), key) > 0:
		main.state.set_lock(String(door.get_meta("mw_sid", "")), 0)        # Door::activate z kluczem
		main.doors.activate(door)

## World::rotateDoor → AiAvoidDoor: aktor, w którego stronę obracają się drzwi, usuwa się z drogi
## (tylko gdy już tego nie robi).
func avoid_door(n: Node3D, door_sid: String) -> void:
	var st := ai_state(n)
	if not (st.packages as Array).is_empty() and String(st.packages[0].get("type", "")) == "avoiddoor":
		return
	stack(n, {"type": "avoiddoor", "door": door_sid, "priority": 2, "duration": 1.0, "first": true}, false)

## AiAvoidDoor::execute: odwrót od drzwi biegiem (kierunek co sekundę zmieniany losowo spośród 4, gdy utknął),
## koniec po sekundzie bez utknięcia albo gdy drzwi stanęły; sąsiedzi w promieniu 100 też ustępują.
func _avoid_door(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float) -> bool:
	var pos := mw_pos(n)
	if bool(p.get("first", false)) or float(p.duration) == 1.0:
		p.last_pos = pos
		p.first = false
	p.duration = float(p.duration) - dt
	if float(p.duration) < 0.0:
		var lp: Vector3 = p.get("last_pos", pos)
		if lp.distance_squared_to(pos) < 100.0:
			p.dir = rng.randi_range(1, 4) - 1           # rollDice(MAX_DIRECTIONS)
			p.duration = 1.0
		else:
			return true
	var sid := String(p.get("door", ""))
	if main.doors == null or main.doors.state_of(sid) == main.doors.IDLE:
		return true
	var door: Node3D = main.doors.node_of(sid)
	if door == null:
		return true
	var tp := MWCoords.godot_to_mw(door.global_position)
	var ang := atan2(pos.x - tp.x, pos.y - tp.y) + TAU / 4.0 * float(p.get("dir", 0))
	var sp := speeds(n)
	n.walk_speed = sp.x / UNITS
	n.run_speed = sp.y / UNITS
	n.want_run = true
	if _turn_to(n, pos + Vector3(sin(ang), cos(ang), 0.0) * 100.0, dt, deg_to_rad(5.0)):
		n.move_input = Vector2(0.0, -1.0)
		r.moving = true
	else:
		n.move_input = Vector2.ZERO
	for o in actor_nodes():
		if o == n or o == main.player or mw_pos(o).distance_to(pos) > 100.0:
			continue
		avoid_door(o, sid)
	return false

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

# --- wykrywanie (MechanicsManager::awarenessCheck) --------------------------------------------------------

var test_roll := -1                     # testy: stały rzut 0..99

func _roll100() -> int:
	return test_roll if test_roll >= 0 else rng.randi() % 100

## Czy obserwator zauważa aktora (ptr): skradanie (fSneakSkillMult × skradanie + 0,2 zręczność + 0,1 szczęście +
## waga butów × fSneakBootMult) × (fSneakDistanceBase + fSneakDistanceMultiplier × odległość) × zmęczenie
## + kameleon (+100 niewidzialność) wobec (skradanie + 0,2 zręczność + 0,1 szczęście − ślepota obserwatora) ×
## zmęczenie × fSneakViewMult (przodem) / fSneakNoViewMult (tyłem); rzut 0..99 ≥ różnica.
func awareness(ptr: Node3D, observer: Node3D, roll := -1) -> bool:
	var cb = main.combat
	var of: Dictionary = cb.fighter_of(observer)
	var pf: Dictionary = cb.fighter_of(ptr)
	if of.is_empty() or pf.is_empty() or cb.is_dead(of):
		return false
	var sneak_term := 0.0
	if ptr == main.player and main.player_sneaking():
		var at: Array = cb.attributes(pf)
		var boots := 0.0
		var b: Dictionary = cb.equipment(pf).get(cb.EQ.SLOT_BOOTS, {})
		if not b.is_empty():
			boots = float(b.rec.get("weight", 0.0))
		sneak_term = float(_gmst("fSneakSkillMult", 1.0)) * float(cb.skill(pf, 19)) + 0.2 * float(at[3]) + 0.1 * float(at[7]) \
			+ boots * float(_gmst("fSneakBootMult", -1.0))
	var p1 := mw_pos(ptr)
	var p2 := mw_pos(observer)
	var dist_term := float(_gmst("fSneakDistanceBase", 0.5)) + float(_gmst("fSneakDistanceMultiplier", 0.002)) * p1.distance_to(p2)
	var x := sneak_term * dist_term * float(cb.fatigue_term(pf)) + float(cb.magic_effect(pf, 40))
	if float(cb.magic_effect(pf, 39)) > 0.0:
		x += 100.0
	var oat: Array = cb.attributes(of)
	var obs := float(cb.skill(of, 19)) + 0.2 * float(oat[3]) + 0.1 * float(oat[7]) - float(cb.magic_effect(of, 47))
	var odir := Vector2(-sin(observer.rotation.y), cos(observer.rotation.y))
	var v := Vector2(p1.x - p2.x, p1.y - p2.y)
	var behind := v.length() > 0.001 and odir.dot(v.normalized()) < 0.0      # kąt > 90° od kierunku patrzenia
	var y := obs * float(cb.fatigue_term(of)) * float(_gmst("fSneakNoViewMult" if behind else "fSneakViewMult", 0.5 if behind else 1.5))
	return float(roll if roll >= 0 else _roll100()) >= x - y

# --- walka (Actors::engageCombat, AiCombat, aicombataction) ------------------------------------------------

func in_combat(n: Node) -> bool:
	for p in ai_state(n).packages:
		if String(p.get("type", "")) == "combat":
			return true
	return false

## AiSequence::isInCombat(target): pakiet walki z tym celem (sid albo "player").
func in_combat_with(n: Node, target_sid: String) -> bool:
	for p in ai_state(n).packages:
		if String(p.get("type", "")) == "combat" and String(p.get("target", "")) == target_sid:
			return true
	return false

## Cel walki (AiSequence::getCombatTarget): sid pierwszego pakietu walki albo "".
func combat_target(n: Node) -> String:
	for p in ai_state(n).packages:
		if String(p.get("type", "")) == "combat":
			return String(p.get("target", ""))
	return ""

## Po stronie gracza (getActorsSidingWith(player)): towarzysz z pakietem AiFollow/AiEscort na gracza.
func sides_with_player(n: Node) -> bool:
	for p in ai_state(n).packages:
		if String(p.get("type", "")) in ["follow", "escort"] and String(p.get("target", "")) == "player":
			return true
	return false

## MechanicsManager::startCombat: pakiet walki przed pozostałymi (priorytet 1).
func start_combat(n: Node, target: Node) -> void:
	if in_combat(n) or not _alive(n):
		return
	var tid := "player" if target == main.player else String(target.get_meta("mw_sid", ""))
	stack(n, {"type": "combat", "target": tid, "priority": 1}, false)
	_rt(n).action = {}
	_rt(n).cooldown = 0.0
	_rt(n).flee = false
	if main.has_method("on_combat_started"):
		main.on_combat_started(n, target)
	if main.dialogue != null:
		main.dialogue.say_voice(n, "attack")    # startCombat: shout, gdy jeszcze nie walczył

func stop_combat(n: Node) -> void:
	var st := ai_state(n)
	st.packages = (st.packages as Array).filter(func(x): return String(x.get("type", "")) != "combat")
	_stop(n)

## getFightTerm: walka + (iFightDistanceBase − fFightDistanceMultiplier × odległość) + (50 − postawa) ×
## fFightDispMult (stworzenia: postawa 50).
func fight_term(n: Node3D, target: Node3D) -> float:
	var fight := float(main.dialogue.ai_setting(main.dialogue.make_actor(n), "fight")) if main.dialogue != null else 30.0
	var d := Vector2(mw_pos(n).x - mw_pos(target).x, mw_pos(n).y - mw_pos(target).y).length()
	var bias := float(_gmst("iFightDistanceBase", 20)) - float(_gmst("fFightDistanceMultiplier", 0.005)) * d
	var disp := 50.0
	var a: Dictionary = main.dialogue.make_actor(n) if main.dialogue != null else {}
	if not a.is_empty() and a.npc:
		disp = float(main.dialogue.derived_disposition(a))
	# isAggressive: NPC wobec wilkołaka (albo gracza znanego jako wilkołak – PCKnownWerewolf) + iWerewolfFightMod
	var ww := false
	if not a.is_empty() and a.npc and String(target.get_meta("mw_actor", "npc" if target == main.player else "")) == "npc":
		if target == main.player:
			ww = bool(main.player_stats().get("werewolf", false)) or (main.scripts != null and main.scripts.get_global("pcknownwerewolf") != 0.0)
		else:
			ww = bool(main.state.actors.get(String(target.get_meta("mw_sid", "")), {}).get("werewolf", false))
	if ww:
		fight += float(_gmst("iWerewolfFightMod", 100))
	return fight + bias + (50.0 - disp) * float(_gmst("fFightDispMult", 0.2))

## engageCombat (względem gracza): agresywny (getFightTerm ≥ 100), w linii wzroku, zauważa gracza.
func _engage(n: CharacterBody3D) -> void:
	if in_combat(n) or main.player == null or main.combat.is_dead(main.combat.player_fighter()):
		return
	var calm := 49 if String(n.get_meta("mw_actor", "")) == "npc" else 50
	if main.magic != null and main.magic.magnitude_of(main.combat.fighter_of(n), calm) > 0.0:
		return
	if mw_pos(n).distance_to(mw_pos(main.player)) > MAX_TRAVEL:
		return
	if fight_term(n, main.player) < 100.0:
		return
	if _los(n, main.player) and awareness(main.player, n):
		start_combat(n, main.player)

## vanillaRateWeaponAndAmmo (broń biała; bez broni 0), vanillaRateSpell (szansa × fAIMagicSpellMult /
## fAIRangeMagicSpellMult), vanillaRateFlee – wybór akcji jak prepareNextAction (uproszczony: broń, czar, ucieczka).
func _choose_action(n: Node3D, target: Node3D) -> Dictionary:
	var cb = main.combat
	var f: Dictionary = cb.fighter_of(n)
	var w: Dictionary = cb.weapon(f)
	var best := {"kind": "melee", "rating": 0.0}
	var anti := 0.0
	if not w.is_empty():
		var sk := float(cb.skill(f, cb.weapon_skill(w))) * 0.01
		var wt := int(w.rec.get("weapon_type", 0))
		var chop_mult := float(_gmst("fAIMeleeWeaponMult", 1.0))
		var bonus := 0.0
		if wt in [9, 10, 11]:
			var ammo: Dictionary = cb.equipment(f).get(cb.EQ.SLOT_AMMUNITION, {})
			if wt == 11 or not ammo.is_empty():
				bonus = float((ammo.rec.get("chop", [0, 0]) as Array)[1]) if not ammo.is_empty() and wt != 11 else 0.0
				chop_mult = float(_gmst("fAIRangeMeleeWeaponMult", 5.0))
				best.kind = "ranged"
			else:
				chop_mult = 0.0
		var ch: Array = w.rec.get("chop", [0, 0])
		var sl: Array = w.rec.get("slash", [0, 0])
		var th: Array = w.rec.get("thrust", [0, 0])
		var rating := float(cb.armor_rating(f)) * float(_gmst("fAIMeleeArmorMult", 1.0)) + maxf((float(ch[1]) + bonus) * sk * chop_mult,
			maxf(float(sl[1]) * sk * float(_gmst("fAIMeleeWeaponMult", 1.0)), float(th[1]) * sk * float(_gmst("fAIMeleeWeaponMult", 1.0))))
		best.rating = rating
		anti = rating
	var spells: Array = main.magic.actor_spells(f) if main.magic != null else f.rec.get("spells", [])
	for sid in spells:
		var sp: Dictionary = main.builder.actors.record("spell", String(sid).to_lower())
		if sp.is_empty() or int(sp.get("spell_type", -1)) != 0:
			continue
		var harmful := false
		var ranged := false
		for e in sp.get("effects", []):
			var mg: Dictionary = main.magic.effect(int(e.get("effect", -1)))
			if bool(mg.get("harmful", false)) and int(e.get("range", 0)) != 0:
				harmful = true
				ranged = ranged or int(e.get("range", 0)) == 2
		if not harmful or main.magic.magicka(f) < float(main.magic.spell_cost(sp)):
			continue
		var mult := float(_gmst("fAIRangeMagicSpellMult" if ranged else "fAIMagicSpellMult", 5.0 if ranged else 1.0))
		var rate := float(main.magic.spell_chance(sp, f)) * mult
		if rate > float(best.rating):
			best = {"kind": "spell", "spell": String(sid).to_lower(), "ranged": ranged, "rating": rate}
			anti = rate
	# vanillaRateFlee
	var flee := float(main.dialogue.ai_setting(main.dialogue.make_actor(n), "flee")) if main.dialogue != null else 30.0
	var fr := flee
	if flee < 100.0:
		var ratio: float = float(cb.health(f)) / maxf(1.0, float(cb.max_health(f)))
		fr = (1.0 - ratio) * float(_gmst("fAIFleeHealthMult", 7.0)) + flee * float(_gmst("fAIFleeFleeMult", 0.3))
		if fr != 0.0:
			fr += float(_gmst("iFightDistanceBase", 20)) - float(_gmst("fFightDistanceMultiplier", 0.005)) * mw_pos(n).distance_to(mw_pos(target))
	if fr < 100.0:
		fr = 0.0
	if fr > anti:
		return {"kind": "flee"}
	return best

func _target_of(p: Dictionary) -> Node3D:
	var tid := String(p.get("target", "player"))
	if tid == "player":
		return main.player
	for x in actor_nodes():
		if String(x.get_meta("mw_sid", "")) == tid:
			return x
	return null

## AiCombat: wybór akcji co odstęp, podejście (bieg) na zasięg broni/czaru, atak w odstępach wg szybkości broni,
## rzucanie czarów (dotyk/cel), strzał, ucieczka. Koniec: cel martwy/nieobecny albo poza zasięgiem 7168.
func _combat(n: CharacterBody3D, r: Dictionary, p: Dictionary, dt: float, react: bool) -> bool:
	var cb = main.combat
	var target := _target_of(p)
	if target == null:
		return true
	var tf: Dictionary = cb.fighter_of(target)
	if tf.is_empty() or cb.is_dead(tf):
		return true
	var f: Dictionary = cb.fighter_of(n)
	if bool(_actor(n).get("knocked_down", false)):       # czas powalenia – main._update_knockdown
		_stop(n)
		return false
	var here := mw_pos(n)
	var there := mw_pos(target)
	if here.distance_to(there) > MAX_TRAVEL:
		return true
	r.cooldown = float(r.get("cooldown", 0.0)) - dt
	if react and (not r.has("action") or (r.action as Dictionary).is_empty() or float(r.cooldown) <= 0.0 and not bool(r.get("attacking", false))):
		r.action = _choose_action(n, target)
		var fleeing: bool = r.action.kind == "flee"
		if fleeing and not bool(r.get("flee", false)) and main.dialogue != null:
			main.dialogue.say_voice(n, "flee")
		r.flee = fleeing
	if bool(r.get("flee", false)):
		var away: Vector3 = here + (here - there).normalized() * 512.0
		path_to(n, away, dt, 32.0, true)
		if float(r.cooldown) <= 0.0:
			r.cooldown = 2.0
		return false
	var act: Dictionary = r.get("action", {})
	var w: Dictionary = cb.weapon(f)
	var reach: float = cb.reach(f, w) if act.get("kind", "melee") == "melee" else (1000.0 if act.get("kind", "") == "ranged" or bool(act.get("ranged", false)) else cb.reach(f, {}))
	var dist := Vector2(here.x - there.x, here.y - there.y).length() - 29.0 - 29.0
	if dist > reach or not _los(n, target):
		path_to(n, there, dt, maxf(1.0, reach * 0.8), true)
		return false
	_stop(n)
	if not _turn_to(n, there, dt, 0.2):
		return false
	if float(r.cooldown) > 0.0:
		return false
	match String(act.get("kind", "melee")):
		"spell":
			if bool(act.get("ranged", false)) and rng.randi() % 100 < int(_gmst("iVoiceAttackOdds", 10)) and main.dialogue != null:
				main.dialogue.say_voice(n, "attack")     # canShout tylko dla czarów na cel
			var touch: Dictionary = tf if not bool(act.get("ranged", false)) else {}
			var res: Dictionary = main.magic.cast_spell(f, String(act.spell), touch)
			if bool(res.get("success", false)) and not (res.get("bolt", []) as Array).is_empty() and main.has_method("launch_bolt_from"):
				main.launch_bolt_from(n, target, f, res.bolt, res.source, res.get("spell", {}))
			r.cooldown = 2.0 + rng.randf()
		"ranged":
			if main.has_method("npc_shoot"):
				main.npc_shoot(n, target, f)
			r.cooldown = 1.5 + rng.randf()
		_:
			# siła: stworzenia bez broni – min(1, 0,1 + los) (prepareHit), z bronią – czas trzymania ataku (los 0..1)
			var strength := minf(1.0, 0.1 + rng.randf()) if w.is_empty() else rng.randf()
			cb.melee(f, tf, rng.randi() % 3, strength)
			if rng.randi() % 100 < int(_gmst("iVoiceAttackOdds", 10)) and main.dialogue != null:
				main.dialogue.say_voice(n, "attack")     # prowokujący okrzyk przy ataku (canShout)
			# odstęp: animacja ataku (readyToStartAttack) + fCombatDelayCreature/NPC + 0,01 × los(0..99), maks. +0,9
			var spd := float(w.rec.get("speed", 1.0)) if not w.is_empty() else 1.0
			var anim := 1.0
			var ap := _player_of(n)
			if f.get("kind", "") == "creature" and ap != null and ap.has_animation("attack1"):
				anim = clampf(ap.get_animation("attack1").length, 0.3, 3.0)
			anim /= maxf(0.25, spd)
			var delay := float(_gmst("fCombatDelayCreature" if f.get("kind", "") == "creature" else "fCombatDelayNPC", 0.1))
			r.cooldown = anim + minf(delay + 0.01 * float(rng.randi() % 100), delay + 0.9)
	r.action = {}
	return false

func _actor(n: Node) -> Dictionary:
	return main.combat._actor_state({"sid": String(n.get_meta("mw_sid", ""))})
