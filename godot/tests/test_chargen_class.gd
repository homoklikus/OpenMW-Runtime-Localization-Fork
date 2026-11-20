extends SceneTree
## Etap 10 – klasa postaci jak w OpenMW: 10 pytań (teksty z Morrowind.ini → world/fallbacks.json), wynik według
## tabeli showClassQuestionDialog, własna klasa (bez powtórzeń umiejętności i atrybutów, bez nazwy – nie można
## zatwierdzić), rekord klasy utworzony w grze (GameState.created) i statystyki liczone z niego.
## godot --headless --path godot -s res://tests/test_chargen_class.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

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

func _run() -> void:
	# tabela wyników (CharacterCreation::showClassQuestionDialog)
	var cases := {[10, 0, 0]: "Warrior", [0, 8, 2]: "Mage", [1, 1, 8]: "Thief", [4, 3, 3]: "Rogue",
		[5, 2, 3]: "Scout", [5, 3, 2]: "Archer", [6, 3, 1]: "Barbarian", [6, 1, 3]: "Crusader", [6, 2, 2]: "Knight",
		[3, 4, 3]: "Spellsword", [2, 5, 3]: "Witchhunter", [2, 6, 2]: "Sorcerer", [3, 6, 1]: "Healer",
		[1, 6, 3]: "Battlemage", [2, 3, 5]: "Monk", [3, 2, 5]: "Pilgrim", [3, 1, 6]: "Agent", [1, 3, 6]: "Assassin",
		[2, 2, 6]: "Acrobat"}
	var bad := []
	for k in cases:
		if ClassDlg.class_for(k[0], k[1], k[2]) != cases[k]:
			bad.append([k, ClassDlg.class_for(k[0], k[1], k[2]), cases[k]])
	check(bad.is_empty(), "tabela klas z pytań jak OpenMW %s" % str(bad))

	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	var cg = main.chargen
	cg.open(main.default_choice())
	cg.name_edit.text = "Testowa"
	cg.accept()
	cg.accept()                                   # rasa → okno wyboru sposobu klasy
	var dlg = cg.class_dialog
	check(cg.mode == "class" and dlg.choice_buttons.size() == 4, "ClassChoiceDialog: 3 sposoby i „Wstecz”")
	check(dlg.questions_available(), "teksty pytań z Morrowind.ini w danych")
	dlg.choice_selected(0)
	await _frames(1)
	check(cg.mode == "class_generate" and dlg.step == 0 and dlg.answer_buttons.size() == 3, "pierwsze pytanie (3 odpowiedzi)")
	check(dlg.question_text == "Pytanie testowe 1?", "tekst pytania z danych (%s)" % dlg.question_text)
	var labels: Array = dlg.answer_buttons.map(func(b): return b.get_meta("label").text if b.has_meta("label") else b.text)
	labels.sort()
	check(labels == ["Magia 1", "Skradanie 1", "Walka 1"], "odpowiedzi z danych (%s)" % [labels])
	for q in 10:
		var i: int = dlg._answers.find(0)      # odpowiedź „walka”, niezależnie od losowej kolejności
		dlg.answer(i)
		await _frames(1)
	check(dlg.step == 10 and dlg.result_class == "warrior", "10 × walka → Wojownik (%s)" % dlg.result_class)
	check(dlg.class_image != null and dlg.class_image.texture != null, "obraz klasy z textures/levelup")
	dlg.generate_ok()
	await _frames(1)
	check(cg.mode == "birth" and cg.choice()["class"] == "warrior", "klasa z pytań przyjęta, dalej znak (%s, %s)" % [cg.mode, cg.choice()["class"]])
	check(String(main.player_stats().get("class", "")) == "warrior", "klasa od razu w postaci (setPlayerClass)")
	# „Wstecz” w oknie znaku → wybór sposobu klasy → własna klasa
	cg.back()
	check(cg.mode == "class", "znak: Wstecz → wybór sposobu klasy")
	dlg.choice_selected(2)
	await _frames(1)
	check(cg.mode == "class_create" and dlg.c_name.text == main.dialogue.gmst_text("sCustomClassName", "Adventurer"),
		"nazwa domyślna sCustomClassName (%s)" % dlg.c_name.text)
	check(dlg.create_state.attributes == [0, 3] and dlg.create_state.major_skills == [0, 1, 2, 3, 4] \
		and dlg.create_state.minor_skills == [5, 6, 7, 8, 9] and dlg.create_state.specialization == 0, "wartości domyślne jak OpenMW")
	dlg.c_name.text = ""
	dlg.c_name.text_changed.emit("")
	check(not dlg.create_ok(), "bez nazwy nie można zatwierdzić")
	dlg.c_name.text = "Łowca testowy"
	dlg.c_name.text_changed.emit("Łowca testowy")
	# okna wyboru jak w OpenMW: specjalizacja, atrybut, umiejętność (przyciski)
	dlg.spec_button.pressed.emit()
	check(dlg.sub_kind == "specialization", "okno wyboru specjalizacji")
	(dlg.sub.find_child("Specialization2", true, false) as Button).pressed.emit()
	check(dlg.sub == null and dlg.create_state.specialization == 2, "specjalizacja: skradanie")
	dlg.attr_buttons[1].pressed.emit()
	check(dlg.sub_kind == "attribute", "okno wyboru atrybutu")
	(dlg.sub.find_child("Attribute0", true, false) as Button).pressed.emit()
	check(dlg.create_state.attributes == [3, 0], "ten sam atrybut w drugim polu – zamiana (%s)" % [dlg.create_state.attributes])
	dlg.major_buttons[0].pressed.emit()
	check(dlg.sub_kind == "skill", "okno wyboru umiejętności (3 kolumny według specjalizacji)")
	(dlg.sub.find_child("Skill5", true, false) as Button).pressed.emit()
	check(dlg.create_state.major_skills[0] == 5 and dlg.create_state.minor_skills[0] == 0, "ta sama umiejętność – zamiana pól")
	(cg.win.find_child("DescriptionButton", true, false) as Button).pressed.emit()
	check(dlg.sub_kind == "description", "okno opisu")
	dlg.desc_edit.text = "Opis testowy"
	(dlg.sub.find_child("OKButton", true, false) as Button).pressed.emit()
	check(dlg.create_state.description == "Opis testowy", "opis zapamiętany")
	var rec: Dictionary = dlg.custom_record()
	var uniq := {}
	for x in rec.major_skills + rec.minor_skills:
		uniq[x] = true
	check(uniq.size() == 10, "10 różnych umiejętności (%s)" % str(rec.major_skills + rec.minor_skills))
	check(dlg.create_ok(), "zatwierdzenie własnej klasy")
	await _frames(1)
	check(cg.choice()["class"] == ClassDlg.CUSTOM_ID and cg.mode == "birth", "własna klasa wybrana, dalej znak")
	check((main.state.created.get("class", {}) as Dictionary).has(ClassDlg.CUSTOM_ID), "rekord klasy w stanie gry (zapis)")
	# okno pamięta wybory (Wstecz → własna klasa ponownie)
	cg.back()
	dlg.choice_selected(2)
	check(dlg.c_name.text == "Łowca testowy" and dlg.create_state.specialization == 2, "okno własnej klasy pamięta wybory")
	dlg.create_ok()
	var st: Dictionary = main.player_stats()
	var base: Dictionary = main.character.build(cg.choice().merged({"class": "synth warrior"}, true))
	var maj: int = int(rec.major_skills[1])
	check(float(st.skills[maj]) >= 30.0, "umiejętność główna własnej klasy podniesiona (+25) (%s)" % st.skills[maj])
	check(st.skills != base.skills, "statystyki liczone z własnej klasy")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
