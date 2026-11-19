extends CanvasLayer
## Okno alchemii jak OpenMW 0.51 (MWGui::AlchemyWindow, files/data/mygui/openmw_alchemy_window.layout):
## skórka MW_Window_NoCaption, prostokąt z [Windows] alchemy (0,25; 0,25; 0,5; 0,5), elementy układu 588 × 444
## rozciągane wg wyrównania MyGUI (HStretch, Stretch, Bottom):
##   sName + pole nazwy (70, 8, 492 + dW, 30); sApparatus + 4 × MW_ItemIconBox 50 × 50 co 60 px (10, 66);
##   sIngredients + 4 miejsca składników (10, 146); ItemView ze składnikami (10, 206, 552 + dW, 132 + dH);
##   sCreatedEffects (250, 40) + MW_Box z listą efektów (250, 66, 312 + dW, 130) – efekt nieznany jako „?”;
##   filtry (MW_Box HBox, 10, 333 + dH, Padding 5, Spacing 10): przycisk sIngredients/sMagicEffects i lista;
##   przyciski (10, 374 + dH): „ - ”, liczba mikstur (96 × 25), „ + ”, odstęp, sCreate, Cancel.
## Kliknięcie składnika w siatce – do pierwszego wolnego miejsca (bez powtórzeń), w miejscu – usunięcie; klik
## w aparat – zdjęcie, w puste miejsce aparatu – ItemSelectionDialog z aparatami tego rodzaju.

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const RECT := Rect2(0.25, 0.25, 0.5, 0.5)
const BASE := Vector2(588, 444)
const APP_TITLES := ["sMortar", "sAlembic", "sCalcinator", "sRetort"]

var main
var ui = null
var win: Control = null
var slots: Array = ["", "", "", ""]          # składniki w miejscach (stosy)
var tools: Dictionary = {}                   # aparaty: rodzaj → {"id", "quality"}
var name_edit: LineEdit = null
var count_edit: LineEdit = null
var filter_type := "name"                    # name | effect (FilterType::ByName / ByEffect)
var filter_value := ""
var effects_shown: Array = []                # testy: [{"key", "known", "text"}]
var _s := 1.0
var _client: Control = null
var _app_boxes: Array = []
var _ing_boxes: Array = []
var _grid: Control = null
var _effects_box: Control = null
var _filter_btn: Button = null
var _filter_opt: OptionButton = null
var _suggested := ""
var _select: Control = null

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

func _me() -> Dictionary:
	return main.combat.player_fighter()

func is_open() -> bool:
	return visible

## AlchemyWindow::onOpen: najlepsze aparaty, puste miejsca, pusta nazwa, liczba 1, filtr według nazw.
func open() -> void:
	_s = UI.ui_scale()
	ui = CU.new(main, _s)
	slots = ["", "", "", ""]
	tools = main.magic.alchemy_tools(_me())
	filter_type = "name"
	filter_value = ""
	_suggested = ""
	_build()
	visible = true
	refresh()
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	name_edit.grab_focus()

