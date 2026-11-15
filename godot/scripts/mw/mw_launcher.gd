class_name MWLauncher
extends RefCounted
## Logika launchera/instalatora: wykrywanie instalacji Morrowinda, sprawdzenie Pythona, uruchomienie
## konwertera (mwconv) jako procesu potomnego z odczytem postępu (linie MWPROGRESS), zapis ustawień.
## UI: scripts/launcher.gd. Konwersja działa lokalnie – dane gry nie opuszczają komputera.

const SETTINGS := "user://mwgodot_settings.cfg"

signal progress(stage: String, done: int, total: int)
signal line(text: String)
signal finished(ok: bool, info: Dictionary)

var python := "python3"
var converter_dir := ""
var pid := -1
var _stdio: FileAccess
var _thread: Thread
var _mutex := Mutex.new()
var _queue: Array = []
var _running := false
var last_done := {}

func _init() -> void:
	converter_dir = default_converter_dir()

## Katalog konwertera: obok pliku wykonywalnego (wydanie) albo ../converter względem projektu (rozwój).
static func default_converter_dir() -> String:
	var exe_side := OS.get_executable_path().get_base_dir().path_join("converter")
	if DirAccess.dir_exists_absolute(exe_side.path_join("mwconv")):
		return exe_side
	return ProjectSettings.globalize_path("res://").path_join("../converter").simplify_path()

## Znane miejsca instalacji (Linux): konfiguracje OpenMW (natywna i Flatpak), Steam, GOG/Wine.
static func candidate_paths() -> Array[Dictionary]:
	var home := OS.get_environment("HOME")
	var out: Array[Dictionary] = []
	var cands := [
		["openmw_cfg", home.path_join(".config/openmw/openmw.cfg")],
		["openmw_cfg", home.path_join(".var/app/org.openmw.OpenMW/config/openmw/openmw.cfg")],
		["morrowind", home.path_join(".steam/steam/steamapps/common/Morrowind")],
		["morrowind", home.path_join(".local/share/Steam/steamapps/common/Morrowind")],
		["morrowind", home.path_join("GOG Games/Morrowind")],
		["morrowind", home.path_join(".wine/drive_c/Program Files (x86)/Bethesda Softworks/Morrowind")],
	]
	for c in cands:
		out.append({"kind": c[0], "path": c[1]})
	return out

## Rozpoznaje, czym jest ścieżka: plik openmw.cfg, katalog gry (z „Data Files”) albo sam „Data Files”.
static func classify(path: String) -> Dictionary:
	if path.get_file() == "openmw.cfg" and FileAccess.file_exists(path):
		return {"kind": "openmw_cfg", "path": path, "ok": true}
	if DirAccess.dir_exists_absolute(path.path_join("Data Files")):
		var esm := _find_ci(path.path_join("Data Files"), "morrowind.esm")
		return {"kind": "morrowind", "path": path, "ok": not esm.is_empty(), "esm": esm}
	if DirAccess.dir_exists_absolute(path):
		var esm := _find_ci(path, "morrowind.esm")
		if not esm.is_empty():
			return {"kind": "data", "path": path, "ok": true, "esm": esm}
	return {"kind": "unknown", "path": path, "ok": false}

