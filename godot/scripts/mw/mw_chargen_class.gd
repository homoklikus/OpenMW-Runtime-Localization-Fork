extends Node
## Okna klasy postaci jak OpenMW (apps/openmw/mwgui/class.cpp, charactercreation.cpp):
##  - ClassChoiceDialog (InfoBoxDialog, openmw_infobox.layout): „odpowiedz na pytania”, „wybierz z listy”,
##    „utwórz własną”, „wstecz” (→ rasa);
##  - pytania (GM_ClassGenerate): 10 pytań z Morrowind.ini/openmw.cfg (Question_N_Question / AnswerOne/Two/Three
##    – walka, magia, skradanie; kolejność odpowiedzi losowana jedną z 6 permutacji; głos „vo\misc\chargen qaN.wav”),
##    wynik według tabeli showClassQuestionDialog w GenerateClassResultDialog (obraz klasy, Wybierz inną / Przyjmij);
##  - PickClassDialog (openmw_chargen_class.layout): lista grywalnych klas (bez własnych, według nazwy), obraz
##    textures/levelup/<id> (brak – warrior), specjalizacja, ulubione atrybuty, umiejętności główne i drugorzędne;
##  - CreateClassDialog (openmw_chargen_create_class.layout) z oknami SelectSpecialization / SelectAttribute /
##    SelectSkill (openmw_chargen_select_*.layout) i DescriptionDialog: nazwa (domyślnie sCustomClassName),
##    specjalizacja, 2 ulubione atrybuty, 5 + 5 umiejętności bez powtórzeń (wybór istniejącej zamienia pola jak
##    onSkillSelected/onAttributeSelected), opis; okno pamięta wybory do końca tworzenia postaci (OpenMW go nie
##    usuwa). Domyślnie: Siła, Zręczność; Blok, Płatnerstwo, Średni pancerz, Ciężki pancerz, Broń obuchowa /
##    Długie ostrza, Topory, Włócznie, Atletyka, Zaklinanie; Walka. Rekord klasy – rekord utworzony w grze
##    (records.dynamic["class"]["mwg_class_player"] → zapis gry), jak setPlayerClass z klasą dynamiczną.

const CUSTOM_ID := "mwg_class_player"
const UI := preload("res://scripts/mw/mw_ui.gd")
const CUI := preload("res://scripts/mw/mw_chargen_ui.gd")
# kolejność: getAttributeId/indexToRefId (Siła … Szczęście), umiejętności według indeksów ESM
const DEFAULT_ATTRS := [0, 3]
const DEFAULT_MAJOR := [0, 1, 2, 3, 4]
const DEFAULT_MINOR := [5, 6, 7, 8, 9]

var cg = null                          # kontroler tworzenia postaci (mw_chargen_window.gd)
var fallbacks := {}
var rng := RandomNumberGenerator.new()
var _fallbacks_root := ""
# pytania
var step := -1                         # pytanie 0..9; 10 = wynik
var counts := [0, 0, 0]                # walka, magia, skradanie
var result_class := ""
var _answers: Array = []               # specjalizacje przycisków bieżącego pytania (kolejność wyświetlania)
var answer_buttons: Array = []
var question_text := ""
# wybór sposobu
var choice_buttons: Array = []
# lista klas
var class_list: ItemList = null
var classes: Array = []
var pick_id := ""
var class_image: TextureRect = null
var _pick_widgets := {}
# własna klasa (pamiętana jak CreateClassDialog)
var create_state := {}
var c_name: LineEdit = null
var spec_button: Button = null
var attr_buttons: Array = []
var major_buttons: Array = []
var minor_buttons: Array = []
var sub: Control = null                # okno podrzędne (wybór specjalizacji/atrybutu/umiejętności, opis)
var sub_kind := ""
var _affected := -1                    # pole zmieniane przez okno wyboru (atrybut 0..1, umiejętność 0..9)
var desc_edit: TextEdit = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()

var ui:
	get:
		return cg.ui

func _t(gm: String, def: String) -> String:
	return ui.t(gm, def)

func _records():
	return cg.character.records

