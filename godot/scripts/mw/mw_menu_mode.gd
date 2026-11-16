extends CanvasLayer
## Tryb menu jak w Morrowindzie/OpenMW (etap 10): prawy przycisk myszy (akcja „menu_mode”, OpenMW A_Inventory) albo
## I / M / N pokazuje naraz cztery okna – statystyki, ekwipunek, magię i mapę – w położeniach domyślnych OpenMW
## ([Windows] stats/inventory/spells/map: x, y, w, h jako ułamek ekranu); okna można przesuwać (pasek tytułu)
## i zmieniać ich rozmiar (prawy dolny róg), układ zapamiętuje zapis gry. Gra jest wstrzymana.
##
## Ekwipunek (InventoryWindow): podgląd postaci gracza w założonych rzeczach, pancerz, obciążenie (pasek),
## kategorie (Wszystko, Broń, Ubiór, Magia, Inne – SortFilterItemModel), siatka ikon 42 × 42 kolumnami jak ItemView
## (tła menu_icon_equip/_magic), liczby w stosach, podpowiedzi (nazwa, waga, wartość, stan, efekty).
## Przeciągnięcie ikony na postać – użyj/załóż, poza okna – upuść na ziemię; dwuklik – użyj/załóż.
## Statystyki (StatsWindow): zdrowie, magia, kondycja, poziom (postęp do awansu), rasa, klasa, atrybuty,
## umiejętności główne/poboczne/pozostałe (postęp), frakcje z rangą, znak urodzenia, reputacja, grzywna.
## Magia (SpellWindow): działające efekty (ikony z czasem), moce, zaklęcia (koszt/szansa), przedmioty magiczne
## (ładunek); kliknięcie wybiera magię.

const UI := preload("res://scripts/mw/mw_ui.gd")

signal closed

var main
const DEFAULT_RECTS := {        # OpenMW files/settings-default.cfg [Windows]
	"stats": Rect2(0.015, 0.015, 0.4275, 0.45),
	"inventory": Rect2(0.015, 0.54, 0.45, 0.38),
	"spells": Rect2(0.63, 0.39, 0.36, 0.51),
	"map": Rect2(0.63, 0.015, 0.36, 0.37),
}
const CATEGORIES := [["all", "sAllTab", "Wszystko"], ["weapon", "sWeaponTab", "Broń"], ["apparel", "sApparelTab", "Ubiór"],
	["magic", "sMagicTab", "Magia"], ["misc", "sMiscTab", "Inne"]]
# kolejność typów jak SortFilterItemModel::getTypeOrder
const TYPE_ORDER := {"weapon": 0, "armor": 1, "clothing": 2, "potion": 3, "ingredient": 4, "apparatus": 5, "book": 6,
	"light": 7, "misc": 8, "lockpick": 9, "repair": 10, "probe": 11}
const ATTR_GMST := ["sAttributeStrength", "sAttributeIntelligence", "sAttributeWillpower", "sAttributeAgility",
	"sAttributeSpeed", "sAttributeEndurance", "sAttributePersonality", "sAttributeLuck"]
const ATTR_PL := ["Siła", "Inteligencja", "Siła woli", "Zręczność", "Szybkość", "Wytrzymałość", "Osobowość", "Szczęście"]
const CELL := 42.0

var scale_ui := 1.0
var category := "all"
var _root: Control
var windows := {}                # nazwa → PanelContainer
var _grid: Control = null
var _doll_vp: SubViewport = null
var _doll: Node3D = null
var _armor_label: Label = null
var _enc_bar: ProgressBar = null
var _enc_label: Label = null
var _cat_buttons := {}
var item_ids: Array = []         # testy: id w kolejności siatki
var spell_rows: Array = []       # testy: [rodzaj, id]

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, def: String) -> String:
	return main.dialogue.gmst_text(gm, def) if main != null and main.dialogue != null else def

func _allowed(n: String) -> bool:
	if main == null or not main.has_method("menu_allowed"):
		return true
	return main.menu_allowed({"spells": "magic"}.get(n, n))

func is_open() -> bool:
	return visible

# --- otwieranie i układ ---------------------------------------------------------------------------------

func open() -> void:
	if visible:
		return
	var vp := get_viewport().get_visible_rect().size
	scale_ui = clampf(vp.y / 720.0, 1.0, 3.0)
	UI.setup(String(main.data_dir) if main != null and main.get("data_dir") != null else "")
	_root = _Backdrop.new()
	_root.name = "MenuMode"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.theme(scale_ui)
	_root.menu = self
	add_child(_root)
	visible = true
	# okna wyłączone w trakcie kreatora postaci (EnableInventoryMenu itd.) nie są pokazywane
	for n in ["stats", "inventory", "spells"]:
		if _allowed(n):
			windows[n] = _window(n, _rect(n, vp))
	if windows.has("stats"):
		_build_stats()
	if windows.has("inventory"):
		_build_inventory()
	if windows.has("spells"):
		_build_spells()
	if main != null and main.get("map_window") != null and _allowed("map"):
		main.map_window.open(_rect("map", vp))
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_hud(false)
	refresh()

