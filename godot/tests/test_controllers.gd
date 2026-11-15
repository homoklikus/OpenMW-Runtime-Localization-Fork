extends SceneTree
## Kontrolery NIF, morfy, cząsteczki i animacje .kf w Godocie.
## godot --headless --path godot -s res://tests/test_controllers.gd -- --data=WYNIKI

var failures: Array[String] = []
var checks := 0
var report := {}

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func by_mw(n: Node, nm: String) -> Node:
	if MWModelCache.extras_of(n).get("mw_name", "") == nm:
		return n
	for c in n.get_children():
		var r := by_mw(c, nm)
		if r:
			return r
	return null

func players(root: Node, prefix: String) -> Array:
	var out := []
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		if String(ap.name).begins_with(prefix):
			out.append(ap)
	return out

func seek_all(aps: Array, t: float) -> void:
	for ap in aps:
		(ap as AnimationPlayer).play("ctl")
		(ap as AnimationPlayer).seek(t, true)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var cache := MWModelCache.new(arg("data"))
	var m := cache.instantiate("meshes/synth/hard_controllers.glb")
	check(m != null, "hard_controllers.glb wczytany")
	root.add_child(m)
	var vis_aps := players(m, "MWCtl_vis")
	var uv_aps := players(m, "MWCtl_uv")
	var alpha_aps := players(m, "MWCtl_alpha")
	var color_aps := players(m, "MWCtl_color")
	var flip_aps := players(m, "MWCtl_flip")
	report["players"] = [vis_aps.size(), uv_aps.size(), alpha_aps.size(), color_aps.size(), flip_aps.size()]
	check(vis_aps.size() == 1 and uv_aps.size() == 1 and alpha_aps.size() == 1 and color_aps.size() == 1 and flip_aps.size() == 1,
		"po jednym odtwarzaczu: vis, uv, alpha, color, flip (%s)" % str(report["players"]))
	var vis_node := by_mw(m, "VisNode") as Node3D
	seek_all(vis_aps, 0.6)
	check(vis_node != null and not vis_node.visible, "widoczność: ukryty w t=0.6 s")
	seek_all(vis_aps, 0.2)
	check(vis_node.visible, "widoczność: widoczny w t=0.2 s")
	var uvm := by_mw(m, "tri uvscroll") as MeshInstance3D
	seek_all(uv_aps, 1.0)
	var mat := uvm.get_surface_override_material(0) as BaseMaterial3D
	check(mat != null and mat.uv1_offset.distance_to(Vector3(0.5, 0.25, 0)) < 1e-3, "UV: przesunięcie (0.5, 0.25) w t=1 s (%s)" % (str(mat.uv1_offset) if mat else "brak"))
	var mm := by_mw(m, "tri matanim") as MeshInstance3D
	seek_all(alpha_aps, 1.0)
	var am := mm.get_surface_override_material(0) as BaseMaterial3D
	report["alpha_t1"] = am.albedo_color.a if am else -1
	check(am != null and absf(am.albedo_color.a - 0.2) < 1e-3, "alfa materiału 0.2 w t=1 s")
	var fm := by_mw(m, "tri flip") as MeshInstance3D
	seek_all(flip_aps, 0.3)
	var fmat := fm.get_surface_override_material(0) as BaseMaterial3D
	check(fmat != null and fmat.albedo_texture != null and fmat.albedo_texture.get_width() == 128, "flip: druga tekstura w t=0.3 s")
	var morph := by_mw(m, "tri morph") as MeshInstance3D
	check(morph != null and morph.mesh.get_blend_shape_count() == 1, "morf: 1 kształt (blend shape)")
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		ap.play(ap.get_animation_list()[0])
		ap.seek(1.0, true)
		report["morph_w_t1"] = morph.get_blend_shape_value(0)
		check(absf(morph.get_blend_shape_value(0) - 1.0) < 1e-3, "morf: waga 1.0 w t=1 s")
		var pn := by_mw(m, "PathNode") as Node3D
		ap.seek(1.0, true)
		report["path_t1"] = pn.position * MWCoords.UNITS_PER_METER
		check(absf(pn.position.x * MWCoords.UNITS_PER_METER - 50.0) < 1.0, "ścieżka: x = 50 jedn. w połowie (t=1 s)")

	var p := cache.instantiate("meshes/synth/hard_particles.glb")
	root.add_child(p)
	var parts := p.find_children("*", "CPUParticles3D", true, false)
	report["particles"] = parts.size()
	check(parts.size() == 2, "2 systemy cząsteczek (CPUParticles3D)")
	if parts.size() > 0:
		var cp := parts[0] as CPUParticles3D
		check(cp.get_parent() == by_mw(p, "Emitter"), "cząsteczki pod węzłem emitera")
		check(cp.color_ramp != null and absf(cp.lifetime - 1.5) < 1e-4, "kolor + czas życia z NIF")
		check((cp.mesh.surface_get_material(0) as BaseMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "mieszanie addytywne")
		check(cp.gravity.length() > 0, "grawitacja z NiGravity")

	var sk := cache.instantiate("meshes/synth/test_skinned.glb")
	root.add_child(sk)
	var lib := sk.get_node_or_null("MWAnimations") as AnimationPlayer
	check(lib != null, "biblioteka animacji z .kf dołączona")
	if lib:
		var names := lib.get_animation_list()
		report["kf_clips"] = names
		check(names.has("idle") and names.has("bend"), "klipy idle i bend")
		check(int(lib.get_meta("mw_missing_tracks", -1)) == 0, "wszystkie ścieżki .kf trafiły w kości")
		lib.play("bend")
		lib.seek(1.0, true)
		var skel := sk.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var q := skel.get_bone_pose_rotation(skel.find_bone("Bone2"))
		report["bend_q"] = q
		check(q.is_equal_approx(Quaternion(Vector3(1, 0, 0), PI / 2)), "bend t=1 s: Bone2 obrócona o 90° wokół X (%s)" % q)
		check(absf(lib.get_animation("bend").length - 2.0) < 1e-3 and lib.get_animation("bend").loop_mode == Animation.LOOP_LINEAR, "bend: 2 s, zapętlony")
	report["cache"] = cache.stats
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
