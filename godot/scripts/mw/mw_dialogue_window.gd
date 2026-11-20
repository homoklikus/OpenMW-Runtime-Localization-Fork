extends CanvasLayer
## Okno rozmowy (etap 6, prosty interfejs – wygląd w stylu Morrowinda w etapie 10), jak DialogueWindow w OpenMW:
## historia odpowiedzi z hiperłączami tematów (tylko tematy dostępne u rozmówcy), pytania (Choice) i „Żegnaj”
## w historii, lista tematów (+ Perswazja dla NPC), pasek postawy, przycisk pożegnania (nieaktywny w trakcie
## pytania). Usługi (handel, czary, podróże, trening…) – w kolejnych etapach; nie są pokazywane.
## Gra jest wstrzymana, gdy okno jest otwarte.

signal closed

const Loc := preload("res://scripts/mw/mw_localization.gd")
# kolory jak OpenMW (Fallback FontColor_color_header/link/answer/notify)
var HEADER := "#dfc99f"
var LINK := "#707ecf"
var ANSWER := "#96321e"
var NOTIFY := "#dfc99f"

const UI := preload("res://scripts/mw/mw_ui.gd")
var dialogue                      # MWDialogue
var main
var panel: PanelContainer
var title: Label
var history_label: RichTextLabel
var topics                          # MWList (mw_list.gd) w skórce MW_SimpleList
var disp_bar: ProgressBar
var disp_label: Label
var bye_btn: Button
var persuasion = null              # PersuasionDialog (mw_persuasion_dialog.gd)
var _topic_ids: Array = []        # pozycja listy → id tematu ("" – wpis specjalny, "#persuasion")
var _links := {}                  # słowa kluczowe dostępnych tematów (dla hiperłączy w historii)

## Układ openmw_dialogue_window.layout (we wnętrzu okna, × skala GUI): marginesy 8; historia w MW_Box (wcięcie
## 7 px) na resztę szerokości; 9 px dalej prawa kolumna 166 px: pasek postawy 18 px z tekstem wewnątrz (ProgressText),
## 5 px, lista tematów, 7 px, przycisk sGoodbye 23 px.
func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	var s := UI.ui_scale()
	panel = PanelContainer.new()
	panel.name = "DialogueWindow"
	panel.theme = UI.theme(s)
	panel.custom_minimum_size = Vector2(380, 230) * s           # MinSize
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	title = Label.new()
	UI.add_head(box, title, s)
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		body.add_theme_constant_override(side, roundi(8 * s))
	box.add_child(body)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", roundi(9 * s))
	body.add_child(row)
	var hist_box := PanelContainer.new()
	hist_box.name = "DialogueHistoryBox"
	var hsb: StyleBox = UI.inner_box().duplicate()
	hsb.content_margin_left = 7 * s
	hsb.content_margin_top = 7 * s
	hsb.content_margin_right = 5 * s
	hsb.content_margin_bottom = 4 * s
	hist_box.add_theme_stylebox_override("panel", hsb)
	hist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hist_box)
	history_label = RichTextLabel.new()
	history_label.name = "History"
	history_label.bbcode_enabled = true
	history_label.scroll_following = true
	history_label.meta_clicked.connect(_on_meta)
	history_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hist_box.add_child(history_label)
	var right := VBoxContainer.new()
	right.name = "DialogueRight"
	right.custom_minimum_size.x = 166 * s
	right.add_theme_constant_override("separation", 0)
	row.add_child(right)
	var disp := Control.new()
	disp.name = "Disposition"
	disp.custom_minimum_size.y = 18 * s
	right.add_child(disp)
	disp_bar = UI.progress_bar("magic", s)
	disp_bar.max_value = 100
	disp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	disp.add_child(disp_bar)
	disp_label = Label.new()
	disp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	disp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disp_label.add_theme_color_override("font_color", UI.color("normal_pressed"))
	disp.add_child(disp_label)
	var gap1 := Control.new()
	gap1.custom_minimum_size.y = 5 * s
	right.add_child(gap1)
	topics = preload("res://scripts/mw/mw_list.gd").new(s)
	topics.name = "TopicsList"
	topics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	topics.item_clicked.connect(_on_topic)
	right.add_child(topics)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 7 * s
	right.add_child(gap2)
	bye_btn = Button.new()
	bye_btn.name = "ByeButton"
	bye_btn.custom_minimum_size.y = 23 * s
	bye_btn.pressed.connect(close)
	right.add_child(bye_btn)
	_build_persuasion()
	visible = false

