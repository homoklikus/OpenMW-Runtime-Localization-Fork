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
var hud: RichTextLabel
## preload zamiast class_name: gra działa też bez ponownego importu projektu po aktualizacji skryptów
const Loc := preload("res://scripts/mw/mw_localization.gd")
const Flora := preload("res://scripts/mw/mw_flora.gd")
const GameStateScript := preload("res://scripts/mw/mw_game_state.gd")
const Events := preload("res://scripts/mw/mw_events.gd")
const MWInput := preload("res://scripts/mw/mw_input.gd")
var events = Events.new()           # szyna zdarzeń (etap 0)
var state = GameStateScript.new()   # różnice stanu gry względem danych bazowych (zapis gry)
var pause_menu: Control
var loc  # Loc
var current_region := ""
var settings := {}
var launched_by_launcher := false

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	# te same argumenty z override.cfg ([mwgodot] cli/<nazwa>=…) – start bez wiersza poleceń (np. przez MCP Godota)
	var ps := "mwgodot/cli/" + name
	if ProjectSettings.has_setting(ps):
		return str(ProjectSettings.get_setting(ps))
	return def

func _ready() -> void:
	MWInput.register_defaults()
	var mk := preload("res://scripts/mw/mw_menu_key.gd").new()
	mk.name = "MenuKey"
	mk.main = self
	add_child(mk)
	var data := arg("data", ProjectSettings.get_setting("mwgodot/data_root", "user://mwdata"))
	var base := arg("base")
	if not base.is_empty():
		MWModelCache.base_roots = PackedStringArray([ProjectSettings.globalize_path(base)])
	settings = _load_settings(arg("settings"))
	launched_by_launcher = not arg("profile").is_empty()
	var project := arg("project", ProjectSettings.get_setting("mwgodot/project_root", "user://mw_project"))
	data = ProjectSettings.globalize_path(data)
	project = ProjectSettings.globalize_path(project)
	radius = int(settings.get("load_radius", ProjectSettings.get_setting("mwgodot/load_radius", 1)))
	interior = arg("cell", ProjectSettings.get_setting("mwgodot/start_cell", ""))
	db = MWWorldDB.new(data, project)
	models = MWModelCache.new(data)
	builder = MWCellBuilder.new(db, models)
	builder.state = state
	state.ref_changed.connect(_on_ref_changed)
	state.dynamic_changed.connect(_on_dynamic_changed)
	if bool(settings.get("grass", true)):
		var fl = Flora.new(models, data, MWModelCache.base_roots)
		if fl.is_active():
			fl.distance = float(settings.get("grass_distance", 90))
			fl.density = float(settings.get("grass_density", 1.0))
			builder.flora = fl
			print("MWGODOT_FLORA tryb=", fl.index.get("mode", ""), " komórki=", fl.index.get("cells", {}).size())
	loc = Loc.create(data, MWModelCache.base_roots, String(settings.get("game_language", "auto")),
			String(settings.get("language", "")), String(settings.get("qa_source", "")))
	if loc.is_active():
		print("MWGODOT_LOCALIZATION ", ",".join(loc.languages), " (dostępne: ", ",".join(loc.available), ")")
	builder.with_water = bool(settings.get("water", true))
	if db.cell_index().is_empty():
		push_error("Brak danych świata w %s – uruchom konwerter (README)." % data)
		_add_message("Brak danych świata w:\n%s\nUruchom konwerter mwconv (patrz docs/DEBIAN13.md)." % data)
		if launched_by_launcher:
			printerr("MWGODOT_ERROR brak danych świata: ", data)
			get_tree().quit(2)  # launcher pokaże błąd z kodem wyjścia
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
	player.mouse_sens = float(settings.get("mouse_sensitivity", player.mouse_sens))
	player.invert_y = bool(settings.get("invert_y", false))
	add_child(player)
	_apply_settings()
	var start_t := _start_transform()
	player.global_position = start_t.origin
	player.rotation.y = start_t.basis.get_euler().y
	_apply_capture()
	var lp := arg("load")
	if not lp.is_empty():
		var lw := load_game(lp)
		print("MWGODOT_LOADED ", lp, " ", JSON.stringify(lw))
		if not lw.is_empty():
			_toast("\n".join(lw), 8.0)
	if not interior.is_empty():
		var key := "int:" + interior.to_lower()
		_load(key)
		envr.set_interior(db.get_cell(key))
	else:
		_update_streaming(true)