func close() -> void:
	visible = false
	if _select != null:
		_select.queue_free()
		_select = null
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	if win != null:
		win.queue_free()
	var vp := get_viewport().get_visible_rect().size
	var r := Rect2((RECT.position * vp).floor(), (RECT.size * vp).floor())
	win = Panel.new()
	win.name = "AlchemyWindow"
	win.theme = UI.theme(_s)
	win.add_theme_stylebox_override("panel", UI.window_box())
	win.position = r.position
	win.size = r.size
	add_child(win)
	# MW_Window_NoCaption: jednolity pasek HB_ALL (4, 4, szer. − 8, 20), wewnętrzna ramka od (4, 24), Client (8, 28)
	var head := Panel.new()
	head.add_theme_stylebox_override("panel", UI.head_box())
	head.position = Vector2(4, 4) * _s
	head.size = Vector2(r.size.x - 8 * _s, 20 * _s)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(head)
	var inner: StyleBox = UI.inner_frame_thick()
	win.draw.connect(func(): win.draw_style_box(inner, Rect2(Vector2(4, 24) * _s, win.size - Vector2(8, 28) * _s)))
	_client = Control.new()
	_client.position = Vector2(8, 28) * _s
	_client.size = r.size - Vector2(16, 36) * _s
	win.add_child(_client)
	var c := _client
	# przesunięcie rozmiaru Client względem układu (588 × 444 → Client 572 × 408)
	var d := (c.size / _s) - (BASE - Vector2(16, 36))
	var dw := d.x
	var dh := d.y
	var nl: Label = ui.label(c, 10, 8, 65, 30, _t("sName", "Name"))
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER         # TextAlign „Left” – wyśrodkowanie w pionie
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.text_submitted.connect(func(_t2): create())
	ui.at(name_edit, c, 70, 8, 492 + dw, 30)
	ui.label(c, 10, 40, 260, 24, _t("sApparatus", "Apparatus")).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_app_boxes = []
	for i in 4:
		var b := _icon_slot(c, 10 + 60 * i, 66)
		var idx := i
		b.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				apparatus_clicked(idx))
		_app_boxes.append(b)
	ui.label(c, 10, 120, 260, 24, _t("sIngredients", "Ingredients")).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ing_boxes = []
	for i in 4:
		var b2 := _icon_slot(c, 10 + 60 * i, 146)
		var idx2 := i
		b2.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				remove_ingredient(idx2))
		_ing_boxes.append(b2)
	# ItemView (Left Top Stretch)
	var iv := Control.new()
	iv.name = "ItemView"
	ui.at(iv, c, 10, 206, 552 + dw, 132 + dh)
	_grid = main.menu_mode._make_grid(iv, "alchemy", self)
	var gp := _grid.get_parent().get_parent() as Control             # GridPanel wypełnia ItemView
	gp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.label(c, 250, 40, 320, 24, _t("sCreatedEffects", "Created Effects")).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var eb: Control = ui.box(c, 250, 66, 312 + dw, 130)
	_effects_box = Control.new()
	_effects_box.name = "CreatedEffects"
	ui.at(_effects_box, eb, 4, 4, 316 + dw, 122)
	# filtry: HBox MW_Box (Bottom HStretch), Padding 5, Spacing 10 – rozkład jak Gui::HBox::align
	var fb: Control = ui.box(c, 10, 333 + dh, 552 + dw, 39)
	_filter_btn = ui.button(_t("sIngredients", "Ingredients"), switch_filter_type)
	_filter_btn.name = "FilterType"
	_filter_opt = OptionButton.new()
	_filter_opt.name = "FilterValue"
	ui.style_combo(_filter_opt)
	_filter_opt.item_selected.connect(func(i): set_filter(_filter_opt.get_item_text(i)))
	_hbox_layout(fb, [_filter_btn, _filter_opt], [false, true], [Vector2.ZERO, Vector2(0, 24) * _s], 5, 10)
	# przyciski: HBox bez skórki (Bottom HStretch), Padding 0, Spacing 4 (domyślne Gui::Box)
	var bh := Control.new()
	bh.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.at(bh, c, 10, 374 + dh, 552 + dw, 28)
	var dec: Button = ui.button(" - ", func(): set_count(brew_count() - 1))
	dec.name = "DecreaseButton"
	count_edit = LineEdit.new()
	count_edit.name = "BrewCount"
	count_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_edit.text = "1"
	count_edit.text_changed.connect(func(t2): set_count(int(t2) if t2.is_valid_int() else 1, false))
	count_edit.text_submitted.connect(func(_t2): create())
	var inc: Button = ui.button(" + ", func(): set_count(brew_count() + 1))
	inc.name = "IncreaseButton"
	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cr: Button = ui.button(_t("sCreate", "Create"), create)
	cr.name = "CreateButton"
	var cn: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), close)
	cn.name = "CancelButton"
	_hbox_layout(bh, [dec, count_edit, inc, sp, cr, cn], [false, false, false, true, false, false],
			[Vector2.ZERO, Vector2(96, 25) * _s, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], 0, 4)
	for b3 in [dec, count_edit, inc, cr, cn]:
		(b3 as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN

## MW_ItemIconBox 50 × 50 (ramka MW_Box_Overlay, ikona od 9, 9 – tło 42 × 42 od 4, 4).
func _icon_slot(parent: Control, x: float, y: float) -> Control:
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.at(b, parent, x, y, 50, 50)
	return b

func _fill_slot(b: Control, id: String, count := 0) -> void:
	for ch in b.get_children():
		ch.queue_free()
	b.tooltip_text = ""
	if not id.is_empty():
		var it: Dictionary = main.interaction.inventory.item(id)
		var tex: Texture2D = UI.icon(String(it.rec.get("icon", "")))
		if tex != null:
			var sh := TextureRect.new()
			sh.texture = tex
			sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sh.modulate = Color(0, 0, 0, 0.5)
			sh.position = Vector2(13, 13) * _s
			sh.size = Vector2(32, 32) * _s
			sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(sh)
			var ic := TextureRect.new()
			ic.texture = tex
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.position = Vector2(9, 9) * _s
			ic.size = Vector2(32, 32) * _s
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(ic)
		if count > 1:
			var cl := Label.new()                      # CountText (5, 19, 32, 18) w tle od 4, 4 – do prawej
			cl.text = str(count)
			cl.add_theme_color_override("font_color", UI.color("count"))
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cl.position = Vector2(9, 23) * _s
			cl.size = Vector2(32, 18) * _s
			cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(cl)
		b.tooltip_text = main.menu_mode.item_tooltip(id)
	var ov := Panel.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_theme_stylebox_override("panel", UI.inner_box())
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ov)

