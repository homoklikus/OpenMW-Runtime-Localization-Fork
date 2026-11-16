extends SceneTree
## Etap 4: postać gracza – statystyki początkowe (OpenMW buildPlayer), wartości pochodne, stałe efekty zdolności,
## obrażenia od upadku, kreator, zapis i odczyt.
## godot --headless --path godot -s res://tests/test_character.gd -- --data=WYNIKI(aktorzy)

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	var ch = main.character
	var st0: Dictionary = main.player_stats()
	check(not st0.is_empty() and st0.race == "synth elf" and st0["class"] == "synth warrior",
			"postać domyślna z rekordu „player” (%s)" % [st0.get("race"), ])
	check(ch.playable("race") == ["synth elf"] and ch.playable("class") == ["synth warrior"] and ch.playable("birthsign") == ["synth sign"],
			"listy wyboru: grywalne rasy i klasy, znaki")
	var hh: Dictionary = ch.heads_hairs("Synth Elf", false)
	check(hh.heads == ["b_n_synth_m_head_01"] and hh.hairs == ["b_n_synth_m_hair_01"], "głowy i włosy rasy/płci (%s)" % [hh])
	var st: Dictionary = ch.build({"name": "Test", "race": "Synth Elf", "female": false, "class": "Synth Warrior",
			"birthsign": "Synth Sign", "head": "b_n_synth_m_head_01", "hair": "b_n_synth_m_hair_01"})
	var d: Dictionary = ch.derived(st)
	check(st.attributes[0] == 50.0 and st.attributes[5] == 50.0 and st.attributes[1] == 40.0, "atrybuty: rasa + 10 ulubionym klasy")
	check(st.skills[5] == 45.0, "długie ostrza: 5 + rasa 10 + główna 25 + specjalizacja 5 = 45 (%s)" % st.skills[5])
	check(st.skills[16] == 15.0 and st.skills[20] == 5.0, "alchemia 5 + drugorzędna 10; akrobatyka 5 (%s, %s)" % [st.skills[16], st.skills[20]])
	check(st.spells == ["synth_ability", "synth_power"], "czary znaku zodiaku (%s)" % [st.spells])
	check(d.attributes[7] == 65.0 and d.attributes[0] == 50.0, "zdolność: szczęście 40 + 25 (moc się nie liczy)")
	check(d.health.modified == 50.0 and is_equal_approx(d.magicka.modified, 80.0) and d.fatigue.modified == 180.0,
			"zdrowie 50, magia 2,0 × 40 = 80, kondycja 50+40+40+50 = 180 (%s, %s, %s)" % [d.health.modified, d.magicka.modified, d.fatigue.modified])
	check(st.health == 50.0 and st.magicka == d.magicka.modified and st.fatigue == 180.0, "wartości bieżące = maksymalne")
	# upadek: 1000 jedn., akrobatyka 5 → (0,07 × (1000 − 400 − 7,5)) × (0,25 + 0,0335 × 95) × (1 − 0,25 × 1,25)
	var expect := (0.07 * (1000.0 - 400.0 - 7.5)) * (0.25 + 0.0335 * 95.0) * (1.0 - 0.25 * 1.25)
	var lost: float = ch.apply_fall(st, 1000.0)
	check(absf(lost - expect) < 0.01 and absf(st.health - (50.0 - expect)) < 0.01, "obrażenia od upadku jak OpenMW (%.2f, oczekiwane %.2f)" % [lost, expect])
	check(ch.apply_fall(st, 300.0) == 0.0, "upadek poniżej fFallDamageDistanceMin – bez obrażeń")
	# kreator → postać w stanie gry → zapis → odczyt
	main.chargen.open({"race": "synth elf", "class": "synth warrior", "birthsign": "synth sign"})
	check(main.chargen.visible and paused, "kreator otwarty, gra wstrzymana")
	main.chargen.name_edit.text = "Nerevar"
	main.chargen._update()
	check(main.chargen.preview.text.contains("Zdrowie[/b] 50") and main.chargen.preview.text.contains("Dar testowy"), "podgląd statystyk w kreatorze")
	main.chargen._create()
	var pst: Dictionary = main.player_stats()
	check(not main.chargen.visible and not paused and pst.name == "Nerevar" and pst.birthsign == "synth sign", "postać utworzona i zapisana w stanie gry")
	pst["health"] = 12.0
	var path := ProjectSettings.globalize_path("user://test_saves/postac.mwsave")
	check(main.save_game(path) == "", "zapis")
	main.state.player["character"] = {}
	var w: Array = main.load_game(path)
	var back: Dictionary = main.player_stats()
	check(back.name == "Nerevar" and back.health == 12.0 and back.skills[5] == 45.0, "odczyt: imię, zdrowie bieżące, umiejętności (%s)" % [w])
	await process_frame
	await process_frame
	check(main.hud.text.contains("Nerevar") and main.hud.text.contains("zdrowie 12/50"), "pasek: imię i zdrowie (%s)" % main.hud.text.right(120))
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
