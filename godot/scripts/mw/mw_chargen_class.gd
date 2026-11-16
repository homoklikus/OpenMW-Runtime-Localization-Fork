extends Control
## Klasa postaci (etap 10) jak OpenMW CharacterCreation: wybór sposobu (ClassChoiceDialog) –
## 1) pytania: 10 pytań z Morrowind.ini/openmw.cfg (Question_N_Question / AnswerOne/Two/Three – walka, magia,
##    skradanie; kolejność odpowiedzi losowa; głos „vo\misc\chargen qaN.wav”), wynik według tabeli
##    showClassQuestionDialog i okno GenerateClassResult (Wróć / OK);
## 2) własna klasa (CreateClassDialog): nazwa, opis, specjalizacja, 2 ulubione atrybuty, 5 głównych i 5 drugorzędnych
##    umiejętności (bez powtórzeń – wybór istniejącej zamienia pola jak onSkillSelected/onAttributeSelected);
##    domyślnie jak w OpenMW (Siła, Zręczność; Blok, Płatnerstwo, Średni pancerz, Ciężki pancerz, Broń obuchowa /
##    Długie ostrza, Topory, Włócznie, Atletyka, Zaklinanie). Rekord klasy jako rekord utworzony w grze
##    (GameState.created["class"]["mwg_class_player"], jak setPlayerClass z klasą dynamiczną).

signal class_chosen(class_id: String)

const CUSTOM_ID := "mwg_class_player"
const SPEC_GMST := ["sSpecializationCombat", "sSpecializationMagic", "sSpecializationStealth"]
const SPEC_DEF := ["Walka", "Magia", "Skradanie"]

var main
var character
var loc = null
var fallbacks := {}
var rng := RandomNumberGenerator.new()
var _panel: PanelContainer
var _box: VBoxContainer
var step := -1                         # pytanie 0..9; 10 = wynik
var counts := [0, 0, 0]               # walka, magia, skradanie
var result_class := ""
var _answers: Array = []              # specjalizacje przycisków bieżącego pytania
# własna klasa
var c_name: LineEdit
var c_desc: TextEdit
var c_spec: OptionButton
var c_attr: Array = []                # 2 × OptionButton
var c_major: Array = []               # 5 × OptionButton
var c_minor: Array = []               # 5 × OptionButton
var _guard := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	rng.randomize()
	var dim := ColorRect.new()                 # przyciemnienie kreatora pod oknem dialogu
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

func _t(gm: String, def: String) -> String:
	return main.dialogue.gmst_text(gm, def) if main != null and main.dialogue != null else def

func load_fallbacks(data_root: String) -> void:
	var f := FileAccess.open(data_root.path_join("world/fallbacks.json"), FileAccess.READ)
	if f != null:
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			fallbacks = j.get("values", {})

## Tekst pytania: tłumaczenie z lokalizacji (sekcja „Question N”), inaczej wartość z instalacji.
func q_text(n: int, key: String) -> String:
	var base := String(fallbacks.get("Question_%d_%s" % [n, key], ""))
	if loc != null and loc.has_method("fallback_value"):
		return loc.fallback_value("Question %d" % n, key, base)
	return base

func questions_available() -> bool:
	for n in range(1, 11):
		if q_text(n, "Question").is_empty():
			return false
	return true

func _clear() -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.07, 0.98)
	sb.set_content_margin_all(12)
	sb.border_color = Color(0.55, 0.45, 0.3)
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_box = VBoxContainer.new()
	_panel.add_child(_box)
	visible = true

func _center() -> void:
	await get_tree().process_frame
	if _panel != null and is_instance_valid(_panel):
		_panel.position = ((get_viewport().get_visible_rect().size - _panel.size) / 2.0).floor()

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	_box.add_child(l)
	return l

