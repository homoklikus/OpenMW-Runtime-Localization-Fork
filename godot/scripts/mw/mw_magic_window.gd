extends CanvasLayer
## Okna magii (etap 7d, prosty interfejs – wygląd w etapie 10), jak w OpenMW:
##   magia (M) – zaklęcia i moce gracza (koszt, szansa), przedmioty do użycia (ładunek), działające efekty;
##             kliknięcie wybiera magię (R – przygotuj, lewy przycisk – rzuć);
##   alchemia  – użycie aparatu z ekwipunku: do 4 składników, aparaty (najlepsze z ekwipunku), podgląd
##             efektów, nazwa, „Stwórz” (AlchemyWindow);
##   zaklinanie – użycie kamienia dusz z duszą albo usługa zaklinacza: przedmiot, kamień, efekty znane
##             z zaklęć gracza (wielkość, czas, obszar, zasięg), sposób rzucania, punkty, szansa/cena (EnchantingDialog).
## Logika w mw_magic.gd.

const UI := preload("res://scripts/mw/mw_ui.gd")
var main
var magic
var mode := ""
var panel: PanelContainer
var title: Label
var left: ItemList
var right: ItemList
var info: Label
var name_edit: LineEdit
var action_btn: Button
var params: HBoxContainer
var spins := {}
var range_opt: OptionButton
var cast_opt: OptionButton
var add_btn: Button
var _left_ids: Array = []
var _right_ids: Array = []
# alchemia
var ingredients: Array = []
# zaklinanie
var enchanter := {}               # aktor rozmowy (usługa) albo {} (samodzielnie)
var ench_item := ""
var ench_gem := ""
var ench_effects: Array = []
var _effect_choice := -1

const SCHOOLS := {11: "Przemiana", 13: "Przywołanie", 10: "Zniszczenie", 12: "Iluzja", 14: "Mistycyzm", 15: "Przywracanie"}
const RANGES := ["na siebie", "dotyk", "cel"]
const CAST_NAMES := ["raz", "przy uderzeniu", "po użyciu", "stały"]

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "MagicWindow"
	panel.custom_minimum_size = Vector2(980, 600)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(UI.make_head(title))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	left = _list(row)
	right = _list(row)
	left.item_clicked.connect(func(i, _p, _b): _click_left(i))
	right.item_clicked.connect(func(i, _p, _b): _click_right(i))
	_build_alchemy(row)
	params = HBoxContainer.new()
	box.add_child(params)
	for k in ["min", "max", "duration", "area"]:
		var l := Label.new()
		l.text = {"min": "min", "max": "maks.", "duration": "czas", "area": "obszar"}[k]
		params.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = 0 if k != "min" and k != "max" else 1
		sp.max_value = 100 if k != "duration" else 1440
		sp.value = 1 if k != "area" else 0
		sp.value_changed.connect(func(_v): refresh())
		params.add_child(sp)
		spins[k] = sp
	range_opt = OptionButton.new()
	for r in RANGES:
		range_opt.add_item(r)
	params.add_child(range_opt)
	add_btn = Button.new()
	add_btn.text = "Dodaj efekt"
	add_btn.pressed.connect(_add_effect)
	params.add_child(add_btn)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size = Vector2(0, 90)
	box.add_child(info)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom)
	cast_opt = OptionButton.new()
	cast_opt.item_selected.connect(func(_i): refresh())
	bottom.add_child(cast_opt)
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.placeholder_text = "Nazwa"
	bottom.add_child(name_edit)
	action_btn = Button.new()
	action_btn.pressed.connect(_action)
	bottom.add_child(action_btn)
	var close_btn := Button.new()
	close_btn.text = "Zamknij (Esc)"
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)
	visible = false

func _list(parent: Control) -> ItemList:
	var l := ItemList.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb) if main != null and main.dialogue != null else fb

func _st() -> Dictionary:
	return main.player_stats()

func _me() -> Dictionary:
	return main.combat.player_fighter()

func _item_name(id: String) -> String:
	var it: Dictionary = main.interaction.inventory.item(id)
	return main.interaction.item_name(String(it.get("kind", "")), id, it.get("rec", {})) if not it.is_empty() else id

func effect_name(id: int) -> String:
	var mg: Dictionary = magic.effect(id)
	var n := String(mg.get("name", str(id)))
	return _t("sEffect" + n, n)

