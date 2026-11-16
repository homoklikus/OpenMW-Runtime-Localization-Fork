extends Node3D
## Diagnostyka wyglądu NPC (etap 2): porównuje pozycje węzłów szkieletu z GLB (jak w imporcie) z naszym Skeleton3D
## i wypisuje części ciała. Argumenty jak w grze (--data, --npc) albo [mwgodot] cli/* w override.cfg.
## godot --path godot res://tools/actor_dump.tscn -- --data=… --npc=fargoth

const ActorVisual := preload("res://scripts/mw/mw_actor_visual.gd")

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	var ps := "mwgodot/cli/" + name
	return str(ProjectSettings.get_setting(ps)) if ProjectSettings.has_setting(ps) else def

func _globals(n: Node, acc: Transform3D, out: Dictionary) -> void:
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		for b in sk.get_bone_count():
			out[sk.get_bone_name(b)] = acc * sk.transform * sk.get_bone_global_rest(b)
		for c in n.get_children():
			if c is BoneAttachment3D:
				var bi := sk.find_bone((c as BoneAttachment3D).bone_name)
				for cc in c.get_children():
					_globals(cc, acc * sk.transform * sk.get_bone_global_rest(bi), out)
		return
	if n is Node3D:
		var t := acc * (n as Node3D).transform
		out[String(n.name)] = t
		for c in n.get_children():
			_globals(c, t, out)

func _ready() -> void:
	var data := arg("data")
	var npc_id := arg("npc", "fargoth")
	var db := MWWorldDB.new(data)
	var models := MWModelCache.new(data)
	var av = ActorVisual.new(db, models)
	var npc: Dictionary = av.record("npc", npc_id)
	var race: Dictionary = av.record("race", String(npc.get("race", "")))
	var skel: String = av.records_index().get("actor", {}).get("skeletons", {}).get("male", "")
	var raw := models.instantiate(skel)
	var g_raw := {}
	_globals(raw, Transform3D.IDENTITY, g_raw)
	var model: Node3D = av.build_npc(npc_id)
	add_child(model)
	var sk := model.get_node("Skeleton") as Skeleton3D
	var report := {"npc": npc_id, "race": race.get("name", ""), "female": npc.get("female", false), "bones": {}, "parts": []}
	for name in ["Bip01", "Bip01 Pelvis", "Head", "Chest", "Groin", "Left Upper Arm", "Right Upper Arm", "Left Forearm",
			"Right Forearm", "Left Wrist", "Left Upper Leg", "Right Upper Leg", "Left Knee", "Left Foot"]:
		var bi := sk.find_bone(name)
		var ours := sk.get_bone_global_rest(bi) if bi >= 0 else Transform3D()
		var theirs: Transform3D = g_raw.get(name, Transform3D())
		report["bones"][name] = {"in_ours": bi >= 0, "in_glb": g_raw.has(name),
			"pos_ours": str(ours.origin.snapped(Vector3.ONE * 0.001)), "pos_glb": str(theirs.origin.snapped(Vector3.ONE * 0.001)),
			"rot_diff_rad": snappedf(ours.basis.get_rotation_quaternion().angle_to(theirs.basis.get_rotation_quaternion()), 0.001)}
	for c in sk.get_children():
		var d := {"node": String(c.name), "class": c.get_class()}
		if c is BoneAttachment3D:
			d["bone"] = (c as BoneAttachment3D).bone_name
			var ch := c.get_child(0) as Node3D
			d["child"] = String(ch.name)
			d["scale"] = str(ch.scale)
			var aabb := AABB()
			for mi in ch.find_children("*", "MeshInstance3D", true, false):
				aabb = mi.get_aabb()
			d["aabb"] = str(aabb)
		report["parts"].append(d)
	report["stats"] = av.stats
	print("MWGODOT_ACTOR ", JSON.stringify(report))
	raw.free()
	var shot := arg("screenshot")
	if shot.is_empty():
		get_tree().quit()
		return
	# zrzut: NPC przodem do kamery; --anim=0 – poza spoczynkowa (bez animacji)
	var ap := model.get_node("MWAnimations") as AnimationPlayer
	var at := float(arg("anim_time", "-1"))
	if arg("anim", "1") == "0":
		ap.stop()
		sk.reset_bone_poses()
	elif at >= 0.0:
		ap.play(arg("anim_name", "idle"))
		ap.seek(at, true)
		ap.pause()
	var cam := Camera3D.new()
	add_child(cam)
	var side := -1.0 if arg("view", "front") == "front" else 1.0     # NPC patrzy w −Z (kierunek +Y w MW)
	cam.position = Vector3(0.0, float(arg("cam_y", "1.0")), side * float(arg("cam_d", "3.0")))
	cam.look_at(Vector3(0, float(arg("cam_y", "1.0")) - 0.05, 0))
	cam.fov = 50
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-40, 30, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.45)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot)
	print("MWGODOT_SHOT ", shot)
	get_tree().quit()