## Nowa postać: okno własnej klasy zaczyna od wartości domyślnych.
func reset() -> void:
	create_state = {}
	step = -1
	result_class = ""

func close_all() -> void:
	_close_sub()
	choice_buttons = []
	answer_buttons = []
	class_list = null
	class_image = null
	c_name = null
	spec_button = null
	attr_buttons = []
	major_buttons = []
	minor_buttons = []

func _close_sub() -> void:
	if sub != null:
		CUI.close(sub)
	sub = null
	sub_kind = ""
	desc_edit = null

# --- teksty pytań ------------------------------------------------------------------------------------------

func load_fallbacks(data_root: String) -> void:
	if data_root == _fallbacks_root and not fallbacks.is_empty():
		return
	_fallbacks_root = data_root
	var f := FileAccess.open(data_root.path_join("world/fallbacks.json"), FileAccess.READ)
	if f != null:
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			fallbacks = j.get("values", {})

func _ensure_fallbacks() -> void:
	if cg != null and cg.main != null and cg.main.get("db") != null and cg.main.db != null:
		load_fallbacks(cg.main.db.data_root)

## Tekst pytania: tłumaczenie z lokalizacji (sekcja „Question N”), inaczej wartość z instalacji.
func q_text(n: int, key: String) -> String:
	var base := String(fallbacks.get("Question_%d_%s" % [n, key], ""))
	var loc = cg.loc if cg != null else null
	if loc != null and loc.has_method("fallback_value"):
		return loc.fallback_value("Question %d" % n, key, base)
	return base

func questions_available() -> bool:
	_ensure_fallbacks()
	for n in range(1, 11):
		if q_text(n, "Question").is_empty():
			return false
	return true

# --- InfoBoxDialog (openmw_infobox.layout) -----------------------------------------------------------------

## Okno z tekstem (zawijanym do 508 px) i przyciskami jeden pod drugim (zawijanymi do 450 px), wyśrodkowane;
## layoutVertically: tekst – margines 4, przyciski – 6, okno – 10 (wysokość okna = 10 + tekst + 10 + przyciski + 10);
## fitToText przycisku MW_Button: napis + 8 × 8 (obszar tekstu skórki 4 px od krawędzi) – porównane ze zrzutem
## ClassChoiceDialog OpenMW (720p: ramka 454…823 × 287…431).
func _info_box(text: String, labels: Array, cb: Callable) -> Array:
	var buttons := []
	var widths := []
	var heights := []
	var maxw := 0.0
	for lab in labels:
		var tw: float = minf(ui.text_width(String(lab)) / ui.sc, 444.0)
		var th: float = ui.wrapped_height(String(lab), 444.0) if ui.text_width(String(lab)) / ui.sc > 444.0 else 16.0
		widths.append(tw + 8.0)
		heights.append(maxf(16.0, th) + 8.0)
		maxw = maxf(maxw, tw + 8.0)
	var bar_h := 6.0
	for h in heights:
		bar_h += h + 6.0
	var text_h := 0.0
	if not text.is_empty():
		text_h = 4.0 + maxf(18.0, ui.wrapped_height(text, 508.0)) + 4.0
	var w := maxf(maxw + 32.0, 532.0 if not text.is_empty() else 0.0)
	var h := (text_h + 10.0 if text_h > 0.0 else 0.0) + bar_h + 20.0
	var win: Control = ui.modal(cg, w, h)
	cg.win = win
	var c: Control = win.get_meta("client")
	var y := 10.0
	if text_h > 0.0:
		var l: Label = ui.wrap_label(c, (w - 8.0 - 508.0) / 2.0, y + 4.0, 508.0, text)
		l.name = "Text"
		y += text_h + 10.0
	y += 6.0
	for i in labels.size():
		var wraps: bool = heights[i] > 24.0
		var b: Button = ui.button("" if wraps else String(labels[i]), cb.bind(i))
		if wraps:
			# tekst zawinięty (MW_Button z WordWrap): etykieta wewnątrz przycisku, kolory stanów jak SandTextButton
			var wl := Label.new()
			wl.text = String(labels[i])
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wl.set_anchors_preset(Control.PRESET_FULL_RECT)
			wl.add_theme_color_override("font_color", UI.color("normal"))
			wl.add_theme_constant_override("line_spacing", 0)
			b.add_child(wl)
			b.mouse_entered.connect(func(): wl.add_theme_color_override("font_color", UI.color("normal_over")))
			b.mouse_exited.connect(func(): wl.add_theme_color_override("font_color", UI.color("normal")))
			b.set_meta("label", wl)
		b.size = Vector2(widths[i], heights[i]) * ui.sc
		b.position = Vector2(floorf(((w - 8.0) - widths[i]) / 2.0), y) * ui.sc
		c.add_child(b)
		buttons.append(b)
		y += heights[i] + 6.0
	return buttons

