extends SceneTree
## Zrzut ekranu: modele testowe albo komórki świata.
## godot --path godot --rendering-driver opengl3 -s res://tests/render_shot.gd -- --data=DIR --out=plik.png [--mode=models|world]
##   [--cam=x,y,z] [--look=x,y,z] [--size=1280x720]

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func vec(s: String, def: Vector3) -> Vector3:
	if s.is_empty():
		return def
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _init() -> void:
	var data := arg("data")
	var out := arg("out", "/tmp/shot.png")
	var mode := arg("mode", "models")
	var sz := arg("size", "1280x720").split("x")
	root.size = Vector2i(int(sz[0]), int(sz[1]))
	var scene := Node3D.new()
	root.add_child(scene)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	scene.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 60
	scene.add_child(cam)

	if mode == "launcher":
		scene.queue_free()
		var l := (load("res://launcher.tscn") as PackedScene).instantiate()
		root.add_child(l)
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out)
		print("SHOT ", out)
		quit(0)
		return
	if mode == "effects":
		var cache := MWModelCache.new(data)
		var items := [["meshes/synth/hard_particles.glb", Vector3(-2, 0, 0), 0.6], ["meshes/synth/hard_controllers.glb", Vector3(2, 0, 0), 1.0],
			["meshes/synth/hard_nodes.glb", Vector3(0, 0, -6), 0.0]]
		for it in items:
			var n := cache.instantiate(it[0])
			n.position = it[1]
			scene.add_child(n)
		var water := MWEnvironment.water_plane(30.0, -0.05)
		scene.add_child(water)
		cam.position = Vector3(0, 3.5, 7)
		cam.look_at_from_position(cam.position, Vector3(0, 0.8, -1))
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out)
		print("SHOT ", out)
		quit(0)
		return
	if mode == "models":
		var cache := MWModelCache.new(data)
		var items := [
			["meshes/synth/test_hut.glb", Vector3(0, 0, 0)],
			["meshes/synth/test_windmill.glb", Vector3(6, 0, -2)],
			["meshes/synth/test_skinned.glb", Vector3(-4, 0, 1)],
			["meshes/synth/test_crate.glb", Vector3(-2.5, 0, 3)],
		]
		for it in items:
			var n := cache.instantiate(it[0])
			if n:
				n.position = it[1]
				scene.add_child(n)
				var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if ap and ap.get_animation_list().size() > 0:
					ap.play(ap.get_animation_list()[0])
					ap.seek(0.5, true)
					ap.pause()
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(30, 30)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.35, 0.4, 0.3)
		ground.material_override = gm
		scene.add_child(ground)
		cam.position = vec(arg("cam"), Vector3(1.5, 4.5, 11))
		cam.look_at_from_position(cam.position, vec(arg("look"), Vector3(1, 2, 0)))
	else:
		var db := MWWorldDB.new(data, arg("project", ""))
		var builder := MWCellBuilder.new(db, MWModelCache.new(data))
		for c in db.cell_index():
			if c.get("interior", false):
				continue
			var cn := builder.build_cell(c["key"])
			if cn:
				scene.add_child(cn)
		cam.far = 2000
		cam.position = vec(arg("cam"), Vector3(60, 60, -100))
		cam.look_at_from_position(cam.position, vec(arg("look"), Vector3(117, 5, -117)))

	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out, " ", img.get_size())
	quit(0)
