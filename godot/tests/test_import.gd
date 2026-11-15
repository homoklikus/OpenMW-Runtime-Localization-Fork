extends SceneTree
## Test importu GLB → Godot (ścieżka runtime GLTFDocument, ta sama co w grze).
## Uruchomienie: godot --headless --path godot -s res://tests/test_import.gd -- --data=/ścieżka/wyniki
## Wynik: JSON (linia "RESULT {...}") + kod wyjścia 0/1.

const U := 69.99125109
var failures: Array[String] = []
var checks := 0
var report := {}

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		printerr("FAIL: ", msg)

func approx(a: float, b: float, eps := 1e-4) -> bool:
	return absf(a - b) <= eps

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := find_named(c, nm)
		if r:
			return r
	return null

func find_by_mw_name(n: Node, nm: String) -> Node:
	if MWModelCache.extras_of(n).get("mw_name", "") == nm:
		return n
	for c in n.get_children():
		var r := find_by_mw_name(c, nm)
		if r:
			return r
	return null

func mesh_world_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		if acc.is_empty():
			acc.append(a)
		else:
			acc[0] = acc[0].merge(a)
	for c in n.get_children():
		mesh_world_aabb(c, t, acc)

func _init() -> void:
	var data := arg("data")
	var cache := MWModelCache.new(data)

	# --- domek ---------------------------------------------------------------------------
	var hut := cache.instantiate("meshes/synth/test_hut.glb")
	check(hut != null, "test_hut.glb wczytany")
	if hut:
		root.add_child(hut)
		var acc := []
		mesh_world_aabb(hut, Transform3D.IDENTITY, acc)
		var aabb: AABB = acc[0]
		report["hut_aabb"] = [aabb.position, aabb.end]
		check(approx(aabb.position.y, 0.0), "podstawa domku na y=0 (było %f)" % aabb.position.y)
		check(approx(aabb.end.y, 288.0 / U), "wysokość domku 288 jedn. = %.4f m (było %f)" % [288.0 / U, aabb.end.y])
		check(approx(aabb.position.x, -144.0 / U), "okap dachu −144 jedn. na X")
		var walls := find_by_mw_name(hut, "tri walls") as MeshInstance3D
		check(walls != null, "węzeł 'tri walls' istnieje")
		if walls:
			var wa := walls.mesh.get_aabb()
			check(approx(wa.size.x, 256.0 / U), "szerokość ścian 256 jedn. = 3.6576 m (było %f)" % wa.size.x)
			var mat := walls.mesh.surface_get_material(0) as StandardMaterial3D
			check(mat != null and mat.albedo_texture != null, "ściany mają teksturę albedo")
			if mat and mat.albedo_texture:
				check(mat.albedo_texture.get_width() == 128, "tekstura ścian 128 px")
			check(walls.get_node_or_null("Collision") == null, "ściany bez własnej kolizji (jest RootCollisionNode)")
		var sign := find_by_mw_name(hut, "SignNode") as Node3D
		check(sign != null, "węzeł SignNode")
		if sign:
			check(sign.position.distance_to(Vector3(100, 150, 160) / U) < 1e-4, "pozycja szyldu (100,−160,150) MW → (%s)" % sign.position)
			check(approx(sign.scale.x, 1.5), "skala szyldu 1.5")
			check(approx(rad_to_deg(sign.rotation.y), 30.0, 1e-3), "obrót szyldu 30° wokół Y (było %f)" % rad_to_deg(sign.rotation.y))
		var sm := find_by_mw_name(hut, "tri sign") as MeshInstance3D
		if sm:
			var m := sm.mesh.surface_get_material(0) as BaseMaterial3D
			check(m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "szyld: alpha scissor (test alfa)")
			check(approx(m.alpha_scissor_threshold, 128.0 / 255.0, 1e-3), "szyld: próg 128/255")
			check(m.cull_mode == BaseMaterial3D.CULL_DISABLED, "szyld: dwustronny")
		var roof := find_by_mw_name(hut, "tri roof") as MeshInstance3D
		if roof:
			var rm := roof.mesh.surface_get_material(0) as BaseMaterial3D
			check(rm.vertex_color_use_as_albedo, "dach: kolory wierzchołków jako albedo")
			var arrays := roof.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > 0, "dach: tablica kolorów")
		var col := find_by_mw_name(hut, "tri collision") as MeshInstance3D
		check(col != null and not col.visible, "kolizja niewidoczna")
		check(col != null and col.get_node_or_null("Collision") is StaticBody3D, "kolizja: StaticBody3D z RootCollisionNode")
		check(find_by_mw_name(hut, "Tri EditorMarker") == null or not (find_by_mw_name(hut, "Tri EditorMarker") is MeshInstance3D), "marker edytora bez siatki")
		# test fizyki: promień z góry trafia w dach kolizji (288 jedn.)
		report["hut_nodes"] = hut.get_child_count()

	# --- wiatrak (animacja) --------------------------------------------------------------
	var wm := cache.instantiate("meshes/synth/test_windmill.glb")
	check(wm != null, "test_windmill.glb wczytany")
	if wm:
		root.add_child(wm)
		var ap := find_named(wm, "AnimationPlayer") as AnimationPlayer
		check(ap != null, "AnimationPlayer w wiatraku")
		if ap:
			var names := ap.get_animation_list()
			report["windmill_anims"] = names
			check(names.size() >= 1, "co najmniej jedna animacja")
			var anim := ap.get_animation(names[0])
			check(approx(anim.length, 4.0, 1e-3), "długość animacji 4 s (było %f)" % anim.length)
			# obrót łopat w t = 1 s: 90° wokół −Z
			var blades := find_by_mw_name(wm, "Blades") as Node3D
			ap.play(names[0])
			ap.seek(1.0, true)
			var q := blades.quaternion
			report["blades_q_t1"] = q
			check(q.is_equal_approx(Quaternion(Vector3(0, 0, -1), PI / 2)) or q.is_equal_approx(-Quaternion(Vector3(0, 0, -1), PI / 2)), "łopaty w t=1 s obrócone o 90° wokół −Z (%s)" % q)
			# Hermite z zerowymi stycznymi: w połowie przedziału y_MW = (−48 + −64)/2 = −56
			check(blades.position.distance_to(Vector3(0, 360, 56) / U) < 1e-3, "pozycja piasty w t=1 s = (0,−56,360) MW (było %s)" % (blades.position * U))

	# --- skin --------------------------------------------------------------------------
	var sk := cache.instantiate("meshes/synth/test_skinned.glb")
	check(sk != null, "test_skinned.glb wczytany")
	if sk:
		root.add_child(sk)
		var skel := find_named(sk, "Skeleton3D") as Skeleton3D
		if skel == null:
			for c in sk.find_children("*", "Skeleton3D", true, false):
				skel = c
		check(skel != null, "Skeleton3D utworzony")
		if skel:
			report["bones"] = skel.get_bone_count()
			check(skel.get_bone_count() >= 2, "co najmniej 2 kości")
		var tubes := sk.find_children("*", "MeshInstance3D", true, false)
		check(tubes.size() == 1 and (tubes[0] as MeshInstance3D).skin != null, "rura ma Skin")

	report["cache"] = cache.stats
	report["errors"] = cache.errors
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
