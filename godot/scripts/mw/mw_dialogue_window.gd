extends CanvasLayer
## Okno rozmowy (etap 6, prosty interfejs – wygląd w stylu Morrowinda w etapie 10), jak DialogueWindow w OpenMW:
## historia odpowiedzi z hiperłączami tematów (tylko tematy dostępne u rozmówcy), pytania (Choice) i „Żegnaj”
## w historii, lista tematów (+ Perswazja dla NPC), pasek postawy, przycisk pożegnania (nieaktywny w trakcie
## pytania). Usługi (handel, czary, podróże, trening…) – w kolejnych etapach; nie są pokazywane.
## Gra jest wstrzymana, gdy okno jest otwarte.

signal closed

const Loc := preload("res://scripts/mw/mw_localization.gd")
const HEADER := "#dfc99f"
const LINK := "#7090d0"
const ANSWER := "#c8a050"
const NOTIFY := "#e0e0a0"

var dialogue                      # MWDialogue
var main
var panel: PanelContainer
var title: Label
var history_label: RichTextLabel
var topics: ItemList
var disp_bar: ProgressBar
var disp_label: Label
var bye_btn: Button
var persuasion: PanelContainer
var gold_label: Label
var _bribe_btns := {}
var _topic_ids: Array = []        # pozycja listy → id tematu ("" – wpis specjalny, "#persuasion")
var _links := {}                  # słowa kluczowe dostępnych tematów (dla hiperłączy w historii)

