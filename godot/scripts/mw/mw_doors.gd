extends RefCounted
## Drzwi obrotowe (bez teleportu) jak w OpenMW: World::activateDoor / rotateDoor / processDoors i Door::activate.
## Drzwi otwierają się o 90° wokół osi Z od obrotu z danych (CellRef) z prędkością 90°/s; zderzenie z aktorem
## (drzwi obracają się w jego stronę) cofa obrót i każe NPC usunąć się z drogi (AiAvoidDoor). Obrót i stan ruchu
## są zapisywane w stanie referencji, więc po wczytaniu komórki/zapisu ruch jest kontynuowany (Door::insertObject).

const IDLE := 0
const OPENING := 1
const CLOSING := 2
const SPEED := PI / 2.0          # 90° na sekundę

var main
var moving := {}                 # sid → OPENING | CLOSING (mDoorStates)

func _init(game_main) -> void:
	main = game_main

func _entry(sid: String) -> Dictionary:
	return main.state.refs.get(sid, {})

func state_of(sid: String) -> int:
	return int(_entry(sid).get("door_state", IDLE))

func _set_state(sid: String, st: int) -> void:
	var e: Dictionary = main.state._entry(sid)
	if st == IDLE:
		e.erase("door_state")
	else:
		e["door_state"] = st

func base_rot(sid: String) -> Vector3:
	var r: Dictionary = main.base_ref(sid)
	var ro: Array = (r.get("mw", {}) as Dictionary).get("rot", [0, 0, 0])
	return Vector3(ro[0], ro[1], ro[2])

func current_rot(sid: String) -> Vector3:
	var m: Dictionary = _entry(sid).get("mw", {})
	if m.has("rot"):
		var ro: Array = m["rot"]
		return Vector3(ro[0], ro[1], ro[2])
	return base_rot(sid)

## Drzwi otwarte (obrót różny od obrotu z danych) – getNearbyDoor/proximityToDoor pomijają takie drzwi.
func is_open(sid: String) -> bool:
	return not is_equal_approx(current_rot(sid).z, base_rot(sid).z)

func node_of(sid: String) -> Node3D:
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				return n
	return null

## Door::activate (drzwi animowane) + World::activateDoor: kierunek ruchu i dźwięk otwarcia/zamknięcia.
func activate(node: Node3D) -> void:
	var sid := String(node.get_meta("mw_sid", ""))
	var st := state_of(sid)
	var door_rot := current_rot(sid).z - base_rot(sid).z
	var opening := true
	if st == OPENING:
		opening = false
	if st == IDLE and door_rot != 0.0:
		opening = false
	var rec: Dictionary = main.db.get_object(String(node.get_meta("mw_base", "")))
	var snd := String(rec.get("open_sound" if opening else "close_sound", ""))
	if main.get("audio") != null and main.audio != null and not snd.is_empty():
		main.audio.play(snd, node.global_position)
	# World::activateDoor
	match st:
		IDLE:
			st = CLOSING if door_rot != 0.0 else OPENING
		CLOSING:
			st = OPENING
		_:
			st = CLOSING
	_set_state(sid, st)
	moving[sid] = st

## World::processDoors.
func process(dt: float) -> void:
	for sid in moving.keys():
		var n := node_of(sid)
		if n == null or state_of(sid) == IDLE:
			moving.erase(sid)              # komórka nieaktywna – ruch wznowi Door::insertObject (resume)
			continue
		if rotate_door(sid, n, int(moving[sid]), dt):
			_set_state(sid, IDLE)
			moving.erase(sid)

## Wznowienie ruchu po wczytaniu komórki (Door::insertObject).
func resume_cell(key: String) -> void:
	for r in main.db.get_cell(key).get("refs", []):
		var sid := String(r.get("sid", ""))
		var st := state_of(sid)
		if st != IDLE:
			moving[sid] = st

func _apply_rot(sid: String, n: Node3D, rot: Vector3) -> void:
	var r: Dictionary = main.base_ref(sid)
	var m: Dictionary = _entry(sid).get("mw", r.get("mw", {}))
	var p: Array = m.get("pos", [0, 0, 0])
	var s := float(m.get("scale", 1.0))
	n.global_transform = Transform3D(MWCoords.mw_rot_to_basis(rot).scaled(Vector3(s, s, s)), n.global_position)
	main.state.store_ref_mw(sid, Vector3(p[0], p[1], p[2]), rot)

