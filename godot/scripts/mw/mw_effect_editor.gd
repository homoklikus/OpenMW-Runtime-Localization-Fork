extends RefCounted
## EffectEditorBase + EditEffectDialog z OpenMW 0.51 (apps/openmw/mwgui/spellcreationdialog.cpp) – wspólna
## część okien zaklinania i tworzenia czarów:
##  - lista znanych efektów (AvailableEffects, MWList): efekty ze zwykłych czarów gracza (ST_Spell) z flagą
##    AllowSpellmaking / AllowEnchanting, bez powtórzeń, posortowane po nazwie;
##  - kliknięcie efektu: ≥ 8 efektów – sNotifyMessage28; efekt bez dozwolonego zasięgu – nic; TargetSkill /
##    TargetAttribute – SelectSkillDialog / SelectAttributeDialog, potem EditEffectDialog (bez sprawdzania
##    powtórzeń, jak w OpenMW); inny efekt już na liście – sOnetypeEffectMessage; inaczej EditEffectDialog;
##  - EditEffectDialog (openmw_edit_effect.layout, MW_DialogNoTransp 362 × 310): efekt dodawany od razu
##    (eventEffectAdded), zasięg Self → Touch → Target wg flag (stały efekt – tylko Self), suwaki
##    siły 1–100 (maks. ≥ min.), czasu 1–1440, obszaru 0–50; pola MagnitudeBox / DurationBox / AreaBox
##    układane kolejno od y = 80 (updateBoxes); Anuluj – nowy efekt usuwany, edytowany przywracany;
##    Usuń (tylko przy edycji) – usunięcie;
##  - lista użytych efektów (UsedEffects): przycisk z MW_EffectImage w wierszu 24 px, klik – edycja.
## mode: "enchanting" | "spellmaking"; on_changed – notifyEffectsChanged okna.

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const MWList := preload("res://scripts/mw/mw_list.gd")
const Box := preload("res://scripts/mw/mw_box_layout.gd")

const SCHOOL_GMST := ["sSchoolAlteration", "sSchoolConjuration", "sSchoolDestruction", "sSchoolIllusion",
	"sSchoolMysticism", "sSchoolRestoration"]

var main
var ui = null                 # mw_chargen_ui (skala, teksty)
var host: Node = null         # węzeł, do którego trafiają okna modalne
var mode := "spellmaking"
var effects: Array = []       # ENAMstruct: {"effect", "skill", "attribute", "range", "area", "duration", "min", "max"}
var constant := false
var on_changed: Callable
var available = null          # MWList
var used_canvas: Control = null
var known: Array = []         # indeksy efektów w kolejności listy (mButtonMapping)
var selected := 0             # mSelectedEffect
var dialog: Control = null    # EditEffectDialog (okno)
var sub: Control = null       # SelectSkill/SelectAttribute (okno)
var editing := false
var old_effect := {}
var effect_rec := {}          # rekord MGEF edytowanego efektu
var _cur := {}                # mEffect
var _w := {}                  # kontrolki okna edycji

func _init(game_main, chargen_ui, host_node: Node, editor_mode: String) -> void:
	main = game_main
	ui = chargen_ui
	host = host_node
	mode = editor_mode

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func _magic():
	return main.magic

func _msg(text: String) -> void:
	main._toast(text)

func effect_name(index: int) -> String:
	var mg: Dictionary = _magic().effect(index)
	var n := String(mg.get("name", str(index)))
	return _t("sEffect" + n, n)

func effect_tooltip(index: int) -> String:
	var mg: Dictionary = _magic().effect(index)
	var sch := int(mg.get("school", -1))
	var school := _t(SCHOOL_GMST[sch], "") if sch >= 0 and sch < SCHOOL_GMST.size() else ""
	var lines := [effect_name(index), "%s: %s" % [_t("sSchool", "School"), school]]
	var d := String(mg.get("description", ""))
	if not d.is_empty():
		lines.append(d)
	return "\n".join(lines)

# --- EffectEditorBase ------------------------------------------------------------------------------------

func setup(list, canvas: Control) -> void:
	available = list
	used_canvas = canvas
	available.item_clicked.connect(available_clicked)

