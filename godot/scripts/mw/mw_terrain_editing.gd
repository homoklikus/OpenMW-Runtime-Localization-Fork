class_name MWTerrainEditing
extends RefCounted
## Edycja terenu dla Construction Set 2.0 (logika bez UI – testowalna headless).
##
## Teren komórki: 65×65 wysokości (m), sąsiednie komórki współdzielą wierzchołki krawędzi. Pędzel działa
## w układzie świata na wszystkich komórkach w zasięgu, więc krawędzie pozostają zgodne (bez szczelin).
## Zmiany zapisywane są jako nadpisania projektu: <projekt>/overrides/terrain/<x>_<y>.json – import z ESM
## pozostaje nietknięty.

enum Op { RAISE, LOWER, SMOOTH, FLATTEN, PAINT }

var db: MWWorldDB
var cells := {}     # Vector2i → {"t": słownik terenu, "h": PackedFloat32Array, "grid": PackedByteArray, "palette": Array}
var dirty := {}     # Vector2i → true

func _init(world_db: MWWorldDB) -> void:
	db = world_db

func load_cell(g: Vector2i) -> bool:
	if cells.has(g):
		return true
	var c := db.get_cell(db.exterior_key(g))
	if c.is_empty() or c.get("terrain") == null:
		return false
	var t := db.get_terrain(c["terrain"])
	if t.is_empty() or t.get("heights_f32_b64") == null:
		return false
	cells[g] = {
		"t": t,
		"h": Marshalls.base64_to_raw(t["heights_f32_b64"]).to_float32_array(),
		"grid": Marshalls.base64_to_raw(t["texture_grid_u8_b64"]) if t.has("texture_grid_u8_b64") else PackedByteArray(),
		"palette": (t.get("texture_palette", []) as Array).duplicate(),
	}
	return true

static func cell_size_m() -> float:
	return MWCoords.CELL_SIZE / MWCoords.UNITS_PER_METER

static func spacing_m() -> float:
	return 128.0 / MWCoords.UNITS_PER_METER

## Pozycja świata wierzchołka (i, j) komórki g.
static func vertex_world(g: Vector2i, i: int, j: int) -> Vector3:
	var s := cell_size_m()
	return Vector3(g.x * s + i * spacing_m(), 0.0, -(g.y * s + j * spacing_m()))

func height_at(p: Vector3) -> float:
	var g := MWCoords.cell_of(p)
	if not load_cell(g):
		return NAN
	var c: Dictionary = cells[g]
	var t: Dictionary = c["t"].duplicate()
	t["heights_f32_b64"] = Marshalls.raw_to_base64(c["h"].to_byte_array())
	var o := vertex_world(g, 0, 0)
	return MWTerrain.height_at(t, p - o)

## Pędzel. Zwraca listę zmienionych komórek.
func brush(op: int, center: Vector3, radius: float, strength: float, flatten_to := 0.0, paint_texture := "") -> Array:
	var changed := []
	var s := cell_size_m()
	var gmin := MWCoords.cell_of(center + Vector3(-radius, 0, radius))
	var gmax := MWCoords.cell_of(center + Vector3(radius, 0, -radius))
	for gx in range(gmin.x, gmax.x + 1):
		for gy in range(gmin.y, gmax.y + 1):
			var g := Vector2i(gx, gy)
			if not load_cell(g):
				continue
			var any := false
			if op == Op.PAINT:
				any = _paint(g, center, radius, paint_texture)
			else:
				any = _heights(g, op, center, radius, strength, flatten_to)
			if any:
				dirty[g] = true
				changed.append(g)
	return changed

func _falloff(d: float, r: float) -> float:
	var x := clampf(1.0 - d / r, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)  # smoothstep

func _heights(g: Vector2i, op: int, center: Vector3, radius: float, strength: float, flatten_to: float) -> bool:
	var c: Dictionary = cells[g]
	var h: PackedFloat32Array = c["h"]
	var src := h.duplicate()
	var any := false
	for j in 65:
		for i in 65:
			var p := vertex_world(g, i, j)
			var d := Vector2(p.x - center.x, p.z - center.z).length()
			if d > radius:
				continue
			var w := _falloff(d, radius)
			var k := j * 65 + i
			match op:
				Op.RAISE:
					h[k] = src[k] + strength * w
				Op.LOWER:
					h[k] = src[k] - strength * w
				Op.FLATTEN:
					h[k] = lerpf(src[k], flatten_to, clampf(strength, 0.0, 1.0) * w)
				Op.SMOOTH:
					var avg := 0.0
					var n := 0
					for dj in [-1, 0, 1]:
						for di in [-1, 0, 1]:
							var ii: int = i + di
							var jj: int = j + dj
							if ii >= 0 and ii < 65 and jj >= 0 and jj < 65:
								avg += src[jj * 65 + ii]
								n += 1
					h[k] = lerpf(src[k], avg / n, clampf(strength, 0.0, 1.0) * w)
			any = true
	c["h"] = h
	return any

