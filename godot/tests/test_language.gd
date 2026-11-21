extends SceneTree
## Etap 10 – jeden język interfejsu: angielski (dane gry, GMST, l10n OpenMW; zapas po angielsku tylko przy braku klucza).
## Nie opiera się wyłącznie na znakach diakrytycznych:
## * źródło tekstu: GMST z danych ma pierwszeństwo przed zapasem w kodzie, l10n OMWEngine z en.yaml,
## * aktywny język: domyślnie „en” (l10n) i brak tłumaczenia danych gry przy game_language = en,
##   ustawienie języka przechodzi do l10n i warstwy tłumaczeń (pl → najpierw PL, potem EN),
## * zapasy: brak klucza w wybranym języku → en.yaml → zapas podany w kodzie,
## * kod: literały napisów w skryptach (poza diagnostyką: print/push_*/_err/_fail) bez polskich słów
##   i diakrytyków,
## * ekrany: ekwipunek, statystyki, magia, rozmowa, handel, trening, podróż, książka, odpoczynek, ustawienia,
##   zapis/wczytanie, menu główne, kreator – widoczne napisy bez polskich słów; podpowiedź celownika na aktorze
##   to sama nazwa (ToolTips), bez „Rozmawiaj”.
## godot --headless --path godot -s res://tests/test_language.gd -- --data=WYNIKI(aktorzy) --scripts=0

const L10N := preload("res://scripts/mw/mw_l10n.gd")
const LOC := preload("res://scripts/mw/mw_localization.gd")

## Częste polskie słowa interfejsu (bez diakrytyków też) – całe słowa, bez rozróżniania wielkości liter.
const PL_WORDS := ["zamknij", "wstecz", "dalej", "anuluj", "zapisz", "wczytaj", "tak", "nie", "brak", "rasa", "klasa",
	"znak", "zdrowie", "magia", "kondycja", "poziom", "waga", "wartosc", "zloto", "handel", "podroz", "trening",
	"oferta", "cena", "koszt", "szansa", "rozmawiaj", "wez", "wszystko", "inne", "bron", "ubior", "umiejetnosci",
	"postep", "dzien", "godz", "komorka", "wnetrze", "pozycja", "kierunek", "ekwipunek", "przedmioty", "frakcje",
	"reputacja", "grzywna", "pancerz", "czary", "moce", "zdolnosci", "wyglad", "imie", "odpocznij", "czekaj",
	"dzwiek", "grafika", "sterowanie", "glosnosc", "muzyka", "zaklecia", "perswazja", "dziennik", "przybysz",
	"specjalizacja", "atrybuty", "pytania", "opis", "wybierz", "zmien", "twarz", "wlosy", "plec", "specjalne"]

var failures: Array[String] = []
var checks := 0
var _re_word: RegEx
var _re_diac: RegEx

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_re_word = RegEx.create_from_string("[A-Za-zÀ-ž]+")
	_re_diac = RegEx.create_from_string("[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]")
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Polski tekst: diakrytyki albo polskie słowo z listy (po usunięciu diakrytyków).
func polish_words(t: String) -> Array:
	var out := []
	if _re_diac.search(t) != null:
		out.append("diakrytyki")
	for m in _re_word.search_all(t):
		var w := m.get_string().to_lower()
		for pair in [["ą", "a"], ["ć", "c"], ["ę", "e"], ["ł", "l"], ["ń", "n"], ["ó", "o"], ["ś", "s"], ["ź", "z"], ["ż", "z"]]:
			w = w.replace(pair[0], pair[1])
		if w in PL_WORDS:
			out.append(w)
	return out

