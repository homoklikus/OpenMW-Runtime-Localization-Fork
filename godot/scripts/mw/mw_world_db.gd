class_name MWWorldDB
extends RefCounted
## Warstwa danych świata wspólna dla gry i Construction Set 2.0.
##
## Warstwy (od najniższej):
##   1. import  – <data_root>/world/…  (generowany przez konwerter z ESM/ESP; tylko do odczytu)
##   2. projekt – <project_root>/overrides/cells/<plik>.json (zmiany z CS 2.0: modified/added/deleted)
## Referencje identyfikowane są stabilnym `sid` ("plik-źródłowy#refnum"), więc ponowny import modów
## nie gubi zmian projektu.

const OVERRIDE_FORMAT := "mwgodot-overrides"

var data_root: String
var project_root: String
var _index: Array = []
var _objects: Dictionary = {}
var _cells: Dictionary = {}       # key → Dictionary (po nałożeniu nadpisań)
var _raw_cells: Dictionary = {}   # key → Dictionary (sam import)
var _terrain: Dictionary = {}
var load_errors: Array[String] = []

func _init(data: String, project := "") -> void:
	data_root = data
	project_root = project
	var idx = _read_json(data_root.path_join("world/index.json"))
	if idx is Dictionary:
		_index = idx.get("cells", [])
	var objs = _read_json(data_root.path_join("world/objects.json"))
	if objs is Dictionary:
		_objects = objs

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

static func _write_json(path: String, obj) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(obj, " ", false))
	f.close()
	return DirAccess.rename_absolute(tmp, path)

func cell_index() -> Array:
	return _index

func find_cell(key: String) -> Dictionary:
	for c in _index:
		if c["key"] == key:
			return c
	return {}

func exterior_key(g: Vector2i) -> String:
	return "ext:%d,%d" % [g.x, g.y]

var _object_overrides = null

## Rekord bazowy z nałożonymi zmianami projektu (overrides/objects.json: id → pola).
func get_object(base_id: String) -> Dictionary:
	var o: Dictionary = _objects.get(base_id.to_lower(), {})
	var ov: Dictionary = object_overrides().get(base_id.to_lower(), {})
	if ov.is_empty():
		return o
	var r := o.duplicate(true)
	for k in ov:
		r[k] = ov[k]
	r["project_modified"] = true
	return r

func object_overrides() -> Dictionary:
	if _object_overrides == null:
		_object_overrides = {}
		if not project_root.is_empty():
			var d = _read_json(project_root.path_join("overrides/objects.json"))
			if d is Dictionary:
				_object_overrides = d.get("objects", {})
	return _object_overrides

func save_object_override(base_id: String, fields: Dictionary) -> Error:
	if project_root.is_empty():
		return ERR_UNCONFIGURED
	var all := object_overrides().duplicate(true)
	var cur: Dictionary = all.get(base_id.to_lower(), {})
	for k in fields:
		cur[k] = fields[k]
	all[base_id.to_lower()] = cur
	_object_overrides = all
	return _write_json(project_root.path_join("overrides/objects.json"),
		{"format": "mwgodot-object-overrides", "version": 1, "objects": all})

## Konflikty modów w komórce: referencje zmieniane przez więcej niż jeden plik + nadpisania projektu.
func cell_conflicts(key: String) -> Array:
	var out := []
	for r in get_cell(key).get("refs", []):
		var chain: Array = r.get("overridden", [])
		if not chain.is_empty() or r.get("project_modified", false):
			var full := chain.duplicate()
			full.append(r.get("source", "?"))
			if r.get("project_modified", false):
				full.append("projekt")
			out.append({"sid": r["sid"], "base": r.get("base", ""), "chain": full})
	return out

func objects() -> Dictionary:
	return _objects

func raw_cell(key: String) -> Dictionary:
	if not _raw_cells.has(key):
		var info := find_cell(key)
		if info.is_empty():
			return {}
		var c = _read_json(data_root.path_join("world").path_join(info["file"]))
		_raw_cells[key] = c if c is Dictionary else {}
	return _raw_cells[key]

func override_path(key: String) -> String:
	var info := find_cell(key)
	if project_root.is_empty() or info.is_empty():
		return ""
	return project_root.path_join("overrides").path_join(info["file"])

func get_overrides(key: String) -> Dictionary:
	var p := override_path(key)
	if p.is_empty():
		return {}
	var o = _read_json(p)
	return o if o is Dictionary else {}

## Komórka po nałożeniu nadpisań projektu.
func get_cell(key: String) -> Dictionary:
	if _cells.has(key):
		return _cells[key]
	var raw := raw_cell(key)
	if raw.is_empty():
		return {}
	var c: Dictionary = raw.duplicate(true)
	var ov := get_overrides(key)
	if not ov.is_empty():
		var deleted: Dictionary = {}
		for sid in ov.get("deleted", []):
			deleted[sid] = true
		var modified: Dictionary = ov.get("modified", {})
		var refs: Array = []
		var orphans: Array = []
		for r in c["refs"]:
			if deleted.has(r["sid"]):
				continue
			if modified.has(r["sid"]):
				var m: Dictionary = modified[r["sid"]]
				for k in m:
					r[k] = m[k]
				r["project_modified"] = true
			refs.append(r)
		for sid in modified:
			var found := false
			for r in refs:
				if r["sid"] == sid:
					found = true
					break
			if not found:
				orphans.append(sid)  # referencja usunięta z modów – zmiana projektu bez celu
		for a in ov.get("added", []):
			var r: Dictionary = a.duplicate(true)
			r["project_added"] = true
			refs.append(r)
		c["refs"] = refs
		if not orphans.is_empty():
			c["override_orphans"] = orphans
	_cells[key] = c
	return c

func invalidate(key := "") -> void:
	if key.is_empty():
		_cells.clear()
	else:
		_cells.erase(key)

func save_overrides(key: String, ov: Dictionary) -> Error:
	var p := override_path(key)
	if p.is_empty():
		return ERR_UNCONFIGURED
	ov["format"] = OVERRIDE_FORMAT
	ov["version"] = 1
	ov["cell"] = key
	var err := _write_json(p, ov)
	invalidate(key)
	return err

func terrain_override_path(g: Vector2i) -> String:
	return "" if project_root.is_empty() else project_root.path_join("overrides/terrain/%d_%d.json" % [g.x, g.y])

## Teren komórki (import + ewentualne nadpisanie projektu z CS 2.0).
func get_terrain(rel: String) -> Dictionary:
	if rel.is_empty():
		return {}
	if not _terrain.has(rel):
		var t = _read_json(data_root.path_join("world").path_join(rel))
		var td: Dictionary = t if t is Dictionary else {}
		if not td.is_empty() and td.has("grid"):
			var g := Vector2i(int(td["grid"][0]), int(td["grid"][1]))
			var p := terrain_override_path(g)
			if not p.is_empty():
				var ov = _read_json(p)
				if ov is Dictionary:
					for k in ov:
						if k not in ["format", "version", "grid"]:
							td[k] = ov[k]
					td["project_modified"] = true
		_terrain[rel] = td
	return _terrain[rel]

func save_terrain_override(g: Vector2i, ov: Dictionary) -> Error:
	var p := terrain_override_path(g)
	if p.is_empty():
		return ERR_UNCONFIGURED
	var err := _write_json(p, ov)
	_terrain.erase("terrain/%d_%d.json" % [g.x, g.y])
	return err
