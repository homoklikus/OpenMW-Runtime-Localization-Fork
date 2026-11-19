extends CanvasLayer
## Okno mapy (etap 10) jak OpenMW MapWindow: mapa lokalna (segmenty widoku z góry wokół gracza, mgła wojny,
## drzwi do innych miejsc ze wskazaniem celu, strzałka gracza) i mapa świata (world/map/global.png z konwertera,
## znaczniki odwiedzonych nazwanych miejsc i odkrytych przez ShowMap, pozycja gracza; kółko myszy – przybliżenie).
## Przełącznik jak w OpenMW: przycisk „Świat”/„Lokalna”. Klawisz N (akcja „map_menu”).

signal closed

var main
var lmap                                 # MWLocalMap
var data_root := ""
var world_mode := false
var scale_ui := 1.0
var _root: Control
var _win: Control
var _view: Control
var _title: Label
var _toggle: Button
var _world_tex: Texture2D = null
var _world_info := {}
var _zoom := 1.0
var _scroll: ScrollContainer = null
var _world_rect: TextureRect = null
var door_markers: Array = []
var detect_markers: Array = []           # testy: [[rodzaj wykrycia, pozycja na mapie]]             # testy: [[nazwa celu, pozycja na mapie]]
var place_markers: Array = []            # testy: [[nazwa, x, y]]
var player_marker_pos := Vector2.ZERO    # testy
var _refresh_t := 0.0
var _waiting := false

const WIN := Vector2(600, 560)
const UI := preload("res://scripts/mw/mw_ui.gd")
var embedded := false                    # część trybu menu (okna jak w OpenMW: mapa obok ekwipunku, statystyk, magii)

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, def: String) -> String:
	return main.dialogue.gmst_text(gm, def) if main != null and main.dialogue != null else def

func _load_world() -> void:
	if not _world_info.is_empty():
		return
	var f := FileAccess.open(data_root.path_join("world/map/map.json"), FileAccess.READ)
	if f != null:
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_world_info = j
	var p := data_root.path_join("world/map/global.png")
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null:
			_world_tex = ImageTexture.create_from_image(img)

## rect – położenie okna w trybie menu (osadzone: bez pauzy i własnego zamykania – robi to tryb menu).
## Układ openmw_map_window.layout: pasek tytułu MW_Window_Pinnable (nazwa komórki, pinezka), widok mapy na całe
## wnętrze okna, przycisk World/Local 61 × 22 nad mapą 10 px od prawej i 9 px od dołu.
func open(rect := Rect2(), menu = null) -> void:
	_load_world()
	embedded = rect.size != Vector2.ZERO
	_menu = menu
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	scale_ui = UI.ui_scale()
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE if embedded else Control.MOUSE_FILTER_STOP
	_root.theme = UI.theme(UI.ui_scale())
	add_child(_root)
	_win = PanelContainer.new()
	var wsize: Vector2 = rect.size if embedded else WIN * scale_ui
	_win.position = rect.position.floor() if embedded else ((vp - wsize) / 2.0).floor()
	_win.custom_minimum_size = wsize
	_win.size = wsize
	_root.add_child(_win)
	var box := VBoxContainer.new()
	_win.add_child(box)
	_title = Label.new()
	_title.name = "Text"
	var head := UI.make_head(_title, scale_ui)
	head.name = "Title"
	head.gui_input.connect(_title_input)
	box.add_child(head)
	if embedded and _menu != null:
		var pin := UI.pin_button(scale_ui, _menu.is_pinned("map"))
		pin.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_menu.toggle_pin("map")
				UI.set_pin_skin(pin, _menu.is_pinned("map"))
				pin.accept_event())
		head.add_child(pin)
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(area)
	_view = Control.new()
	_view.clip_contents = true
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.custom_minimum_size = (wsize - Vector2(16, 36) * scale_ui).max(Vector2(64, 64)) if embedded else Vector2(WIN.x - 20, WIN.y - 60) * scale_ui
	area.add_child(_view)
	_toggle = Button.new()
	_toggle.name = "WorldButton"
	_toggle.pressed.connect(func(): set_world(not world_mode))
	_toggle.anchor_left = 1.0
	_toggle.anchor_right = 1.0
	_toggle.anchor_top = 1.0
	_toggle.anchor_bottom = 1.0
	_toggle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toggle.offset_right = -10.0 * scale_ui
	_toggle.offset_bottom = -9.0 * scale_ui
	_toggle.custom_minimum_size = Vector2(61, 22) * scale_ui
	area.add_child(_toggle)
	if not embedded:
		var close_b := Button.new()
		close_b.text = _t("sClose", "Close")
		close_b.pressed.connect(close)
		close_b.anchor_left = 0.0
		close_b.anchor_top = 1.0
		close_b.anchor_bottom = 1.0
		close_b.grow_vertical = Control.GROW_DIRECTION_BEGIN
		close_b.offset_left = 10.0 * scale_ui
		close_b.offset_bottom = -9.0 * scale_ui
		area.add_child(close_b)
	visible = true
	pinned_mode = false
	if not embedded:
		get_tree().paused = true
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_world(world_mode)