static func _load_settings(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## Ustawienia z launchera (plik --settings): tylko opcje obsługiwane przez Runtime.
func _apply_settings() -> void:
	if settings.is_empty():
		return
	var mode := String(settings.get("window_mode", "windowed"))
	if DisplayServer.get_name() != "headless":
		match mode:
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"exclusive":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var r := String(settings.get("resolution", "1280x720")).split("x")
				if r.size() == 2:
					var want := Vector2i(int(r[0]), int(r[1]))
					var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
					DisplayServer.window_set_size(want)
					if scr.size.x > 0:   # wyśrodkuj na bieżącym ekranie (okno 3440x1440 na całą szerokość)
						DisplayServer.window_set_position(scr.position + (scr.size - want).max(Vector2i.ZERO) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.get("max_fps", 0))
	get_viewport().scaling_3d_scale = float(settings.get("scale_3d", 1.0))
	var sh := String(settings.get("shadows", "medium"))
	envr.sun.shadow_enabled = sh != "off"
	RenderingServer.directional_shadow_atlas_set_size({"low": 1024, "medium": 2048, "high": 4096}.get(sh, 2048), true)
	envr.env.fog_enabled = bool(settings.get("fog", true))
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.far = float(settings.get("view_distance", 1500))

func _start_position() -> Vector3:
	return _start_transform().origin

## Miejsce startu. Kolejność: --pos (jednostki MW) → nazwane miejsce (--start, ustawienie „start_location”,
## potem Balmora i Seyda Neen) → środek pierwszej komórki zewnętrznej.
## Nazwane miejsce: punkt wyjścia z budynku tego miasta (cel drzwi wnętrza „<miasto>, …” prowadzących na
## zewnątrz) najbliższy środka komórek miasta – ulica przed drzwiami, nie dach ani rzeka.
func _start_transform() -> Transform3D:
	var p := arg("pos")
	if not p.is_empty():
		var v := p.split(",")
		return Transform3D(Basis(), MWCoords.mw_to_godot(Vector3(float(v[0]), float(v[1]), float(v[2]))))
	if interior.is_empty():
		for name in [arg("start"), String(settings.get("start_location", "")), "Balmora", "Seyda Neen"]:
			if name.is_empty():
				continue
			var t = _named_start(name)
			if t != null:
				start_name = name
				return t
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
			return Transform3D(Basis(), pos)
	return Transform3D(Basis(), Vector3(0, 2, 0))

var start_name := ""

func _named_start(name: String) -> Variant:
	var lname := name.to_lower()
	var centre := Vector3.ZERO
	var n_ext := 0
	for c in db.cell_index():
		if not c.get("interior", false) and String(c.get("name", "")).to_lower() == lname:
			var g: Array = c["grid"]
			centre += MWCoords.mw_to_godot(Vector3((g[0] + 0.5) * MWCoords.CELL_SIZE, (g[1] + 0.5) * MWCoords.CELL_SIZE, 0))
			n_ext += 1
	# punkty wyjścia z budynków miasta (cele drzwi wnętrz „<miasto>, …” prowadzących na zewnątrz)
	var exits: Array[Transform3D] = []
	for c in db.cell_index():
		if not c.get("interior", false) or not String(c.get("name", "")).to_lower().begins_with(lname + ","):
			continue
		for r in db.get_cell(c["key"]).get("refs", []):
			var ex: Dictionary = r.get("extra", {})
			if not ex.has("door_dest") or not String(ex.get("door_dest_cell", "")).is_empty():
				continue  # tylko drzwi prowadzące na zewnątrz
			var g: Dictionary = ex["door_dest"].get("godot", {})
			var o: Array = g.get("origin", [0, 0, 0])
			var q: Array = g.get("quat", [0, 0, 0, 1])
			var pos := Vector3(o[0], o[1], o[2])
			if db.find_cell(db.exterior_key(MWCoords.cell_of(pos))).is_empty():
				continue  # komórka poza przekonwertowanym zakresem
			exits.append(Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), pos + Vector3(0, 0.1, 0)))
	if n_ext > 0:
		centre /= n_ext
	elif not exits.is_empty():
		for t in exits:
			centre += t.origin
		centre /= exits.size()
	else:
		return null
	if not exits.is_empty():
		var best: Transform3D = exits[0]
		var best_d := INF
		for t in exits:
			var d := Vector2(t.origin.x - centre.x, t.origin.z - centre.z).length()
			if d < best_d:
				best_d = d
				best = t
		return best
	# brak wnętrz: środek komórek miasta, nad terenem (może wypaść na dachu – lepsze niż góry obok)
	var cell := db.get_cell(db.exterior_key(MWCoords.cell_of(centre)))
	if cell.is_empty() or cell.get("terrain") == null:
		return null
	var tr := db.get_terrain(cell["terrain"])
	var to: Array = tr["origin_godot"]
	centre.y = MWTerrain.height_at(tr, centre - Vector3(to[0], to[1], to[2])) + 2.0
	return Transform3D(Basis(), centre)