# --- ClassChoiceDialog ---------------------------------------------------------------------------------------

var _choice_map: Array = []            # przycisk → sposób (0 pytania, 1 lista, 2 własna, 3 wstecz)

## Bez tekstów pytań w danych gracza (brak [Question N] w Morrowind.ini/openmw.cfg) opcja pytań jest pomijana –
## OpenMW ma je zawsze (wartości domyślne openmw.cfg), a teksty gry nie mogą trafić do repozytorium.
func spawn_choice() -> void:
	_ensure_fallbacks()
	var labels := []
	_choice_map = []
	if questions_available():
		labels.append(_t("sClassChoiceMenu1", "Answer questions (a class is chosen for you)"))
		_choice_map.append(0)
	labels.append(_t("sClassChoiceMenu2", "Pick from a list of classes"))
	_choice_map.append(1)
	labels.append(_t("sClassChoiceMenu3", "Create your own class"))
	_choice_map.append(2)
	labels.append(_t("sBack", "Back"))
	_choice_map.append(3)
	choice_buttons = _info_box("", labels, _choice_button)

func _choice_button(i: int) -> void:
	choice_selected(int(_choice_map[i]) if i >= 0 and i < _choice_map.size() else 3)

## onClassChoice: 0 – pytania, 1 – lista, 2 – własna, 3 – wstecz (rasa).
func choice_selected(i: int) -> void:
	if i == 0 and not questions_available():
		return
	cg._pop()
	match i:
		0: cg._push("class_generate")
		1: cg._push("class_pick")
		2: cg._push("class_create")
		3: cg._push("race")

# --- pytania (GM_ClassGenerate) ------------------------------------------------------------------------------

func spawn_generate() -> void:
	step = 0
	counts = [0, 0, 0]
	result_class = ""
	_show_question()

## Zgodność ze starszymi testami: rozpoczęcie pytań z bieżącego okna.
func start_questions() -> void:
	cg._pop()
	cg._push("class_generate")

func _show_question() -> void:
	if step == 10:
		_show_result()
		return
	if step > 10:
		cg._pop()
		cg._push("class")
		return
	if cg.win != null:
		CUI.close(cg.win)
		cg.win = null
	var n := step + 1
	question_text = q_text(n, "Question")
	var answers := [[q_text(n, "AnswerOne"), 0], [q_text(n, "AnswerTwo"), 1], [q_text(n, "AnswerThree"), 2]]
	# sGenerateClassSteps: rollDice(6) – jedna z 6 kolejności odpowiedzi
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	var p: Array = perms[rng.randi_range(0, 5)]
	_answers = []
	var labels := []
	for k in p:
		labels.append(String(answers[k][0]))
		_answers.append(int(answers[k][1]))
	answer_buttons = _info_box(question_text, labels, answer)
	if cg.main != null and cg.main.get("audio") != null and cg.main.audio != null:
		cg.main.audio.say("player", "vo\\misc\\chargen qa%d.wav" % n)

## onClassQuestionChosen (indeks przycisku w kolejności wyświetlenia); poza 0..2 – powrót do wyboru sposobu.
func answer(i: int) -> void:
	if step < 0 or step >= 10:
		return
	if cg.main != null and cg.main.get("audio") != null and cg.main.audio != null:
		cg.main.audio.stop_say("player")
	if i < 0 or i >= 3:
		cg._pop()
		cg._push("class")
		return
	counts[int(_answers[i])] += 1
	step += 1
	_show_question()

