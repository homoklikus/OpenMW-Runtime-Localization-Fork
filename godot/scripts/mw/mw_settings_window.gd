extends CanvasLayer
## Okno opcji jak OpenMW 0.51 SettingsWindow (apps/openmw/mwgui/settingswindow.cpp, openmw_settings_window.layout):
##  - okno MW_Window „#{OMWEngine:SettingsWindow}” w trybie GM_Settings, [Windows] settings 0,1; 0,1; 0,8 × 0,8
##    ekranu (najmniej 640 × 550), zakładki: Prefs, Audio, Controls, Video (Video, Detail Level, Water); przycisk OK
##    w prawym dolnym rogu (toggleSettingsWindow), Esc – wyjście z trybu; zmiana działa od razu (apply()), zapis
##    ustawień przy zamknięciu (onClose → saveUser; tu ingame_settings.json, scalany przez launcher);
##  - suwaki MW_HScroll: pozycja 0…Range−1 ↔ min…max (configureWidgets / onSliderChangePosition), nagłówek
##    z wartością (SettingLabelCaption, np. „Difficulty (20)”), podpisy skrajne (Full/None, Fast/Slow, …);
##  - przełączniki MW_Button z napisem #{Interface:On}/#{Interface:Off} (onButtonToggled);
##  - sterowanie: lista akcji (getActionKeySorting) z przypisaniami; kliknięcie – „None”, komunikat stały
##    #{OMWEngine:RebindAction}, następny klawisz/przycisk przypisuje (Esc anuluje); „Reset Controls” z pytaniem
##    #{OMWEngine:ConfirmResetBindings};
##  - wideo: lista rozdzielczości (malejąco, „W × H (a:b)”, potwierdzenie #{OMWEngine:ConfirmResolution}), tryb okna
##    (Fullscreen / Windowed Fullscreen / Windowed – lista wyłączona przy Windowed Fullscreen, ramka okna tylko
##    w oknie), VSync (Off/On/Adaptive), pole widzenia 30…110.
## Pominięte (port ich nie obsługuje – bez atrap): przetwarzanie końcowe, gamma, filtrowanie tekstur, anizotropia,
## szczegóły wody poza shaderem, zakładka Lights, Scripts (Lua), Language (język ustawia launcher), przełącznik
## Mouse/Keyboard – Controller (zmiana przypisań pada); „Enable Controller” działa (mw_gamepad.gd).
## Odległość widzenia: suwak „Large” OpenMW (2500…81920 j., „× komórki”) – ustawienie portu w metrach.

signal closed

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const MWInput := preload("res://scripts/mw/mw_input.gd")

const SENS_BASE := 0.0025          # „camera sensitivity” 1,0 = 0,0025 rad/px (dotychczasowa domyślna czułość)

## Zakładki: wpisy {t: slider|check|checks|controls|video}. Suwak: key, cap (nagłówek), label (SettingLabelCaption),
## range, page, min, max, kind (float|int|cell), lo/hi (podpisy), conv (przeliczenie ustawienia portu).
const PAGES := [
	["Preferences", [
		{"t": "slider", "key": "menu_transparency", "cap": "MenuTransparency", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "lo": "TransparencyFull", "hi": "TransparencyNone", "def": 0.84},
		{"t": "slider", "key": "tooltip_delay", "cap": "MenuHelpDelay", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "lo": "DelayLow", "hi": "DelayHigh", "def": 0.0},
		{"t": "slider", "key": "difficulty", "cap": "Difficulty", "label": "DifficultyValue", "range": 201, "page": 1, "min": -100, "max": 100, "kind": "int", "lo": "DifficultyEasy", "hi": "DifficultyHard", "def": 0},
		{"t": "slider", "key": "actors_processing_range", "cap": "ActorsProcessingRange", "label": "ActorsProcessingRangeValue", "range": 3584, "page": 300, "min": 3584, "max": 7168, "kind": "int", "lo": "DistanceLow", "hi": "DistanceHigh", "def": 7168},
		{"t": "check", "key": "autosave", "cap": "AutoSaveOnResting", "def": true},
		{"t": "check", "key": "best_attack", "cap": "BestAttack", "def": false},
		{"t": "check", "key": "subtitles", "cap": "Subtitles", "def": true},
		{"t": "check", "key": "crosshair", "cap": "Crosshair", "def": true},
	]],
	["Audio", [
		{"t": "slider", "key": "master_volume", "cap": "AudioMaster", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "def": 1.0},
		{"t": "slider", "key": "voice_volume", "cap": "AudioVoice", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "def": 0.8},
		{"t": "slider", "key": "sfx_volume", "cap": "AudioEffects", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "def": 1.0},
		{"t": "slider", "key": "footsteps_volume", "cap": "AudioFootsteps", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "def": 0.2},
		{"t": "slider", "key": "music_volume", "cap": "AudioMusic", "range": 10000, "page": 300, "min": 0.0, "max": 1.0, "kind": "float", "def": 0.5},
	]],
	["Controls", [
		{"t": "controls"},
		{"t": "checks", "items": [{"key": "invert_x", "cap": "InvertXAxis", "def": false}, {"key": "invert_y", "cap": "InvertYAxis", "def": false}]},
		{"t": "slider", "key": "mouse_sensitivity", "cap": "CameraSensitivity", "range": 10000, "page": 300, "min": 0.2, "max": 5.0, "kind": "float", "lo": "SensitivityLow", "hi": "SensitivityHigh", "conv": "sens", "def": SENS_BASE},
		{"t": "check", "key": "enable_controller", "cap": "EnableController", "def": true},
	]],
	["Video", []],
	["Language", [{"t": "language"}]],
]
const VIDEO_PAGES := [
	["Video", [
		{"t": "video"},
		{"t": "slider", "key": "fov", "cap": "", "label": "FieldOfViewValue", "range": 81, "page": 1, "min": 30.0, "max": 110.0, "kind": "float", "lo": "FieldOfViewLow", "hi": "FieldOfViewHigh", "def": 60, "int_store": true},
	]],
	["DetailLevel", [
		{"t": "slider", "key": "view_distance", "cap": "ViewDistance", "label": "ViewDistanceValueCells", "range": 79421, "page": 2048, "min": 2500.0, "max": 81920.0, "kind": "cell", "lo": "DistanceLow", "hi": "DistanceHigh", "conv": "meters", "def": 1500},
	]],
	["Water", [
		{"t": "check", "key": "water_shader", "cap": "WaterShader", "def": true},
	]],
]
const STANDARD_RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "1920x1200", "2560x1080",
	"2560x1440", "3440x1440", "3840x1600", "3840x2160", "5120x1440"]

