extends SceneTree
## Etap 10 – dźwięk świata: głos „Hello” przy powitaniu (dialog głosowy z plikiem Vo, napis, aktor nie mówi
## dwóch kwestii naraz), Say ze skryptu z nagraniem (SayDone po końcu pliku), dźwięk otoczenia regionu
## (RegionSoundSelector), pętla pogody, muzyka: eksploracja → bitwa → eksploracja, StreamMusic ze skryptu.
## godot --headless --path godot -s res://tests/test_sound_world.gd -- --data=WYNIKI(aktorzy) --pos=2600,2700,900

var failures: Array[String] = []
var checks := 0
var report := {}

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

func _until(cond: Callable, max_frames: int) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await process_frame
	return -1

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
	var au = main.audio
	var mu = main.music
	check(au != null and mu != null, "dźwięk i muzyka uruchomione")

	# --- głos przy powitaniu
	var walker := _node(main, "synth_walker")
	check(walker != null, "wędrowiec w komórce")
	var said := []
	main.dialogue.voice_said.connect(func(sid, topic, iid): said.append([sid, topic, iid]))
	var ok: bool = main.dialogue.say_voice(walker, "hello")
	check(ok and said.size() == 1 and said[0][2] == "hello_walker", "Hello: odpowiedź dla wędrowca (%s)" % str(said))
	var wsid := String(walker.get_meta("mw_sid", ""))
	check(au.say_active(wsid), "głos z pliku Vo gra")
	check(not main.dialogue.say_voice(walker, "hello"), "aktor nie mówi drugiej kwestii, gdy pierwsza trwa")
	var villager := _node(main, "synth_villager")
	check(villager != null and not main.dialogue.say_voice(villager, "hello"), "bez pasującej odpowiedzi – brak kwestii")
	var end := await _until(func(): return not au.say_active(wsid), 300)
	check(end >= 0, "kwestia się kończy (%d klatek)" % end)

	# --- Say ze skryptu: SayDone po nagraniu
	var host = main.script_host
	var t := {"sid": String(villager.get_meta("mw_sid", "")), "node": villager, "base": "synth_villager"}
	host.say(t, "vo\\synth.wav", "Kim jestes?")
	check(au.say_active(t.sid) and not host.say_done(t), "Say: nagranie gra, SayDone = 0")
	var done := await _until(func(): return host.say_done(t), 400)
	check(done >= 0, "Say: SayDone = 1 po nagraniu (%d klatek)" % done)
	host.say(t, "vo\\nie_ma_takiego.wav", "Tekst")
	check(not au.say_active(t.sid) and not host.say_done(t), "Say bez pliku: czas z długości tekstu")

	# --- dźwięk otoczenia regionu
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	au.region_played = 0
	var region := {"sounds": [{"id": "Synth Wind", "chance": 100}]}
	for i in 600:
		au.region_tick(1.0 / 60.0, region, true, rng)
		await process_frame
	report["region_played"] = au.region_played
	check(au.region_played >= 2, "dźwięk regionu co 1–5 s, gdy poprzedni się skończył (%d w 10 s)" % au.region_played)
	var before: int = au.region_played
	for i in 300:
		au.region_tick(1.0 / 60.0, region, false, rng)
	check(au.region_played == before, "we wnętrzu bez dźwięków regionu")
	check(not (main.envr.regions.get("synthetic region", {}).get("sounds", []) as Array).is_empty(),
			"szanse dźwięków regionu z danych (REGN SNAM)")

	# --- pętla pogody (bez pliku – tylko stan) i pod wodą
	au.ambient_tick("clear", true, false)
	check(au.loop_playing("weather") == "", "bezchmurnie – bez pętli pogody")

	# --- muzyka
	var explore := await _until(func(): return mu.current == "explore" and mu.is_playing(), 120)
	check(explore >= 0, "muzyka eksploracji gra (%s)" % mu.track)
	var guard := _node(main, "synth_guard")
	main.ai.start_combat(guard, main.player)
	var battle := await _until(func(): return mu.current == "battle" and mu.is_playing(), 240)
	check(battle >= 0, "walka w pobliżu → muzyka bitwy (%s)" % mu.track)
	main.ai.stop_combat(guard)
	var back := await _until(func(): return mu.current == "explore" and mu.is_playing(), 240)
	check(back >= 0, "koniec walki → znów eksploracja")
	var first: String = mu.track
	await _until(func(): return mu.track != first, 200)
	check(mu.track != first and mu.track.begins_with("music/explore/"), "po utworze następny z playlisty (%s → %s)" % [first, mu.track])
	main.scripts.start("synth_music")
	await _until(func(): return mu.music_type == "script" and mu.is_playing() and mu.track.contains("battle"), 1500)
	check(mu.music_type == "script" and mu.track == "music/battle/synth_battle.wav", "StreamMusic ze skryptu (%s)" % mu.track)
	main.ai.start_combat(guard, main.player)
	await _frames(20)
	check(mu.music_type == "script", "muzyki skryptu nie przerywa playlista bitwy")
	main.ai.stop_combat(guard)

	report["played"] = au.stats.played
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(1 if failures.size() > 0 else 0)