## World::rotateDoor: obrót o duration·90° w stronę stanu, cofnięcie przy zderzeniu z aktorem, w stronę którego
## drzwi się obracają (NPC dostaje AiAvoidDoor). true – osiągnięto pozycję końcową.
func rotate_door(sid: String, n: Node3D, st: int, dt: float) -> bool:
	var old := current_rot(sid)
	var min_rot := base_rot(sid).z
	var max_rot := min_rot + PI / 2.0
	var diff := dt * SPEED * (1.0 if st == OPENING else -1.0)
	var target := clampf(old.z + diff, min_rot, max_rot)
	var nr := old
	nr.z = target
	_apply_rot(sid, n, nr)
	var reached := (target == max_rot and st != IDLE) or target == min_rot
	var blocked := false
	var leaf_old := _leaf_world(sid, n, old)
	var leaf := _leaf_world(sid, n, nr)          # skrzydło po obrocie (MW, w poziomie)
	var sweep := signf(Vector2(leaf_old.x, leaf_old.y).angle_to(Vector2(leaf.x, leaf.y)))
	var hinge := MWCoords.godot_to_mw(n.global_position)
	for actor in _actors_touching(n):
		var a := MWCoords.godot_to_mw(actor.global_position) - hinge
		a.z = 0.0
		# punkt drzwi przy aktorze porusza się stycznie (Quat(diff, Z)·local − local); drzwi „idą” na aktora,
		# gdy aktor leży przed skrzydłem w kierunku obrotu
		var ahead := sweep * Vector2(leaf.x, leaf.y).angle_to(Vector2(a.x, a.y))
		if ahead < 0.0:
			continue                       # drzwi odchodzą od aktora
		blocked = true
		if actor != main.player and main.ai != null and main.ai.has_method("avoid_door"):
			main.ai.avoid_door(actor, sid)
		reached = false
	if blocked:
		_apply_rot(sid, n, old)
	return reached

var _leaf := {}
## Kierunek skrzydła (od zawiasu do środka modelu) w świecie MW dla obrotu rot – do rozstrzygnięcia, czy drzwi
## obracają się w stronę aktora (OpenMW: kierunek ruchu punktu kontaktu · normalna).
func _leaf_world(sid: String, n: Node3D, rot: Vector3) -> Vector3:
	if not _leaf.has(sid):
		var box := AABB()
		var first := true
		var inv := n.global_transform.affine_inverse()
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var bb: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		var c: Vector3 = box.get_center() if not first else Vector3(1, 0, 0)
		c.y = 0.0
		_leaf[sid] = c.normalized() if c.length() > 0.0001 else Vector3(1, 0, 0)
	var w: Vector3 = MWCoords.mw_rot_to_basis(rot) * (_leaf[sid] as Vector3)
	var m := MWCoords.godot_to_mw(w) - MWCoords.godot_to_mw(Vector3.ZERO)
	m.z = 0.0
	return m.normalized()

## Aktorzy (z graczem), których kolizja nachodzi na kolizję drzwi (getCollisionsPoints Door ↔ Actor).
func _actors_touching(n: Node3D) -> Array:
	var out := []
	var bodies := {}
	for b in n.find_children("*", "StaticBody3D", true, false):
		bodies[(b as CollisionObject3D).get_rid()] = true
	if bodies.is_empty():
		return out
	var space := n.get_world_3d().direct_space_state
	var cands: Array = main.ai.actor_nodes() if main.ai != null else []
	if main.player != null:
		cands = cands + [main.player]
	for a in cands:
		if not (a is CharacterBody3D) or (a as Node3D).global_position.distance_to(n.global_position) > 4.0:
			continue
		for cs in (a as Node).get_children():
			if not (cs is CollisionShape3D) or (cs as CollisionShape3D).shape == null:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = (cs as CollisionShape3D).shape
			q.transform = (cs as CollisionShape3D).global_transform
			q.exclude = [(a as CollisionObject3D).get_rid()]
			for res in space.intersect_shape(q, 16):
				if bodies.has(res.get("rid")):
					out.append(a)
					break
			break
	return out

## World::hasCollisionWithDoor: odcinek (MW) przecina prostopadłościan otaczający drzwi w ich układzie lokalnym.
func on_the_way(n: Node3D, from_mw: Vector3, to_mw: Vector3) -> bool:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for b in n.find_children("*", "CollisionShape3D", true, false):
		var cs := b as CollisionShape3D
		if cs.shape == null:
			continue
		var dbg: Mesh = cs.shape.get_debug_mesh()
		if dbg == null:
			continue
		var bb: AABB = (inv * cs.global_transform) * dbg.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		return false
	var a := inv * MWCoords.mw_to_godot(from_mw)
	var b2 := inv * MWCoords.mw_to_godot(to_mw)
	return box.intersects_segment(a, b2) != null
