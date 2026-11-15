extends Node3D
## Gra: strumieniowanie komórek wokół gracza z przekonwertowanych danych.
## Argumenty (po "--"): --data=KATALOG  --project=KATALOG  --cell="Nazwa wnętrza"  --pos=x,y,z (MW)
## Domyślne wartości: ustawienia projektu mwgodot/*.

var db: MWWorldDB
var models: MWModelCache
var builder: MWCellBuilder
var player: CharacterBody3D
var loaded := {}  # key → Node3D
var radius := 1
var interior := ""
var envr: MWEnvironment
var hud: Label
var current_region := ""

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func _ready() -> void:
	var data := arg("data", MWLauncher.load_settings().get("data_root",
		ProjectSettings.get_setting("mwgodot/data_root", "user://mwdata")))
	var project := arg("project", ProjectSettings.get_setting("mwgodot/project_root", "user://mw_project"))
	data = ProjectSettings.globalize_path(data)
	project = ProjectSettings.globalize_path(project)
	radius = int(ProjectSettings.get_setting("mwgodot/load_radius", 1))
	interior = arg("cell", ProjectSettings.get_setting("mwgodot/start_cell", ""))
	db = MWWorldDB.new(data, project)
	models = MWModelCache.new(data)
	builder = MWCellBuilder.new(db, models)
	if db.cell_index().is_empty():
		push_error("Brak danych świata w %s – uruchom konwerter (README)." % data)
		_add_message("Brak danych świata w:\n%s\nUruchom konwerter mwconv (patrz docs/DEBIAN13.md)." % data)
		return
	envr = MWEnvironment.new()
	envr.name = "Environment"
	var regs = MWWorldDB._read_json(data.path_join("world/regions.json"))
	if regs is Dictionary:
		envr.regions = regs
	add_child(envr)
	_setup_hud()
	player = preload("res://scripts/player.gd").new() as CharacterBody3D
	player.name = "Player"
	add_child(player)
	var start := _start_position()
	player.global_position = start
	if not interior.is_empty():
		var key := "int:" + interior.to_lower()
		_load(key)
		envr.set_interior(db.get_cell(key))
	else:
		_update_streaming(true)

func _start_position() -> Vector3:
	var p := arg("pos")
	if not p.is_empty():
		var v := p.split(",")
		return MWCoords.mw_to_godot(Vector3(float(v[0]), float(v[1]), float(v[2])))
	# środek pierwszej komórki zewnętrznej z indeksu, nad terenem
	for c in db.cell_index():
		if not c.get("interior", false) and interior.is_empty():
			var g: Array = c["grid"]
			var mw := Vector3((g[0] + 0.5) * MWCoords.CELL_SIZE, (g[1] + 0.5) * MWCoords.CELL_SIZE, 0)
			var pos := MWCoords.mw_to_godot(mw)
			var cell := db.get_cell(c["key"])
			if cell.get("terrain") != null:
				var t := db.get_terrain(cell["terrain"])
				var o: Array = t["origin_godot"]
				pos.y = MWTerrain.height_at(t, pos - Vector3(o[0], o[1], o[2])) + 2.0
			return pos
	return Vector3(0, 2, 0)

func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(12, 8)
	cl.add_child(hud)
	add_child(cl)

func _process(_d: float) -> void:
	if player == null:
		return
	if interior.is_empty():
		_update_streaming(false)
		var g := MWCoords.cell_of(player.global_position)
		var c := db.get_cell(db.exterior_key(g))
		var reg := String(c.get("region", ""))
		if reg != current_region:
			current_region = reg
			envr.set_region(reg)
	var hint := ""
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		for ch in player.get_children():
			if ch is Camera3D:
				cam = ch
	if cam:
		var r := MWTravel.pick(cam)
		if r:
			var base := db.get_object(String(r.get_meta("mw_base", "")))
			hint = "\n[E] %s" % base.get("name", r.get_meta("mw_base", ""))
	var rname := interior if not interior.is_empty() else String(envr.regions.get(current_region.to_lower(), {}).get("name", current_region))
	hud.text = "%s  |  dzień %d, %02d:%02d  |  %s%s" % [rname, envr.day + 1, int(envr.game_hour), int(fmod(envr.game_hour, 1.0) * 60), envr.weather, hint]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("activate") and player:
		for ch in player.get_children():
			if ch is Camera3D:
				var r := MWTravel.pick(ch)
				if r:
					activate(r)

## Aktywacja referencji: na razie drzwi z celem (DODT/DNAM).
func activate(r: Node) -> bool:
	var dest := MWTravel.door_destination(r)
	if dest.is_empty():
		return false
	travel(dest)
	return true

func travel(dest: Dictionary) -> void:
	for key in loaded.keys():
		loaded[key].queue_free()
	loaded.clear()
	var t: Transform3D = dest["transform"]
	if String(dest.get("cell_key", "")) != "":
		interior = String(dest["cell_name"])
		_load(dest["cell_key"])
		envr.set_interior(db.get_cell(dest["cell_key"]))
	else:
		interior = ""
		envr.set_interior({})
		player.global_position = t.origin
		_update_streaming(true)
	player.global_position = t.origin
	player.rotation.y = t.basis.get_euler().y
	player.velocity = Vector3.ZERO

func _update_streaming(_force: bool) -> void:
	var g := MWCoords.cell_of(player.global_position)
	var want := {}
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var key := db.exterior_key(g + Vector2i(dx, dy))
			if not db.find_cell(key).is_empty():
				want[key] = true
	for key in want:
		if not loaded.has(key):
			_load(key)
	for key in loaded.keys():
		if not want.has(key):
			loaded[key].queue_free()
			loaded.erase(key)

func _load(key: String) -> void:
	var n := builder.build_cell(key)
	if n:
		add_child(n)
		loaded[key] = n

func _add_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(20, 20)
	var cl := CanvasLayer.new()
	cl.add_child(l)
	add_child(cl)
