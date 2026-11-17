extends Node
## Muzyka (etap 10) jak w OpenMW: playlisty z katalogów music/explore i music/battle (skrypt Lua
## scripts/omw/music/music.lua): bitwa (priorytet 10) przed eksploracją (100), utwory w losowej kolejności bez
## powtórzenia tego samego utworu na styku kolejek, przejście z wyciszeniem (fade 1 s); muzyka bitwy, gdy jakiś
## aktor w zasięgu ma cel walki. StreamMusic ze skryptu (MusicType::MWScript) nie jest przerywany przez
## playlisty, dopóki gra. Śmierć gracza: music/special/mw_death.mp3. Głośność jak OpenMW [Sound] music volume 0,5.

var data_root := ""
var enabled := true
var volume := 0.5
var fade_time := 1.0

var playlists := {}            # id → {"priority", "tracks": [ścieżki względne], "order": [indeksy]}
var current := ""              # id bieżącej playlisty
var music_type := "normal"     # normal | script
var track := ""                # bieżący plik (względem <dane>)
var _player: AudioStreamPlayer = null
var _fade := 0.0               # > 0: wyciszanie w toku (pozostały czas)
var _next := ""
var rng := RandomNumberGenerator.new()
var started := 0               # testy: ile utworów rozpoczęto

func setup(root: String) -> void:
	data_root = root
	rng.randomize()
	_register("battle", 10)
	_register("explore", 100)

func _register(id: String, priority: int) -> void:
	var tracks := []
	var dir := data_root.path_join("music").path_join(id)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			if f.get_extension().to_lower() in ["mp3", "wav"]:
				tracks.append("music/%s/%s" % [id, f])
	tracks.sort()
	playlists[id] = {"priority": priority, "tracks": tracks, "order": _order(tracks.size(), -1)}

## helpers.initTracksOrder + zamiana, gdy pierwszy z nowej kolejki to ostatnio grany (music.lua).
func _order(n: int, last: int) -> Array:
	var o := range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = o[i]
		o[i] = o[j]
		o[j] = t
	if n > 1 and o[n - 1] == last:            # zdejmowany jest koniec tablicy (table.remove)
		var k := rng.randi_range(0, n - 2)
		var t2 = o[n - 1]
		o[n - 1] = o[k]
		o[k] = t2
	return o

func is_playing() -> bool:
	return _player != null and is_instance_valid(_player) and _player.playing

## Co klatkę: in_combat – czy jakiś aktor w zasięgu walczy; dead – gracz martwy (bez zmiany playlist).
func tick(delta: float, in_combat: bool, dead := false) -> void:
	_update_fade(delta)
	if not enabled:
		return
	if dead and is_playing():
		return
	if music_type == "script" and (is_playing() or not _next.is_empty()):
		return
	var want := "battle" if in_combat and not (playlists.battle.tracks as Array).is_empty() else "explore"
	if (playlists[want].tracks as Array).is_empty():
		return
	if want == current and (is_playing() or not _next.is_empty()):
		return
	_switch(want)

func _switch(id: String) -> void:
	var pl: Dictionary = playlists[id]
	var order: Array = pl.order
	if order.is_empty():
		order = _order((pl.tracks as Array).size(), -1)
	var idx: int = order.pop_back()
	if order.is_empty():
		order = _order((pl.tracks as Array).size(), idx)
	pl.order = order
	current = id
	music_type = "normal"
	_advance(String(pl.tracks[idx]), fade_time)

## StreamMusic ze skryptu: od razu z wyciszeniem poprzedniego, bez przerywania przez playlisty.
func stream_script(file: String, fade := 1.0) -> void:
	var f := file.replace("\\", "/").to_lower()
	if not f.begins_with("music/"):
		f = "music/" + f
	music_type = "script"
	current = ""
	_advance(f, fade)

## Engine::go: muzyka tytułowa w menu głównym (MWSound::titleMusic, MusicType::Normal – playlisty gry ją zastąpią).
const TITLE_MUSIC := "music/special/morrowind title.mp3"

func play_title() -> bool:
	if not enabled or not FileAccess.file_exists(data_root.path_join(TITLE_MUSIC)):
		push_warning("Title music not found")
		return false
	music_type = "normal"
	current = ""
	_next = ""
	_fade = 0.0
	_start(TITLE_MUSIC)
	return is_playing()

## SoundManager::stopMusic (np. przed filmem nowej gry).
func stop_music() -> void:
	_next = ""
	_fade = 0.0
	_stop()
	track = ""
	current = ""

## Wstrzymanie na czas filmu (pauseSounds VideoPlayback).
func set_paused(on: bool) -> void:
	if _player != null and is_instance_valid(_player):
		_player.stream_paused = on

func player_died() -> void:
	music_type = "script"
	_advance("music/special/mw_death.mp3", fade_time)

## advanceMusic: gdy nic nie gra – od razu, inaczej wyciszenie bieżącego i potem następny.
func _advance(file: String, fade: float) -> void:
	if not is_playing():
		_start(file)
		return
	_next = file
	_fade = maxf(fade, 0.01)

func _update_fade(delta: float) -> void:
	if _fade <= 0.0:
		if not _next.is_empty() and not is_playing():
			var n := _next
			_next = ""
			_start(n)
		return
	_fade -= delta
	if is_playing():
		_player.volume_db = linear_to_db(maxf(volume * clampf(_fade / fade_time, 0.0, 1.0), 0.0001))
	if _fade <= 0.0:
		_fade = 0.0
		_stop()
		if not _next.is_empty():
			var n2 := _next
			_next = ""
			_start(n2)

func _stop() -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = null

func _start(file: String) -> void:
	_stop()
	track = file
	var path := data_root.path_join(file)
	var s: AudioStream = null
	if FileAccess.file_exists(path):
		match file.get_extension().to_lower():
			"mp3": s = AudioStreamMP3.load_from_file(path)
			"wav": s = AudioStreamWAV.load_from_file(path)
	if s == null:
		if music_type == "script":
			music_type = "normal"
		return
	_player = AudioStreamPlayer.new()
	_player.stream = s
	_player.volume_db = linear_to_db(maxf(volume, 0.0001))
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.finished.connect(_on_finished)
	_player.play()
	started += 1

func _on_finished() -> void:
	_stop()
	if music_type == "script" and _next.is_empty():
		music_type = "normal"
