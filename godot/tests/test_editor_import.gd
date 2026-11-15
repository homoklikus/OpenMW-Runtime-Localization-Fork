extends SceneTree
## Test importu edytorowego (ResourceImporterScene) syntetycznego GLB umieszczonego w res://.
## Wymaga wcześniejszego: godot --headless --path godot --import

func _init() -> void:
	var fails := []
	var ps := load("res://tests/_fixture/meshes/synth/test_hut.glb") as PackedScene
	if ps == null:
		fails.append("brak zaimportowanej sceny")
	else:
		var n := ps.instantiate()
		var meshes := n.find_children("*", "MeshInstance3D", true, false)
		var tex_ok := 0
		for m in meshes:
			var mat = (m as MeshInstance3D).get_active_material(0)
			if mat is BaseMaterial3D and mat.albedo_texture:
				tex_ok += 1
		print("editor import: meshes=%d textured=%d" % [meshes.size(), tex_ok])
		if meshes.size() < 3: fails.append("za mało siatek: %d" % meshes.size())
		if tex_ok < 3: fails.append("za mało teksturowanych siatek: %d" % tex_ok)
		n.free()
	print("RESULT ", JSON.stringify({"failures": fails}))
	quit(0 if fails.is_empty() else 1)