## Tabela CharacterCreation::showClassQuestionDialog (liczba odpowiedzi walka/magia/skradanie → klasa).
static func class_for(combat: int, magic: int, stealth: int) -> String:
	if combat > 7:
		return "Warrior"
	if magic > 7:
		return "Mage"
	if stealth > 7:
		return "Thief"
	match combat:
		4: return "Rogue"
		5: return "Scout" if stealth == 3 else "Archer"
		6:
			if stealth == 1:
				return "Barbarian"
			return "Crusader" if stealth == 3 else "Knight"
		7: return "Warrior"
	match magic:
		4: return "Spellsword"
		5: return "Witchhunter"
		6:
			if combat == 2:
				return "Sorcerer"
			return "Healer" if combat == 3 else "Battlemage"
		7: return "Mage"
	match stealth:
		3: return "Bard" if magic == 3 else "Warrior"
		5: return "Monk" if magic == 3 else "Pilgrim"
		6:
			if magic == 1:
				return "Agent"
			return "Assassin" if magic == 3 else "Acrobat"
		7: return "Thief"
	return "Warrior"

## setClassImage: textures/levelup/<id>, brak – warrior.
func class_texture(id: String) -> Texture2D:
	var t := UI.texture("textures/levelup/" + id.to_lower())
	if t == null:
		t = UI.texture("textures/levelup/warrior")
	return t

## GenerateClassResultDialog (openmw_chargen_generate_class_result.layout, VBox z marginesem 8 i odstępem 8).
func _show_result() -> void:
	step = 10
	result_class = class_for(counts[0], counts[1], counts[2]).to_lower()
	if cg.win != null:
		CUI.close(cg.win)
		cg.win = null
	var reflect := _t("sMessageQuestionAnswer1", "Your personality and past fit the class:")
	var rh: float = maxf(18.0, ui.wrapped_height(reflect, 265.0))
	var back_b: Button = ui.button(_t("sMessageQuestionAnswer3", "Choose another class"), func(): generate_back())
	var ok_b: Button = ui.button(_t("sMessageQuestionAnswer2", "Accept this class"), func(): generate_ok())
	back_b.name = "BackButton"
	ok_b.name = "OKButton"
	var row_w: float = (back_b.size.x + ok_b.size.x) / ui.sc + 4.0
	var inner_w := maxf(265.0, row_w)
	var w := inner_w + 16.0 + 8.0
	var h := 8.0 + 138.0 + 8.0 + rh + 8.0 + 18.0 + 8.0 + 24.0 + 8.0 + 8.0
	var win: Control = ui.modal(cg, w, h)
	cg.win = win
	var c: Control = win.get_meta("client")
	var x0 := (w - 8.0 - 265.0) / 2.0
	class_image = ui.image_box(c, x0, 8, 265, 138)
	class_image.name = "ClassImage"
	class_image.texture = class_texture(result_class)
	var y := 8.0 + 138.0 + 8.0
	var rl: Label = ui.wrap_label(c, x0, y, 265, reflect, "sand", HORIZONTAL_ALIGNMENT_CENTER)
	rl.name = "ReflectT"
	y += rh + 8.0
	var nl: Label = ui.label(c, x0, y, 265, 18, ui.rec_name("class", "CLAS", result_class), "sand", HORIZONTAL_ALIGNMENT_CENTER)
	nl.name = "ClassName"
	y += 18.0 + 8.0
	ui.button_row(c, (w - 8.0 - row_w) / 2.0, y, row_w, 24, [back_b, ok_b], false)

func _select_generated() -> void:
	if not result_class.is_empty():
		cg.apply("class", {"class": result_class})

func generate_ok() -> bool:
	if step != 10:
		return false
	_select_generated()
	cg.handle_done(cg.CSE_CLASS, "birth")
	return true

func generate_back() -> void:
	if step == 10:
		_select_generated()
	cg._pop()
	cg._push("class")

## Zgodność ze starszymi testami.
func accept_result() -> void:
	generate_ok()

# --- PickClassDialog (491 × 316) ----------------------------------------------------------------------------