var _menu = null
var pinned_mode := false             # przypięta mapa poza trybem GUI (bez obsługi myszy)

func _title_input(e: InputEvent) -> void:
	if _menu != null:
		_menu._title_input(e, "map")
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and embedded and not pinned_mode:
		var vp := get_viewport().get_visible_rect().size
		_win.position = (_win.position + e.relative).clamp(Vector2.ZERO, vp - Vector2(40, 20))

func set_window_visible(on: bool) -> void:
	if _win != null:
		_win.visible = on

## Mapa przypięta: zostaje po zamknięciu trybu menu, bez reakcji na mysz (jak okna OpenMW poza trybem GUI).
func set_pinned_mode(on: bool) -> void:
	pinned_mode = on
	if _win != null:
		_win.visible = true
		_win.propagate_call("set", ["mouse_filter", Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP])

func set_world(on: bool) -> void:
	world_mode = on
	_toggle.text = _t("sLocal", "Local") if on else _t("sWorld", "World")
	for c in _view.get_children():
		c.queue_free()
	_scroll = null
	_world_rect = null
	if on:
		_build_world()
	else:
		_build_local()

# --- mapa lokalna ---------------------------------------------------------------------------------------

func _build_local() -> void:
	door_markers = []
	_waiting = false
	if main == null or main.player == null or lmap == null:
		return
	_title.text = main.display_location()
	var pp: Vector3 = main.player.global_position
	var T := 256.0 * scale_ui
	var center: Vector2 = _view.custom_minimum_size / 2.0
	var L: Dictionary = lmap.locate(pp)
	var pf: Vector2 = L.f
	var top_y: float = pp.y + 60.0
	var layer_tiles := Control.new()
	layer_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(layer_tiles)
	for s in lmap.visible_segments(pp):
		var pos: Vector2 = center + (Vector2(s) - pf) * T
		var tex: Texture2D = lmap.texture(s)
		if not lmap.has_render(s):
			_waiting = true
			lmap.request(s, top_y)
		if tex == null:
			var bg := ColorRect.new()
			bg.color = Color(0.12, 0.1, 0.08)
			bg.position = pos
			bg.size = Vector2(T, T)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer_tiles.add_child(bg)
		else:
			var r := TextureRect.new()
			r.texture = tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.position = pos
			r.size = Vector2(T, T)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer_tiles.add_child(r)
		var fog := TextureRect.new()
		fog.texture = lmap.fog_texture(s)
		fog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fog.stretch_mode = TextureRect.STRETCH_SCALE
		fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		fog.position = pos
		fog.size = Vector2(T, T)
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer_tiles.add_child(fog)
	# drzwi prowadzące gdzie indziej (jak znaczniki drzwi OpenMW – tylko w odkrytej części mapy)
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			var d: Dictionary = MWTravel.door_destination(n)
			if d.is_empty():
				continue
			var dl: Dictionary = lmap.locate((n as Node3D).global_position)
			if not lmap.explored(dl.seg, dl.uv):
				continue
			var mp: Vector2 = center + (Vector2(dl.f) - pf) * T
			var name := _dest_name(d)
			door_markers.append([name, mp])
			var m := ColorRect.new()
			m.color = Color(0.85, 0.15, 0.1)
			m.size = Vector2(6, 6) * scale_ui
			m.position = mp - m.size / 2.0
			m.tooltip_text = name
			_view.add_child(m)
	# MapWindow::updateMagicMarkers: Wykrywanie zwierząt / zaklęć / kluczy (World::listDetectedReferences)
	detect_markers = []
	if main.magic != null:
		for kind in ["creature", "enchantment", "key"]:
			for n in main.magic.detected_references(kind):
				var ml: Dictionary = lmap.locate((n as Node3D).global_position)
				var mp2: Vector2 = center + (Vector2(ml.f) - pf) * T
				detect_markers.append([kind, mp2])
				var dm := ColorRect.new()
				dm.color = {"creature": Color(0.9, 0.6, 0.2), "enchantment": Color(0.4, 0.5, 1.0), "key": Color(1.0, 0.9, 0.3)}[kind]
				dm.size = Vector2(5, 5) * scale_ui
				dm.position = mp2 - dm.size / 2.0
				dm.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_view.add_child(dm)
	_player_arrow(center, main.player)
	player_marker_pos = center

