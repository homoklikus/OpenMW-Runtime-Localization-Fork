extends SceneTree
## Etap 6: dialogi, zadania i dziennik – powitania (TalkedToPc), tematy z hiperłączami, pytania (Choice),
## skrypty wyniku w kontekście rozmówcy (zmienne lokalne, Journal, ModDisposition, PCJoinFaction, Goodbye),
## odmowa wg postawy („Info Refusal”), perswazja, podstawienia (%PCName, %Name, %Rank, %Faction, %Cell),
## dziennik z datą, zakończenie zadania, dziennik tematów, okno dziennika, zapis i odczyt.
## godot --headless --path godot -s res://tests/test_dialogue.gd -- --data=WYNIKI(aktorzy)

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Ostatnia odpowiedź (bez komunikatów, np. o wpisie w dzienniku).
func _last(dl) -> Dictionary:
	for i in range(dl.history.size() - 1, -1, -1):
		if dl.history[i].kind == "response":
			return dl.history[i]
	return {}

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var dl = main.dialogue
	var win = main.dialogue_window
	var st = main.state
	main.player_stats()["name"] = "Tester"
	check(dl != null and dl.available(), "dane dialogów wczytane (world/records/dialogue.json)")
	# wpis z dziennika ze skryptu startowego (Journal synth_q 10) – tekst z podstawieniem komórki, data
	var ents: Array = dl._ds().entries
	check(ents.size() == 1 and String(ents[0].text).begins_with("Zaczalem zadanie testowe w ") and not String(ents[0].text).contains("%"),
			"Journal: wpis z tekstem odpowiedzi i podstawieniem %%Cell (%s)" % [ents])
	check(ents.size() == 1 and ents[0].has("day") and ents[0].has("month") and ents[0].has("day_of_month"), "wpis z datą")
	# stworzenie i NPC bez powitania – okno się nie otwiera
	var cr := _ref(main, "synth_creature")
	check(cr != null and main.activate(cr) and not win.visible, "stworzenie bez odpowiedzi – brak okna rozmowy")
	var vf := _ref(main, "synth_villager_f")
	check(vf != null and not main.open_dialogue(vf) and not win.visible, "NPC bez powitania – brak okna")
	# rozmowa z NPC: pierwsze powitanie (TalkedToPc == 0)
	var v := _ref(main, "synth_villager")
	check(v != null and main.activate(v) and win.visible and get_root().get_tree().paused, "aktywacja NPC otwiera okno rozmowy (pauza)")
	check(String(_last(dl).get("text", "")) == "Witaj, Tester. Pytaj o Synth Lore, jesli chcesz.", "powitanie z %%PCName (%s)" % [_last(dl)])
	check(dl.available_topics() == ["synth lore"], "temat poznany z tekstu powitania (%s)" % [dl.available_topics()])
	check(win.history_label.text.contains("[url=topic:synth%20lore]"), "hiperłącze tematu w historii")
	check(dl.derived_disposition(dl.actor) == 50, "postawa pochodna: 50 + rasa 5 + osobowość −5 = 50 (%d)" % dl.derived_disposition(dl.actor))
	# temat z pytaniem
	win.select_topic("synth lore")
	check(String(_last(dl).get("text", "")) == "Czy pomozesz mi z dzwignia?" and String(_last(dl).title) == "Synth Lore",
			"odpowiedź tematu z tytułem")
	check(dl.in_choice and dl.choices == [["Tak", 1], ["Nie", 2]] and win.bye_btn.disabled and not win.close(),
			"Choice: pytanie, „Żegnaj” nieaktywne, okna nie można zamknąć")
	check(win.history_label.text.contains("[url=choice:1]"), "odpowiedzi w historii jako odnośniki")
	win._on_meta("choice:1")
	var vsid := String(v.get_meta("mw_sid"))
	check(String(_last(dl).get("text", "")) == "Dziekuje. Opowiem ci o @Synth Secret#." and not dl.in_choice
			and win.history_label.text.contains("[url=topic:synth%20secret][color=" + win.LINK + "]Synth Secret[/color][/url]."),
			"odpowiedź na pytanie (Choice == 1), „@temat#” jako odnośnik z nazwą (%s)" % [_last(dl)])
	check(float(st.scripts.locals.get(vsid, {}).get("helped", 0)) == 1.0, "skrypt wyniku: zmienna lokalna rozmówcy")
	check(int(st.journal.get("synth_q", 0)) == 30 and bool(dl._ds().quests.get("synth_q", {}).get("finished", false)),
			"Journal 30: indeks i zakończenie zadania (QSTF)")
	check(String(dl._ds().entries[-1].text) == "Syntetyczny poprosil o pomoc. Zadanie zakonczone.", "%%Name rozmówcy we wpisie")
	check(dl.history.any(func(h): return h.kind == "message"), "komunikat o wpisie w historii rozmowy")
	check(dl.base_disposition(dl.actor) == 60, "ModDisposition 10 (%d)" % dl.base_disposition(dl.actor))
	check("synth secret" in dl.available_topics(), "temat z odnośnika „@Synth Secret#” dodany")
	check((dl._ds().topics.get("synth lore", []) as Array).size() == 2, "dziennik tematów: dwie odpowiedzi")
	win.select_topic("synth secret")
	check(String(_last(dl).get("text", "")) == "To tajemnica gildii Synth Guild.", "filtr zmiennej lokalnej (helped == 1)")
	win.select_topic("synth lore")
	check(String(_last(dl).get("text", "")) == "Juz wszystko wiesz.", "filtr dziennika (synth_q >= 30) – pierwsza pasująca")
	# odmowa wg postawy
	dl.add_topic("Picky")
	win.refresh()
	win.select_topic("picky")
	check(String(_last(dl).get("text", "")) == "Nie mam ochoty z toba rozmawiac." and not dl._ds().topics.has("picky"),
			"za niska postawa → „Info Refusal” (bez wpisu w dzienniku tematów)")
	# perswazja (rzut 0 – sukces)
	var before: int = dl.derived_disposition(dl.actor)
	var pr: Dictionary = dl.persuade("admire", 0)
	check(bool(pr.get("success", false)) and dl.derived_disposition(dl.actor) > before and String(_last(dl).text) == "Milo to slyszec.",
			"perswazja: podziw udany, postawa rośnie (%s)" % [pr])
	var after: int = dl.derived_disposition(dl.actor)
	var r99: Dictionary = dl.persuasion_change("admire", 99)
	check(not bool(r99.success), "rzut 99 – podziw nieudany")
	check(win.close() and not win.visible and not get_root().get_tree().paused, "pożegnanie zamyka okno")
	check(dl.base_disposition(dl.make_actor(v)) == 60 + int(pr.perm), "pożegnanie: trwała zmiana postawy z perswazji (%d, perm %d)" % [dl.base_disposition(dl.make_actor(v)), int(pr.perm)])
	# ponowna rozmowa – drugie powitanie (%Name)
	check(main.open_dialogue(v) and String(dl.history[0].text) == "Znowu ty, Tester? Jestem Syntetyczny.", "drugie powitanie (TalkedToPc)")
	# Goodbye w skrypcie wyniku
	st.journal["synth_q"] = 0
	win.select_topic("synth lore")
	win._on_meta("choice:2")
	check(dl.goodbye_flag and not win.bye_btn.disabled and win.history_label.text.contains("[url=goodbye]"),
			"Goodbye: rozmowa zakończona, odnośnik pożegnania")
	win._on_meta("goodbye")
	check(not win.visible, "odnośnik pożegnania zamyka okno")
	# strażnik: frakcja, %Rank, %Faction, PCJoinFaction, %PCRank, filtr frakcji gracza
	var g := _ref(main, "synth_guard")
	check(g != null and main.open_dialogue(g) and String(dl.history[0].text) == "Strazniku Czeladnik z Gildia Testowa, czego chcesz?",
			"powitanie wg frakcji z %%Rank i %%Faction (%s)" % [dl.history[0] if not dl.history.is_empty() else {}])
	dl.add_topic("synth guild")
	win.refresh()
	win.select_topic("synth guild")
	check(dl.player_factions().has("synth guild") and int(dl.player_factions()["synth guild"].rank) == 0, "PCJoinFaction")
	win.select_topic("synth guild")
	check(String(_last(dl).text) == "Witaj w gildii, Nowicjusz.", "filtr frakcji gracza i %%PCRank (%s)" % [_last(dl)])
	check(dl.derived_disposition(dl.actor) == 50 + 0, "postawa: reakcja frakcji 0 – bez zmiany")
	win.close()
	# podstawienia i słowa kluczowe
	check(dl.fix_defines("%PCName: %SynthTicks%", {}, false).begins_with("Tester: ") and dl.fix_defines("100%", {}, false) == "100%",
			"podstawienia: zmienna globalna, pojedynczy %%")
	var kw := {}
	dl._seed(kw, "synth lore", "synth lore")
	dl._seed(kw, "synth", "synth")
	var m: Array = dl.parse_hypertext("O Synth Lorem i (synth) xsynth", kw)
	check(m.size() == 2 and m[0].id == "synth lore" and m[0].display == "Synth Lore" and m[1].id == "synth",
			"słowa kluczowe: najdłuższe wygrywa, początek słowa (%s)" % [m])
	# okno dziennika
	var jw = main.journal_window
	jw.open()
	check(jw.visible and jw.all_text.text.contains("Zadanie zakonczone"), "okno dziennika: wszystkie wpisy")
	check(jw._quests.is_empty(), "zakończone zadania ukryte domyślnie")
	jw.show_finished.button_pressed = true
	check(jw._quests.size() == 1 and String(jw._quests[0].name) == "Zadanie testowe", "zadanie z nazwą (QSTN) po włączeniu zakończonych")
	check(jw._topics.has("synth lore"), "dziennik tematów w oknie")
	jw.close()
	# zapis i odczyt
	var path := ProjectSettings.globalize_path("user://test_saves/dialogi.mwsave")
	check(main.save_game(path) == "", "zapis")
	var n_entries: int = dl._ds().entries.size()
	st.dialogue = {}
	main.player_stats()["factions"] = {}
	var w: Array = main.load_game(path)
	check(not str(w).contains("BŁĄD") and dl._ds().entries.size() == n_entries and dl._ds().known.has("synth secret")
			and dl.base_disposition(dl.make_actor(_ref(main, "synth_villager"))) != 50 and dl.player_factions().has("synth guild"),
			"odczyt: dziennik, znane tematy, postawa NPC, frakcje gracza")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "partial": dl.report().partial}))
	quit(1 if failures.size() > 0 else 0)
