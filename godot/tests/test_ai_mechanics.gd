extends SceneTree
## Regresje mechaniki zgodnej z OpenMW (bez danych gry – sceny syntetyczne):
## * buildPathByPathgridImpl (mw_pathgrid.build_path): droga między poziomami przez schody, „prosto do celu”
##   tylko gdy cel bliżej niż pierwszy punkt, pomijanie pierwszego punktu zależne od widoczności, cel dopisany
##   tylko dla osiągalnego punktu końcowego,
## * Stepper::step (mw_actor._try_step): wejście na próg niższy niż sStepSizeUp (34 j.), zatrzymanie na wyższym,
## * drzwi obrotowe (mw_doors.gd): World::activateDoor/rotateDoor – 90° w 1 s, zamykanie, zatrzymanie na aktorze
##   w kierunku obrotu (AiAvoidDoor), brak zatrzymania, gdy drzwi odchodzą od aktora, wznowienie ruchu po
##   wczytaniu komórki, hasCollisionWithDoor.
## godot --headless --path godot -s res://tests/test_ai_mechanics.gd

const PG := preload("res://scripts/mw/mw_pathgrid.gd")
const ACTOR := preload("res://scripts/mw/mw_actor.gd")
const DOORS := preload("res://scripts/mw/mw_doors.gd")
const GS := preload("res://scripts/mw/mw_game_state.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

# --- siatka ścieżek ----------------------------------------------------------------------------------------

func _ship_grid():
	# dolny pokład (z −100), schody, górny pokład (z 100) – jak okręt więzienny
	var cell := {"pathgrid": {"points": [[0, 0, -100], [0, 400, -100], [0, 600, 0], [0, 800, 100], [200, 800, 100], [900, 900, 100]],
		"edges": [[0, 1], [1, 0], [1, 2], [2, 1], [2, 3], [3, 2], [3, 4], [4, 3]]}}
	return PG.from_cell(cell)

func _test_pathgrid() -> void:
	var g = _ship_grid()
	# z górnego pokładu na dolny: przez schody, nie „prosto” (cel jest niżej, punkty siatki bliżej niż cel)
	var p: Array = g.build_path(Vector3(10, 830, 100), Vector3(0, 30, -100), func(_a, _b): return true)
	var via_stairs := p.any(func(v): return (v as Vector3).is_equal_approx(Vector3(0, 600, 0)))
	check(p.size() >= 3 and via_stairs and (p.back() as Vector3).is_equal_approx(Vector3(0, 30, -100)),
		"pathgrid: droga między poziomami przez schody (%s)" % [p])
	# prosto do celu tylko, gdy start→cel krótsze niż start→pierwszy punkt
	var d: Array = g.build_path(Vector3(0, 100, -100), Vector3(0, 130, -100))
	check(d.size() == 1 and (d[0] as Vector3).is_equal_approx(Vector3(0, 130, -100)), "pathgrid: bliski cel – prosto (%s)" % [d])
	# pierwszy punkt za aktorem: pomijany przy widoczności drugiego, zostaje bez niej
	var from := Vector3(0, 200, -100)
	var seen: Array = g.build_path(from, Vector3(0, 820, 100), func(_a, _b): return true)
	var blind: Array = g.build_path(from, Vector3(0, 820, 100), func(_a, _b): return false)
	check(not (seen[0] as Vector3).is_equal_approx(Vector3(0, 0, -100)) and (blind[0] as Vector3).is_equal_approx(Vector3(0, 0, -100)),
		"pathgrid: pierwszy punkt pomijany tylko przy widoczności (%s / %s)" % [seen[0], blind[0]])
	# cel przy punkcie z innej składowej: punkt końcowy nie jest najbliższy celowi → cel niedopisany
	var u: Array = g.build_path(Vector3(0, 0, -100), Vector3(900, 905, 100))
	check(not u.is_empty() and not (u.back() as Vector3).is_equal_approx(Vector3(900, 905, 100)),
		"pathgrid: nieosiągalny cel nie jest dopisywany (%s)" % [u.back() if not u.is_empty() else null])

# --- stopnie ---------------------------------------------------------------------------------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = pos
	return b

func _step_case(ledge_units: float) -> float:
	var world := Node3D.new()
	root.add_child(world)
	var u := 1.0 / MWCoords.UNITS_PER_METER
	_box(world, Vector3(20, 1, 20), Vector3(0, -0.5, 0))                       # podłoga y = 0
	var h := ledge_units * u
	_box(world, Vector3(20, h, 10), Vector3(0, h / 2.0, -6.0))                 # próg od z = −1 w głąb
	var a: CharacterBody3D = ACTOR.new()
	a.capsule_radius = 0.35
	a.capsule_height = 1.8
	world.add_child(a)
	a.global_position = Vector3(0, 0.05, 0)        # początek aktora = stopy
	for i in 30:
		await physics_frame
	for i in 120:
		a.move_input = Vector2(0, -1)
		await physics_frame
	var y := a.global_position.y
	world.queue_free()
	await process_frame
	return y

func _test_steps() -> void:
	var u := 1.0 / MWCoords.UNITS_PER_METER
	var low := await _step_case(20.0)
	check(absf(low - 20.0 * u) < 0.08, "Stepper: próg 20 j. pokonany (wysokość %.3f m)" % low)
	var high := await _step_case(48.0)
	check(high < 0.1, "Stepper: próg 48 j. (> sStepSizeUp 34) zatrzymuje (wysokość %.3f m)" % high)

# --- drzwi -----------------------------------------------------------------------------------------------

class FakeDB:
	func get_object(_id: String) -> Dictionary:
		return {"type": "DOOR", "open_sound": "", "close_sound": ""}
	func get_cell(_key: String) -> Dictionary:
		return {"refs": [{"sid": "door#1", "base": "test_door", "mw": {"pos": [0, 0, 0], "rot": [0, 0, 0], "scale": 1.0}}]}

class FakeAI:
	var avoided: Array = []
	var nodes: Array = []
	func actor_nodes() -> Array:
		return nodes
	func avoid_door(n: Node, sid: String) -> void:
		avoided.append([n, sid])

class FakeMain:
	var state = GS.new()
	var db = FakeDB.new()
	var ai = FakeAI.new()
	var loaded := {}
	var player = null
	var audio = null
	func base_ref(_sid: String) -> Dictionary:
		return db.get_cell("").refs[0]

func _door_scene(fm) -> Node3D:
	var cell := Node3D.new()
	var refs := Node3D.new()
	refs.name = "Refs"
	cell.add_child(refs)
	root.add_child(cell)
	fm.loaded["int:test"] = cell
	var d := Node3D.new()
	d.set_meta("mw_sid", "door#1")
	d.set_meta("mw_base", "test_door")
	refs.add_child(d)
	# skrzydło: 1 m od zawiasu wzdłuż +X (Godot), grubość 0,1 m, wysokość 2 m
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 2.0, 0.1)
	cs.shape = sh
	cs.position = Vector3(0.5, 1.0, 0)
	b.add_child(cs)
	d.add_child(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	mi.mesh = bm
	mi.position = cs.position
	d.add_child(mi)
	return d

func _blocker(parent: Node, pos: Vector3) -> CharacterBody3D:
	var a := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.3, 1.8, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	a.add_child(cs)
	parent.add_child(a)
	a.global_position = pos
	return a

func _run_door(doors, frames: int) -> void:
	for i in frames:
		doors.process(1.0 / 60.0)
		await physics_frame

func _test_doors() -> void:
	var fm := FakeMain.new()
	var d := _door_scene(fm)
	var doors = DOORS.new(fm)
	await physics_frame
	doors.activate(d)
	check(doors.state_of("door#1") == DOORS.OPENING, "drzwi: aktywacja zamkniętych → otwieranie")
	await _run_door(doors, 30)
	var half: float = doors.current_rot("door#1").z
	check(absf(half - PI / 4.0) < 0.06, "drzwi: 90°/s (po 0,5 s %.3f rad)" % half)
	await _run_door(doors, 40)
	check(doors.state_of("door#1") == DOORS.IDLE and is_equal_approx(doors.current_rot("door#1").z, PI / 2.0) and doors.is_open("door#1"),
		"drzwi: otwarte o 90° i nieruchome (%.3f)" % doors.current_rot("door#1").z)
	# zamykanie (aktywacja otwartych) i przerwanie ruchu w trakcie
	doors.activate(d)
	check(doors.state_of("door#1") == DOORS.CLOSING, "drzwi: aktywacja otwartych → zamykanie")
	await _run_door(doors, 20)
	doors.activate(d)
	check(doors.state_of("door#1") == DOORS.OPENING, "drzwi: aktywacja w trakcie zamykania → otwieranie")
	await _run_door(doors, 40)
	doors.activate(d)
	await _run_door(doors, 80)
	check(doors.state_of("door#1") == DOORS.IDLE and not doors.is_open("door#1"), "drzwi: zamknięte z powrotem")
	# aktor po stronie, w którą skrzydło się obraca – drzwi stają, NPC dostaje AiAvoidDoor
	var leaf_before: Vector3 = doors._leaf_world("door#1", d, Vector3.ZERO)
	doors.activate(d)
	doors.process(1.0 / 60.0)
	var leaf_after: Vector3 = doors._leaf_world("door#1", d, doors.current_rot("door#1"))
	var sweep := signf(Vector2(leaf_before.x, leaf_before.y).angle_to(Vector2(leaf_after.x, leaf_after.y)))
	# punkt 0,6 m od zawiasu, 25° dalej w kierunku obrotu (MW → Godot)
	var ang := deg_to_rad(25.0) * sweep
	var mw_pt := Vector3(leaf_before.x, leaf_before.y, 0).normalized().rotated(Vector3(0, 0, 1), ang) * (0.6 * MWCoords.UNITS_PER_METER)
	var ahead := _blocker(d.get_parent(), MWCoords.mw_to_godot(mw_pt))
	fm.ai.nodes = [ahead]
	await _run_door(doors, 90)
	var r_block: float = doors.current_rot("door#1").z
	check(doors.state_of("door#1") == DOORS.OPENING and r_block < deg_to_rad(30.0), "drzwi: zatrzymane na aktorze (%.3f rad)" % r_block)
	check(not fm.ai.avoided.is_empty() and fm.ai.avoided[0][0] == ahead, "drzwi: NPC na drodze dostaje AiAvoidDoor")
	# aktor usunięty – drzwi kończą ruch; aktor za skrzydłem (drzwi odchodzą) nie blokuje zamykania od niego
	ahead.queue_free()
	fm.ai.nodes = []
	await _run_door(doors, 90)
	check(doors.state_of("door#1") == DOORS.IDLE and doors.is_open("door#1"), "drzwi: po zejściu aktora otwarte")
	# wznowienie: stan ruchu w stanie referencji → resume_cell po wczytaniu komórki
	doors.activate(d)
	doors.moving.clear()                       # jak po wyładowaniu komórki
	doors.resume_cell("int:test")
	check(doors.moving.has("door#1") and int(doors.moving["door#1"]) == DOORS.CLOSING, "drzwi: wznowienie ruchu po wczytaniu komórki")
	await _run_door(doors, 90)
	check(not doors.is_open("door#1"), "drzwi: wznowione zamykanie dokończone")
	# hasCollisionWithDoor: odcinek przez skrzydło / obok
	var u := MWCoords.UNITS_PER_METER
	var leaf: Vector3 = doors._leaf_world("door#1", d, Vector3.ZERO) * 0.5 * u
	var perp := Vector3(-leaf.y, leaf.x, 0).normalized() * 40.0
	var zz := Vector3(0, 0, 60)
	check(doors.on_the_way(d, leaf + perp + zz, leaf - perp + zz),
		"drzwi: odcinek przez skrzydło przecina drzwi")
	check(not doors.on_the_way(d, Vector3(300, 300, 60), Vector3(400, 300, 60)), "drzwi: odcinek obok nie przecina")
	d.get_parent().get_parent().queue_free()

func _run() -> void:
	_test_pathgrid()
	await _test_steps()
	await _test_doors()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)