func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "DialogueWindow"
	panel.custom_minimum_size = Vector2(980, 560)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.scroll_following = true
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.size_flags_stretch_ratio = 2.6
	history_label.meta_clicked.connect(_on_meta)
	row.add_child(history_label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	disp_bar = ProgressBar.new()
	disp_bar.max_value = 100
	disp_bar.show_percentage = false
	right.add_child(disp_bar)
	disp_label = Label.new()
	disp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(disp_label)
	topics = ItemList.new()
	topics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	topics.item_activated.connect(_on_topic)
	topics.item_clicked.connect(func(i, _p, _b): _on_topic(i))
	right.add_child(topics)
	bye_btn = Button.new()
	bye_btn.pressed.connect(close)
	right.add_child(bye_btn)
	_build_persuasion()
	visible = false

func _build_persuasion() -> void:
	persuasion = PanelContainer.new()
	persuasion.name = "Persuasion"
	persuasion.visible = false
	add_child(persuasion)
	var box := VBoxContainer.new()
	persuasion.add_child(box)
	var t := Label.new()
	t.name = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	for k in dialogue_kinds():
		var b := Button.new()
		b.name = k
		var kind: String = k
		b.pressed.connect(func(): _persuade(kind))
		box.add_child(b)
		if kind.begins_with("bribe"):
			_bribe_btns[kind] = b
	gold_label = Label.new()
	box.add_child(gold_label)
	var c := Button.new()
	c.name = "cancel"
	c.pressed.connect(func(): persuasion.visible = false)
	box.add_child(c)

static func dialogue_kinds() -> Array:
	return ["admire", "intimidate", "taunt", "bribe10", "bribe100", "bribe1000"]

func _t(gm: String, fb: String) -> String:
	return dialogue.gmst_text(gm, fb) if dialogue != null else fb

## Otwiera rozmowę z aktorem (węzeł referencji). false – brak powitania (okno się nie otwiera, jak w OpenMW).
func open(node: Node) -> bool:
	if not dialogue.start(node):
		return false
	title.text = dialogue.actor_name(dialogue.actor)
	bye_btn.text = _t("sGoodbye", "Żegnaj")
	visible = true
	persuasion.visible = false
	refresh()
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

## Odświeżenie: lista tematów, hiperłącza, historia, postawa (updateTopics + updateHistory).
func refresh() -> void:
	if not visible:
		return
	var av: Array = dialogue.available_topics()
	topics.clear()
	_topic_ids = []
	var special := 0
	if dialogue.actor.get("npc", false):
		topics.add_item(_t("sPersuasion", "Perswazja"))
		_topic_ids.append("#persuasion")
		special += 1
	if main != null and main.get("trade") != null:
		for e in main.trade.service_entries(dialogue.actor):
			topics.add_item(String(e[1]))
			_topic_ids.append("#svc:" + String(e[0]))
			special += 1
	if special > 0:
		topics.add_item("")
		topics.set_item_selectable(topics.item_count - 1, false)
		topics.set_item_disabled(topics.item_count - 1, true)
		_topic_ids.append("")
	_links = {}
	for t in av:
		var name: String = dialogue.topic_name(t)
		topics.add_item(name)
		_topic_ids.append(t)
		dialogue._seed(_links, name.to_lower(), t)
	var blocked: bool = dialogue.in_choice or dialogue.goodbye_flag
	for i in topics.item_count:
		if _topic_ids[i] != "":
			topics.set_item_disabled(i, blocked)
	bye_btn.disabled = dialogue.in_choice and not dialogue.goodbye_flag
	_render_history()
	if dialogue.actor.get("npc", false):
		var d: int = dialogue.derived_disposition(dialogue.actor)
		disp_bar.visible = true
		disp_label.visible = true
		disp_bar.value = d
		disp_label.text = "%d/100" % d
	else:
		disp_bar.visible = false
		disp_label.visible = false

func _render_history() -> void:
	var out := ""
	for h in dialogue.history:
		if h.kind == "message":
			out += "\n[color=%s]%s[/color]\n" % [NOTIFY, Loc.escape_bbcode(String(h.text))]
			continue
		if not String(h.title).is_empty():
			out += "\n[color=%s]%s[/color]\n" % [HEADER, Loc.escape_bbcode(String(h.title))]
		out += _linkify(String(h.text)) + "\n"
	for c in dialogue.choices:
		out += "\n[url=choice:%d][color=%s]%s[/color][/url]" % [int(c[1]), ANSWER, Loc.escape_bbcode(String(c[0]))]
	if dialogue.goodbye_flag:
		out += "\n[url=goodbye][color=%s]%s[/color][/url]" % [ANSWER, Loc.escape_bbcode(_t("sGoodbye", "Żegnaj"))]
	history_label.text = out

## Response::write – tekst z „@temat#” zamienionym na nazwę i hiperłączami dostępnych tematów.
func _linkify(text: String) -> String:
	var matches: Array = dialogue.parse_hypertext(text, _links)
	var out := ""
	var pos := 0
	for m in matches:
		out += Loc.escape_bbcode(text.substr(pos, int(m.beg) - pos))
		var disp := String(m.display)
		if _topic_ids.has(String(m.id)):
			out += "[url=topic:%s][color=%s]%s[/color][/url]" % [String(m.id).uri_encode(), LINK, Loc.escape_bbcode(disp)]
		else:
			out += Loc.escape_bbcode(disp)
		pos = int(m.end)
	return out + Loc.escape_bbcode(text.substr(pos))

func _on_meta(meta) -> void:
	var s := String(meta)
	if s == "goodbye":
		close(true)
	elif s.begins_with("choice:"):
		if dialogue.goodbye_flag:
			close(true)
			return
		dialogue.answer(int(s.substr(7)))
		_after_action()
	elif s.begins_with("topic:"):
		select_topic(s.substr(6).uri_decode())

func _on_topic(i: int) -> void:
	if i < 0 or i >= _topic_ids.size():
		return
	var id: String = _topic_ids[i]
	topics.deselect_all()
	if id == "#persuasion":
		if not dialogue.in_choice and not dialogue.goodbye_flag:
			_open_persuasion()
	elif id.begins_with("#svc:"):
		if not dialogue.in_choice and not dialogue.goodbye_flag:
			main.trade_window.open(id.substr(5))
	elif id != "":
		select_topic(id)

func select_topic(id: String) -> void:
	if dialogue.goodbye_flag or dialogue.in_choice:
		return
	dialogue.select_topic(id)
	_after_action()

func _after_action() -> void:
	refresh()

func _open_persuasion() -> void:
	var g: int = dialogue.gold()
	(persuasion.get_node("VBoxContainer/Title") as Label).text = _t("sPersuasionMenuTitle", "Perswazja")
	var labels := {"admire": ["sAdmire", "Podziw"], "intimidate": ["sIntimidate", "Zastraszenie"],
		"taunt": ["sTaunt", "Drwina"], "bribe10": ["sBribe 10 Gold", "Łapówka (10 sztuk złota)"],
		"bribe100": ["sBribe 100 Gold", "Łapówka (100 sztuk złota)"], "bribe1000": ["sBribe 1000 Gold", "Łapówka (1000 sztuk złota)"]}
	for k in labels:
		var b := persuasion.get_node("VBoxContainer/" + k) as Button
		b.text = _t(labels[k][0], labels[k][1])
	(_bribe_btns["bribe10"] as Button).disabled = g < 10
	(_bribe_btns["bribe100"] as Button).disabled = g < 100
	(_bribe_btns["bribe1000"] as Button).disabled = g < 1000
	gold_label.text = "%s: %d" % [_t("sGold", "Złoto"), g]
	(persuasion.get_node("VBoxContainer/cancel") as Button).text = _t("sCancel", "Anuluj")
	persuasion.visible = true
	persuasion.position = (get_viewport().get_visible_rect().size - persuasion.get_combined_minimum_size()) / 2.0

func _persuade(kind: String, roll := -1) -> void:
	dialogue.persuade(kind, roll)
	persuasion.visible = false
	_after_action()

## Zamknięcie: w trakcie pytania niemożliwe (exit() w OpenMW), chyba że rozmowa zakończona przez Goodbye.
func close(force := false) -> bool:
	if not visible:
		return true
	if dialogue.in_choice and not dialogue.goodbye_flag and not force:
		return false
	dialogue.end()
	visible = false
	if main != null and main.get("trade_window") != null:
		main.trade_window.close()
	persuasion.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	if main != null and main.has_method("on_dialogue_closed"):
		main.on_dialogue_closed()
	return true
