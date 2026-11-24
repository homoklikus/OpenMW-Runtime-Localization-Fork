extends CanvasLayer
const UI := preload("res://scripts/mw/mw_ui.gd")
## Okno książki i zwoju (etap 10) jak OpenMW BookWindow/ScrollWindow (openmw_book.layout, openmw_scroll.layout):
## książka – dwie strony 250×328 (lewa/prawa, numery stron, poprzednia/następna, „Weź”, „Zamknij”), zwój – jedna
## przewijana kolumna o szerokości 390. Tła i przyciski z tekstur gry (tx_menubook*, scroll), gdy są
## przekonwertowane; bez nich – zastępcze tło i zwykłe przyciski. Rozmiary w pikselach interfejsu × skala
## (wysokość okna / 600). Dźwięki: „book open”/„book close”, „scroll”, „book page”/„book page2”, „Item Book Up”.

signal closed(taken: bool)

const Book := preload("res://scripts/mw/mw_book.gd")

var main
var data_root := ""
var book_id := ""
var is_scroll := false
var take_visible := false
var take_allowed := true          # BookWindow::setInventoryAllowed (GW_Inventory) – przycisk „Weź” tylko z ekwipunkiem

## WindowManager::allow/disallowAll → BookWindow/ScrollWindow::setInventoryAllowed (także przy otwartym oknie).
func set_inventory_allowed(on: bool) -> void:
	take_allowed = on
	if _take != null and is_instance_valid(_take):
		_take.visible = take_visible and take_allowed
var current := 0                   # numer rozkładówki (książka)
var fmt = null
var _root: Control
var _pages: Array = []             # [lewa, prawa] – kontenery przycinające
var _papers: Array = []
var _num: Array = []
var _prev: BaseButton
var _next: BaseButton
var _take: BaseButton
var _close: BaseButton
var _scroll_view: ScrollContainer
var scale_ui := 1.0

const BOOK_SIZE := Vector2(584, 398)
const SCROLL_SIZE := Vector2(512, 372)

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

## Tekst książki: tłumaczenie RLF (BOOK|id|TEXT, ze znacznikami), inaczej tekst z ESM; podstawienia %PCName….
func book_text(id: String, rec: Dictionary) -> String:
	var t := String(rec.get("text", ""))
	if main != null and main.loc != null and main.loc.is_active():
		var e: Array = main.loc.lookup(MWLocalization.key("BOOK", id, "TEXT"), "texts")
		if not e.is_empty() and e[0] is String:
			t = String(e[0])
	if main != null and main.dialogue != null:
		t = main.dialogue.fix_defines(t, {}, false)
	return t

func open(id: String, rec: Dictionary, show_take: bool) -> void:
	book_id = id.to_lower()
	is_scroll = bool(rec.get("scroll", false))
	take_visible = show_take
	if main != null and main.has_method("menu_allowed"):
		take_allowed = main.menu_allowed("inventory")
	current = 0
	scale_ui = 1.0
	var vp := Vector2(1280, 720)
	if get_viewport() != null:
		vp = get_viewport().get_visible_rect().size
	scale_ui = UI.book_scale(vp)                # ScalingLayer „JournalBooks” (600 × 520) jak w OpenMW
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var text := book_text(book_id, rec)
	fmt = Book.new()
	fmt.image_exists = func(src, w, h): return Book.bookart_path(data_root, src, w, h)
	var size := SCROLL_SIZE if is_scroll else BOOK_SIZE
	var win := Control.new()
	win.size = size * scale_ui
	win.position = UI.book_origin(vp, size)        # WindowBase::center na ScalingLayer
	_root.add_child(win)
	if is_scroll:
		_build_scroll(win, text)
	else:
		_build_book(win, text)
	visible = true
	main.gui.push("scroll" if is_scroll else "book", [self])
	_sound("scroll" if is_scroll else "book open")

func _px(v: Vector2) -> Vector2:
	return v * scale_ui

