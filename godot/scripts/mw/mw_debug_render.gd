extends Node3D
## Tryby renderowania debugowego OpenMW (RenderingManager::toggleRenderMode, ToggleBorders) w porcie:
##  * Render_Pathgrid (TogglePathGrid, tpg) – SceneUtil::createPathgridGeometry: romby 32 × 80 j. w punktach siatki
##    ścieżek (kolory DiamondColors), krawędzie między łącznikami rombów (DiamondEdgeColor);
##  * Render_CollisionDebug (ToggleCollisionBoxes / ToggleCollisionGrid, tcb / tcg) – kształty kolizji wczytanych
##    komórek i aktorów (MWPhysics DebugDrawer – siatki kształtów fizyki);
##  * ToggleBorders (tb) – Terrain::CellBorder: linia łamana 2 × 40 odcinków wzdłuż południowej i wschodniej krawędzi
##    każdej wczytanej komórki zewnętrznej, 10 j. nad terenem, na zmianę czarna i żółta.
## Przebudowa przy zmianie wczytanych komórek (addCell/removeCell).

const DIAMOND_HALF_HEIGHT := 40.0
const DIAMOND_HALF_WIDTH := 16.0
const DIAMOND_POINTS := [Vector3(0, 0, 80), Vector3(-16, -16, 40), Vector3(-16, 16, 40), Vector3(16, -16, 40),
	Vector3(16, 16, 40), Vector3(0, 0, 0)]
const DIAMOND_INDICES := [0, 2, 1, 0, 1, 3, 0, 3, 4, 0, 4, 2, 5, 1, 2, 5, 3, 1, 5, 4, 3, 5, 2, 4]
const DIAMOND_COLORS := [Color(0, 0, 1), Color(0, .05, .95), Color(0, .1, .95), Color(0, .15, .95), Color(0, .2, .95),
	Color(0, .25, 1)]
const EDGE_COLOR := Color(0.5, 1, 1)
const CONNECTORS := [1, 2, 3, 4]

var main
var pathgrid := false
var collision := false
var borders := false
var _cells_sig := ""
var _shapes: Array = []              # [MeshInstance3D, CollisionShape3D] – ruchome kształty (aktorzy) co klatkę

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func toggle(kind: String) -> bool:
	match kind:
		"pathgrid":
			pathgrid = not pathgrid
		"collision":
			collision = not collision
		"borders":
			borders = not borders
	rebuild()
	return bool(get(kind))

func any_enabled() -> bool:
	return pathgrid or collision or borders

func _process(_dt: float) -> void:
	if not any_enabled() or main == null:
		return
	var sig := ",".join((main.loaded as Dictionary).keys())
	if sig != _cells_sig:
		rebuild()
	for pair in _shapes:
		if is_instance_valid(pair[1]) and is_instance_valid(pair[0]):
			(pair[0] as Node3D).global_transform = (pair[1] as Node3D).global_transform

func rebuild() -> void:
	for c in get_children():
		c.free()
	_shapes.clear()
	_cells_sig = ",".join((main.loaded as Dictionary).keys()) if main != null else ""
	if main == null:
		return
	for key in main.loaded:
		var cell: Dictionary = main.db.get_cell(key)
		if pathgrid:
			_add_pathgrid(cell)
		if borders and not String(key).begins_with("int:") and cell.get("terrain") != null:
			_add_border(cell)
	if collision:
		_add_collision()

func _mw(v: Vector3) -> Vector3:
	return MWCoords.mw_to_godot(v)

func _add_pathgrid(cell: Dictionary) -> void:
	var pg: Dictionary = cell.get("pathgrid", {})
	var pts: Array = pg.get("points", [])
	if pts.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in pts:
		var base := Vector3(float(p[0]), float(p[1]), float(p[2]))
		for i in DIAMOND_INDICES:
			st.set_color(DIAMOND_COLORS[i])
			st.add_vertex(_mw(base + DIAMOND_POINTS[i]))
	var mi := MeshInstance3D.new()
	mi.name = "Pathgrid"
	mi.mesh = st.commit()
	mi.material_override = _material()
	add_child(mi)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_LINES)
	var n := 0
	for e in pg.get("edges", []):
		var a := int(e[0])
		var b := int(e[1])
		if a == b or a < 0 or b < 0 or a >= pts.size() or b >= pts.size():
			continue
		var pa := Vector3(float(pts[a][0]), float(pts[a][1]), float(pts[a][2]))
		var pb := Vector3(float(pts[b][0]), float(pts[b][1]), float(pts[b][2]))
		var d := (pb - pa).normalized()
		d = Vector3(d.y, -d.x, d.z)                     # osg::Quat(−π/2, Z) * dir
		var di := 0
		if d.y >= 0 and d.x > 0:
			di = 3
		elif d.x <= 0 and d.y > 0:
			di = 1
		elif d.y <= 0 and d.x < 0:
			di = 0
		elif d.x >= 0 and d.y < 0:
			di = 2
		var off: Vector3 = DIAMOND_POINTS[CONNECTORS[di]]
		lines.set_color(EDGE_COLOR)
		lines.add_vertex(_mw(pa + off))
		lines.set_color(EDGE_COLOR)
		lines.add_vertex(_mw(pb + off))
		n += 1
	if n > 0:
		var li := MeshInstance3D.new()
		li.name = "PathgridEdges"
		li.mesh = lines.commit()
		li.material_override = _material()
		add_child(li)

func _add_border(cell: Dictionary) -> void:
	var t: Dictionary = main.db.get_terrain(cell["terrain"])
	if t.is_empty():
		return
	var g: Array = cell.get("grid", [0, 0])
	var o: Array = t["origin_godot"]
	var origin := Vector3(o[0], o[1], o[2])
	var size := float(MWCoords.CELL_SIZE)
	var corner := Vector3(float(g[0]) * size, float(g[1]) * size, 0.0)
	var segs := 40
	var step := size / float(segs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(0, 2 * segs + 1):
		var p := Vector3(i * step, 0, 0) if i < segs else Vector3(size, (i - segs) * step, 0)
		var gp := _mw(corner + p)
		gp.y = MWTerrain.height_at(t, gp - origin) + 10.0 / MWCoords.UNITS_PER_METER
		st.set_color(Color(0, 0, 0) if i % 2 == 0 else Color(1, 1, 0))
		st.add_vertex(gp)
	var mi := MeshInstance3D.new()
	mi.name = "CellBorder"
	mi.mesh = st.commit()
	mi.material_override = _material()
	add_child(mi)

func _add_collision() -> void:
	var mat := _material()
	mat.albedo_color = Color(1, 1, 1)
	for cs in main.get_tree().root.find_children("*", "CollisionShape3D", true, false):
		var c := cs as CollisionShape3D
		if c.shape == null or c.disabled:
			continue
		var mesh := c.shape.get_debug_mesh()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Collision"
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		mi.global_transform = c.global_transform
		_shapes.append([mi, c])