func _dest_name(d: Dictionary) -> String:
	var cell := String(d.get("cell_name", ""))
	if not cell.is_empty():
		return main.loc.plain(MWLocalization.key("CELL", cell, "NAME"), cell) if main.loc != null else cell
	var t: Transform3D = d.get("transform", Transform3D())
	var c: Dictionary = main.db.get_cell(main.db.exterior_key(MWCoords.cell_of(t.origin)))
	var nm := String(c.get("name", ""))
	if nm.is_empty():
		var reg := String(c.get("region", "")).to_lower()
		return String(main.envr.regions.get(reg, {}).get("name", reg)) if main.envr != null else reg
	return main.loc.plain(MWLocalization.key("CELL", nm, "NAME"), nm) if main.loc != null else nm

## Strzałka gracza: kierunek patrzenia względem góry mapy (północ/NorthMarker).
func _player_arrow(at: Vector2, player: Node3D) -> void:
	var cam := player.get_node_or_null("Camera3D") as Node3D
	var fwd: Vector3 = -(cam.global_transform.basis.z if cam != null else player.global_transform.basis.z)
	var q: Vector2 = lmap.to_q(Vector3(fwd.x, 0, fwd.z)) if lmap != null else Vector2(fwd.x, fwd.z)
	var poly := Polygon2D.new()
	var s := 9.0 * scale_ui
	poly.polygon = PackedVector2Array([Vector2(0, -s), Vector2(s * 0.6, s * 0.7), Vector2(-s * 0.6, s * 0.7)])
	poly.color = Color(1.0, 0.85, 0.3)
	poly.position = at
	poly.rotation = Vector2(0, -1).angle_to(q.normalized()) if q.length() > 0.001 else 0.0
	_view.add_child(poly)

# --- mapa świata ----------------------------------------------------------------------------------------

func _world_px(mw: Vector3) -> Vector2:
	var cp := float(_world_info.get("cell_px", 18))
	var mn: Array = _world_info.get("min", [0, 0])
	var mx: Array = _world_info.get("max", [0, 0])
	return Vector2((mw.x / MWCoords.CELL_SIZE - float(mn[0])) * cp, (float(mx[1]) + 1.0 - mw.y / MWCoords.CELL_SIZE) * cp)