func effect_text(e: Dictionary) -> String:
	var id := int(e.get("effect", -1))
	var mg: Dictionary = magic.effect(id)
	var t := effect_name(id)
	if bool(mg.get("target_attribute", false)) and int(e.get("attribute", -1)) >= 0:
		t += " (%s)" % main.rest_window.ATTR_NAMES[clampi(int(e.attribute), 0, 7)]
	elif bool(mg.get("target_skill", false)) and int(e.get("skill", -1)) >= 0:
		var names: Array = main.builder.actors.records_index().get("skills", [])
		t += " (%s)" % (String(names[int(e.skill)]) if int(e.skill) < names.size() else str(e.skill))
	if not bool(mg.get("no_magnitude", false)):
		var mn := int(e.get("min", 0))
		var mx := int(e.get("max", 0))
		t += " %d%s pkt" % [mn, ("–%d" % mx) if mx != mn else ""]
	if not bool(mg.get("no_duration", false)) and int(e.get("duration", 0)) > 0:
		t += ", %d s" % int(e.duration)
	if int(e.get("area", 0)) > 0:
		t += ", obszar %d" % int(e.area)
	t += ", " + RANGES[clampi(int(e.get("range", 0)), 0, 2)]
	return t

func _show(m: String) -> void:
	mode = m
	visible = true
	params.visible = m == "enchant"
	cast_opt.visible = m == "enchant"
	name_edit.visible = m != "spells"
	action_btn.visible = m != "spells"
	name_edit.text = ""
	refresh()
	panel.position = (get_viewport().get_visible_rect().size - panel.custom_minimum_size) / 2.0
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_spells() -> void:
	_show("spells")

func open_alchemy() -> void:
	ingredients = []
	_show("alchemy")

## Zaklinanie: a – aktor rozmowy (usługa zaklinacza) albo {} (samodzielnie, gem – wybrany kamień).
func open_enchant(a := {}, gem := "") -> void:
	enchanter = a
	ench_item = ""
	ench_gem = gem
	ench_effects = []
	_effect_choice = -1
	_show("enchant")

func close() -> void:
	visible = false
	if main.get("dialogue_window") != null and main.dialogue_window.visible:
		return                             # usługa – wracamy do rozmowy (pauza trwa)
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh() -> void:
	left.clear()
	right.clear()
	_left_ids = []
	_right_ids = []
	alch_box.visible = mode == "alchemy"
	left.visible = mode != "alchemy"
	right.visible = mode != "alchemy"
	params.visible = mode == "enchant"
	cast_opt.visible = mode == "enchant"
	match mode:
		"spells": _refresh_spells()
		"alchemy": _refresh_alchemy()
		"enchant": _refresh_enchant()

# --- magia -----------------------------------------------------------------------------------------------

func _refresh_spells() -> void:
	title.text = _t("sMagicMenu", "Magia")
	var st := _st()
	var sel: Dictionary = main.selected_magic()
	for sid in st.get("spells", []):
		var sp: Dictionary = magic.records.record("spell", String(sid))
		var typ := int(sp.get("spell_type", -1))
		if sp.is_empty() or not typ in [magic.SPELL_SPELL, magic.SPELL_POWER]:
			continue
		var label := String(sp.get("name", sid))
		if typ == magic.SPELL_POWER:
			label += "  [moc%s]" % ("" if magic.can_use_power(_me(), String(sid)) else " – użyta dziś")
		else:
			label += "  koszt %d, szansa %d%%" % [magic.spell_cost(sp), int(magic.spell_chance(sp, _me()))]
		if sel.get("kind") == "spell" and sel.get("id") == String(sid):
			label = "» " + label
		left.add_item(label)
		_left_ids.append(String(sid))
	for e in main.interaction.inventory.ordered(main.interaction.inventory.contents("player", {})):
		var it: Dictionary = main.interaction.inventory.item(String(e.id))
		var en: Dictionary = magic.item_enchantment(it)
		if en.is_empty() or not int(en.get("type", -1)) in [magic.ENCH_WHEN_USED, magic.ENCH_CAST_ONCE]:
			continue
		var label2 := _item_name(String(e.id))
		if int(en.type) == magic.ENCH_WHEN_USED:
			label2 += "  ładunek %d/%d, koszt %d" % [int(magic.item_charge(_me(), String(e.id), en)), magic.enchantment_charge(en),
				magic.effective_cast_cost(en, _me())]
		else:
			label2 += "  ×%d (zwój)" % int(e.count)
		if sel.get("kind") == "item" and sel.get("id") == String(e.id):
			label2 = "» " + label2
		right.add_item(label2)
		_right_ids.append(String(e.id))
	var lines := ["Wybrana magia: " + (main.selected_magic_name() if not sel.is_empty() else "brak") + "  (R – przygotuj, lewy przycisk – rzuć)"]
	for sp2 in magic.active(_me()):
		var parts := []
		for x in sp2.effects:
			parts.append("%s%s" % [effect_name(int(x.effect)), (" %d s" % ceili(float(x.time_left))) if float(x.duration) > 0.0 else ""])
		lines.append("%s: %s" % [String(sp2.get("name", sp2.id)), ", ".join(parts)])
	info.text = "\n".join(lines)

