extends Node
## Minimalny dźwięk (etap 3): efekty z rekordów SOUN (pliki z <dane>/sound/… – WAV/MP3 kopiowane przez konwerter),
## dźwięk w przestrzeni 3D albo bez pozycji; kroki gracza. Głosy, muzyka i dźwięki otoczenia – etap 10.
## Głośność i zasięg jak w OpenMW (SoundManager): volume/255, min/max z rekordu × fAudioMinDistanceMult (20)
## i fAudioMaxDistanceMult (50) – w jednostkach MW; 0/0 → fAudioDefaultMinDistance/MaxDistance.

var data_root := ""
var records                    # obiekt z record(file, id)
var enabled := true
var _cache := {}
var stats := {"played": 0, "missing": 0, "loaded": 0}
var last_played := ""          # diagnostyka/testy

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

## Odtwarza dźwięk SOUN; at = pozycja w Godocie (NAN – bez pozycji). Zwraca odtwarzacz albo null.
func play(sound_id: String, at = null, volume := 1.0) -> Node:
	if not enabled or sound_id.is_empty():
		return null
	var s := stream(sound_id)
	if s == null:
		return null
	var rec: Dictionary = records.record("sound", sound_id.to_lower())
	var vol := float(rec.get("volume", 255)) / 255.0 * volume
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		var mn := float(rec.get("min_range", 0))
		var mx := float(rec.get("max_range", 0))
		if mn == 0.0 and mx == 0.0:
			mn = _gmst("faudiodefaultmindistance", 100.0)
			mx = _gmst("faudiodefaultmaxdistance", 2000.0)
		else:
			mn = maxf(mn, 1.0) * _gmst("faudiomindistancemult", 20.0)
			mx = maxf(mx, 1.0) * _gmst("faudiomaxdistancemult", 50.0)
		p3.unit_size = mn / MWCoords.UNITS_PER_METER
		p3.max_distance = maxf(mx, mn) / MWCoords.UNITS_PER_METER
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

func footsteps(actor: Node3D, delta_pos: float, on_floor: bool, swimming: bool) -> void:
	if not on_floor or swimming:
		_step_dist = 0.0
		return
	_step_dist += delta_pos
	if _step_dist >= 0.9:
		_step_dist = 0.0
		play("FootBareLeft" if _step_left else "FootBareRight", null, 0.6)
		_step_left = not _step_left
