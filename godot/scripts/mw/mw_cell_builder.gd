class_name MWCellBuilder
extends RefCounted
## Buduje węzeł Godota dla komórki: teren + referencje (modele GLB, światła) + metadane.
## Każda referencja to Node3D "MWRef" z meta: mw_sid, mw_base, mw_source – używane przez grę i CS 2.0.

var db: MWWorldDB
var models: MWModelCache
var editor_mode := false        # CS 2.0: bez kolizji terenu, modele jako dzieci bez właściciela
var with_lights := true
var with_water := true
var stats := {"cells": 0, "refs": 0, "missing_model": 0, "no_model": 0, "build_ms": 0.0}

func _init(world_db: MWWorldDB, model_cache: MWModelCache) -> void:
	db = world_db
	models = model_cache

func build_cell(key: String) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var c := db.get_cell(key)
	if c.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Cell_" + key.replace(":", "_").replace(",", "_").replace(" ", "_")
	root.set_meta("mw_cell_key", key)
	root.set_meta("mw_cell_name", c.get("name", ""))
	if not c.get("interior", false) and c.get("terrain") != null:
		var t := db.get_terrain(c["terrain"])
		var tn := MWTerrain.build(t, db.data_root, not editor_mode)
		if tn:
			root.add_child(tn)
	if with_water and c.get("has_water", false):
		if c.get("interior", false):
			root.add_child(MWEnvironment.water_plane(600.0, float(c.get("water_height_m", 0.0))))
		elif c.has("origin_godot"):
			var o: Array = c["origin_godot"]
			var size := MWCoords.CELL_SIZE / MWCoords.UNITS_PER_METER
			var w := MWEnvironment.water_plane(size, float(c.get("water_height_m", 0.0)))
			w.position = Vector3(o[0] + size / 2.0, w.position.y, o[2] - size / 2.0)
			root.add_child(w)
	var refs_node := Node3D.new()
	refs_node.name = "Refs"
	root.add_child(refs_node)
	for r in c.get("refs", []):
		var n := build_ref(r)
		if n:
			refs_node.add_child(n)
	stats.cells += 1
	stats.build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return root

func build_ref(r: Dictionary) -> Node3D:
	var base := db.get_object(r.get("base", ""))
	var n := Node3D.new()
	n.name = _safe_name(r.get("base", "ref") + "_" + String(r.get("sid", "")).get_slice("#", 1))
	n.transform = MWCoords.ref_transform(r)
	n.set_meta("mw_sid", r.get("sid", ""))
	n.set_meta("mw_base", r.get("base", ""))
	n.set_meta("mw_source", r.get("source", ""))
	if r.has("extra"):
		n.set_meta("mw_extra", r["extra"])
	stats.refs += 1
	if base.is_empty():
		n.set_meta("mw_missing_base", true)
		return n
	var glb: String = base.get("glb", "")
	if not glb.is_empty():
		var m := models.instantiate(glb)
		if m:
			m.name = "Model"
			n.add_child(m)
		else:
			stats.missing_model += 1
			n.add_child(_placeholder())
	else:
		stats.no_model += 1
	if with_lights and base.has("light"):
		var L: Dictionary = base["light"]
		var ol := OmniLight3D.new()
		ol.name = "Light"
		var col: Array = L.get("color", [255, 255, 255])
		ol.light_color = Color8(int(col[0]), int(col[1]), int(col[2]))
		ol.omni_range = float(L.get("radius", 256)) / MWCoords.UNITS_PER_METER
		ol.light_energy = 1.0
		ol.light_negative = L.get("negative", false)
		ol.shadow_enabled = false
		n.add_child(ol)
	return n

func _placeholder() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	mi.mesh = bm
	return mi

static func _safe_name(s: String) -> String:
	for ch in [".", ":", "@", "/", "\"", "%", "#", " "]:
		s = s.replace(ch, "_")
	return s
