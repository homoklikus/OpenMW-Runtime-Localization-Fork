extends RefCounted
## Siatka nawigacji (navmesh) jak DetourNavigator w OpenMW (components/detournavigator): dla każdej wczytanej
## komórki wypiekana w tle z kolizji świata (bez aktorów i drzwi – NPC otwierają drzwi), parametry agenta
## i rastra z [Navigator] OpenMW (rozmiar komórki 0,2 × 34 j., wysokość stopnia 34 j., nachylenie 46°,
## maks. krawędź 12, błąd uproszczenia 1,3, próbkowanie 6/1, regiony 64/400, 6 wierzchołków na wielokąt).
## Zapytanie o drogę jak findPath: Success / PartialPath (koniec nie osiąga celu) / NavMeshNotFound (komórka
## jeszcze bez siatki) – wtedy AI używa siatki ścieżek (PathFinder::buildPath).

const UNITS := MWCoords.UNITS_PER_METER
const RECAST_SCALE := 1.0 / 34.0                 # recast scale factor
const CELL_SIZE := 0.2 / RECAST_SCALE           # 6,8 j.
const STEP_UP := 34.0                            # Constants::sStepSizeUp
const MAX_SLOPE := 46.0                          # sMaxSlope
const ACTOR_HALF := 0.35                         # połowa szerokości aktora (m) – prostopadłościan aktora (mw_actor)
# getAgentRadius dla CollisionShapeType::Aabb (domyślny kształt aktora w OpenMW): max(połowa x, y) × √2 – siatka
# omija przeszkody o promień opisany na prostopadłościanie, więc aktor przechodzi każdą drogą z siatki
const AGENT_RADIUS := ACTOR_HALF * 1.41421356
const AGENT_HEIGHT := 1.8

var main
var regions := {}             # klucz komórki → RID regionu
var pending := {}             # klucz → true (wypiekanie w toku)
var ready_iter := {}          # klucz → numer iteracji mapy, od którego region jest w niej widoczny
var enabled := true
var bakes := 0                # liczba ukończonych (testy, diagnostyka)
var _maps := {}               # przestrzeń świata → RID mapy nawigacji

func _init(game_main) -> void:
	main = game_main

## Przestrzeń świata komórki (jak osobny Navigator na worldspace w OpenMW): wszystkie komórki zewnętrzne dzielą
## jedną mapę, każde wnętrze ma własną – zapytanie o drogę w świecie nie trafia na wielokąty wnętrza (wnętrza
## leżą w Godocie przy początku układu, zewnętrze tysiące jednostek dalej), także zanim zwolniony region zniknie.
static func worldspace(key: String) -> String:
	return key if key.begins_with("int:") else "ext"

func _map_for(key: String) -> RID:
	var ws := worldspace(key)
	if ws == "ext":
		return main.get_world_3d().navigation_map
	if not _maps.has(ws):
		var m := NavigationServer3D.map_create()
		NavigationServer3D.map_set_up(m, Vector3.UP)
		NavigationServer3D.map_set_active(m, true)
		_maps[ws] = m
	return _maps[ws]

func _map() -> RID:
	return main.get_world_3d().navigation_map

func _navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = CELL_SIZE / UNITS
	nm.cell_height = CELL_SIZE / UNITS
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = AGENT_HEIGHT
	nm.agent_max_climb = STEP_UP / UNITS
	nm.agent_max_slope = MAX_SLOPE
	nm.edge_max_length = 12.0 * nm.cell_size
	nm.edge_max_error = 1.3
	nm.region_min_size = 8.0                     # 64 komórki (Godot podnosi do kwadratu)
	nm.region_merge_size = 20.0                  # 400
	nm.detail_sample_distance = 6.0
	nm.detail_sample_max_error = 1.0
	nm.vertices_per_polygon = 6
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 0xFFFFFFFF
	return nm

func _group(key: String) -> String:
	return "mw_nav_" + key.md5_text().substr(0, 12)

## Kolizje do wypieku: ciała statyczne bez drzwi i aktorów. Komórka zewnętrzna dostaje też kolizje wczytanych
## sąsiadów zachodzące na jej kwadrat (np. kadłub statku z komórki obok) – jak kafelki DetourNavigator, które
## zbierają wszystkie obiekty świata nachodzące na kafelek, niezależnie od komórki referencji.
func _tag(key: String, roots: Array) -> int:
	var g := _group(key)
	var count := 0
	var area := _ext_area(key)
	for root in roots:
		for b in (root as Node).find_children("*", "StaticBody3D", true, false):
			var ref := MWTravel.ref_of(b)
			if ref != null:
				if ref.has_meta("mw_actor"):
					continue
				var base := String(ref.get_meta("mw_base", ""))
				if String(main.db.get_object(base).get("type", "")) == "DOOR":
					continue
			if root != roots[0] and area.size != Vector3.ZERO and not area.has_point(b.global_position):
				continue
			b.add_to_group(g)
			count += 1
	return count

## Kwadrat komórki zewnętrznej (Godot) poszerzony o NEIGHBOR_REACH: obiekty sąsiadów z punktem odniesienia w tym
## obszarze mogą zachodzić na komórkę (duże modele – statki, mury). Pusty dla wnętrz.
const NEIGHBOR_REACH := 2048.0

func _ext_area(key: String) -> AABB:
	if key.begins_with("int:"):
		return AABB()
	var g := key.substr(4).split(",")
	if g.size() != 2:
		return AABB()
	var x0 := float(g[0]) * 8192.0 - NEIGHBOR_REACH
	var y0 := float(g[1]) * 8192.0 - NEIGHBOR_REACH
	var w := 8192.0 + 2.0 * NEIGHBOR_REACH
	var a := MWCoords.mw_to_godot(Vector3(x0, y0 + w, -20000.0))
	var b := MWCoords.mw_to_godot(Vector3(x0 + w, y0, 20000.0))
	return AABB(Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)), (b - a).abs())

