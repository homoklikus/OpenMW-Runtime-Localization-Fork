class_name MWModelCache
extends RefCounted
## Wczytywanie modeli GLB w czasie działania (GLTFDocument) z katalogu danych gracza.
## Wyeksportowana gra nie może importować zasobów edytorem, dlatego przekonwertowane dane
## (poza res://) ładujemy dynamicznie i przetwarzamy wg znaczników `extras` z konwertera:
##   mw_collision → kolizja (StaticBody3D), bez siatki widocznej
##   mw_hidden    → węzeł ukryty
##   mw_blend_mode / mw_cull / mw_billboard → ustawienia materiałów

var data_root: String
var _cache := {}           # glb_rel → PackedScene (lub null przy błędzie)
var stats := {"loaded": 0, "failed": 0, "load_ms": 0.0, "instances": 0}
var errors: Array[String] = []

func _init(root: String) -> void:
	data_root = root

func get_scene(glb_rel: String) -> PackedScene:
	if _cache.has(glb_rel):
		return _cache[glb_rel]
	var t0 := Time.get_ticks_usec()
	var path := data_root.path_join(glb_rel)
	var ps: PackedScene = null
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(path, state)
		if err == OK:
			var root := doc.generate_scene(state)
			if root:
				postprocess(root)
				_own(root, root)
				ps = PackedScene.new()
				if ps.pack(root) != OK:
					ps = null
				root.free()
		else:
			errors.append("%s: błąd GLTF %d" % [glb_rel, err])
	else:
		errors.append("%s: brak pliku" % glb_rel)
	stats.load_ms += (Time.get_ticks_usec() - t0) / 1000.0
	if ps:
		stats.loaded += 1
	else:
		stats.failed += 1
	_cache[glb_rel] = ps
	return ps

func instantiate(glb_rel: String) -> Node3D:
	var ps := get_scene(glb_rel)
	if ps == null:
		return null
	stats.instances += 1
	return ps.instantiate() as Node3D

static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)

static func extras_of(n: Object) -> Dictionary:
	if n.has_meta("extras"):
		var e = n.get_meta("extras")
		if e is Dictionary:
			return e
	return {}

## Przetwarzanie sceny wygenerowanej z GLB (wywoływane raz na model).
static func postprocess(root: Node) -> void:
	var st := {"has_collision": false}  # lambdy GDScript przechwytują zmienne przez wartość
	var meshes: Array[MeshInstance3D] = []
	_walk(root, func(n: Node):
		if n is MeshInstance3D:
			meshes.append(n)
		if extras_of(n).get("mw_collision", false):
			st.has_collision = true
	)
	var has_collision: bool = st.has_collision
	for mi in meshes:
		var ex := extras_of(mi)
		var collision: bool = ex.get("mw_collision", false)
		if not collision and mi.mesh:
			var mex := extras_of(mi.mesh)
			collision = mex.get("mw_collision", false)
		if collision:
			_add_static_collision(mi)
			mi.visible = false
			mi.set_meta("mw_collision_only", true)
			continue
		if ex.get("mw_hidden", false):
			mi.visible = false
		_fix_materials(mi, ex)
		if not has_collision and mi.visible and mi.skin == null:
			# brak RootCollisionNode ⇒ kolizja z całej widocznej geometrii (jak w grze)
			_add_static_collision(mi)
	_walk(root, func(n: Node):
		if n is Node3D and not (n is MeshInstance3D) and extras_of(n).get("mw_hidden", false):
			(n as Node3D).visible = false
	)

static func _walk(n: Node, f: Callable) -> void:
	f.call(n)
	for c in n.get_children():
		_walk(c, f)

static func _add_static_collision(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var shape := mi.mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)

static func _fix_materials(mi: MeshInstance3D, node_extras: Dictionary) -> void:
	if mi.mesh == null:
		return
	var billboard: bool = false
	var p := mi.get_parent()
	while p:
		if extras_of(p).get("mw_billboard", false):
			billboard = true
			break
		p = p.get_parent()
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if not (m is BaseMaterial3D):
			continue
		var bm := m as BaseMaterial3D
		var ex := extras_of(bm)
		var bmode: String = ex.get("mw_blend_mode", "")
		if bmode.ends_with("/ONE"):
			bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		if ex.get("mw_cull", "") == "front":
			bm.cull_mode = BaseMaterial3D.CULL_FRONT
		if ex.has("mw_alpha") and ex["mw_alpha"].get("test", false):
			bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
		if billboard:
			bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Morrowind nie używa PBR: brak odbić, pełna szorstkość
		bm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if not ex.get("mw_specular_enabled", false) else BaseMaterial3D.SPECULAR_SCHLICK_GGX
