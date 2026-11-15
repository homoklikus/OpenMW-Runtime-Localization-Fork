class_name MWCoords
extends RefCounted
## Przekształcenia Morrowind (Z w górę, jednostki gry) ↔ Godot (Y w górę, metry).
## godot(x, y, z) = (mw_x, mw_z, -mw_y) / UNITS_PER_METER — identycznie jak w konwerterze (coords.py).

const UNITS_PER_METER := 69.99125109
const CELL_SIZE := 8192.0

static func mw_to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y) / UNITS_PER_METER

static func godot_to_mw(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y) * UNITS_PER_METER

## Komórka zewnętrzna (gx, gy) zawierająca punkt Godota.
static func cell_of(p: Vector3) -> Vector2i:
	var mw := godot_to_mw(p)
	return Vector2i(floori(mw.x / CELL_SIZE), floori(mw.y / CELL_SIZE))

## Obrót referencji ESM (radiany) → Basis Godota. MW: R = Rx(-rx)·Ry(-ry)·Rz(-rz) (wektory kolumnowe).
static func mw_rot_to_basis(rot: Vector3) -> Basis:
	var r := _rx(-rot.x) * _ry(-rot.y) * _rz(-rot.z)
	return _mw_basis_to_godot(r)

## Basis Godota (bez skali) → kąty ESM (rx, ry, rz).
static func basis_to_mw_rot(b: Basis) -> Vector3:
	var r := _godot_basis_to_mw(b.orthonormalized())
	# r = Rx(a)·Ry(b)·Rz(c), a = -rx …; elementy macierzy: r[kolumna][wiersz]
	var r02 := r.z.x
	var sb: float = clamp(r02, -1.0, 1.0)
	var bb := asin(sb)
	var aa := 0.0
	var cc := 0.0
	if absf(sb) < 0.999999:
		aa = atan2(-r.z.y, r.z.z)
		cc = atan2(-r.y.x, r.x.x)
	else:
		aa = atan2(r.y.z, r.y.y)
	return Vector3(-aa, -bb, -cc)

static func _rx(a: float) -> Basis:
	return Basis(Vector3(1, 0, 0), a)

static func _ry(a: float) -> Basis:
	return Basis(Vector3(0, 1, 0), a)

static func _rz(a: float) -> Basis:
	return Basis(Vector3(0, 0, 1), a)

# M: (x, y, z)_mw → (x, z, -y)_godot ; R_g = M R M^T
static func _mw_basis_to_godot(r: Basis) -> Basis:
	var m := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))  # kolumny: obrazy osi MW
	return m * r * m.transposed()

static func _godot_basis_to_mw(r: Basis) -> Basis:
	var m := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	return m.transposed() * r * m

## Transform referencji z rekordu komórki (używa przeliczonych wartości "godot", gdy są).
static func ref_transform(ref: Dictionary) -> Transform3D:
	var g: Dictionary = ref.get("godot", {})
	var s: float = float(g.get("scale", 1.0))
	var q: Array = g.get("quat", [0, 0, 0, 1])
	var o: Array = g.get("origin", [0, 0, 0])
	var b := Basis(Quaternion(q[0], q[1], q[2], q[3])).scaled(Vector3(s, s, s))
	return Transform3D(b, Vector3(o[0], o[1], o[2]))

## Transform Godota → słownik pól "mw" i "godot" (do zapisu nadpisań CS 2.0).
static func transform_to_ref_fields(t: Transform3D) -> Dictionary:
	var s := t.basis.get_scale()
	var scale := (s.x + s.y + s.z) / 3.0
	var q := t.basis.orthonormalized().get_rotation_quaternion()
	var mwp := godot_to_mw(t.origin)
	var mwr := basis_to_mw_rot(t.basis)
	return {
		"mw": {"pos": [mwp.x, mwp.y, mwp.z], "rot": [mwr.x, mwr.y, mwr.z], "scale": scale},
		"godot": {"origin": [t.origin.x, t.origin.y, t.origin.z], "quat": [q.x, q.y, q.z, q.w], "scale": scale},
	}