func _texts(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	elif n is LineEdit:
		out.append((n as LineEdit).placeholder_text)
	elif n is ItemList:
		for i in (n as ItemList).item_count:
			out.append((n as ItemList).get_item_text(i))
	for c in n.get_children():
		_texts(c, out)

func _screen(main, name: String, ignore := []) -> void:
	var t := []
	_texts(main, t)
	var bad := []
	for s in t:
		if String(s) in ignore:
			continue
		var p := polish_words(String(s))
		if not p.is_empty():
			bad.append("%s %s" % [String(s).left(50), p])
	check(t.size() >= 3, "ekran „%s”: widoczne napisy (%d)" % [name, t.size()])
	check(bad.is_empty(), "ekran „%s” po angielsku (%s)" % [name, bad.slice(0, 5)])

## Literały w skryptach – bez napisów diagnostycznych i komentarzy.
func _test_sources() -> void:
	var lit := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var diag := RegEx.create_from_string("print|push_warning|push_error|printerr|_err\\(|_fail\\(|_missing\\(|errors\\.append|BŁĄD")
	var bad := []
	var scanned := 0
	for d in ["res://scripts/", "res://scripts/mw/"]:
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd"):
				continue
			var lines := FileAccess.get_file_as_string(d + f).split("\n")
			for i in lines.size():
				var l := lines[i]
				if l.strip_edges().begins_with("#"):
					continue
				var hash := l.find(" # ")
				if hash >= 0:
					l = l.left(hash)
				if diag.search(l) != null:
					continue
				for m in lit.search_all(l):
					scanned += 1
					var p := polish_words(m.get_string(1))
					if not p.is_empty():
						bad.append("%s:%d %s %s" % [f, i + 1, m.get_string(1).left(40), p])
	check(scanned > 1000, "przeskanowano literały skryptów (%d)" % scanned)
	check(bad.is_empty(), "literały interfejsu w kodzie bez polskiego (%d: %s)" % [bad.size(), bad.slice(0, 8)])

func _test_locale(main) -> void:
	# l10n OpenMW: domyślny język en, zapasy en.yaml → kod
	check(L10N.locales.size() >= 1 and L10N.locales[0] == "en", "aktywny język l10n: en (%s)" % [L10N.locales])
	var en_yaml: Dictionary = L10N._load("OMWEngine", "en")
	check(L10N.text("SaveGameDenied") == String(en_yaml.get("SaveGameDenied", "")) and not String(en_yaml.get("SaveGameDenied", "")).is_empty(),
		"tekst z l10n OMWEngine/en.yaml")
	check(L10N.text("NoSuchKeyForTest", "Fallback text") == "Fallback text", "brak klucza – zapas z kodu")
	var prev := L10N.locales
	L10N.set_locales("pl")
	check(L10N.locales == PackedStringArray(["pl", "en"]), "ustawienie pl → [pl, en] (%s)" % [L10N.locales])
	var pl_yaml: Dictionary = L10N._load("OMWEngine", "pl")
	if pl_yaml.has("SaveGameDenied"):
		check(L10N.text("SaveGameDenied") == String(pl_yaml.SaveGameDenied), "pl: tekst z pl.yaml (infrastruktura wielojęzyczna zachowana)")
	check(L10N.text("NoSuchKeyForTest", "Fallback text") == "Fallback text", "pl: brak klucza – zapas")
	L10N.locales = prev
	# warstwa tłumaczeń danych gry: game_language = en → EN; auto + język launchera → ten język
	var l_en = LOC.create(main.db.data_root, [], "en", "pl")
	check(l_en.languages == PackedStringArray(["EN"]), "game_language = en → EN (%s)" % [l_en.languages])
	var l_auto = LOC.create(main.db.data_root, [], "auto", "pl")
	check(l_auto.languages == PackedStringArray(["PL"]), "auto przejmuje język launchera (%s)" % [l_auto.languages])
	var l_orig = LOC.create(main.db.data_root, [], "original", "pl")
	check(l_orig.languages.is_empty(), "original – teksty z danych bez tłumaczenia")
	# GMST z danych ma pierwszeństwo przed zapasem z kodu
	var recs = main.builder.actors
	recs.record("gmst", "")
	var store: Dictionary = recs._records["gmst"]
	var had := store.has("sclose")
	var old = store.get("sclose")
	store["sclose"] = {"value": "Close From Data"}
	check(main.dialogue.gmst_text("sClose", "Close") == "Close From Data", "GMST z danych przed zapasem")
	if had:
		store["sclose"] = old
	else:
		store.erase("sclose")
	check(main.dialogue.gmst_text("sClose", "Close") == (String(old.value) if had else "Close"), "brak GMST – zapas angielski")

func _run() -> void:
	_test_sources()
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	_test_locale(main)
	var g = main.gui
	# podpowiedź celownika na aktorze: sama nazwa
	var v: Node3D = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == "synth_trader":
				v = n
	if v != null:
		var nm: String = main.dialogue.actor_name(main.dialogue.make_actor(v))
		var cam: Camera3D = main.player.get_node_or_null("Camera3D")
		if cam != null:
			main.player.global_position = v.global_position + Vector3(0, 0, 1.2)
			main.player.rotation.y = 0.0
			cam.rotation.x = -0.3
			await _frames(4)
			var h: String = main.focus_text()
			check(h.is_empty() or h == nm, "podpowiedź na aktorze = nazwa (%s / %s)" % [h, nm])
	# ekwipunek, statystyki, magia
	main.menu_mode.open()
	await _frames(3)
	_screen(main, "ekwipunek/statystyki/magia")
	g.exit_current()
	await _frames(2)
	# rozmowa i usługi
	if v != null and main.open_dialogue(v):
		await _frames(3)
		_screen(main, "rozmowa")
		for svc in ["barter", "training", "travel", "spells"]:
			main.trade_window.open(svc)
			await _frames(3)
			_screen(main, svc)
			g.exit_current()
			await _frames(2)
		main.dialogue_window.close()
		await _frames(2)
	# książka
	main.book_window.open("synth_book", main.builder.actors.record("book", "synth_book"), true)
	await _frames(3)
	_screen(main, "książka")
	main.book_window.close()
	# odpoczynek
	if main.rest_window.open():
		await _frames(3)
		_screen(main, "odpoczynek")
		main.rest_window.close()
	# ustawienia, zapis, wczytanie, menu główne
	main.open_settings()
	await _frames(3)
	_screen(main, "ustawienia")
	main.settings_window.close()
	await _frames(2)
	main.main_menu.open()
	await _frames(3)
	_screen(main, "menu główne")
	main.save_dialog.open(false)
	await _frames(3)
	_screen(main, "zapis gry")
	main.save_dialog.close()
	main.save_dialog.open(true)
	await _frames(3)
	_screen(main, "wczytanie gry")
	main.save_dialog.close()
	main.main_menu.close()
	await _frames(2)
	_test_gmst_locale(main)
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)

