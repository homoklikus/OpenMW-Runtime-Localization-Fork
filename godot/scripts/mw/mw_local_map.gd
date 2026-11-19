extends Node
## Mapa lokalna (etap 10) jak OpenMW LocalMap: obszar podzielony na segmenty po 8192 jedn. (komórka zewnętrzna
## = segment; wnętrze – siatka segmentów nad prostokątem obejmującym referencje, obrócona tak, by NorthMarker
## wskazywał górę mapy). Obraz segmentu: widok z góry kamerą ortogonalną renderowany raz (SubViewport) bez mgły,
## z jasnym światłem otoczenia. Mgła wojny: 32 × 32 na segment, odkrywanie w promieniu 0,17 segmentu wokół gracza
## z łagodnym brzegiem (alfa = min(stara, odl² / r² × 255)) w siatce 3 × 3 – jak LocalMap::updatePlayer;
## stan mgły w zapisie (player.map_fog).

const FOG_RES := 32
const RES := 256                         # OpenMW „local map resolution”
var seg_m := MWCoords.CELL_SIZE / MWCoords.UNITS_PER_METER

var main
var area := ""                           # "ext" albo "int:<nazwa>"
var angle := 0.0                         # obrót mapy wnętrza (NorthMarker), radiany wokół osi Y Godota
var origin := Vector2.ZERO               # początek siatki segmentów w układzie mapy (q)
var seg_min := Vector2i.ZERO             # wnętrze: zakres segmentów
var seg_max := Vector2i.ZERO
var _tex := {}                           # klucz segmentu → Texture2D
var _fog := {}                           # klucz segmentu → PackedByteArray (FOG_RES²)
var _pending := {}
var _t := 0.0
var rendered := 0                        # testy
var top_y := 0.0                         # wnętrze: zMax / zMin geometrii (kamera od zMax + 5 jedn. do zMin)
var bottom_y := 0.0
const INTERIOR_PADDING := 500.0          # LocalMap: „Do NOT change padding!”
const MAP_BRIGHTNESS := 0.9              # podłoga w świetle mapy OpenMW: ambient 0,3 + 0,7 × lambert (−0,3, −0,3, 0,7)

## Obszar po wejściu do komórki: zewnętrze – bez obrotu; wnętrze – obrót z NorthMarker i zakres z referencji.
func set_area(new_area: String, refs_root: Node = null) -> void:
	if new_area == area and not new_area.begins_with("int:"):
		return
	area = new_area
	angle = 0.0
	origin = Vector2.ZERO
	if area.begins_with("int:") and refs_root != null:
		# LocalMap::requestInteriorMap: granice sceny (geometria modeli), obrót wg NorthMarker, margines 500 jedn.
		var pts: Array = []
		top_y = -INF
		bottom_y = INF
		for n in refs_root.get_children():
			if not n is Node3D:
				continue
			if String(n.get_meta("mw_base", "")).to_lower() == "northmarker":
				angle = (n as Node3D).global_rotation.y
			var box := _node_aabb(n as Node3D)
			if box.size == Vector3.ZERO:
				pts.append((n as Node3D).global_position)
				continue
			for i in 8:
				pts.append(box.get_endpoint(i))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			var q := to_q(p)
			lo = lo.min(q)
			hi = hi.max(q)
			top_y = maxf(top_y, p.y)
			bottom_y = minf(bottom_y, p.y)
		if pts.is_empty():
			lo = Vector2.ZERO
			hi = Vector2.ZERO
			top_y = 0.0
			bottom_y = 0.0
		var pad := INTERIOR_PADDING / MWCoords.UNITS_PER_METER
		origin = lo - Vector2(pad, pad)
		seg_min = Vector2i.ZERO
		seg_max = Vector2i(floori((hi.x + pad - origin.x) / seg_m), floori((hi.y + pad - origin.y) / seg_m))