func _set_hud(_on: bool) -> void:
	pass                                   # HUD (mw_hud.gd) chowa się sam, gdy tryb menu jest otwarty

func close() -> void:
	if not visible:
		return
	_save_layout()
	visible = false
	if main != null and main.get("map_window") != null and main.map_window.visible and main.map_window.embedded:
		main.map_window.close()
	if _root != null:
		_root.queue_free()
		_root = null
	windows = {}
	_grid = null
	_cont_grid = null
	cont_sid = ""
	_stat_left = null
	_spell_list = null
	_doll_vp = null
	_doll = null
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_hud(true)
	closed.emit()

func _layout_store() -> Dictionary:
	if main == null or main.get("state") == null:
		return {}
	if not main.state.player.get("ui_windows") is Dictionary:
		main.state.player["ui_windows"] = {}
	return main.state.player["ui_windows"]

func _rect(name: String, vp: Vector2) -> Rect2:
	var r: Rect2 = DEFAULT_RECTS[name]
	var saved = _layout_store().get(name)
	if saved is Array and saved.size() == 4:
		r = Rect2(float(saved[0]), float(saved[1]), float(saved[2]), float(saved[3]))
	return Rect2(r.position * vp, r.size * vp)

func _save_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var store := _layout_store()
	for n in windows:
		var w: Control = windows[n]
		store[n] = [w.position.x / vp.x, w.position.y / vp.y, w.size.x / vp.x, w.size.y / vp.y]

func _window(name: String, rect: Rect2) -> PanelContainer:
	var w := PanelContainer.new()
	w.name = name.capitalize() + "Window"
	w.position = rect.position.floor()
	w.size = rect.size.floor()
	w.custom_minimum_size = Vector2(160, 120) * scale_ui
	_root.add_child(w)
	var box := VBoxContainer.new()
	box.name = "Box"
	w.add_child(box)
	var head := PanelContainer.new()
	head.name = "Title"
	head.add_theme_stylebox_override("panel", UI.head_box())
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.gui_input.connect(_drag_window.bind(w))
	box.add_child(head)
	var tl := Label.new()
	tl.name = "Text"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_color", UI.color("header"))
	head.add_child(tl)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var grip := Control.new()
	grip.name = "Resize"
	grip.custom_minimum_size = Vector2(12, 12) * scale_ui
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.size_flags_horizontal = Control.SIZE_SHRINK_END
	grip.gui_input.connect(_resize_window.bind(w))
	box.add_child(grip)
	return w

func _title(name: String, text: String) -> void:
	if windows.has(name):
		(windows[name].get_node("Box/Title/Text") as Label).text = text

func _body(name: String) -> VBoxContainer:
	return windows[name].get_node("Box/Body") as VBoxContainer

func _drag_window(e: InputEvent, w: Control) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var vp := get_viewport().get_visible_rect().size
		w.position = (w.position + e.relative).clamp(Vector2.ZERO, vp - Vector2(40, 20))

func _resize_window(e: InputEvent, w: Control) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		w.size = (w.size + e.relative).max(w.custom_minimum_size)
		_layout_grid.call_deferred()

func refresh() -> void:
	if not visible:
		return
	_refresh_stats()
	_refresh_inventory()
	_refresh_spells()
	_refresh_container()

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("menu_mode") or e.is_action_pressed("inventory") or e.is_action_pressed("magic_menu") \
			or e.is_action_pressed("map_menu") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()

# --- statystyki -----------------------------------------------------------------------------------------

var _stat_bars := {}
var _stat_left: VBoxContainer
var _stat_right: VBoxContainer

func _build_stats() -> void:
	var body := _body("stats")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", UI.inner_box())
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 0.85
	cols.add_child(lp)
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(ls)
	_stat_left = VBoxContainer.new()
	_stat_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_stat_left)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", UI.inner_box())
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rp)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rs)
	_stat_right = VBoxContainer.new()
	_stat_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_stat_right)

func _row(parent: Control, left: String, right: String, tip := "", col := Color(0, 0, 0, 0)) -> HBoxContainer:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = left
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.clip_text = true
	h.add_child(a)
	var b := Label.new()
	b.text = right
	if col.a > 0.0:
		b.add_theme_color_override("font_color", col)
	h.add_child(b)
	if not tip.is_empty():
		h.tooltip_text = tip
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		a.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(h)
	return h