func _class_ids() -> Array:
	var out: Array = cg.character.playable("class").filter(func(c): return c != CUSTOM_ID)
	out.sort_custom(func(a, b): return ui.rec_name("class", "CLAS", a).naturalnocasecmp_to(ui.rec_name("class", "CLAS", b)) < 0)
	return out

func spawn_pick() -> void:
	var win: Control = ui.modal(cg, 491, 316)
	cg.win = win
	var c: Control = win.get_meta("client")
	class_list = ui.list(c, 8, 8, 194, 138)
	class_list.name = "ClassList"
	classes = _class_ids()
	for id in classes:
		class_list.add_item(ui.rec_name("class", "CLAS", id))
	class_list.item_selected.connect(_on_class_selected)
	class_list.item_activated.connect(func(i): _on_class_selected(i); pick_ok())
	class_image = ui.image_box(c, 210, 8, 265, 138)
	class_image.name = "ClassImage"
	var g = ui.group(c, 8, 156, 484, 178)
	var sh: Label = ui.label(g, 0, 0, 166, 18, _t("sChooseClassMenu1", "Specialization:"), "header")
	sh.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_pick_widgets = {}
	_pick_widgets["spec"] = ui.label(g, 0, 18, 166, 18, "")
	var fh := _t("sChooseClassMenu2", "Favorite Attributes:")
	var fhh: float = maxf(18.0, ui.wrapped_height(fh, 166.0))
	var fl: Label = ui.wrap_label(g, 0, 39, 166, fh, "header")
	fl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_pick_widgets["attr"] = [ui.label(g, 0, 39 + fhh, 166, 18, ""), ui.label(g, 0, 39 + fhh + 18, 166, 18, "")]
	var mh: Label = ui.label(g, 166, 0, 162, 18, _t("sChooseClassMenu3", "Major Skills:"), "header")
	mh.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var nh: Label = ui.label(g, 332, 0, 166, 18, _t("sChooseClassMenu4", "Minor Skills:"), "header")
	nh.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_pick_widgets["major"] = []
	_pick_widgets["minor"] = []
	for i in 5:
		_pick_widgets["major"].append(ui.label(g, 166, 18 + 18 * i, 166, 18, ""))
		_pick_widgets["minor"].append(ui.label(g, 332, 18 + 18 * i, 166, 18, ""))
	var back_b: Button = ui.button(_t("sBack", "Back"), func(): pick_back())
	back_b.name = "BackButton"
	var ok_b: Button = ui.button(_t("sNext", "Next") if cg.next_shown(cg.CSE_CLASS) else _t("sOK", "OK"), func(): pick_ok())
	ok_b.name = "OKButton"
	ui.button_row(c, 0, 276, 475, 28, [back_b, ok_b])
	# setClassId(klasa gracza); updateClasses: bez klasy – pierwsza z listy
	pick_id = ""
	var want := String(cg.cur.get("class", "")).to_lower()
	var idx := classes.find(want)
	if idx < 0 and not classes.is_empty():
		idx = 0
	if idx >= 0:
		class_list.select(idx)
		class_list.ensure_current_is_visible()
		pick_id = classes[idx]
	_update_pick_stats()
	class_list.grab_focus.call_deferred()

func _on_class_selected(i: int) -> void:
	if i < 0 or i >= classes.size():
		return
	if String(classes[i]) == pick_id:
		return
	pick_id = classes[i]
	_update_pick_stats()

func _update_pick_stats() -> void:
	if pick_id.is_empty():
		return
	var cls: Dictionary = _records().record("class", pick_id)
	_pick_widgets["spec"].text = ui.spec_name(int(cls.get("specialization", 0)))
	var attrs: Array = cls.get("attributes", [])
	for i in 2:
		(_pick_widgets["attr"][i] as Label).text = ui.attr_name(int(attrs[i])) if i < attrs.size() else ""
	var maj: Array = cls.get("major_skills", [])
	var mnr: Array = cls.get("minor_skills", [])
	for i in 5:
		(_pick_widgets["major"][i] as Label).text = ui.skill_name(int(maj[i])) if i < maj.size() else ""
		(_pick_widgets["minor"][i] as Label).text = ui.skill_name(int(mnr[i])) if i < mnr.size() else ""
	if class_image != null:
		class_image.texture = class_texture(pick_id)