## startEditing: znane efekty z czarów gracza (tylko ST_Spell), flaga zależna od trybu, sortowanie po nazwie.
func start_editing() -> void:
	var st: Dictionary = main.player_stats()
	var flag := "spellmaking" if mode == "spellmaking" else "enchanting"
	var found := []
	for sid in st.get("spells", []):
		var sp: Dictionary = _magic().records.record("spell", String(sid))
		if sp.is_empty() or int(sp.get("spell_type", 0)) != 0:
			continue
		for e in sp.get("effects", []):
			var idx := int(e.get("effect", -1))
			var mg: Dictionary = _magic().effect(idx)
			if mg.is_empty() or not bool(mg.get(flag, false)):
				continue
			if not idx in found:
				found.append(idx)
	found.sort_custom(func(a, b): return effect_name(a) < effect_name(b))
	known = found
	available.clear()
	for idx in known:
		available.add_item(effect_name(idx))
	for i in known.size():
		var b = available._items[i].button
		if b != null:
			# createMagicEffectToolTip
			if main.get("tooltips") != null and main.tooltips != null:
				(b as Control).set_meta("mw_tip", main.tooltips.magic_effect_tip(int(known[i])))
			else:
				(b as Control).tooltip_text = effect_tooltip(int(known[i]))
	effects = []
	update_effects_view()

func _allowed(mg: Dictionary) -> Array:
	return [bool(mg.get("cast_self", false)) or constant,
		bool(mg.get("cast_touch", false)) and not constant,
		bool(mg.get("cast_target", false)) and not constant]

## onAvailableEffectClicked.
func available_clicked(i: int) -> void:
	if effects.size() >= 8:
		_msg(_t("sNotifyMessage28", "You can only have 8 effects."))
		return
	if i < 0 or i >= known.size():
		return
	var idx := int(known[i])
	var mg: Dictionary = _magic().effect(idx)
	var al := _allowed(mg)
	if not (al[0] or al[1] or al[2]):
		return
	if bool(mg.get("target_skill", false)):
		_open_select_skill(idx)
	elif bool(mg.get("target_attribute", false)):
		_open_select_attribute(idx)
	else:
		for e in effects:
			if int(e.get("effect", -1)) == idx:
				_msg(_t("sOnetypeEffectMessage", "This effect is already on the list."))
				return
		new_effect(idx)

func _modified(e: Dictionary) -> void:
	if selected >= 0 and selected < effects.size():
		effects[selected] = e.duplicate()
	update_effects_view()

func _removed() -> void:
	if selected >= 0 and selected < effects.size():
		effects.remove_at(selected)
	update_effects_view()

func _added(e: Dictionary) -> void:
	effects.append(e.duplicate())
	selected = effects.size() - 1
	update_effects_view()

## setConstantEffect: włączenie stałego efektu ustawia zasięg wszystkich efektów na Self.
func set_constant(c: bool) -> void:
	if not constant and c:
		for e in effects:
			e["range"] = 0
	constant = c

