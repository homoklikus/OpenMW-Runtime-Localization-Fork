extends SceneTree
## Sonda tworzenia postaci na prawdziwych danych (Xvfb, renderer zgodności): pięć okien jak OpenMW i okna klas,
## zrzuty do porównania z OpenMW (te same nazwy co w tools/openmw-xvfb: name, race, classchoice, classpick,
## classcreate, selspec, selattr, selskill, question1, genresult, birth, review), potem sprawdzenie wszystkich ras
## i obu płci (twarze, włosy, podgląd), wszystkich klas (obraz, statystyki), wszystkich znaków (obraz, czary),
## pytań (wynik = istniejąca klasa) i statystyk końcowych (= buildPlayer od zera po wielu powrotach).
## Zrzuty zawierają obraz gry – tylko lokalnie (PROBE_SHOTS=katalog). Wyniki: identyfikatory i liczby.
## godot --rendering-method gl_compatibility --resolution 1280x720 --path godot -s res://tests/probe_chargen.gd --
##   --data=WYNIKI --cell="Seyda Neen" --scripts=0
var main
var cg
var shots := ""
var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init():
	_run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(shots.path_join(name + ".png"))
		print("PROBE zrzut ", name)

func wait_s(s: float) -> void:
	await create_timer(s, true).timeout

func ch() -> Dictionary:
	return main.state.player.get("chargen_choice", main.default_choice())