var main
var _root: Control = null
var win: Panel = null
var title: Label = null
var tab_buttons: Array = []         # przyciski zakładek głównych
var video_tab_buttons: Array = []
var pages: Array = []               # kontrolki stron
var video_pages: Array = []
var current_page := 0
var current_video_page := 0
var ok_button: Button = null
var sliders := {}                   # klucz → HScrollBar
var slider_labels := {}             # klucz → Label nagłówka
var checks := {}                    # klucz → Button On/Off
var controls_box: VBoxContainer = null
var keyboard_mode := true           # mKeyboardMode: lista klawiatury albo pada
var keyboard_switch: Button = null
var controller_switch: Button = null
var binding_buttons := {}           # akcja → Button przypisania
var rebinding := ""                 # akcja oczekująca na klawisz (enableDetectingBindingMode)
var resolution_list: ItemList = null
var resolutions: Array = []         # [Vector2i]
var window_mode_list: OptionButton = null
var vsync_list: OptionButton = null
var window_border_button: Button = null
var window_mode_hint: Label = null
var changed := {}
var _s := 1.0

func _ready() -> void:
	layer = 41                       # warstwa Settings (nad MainMenu = 40, jak openmw_layers.xml)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(key: String, fb := "") -> String:
	return L10n.text(key, fb if not fb.is_empty() else key)

func _gm(key: String, fb: String) -> String:
	if main != null and main.get("dialogue") != null and main.dialogue != null:
		return main.dialogue.gmst_text(key, fb)
	return fb

## Opis akcji: „#{s…}” (GMST) albo „#{OMWEngine:…}”.
func _desc(tag: String) -> String:
	if tag.begins_with("OMWEngine:"):
		return _t(tag.substr(10))
	return _gm(tag, tag.substr(1))

func _on_text() -> String:
	return L10n.ctx_text("Interface", "On", "On")

func _off_text() -> String:
	return L10n.ctx_text("Interface", "Off", "Off")

func _none_text() -> String:
	return L10n.ctx_text("Interface", "None", "None")

## Format ICU z plików l10n: {value}, {value, number, ::.00}, {value, number, :: group-off}, {cells, …}.
static func format_icu(pattern: String, args: Dictionary) -> String:
	var re := RegEx.new()
	re.compile("\\{(\\w+)(?:,\\s*number,\\s*::\\s*([^}]*))?\\}")
	var out := pattern
	for m in re.search_all(pattern):
		var name := m.get_string(1)
		if not args.has(name):
			continue
		var fmt := m.get_string(2).strip_edges()
		var v = args[name]
		var txt := ""
		if fmt.begins_with("."):
			txt = ("%." + str(fmt.length() - 1) + "f") % float(v)
		elif v is int:
			txt = str(v)
		else:
			txt = str(snappedf(float(v), 0.001))
		out = out.replace(m.get_string(0), txt)
	return out

func value(key: String):
	return main.settings.get(key, _default_of(key))

func _default_of(key: String):
	for pg in PAGES + VIDEO_PAGES:
		for e in pg[1]:
			if String(e.get("key", "")) == key:
				return e.def
			for it in e.get("items", []):
				if String(it.key) == key:
					return it.def
	return {"window_border": true, "vsync": true, "gmst_overrides_l10n": true}.get(key)

func is_open() -> bool:
	return visible

# --- budowa okna ------------------------------------------------------------------------------------------

func open() -> void:
	_s = UI.ui_scale()
	changed = {}
	rebinding = ""
	_build()
	visible = true
	if main != null and main.get("gui") != null and main.gui != null:
		main.gui.push("settings", [self], close)       # GM_Settings
	show_page(current_page)
	ok_button.grab_focus()                             # onOpen: setKeyFocusWidget(mOkButton)

