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
## szczegóły wody poza shaderem, zakładka Lights, Scripts (Lua), Language (język ustawia launcher), pad.
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
	]],
	["Video", []],
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
	layer = 26                       # warstwa Settings
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
	return {"window_border": true, "vsync": true}.get(key)

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
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", roundi(4 * _s))
	win.add_child(box)
	title = Label.new()
	title.text = _t("SettingsWindow", "Options")
	UI.add_head(box, title, _s)
	box.offset_left = 8 * _s
	box.offset_right = -8 * _s
	box.offset_top = 4 * _s
	box.offset_bottom = -8 * _s
	var tabs_row := HBoxContainer.new()
	tabs_row.name = "SettingsTab"
	tabs_row.add_theme_constant_override("separation", 0)
	box.add_child(tabs_row)
	var page_frame := Panel.new()
	page_frame.name = "TabPages"
	page_frame.add_theme_stylebox_override("panel", UI.inner_box())
	page_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_frame.clip_contents = true
	box.add_child(page_frame)
	for i in PAGES.size():
		var b := _tab_button(" %s " % _t(String(PAGES[i][0])), show_page.bind(i))
		b.name = "Tab" + String(PAGES[i][0])
		tabs_row.add_child(b)
		tab_buttons.append(b)
		var pg := _page(String(PAGES[i][0]), PAGES[i][1])
		page_frame.add_child(pg)
		pages.append(pg)
	_build_video(pages[3])
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(bottom)
	ok_button = Button.new()
	ok_button.name = "OkButton"
	ok_button.text = L10n.ctx_text("Interface", "OK", "OK")
	ok_button.pressed.connect(close)                   # onOkButtonClicked → toggleSettingsWindow
	bottom.add_child(ok_button)

func _tab_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _page(name: String, entries: Array) -> Control:
	var pg := VBoxContainer.new()
	pg.name = "Page" + name
	pg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pg.offset_left = 8 * _s
	pg.offset_right = -8 * _s
	pg.offset_top = 8 * _s
	pg.offset_bottom = -8 * _s
	pg.add_theme_constant_override("separation", roundi(6 * _s))
	pg.visible = false
	for e in entries:
		match String(e.t):
			"slider":
				pg.add_child(_slider(e))
			"check":
				pg.add_child(_check_row([e]))
			"checks":
				pg.add_child(_check_row(e.items))
			"controls":
				_build_controls(pg)
			"video":
				_build_video_mode(pg)
	return pg

func _build_video(host: Control) -> void:
	var inner_tabs := HBoxContainer.new()
	inner_tabs.name = "VideoTabs"
	inner_tabs.add_theme_constant_override("separation", 0)
	host.add_child(inner_tabs)
	var frame := Panel.new()
	frame.name = "VideoPages"
	frame.add_theme_stylebox_override("panel", UI.inner_box())
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(frame)
	for i in VIDEO_PAGES.size():
		var b := _tab_button(" %s " % _t(String(VIDEO_PAGES[i][0])), show_video_page.bind(i))
		b.name = "VideoTab" + String(VIDEO_PAGES[i][0])
		inner_tabs.add_child(b)
		video_tab_buttons.append(b)
		var pg := _page("Video" + String(VIDEO_PAGES[i][0]), VIDEO_PAGES[i][1])
		frame.add_child(pg)
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

func _slider(e: Dictionary) -> Control:
	var w := VBoxContainer.new()
	w.name = "Slider_" + String(e.key)
	w.add_theme_constant_override("separation", roundi(2 * _s))
	var head := Label.new()
	head.name = "Caption"
	head.add_theme_color_override("font_color", UI.color("normal"))
	w.add_child(head)
	var sb := HScrollBar.new()
	sb.name = "Scroll"
	var rng := int(e.range)
	sb.min_value = 0
	sb.step = 1
	sb.page = float(e.page)
	sb.max_value = float(rng - 1) + sb.page
	sb.custom_minimum_size = Vector2(0, 18 * _s)
	UI.setup_scroll_bar(sb, _s)
	w.add_child(sb)
	# configureWidgets: pozycja z wartości (ograniczonej do min…max)
	var lo := float(e.min)
	var hi := float(e.max)
	var cur := clampf(_setting_to_omw(e), lo, hi)
	sb.set_value_no_signal(roundf((cur - lo) / (hi - lo) * float(rng - 1)))
	sb.value_changed.connect(_on_slider.bind(e))
	sliders[String(e.key)] = sb
	slider_labels[String(e.key)] = head
	_update_slider_label(e, cur)
	if e.has("lo") or e.has("hi"):
		var marks := Control.new()
		marks.name = "Marks"
		marks.custom_minimum_size = Vector2(0, 16 * _s)
		var l := Label.new()
		l.name = "Low"
		l.text = _t(String(e.get("lo", "")))
		l.add_theme_color_override("font_color", UI.color("normal"))
		marks.add_child(l)
		var r := Label.new()
		r.name = "High"
		r.text = _t(String(e.get("hi", "")))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.set_anchors_preset(Control.PRESET_TOP_WIDE)
		r.add_theme_color_override("font_color", UI.color("normal"))
		marks.add_child(r)
		w.add_child(marks)
	return w

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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(4 * _s))
	for it in items:
		var b := Button.new()
		b.name = "Check_" + String(it.key)
		b.focus_mode = Control.FOCUS_NONE
		b.text = _on_text() if bool(value(String(it.key))) else _off_text()
		b.custom_minimum_size = Vector2(24, 24) * _s
		b.pressed.connect(toggle_check.bind(String(it.key)))
		row.add_child(b)
		checks[String(it.key)] = b
		var l := Label.new()
		l.text = _t(String(it.cap))
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