## Wybór klasy na liście (testy).
func choose_class(id: String) -> bool:
	if class_list == null:
		return false
	var i := classes.find(id.to_lower())
	if i < 0:
		return false
	class_list.select(i)
	_on_class_selected(i)
	return true

func _select_picked() -> void:
	if not pick_id.is_empty():
		cg.apply("class", {"class": pick_id})

func pick_ok() -> bool:
	if class_list == null or class_list.get_selected_items().is_empty():
		return false
	_select_picked()
	cg.handle_done(cg.CSE_CLASS, "birth")
	return true

func pick_back() -> void:
	_select_picked()
	cg._pop()
	cg._push("class")

# --- CreateClassDialog (498 × 198) --------------------------------------------------------------------------

func _default_state() -> Dictionary:
	return {"name": _t("sCustomClassName", "Adventurer"), "description": "", "specialization": 0,
		"attributes": DEFAULT_ATTRS.duplicate(), "major_skills": DEFAULT_MAJOR.duplicate(),
		"minor_skills": DEFAULT_MINOR.duplicate()}

func spawn_create() -> void:
	if create_state.is_empty():
		create_state = _default_state()
	var win: Control = ui.modal(cg, 498, 198)
	cg.win = win
	var c: Control = win.get_meta("client")
	var lt: Label = ui.label(c, 8, 8, 52, 23, _t("sName", "Name"), "header")
	lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c_name = LineEdit.new()
	c_name.name = "EditName"
	c_name.text = String(create_state.name)
	c_name.add_theme_stylebox_override("normal", UI.inner_box(Color(0, 0, 0, 0)))
	c_name.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	c_name.text_changed.connect(func(t): create_state["name"] = t)
	ui.at(c_name, c, 72, 8, 410, 23)
	var g = ui.group(c, 8, 38, 480, 116)
	var sh: Label = ui.label(g, 0, 0, 156, 18, _t("sChooseClassMenu1", "Specialization:"), "header")
	sh.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	spec_button = ui.text_button(g, 0, 18, 166, 18, "", func(): _open_select_spec())
	spec_button.name = "SpecializationName"
	var fh := _t("sChooseClassMenu2", "Favorite Attributes:")
	var fhh: float = maxf(18.0, ui.wrapped_height(fh, 166.0))
	var fl: Label = ui.wrap_label(g, 0, 41, 166, fh, "header")
	fl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	attr_buttons = []
	for i in 2:
		attr_buttons.append(ui.text_button(g, 0, 41 + fhh + 18 * i, 166, 18, "", _open_select_attr.bind(i)))
	# CreateClassDialog: nagłówki sSkillClassMajor / sSkillClassMinor (inaczej niż PickClassDialog)
	var mh: Label = ui.label(g, 166, 0, 166, 18, _t("sSkillClassMajor", "Major Skills"), "header")
	mh.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var nh: Label = ui.label(g, 332, 0, 166, 18, _t("sSkillClassMinor", "Minor Skills"), "header")
	nh.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	major_buttons = []
	minor_buttons = []
	for i in 5:
		major_buttons.append(ui.text_button(g, 166, 18 + 18 * i, 166, 18, "", _open_select_skill.bind(i)))
		minor_buttons.append(ui.text_button(g, 332, 18 + 18 * i, 166, 18, "", _open_select_skill.bind(5 + i)))
	var desc_b: Button = ui.button(_t("sCreateClassMenu1", "Description"), func(): _open_description())
	desc_b.name = "DescriptionButton"
	var back_b: Button = ui.button(_t("sBack", "Back"), func(): create_back())
	back_b.name = "BackButton"
	var ok_b: Button = ui.button(_t("sNext", "Next") if cg.next_shown(cg.CSE_CLASS) else _t("sOK", "OK"), func(): create_ok())
	ok_b.name = "OKButton"
	ui.button_row(c, 0, 158, 482, 28, [desc_b, back_b, ok_b])
	_refresh_create()
	c_name.grab_focus.call_deferred()