func _build() -> void:
	if _root != null:
		_root.queue_free()
	sliders = {}
	slider_labels = {}
	checks = {}
	binding_buttons = {}
	tab_buttons = []
	video_tab_buttons = []
	pages = []
	video_pages = []
	controls_box = null
	_root = Control.new()
	_root.name = "SettingsRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.theme(_s)
	add_child(_root)
	var vp := get_viewport().get_visible_rect().size
	var sz := (vp * 0.8).max(Vector2(640, 550) * _s).min(vp)
	win = Panel.new()
	win.name = "SettingsWindow"
	win.position = ((vp - sz) / 2.0).floor()            # [Windows] settings (0,1; 0,1), center()
	win.size = sz.floor()
	win.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(win)
	# MW_Window: obszar klienta (8, 28, W − 16, H − 36) z paskiem tytułu nad nim
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", roundi(4 * _s))
	win.add_child(box)
	title = Label.new()
	title.text = _t("SettingsWindow", "Options")
	UI.add_head(box, title, _s)
	box.offset_left = 8 * _s
	box.offset_right = -8 * _s
	box.offset_top = 4 * _s
	box.offset_bottom = -8 * _s
	var cw := floorf(win.size.x / _s) - 16.0
	var ch := floorf(win.size.y / _s) - 36.0
	var client := _at(win, Control.new(), 8, 28, cw, ch)
	client.name = "Client"
	client.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TabControl „SettingsTab” (8 8 368 405, Stretch): nagłówek 24, MW_Box od y = 30, TabItem z wcięciem 4
	var tw := cw - 16.0
	var th := ch - 44.0
	var tabc := _at(client, Control.new(), 8, 8, tw, th)
	tabc.name = "SettingsTab"
	tabc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_w = tw - 8.0
	_page_h = th - 36.0
	var names := []
	for i in PAGES.size():
		names.append(_t(String(PAGES[i][0])))
	tab_buttons = _tab_header(tabc, names, show_page)
	var page_frame := _at(tabc, Panel.new(), 0, 30, tw, th - 32.0) as Panel
	page_frame.name = "TabPages"
	page_frame.add_theme_stylebox_override("panel", UI.inner_box())
	page_frame.clip_contents = true
	for i in PAGES.size():
		tab_buttons[i].name = "Tab" + String(PAGES[i][0])
		var pg := _page(String(PAGES[i][0]), PAGES[i][1], _page_w, _page_h)
		_at(page_frame, pg, 4, 4, _page_w, _page_h)
		pages.append(pg)
	_build_video(pages[3])
	# OkButton (320 420 56 24, Right Bottom, ExpandDirection Left)
	ok_button = Button.new()
	ok_button.name = "OkButton"
	ok_button.text = L10n.ctx_text("Interface", "OK", "OK")
	ok_button.pressed.connect(close)                   # onOkButtonClicked → toggleSettingsWindow
	client.add_child(ok_button)
	ok_button.clip_text = true
	var okw := _text_w(ok_button, ok_button.text) + 24.0  # AutoSizedButton: napis + 24, ExpandDirection Left
	ok_button.position = Vector2(cw - 8.0 - okw, ch - 5.0 - 24.0) * _s
	ok_button.size = Vector2(okw, 24) * _s

var _page_w := 360.0
var _page_h := 369.0

## Kontrolka w rodzicu bez kontenera, w jednostkach layoutu (× skala UI).
func _at(parent: Control, c: Control, x: float, y: float, w: float, h: float) -> Control:
	if c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
		(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # NormalText/SandText: TextAlign Left Bottom
	parent.add_child(c)
	c.position = (Vector2(x, y) * _s).round()
	c.size = (Vector2(w, h) * _s).round()
	return c

## Szerokość napisu czcionką motywu (w jednostkach layoutu).
func _text_w(c: Control, text: String) -> float:
	var f := c.get_theme_font("font")
	var fs := c.get_theme_font_size("font_size")
	return ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / _s)

## Nagłówek TabControl (ButtonAutoWidth, MW_Button_RightPadding): przycisk = napis + 12 (ramka 4 + 4, odstęp 4).
func _tab_header(host: Control, names: Array, cb: Callable) -> Array:
	var out := []
	var x := 0.0
	for i in names.size():
		var b := _tab_button(" %s " % names[i], cb.bind(i))
		host.add_child(b)
		var w := _text_w(b, b.text) + 8.0
		b.clip_text = true
		b.position = (Vector2(x, 0) * _s).round()
		b.size = (Vector2(w, 24) * _s).round()
		x += w + 4.0                                     # MW_Button_RightPadding: 4 px odstępu po ramce
		out.append(b)
	return out

func _tab_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _page(name: String, entries: Array, pw: float, ph: float) -> Control:
	var pg := Control.new()
	pg.name = "Page" + name
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pg.visible = false
	var d := ph - 369.0                                 # elementy z align Bottom (Controls)
	var ns := 0
	var nc := 0
	for e in entries:
		match String(e.t):
			"slider":
				var g := _slider_geo(name, ns, d)
				_at(pg, _slider(e, g, pw - g[0] * 2.0), g[0], g[1], pw - g[0] * 2.0, g[6])
				ns += 1
			"check", "checks":
				var y := 0.0
				match name:
					"Preferences":
						y = 250.0 + 30.0 * nc
					"Controls":
						y = (228.0 if String(e.t) == "checks" else 328.0) + d
					_:
						y = 0.0
				var items: Array = e.items if String(e.t) == "checks" else [e]
				_at(pg, _check_row(items), 4.0 if not name.begins_with("Video") else 0.0, y, pw, 28)
				nc += 1
			"controls":
				_build_controls(pg, pw, d)
			"video":
				_build_video_mode(pg)
			"language":
				_build_language(pg)
	return pg

