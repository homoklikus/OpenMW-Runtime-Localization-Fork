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

func get_object(base_id: String) -> Dictionary:
	return _objects.get(base_id.to_lower(), {})

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

func get_terrain(rel: String) -> Dictionary:
	if rel.is_empty():
		return {}
	if not _terrain.has(rel):
		var t = _read_json(data_root.path_join("world").path_join(rel))
		_terrain[rel] = t if t is Dictionary else {}
	return _terrain[rel]