func _tex(rel: String) -> Texture2D:
	var p := data_root.path_join(rel)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	return ImageTexture.create_from_image(img) if img != null else null

func _bg(parent: Control, rel: String, pos: Vector2, size: Vector2, fallback: Color) -> void:
	var t := _tex(rel)
	if t != null:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.position = _px(pos)
		r.size = _px(size)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(r)
	else:
		var c := ColorRect.new()
		c.color = fallback
		c.position = _px(pos)
		c.size = _px(size)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(c)

## Przycisk z teksturami tx_menubook_<nazwa>_idle/over/pressed; bez nich – zwykły przycisk z napisem.
func _button(parent: Control, name: String, label: String, pos: Vector2, size: Vector2, cb: Callable) -> BaseButton:
	var idle := _tex("textures/tx_menubook_%s_idle.png" % name)
	var b: BaseButton
	if idle != null:
		var tb := TextureButton.new()
		tb.texture_normal = idle
		tb.texture_hover = _tex("textures/tx_menubook_%s_over.png" % name)
		tb.texture_pressed = _tex("textures/tx_menubook_%s_pressed.png" % name)
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_SCALE
		b = tb
	else:
		var bt := Button.new()
		bt.text = label
		b = bt
	b.name = name.capitalize() + "Button"
	b.position = _px(pos)
	b.size = _px(size)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _t(gm: String, def: String) -> String:
	return main.dialogue.gmst_text(gm, def) if main != null and main.dialogue != null else def

func _build_book(win: Control, text: String) -> void:
	_bg(win, "textures/tx_menubook.png", Vector2(-71, 0), Vector2(728, 398), Color(0.82, 0.74, 0.58))
	fmt.format(text, 250.0 * scale_ui, 328.0 * scale_ui, int(round(16 * scale_ui)), true, scale_ui)
	_pages = []
	_papers = []
	_num = []
	for x in [30.0, 310.0]:
		var clip := Control.new()
		clip.clip_contents = true
		clip.position = _px(Vector2(x, 15))
		clip.size = _px(Vector2(250, 328))
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(clip)
		_pages.append(clip)
		var paper := _paper()
		clip.add_child(paper)
		_papers.append(paper)
		var num := Label.new()
		num.position = _px(Vector2(x, 358))
		num.size = _px(Vector2(250, 16))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_override("font", Book.font("default"))
		num.add_theme_font_size_override("font_size", int(16 * scale_ui))
		num.add_theme_color_override("font_color", Color.BLACK)
		win.add_child(num)
		_num.append(num)
	_take = _button(win, "take", _t("sTake", "Take"), Vector2(40, 358), Vector2(64, 32), take)
	_prev = _button(win, "prev", _t("sPrev", "Prev"), Vector2(205, 358), Vector2(48, 32), prev_page)
	_next = _button(win, "next", _t("sNext", "Next"), Vector2(330, 358), Vector2(48, 32), next_page)
	_close = _button(win, "close", _t("sClose", "Close"), Vector2(488, 358), Vector2(48, 32), close)
	_take.visible = take_visible and take_allowed
	update_pages()

func _build_scroll(win: Control, text: String) -> void:
	_bg(win, "textures/scroll.png", Vector2.ZERO, SCROLL_SIZE, Color(0.86, 0.8, 0.64))
	fmt.format(text, 390.0 * scale_ui, 235.0 * scale_ui, int(round(16 * scale_ui)), true, scale_ui)
	_scroll_view = ScrollContainer.new()
	_scroll_view.position = _px(Vector2(60, 84))
	_scroll_view.size = _px(Vector2(410, 235))
	_scroll_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(_scroll_view)
	var paper := _paper()
	paper.custom_minimum_size = Vector2(fmt.page_w, maxf(fmt.paper_h, 1.0))
	_scroll_view.add_child(paper)
	_papers = [paper]
	_take = _button(win, "take", _t("sTake", "Take"), Vector2(12, 14), Vector2(128, 32), take)
	_close = _button(win, "close", _t("sClose", "Close"), Vector2(415, 20), Vector2(128, 32), close)
	_take.visible = take_visible and take_allowed