func _bar_row(parent: Control, label: String, kind: String, cur: float, mx: float) -> void:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = label
	a.custom_minimum_size.x = 80 * scale_ui
	h.add_child(a)
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size.y = 18 * scale_ui
	h.add_child(holder)
	var pb := UI.progress_bar(kind, scale_ui)
	pb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.max_value = maxf(mx, 1.0)
	pb.value = clampf(cur, 0.0, pb.max_value)
	holder.add_child(pb)
	var t := Label.new()
	t.text = "%d/%d" % [roundi(cur), roundi(mx)]
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", UI.color("normal_pressed"))
	holder.add_child(t)
	parent.add_child(h)
	_stat_bars[kind] = pb

func _val_color(base: float, mod: float) -> Color:
	if mod > base + 0.01:
		return UI.color("positive")
	if mod < base - 0.01:
		return UI.color("negative")
	return UI.color("normal")

func _refresh_stats() -> void:
	if _stat_left == null or main == null:
		return
	for c in _stat_left.get_children() + _stat_right.get_children():
		c.queue_free()
	var st: Dictionary = main.player_stats()
	_title("stats", String(st.get("name", "")) if not String(st.get("name", "")).is_empty() else _t("sStats", "Statystyki"))
	if st.is_empty() or main.character == null:
		return
	var ch = main.character
	var d: Dictionary = ch.derived(st)
	_bar_row(_stat_left, _t("sHealth", "Zdrowie"), "health", float(st.get("health", 0)), float(d.health.modified))
	_bar_row(_stat_left, _t("sMagic", "Magia"), "magic", float(st.get("magicka", 0)), float(d.magicka.modified))
	_bar_row(_stat_left, _t("sFatigue", "Kondycja"), "fatigue", float(st.get("fatigue", 0)), float(d.fatigue.modified))
	_stat_left.add_child(HSeparator.new())
	var prog: Dictionary = st.get("progress", {})
	var lvl_tip := "%s: %d/10" % [_t("sLevelProgress", "Postęp do awansu"), int(prog.get("level", 0))]
	_row(_stat_left, _t("sLevel", "Poziom"), str(int(st.get("level", 1))), lvl_tip)
	var race: Dictionary = main.builder.actors.record("race", String(st.get("race", "")))
	_row(_stat_left, _t("sRace", "Rasa"), String(race.get("name", st.get("race", ""))))
	var cls: Dictionary = ch._class_of(st)
	_row(_stat_left, _t("sClass", "Klasa"), String(cls.get("name", st.get("class", ""))))
	_stat_left.add_child(HSeparator.new())
	var base_a: Array = st.get("attributes", [])
	for i in 8:
		var b := float(base_a[i]) if i < base_a.size() else 0.0
		var m := float(d.attributes[i])
		_row(_stat_left, _t(ATTR_GMST[i], ATTR_PL[i]), str(int(m)), "", _val_color(b, m))
	# umiejętności
	var names: Array = main.builder.actors.records_index().get("skills", [])
	var major: Array = cls.get("major_skills", [])
	var minor: Array = cls.get("minor_skills", [])
	var groups := [["sSkillClassMajor", "Umiejętności główne", major], ["sSkillClassMinor", "Umiejętności poboczne", minor]]
	var misc := []
	for i in 27:
		if not (i in major or float(i) in major) and not (i in minor or float(i) in minor):
			misc.append(i)
	groups.append(["sSkillClassMisc", "Pozostałe umiejętności", misc])
	var base_s: Array = st.get("skills", [])
	var sprog: Array = prog.get("skills", [])
	for g in groups:
		_stat_right.add_child(UI.header(_t(g[0], g[1])))
		for sk in g[2]:
			var i := int(sk)
			if i < 0 or i >= 27:
				continue
			var sid := String(names[i]) if i < names.size() else str(i)
			var b2 := float(base_s[i]) if i < base_s.size() else 0.0
			var m2 := float(d.skills[i])
			var req: float = ch.skill_requirement(st, i)
			var tip := "%s: %d/%d" % [_t("sSkillProgress", "Postęp"), int(float(sprog[i]) if i < sprog.size() else 0.0), int(req)]
			_row(_stat_right, _t("sSkill" + sid.capitalize().replace(" ", ""), sid.capitalize()), str(int(m2)), tip, _val_color(b2, m2))
		_stat_right.add_child(HSeparator.new())
	var facs: Dictionary = st.get("factions", {})
	if not facs.is_empty():
		_stat_right.add_child(UI.header(_t("sFaction", "Frakcje")))
		for fid in facs:
			var fr: Dictionary = main.builder.actors.record("faction", String(fid))
			if bool(fr.get("hidden", false)):
				continue
			var rank := int((facs[fid] as Dictionary).get("rank", 0))
			var ranks: Array = fr.get("ranks", [])
			var rname := String(ranks[rank]) if rank >= 0 and rank < ranks.size() and ranks[rank] is String else ""
			if rank >= 0 and rank < ranks.size() and ranks[rank] is Dictionary:
				rname = String((ranks[rank] as Dictionary).get("name", ""))
			_row(_stat_right, String(fr.get("name", fid)), rname)
		_stat_right.add_child(HSeparator.new())
	var sign: Dictionary = main.builder.actors.record("birthsign", String(st.get("birthsign", "")))
	if not sign.is_empty():
		_row(_stat_right, _t("sBirthSign", "Znak urodzenia"), String(sign.get("name", "")))
	_row(_stat_right, _t("sReputation", "Reputacja"), str(int(st.get("reputation", 0))))
	_row(_stat_right, _t("sBounty", "Grzywna"), str(int(st.get("bounty", 0))))