## Prostokąt otaczający geometrię węzła (siatki wizualne) w układzie świata.
static func _node_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		if not v.visible:
			continue
		var b := v.global_transform * v.get_aabb()
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box

## Punkt świata (Godot) → układ mapy q (x w prawo, y w dół; północ u góry).
func to_q(p: Vector3) -> Vector2:
	var v := Vector2(p.x, p.z).rotated(angle)              # obrót o −kąt mapy (oś Y Godota: znak przeciwny)
	return v

func q_to_world(q: Vector2, y: float) -> Vector3:
	var v := q.rotated(-angle)
	return Vector3(v.x, y, v.y)

## Segment i położenie w nim (0..1) dla punktu świata.
func locate(p: Vector3) -> Dictionary:
	var q := to_q(p) - origin
	var s := Vector2i(floori(q.x / seg_m), floori(q.y / seg_m))
	return {"seg": s, "uv": Vector2(q.x / seg_m - s.x, q.y / seg_m - s.y), "f": q / seg_m}

func seg_key(s: Vector2i) -> String:
	return "%s|%d|%d" % [area, s.x, s.y]

## Segmenty widoczne wokół gracza: zewnętrze 3 × 3, wnętrze – wszystkie.
func visible_segments(player_pos: Vector3) -> Array:
	var out := []
	if area.begins_with("int:"):
		for j in range(seg_min.y, seg_max.y + 1):
			for i in range(seg_min.x, seg_max.x + 1):
				out.append(Vector2i(i, j))
	else:
		var s: Vector2i = locate(player_pos).seg
		for j in range(-1, 2):
			for i in range(-1, 2):
				out.append(s + Vector2i(i, j))
	return out

# --- obraz segmentu -----------------------------------------------------------------------------------

func texture(s: Vector2i) -> Texture2D:
	return _tex.get(seg_key(s))

## Segment już renderowany (także bez obrazu – brak renderera).
func has_render(s: Vector2i) -> bool:
	return _tex.has(seg_key(s))

## Renderuje segment (asynchronicznie – po klatce); bez renderera (tryb headless) obraz pozostaje pusty.
func request(s: Vector2i, cam_y: float) -> void:
	var k := seg_key(s)
	if _tex.has(k) or _pending.has(k) or main == null:
		return
	_pending[k] = true
	_render(s, k, cam_y)

func _render(s: Vector2i, k: String, cam_y: float) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	# LocalMapRenderToTexture: bez oświetlenia sceny (własne światło mapy OpenMW ≈ stała jasność podłóg 0,9),
	# bez mgły; wnętrze – kamera od zMax + 5 jedn. do zMin (near 5, far zMax − zMin + 10)
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = seg_m
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var u := 1.0 / MWCoords.UNITS_PER_METER
	var ztop := cam_y
	if area.begins_with("int:"):
		ztop = top_y + 5.0 * u
		cam.near = 5.0 * u
		cam.far = maxf(top_y - bottom_y, 0.0) + 10.0 * u
	else:
		cam.near = 0.5
		cam.far = 2000.0
	var center_q := origin + (Vector2(s) + Vector2(0.5, 0.5)) * seg_m
	cam.rotation = Vector3(-PI / 2.0, angle, 0.0)     # góra obrazu = północ (−Z obrócone o kąt mapy)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	cam.environment = env
	vp.add_child(cam)
	add_child(vp)
	cam.global_position = q_to_world(center_q, ztop)
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if vp.get_texture() != null else null
	vp.queue_free()
	_pending.erase(k)
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		var data := img.get_data()
		for i in range(0, data.size(), 4):
			data[i] = int(data[i] * MAP_BRIGHTNESS)
			data[i + 1] = int(data[i + 1] * MAP_BRIGHTNESS)
			data[i + 2] = int(data[i + 2] * MAP_BRIGHTNESS)
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
		_tex[k] = ImageTexture.create_from_image(img)
	else:
		_tex[k] = null                       # brak renderera – bez obrazu (mgła i znaczniki działają)
	rendered += 1