# --- alchemia --------------------------------------------------------------------------------------------

## Układ jak openmw_alchemy_window.layout: aparaty (4 pola: moździerz, alembik, kalcynator, retorta), składniki
## (4 pola – kliknięcie usuwa), efekty, poniżej siatka składników z ekwipunku (kliknięcie – dodaj).
var alch_box: VBoxContainer
var _apparatus_slots: Array = []
var _ingredient_slots: Array = []
var _alch_effects: VBoxContainer
var _alch_grid: Control = null
var alch_grid_ids: Array = []        # testy
const APPARATUS_GMST := [["sMortar", "Moździerz"], ["sAlembic", "Alembik"], ["sCalcinator", "Kalcynator"], ["sRetort", "Retorta"]]

func _slot(parent: Control) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 0.6)))
	p.custom_minimum_size = Vector2(50, 50) * _scale()
	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 6
	ic.offset_top = 6
	ic.offset_right = -6
	ic.offset_bottom = -6
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ic)
	parent.add_child(p)
	return p

func _scale() -> float:
	return UI.ui_scale() if get_viewport() != null else 1.0

func _build_alchemy(row: Control) -> void:
	alch_box = VBoxContainer.new()
	alch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alch_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	alch_box.visible = false
	row.add_child(alch_box)
	var top := HBoxContainer.new()
	alch_box.add_child(top)
	var ap := VBoxContainer.new()
	top.add_child(ap)
	ap.add_child(UI.header(_t("sApparatus", "Aparaty")))
	var aprow := HBoxContainer.new()
	ap.add_child(aprow)
	for i in 4:
		_apparatus_slots.append(_slot(aprow))
	var ing := VBoxContainer.new()
	top.add_child(ing)
	ing.add_child(UI.header(_t("sIngredients", "Składniki")))
	var irow := HBoxContainer.new()
	ing.add_child(irow)
	for i in 4:
		var sl := _slot(irow)
		var idx := i
		sl.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and idx < ingredients.size(): remove_ingredient(String(ingredients[idx])))
		_ingredient_slots.append(sl)
	var fx := VBoxContainer.new()
	fx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fx)
	fx.add_child(UI.header(_t("sCreatedEffects", "Efekty")))
	_alch_effects = VBoxContainer.new()
	fx.add_child(UI.framed(_alch_effects))

func click_item(id: String, _source: String) -> void:
	if mode == "alchemy" and not id in ingredients and ingredients.size() < 4:
		ingredients.append(id)
		refresh()

func activate_item(_id: String, _source: String) -> void:
	pass

func dropped_on(_target: String, data: Dictionary) -> void:
	click_item(String(data.get("mw_item", "")), "")

func remove_ingredient(id: String) -> void:
	ingredients.erase(id)
	refresh()

