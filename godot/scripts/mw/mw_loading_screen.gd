extends CanvasLayer
## Ekran ładowania jak OpenMW LoadingScreen (mwgui/loadingscreen.cpp, openmw_loading_screen.layout):
## * loadingOn/loadingOff zagnieżdżone (licznik), etykieta (setLabel) i pasek postępu (setProgressRange,
##   increaseProgress) w okienku przy dolnej krawędzi (szer. ≥ 300, 8 px od dołu),
## * bez gry (menu główne → nowa gra/wczytanie): tapeta – losowy obraz z Splash/ (proporcje 4:3), zmieniany co 5 s,
## * w grze (przejście między komórkami): zamrożona ostatnia klatka obrazu i okienko z paskiem; pokazywane dopiero
##   po 50 ms (initialDelay) pomniejszonych o postęp – szybkie ładowanie nie miga ekranem,
## * rysowanie w trakcie ładowania z limitem klatek (needToDrawLoadingScreen, 120 kl./s) – Godot ładuje komórki
##   synchronicznie, więc klatkę rysujemy wprost (RenderingServer.force_draw), jak OpenMW w draw().
## Etykieta „ważna” (zapisywanie): przy ładowaniu tak szybkim, że ekranu nie pokazano – komunikat w grze.

const UI := preload("res://scripts/mw/mw_ui.gd")
const INITIAL_DELAY := 0.05
const TARGET_FPS := 120.0

var main = null
var data_roots: Array = []
var splash: Array = []               # ścieżki obrazów Splash/
var nested := 0
var show_wallpaper := false
var label := ""
var important := false
var progress := 0
var progress_range := 1
var shown_count := 0                 # testy: ile razy ekran faktycznie narysowano
var last_splash := ""
var _on_time := 0.0
var _fader_t := 0.0                  # czas ostatniego kroku zaciemnienia w trakcie synchronicznego ładowania
var _last_render := -1.0
var _last_wallpaper := -1.0
var _root: Control = null
var _splash_rect: TextureRect = null
var _scene_rect: TextureRect = null
var _box: PanelContainer = null
var _label: Label = null
var _bar: ProgressBar = null
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	rng.randomize()

func _process(_dt: float) -> void:
	if main != null and main.has_method("_update_reveal"):
		main._update_reveal()                # odsłonięcie świata po przejściu – także w pauzie

## findSplashScreens: splash/*.(tga|dds|png…) – konwerter zapisuje PNG.
func find_splash_screens() -> void:
	splash.clear()
	for r in data_roots:
		var d := DirAccess.open(String(r).path_join("splash"))
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "bmp", "tga", "dds"]:
				var p := String(r).path_join("splash").path_join(f)
				if not splash.any(func(x): return String(x).get_file().to_lower() == f.to_lower()):
					splash.append(p)
	splash.sort()
	if splash.is_empty():
		push_warning("Brak obrazów ekranu ładowania (Splash/)")

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(black)
	_scene_rect = TextureRect.new()
	_scene_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scene_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(_scene_rect)
	_splash_rect = TextureRect.new()
	_splash_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(_splash_rect)
	var sc := UI.ui_scale()
	_box = PanelContainer.new()
	_box.name = "LoadingBox"
	_box.theme = UI.theme(sc)
	_root.add_child(_box)
	var v := VBoxContainer.new()
	_box.add_child(v)
	_label = Label.new()
	_label.name = "LoadingText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", UI.color("normal").lightened(0.15))
	v.add_child(_label)
	_bar = UI.progress_bar("normal", sc)
	_bar.name = "ProgressBar"
	_bar.custom_minimum_size = Vector2(260, 6) * sc
	v.add_child(_bar)

## LoadingScreen::loadingOn.
func loading_on() -> void:
	nested += 1
	if nested > 1 and visible:
		return
	_build()
	_on_time = _now()
	_fader_t = _on_time
	show_wallpaper = main != null and String(main.game_state) == "nogame"
	visible = false                   # pokazujemy dopiero przy pierwszym rysowaniu (needToDrawLoadingScreen)
	if show_wallpaper:
		change_wallpaper()
	else:
		_splash_rect.visible = false
		_scene_rect.visible = true
		_scene_rect.texture = null
		var vt := get_viewport().get_texture()
		if vt != null and DisplayServer.get_name() != "headless":
			var img := vt.get_image()             # kopia ostatniej klatki (CopyFramebufferToTextureCallback)
			if img != null and not img.is_empty():
				_scene_rect.texture = ImageTexture.create_from_image(img)
	set_progress_range(1)
	draw()