## „Papier”: wszystkie elementy tekstu i obrazy w pozycjach z formatowania (piksele × skala).
func _paper() -> Control:
	var paper := Control.new()
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = Vector2(fmt.page_w, maxf(fmt.paper_h, fmt.page_h))
	for e in fmt.elements:
		if e.kind == "text":
			var l := Label.new()
			l.text = e.text
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.position = Vector2(0, e.y)
			l.size = Vector2(fmt.page_w, e.h)
			l.add_theme_font_override("font", Book.font(e.face, e.bold, e.italic))
			l.add_theme_font_size_override("font_size", fmt.font_size)
			l.add_theme_color_override("font_color", e.color)
			l.add_theme_constant_override("line_spacing", 0)
			l.horizontal_alignment = {"center": HORIZONTAL_ALIGNMENT_CENTER, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(e.align, HORIZONTAL_ALIGNMENT_LEFT)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			paper.add_child(l)
		elif e.kind == "img":
			var img := Image.load_from_file(e.src)
			if img == null:
				continue
			var r := TextureRect.new()
			r.texture = ImageTexture.create_from_image(img)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			var x := 0.0
			if e.align == "center":
				x = (fmt.page_w - e.w) / 2.0
			elif e.align == "right":
				x = fmt.page_w - e.w
			r.position = Vector2(x, e.y)
			r.size = Vector2(e.w, e.h)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			paper.add_child(r)
	return paper

func page_count() -> int:
	return fmt.pages.size() if fmt != null else 0

## updatePages: rozkładówka = strony 2n i 2n+1; papier przesunięty o początek strony i przycięty do jej końca.
func update_pages() -> void:
	if is_scroll or fmt == null:
		return
	var n: int = fmt.pages.size()
	_num[0].text = str(current * 2 + 1)
	_num[1].text = str(current * 2 + 2)
	_next.visible = (current + 1) * 2 < n
	_prev.visible = current != 0
	for side in 2:
		var idx := current * 2 + side
		var paper: Control = _papers[side]
		if idx < n:
			var pg: Array = fmt.pages[idx]
			paper.position = Vector2(0, -float(pg[0]))
			_pages[side].size = Vector2(fmt.page_w, minf(fmt.page_h, float(pg[1]) - float(pg[0])))
			paper.visible = true
			_num[side].visible = true
		else:
			paper.visible = false
			_num[side].visible = false

func next_page() -> void:
	if fmt != null and (current + 1) * 2 < fmt.pages.size():
		current += 1
		_sound("book page2")
		update_pages()

func prev_page() -> void:
	if current > 0:
		current -= 1
		_sound("book page")
		update_pages()

## Tekst widocznych stron (testy).
func visible_text(side := 0) -> String:
	if fmt == null:
		return ""
	if is_scroll:
		return "\n".join(fmt.elements.filter(func(e): return e.kind == "text").map(func(e): return e.text))
	var idx := current * 2 + side
	if idx >= fmt.pages.size():
		return ""
	var pg: Array = fmt.pages[idx]
	var parts := []
	for e in fmt.elements:
		if e.kind == "text" and float(e.y) + float(e.h) > float(pg[0]) and float(e.y) < float(pg[1]):
			parts.append(e.text)
	return "\n".join(parts)

var _taken := false

func take() -> void:
	_taken = true
	_sound("Item Book Up")
	close()

func close() -> void:
	if not visible:
		return
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	main.gui.remove("scroll")
	main.gui.remove("book")
	if not _taken:
		_sound("scroll" if is_scroll else "book close")
	var t := _taken
	_taken = false
	closed.emit(t)

func _sound(id: String) -> void:
	if main != null and main.get("audio") != null and main.audio != null:
		main.audio.play(id)

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_right"):
		next_page()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_left"):
		prev_page()
		get_viewport().set_input_as_handled()