## Geometria suwaka: [x, y grupy, y napisu, wys. napisu, y paska, wys. paska, wys. grupy, y podpisów]
func _slider_geo(page: String, k: int, d: float) -> Array:
	match page:
		"Preferences":
			return [4.0, 4.0 + 60.0 * k, 0.0, 16.0, 20.0, 14.0, 54.0, 38.0]
		"Audio":
			return [4.0, 4.0 + 50.0 * k, 0.0, 18.0, 24.0, 18.0, 42.0, -1.0]
		"Controls":
			return [4.0, 258.0 + d, 0.0, 18.0, 24.0, 18.0, 66.0, 48.0]
		"VideoVideo":
			return [0.0, 238.0, 0.0, 18.0, 24.0, 18.0, 66.0, 48.0]
		"VideoDetailLevel":
			return [0.0, 104.0, 0.0, 18.0, 22.0, 18.0, 62.0, 44.0]
	return [4.0, 4.0 + 60.0 * k, 0.0, 16.0, 20.0, 14.0, 54.0, 38.0]

func _build_video(host: Control) -> void:
	# TabControlInner (4 4 352 390, Stretch): nagłówek 24, strony od y = 28 bez ramki
	var iw := _page_w - 8.0
	var ih := _page_h - 8.0
	var inner := _at(host, Control.new(), 4, 4, iw, ih)
	inner.name = "VideoTabs"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var names := []
	for i in VIDEO_PAGES.size():
		names.append(_t(String(VIDEO_PAGES[i][0])))
	video_tab_buttons = _tab_header(inner, names, show_video_page)
	var frame := _at(inner, Control.new(), 0, 28, iw, ih - 28.0)
	frame.name = "VideoPages"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	for i in VIDEO_PAGES.size():
		video_tab_buttons[i].name = "VideoTab" + String(VIDEO_PAGES[i][0])
		var pg := _page("Video" + String(VIDEO_PAGES[i][0]), VIDEO_PAGES[i][1], iw, ih - 28.0)
		_at(frame, pg, 0, 0, iw, ih - 28.0)
		video_pages.append(pg)
	show_video_page(current_video_page)

func show_page(i: int) -> void:
	current_page = clampi(i, 0, pages.size() - 1)
	for k in pages.size():
		(pages[k] as Control).visible = k == current_page
		(tab_buttons[k] as Button).set_pressed_no_signal(k == current_page)
	if current_page == 2:
		update_controls_box()

func show_video_page(i: int) -> void:
	current_video_page = clampi(i, 0, video_pages.size() - 1)
	for k in video_pages.size():
		(video_pages[k] as Control).visible = k == current_video_page
		(video_tab_buttons[k] as Button).set_pressed_no_signal(k == current_video_page)

# --- suwaki i przełączniki ------------------------------------------------------------------------------

## Wartość ustawienia w jednostkach OpenMW (dla suwaka).
func _setting_to_omw(e: Dictionary) -> float:
	var v := float(value(String(e.key)))
	match String(e.get("conv", "")):
		"sens":
			return v / SENS_BASE
		"meters":
			return v * MWCoords.UNITS_PER_METER
	return v

func _omw_to_setting(e: Dictionary, v: float):
	match String(e.get("conv", "")):
		"sens":
			return v * SENS_BASE
		"meters":
			return int(roundf(v / MWCoords.UNITS_PER_METER))
	if String(e.kind) == "int":
		return int(v)
	if bool(e.get("int_store", false)):
		return int(roundf(v))
	return v

func _slider(e: Dictionary, g: Array, w: float) -> Control:
	var grp := Control.new()
	grp.name = "Slider_" + String(e.key)
	grp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := Label.new()
	head.name = "Caption"
	head.add_theme_color_override("font_color", UI.color("header"))     # NormalText: fontcolour=header
	_at(grp, head, 0, g[2], w, g[3])
	var sb := HScrollBar.new()
	sb.name = "Scroll"
	var rng := int(e.range)
	sb.min_value = 0
	sb.step = 1
	sb.page = float(e.page)
	sb.max_value = float(rng - 1) + sb.page
	UI.setup_scroll_bar(sb, _s)
	sb.custom_minimum_size = Vector2.ZERO
	_at(grp, sb, 0, g[4], w, g[5])
	# configureWidgets: pozycja z wartości (ograniczonej do min…max)
	var lo := float(e.min)
	var hi := float(e.max)
	var cur := clampf(_setting_to_omw(e), lo, hi)
	sb.set_value_no_signal(roundf((cur - lo) / (hi - lo) * float(rng - 1)))
	sb.value_changed.connect(_on_slider.bind(e))
	sliders[String(e.key)] = sb
	slider_labels[String(e.key)] = head
	_update_slider_label(e, cur)
	if (e.has("lo") or e.has("hi")) and float(g[7]) >= 0.0:
		var marks := _at(grp, Control.new(), 0, g[7], w, 16)
		marks.name = "Marks"
		marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.name = "Low"
		l.text = _t(String(e.get("lo", "")))
		l.add_theme_color_override("font_color", UI.color("normal"))
		_at(marks, l, 0, 0, w, 16)
		var r := Label.new()
		r.name = "High"
		r.text = _t(String(e.get("hi", "")))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_theme_color_override("font_color", UI.color("normal"))
		_at(marks, r, 0, 0, w, 16)
	return grp

