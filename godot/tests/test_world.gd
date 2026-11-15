extends SceneTree
## Test świata i Construction Set 2.0 (headless):
##  * zbudowanie wszystkich komórek z world/ (teren, referencje, światła),
##  * zgodność pozycji referencji z danymi MW, kolizje (promień w dach chaty), lądowanie postaci na terenie,
##  * CS 2.0: przesunięcie / usunięcie / dodanie referencji → zapis nadpisań → ponowne wczytanie,
##  * round-trip współrzędnych MW ↔ Godot.
## godot --headless --path godot -s res://tests/test_world.gd -- --data=WYNIKI --project=KATALOG [--phase=build|verify]

var failures: Array[String] = []
var checks := 0
var report := {}

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		printerr("FAIL: ", msg)

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var data := arg("data")
	var project := arg("project")
	var phase := arg("phase", "build")
	var db := MWWorldDB.new(data, project)
	var models := MWModelCache.new(data)
	check(db.cell_index().size() == 5, "5 komórek w indeksie (jest %d)" % db.cell_index().size())

	# --- współrzędne: round-trip MW ↔ Godot -------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for i in 200:
		var rot := Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 1.4), rng.randf_range(-3, 3))
		var b := MWCoords.mw_rot_to_basis(rot)
		var back := MWCoords.basis_to_mw_rot(b)
		var b2 := MWCoords.mw_rot_to_basis(back)
		worst = maxf(worst, (b.x - b2.x).length() + (b.y - b2.y).length() + (b.z - b2.z).length())
	check(worst < 1e-4, "round-trip obrotów MW↔Godot (maks. błąd %f)" % worst)

	if phase == "build":
		await _phase_build(db, models)
	else:
		_phase_verify(db, models)
	report["models"] = models.stats
	report["model_errors"] = models.errors
	print("RESULT ", JSON.stringify({"phase": phase, "checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)

func _phase_build(db: MWWorldDB, models: MWModelCache) -> void:
	var builder := MWCellBuilder.new(db, models)
	var world := Node3D.new()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	for c in db.cell_index():
		if c.get("interior", false):
			continue
		var n := builder.build_cell(c["key"])
		check(n != null, "komórka %s zbudowana" % c["key"])
		if n:
			world.add_child(n)
	report["build_ms_ext"] = Time.get_ticks_msec() - t0
	report["builder"] = builder.stats
	check(builder.stats.refs == 19, "19 referencji zewnętrznych (jest %d)" % builder.stats.refs)
	check(builder.stats.missing_model == 0, "wszystkie modele wczytane")
	# znaczniki edytora (TempleMarker itp.): w grze bez modelu i kolizji, w CS 2.0 widoczne
	var mk := {"sid": "x.esm#99", "base": "TempleMarker", "godot": {"origin": [0, 0, 0], "quat": [0, 0, 0, 1], "scale": 1.0}}
	var hidden := builder.build_ref(mk)
	check(hidden.has_meta("mw_marker") and hidden.get_child_count() == 0, "TempleMarker w grze: bez modelu i kolizji")
	var eb := MWCellBuilder.new(db, models)
	eb.editor_mode = true
	var shown := eb.build_ref({"sid": "x.esm#98", "base": "synth_hut", "godot": mk["godot"]})
	check(shown.get_child_count() > 0 and not shown.has_meta("mw_marker"), "zwykły obiekt nadal z modelem")
	check(MWCellBuilder.is_hidden_marker("DivineMarker") and not MWCellBuilder.is_hidden_marker("synth_hut"),
			"lista znaczników: DivineMarker tak, zwykłe obiekty nie")
	builder.stats.refs -= 1
	builder.stats.markers -= 1
	hidden.free()
	shown.free()
	# wnętrze osobno
	var interior := builder.build_cell("int:synthville, test house")
	check(interior != null and interior.get_node("Refs").get_child_count() == 8, "wnętrze: 8 referencji (z drzwiami wyjściowymi)")
	if interior:
		interior.free()
	var lights := world.find_children("Light", "OmniLight3D", true, false)
	check(lights.size() == 1, "jedno światło zewnętrzne (lampa)")
	if lights.size() == 1:
		check(absf((lights[0] as OmniLight3D).omni_range - 512.0 / MWCoords.UNITS_PER_METER) < 1e-3, "promień światła 512 jedn.")

	# pozycja referencji chaty zmienionej przez plugin: (1400, 8600, h) MW
	var hut: Node3D = null
	for r in world.find_children("*", "Node3D", true, false):
		if r.get_meta("mw_sid", "") == "mwg_synthtown.esm#1":
			hut = r
	check(hut != null, "referencja mwg_synthtown.esm#1 istnieje")
	if hut == null:
		return
	var mwp := MWCoords.godot_to_mw(hut.global_position)
	check(absf(mwp.x - 1400) < 0.05 and absf(mwp.y - 8600) < 0.05, "pozycja chaty po pluginie (1400, 8600) MW (jest %s)" % mwp)
	check(absf(hut.scale.x - 1.2) < 1e-4, "skala chaty 1.2 z pluginu")

	await physics_frame
	await physics_frame
	# promień z góry w środek chaty: dach kolizji na wys. 288 jedn. × 1.2 nad podstawą
	var space := (world as Node3D).get_world_3d().direct_space_state
	var top := hut.global_position + Vector3(0, 50, 0)
	var q := PhysicsRayQueryParameters3D.create(top, hut.global_position - Vector3(0, 5, 0))
	var hit := space.intersect_ray(q)
	check(not hit.is_empty(), "promień trafia w kolizję chaty")
	if not hit.is_empty():
		var hh: float = hit.position.y - hut.global_position.y
		report["hut_roof_hit_m"] = hh
		check(absf(hh - 288.0 * 1.2 / MWCoords.UNITS_PER_METER) < 0.02, "wysokość kolizji dachu 345.6 jedn. (jest %.1f jedn.)" % (hh * MWCoords.UNITS_PER_METER))
	# promień w teren z dala od obiektów
	var probe := MWCoords.mw_to_godot(Vector3(6000, 1000, 0))
	var c00 := db.get_cell("ext:0,0")
	var t := db.get_terrain(c00["terrain"])
	var o: Array = t["origin_godot"]
	var expected := MWTerrain.height_at(t, probe - Vector3(o[0], o[1], o[2]))
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3(0, 200, 0), probe - Vector3(0, 200, 0)))
	check(not hit.is_empty() and absf(hit.position.y - expected) < 0.01, "kolizja terenu = wysokość z danych (%.3f vs %s)" % [expected, str(hit.get("position", "brak"))])

	# postać: spadek na teren
	var player := preload("res://scripts/player.gd").new() as CharacterBody3D
	world.add_child(player)
	player.global_position = probe + Vector3(0, expected + 3.0 - probe.y, 0)
	for i in 180:
		await physics_frame
	report["player_y"] = player.global_position.y
	report["terrain_y"] = expected
	check(player.is_on_floor() and absf(player.global_position.y - expected) < 0.1, "postać stoi na terenie (y=%.3f, teren %.3f)" % [player.global_position.y, expected])

	# --- CS 2.0: edycja i zapis nadpisań ------------------------------------------------------
	var ed := MWCellEditing.new(db, models)
	var cell := ed.open_cell("ext:0,1")
	check(cell != null, "CS: komórka ext:0,1 otwarta")
	var refs := cell.get_node("Refs")
	var n_before := refs.get_child_count()
	var moved: Node3D = null
	var removed_sid := ""
	for r in refs.get_children():
		if r.get_meta("mw_sid") == "mwg_synthtown.esm#2":
			moved = r
		elif r.get_meta("mw_sid") == "mwg_synthtown.esm#16":
			removed_sid = r.get_meta("mw_sid")
			refs.remove_child(r)
			r.free()
	check(moved != null, "CS: referencja #2 znaleziona")
	moved.position += Vector3(2, 0, -1)
	moved.rotate_y(deg_to_rad(45))
	ed.add_ref(cell, "synth_crate", Transform3D(Basis(), moved.position + Vector3(3, 0, 0)))
	var ov := ed.compute_overrides(cell)
	report["overrides"] = {"modified": ov.modified.keys(), "added": ov.added.size(), "deleted": ov.deleted}
	check(ov.modified.size() == 1 and ov.modified.has("mwg_synthtown.esm#2"), "CS: dokładnie 1 zmieniona referencja")
	check(ov.added.size() == 1 and ov.added[0]["sid"] == "project#1", "CS: 1 dodana (project#1)")
	check(ov.deleted == [removed_sid], "CS: 1 usunięta (%s)" % removed_sid)
	# pozycja MW zapisana w nadpisaniu zgodna z transformacją
	var mwpos: Array = ov.modified["mwg_synthtown.esm#2"]["mw"]["pos"]
	var expect := MWCoords.godot_to_mw(moved.position)
	check(Vector3(mwpos[0], mwpos[1], mwpos[2]).distance_to(expect) < 1e-3, "CS: pozycja MW w nadpisaniu")
	check(ed.save(cell) == OK, "CS: zapis nadpisań")
	report["override_file"] = db.override_path("ext:0,1")
	# żadnych zasobów gry w zapisanej scenie: pakujemy i sprawdzamy, że modele nie są zapisywane
	var ps := PackedScene.new()
	ps.pack(cell)
	var st := ps.get_state()
	var has_mesh := false
	for i in st.get_node_count():
		if st.get_node_type(i) == "MeshInstance3D":
			has_mesh = true
	check(not has_mesh, "CS: scena robocza nie zawiera siatek (tylko transformacje i metadane)")
	report["scene_nodes"] = st.get_node_count()
	cell.free()
	# plik roboczy .tscn (jak we wtyczce): zapis → wczytanie → odtworzenie modeli i terenu
	var cell2 := ed.open_cell("ext:0,1")
	cell2.set_script(preload("res://addons/mw_cs2/mw_cell_root.gd"))
	cell2.set("data_root", db.data_root)
	cell2.set("project_root", db.project_root)
	cell2.set("cell_key", "ext:0,1")
	var ps2 := PackedScene.new()
	ps2.pack(cell2)
	cell2.free()
	ResourceSaver.save(ps2, "user://cs2_test_cell.tscn")
	var txt := FileAccess.get_file_as_string("user://cs2_test_cell.tscn")
	report["tscn_bytes"] = txt.length()
	check(not txt.contains("ArrayMesh") and not txt.contains(".glb") and not txt.contains(".png"), "CS: .tscn bez odwołań do zasobów gry")
	var reopened := (load("user://cs2_test_cell.tscn") as PackedScene).instantiate()
	root.add_child(reopened)
	var meshes := reopened.find_children("*", "MeshInstance3D", true, false)
	report["reopened_meshes"] = meshes.size()
	check(meshes.size() > 10, "CS: po ponownym otwarciu modele i teren odtworzone (%d siatek)" % meshes.size())
	var refs2 := reopened.get_node("Refs").get_child_count()
	check(refs2 == 8, "CS: po ponownym otwarciu 8 referencji (z nadpisaniami: %d)" % refs2)
	reopened.free()
	check(n_before == 8, "CS: komórka ext:0,1 miała 8 referencji (było %d)" % n_before)

func _phase_verify(db: MWWorldDB, models: MWModelCache) -> void:
	# po (ponownym) imporcie danych: nadpisania projektu nadal działają
	var c := db.get_cell("ext:0,1")
	var by_sid := {}
	for r in c["refs"]:
		by_sid[r["sid"]] = r
	check(not by_sid.has("mwg_synthtown.esm#16"), "verify: usunięta referencja nie wraca po imporcie")
	check(by_sid.has("project#1"), "verify: dodana referencja obecna")
	check(by_sid.has("mwg_synthtown.esm#2") and by_sid["mwg_synthtown.esm#2"].get("project_modified", false), "verify: zmiana #2 zachowana")
	check(by_sid.has("mwg_synthtown_patch.esp#1"), "verify: referencja z pluginu nadal obecna")
	report["refs_after"] = by_sid.size()
	report["orphans"] = c.get("override_orphans", [])
	report["sources"] = c.get("sources", [])
	var extra_src := arg("expect-source")
	if not extra_src.is_empty():
		check(extra_src in c.get("sources", []), "verify: nowy plugin %s widoczny w źródłach komórki" % extra_src)
		var found := false
		for r in c["refs"]:
			if r.get("source", "") == extra_src:
				found = true
		check(found, "verify: referencja z nowego pluginu obecna")