static func _find_ci(dir: String, name_lower: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for f in d.get_files():
		if f.to_lower() == name_lower:
			return dir.path_join(f)
	return ""

static func detect() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for c in candidate_paths():
		var r := classify(c["path"])
		if r["ok"]:
			found.append(r)
	return found

## Sprawdza Pythona i zależności konwertera.
func check_python() -> Dictionary:
	var out := []
	var code := OS.execute(python, ["-c", "import sys, numpy, PIL; print(sys.version.split()[0], numpy.__version__, PIL.__version__)"], out, true)
	var ok := code == 0
	return {"ok": ok, "details": "\n".join(out).strip_edges(),
		"hint": "" if ok else "Zainstaluj: sudo apt install python3 python3-numpy python3-pil"}

func build_args(install: Dictionary, out_dir: String, opts: Dictionary) -> PackedStringArray:
	var a := PackedStringArray(["-m", "mwconv", "convert", "--progress-json", "--out", out_dir])
	match String(install.get("kind", "")):
		"openmw_cfg":
			a.append_array(["--openmw-cfg", install["path"]])
		"morrowind":
			a.append_array(["--morrowind", install["path"]])
		"data":
			a.append_array(["--data", install["path"]])
			for c in opts.get("content", ["Morrowind.esm"]):
				a.append_array(["--content", c])
			for arc in opts.get("archives", []):
				a.append_array(["--archive", arc])
	if opts.get("all_cells", false):
		a.append("--all-cells")
	for c in opts.get("cells", []):
		a.append_array(["--cell", c])
	if opts.has("grid_range"):
		a.append("--grid-range=" + String(opts["grid_range"]))
	if opts.get("all_models", false):
		a.append("--all-models")
	if opts.get("bake", false):
		a.append_array(["--bake-godot", OS.get_executable_path(), "--bake-project", ProjectSettings.globalize_path("res://")])
	if opts.has("jobs"):
		a.append_array(["--jobs", str(opts["jobs"])])
	return a

## Uruchamia konwersję w tle. Postęp odbierany przez poll() (wywoływane co klatkę) → sygnały.
func start(install: Dictionary, out_dir: String, opts := {}) -> Error:
	if _running:
		return ERR_BUSY
	var args := build_args(install, out_dir, opts)
	# uruchomienie z katalogu konwertera: python -m mwconv wymaga go w sys.path
	var env_args := PackedStringArray(["-c", "import sys, runpy; sys.path.insert(0, %s); sys.argv=['mwconv'] + sys.argv[1:]; runpy.run_module('mwconv', run_name='__main__')" % JSON.stringify(converter_dir)])
	env_args.append_array(args.slice(2))  # pomijamy "-m mwconv"
	var p := OS.execute_with_pipe(python, env_args, true)  # potoki blokujące – czytane w osobnym wątku
	if p.is_empty():
		return ERR_CANT_FORK
	pid = p["pid"]
	_stdio = p["stdio"]
	_running = true
	_thread = Thread.new()
	_thread.start(_reader)
	return OK

func _reader() -> void:
	while _stdio and _stdio.is_open():
		var l := _stdio.get_line()
		if l.is_empty() and _stdio.get_error() != OK:
			break
		_mutex.lock()
		_queue.append(l)
		_mutex.unlock()
	_mutex.lock()
	_queue.append("\u0000EOF")
	_mutex.unlock()

func is_running() -> bool:
	return _running

func poll() -> void:
	_mutex.lock()
	var q := _queue.duplicate()
	_queue.clear()
	_mutex.unlock()
	for l in q:
		if l == "\u0000EOF":
			_finish()
			continue
		if String(l).begins_with("MWPROGRESS "):
			var ev = JSON.parse_string(String(l).substr(11))
			if ev is Dictionary:
				match String(ev.get("event", "")):
					"progress":
						progress.emit(ev["stage"], int(ev["done"]), int(ev["total"]))
					"stage":
						progress.emit(ev["stage"], 0, int(ev.get("total", 0)))
					"done":
						last_done = ev
		else:
			line.emit(String(l))

func _finish() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_running = false
	# sukces = konwerter doszedł do końca (zdarzenie "done"); błędy pojedynczych modeli są w raporcie
	finished.emit(not last_done.is_empty(), last_done)

## Czy katalog wyników nadaje się do gry.
static func data_ready(out_dir: String) -> bool:
	return FileAccess.file_exists(out_dir.path_join("world/index.json"))

static func save_settings(values: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	for k in values:
		cf.set_value("mwgodot", k, values[k])
	cf.save(SETTINGS)

static func load_settings() -> Dictionary:
	var cf := ConfigFile.new()
	var out := {}
	if cf.load(SETTINGS) == OK and cf.has_section("mwgodot"):
		for k in cf.get_section_keys("mwgodot"):
			out[k] = cf.get_value("mwgodot", k)
	return out
