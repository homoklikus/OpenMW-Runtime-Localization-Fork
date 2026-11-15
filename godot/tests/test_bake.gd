extends SceneTree
## Wypieczone sceny vs GLB: ta sama struktura, tekstury skompresowane, czas wczytania.
## godot --headless --path godot -s res://tests/test_bake.gd -- --data=WYNIKI   (po tools/bake_models.gd)

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func count(n: Node, cls: String) -> int:
	return n.find_children("*", cls, true, false).size()

func _init() -> void:
	var data := arg("data")
	var fails := []
	var rep := {}
	var models := ["meshes/synth/test_hut.glb", "meshes/synth/test_windmill.glb", "meshes/synth/test_skinned.glb",
		"meshes/synth/hard_controllers.glb", "meshes/synth/hard_particles.glb", "meshes/synth/hard_nodes.glb"]
	var times := {"glb": 0.0, "baked": 0.0}
	for pass_name in ["glb", "baked"]:
		var c := MWModelCache.new(data)
		c.use_baked = pass_name == "baked"
		var t0 := Time.get_ticks_usec()
		for m in models:
			c.get_scene(m)
		times[pass_name] = (Time.get_ticks_usec() - t0) / 1000.0
		rep[pass_name + "_stats"] = c.stats
	for m in models:
		var a := MWModelCache.new(data)
		a.use_baked = false
		var b := MWModelCache.new(data)
		var na := a.instantiate(m)
		var nb := b.instantiate(m)
		for cls in ["MeshInstance3D", "AnimationPlayer", "CPUParticles3D", "StaticBody3D", "Skeleton3D"]:
			if count(na, cls) != count(nb, cls):
				fails.append("%s: różna liczba %s (%d vs %d)" % [m, cls, count(na, cls), count(nb, cls)])
		na.free()
		nb.free()
	var hut := MWModelCache.new(data).instantiate("meshes/synth/test_hut.glb")
	root.add_child(hut)
	var compressed := 0
	for mi in hut.find_children("*", "MeshInstance3D", true, false):
		var mat = (mi as MeshInstance3D).mesh.surface_get_material(0)
		if mat is BaseMaterial3D and mat.albedo_texture is PortableCompressedTexture2D:
			compressed += 1
	if compressed < 3:
		fails.append("tekstury wypieczone nieskompresowane (%d)" % compressed)
	if rep["baked_stats"].get("baked", 0) != models.size():
		fails.append("nie wszystkie modele z baked/ (%s)" % str(rep["baked_stats"]))
	rep["load_ms"] = times
	rep["compressed_textures_hut"] = compressed
	print("RESULT ", JSON.stringify({"failures": fails, "report": rep}))
	quit(0 if fails.is_empty() else 1)
