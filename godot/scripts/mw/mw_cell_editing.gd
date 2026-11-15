class_name MWCellEditing
extends RefCounted
## Logika edycji komórek wspólna dla wtyczki Construction Set 2.0 i testów headless.
##
## Komórka edytowana to scena Godota: korzeń z meta mw_cell_key, dzieci "Refs/<MWRef>".
## Model 3D referencji jest dzieckiem bez właściciela (owner = null), więc NIE trafia do zapisanej sceny –
## w pliku .tscn zostają tylko transformacje i metadane (żadnych zasobów Bethesdy).
## Zapis tworzy plik nadpisań projektu (modified / added / deleted) względem warstwy importu.

const POS_EPS := 1e-4
const ROT_EPS := 1e-5

var db: MWWorldDB
var models: MWModelCache

func _init(world_db: MWWorldDB, model_cache: MWModelCache) -> void:
	db = world_db
	models = model_cache

## Buduje edytowalną scenę komórki. `owner_root` – węzeł, który ma być właścicielem (zapis do .tscn).
func open_cell(key: String) -> Node3D:
	var b := MWCellBuilder.new(db, models)
	b.editor_mode = true
	var root := b.build_cell(key)
	if root == null:
		return null
	_set_owners(root)
	return root

static func _set_owners(root: Node3D) -> void:
	var refs := root.get_node_or_null("Refs")
	if refs:
		refs.owner = root
		for r in refs.get_children():
			r.owner = root   # MWRef – zapisywany; jego dzieci (model) celowo bez właściciela
	for c in root.get_children():
		if c.name.begins_with("Terrain_"):
			c.owner = null

## Dodaje nową referencję (obiekt bazowy z objects.json) w pozycji Godota.
func add_ref(root: Node3D, base_id: String, at: Transform3D) -> Node3D:
	var used := {}
	for r in root.get_node("Refs").get_children():
		used[String(r.get_meta("mw_sid", ""))] = true
	var k := 1
	while used.has("project#%d" % k):
		k += 1
	var sid := "project#%d" % k
	var rec := {"sid": sid, "base": base_id, "source": "project"}
	rec.merge(MWCoords.transform_to_ref_fields(at))
	var b := MWCellBuilder.new(db, models)
	b.editor_mode = true
	var n := b.build_ref(rec)
	n.set_meta("mw_project_added", true)
	root.get_node("Refs").add_child(n)
	n.owner = root
	return n

## Porównuje scenę z warstwą importu i zwraca słownik nadpisań.
func compute_overrides(root: Node3D) -> Dictionary:
	var key: String = root.get_meta("mw_cell_key")
	var raw := db.raw_cell(key)
	var imported := {}
	for r in raw.get("refs", []):
		imported[r["sid"]] = r
	var modified := {}
	var added := []
	var present := {}
	for n in root.get_node("Refs").get_children():
		var sid := String(n.get_meta("mw_sid", ""))
		present[sid] = true
		var fields := MWCoords.transform_to_ref_fields(n.transform)
		if imported.has(sid):
			var orig := MWCoords.ref_transform(imported[sid])
			if not _same(orig, n.transform):
				modified[sid] = fields
			if n.has_meta("mw_extra") and imported[sid].get("extra", {}) != n.get_meta("mw_extra"):
				modified.get_or_add(sid, fields)["extra"] = n.get_meta("mw_extra")
			if String(n.get_meta("mw_base", "")).to_lower() != String(imported[sid].get("base", "")).to_lower():
				modified.get_or_add(sid, fields)["base"] = n.get_meta("mw_base")
		else:
			var rec := {"sid": sid, "base": n.get_meta("mw_base", ""), "source": "project"}
			rec.merge(fields)
			if n.has_meta("mw_extra"):
				rec["extra"] = n.get_meta("mw_extra")
			added.append(rec)
	var deleted := []
	for sid in imported:
		if not present.has(sid):
			deleted.append(sid)
	deleted.sort()
	return {"modified": modified, "added": added, "deleted": deleted}

func save(root: Node3D) -> Error:
	var ov := compute_overrides(root)
	return db.save_overrides(root.get_meta("mw_cell_key"), ov)

static func _same(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > POS_EPS:
		return false
	var sa := a.basis.get_scale()
	var sb := b.basis.get_scale()
	if sa.distance_to(sb) > POS_EPS:
		return false
	var qa := a.basis.orthonormalized().get_rotation_quaternion()
	var qb := b.basis.orthonormalized().get_rotation_quaternion()
	return absf(qa.dot(qb)) > 1.0 - ROT_EPS
