extends Node
## Dźwięk (etap 3): efekty z rekordów SOUN (pliki z <dane>/sound/… – WAV/MP3 kopiowane przez konwerter),
## dźwięk w przestrzeni 3D albo bez pozycji; kroki gracza. Etap 10: głosy (sound/vo – SoundManager::say: jedna
## kwestia naraz na aktora, z głowy aktora), dźwięki otoczenia regionu (RegionSoundSelector), pętle pogody,
## dźwięk pod wodą; muzyka – mw_music.gd. Głośności jak domyślne ustawienia OpenMW (efekty 1,0, głosy 0,8).
## Głośność i zasięg jak w OpenMW (SoundManager): volume/255, min/max z rekordu × fAudioMinDistanceMult (20)
## i fAudioMaxDistanceMult (50) – w jednostkach MW; 0/0 → fAudioDefaultMinDistance/MaxDistance.

var data_root := ""
var records                    # obiekt z record(file, id)
var enabled := true
var _cache := {}
var stats := {"played": 0, "missing": 0, "loaded": 0}
var last_played := ""          # diagnostyka/testy
var voice_volume := 0.8        # OpenMW [Sound] voice volume
var sfx_volume := 1.0          # OpenMW [Sound] sfx volume
var footsteps_volume := 0.2    # OpenMW [Sound] footsteps volume

func setup(root: String, records_source) -> void:
	data_root = root
	records = records_source

func _gmst(id: String, def: float) -> float:
	var g: Dictionary = records.record("gmst", id) if records != null else {}
	return float(g.get("value", def)) if not g.is_empty() else def

static func norm(f: String) -> String:
	return f.replace("\\", "/").to_lower()

func stream(sound_id: String) -> AudioStream:
	var k := sound_id.to_lower()
	if _cache.has(k):
		return _cache[k]
	var rec: Dictionary = records.record("sound", k) if records != null else {}
	var s: AudioStream = null
	if not rec.is_empty() and rec.has("file"):
		var path := data_root.path_join("sound").path_join(norm(String(rec["file"])))
		if FileAccess.file_exists(path):
			match path.get_extension():
				"wav":
					s = AudioStreamWAV.load_from_file(path)
				"mp3":
					s = AudioStreamMP3.load_from_file(path)
			if s:
				stats.loaded += 1
	if s == null:
		stats.missing += 1
	_cache[k] = s
	return s

## Dźwięki skryptów przypisane do obiektu (klucz „obiekt|id dźwięku”), jak w OpenMW SoundManager: na jednym
## obiekcie gra naraz tylko jedna kopia danego dźwięku – GetSoundPlaying/StopSound je sprawdzają i zatrzymują,
## a PlayLoopSound3D, gdy ta pętla już gra, niczego nie dokłada. Bez tego skrypty w rodzaju
## „if (GetSoundPlaying … == 0) PlayLoopSound3DVP …” tworzyły setki odtwarzaczy na sekundę (przycięcia gry).
var _tracked := {}

func play_on(owner_key: String, sound_id: String, at = null, volume := 1.0, pitch := 1.0, loop := false) -> Node:
	var k := owner_key + "|" + sound_id.to_lower()
	var old = _tracked.get(k)
	if old != null and is_instance_valid(old):
		if loop and bool(old.get_meta("mw_loop", false)):
			if at is Vector3 and old is Node3D:
				(old as Node3D).position = at
			return old
		old.queue_free()                 # nowe odtworzenie zastępuje poprzednią kopię na tym obiekcie
	_tracked.erase(k)
	var p := play(sound_id, at, volume)
	if p == null:
		return null
	p.set("pitch_scale", maxf(pitch, 0.01))
	if loop:
		p.set_meta("mw_loop", true)
		p.finished.disconnect(p.queue_free)
		p.finished.connect(p.play)
	_tracked[k] = p
	p.tree_exiting.connect(func():
		if _tracked.get(k) == p:
			_tracked.erase(k))
	return p

func is_playing_on(owner_key: String, sound_id: String) -> bool:
	var p = _tracked.get(owner_key + "|" + sound_id.to_lower())
	return p != null and is_instance_valid(p) and not p.is_queued_for_deletion()

func stop_on(owner_key: String, sound_id := "") -> void:
	for k in _tracked.keys():
		if (k as String).begins_with(owner_key + "|") and (sound_id.is_empty() or k == owner_key + "|" + sound_id.to_lower()):
			var p = _tracked[k]
			if p != null and is_instance_valid(p):
				p.queue_free()
			_tracked.erase(k)

## Liczba aktywnych odtwarzaczy (diagnostyka/testy).
func player_count() -> int:
	return get_child_count()