func forget_textures() -> void:
	_tex.clear()

# --- mgła wojny ---------------------------------------------------------------------------------------

func fog(s: Vector2i) -> PackedByteArray:
	var k := seg_key(s)
	if _fog.has(k):
		return _fog[k]
	var saved: Dictionary = main.state.player.get("map_fog", {}) if main != null else {}
	var data := PackedByteArray()
	if saved.has(k):
		var raw := Marshalls.base64_to_raw(String(saved[k]))
		data = raw.decompress(FOG_RES * FOG_RES, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != FOG_RES * FOG_RES:
		data = PackedByteArray()
		data.resize(FOG_RES * FOG_RES)
		data.fill(255)
	_fog[k] = data
	return data

func explored(s: Vector2i, uv: Vector2) -> bool:
	var d := fog(s)
	var tu := clampi(int((FOG_RES - 1) * uv.x), 0, FOG_RES - 1)
	var tv := clampi(int((FOG_RES - 1) * uv.y), 0, FOG_RES - 1)
	return d[tv * FOG_RES + tu] < 200

## LocalMap::updatePlayer: odkrywanie mgły w segmencie gracza i sąsiednich, gdy promień sięga ich brzegu.
func update_player(p: Vector3) -> void:
	var L := locate(p)
	var s: Vector2i = L.seg
	var u: float = L.uv.x
	var v: float = L.uv.y
	var r := 0.17 * (FOG_RES - 1)
	var r2 := r * r
	var r_uv := r / FOG_RES
	for my in range(-1, 2):
		for mx in range(-1, 2):
			var affected := mx == 0 and my == 0
			if not affected:
				var ax := (u + r_uv > 1.0) if mx > 0 else (u - r_uv < 0.0)
				var ay := (v + r_uv > 1.0) if my > 0 else (v - r_uv < 0.0)
				affected = (ax and my == 0) or (ay and mx == 0) or (ax and ay)
			if not affected:
				continue
			var seg := s + Vector2i(mx, my)
			if area.begins_with("int:") and (seg.x < seg_min.x or seg.y < seg_min.y or seg.x > seg_max.x or seg.y > seg_max.y):
				continue
			var d := fog(seg)
			var changed := false
			for tv in FOG_RES:
				for tu in FOG_RES:
					var dx := (tu + mx * (FOG_RES - 1)) - u * (FOG_RES - 1)
					var dy := (tv + my * (FOG_RES - 1)) - v * (FOG_RES - 1)
					var a := mini(d[tv * FOG_RES + tu], int(clampf((dx * dx + dy * dy) / r2, 0.0, 1.0) * 255.0))
					if a != d[tv * FOG_RES + tu]:
						d[tv * FOG_RES + tu] = a
						changed = true
			if changed:
				_store(seg_key(seg), d)

func _store(k: String, d: PackedByteArray) -> void:
	if main == null:
		return
	var saved: Dictionary = main.state.player.get("map_fog", {})
	saved[k] = Marshalls.raw_to_base64(d.compress(FileAccess.COMPRESSION_DEFLATE))
	main.state.player["map_fog"] = saved

func fog_texture(s: Vector2i) -> ImageTexture:
	var d := fog(s)
	var img := Image.create(FOG_RES, FOG_RES, false, Image.FORMAT_RGBA8)
	for tv in FOG_RES:
		for tu in FOG_RES:
			img.set_pixel(tu, tv, Color(0, 0, 0, d[tv * FOG_RES + tu] / 255.0))
	return ImageTexture.create_from_image(img)

## Po wczytaniu zapisu: mgła z nowego stanu.
func reset_fog() -> void:
	_fog.clear()

func tick(delta: float, player_pos: Vector3) -> void:
	_t += delta
	if _t < 0.2:
		return
	_t = 0.0
	update_player(player_pos)
