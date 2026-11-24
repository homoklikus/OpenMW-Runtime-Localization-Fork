extends CanvasLayer
## Dziennik jak JournalWindow w OpenMW (mwgui/journalwindow.cpp, openmw_journal.layout, journalbooks.cpp):
## księga 565 × 390 na warstwie „JournalBooks” (ScalingLayer 600 × 520 – UI.book_scale), tło tx_menubook,
## dwie strony 240 × 320 składane silnikiem książek (MWBook), przyciski z tekstur tx_menubook_* (szerokość z proporcji
## tekstury przy wysokości z układu – BookWindowBase::adjustButton), numery stron czcionką księgi.
##   Księga główna: wpisy w kolejności dodania – nagłówek z datą (kolor journalHeaderColour 0,6/0/0), tekst czarny,
##     odstęp między wpisami; bez wpisów – „You have no journal entries!” (napis z kodu OpenMW).
##   Opcje (nakładka tx_menubook_bookmark): indeks tematów ( A ) … ( Z ) w dwóch kolumnach → lista tematów na literę
##     → księga tematu (nazwa, „rozmówca” „tekst”); Zadania → lista (aktywne / wszystkie: Show All / Show Active),
##     → księga zadania (nazwa, wpisy bez dat); Anuluj – powrót do indeksu albo do księgi.
##   Stos ksiąg: księga tematu/zadania nad główną – przycisk Journal (powrót) zamiast Close.
## Klawisz J (akcja „journal”) otwiera i zamyka; gra jest wstrzymana, gdy okno jest otwarte.

const UI := preload("res://scripts/mw/mw_ui.gd")
const Book := preload("res://scripts/mw/mw_book.gd")
const MONTHS := ["sMonthMorningstar", "sMonthSunsdawn", "sMonthFirstseed", "sMonthRainshand", "sMonthSecondseed",
	"sMonthMidyear", "sMonthSunsheight", "sMonthLastseed", "sMonthHeartfire", "sMonthFrostfall", "sMonthSunsdusk",
	"sMonthEveningstar"]
const MONTHS_FB := ["Morning Star", "Sun's Dawn", "First Seed", "Rain's Hand", "Second Seed", "Mid Year",
	"Sun's Height", "Last Seed", "Hearthfire", "Frost Fall", "Sun's Dusk", "Evening Star"]
const WIN := Vector2(565, 390)
const HEADER_COLOR := "990000"           # journalbooks.hpp: journalHeaderColour (0,60; 0,00; 0,00)
const EMPTY_HEADER := "You have no journal entries!"
const EMPTY_BODY := "You should have gone though the starting quest and got an initial quest."

var dialogue
var main
var data_root := ""
var scale_ui := 1.0
var panel: Control                       # okno księgi (rozmiar WIN × skala)
var _root: Control
var _pages := []                         # dwa obszary stron (przycinanie)
var _papers := []
var _num := []
var _btn := {}                           # nazwa → przycisk
var _overlay: Control
var _index := []                         # dwie kolumny indeksu tematów
var _list: VBoxContainer                 # lista tematów albo zadań
var _list_box: ScrollContainer
var _states: Array = []                  # stos ksiąg: {"markup", "fmt", "page"}
var _quest_mode := false
var _topics_mode := false
var _all_quests := false
var _quests: Array = []
var _topics: Array = []

func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func date_text(e: Dictionary) -> String:
	var m := int(e.get("month", 0))
	var mname: String = dialogue.gmst_text(MONTHS[m], MONTHS_FB[m]) if m >= 0 and m < 12 else ""
	return "%d %s (%s %d)" % [int(e.get("day_of_month", 1)), mname, dialogue.gmst_text("sDay", "Day"), int(e.get("day", 1))]

static func _esc(t: String) -> String:
	return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<BR>")

func _header(t: String) -> String:
	return "<FONT COLOR=\"%s\">%s</FONT><BR>" % [HEADER_COLOR, _esc(t)]

## createJournalBook / createEmptyJournalBook.
func journal_markup() -> String:
	var entries: Array = dialogue._ds().entries
	if entries.is_empty():
		return _header(EMPTY_HEADER) + "<FONT COLOR=\"000000\">%s</FONT><BR>" % _esc(EMPTY_BODY)
	var out := ""
	for e in entries:
		out += _header(date_text(e)) + "<FONT COLOR=\"000000\">%s</FONT><BR><BR>" % _esc(String(e.get("text", "")))
	return out

