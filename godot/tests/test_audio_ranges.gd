extends SceneTree
## Etap 10 cz. 34: zasięg i głośność dźwięków jak OpenMW 0.51 – SoundBufferPool::insertSound (MinRange/MaxRange albo
## fAudioDefaultMin/MaxDistance, × fAudioMin/MaxDistanceMult), SoundManager::say (fAudioVoiceDefaultMin/MaxDistance
## × mnożniki), głośność rekordu 10^((v/255 × 3348 − 3348)/2000). Wcześniej głos NPC miał zasięg 40 j. (0,6 m) –
## na sprzęcie użytkownika głosy były niesłyszalne.
## godot --headless --path godot -s res://tests/test_audio_ranges.gd -- --data=WYNIKI(aktorzy) --scripts=0

const MWCoords := preload("res://scripts/mw/mw_coords.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var au = main.audio
	var mn_mult: float = au._gmst("faudiomindistancemult", 20.0)
	var mx_mult: float = au._gmst("faudiomaxdistancemult", 50.0)
	var d: Vector2 = au.sound_range(0.0, 0.0)
	check(is_equal_approx(d.x, maxf(au._gmst("faudiodefaultmindistance", 5.0) * mn_mult, 1.0))
		and is_equal_approx(d.y, maxf(au._gmst("faudiodefaultmaxdistance", 40.0) * mx_mult, d.x)),
		"bez zasięgu w rekordzie: fAudioDefault × mnożniki (%s)" % d)
	var r: Vector2 = au.sound_range(3.0, 30.0)
	check(is_equal_approx(r.x, 3.0 * mn_mult) and is_equal_approx(r.y, 30.0 * mx_mult), "MinRange/MaxRange × mnożniki (%s)" % r)
	var r2: Vector2 = au.sound_range(0.01, 0.0)
	check(r2.x >= 1.0 and r2.y >= r2.x, "min ≥ 1, max ≥ min (%s)" % r2)
	var v: Vector2 = au.voice_range()
	check(is_equal_approx(v.x, maxf(au._gmst("faudiovoicedefaultmindistance", 10.0) * mn_mult, 1.0))
		and is_equal_approx(v.y, maxf(au._gmst("faudiovoicedefaultmaxdistance", 80.0) * mx_mult, v.x)) and v.y >= 1000.0,
		"głos: fAudioVoiceDefault × mnożniki, zasięg ≥ 1000 j. (%s)" % v)
	check(is_equal_approx(au.record_volume({"volume": 255}), 1.0) and absf(au.record_volume({"volume": 0}) - pow(10.0, -3348.0 / 2000.0)) < 1e-6
		and absf(au.record_volume({"volume": 128}) - pow(10.0, (128.0 / 255.0 * 3348.0 - 3348.0) / 2000.0)) < 1e-6,
		"głośność rekordu: 10^((v/255 × 3348 − 3348)/2000)")
	# say(): odtwarzacz 3D przy aktorze z zasięgiem głosu
	var n := Node3D.new()
	main.add_child(n)
	var secs: float = au.say("diag_test", "Vo\\synth\\hello.wav", n)
	var p = au._voices.get("diag_test")
	if p != null and p is AudioStreamPlayer3D:
		check(is_equal_approx(p.unit_size, v.x / MWCoords.UNITS_PER_METER) and is_equal_approx(p.max_distance, v.y / MWCoords.UNITS_PER_METER),
			"say: unit_size i max_distance z zasięgu głosu")
	else:
		check(false, "say: brak odtwarzacza 3D (%s)" % secs)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
