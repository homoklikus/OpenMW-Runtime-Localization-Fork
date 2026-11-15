extends SceneTree
## Construction Set 2.0: edycja terenu (pędzle, krawędzie bez szczelin, malowanie tekstur, zapis jako
## nadpisanie), edycja rekordu bazowego, lista konfliktów modów.
## godot --headless --path godot -s res://tests/test_cs2.gd -- --data=WYNIKI --project=KATALOG

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

func _init() -> void:
	var data := arg("data")
	var project := arg("project")
	var db := MWWorldDB.new(data, project)
	var te := MWTerrainEditing.new(db)
	# narożnik czterech komórek (0,0),(1,0),(0,1),(1,1) = punkt MW (8192, 8192)
	var corner := MWCoords.mw_to_godot(Vector3(8192, 8192, 0))
	var h0 := te.height_at(corner + Vector3(0.01, 0, -0.01))
	var changed := te.brush(MWTerrainEditing.Op.RAISE, corner, 10.0, 2.0)
	report["changed_cells"] = changed.size()
	check(changed.size() == 4, "pędzel w narożniku zmienia 4 komórki (%d)" % changed.size())
	var h1 := te.height_at(corner + Vector3(0.01, 0, -0.01))
	check(absf(h1 - h0 - 2.0) < 0.05, "podniesienie o 2 m w środku pędzla (%.3f → %.3f)" % [h0, h1])
	# krawędź (0,0)/(1,0): wierzchołek i=64 w (0,0) == i=0 w (1,0) dla każdego j
	var a: PackedFloat32Array = te.cells[Vector2i(0, 0)]["h"]
	var b: PackedFloat32Array = te.cells[Vector2i(1, 0)]["h"]
	var worst := 0.0
	for j in 65:
		worst = maxf(worst, absf(a[j * 65 + 64] - b[j * 65 + 0]))
	check(worst < 1e-5, "krawędź komórek bez szczeliny (maks. różnica %f)" % worst)
	# wygładzanie i spłaszczanie
	te.brush(MWTerrainEditing.Op.FLATTEN, corner, 6.0, 1.0, h0)
	var h2 := te.height_at(corner + Vector3(0.01, 0, -0.01))
	check(absf(h2 - h0) < 0.05, "spłaszczenie do wysokości docelowej")
	te.brush(MWTerrainEditing.Op.SMOOTH, corner, 12.0, 1.0)
	# malowanie
	var p := MWCoords.mw_to_godot(Vector3(2000, 2000, 0))
	te.brush(MWTerrainEditing.Op.PAINT, p, 5.0, 1.0, 0.0, "textures/tx_synth_dirt.png")
	var c00: Dictionary = te.cells[Vector2i(0, 0)]
	var tidx: int = c00["grid"][3 * 16 + 3]  # kafel (3,3) zawiera punkt (2000,2000) MW: 2000/512 = 3.9
	check(c00["palette"][tidx] == "textures/tx_synth_dirt.png", "malowanie tekstury terenu")
	var n := te.save()
	check(n == 4, "zapisano 4 nadpisania terenu (%d)" % n)
	# ponowne wczytanie przez warstwę danych (jak gra)
	var db2 := MWWorldDB.new(data, project)
	var t := db2.get_terrain("terrain/0_0.json")
	check(t.get("project_modified", false), "gra widzi zmieniony teren (nadpisanie projektu)")
	var te2 := MWTerrainEditing.new(db2)
	var h3 := te2.height_at(corner + Vector3(0.01, 0, -0.01))
	report["heights"] = [h0, h1, h2, h3]
	check(absf(h3 - te.height_at(corner + Vector3(0.01, 0, -0.01))) < 1e-4, "wysokość po ponownym wczytaniu")
	var mesh := MWTerrain.build(t, data, true)
	check(mesh != null, "siatka terenu z nadpisania")
	if mesh:
		mesh.free()
	# promień w teren
	var hit = te2.raycast(corner + Vector3(0.5, 100, -0.5), Vector3(0, -1, 0))
	check(hit != null and absf(hit.y - te2.height_at(hit)) < 0.01, "raycast w teren (pędzel w widoku 3D)")
	# rekord bazowy
	check(db2.save_object_override("synth_crate", {"name": "Skrzynka z projektu", "light": {"radius": 300, "color": [255, 0, 0]}}) == OK, "zapis zmian rekordu bazowego")
	var db3 := MWWorldDB.new(data, project)
	var o := db3.get_object("synth_crate")
	check(o.get("name") == "Skrzynka z projektu" and o.get("project_modified", false), "gra widzi zmieniony rekord bazowy")
	check(o.get("overridden", []).has("mwg_synthtown.esm"), "historia rekordu: ESM → plugin (%s)" % str(o.get("overridden")))
	# konflikty modów
	var conf := db3.cell_conflicts("ext:0,1")
	report["conflicts"] = conf
	var hut := conf.filter(func(x): return x["sid"] == "mwg_synthtown.esm#1")
	check(hut.size() == 1 and hut[0]["chain"] == ["mwg_synthtown.esm", "mwg_synthtown_patch.esp"], "konflikt: chata #1 ESM → patch")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
