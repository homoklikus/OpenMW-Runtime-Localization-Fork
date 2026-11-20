extends SceneTree
## Tworzenie postaci w pięciu oknach jak OpenMW CharacterCreation: imię (puste – komunikat, okno zostaje), rasa
## (lista według nazwy, płeć, twarze i włosy z zawijaniem, premie i moce, podgląd 3D z kamerą przy kości głowy),
## klasa (wybór sposobu, lista, pytania, własna – osobny test), znak (lista, obraz, zdolności/moce/czary z efektami),
## przegląd (wartości z postaci, przyciski powrotu, „Wstecz” → znak → przegląd, ReviewNext); etapy CSE przy
## menu ze skryptów (okno zamyka się, gdy etap nie był jeszcze osiągnięty); brak podwójnych premii po powrotach;
## zapis i odczyt postaci z własną klasą.
## godot --headless --path godot -s res://tests/test_chargen_windows.gd -- --data=WYNIKI(aktorzy) --pos=… --scripts=0

const ClassDlg := preload("res://scripts/mw/mw_chargen_class.gd")

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

func _same_stats(a: Dictionary, b: Dictionary) -> bool:
	return a.attributes == b.attributes and a.skills == b.skills and a.spells == b.spells

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	var cg = main.chargen
	var ch = main.character
	var created := []
	cg.created.connect(func(st): created.append(st))
	var defaults: Dictionary = main.default_choice()
	cg.open(defaults)
	await _frames(1)
	# --- imię ---------------------------------------------------------------------------------------------
	check(cg.visible and paused and cg.mode == "name" and cg.step == "name", "okno imienia (osobne), gra wstrzymana")
	check(cg.win != null and is_equal_approx(cg.win.size.x, 320.0 * cg.ui.sc) and is_equal_approx(cg.win.size.y, 97.0 * cg.ui.sc),
		"rozmiar okna imienia jak openmw_text_input.layout (320 × 97)")
	check(cg.ok_button.text == main.dialogue.gmst_text("sOK", "OK"), "przycisk OK (etap niezaczęty – bez „Dalej”)")
	cg.name_edit.text = "   "
	check(not cg.accept() and cg.mode == "name", "puste imię – okno zostaje (sNotifyMessage37)")
	cg.name_edit.text = "Testowa"
	cg.name_edit.text_submitted.emit("Testowa")      # Enter
	await _frames(1)
	check(cg.mode == "race" and String(main.player_stats().get("name", "")) == "Testowa", "Enter zatwierdza imię; imię od razu w postaci")
	# --- rasa ---------------------------------------------------------------------------------------------
	check(is_equal_approx(cg.win.size.x, 640.0 * cg.ui.sc) and is_equal_approx(cg.win.size.y, 433.0 * cg.ui.sc), "okno rasy 640 × 433")
	var items := []
	for i in cg.race_list.item_count:
		items.append(cg.race_list.get_item_text(i))
	check(items == ["Ork testowy", "Synth Elf"] and cg.races == ["synth orc", "synth elf"], "lista ras grywalnych według nazwy (%s)" % [items])
	check(cg.race_id == "synth elf" and cg.race_list.get_selected_items() == PackedInt32Array([1]), "rasa postaci zaznaczona (%s)" % cg.race_id)
	check(cg.heads == ["b_n_synth_m_head_01", "b_n_synth_m_head_02"] and cg.hairs == ["b_n_synth_m_hair_01"], "twarze i włosy rasy/płci")
	check(cg.face_index == 0 and cg.race_result().head == "b_n_synth_m_head_01", "twarz postaci wybrana")
	check(cg.skill_box.get_child_count() == 1 and cg.power_box.get_child_count() == 0, "premie umiejętności rasy (1) i brak mocy")
	check(cg.head_rotate.value == 600.0 and absf(cg.angle - (600.0 / 999.0 - 0.5) * TAU) < 0.001, "obrót podglądu: 500 + 100 jak OpenMW")
	await _frames(3)
	check(cg._doll != null and cg.preview_vp != null and cg.preview_rect.texture != null, "podgląd 3D postaci w oknie rasy")
	var head: Vector3 = cg._head_position()
	var skel: Skeleton3D = cg._find_skeleton(cg._doll)
	check(skel != null and skel.find_bone("Bip01 Head") >= 0, "kość „Bip01 Head” w szkielecie podglądu")
	check(cg._cam != null and cg._cam.global_position.distance_to(head) > 1.5 and absf(cg._cam.fov - 12.3) < 0.01,
		"kamera podglądu przy głowie (odsunięcie 125 jedn., pole widzenia 12,3°)")
	cg._face_next()
	check(cg.race_result().head == "b_n_synth_m_head_02", "następna twarz")
	cg._face_next()
	check(cg.face_index == 0, "twarze zawijają się")
	cg._face_prev()
	check(cg.face_index == 1, "poprzednia twarz z zawinięciem")
	cg._hair_next()
	check(cg.hair_index == 0, "jedne włosy – zawinięcie w miejscu")
	cg._gender_next()
	check(cg.female and cg.face_index == 0 and cg.heads == ["b_n_synth_f_head_01"] and cg.race_result().hair == "b_n_synth_f_hair_01",
		"zmiana płci: części kobiece, indeksy od zera")
	var before: int = cg.skill_box.get_child_count()
	check(cg.choose("race", "synth orc"), "wybór rasy z listy")
	await _frames(1)
	check(cg.skill_box.get_child_count() == 2 and cg.power_box.get_child_count() == 1 and before == 1, "premie i moce aktualizowane na bieżąco")
	check(cg.heads.is_empty() and cg.race_result().head == String(defaults.head), "rasa bez części – głowa bez zmian")
	cg.choose("race", "synth elf")
	cg._gender_next()                                 # z powrotem mężczyzna
	cg._face_next()
	cg.back()                                         # Wstecz → imię (wybór zastosowany)
	check(cg.mode == "name" and String(main.player_stats().get("head", "")) == "b_n_synth_m_head_02", "rasa: Wstecz → imię, wybór zastosowany")
	check(cg.name_edit.text == "Testowa", "okno imienia pamięta imię")
	check(cg.ok_button.text == main.dialogue.gmst_text("sNext", "Next"), "imię: po przejściu etapu przycisk „Dalej”")
	cg.accept()
	check(cg.mode == "race" and cg.face_index == 1, "rasa: ponownie otwarta z twarzą postaci")
	cg.choose("race", "synth orc")
	cg._gender_next()                                 # kobieta – inne atrybuty
	cg.accept()
	await _frames(1)
	var orc: Dictionary = ch.records.record("race", "synth orc")
	var st: Dictionary = main.player_stats()
	check(st.race == "synth orc" and st.female, "rasa i płeć w postaci")
	# --- klasa (lista) --------------------------------------------------------------------------------------
	check(cg.mode == "class" and cg.step == "class", "okno wyboru sposobu klasy")
	cg.class_dialog.choice_selected(1)
	check(cg.mode == "class_pick" and cg.class_dialog.classes == ["synth warrior"], "lista klas grywalnych (bez niegrywalnych)")
	check(cg.class_dialog.class_image.texture != null, "obraz klasy z textures/levelup")
	check(cg.class_dialog._pick_widgets["major"][0].text != "", "umiejętności klasy w oknie")
	cg.class_dialog.pick_ok()
	# --- znak ---------------------------------------------------------------------------------------------
	check(cg.mode == "birth" and is_equal_approx(cg.win.size.x, 527.0 * cg.ui.sc), "okno znaku 527 × 378")
	var signs := []
	for i in cg.birth_list.item_count:
		signs.append(cg.birth_list.get_item_text(i))
	check(signs == ["Gwiazda testowa", "Znak testowy"], "znaki według nazwy (%s)" % [signs])
	check(cg.sign_id == "synth star" and cg.birth_image.texture != null, "bez znaku postaci – pierwszy z listy; obraz znaku (TNAM)")
	var texts := []
	for c in cg.spell_area.get_children():
		for l in c.find_children("*", "Label", true, false) + ([c] if c is Label else []):
			texts.append((l as Label).text)
	check(texts.size() >= 3 and "Sila testowa" in texts, "czary znaku z efektami (%s)" % [texts])
	cg.choose("birthsign", "synth sign")
	await _frames(1)
	texts = []
	for c in cg.spell_area.get_children():
		for l in c.find_children("*", "Label", true, false) + ([c] if c is Label else []):
			texts.append((l as Label).text)
	var effect_line := ""
	for t in texts:
		if t.contains("25"):
			effect_line = t
	check("Dar testowy" in texts and "Moc testowa" in texts and not effect_line.is_empty() and not effect_line.contains(" na "),
		"zdolność (efekty stałe – bez czasu i zasięgu) i moc (%s)" % [texts])
	cg.accept()
	# --- przegląd -----------------------------------------------------------------------------------------
	check(cg.mode == "review" and cg.step == "statreview" and is_equal_approx(cg.win.size.x, 541.0 * cg.ui.sc), "okno przeglądu 541 × 428")
	var rv: Dictionary = cg.review_values
	var expect: Dictionary = ch.build({"race": "synth orc", "female": true, "class": "synth warrior", "birthsign": "synth sign"})
	var d: Dictionary = ch.derived(expect)
	var exp_attrs := []
	for i in 8:
		exp_attrs.append(int(d.attributes[i]))
	check(rv.attributes == exp_attrs, "atrybuty w przeglądzie = buildPlayer (%s / %s)" % [rv.attributes, exp_attrs])
	var fa: Array = orc.attributes.female
	check(int(expect.attributes[1]) == int(fa[1]) and int(expect.attributes[0]) == int(fa[0]) + 10, "atrybuty kobiety rasy + ulubione klasy")
	check(rv.health == [int(expect.health), int(d.health.modified)] and rv.name == "Testowa" and rv.race == "synth orc"
		and rv["class"] == "synth warrior" and rv.sign == "synth sign", "przegląd: imię, rasa, klasa, znak, zdrowie")
	check("synth_power" in rv.spells and "synth_ability" in rv.spells and "synth_spark" in rv.spells, "przegląd: moce rasy i znaku, czar początkowy")
	check(rv.skills[10] == int(d.skills[10]) and int(d.skills[10]) == 5 + 15 + 10, "zniszczenie: 5 + rasa 15 + drugorzędna 10 (%s)" % rv.skills[10])
	# Wstecz → znak (ReviewBack: „Dalej”) → przegląd
	cg.back()
	check(cg.mode == "birth" and cg.ok_button.text == main.dialogue.gmst_text("sNext", "Next"), "przegląd: Wstecz → znak")
	cg.choose("birthsign", "synth star")
	cg.accept()
	check(cg.mode == "review" and cg.review_values.sign == "synth star", "znak → z powrotem przegląd")
	# ReviewNext: przycisk rasy → rasa → przegląd; brak podwójnych premii
	(cg.win.find_child("RaceButton", true, false) as Button).pressed.emit()
	check(cg.mode == "race" and cg.ok_button.text == main.dialogue.gmst_text("sNext", "Next"), "przycisk „Rasa” w przeglądzie → okno rasy")
	cg.choose("race", "synth elf")
	cg._gender_next()
	cg.accept()
	check(cg.mode == "review" and cg.review_values.race == "synth elf", "po zatwierdzeniu rasy – powrót do przeglądu")
	var fresh: Dictionary = ch.build(cg.choice())
	check(_same_stats(main.player_stats(), fresh), "statystyki po powrotach = zbudowane od zera (bez podwójnych premii)")
	for k in 3:
		(cg.win.find_child("ClassButton", true, false) as Button).pressed.emit()
		cg.accept()                                   # wybór sposobu → lista → OK → przegląd
	check(cg.mode == "review" and _same_stats(main.player_stats(), ch.build(cg.choice())), "wielokrotna zmiana klasy – bez kumulacji premii")
	(cg.win.find_child("NameButton", true, false) as Button).pressed.emit()
	cg.name_edit.text = "Nowa"
	cg.accept()
	check(cg.mode == "review" and cg.review_values.name == "Nowa", "przycisk „Imię” → zmiana imienia → przegląd")
	(cg.win.find_child("SignButton", true, false) as Button).pressed.emit()
	check(cg.mode == "birth", "przycisk „Znak” → okno znaku")
	cg.accept()
	# klasa z pytań z przeglądu
	(cg.win.find_child("ClassButton", true, false) as Button).pressed.emit()
	cg.class_dialog.choice_selected(0)
	for q in 10:
		cg.class_dialog.answer(cg.class_dialog._answers.find(1))       # magia
	check(cg.class_dialog.result_class == "mage" and cg.class_dialog.class_image.texture != null, "10 × magia → Mag (obraz zastępczy warrior)")
	cg.class_dialog.generate_back()
	check(cg.mode == "class" and cg.choice()["class"] == "mage", "wynik: „Wybierz inną” – klasa zastosowana, wybór sposobu")
	cg.back()
	check(cg.mode == "race", "wybór sposobu: Wstecz → rasa")
	cg.accept()
	cg.class_dialog.choice_selected(1)
	cg.accept()
	check(cg.mode == "review", "rasa → klasa → przegląd (ReviewNext)")
	cg.accept()
	await _frames(1)
	check(not cg.visible and not paused and cg.mode == "" and created.size() == 1, "przegląd OK – koniec tworzenia postaci")
	check(String(main.player_stats().get("name", "")) == "Nowa", "postać utworzona")
	# --- menu ze skryptów: etapy CSE ------------------------------------------------------------------------
	cg.reset()
	cg.open_step("name", main.state.player.get("chargen_choice", defaults))
	check(cg.mode == "name" and cg.ok_button.text == main.dialogue.gmst_text("sOK", "OK"), "EnableNameMenu: okno imienia, OK")
	cg.name_edit.text = "Skrypt"
	cg.accept()
	check(not cg.visible and cg.mode == "" and cg.stage == cg.CSE_NAME and not paused, "etap nieosiągnięty – okno zamyka się (skrypt prowadzi dalej)")
	cg.open_step("race", main.state.player.get("chargen_choice", defaults))
	check(cg.ok_button.text == main.dialogue.gmst_text("sOK", "OK"), "EnableRaceMenu: OK (rasa jeszcze niewybrana)")
	cg.accept()
	check(not cg.visible and cg.stage == cg.CSE_RACE, "rasa wybrana – okno zamknięte")
	cg.open_step("class", main.state.player.get("chargen_choice", defaults))
	cg.accept()
	check(not cg.visible and cg.stage == cg.CSE_CLASS, "klasa wybrana – okno zamknięte")
	cg.open_step("birth", main.state.player.get("chargen_choice", defaults))
	cg.accept()
	check(not cg.visible and cg.stage == cg.CSE_BIRTH, "znak wybrany – okno zamknięte")
	cg.open_step("statreview", main.state.player.get("chargen_choice", defaults))
	check(cg.mode == "review", "EnableStatReviewMenu: przegląd")
	cg.back()
	check(cg.mode == "birth" and cg.ok_button.text == main.dialogue.gmst_text("sNext", "Next"), "przegląd ze skryptu: Wstecz → znak „Dalej”")
	cg.accept()
	check(cg.mode == "review", "znak → przegląd")
	cg.accept()
	check(not cg.visible and created.size() == 1, "koniec przeglądu ze skryptu – bez sygnału kreatora szybkiego")
	# --- własna klasa w zapisie -----------------------------------------------------------------------------
	cg.open_step("class", main.state.player.get("chargen_choice", defaults))
	cg.class_dialog.choice_selected(2)
	cg.class_dialog.c_name.text = "Klasa zapisu"
	cg.class_dialog.c_name.text_changed.emit("Klasa zapisu")
	cg.class_dialog.create_ok()
	var path := ProjectSettings.globalize_path("user://chargen_windows/test.mwsave")
	check(main.save_game(path) == "", "zapis")
	var sk_before: Array = (main.player_stats().skills as Array).duplicate()
	main.state.player["character"] = {}
	main.load_game(path)
	await _frames(3)
	var back: Dictionary = main.player_stats()
	check(String(back.get("class", "")) == ClassDlg.CUSTOM_ID and back.skills == sk_before, "odczyt: własna klasa i umiejętności")
	check(String(ch.records.record("class", ClassDlg.CUSTOM_ID).get("name", "")) == "Klasa zapisu", "odczyt: rekord własnej klasy")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
