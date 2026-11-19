extends CanvasLayer
## Menu główne jak OpenMW MainMenu (mwgui/mainmenu.cpp): przyciski-obrazy z tekstur gry gracza
## (textures/menu_<id>.dds, _over, _pressed), kolejność i widoczność wg stanu gry (updateMenu):
##   gra trwa:  Wróć, Nowa gra, Zapisz (CharGenState −1 i zapis dozwolony), Wczytaj (gdy są zapisy), Opcje, Wyjdź
##   brak gry:  Nowa gra, Wczytaj (gdy są zapisy), Opcje, Zasługi (film mw_credits.bik), Wyjdź
## Brak gry: tło textures/menu_morrowind.dds (proporcje 4:3, czarne pasy), przyciski przy dolnej krawędzi (24 px),
## wersja w prawym dolnym rogu; animowane tło tylko, gdy w danych jest video/menu_background.bik (w Morrowindzie
## go nie ma – OpenMW pokazuje wtedy obraz). W grze: przyciski na środku, bez tła (to samo menu = menu pauzy).
## Nowa gra / Wyjdź w trakcie gry – potwierdzenie. Dźwięk „Menu Click”. Esc zamyka menu tylko w trakcie gry.

const L10n := preload("res://scripts/mw/mw_l10n.gd")
const UI := preload("res://scripts/mw/mw_ui.gd")
const BUTTONS := ["return", "newgame", "savegame", "loadgame", "options", "credits", "exitgame"]

var main = null
var version_text := "OpenMWGodot"
var _root: Control = null
var _bg: Control = null
var _bg_video: VideoStreamPlayer = null
var _box: Control = null
var _version: Label = null
var buttons := {}                  # id → TextureButton (albo Button, gdy brak tekstur)
var shown: Array = []              # widoczne przyciski w kolejności (testy)

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	get_viewport().size_changed.connect(func():
		if visible:
			update_menu())

func is_open() -> bool:
	return visible

func open() -> void:
	visible = true
	update_menu()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	visible = false
	_show_background(false)

func _scale() -> float:
	return UI.ui_scale()

func _tex(name: String) -> Texture2D:
	return UI.texture("textures/" + name)

## updateMenu.
func update_menu() -> void:
	if _root == null:
		_root = Control.new()
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_root)
		_box = Control.new()
		_root.add_child(_box)
		_version = Label.new()
		_version.name = "VersionText"
		_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_version.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_version.add_theme_font_override("font", UI.font())
		_version.add_theme_color_override("font_color", UI.color("normal"))
		_root.add_child(_version)
	var state := String(main.game_state)
	var nogame := state == "nogame"
	_show_background(nogame)
	_version.text = version_text
	_version.visible = nogame
	_version.add_theme_font_size_override("font_size", roundi(12 * _scale()))
	_version.position = get_viewport().get_visible_rect().size - _version.get_combined_minimum_size() - Vector2(8, 4)
	var want := []
	if state == "running":
		want.append("return")
	want.append("newgame")
	if state == "running" and main.saving_allowed():
		want.append("savegame")
	if main.saves != null and main.saves.has_any():
		want.append("loadgame")
	want.append("options")
	if nogame:
		want.append("credits")
	want.append("exitgame")
	shown = want
	var sc := _scale()
	var maxw := 0.0
	for id in BUTTONS:
		if not buttons.has(id):
			buttons[id] = _make_button(id)
			_box.add_child(buttons[id])
		buttons[id].visible = false
	var sizes := {}
	for id in BUTTONS:
		var s := _button_size(id)
		sizes[id] = s
		maxw = maxf(maxw, s.x)
	var cur_h := 0.0
	for id in want:
		var b: Control = buttons[id]
		b.visible = true
		var s: Vector2 = sizes[id]
		b.position = Vector2(floorf((maxw - s.x) / 2.0), cur_h) * sc
		b.size = s * sc
		cur_h += s.y
	var vp := get_viewport().get_visible_rect().size
	_box.size = Vector2(maxw, cur_h) * sc
	if nogame:
		_box.position = Vector2(vp.x / 2.0 - maxw * sc / 2.0, vp.y - cur_h * sc - 24.0 * sc).floor()
	else:
		_box.position = ((vp - _box.size) / 2.0).floor()

## Rozmiar przycisku jak MainMenu::updateMenu: tekstury o wysokości 64 (skala = h/64), przycięcie 16 px u dołu.
func _button_size(id: String) -> Vector2:
	var t := _tex("menu_" + id)
	if t == null:
		return Vector2(200, 32)
	var scale := t.get_height() / 64.0
	return Vector2(floorf(t.get_width() / scale), floorf(t.get_height() / scale - 16.0))