## updateEffectsView: przycisk 24 px na efekt (MW_EffectImage), szerokość płótna – najdłuższy wiersz.
func update_effects_view() -> void:
	if used_canvas != null:
		for c in used_canvas.get_children():
			used_canvas.remove_child(c)
			c.queue_free()
		var y := 0.0
		var wmax := 0.0
		for i in effects.size():
			var e: Dictionary = effects[i]
			var mg: Dictionary = _magic().effect(int(e.get("effect", -1)))
			var text: String = ui.effect_text(e, constant)
			var w: float = 24.0 + ceilf(ui.text_width(text) / ui.sc)
			var b := Button.new()
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
				b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			b.position = Vector2(0, y) * ui.sc
			b.size = Vector2(w, 24) * ui.sc
			b.name = "Effect%d" % i
			used_canvas.add_child(b)
			var line: Control = ui.effect_line(b, 0, 0, w, String(mg.get("icon", "")), text)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for c2 in line.get_children():
				(c2 as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			var k := i
			b.pressed.connect(func(): edit_effect(k))
			y += 24.0
			wmax = maxf(wmax, w)
		used_canvas.custom_minimum_size = Vector2(wmax, y) * ui.sc
	if on_changed.is_valid():
		on_changed.call()

# --- EditEffectDialog ------------------------------------------------------------------------------------

func is_dialog_open() -> bool:
	return dialog != null and is_instance_valid(dialog)

func _close_dialog() -> void:
	if is_dialog_open():
		CU.close(dialog)
	dialog = null
	_w = {}

func _build_dialog() -> void:
	_close_dialog()
	dialog = ui.modal(host, 362, 310, true)
	dialog.name = "EditEffectDialog"
	var c: Control = dialog.get_meta("client")
	var img := TextureRect.new()
	img.name = "EffectImage"
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_SCALE
	ui.at(img, c, 8, 12, 16, 16)
	var nm: Label = ui.label(c, 36, 8, 400, 24, "", "header")
	nm.name = "EffectName"
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# AutoSizedTextBox poza Boxem: rozmiar = rozmiar tekstu (notifySizeChange)
	var bl := Box.new(ui.sc)
	var rt := _t("sRange", "Range")
	ui.label(c, 8, 36, bl.text_size(rt).x, 16, rt, "header")
	var rb: Button = ui.button("", range_clicked)
	rb.name = "RangeButton"
	c.add_child(rb)
	rb.position = Vector2(130, 36) * ui.sc
	_w = {"image": img, "name": nm, "range": rb, "client": c}
	# MagnitudeBox (8, 80, 400, 70)
	var mb: Control = ui.group(c, 8, 80, 400, 70)
	mb.name = "MagnitudeBox"
	var mt := _t("sMagnitude", "Magnitude")
	ui.label(mb, 0, 0, bl.text_size(mt).x, 16, mt, "header")
	_w["mag_min_val"] = _value_label(mb, 122, 0, "MagnitudeMinValue")
	_w["mag_min"] = _slider(mb, 122, 20, 100, "MagnitudeMinSlider", mag_min_changed)
	_w["mag_max_val"] = _value_label(mb, 122, 32, "MagnitudeMaxValue")
	_w["mag_max"] = _slider(mb, 122, 52, 100, "MagnitudeMaxSlider", mag_max_changed)
	_w["mag_box"] = mb
	# DurationBox (8, 153, 400, 40)
	var db: Control = ui.group(c, 8, 153, 400, 40)
	db.name = "DurationBox"
	var dt := _t("sDuration", "Duration")
	var dl: Label = ui.label(db, 0, 20, bl.text_size(dt).x, 16, dt, "header")
	dl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_w["dur_val"] = _value_label(db, 122, 0, "DurationValue")
	_w["dur"] = _slider(db, 122, 20, 1440, "DurationSlider", duration_changed)
	_w["dur_box"] = db
	# AreaBox (8, 197, 400, 40)
	var ab: Control = ui.group(c, 8, 197, 400, 40)
	ab.name = "AreaBox"
	var at2 := _t("sArea", "Area")
	var al: Label = ui.label(ab, 0, 20, bl.text_size(at2).x, 16, at2, "header")
	al.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_w["area_val"] = _value_label(ab, 122, 0, "AreaValue")
	_w["area"] = _slider(ab, 122, 20, 51, "AreaSlider", area_changed)
	_w["area_box"] = ab
	# przyciski: HBox (8, 266, 336, 24) – Spacer, sDelete, OK, Anuluj
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(row)
	var del: Button = ui.button(_t("sDelete", "Delete"), delete_clicked)
	del.name = "DeleteButton"
	var ok: Button = ui.button(L10n.ctx_text("Interface", "OK", "OK"), ok_clicked)
	ok.name = "OkButton"
	var cn: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), cancel_clicked)
	cn.name = "CancelButton"
	for b in [del, ok, cn]:
		row.add_child(b)
	_w["delete"] = del
	_w["row"] = {"type": "hbox", "control": row, "children": [{"type": "spacer"},
		{"type": "button", "control": del}, {"type": "button", "control": ok}, {"type": "button", "control": cn}]}
	_layout_buttons()

func _layout_buttons() -> void:
	var bl := Box.new(ui.sc)
	bl.place(_w.row, Rect2(8, 266, 336, 24))