# --- ekwipunek ------------------------------------------------------------------------------------------

func _build_inventory() -> void:
	var body := _body("inventory")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	# lewa część: postać, pancerz, obciążenie
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.42
	cols.add_child(left)
	var avatar = _DollDrop.new()
	avatar.name = "Avatar"
	avatar.add_theme_stylebox_override("panel", UI.inner_box())
	avatar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar.menu = self
	avatar.target = "avatar"
	left.add_child(avatar)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(svc)
	_doll_vp = SubViewport.new()
	_doll_vp.own_world_3d = true
	_doll_vp.transparent_bg = true
	_doll_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_doll_vp)
	_armor_label = Label.new()
	_armor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_armor_label)
	var enc := Control.new()
	enc.custom_minimum_size.y = 18 * scale_ui
	left.add_child(enc)
	_enc_bar = UI.progress_bar("health", scale_ui)
	_enc_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	enc.add_child(_enc_bar)
	_enc_label = Label.new()
	_enc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enc_label.add_theme_color_override("font_color", UI.color("normal_pressed"))
	enc.add_child(_enc_label)
	# prawa część: kategorie i siatka
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var tabs := HBoxContainer.new()
	right.add_child(tabs)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = _t(c[1], c[2])
		b.toggle_mode = true
		b.button_pressed = c[0] == category
		b.pressed.connect(set_category.bind(String(c[0])))
		tabs.add_child(b)
		_cat_buttons[c[0]] = b
	_grid = _make_grid(right, "inventory")

func set_category(c: String) -> void:
	category = c
	for k in _cat_buttons:
		_cat_buttons[k].button_pressed = k == c
	_refresh_inventory()

## Kategoria jak SortFilterItemModel::filterAccepts (zaklęte przedmioty także w „Magia”).
func in_category(kind: String, enchanted: bool, cat: String) -> bool:
	if cat == "all":
		return true
	var c := ""
	match kind:
		"armor", "clothing": c = "apparel"
		"weapon": c = "weapon"
		"ingredient", "potion": c = "magic"
		_: c = "misc"
	return c == cat or (cat == "magic" and enchanted)

func _enchanted(it: Dictionary) -> bool:
	return not String(it.get("rec", {}).get("enchant", "")).is_empty()

## Kolejność jak SortFilterItemModel::Compare: założone najpierw, potem typ, nazwa, wartość, waga.
func sorted_items(sid := "player", rec := {}) -> Array:
	var inv = main.interaction.inventory
	var out := []
	for e in inv.contents(sid, rec):
		var it: Dictionary = inv.item(String(e.id))
		if it.is_empty():
			continue
		var worn: bool = sid == "player" and main.equipped_slot_of(String(e.id)) >= 0
		var name: String = main.interaction.item_name(String(it.kind), String(e.id), it.rec)
		out.append({"id": String(e.id), "count": int(e.count), "kind": String(it.kind), "rec": it.rec, "worn": worn,
			"name": name, "magic": _enchanted(it)})
	out.sort_custom(func(a, b):
		if a.worn != b.worn:
			return a.worn
		var ta := int(TYPE_ORDER.get(a.kind, 99))
		var tb := int(TYPE_ORDER.get(b.kind, 99))
		if ta != tb:
			return ta < tb
		var na := String(a.name).to_lower()
		var nb := String(b.name).to_lower()
		if na != nb:
			return na < nb
		var va := int(a.rec.get("value", 0))
		var vb := int(b.rec.get("value", 0))
		if va != vb:
			return va > vb
		return String(a.id) < String(b.id))
	return out