func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	hud = RichTextLabel.new()      # BBCode: formatowanie z tłumaczeń ([c] [b] [i]) i znacznik QA
	hud.bbcode_enabled = true
	hud.fit_content = true
	hud.scroll_active = false
	hud.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.position = Vector2(12, 8)
	hud.size = Vector2(1600, 120)
	cl.add_child(hud)
	add_child(cl)

var _frames := 0

## Tryb zrzutu (porównania z OpenMW, np. ujęcia MCP-openMW openmw_capture_plan):
##   --camera=x,y,z   pozycja kamery (jednostki MW)      --look=yaw,pitch  radiany jak w OpenMW
##                    (yaw 0 = północ/+Y, zgodnie z ruchem wskazówek; pitch > 0 = w dół)
##   --hour=12  --weather=clear  --fov=60 (pionowe, jak OpenMW)  --screenshot=PLIK.png  --shot-frames=120
##   --save=PLIK.mwsave (zapis gry w chwili zrzutu)   --load=PLIK.mwsave (także poza trybem zrzutu: wczytanie przy starcie)
## Kamera stoi w miejscu (latanie), czas zatrzymany, pasek ukryty; po zrzucie gra kończy się (--quit=0: zostaje).
func _apply_capture() -> void:
	var c := arg("camera")
	if not c.is_empty():
		var v := c.split(",")
		player.fly = true
		player.global_position = MWCoords.mw_to_godot(Vector3(float(v[0]), float(v[1]), float(v[2]))) - Vector3(0, 1.65, 0)
		player.velocity = Vector3.ZERO
	var look := arg("look")
	if not look.is_empty():
		var l := look.split(",")
		player.rotation.y = -float(l[0])
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam and l.size() > 1:
			cam.rotation.x = -float(l[1])
	var fov := arg("fov")
	if not fov.is_empty():
		var cam2 := player.get_node_or_null("Camera3D") as Camera3D
		if cam2:
			cam2.fov = float(fov)
	var hour := arg("hour")
	if not hour.is_empty():
		envr.time_running = false
		envr.game_hour = float(hour)
		envr.apply()
	var w := arg("weather").to_lower()
	if not w.is_empty():
		envr.forced_weather = w
		envr.pick_weather()
	if not arg("screenshot").is_empty() and hud:
		hud.visible = false

func _capture_tick() -> void:
	var shot := arg("screenshot")
	if shot.is_empty() or _frames != int(arg("shot-frames", "120")):
		return
	if player and player.fly:
		player.velocity = Vector3.ZERO
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
	var err := img.save_png(shot)
	print("MWGODOT_SHOT ", shot, " ", img.get_width(), "x", img.get_height(), " err=", err,
		" flora=", JSON.stringify(builder.flora.stats if builder.flora else {}))
	var sp := arg("save")
	if not sp.is_empty():
		print("MWGODOT_SAVED ", sp, " ", save_game(sp))
	if arg("quit", "1") != "0":
		get_tree().quit(0 if err == OK else 4)

func _process(_d: float) -> void:
	_frames += 1
	_update_torches(_d)
	_capture_tick()
	var autotest := int(arg("autotest-frames", "0"))
	if autotest > 0 and _frames == autotest:
		# tryb testu integracyjnego (launcher): raport i wyjście z kodem zależnym od błędów ładowania
		var st := {"cells": loaded.size(), "models": models.stats if models else {}, "data": db.data_root if db else "",
			"base_roots": MWModelCache.base_roots, "settings_profile": settings.get("profile", ""),
			"max_fps": Engine.max_fps, "flora": builder.flora.stats if builder.flora else {}}
		print("MWGODOT_STATS ", JSON.stringify(st))
		get_tree().quit(0 if models and models.stats.failed == 0 and loaded.size() > 0 else 3)
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
		# podpowiedź tylko dla tego, co klawisz E faktycznie obsługuje (na razie: drzwi z celem podróży)
		if r and not r.has_meta("mw_marker") and not MWTravel.door_destination(r).is_empty():
			var base := db.get_object(String(r.get_meta("mw_base", "")))
			hint = "\n[lb]E] %s" % loc.object_name_bbcode(base, String(r.get_meta("mw_base", "")))
	var rname := display_location()
	hud.text = "%s  |  dzień %d, %02d:%02d  |  %s%s%s" % [rname, envr.day + 1, int(envr.game_hour), int(fmod(envr.game_hour, 1.0) * 60), envr.weather, coords_text(), hint]