func _run():
	shots = OS.get_environment("PROBE_SHOTS")
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shots)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await wait_s(6.0)
	cg = main.chargen
	var character = main.character
	cg.reset()
	main.state.player["chargen_choice"] = main.default_choice()
	# --- zrzuty okien ----------------------------------------------------------------------------------------
	cg.open_step("name", ch())
	await shot("name")
	cg.name_edit.text = "abc"
	await shot("name2")
	cg.accept()
	cg.open_step("race", ch())
	await wait_s(1.0)
	await shot("race")
	cg.accept()
	cg.open_step("class", ch())
	await shot("classchoice")
	cg.class_dialog.choice_selected(1)
	await shot("classpick")
	cg.back()
	cg.class_dialog.choice_selected(2)
	await shot("classcreate")
	cg.class_dialog.spec_button.pressed.emit()
	await shot("selspec")
	cg.class_dialog._close_sub()
	cg.class_dialog.attr_buttons[0].pressed.emit()
	await shot("selattr")
	cg.class_dialog._close_sub()
	cg.class_dialog.major_buttons[0].pressed.emit()
	await shot("selskill")
	cg.class_dialog._close_sub()
	(cg.win.find_child("DescriptionButton", true, false) as Button).pressed.emit()
	await shot("description")
	cg.class_dialog._close_sub()
	cg.back()
	cg.class_dialog.choice_selected(0)
	await shot("question1")
	for q in 10:
		cg.class_dialog.answer(0)
	await shot("genresult")
	print("PROBE wynik pytań (przyciski 1.) ", cg.class_dialog.result_class)
	cg.class_dialog.generate_ok()
	cg.open_step("birth", ch())
	await shot("birth")
	cg.accept()
	cg.open_step("statreview", ch())
	await shot("review")
	cg.accept()
	# --- wszystkie rasy i obie płcie -------------------------------------------------------------------------
	cg.reset()
	cg.open_step("race", ch())
	var races: Array = cg.races.duplicate()
	print("PROBE rasy ", races.size(), " ", races)
	check(races.size() == 10, "10 grywalnych ras Morrowinda (%d)" % races.size())
	var bad := []
	for r in races:
		for fem in [false, true]:
			cg.choose("race", r)
			if cg.female != fem:
				cg._gender_next()
			var nh: int = cg.heads.size()
			var nr: int = cg.hairs.size()
			if nh == 0 or nr == 0:
				bad.append([r, fem, nh, nr])
			var heads_seen := {}
			for i in nh:
				heads_seen[cg.race_result().head] = true
				cg._face_next()
			var hairs_seen := {}
			for i in nr:
				hairs_seen[cg.race_result().hair] = true
				cg._hair_next()
			if heads_seen.size() != nh or hairs_seen.size() != nr or cg.face_index != 0 or cg.hair_index != 0:
				bad.append([r, fem, "cykl"])
			await process_frame
			if cg._doll == null:
				bad.append([r, fem, "podgląd"])
			print("PROBE rasa %s %s twarze=%d włosy=%d" % [r, "K" if fem else "M", nh, nr])
			if fem == true or r == races[0]:
				await shot("race_%s_%s" % [String(r).replace(" ", "_"), "f" if fem else "m"])
	check(bad.is_empty(), "każda rasa i płeć: twarze, włosy (zawijanie), podgląd (%s)" % [bad])
	cg.accept()
	# --- wszystkie klasy ---------------------------------------------------------------------------------------
	cg.open_step("class", ch())
	cg.class_dialog.choice_selected(1)
	var classes: Array = cg.class_dialog.classes.duplicate()
	print("PROBE klasy ", classes.size())
	check(classes.size() == 21, "21 grywalnych klas (%d)" % classes.size())
	var bad_c := []
	for c in classes:
		cg.choose("class", c)
		var w: Dictionary = cg.class_dialog._pick_widgets
		if cg.class_dialog.class_image.texture == null or String(w.spec.text).is_empty() or String(w.major[4].text).is_empty() \
				or String(w.minor[4].text).is_empty() or String(w.attr[1].text).is_empty():
			bad_c.append(c)
		if UI_tex("textures/levelup/" + String(c)) == null:
			print("PROBE klasa bez własnego obrazu (zastępczy warrior): ", c)
	check(bad_c.is_empty(), "każda klasa: obraz, specjalizacja, atrybuty, umiejętności (%s)" % [bad_c])
	cg.accept()
	# pytania: każda kombinacja liczby odpowiedzi daje istniejącą klasę
	var bad_q := []
	for combat in 11:
		for magic in 11 - combat:
			var cls: String = cg.class_dialog.class_for(combat, magic, 10 - combat - magic).to_lower()
			if character.records.record("class", cls).is_empty():
				bad_q.append([combat, magic, cls])
	check(bad_q.is_empty(), "wynik pytań zawsze istniejącą klasą (%s)" % [bad_q])
	# --- wszystkie znaki ---------------------------------------------------------------------------------------
	cg.open_step("birth", ch())
	var signs: Array = cg.signs.duplicate()
	print("PROBE znaki ", signs.size())
	check(signs.size() == 13, "13 znaków urodzenia (%d)" % signs.size())
	var bad_s := []
	for s in signs:
		cg.choose("birthsign", s)
		var lines: int = cg.spell_area.get_child_count()
		if cg.birth_image.texture == null or lines < 2:
			bad_s.append([s, lines])
		print("PROBE znak %s elementy=%d" % [s, lines])
	check(bad_s.is_empty(), "każdy znak: obraz i czary z efektami (%s)" % [bad_s])
	cg.accept()
	# --- statystyki końcowe po wielu powrotach ---------------------------------------------------------------
	cg.open_step("statreview", ch())
	for i in 3:
		(cg.win.find_child("RaceButton", true, false) as Button).pressed.emit()
		cg.choose("race", races[(i * 3) % races.size()])
		cg.accept()
		(cg.win.find_child("ClassButton", true, false) as Button).pressed.emit()
		cg.class_dialog.choice_selected(1)
		cg.choose("class", classes[(i * 5) % classes.size()])
		cg.accept()
		(cg.win.find_child("SignButton", true, false) as Button).pressed.emit()
		cg.choose("birthsign", signs[(i * 4) % signs.size()])
		cg.accept()
	var st: Dictionary = main.player_stats()
	var fresh: Dictionary = character.build(cg.choice())
	check(st.attributes == fresh.attributes and st.skills == fresh.skills and st.spells == fresh.spells,
		"statystyki po powrotach = buildPlayer od zera")
	print("PROBE postać rasa=%s klasa=%s znak=%s zdrowie=%s czary=%d" % [st.race, st["class"], st.birthsign, st.health, (st.spells as Array).size()])
	cg.accept()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)

func UI_tex(rel: String) -> Texture2D:
	return preload("res://scripts/mw/mw_ui.gd").texture(rel)