func _crop(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	var scale := t.get_height() / 64.0
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(0, 0, t.get_width(), floorf(t.get_height() - 16.0 * scale))
	return at

const FALLBACK_LABELS := {"return": "Wróć", "newgame": "Nowa gra", "savegame": "Zapisz grę", "loadgame": "Wczytaj grę",
	"options": "Opcje", "credits": "Zasługi", "exitgame": "Wyjdź"}

func _make_button(id: String) -> Control:
	var t := _tex("menu_" + id)
	var b: BaseButton
	if t != null:
		var tb := TextureButton.new()
		tb.texture_normal = _crop(t)
		tb.texture_hover = _crop(_tex("menu_" + id + "_over"))
		tb.texture_pressed = _crop(_tex("menu_" + id + "_pressed"))
		tb.texture_focused = tb.texture_hover
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_SCALE
		b = tb
	else:                              # dane syntetyczne bez tekstur menu – zwykły przycisk z podpisem
		var bb := Button.new()
		bb.text = String(FALLBACK_LABELS[id])
		bb.theme = UI.theme(_scale())
		b = bb
	b.name = id
	b.pressed.connect(func(): on_button(id))
	return b

## onButtonClicked.
func on_button(id: String) -> void:
	if main.audio != null:
		main.audio.play("Menu Click")
	match id:
		"return":
			main.close_main_menu()
		"credits":
			main.video.play("mw_credits.bik", true)
		"exitgame":
			if main.game_state == "nogame":
				main.request_quit()
			else:
				main.confirm.ask(L10n.text("QuitGameConfirmation"), func(): main.request_quit())
		"newgame":
			if main.game_state == "nogame":
				main.close_main_menu()
				main.new_game()
			else:
				main.confirm.ask(L10n.text("NewGameConfirmation"), func():
					main.close_main_menu()
					main.new_game())
		"loadgame", "savegame":
			main.save_dialog.open(id == "loadgame")
		"options":
			main.open_settings()

## showBackground: obraz menu (albo animowane tło, gdy jest video/menu_background).
func _show_background(show: bool) -> void:
	if not show:
		if _bg != null:
			_bg.queue_free()
			_bg = null
			_bg_video = null
		return
	if _bg != null:
		_layout_bg()
		return
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = black
	add_child(_bg)
	move_child(_bg, 0)
	var vpath: String = main.video.resolve("menu_background.bik") if main.video != null else ""
	if not vpath.is_empty():
		_bg_video = VideoStreamPlayer.new()
		var st := VideoStreamTheora.new()
		st.file = vpath
		_bg_video.stream = st
		_bg_video.expand = true
		_bg_video.loop = true           # MenuVideo::run – po końcu od nowa
		_bg_video.process_mode = Node.PROCESS_MODE_ALWAYS
		black.add_child(_bg_video)
		_bg_video.play()
	else:
		var tr := TextureRect.new()
		tr.name = "Background"
		tr.texture = _tex("menu_morrowind")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		black.add_child(tr)
	_layout_bg()

## BackgroundImage::setBackgroundImage(fixedRatio = true, stretch = false): 4:3 w środku ekranu.
func _layout_bg() -> void:
	if _bg == null or _bg.get_child_count() == 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var c := _bg.get_child(0) as Control
	var aspect := 4.0 / 3.0
	var s := Vector2(vp.y * aspect, vp.y) if vp.x / vp.y > aspect else Vector2(vp.x, vp.x / aspect)
	c.size = s.floor()
	c.position = ((vp - s) / 2.0).floor()

func background_kind() -> String:
	if _bg == null:
		return ""
	return "video" if _bg_video != null else "image"

## MainMenu::exit: Esc zamyka menu tylko, gdy gra trwa.
func _unhandled_input(e: InputEvent) -> void:
	if not visible or main == null:
		return
	if e.is_action_pressed("menu") or (e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_ESCAPE):
		if (main.save_dialog != null and main.save_dialog.visible) or main.confirm.is_open():
			return
		if main.settings_window_open():
			main.close_settings()
		elif main.game_state == "running":
			main.close_main_menu()
		get_viewport().set_input_as_handled()

## StateManager::update: czas gry liczony w każdej klatce (także w menu i pauzie), poza stanem bez gry.
func _process(dt: float) -> void:
	if main != null and String(main.game_state) != "nogame":
		main.time_played += dt
