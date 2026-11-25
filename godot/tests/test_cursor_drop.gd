extends SceneTree
## Etap 10 cz. 33: kursory gry (openmw_pointer.xml – obraz 32 × 32, obrót, punkt aktywny) i upuszczanie przedmiotu
## w świat jak WorldItemModel (canPlaceObject → placeObject w punkcie kursora, inaczej dropObjectOnGround pod nogi
## gracza), kursor drop_ground nad światem.
## godot --headless --path godot -s res://tests/test_cursor_drop.gd -- --data=WYNIKI(aktorzy) --scripts=0

const MWCursor := preload("res://scripts/mw/mw_cursor.gd")
const MWCoords := preload("res://scripts/mw/mw_coords.gd")

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
	# --- obraz wskaźnika: obrót zgodnie z ruchem wskazówek o −Rotation (SDL_RenderCopyEx) ---
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(30, 15, Color(1, 1, 1, 1))              # punkt po prawej od środka
	img.set_pixel(30, 16, Color(1, 1, 1, 1))
	var r90 := MWCursor.rotated(img, 90.0)                 # 90° w prawo (vresize: Rotation 90 → kąt −90 … patrz niżej)
	check(r90.get_pixel(15, 30).a > 0.4 or r90.get_pixel(16, 30).a > 0.4, "obrót o 90° zgodnie z ruchem wskazówek: punkt z prawej na dół")
	var rm90 := MWCursor.rotated(img, -90.0)
	check(rm90.get_pixel(15, 1).a > 0.4 or rm90.get_pixel(16, 1).a > 0.4, "obrót o −90°: punkt z prawej do góry")
	var dir := "user://cursor_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir).path_join("textures"))
	var small := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	small.fill(Color(1, 0, 0, 1))
	small.save_png(ProjectSettings.globalize_path(dir).path_join("textures/tx_cursormove.png"))
	var pi := MWCursor.pointer_image(ProjectSettings.globalize_path(dir), "textures/tx_cursormove", 45.0)
	check(pi != null and pi.get_width() == 32 and pi.get_height() == 32, "wskaźnik przeskalowany do 32 × 32")
	check(pi != null and pi.get_pixel(0, 0).a < 0.1 and pi.get_pixel(16, 16).a > 0.9, "obrót o 45°: rogi przezroczyste, środek kryjący")
	check(MWCursor.POINTERS.size() == 6 and MWCursor.POINTERS[0][2] == Vector2i(7, 0), "6 wskaźników OpenMW, strzałka z punktem (7, 0)")
	# --- upuszczenie w świat ---
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var inv = main.interaction.inventory
	inv.add("player", {}, "misc_synth_spoon", 3)
	var pmw: Vector3 = MWCoords.godot_to_mw(main.player.global_position)
	var sid: String = main.drop_item("misc_synth_spoon", 1)
	var d: Dictionary = main.state.dynamic.get(sid, {})
	var pos: Array = d.get("mw", {}).get("pos", [0, 0, 0])
	check(not sid.is_empty() and Vector2(float(pos[0]) - pmw.x, float(pos[1]) - pmw.y).length() < 1.0,
		"dropObjectOnGround: pod nogami gracza (%s vs %s)" % [pos, pmw])
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	check(cam != null, "kamera")
	if cam != null:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		var target: Vector3 = main.player.global_position + fwd.normalized() * 1.2
		var screen := cam.unproject_position(target)
		check(main.can_place_object(screen), "canPlaceObject: płaska ziemia 1,2 m przed graczem (%s)" % screen)
		var sid2: String = main.drop_item("misc_synth_spoon", 1, screen)
		var p2: Array = main.state.dynamic.get(sid2, {}).get("mw", {}).get("pos", [0, 0, 0])
		var tmw := MWCoords.godot_to_mw(target)
		check(Vector2(float(p2[0]) - tmw.x, float(p2[1]) - tmw.y).length() < 15.0, "placeObject: w punkcie kursora (cel na wysokości stóp gracza, ziemia niżej) (%s vs %s)" % [p2, tmw])
		# daleko (poza 200 j.) – nie da się postawić
		var far := cam.unproject_position(main.player.global_position + fwd.normalized() * 30.0)
		check(not main.can_place_object(far), "punkt dalej niż 200 j. – canPlaceObject fałsz")
		var sid3: String = main.drop_item("misc_synth_spoon", 1, far)
		var p3: Array = main.state.dynamic.get(sid3, {}).get("mw", {}).get("pos", [0, 0, 0])
		check(Vector2(float(p3[0]) - pmw.x, float(p3[1]) - pmw.y).length() < 1.0, "bez miejsca – pod nogi gracza")
	# --- krawędzie okna MW_Window: widżety „Action” (Scale), kursory ---
	var mm = main.menu_mode
	mm.open()
	await _frames(2)
	var w: Control = mm.windows["inventory"]
	var zones := w.find_children("Resize_*", "", true, false)
	check(zones.size() == 16, "16 stref zmiany rozmiaru (krawędzie i rogi z trzech części) (%d)" % zones.size())
	var zl: Control = w.find_child("Resize_L", true, false)
	var ztl: Control = w.find_child("Resize_TL", true, false)
	check(zl != null and zl.mouse_default_cursor_shape == Control.CURSOR_HSIZE and ztl.mouse_default_cursor_shape == Control.CURSOR_FDIAGSIZE,
		"kursory: lewa krawędź hresize, róg lewy górny dresize")
	if zl != null:
		var gr := zl.get_global_rect()
		check(absf(gr.position.x - w.get_global_rect().position.x) < 1.0 and absf(gr.size.x - 4.0 * mm.scale_ui) < 1.0,
			"lewa krawędź: pas 4 px przy zewnętrznej krawędzi okna (%s vs %s)" % [gr, w.get_global_rect()])
		var p0 := w.position
		var s0 := w.size
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(-20, 0)
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm._resize_window(ev, w, [1, 0, -1, 0])
		check(is_equal_approx(w.position.x, p0.x - 20.0) and is_equal_approx(w.size.x, s0.x + 20.0) and is_equal_approx(w.size.y, s0.y),
			"ciągnięcie lewej krawędzi w lewo: okno szersze, prawa krawędź w miejscu")
		ev.relative = Vector2(5000, 0)
		mm._resize_window(ev, w, [1, 0, -1, 0])
		check(is_equal_approx(w.size.x, w.custom_minimum_size.x) and is_equal_approx(w.position.x + w.size.x, p0.x + s0.x),
			"minimalny rozmiar – prawa krawędź nadal w miejscu")
	# --- kliknięcie przedmiotu w świecie przy otwartym ekwipunku: pickUpObject (do ręki) ---
	if cam != null:
		var fwd2 := -cam.global_transform.basis.z
		fwd2.y = 0.0
		var spot: Vector3 = main.player.global_position + fwd2.normalized() * 0.8
		var scr := cam.unproject_position(spot)
		inv.add("player", {}, "misc_synth_spoon", 1)
		var psid: String = main.drop_item("misc_synth_spoon", 1, scr)
		await _frames(3)
		var node: Node = main.interaction.node_of(psid) if main.interaction.has_method("node_of") else null
		var at: Vector3 = (node as Node3D).global_position + Vector3(0, 0.03, 0) if node is Node3D else spot
		# ToolTips::update w trybie GUI nad światem: podpowiedź przedmiotu pod kursorem
		check(main.tooltips._update_gui_world(main.get_viewport(), cam.unproject_position(at)) and main.tooltips.gui_world_key.contains("caption")
			and main.tooltips.box.visible, "podpowiedź przedmiotu pod kursorem w trybie ekwipunku (%s)" % main.tooltips.gui_world_key.left(80))
		var c0: int = inv.count_of("player", {}, "misc_synth_spoon")
		var handled: bool = mm.world_pick(cam.unproject_position(at), {})
		check(handled and mm.is_holding() and String(mm.held.id) == "misc_synth_spoon" and int(mm.held.count) == 1,
			"pickUpObject: łyżka spod kursora przy kursorze (%s)" % [mm.held])
		check(inv.count_of("player", {}, "misc_synth_spoon") == c0 + 1 and not main.state.dynamic.has(psid),
			"przedmiot w ekwipunku, usunięty ze świata")
		mm.held_drop("inventory")
	mm.close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