func _refresh_create() -> void:
	if spec_button == null:
		return
	spec_button.text = ui.spec_name(int(create_state.specialization))
	for i in 2:
		(attr_buttons[i] as Button).text = ui.attr_name(int(create_state.attributes[i]))
	for i in 5:
		(major_buttons[i] as Button).text = ui.skill_name(int(create_state.major_skills[i]))
		(minor_buttons[i] as Button).text = ui.skill_name(int(create_state.minor_skills[i]))

func custom_record() -> Dictionary:
	return {"id": CUSTOM_ID, "name": String(create_state.get("name", "")).strip_edges(),
		"description": String(create_state.get("description", "")),
		"specialization": int(create_state.get("specialization", 0)),
		"attributes": (create_state.get("attributes", []) as Array).duplicate(),
		"major_skills": (create_state.get("major_skills", []) as Array).duplicate(),
		"minor_skills": (create_state.get("minor_skills", []) as Array).duplicate(),
		"playable": true, "services": 0}

## selectCreatedClass: rekord klasy gracza (dynamiczny) i setPlayerClass; okno pamięta wybory.
func _select_created() -> void:
	var rec := custom_record()
	var dyn: Dictionary = _records().dynamic
	if not dyn.has("class"):
		dyn["class"] = {}
	dyn["class"][CUSTOM_ID] = rec
	cg.apply("class", {"class": CUSTOM_ID})

## onOkClicked: bez nazwy nic się nie dzieje.
func create_ok() -> bool:
	if String(create_state.get("name", "")).strip_edges().is_empty():
		return false
	_select_created()
	cg.handle_done(cg.CSE_CLASS, "birth")
	return true

## Zgodność ze starszymi testami.
func accept_custom() -> bool:
	return create_ok()

func create_back() -> void:
	# „not done in MW, but we do it for consistency with the other dialogs”
	_select_created()
	cg._pop()
	cg._push("class")

## Zgodność ze starszymi testami: otwarcie okna własnej klasy.
func start_custom() -> void:
	cg._pop()
	cg._push("class_create")

## onAttributeSelected: ten sam atrybut w drugim polu – zamiana.
func set_attribute(slot: int, attr: int) -> void:
	var a: Array = create_state.attributes
	var other := 1 - slot
	if int(a[other]) == attr:
		a[other] = a[slot]
	a[slot] = attr
	_refresh_create()

## onSkillSelected: umiejętność wybrana już w innym polu – tamto pole dostaje poprzednią wartość tego pola.
func set_skill(slot: int, skill: int) -> void:
	var maj: Array = create_state.major_skills
	var mnr: Array = create_state.minor_skills
	var cur_v: int = int(maj[slot]) if slot < 5 else int(mnr[slot - 5])
	for k in 10:
		if k == slot:
			continue
		var v: int = int(maj[k]) if k < 5 else int(mnr[k - 5])
		if v == skill:
			if k < 5:
				maj[k] = cur_v
			else:
				mnr[k - 5] = cur_v
			break
	if slot < 5:
		maj[slot] = skill
	else:
		mnr[slot - 5] = skill
	_refresh_create()

func set_specialization(s: int) -> void:
	create_state["specialization"] = s
	_refresh_create()

func _pick_spec(i: int) -> void:
	set_specialization(i)
	_close_sub()

func _pick_attr(slot: int, i: int) -> void:
	set_attribute(slot, i)
	_close_sub()

func _pick_skill(slot: int, k: int) -> void:
	set_skill(slot, k)
	_close_sub()

func _description_ok() -> void:
	if desc_edit != null:
		create_state["description"] = desc_edit.text
	_close_sub()

# okna wyboru (MW_DialogNoTransp)
func _sub_modal(w: float, h: float, kind: String) -> Control:
	_close_sub()
	sub = ui.modal(cg, w, h, true)
	sub_kind = kind
	return sub.get_meta("client")