## Siatka ikon w przewijanym obszarze (ItemView): zwraca kontrolkę siatki; source – „inventory” | „container”.
func _make_grid(parent: Control, source: String) -> Control:
	var gp = _DollDrop.new()                      # obszar przyjmujący upuszczone przedmioty
	gp.name = "GridPanel"
	gp.menu = self
	gp.target = source
	gp.add_theme_stylebox_override("panel", UI.inner_box())
	gp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(gp)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	gp.add_child(sc)
	var grid := Control.new()
	grid.name = "Grid"
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	sc.resized.connect(func(): _layout(grid))
	return grid

func _fill_grid(grid: Control, entries: Array, source: String) -> Array:
	for c in grid.get_children():
		c.queue_free()
	var ids := []
	for e in entries:
		var cell = _ItemCell.new()
		cell.menu = self
		cell.item_id = e.id
		cell.source = source
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.custom_minimum_size = Vector2(CELL, CELL) * scale_ui
		cell.size = cell.custom_minimum_size
		cell.tooltip_text = item_tooltip(e.id)
		var fr := UI.icon_frame(e.magic, "equip" if e.worn else "")
		if fr != null:
			var fb := TextureRect.new()
			fb.texture = fr
			fb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fb.set_anchors_preset(Control.PRESET_FULL_RECT)
			fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(fb)
		elif e.worn:
			var wb := Panel.new()
			wb.set_anchors_preset(Control.PRESET_FULL_RECT)
			wb.add_theme_stylebox_override("panel", UI.inner_box(Color(0.3, 0.25, 0.1, 0.5)))
			wb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(wb)
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.texture = UI.icon(String(e.rec.get("icon", "")))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.position = Vector2(5, 5) * scale_ui
		ic.size = Vector2(32, 32) * scale_ui
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(ic)
		if ic.texture == null:
			var nl := Label.new()
			nl.text = String(e.name).left(3)
			nl.position = Vector2(4, 8) * scale_ui
			nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(nl)
		if int(e.count) > 1:
			var cl := Label.new()
			cl.text = str(e.count)
			cl.add_theme_color_override("font_color", UI.color("count"))
			cl.add_theme_font_size_override("font_size", roundi(13 * scale_ui))
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			cl.set_anchors_preset(Control.PRESET_FULL_RECT)
			cl.offset_right = -3 * scale_ui
			cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(cl)
		grid.add_child(cell)
		ids.append(e.id)
	_layout(grid)
	return ids

func _refresh_inventory() -> void:
	if _grid == null or main == null or main.get("interaction") == null:
		return
	_title("inventory", _t("sInventory", "Ekwipunek"))
	var entries := []
	for e in sorted_items():
		if in_category(e.kind, e.magic, category):
			entries.append(e)
	item_ids = _fill_grid(_grid, entries, "inventory")
	# pancerz i obciążenie
	var st: Dictionary = main.player_stats()
	var w: float = main.player_weight()
	var cap: float = main.character.capacity(st) if not st.is_empty() else 0.0
	_enc_bar.max_value = maxf(cap, 1.0)
	_enc_bar.value = minf(w, _enc_bar.max_value)
	_enc_label.text = "%d/%d" % [roundi(w), roundi(cap)]
	_enc_label.get_parent().tooltip_text = _t("sEncumbrance", "Obciążenie")
	_armor_label.text = "%s: %d" % [_t("sArmor", "Pancerz"), roundi(player_armor_rating())]
	_rebuild_doll()

func _layout_grid() -> void:
	_layout(_grid)
	_layout(_cont_grid)

## Rozmieszczenie kolumnami (ItemView::layoutWidgets): wiersze = wysokość / 42, przewijanie w poziomie.
func _layout(grid: Control) -> void:
	if grid == null or not is_instance_valid(grid):
		return
	var sc := grid.get_parent() as Control
	var cs := CELL * scale_ui
	var rows := maxi(1, int(sc.size.y / cs))
	var i := 0
	for c in grid.get_children():
		if c.is_queued_for_deletion():
			continue
		(c as Control).position = Vector2(int(i / rows) * cs, (i % rows) * cs)
		i += 1
	grid.custom_minimum_size = Vector2(ceilf(float(i) / rows) * cs, rows * cs)

# --- pojemnik (ContainerWindow) --------------------------------------------------------------------------

var cont_sid := ""
var cont_rec := {}
var cont_name := ""
var _cont_grid: Control = null
var cont_ids: Array = []          # testy

