extends SceneTree
## Roślinność (port forka OpenMW RLF): MultiMesh na model i komórkę, liczba roślin jak w danych konwertera,
## gęstość w grze (ranga), pozycje na terenie, bez kolizji i cieni, test alfa.
## godot --headless --path godot -s res://tests/test_flora.gd -- --data=WYNIKI

const Flora := preload("res://scripts/mw/mw_flora.gd")
var failures: Array[String] = []
var checks := 0

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

func _init() -> void:
	var data := arg("data")
	var models := MWModelCache.new(data)
	var fl = Flora.new(models, data)
	check(fl.is_active(), "index roślinności wczytany")
	var report := {"mode": fl.index.get("mode", ""), "cells": {}}
	var total := 0
	var built := 0
	for key in fl.index.get("cells", {}):
		var node: Node3D = fl.build_cell(key)
		check(node != null, "komórka %s zbudowana" % key)
		if node == null:
			continue
		var n := 0
		for mmi in node.get_children():
			check(mmi is MultiMeshInstance3D, "dziecko to MultiMeshInstance3D")
			check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "bez cieni")
			check(mmi.visibility_range_end > 0, "zasięg widoczności")
			var mat = mmi.multimesh.mesh.surface_get_material(0)
			check(mat is BaseMaterial3D and not mat.vertex_color_use_as_albedo, "kolor wierzchołków (znacznik wiatru MGE) nie barwi")
			check(mmi.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == null, "bez kolorów wierzchołków w siatce")
			check(mat is BaseMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "test alfa")
			n += mmi.multimesh.instance_count
		check(node.find_children("*", "StaticBody3D", true, false).is_empty(), "roślinność bez kolizji")
		check(n == fl.count_for(key), "%s: %d roślin (index: %d)" % [key, n, fl.count_for(key)])
		report["cells"][key] = n
		total += n
		built += 1
		root.add_child(node)
	# pozycja pierwszej rośliny = pozycja z pliku (MW → Godot)
	var key0: String = fl.index["cells"].keys()[0]
	var raw := FileAccess.get_file_as_bytes(data.path_join("world/flora").path_join(fl.index["cells"][key0]["file"]))
	var n0 := raw.decode_u32(6)
	var p := raw.slice(10).decompress(n0 * 24, FileAccess.COMPRESSION_DEFLATE)
	var mw := Vector3(p.decode_float(n0 * 2), p.decode_float(n0 * 6), p.decode_float(n0 * 10))
	var expected := MWCoords.mw_to_godot(mw)
	var found := false
	var dec: Dictionary = fl.decode_cell(key0)
	for mi in dec:
		for t in dec[mi]:
			if t.origin.distance_to(expected) < 0.01:
				found = true
	check(found, "pozycja rośliny zgodna z plikiem (MW → Godot)")
	# gęstość w grze: ranga 0–255 → ok. połowa przy 0.5
	var half = Flora.new(models, data)
	half.density = 0.5
	var nh := 0
	for key in half.index["cells"]:
		var nd: Node3D = half.build_cell(key)
		for mmi in nd.get_children():
			nh += mmi.multimesh.instance_count
		nd.free()
	check(nh > total * 0.4 and nh < total * 0.6, "gęstość 0.5 → ok. połowa (%d z %d)" % [nh, total])
	report["total"] = total
	report["half"] = nh
	report["stats"] = fl.stats
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