## Widok z ostatniej sesji – zapisywany lokalnie (katalog zapisów profilu), launcher pokazuje go na ekranie głównym.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and DisplayServer.get_name() != "headless":
		var saves := arg("saves")
		if not saves.is_empty() and player != null:
			var img := get_viewport().get_texture().get_image()
			if img:
				DirAccess.make_dir_recursive_absolute(saves)
				img.resize(640, int(640.0 * img.get_height() / max(1, img.get_width())), Image.INTERPOLATE_BILINEAR)
				img.save_png(saves.path_join("last_view.png"))

## Nazwa miejsca w pasku: wnętrze (CELL|nazwa|NAME) albo region (REGN|id|FNAM) – przetłumaczona, jeśli jest.
func display_location() -> String:
	if not interior.is_empty():
		return Loc.escape_bbcode(loc.plain(Loc.key("CELL", interior, "NAME"), interior))
	var reg := current_region.to_lower()
	var name := String(envr.regions.get(reg, {}).get("name", current_region))
	return Loc.escape_bbcode(loc.plain(Loc.key("REGN", reg, "FNAM"), name))

## Współrzędne do testów (F3 – pokaż/ukryj, F4 – kopiuj do schowka i zapisz w logu).
## Pozycja w jednostkach Morrowinda (jak w Construction Set i konsoli gry); „--pos=x,y,z” uruchamia grę w tym miejscu.
var show_coords := true

func position_string() -> String:
	if player == null:
		return ""
	var mw := MWCoords.godot_to_mw(player.global_position)
	return "%d,%d,%d" % [roundi(mw.x), roundi(mw.y), roundi(mw.z)]

func coords_text() -> String:
	if not show_coords or player == null:
		return ""
	var cell := ""
	if interior.is_empty():
		var g := MWCoords.cell_of(player.global_position)
		cell = "komórka %d,%d" % [g.x, g.y]
	else:
		cell = "wnętrze „%s”" % interior
	var yaw := fposmod(-rad_to_deg(player.rotation.y), 360.0)
	return "\n%s  |  pozycja %s  |  kierunek %d°  [lb]F3 ukryj, F4 kopiuj]" % [Loc.escape_bbcode(cell), position_string(), roundi(yaw)]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("quick_save"):
		var r := save_game(quicksave_path())
		_toast("Zapisano grę (szybki zapis)" if r.is_empty() else "Błąd zapisu: " + r)
	elif e.is_action_pressed("quick_load"):
		var w = load_game(quicksave_path())
		_toast(("Wczytano grę" + ("" if w.is_empty() else ":\n" + "\n".join(w))) if not (w.size() == 1 and String(w[0]).begins_with("BŁĄD")) else String(w[0]))
	elif e.is_action_pressed("toggle_coords"):
		show_coords = not show_coords
	elif e.is_action_pressed("copy_position") and player:
		var line := "--pos=%s" % position_string()
		if not interior.is_empty():
			line = "--cell=\"%s\" %s" % [interior, line]
		DisplayServer.clipboard_set(line)
		print("MWGODOT_POS ", line)
		_toast("Skopiowano do schowka: " + line)
	if e.is_action_pressed("activate") and player:
		for ch in player.get_children():
			if ch is Camera3D:
				var r := MWTravel.pick(ch)
				if r:
					activate(r)

## Aktywacja referencji: na razie drzwi z celem (DODT/DNAM).
func activate(r: Node) -> bool:
	events.activated.emit(String(r.get_meta("mw_sid", "")), String(r.get_meta("mw_base", "")), "player")
	var dest := MWTravel.door_destination(r)
	if dest.is_empty():
		return false
	travel(dest)
	return true