## updateSliderLabel: SettingLabelCaption z wartością (Cell – w komórkach: wartość / 8192).
func _update_slider_label(e: Dictionary, v: float) -> void:
	var head: Label = slider_labels.get(String(e.key))
	if head == null:
		return
	if e.has("label"):
		var args := {"value": int(v) if String(e.kind) == "int" else v}
		if String(e.kind) == "cell":
			args = {"cells": v / MWCoords.CELL_SIZE}
		head.text = format_icu(_t(String(e.label)), args)
	else:
		head.text = _t(String(e.cap))

## onSliderChangePosition: wartość = min + (max − min) × pozycja / (Range − 1); od razu apply().
func _on_slider(pos: float, e: Dictionary) -> void:
	var rng := int(e.range)
	var lo := float(e.min)
	var hi := float(e.max)
	var v := lo + (hi - lo) * (pos / float(rng - 1))
	if String(e.kind) == "int":
		v = float(int(v))
	_update_slider_label(e, v)
	set_value(String(e.key), _omw_to_setting(e, v))

## Ustawienie suwaka na pozycji (testy, klawiatura).
func set_slider_position(key: String, pos: int) -> void:
	var sb: HScrollBar = sliders.get(key)
	if sb != null:
		sb.value = pos

func _check_row(items: Array) -> Control:
	# HBox: AutoSizedButton 24 × 24 i AutoSizedTextBox (28 4), odstęp 4
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", roundi(4 * _s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in items:
		var b := Button.new()
		b.name = "Check_" + String(it.key)
		b.focus_mode = Control.FOCUS_NONE
		b.text = _on_text() if bool(value(String(it.key))) else _off_text()
		b.custom_minimum_size = Vector2(24, 24) * _s
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # MyGUI HBox: element wyśrodkowany w wysokości wiersza
		b.pressed.connect(toggle_check.bind(String(it.key)))
		row.add_child(b)
		checks[String(it.key)] = b
		var l := Label.new()
		l.text = _t(String(it.cap))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.custom_minimum_size.y = 24 * _s
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", UI.color("normal"))
		row.add_child(l)
	return row

## onButtonToggled: napis On ↔ Off, ustawienie, apply().
func toggle_check(key: String) -> void:
	var b: Button = checks.get(key)
	var on := b == null or b.text != _on_text()
	if b != null:
		b.text = _on_text() if on else _off_text()
	set_value(key, on)

## Zmiana jednej opcji – od razu w grze (SettingsWindow::apply → processChangedSettings).
func set_value(key: String, v) -> void:
	main.settings[key] = v
	changed[key] = v
	main.apply_live_settings()

# --- sterowanie (ControlsBox) ---------------------------------------------------------------------------

func _build_controls(pg: Control, pw: float, d: float) -> void:
	# MW_Box (4 38 352 154, Stretch) ze ScrollView (4 4 344 146); ResetControlsButton (4 198, Left Bottom)
	var frame := _at(pg, Panel.new(), 4, 38, pw - 8.0, 154.0 + d) as Panel
	frame.add_theme_stylebox_override("panel", UI.inner_box())
	var sc := ScrollContainer.new()
	sc.name = "ControlsBox"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.setup_scroll(sc, _s)
	UI.mw_scroll_view(sc, _s)                           # MW_ScrollView
	_at(frame, sc, 4, 4, pw - 16.0, 146.0 + d)
	# HBox (4 4 360 28, Spacing 4): KeyboardButton / ControllerButton (AutoSizedButton, stan wybrany)
	var x := 4.0
	keyboard_switch = Button.new()
	keyboard_switch.name = "KeyboardButton"
	keyboard_switch.text = _t("MouseAndKeyboard", "Mouse/Keyboard")
	controller_switch = Button.new()
	controller_switch.name = "ControllerButton"
	controller_switch.text = _t("Controller", "Controller")
	for b in [keyboard_switch, controller_switch]:
		b.toggle_mode = true
		b.clip_text = true
		pg.add_child(b)
		var bw := _text_w(b, b.text) + 24.0
		b.position = (Vector2(x, 6) * _s).round()
		b.size = (Vector2(bw, 24) * _s).round()
		x += bw + 4.0
	keyboard_switch.pressed.connect(set_keyboard_mode.bind(true))
	controller_switch.pressed.connect(set_keyboard_mode.bind(false))
	keyboard_switch.set_pressed_no_signal(keyboard_mode)
	controller_switch.set_pressed_no_signal(not keyboard_mode)
	controls_box = VBoxContainer.new()
	controls_box.name = "Rows"
	controls_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_box.add_theme_constant_override("separation", 0)
	sc.add_child(controls_box)
	var reset := Button.new()
	reset.name = "ResetControlsButton"
	reset.text = _t("ResetControls", "Reset Controls")
	reset.pressed.connect(_on_reset_bindings)
	pg.add_child(reset)
	reset.clip_text = true
	var rw := _text_w(reset, reset.text) + 24.0          # AutoSizedButton: napis + 24
	reset.position = (Vector2(4, 198.0 + d) * _s).round()
	reset.size = (Vector2(rw, 24) * _s).round()

