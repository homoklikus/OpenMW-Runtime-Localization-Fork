extends SceneTree
## Eksperyment first-fish (mods/first-fish): import modelu GLB w czasie działania (skala, osie, materiał,
## szkielet), animacja swim_idle (pętla, faktyczne wygięcie ogona), zachowanie pływania przez 120 s symulacji
## (obszar, pas wody nad dnem i pod lustrem, zmiany kursu), ładowarka modów (mod.json, skrypt zachowania).
## godot --headless --path godot -s res://tests/test_first_fish.gd

var failures: Array[String] = []
var checks := 0
var loader

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _mesh_aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../mods").simplify_path()
	var Mods = load("res://scripts/mw/mw_native_mods.gd")
	loader = Mods.new(null, dir)
	var mod: Dictionary = {}
	for m in loader.mods:
		if m.id == "first-fish":
			mod = m
	check(not mod.is_empty(), "mod first-fish znaleziony w %s" % dir)
	if mod.is_empty():
		_finish()
		return
	var c: Dictionary = mod.def.creatures[0]
	var proto: Node3D = loader._model(String(mod.dir).path_join(c.model))
	check(proto != null, "GLB wczytany (GLTFDocument)")
	var script: GDScript = loader._script(String(mod.dir).path_join(c.behaviour))
	check(script != null, "skrypt zachowania kompiluje się")
	if proto == null or script == null:
		_finish()
		return
	# --- model: skala, osie, materiał, szkielet
	var inst := proto.duplicate() as Node3D
	root.add_child(inst)
	var box := _mesh_aabb(inst)
	check(box.size.z > 0.30 and box.size.z < 0.42 and box.size.x < 0.2 and box.size.y < 0.2,
			"rozmiar małej ryby: %s m (długość wzdłuż Z)" % box.size)
	check(box.position.z < -0.12 and box.end.z > 0.15, "pysk w −Z (przód węzła), płetwa ogonowa w +Z")
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0] if not inst.find_children("*", "Skeleton3D", true, false).is_empty() else null
	check(skel != null and skel.get_bone_count() == 4, "szkielet 4 kości")
	var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mat := mi.get_active_material(0) as StandardMaterial3D
	check(mat != null and mat.albedo_texture != null and mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"materiał: tekstura albedo, dwustronny (płetwy)")
	# --- animacja
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0] if not inst.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	check(ap != null and ap.has_animation("swim_idle"), "animacja swim_idle")
	if ap != null and skel != null and ap.has_animation("swim_idle"):
		var anim := ap.get_animation("swim_idle")
		check(absf(anim.length - 1.0) < 0.05, "długość pętli 1 s (%s)" % anim.length)
		var tail := skel.find_bone("tail2")
		ap.play("swim_idle")
		var rots := []
		for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
			ap.seek(t, true)
			rots.append(skel.get_bone_pose_rotation(tail))
		check((rots[1] as Quaternion).angle_to(rots[3]) > deg_to_rad(20.0), "ogon wygina się na boki (%.1f°)" % rad_to_deg((rots[1] as Quaternion).angle_to(rots[3])))
		check((rots[0] as Quaternion).angle_to(rots[4]) < deg_to_rad(1.0), "pętla bez skoku (klatka 0 = klatka końcowa)")
	inst.queue_free()
	# --- zachowanie: 3 rybki, nierówne dno, 120 s symulacji
	var ground := func(x: float, z: float) -> float: return -2.2 + 0.6 * sin(x * 0.7) * cos(z * 0.5)
	var fishes := []
	var home := Vector3(10, 0, -5)
	for i in 3:
		var f := Node3D.new()
		f.add_child(proto.duplicate())
		f.set_script(script)
		var r := RandomNumberGenerator.new()
		r.seed = 100 + i
		f.set("rng", r)
		f.set("home", home)
		f.set("radius", 3.5)
		f.set("water_y", 0.0)
		f.set("ground", ground)
		f.set("params", (c.get("params", {}) as Dictionary).merged({"animation": "swim_idle"}))
		root.add_child(f)
		f.global_position = home + Vector3(i * 0.5, -1.0, 0)
		fishes.append(f)
	await process_frame
	var max_off := 0.0
	var yaws := {}
	var band_ok := true
	var steps := 120 * 30
	for s in steps:
		for f in fishes:
			f._process(1.0 / 30.0)
			var p: Vector3 = f.global_position
			max_off = maxf(max_off, Vector2(p.x - home.x, p.z - home.z).length())
			if p.y > -0.2 or p.y < float(ground.call(p.x, p.z)) + 0.15:
				band_ok = false
			yaws[int(rad_to_deg(f.rotation.y)) / 30] = true
	var trav := 0.0
	var viol := 0
	for f in fishes:
		trav += float(f.travelled)
		viol += int(f.violations)
		check(f.find_children("*", "AnimationPlayer", true, false)[0].is_playing(), "animacja gra w pętli na rybce")
	check(band_ok and viol == 0, "zawsze pod lustrem wody i nad dnem (naruszenia: %d)" % viol)
	check(max_off <= 3.5 * 1.25, "zostaje w obszarze (maks. %.2f m z 3,5 m)" % max_off)
	check(trav > 3 * 120 * 0.25 * 0.4, "pływa (droga %.1f m w 120 s, 3 rybki)" % trav)
	check(yaws.size() >= 6, "zmienia kierunek (%d z 12 sektorów kursu)" % yaws.size())
	check(loader.errors.is_empty(), "bez błędów ładowarki (%s)" % [loader.errors])
	_finish()

func _finish() -> void:
	if loader != null:
		loader.free_cache()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