func travel(dest: Dictionary) -> void:
	for key in loaded.keys():
		events.cell_unloaded.emit(key)
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
			events.cell_unloaded.emit(key)
			loaded[key].queue_free()
			loaded.erase(key)

func _load(key: String) -> void:
	if builder.actors != null:
		builder.actors.torches = use_torches(key)
	var n := builder.build_cell(key)
	if n:
		add_child(n)
		loaded[key] = n
		events.cell_loaded.emit(key)

## World::useTorches: na zewnątrz po zmroku (przed 6:00 i po 20:00 – wschód 6, zachód 18 + 2 h zmierzchu) i bez
## opadów (pogody z „Using Precip”: deszcz, burza, śnieg, zamieć); we wnętrzach – gdy suma składowych światła
## otoczenia ≤ 201 i spanie nie jest zabronione.
func use_torches(key := "") -> bool:
	var k := key if not key.is_empty() else ("" if interior.is_empty() else "int:" + interior.to_lower())
	if k.begins_with("int:"):
		var c := db.get_cell(k)
		if c.get("behave_like_exterior", false):
			pass
		else:
			var amb: Array = (c.get("ambient", {}) as Dictionary).get("ambient_rgb", [255, 255, 255])
			return (int(c.get("flags", 0)) & 0x04) == 0 and int(amb[0]) + int(amb[1]) + int(amb[2]) <= 201
	var h := float(envr.game_hour)
	return (h < 6.0 or h > 20.0) and not String(envr.weather) in ["rain", "thunder", "snow", "blizzard"]

## Co sekundę (jak Actors::update): zmiana pory/pogody → NPC biorą albo odkładają pochodnie.
var _torch_timer := 0.0
func _update_torches(delta: float) -> void:
	_torch_timer += delta
	if _torch_timer < 1.0 or builder == null or builder.actors == null:
		return
	_torch_timer = 0.0
	var t := use_torches()
	if t == builder.actors.torches:
		return
	builder.actors.torches = t
	for key in loaded:
		var refs_node: Node = loaded[key].get_node_or_null("Refs")
		if refs_node == null:
			continue
		for n in refs_node.get_children():
			if n.get_meta("mw_actor", "") == "npc":
				_on_ref_changed(String(n.get_meta("mw_sid", "")))

func _toast(text: String, seconds := 3.0) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(12, 90)
	var cl := CanvasLayer.new()
	cl.add_child(l)
	add_child(cl)
	get_tree().create_timer(seconds).timeout.connect(cl.queue_free)

func _add_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(20, 20)
	var cl := CanvasLayer.new()
	cl.add_child(l)
	add_child(cl)


# --- stan gry: zapis i odczyt (etap 0) ---------------------------------------------------------------

func saves_dir() -> String:
	var s := arg("saves")
	return s if not s.is_empty() else ProjectSettings.globalize_path("user://saves")

func quicksave_path() -> String:
	return saves_dir().path_join("quicksave.mwsave")

## Nagłówek zapisu: profil, lista treści z manifestu konwersji (wtyczki + SHA-256, kolejność ładowania),
## odcisk danych bazowych – do wykrywania niezgodności przy odczycie.
func save_header() -> Dictionary:
	var content := []
	var man = MWWorldDB._read_json(db.data_root.path_join("world/manifest.json"))
	if man is Dictionary:
		for c in man.get("content", []):
			content.append({"name": c.get("name", ""), "sha256": c.get("sha256", "")})
	return {"profile": arg("profile", "default"), "character": "", "content": content,
		"base_fingerprint": JSON.stringify(content).sha256_text(), "world_format": 1,
		"created": Time.get_datetime_string_from_system(), "game": "OpenMWGodot"}

func capture_state() -> void:
	state.time = {"day": envr.day, "hour": envr.game_hour}
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	var p := MWCoords.godot_to_mw(player.global_position)
	var keep: Dictionary = state.player.duplicate()      # np. poziom gracza (etap 4)
	keep.merge({"interior": interior, "fly": player.fly,
		"mw": {"pos": [p.x, p.y, p.z], "rot": [-(cam.rotation.x if cam else 0.0), 0.0, -player.rotation.y]}}, true)
	state.player = keep

## Zwraca "" albo opis błędu.
func save_game(path: String) -> String:
	if player == null:
		return "gra nie jest uruchomiona"
	capture_state()
	var err := GameStateScript.write_file(path, state.to_dict(save_header()))
	if err != OK:
		return "kod %d" % err
	print("MWGODOT_SAVE ", path)
	events.game_saved.emit(path)
	return ""