## updateControlsBox: wiersz = opis akcji (z lewej) i przypisanie (z prawej, klikalne); usuwa komunikat stały.
func update_controls_box() -> void:
	if controls_box == null:
		return
	for c in controls_box.get_children():
		controls_box.remove_child(c)
		c.queue_free()
	binding_buttons = {}
	if main != null and main.has_method("remove_static_message_box"):
		main.remove_static_message_box()
	var h := roundf((16 + 2) * _s)
	var descs := {}
	for a in MWInput.CONFIGURABLE:
		descs[String(a[0])] = String(a[1])
	var acts: Array = MWInput.CONFIGURABLE.map(func(a): return String(a[0])) if keyboard_mode else MWInput.CONTROLLER_SORTING
	for act in acts:
		if not InputMap.has_action(act) or not descs.has(act):
			continue
		var a := [act, descs[act]]
		var row := HBoxContainer.new()
		row.name = "Row_" + act
		row.custom_minimum_size = Vector2(0, h)
		var l := Label.new()
		l.name = "Desc"
		l.text = _desc(String(a[1]))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", UI.color("normal"))
		row.add_child(l)
		var b := Button.new()
		b.name = "Bind"
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.text = MWInput.binding_name(act, _gm("sMouse", "Mouse"), _none_text()) if keyboard_mode \
			else MWInput.controller_binding_name(act, _none_text())
		b.add_theme_color_override("font_color", UI.color("normal"))
		b.add_theme_color_override("font_hover_color", UI.color("normal_over"))
		b.pressed.connect(start_rebind.bind(act))
		row.add_child(b)
		controls_box.add_child(row)
		binding_buttons[act] = b

## onKeyboardSwitchClicked / onControllerSwitchClicked.
func set_keyboard_mode(on: bool) -> void:
	keyboard_switch.set_pressed_no_signal(on)
	controller_switch.set_pressed_no_signal(not on)
	if keyboard_mode == on:
		return
	keyboard_mode = on
	rebinding = ""
	update_controls_box()

## onRebindAction: napis „None”, komunikat stały #{OMWEngine:RebindAction}, oczekiwanie na klawisz.
func start_rebind(action: String) -> void:
	rebinding = action
	var b: Button = binding_buttons.get(action)
	if b != null:
		b.text = _none_text()
	if main != null and main.has_method("static_message_box"):
		main.static_message_box(_t("RebindAction", "Press a key or button to rebind this control."))

## Wejście w trybie przypisywania (BindingsListener): Esc – anulowanie, zastrzeżone – bez zmian, inne – przypisanie;
## notifyInputActionBound → updateControlsBox.
func _input(e: InputEvent) -> void:
	if not visible or rebinding.is_empty():
		return
	var press: bool = (e is InputEventKey and e.pressed and not (e as InputEventKey).echo) or (e is InputEventMouseButton and e.pressed) \
		or (e is InputEventJoypadButton and e.pressed) or e is InputEventJoypadMotion
	if not press:
		return
	get_viewport().set_input_as_handled()
	if handle_rebind_event(e) != "ignored":
		pass

## Esc przerywa w obu trybach; w trybie Controller klawiatura i mysz pomijane (mDetectingKeyboard = false),
## w trybie klawiatury – pad.
func handle_rebind_event(e: InputEvent) -> String:
	var r := ""
	if e is InputEventKey and MWInput.code_of(e) == KEY_ESCAPE:
		r = "cancel"
	elif keyboard_mode:
		r = "ignored" if (e is InputEventJoypadButton or e is InputEventJoypadMotion) else MWInput.rebind(rebinding, e)
	else:
		r = MWInput.rebind_controller(rebinding, e) if (e is InputEventJoypadButton or e is InputEventJoypadMotion) else "ignored"
	if r == "ignored":
		return r
	rebinding = ""
	update_controls_box()
	return r

func _on_reset_bindings() -> void:
	main.confirm.ask(_t("ConfirmResetBindings", "Reset all controls to the default?"), func():
		if keyboard_mode:
			MWInput.reset_defaults()
		else:
			MWInput.reset_controller_defaults()       # resetToDefaultControllerBindings
		update_controls_box())

# --- wideo ----------------------------------------------------------------------------------------------

## Misc::getResolutionText: „W × H (a:b)” ze zwyczajowymi nazwami proporcji.
static func resolution_text(x: int, y: int) -> String:
	var a := x
	var b := y
	while b != 0:
		var t := b
		b = a % b
		a = t
	if a == 0:
		return ""
	var xa := x / a
	var ya := y / a
	var flipped := ya > xa
	if flipped:
		var t2 := xa
		xa = ya
		ya = t2
	if (xa == 683 and ya == 384) or (xa == 85 and ya == 48):
		xa = 16
		ya = 9
	elif (xa == 49 and ya == 36) or (xa == 39 and ya == 29):
		xa = 4
		ya = 3
	elif xa == 8 and ya == 5:
		xa = 16
		ya = 10
	elif xa == 5 and ya == 3:
		xa = 15
		ya = 9
	else:
		var ratio := float(xa) / float(ya)
		if ratio >= 21.0 / 9.0 and ratio < 22.0 / 9.0:
			xa = 21
			ya = 9
	if flipped:
		var t3 := xa
		xa = ya
		ya = t3
	return "%d × %d (%d:%d)" % [x, y, xa, ya]