## Zasłonięcie sceny zamrożoną klatką do końca odsłaniania (main._begin_reveal) – także gdy ładowanie było tak
## szybkie, że ekranu nie narysowano (bez okienka z paskiem, jeśli nic nie trwało dłużej niż initialDelay).
func hold() -> void:
	if nested <= 0 or show_wallpaper:
		return
	visible = true
	if _box != null and _last_render < _on_time:
		_box.visible = false
	_layout()

## LoadingScreen::loadingOff.
func loading_off() -> void:
	nested -= 1
	if nested > 0:
		return
	nested = 0
	if _last_render < _on_time and important:
		if main != null and main.has_method("_toast"):
			main._toast(label)                   # ładowanie tak szybkie, że ekranu nie było – komunikat
	important = false
	visible = false
	if _box != null:
		_box.visible = true
	if _scene_rect != null:
		_scene_rect.texture = null

func set_label(text: String, is_important := false) -> void:
	label = text
	important = is_important
	if _label != null:
		_label.text = text
	_layout()

func set_progress_range(r: int) -> void:
	progress_range = maxi(r, 0) + 1
	progress = 0
	if _bar != null:
		_bar.max_value = progress_range
		_bar.value = 0

func increase_progress(n := 1) -> void:
	progress = mini(progress + n, progress_range - 1)
	if _bar != null:
		_bar.value = progress
	draw()

func set_progress(v: int) -> void:
	progress = mini(v, progress_range - 1)
	if _bar != null:
		_bar.value = progress
	draw()

## changeWallpaper: losowy obraz Splash/, 4:3.
func change_wallpaper() -> void:
	_scene_rect.visible = false
	_scene_rect.texture = null
	if splash.is_empty():
		_splash_rect.visible = false
		return
	var p := String(splash[rng.randi_range(0, splash.size() - 1)])
	last_splash = p
	var img := Image.load_from_file(p)
	_splash_rect.texture = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	_splash_rect.visible = true
	_layout()

func _layout() -> void:
	if _root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var aspect := 4.0 / 3.0
	var s := Vector2(vp.y * aspect, vp.y) if vp.x / vp.y > aspect else Vector2(vp.x, vp.x / aspect)
	_splash_rect.size = s.floor()
	_splash_rect.position = ((vp - s) / 2.0).floor()
	var sc := UI.ui_scale()
	_box.custom_minimum_size = Vector2(maxf(300.0 * sc, _label.get_combined_minimum_size().x + 40 * sc), 0)
	_box.reset_size()
	var bs := _box.get_combined_minimum_size()
	if main != null and main.has_method("message_count") and main.message_count() > 0:
		_box.position = ((vp - bs) / 2.0).floor()
	else:
		_box.position = Vector2(floorf(vp.x / 2.0 - bs.x / 2.0), vp.y - bs.y - 8.0 * sc)

## needToDrawLoadingScreen.
func need_draw() -> bool:
	var t := _now()
	if t <= _last_render + 1.0 / TARGET_FPS:
		return false
	var already := _last_render > _on_time
	var diff := t - _on_time
	if not already:
		diff -= float(progress) / float(maxi(progress_range, 1)) * 0.1
	if not show_wallpaper and diff < INITIAL_DELAY:
		return false
	return true

## LoadingScreen::draw – w trakcie synchronicznego ładowania klatka rysowana od razu.
func draw() -> void:
	if nested <= 0 or not need_draw():
		return
	if show_wallpaper and _now() > _last_wallpaper + 5.0:
		_last_wallpaper = _now()
		change_wallpaper()
	visible = true
	if _box != null:
		_box.visible = true
	_layout()
	_last_render = _now()
	shown_count += 1
	# OpenMW: klatki ekranu ładowania przechodzą przez pętlę zdarzeń – ScreenFader (onFrameStart) postępuje z
	# rzeczywistym czasem, więc fadeScreenOut z początku przejścia przy długim ładowaniu dochodzi do czerni
	if main != null and main.get("fader") != null:
		main.fader.step(_now() - _fader_t)
	_fader_t = _now()
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(true)