## createQuestBook: nazwa zadania (nagłówek), wpisy bez dat.
func quest_markup(g: Dictionary) -> String:
	var out := _header(String(g.name)) + "<BR>"
	for e in g.entries:
		out += "<FONT COLOR=\"000000\">%s</FONT><BR><BR>" % _esc(String(e.get("text", "")))
	return out

## createTopicBook: nazwa tematu (nagłówek), wpisy „rozmówca "tekst"”.
func topic_markup(topic: String) -> String:
	var out := _header(dialogue.topic_name(topic)) + "<BR>"
	for e in dialogue._ds().topics.get(topic, []):
		out += "<FONT COLOR=\"000000\">%s \"%s\"</FONT><BR><BR>" % [_esc(String(e.get("actor", ""))), _esc(String(e.get("text", "")))]
	return out

# --- budowa okna -----------------------------------------------------------------------------------------

func _tex(rel: String) -> Texture2D:
	var root := data_root
	if root.is_empty() and main != null:
		root = String(main.get("data_dir")) if main.get("data_dir") != null else ""
	var p := root.path_join(rel)
	if root.is_empty() or not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	return ImageTexture.create_from_image(img) if img != null else null

func _px(v: Vector2) -> Vector2:
	return (v * scale_ui).floor()

## ImageButton z teksturami tx_menubook_<nazwa>_idle/over/pressed; szerokość z proporcji tekstury przy wysokości
## z układu (adjustButton); „next” 64 px – 7 px śmieci po prawej (JournalWindowImpl).
func _button(parent: Control, name: String, label: String, pos: Vector2, size: Vector2, cb: Callable) -> BaseButton:
	var idle := _tex("textures/tx_menubook_%s_idle.png" % name)
	var b: BaseButton
	var sz := size
	if idle != null:
		var tb := TextureButton.new()
		var over := _tex("textures/tx_menubook_%s_over.png" % name)
		var pressed := _tex("textures/tx_menubook_%s_pressed.png" % name)
		sz = Vector2(roundf(idle.get_width() * size.y / idle.get_height()), size.y)
		if name == "next" and int(sz.x) == 64:
			sz.x = 57.0
			var crop := func(t: Texture2D) -> Texture2D:
				if t == null:
					return null
				var at := AtlasTexture.new()
				at.atlas = t
				at.region = Rect2(0, 0, t.get_width() * 57.0 / 64.0, t.get_height())
				return at
			idle = crop.call(idle)
			over = crop.call(over)
			pressed = crop.call(pressed)
		tb.texture_normal = idle
		tb.texture_hover = over
		tb.texture_pressed = pressed
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_SCALE
		b = tb
	else:
		var bt := Button.new()
		bt.text = label
		b = bt
	b.name = name.capitalize().replace(" ", "") + "Button"
	b.position = _px(pos)
	b.size = _px(sz)
	b.pressed.connect(cb)
	parent.add_child(b)
	_btn[name] = b
	return b