## Wczytane komórki zewnętrzne sąsiadujące z kluczem (siatka 3 × 3).
func _neighbors(key: String) -> Array:
	var out := []
	if key.begins_with("int:") or main.get("loaded") == null:
		return out
	var g := key.substr(4).split(",")
	if g.size() != 2:
		return out
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var k := "ext:%d,%d" % [int(g[0]) + dx, int(g[1]) + dy]
			if main.loaded.has(k) and is_instance_valid(main.loaded[k]):
				out.append(k)
	return out

## Wypiek w tle dla wczytanej komórki (wywołuje main._load). Nowa komórka zewnętrzna zmienia też geometrię
## kwadratów sąsiadów (jej obiekty mogą na nie zachodzić) – ich siatki są wypiekane ponownie.
func bake_cell(key: String, root: Node3D, rebake_neighbors := true) -> void:
	if not enabled or root == null:
		return
	if rebake_neighbors:
		clear_cell(key)                      # nowa komórka; ponowny wypiek sąsiada zostawia starą siatkę do końca
	var roots: Array = [root]
	for k in _neighbors(key):
		roots.append(main.loaded[k])
	if _tag(key, roots) == 0:
		return
	var nm := _navmesh()
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nm.geometry_source_group_name = _group(key)
	if not key.begins_with("int:"):
		# komórka zewnętrzna: tylko jej kwadrat (z marginesem na łączenie krawędzi sąsiednich siatek)
		var g := key.substr(4).split(",")
		if g.size() == 2:
			var x0 := float(g[0]) * 8192.0
			var y0 := float(g[1]) * 8192.0
			var a := MWCoords.mw_to_godot(Vector3(x0, y0 + 8192.0, -20000.0))
			var b := MWCoords.mw_to_godot(Vector3(x0 + 8192.0, y0, 20000.0))
			nm.filter_baking_aabb = AABB(Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)), (b - a).abs())
			nm.border_size = 16.0 * nm.cell_size
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, main if roots.size() > 1 else root)
	pending[key] = [nm, src]                  # zasoby muszą żyć do końca wypieku w tle
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _baked.bind(key, nm))
	if rebake_neighbors:
		for k in _neighbors(key):
			if regions.has(k) or pending.has(k):
				bake_cell(k, main.loaded[k], false)

func _baked(key: String, nm: NavigationMesh) -> void:
	if not pending.has(key) or pending[key][0] != nm:
		return                                   # komórka zwolniona albo wypiekana od nowa
	pending.erase(key)
	var m := _map_for(key)
	if regions.has(key):
		NavigationServer3D.free_rid(regions[key])
	NavigationServer3D.map_set_cell_size(m, nm.cell_size)
	NavigationServer3D.map_set_cell_height(m, nm.cell_height)
	var r := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(r, m)
	NavigationServer3D.region_set_navigation_mesh(r, nm)
	regions[key] = r
	# region staje się widoczny w zapytaniach dopiero po synchronizacji mapy; przy asynchronicznych iteracjach
	# (navigation/3d/use_async_iterations, domyślnie włączone) budowa trwająca w chwili zmiany kończy się
	# iteracją bez regionu – pewna jest dopiero druga kolejna (test_navmesh)
	ready_iter[key] = NavigationServer3D.map_get_iteration_id(m) + 2
	bakes += 1

func clear_cell(key: String) -> void:
	pending.erase(key)
	ready_iter.erase(key)
	if regions.has(key):
		NavigationServer3D.free_rid(regions[key])
		regions.erase(key)

func clear_all() -> void:
	for k in regions.keys():
		clear_cell(k)
	pending.clear()
	for ws in _maps:
		NavigationServer3D.free_rid(_maps[ws])
	_maps.clear()

func has_cell(key: String) -> bool:
	return regions.has(key) and NavigationServer3D.map_get_iteration_id(_map_for(key)) >= int(ready_iter.get(key, 0))

## findPath (punkty MW): {"status": "ok" | "partial" | "not_found", "path": [Vector3]}.
func find_path(cell_key: String, from_mw: Vector3, to_mw: Vector3) -> Dictionary:
	# NavMeshNotFound: komórka bez siatki albo region jeszcze niezsynchronizowany z mapą (świeży wypiek / wymiana)
	if not enabled or not has_cell(cell_key):
		return {"status": "not_found", "path": []}
	var m := _map_for(cell_key)
	if NavigationServer3D.map_get_iteration_id(m) == 0:
		return {"status": "not_found", "path": []}
	var pts := NavigationServer3D.map_get_path(m, MWCoords.mw_to_godot(from_mw), MWCoords.mw_to_godot(to_mw), true)
	if pts.is_empty():
		return {"status": "partial", "path": []}
	var out: Array = []
	for p in pts:
		out.append(MWCoords.godot_to_mw(p))
	var last: Vector3 = out.back()
	var horiz := Vector2(last.x - to_mw.x, last.y - to_mw.y).length()
	var partial := horiz > 32.0 or absf(last.z - to_mw.z) > AGENT_HEIGHT * UNITS
	return {"status": "partial" if partial else "ok", "path": out}

## IsValidShortcut: odcinek bez załamań po siatce (droga z dwóch punktów kończąca się w celu).
func valid_shortcut(cell_key: String, a: Vector3, b: Vector3) -> bool:
	var r := find_path(cell_key, a, b)
	return String(r.status) == "ok" and (r.path as Array).size() <= 2
