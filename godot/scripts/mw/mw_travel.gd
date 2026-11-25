class_name MWTravel
extends RefCounted
## Drzwi i przejścia między komórkami (DODT/DNAM z referencji).

## Znajduje referencję MW (węzeł z meta mw_sid) będącą przodkiem trafionego węzła.
static func ref_of(n: Node) -> Node3D:
	while n:
		if n.has_meta("mw_sid"):
			return n as Node3D
		n = n.get_parent()
	return null

## Cel podróży drzwi: {} gdy brak, inaczej {"cell_key": "int:…" lub "", "transform": Transform3D}.
## Pusty cell_key oznacza świat zewnętrzny (komórka wynika z pozycji).
static func door_destination(ref: Node) -> Dictionary:
	if ref == null or not ref.has_meta("mw_extra"):
		return {}
	var ex: Dictionary = ref.get_meta("mw_extra")
	if not ex.has("door_dest"):
		return {}
	var d: Dictionary = ex["door_dest"]
	var g: Dictionary = d.get("godot", {})
	var o: Array = g.get("origin", [0, 0, 0])
	var q: Array = g.get("quat", [0, 0, 0, 1])
	var cell := String(ex.get("door_dest_cell", ""))
	return {
		"cell_key": ("int:" + cell.to_lower()) if not cell.is_empty() else "",
		"cell_name": cell,
		"transform": Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(o[0], o[1], o[2])),
	}

## Promień „aktywacji” z kamery – zwraca referencję MW w zasięgu (domyślnie 3 m, jak w grze ~ 192 jedn.).
static func pick(camera: Camera3D, max_dist := 3.0) -> Node3D:
	return pick_hit(camera, max_dist).get("node")

## Jak pick, z odległością do punktu trafienia ({"node", "dist"}; brak trafienia – node = null).
static func pick_hit(camera: Camera3D, max_dist := 3.0, exclude: Array[RID] = []) -> Dictionary:
	var space := camera.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"node": null, "dist": INF}
	return {"node": ref_of(hit.collider), "dist": from.distance_to(hit.position)}
