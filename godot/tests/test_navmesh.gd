extends SceneTree
## MWNavMesh: osobne mapy na przestrzeń świata, gotowość regionu po synchronizacji mapy, geometria sąsiadów.
## Regresja sondy nowej gry (wyjście ze statku więziennego): pierwsza droga po przejściu do świata zewnętrznego
## wiodła po starych wielokątach wnętrza ze wspólnej mapy, a kadłub z sąsiedniej komórki nie trafiał do siatki.
## godot --headless --path godot -s res://tests/test_navmesh.gd

const MAIN_SRC := """extends Node3D
var db = null
var loaded := {}
"""

var fails := []
var main: Node3D
var nav
const NavMesh := preload("res://scripts/mw/mw_navmesh.gd")

func _initialize() -> void:
	_run()

## Płyta kolizji (punkty MW): środek, rozmiar w jednostkach MW.
func _slab(parent: Node, center_mw: Vector3, size_mw: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_mw.x, size_mw.z, size_mw.y) / MWCoords.UNITS_PER_METER
	c.shape = box
	b.add_child(c)
	parent.add_child(b)
	b.global_position = MWCoords.mw_to_godot(center_mw)
	return b

func _cell(key: String) -> Node3D:
	var n := Node3D.new()
	n.name = key.replace(":", "_").replace(",", "_")
	main.add_child(n)
	main.loaded[key] = n
	return n

func _wait_baked(keys: Array, frames := 600) -> bool:
	for i in frames:
		await physics_frame
		var all := true
		for k in keys:
			if not nav.has_cell(k):
				all = false
		if all:
			return true
	return false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _run() -> void:
	var s := GDScript.new()
	s.source_code = MAIN_SRC
	s.reload()
	main = Node3D.new()
	main.set_script(s)
	root.add_child(main)
	nav = NavMesh.new(main)
	await process_frame

	# 1. wnętrze (przy początku układu, jak w Godocie) i komórka zewnętrzna 0,0
	var interior := _cell("int:test")
	_slab(interior, Vector3(0, 0, -8), Vector3(2000, 2000, 16))
	nav.bake_cell("int:test", interior)
	_check(not nav.has_cell("int:test"), "has_cell przed końcem wypieku")
	var ok_i: bool = await _wait_baked(["int:test"])
	_check(ok_i, "wnętrze nie wypieczone")
	_check(nav._map_for("int:test") != nav._map_for("ext:0,0"), "wnętrze i świat dzielą mapę nawigacji")
	_check(nav._map_for("int:test") == nav._map_for("int:test"), "mapa wnętrza niestała")
	_check(nav._map_for("int:inne") != nav._map_for("int:test"), "dwa wnętrza dzielą mapę")

	var ext := _cell("ext:0,0")
	_slab(ext, Vector3(4096, 4096, -8), Vector3(8000, 8000, 16))
	nav.bake_cell("ext:0,0", ext)
	var ok_e: bool = await _wait_baked(["ext:0,0"])
	_check(ok_e, "komórka zewnętrzna nie wypieczona")
	# zapytanie w świecie w okolicy, gdzie leży wnętrze, nie może prowadzić po jego wielokątach
	var r_far: Dictionary = nav.find_path("ext:0,0", Vector3(-500, -500, 0), Vector3(500, 500, 0))
	for p in r_far.path:
		_check((p as Vector3).x >= -10.0 and (p as Vector3).y >= -10.0,
			"droga w świecie po wielokątach wnętrza: %s" % str(p))
		break
	var r_in: Dictionary = nav.find_path("int:test", Vector3(-500, -500, 0), Vector3(500, 500, 0))
	_check(String(r_in.status) == "ok", "droga we wnętrzu: %s" % String(r_in.status))
	var em: RID = nav._map_for("ext:0,0")
	# gotowa komórka ⇒ mapa zna jej wielokąty (zapytanie nie trafia w pustą mapę po zmianie regionu)
	var cp0 := MWCoords.godot_to_mw(NavigationServer3D.map_get_closest_point(em, MWCoords.mw_to_godot(Vector3(1000, 1000, 0))))
	_check(cp0.distance_to(Vector3(1000, 1000, 0)) < 40.0, "has_cell przed synchronizacją mapy: %s" % str(cp0.round()))
	var r_ext: Dictionary = nav.find_path("ext:0,0", Vector3(1000, 1000, 0), Vector3(6000, 6000, 0))
	_check(String(r_ext.status) == "ok", "droga w świecie: %s %s" % [String(r_ext.status), str(r_ext.path.slice(-2))])

	# 2. zwolnione wnętrze nie odpowiada; świat nadal tak
	nav.clear_cell("int:test")
	_check(String(nav.find_path("int:test", Vector3(0, 0, 0), Vector3(100, 0, 0)).status) == "not_found",
		"zwolnione wnętrze nadal ma siatkę")

	# 3. obiekt sąsiedniej komórki (punkt odniesienia w 1,0) zachodzący na 0,0 trafia do siatki 0,0
	var nb := _cell("ext:1,0")
	_slab(nb, Vector3(8192 + 4096, 4096, -8), Vector3(8000, 8000, 16))
	_slab(nb, Vector3(8192 + 300, 2000, 240), Vector3(3000, 600, 16))     # pomost wchodzący do 0,0 aż do x≈6900
	nav.bake_cell("ext:1,0", nb)              # przebudowuje też wypieczonego sąsiada 0,0
	_check(nav.pending.has("ext:0,0"), "sąsiad 0,0 nie wypiekany ponownie po wczytaniu 1,0")
	_check(nav.has_cell("ext:0,0"), "stara siatka 0,0 usunięta przed końcem ponownego wypieku")
	await physics_frame
	var ok_n: bool = false
	for i in 600:
		await physics_frame
		if not nav.pending.has("ext:0,0") and not nav.pending.has("ext:1,0") and nav.has_cell("ext:0,0") and nav.has_cell("ext:1,0"):
			ok_n = true
			break
	_check(ok_n, "ponowny wypiek sąsiadów nie zakończony")
	var deck_pt := Vector3(7200, 2000, 248)
	var rid: RID = nav.regions["ext:0,0"]
	var cp := MWCoords.godot_to_mw(NavigationServer3D.region_get_closest_point(rid, MWCoords.mw_to_godot(deck_pt)))
	var on_deck := cp.distance_to(deck_pt) < 40.0
	_check(on_deck, "siatka 0,0 bez pomostu z komórki 1,0 (geometria sąsiada pominięta): %s" % str(cp.round()))

	nav.clear_all()
	print("RESULT ", JSON.stringify({"failures": fails, "bakes": nav.bakes}))
	quit(0 if fails.is_empty() else 1)