## Odtwarza dźwięk SOUN; at = pozycja w Godocie (NAN – bez pozycji). Zwraca odtwarzacz albo null.
func play(sound_id: String, at = null, volume := 1.0) -> Node:
	if not enabled or sound_id.is_empty():
		return null
	var s := stream(sound_id)
	if s == null:
		return null
	var rec: Dictionary = records.record("sound", sound_id.to_lower())
	var vol := record_volume(rec) * volume * sfx_volume
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		var r := sound_range(float(rec.get("min_range", 0)), float(rec.get("max_range", 0)))
		p3.unit_size = r.x / MWCoords.UNITS_PER_METER
		p3.max_distance = r.y / MWCoords.UNITS_PER_METER
		p3.position = at
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.process_mode = Node.PROCESS_MODE_ALWAYS        # dźwięki okien przy pauzie
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	stats.played += 1
	last_played = sound_id
	return p

# --- kroki gracza (co ~0,9 m chodu; lewa/prawa na zmianę; boso – bez ekwipunku gracza, etap 4) ----------------

var _step_dist := 0.0
var _step_left := true

## choose(left: bool) -> id dźwięku (etap 10: wg butów i wody jak Npc::getSoundIdFromSndGen); bez – boso.
func footsteps(actor: Node3D, delta_pos: float, on_floor: bool, swimming: bool, choose: Callable = Callable()) -> void:
	if (not on_floor and not swimming):
		_step_dist = 0.0
		return
	_step_dist += delta_pos
	if _step_dist >= (1.4 if swimming else 0.9):
		_step_dist = 0.0
		var snd := String(choose.call(_step_left)) if choose.is_valid() else ("FootBareLeft" if _step_left else "FootBareRight")
		if not snd.is_empty():
			play(snd, null, footsteps_volume / maxf(sfx_volume, 0.01))
		_step_left = not _step_left

# --- głosy (etap 10) -------------------------------------------------------------------------------------

var _voices := {}              # właściciel (sid / „player”) → odtwarzacz
var _files := {}               # ścieżka → AudioStream (null = brak)

## Plik dźwięku z danych (ścieżka względem <dane>, np. „sound/vo/d/m/hlo_dm001.mp3”) – jak
## Misc::ResourceHelpers::correctSoundPath: brakujący .wav szukany jako .mp3 (Bethesda zmieniła część formatów).
func file_stream(rel: String) -> AudioStream:
	var k := norm(rel)
	if _files.has(k):
		return _files[k]
	var s: AudioStream = null
	for cand in [k, k.get_basename() + ".mp3", k.get_basename() + ".wav"]:
		var path := data_root.path_join(cand)
		if FileAccess.file_exists(path):
			match cand.get_extension():
				"wav": s = AudioStreamWAV.load_from_file(path)
				"mp3": s = AudioStreamMP3.load_from_file(path)
			if s != null:
				break
	_files[k] = s
	return s

## Ścieżka głosu z rekordu (INFO SNAM, argument Say): „Vo\d\m\x.mp3” → „sound/vo/d/m/x.mp3”.
static func voice_path(file: String) -> String:
	var f := norm(file)
	return f if f.begins_with("sound/") else "sound/" + f

## SoundBufferPool::insertSound: zasięg dźwięku (jednostki MW) – MinRange/MaxRange rekordu, przy obu zerowych
## fAudioDefaultMin/MaxDistance; potem × fAudioMin/MaxDistanceMult, min ≥ 1, max ≥ min. → (min, max)
func sound_range(min_range: float, max_range: float) -> Vector2:
	var mn := min_range
	var mx := max_range
	if mn == 0.0 and mx == 0.0:
		mn = _gmst("faudiodefaultmindistance", 5.0)
		mx = _gmst("faudiodefaultmaxdistance", 40.0)
	mn = maxf(mn * _gmst("faudiomindistancemult", 20.0), 1.0)
	mx = maxf(mx * _gmst("faudiomaxdistancemult", 50.0), mn)
	return Vector2(mn, mx)

## SoundManager::say: zasięg głosu – fAudioVoiceDefaultMin/MaxDistance × fAudioMin/MaxDistanceMult (min ≥ 1).
func voice_range() -> Vector2:
	var mn := maxf(_gmst("faudiovoicedefaultmindistance", 10.0) * _gmst("faudiomindistancemult", 20.0), 1.0)
	var mx := maxf(_gmst("faudiovoicedefaultmaxdistance", 80.0) * _gmst("faudiomaxdistancemult", 50.0), mn)
	return Vector2(mn, mx)

## Głośność rekordu SOUN jak SoundBufferPool: 10^((v / 255 × 3348 − 3348) / 2000).
static func record_volume(rec: Dictionary) -> float:
	var v := float(rec.get("volume", 255))
	return pow(10.0, (v / 255.0 * 3348.0 - 3348.0) / 2000.0)