## Pojemnik jak OpenMW: okno pojemnika (ułożenie [Windows] container) i ekwipunek gracza obok; przeciąganie między
## oknami, dwuklik w pojemniku – weź stos, dwuklik w ekwipunku – włóż; „Weź wszystko”, „Zamknij”.
func open_container(sid: String, rec: Dictionary, name: String) -> void:
	if visible:
		close()
	cont_sid = sid
	cont_rec = rec
	cont_name = name
	var vp := get_viewport().get_visible_rect().size
	scale_ui = clampf(vp.y / 720.0, 1.0, 3.0)
	UI.setup(String(main.data_dir) if main != null and main.get("data_dir") != null else "")
	_root = _Backdrop.new()
	_root.name = "MenuMode"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.theme(scale_ui)
	_root.menu = self
	add_child(_root)
	visible = true
	windows["inventory"] = _window("inventory", _rect("inventory", vp))
	_build_inventory()
	windows["container"] = _window("container", Rect2(Vector2(0.49, 0.54) * vp, Vector2(0.39, 0.38) * vp))
	var body := _body("container")
	_cont_grid = _make_grid(body, "container")
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(btns)
	var ta := Button.new()
	ta.text = _t("sTakeAll", "Weź wszystko")
	ta.pressed.connect(take_all)
	btns.add_child(ta)
	var cb := Button.new()
	cb.text = _t("sClose", "Zamknij")
	cb.pressed.connect(close)
	btns.add_child(cb)
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_hud(false)
	refresh()

func _refresh_container() -> void:
	if _cont_grid == null or not is_instance_valid(_cont_grid):
		return
	var inv = main.interaction.inventory
	var items: Array = inv.contents(cont_sid, cont_rec)
	var cap := float(cont_rec.get("capacity", 0.0))
	var w: float = inv.total_weight(items)
	_title("container", cont_name + ("  (%d/%d)" % [roundi(w), roundi(cap)] if cap > 0.0 else ""))
	cont_ids = _fill_grid(_cont_grid, sorted_items(cont_sid, cont_rec), "container")

func _count(sid: String, rec: Dictionary, id: String) -> int:
	return int(main.interaction.inventory.count_of(sid, rec, id))

## Z pojemnika do gracza (cały stos).
func take_item(id: String) -> void:
	var n := _count(cont_sid, cont_rec, id)
	if n > 0 and main.interaction.move(cont_sid, cont_rec, "player", {}, id, n) > 0 and main.get("audio") != null:
		main.audio.play(main.interaction.item_sound(id, true))
	refresh()

## Od gracza do pojemnika (cały stos; założone – zdejmowane). Pojemność: OpenMW nie pozwala przekroczyć
## (sContentsMessage3).
func put_item(id: String) -> void:
	var n := _count("player", {}, id)
	if n <= 0:
		return
	var cap := float(cont_rec.get("capacity", 0.0))
	if cap > 0.0 and cont_rec.has("capacity"):
		var inv = main.interaction.inventory
		var it: Dictionary = inv.item(id)
		var w: float = inv.total_weight(inv.contents(cont_sid, cont_rec)) + float(it.get("rec", {}).get("weight", 0.0)) * n
		if w > cap + 0.001:
			if main.has_method("_toast"):
				main._toast(_t("sContentsMessage3", "Nie ma tu wystarczająco miejsca."))
			return
	if main.interaction.move("player", {}, cont_sid, cont_rec, id, n) > 0 and main.get("audio") != null:
		main.audio.play(main.interaction.item_sound(id, false))
	refresh()

func take_all() -> void:
	main.interaction.take_all(cont_sid, cont_rec)
	if main.get("audio") != null:
		main.audio.play("Item Misc Up")
	close()

## Upuszczenie przeciąganego przedmiotu na obszar okna.
func dropped_on(target: String, data: Dictionary) -> void:
	var id := String(data.get("mw_item", ""))
	var src := String(data.get("source", "inventory"))
	if target == "container" and src == "inventory":
		put_item(id)
	elif target in ["inventory", "avatar"] and src == "container":
		take_item(id)
	elif target == "avatar" and src == "inventory":
		use_item(id)

## Dwuklik: w trybie pojemnika – przełożenie, inaczej – użyj/załóż.
func activate_item(id: String, source: String) -> void:
	if source == "container":
		take_item(id)
	elif _cont_grid != null and is_instance_valid(_cont_grid):
		put_item(id)
	else:
		use_item(id)

## Pancerz gracza (getArmorRating): suma pancerza założonych zbroi wg miejsc (waga miejsca) + bez zbroi.
func player_armor_rating() -> float:
	if main == null or main.get("combat") == null:
		return 0.0
	return float(main.combat.armor_rating(main.combat.player_fighter()))

