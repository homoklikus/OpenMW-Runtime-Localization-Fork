extends CanvasLayer
## Filmy jak OpenMW WindowManager::playVideo (mwgui/windowmanagerimp.cpp):
## * plik „video\<nazwa>” – u nas <dane>/video/<nazwa>.ogv (Theora z lokalnej konwersji Binka przez ffmpeg;
##   szukany też w konwersji bazowej profilu); brak pliku = film pominięty (VideoWidget nie wystartuje),
## * czarne tło na cały ekran i obraz z zachowaniem proporcji (autoResize bez [GUI] stretch menu background),
## * w trakcie filmu świat stoi (OpenMW odtwarza film we własnej pętli zamiast klatki gry) – u nas pauza drzewa
##   na czas filmu; scena 3D niewidoczna (enableScene(false)), kursor ukryty,
## * allowSkipping: tylko Esc przerywa film (onVideoKeyPressed),
## * overrideSounds (domyślnie tak): pozostałe dźwięki wstrzymane, gdy film ma ścieżkę dźwięku (pauseSounds
##   VideoPlayback); bez tego (logo Morrowinda w menu głównym) muzyka gra dalej.
## Odtwarzanie jest asynchroniczne: `await play(...)` zwraca po końcu filmu albo pominięciu.

signal finished(name: String, skipped: bool)

var main = null
var data_roots: Array = []          # [<dane>, …bazy profilu]
var playing := false
var current := ""
var allow_skipping := true
var _player: VideoStreamPlayer = null
var _bg: ColorRect = null
var _skipped := false
var _paused_before := false
var _music_paused := false
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var played: Array = []              # testy/sondy: [nazwa, pominięty, czas odtwarzania s]
var _t0 := 0

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.visible = false
	add_child(_bg)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.finished.connect(_on_finished)
	_bg.add_child(_player)
	get_viewport().size_changed.connect(_resize)

## Ścieżka pliku filmu albo "" (nazwa jak w skryptach/fallbackach: „mw_intro.bik”, „video\x.bik”).
func resolve(name: String) -> String:
	var n := name.replace("\\", "/").to_lower()
	if n.begins_with("video/"):
		n = n.substr(6)
	n = n.get_basename() + ".ogv"
	for r in data_roots:
		var p := String(r).path_join("video").path_join(n)
		if FileAccess.file_exists(p):
			return p
	return ""

## Czy film ma ścieżkę dźwięku (video/index.json z konwersji; brak informacji – tak).
func has_audio(name: String) -> bool:
	var n := name.replace("\\", "/").to_lower()
	if not n.begins_with("video/"):
		n = "video/" + n
	n = n.get_basename() + ".bik"
	for r in data_roots:
		var p := String(r).path_join("video/index.json")
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if d is Dictionary and (d.get("videos", {}) as Dictionary).has(n):
				return bool(d.videos[n].get("audio", true))
	return true

## WindowManager::playVideo. Zwraca true, gdy film był odtwarzany (false – brak pliku).
func play(name: String, skippable := true, override_sounds := true) -> bool:
	if playing:
		stop()
	var path := resolve(name)
	if path.is_empty():
		push_warning("Film %s: brak pliku (konwersja filmów: ffmpeg)" % name)
		played.append([name.to_lower(), false, 0.0, "brak"])
		return false
	var st := VideoStreamTheora.new()
	st.file = path
	_player.stream = st
	current = name.to_lower()
	allow_skipping = skippable
	_skipped = false
	playing = true
	_bg.visible = true
	_resize()
	var tree := get_tree()
	_paused_before = tree.paused
	_music_paused = false
	if override_sounds and has_audio(name) and main != null and main.get("music") != null and main.music != null:
		main.music.set_paused(true)             # muzyka gra w pauzie drzewa – wstrzymywana jawnie
		_music_paused = true
	tree.paused = true                          # pozostałe dźwięki (węzły zależne od pauzy) stoją razem ze światem
	if main != null and main.has_method("set_scene_visible"):
		main.set_scene_visible(false)
	if DisplayServer.get_name() != "headless":
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_player.volume_db = linear_to_db(_volume())
	_t0 = Time.get_ticks_msec()
	_player.play()
	await finished
	return true

func _volume() -> float:
	if main == null or main.get("settings") == null:
		return 1.0
	var s: Dictionary = main.settings
	return clampf(float(s.get("master_volume", 1.0)), 0.0, 1.0)        # volumeFromType(Movie): tylko master

## Esc przerywa film (tylko z allowSkipping).
func _input(e: InputEvent) -> void:
	if not playing:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if (e as InputEventKey).keycode == KEY_ESCAPE and allow_skipping:
			_skipped = true
			stop()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton or e is InputEventMouseMotion:
		get_viewport().set_input_as_handled()

func stop() -> void:
	if not playing:
		return
	_player.stop()
	_on_finished()

func _on_finished() -> void:
	if not playing:
		return
	playing = false
	_bg.visible = false
	_player.stream = null
	if _music_paused and main != null and main.get("music") != null and main.music != null:
		main.music.set_paused(false)
	_music_paused = false
	get_tree().paused = _paused_before
	if main != null and main.has_method("set_scene_visible"):
		main.set_scene_visible(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_before
	var secs := (Time.get_ticks_msec() - _t0) / 1000.0
	played.append([current, _skipped, secs, "ok"])
	var n := current
	current = ""
	finished.emit(n, _skipped)

## Proporcje obrazu zachowane, czarne pasy (VideoWidget::autoResize(false)).
func _resize() -> void:
	if _player == null or _player.stream == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var tex := _player.get_video_texture()
	var vs := Vector2(640, 480)
	if tex != null and tex.get_width() > 0:
		vs = Vector2(tex.get_width(), tex.get_height())
	var sc := minf(vp.x / vs.x, vp.y / vs.y)
	_player.size = (vs * sc).floor()
	_player.position = ((vp - _player.size) / 2.0).floor()

func _process(_d: float) -> void:
	if playing:
		_resize()