# --- stan i akcje --------------------------------------------------------------------------------------------

func brew_count() -> int:
	return maxi(1, int(count_edit.text)) if count_edit != null and count_edit.text.is_valid_int() else 1

func set_count(n: int, write := true) -> void:
	n = maxi(1, absi(n))
	if write and count_edit != null:
		count_edit.text = str(n)

## Siatka: klik składnika – Alchemy::addIngredient (pierwsze wolne miejsce, bez powtórzeń), dźwięk podniesienia.
func click_item(id: String, _source: String) -> void:
	add_ingredient(id)

func activate_item(id: String, _source: String) -> void:
	add_ingredient(id)

func dropped_on(_target: String, data: Dictionary) -> void:
	add_ingredient(String(data.get("mw_item", "")))

func add_ingredient(id: String) -> int:
	var it: Dictionary = main.interaction.inventory.item(id)
	if it.is_empty() or String(it.kind) != "ingredient":
		return -1
	var slot := slots.find("")
	if slot < 0:
		return -1
	for s2 in slots:
		if not String(s2).is_empty() and main.interaction.inventory.base_id(String(s2)) == main.interaction.inventory.base_id(id):
			return -1
	slots[slot] = id
	if main.get("audio") != null and main.audio != null:
		main.audio.play(main.interaction.item_sound(id, true))
	refresh()
	return slot

func remove_ingredient(i: int) -> void:
	if i >= 0 and i < 4 and not String(slots[i]).is_empty():
		slots[i] = ""
		refresh()

## Klik w aparat: zdjęcie z miejsca; puste miejsce – wybór aparatu tego rodzaju (ItemSelectionDialog).
func apparatus_clicked(i: int) -> void:
	if tools.has(i):
		tools.erase(i)
		refresh()
		return
	_open_apparatus_selection(i)

func switch_filter_type() -> void:
	if filter_type == "name":
		filter_type = "effect"
		_filter_btn.text = _t("sMagicEffects", "Magic Effects")
	else:
		filter_type = "name"
		_filter_btn.text = _t("sIngredients", "Ingredients")
	_relayout_filters()
	filter_value = ""
	refresh()

func _relayout_filters() -> void:
	var fb := _filter_btn.get_parent() as Control
	_filter_btn.size = Vector2(ui.text_width(_filter_btn.text) + 24 * _s, 24 * _s)
	fb.remove_child(_filter_btn)
	fb.remove_child(_filter_opt)
	_hbox_layout(fb, [_filter_btn, _filter_opt], [false, true], [Vector2.ZERO, Vector2(0, 24) * _s], 5, 10)

func set_filter(v: String) -> void:
	filter_value = v
	_refresh_grid()

