extends SceneTree
## Etap 10 (zgłoszenie: „animacja biegu jakby się resetowała”): grupy ruchu i bezczynności zapętlone jak
## Animation::play z nieskończoną liczbą pętli – w pętli tylko odcinek „loop start” → „loop stop”, nie cały klip
## „start” → „stop” (skok pozy co cykl); grupy bez pętli (śmierć) – cały klip; klawisze dźwięków z odcinka pętli.
## godot --headless --path godot -s res://tests/test_anim_loop.gd

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	var AV := load("res://scripts/mw/mw_actor_visual.gd")
	var av = AV.new(null, null)
	var sk := Skeleton3D.new()
	sk.add_bone("Bip01")
	var doc := {"duration": 4.0,
		"clips": {"runforward": {"start": 0.0, "stop": 4.0, "loop_start": 1.0, "loop_stop": 3.0},
			"death1": {"start": 0.0, "stop": 4.0, "loop_start": 1.0, "loop_stop": 3.0},
			"idle": {"start": 0.0, "stop": 4.0, "loop_start": null, "loop_stop": null}},
		"text_keys": [[0.5, "SoundGen: Left"], [1.5, "SoundGen: Right"], [2.5, "SoundGen: Left"]],
		"tracks": [{"node": "Bip01", "translation": {"times": [0.0, 1.0, 3.0, 4.0],
			"values": [[0, 5, 0], [0, 0, 0], [0, 0, 10], [0, 7, 12]]}}]}
	var lib: AnimationLibrary = av.anim_library("test", [doc], sk)
	var run := lib.get_animation("runforward")
	check(is_equal_approx(run.length, 2.0), "runforward: pętla loop start → loop stop (2 s, jest %.2f)" % run.length)
	check(run.loop_mode == Animation.LOOP_LINEAR, "runforward zapętlony")
	check(is_equal_approx(float(run.get_meta("mw_speed", 0.0)), 5.0), "prędkość grupy z odcinka pętli (10 m / 2 s – %.2f)" % float(run.get_meta("mw_speed", 0.0)))
	var keys: Array = run.get_meta("mw_keys", [])
	check(keys.size() == 2 and is_equal_approx(float(keys[0][0]), 0.5), "klawisze dźwięków z odcinka pętli (%s)" % [keys])
	var death := lib.get_animation("death1")
	check(is_equal_approx(death.length, 4.0), "death1 bez skracania (%.2f)" % death.length)
	check(is_equal_approx(lib.get_animation("idle").length, 4.0), "idle bez pętli w klipie – cały klip")
	sk.free()
	print("RESULT ", JSON.stringify({"test": "anim_loop", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
