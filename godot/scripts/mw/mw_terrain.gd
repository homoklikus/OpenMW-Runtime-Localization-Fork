class_name MWTerrain
extends RefCounted
## Budowa siatki, materiału i kolizji terenu komórki z pliku world/terrain/<x>_<y>.json.

const SHADER := preload("res://shaders/mw_terrain.gdshader")
const LAYER_SIZE := 256
static var _array_cache := {}  # paleta → Texture2DArray

static func build(t: Dictionary, data_root: String, with_collision := true) -> Node3D:
	if t.is_empty() or t.get("heights_f32_b64") == null:
		return null
	var n: int = t["size"]
	var sp: float = t["spacing_m"]
	var h := Marshalls.base64_to_raw(t["heights_f32_b64"]).to_float32_array()
	var normals := PackedByteArray()
	if t.has("normals_i8_b64"):
		normals = Marshalls.base64_to_raw(t["normals_i8_b64"])
	var colors := PackedByteArray()
	if t.has("colors_u8_b64"):
		colors = Marshalls.base64_to_raw(t["colors_u8_b64"])

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	uvs.resize(n * n)
	for j in n:
		for i in n:
			var k := j * n + i
			verts[k] = Vector3(i * sp, h[k], -j * sp)
			if normals.size() >= 3 * n * n:
				var nx := normals.decode_s8(3 * k) / 127.0
				var ny := normals.decode_s8(3 * k + 1) / 127.0
				var nz := normals.decode_s8(3 * k + 2) / 127.0
				norms[k] = Vector3(nx, ny, nz).normalized()
			else:
				norms[k] = Vector3.UP
			if colors.size() >= 3 * n * n:
				cols[k] = Color8(colors[3 * k], colors[3 * k + 1], colors[3 * k + 2])
			else:
				cols[k] = Color.WHITE
			uvs[k] = Vector2(float(i) / (n - 1), float(j) / (n - 1))
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# wzór „diamond” jak w grze: (x+y) parzyste ⇒ przekątna a–d, nieparzyste ⇒ b–c.
			# Godot: przednie ściany zgodnie z ruchem wskazówek zegara (patrząc z góry)
			if (i + j) % 2 == 0:
				idx.append_array([a, c, d, a, d, b])
			else:
				idx.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material(t, data_root))

	var o: Array = t["origin_godot"]
	var root := Node3D.new()
	root.name = "Terrain_%d_%d" % [t["grid"][0], t["grid"][1]]
	root.position = Vector3(o[0], o[1], o[2])
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root.add_child(mi)
	if with_collision:
		var body := StaticBody3D.new()
		body.name = "Collision"
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		root.add_child(body)
	return root

static func _material(t: Dictionary, data_root: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var palette: Array = t.get("texture_palette", [])
	if palette.is_empty():
		palette = [""]
	var key := "|".join(palette)
	if not _array_cache.has(key):
		var imgs: Array[Image] = []
		for p in palette:
			var img: Image = null
			if not String(p).is_empty():
				img = Image.load_from_file(data_root.path_join(p))
			if img == null:
				img = Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
				img.fill(Color(0.5, 0.5, 0.45))
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != LAYER_SIZE or img.get_height() != LAYER_SIZE:
				img.resize(LAYER_SIZE, LAYER_SIZE, Image.INTERPOLATE_BILINEAR)
			img.generate_mipmaps()
			imgs.append(img)
		var arr := Texture2DArray.new()
		arr.create_from_images(imgs)
		_array_cache[key] = arr
	m.set_shader_parameter("layers", _array_cache[key])
	m.set_shader_parameter("layer_count", float(palette.size()))
	if t.has("texture_grid_u8_b64"):
		var raw := Marshalls.base64_to_raw(t["texture_grid_u8_b64"])
		var im := Image.create_from_data(16, 16, false, Image.FORMAT_R8, raw)
		m.set_shader_parameter("index_map", ImageTexture.create_from_image(im))
	return m

## Wysokość terenu (m) w punkcie lokalnym komórki – triangulacja taka jak siatki.
static func height_at(t: Dictionary, local: Vector3) -> float:
	var n: int = t["size"]
	var sp: float = t["spacing_m"]
	var h := Marshalls.base64_to_raw(t["heights_f32_b64"]).to_float32_array()
	var fx := clampf(local.x / sp, 0, n - 1.001)
	var fy := clampf(-local.z / sp, 0, n - 1.001)
	var i := int(fx)
	var j := int(fy)
	var u := fx - i
	var v := fy - j
	var ha := h[j * n + i]
	var hb := h[j * n + i + 1]
	var hc := h[(j + 1) * n + i]
	var hd := h[(j + 1) * n + i + 1]
	if (i + j) % 2 == 0:  # przekątna a–d
		if u >= v:
			return ha + (hb - ha) * u + (hd - hb) * v
		return ha + (hc - ha) * v + (hd - hc) * u
	if u + v <= 1.0:  # przekątna b–c
		return ha + (hb - ha) * u + (hc - ha) * v
	return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)