func _button(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func close() -> void:
	visible = false
	if main != null and main.audio != null:
		main.audio.stop_say("player")
	if _panel != null:
		_panel.queue_free()
		_panel = null

# --- pytania ---------------------------------------------------------------------------------------------

func start_questions() -> void:
	step = 0
	counts = [0, 0, 0]
	result_class = ""
	_show_question()

func _show_question() -> void:
	if step >= 10:
		_show_result()
		return
	_clear()
	var n := step + 1
	_label(q_text(n, "Question"))
	var answers := [[q_text(n, "AnswerOne"), 0], [q_text(n, "AnswerTwo"), 1], [q_text(n, "AnswerThree"), 2]]
	# losowa kolejność odpowiedzi (rollDice(6) – jedna z 6 permutacji)
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	var p: Array = perms[rng.randi_range(0, 5)]
	_answers = []
	for k in p:
		var a: Array = answers[k]
		_answers.append(int(a[1]))
		var b := _button(_box, String(a[0]), answer.bind(_answers.size() - 1))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if main != null and main.audio != null:
		main.audio.say("player", "vo\\misc\\chargen qa%d.wav" % n)
	_center()

## Odpowiedź (indeks przycisku w kolejności wyświetlenia).
func answer(i: int) -> void:
	if step < 0 or step >= 10 or i < 0 or i >= _answers.size():
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

func _class_name(id: String) -> String:
	var r: Dictionary = character.records.record("class", id)
	var fb := String(r.get("name", id))
	if loc != null and loc.has_method("is_active") and loc.is_active():
		return loc.plain(loc.key("CLAS", id, "FNAM"), fb)
	return fb

func _show_result() -> void:
	step = 10
	result_class = class_for(counts[0], counts[1], counts[2]).to_lower()
	_clear()
	_label(_t("sClassChoiceMenu1", "Na podstawie twoich odpowiedzi najlepiej pasuje do ciebie klasa:"))
	var nm := _label(_class_name(result_class))
	nm.add_theme_font_size_override("font_size", 22)
	var desc := String(character.records.record("class", result_class).get("description", ""))
	if not desc.is_empty():
		_label(desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_box.add_child(row)
	_button(row, _t("sBack", "Wróć"), close)
	_button(row, _t("sOK", "OK"), accept_result)
	_center()

func accept_result() -> void:
	var c := result_class
	close()
	if not c.is_empty():
		class_chosen.emit(c)

# --- własna klasa ----------------------------------------------------------------------------------------

func _opt(items: Array, sel: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.select(sel)
	return o

func start_custom() -> void:
	_clear()
	_panel.custom_minimum_size = Vector2(760, 0)
	var attrs: Array = character.records.records_index().get("attributes", [])
	var skills: Array = character.skill_names()
	var grid := GridContainer.new()
	grid.columns = 2
	_box.add_child(grid)
	var add := func(label: String, ctl: Control):
		var l := Label.new()
		l.text = label
		grid.add_child(l)
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(ctl)
	var prev: Dictionary = character.records.dynamic.get("class", {}).get(CUSTOM_ID, {})
	c_name = LineEdit.new()
	c_name.text = String(prev.get("name", ""))
	c_name.placeholder_text = _t("sName", "Nazwa")
	add.call(_t("sName", "Nazwa"), c_name)
	c_spec = _opt(range(3).map(func(i): return _t(SPEC_GMST[i], SPEC_DEF[i])), int(prev.get("specialization", 0)))
	add.call(_t("sChooseClassMenu1", "Specjalizacja"), c_spec)
	var pa: Array = prev.get("attributes", [0, 3])
	c_attr = []
	for i in 2:
		var o := _opt(attrs, int(pa[i]))
		o.item_selected.connect(_attr_changed.bind(i))
		c_attr.append(o)
		add.call(_t("sChooseClassMenu2", "Ulubione atrybuty") if i == 0 else "", o)
	var pmaj: Array = prev.get("major_skills", [0, 1, 2, 3, 4])
	var pmin: Array = prev.get("minor_skills", [5, 6, 7, 8, 9])
	c_major = []
	c_minor = []
	for i in 5:
		var o := _opt(skills, int(pmaj[i]))
		o.item_selected.connect(_skill_changed.bind(o))
		c_major.append(o)
		add.call(_t("sChooseClassMenu3", "Umiejętności główne") if i == 0 else "", o)
	for i in 5:
		var o := _opt(skills, int(pmin[i]))
		o.item_selected.connect(_skill_changed.bind(o))
		c_minor.append(o)
		add.call(_t("sChooseClassMenu4", "Umiejętności drugorzędne") if i == 0 else "", o)
	c_desc = TextEdit.new()
	c_desc.text = String(prev.get("description", ""))
	c_desc.custom_minimum_size = Vector2(0, 60)
	add.call(_t("sDescription", "Opis"), c_desc)
	for o in c_major + c_minor:
		(o as OptionButton).set_meta("prev", (o as OptionButton).selected)
	for o in c_attr:
		(o as OptionButton).set_meta("prev", (o as OptionButton).selected)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_box.add_child(row)
	_button(row, _t("sBack", "Wróć"), close)
	_button(row, _t("sOK", "OK"), accept_custom)
	_center()

## onAttributeSelected: ten sam atrybut w drugim polu – zamiana.
func _attr_changed(sel: int, i: int) -> void:
	if _guard:
		return
	_guard = true
	var other: OptionButton = c_attr[1 - i]
	if other.selected == sel:
		other.select(int(c_attr[i].get_meta("prev")))
	for o in c_attr:
		o.set_meta("prev", o.selected)
	_guard = false

## onSkillSelected: umiejętność wybrana już w innym polu – tamto pole dostaje poprzednią wartość tego pola.
func _skill_changed(sel: int, o: OptionButton) -> void:
	if _guard:
		return
	_guard = true
	for x in c_major + c_minor:
		if x != o and (x as OptionButton).selected == sel:
			(x as OptionButton).select(int(o.get_meta("prev")))
			break
	for x in c_major + c_minor:
		(x as OptionButton).set_meta("prev", (x as OptionButton).selected)
	_guard = false

func custom_record() -> Dictionary:
	return {"id": CUSTOM_ID, "name": c_name.text.strip_edges(), "description": c_desc.text.strip_edges(),
		"specialization": c_spec.selected, "attributes": c_attr.map(func(o): return o.selected),
		"major_skills": c_major.map(func(o): return o.selected), "minor_skills": c_minor.map(func(o): return o.selected),
		"playable": true, "services": 0}

## onOkClicked: bez nazwy nic się nie dzieje (jak OpenMW).
func accept_custom() -> bool:
	if c_name == null or c_name.text.strip_edges().is_empty():
		return false
	var rec := custom_record()
	var dyn: Dictionary = character.records.dynamic
	if not dyn.has("class"):
		dyn["class"] = {}
	dyn["class"][CUSTOM_ID] = rec
	close()
	class_chosen.emit(CUSTOM_ID)
	return true