## AlchemyWindow::onCreateButtonClicked → createPotions(min(countPotionsToBrew, liczba)).
func create() -> Dictionary:
	var tool_d := tools.duplicate()
	if tool_d.is_empty():
		tool_d = {-1: {}}                          # brak aparatów – bez domyślnego doboru w brew
	var nm := name_edit.text if name_edit != null else ""
	var n: int = mini(main.magic.potions_to_brew(_me(), slots, nm.strip_edges(), tools), brew_count())
	var res: Dictionary = main.magic.brew(_me(), slots, nm, -1, maxi(1, n), tool_d)
	if not String(res.get("message", "")).is_empty():
		main._toast(String(res.message))
	for i in 4:                                    # miejsca składników, które się skończyły
		if not String(slots[i]).is_empty() and main.interaction.inventory.count_of("player", {}, String(slots[i])) <= 0:
			slots[i] = ""
	refresh()
	return res

func refresh() -> void:
	if win == null:
		return
	var inv = main.interaction.inventory
	for t in tools.keys():                        # aparat zniknął z ekwipunku
		if inv.count_of("player", {}, String(tools[t].id)) <= 0:
			tools.erase(t)
	for i in 4:
		_fill_slot(_app_boxes[i], String(tools[i].id) if tools.has(i) else "")
		var sid := String(slots[i])
		_fill_slot(_ing_boxes[i], sid, inv.count_of("player", {}, sid) if not sid.is_empty() else 0)
	# AlchemyWindow::update: nazwa podpowiadana z pierwszego efektu, gdy się zmienia
	var keys := _effect_keys()
	var sug := _effect_name(keys[0]) if not keys.is_empty() else ""
	if sug != _suggested:
		name_edit.text = sug
		_suggested = sug
	_refresh_effects(keys)
	_refresh_filters()
	_refresh_grid()

func _ingredient_recs() -> Array:
	var out := []
	for sid in slots:
		if not String(sid).is_empty():
			var it: Dictionary = main.interaction.inventory.item(String(sid))
			if not it.is_empty():
				out.append(it.rec)
	return out

func _effect_keys() -> Array:
	return main.magic.common_effects(_ingredient_recs())

func _effect_dict(key: String) -> Dictionary:
	var p := key.split(":")
	var id := int(p[0])
	var arg := int(p[1])
	var mg: Dictionary = main.magic.effect(id)
	return {"effect": id, "skill": arg if bool(mg.get("target_skill", false)) else -1,
		"attribute": arg if bool(mg.get("target_attribute", false)) else -1}

func _effect_name(key: String) -> String:
	return ui.effect_text(_effect_dict(key), true)

## Lista utworzonych efektów (MWEffectList, MW_EffectImage po 24 px): bez wielkości i czasu; nieznany – „?”.
func _refresh_effects(keys: Array) -> void:
	for ch in _effects_box.get_children():
		ch.queue_free()
	effects_shown = []
	var y := 0.0
	for i in keys.size():
		var known: bool = main.magic.known_effect(_me(), i)
		var e := _effect_dict(String(keys[i]))
		var text: String = _effect_name(String(keys[i])) if known else "?"
		var icon := String(main.magic.effect(int(e.effect)).get("icon", "")) if known else ""
		var g: Control = ui.effect_line(_effects_box, 0, y, _effects_box.size.x / _s, icon, text)
		if not known:
			g.get_child(1).position.x = 12 * _s      # sIconOffset / 2 – w miejsce brakującej ikony
		effects_shown.append({"key": keys[i], "known": known, "text": text})
		y += 24

func _refresh_filters() -> void:
	var names := {}
	var effs := {}
	var sk := float(main.combat.skill(_me(), 16))
	for e in main.menu_mode.sorted_items():
		if String(e.kind) != "ingredient":
			continue
		names[String(e.name)] = true
		for x in main.magic.ingredient_known_effects(e.rec, sk):
			effs[ui.effect_text(x, true)] = true
	var items: Array = (names if filter_type == "name" else effs).keys()
	items.sort()
	_filter_opt.clear()
	for t in items:
		_filter_opt.add_item(String(t))
	var idx := items.find(filter_value)
	_filter_opt.select(idx)