func _image(parent: Control, rel: String, pos: Vector2, size: Vector2, fallback: Color) -> Control:
	var t := _tex(rel)
	var c: Control
	if t != null:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		c = r
	else:
		var cr := ColorRect.new()
		cr.color = fallback
		c = cr
	c.position = _px(pos)
	c.size = _px(size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

func _book_label(text: String, color := Color.BLACK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Book.font("default"))
	l.add_theme_font_size_override("font_size", int(round(16 * scale_ui)))
	l.add_theme_color_override("font_color", color)
	return l

func _build() -> void:
	if _root != null:
		_root.queue_free()
	_btn = {}
	_pages = []
	_papers = []
	_num = []
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	scale_ui = UI.book_scale(vp)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	panel = Control.new()
	panel.name = "JournalWindow"
	panel.size = _px(WIN)
	panel.custom_minimum_size = panel.size
	panel.position = UI.book_origin(vp, WIN)       # WindowBase::center na ScalingLayer
	_root.add_child(panel)
	_image(panel, "textures/tx_menubook.png", Vector2(-70, 0), Vector2(705, 390), Color(0.82, 0.74, 0.58))
	for x in [30.0, 295.0]:
		var clip := Control.new()
		clip.clip_contents = true
		clip.position = _px(Vector2(x, 22))
		clip.size = _px(Vector2(240, 320))
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(clip)
		_pages.append(clip)
	for x in [150.0, 410.0]:
		var num := _book_label("")
		num.position = _px(Vector2(x, 350))
		num.size = _px(Vector2(32, 16))
		panel.add_child(num)
		_num.append(num)
	_button(panel, "options", "Options", Vector2(40, 350), Vector2(64, 32), _on_options)
	_button(panel, "prev", "Prev", Vector2(205, 350), Vector2(48, 32), prev_page)
	_button(panel, "next", "Next", Vector2(300, 350), Vector2(48, 32), next_page)
	_button(panel, "close", "Close", Vector2(460, 350), Vector2(48, 32), close)
	_button(panel, "journal", "Journal", Vector2(460, 350), Vector2(64, 32), _on_journal)
	# nakładka opcji (położenie względem okna jak w układzie: 293 0 386 350)
	_overlay = Control.new()
	_overlay.name = "OptionsOverlay"
	_overlay.position = _px(Vector2(293, 0))
	_overlay.size = _px(Vector2(386, 350))
	panel.add_child(_overlay)
	_image(_overlay, "textures/tx_menubook_bookmark.png", Vector2.ZERO, Vector2(386, 350), Color(0.8, 0.72, 0.55))
	_index = []
	for col in 2:
		var v := VBoxContainer.new()
		v.position = _px(Vector2(20.0 if col == 0 else 130.0, 10))
		v.size = _px(Vector2(92, 260))
		v.add_theme_constant_override("separation", 0)
		_overlay.add_child(v)
		_index.append(v)
		for i in 13:
			var ch := char(65 + col * 13 + i)
			var lb := LinkButton.new()
			lb.text = "( %s )" % ch
			lb.underline = LinkButton.UNDERLINE_MODE_NEVER
			lb.add_theme_font_override("font", Book.font("default"))
			lb.add_theme_font_size_override("font_size", int(round(16 * scale_ui)))
			lb.add_theme_color_override("font_color", UI.color("journal_topic"))
			lb.add_theme_color_override("font_hover_color", UI.color("journal_topic_over"))
			lb.add_theme_color_override("font_pressed_color", UI.color("journal_topic_pressed"))
			lb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			lb.pressed.connect(_on_index.bind(ch))
			v.add_child(lb)
	_list_box = ScrollContainer.new()
	_list_box.position = _px(Vector2(8, 40))
	_list_box.size = _px(Vector2(226, 212))
	_list_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay.add_child(_list_box)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_list_box.add_child(_list)
	_button(_overlay, "quests_active", "Show Active", Vector2(76, 15), Vector2(96, 32), _on_show_active)
	_button(_overlay, "quests_all", "Show All", Vector2(83, 15), Vector2(72, 32), _on_show_all)
	var cancel := _button(_overlay, "cancel", "Cancel", Vector2(92, 290), Vector2(56, 32), _on_cancel)
	var quests := _button(_overlay, "quests", "Quests", Vector2(130, 265), Vector2(56, 32), _on_quests)
	var topics := _button(_overlay, "topics", "Topics", Vector2(20, 265), Vector2(56, 32), _on_topics)
	# Zadania na prawo od Anuluj, Tematy na lewo (przy szerokości 64 px) – JournalWindowImpl
	quests.position.x = cancel.position.x + cancel.size.x
	if is_equal_approx(topics.size.x, roundf(64 * scale_ui)) or topics.size.x <= cancel.size.x + 1.0:
		topics.position.x = cancel.position.x - topics.size.x
	else:
		topics.position.x = quests.position.x - topics.size.x

# --- księgi i strony -------------------------------------------------------------------------------------

func _typeset(markup: String) -> Book:
	var fmt := Book.new()
	fmt.image_exists = func(src, w, h): return Book.bookart_path(data_root, src, w, h)
	fmt.format(markup, 240.0 * scale_ui, 320.0 * scale_ui, int(round(16 * scale_ui)), true, scale_ui)
	return fmt

func _paper(fmt: Book) -> Control:
	var paper := Control.new()
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = Vector2(fmt.page_w, maxf(fmt.paper_h, fmt.page_h))
	for e in fmt.elements:
		if e.kind != "text":
			continue
		var l := Label.new()
		l.text = e.text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.position = Vector2(0, e.y)
		l.size = Vector2(fmt.page_w, e.h)
		l.add_theme_font_override("font", Book.font(e.face, e.bold, e.italic))
		l.add_theme_font_size_override("font_size", fmt.font_size)
		l.add_theme_color_override("font_color", e.color)
		l.add_theme_constant_override("line_spacing", 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(l)
	return paper

func _push_book(markup: String) -> void:
	_states.append({"markup": markup, "fmt": _typeset(markup), "page": 0})
	_show_book()

func _replace_book(markup: String) -> void:
	if _states.is_empty():
		_push_book(markup)
		return
	_states[-1] = {"markup": markup, "fmt": _typeset(markup), "page": 0}
	_show_book()

func _show_book() -> void:
	for p in _papers:
		p.queue_free()
	_papers = []
	if _states.is_empty():
		return
	var fmt: Book = _states[-1].fmt
	for side in 2:
		var paper := _paper(fmt)
		_pages[side].add_child(paper)
		_papers.append(paper)
	_btn.close.visible = _states.size() < 2
	_btn.journal.visible = _states.size() >= 2
	update_pages()

## updateShowingPages: strony page i page+1; Dalej – gdy zostały więcej niż 2, Wstecz – gdy page > 0.
func update_pages() -> void:
	if _states.is_empty():
		return
	var st: Dictionary = _states[-1]
	var fmt: Book = st.fmt
	var page := int(st.page)
	var rel: int = fmt.pages.size() - page
	_btn.next.visible = rel > 2 and not _overlay.visible
	_btn.prev.visible = page > 0 and not _overlay.visible
	for side in 2:
		var idx := page + side
		var paper: Control = _papers[side]
		_num[side].text = str(idx + 1)
		_num[side].visible = rel > side
		if idx < fmt.pages.size():
			var pg: Array = fmt.pages[idx]
			paper.position = Vector2(0, -float(pg[0]))
			_pages[side].size = Vector2(fmt.page_w, minf(fmt.page_h, float(pg[1]) - float(pg[0])))
			paper.visible = true
		else:
			paper.visible = false

func page_count() -> int:
	return (_states[-1].fmt as Book).pages.size() if not _states.is_empty() else 0

func current_page() -> int:
	return int(_states[-1].page) if not _states.is_empty() else 0

func next_page() -> void:
	if _states.is_empty():
		return
	var st: Dictionary = _states[-1]
	if (st.fmt as Book).pages.size() - int(st.page) > 2:
		st.page = int(st.page) + 2
		_sound("book page2")
		update_pages()

func prev_page() -> void:
	if _states.is_empty():
		return
	var st: Dictionary = _states[-1]
	if int(st.page) > 0:
		st.page = maxi(0, int(st.page) - 2)
		_sound("book page")
		update_pages()

## Tekst widocznej strony (testy): side 0 – lewa, 1 – prawa.
func visible_text(side := 0) -> String:
	if _states.is_empty():
		return ""
	var fmt: Book = _states[-1].fmt
	var idx := int(_states[-1].page) + side
	if idx >= fmt.pages.size():
		return ""
	var pg: Array = fmt.pages[idx]
	var parts := []
	for e in fmt.elements:
		if e.kind == "text" and float(e.y) + float(e.h) > float(pg[0]) and float(e.y) < float(pg[1]):
			parts.append(e.text)
	return "\n".join(parts)

# --- tryby ---------------------------------------------------------------------------------------------

## setBookMode: księga bez nakładki opcji.
func _book_mode() -> void:
	_topics_mode = false
	_overlay.visible = false
	_btn.options.visible = true
	_show_book()

## notifyOptions: nakładka z indeksem tematów (albo listą zadań, jeśli była otwarta).
func _on_options() -> void:
	_overlay.visible = true
	_btn.options.visible = false
	for n in ["prev", "next", "close", "journal"]:
		_btn[n].visible = false
	for p in _papers:
		p.visible = false
	for n in _num:
		n.visible = false
	if _quest_mode:
		_on_quests()
	else:
		_on_topics()

func _on_topics() -> void:
	_quest_mode = false
	_topics_mode = false
	for v in _index:
		v.visible = true
	_list_box.visible = false
	_btn.quests_all.visible = false
	_btn.quests_active.visible = false
	_sound("book page")

func _clear_list() -> void:
	for c in _list.get_children():
		c.queue_free()

func _list_item(text: String, cb: Callable, active := true) -> void:
	var lb := LinkButton.new()
	lb.text = text
	lb.underline = LinkButton.UNDERLINE_MODE_NEVER
	lb.add_theme_font_override("font", Book.font("default"))
	lb.add_theme_font_size_override("font_size", int(round(16 * scale_ui)))
	var base := "journal_topic" if active else "journal_link"
	lb.add_theme_color_override("font_color", UI.color(base))
	lb.add_theme_color_override("font_hover_color", UI.color(base + "_over"))
	lb.add_theme_color_override("font_pressed_color", UI.color(base + "_pressed"))
	lb.pressed.connect(cb)
	_list.add_child(lb)

## notifyIndexLinkClicked: tematy zaczynające się na literę.
func _on_index(ch: String) -> void:
	for v in _index:
		v.visible = false
	_list_box.visible = true
	_topics_mode = true
	_clear_list()
	_topics = (dialogue._ds().topics as Dictionary).keys().filter(func(k): return dialogue.topic_name(k).to_upper().begins_with(ch))
	_topics.sort_custom(func(a, b): return dialogue.topic_name(a).to_lower() < dialogue.topic_name(b).to_lower())
	for k in _topics:
		_list_item(dialogue.topic_name(k), _on_topic.bind(k))
	_sound("book page")

func _on_topic(topic: String) -> void:
	if _states.size() > 1:
		_replace_book(topic_markup(topic))
	else:
		_push_book(topic_markup(topic))
	_overlay.visible = false
	_btn.options.visible = true
	_btn.journal.visible = true
	_btn.close.visible = false

## notifyQuests: lista zadań – aktywne albo wszystkie (zakończone nieaktywne).
func _on_quests() -> void:
	_quest_mode = true
	for v in _index:
		v.visible = false
	_list_box.visible = true
	_btn.quests_all.visible = not _all_quests
	_btn.quests_active.visible = _all_quests
	_fill_quests()
	_clear_list()
	for g in _quests:
		_list_item(String(g.name), _on_quest.bind(g), not bool(g.finished))
	_sound("book page")

func _on_quest(g: Dictionary) -> void:
	if _states.size() > 1:
		_replace_book(quest_markup(g))
	else:
		_push_book(quest_markup(g))
	_overlay.visible = false
	_btn.options.visible = true
	_btn.journal.visible = true
	_btn.close.visible = false

func _on_show_all() -> void:
	_all_quests = true
	_on_quests()

func _on_show_active() -> void:
	_all_quests = false
	_on_quests()

## notifyCancel: z listy tematów – do indeksu, inaczej – do księgi.
func _on_cancel() -> void:
	if _topics_mode:
		_on_topics()
	else:
		_book_mode()
		_sound("book page")

## notifyJournal: zdjęcie księgi tematu/zadania ze stosu.
func _on_journal() -> void:
	if _states.size() > 1:
		_states.pop_back()
	_book_mode()
	_sound("book page")

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
	if not _all_quests:
		_quests = _quests.filter(func(g): return not g.finished)
	_quests.sort_custom(func(a, b): return String(a.name).to_lower() < String(b.name).to_lower())

# --- otwieranie ------------------------------------------------------------------------------------------

## JournalWindowImpl::onOpen: księga główna od ostatniej rozkładówki.
func open() -> void:
	_build()
	_states = []
	var markup := journal_markup()
	_push_book(markup)
	var st: Dictionary = _states[-1]
	var n: int = (st.fmt as Book).pages.size()
	st.page = maxi(0, n - 1 - ((n - 1) % 2)) if n > 0 else 0
	_book_mode()
	visible = true
	main.gui.push("journal", [self])
	_sound("book open")

func refresh() -> void:
	if visible:
		open()

func close() -> void:
	if not visible:
		return
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	main.gui.remove("journal")
	_sound("book close")

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _sound(id: String) -> void:
	if main != null and main.get("audio") != null and main.audio != null:
		main.audio.play(id)

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_right"):
		next_page()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_left"):
		prev_page()
		get_viewport().set_input_as_handled()