func _build_controls(pg: Control) -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.inner_box())
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pg.add_child(frame)
	var sc := ScrollContainer.new()
	sc.name = "ControlsBox"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.setup_scroll(sc, _s)
	frame.add_child(sc)
	controls_box = VBoxContainer.new()
	controls_box.name = "Rows"
	controls_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_box.add_theme_constant_override("separation", 0)
	sc.add_child(controls_box)
	var reset := Button.new()
	reset.name = "ResetControlsButton"
	reset.text = _t("ResetControls", "Reset Controls")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_on_reset_bindings)
	pg.add_child(reset)

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
	for a in MWInput.CONFIGURABLE:
		var act := String(a[0])
		if not InputMap.has_action(act):
			continue
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
		b.text = MWInput.binding_name(act, _gm("sMouse", "Mouse"), _none_text())
		b.add_theme_color_override("font_color", UI.color("normal"))
		b.add_theme_color_override("font_hover_color", UI.color("normal_over"))
		b.pressed.connect(start_rebind.bind(act))
		row.add_child(b)
		controls_box.add_child(row)
		binding_buttons[act] = b

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
	var press: bool = (e is InputEventKey and e.pressed and not (e as InputEventKey).echo) or (e is InputEventMouseButton and e.pressed)
	if not press:
		return
	get_viewport().set_input_as_handled()
	if handle_rebind_event(e) != "ignored":
		pass

func handle_rebind_event(e: InputEvent) -> String:
	var r := MWInput.rebind(rebinding, e)
	if r == "ignored":
		return r
	rebinding = ""
	update_controls_box()
	return r

func _on_reset_bindings() -> void:
	main.confirm.ask(_t("ConfirmResetBindings", "Reset all controls to the default?"), func():
		MWInput.reset_defaults()
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(12 * _s))
	pg.add_child(row)
	resolution_list = ItemList.new()
	resolution_list.name = "ResolutionList"
	resolution_list.custom_minimum_size = Vector2(195, 225) * _s
	resolutions = list_resolutions()
	for r in resolutions:
		resolution_list.add_item(resolution_text(r.x, r.y))
	resolution_list.item_selected.connect(_on_resolution_selected)
	row.add_child(resolution_list)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(4 * _s))
	row.add_child(col)
	var l1 := Label.new()
	l1.text = _t("WindowMode")
	col.add_child(l1)
	window_mode_list = OptionButton.new()
	window_mode_list.name = "WindowModeList"
	window_mode_list.add_item(_t("WindowModeFullscreen"))
	window_mode_list.add_item(_t("WindowModeWindowedFullscreen"))
	window_mode_list.add_item(_t("WindowModeWindowed"))
	window_mode_list.custom_minimum_size = Vector2(200, 24) * _s
	window_mode_list.item_selected.connect(_on_window_mode)
	col.add_child(window_mode_list)
	var l2 := Label.new()
	l2.text = _t("VSync")
	col.add_child(l2)
	vsync_list = OptionButton.new()
	vsync_list.name = "VSyncModeList"
	vsync_list.add_item(_off_text())
	vsync_list.add_item(_on_text())
	vsync_list.add_item(_t("VSyncAdaptive"))
	vsync_list.custom_minimum_size = Vector2(200, 24) * _s
	vsync_list.item_selected.connect(_on_vsync)
	col.add_child(vsync_list)
	col.add_child(_check_row([{"key": "window_border", "cap": "WindowBorder"}]))
	window_border_button = checks["window_border"]
	var hint := Label.new()
	hint.text = _t("FrameRateHint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0) * _s
	col.add_child(hint)
	window_mode_hint = Label.new()
	window_mode_hint.name = "WindowModeHint"
	window_mode_hint.text = _t("WindowModeHint")
	col.add_child(window_mode_hint)
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
