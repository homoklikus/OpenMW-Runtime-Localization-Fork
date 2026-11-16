extends CanvasLayer
## Dziennik (etap 6, prosty interfejs – księga w stylu Morrowinda w etapie 10), jak JournalWindow w OpenMW:
##   „Dziennik” – wszystkie wpisy w kolejności dodania z datą (dzień miesiąca, miesiąc, dzień gry),
##   „Zadania” – nazwy zadań (aktywne albo wszystkie, z zakończonymi) i ich wpisy,
##   „Tematy” – dziennik tematów: odpowiedzi rozmówców (nazwa rozmówcy, tekst).
## Klawisz J (akcja „journal”) otwiera i zamyka; gra jest wstrzymana, gdy okno jest otwarte.

const Loc := preload("res://scripts/mw/mw_localization.gd")
const MONTHS := ["sMonthMorningstar", "sMonthSunsdawn", "sMonthFirstseed", "sMonthRainshand", "sMonthSecondseed",
	"sMonthMidyear", "sMonthSunsheight", "sMonthLastseed", "sMonthHeartfire", "sMonthFrostfall", "sMonthSunsdusk",
	"sMonthEveningstar"]
const MONTHS_FB := ["Gwiazda Poranna", "Świt Słońca", "Pierwszy Siew", "Deszczowa Dłoń", "Drugi Siew", "Połowa Roku",
	"Wysokie Słońce", "Ostatni Siew", "Domowe Ognisko", "Pierwszy Mróz", "Zmierzch Słońca", "Gwiazda Wieczorna"]

var dialogue
var main
var panel: PanelContainer
var tabs: TabContainer
var all_text: RichTextLabel
var quest_list: ItemList
var quest_text: RichTextLabel
var show_finished: CheckBox
var topic_list: ItemList
var topic_text: RichTextLabel
var _quests: Array = []
var _topics: Array = []

func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "JournalWindow"
	panel.custom_minimum_size = Vector2(980, 600)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	all_text = _rich()
	all_text.name = "Dziennik"
	tabs.add_child(all_text)
	var q := VBoxContainer.new()
	q.name = "Zadania"
	tabs.add_child(q)
	show_finished = CheckBox.new()
	show_finished.text = "Pokaż zakończone zadania"
	show_finished.toggled.connect(func(_b): _fill_quests())
	q.add_child(show_finished)
	var qr := HBoxContainer.new()
	qr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	q.add_child(qr)
	quest_list = ItemList.new()
	quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_list.item_selected.connect(_show_quest)
	qr.add_child(quest_list)
	quest_text = _rich()
	quest_text.size_flags_stretch_ratio = 2.0
	qr.add_child(quest_text)
	var t := HBoxContainer.new()
	t.name = "Tematy"
	tabs.add_child(t)
	topic_list = ItemList.new()
	topic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topic_list.item_selected.connect(_show_topic)
	t.add_child(topic_list)
	topic_text = _rich()
	topic_text.size_flags_stretch_ratio = 2.0
	t.add_child(topic_text)
	var close_btn := Button.new()
	close_btn.text = "Zamknij (J)"
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
	visible = false

func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r

func date_text(e: Dictionary) -> String:
	var m := int(e.get("month", 0))
	var mname: String = dialogue.gmst_text(MONTHS[m], MONTHS_FB[m]) if m >= 0 and m < 12 else ""
	return "%d %s (%s %d)" % [int(e.get("day_of_month", 1)), mname, dialogue.gmst_text("sDay", "Dzień"), int(e.get("day", 1))]

func open() -> void:
	visible = true
	refresh()
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func refresh() -> void:
	var out := ""
	for e in dialogue._ds().entries:
		out += "[color=#dfc99f]%s[/color]\n%s\n\n" % [Loc.escape_bbcode(date_text(e)), Loc.escape_bbcode(String(e.get("text", "")))]
	all_text.text = out if not out.is_empty() else "(brak wpisów)"
	_fill_quests()
	_topics = (dialogue._ds().topics as Dictionary).keys()
	_topics.sort_custom(func(a, b): return dialogue.topic_name(a).to_lower() < dialogue.topic_name(b).to_lower())
	topic_list.clear()
	for k in _topics:
		topic_list.add_item(dialogue.topic_name(k))
	topic_text.text = ""

## Zadania jak w OpenMW (JournalViewModel): nazwa z odpowiedzi „QSTN”; zadania o tej samej nazwie razem.
func _fill_quests() -> void:
	_quests = []
	var by_name := {}
	for q in dialogue.quests_view():
		var name := String(q.name)
		if name.is_empty():
			continue
		if by_name.has(name):
			var g: Dictionary = by_name[name]
			g.entries.append_array(q.entries)
			g.finished = g.finished and q.finished
			continue
		var g2 := {"name": name, "finished": q.finished, "entries": q.entries.duplicate(), "ids": [q.id]}
		by_name[name] = g2
		_quests.append(g2)
	if not show_finished.button_pressed:
		_quests = _quests.filter(func(g): return not g.finished)
	_quests.sort_custom(func(a, b): return String(a.name).to_lower() < String(b.name).to_lower())
	quest_list.clear()
	for g in _quests:
		quest_list.add_item(String(g.name) + ("  (zakończone)" if g.finished else ""))
	quest_text.text = ""

func _show_quest(i: int) -> void:
	var out := ""
	for e in _quests[i].entries:
		out += "[color=#dfc99f]%s[/color]\n%s\n\n" % [Loc.escape_bbcode(date_text(e)), Loc.escape_bbcode(String(e.get("text", "")))]
	quest_text.text = out

func _show_topic(i: int) -> void:
	var out := ""
	for e in dialogue._ds().topics.get(_topics[i], []):
		out += "[color=#dfc99f]%s[/color]\n%s\n\n" % [Loc.escape_bbcode(String(e.get("actor", ""))), Loc.escape_bbcode(String(e.get("text", "")))]
	topic_text.text = out