func _refresh_alchemy_layout(tools: Dictionary, res: Dictionary) -> void:
	var mm = main.menu_mode
	if _alch_grid == null:
		mm.scale_ui = _scale()
		_alch_grid = mm._make_grid(alch_box, "alchemy", self)
	for i in 4:
		var ic := _apparatus_slots[i].get_node("Icon") as TextureRect
		var nm: String = _t(APPARATUS_GMST[i][0], APPARATUS_GMST[i][1])
		if tools.has(i):
			var it: Dictionary = main.interaction.inventory.item(String(tools[i].id))
			ic.texture = UI.icon(String(it.get("rec", {}).get("icon", "")))
			_apparatus_slots[i].tooltip_text = "%s\n%s (%.2f)" % [nm, _item_name(String(tools[i].id)), float(tools[i].quality)]
		else:
			ic.texture = null
			_apparatus_slots[i].tooltip_text = nm
	for i in 4:
		var ic2 := _ingredient_slots[i].get_node("Icon") as TextureRect
		if i < ingredients.size():
			var it2: Dictionary = main.interaction.inventory.item(String(ingredients[i]))
			ic2.texture = UI.icon(String(it2.get("rec", {}).get("icon", "")))
			_ingredient_slots[i].tooltip_text = _item_name(String(ingredients[i]))
		else:
			ic2.texture = null
			_ingredient_slots[i].tooltip_text = ""
	for c in _alch_effects.get_children():
		c.queue_free()
	for e2 in res.get("effects", []):
		var l := Label.new()
		l.text = effect_text(e2)
		_alch_effects.add_child(l)
	var entries := []
	var inv = main.interaction.inventory
	for e in inv.ordered(inv.contents("player", {})):
		if String(e.kind) != "ingredient":
			continue
		var used := 1 if String(e.id) in ingredients else 0
		if int(e.count) - used <= 0:
			continue
		var it3: Dictionary = inv.item(String(e.id))
		entries.append({"id": String(e.id), "count": int(e.count) - used, "rec": it3.get("rec", {}), "worn": false, "magic": false})
	alch_grid_ids = mm._fill_grid(_alch_grid, entries, "inventory", self)

func _refresh_alchemy() -> void:
	title.text = _t("sAlchemyMenu1", "Alchemia")
	action_btn.text = _t("sCreate", "Stwórz")
	for e in main.interaction.inventory.ordered(main.interaction.inventory.contents("player", {})):
		if String(e.kind) != "ingredient":
			continue
		left.add_item("%s ×%d" % [_item_name(String(e.id)), int(e.count)])
		_left_ids.append(String(e.id))
	for id in ingredients:
		right.add_item(_item_name(String(id)))
		_right_ids.append(String(id))
	var tools: Dictionary = magic.alchemy_tools(_me())
	var tl := []
	for t in tools:
		tl.append("%s (%.2f)" % [_item_name(String(tools[t].id)), float(tools[t].quality)])
	var res: Dictionary = magic.alchemy_result(_me(), ingredients, tools)
	_refresh_alchemy_layout(tools, res)
	var fx := []
	for e2 in res.get("effects", []):
		fx.append(effect_text(e2))
	info.text = "Aparaty: %s\nEfekty: %s\nKliknij składnik w siatce, aby dodać (do 4), a w polu składnika – aby usunąć." % [
		", ".join(tl) if not tl.is_empty() else "brak (potrzebny moździerz)", ", ".join(fx) if not fx.is_empty() else "—"]

# --- zaklinanie ------------------------------------------------------------------------------------------

func _cast_types() -> Array:
	return magic.cast_types_for(main.interaction.inventory.item(ench_item), ench_gem) if not ench_item.is_empty() else []

func cast_type() -> int:
	var ct := _cast_types()
	if ct.is_empty():
		return magic.ENCH_WHEN_USED
	return int(ct[clampi(cast_opt.selected, 0, ct.size() - 1)])

func _refresh_enchant() -> void:
	title.text = _t("sEnchantmentMenu1", "Zaklinanie") + ("" if enchanter.is_empty() else " – " + String(main.dialogue.actor_name(enchanter)))
	action_btn.text = _t("sBuy", "Kup") if not enchanter.is_empty() else _t("sEnchantmentMenu1", "Zaklnij")
	var inv = main.interaction.inventory
	for e in inv.ordered(inv.contents("player", {})):
		var id := String(e.id)
		var it: Dictionary = inv.item(id)
		if magic.is_soul_gem(id) and magic.gem_charge(id) > 0:
			left.add_item("%s%s  dusza %d" % ["» " if id == ench_gem else "", _item_name(id), magic.gem_charge(id)])
			_left_ids.append("gem:" + id)
		elif String(e.kind) in ["weapon", "armor", "clothing", "book"] and float(it.rec.get("enchant_capacity", 0)) > 0.0 \
				and String(it.rec.get("enchant", "")).is_empty() and not (String(e.kind) == "book" and not bool(it.rec.get("scroll", false))):
			left.add_item("%s%s  pojemność %d" % ["» " if id == ench_item else "", _item_name(id), magic.max_enchant_value(it)])
			_left_ids.append("item:" + id)
	for fid in magic.known_enchant_effects(_st()):
		right.add_item(("» " if fid == _effect_choice else "") + effect_name(int(fid)))
		_right_ids.append("fx:%d" % int(fid))
	for i in ench_effects.size():
		right.add_item("  ✓ " + effect_text(ench_effects[i]) + "  (kliknij, aby usunąć)")
		_right_ids.append("del:%d" % i)
	var ct := _cast_types()
	var prev := cast_opt.selected
	cast_opt.clear()
	for c in ct:
		cast_opt.add_item(CAST_NAMES[int(c)])
	if not ct.is_empty():
		cast_opt.select(clampi(prev, 0, ct.size() - 1))
	var typ := cast_type()
	var pts: float = magic.enchant_points(ench_effects, typ, false)
	var it2: Dictionary = inv.item(ench_item) if not ench_item.is_empty() else {}
	var lines := ["Przedmiot: %s, kamień: %s" % [_item_name(ench_item) if not ench_item.is_empty() else "—",
		_item_name(ench_gem) if not ench_gem.is_empty() else "—"],
		"Punkty zaklęcia: %d / %d, koszt rzucenia: %d, ładunek: %d" % [int(pts), magic.max_enchant_value(it2) if not it2.is_empty() else 0,
			magic.enchant_cast_cost(ench_effects, typ), magic.gem_charge(ench_gem) if not ench_gem.is_empty() else 0]]
	if enchanter.is_empty():
		lines.append("Szansa powodzenia: %d%%" % maxi(0, magic.enchant_chance(_me(), ench_effects, typ)))
	elif not ench_effects.is_empty():
		lines.append("Cena: %d (złoto: %d)" % [magic.enchant_price(enchanter, ench_effects, typ), main.trade.player_gold()])
	info.text = "\n".join(lines)