func _value_label(parent: Control, x: float, y: float, nm: String) -> Label:
	var l: Label = ui.label(parent, x, y, 210, 20, "0", "sand", HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.name = nm
	return l

## MW_HScroll: Range N (pozycje 0..N−1), Page 1, MoveToClick false.
func _slider(parent: Control, x: float, y: float, range_n: int, nm: String, cb: Callable) -> HScrollBar:
	var s := HScrollBar.new()
	s.name = nm
	s.min_value = 0
	s.max_value = range_n
	s.page = 1
	s.step = 1
	ui.at(s, parent, x, y, 210, 13)
	s.value_changed.connect(func(v): cb.call(int(v)))
	return s

func _set_pos(key: String, pos: int) -> void:
	(_w[key] as HScrollBar).set_value_no_signal(pos)

func _range_caption() -> void:
	var r := int(_cur.get("range", 0))
	(_w.range as Button).text = _t(["sRangeSelf", "sRangeTouch", "sRangeTarget"][clampi(r, 0, 2)],
		["Self", "Touch", "Target"][clampi(r, 0, 2)])
	var b := _w.range as Button
	b.size = Vector2(ui.text_width(b.text) + 24 * ui.sc, 24 * ui.sc)

func _set_magic_effect(idx: int) -> void:
	effect_rec = _magic().effect(idx)
	(_w.image as TextureRect).texture = UI.icon(String(effect_rec.get("icon", ""))) if effect_rec.has("icon") else null
	(_w.name as Label).text = effect_name(idx)
	_cur["effect"] = idx
	update_boxes()

## newEffect: zasięg Self, gdy niedozwolony – Touch, gdy i ten – Target, potem onRangeButtonClicked
## (przejście do następnego dozwolonego); wartości 1, 1, 1, obszar 0; efekt trafia na listę od razu.
func new_effect(idx: int, skill := -1, attribute := -1) -> void:
	_build_dialog()
	_cur = {"effect": idx, "skill": -1, "attribute": -1, "range": 0, "area": 0, "duration": 1, "min": 1, "max": 1}
	_set_magic_effect(idx)
	editing = false
	(_w.delete as Control).visible = false
	_layout_buttons()
	var al := _allowed(effect_rec)
	_cur.range = 0
	if not al[0]:
		_cur.range = 1
	if not al[1]:
		_cur.range = 2
	_added(_cur)
	if skill >= 0:
		_cur.skill = skill
		_modified(_cur)
	if attribute >= 0:
		_cur.attribute = attribute
		_modified(_cur)
	range_clicked()
	for k in ["mag_min", "mag_max", "area", "dur"]:
		_set_pos(k, 0)
	(_w.dur_val as Label).text = "1"
	(_w.mag_min_val as Label).text = "1"
	(_w.mag_max_val as Label).text = _t("sTo", "-") + " 1"
	(_w.area_val as Label).text = "0"

## editEffect.
func edit_effect(i: int) -> void:
	if i < 0 or i >= effects.size():
		return
	selected = i
	var e: Dictionary = effects[i]
	_build_dialog()
	_cur = e.duplicate()
	old_effect = e.duplicate()
	_set_magic_effect(int(e.effect))
	editing = true
	(_w.delete as Control).visible = true
	_layout_buttons()
	_set_pos("mag_min", int(e.min) - 1)
	_set_pos("mag_max", int(e.max) - 1)
	_set_pos("area", int(e.area))
	_set_pos("dur", int(e.duration) - 1)
	_range_caption()
	mag_min_changed(int(e.min) - 1)
	mag_max_changed(int(e.max) - 1)
	area_changed(int(e.area))
	duration_changed(int(e.duration) - 1)
	_modified(_cur)
	update_boxes()

## updateBoxes: kolejne pola od y = 80 (pozycja MagnitudeBox z układu).
func update_boxes() -> void:
	if _w.is_empty():
		return
	var y := 80.0
	for k in ["mag_box", "dur_box", "area_box"]:
		(_w[k] as Control).visible = false
	if not bool(effect_rec.get("no_magnitude", false)):
		(_w.mag_box as Control).position.y = y * ui.sc
		(_w.mag_box as Control).visible = true
		y += 70.0
	if not bool(effect_rec.get("no_duration", false)) and not constant:
		(_w.dur_box as Control).position.y = y * ui.sc
		(_w.dur_box as Control).visible = true
		y += 40.0
	if int(_cur.get("range", 0)) != 0:
		(_w.area_box as Control).position.y = y * ui.sc
		(_w.area_box as Control).visible = true

## onRangeButtonClicked: następny zasięg, pomijając niedozwolone; Self zeruje obszar.
func range_clicked() -> void:
	_cur.range = (int(_cur.range) + 1) % 3
	var al := _allowed(effect_rec)
	if int(_cur.range) == 0 and not al[0]:
		_cur.range = (int(_cur.range) + 1) % 3
	if int(_cur.range) == 1 and not al[1]:
		_cur.range = (int(_cur.range) + 1) % 3
	if int(_cur.range) == 2 and not al[2]:
		_cur.range = (int(_cur.range) + 1) % 3
	if int(_cur.range) == 0:
		_set_pos("area", 0)
		area_changed(0)
	_range_caption()
	update_boxes()
	_modified(_cur)

func mag_min_changed(pos: int) -> void:
	(_w.mag_min_val as Label).text = str(pos + 1)
	_cur["min"] = pos + 1
	mag_max_changed(int((_w.mag_max as HScrollBar).value))
	_modified(_cur)

## onMagnitudeMaxChanged: maksimum nie mniejsze niż minimum.
func mag_max_changed(pos: int) -> void:
	if pos + 1 < absi(int(_cur.get("min", 1))):
		pos = int(_cur.min) - 1
		_set_pos("mag_max", pos)
	_cur["max"] = pos + 1
	(_w.mag_max_val as Label).text = _t("sTo", "-") + " " + str(pos + 1)
	_modified(_cur)

func duration_changed(pos: int) -> void:
	(_w.dur_val as Label).text = str(pos + 1)
	_cur["duration"] = pos + 1
	_modified(_cur)

func area_changed(pos: int) -> void:
	(_w.area_val as Label).text = str(pos)
	_cur["area"] = pos
	_modified(_cur)

func delete_clicked() -> void:
	_close_dialog()
	_removed()

func ok_clicked() -> void:
	_close_dialog()

## onCancelButtonClicked → exit(): przy edycji przywraca stary efekt, nowy usuwa.
func cancel_clicked() -> void:
	_close_dialog()
	if editing:
		_modified(old_effect)
	else:
		_removed()

## Ustawia suwak jak użytkownik (testy, sterowanie z klawiatury).
func set_slider(key: String, pos: int) -> void:
	var s := _w.get(key) as HScrollBar
	if s != null:
		s.value = pos

# --- SelectSkillDialog / SelectAttributeDialog (openmw_chargen_select_skill/attribute.layout) -----------

func _close_sub() -> void:
	if sub != null and is_instance_valid(sub):
		CU.close(sub)
	sub = null

## SelectAttributeDialog (247 × 231): po wyborze EditEffectDialog z atrybutem.
func _open_select_attribute(idx: int) -> void:
	_close_sub()
	sub = ui.modal(host, 247, 231, true)
	sub.name = "SelectAttributeDialog"
	var g: Control = ui.group(sub.get_meta("client"), 14, 14, 216, 204)
	ui.label(g, 0, 0, 216, 18, _t("sAttributesMenu1", "Choose an attribute"), "header", HORIZONTAL_ALIGNMENT_CENTER)
	var area: Control = ui.group(g, 0, 28, 216, 144)
	for i in 8:
		var b: Button = ui.text_button(area, 0, 18 * i, 216, 18, ui.attr_name(i), func():
			_close_sub()
			new_effect(idx, -1, i), HORIZONTAL_ALIGNMENT_CENTER)
		b.name = "Attribute%d" % i
	_cancel_row(g, 0, 175, 216)

## SelectSkillDialog (487 × 275): trzy kolumny według specjalizacji umiejętności.
func _open_select_skill(idx: int) -> void:
	_close_sub()
	sub = ui.modal(host, 487, 275, true)
	sub.name = "SelectSkillDialog"
	var g: Control = ui.group(sub.get_meta("client"), 17, 14, 457, 246)
	ui.label(g, 0, 0, 457, 18, _t("sSkillsMenu1", "Choose a skill"), "header", HORIZONTAL_ALIGNMENT_CENTER)
	var ids: Array = ui.skill_ids()
	for col in [[0, 0, 154], [1, 158, 154], [2, 316, 131]]:
		ui.label(g, col[1], 32, col[2], 18, ui.spec_name(col[0]), "header")
		var y := 0.0
		var area: Control = ui.group(g, col[1], 50, 154, 168)
		for si in ids.size():
			var srec: Dictionary = _magic().records.record("skill", String(ids[si]))
			if int(srec.get("specialization", -1)) != int(col[0]):
				continue
			var k: int = si
			var b: Button = ui.text_button(area, 0, y, 154, 18, ui.skill_name(si), func():
				_close_sub()
				new_effect(idx, k, -1))
			b.name = "Skill%d" % si
			y += 18.0
	_cancel_row(g, 0, 218, 457)

func _cancel_row(g: Control, x: float, y: float, w: float) -> void:
	var cancel: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), _close_sub)
	cancel.name = "CancelButton"
	ui.button_row(g, x, y, w, 28, [cancel])

func close_all() -> void:
	_close_sub()
	_close_dialog()