## Say: głos aktora (node – węzeł aktora albo null = gracz/bez pozycji). Poprzednia kwestia tego aktora jest
## przerywana (stopSay). Zwraca długość nagrania w sekundach albo -1, gdy pliku nie ma.
func say(owner_key: String, file: String, node: Node3D = null, head_height := 1.6) -> float:
	stop_say(owner_key)
	if not enabled or file.is_empty():
		return -1.0
	var s := file_stream(voice_path(file))
	if s == null:
		stats.missing += 1
		return -1.0
	var p: Node
	if node != null and is_instance_valid(node):
		var p3 := AudioStreamPlayer3D.new()
		var vr := voice_range()
		p3.unit_size = vr.x / MWCoords.UNITS_PER_METER
		p3.max_distance = vr.y / MWCoords.UNITS_PER_METER
		p3.position = Vector3(0, head_height, 0)
		node.add_child(p3)             # głos idzie za aktorem (OpenMW aktualizuje pozycję z głowy)
		p = p3
	else:
		p = AudioStreamPlayer.new()
		add_child(p)
	p.stream = s
	p.volume_db = linear_to_db(maxf(voice_volume, 0.0001))
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.queue_free)
	p.play()
	_voices[owner_key] = p
	stats.played += 1
	last_played = file
	return s.get_length()

func say_active(owner_key: String) -> bool:
	var p = _voices.get(owner_key)
	return p != null and is_instance_valid(p) and not p.is_queued_for_deletion() and p.playing

func stop_say(owner_key: String) -> void:
	var p = _voices.get(owner_key)
	if p != null and is_instance_valid(p):
		p.queue_free()
	_voices.erase(owner_key)

# --- otoczenie: dźwięki regionu, pogoda, pod wodą (etap 10) -------------------------------------------

## RegionSoundSelector: co losowy czas z [min, max] (Morrowind.ini Weather_Minimum/Maximum_Time_Between_
## Environmental_Sounds = 1 i 5 s) losowanie po kolei z listy regionu (roll0to99 < szansa); nowy dźwięk dopiero,
## gdy poprzedni się skończył. Tylko na zewnątrz.
var env_min_time := 1.0
var env_max_time := 5.0
var _env_passed := 0.0
var _env_next := 0.0
var _region_sound: Node = null
var region_played := 0         # testy

func region_tick(delta: float, region: Dictionary, exterior: bool, rng: RandomNumberGenerator = null) -> void:
	if not exterior:
		return
	if _region_sound != null and is_instance_valid(_region_sound) and not _region_sound.is_queued_for_deletion():
		return
	_env_passed += delta
	if _env_passed < _env_next:
		return
	var a := rng.randf() if rng != null else randf()
	_env_next = env_min_time + (env_max_time - env_min_time) * a
	_env_passed = 0.0
	for snd in region.get("sounds", []):
		if not snd is Dictionary:
			continue
		var roll := rng.randi_range(0, 99) if rng != null else randi_range(0, 99)
		if roll < int(snd.get("chance", 0)):
			_region_sound = play(String(snd.get("id", "")))
			if _region_sound != null:
				region_played += 1
			return

## Pętle pogody jak domyślne Weather_*_Ambient_Loop_Sound_ID (Morrowind.ini) i dźwięk pod wodą („Underwater”).
const WEATHER_LOOPS := {"rain": "Rain", "thunder": "rain heavy", "ash": "ashstorm", "blight": "Blight",
	"blizzard": "BM Blizzard"}
var _loops := {}               # nazwa → odtwarzacz

func _loop(name: String, sound_id: String, on: bool) -> void:
	var p = _loops.get(name)
	var cur := String(p.get_meta("mw_id", "")) if p != null and is_instance_valid(p) else ""
	if on and cur == sound_id:
		return
	if p != null and is_instance_valid(p):
		p.queue_free()
	_loops.erase(name)
	if not on or sound_id.is_empty():
		return
	var np := play(sound_id)
	if np != null:
		np.set_meta("mw_id", sound_id)
		np.finished.disconnect(np.queue_free)
		np.finished.connect(np.play)
		_loops[name] = np

func ambient_tick(weather: String, exterior: bool, underwater: bool) -> void:
	var w := weather.to_lower()
	_loop("weather", String(WEATHER_LOOPS.get(w, "")), exterior and WEATHER_LOOPS.has(w))
	_loop("underwater", "Underwater", underwater)

func loop_playing(name: String) -> String:
	var p = _loops.get(name)
	return String(p.get_meta("mw_id", "")) if p != null and is_instance_valid(p) else ""
