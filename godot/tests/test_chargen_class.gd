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
	cg.open({})
	await _frames(2)
	var dlg = cg.class_dialog
	check(cg.questions_button.visible, "pytania dostępne (teksty z Morrowind.ini w danych)")
	dlg.start_questions()
	await _frames(1)
	check(dlg.visible and dlg.step == 0, "pierwsze pytanie")
	var texts := []
	for b in dlg._box.get_children():
		if b is Label:
			texts.append(b.text)
	check("Pytanie testowe 1?" in texts, "tekst pytania z danych (%s)" % str(texts))
	for q in 10:
		var i: int = dlg._answers.find(0)      # odpowiedź „walka”, niezależnie od losowej kolejności
		dlg.answer(i)
		await _frames(1)
	check(dlg.step == 10 and dlg.result_class == "warrior", "10 × walka → Wojownik (%s)" % dlg.result_class)
	dlg.accept_result()
	await _frames(1)
	check(not dlg.visible and cg.choice()["class"] == "warrior", "klasa z pytań wybrana w kreatorze (%s)" % cg.choice()["class"])
	# własna klasa
	dlg.start_custom()
	await _frames(1)
	check(not dlg.accept_custom(), "bez nazwy nie można zatwierdzić")
	dlg.c_name.text = "Łowca testowy"
	var minor0: int = dlg.c_minor[0].selected
	var major0: int = dlg.c_major[0].selected
	dlg.c_major[0].select(minor0)
	dlg._skill_changed(minor0, dlg.c_major[0])
	check(dlg.c_major[0].selected == minor0 and dlg.c_minor[0].selected == major0, "ta sama umiejętność – zamiana pól")
	dlg.c_attr[1].select(dlg.c_attr[0].selected)
	dlg._attr_changed(dlg.c_attr[0].selected, 1)
	check(dlg.c_attr[0].selected != dlg.c_attr[1].selected, "ulubione atrybuty bez powtórzeń")
	dlg.c_spec.select(2)
	var rec: Dictionary = dlg.custom_record()
	var all_sk: Array = rec.major_skills + rec.minor_skills
	var uniq := {}
	for x in all_sk:
		uniq[x] = true
	check(uniq.size() == 10, "10 różnych umiejętności (%s)" % str(all_sk))
	check(dlg.accept_custom(), "zatwierdzenie własnej klasy")
	await _frames(1)
	check(cg.choice()["class"] == ClassDlg.CUSTOM_ID, "własna klasa wybrana")
	check((main.state.created.get("class", {}) as Dictionary).has(ClassDlg.CUSTOM_ID), "rekord klasy w stanie gry (zapis)")
	var st: Dictionary = main.character.build(cg.choice())
	var base: Dictionary = main.character.build(cg.choice().merged({"class": "warrior"}, true))
	var maj: int = int(rec.major_skills[1])
	check(float(st.skills[maj]) >= 30.0, "umiejętność główna własnej klasy podniesiona (+25) (%s)" % st.skills[maj])
	check(st.skills != base.skills, "statystyki liczone z własnej klasy")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