func item_tooltip(id: String) -> String:
	var it: Dictionary = main.interaction.inventory.item(id)
	if it.is_empty():
		return id
	var rec: Dictionary = it.rec
	var lines := [main.interaction.item_name(String(it.kind), id, rec)]
	match String(it.kind):
		"weapon":
			var t := int(rec.get("weapon_type", 0))
			if t in [9, 10, 11, 12, 13]:
				lines.append("%s: %d – %d" % [_t("sAttack", "Atak"), int(rec.get("chop_min", 0)), int(rec.get("chop_max", 0))])
			else:
				lines.append("%s: %d – %d" % [_t("sChop", "Cięcie"), int(rec.get("chop_min", 0)), int(rec.get("chop_max", 0))])
				lines.append("%s: %d – %d" % [_t("sSlash", "Zamach"), int(rec.get("slash_min", 0)), int(rec.get("slash_max", 0))])
				lines.append("%s: %d – %d" % [_t("sThrust", "Pchnięcie"), int(rec.get("thrust_min", 0)), int(rec.get("thrust_max", 0))])
		"armor":
			lines.append("%s: %d" % [_t("sArmorRating", "Pancerz"), int(rec.get("armor", 0))])
	if rec.has("health") and String(it.kind) in ["weapon", "armor", "lockpick", "probe", "repair"]:
		var h := int(rec.get("health", 0))
		lines.append("%s: %d/%d" % [_t("sCondition", "Stan") if String(it.kind) in ["weapon", "armor"] else _t("sUses", "Użycia"), h, h])
	lines.append("%s: %s" % [_t("sWeight", "Waga"), str(snappedf(float(rec.get("weight", 0)), 0.01))])
	lines.append("%s: %d" % [_t("sValue", "Wartość"), int(rec.get("value", 0))])
	if main.get("magic") != null:
		var en: Dictionary = main.magic.item_enchantment(it)
		var effects: Array = en.get("effects", []) if not en.is_empty() else rec.get("effects", [])
		for e in effects:
			var mg: Dictionary = main.magic.effect(int(e.get("effect", -1)))
			if mg.is_empty():
				continue
			var n := String(mg.get("name", ""))
			lines.append(_t("sEffect" + n, n))
	return "\n".join(lines)

## Użycie przedmiotu (InventoryWindow::useItem) – logika okna przedmiotów (mikstury, składniki, aparaty, książki,
## kamienie dusz, zakładanie).
func use_item(id: String) -> void:
	var iw = main.item_window
	iw.mode = "inventory"
	iw.refresh()
	var i: int = iw._right_ids.find(id)
	if i < 0:
		return
	var it: Dictionary = main.interaction.inventory.item(id)
	var k := String(it.get("kind", ""))
	if k in ["apparatus", "book"] or (k == "misc" and main.get("magic") != null and main.magic.is_soul_gem(id) and main.magic.gem_charge(id) > 0):
		close()                    # okno alchemii, książki, zaklinania zamiast trybu menu
	iw.use_item(i)
	iw.visible = false
	refresh()

func drop_to_world(id: String, source := "inventory") -> void:
	if source != "inventory":
		return
	var n: int = main.interaction.inventory.count_of("player", {}, id)
	if n <= 0:
		return
	main.drop_item(id, n)
	if main.get("audio") != null:
		main.audio.play(main.interaction.item_sound(id, false))
	refresh()

func _rebuild_doll() -> void:
	if _doll_vp == null or main == null or not main.has_method("player_doll"):
		return
	for c in _doll_vp.get_children():
		c.queue_free()
	_doll = main.player_doll()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.55)
	env.environment = e
	_doll_vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.5, 0.6, 0)
	_doll_vp.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.0, 4.3)
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0))
	_doll_vp.add_child(cam)
	if _doll != null:
		_doll.process_mode = Node.PROCESS_MODE_ALWAYS
		_doll.rotation.y = PI                      # przodem do kamery
		_doll_vp.add_child(_doll)

# --- magia ----------------------------------------------------------------------------------------------

var _fx_box: HFlowContainer
var _spell_list: VBoxContainer

func _build_spells() -> void:
	var body := _body("spells")
	var fp := PanelContainer.new()
	fp.add_theme_stylebox_override("panel", UI.inner_box())
	fp.custom_minimum_size.y = 30 * scale_ui
	body.add_child(fp)
	_fx_box = HFlowContainer.new()
	fp.add_child(_fx_box)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", UI.inner_box())
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(lp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(sc)
	_spell_list = VBoxContainer.new()
	_spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_spell_list)

