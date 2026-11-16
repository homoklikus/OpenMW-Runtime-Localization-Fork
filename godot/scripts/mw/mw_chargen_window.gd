extends CanvasLayer
## Minimalny kreator postaci (etap 4): imię, rasa, płeć, głowa, włosy, klasa, znak zodiaku; podgląd statystyk
## liczonych jak w OpenMW (MWCharacter.build/derived). Pełny kreator w stylu Morrowinda – etap 10.

signal created(stats: Dictionary)

var character          # MWCharacter
var loc = null
var name_edit: LineEdit
var race_opt: OptionButton
var sex_opt: OptionButton
var head_opt: OptionButton
var hair_opt: OptionButton
var class_opt: OptionButton
var sign_opt: OptionButton
var preview: RichTextLabel
var _races := []
var _classes := []
var _signs := []
var _heads := []
var _hairs := []

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.name = "CharGen"
	panel.custom_minimum_size = Vector2(980, 600)
	add_child(panel)
	var root := HBoxContainer.new()
	panel.add_child(root)
	var form := GridContainer.new()
	form.columns = 2
	form.custom_minimum_size = Vector2(420, 0)
	root.add_child(form)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Imię postaci"
	_row(form, "Imię", name_edit)
	race_opt = _row(form, "Rasa", OptionButton.new())
	sex_opt = _row(form, "Płeć", OptionButton.new())
	head_opt = _row(form, "Głowa", OptionButton.new())
	hair_opt = _row(form, "Włosy", OptionButton.new())
	class_opt = _row(form, "Klasa", OptionButton.new())
	sign_opt = _row(form, "Znak zodiaku", OptionButton.new())
	var ok := Button.new()
	ok.text = "Utwórz postać"
	ok.pressed.connect(_create)
	form.add_child(Control.new())
	form.add_child(ok)
	preview = RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.custom_minimum_size = Vector2(540, 560)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(preview)
	sex_opt.add_item("Mężczyzna")
	sex_opt.add_item("Kobieta")
	for o in [race_opt, sex_opt]:
		o.item_selected.connect(func(_i): _fill_heads(); _update())
	for o in [head_opt, hair_opt, class_opt, sign_opt]:
		o.item_selected.connect(func(_i): _update())
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	visible = false

func _row(grid: GridContainer, label: String, ctl: Control) -> Control:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctl)
	return ctl

func _name(file: String, rtype: String, id: String) -> String:
	var r: Dictionary = character.records.record(file, id)
	var fb := String(r.get("name", id))
	if loc != null and loc.has_method("is_active") and loc.is_active():
		return loc.plain(loc.key(rtype, id, "FNAM"), fb)
	return fb

func open(defaults: Dictionary = {}) -> void:
	_races = character.playable("race")
	_classes = character.playable("class")
	_signs = character.playable("birthsign")
	for pair in [[race_opt, _races, "race", "RACE"], [class_opt, _classes, "class", "CLAS"], [sign_opt, _signs, "birthsign", "BSGN"]]:
		var o: OptionButton = pair[0]
		o.clear()
		for id in pair[1]:
			o.add_item(_name(pair[2], pair[3], id))
	_select(race_opt, _races, String(defaults.get("race", "")))
	_select(class_opt, _classes, String(defaults.get("class", "")))
	_select(sign_opt, _signs, String(defaults.get("birthsign", "")))
	sex_opt.select(1 if defaults.get("female", false) else 0)
	name_edit.text = String(defaults.get("name", ""))
	_fill_heads()
	_update()
	visible = true
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func _select(o: OptionButton, ids: Array, id: String) -> void:
	var i := ids.find(id.to_lower())
	if o.item_count > 0:
		o.select(maxi(i, 0))

func _fill_heads() -> void:
	if race_opt.selected < 0 or _races.is_empty():
		return
	var hh: Dictionary = character.heads_hairs(_races[race_opt.selected], sex_opt.selected == 1)
	_heads = hh.heads
	_hairs = hh.hairs
	for pair in [[head_opt, _heads], [hair_opt, _hairs]]:
		var o: OptionButton = pair[0]
		o.clear()
		for id in pair[1]:
			o.add_item(String(id))
		if o.item_count > 0:
			o.select(0)

func choice() -> Dictionary:
	return {"name": name_edit.text.strip_edges(),
		"race": _races[race_opt.selected] if race_opt.selected >= 0 and _races.size() > 0 else "",
		"female": sex_opt.selected == 1,
		"head": _heads[head_opt.selected] if head_opt.selected >= 0 and _heads.size() > 0 else "",
		"hair": _hairs[hair_opt.selected] if hair_opt.selected >= 0 and _hairs.size() > 0 else "",
		"class": _classes[class_opt.selected] if class_opt.selected >= 0 and _classes.size() > 0 else "",
		"birthsign": _signs[sign_opt.selected] if sign_opt.selected >= 0 and _signs.size() > 0 else ""}

func _update() -> void:
	var st: Dictionary = character.build(choice())
	var d: Dictionary = character.derived(st)
	var attr_names: Array = character.records.records_index().get("attributes", [])
	var skill_names: Array = character.skill_names()
	var t := "[b]Atrybuty[/b]\n"
	for i in 8:
		var base := int(st.attributes[i])
		var mod := int(d.attributes[i])
		t += "%s: %d%s\n" % [String(attr_names[i]) if i < attr_names.size() else str(i), mod, (" (%d)" % base) if mod != base else ""]
	t += "\n[b]Zdrowie[/b] %d   [b]Magia[/b] %d   [b]Kondycja[/b] %d\n\n[b]Umiejętności[/b]\n" % [
			int(d.health.modified), int(d.magicka.modified), int(d.fatigue.modified)]
	var order := range(27)
	order.sort_custom(func(x, y): return d.skills[x] > d.skills[y])
	var cells := []
	for i in order:
		cells.append("%s %d" % [String(skill_names[i]) if i < skill_names.size() else str(i), int(d.skills[i])])
	t += ",  ".join(cells)
	if not (st.spells as Array).is_empty():
		t += "\n\n[b]Zdolności i moce[/b]: " + ", ".join((st.spells as Array).map(func(s): return _name("spell", "SPEL", s)))
	preview.text = t

func _create() -> void:
	var st: Dictionary = character.build(choice())
	if String(st.name).is_empty():
		st["name"] = "Przybysz"
	visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	created.emit(st)
