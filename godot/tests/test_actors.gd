extends SceneTree
## Etap 2: NPC złożeni z części ciała (szkielet, skinning, części sztywne, lustro lewej strony, zastępcze męskie
## części dla kobiet, pomijanie „1st”), animacja bezczynności NPC i stworzeń.
## godot --headless --path godot -s res://tests/test_actors.gd -- --data=WYNIKI

var failures: Array[String] = []
var checks := 0
var cell: Node3D
var builder
var frames := 0
var rest_arm: Quaternion

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""

func _all(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_all(c, out)

func _actor(kind: String, base: String) -> Node3D:
	for r in cell.get_node("Refs").get_children():
		if r.get_meta("mw_actor", "") == kind and String(r.get_meta("mw_base", "")) == base:
			return r
	return null

func _initialize() -> void:
	var data := arg("data")
	var db := MWWorldDB.new(data)
	var models := MWModelCache.new(data)
	builder = MWCellBuilder.new(db, models)
	check(builder.actors.available(), "rekordy aktorów dostępne")
	cell = builder.build_cell("ext:0,0")
	root.add_child(cell)
	var m := _actor("npc", "synth_villager")
	var f := _actor("npc", "synth_villager_f")
	var c := _actor("creature", "synth_creature")
	check(m != null and f != null and c != null, "NPC (mężczyzna, kobieta) i stworzenie zbudowane")
	if m == null or f == null:
		return
	var sk := m.get_node_or_null("Model/Skeleton") as Skeleton3D
	check(sk != null and sk.find_bone("Bip01") >= 0 and sk.find_bone("Head") >= 0 and sk.find_bone("Left Forearm") >= 0,
			"szkielet: Skeleton3D z kośćmi Bip01 i węzłami mocowania")
	var nodes := []
	_all(m, nodes)
	var names := nodes.map(func(n): return String(n.name))
	check(not names.has("Tri Mannequin"), "manekin szkieletu pominięty")
	var skinned := nodes.filter(func(n): return n is MeshInstance3D and n.skin != null)
	check(skinned.map(func(n): return String(n.name)).filter(func(s): return s in ["Tri Chest", "Tri Left Hand 0", "Tri Right Hand 0"]).size() == 3,
			"części ze skinningiem przepięte (tułów, dłonie): %s" % [skinned.map(func(n): return n.name)])
	for mi in skinned:
		check(mi.get_node_or_null(mi.skeleton) == sk, "skóra %s wskazuje szkielet NPC" % mi.name)
		for i in mi.skin.get_bind_count():
			check(sk.find_bone(mi.skin.get_bind_name(i)) >= 0, "kość wiązania %s istnieje" % mi.skin.get_bind_name(i))
	var att := nodes.filter(func(n): return n is BoneAttachment3D)
	var by_bone := {}
	for a in att:
		by_bone[a.bone_name] = by_bone.get(a.bone_name, []) + [a]
	check(by_bone.get("Head", []).size() == 2, "głowa i włosy na kości Head (%s)" % [by_bone.keys()])
	check(by_bone.has("Left Forearm") and by_bone["Left Forearm"][0].get_child(0).scale.x < 0.0, "lewe przedramię odbite (skala X −1)")
	check(by_bone.has("Right Forearm") and by_bone["Right Forearm"][0].get_child(0).scale.x > 0.0, "prawe przedramię bez odbicia")
	check(not by_bone.has("Right Hand") and not by_bone.has("Left Hand"), "część „1st” pominięta w 3. osobie")
	# kobieta: żeński tułów (szerszy), dłonie i przedramiona – męskie zastępcze
	var fn := []
	_all(f, fn)
	var fchest = fn.filter(func(n): return n is MeshInstance3D and String(n.name) == "Tri Chest")
	check(fchest.size() == 1 and fchest[0].mesh.get_aabb().size.x > 0.45, "kobieta: żeński tułów")
	check(fn.filter(func(n): return n is MeshInstance3D and String(n.name) == "Tri Left Hand 0").size() == 1,
			"kobieta: męskie dłonie jako zastępcze")
	var ap := m.get_node("Model/MWAnimations") as AnimationPlayer
	check(ap.is_playing() and ap.current_animation == "idle", "NPC: bezczynność w pętli (%s)" % ap.current_animation)
	var cap := c.get_node("Model").find_children("MWAnimations", "AnimationPlayer", true, false)
	check(cap.size() > 0 and (cap[0] as AnimationPlayer).is_playing() and (cap[0] as AnimationPlayer).current_animation == "idle",
			"stworzenie: animacja bezczynności")
	rest_arm = sk.get_bone_rest(sk.find_bone("Bip01 L UpperArm")).basis.get_rotation_quaternion()

func _process(_delta: float) -> bool:
	frames += 1
	if frames < 20:
		return false
	var m := _actor("npc", "synth_villager")
	if m:
		var sk := m.get_node("Model/Skeleton") as Skeleton3D
		var q := sk.get_bone_pose_rotation(sk.find_bone("Bip01 L UpperArm"))
		check(q.angle_to(rest_arm) > 0.5, "animacja zmienia pozę kości (ramię opuszczone z pozy T: %.2f rad)" % q.angle_to(rest_arm))
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": builder.actors.stats}))
	quit(1 if failures.size() > 0 else 0)
	return true
