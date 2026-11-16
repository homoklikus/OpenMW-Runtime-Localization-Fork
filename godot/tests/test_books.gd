extends SceneTree
## Etap 10 – książki i zwoje: parser znaczników Morrowinda (BR, P, DIV, FONT, IMG, tekst po ostatnim BR
## ukryty) i znaczników RLF, podział na strony w granicach linii, okno książki (rozkładówka, następna/poprzednia,
## „Weź” tylko dla książki w świecie), zwój jako jedna przewijana kolumna, podstawienia (%PCName), ilustracja
## z BookArt, umiejętność z książki raz (books_read w zapisie), czytanie z ekwipunku bez „Weź”.
## godot --headless --path godot -s res://tests/test_books.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

const Book := preload("res://scripts/mw/mw_book.gd")

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

func _parser_checks() -> void:
	var b := Book.new()
	b.format("<DIV ALIGN=\"CENTER\">Tytul<BR><BR><DIV ALIGN=\"LEFT\">Raz<BR>dwa<BR>ogon", 250, 328)
	var texts: Array = b.elements.filter(func(e): return e.kind == "text").map(func(e): return e.text)
	report["parser"] = texts
	check(texts.size() >= 2 and String(texts[0]).strip_edges() == "Tytul", "pierwszy blok: tytuł (%s)" % str(texts))
	check(b.elements[0].align == "left" or b.elements[0].align == "center", "wyrównanie z DIV")
	var all := "\n".join(texts)
	check(all.contains("Raz\ndwa") and not all.contains("ogon"), "BR = nowa linia, tekst po ostatnim BR ukryty")
	var c := Book.new()
	c.format("<FONT COLOR=\"FF0000\">czerwony<BR>[b]gruby[/b] zwykly<BR>", 250, 328)
	var red: Array = c.elements.filter(func(e): return e.kind == "text" and e.text.contains("czerwony"))
	check(not red.is_empty() and red[0].color.is_equal_approx(Color8(255, 0, 0)), "FONT COLOR")
	var bold: Array = c.elements.filter(func(e): return e.kind == "text" and e.text == "gruby")
	check(not bold.is_empty() and bold[0].bold, "[b] RLF – pogrubienie w osobnym bloku")
	# podział: 60 linii po ~16 px na stronie 328 px → kilka stron, granice w wielokrotnościach linii
	var long := ""
	for i in 60:
		long += "Linia %d<BR>" % i
	var d := Book.new()
	d.format(long + "x<BR>", 250, 328)
	report["pages"] = d.pages.size()
	check(d.pages.size() >= 3, "długi tekst – kilka stron (%d)" % d.pages.size())
	var ok := true
	for pg in d.pages:
		var off := fmod(float(pg[0]), d.line_h)
		if off > 0.01 and d.line_h - off > 0.01:
			ok = false
	check(ok, "strony zaczynają się na granicy linii")
	var e := Book.new()
	e.format("Strona A<BR>[pagebreak]\nStrona B<BR>", 250, 328)
	check(e.pages.size() == 2, "[pagebreak] RLF – nowa strona (%d)" % e.pages.size())

func _run() -> void:
	_parser_checks()
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	main.state.player["character"] = main.state.player.get("character", {})
	var bw = main.book_window
	check(bw != null, "okno książki")
	var book_node: Node = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == "synth_book":
				book_node = n
	check(book_node != null, "książka w świecie")
	var st: Dictionary = main.player_stats()
	var before := float(st.skills[8]) if not st.is_empty() else -1.0
	main.activate(book_node)
	await _frames(2)
	check(bw.visible and not bw.is_scroll, "aktywacja książki – okno książki (nie podniesienie)")
	check(bw._take.visible, "książka w świecie – przycisk „Weź”")
	check(get_root().get_tree().paused, "czytanie wstrzymuje grę")
	check(main.script_host.menu_mode(), "okno książki = tryb menu")
	var n_pages: int = bw.page_count()
	report["book_pages"] = n_pages
	check(n_pages >= 4, "książka na kilku stronach (%d)" % n_pages)
	check(bw.visible_text(0).contains("KSIEGA TESTOWA"), "pierwsza strona: tytuł")
	var all_text := "\n".join(bw.fmt.elements.filter(func(x): return x.kind == "text").map(func(x): return x.text))
	check(not all_text.contains("UKRYTY OGON"), "tekst po ostatnim BR niewidoczny")
	check(bw.fmt.elements.any(func(x): return x.kind == "img" and String(x.src).ends_with("bookart/synth_pic.png")), "ilustracja z BookArt")
	check(not bw._prev.visible and bw._next.visible, "pierwsza rozkładówka: tylko „Następna”")
	bw.next_page()
	check(bw.current == 1 and bw._prev.visible and bw._num[0].text == "3", "następna rozkładówka (strony 3–4)")
	var st2: Dictionary = main.player_stats()
	if before >= 0.0:
		check(float(st2.skills[8]) == before + 1.0, "umiejętność z książki +1 (%s → %s)" % [before, st2.skills[8]])
	bw.take()
	await _frames(3)
	check(not bw.visible and not get_root().get_tree().paused, "„Weź” zamyka okno")
	check(main.interaction.inventory.count_of("player", {}, "synth_book") == 1, "książka w ekwipunku po „Weź”")
	check(not is_instance_valid(book_node) or not book_node.is_inside_tree() or not book_node.visible, "książka zniknęła ze świata")
	# ponowne czytanie z ekwipunku – bez „Weź” i bez drugiego wzrostu umiejętności
	main.read_book("synth_book")
	await _frames(2)
	check(bw.visible and not bw._take.visible, "czytanie z ekwipunku – bez „Weź”")
	if before >= 0.0:
		check(float(main.player_stats().skills[8]) == before + 1.0, "umiejętność z tej samej książki tylko raz")
	check((main.state.player.get("books_read", {}) as Dictionary).has("synth_book"), "przeczytane książki w stanie gry (zapis)")
	bw.close()
	await _frames(2)
	# zwój
	main.interaction.inventory.add("player", {}, "synth_note", 1)
	main.read_book("synth_note")
	await _frames(2)
	check(bw.visible and bw.is_scroll and bw._scroll_view != null, "zwój – jedna przewijana kolumna")
	var nt: String = bw.visible_text()
	var pname := String(main.player_stats().get("name", ""))
	check(nt.contains("Notatka testowa") and not nt.contains("%PCName") and (pname.is_empty() or nt.contains(pname)), "podstawienie %%PCName (%s)" % nt.left(60))
	check(bw.fmt.elements.any(func(x): return x.kind == "text" and x.face == "daedric"), "FONT FACE=Daedric – czcionka daedryjska")
	bw.close()
	await _frames(2)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(1 if failures.size() > 0 else 0)
