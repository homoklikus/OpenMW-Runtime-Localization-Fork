extends CanvasLayer
## Ustawienia w grze (etap 10; Esc → Ustawienia): dźwięk (głośności jak OpenMW [Sound], napisy), sterowanie
## (czułość myszy, odwrócenie osi, pole widzenia) i grafika (odległość widzenia, cienie, mgła, V-Sync, limit FPS).
## Zmiany działają od razu; „Zapisz” zapisuje je atomowo do ingame_settings.json obok ustawień z launchera –
## launcher scala je z profilem przy następnym uruchomieniu (mwcore.launch.merge_ingame). „Anuluj” przywraca.
## Te same klucze i zakresy co schemat launchera (converter/mwcore/settings.py).

signal closed

const OPTIONS := [
	["audio", "Dźwięk"],
	["master_volume", "Głośność ogólna", "float", 0.0, 1.0, 0.05, 1.0],
	["music_volume", "Muzyka", "float", 0.0, 1.0, 0.05, 0.5],
	["voice_volume", "Głosy", "float", 0.0, 1.0, 0.05, 0.8],
	["sfx_volume", "Efekty", "float", 0.0, 1.0, 0.05, 1.0],
	["footsteps_volume", "Kroki", "float", 0.0, 1.0, 0.05, 0.2],
	["subtitles", "Napisy kwestii", "bool", 0, 0, 0, true],
	["controls", "Sterowanie"],
	["mouse_sensitivity", "Czułość myszy", "float", 0.0005, 0.01, 0.0005, 0.0025],
	["invert_y", "Odwróć oś Y", "bool", 0, 0, 0, false],
	["fov", "Pole widzenia [°]", "int", 40, 110, 1, 60],
	["graphics", "Grafika"],
	["view_distance", "Odległość widzenia [m]", "int", 200, 6000, 100, 1500],
	["shadows", "Jakość cieni", "choice", ["off", "low", "medium", "high"], 0, 0, "medium"],
	["water_shader", "Woda z falami (shader)", "bool", 0, 0, 0, true],
	["fog", "Mgła i pogoda", "bool", 0, 0, 0, true],
	["vsync", "Synchronizacja pionowa", "bool", 0, 0, 0, true],
	["max_fps", "Limit FPS (0 = brak)", "int", 0, 360, 10, 0],
]
const CHOICE_LABELS := {"off": "wyłączone", "low": "niska", "medium": "średnia", "high": "wysoka"}

var main
var _root: Control
var _controls := {}                   # klucz → kontrolka
var _initial := {}
var changed := {}

func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func value(key: String):
	for o in OPTIONS:
		if o.size() > 2 and o[0] == key:
			return main.settings.get(key, o[6])
	return main.settings.get(key)

func open() -> void:
	_initial = {}
	changed = {}
	for o in OPTIONS:
		if o.size() > 2:
			_initial[o[0]] = value(o[0])
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var grid: GridContainer = null
	_controls = {}
	for o in OPTIONS:
		if o.size() == 2:
			var h := Label.new()
			h.text = String(o[1])
			h.add_theme_font_size_override("font_size", 18)
			box.add_child(h)
			grid = GridContainer.new()
			grid.columns = 2
			box.add_child(grid)
			continue
		var l := Label.new()
		l.text = String(o[1])
		l.custom_minimum_size = Vector2(240, 0)
		grid.add_child(l)
		grid.add_child(_control(o))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = "Anuluj"
	cancel.pressed.connect(cancel_changes)
	row.add_child(cancel)
	var save := Button.new()
	save.text = "Zapisz"
	save.pressed.connect(save_and_close)
	row.add_child(save)
	visible = true
	await get_tree().process_frame
	if is_instance_valid(panel):
		panel.position = ((get_viewport().get_visible_rect().size - panel.size) / 2.0).floor()

func _control(o: Array) -> Control:
	var key := String(o[0])
	var v = value(key)
	var c: Control
	match String(o[2]):
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(v)
			cb.toggled.connect(func(on): set_value(key, on))
			c = cb
		"choice":
			var ob := OptionButton.new()
			var choices: Array = o[3]
			for ch in choices:
				ob.add_item(String(CHOICE_LABELS.get(ch, ch)))
			ob.select(maxi(0, choices.find(String(v))))
			ob.item_selected.connect(func(i): set_value(key, choices[i]))
			c = ob
		_:
			var hb := HBoxContainer.new()
			var sl := HSlider.new()
			sl.min_value = float(o[3])
			sl.max_value = float(o[4])
			sl.step = float(o[5])
			sl.value = float(v)
			sl.custom_minimum_size = Vector2(200, 0)
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lab := Label.new()
			lab.custom_minimum_size = Vector2(60, 0)
			var is_int: bool = o[2] == "int"
			var fmt := func(x: float) -> String:
				return str(int(x)) if is_int else ("%.4f" % x if float(o[4]) < 0.1 else "%d%%" % int(round(x * 100)))
			lab.text = fmt.call(float(v))
			sl.value_changed.connect(func(x):
				lab.text = fmt.call(x)
				set_value(key, int(x) if is_int else x))
			hb.add_child(sl)
			hb.add_child(lab)
			c = hb
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls[key] = c
	return c

## Zmiana jednej opcji – od razu w grze.
func set_value(key: String, v) -> void:
	main.settings[key] = v
	changed[key] = v
	main.apply_live_settings()

func cancel_changes() -> void:
	for k in _initial:
		main.settings[k] = _initial[k]
	changed = {}
	main.apply_live_settings()
	close()

func save_and_close() -> void:
	main.save_ingame_settings(changed)
	close()

func close() -> void:
	visible = false
	if _root != null:
		_root.queue_free()
		_root = null
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if visible and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu")):
		cancel_changes()
		get_viewport().set_input_as_handled()
