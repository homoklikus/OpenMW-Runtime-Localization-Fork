extends SceneTree
## Ruch aktora po stopniach (jak OpenMW Stepper: sStepSizeUp = 34 jedn.) i dźwięki skryptów przypisane do
## obiektu (GetSoundPlaying/StopSound, pętla PlayLoopSound3D bez dokładania odtwarzaczy).
## Dane syntetyczne – bez zasobów gry.
## godot --headless --path godot -s res://tests/test_step_sound.gd

const Actor := preload("res://scripts/mw/mw_actor.gd")
const Audio := preload("res://scripts/mw/mw_audio.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

class FakeRecords:
	func record(file: String, id: String) -> Dictionary:
		if file == "sound" and id in ["synth creak", "synth bell"]:
			return {"file": id.replace(" ", "_") + ".wav", "volume": 255}
		return {}

func _init() -> void:
	_run.call_deferred()

func _box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	parent.add_child(b)

## Aktor idzie 2 s naprzód (−z) w stronę uskoku o wysokości h_mw (jednostki MW); zwraca końcowe y i z.
func _walk_to_step(h_mw: float) -> Vector2:
	var w := Node3D.new()
	root.add_child(w)
	_box(w, Vector3(20, 1, 40), Vector3(0, -0.5, 0))                      # podłoga, wierzch y = 0
	var h := h_mw / MWCoords.UNITS_PER_METER
	_box(w, Vector3(20, h, 10), Vector3(0, h * 0.5, -6.0))               # stopień od z = −1 do −11
	var a := Actor.new()
	a.kind = "player"
	w.add_child(a)
	a.global_position = Vector3(0, 0.01, 0)
	for i in 10:
		await physics_frame
	for i in 120:
		a.move_input = Vector2(0, -1)
		await physics_frame
	var r := Vector2(a.global_position.y, a.global_position.z)
	w.queue_free()
	await physics_frame
	return r

func _run() -> void:
	# --- stopnie
	var low := await _walk_to_step(16.0)          # jak krawędź trapu okrętu więziennego nad pokładem
	check(low.x > 0.2 and low.y < -2.5, "stopień 16 jedn.: aktor wchodzi i idzie dalej (y=%.2f z=%.2f)" % [low.x, low.y])
	var mid := await _walk_to_step(30.0)
	check(mid.x > 0.4 and mid.y < -2.5, "stopień 30 jedn. (< sStepSizeUp 34): wchodzi (y=%.2f z=%.2f)" % [mid.x, mid.y])
	var wall := await _walk_to_step(60.0)
	check(wall.x < 0.1 and wall.y > -1.0, "uskok 60 jedn.: zatrzymuje (y=%.2f z=%.2f)" % [wall.x, wall.y])

	# --- dźwięki skryptów
	var dir := OS.get_user_data_dir().path_join("test_step_sound")
	DirAccess.make_dir_recursive_absolute(dir.path_join("sound"))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(22050)                                # ok. 0,5 s ciszy
	wav.data = pcm
	for f in ["synth_creak.wav", "synth_bell.wav"]:
		wav.save_to_wav(dir.path_join("sound").path_join(f))
	var au := Audio.new()
	root.add_child(au)
	au.setup(dir, FakeRecords.new())
	for i in 30:                                     # skrypt wołający pętlę w każdej klatce
		au.play_on("ship#1", "Synth Creak", Vector3.ZERO, 0.5, 1.2, true)
		await process_frame
	check(au.player_count() == 1, "PlayLoopSound3D co klatkę: jeden odtwarzacz (%d)" % au.player_count())
	check(au.is_playing_on("ship#1", "synth creak"), "GetSoundPlaying: pętla gra")
	check(not au.is_playing_on("ship#2", "synth creak"), "GetSoundPlaying: inny obiekt – nie gra")
	for i in 5:                                      # zwykły dźwięk ponownie – zastępuje poprzednią kopię
		au.play_on("bell#1", "Synth Bell", Vector3.ZERO)
		await process_frame
	check(au.player_count() == 2, "PlaySound3D powtórzony: jedna kopia na obiekt (%d)" % au.player_count())
	au.stop_on("ship#1", "synth creak")
	await process_frame
	check(not au.is_playing_on("ship#1", "synth creak"), "StopSound zatrzymuje pętlę")
	await create_timer(1.0).timeout
	check(not au.is_playing_on("bell#1", "synth bell") and au.player_count() == 0, "dźwięk jednorazowy kończy się i znika (%d)" % au.player_count())

	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