## Język „gmst” (OpenMW vfs-mw/l10n/*/gmst.yaml, l10n::Manager, MessageBundles): przy gmst overrides l10n = true
## teksty silnika pochodzą z GMST danych gry (Options = sOptions, OK = sOK, Prefs = sPrefs), wzorce {gmst:…}
## z podstawieniami printf → {zmienna}, formy plural; brak GMST → kolejny język; przy false – najpierw l10n.
func _test_gmst_locale(main) -> void:
	var L10n = load("res://scripts/mw/mw_l10n.gd")
	var keep_lookup: Callable = L10n.gmst_lookup
	var keep_first: bool = L10n.gmst_first
	var fake := {"sOptions": "Options Menu", "sOK": "Okay", "sDifficulty": "Hardness", "sNotifyMessage39": "Your %s skill increased to %d.",
		"sNotifyMessage42": "Out after %d day.", "sNotifyMessage43": "Out after %d days.", "sLoadLastSaveMsg": "Load '%s'?"}
	L10n.gmst_lookup = func(id: String) -> String: return String(fake.get(id, ""))
	L10n.gmst_first = true
	check(L10n.text("SettingsWindow") == "Options Menu", "gmst: SettingsWindow = sOptions (%s)" % L10n.text("SettingsWindow"))
	check(L10n.ctx_text("Interface", "OK") == "Okay", "gmst: Interface OK = sOK")
	check(L10n.text("DifficultyValue", "", {"value": 5}) == "Hardness (5)", "gmst: wzorzec {gmst:sDifficulty} ({value}) (%s)" % L10n.text("DifficultyValue", "", {"value": 5}))
	check(L10n.ctx_text("Mechanics", "SkillIncreasedTo", "", {"skill": "Block", "level": 7}) == "Your Block skill increased to 7.",
		"gmst: printf → {skill}/{level} (%s)" % L10n.ctx_text("Mechanics", "SkillIncreasedTo", "", {"skill": "Block", "level": 7}))
	check(L10n.ctx_text("Mechanics", "ReleasedFromPrison", "", {"days": 1}) == "Out after 1 day."
		and L10n.ctx_text("Mechanics", "ReleasedFromPrison", "", {"days": 3}) == "Out after 3 days.", "gmst: plural one/other")
	check(L10n.text("Audio") == "Audio", "gmst: brak sAudio – tekst z en.yaml (%s)" % L10n.text("Audio"))
	L10n.gmst_first = false
	check(L10n.text("SettingsWindow") == "Options", "gmst overrides l10n = false: najpierw en.yaml (%s)" % L10n.text("SettingsWindow"))
	L10n.gmst_lookup = keep_lookup
	L10n.gmst_first = keep_first
	# w grze: wyszukiwanie w GMST danych (z warstwą tłumaczeń)
	if main.dialogue != null and not String(main.dialogue.gmst_text("sOK", "")).is_empty():
		check(L10n.ctx_text("Interface", "OK") == main.dialogue.gmst_text("sOK", ""), "gmst: OK z GMST danych gry")