## Zwraca listę ostrzeżeń (pusta = zgodny); błąd jako jedyny element "BŁĄD: …". Oryginalny plik zostaje.
func load_game(path: String) -> Array:
	var raw := GameStateScript.read_file(path)
	if raw.has("error"):
		return ["BŁĄD: " + String(raw["error"])]
	var old_version := int(raw.get("version", 0))
	var m := GameStateScript.migrate(raw)
	if m.has("error"):
		return ["BŁĄD: " + String(m["error"])]
	if m.get("migrated", false):
		GameStateScript.backup_before_migration(path, old_version)
	var d: Dictionary = m["data"]
	var warnings := GameStateScript.compatibility(d.get("header", {}), save_header())
	warnings.append_array(state.from_dict(d))
	_apply_state()
	print("MWGODOT_LOAD ", path, " ostrzeżenia=", warnings.size())
	events.game_loaded.emit(path, warnings)
	return warnings

func _apply_state() -> void:
	envr.day = int(state.time.get("day", 0))
	envr.game_hour = float(state.time.get("hour", 9.0))
	envr.apply()
	var pl: Dictionary = state.player
	var mw: Dictionary = pl.get("mw", {})
	var pos: Array = mw.get("pos", [])
	var rot: Array = mw.get("rot", [0, 0, 0])
	for key in loaded.keys():
		events.cell_unloaded.emit(key)
		loaded[key].free()
	loaded.clear()
	var inter := String(pl.get("interior", ""))
	interior = inter
	if pos.size() == 3:
		player.global_position = MWCoords.mw_to_godot(Vector3(pos[0], pos[1], pos[2]))
	player.rotation.y = -float(rot[2])
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.rotation.x = -float(rot[0])
	player.fly = bool(pl.get("fly", false))
	player.velocity = Vector3.ZERO
	if not inter.is_empty():
		var key := "int:" + inter.to_lower()
		_load(key)
		envr.set_interior(db.get_cell(key))
	else:
		envr.set_interior({})
		_update_streaming(true)

## Zmiana referencji w GameState → przebudowa tylko jej węzła w wczytanych komórkach.
func _on_ref_changed(sid: String) -> void:
	for key in loaded:
		var refs_node: Node = loaded[key].get_node_or_null("Refs")
		if refs_node == null:
			continue
		for n in refs_node.get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				for r in db.get_cell(key).get("refs", []):
					if String(r.get("sid", "")) == sid:
						var nn := builder.build_ref(state.apply_to_ref(r))
						refs_node.add_child(nn)
						refs_node.move_child(nn, n.get_index())
						n.free()
						return

## Przedmiot położony/podniesiony w świecie (dyn#N) → dodanie albo usunięcie węzła we wczytanej komórce.
func _on_dynamic_changed(sid: String) -> void:
	for key in loaded:
		var refs_node: Node = loaded[key].get_node_or_null("Refs")
		if refs_node == null:
			continue
		for n in refs_node.get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				n.free()
		for r in state.dynamic_refs(key):
			if String(r["sid"]) == sid:
				var nn := builder.build_ref(r)
				if nn:
					refs_node.add_child(nn)

## Menu pauzy (Esc): wróć, szybki zapis/odczyt, wyjście. Szkielet UI etapu 0.
func toggle_pause_menu() -> void:
	if pause_menu == null:
		pause_menu = _build_pause_menu()
	pause_menu.visible = not pause_menu.visible
	get_tree().paused = pause_menu.visible
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_menu.visible else Input.MOUSE_MODE_CAPTURED

func _build_pause_menu() -> Control:
	var cl := CanvasLayer.new()
	cl.layer = 10
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	var panel := PanelContainer.new()
	panel.name = "PauseMenu"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Pauza"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for item in [["Wróć do gry", func(): toggle_pause_menu()],
			["Szybki zapis (F5)", func(): _toast("Zapisano grę" if save_game(quicksave_path()).is_empty() else "Błąd zapisu")],
			["Szybki odczyt (F9)", func():
				var w = load_game(quicksave_path())
				toggle_pause_menu()
				_toast("Wczytano grę" if w.is_empty() else "\n".join(w))],
			["Wyjdź z gry", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		box.add_child(b)
	cl.add_child(panel)
	panel.position = (get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0
	panel.visible = false
	return panel
