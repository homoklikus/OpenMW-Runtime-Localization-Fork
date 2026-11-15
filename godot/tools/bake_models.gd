extends SceneTree
## Wypiekanie modeli GLB → natywne sceny Godota (.scn) z teksturami skompresowanymi pod GPU.
## Uruchamiane LOKALNIE u gracza (naszym binarnym Godotem w trybie headless), wynik nie opuszcza komputera.
##   godot --headless --path godot -s res://tools/bake_models.gd -- --data=WYNIKI [--out=WYNIKI/baked]
##        [--compress=s3tc|bptc|etc2|astc|lossless] [--only=meshes/x/...glb]
## Każda tekstura jest zapisywana raz (deduplikacja wg zawartości) jako .res i współdzielona przez sceny.

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

var tex_saved := {}   # hash obrazu → ścieżka .res
var stats := {"models": 0, "failed": 0, "textures": 0, "texture_reuse": 0, "ms": 0.0, "bytes_scn": 0, "bytes_tex": 0}

func _init() -> void:
	var data := arg("data")
	var out := arg("out", data.path_join("baked"))
	var mode := arg("compress", "s3tc")
	var only := arg("only")
	var list := arg("list")  # plik z listą GLB (po jednym w linii) – wypiekanie przyrostowe
	var cache := MWModelCache.new(data)
	cache.use_baked = false  # zawsze ze świeżego GLB – inaczej ponowne wypiekanie powielało starą scenę
	var files: Array[String] = []
	if not list.is_empty():
		for line in FileAccess.get_file_as_string(list).split("\n"):
			if line.strip_edges() != "":
				files.append(line.strip_edges())
	elif only.is_empty():
		_find(data.path_join("meshes"), "meshes", files)
	else:
		files.append(only)
	var t0 := Time.get_ticks_msec()
	for rel in files:
		var ps := cache.get_scene(rel)
		if ps == null:
			stats.failed += 1
			continue
		var root := ps.instantiate()
		_bake_textures(root, out, mode)
		MWModelCache._own(root, root)
		var baked := PackedScene.new()
		baked.pack(root)
		var dst := out.path_join(rel.get_basename() + ".scn")
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		if ResourceSaver.save(baked, dst, ResourceSaver.FLAG_COMPRESS) == OK:
			stats.models += 1
			stats.bytes_scn += FileAccess.get_file_as_bytes(dst).size()
		else:
			stats.failed += 1
		root.free()
	stats.ms = Time.get_ticks_msec() - t0
	print("BAKE ", JSON.stringify(stats))
	quit(0 if stats.failed == 0 else 1)

func _find(dir: String, rel: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".glb"):
			out.append(rel.path_join(f))
	for sub in d.get_directories():
		_find(dir.path_join(sub), rel.path_join(sub), out)

func _bake_textures(root: Node, out: String, mode: String) -> void:
	var mats: Array[BaseMaterial3D] = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			for mat in [m.mesh.surface_get_material(s), m.get_surface_override_material(s)]:
				if mat is BaseMaterial3D and not mats.has(mat):
					mats.append(mat)
	for cp in root.find_children("*", "CPUParticles3D", true, false):
		var pm := (cp as CPUParticles3D).mesh
		if pm and pm.surface_get_material(0) is BaseMaterial3D:
			mats.append(pm.surface_get_material(0))
	for bm in mats:
		for prop in ["albedo_texture", "emission_texture", "normal_texture", "detail_albedo"]:
			var t = bm.get(prop)
			if t is Texture2D and not (t is PortableCompressedTexture2D):
				var nt := _compress(t, out, mode)
				if nt:
					bm.set(prop, nt)

func _compress(t: Texture2D, out: String, mode: String) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var key := str(hash(img.get_data())) + "_%dx%d" % [img.get_width(), img.get_height()]
	var path := out.path_join("textures").path_join(key + ".res")
	if tex_saved.has(key) or FileAccess.file_exists(path):
		stats.texture_reuse += 1
		tex_saved[key] = path
		return load(path)
	if not img.has_mipmaps():
		img.generate_mipmaps()
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var pct := PortableCompressedTexture2D.new()
	pct.keep_compressed_buffer = true
	var cm: int = {"s3tc": PortableCompressedTexture2D.COMPRESSION_MODE_S3TC,
		"bptc": PortableCompressedTexture2D.COMPRESSION_MODE_BPTC,
		"etc2": PortableCompressedTexture2D.COMPRESSION_MODE_ETC2,
		"astc": PortableCompressedTexture2D.COMPRESSION_MODE_ASTC,
		"lossless": PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS}.get(mode, PortableCompressedTexture2D.COMPRESSION_MODE_S3TC)
	pct.create_from_image(img, cm)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if ResourceSaver.save(pct, path) != OK:
		return null
	stats.textures += 1
	stats.bytes_tex += FileAccess.get_file_as_bytes(path).size()
	tex_saved[key] = path
	return load(path)