func _cancel_row(c: Control, x: float, y: float, w: float) -> void:
	var cancel: Button = ui.button(preload("res://scripts/mw/mw_l10n.gd").ctx_text("Interface", "Cancel", "Cancel"), func(): _close_sub())
	cancel.name = "CancelButton"
	ui.button_row(c, x, y, w, 28, [cancel])

## SelectSpecializationDialog (247 × 144).
func _open_select_spec() -> void:
	var c: Control = _sub_modal(247, 144, "specialization")
	var g = ui.group(c, 14, 14, 216, 116)
	ui.label(g, 0, 0, 216, 18, _t("sSpecializationMenu1", "Choose a specialization"), "header", HORIZONTAL_ALIGNMENT_CENTER)
	for i in 3:
		var b: Button = ui.text_button(g, 0, 28 + 18 * i, 216, 18, ui.spec_name(i), _pick_spec.bind(i), HORIZONTAL_ALIGNMENT_CENTER)
		b.name = "Specialization%d" % i
	_cancel_row(g, 0, 88, 216)

## SelectAttributeDialog (247 × 231): atrybuty MW_StatNameButtonC.
func _open_select_attr(slot: int) -> void:
	_affected = slot
	var c: Control = _sub_modal(247, 231, "attribute")
	var g = ui.group(c, 14, 14, 216, 204)
	ui.label(g, 0, 0, 216, 18, _t("sAttributesMenu1", "Choose an attribute"), "header", HORIZONTAL_ALIGNMENT_CENTER)
	var area = ui.group(g, 0, 28, 216, 144)
	for i in 8:
		var b: Button = ui.text_button(area, 0, 18 * i, 216, 18, ui.attr_name(i), _pick_attr.bind(slot, i), HORIZONTAL_ALIGNMENT_CENTER)
		b.name = "Attribute%d" % i
	_cancel_row(g, 0, 175, 216)

## SelectSkillDialog (487 × 275): trzy kolumny umiejętności według specjalizacji umiejętności.
func _open_select_skill(slot: int) -> void:
	_affected = slot
	var c: Control = _sub_modal(487, 275, "skill")
	var g = ui.group(c, 17, 14, 457, 246)
	ui.label(g, 0, 0, 457, 18, _t("sSkillsMenu1", "Choose a skill"), "header", HORIZONTAL_ALIGNMENT_CENTER)
	var cols := [[0, 0, 154], [1, 158, 154], [2, 316, 131]]
	var ids: Array = ui.skill_ids()
	for col in cols:
		ui.label(g, col[1], 32, col[2], 18, ui.spec_name(col[0]), "header")
		var y := 0.0
		var area = ui.group(g, col[1], 50, 154, 168)
		for si in ids.size():
			var srec: Dictionary = _records().record("skill", String(ids[si]))
			if int(srec.get("specialization", -1)) != int(col[0]):
				continue
			var k: int = si
			var b: Button = ui.text_button(area, 0, y, 154, 18, ui.skill_name(si), _pick_skill.bind(slot, k))
			b.name = "Skill%d" % si
			y += 18.0
	_cancel_row(g, 0, 218, 457)

## DescriptionDialog (244 × 248).
func _open_description() -> void:
	var c: Control = _sub_modal(244, 248, "description")
	ui.box(c, 8, 8, 220, 192)
	desc_edit = TextEdit.new()
	desc_edit.name = "TextEdit"
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc_edit.text = String(create_state.get("description", ""))
	var empty := StyleBoxEmpty.new()
	desc_edit.add_theme_stylebox_override("normal", empty)
	desc_edit.add_theme_stylebox_override("focus", empty)
	desc_edit.add_theme_color_override("font_color", UI.color("normal"))
	ui.at(desc_edit, c, 10, 10, 218, 190)
	var ok: Button = ui.button(_t("sInputMenu1", "OK"), _description_ok)
	ok.name = "OKButton"
	ok.position = Vector2(228 * ui.sc - ok.size.x, 208 * ui.sc)
	c.add_child(ok)
	desc_edit.grab_focus.call_deferred()

func _unhandled_input(e: InputEvent) -> void:
	if sub != null and e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		_close_sub()
		get_viewport().set_input_as_handled()