func _add_effect() -> void:
	if mode != "enchant" or _effect_choice < 0:
		return
	var mg: Dictionary = magic.effect(_effect_choice)
	var e := {"effect": _effect_choice, "skill": -1, "attribute": -1, "range": range_opt.selected,
		"area": int(spins.area.value), "duration": int(spins.duration.value),
		"min": int(spins.min.value), "max": maxi(int(spins.min.value), int(spins.max.value))}
	if bool(mg.get("target_attribute", false)) or bool(mg.get("target_skill", false)):
		for sid in _st().get("spells", []):       # atrybut/umiejętność jak w znanym zaklęciu
			for x in magic.records.record("spell", String(sid)).get("effects", []):
				if int(x.get("effect", -1)) == _effect_choice:
					e.skill = int(x.get("skill", -1))
					e.attribute = int(x.get("attribute", -1))
	if bool(mg.get("no_magnitude", false)):
		e.min = 0
		e.max = 0
	if bool(mg.get("no_duration", false)) or cast_type() == magic.ENCH_CONSTANT:
		e.duration = 0 if bool(mg.get("no_duration", false)) else e.duration
	if ench_effects.size() < 8:
		ench_effects.append(e)
	refresh()

# --- kliknięcia ------------------------------------------------------------------------------------------

func _click_left(i: int) -> void:
	if i < 0 or i >= _left_ids.size():
		return
	var id: String = _left_ids[i]
	match mode:
		"spells":
			main.select_magic("spell", id)
		"alchemy":
			if not id in ingredients and ingredients.size() < 4:
				ingredients.append(id)
		"enchant":
			if id.begins_with("gem:"):
				ench_gem = id.substr(4)
			elif id.begins_with("item:"):
				ench_item = id.substr(5)
	refresh()

func _click_right(i: int) -> void:
	if i < 0 or i >= _right_ids.size():
		return
	var id: String = _right_ids[i]
	match mode:
		"spells":
			main.select_magic("item", id)
		"alchemy":
			ingredients.erase(id)
		"enchant":
			if id.begins_with("fx:"):
				_effect_choice = int(id.substr(3))
			elif id.begins_with("del:"):
				ench_effects.remove_at(int(id.substr(4)))
	refresh()

func _action() -> void:
	match mode:
		"alchemy":
			var r: Dictionary = magic.brew(_me(), ingredients, name_edit.text)
			main._toast(String(r.get("message", "")), 2.5)
			ingredients = ingredients.filter(func(x): return main.interaction.inventory.count_of("player", {}, String(x)) > 0)
		"enchant":
			var r2: Dictionary = magic.enchant(_me(), ench_item, ench_gem, ench_effects, cast_type(), name_edit.text, enchanter)
			main._toast(String(r2.get("message", "")), 2.5)
			if bool(r2.get("success", false)) or bool(r2.get("failed", false)):
				ench_item = ""
				ench_gem = ""
				ench_effects = []
	refresh()
