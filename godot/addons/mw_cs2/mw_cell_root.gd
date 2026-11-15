@tool
extends Node3D
## Korzeń edytowanej komórki (Construction Set 2.0). Plik .tscn przechowuje wyłącznie transformacje
## i metadane referencji; modele i teren są odtwarzane przy otwarciu z lokalnych danych gracza.

@export var data_root := ""
@export var project_root := ""
@export var cell_key := ""

func _ready() -> void:
	if data_root.is_empty() or cell_key.is_empty():
		return
	rebuild_visuals()

func rebuild_visuals() -> void:
	var db := MWWorldDB.new(data_root, project_root)
	var models := MWModelCache.new(data_root)
	var b := MWCellBuilder.new(db, models)
	b.editor_mode = true
	set_meta("mw_cell_key", cell_key)
	# teren
	for c in get_children():
		if c.name.begins_with("Terrain_"):
			c.free()
	var cell := db.get_cell(cell_key)
	if cell.get("terrain") != null:
		var tn := MWTerrain.build(db.get_terrain(cell["terrain"]), data_root, false)
		if tn:
			add_child(tn)
			move_child(tn, 0)
	# modele referencji
	var refs := get_node_or_null("Refs")
	if refs == null:
		return
	for r in refs.get_children():
		if r.get_node_or_null("Model") != null or r.get_node_or_null("Light") != null:
			continue
		var tmp := b.build_ref({"sid": r.get_meta("mw_sid", ""), "base": r.get_meta("mw_base", ""),
			"godot": {"origin": [0, 0, 0], "quat": [0, 0, 0, 1], "scale": 1.0}})
		for ch in tmp.get_children():
			tmp.remove_child(ch)
			r.add_child(ch)  # bez właściciela ⇒ nie trafia do zapisu sceny
		tmp.free()