## Rozdzielczości: standardowe nie większe od ekranu i natywna ekranu, malejąco (sortResolutions).
func list_resolutions() -> Array:
	var scr := Vector2i(3840, 2160)
	if DisplayServer.get_name() != "headless":
		scr = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out := []
	for r in STANDARD_RESOLUTIONS + ["%dx%d" % [scr.x, scr.y]]:
		var p := String(r).split("x")
		var v := Vector2i(int(p[0]), int(p[1]))
		if v.x <= scr.x and v.y <= scr.y and not out.has(v):
			out.append(v)
	out.sort_custom(func(a, b): return a.x > b.x or (a.x == b.x and a.y > b.y))
	return out

func _build_video_mode(pg: Control) -> void:
	# strona „Video” TabControlInner: ResolutionList (0 4 195 225), prawa kolumna od x = 207
	resolution_list = ItemList.new()
	resolution_list.name = "ResolutionList"
	resolutions = list_resolutions()
	for r in resolutions:
		resolution_list.add_item(resolution_text(r.x, r.y))
	resolution_list.item_selected.connect(_on_resolution_selected)
	_at(pg, resolution_list, 0, 4, 195, 225)          # MW_List: ramka w skórce listy
	var l1 := Label.new()
	l1.text = _t("WindowMode")
	l1.add_theme_color_override("font_color", UI.color("header"))
	_at(pg, l1, 207, 4, 250, 18)
	window_mode_list = OptionButton.new()
	window_mode_list.name = "WindowModeList"
	window_mode_list.add_item(_t("WindowModeFullscreen"))
	window_mode_list.add_item(_t("WindowModeWindowedFullscreen"))
	window_mode_list.add_item(_t("WindowModeWindowed"))
	window_mode_list.item_selected.connect(_on_window_mode)
	_at(pg, window_mode_list, 207, 24, 200, 24)
	var l2 := Label.new()
	l2.text = _t("VSync")
	l2.add_theme_color_override("font_color", UI.color("header"))
	_at(pg, l2, 207, 54, 250, 18)
	vsync_list = OptionButton.new()
	vsync_list.name = "VSyncModeList"
	vsync_list.add_item(_off_text())
	vsync_list.add_item(_on_text())
	vsync_list.add_item(_t("VSyncAdaptive"))
	vsync_list.item_selected.connect(_on_vsync)
	_at(pg, vsync_list, 207, 76, 200, 24)              # HBox (207, 74, 400, 28): pole 24 px wyśrodkowane
	_at(pg, _check_row([{"key": "window_border", "cap": "WindowBorder"}]), 207, 108, 300, 28)
	window_border_button = checks["window_border"]
	var hint := Label.new()
	hint.text = _t("FrameRateHint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UI.color("normal"))
	_at(pg, hint, 207, 174, 300, 32)
	window_mode_hint = Label.new()
	window_mode_hint.name = "WindowModeHint"
	window_mode_hint.text = _t("WindowModeHint")
	window_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	window_mode_hint.add_theme_color_override("font_color", UI.color("normal"))
	_at(pg, window_mode_hint, 207, 216, 300, 32)
	update_window_mode_settings()
	var vs := bool(value("vsync"))
	vsync_list.select(2 if vs and bool(main.settings.get("vsync_adaptive", false)) else (1 if vs else 0))

## Fullscreen (0) = wyłączny pełny ekran, Windowed Fullscreen (1) = pełny ekran Godota, Windowed (2).
func window_mode_index() -> int:
	match String(main.settings.get("window_mode", "windowed")):
		"exclusive":
			return 0
		"fullscreen":
			return 1
	return 2

## highlightCurrentResolution + updateWindowModeSettings.
func update_window_mode_settings() -> void:
	var idx := window_mode_index()
	window_mode_list.select(idx)
	var cur := String(main.settings.get("resolution", "1280x720")).split("x")
	resolution_list.deselect_all()
	for i in resolutions.size():
		if cur.size() == 2 and resolutions[i] == Vector2i(int(cur[0]), int(cur[1])):
			resolution_list.select(i)
	for i in resolution_list.item_count:
		resolution_list.set_item_disabled(i, idx == 1)
	window_mode_hint.visible = idx == 1
	window_border_button.disabled = idx != 2

func _on_window_mode(i: int) -> void:
	set_value("window_mode", ["exclusive", "fullscreen", "windowed"][i])
	update_window_mode_settings()
	main.apply_display()

func _on_vsync(i: int) -> void:
	main.settings["vsync_adaptive"] = i == 2
	changed["vsync_adaptive"] = i == 2
	set_value("vsync", i != 0)

## onResolutionSelected: pytanie #{OMWEngine:ConfirmResolution}; OK – zmiana, Anuluj – zaznaczenie przywrócone.
func _on_resolution_selected(i: int) -> void:
	if resolution_list.is_item_disabled(i):
		return
	var r: Vector2i = resolutions[i]
	main.confirm.ask(_t("ConfirmResolution", "New resolution will be applied immediately. Do you want to continue?"),
		func():
			set_value("resolution", "%dx%d" % [r.x, r.y])
			main.apply_display(),
		func(): update_window_mode_settings())

# --- język (zakładka Language) --------------------------------------------------------------------------

var primary_language: OptionButton = null
var secondary_language: OptionButton = null
var languages: Array = []           # kody z plików l10n (bez „gmst”), posortowane

## Dostępne języki: nazwy plików *.yaml we wszystkich kontekstach l10n poza udawanym „gmst” (SettingsWindow).
func available_languages() -> Array:
	var out := []
	for ctx in DirAccess.get_directories_at(L10n.DIR):
		for f in DirAccess.get_files_at(L10n.DIR.path_join(ctx)):
			if f.get_extension() == "yaml":
				var n := f.get_basename()
				if n != "gmst" and not out.has(n):
					out.append(n)
	out.sort()
	return out

static func language_name(code: String) -> String:
	var n := TranslationServer.get_locale_name(code)
	return n if not n.is_empty() else code

## Preferowane języki z ustawienia (domyślnie „en”).
func current_locales() -> PackedStringArray:
	var out := PackedStringArray()
	for p in String(main.settings.get("preferred_locales", "en")).split(",", false):
		if not p.strip_edges().is_empty():
			out.append(p.strip_edges())
	if out.is_empty():
		out.append("en")
	return out

func _build_language(pg: Control) -> void:
	# openmw_settings_window.layout, TabItem Language
	var note := Label.new()
	note.text = _t("LanguageNote")
	note.add_theme_color_override("font_color", UI.color("normal"))
	_at(pg, note, 4, 4, 300, 16)                       # AutoSizedTextBox: wysokość napisu
	var l1 := Label.new()
	l1.text = _t("PrimaryLanguage")
	l1.tooltip_text = _t("PrimaryLanguageTooltip")
	l1.mouse_filter = Control.MOUSE_FILTER_PASS
	l1.add_theme_color_override("font_color", UI.color("header"))
	_at(pg, l1, 4, 28, 250, 18)
	primary_language = OptionButton.new()
	primary_language.name = "PrimaryLanguage"
	_at(pg, primary_language, 4, 52, 250, 24)
	var l2 := Label.new()
	l2.text = _t("SecondaryLanguage")
	l2.tooltip_text = _t("SecondaryLanguageTooltip")
	l2.mouse_filter = Control.MOUSE_FILTER_PASS
	l2.add_theme_color_override("font_color", UI.color("header"))
	_at(pg, l2, 262, 28, 250, 18)
	secondary_language = OptionButton.new()
	secondary_language.name = "SecondaryLanguage"
	_at(pg, secondary_language, 262, 52, 250, 24)
	# updateLanguage: lista języków, „None” na początku drugiej listy, zaznaczenie z preferred locales
	languages = available_languages()
	var cur := current_locales()
	secondary_language.add_item(_none_text())
	secondary_language.select(0)
	for i in languages.size():
		var nm := language_name(String(languages[i]))
		primary_language.add_item(nm)
		secondary_language.add_item(nm)
		if languages[i] == cur[0]:
			primary_language.select(i)
		if cur.size() > 1 and languages[i] == cur[1]:
			secondary_language.select(i + 1)
	primary_language.item_selected.connect(func(i: int): _on_language(0, i))
	secondary_language.item_selected.connect(func(i: int): _on_language(1, i))
	_at(pg, _check_row([{"key": "gmst_overrides_l10n", "cap": "GmstOverridesL10n"}]), 4, 84, 500, 32)
	var gb: Button = checks["gmst_overrides_l10n"]
	gb.pressed.connect(_restart_notice)

## onLanguageChanged: komunikat ChangeRequiresRestart, zapis listy języków (drugi „None” → tylko pierwszy).
func _on_language(priority: int, idx: int) -> void:
	_restart_notice()
	var cur := current_locales()
	while cur.size() <= priority:
		cur.append("en")
	var code := ""
	if priority == 0:
		code = String(languages[idx]) if idx >= 0 and idx < languages.size() else ""
	elif idx > 0:
		code = String(languages[idx - 1])
	if not code.is_empty():
		cur[priority] = code
	else:
		cur.resize(1)
	set_value("preferred_locales", ",".join(cur))

func _restart_notice() -> void:
	if main != null and main.has_method("show_message_box"):
		main.show_message_box(_t("ChangeRequiresRestart", "This change requires a restart to take effect."),
			[L10n.ctx_text("Interface", "OK", "OK")], Callable(), true)

# --- zamknięcie -----------------------------------------------------------------------------------------

## onClose: zapis ustawień (saveUser) i przypisań (saveBindings).
func close() -> void:
	if not visible:
		return
	visible = false
	rebinding = ""
	if main != null and main.has_method("remove_static_message_box"):
		main.remove_static_message_box()
	if not changed.is_empty():
		main.save_ingame_settings(changed)
	if _root != null:
		_root.queue_free()
		_root = null
	if main != null and main.get("gui") != null and main.gui != null and main.gui.contains("settings"):
		main.gui.remove("settings")
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if visible and rebinding.is_empty() and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu")):
		close()
		get_viewport().set_input_as_handled()
