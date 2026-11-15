extends RefCounted
## Roślinność (groundcover) – rysowanie roślin wyliczonych przez konwerter (mwconv/flora.py, port forka OpenMW RLF:
## groundcover z wtyczek, flora proceduralna, reguły Remirosa). Jak w OpenMW: bez kolizji, instancjonowane
## (MultiMesh na model i komórkę), wymuszony test alfa (próg 128/255), bez cieni, ograniczony zasięg widoczności.
##
## Plik world/flora/<x>_<y>.bin: "MWFL", u16 wersja, u32 N, zlib: kolumny u16 model, f32 x/y/z (MW),
## i16 rx/ry/rz (rad×10000), u16 skala×10000, u8 ranga, u8 źródło. Ranga pozwala zmniejszyć gęstość w grze.

const MWCoordsS := preload("res://scripts/mw/mw_coords.gd")

var models: MWModelCache
var roots: Array[String] = []
var index := {}
var distance := 90.0          # [m] – zasięg rysowania (OpenMW: [Groundcover] rendering distance)
var density := 1.0            # 0–1 – część roślin rysowana w grze (bez ponownej konwersji)
var stats := {"cells": 0, "instances": 0, "multimeshes": 0, "ms": 0.0}
var _parts := {}              # glb → [[Mesh, Transform3D]]

func _init(model_cache: MWModelCache, data_root: String, base_roots: Array = []) -> void:
	models = model_cache
	roots.append(data_root)
	for r in base_roots:
		roots.append(String(r))
	for r in roots:
		var p := r.path_join("world/flora/index.json")
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				index = j
				index["_root"] = r
			break

func is_active() -> bool:
	return not index.is_empty() and not index.get("cells", {}).is_empty()

func count_for(key: String) -> int:
	return int(index.get("cells", {}).get(key, {}).get("count", 0))

## Rośliny komórki: {indeks modelu: [Transform3D]} po zastosowaniu gęstości (pusty słownik, gdy brak).
func decode_cell(key: String) -> Dictionary:
	var c: Dictionary = index.get("cells", {}).get(key, {})
	if c.is_empty() or density <= 0.0:
		return {}
	var raw := FileAccess.get_file_as_bytes(String(index["_root"]).path_join("world/flora").path_join(String(c["file"])))
	if raw.size() < 10 or raw.slice(0, 4).get_string_from_ascii() != "MWFL":
		push_warning("Roślinność: uszkodzony plik %s" % c["file"])
		return {}
	var n := raw.decode_u32(6)
	var p := raw.slice(10).decompress(n * 24, FileAccess.COMPRESSION_DEFLATE)
	if p.size() < n * 24:
		push_warning("Roślinność: nie można rozpakować %s" % c["file"])
		return {}
	var o_m := 0
	var o_x := n * 2
	var o_y := o_x + n * 4
	var o_z := o_y + n * 4
	var o_rx := o_z + n * 4
	var o_ry := o_rx + n * 2
	var o_rz := o_ry + n * 2
	var o_s := o_rz + n * 2
	var o_rank := o_s + n * 2
	var limit := int(density * 256.0)
	var by_model := {}
	for i in n:
		if limit < 256 and p[o_rank + i] >= limit:
			continue
		var mi := p.decode_u16(o_m + i * 2)
		var mw := Vector3(p.decode_float(o_x + i * 4), p.decode_float(o_y + i * 4), p.decode_float(o_z + i * 4))
		var rot := Vector3(p.decode_s16(o_rx + i * 2), p.decode_s16(o_ry + i * 2), p.decode_s16(o_rz + i * 2)) / 10000.0
		var s := p.decode_u16(o_s + i * 2) / 10000.0
		var b := MWCoordsS.mw_rot_to_basis(rot).scaled(Vector3(s, s, s))
		if not by_model.has(mi):
			by_model[mi] = []
		by_model[mi].append(Transform3D(b, MWCoordsS.mw_to_godot(mw)))
	return by_model

## Węzeł „Flora” komórki (null, gdy brak roślin).
func build_cell(key: String) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var by_model := decode_cell(key)
	if by_model.is_empty():
		return null
	var n := count_for(key)
	var root := Node3D.new()
	root.name = "Flora"
	root.set_meta("mw_flora_count", n)
	var mlist: Array = index.get("models", [])
	for mi in by_model:
		if mi >= mlist.size():
			continue
		var parts := _model_parts(String(mlist[mi]["glb"]))
		var xs: Array = by_model[mi]
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = xs.size()
			var local: Transform3D = part[1]
			for k in xs.size():
				mm.set_instance_transform(k, xs[k] * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = distance
			mmi.visibility_range_end_margin = distance * 0.1
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			root.add_child(mmi)
			stats.multimeshes += 1
		stats.instances += xs.size()
	stats.cells += 1
	stats.ms += (Time.get_ticks_usec() - t0) / 1000.0
	return root

## Siatki modelu (bez kolizji i ukrytych węzłów) z transformacją względem korzenia; materiały jak w groundcover
## OpenMW: test alfa 128/255, bez mieszania, obie strony.
func _model_parts(glb: String) -> Array:
	if _parts.has(glb):
		return _parts[glb]
	var out := []
	var scene := models.instantiate(glb)
	if scene:
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree() or m.has_meta("mw_collision_only"):
				continue
			var mesh := _up_normals(m.mesh)
			for si in mesh.get_surface_count():
				var mat = mesh.surface_get_material(si)
				if mat is BaseMaterial3D:
					var bm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					bm.alpha_scissor_threshold = 128.0 / 255.0
					bm.cull_mode = BaseMaterial3D.CULL_BACK      # obie strony z _up_normals
					bm.disable_receive_shadows = true   # płaskie kępy tuż nad terenem łapały artefakty cienia
					# kolor wierzchołków w modelach Remirosa to znacznik wiatru MGE XE (np. kamienie: 0,1,1 = bez
					# kołysania), nie kolor – shader groundcover OpenMW go nie używa (wcześniej: turkusowe kamienie)
					bm.vertex_color_use_as_albedo = false
					mesh.surface_set_material(si, bm)
			out.append([mesh, _relative(m, scene)])
		scene.free()
	_parts[glb] = out
	return out

## Normalne „w górę” jak shader groundcover OpenMW (normal = vec3(0,0,1) w układzie MW): kępy są oświetlone
## równo z obu stron. Godot przy materiale dwustronnym odwraca normalną tylnej strony (czarne kępy), więc każdy
## trójkąt dostaje kopię o odwrotnym nawinięciu z tą samą normalną, a materiał rysuje tylko przednie strony.
static func _up_normals(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		arrays[Mesh.ARRAY_COLOR] = null      # znacznik wiatru MGE XE, nie kolor (patrz _model_parts)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if src.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES:
			if idx == null or (idx as PackedInt32Array).is_empty():
				idx = PackedInt32Array(range(verts.size()))
			var both := PackedInt32Array(idx)
			for t in range(0, idx.size() - 2, 3):
				both.append_array([idx[t], idx[t + 2], idx[t + 1]])
			arrays[Mesh.ARRAY_INDEX] = both
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), arrays)
		out.surface_set_material(si, src.surface_get_material(si))
	return out

static func _relative(n: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