func _spell_button(text: String, right: String, kind: String, id: String, selected: bool, tip := "") -> void:
	var h := HBoxContainer.new()
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	if selected:
		b.add_theme_color_override("font_color", UI.color("active"))
		b.add_theme_color_override("font_hover_color", UI.color("active_over"))
	b.tooltip_text = tip
	b.pressed.connect(func(): select_spell(kind, id))
	h.add_child(b)
	var r := Label.new()
	r.text = right
	h.add_child(r)
	_spell_list.add_child(h)
	spell_rows.append([kind, id])

func select_spell(kind: String, id: String) -> void:
	main.select_magic(kind, id)
	_refresh_spells()

func _refresh_spells() -> void:
	if _spell_list == null or main == null or main.get("magic") == null:
		return
	var magic = main.magic
	for c in _spell_list.get_children() + _fx_box.get_children():
		c.queue_free()
	spell_rows = []
	var sel: Dictionary = main.selected_magic()
	_title("spells", main.selected_magic_name() if not sel.is_empty() else _t("sMagicMenu", "Magia"))
	var me: Dictionary = main.combat.player_fighter()
	# działające efekty – ikony z czasem pozostałym w podpowiedzi
	for sp2 in magic.active(me):
		for x in sp2.effects:
			var mg: Dictionary = magic.effect(int(x.effect))
			var ic := TextureRect.new()
			ic.texture = UI.icon(String(mg.get("icon", "")))
			ic.custom_minimum_size = Vector2(16, 16) * scale_ui
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var n := String(mg.get("name", ""))
			ic.tooltip_text = "%s\n%s%s" % [_t("sEffect" + n, n), String(sp2.get("name", sp2.id)),
				("\n%d s" % ceili(float(x.time_left))) if float(x.duration) > 0.0 else ""]
			_fx_box.add_child(ic)
	var st: Dictionary = main.player_stats()
	var powers := []
	var spells := []
	for sid in st.get("spells", []):
		var sp: Dictionary = magic.records.record("spell", String(sid))
		var typ := int(sp.get("spell_type", -1))
		if typ == magic.SPELL_POWER:
			powers.append([String(sid), sp])
		elif typ == magic.SPELL_SPELL:
			spells.append([String(sid), sp])
	var by_name := func(a, b): return String(a[1].get("name", a[0])).to_lower() < String(b[1].get("name", b[0])).to_lower()
	powers.sort_custom(by_name)
	spells.sort_custom(by_name)
	if not powers.is_empty():
		_spell_list.add_child(UI.header(_t("sPowers", "Moce")))
		for p in powers:
			_spell_button(String(p[1].get("name", p[0])), "" if magic.can_use_power(me, p[0]) else "–", "spell", p[0],
				sel.get("kind") == "spell" and sel.get("id") == p[0])
	if not spells.is_empty():
		_spell_list.add_child(UI.header(_t("sSpells", "Zaklęcia")))
		var cc := "%s/%s" % [_t("sCostCharge", "Koszt"), _t("sChance", "Szansa")]
		for p in spells:
			_spell_button(String(p[1].get("name", p[0])), "%d/%d" % [magic.spell_cost(p[1]), int(magic.spell_chance(p[1], me))],
				"spell", p[0], sel.get("kind") == "spell" and sel.get("id") == p[0], cc)
	var items := []
	var inv = main.interaction.inventory
	for e in inv.ordered(inv.contents("player", {})):
		var it: Dictionary = inv.item(String(e.id))
		var en: Dictionary = magic.item_enchantment(it)
		if en.is_empty() or not int(en.get("type", -1)) in [magic.ENCH_WHEN_USED, magic.ENCH_CAST_ONCE]:
			continue
		var right := ""
		if int(en.type) == magic.ENCH_WHEN_USED:
			right = "%d/%d" % [magic.effective_cast_cost(en, me), int(magic.item_charge(me, String(e.id), en))]
		else:
			right = "×%d" % int(e.count)
		items.append([String(e.id), main.interaction.item_name(String(it.kind), String(e.id), it.rec), right])
	if not items.is_empty():
		_spell_list.add_child(UI.header(_t("sMagicItem", "Przedmioty magiczne")))
		for x in items:
			_spell_button(x[1], x[2], "item", x[0], sel.get("kind") == "item" and sel.get("id") == x[0])

# --- elementy przeciągania ------------------------------------------------------------------------------

## Komórka siatki ekwipunku: przeciąganie (ikona pod kursorem), dwuklik – użyj/załóż.
const _ItemCell := preload("res://scripts/mw/mw_menu_cell.gd")
const _DollDrop := preload("res://scripts/mw/mw_menu_doll.gd")
const _Backdrop := preload("res://scripts/mw/mw_menu_backdrop.gd")