## Znane miejsca: nazwane komórki odwiedzone (player.map_visited) i odkryte skryptem ShowMap (prefiks nazwy).
func known_places() -> Array:
	var out := []
	var visited: Dictionary = main.state.player.get("map_visited", {})
	var prefixes: Array = (main.dialogue._ds().get("map_markers", []) as Array) if main.dialogue != null else []
	for e in _world_info.get("named", []):
		var nm := String(e[2])
		var known := visited.has("%d,%d" % [int(e[0]), int(e[1])])
		if not known:
			for p in prefixes:
				if nm.to_lower().begins_with(String(p).to_lower()):
					known = true
					break
		if known:
			out.append(e)
	return out

func _build_world() -> void:
	place_markers = []
	_title.text = _t("sWorld", "Świat")
	if _world_tex == null:
		var l := Label.new()
		l.text = "Brak mapy świata – kliknij „Aktualizuj” w launcherze."
		_view.add_child(l)
		return
	var avail: Vector2 = _view.custom_minimum_size
	var fit := minf(avail.x / _world_tex.get_width(), avail.y / _world_tex.get_height())
	var z := fit * _zoom
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = avail
	_scroll.size = avail
	_view.add_child(_scroll)
	_world_rect = TextureRect.new()
	_world_rect.texture = _world_tex
	_world_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_world_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_world_rect.custom_minimum_size = Vector2(_world_tex.get_width(), _world_tex.get_height()) * z
	_scroll.add_child(_world_rect)
	for e in known_places():
		var mwp := Vector3((float(e[0]) + 0.5) * MWCoords.CELL_SIZE, (float(e[1]) + 0.5) * MWCoords.CELL_SIZE, 0)
		var p := _world_px(mwp) * z
		var nm := String(e[2])
		var disp: String = main.loc.plain(MWLocalization.key("CELL", nm, "NAME"), nm) if main.loc != null else nm
		place_markers.append([disp, int(e[0]), int(e[1])])
		var m := ColorRect.new()
		m.color = Color(0.9, 0.75, 0.35)
		m.size = Vector2(5, 5) * scale_ui
		m.position = p - m.size / 2.0
		m.tooltip_text = disp
		_world_rect.add_child(m)
	# gracz: we wnętrzu – ostatnia pozycja na zewnątrz
	var pmw := MWCoords.godot_to_mw(main.player.global_position)
	if not main.interior.is_empty():
		var le: Array = main.state.player.get("last_exterior", [])
		pmw = Vector3(float(le[0]), float(le[1]), 0) if le.size() >= 2 else Vector3.ZERO
	var pp := _world_px(pmw) * z
	player_marker_pos = pp
	var arrow := Polygon2D.new()
	var s := 7.0 * scale_ui
	arrow.polygon = PackedVector2Array([Vector2(0, -s), Vector2(s * 0.6, s * 0.7), Vector2(-s * 0.6, s * 0.7)])
	arrow.color = Color(1, 0.2, 0.2)
	arrow.position = pp
	_world_rect.add_child(arrow)
	_center_on.call_deferred(pp)

func _center_on(p: Vector2) -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_horizontal = int(p.x - _scroll.size.x / 2.0)
		_scroll.scroll_vertical = int(p.y - _scroll.size.y / 2.0)

func _process(delta: float) -> void:
	if not visible or world_mode:
		return
	_refresh_t += delta
	if _refresh_t > 0.5 and lmap != null and lmap._pending.is_empty() and _needs_refresh():
		_refresh_t = 0.0
		set_world(false)

func _needs_refresh() -> bool:
	return _waiting

func close() -> void:
	if not visible:
		return
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	if not embedded:
		get_tree().paused = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	embedded = false
	pinned_mode = false
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if not visible or pinned_mode:
		return
	if embedded and not (e is InputEventMouseButton):
		return                               # klawisze obsługuje tryb menu
	if not embedded and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu") or e.is_action_pressed("map_menu")):
		close()
		get_viewport().set_input_as_handled()
	elif world_mode and e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 1.0, 8.0)
			set_world(true)
			get_viewport().set_input_as_handled()
