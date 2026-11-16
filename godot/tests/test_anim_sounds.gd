extends SceneTree
## Etap 10 – dźwięki z kluczy animacji: „Sound:” i „SoundGen:” z tekstów .kf (przecięcie klucza w trakcie
## odtwarzania, także po zapętleniu), kroki NPC i gracza wg butów i wody, rekordy SNDG stworzeń (własne → ogólne).
## godot --headless --path godot -s res://tests/test_anim_sounds.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

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

func _node(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	get_root().get_tree().paused = false
	var asnd = main.anim_sounds
	check(asnd != null, "dźwięki animacji uruchomione")
	var vil := _node(main, "synth_villager")
	var ap: AnimationPlayer = main.ai._player_of(vil)
	check(ap != null and ap.has_animation("idle"), "animacja bezczynności NPC")
	var keys: Array = ap.get_animation("idle").get_meta("mw_keys", []) if ap != null else []
	check(keys.size() == 3, "klucze dźwięku z tekstów .kf (%s)" % str(keys))
	# odtwarzanie: po 2,5 s (pętla) wszystkie trzy klucze odtworzone
	main.player.global_position = vil.global_position + Vector3(2, 0, 0)
	asnd.played.clear()
	ap.play("idle")
	ap.seek(0.0, true)
	var vsid := String(vil.get_meta("mw_sid", ""))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2600:
		await process_frame
		asnd.tick(0.016)
	var mine: Array = asnd.played.filter(func(p): return p[0] == vsid).map(func(p): return p[1])
	check(mine.any(func(s): return String(s).to_lower() == "item misc up"), "„Sound: Item Misc Up” przy aktorze (%s)" % str(mine))
	check(mine.any(func(s): return String(s).to_lower().begins_with("foot")), "„SoundGen: Left/Right” – kroki NPC")
	# kroki wg butów i wody
	check(asnd.footstep(vil, true, true, true, true) == "Swim Left", "pływanie – Swim Left")
	check(asnd.footstep(vil, false, false, true, true) == "FootWaterRight", "w wodzie – FootWaterRight")
	check(asnd.footstep(vil, true, false, false, false) == "", "w powietrzu – bez kroku")
	var sk: int = asnd.boots_skill(vil)
	var exp: String = {21: "footLightLeft", 2: "FootMedLeft", 3: "FootHeavyLeft"}.get(sk, "FootBareLeft")
	check(asnd.footstep(vil, true, false, false, true) == exp, "buty (%d) → %s" % [sk, exp])
	check(main._player_step_sound(true).begins_with("Foot") or main._player_step_sound(true).begins_with("foot"), "kroki gracza wg butów")
	# SNDG
	var cr := _node(main, "synth_creature")
	check(cr != null and asnd.sound_for(cr, "moan") == "Item Misc Down", "SNDG stworzenia: pomruk z własnego rekordu")
	check(asnd.creature_sound("synth_creature", 0) == "FootBareLeft", "brak własnego – ogólny SNDG (krok)")
	check(asnd.creature_sound("synth_creature", 6) == "", "brak rekordu – bez dźwięku")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
