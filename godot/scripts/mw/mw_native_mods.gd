extends RefCounted
## Natywne mody OpenMWGodot (eksperyment „first-fish”): katalog `mods/<id>/mod.json` obok projektu (albo
## `--mods=KATALOG`, ustawienie `native_mods_dir`; `--mods=` pusty – wyłączone). Mod opisuje stworzenia
## (model glTF/GLB z animacją, skrypt zachowania GDScript) i miejsca pojawiania się w świecie (jednostki MW).
## Nie zmienia danych gry ani zapisu: obiekty powstają przy wczytaniu komórki jako dzieci jej węzła i znikają
## z nią. To minimalny prototyp – bez systemu fauny, kolizji, walki i łupów.

var main
var root_dir := ""
var mods: Array = []                 # [{"id", "dir", "def"}]
var spawned: Array = []              # węzły utworzone w tej sesji (do testów)
var errors: Array = []
var _scenes := {}                    # ścieżka GLB → Node3D (wzorzec do duplikowania)
var _scripts := {}                   # ścieżka .gd → GDScript

func _init(game_main, dir: String) -> void:
	main = game_main
	root_dir = dir
	_scan()

func _err(msg: String) -> void:
	errors.append(msg)
	push_warning("MWGODOT_NATIVE_MOD " + msg)

func _scan() -> void:
	if root_dir.is_empty() or not DirAccess.dir_exists_absolute(root_dir):
		return
	for d in DirAccess.get_directories_at(root_dir):
		var path := root_dir.path_join(d).path_join("mod.json")
		if not FileAccess.file_exists(path):
			continue
		var def = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not def is Dictionary or String(def.get("format", "")) != "openmwgodot-native-mod":
			_err("%s: nieprawidłowy mod.json" % d)
			continue
		mods.append({"id": String(def.get("id", d)), "dir": root_dir.path_join(d), "def": def})

## Wczytana komórka zewnętrzna: miejsca pojawiania się, których środek leży w tej komórce.
func on_cell_loaded(key: String) -> void:
	if not key.begins_with("ext:"):
		return
	for m in mods:
		var creatures := {}
		for c in m.def.get("creatures", []):
			creatures[String(c.get("id", ""))] = c
		for s in m.def.get("spawns", []):
			var p: Array = s.get("pos", [])
			if p.size() < 2:
				continue
			var g := MWCoords.mw_to_godot(Vector3(float(p[0]), float(p[1]), 0.0))
			if main.db.exterior_key(MWCoords.cell_of(g)) != key:
				continue
			var c: Dictionary = creatures.get(String(s.get("creature", "")), {})
			if c.is_empty():
				_err("%s: nieznane stworzenie %s" % [m.id, s.get("creature")])
				continue
			_spawn(m, c, s, key, g)

func _spawn(m: Dictionary, c: Dictionary, s: Dictionary, key: String, home: Vector3) -> void:
	var cell_root: Node = main.loaded.get(key)
	if cell_root == null:
		return
	var proto := _model(String(m.dir).path_join(String(c.get("model", ""))))
	var script := _script(String(m.dir).path_join(String(c.get("behaviour", ""))))
	if proto == null or script == null:
		return
	var water: float = main.cell_water_m(key) if main.has_method("cell_water_m") else 0.0
	if is_inf(water):
		_err("%s: komórka %s bez wody" % [m.id, key])
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.get("seed", 1))
	var radius := float(s.get("radius", 200)) / MWCoords.UNITS_PER_METER
	var params: Dictionary = (c.get("params", {}) as Dictionary).duplicate()
	params["animation"] = String(c.get("animation", "swim_idle"))
	for i in int(s.get("count", 1)):
		var fish := Node3D.new()
		fish.name = "%s_%s_%d" % [m.id, c.get("id", "creature"), i]
		fish.set_meta("mw_native_mod", m.id)
		fish.add_child(proto.duplicate())
		fish.set_script(script)
		var r := RandomNumberGenerator.new()
		r.seed = rng.randi()
		fish.set("rng", r)
		fish.set("home", home)
		fish.set("radius", radius)
		fish.set("water_y", water)
		fish.set("ground", ground_height)
		fish.set("params", params)
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * radius * 0.5
		var start := home + Vector3(cos(a) * d, 0.0, sin(a) * d)
		start.y = lerpf(ground_height(start.x, start.z) + 0.2, water - 0.25, 0.5)
		cell_root.add_child(fish)
		fish.global_position = start
		spawned.append(fish)

## Wysokość dna (teren komórki zewnętrznej) w punkcie Godota – jak MWTerrain.height_at siatki terenu.
func ground_height(x: float, z: float) -> float:
	var key: String = main.db.exterior_key(MWCoords.cell_of(Vector3(x, 0, z)))
	var cell: Dictionary = main.db.get_cell(key)
	if cell.get("terrain") == null:
		return -100.0
	var t: Dictionary = main.db.get_terrain(cell["terrain"])
	var o: Array = t["origin_godot"]
	return MWTerrain.height_at(t, Vector3(x, 0, z) - Vector3(o[0], o[1], o[2]))

## Model glTF/GLB wczytany w czasie działania (GLTFDocument – bez importu do projektu), jeden wzorzec na plik.
func _model(path: String) -> Node3D:
	if _scenes.has(path):
		return _scenes[path]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		_err("model %s: błąd %d" % [path, err])
		_scenes[path] = null
		return null
	var n := doc.generate_scene(st) as Node3D
	_scenes[path] = n
	return n

## Skrypt zachowania z katalogu modu (źródło GDScript kompilowane w czasie działania).
func _script(path: String) -> GDScript:
	if _scripts.has(path):
		return _scripts[path]
	if not FileAccess.file_exists(path):
		_err("brak skryptu %s" % path)
		_scripts[path] = null
		return null
	var s := GDScript.new()
	s.source_code = FileAccess.get_file_as_string(path)
	if s.reload() != OK:
		_err("skrypt %s się nie kompiluje" % path)
		_scripts[path] = null
		return null
	_scripts[path] = s
	return s

## Zwolnienie wzorców modeli (węzły poza drzewem) – przy wyjściu z gry i w testach.
func free_cache() -> void:
	for n in _scenes.values():
		if n != null and is_instance_valid(n):
			n.free()
	_scenes.clear()