## ItemView: składniki gracza (Filter_OnlyIngredients) bez stosów leżących w miejscach (addDragItem),
## filtr nazwy albo efektu (setNameFilter / setEffectFilter).
func _refresh_grid() -> void:
	var entries := []
	var sk := float(main.combat.skill(_me(), 16))
	for e in main.menu_mode.sorted_items():
		if String(e.kind) != "ingredient" or String(e.id) in slots:
			continue
		if not filter_value.is_empty():
			if filter_type == "name" and not String(e.name).to_lower().contains(filter_value.to_lower()):
				continue
			if filter_type == "effect":
				var hit := false
				for x in main.magic.ingredient_known_effects(e.rec, sk):
					if ui.effect_text(x, true).to_lower().contains(filter_value.to_lower()):
						hit = true
				if not hit:
					continue
		entries.append(e)
	main.menu_mode._fill_grid(_grid, entries, "alchemy", self)

# --- wybór aparatu (ItemSelectionDialog, Filter_OnlyAlchemyTools + rodzaj) ------------------------------------

func _open_apparatus_selection(kind: int) -> void:
	if _select != null:
		_select.queue_free()
	var dlg: Control = ui.modal(self, 380, 285, true)
	_select = dlg.get_meta("layer")
	var c: Control = dlg.get_meta("client")
	ui.label(c, 8, 8, 300, 18, _t(APP_TITLES[kind], "Apparatus"))
	var view := Control.new()
	ui.at(view, c, 8, 34, 355, 200)
	var grid: Control = main.menu_mode._make_grid(view, "apparatus", _SelOwner.new(self, kind))
	(grid.get_parent().get_parent() as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var entries := []
	for e in main.menu_mode.sorted_items():
		if String(e.kind) == "apparatus" and int(e.rec.get("apparatus_type", -1)) == kind:
			entries.append(e)
	main.menu_mode._fill_grid(grid, entries, "apparatus", _SelOwner.new(self, kind))
	var cb: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), func():
		_select.queue_free()
		_select = null)
	c.add_child(cb)
	await get_tree().process_frame
	if is_instance_valid(cb):
		var bw := maxf(24 * _s, cb.get_combined_minimum_size().x)
		cb.position = Vector2(364 * _s - bw, 240 * _s)
		cb.size = Vector2(bw, 24 * _s)

## AlchemyWindow::onItemSelected: aparat w swoim miejscu, dźwięk odkładania.
func select_apparatus(kind: int, id: String) -> void:
	if _select != null:
		_select.queue_free()
		_select = null
	var it: Dictionary = main.interaction.inventory.item(id)
	if it.is_empty():
		return
	tools[kind] = {"id": id, "quality": float(it.rec.get("quality", 0.0))}
	if main.get("audio") != null and main.audio != null:
		main.audio.play(main.interaction.item_sound(id, false))
	refresh()

class _SelOwner:
	var w
	var kind := 0
	func _init(window, k: int) -> void:
		w = window
		kind = k
	func click_item(id: String, _s: String) -> void:
		w.select_apparatus(kind, id)
	func activate_item(id: String, _s: String) -> void:
		w.select_apparatus(kind, id)
	func dropped_on(_t: String, _d: Dictionary) -> void:
		pass


## Gui::HBox::align: AutoSizedButton – rozmiar żądany (tekst + 24×8), pozostałe – rozmiar z układu;
## rozciągane w poziomie (HStretch) dzielą resztę szerokości; w pionie wyśrodkowanie dzieleniem całkowitym.
func _hbox_layout(box: Control, items: Array, stretch: Array, fixed: Array, padding: int, spacing: int) -> void:
	var pad := padding * _s
	var spc := spacing * _s
	var sizes := []
	var total := 0.0
	var n_st := 0
	for i in items.size():
		var sz: Vector2 = fixed[i] if fixed[i] != Vector2.ZERO or not (items[i] is Button) else (items[i] as Control).size
		sizes.append(sz)
		total += sz.x
		if i != items.size() - 1:
			total += spc
		if stretch[i]:
			n_st += 1
	var cw := box.size.x
	var ch := box.size.y
	var x := pad
	for i in items.size():
		var w := items[i] as Control
		var sz: Vector2 = sizes[i]
		var ww := sz.x + (floorf((cw - pad * 2 - total) / n_st) if stretch[i] else 0.0)
		w.position = Vector2(x, pad + floorf((ch - pad * 2 - sz.y) / 2.0))
		w.size = Vector2(ww, sz.y)
		box.add_child(w)
		x += ww + spc
