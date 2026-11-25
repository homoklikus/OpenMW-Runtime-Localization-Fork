extends SceneTree
## Etap 10 (zgłoszenie: woda „pojawia się i znika” zależnie od kąta): odbicie wody jak OpenMW Reflection –
## kamera odbita względem poziomu wody, maska wg [Water] reflection detail (calcNodeMask), warstwy siatek
## (teren, aktorzy, roślinność, woda), znacznik przebiegu odbicia poza kamerami gracza, tekstura w shaderze wody,
## poziom odcięcia terenu, ToggleWorld.
## godot --headless --path godot -s res://tests/test_water_reflection.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var WR := load("res://scripts/mw/mw_water_reflection.gd")
	var Env := load("res://scripts/mw/mw_environment.gd")
	# calcNodeMask
	check(WR.node_mask(0, false) == WR.REFLECTION_PASS, "detail 0: samo niebo")
	check(WR.node_mask(1, false) == WR.REFLECTION_PASS | WR.LAYER_TERRAIN, "detail 1: teren")
	check(WR.node_mask(2, false) == WR.REFLECTION_PASS | WR.LAYER_TERRAIN | WR.LAYER_DEFAULT, "detail 2: świat")
	check(WR.node_mask(4, false) & WR.LAYER_ACTOR != 0 and WR.node_mask(4, false) & WR.LAYER_GROUNDCOVER == 0, "detail 4: aktorzy bez roślinności")
	check(WR.node_mask(5, false) & WR.LAYER_GROUNDCOVER != 0, "detail 5: roślinność")
	check(WR.node_mask(0, true) == WR.node_mask(2, false), "wnętrze: co najmniej 2")
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(30)
	var pl = main.player
	var eye: Camera3D = pl.get_node("Camera3D")
	check(eye.cull_mask & WR.REFLECTION_PASS == 0 and eye.cull_mask & WR.LAYER_WATER != 0, "kamera gracza: bez znacznika odbicia, z wodą")
	var waters: Array = root.find_children("Water", "MeshInstance3D", true, false).filter(func(n): return n.has_meta("mw_water"))
	check(not waters.is_empty() and waters.all(func(w): return (w as MeshInstance3D).layers == WR.LAYER_WATER), "płaszczyzny wody na warstwie wody (%d)" % waters.size())
	var actor_ok := true
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if n.has_meta("mw_actor"):
				for g in n.find_children("*", "GeometryInstance3D", true, false):
					if (g as GeometryInstance3D).layers != WR.LAYER_ACTOR:
						actor_ok = false
	var tmeshes := 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).layers == WR.LAYER_TERRAIN:
			tmeshes += 1
	check(tmeshes > 0, "teren na warstwie terenu (%d siatek)" % tmeshes)
	check(actor_ok, "siatki aktorów na warstwie aktorów")
	var body_ok: bool = main.player_body.model != null
	for g in main.player_body.model.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).layers != WR.LAYER_ACTOR:
			body_ok = false
	check(body_ok, "postać gracza na warstwie aktorów (Mask_Player)")
	# woda w komórce gracza – kamera odbicia
	var h := waters[0].global_position.y as float if not waters.is_empty() else 0.0
	pl.fly = true
	pl.global_position.y = h + 2.0
	await _frames(5)
	print("water_level ", pl.water_level, " h ", h, " mode ", Env.water_mode)
	var wr = main.water_reflection
	check(float(pl.water_level) > -1e9, "gracz nad wodą (poziom %.2f)" % float(pl.water_level))
	check(wr.active and wr.vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "odbicie aktywne nad wodą")
	var mat: ShaderMaterial = Env._water_material()
	check(bool(mat.get_shader_parameter("reflection_on")) and mat.get_shader_parameter("reflection_tex") != null, "shader wody dostaje teksturę odbicia")
	var view: Camera3D = main.view_camera()
	var wy := float(pl.water_level)
	check(absf(wr.cam.global_position.y - (2.0 * wy - view.global_position.y)) < 0.01 and absf(wr.cam.global_position.x - view.global_position.x) < 0.01,
		"kamera odbicia w punkcie odbitym (%.2f vs %.2f)" % [wr.cam.global_position.y, 2.0 * wy - view.global_position.y])
	eye.rotation.x = -0.4
	await _frames(2)
	var vf: Vector3 = -view.global_transform.basis.z
	var rf: Vector3 = -wr.cam.global_transform.basis.z
	check(absf(rf.y + vf.y) < 0.01 and absf(rf.x - vf.x) < 0.01 and absf(rf.z - vf.z) < 0.01, "kierunek odbity (pion przeciwny)")
	check(absf(wr.cam.fov - view.fov) < 0.01 and wr.vp.size.y == wr.rtt_size, "ta sama projekcja, wysokość RTT %d" % wr.vp.size.y)
	check(wr.cam.cull_mask == WR.node_mask(2, false), "domyślna maska: reflection detail 2 (%d)" % wr.cam.cull_mask)
	var gv = RenderingServer.global_shader_parameter_get("mw_water_clip_y")     # null w rendererze testowym (dummy)
	check(is_equal_approx(float(wr.water_y), wy) and (gv == null or is_equal_approx(float(gv), wy)), "poziom odcięcia terenu = poziom wody")
	main.settings["water_reflection_detail"] = 5
	main.apply_live_settings()
	await _frames(2)
	check(wr.cam.cull_mask & WR.LAYER_GROUNDCOVER != 0, "reflection detail 5 z ustawień – roślinność w odbiciu")
	main.console.execute("tw")
	await _frames(2)
	check(wr.cam.cull_mask == WR.REFLECTION_PASS, "ToggleWorld: odbicie bez świata")
	main.console.execute("tw")
	# pod wodą – bez tekstury odbicia w shaderze nad wodą, kamera odbicia wyłączona poza wodą
	main.settings["water_shader"] = false
	main.apply_live_settings()
	await _frames(3)
	check(not wr.active and wr.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "prosta woda – bez kamery odbicia")
	print("RESULT ", JSON.stringify({"test": "water_reflection", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