func _paint(g: Vector2i, center: Vector3, radius: float, texture: String) -> bool:
	var c: Dictionary = cells[g]
	var palette: Array = c["palette"]
	var idx := palette.find(texture)
	if idx < 0:
		palette.append(texture)
		idx = palette.size() - 1
	var grid: PackedByteArray = c["grid"]
	if grid.size() < 256:
		grid.resize(256)
	var any := false
	var tile := cell_size_m() / 16.0
	var o := vertex_world(g, 0, 0)
	for ty in 16:
		for tx in 16:
			var p := o + Vector3((tx + 0.5) * tile, 0, -(ty + 0.5) * tile)
			if Vector2(p.x - center.x, p.z - center.z).length() <= radius:
				grid[ty * 16 + tx] = idx
				any = true
	c["grid"] = grid
	return any

## Normalne z wysokości (różnice centralne), w układzie Godota, int8 jak w danych.
static func normals_i8(h: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(65 * 65 * 3)
	var sp := spacing_m()
	for j in 65:
		for i in 65:
			var hl := h[j * 65 + maxi(i - 1, 0)]
			var hr := h[j * 65 + mini(i + 1, 64)]
			var hd := h[maxi(j - 1, 0) * 65 + i]
			var hu := h[mini(j + 1, 64) * 65 + i]
			var dx := (hr - hl) / (sp * (mini(i + 1, 64) - maxi(i - 1, 0)))
			var dn := (hu - hd) / (sp * (mini(j + 1, 64) - maxi(j - 1, 0)))  # wzdłuż północy (−Z)
			var n := Vector3(-dx, 1.0, dn).normalized()
			var k := (j * 65 + i) * 3
			out.encode_s8(k, int(round(n.x * 127)))
			out.encode_s8(k + 1, int(round(n.y * 127)))
			out.encode_s8(k + 2, int(round(n.z * 127)))
	return out

## Słownik terenu z bieżącymi zmianami (do budowy siatki w edytorze).
func terrain_dict(g: Vector2i) -> Dictionary:
	var c: Dictionary = cells[g]
	var t: Dictionary = c["t"].duplicate()
	var h: PackedFloat32Array = c["h"]
	t["heights_f32_b64"] = Marshalls.raw_to_base64(h.to_byte_array())
	t["normals_i8_b64"] = Marshalls.raw_to_base64(normals_i8(h))
	t["texture_palette"] = c["palette"]
	if (c["grid"] as PackedByteArray).size() == 256:
		t["texture_grid_u8_b64"] = Marshalls.raw_to_base64(c["grid"])
	var mn := INF
	var mx := -INF
	for v in h:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	t["height_min_m"] = mn
	t["height_max_m"] = mx
	t["project_modified"] = true
	return t

func save() -> int:
	var n := 0
	for g in dirty:
		var t := terrain_dict(g)
		var ov := {"format": "mwgodot-terrain-override", "version": 1, "grid": [g.x, g.y]}
		for k in ["heights_f32_b64", "normals_i8_b64", "texture_palette", "texture_grid_u8_b64", "height_min_m", "height_max_m"]:
			if t.has(k):
				ov[k] = t[k]
		if db.save_terrain_override(g, ov) == OK:
			n += 1
	dirty.clear()
	return n

## Przecięcie promienia z terenem (marsz + bisekcja) – do pędzla w widoku 3D edytora.
func raycast(from: Vector3, dir: Vector3, max_dist := 2000.0) -> Variant:
	dir = dir.normalized()
	var step := spacing_m() * 0.5
	var prev := from
	var prev_above := true
	var t := 0.0
	while t < max_dist:
		var p := from + dir * t
		var h := height_at(p)
		if not is_nan(h):
			var above := p.y > h
			if not above and prev_above and t > 0.0:
				var a := prev
				var b := p
				for k in 20:
					var m := (a + b) * 0.5
					var hm := height_at(m)
					if m.y > hm:
						a = m
					else:
						b = m
				return (a + b) * 0.5
			prev_above = above
		prev = p
		t += step
	return null