func _build_persuasion() -> void:
	persuasion = preload("res://scripts/mw/mw_persuasion_dialog.gd").new(main, dialogue)
	persuasion.on_persuade = _after_action

static func dialogue_kinds() -> Array:
	return ["admire", "intimidate", "taunt", "bribe10", "bribe100", "bribe1000"]

func _t(gm: String, fb: String) -> String:
	return dialogue.gmst_text(gm, fb) if dialogue != null else fb

## Otwiera rozmowę z aktorem (węzeł referencji). false – brak powitania (okno się nie otwiera, jak w OpenMW).
func open(node: Node) -> bool:
	if not dialogue.start(node):
		# brak powitania: towarzysz – od razu okno towarzysza (BM_bear_be_unique), inaczej bez rozmowy
		if main != null and main.get("menu_mode") != null and node != null:
			var a: Dictionary = dialogue.make_actor(node)
			if main.menu_mode.is_companion(a):
				main.menu_mode.open_companion(a)
				return true
		return false
	title.text = dialogue.actor_name(dialogue.actor)
	bye_btn.text = _t("sGoodbye", "Goodbye")
	visible = true
	persuasion.close()
	refresh()
	# położenie i rozmiar jak OpenMW ([Windows] dialogue: 0,15; 0,5; 0,7 × 0,45 ekranu)
	var vp := get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(0.7, 0.45) * vp
	panel.size = panel.custom_minimum_size
	panel.position = (Vector2(0.15, 0.5) * vp).floor()
	HEADER = "#" + UI.color("header").to_html(false)
	LINK = "#" + UI.color("link").to_html(false)
	ANSWER = "#" + UI.color("answer").to_html(false)
	NOTIFY = "#" + UI.color("notify").to_html(false)
	_render_history()
	main.gui.push("dialogue", [self], func(): close())      # GM_Dialogue; Esc = „Żegnaj” (nie w trakcie pytania)
	return true

## GuiModeState::update(true) po zamknięciu trybu nad rozmową (handel, usługi): odświeżenie tematów i złota.
func gui_resumed() -> void:
	refresh()

## Odświeżenie: lista tematów, hiperłącza, historia, postawa (updateTopics + updateHistory).
func refresh() -> void:
	if not visible:
		return
	var av: Array = dialogue.available_topics()
	topics.clear()
	_topic_ids = []
	var special := 0
	if dialogue.actor.get("npc", false):
		topics.add_item(_t("sPersuasion", "Persuasion"))
		_topic_ids.append("#persuasion")
		special += 1
	if main != null and main.get("trade") != null:
		for e in main.trade.service_entries(dialogue.actor):
			topics.add_item(String(e[1]))
			_topic_ids.append("#svc:" + String(e[0]))
			special += 1
	# updateTopicsPane: sCompanionShare na końcu usług, gdy aktor jest towarzyszem
	if main != null and main.get("menu_mode") != null and main.menu_mode.is_companion(dialogue.actor):
		topics.add_item(_t("sCompanionShare", "Companion Share"))
		_topic_ids.append("#companion")
		special += 1
	if special > 0:
		topics.add_separator()                 # updateTopicsPane: addSeparator po usługach
		_topic_ids.append("")
	_links = {}
	for t in av:
		var name: String = dialogue.topic_name(t)
		topics.add_item(name, 3)               # sVerticalPadding = 3
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
		disp_bar.get_parent().visible = true
		disp_bar.value = d
		disp_label.text = "%d/100" % d
	else:
		disp_bar.get_parent().visible = false

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
		out += "\n[url=goodbye][color=%s]%s[/color][/url]" % [ANSWER, Loc.escape_bbcode(_t("sGoodbye", "Goodbye"))]
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
	elif id == "#companion":
		if not dialogue.in_choice and not dialogue.goodbye_flag:
			main.menu_mode.open_companion(dialogue.actor)     # pushGuiMode(GM_Companion, aktor)
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
	persuasion.open(self)

func _persuade(kind: String, roll := -1) -> void:
	persuasion.persuade(kind, roll)

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
	persuasion.close()
	for wn in ["service_window", "enchanting_window", "spellcreation_window"]:
		var w = main.get(wn)            # DialogueWindow::onGoodbye: okna usług zamykane razem z rozmową
		if w != null and w.visible:
			w.close()
	main.gui.remove("dialogue")
	closed.emit()
	if main != null and main.has_method("on_dialogue_closed"):
		main.on_dialogue_closed()
	return true
