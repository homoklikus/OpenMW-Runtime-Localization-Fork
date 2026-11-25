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
const MAX_RECTS := {            # [Windows] <okno> maximized x/y/w/h
	"stats": Rect2(0.255, 0.275, 0.4275, 0.45),
	"inventory": Rect2(0.015, 0.02, 0.97, 0.875),
	"spells": Rect2(0.32, 0.02, 0.36, 0.88),
	"map": Rect2(0.015, 0.02, 0.97, 0.875),
}
var _pin_layer: CanvasLayer = null      # przypięte okna poza trybem GUI (WindowManager::updateVisible)
var _pin_t := 0.0
const CATEGORIES := [["all", "sAllTab", "All"], ["weapon", "sWeaponTab", "Weapon"], ["apparel", "sApparelTab", "Apparel"],
	["magic", "sMagicTab", "Magic"], ["misc", "sMiscTab", "Misc"]]
# kolejność typów jak SortFilterItemModel::getTypeOrder
const TYPE_ORDER := {"weapon": 0, "armor": 1, "clothing": 2, "potion": 3, "ingredient": 4, "apparatus": 5, "book": 6,
	"light": 7, "misc": 8, "lockpick": 9, "repair": 10, "probe": 11}
const ATTR_GMST := ["sAttributeStrength", "sAttributeIntelligence", "sAttributeWillpower", "sAttributeAgility",
	"sAttributeSpeed", "sAttributeEndurance", "sAttributePersonality", "sAttributeLuck"]
const ATTR_EN := ["Strength", "Intelligence", "Willpower", "Agility", "Speed", "Endurance", "Personality", "Luck"]
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
var _inv_left: Control = null
var inv_filter: LineEdit
var spell_filter: LineEdit
var spell_delete: Button
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
	if _pin_layer != null:                 # przypięte okna wracają do trybu menu (budowane od nowa)
		_pin_layer.queue_free()
		_pin_layer = null
		_pinned_windows = []
	var vp := get_viewport().get_visible_rect().size
	scale_ui = UI.ui_scale()
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
		main.map_window.open(_rect("map", vp), self)
	_apply_shown()
	_gui_mode = "inventory"
	main.gui.push("inventory", [self], close)          # GM_Inventory
	_set_hud(false)
	refresh()

var _gui_mode := ""

## GuiModeState::update(true): powrót z trybu otwartego nad ekwipunkiem (alchemia, naprawa, zaklinanie…).
func gui_resumed() -> void:
	refresh()

func _set_hud(_on: bool) -> void:
	pass                                   # HUD (mw_hud.gd) chowa się sam, gdy tryb menu jest otwarty

func close() -> void:
	if not visible:
		return
	if main != null and main.get("count_dialog") != null and is_instance_valid(main.count_dialog) and main.count_dialog.is_open():
		main.count_dialog.press_cancel()        # okno ilości dotyczy zamykanego okna
	_save_layout()
	if is_holding():                          # DragAndDrop::finish – przedmiot zostaje w ekwipunku
		held = {}
		_hide_held()
	visible = false
	if main != null and main.get("gui") != null and not _gui_mode.is_empty():
		var m := _gui_mode
		_gui_mode = ""
		if is_suspended_gui():
			main.gui._set_visible([self], true, [])
		main.gui.remove(m)
	var was_container := not cont_sid.is_empty()
	if not pickpocket.is_empty():
		var pp := pickpocket
		pickpocket = {}
		# PickpocketItemModel::onClose: Pickpocket::finish – wykrycie przy zamknięciu (bez wykrycia wcześniej)
		if not bool(pp.detected) and main.get("crime") != null and is_instance_valid(pp.node):
			if main.crime.pick_finish(pp.node):
				main.crime.commit(pp.node, main.crime.PICKPOCKET, "", 0, true)
	barter = null
	barter_total = null
	barter_total_label = null
	if main != null and main.get("map_window") != null and main.map_window.visible and main.map_window.embedded:
		if is_pinned("map") and _allowed("map") and not was_container:
			main.map_window.set_pinned_mode(true)
		else:
			main.map_window.close()
	if not was_container:
		_keep_pinned()
	if _root != null:
		_root.queue_free()
		_root = null
	windows = {}
	if not "inventory" in _pinned_windows:
		_grid = null
	_cont_grid = null
	cont_sid = ""
	companion = {}
	_comp_bar = null
	if not "stats" in _pinned_windows:
		_stat_left = null
	if not "spells" in _pinned_windows:
		_spell_list = null
	if not "inventory" in _pinned_windows:
		_doll_vp = null
		_inv_left = null
		_doll = null
	_set_hud(true)
	closed.emit()

## [Windows] <okno> x/y/w/h – globalnie (main.window_store), nie w zapisie gry.
func _layout_store() -> Dictionary:
	if main == null or not main.has_method("window_store"):
		return {}
	return main.window_store("ui_windows")

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
	if main != null and main.has_method("save_window_settings"):
		main.save_window_settings()

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
	var tl := Label.new()
	tl.name = "Text"
	var head := UI.add_head(box, tl, scale_ui)
	head.name = "Title"
	head.gui_input.connect(_drag_window.bind(w))
	head.gui_input.connect(_title_input.bind(name))
	# MW_Window_Pinnable: przycisk pinezki przy prawym końcu paska tytułu
	var pin := UI.pin_button(scale_ui, is_pinned(name))
	pin.gui_input.connect(_pin_input.bind(name, pin))
	head.add_child(pin)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	# zmiana rozmiaru krawędziami okna jak skórka MW_Window (openmw_windows.skin.xml, widżety „Action”): krawędzie
	# 4 px (TB_T/L/R/B, od 14 px od rogów), rogi z trzech części (4 × 4 i dwa odcinki 10 × 4 / 4 × 10); Scale –
	# przesunięcie lewej/górnej krawędzi i zmiana rozmiaru; kursory hresize/vresize/dresize/dresize2. W nakładce nad
	# treścią (Body wypełnia obszar Client).
	var over := Control.new()
	over.name = "Overlay"
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(over)
	# nakładka leży w obszarze treści panelu – strefy wysunięte o marginesy skórki do zewnętrznej krawędzi okna
	var sb: StyleBox = w.get_theme_stylebox("panel")
	var ml := sb.get_margin(SIDE_LEFT) if sb != null else 0.0
	var mt := sb.get_margin(SIDE_TOP) if sb != null else 0.0
	var mr := sb.get_margin(SIDE_RIGHT) if sb != null else 0.0
	var mb := sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0
	var hx := func(anchor: float, off: float) -> float: return off * scale_ui + (mr if anchor > 0.5 else -ml)
	var vy := func(anchor: float, off: float) -> float: return off * scale_ui + (mb if anchor > 0.5 else -mt)
	for a in WINDOW_ACTIONS:
		var z := Control.new()
		z.name = "Resize_" + String(a[0])
		var r: Array = a[1]                        # [anchor_l, off_l, anchor_t, off_t, anchor_r, off_r, anchor_b, off_b]
		z.anchor_left = r[0]
		z.offset_left = hx.call(float(r[0]), float(r[1]))
		z.anchor_top = r[2]
		z.offset_top = vy.call(float(r[2]), float(r[3]))
		z.anchor_right = r[4]
		z.offset_right = hx.call(float(r[4]), float(r[5]))
		z.anchor_bottom = r[6]
		z.offset_bottom = vy.call(float(r[6]), float(r[7]))
		z.mouse_default_cursor_shape = int(a[3])
		z.gui_input.connect(_resize_window.bind(w, a[2]))
		over.add_child(z)
	return w

# --- przypinanie, ukrywanie, maksymalizacja (WindowPinnableBase, WindowManager) -----------------------------

func _ui(key: String) -> Dictionary:
	if main == null or not main.has_method("window_store"):
		return {}
	return main.window_store(key)

func _ui_changed() -> void:
	if main != null and main.has_method("save_window_settings"):
		main.save_window_settings()

## [Windows] <okno> pin
func is_pinned(n: String) -> bool:
	return bool(_ui("ui_pins").get(n, false))

## [Windows] <okno> hidden (WindowManager::toggleVisible)
func is_hidden(n: String) -> bool:
	return bool(_ui("ui_hidden").get(n, false))

func _pin_input(e: InputEvent, n: String, b: Control) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		toggle_pin(n)
		UI.set_pin_skin(b, is_pinned(n))
		b.accept_event()

## WindowPinnableBase::onPinButtonPressed: przypięte okno zostaje poza trybem GUI, a jego część HUD się chowa.
func toggle_pin(n: String) -> void:
	_ui("ui_pins")[n] = not is_pinned(n)
	_ui_changed()
	if main != null and main.get("mw_hud") != null and main.mw_hud.has_method("_apply_allowed"):
		main.mw_hud._apply_allowed()

## WindowBase::onTitleDoubleClicked (Stats/Inventory/Spell/MapWindow): z Shift – maksymalizacja,
## bez – ukrycie okna, jeśli nie jest przypięte.
func _title_input(e: InputEvent, n: String) -> void:
	if e is InputEventMouseButton and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
		if e.shift_pressed:
			toggle_maximized(n)
		elif not is_pinned(n):
			toggle_visible(n)

## WindowManager::toggleVisible: tylko w trybie Interface; zmienia ustawienie „hidden”.
func toggle_visible(n: String) -> void:
	if not visible or not cont_sid.is_empty():
		return
	if n == "magic":
		n = "spells"
	_ui("ui_hidden")[n] = not is_hidden(n)
	_ui_changed()
	_apply_shown()

func _apply_shown() -> void:
	for n in windows:
		(windows[n] as Control).visible = not is_hidden(n)
	if main != null and main.get("map_window") != null and main.map_window.visible and main.map_window.embedded:
		main.map_window.set_window_visible(not is_hidden("map"))

## WindowManager::toggleMaximized: zamiana na prostokąt „maximized” z ustawień i z powrotem.
func toggle_maximized(n: String) -> void:
	var vp := get_viewport().get_visible_rect().size
	var mx := _ui("ui_max")
	var to_max := not bool(mx.get(n, false))
	var r: Rect2 = MAX_RECTS[n] if to_max else _rect_frac(n)
	var w: Control = windows.get(n) if n != "map" else (main.map_window._win if main != null and main.get("map_window") != null else null)
	if w != null:
		w.position = (r.position * vp).floor()
		w.size = (r.size * vp).floor()
		if n == "map":
			w.custom_minimum_size = w.size
	mx[n] = to_max
	_ui_changed()

## Prostokąt zwykły (zapamiętany albo domyślny) w ułamkach ekranu.
func _rect_frac(n: String) -> Rect2:
	var saved = _layout_store().get(n)
	if saved is Array and saved.size() == 4:
		return Rect2(float(saved[0]), float(saved[1]), float(saved[2]), float(saved[3]))
	return DEFAULT_RECTS[n]

## HUD::on*Clicked w trybie Interface: paski – statystyki, broń – ekwipunek, czar – magia, minimapa – mapa
## (tło trybu menu leży nad HUD, więc kliknięcie przychodzi tutaj).
## HUD::onWorldClicked w trybie ekwipunku/pojemnika (bez przedmiotu przy kursorze) → InventoryWindow::pickUpObject:
## przedmiot pod kursorem (getFocusObject w trybie GUI) do ekwipunku i od razu przy kursorze (startDrag); z Alt –
## tylko do ekwipunku (dźwięk odłożenia). Warunki: ekwipunek dozwolony, przedmiot z podpowiedzią, skrypt bez OnActivate
## (RefData::activate), gracz nie sparaliżowany, nie powalony, żywy. → czy kliknięcie obsłużone
func world_pick(screen: Vector2, mods := {}) -> bool:
	if main == null or not main.has_method("gui_focus_object") or barter != null or not companion.is_empty():
		return false
	if main.has_method("menu_allowed") and not main.menu_allowed("inventory"):
		return false
	var node: Node = main.gui_focus_object(screen)
	if node == null or main.interaction.kind_of(node) != "item":
		return false
	var c: Dictionary = main.interaction.snapshot(node)
	if String(c.get("name", "")).is_empty():
		return false                                  # hasToolTip
	var scr: String = String(main.interaction.base_of(node).get("script", ""))
	if main.get("scripts") != null and main.scripts != null and not scr.is_empty() and main.scripts.uses(scr, "onactivate"):
		main.scripts.activated[String(c.sid)] = true  # Flag_SuppressActivate: aktywacja przez skrypt
		return true
	if main.get("magic") != null and main.magic != null:
		main.magic.break_invisibility(main.combat.player_fighter())
	var me: Dictionary = main.combat.player_fighter()
	if main.combat.magic_effect(me, 45) > 0.0 or main.combat.knocked_down(me) or main.combat.is_dead(me):
		return true
	var r: Dictionary = main.interaction.take_ref(c)
	var id := String(r.get("item", ""))
	var n := int(r.get("count", 0))
	if id.is_empty() or n <= 0:
		return true
	if is_holding():
		held = {}
		_hide_held()
	if bool(mods.get("alt", false)):
		if main.get("audio") != null:
			main.audio.play(main.interaction.item_sound(id, false))    # getDownSoundId
	else:
		if main.get("audio") != null:
			main.audio.play(main.interaction.item_sound(id, true))     # startDrag: getUpSoundId
		held = {"id": id, "count": n, "worn": false}
		_show_held()
	refresh()
	return true

func hud_click(pos: Vector2) -> bool:
	if main == null or main.get("mw_hud") == null or not cont_sid.is_empty():
		return false
	var hud = main.mw_hud
	var parts := [["stats", hud.bars.values()], ["inventory", [hud.weap_box]], ["magic", [hud.spell_box]], ["map", [hud.minimap]]]
	for part in parts:
		for c in part[1]:
			if c != null and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(pos):
				if part[0] in ["inventory", "magic"] and bool(main.player_stats().get("werewolf", false)):
					main.message_box(_t("sWerewolfRefusal", "You cannot do that as a werewolf."))
					return true
				toggle_visible(String(part[0]))
				return true
	return false

## Poza trybem GUI: przypięte (i dozwolone) okna na osobnej warstwie, odświeżane co 0,5 s.
func _keep_pinned() -> void:
	if _pin_layer != null:
		_pin_layer.queue_free()
		_pin_layer = null
	var keep := []
	for n in windows:
		if is_pinned(n) and _allowed(n):         # updateVisible: pinned && allowed && !forceHidden
			keep.append(n)
	if keep.is_empty():
		return
	_pin_layer = CanvasLayer.new()
	_pin_layer.name = "PinnedWindows"
	_pin_layer.layer = 19
	add_sibling(_pin_layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme = UI.theme(scale_ui)
	_pin_layer.add_child(holder)
	for n in keep:
		var w: Control = windows[n]
		w.visible = true
		w.reparent(holder)
		w.propagate_call("set", ["mouse_filter", Control.MOUSE_FILTER_IGNORE])
	_pinned_windows = keep

var _pinned_windows: Array = []

func _process(delta: float) -> void:
	if _held_icon != null:                    # ControllerFollowMouse: lewy górny róg ikony w punkcie kursora
		_held_icon.position = get_viewport().get_mouse_position()
	if _pin_layer == null or visible:
		return
	_pin_t += delta
	if _pin_t < 0.5:
		return
	_pin_t = 0.0
	if "stats" in _pinned_windows:
		_refresh_stats()
	if "inventory" in _pinned_windows:
		_refresh_inventory()
	if "spells" in _pinned_windows:
		_refresh_spells()

func _title(name: String, text: String) -> void:
	if windows.has(name):
		(windows[name].get_node("Box/CaptionArea/Title/Client/Text") as Label).text = text

func _body(name: String) -> VBoxContainer:
	return windows[name].get_node("Box/Body") as VBoxContainer

func _drag_window(e: InputEvent, w: Control) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var vp := get_viewport().get_visible_rect().size
		w.position = (w.position + e.relative).clamp(Vector2.ZERO, vp - Vector2(40, 20))

## Widżety „Action” skórki MW_Window: [nazwa, kotwice/przesunięcia (px okna 256 × 256 → kotwice), Scale (x, y, w, h),
## kursor]. Kotwica 0 – od lewej/górnej, 1 – od prawej/dolnej krawędzi.
const WINDOW_ACTIONS := [
	["T", [0, 14, 0, 0, 1, -14, 0, 4], [0, 1, 0, -1], Control.CURSOR_VSIZE],
	["L", [0, 0, 0, 14, 0, 4, 1, -14], [1, 0, -1, 0], Control.CURSOR_HSIZE],
	["R", [1, -4, 0, 14, 1, 0, 1, -14], [0, 0, 1, 0], Control.CURSOR_HSIZE],
	["B", [0, 14, 1, -4, 1, -14, 1, 0], [0, 0, 0, 1], Control.CURSOR_VSIZE],
	["TL_T", [0, 4, 0, 0, 0, 14, 0, 4], [1, 1, -1, -1], Control.CURSOR_FDIAGSIZE],
	["TL", [0, 0, 0, 0, 0, 4, 0, 4], [1, 1, -1, -1], Control.CURSOR_FDIAGSIZE],
	["TL_B", [0, 0, 0, 4, 0, 4, 0, 14], [1, 1, -1, -1], Control.CURSOR_FDIAGSIZE],
	["TR_T", [1, -14, 0, 0, 1, -4, 0, 4], [0, 1, 1, -1], Control.CURSOR_BDIAGSIZE],
	["TR", [1, -4, 0, 0, 1, 0, 0, 4], [0, 1, 1, -1], Control.CURSOR_BDIAGSIZE],
	["TR_B", [1, -4, 0, 4, 1, 0, 0, 14], [0, 1, 1, -1], Control.CURSOR_BDIAGSIZE],
	["BL_T", [0, 0, 1, -14, 0, 4, 1, -4], [1, 0, -1, 1], Control.CURSOR_BDIAGSIZE],
	["BL", [0, 0, 1, -4, 0, 4, 1, 0], [1, 0, -1, 1], Control.CURSOR_BDIAGSIZE],
	["BL_B", [0, 4, 1, -4, 0, 14, 1, 0], [1, 0, -1, 1], Control.CURSOR_BDIAGSIZE],
	["BR_T", [1, -4, 1, -14, 1, 0, 1, -4], [0, 0, 1, 1], Control.CURSOR_FDIAGSIZE],
	["BR", [1, -4, 1, -4, 1, 0, 1, 0], [0, 0, 1, 1], Control.CURSOR_FDIAGSIZE],
	["BR_B", [1, -14, 1, -4, 1, -4, 1, 0], [0, 0, 1, 1], Control.CURSOR_FDIAGSIZE],
]

## Window::notifyMouseDrag (MyGUI) dla widżetu „Action”: przesunięcie myszy × Scale – lewa/górna krawędź i rozmiar,
## z minimalnym rozmiarem okna (krawędź przeciwna stoi w miejscu).
func _resize_window(e: InputEvent, w: Control, sc := [0, 0, 1, 1]) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var d: Vector2 = e.relative
		var new_size := w.size + Vector2(d.x * float(sc[2]), d.y * float(sc[3]))
		var clamped := new_size.max(w.custom_minimum_size)
		var pos := w.position
		if float(sc[0]) != 0.0:
			pos.x += w.size.x - clamped.x             # lewa krawędź: prawa zostaje
		if float(sc[1]) != 0.0:
			pos.y += w.size.y - clamped.y
		w.position = pos
		w.size = clamped
		_layout_grid.call_deferred()

func refresh() -> void:
	if not visible:
		return
	_refresh_stats()
	_refresh_inventory()
	_refresh_spells()
	_refresh_container()

func is_suspended_gui() -> bool:
	return bool(get_meta("gui_suspended", false))

func _unhandled_input(e: InputEvent) -> void:
	if not visible or is_suspended_gui():
		return
	if e.is_action_pressed("menu_mode") or e.is_action_pressed("inventory") or e.is_action_pressed("magic_menu") \
			or e.is_action_pressed("map_menu") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()

# --- statystyki -----------------------------------------------------------------------------------------

var _stat_bars := {}
var _stat_boxes: Array = []
var _stat_left: Control
var _stat_right: VBoxContainer
## StatsWindow::addSkills: wartość kończy się 24 px przed prawą krawędzią SkillView (coord1 = W − (10 + v) − 24);
## treść kończy się 18 px przed krawędzią (pasek 14 + 4 jak MW_ScrollView), odstęp HBox 4 → dopełnienie 2.
const SKILL_RIGHT_PAD := 2.0

## openmw_stats_window.layout + StatsWindow::onWindowResize: lewa część 0,44 szerokości okna z trzema polami MW_Box
## (paski 62 px, poziom/rasa/klasa 62 px, atrybuty do dołu; odstępy 8 px), prawa – pole umiejętności z przewijaniem.
## Zawartość nie narzuca szerokości (napisy przycinane), więc okno ma rozmiar z ustawień OpenMW.
func _build_stats() -> void:
	var body := _body("stats")
	# obszar Client z przycinaniem: panele rozmieszcza _layout_stats (StatsWindow::onWindowResize)
	var client := Control.new()
	client.name = "StatsClient"
	client.clip_contents = true
	client.size_flags_vertical = Control.SIZE_EXPAND_FILL
	client.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(client)
	_stat_left = client
	_stat_boxes = []
	var boxes: Array = []
	for i in 3:
		var bp := PanelContainer.new()
		var sb: StyleBox = UI.inner_box().duplicate()
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_content_margin(side, 4 * scale_ui)
		if i == 1:
			sb.content_margin_bottom = 2 * scale_ui        # trzeci wiersz (4, 42, …, 18) kończy się 2 px przed dołem
		bp.add_theme_stylebox_override("panel", sb)
		bp.clip_contents = true
		client.add_child(bp)
		boxes.append(bp)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < 2:
			bp.add_child(v)
		else:
			# AttributeView: przewijany widok bez paska – lista nie narzuca wysokości okna
			var sc := ScrollContainer.new()
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
			bp.add_child(sc)
			sc.add_child(v)
		_stat_boxes.append(v)
	var rp := PanelContainer.new()
	rp.name = "Skills"
	var rsb: StyleBox = UI.inner_box().duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		rsb.set_content_margin(side, 4 * scale_ui)          # SkillView (4, 4) w MW_Box
	rp.add_theme_stylebox_override("panel", rsb)
	rp.clip_contents = true
	client.add_child(rp)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.mw_scroll_view(rs, scale_ui)                     # SkillView: MW_ScrollView
	rp.add_child(rs)
	_stat_right = VBoxContainer.new()
	_stat_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_right.add_theme_constant_override("separation", 0)     # wiersze co 18 px (fontSize + 2)
	rs.add_child(_stat_right)
	client.resized.connect(_layout_stats.bind(boxes, rp))
	_layout_stats(boxes, rp)

## StatsWindow::onWindowResize (openmw_stats_window.layout 500 × 342, LeftPaneRatio 0,44, LeftOffsetWidth 24):
## panele mają wysokość całego okna (H) i leżą w obszarze Client (przycinane): lewy – szerokość int(0,44 × W), MW_Box
## w (8, 8 / 78 / 148) do prawej krawędzi panelu, ostatni do 42 px przed dołem; prawy – od lewego, int(0,56 × W),
## ramka umiejętności (8, 8) do 24 px przed prawą krawędzią i 42 px przed dołem. Węższe okno: minimalna szerokość
## lewego panelu int(500 × 0,44), a poniżej niej + 24 px – sam lewy panel.
func _layout_stats(boxes: Array, rp: Control) -> void:
	if not windows.has("stats"):
		return
	var win := windows["stats"] as Control
	var s := scale_ui
	var W := int(win.size.x)
	var H := int(win.size.y)
	var min_full := int(500 * s)
	var min_left := int(min_full * 0.44)
	var lw: int
	var rx := 0
	var rw := 0
	rp.visible = W >= min_left + int(24 * s)
	if not rp.visible:
		lw = W - int(24 * s)
	elif W < min_full:
		lw = min_left
		rx = min_left
		rw = W - min_left
	else:
		lw = int(0.44 * W)
		rx = lw
		rw = int(0.56 * W)
	var tops := [8, 78, 148]
	for i in 3:
		var bp := boxes[i] as Control
		var top := roundf(tops[i] * s)
		var h := roundf(62 * s) if i < 2 else maxf(0.0, H - top - roundf(42 * s))
		bp.position = Vector2(roundf(8 * s), top)
		bp.size = Vector2(maxf(0.0, lw - roundf(8 * s)), h)
	rp.position = Vector2(rx + roundf(8 * s), roundf(8 * s))
	rp.size = Vector2(maxf(0.0, rw - roundf(32 * s)), maxf(0.0, H - roundf(50 * s)))

## Wiersz nazwa–wartość. indent/right_pad – StatsWindow::addValueItem (nazwa od x = 10, wartość przy prawej krawędzi
## z miejscem na pasek przewijania), wysokość wiersza = rozmiar czcionki + 2.
func _row(parent: Control, left: String, right: String, tip: Variant = "", col := Color(0, 0, 0, 0), indent := 0.0, right_pad := 0.0, left_skin := "SandText") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 18 * scale_ui
	if indent > 0.0:
		var sp := Control.new()
		sp.custom_minimum_size.x = indent * scale_ui
		h.add_child(sp)
	var a := Label.new()
	a.text = left
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.clip_text = true
	UI.text_skin(a, left_skin, scale_ui)            # nazwa: SandText (NormalText w polu poziom/rasa/klasa)
	h.add_child(a)
	var b := Label.new()
	b.text = right
	UI.text_skin(b, "SandTextRight", scale_ui)      # wartość
	if col.a > 0.0:
		b.add_theme_color_override("font_color", col)
	h.add_child(b)
	if right_pad > 0.0:
		var rp := Control.new()
		rp.custom_minimum_size.x = right_pad * scale_ui
		h.add_child(rp)
	if tip is Dictionary and not (tip as Dictionary).is_empty():
		h.set_meta("mw_tip", tip)                  # ToolTips typu Layout (umiejętność, atrybut, klasa…)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
	elif tip is String and not (tip as String).is_empty():
		h.tooltip_text = tip
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		a.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(h)
	return h

func _bar_row(parent: Control, label: String, kind: String, cur: float, mx: float) -> void:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = label
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.clip_text = true
	h.add_child(a)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(130, 18) * scale_ui      # ProgressBar 130 × 18 przy prawej krawędzi
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
	# openmw_stats_window.layout: HealthToolTip (ikona, sHealthDesc/sMagDesc/sFatDesc, „bieżące / największe”)
	if main != null and main.get("tooltips") != null and main.tooltips != null:
		h.set_meta("mw_tip", main.tooltips.health_tip(kind, roundi(cur), roundi(mx)))
		h.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(h)
	_stat_bars[kind] = pb

## StatsWindow::addGroup: nagłówek SandBrightText w wierszu fontSize + 2 (18 px), wyrównany do dołu.
func _group(l: Label) -> Label:
	l.custom_minimum_size.y = 18 * scale_ui
	return UI.text_skin(l, "SandBrightText", scale_ui)

## MW_HLine w liście umiejętności (StatsWindow::addSeparator): od x = 10, szerokość widoku − 38, wysokość 18.
func _hline() -> Control:
	return preload("res://scripts/mw/mw_list.gd").hline(scale_ui, 10.0, 28.0)

func _val_color(base: float, mod: float) -> Color:
	if mod > base + 0.01:
		return UI.color("positive")
	if mod < base - 0.01:
		return UI.color("negative")
	return UI.color("normal")

func _refresh_stats() -> void:
	if _stat_left == null or main == null:
		return
	for c in _stat_boxes[0].get_children() + _stat_boxes[1].get_children() + _stat_boxes[2].get_children() + _stat_right.get_children():
		c.queue_free()
	var st: Dictionary = main.player_stats()
	# StatsWindow: tytuł – imię postaci (bez kreatora: nazwa rekordu NPC „player”)
	var pname := String(st.get("name", ""))
	if pname.is_empty() and main.builder != null and main.builder.actors != null:
		pname = String(main.builder.actors.record("npc", "player").get("name", ""))
	_title("stats", pname if not pname.is_empty() else _t("sStats", "Stats"))
	if st.is_empty() or main.character == null:
		return
	var ch = main.character
	var d: Dictionary = ch.derived(st)
	_bar_row(_stat_boxes[0], _t("sHealth", "Health"), "health", float(st.get("health", 0)), float(d.health.modified))
	_bar_row(_stat_boxes[0], _t("sMagic", "Magicka"), "magic", float(st.get("magicka", 0)), float(d.magicka.modified))
	_bar_row(_stat_boxes[0], _t("sFatigue", "Fatigue"), "fatigue", float(st.get("fatigue", 0)), float(d.fatigue.modified))
	var prog: Dictionary = st.get("progress", {})
	var tt = main.get("tooltips")
	# LevelToolTip: postęp do awansu (iLevelUpTotal) i mnożniki atrybutów > 1 (getLevelupAttributeMultiplier)
	var lvl_tip: Variant = ""
	if tt != null:
		var total := int(main.combat._gmst("iLevelUpTotal", 10))
		var det := []
		var base_attr: Array = st.get("attributes", [])
		for ai in 8:
			var mult := int(main.character.levelup_multiplier(st, ai))
			mult = mini(mult, 100 - int(float(base_attr[ai]) if ai < base_attr.size() else 0.0))
			if mult > 1:
				det.append("%s x%d" % [_t(ATTR_GMST[ai], ATTR_EN[ai]), mult])
		lvl_tip = tt.level_tip(int(st.get("level_progress", prog.get("level", 0))), total, "\n".join(det))
	_row(_stat_boxes[1], _t("sLevel", "Level"), str(int(st.get("level", 1))), lvl_tip, Color(0, 0, 0, 0), 0.0, 0.0, "NormalText")
	var lv_gap := Control.new()                     # wiersze HBox w (4, 4), (4, 24), (4, 42)
	lv_gap.custom_minimum_size.y = 2 * scale_ui
	_stat_boxes[1].add_child(lv_gap)
	var race: Dictionary = main.builder.actors.record("race", String(st.get("race", "")))
	_row(_stat_boxes[1], _t("sRace", "Race"), String(race.get("name", st.get("race", ""))), tt.race_tip(race) if tt != null and not race.is_empty() else "", Color(0, 0, 0, 0), 0.0, 0.0, "NormalText")
	var cls: Dictionary = ch._class_of(st)
	_row(_stat_boxes[1], _t("sClass", "Class"), String(cls.get("name", st.get("class", ""))), tt.class_tip(cls) if tt != null else "", Color(0, 0, 0, 0), 0.0, 0.0, "NormalText")
	var base_a: Array = st.get("attributes", [])
	for i in 8:
		var b := float(base_a[i]) if i < base_a.size() else 0.0
		var m := float(d.attributes[i])
		_row(_stat_boxes[2], _t(ATTR_GMST[i], ATTR_EN[i]), str(int(m)), tt.attribute_tip(i) if tt != null else "", _val_color(b, m))
	# umiejętności
	var names: Array = main.builder.actors.records_index().get("skills", [])
	var major: Array = cls.get("major_skills", [])
	var minor: Array = cls.get("minor_skills", [])
	var groups := [["sSkillClassMajor", "Major Skills", major], ["sSkillClassMinor", "Minor Skills", minor]]
	var misc := []
	for i in 27:
		if not (i in major or float(i) in major) and not (i in minor or float(i) in minor):
			misc.append(i)
	groups.append(["sSkillClassMisc", "Misc Skills", misc])
	var base_s: Array = st.get("skills", [])
	var sprog: Array = prog.get("skills", [])
	for g in groups:
		_stat_right.add_child(_group(UI.header(_t(g[0], g[1]))))
		for sk in g[2]:
			var i := int(sk)
			if i < 0 or i >= 27:
				continue
			var sid := String(names[i]) if i < names.size() else str(i)
			var b2 := float(base_s[i]) if i < base_s.size() else 0.0
			var m2 := float(d.skills[i])
			var req: float = ch.skill_requirement(st, i)
			# StatsWindow::setValue: postęp w procentach int(postęp / wymaganie × 100 + 0,5); umiejętność ≥ 100 – sSkillMaxReached
			var pct := int(float(sprog[i] if i < sprog.size() else 0.0) / maxf(req, 0.0001) * 100.0 + 0.5)
			var tip: Variant = tt.skill_tip(i, pct, b2 >= 100.0) if tt != null else ""
			_row(_stat_right, _t("sSkill" + sid.capitalize().replace(" ", ""), sid.capitalize()), str(int(m2)), tip, _val_color(b2, m2), 10.0, SKILL_RIGHT_PAD)
		_stat_right.add_child(_hline())
	var facs: Dictionary = st.get("factions", {})
	if not facs.is_empty():
		_stat_right.add_child(_group(UI.header(_t("sFaction", "Factions"))))
		for fid in facs:
			var fr: Dictionary = main.builder.actors.record("faction", String(fid))
			if bool(fr.get("hidden", false)):
				continue
			var rank := int((facs[fid] as Dictionary).get("rank", 0))
			var ranks: Array = fr.get("ranks", [])
			var rname := String(ranks[rank]) if rank >= 0 and rank < ranks.size() and ranks[rank] is String else ""
			if rank >= 0 and rank < ranks.size() and ranks[rank] is Dictionary:
				rname = String((ranks[rank] as Dictionary).get("name", ""))
			_row(_stat_right, String(fr.get("name", fid)), rname, _faction_tip(fr, rank, bool((facs[fid] as Dictionary).get("expelled", false))) if tt != null else "", Color(0, 0, 0, 0), 10.0, SKILL_RIGHT_PAD)
		_stat_right.add_child(_hline())
	var sign: Dictionary = main.builder.actors.record("birthsign", String(st.get("birthsign", "")))
	if not sign.is_empty():
		_row(_stat_right, _t("sBirthSign", "Birthsign"), String(sign.get("name", "")), tt.birthsign_tip(sign) if tt != null else "", Color(0, 0, 0, 0), 10.0, SKILL_RIGHT_PAD)
	_row(_stat_right, _t("sReputation", "Reputation"), str(int(st.get("reputation", 0))), tt.text_tip(_t("sSkillsMenuReputationHelp", "")) if tt != null else "", Color(0, 0, 0, 0), 10.0, SKILL_RIGHT_PAD)
	_row(_stat_right, _t("sBounty", "Bounty"), str(int(st.get("bounty", 0))), tt.text_tip(_t("sCrimeHelp", "")) if tt != null else "", Color(0, 0, 0, 0), 10.0, SKILL_RIGHT_PAD)

## StatsWindow::addItem frakcji: FactionToolTip – nazwa (nagłówek), ranga albo sExpelled; gdy jest wyższa ranga:
## sNextRank, wymagania atrybutów, sFavoriteSkills, sNeedOneSkill / sNeedTwoSkills.
func _faction_tip(fr: Dictionary, rank: int, expelled: bool) -> Dictionary:
	var lines := [["header", String(fr.get("name", ""))]]
	var ranks: Array = fr.get("ranks", [])
	var rn := func(i: int) -> String:
		if i < 0 or i >= ranks.size():
			return ""
		return String((ranks[i] as Dictionary).get("name", "")) if ranks[i] is Dictionary else String(ranks[i])
	if expelled:
		lines.append(["normal", _t("sExpelled", "Expelled")])
	else:
		var r := maxi(0, rank)
		if r < ranks.size():
			lines.append(["normal", rn.call(r)])
		if r + 1 < ranks.size() and not String(rn.call(r + 1)).is_empty():
			lines.append(["normal", ""])
			lines.append(["header", "%s %s" % [_t("sNextRank", "Next Rank:"), rn.call(r + 1)]])
			var req: Array = fr.get("rank_requirements", [])
			var rq: Dictionary = req[r + 1] if r + 1 < req.size() and req[r + 1] is Dictionary else {}
			var at: Array = fr.get("attributes", [0, 0])
			lines.append(["normal", "%s: %d, %s: %d" % [_t(ATTR_GMST[clampi(int(at[0]), 0, 7)], ""), int((rq.get("attributes", [0, 0]) as Array)[0]),
				_t(ATTR_GMST[clampi(int(at[1]) if at.size() > 1 else 0, 0, 7)], ""), int((rq.get("attributes", [0, 0]) as Array)[1])]])
			lines.append(["normal", ""])
			lines.append(["header", _t("sFavoriteSkills", "Favorite Skills")])
			var sk := []
			for i in fr.get("skills", []):
				if int(i) >= 0:
					sk.append(main.tooltips._skill_name(int(i)))
			lines.append(["normal", ", ".join(sk)])
			var need := ""
			if int(rq.get("primary_skill", 0)) > 0:
				need = "%s %d" % [_t("sNeedOneSkill", "Need one skill at"), int(rq.primary_skill)]
			if int(rq.get("favoured_skill", 0)) > 0:
				need += " %s %s %d" % [_t("sand", "and"), _t("sNeedTwoSkills", "two skills at"), int(rq.favoured_skill)]
			lines.append(["normal", ""])
			lines.append(["normal", need.strip_edges()])
	return main.tooltips.faction_tip(lines)

# --- ekwipunek ------------------------------------------------------------------------------------------

func _build_inventory() -> void:
	var body := _body("inventory")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# LeftPane (0, 0, L, H − 44) z polami od x = 8 do 4 px przed prawą krawędzią, RightPane od L + 4 o szerokości
	# W − L − 27 (7 px przed prawą krawędzią Client); obie części kończą się 8 px nad dołem Client
	cols.add_theme_constant_override("separation", roundi(8 * scale_ui))
	body.add_child(cols)
	# lewa część (openmw_inventory_window.layout, LeftPane 224 px): pasek obciążenia 212 × 24 (MW_ChargeBar_Blue),
	# odstęp 6, ramka postaci (MW_Box) z wartością pancerza w dolnych 24 px (ProgressText)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = 0
	_inv_left = left
	var iw: Control = windows["inventory"]
	iw.resized.connect(_adjust_inv_panes)
	_adjust_inv_panes()
	left.add_theme_constant_override("separation", roundi(6 * scale_ui))
	var left_m := MarginContainer.new()
	left_m.name = "LeftPane"
	left_m.size_flags_horizontal = 0
	left_m.add_theme_constant_override("margin_left", roundi(8 * scale_ui))
	left_m.add_theme_constant_override("margin_top", roundi(8 * scale_ui))
	left_m.add_theme_constant_override("margin_bottom", roundi(8 * scale_ui))
	cols.add_child(left_m)
	left_m.add_child(left)
	var enc := Control.new()
	enc.name = "EncumbranceBar"
	enc.custom_minimum_size.y = 24 * scale_ui
	left.add_child(enc)
	_enc_bar = UI.progress_bar("magic", scale_ui)
	_enc_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	enc.add_child(_enc_bar)
	_enc_label = Label.new()
	_enc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enc_label.add_theme_color_override("font_color", UI.color("normal"))
	enc.add_child(_enc_label)
	var avatar = _DollDrop.new()
	avatar.name = "Avatar"
	avatar.add_theme_stylebox_override("panel", UI.inner_box())
	avatar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar.menu = self
	avatar.target = "avatar"
	left.add_child(avatar)
	var av_box := Control.new()
	av_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(av_box)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.offset_bottom = -24 * scale_ui
	av_box.add_child(svc)
	_doll_vp = SubViewport.new()
	_doll_vp.own_world_3d = true
	_doll_vp.transparent_bg = true
	_doll_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_doll_vp)
	_armor_label = Label.new()
	_armor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_armor_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_armor_label.offset_top = -24 * scale_ui
	_armor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_box.add_child(_armor_label)
	# prawa część: kategorie i siatka
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Categories (0, 6, …, 28), ItemView od y = 38
	right.add_theme_constant_override("separation", roundi(4 * scale_ui))
	var right_m := MarginContainer.new()
	right_m.name = "RightPane"
	right_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_m.add_theme_constant_override("margin_top", roundi(6 * scale_ui))
	right_m.add_theme_constant_override("margin_right", roundi(7 * scale_ui))
	right_m.add_theme_constant_override("margin_bottom", roundi(8 * scale_ui))
	cols.add_child(right_m)
	right_m.add_child(right)
	# wiersz kategorii: przy wąskim oknie (np. 0,45 × 1280) przyciski są przycinane jak w MyGUI, a nie rozpychają okna
	var tabs_clip := Control.new()
	tabs_clip.clip_contents = true
	right.add_child(tabs_clip)
	var tabs := HBoxContainer.new()
	tabs.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tabs.offset_top = 2 * scale_ui                # przyciski 24 px wyśrodkowane w wierszu 28 px (HBox)
	tabs_clip.add_child(tabs)
	tabs_clip.custom_minimum_size.y = 28 * scale_ui           # HBox Categories 28 px (przyciski 24 u góry)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = _t(c[1], c[2])
		b.toggle_mode = true
		b.button_pressed = c[0] == category
		# zaznaczona kategoria: stany normal_checked/highlighted_checked skórki MW_Button – kolory „active”
		b.add_theme_color_override("font_pressed_color", UI.color("active"))
		b.add_theme_color_override("font_hover_pressed_color", UI.color("active_over"))
		b.pressed.connect(set_category.bind(String(c[0])))
		b.custom_minimum_size.y = 24 * scale_ui        # AutoSizedButton (0, 0, 60, 24)
		tabs.add_child(b)
		_cat_buttons[c[0]] = b
	# FilterEdit (MW_TextBoxEditWithBorder, HStretch): filtr nazw – SortFilterItemModel::setNameFilter
	inv_filter = LineEdit.new()
	inv_filter.name = "FilterEdit"
	inv_filter.set_meta("accept_tab", true)               # AcceptTab
	inv_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_filter.custom_minimum_size.x = 0
	inv_filter.text_changed.connect(func(_t2): _refresh_inventory())
	inv_filter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(inv_filter)
	# handel (GM_Barter): siatka gracza z modelem handlu – sprzedawane znikają, kupowane z tłem „barter”
	_grid = _make_grid(right, "player", barter) if barter != null else _make_grid(right, "inventory")

## InventoryWindow::adjustPanes: lewa część ma szerokość (wysokość okna − 44 − ArmorRating 24) × 0,5 (stały
## stosunek boków podglądu postaci 0,5), pola w niej od x = 8 do 4 px przed prawą krawędzią; reszta – siatka.
func _adjust_inv_panes() -> void:
	if _inv_left == null or not is_instance_valid(_inv_left) or not windows.has("inventory"):
		return
	var h: float = (windows["inventory"] as Control).size.y
	_inv_left.custom_minimum_size.x = maxf(0.0, floorf((h - 68.0 * scale_ui) * 0.5) - 12.0 * scale_ui)

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

## Klucze sortowania SortFilterItemModel::Compare dla wpisu {id, kind, rec, name}: stype (ItemStack::Type –
## 0 Barter, 1 Equipped, 2 Normal), ładunek zaklęcia w % (101 – stały efekt, −1 – bez zaklęcia), stan (−1 – bez
## stanu), pozostały czas użycia, wartość i waga. holder – „player” (ładunki z postaci) albo "" (pełne).
func sort_keys(e: Dictionary, stype: int, holder := "") -> Dictionary:
	var rec: Dictionary = e.rec
	var kind := String(e.kind)
	e["stype"] = stype
	var pct := -1
	var ench := String(rec.get("enchant", "")).to_lower()
	if not ench.is_empty():
		var en: Dictionary = main.builder.actors.record("enchantment", ench)
		if not en.is_empty():
			if int(en.get("type", -1)) == 3:
				pct = 101
			else:
				var mx := 0.0
				if main.get("magic") != null:
					mx = float(main.magic.enchantment_charge(en))
				var cur := mx
				if holder == "player":
					cur = float((main.player_stats().get("item_charge", {}) as Dictionary).get(String(e.id).to_lower(), mx))
				pct = int((cur / mx if mx > 0.0 else 1.0) * 100.0)
	e["charge_pct"] = pct
	var has_health := kind in ["armor", "lockpick", "probe", "repair"] or (kind == "weapon" and int(rec.get("weapon_type", 0)) < 11)
	e["health"] = int(main.interaction.inventory.item_charge(String(e.id))) if has_health else -1
	e["usage"] = float(rec.get("time", -1.0)) if kind == "light" else -1.0
	e["value"] = int(rec.get("value", 0))
	e["weight"] = float(rec.get("weight", 0.0))
	return e

## SortFilterItemModel::Compare (OpenMW 0.51).
static func item_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a.stype) != int(b.stype):
		return int(a.stype) < int(b.stype)
	var ta := int(TYPE_ORDER.get(a.kind, 99))
	var tb := int(TYPE_ORDER.get(b.kind, 99))
	if ta != tb:
		return ta < tb
	var na := String(a.name).to_lower()
	var nb := String(b.name).to_lower()
	if na != nb:
		return na < nb
	if int(a.charge_pct) != int(b.charge_pct):
		return int(a.charge_pct) > int(b.charge_pct)
	if int(a.health) >= 0 and int(b.health) >= 0 and int(a.health) != int(b.health):
		return int(a.health) > int(b.health)
	if float(a.usage) != float(b.usage):
		return float(a.usage) > float(b.usage)
	if int(a.value) != int(b.value):
		return int(a.value) > int(b.value)
	if float(a.weight) != float(b.weight):
		return float(a.weight) > float(b.weight)
	return String(a.id) < String(b.id)

## Przedmioty pojemnika/gracza w kolejności SortFilterItemModel::Compare: założone najpierw, potem typ, nazwa,
## ładunek zaklęcia, stan, czas użycia, wartość, waga, id.
func sorted_items(sid := "player", rec := {}) -> Array:
	var inv = main.interaction.inventory
	var out := []
	var items: Array = inv.contents(sid, rec)
	var npc_worn := actor_worn(sid, rec, items) if sid != "player" else {}
	for e in items:
		var it: Dictionary = inv.item(String(e.id))
		if it.is_empty():
			continue
		var name: String = main.interaction.item_name(String(it.kind), String(e.id), it.rec)
		var wc := worn_copies(String(e.id)) if sid == "player" else int(npc_worn.get(String(e.id), 0))
		for st in item_stacks(e, it, wc):
			var worn := bool(st.worn)
			out.append(sort_keys({"id": String(e.id), "count": int(st.count), "kind": String(it.kind), "rec": it.rec, "worn": worn,
				"name": name, "magic": _enchanted(it), "stack": st}, 1 if worn else 2, "player" if sid == "player" else ""))
	out.sort_custom(item_less)
	return out

const SK_SNEAK := 19

## Klucz stosu (ItemStack) do porównań PickpocketItemModel (mHiddenItems).
static func _stack_key(e: Dictionary) -> String:
	return "%s|%s|%d" % [String(e.id), str(bool(e.get("worn", false))), int((e.get("stack", {}) as Dictionary).get("count", e.get("count", 0)))]

## PickpocketItemModel::update: bez przedmiotów przywołanych, ukrytych i założonych (Type_Equipped).
func pickpocket_items() -> Array:
	var out := []
	for e in sorted_items(cont_sid, cont_rec):
		if bool(e.get("worn", false)) or (main.get("trade") != null and main.trade.is_bound_item(String(e.id))):
			continue
		if (pickpocket.hidden as Dictionary).has(_stack_key(e)):
			continue
		out.append(e)
	return out

## Liczba założonych egzemplarzy przedmiotu gracza (miejsca ekwipunku z tym identyfikatorem).
func worn_copies(id: String) -> int:
	var eq: Dictionary = main.player_stats().get("equipment", {}) if main != null and main.has_method("player_stats") else {}
	var n := 0
	for s in eq:
		if eq[s] is Dictionary and String(eq[s].get("id", "")) == id.to_lower():
			n += 1
	return n

## Założone przedmioty NPC (zwłoki, towarzysz – InventoryItemModel aktora: Type_Equipped): id → liczba egzemplarzy,
## wg doboru wyposażenia aktora (autoEquip, jak przy wyglądzie i u kupca). Pojemnik i stworzenie – brak.
func actor_worn(sid: String, rec: Dictionary, items: Array) -> Dictionary:
	var out := {}
	if not rec.has("race") or main == null or main.get("builder") == null:
		return out
	var eq = main.builder.actors
	if eq.equipment == null:
		eq.equipment = eq.Equipment.new(eq)
	var slots: Dictionary = eq.equipment.auto_equip(rec, items)
	for slot in slots:
		var id := String((slots[slot] as Dictionary).get("id", "")).to_lower()
		if not id.is_empty():
			out[id] = int(out.get(id, 0)) + 1
	return out

## Stosy wpisu inwentarza jak ItemStack-i OpenMW: [{count, worn}]. InventoryStore::stacks – założony egzemplarz nie
## łączy się z niezałożonymi (osobny stos Type_Equipped; dwa jednakowe pierścienie – dwa stosy), chyba że przedmiot
## łączy się w stos także założony (getEquipmentSlots().second: amunicja i broń miotana – cały stos założony).
## ContainerStore::stacks – przedmioty ze skryptem: każdy stos osobno („parts” wpisu).
func item_stacks(e: Dictionary, it: Dictionary, worn = 0) -> Array:
	var parts: Array = Inv.stacks_of(e)
	var out := []
	if worn is bool:
		worn = worn_copies(String(e.id)) if worn else 0
	if worn > 0 and String(it.get("kind", "")) == "weapon" and int((it.get("rec", {}) as Dictionary).get("weapon_type", 0)) >= 11:
		if not parts.is_empty():
			out.append({"count": int(parts[0]), "worn": true})
			parts.remove_at(0)
		worn = 0
	while worn > 0 and not parts.is_empty():
		out.append({"count": 1, "worn": true})
		parts[0] = int(parts[0]) - 1
		if int(parts[0]) <= 0:
			parts.remove_at(0)
		worn -= 1
	for p in parts:
		out.append({"count": int(p), "worn": false})
	return out

## Siatka ikon w przewijanym obszarze (ItemView): zwraca kontrolkę siatki; source – „inventory” | „container”.
## owner – obiekt obsługujący activate_item(id, source), dropped_on(target, data) i (opcjonalnie) click_item(id, source)
## – tryb menu albo inne okno (handel, alchemia).
func _make_grid(parent: Control, source: String, owner = null) -> Control:
	var gp = _DollDrop.new()                      # obszar przyjmujący upuszczone przedmioty
	gp.name = "GridPanel"
	gp.menu = owner if owner != null else self
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

## entries: {"id","count","rec","magic","worn"} (+ „state”: "barter"/"equip", „tip” – dodatkowy wiersz podpowiedzi).
func _fill_grid(grid: Control, entries: Array, source: String, owner = null) -> Array:
	for c in grid.get_children():
		c.queue_free()
	var ids := []
	for e in entries:
		var cell = _ItemCell.new()
		cell.menu = owner if owner != null else self
		cell.item_id = e.id
		cell.source = String(e.get("source", source))
		cell.stack = e.get("stack", {})
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.custom_minimum_size = Vector2(CELL, CELL) * scale_ui
		cell.size = cell.custom_minimum_size
		set_item_tip(cell, String(e.id), int(e.count), String(e.get("tip", "")))
		var fr := UI.icon_frame(e.magic, String(e.get("state", "equip" if e.worn else "")))
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
			nl.text = String(e.get("name", main.interaction.item_name(String(e.get("kind", "")), String(e.id), e.rec) if main != null else e.id)).left(3)
			nl.position = Vector2(4, 8) * scale_ui
			nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(nl)
		if int(e.count) > 1 or e.has("count_text"):
			var cl := Label.new()
			cl.text = String(e.get("count_text", str(e.count)))
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

## WindowManager::setSelectedWeapon / unsetSelectedWeapon: tytuł okna ekwipunku – nazwa broni w prawej ręce,
## bez broni – sSkillHandtohand.
func _weapon_title() -> String:
	var eq: Dictionary = main.player_stats().get("equipment", {})
	var we: Dictionary = eq.get(str(main.EQ.SLOT_CARRIED_RIGHT), {})
	if not we.is_empty():
		var it: Dictionary = main.interaction.inventory.item(String(we.id))
		if not it.is_empty():
			return main.interaction.item_name(String(it.get("kind", "")), String(we.id), it.get("rec", {}))
	return _t("sSkillHandtohand", "Hand-to-hand")

func _refresh_inventory() -> void:
	if _grid == null or main == null or main.get("interaction") == null:
		return
	if barter != null:
		_title("inventory", _weapon_title())
		barter.refresh()
		_refresh_enc()
		return
	_title("inventory", _weapon_title())
	var entries := []
	var flt := inv_filter.text.strip_edges().to_lower() if inv_filter != null else ""
	for e in sorted_items():
		if in_category(e.kind, e.magic, category) and (flt.is_empty() or String(e.name).to_lower().contains(flt)):
			entries.append(e)
	if is_holding():                          # SortFilterItemModel::addDragItem – podniesiona liczba ukryta
		var kept := []
		var hide := int(held.count)
		for pass_worn in [bool(held.get("worn", false)), not bool(held.get("worn", false))]:
			for i in entries.size():
				var e: Dictionary = entries[i]
				if hide <= 0 or String(e.id) != String(held.id) or bool(e.get("worn", false)) != pass_worn:
					continue
				var take := mini(hide, int(e.count))
				hide -= take
				e = e.duplicate()
				e.count = int(e.count) - take
				entries[i] = e
		for e in entries:
			if int(e.count) <= 0:
				continue
			kept.append(e)
		entries = kept
	item_ids = _fill_grid(_grid, entries, "inventory")
	_refresh_enc()

## Pasek obciążenia, pancerz i podgląd postaci w oknie ekwipunku.
func _refresh_enc() -> void:
	if _enc_bar == null or not is_instance_valid(_enc_bar):
		return
	var st: Dictionary = main.player_stats()
	var w: float = main.player_weight()
	var cap: float = main.character.capacity(st) if not st.is_empty() else 0.0
	_enc_bar.max_value = maxf(cap, 1.0)
	_enc_bar.value = minf(w, _enc_bar.max_value)
	_enc_label.text = "%d/%d" % [roundi(w), roundi(cap)]
	_enc_label.get_parent().tooltip_text = _t("sEncumbrance", "Encumbrance")
	_armor_label.text = "%s: %d" % [_t("sArmor", "Armor"), roundi(player_armor_rating())]
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
## corpse – przeszukanie martwego aktora (ContainerWindow: przycisk sDisposeofCorpse widoczny przy łupieniu).
func open_container(sid: String, rec: Dictionary, name: String, corpse := false, pick_node: Node = null, knocked := false) -> void:
	if visible:
		close()
	cont_corpse = corpse
	pickpocket = {}
	if pick_node != null:
		pickpocket = {"node": pick_node, "knocked": knocked, "hidden": {}, "detected": false}
		if not knocked:                       # PickpocketItemModel: mHiddenItems – osobno dla każdego stosu
			var sneak: float = main.combat.skill(main.combat.player_fighter(), SK_SNEAK)
			for e in sorted_items(sid, rec):
				if main.crime._roll() > sneak:
					pickpocket.hidden[_stack_key(e)] = true
	cont_sid = sid
	cont_rec = rec
	cont_name = name
	var vp := get_viewport().get_visible_rect().size
	scale_ui = UI.ui_scale()
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
	# openmw_container_window.layout: ItemView od 5 px, pod nim (po 5 px) HBox do prawej: sDisposeofCorpse (tylko
	# przy łupieniu ciała), sTakeAll, Close (l10n Interface)
	windows["container"] = _window("container", Rect2(Vector2(0.49, 0.54) * vp, Vector2(0.39, 0.38) * vp))
	(windows["container"].get_node("Box/CaptionArea/Title/Pin") as Control).visible = false    # MW_Window – bez pinezki
	var cbody := _body("container")
	var cm := MarginContainer.new()
	cm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cm.add_theme_constant_override("margin_top", roundi(5 * scale_ui))
	cm.add_theme_constant_override("margin_right", roundi(4 * scale_ui))
	cm.add_theme_constant_override("margin_bottom", roundi(1 * scale_ui))
	cbody.add_child(cm)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", roundi(5 * scale_ui))
	cm.add_child(body)
	var gm := MarginContainer.new()
	gm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gm.add_theme_constant_override("margin_left", roundi(5 * scale_ui))
	body.add_child(gm)
	_cont_grid = _make_grid(gm, "container")
	var btns := HBoxContainer.new()
	btns.name = "Buttons"
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.custom_minimum_size.y = 28 * scale_ui
	btns.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(btns)
	var dc := Button.new()
	dc.name = "DisposeCorpseButton"
	dc.text = _t("sDisposeofCorpse", "Dispose of Corpse")
	dc.visible = corpse
	dc.pressed.connect(dispose_corpse)
	btns.add_child(dc)
	var ta := Button.new()
	ta.name = "TakeButton"
	ta.text = _t("sTakeAll", "Take All")
	ta.pressed.connect(take_all)
	btns.add_child(ta)
	var cb := Button.new()
	cb.name = "CloseButton"
	cb.text = preload("res://scripts/mw/mw_l10n.gd").ctx_text("Interface", "Close", _t("sClose", "Close"))
	cb.pressed.connect(close)
	btns.add_child(cb)
	UI.auto_button_row(btns, scale_ui)               # AutoSizedButton 24 px wyśrodkowane w wierszu 28 px
	_gui_mode = "container"
	main.gui.push("container", [self], close)           # GM_Container
	_set_hud(false)
	refresh()

# --- towarzysz (GM_Companion): CompanionWindow (openmw_companion_window.layout) + ekwipunek -----------------------

var companion := {}                       # aktor z rozmowy (make_actor)
var _comp_bar: ProgressBar = null
var _comp_bar_text: Label = null
var comp_profit_label: Label = null
var comp_filter: LineEdit = null

## DialogueWindow::isCompanion: skrypt aktora ze zmienną lokalną „companion” ≠ 0.
func is_companion(a: Dictionary) -> bool:
	var scr := String(a.get("script", ""))
	return main.scripts != null and not scr.is_empty() and main.scripts.local_value(String(a.get("sid", "")), "companion") != 0.0

## CompanionItemModel::hasProfit: skrypt deklaruje „minimumprofit”.
func companion_has_profit() -> bool:
	var scr := String(companion.get("script", ""))
	return main.scripts != null and not scr.is_empty() and main.scripts.script_has_local(scr, "minimumprofit")

func companion_profit() -> int:
	return int(main.scripts.local_value(String(companion.get("sid", "")), "minimumprofit"))

## pushGuiMode(GM_Companion, aktor): okno towarzysza (setCoord(200, 0, 600, 300)) i ekwipunek gracza.
func open_companion(a: Dictionary) -> void:
	if visible:
		close()
	companion = a
	cont_corpse = false
	cont_sid = String(a.sid)
	cont_rec = a.rec
	cont_name = main.dialogue.actor_name(a)
	var vp := get_viewport().get_visible_rect().size
	scale_ui = UI.ui_scale()
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
	windows["container"] = _window("container", Rect2(Vector2(200, 0) * scale_ui, Vector2(600, 300) * scale_ui))
	(windows["container"].get_node("Box/CaptionArea/Title/Pin") as Control).visible = false   # MW_Window
	windows["container"].name = "CompanionWindow"
	var cbody := _body("container")
	var cm := MarginContainer.new()
	cm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [["margin_left", 5], ["margin_top", 5], ["margin_right", 4], ["margin_bottom", 1]]:
		cm.add_theme_constant_override(side[0], roundi(side[1] * scale_ui))
	cbody.add_child(cm)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", roundi(5 * scale_ui))
	cm.add_child(body)
	comp_filter = LineEdit.new()                          # FilterEdit (5, 5, 575, 23)
	comp_filter.name = "FilterEdit"
	comp_filter.set_meta("accept_tab", true)               # AcceptTab
	comp_filter.custom_minimum_size.y = 23 * scale_ui
	comp_filter.text_changed.connect(func(_t2): _refresh_container())
	body.add_child(comp_filter)
	_cont_grid = _make_grid(body, "container")            # ItemView (5, 33, 575, 197)
	var row := HBoxContainer.new()                        # HBox (5, 235, 575, 24): pasek, zysk, Close
	row.name = "Bottom"
	row.custom_minimum_size.y = 24 * scale_ui
	body.add_child(row)
	var holder := Control.new()                           # MW_ChargeBar_Blue (EncumbranceBar)
	holder.name = "EncumbranceBar"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size.y = 18 * scale_ui
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(holder)
	_comp_bar = UI.progress_bar("magic", scale_ui)
	_comp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_comp_bar)
	_comp_bar_text = Label.new()
	_comp_bar_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_comp_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_comp_bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(_comp_bar_text)
	comp_profit_label = Label.new()
	comp_profit_label.name = "ProfitLabel"
	row.add_child(comp_profit_label)
	var cb := Button.new()
	cb.name = "CloseButton"
	cb.text = preload("res://scripts/mw/mw_l10n.gd").ctx_text("Interface", "Close", _t("sClose", "Close"))
	cb.pressed.connect(companion_close_clicked)
	row.add_child(cb)
	_gui_mode = "companion"
	main.gui.push("companion", [self], companion_close_clicked)    # GM_Companion (rozmowa ukryta pod spodem)
	_set_hud(false)
	refresh()

## updateEncumbranceBar: obciążenie (zaokrąglone w górę) / udźwig; sProfitValue N, gdy skrypt ma minimumprofit.
func _refresh_companion() -> void:
	if _comp_bar == null or not is_instance_valid(_comp_bar) or companion.is_empty():
		return
	var f: Dictionary = main.combat.fighter_of(companion.node) if companion.get("node") != null else {}
	var cap := 0.0
	var enc := 0.0
	if not f.is_empty():
		var strength := float(main.combat.attributes(f)[0])
		cap = strength * (5.0 if f.kind == "creature" else float(main.combat._gmst("fEncumbranceStrMult", 5.0)))
		enc = ceilf(float(main.magic.encumbrance(f)))
	_comp_bar.max_value = maxf(cap, 1.0)
	_comp_bar.value = clampf(enc, 0.0, _comp_bar.max_value)
	_comp_bar_text.text = "%d/%d" % [int(enc), int(cap)]
	comp_profit_label.text = ("%s %d" % [_t("sProfitValue", "Profit:"), companion_profit()]) if companion_has_profit() else ""

## CompanionItemModel: przy dodaniu do towarzysza zysk + wartość × liczba, przy zabraniu −; bez kradzieży.
func companion_transfer(id: String, count: int, to_companion: bool) -> int:
	var inv = main.interaction.inventory
	var n: int
	if to_companion:
		n = inv.transfer("player", {}, cont_sid, cont_rec, id, count)
	else:
		n = inv.transfer(cont_sid, cont_rec, "player", {}, id, count)
	if n > 0 and companion_has_profit():
		var v: int = main.trade.item_value(id) * n
		main.scripts.set_local_value(String(companion.sid), "minimumprofit", companion_profit() + (v if to_companion else -v))
	if n > 0 and main.get("audio") != null:
		main.audio.play(main.interaction.item_sound(id, not to_companion))
	if n > 0 and main.has_method("_check_equipment"):
		main._check_equipment()
	refresh()
	return n

## onCloseButtonClicked / exit: przy ujemnym zysku ostrzeżenie (sCompanionWarningMessage) zamiast zamknięcia;
## pierwszy przycisk – zamknięcie i wyjście z rozmowy (exitCurrentGuiMode – skrypt umowy Calvusa).
func companion_close_clicked() -> void:
	if companion_has_profit() and companion_profit() < 0:
		main.show_message_box(_t("sCompanionWarningMessage", "Your companion is not happy with the trade."),
			[_t("sCompanionWarningButtonOne", "Leave"), _t("sCompanionWarningButtonTwo", "Stay")],
			func(b: int):
				if b == 0:
					close()
					main.gui.exit_current(), true)
		return
	close()

# --- handel (GM_Barter): okno ekwipunku gracza („inventory barter”) i okno kupca (openmw_trade_window.layout) ---

var barter = null                         # mw_trade_window w trybie handlu
var barter_total: SpinBox = null
var barter_total_label: Label = null
var barter_player_gold: Label = null
var barter_merchant_gold: Label = null
const BARTER_RECT := Rect2(0.6, 0.27, 0.38, 0.63)     # [Windows] barter

func open_barter(tw) -> void:
	if visible:
		close()
	barter = tw
	var vp := get_viewport().get_visible_rect().size
	scale_ui = UI.ui_scale()
	UI.setup(String(main.data_dir) if main != null and main.get("data_dir") != null else "")
	_root = _Backdrop.new()
	_root.name = "MenuMode"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.theme(scale_ui)
	_root.menu = self
	add_child(_root)
	visible = true
	cont_sid = "#barter"
	windows["inventory"] = _window("inventory", _rect("inventory", vp))
	_build_inventory()
	var bw := _window("barter", Rect2(BARTER_RECT.position * vp, BARTER_RECT.size * vp))
	windows["barter"] = bw
	(bw.get_node("Box/CaptionArea/Title/Pin") as Control).visible = false        # MW_Window – bez pinezki
	# openmw_trade_window.layout (Client 584 × 324 przy oknie 600 × 360): Categories (8, 8, …, 24), ItemView
	# (8, 38) do 10 px przed prawą krawędzią, BottomPane (8, 231, …, 92) przy dolnej krawędzi (1 px odstępu):
	# wiersze w y = 0 (24 px), 28 i 60 (po 28 px)
	var bm := MarginContainer.new()
	bm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [["margin_left", 8], ["margin_top", 8], ["margin_right", 10], ["margin_bottom", 1]]:
		bm.add_theme_constant_override(side[0], roundi(side[1] * scale_ui))
	_body("barter").add_child(bm)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	bm.add_child(body)
	var cats := HBoxContainer.new()
	cats.custom_minimum_size.y = 24 * scale_ui
	body.add_child(cats)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = _t(c[1], c[2])
		b.toggle_mode = true
		b.button_pressed = c[0] == "all"
		b.add_theme_color_override("font_pressed_color", UI.color("active"))
		b.add_theme_color_override("font_hover_pressed_color", UI.color("active_over"))
		var cat: String = c[0]
		b.pressed.connect(func():
			for x in cats.get_children():
				if x is Button:
					(x as Button).button_pressed = x == b
			tw.merchant_category = cat
			tw.refresh())
		b.custom_minimum_size.y = 24 * scale_ui
		cats.add_child(b)
	var flt := LineEdit.new()
	flt.name = "FilterEdit"
	flt.set_meta("accept_tab", true)                 # AcceptTab
	flt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flt.custom_minimum_size.x = 0
	flt.text_changed.connect(func(t): tw.merchant_filter = t; tw.refresh())
	flt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cats.add_child(flt)
	var gap_c := Control.new()
	gap_c.custom_minimum_size.y = 6 * scale_ui
	body.add_child(gap_c)
	tw.merchant_grid = _make_grid(body, "merchant", tw)
	tw.player_grid = _grid
	var gap_b := Control.new()
	gap_b.custom_minimum_size.y = 8 * scale_ui
	body.add_child(gap_b)
	# BottomPane: +/saldo/złoto gracza, −/kwota/złoto kupca, MaxSale … Offer Cancel
	var bp := VBoxContainer.new()
	bp.name = "BottomPane"
	bp.custom_minimum_size.y = 92 * scale_ui
	bp.add_theme_constant_override("separation", roundi(4 * scale_ui))
	body.add_child(bp)
	var r1 := HBoxContainer.new()
	r1.custom_minimum_size.y = 24 * scale_ui
	bp.add_child(r1)
	var inc := Button.new()
	inc.text = "+"
	inc.custom_minimum_size.x = 40 * scale_ui
	inc.pressed.connect(func(): tw.change_balance(1))
	r1.add_child(inc)
	barter_total_label = Label.new()
	r1.add_child(barter_total_label)
	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(sp1)
	barter_player_gold = Label.new()
	r1.add_child(barter_player_gold)
	var r2 := HBoxContainer.new()
	r2.custom_minimum_size.y = 28 * scale_ui
	bp.add_child(r2)
	var dec := Button.new()
	dec.text = "-"
	dec.custom_minimum_size.x = 40 * scale_ui
	dec.pressed.connect(func(): tw.change_balance(-1))
	r2.add_child(dec)
	barter_total = SpinBox.new()
	barter_total.min_value = 0
	barter_total.max_value = 1000000000
	barter_total.custom_minimum_size.x = 140 * scale_ui
	barter_total.value_changed.connect(func(v): tw.set_balance_abs(int(v)))
	r2.add_child(barter_total)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(sp2)
	barter_merchant_gold = Label.new()
	r2.add_child(barter_merchant_gold)
	var r3 := HBoxContainer.new()
	r3.custom_minimum_size.y = 28 * scale_ui
	bp.add_child(r3)
	var mx := Button.new()
	mx.name = "MaxSaleButton"
	mx.text = _t("sMaxSale", "Max Sale")
	mx.pressed.connect(func(): tw.max_sale())
	r3.add_child(mx)
	var sp3 := Control.new()
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r3.add_child(sp3)
	var of := Button.new()
	of.name = "OfferButton"
	of.text = _t("sBarterDialog8", "Offer")
	of.pressed.connect(func(): tw.make_offer())
	r3.add_child(of)
	var cn := Button.new()
	cn.name = "CancelButton"
	cn.text = preload("res://scripts/mw/mw_l10n.gd").ctx_text("Interface", "Cancel", _t("sCancel", "Cancel"))
	cn.pressed.connect(func(): tw.close())
	r3.add_child(cn)
	# HBox::align: dzieci 24 px wyśrodkowane w pionie (wiersze 28 px – 2 px od góry), przyciski 24 px
	for row in [r1, r2, r3]:
		UI.auto_button_row(row, scale_ui)
		for c in (row as Control).get_children():
			(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barter_total.custom_minimum_size.y = 24 * scale_ui
	_gui_mode = "barter"
	main.gui.push("barter", [self, tw], func(): tw.close())     # GM_Barter (ekwipunek + okno kupca)
	refresh()

## TradeWindow::updateLabels: „sTotalCost” przy ujemnym saldzie (płaci gracz), „sTotalSold” przy dodatnim.
func barter_labels(balance: int, player_gold: int, merchant_gold: int) -> void:
	if barter_total_label == null:
		return
	barter_total_label.text = _t("sTotalCost", "Total Cost") if balance < 0 else _t("sTotalSold", "Total Sold")
	barter_total.set_value_no_signal(absi(balance))
	barter_player_gold.text = "%s %d" % [_t("sYourGold", "Your Gold"), player_gold]
	barter_merchant_gold.text = "%s %d" % [_t("sSellerGold", "Seller Gold"), merchant_gold]

func _refresh_container() -> void:
	if _cont_grid == null or not is_instance_valid(_cont_grid):
		return
	var inv = main.interaction.inventory
	var items: Array = inv.contents(cont_sid, cont_rec)
	var cap := float(cont_rec.get("capacity", 0.0))
	var w: float = inv.total_weight(items)
	if not companion.is_empty():
		_title("container", cont_name)                    # setTitle(nazwa aktora)
		var flt := comp_filter.text.strip_edges().to_lower() if comp_filter != null else ""
		var entries := sorted_items(cont_sid, cont_rec).filter(func(e): return flt.is_empty() or String(e.name).to_lower().contains(flt))
		cont_ids = _fill_grid(_cont_grid, entries, "container")
		_refresh_companion()
		return
	_title("container", cont_name + ("  (%d/%d)" % [roundi(w), roundi(cap)] if cap > 0.0 else ""))
	cont_ids = _fill_grid(_cont_grid, pickpocket_items() if not pickpocket.is_empty() else sorted_items(cont_sid, cont_rec), "container")

func _count(sid: String, rec: Dictionary, id: String) -> int:
	return int(main.interaction.inventory.count_of(sid, rec, id))

## Okno ilości przed przeniesieniem stosu (Inventory/Container/TradeWindow::onItemSelected): Ctrl – 1 sztuka,
## stos > 1 bez Shift – CountDialog z komunikatem (sTake, sQuanityMenuMessage01/02), inaczej od razu cb(liczba).
## mods: {"shift", "ctrl"} – stan klawiszy w chwili wybrania przedmiotu (OpenMW: kliknięcie podnoszące przedmiot).
func ask_count(id: String, count: int, message_gmst: String, mods: Dictionary, cb: Callable) -> void:
	if count <= 0:
		return
	if bool(mods.get("ctrl", false)):
		count = 1
	if count > 1 and not bool(mods.get("shift", false)) and main != null and main.has_method("get_count_dialog"):
		var it: Dictionary = main.interaction.inventory.item(id)
		var name: String = main.interaction.item_name(String(it.get("kind", "")), id, it.get("rec", {})) if not it.is_empty() else id
		main.get_count_dialog().open_count(name, _t(message_gmst, _COUNT_FALLBACK.get(message_gmst, "")), count, cb)
	else:
		cb.call(count)

const _COUNT_FALLBACK := {"sTake": "Take", "sDrop": "Drop", "sQuanityMenuMessage01": "Sell how many?",
	"sQuanityMenuMessage02": "Buy how many?"}

## Z pojemnika do gracza (n < 0 – cały stos).
func take_item(id: String, count := -1) -> void:
	var n := _count(cont_sid, cont_rec, id)
	if count > 0:
		n = mini(n, count)
	if not companion.is_empty():
		companion_transfer(id, n, false)
		return
	if not pickpocket.is_empty() and n > 0:
		if not _pickpocket_take(id, n):
			return
	if n > 0 and main.interaction.move(cont_sid, cont_rec, "player", {}, id, n) > 0 and main.get("audio") != null:
		main.audio.play(main.interaction.item_sound(id, true))
	refresh()

## PickpocketItemModel::onTakeItem: NPC powalony – zwykłe itemTaken (kradzież, gdy ktoś widzi); inaczej stealItem:
## Pickpocket::pick (wartość stosu) – wykrycie: commitCrime(OT_Pickpocket, ofiara świadoma), okno zamknięte, przedmiot
## zostaje; powodzenie – postęp Skradania (Sneak_PickPocket) i itemTaken bez alarmu. → czy zabrać
func _pickpocket_take(id: String, n: int) -> bool:
	var node: Node = pickpocket.node
	if bool(pickpocket.knocked):
		main.crime.npc_item_taken(node, id, n, true)
		return true
	if main.crime.pick(node, id, n):
		main.crime.commit(node, main.crime.PICKPOCKET, "", 0, true)
		pickpocket.detected = true
		close()
		return false
	main.skill_used(SK_SNEAK, "sneak_pickpocket")
	main.crime.npc_item_taken(node, id, n, false)
	return true

## Od gracza do pojemnika (cały stos; założone – zdejmowane). Pojemność: OpenMW nie pozwala przekroczyć
## (sContentsMessage3).
func put_item(id: String, count := -1) -> void:
	if not pickpocket.is_empty():
		return                                 # PickpocketItemModel::onDropItem: bez „odwrotnej kradzieży”
	var n := _count("player", {}, id)
	if count > 0:
		n = mini(n, count)
	if n <= 0:
		return
	if not companion.is_empty():
		companion_transfer(id, n, true)
		return
	var cap := float(cont_rec.get("capacity", 0.0))
	if cap > 0.0 and cont_rec.has("capacity"):
		var inv = main.interaction.inventory
		var it: Dictionary = inv.item(id)
		var w: float = inv.total_weight(inv.contents(cont_sid, cont_rec)) + float(it.get("rec", {}).get("weight", 0.0)) * n
		if w > cap + 0.001:
			if main.has_method("_toast"):
				main._toast(_t("sContentsMessage3", "There is not enough room here."))
			return
	if main.interaction.move("player", {}, cont_sid, cont_rec, id, n) > 0 and main.get("audio") != null:
		main.audio.play(main.interaction.item_sound(id, false))
	refresh()

var cont_corpse := false
## Kradzież kieszonkowa (ContainerWindow::setPtr z żywym NPC – PickpocketItemModel): {"node", "knocked", "hidden"
## (klucze stosów niewidocznych: rzut 0–99 > Skradanie przy otwarciu, gdy NPC nie jest powalony), "detected"}; pusty – zwykły pojemnik.
var pickpocket := {}

## ContainerWindow::onDisposeCorpseButtonClicked: najpierw „weź wszystko”, potem ciało trwałego aktora zostaje
## (sDisposeCorpseFail), a pozostałe są usuwane ze świata (deleteObject).
func dispose_corpse() -> void:
	var sid := cont_sid
	var persistent := bool(cont_rec.get("persistent", false))
	take_all()
	if persistent:
		main.message_box(_t("sDisposeCorpseFail", "You cannot dispose of this corpse."))
	elif not sid.is_empty():
		main.state.delete_ref(sid)

func take_all() -> void:
	if not pickpocket.is_empty():              # onTakeAllButtonClicked: onTakeItem dla każdego stosu, do wykrycia
		for e in pickpocket_items():
			if pickpocket.is_empty() or bool(pickpocket.get("detected", false)):
				return
			if not _pickpocket_take(String(e.id), int(e.count)):
				return
			main.interaction.move(cont_sid, cont_rec, "player", {}, String(e.id), int(e.count))
		if main.get("audio") != null:
			main.audio.play("Item Misc Up")
		close()
		return
	main.interaction.take_all(cont_sid, cont_rec)
	if main.get("audio") != null:
		main.audio.play("Item Misc Up")
	close()

## Upuszczenie przeciąganego przedmiotu na obszar okna.
## Przenoszony stos > 1 – najpierw okno ilości (sTake, jak przy podniesieniu w OpenMW); Ctrl – 1, Shift – cały.
func dropped_on(target: String, data: Dictionary) -> void:
	var id := String(data.get("mw_item", ""))
	var src := String(data.get("source", "inventory"))
	pressed_stack = data.get("stack", {}) if data.get("stack") is Dictionary else {}
	if target == "container" and src == "inventory":
		ask_count(id, _stack_avail(_count("player", {}, id)), "sTake", data, func(n: int): put_item(id, n))
	elif target in ["inventory", "avatar"] and src == "container":
		ask_count(id, _stack_avail(_count(cont_sid, cont_rec, id)), "sTake", data, func(n: int): take_item(id, n))
	elif target == "avatar" and src == "inventory":
		use_item(id)

# --- DragAndDrop (apps/openmw/mwgui/draganddrop.cpp): przedmiot „przy kursorze” ---------------------------------
## Kliknięcie przedmiotu podnosi go (z pojemnika – od razu do ekwipunku gracza, jak startDrag; założony – zdjęty,
## ensureSelectedItemUnequipped); ikona 42 × 42 z liczbą idzie za kursorem (lewy górny róg w punkcie kursora,
## ControllerFollowMouse); następne kliknięcie odkłada: siatka ekwipunku – bez zmian, pojemnik – przełożenie, postać –
## użyj/załóż, poza oknami – na ziemię. Zamknięcie okna – przedmiot zostaje w ekwipunku (finish).
var held := {}                              # {"id", "count", "worn"} – mIsOnDragAndDrop
var pressed_stack := {}                     # stos klikniętej komórki ({count, worn}; pusty – cały wpis)

## Liczba sztuk do przeniesienia: stos klikniętej komórki (ItemStack::mCount), bez niego – wszystkie sztuki.
func _stack_avail(total: int) -> int:
	return mini(total, int(pressed_stack.count)) if pressed_stack.has("count") else total

var _held_layer: CanvasLayer = null
var _held_icon: Control = null

func is_holding() -> bool:
	return not held.is_empty()

func cell_pressed(id: String, source: String, mods := {}) -> void:
	if is_holding():
		held_drop(source)
		return
	if bool(mods.get("alt", false)) and _cont_grid != null and is_instance_valid(_cont_grid):
		activate_item(id, source, mods)            # transferItem (Alt)
		return
	var avail := _stack_avail(_count(cont_sid, cont_rec, id) if source == "container" else _count("player", {}, id))
	var worn := bool(pressed_stack.get("worn", source != "container"))
	ask_count(id, avail, "sTake", mods, func(n: int): _pick_up(id, source, n, worn))

func _pick_up(id: String, source: String, n: int, worn := true) -> void:
	if n <= 0:
		return
	if source == "container":
		var before := _count("player", {}, id)
		take_item(id, n)                           # startDrag: przedmiot spoza ekwipunku trafia do niego od razu
		n = _count("player", {}, id) - before
		if n <= 0:
			return
	else:
		# ensureSelectedItemUnequipped: tylko gdy podniesiony stos jest założony (niezałożone sztuki tego samego
		# przedmiotu to osobny stos – założony egzemplarz zostaje)
		var slot: int = main.equipped_slot_of(id) if main.has_method("equipped_slot_of") else -1
		if worn and slot >= 0 and main.has_method("unequip_slot"):
			main.unequip_slot(slot)
		if main.get("audio") != null:
			main.audio.play(main.interaction.item_sound(id, true))      # getUpSoundId
	held = {"id": id, "count": n, "worn": worn and source != "container"}
	_show_held()
	refresh()

func held_drop(target: String, screen = null) -> void:
	if not is_holding():
		return
	var h := held
	held = {}
	_hide_held()
	var id := String(h.id)
	var n := int(h.count)
	match target:
		"container":
			if not pickpocket.is_empty():      # onDropItem = false – przedmiot zostaje przy kursorze
				held = h
				_show_held()
				return
			put_item(id, n)
		"avatar":
			use_item(id)
		"world":
			_drop_count(id, n, screen)
		_:
			if main.get("audio") != null:
				main.audio.play(main.interaction.item_sound(id, false))  # getDownSoundId
	refresh()

func _show_held() -> void:
	if _held_layer == null:
		_held_layer = CanvasLayer.new()
		_held_layer.name = "DragAndDrop"
		_held_layer.layer = 95                    # warstwa DragAndDrop (openmw_layers.xml) – nad oknami
		_held_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_held_layer)
	if _held_icon != null:
		_held_icon.queue_free()
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(CELL, CELL) * scale_ui
	var it: Dictionary = main.interaction.inventory.item(String(held.id))
	var ic := TextureRect.new()
	ic.texture = UI.icon(String(it.get("rec", {}).get("icon", "")))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(5, 5) * scale_ui
	ic.size = Vector2(32, 32) * scale_ui
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(ic)
	if int(held.count) > 1:
		var cl := Label.new()                     # liczba jak w siatce (ItemWidget::setCount)
		cl.text = str(int(held.count))
		cl.add_theme_color_override("font_color", UI.color("count"))
		cl.add_theme_font_size_override("font_size", roundi(13 * scale_ui))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cl.offset_right = -3 * scale_ui
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(cl)
	_held_layer.add_child(c)
	_held_icon = c
	_held_icon.position = get_viewport().get_mouse_position()

func _hide_held() -> void:
	if _held_icon != null:
		_held_icon.queue_free()
		_held_icon = null

## Dwuklik: w trybie pojemnika – przełożenie (z oknem ilości), inaczej – użyj/załóż.
func activate_item(id: String, source: String, mods := {}) -> void:
	if source == "container":
		ask_count(id, _stack_avail(_count(cont_sid, cont_rec, id)), "sTake", mods, func(n: int): take_item(id, n))
	elif _cont_grid != null and is_instance_valid(_cont_grid):
		ask_count(id, _stack_avail(_count("player", {}, id)), "sTake", mods, func(n: int): put_item(id, n))
	else:
		use_item(id)

## Kliknięcie z Alt (ContainerWindow/InventoryWindow::transferItem): przełożenie do drugiego okna, z oknem ilości.
func click_item(id: String, source: String, mods := {}) -> void:
	if not bool(mods.get("alt", false)) or _cont_grid == null or not is_instance_valid(_cont_grid):
		return
	activate_item(id, source, mods)

## Pancerz gracza (getArmorRating): suma pancerza założonych zbroi wg miejsc (waga miejsca) + bez zbroi.
func player_armor_rating() -> float:
	if main == null or main.get("combat") == null:
		return 0.0
	return float(main.combat.armor_rating(main.combat.player_fighter()))

func item_tooltip(id: String, count := 1) -> String:
	if main == null or main.get("tooltips") == null or main.tooltips == null:
		return id
	var info: Dictionary = main.tooltips.item_info(id, count)
	if info.is_empty():
		return id
	var lines := [String(info.caption)]
	var t := String(info.get("text", ""))
	if t.begins_with("\n"):
		t = t.substr(1)
	if not t.is_empty():
		lines.append(t)
	for e in info.get("effects", []):
		lines.append(main.tooltips.effect_line_text(e, {"no_target": info.get("is_potion", false),
			"no_magnitude": info.get("is_ingredient", false), "constant": info.get("is_ingredient", false)})
			if bool(e.get("known", true)) else "?")
	var en: Dictionary = info.get("enchant", {})
	for e in en.get("effects", []):
		lines.append(main.tooltips.effect_line_text(e, {"constant": int(en.get("type", 0)) == 3}))
	return "\n".join(lines)

## Podpowiedź przedmiotu w układzie OpenMW (ToolTips, typ ItemModelIndex/ItemPtr) na kontrolce: meta „mw_tip”,
## bez zwykłej podpowiedzi Godota. extra – dodatkowy wiersz (np. cena w handlu).
static func set_item_tip(c: Control, id: String, count := 1, extra := "") -> void:
	if c == null:
		return
	c.tooltip_text = ""
	var tip := {"type": "item", "id": id, "count": count}
	if not extra.is_empty():
		tip["extra"] = extra
	c.set_meta("mw_tip", tip)

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
	# alchemia, książka, naprawa, kamień dusz: tryb GUI na stosie nad ekwipunkiem (po zamknięciu – powrót tutaj)
	iw.use_item(i)
	iw.visible = false
	refresh()

func drop_to_world(id: String, source := "inventory", mods := {}, screen = null) -> void:
	if source != "inventory":
		return
	pressed_stack = mods.get("stack", {}) if mods.get("stack") is Dictionary else {}
	ask_count(id, _stack_avail(main.interaction.inventory.count_of("player", {}, id)), "sTake", mods,
		func(n: int): _drop_count(id, n, screen))

func _drop_count(id: String, count: int, screen = null) -> void:
	var n: int = mini(count, main.interaction.inventory.count_of("player", {}, id))
	if n <= 0:
		return
	main.drop_item(id, n, screen)
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
	preload("res://scripts/mw/mw_environment.gd").apply_gamma_space(e)     # oświetlenie w gammie jak OpenMW
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

var _fx_box: HBoxContainer
var _spell_list: VBoxContainer

func _build_spells() -> void:
	# Client 284 × 564 (okno 300 × 600): MW_Box (8, 8, 268, 23), SpellView (8, 38, 268, 490), HBox (8, 535, 268, 23)
	var sm := MarginContainer.new()
	sm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [["margin_left", 8], ["margin_top", 8], ["margin_right", 8], ["margin_bottom", 6]]:
		sm.add_theme_constant_override(side[0], roundi(side[1] * scale_ui))
	_body("spells").add_child(sm)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", roundi(7 * scale_ui))
	sm.add_child(body)
	# openmw_spell_window.layout: pole efektów MW_Box 268 × 23 (ikony 16 px od 2, 1), lista, na dole pole filtra
	# (MW_TextBoxEditWithBorder 23 px) i przycisk sDelete przy prawej krawędzi
	var fp := PanelContainer.new()
	var fsb: StyleBox = UI.inner_box().duplicate()
	fsb.content_margin_left = 2 * scale_ui
	fsb.content_margin_top = 1 * scale_ui
	fsb.content_margin_right = 2 * scale_ui
	fsb.content_margin_bottom = 2 * scale_ui
	fp.add_theme_stylebox_override("panel", fsb)
	fp.custom_minimum_size.y = 23 * scale_ui
	body.add_child(fp)
	_fx_box = HBoxContainer.new()
	_fx_box.add_theme_constant_override("separation", 0)
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
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size.y = 23 * scale_ui
	body.add_child(bottom)
	spell_filter = LineEdit.new()
	spell_filter.name = "FilterEdit"
	spell_filter.set_meta("accept_tab", true)               # AcceptTab
	spell_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_filter.text_changed.connect(func(_t2): _refresh_spells())
	spell_filter.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bottom.add_child(spell_filter)
	spell_delete = Button.new()
	spell_delete.name = "DeleteSpellButton"
	spell_delete.text = _t("sDelete", "Delete")
	spell_delete.pressed.connect(_on_delete_spell)
	bottom.add_child(spell_delete)

## SpellWindow::onDeleteClicked: usunięcie wybranego czaru (nie mocy, zdolności ani przedmiotu) po potwierdzeniu
## (sQuestionDeleteSpell z nazwą czaru).
func _on_delete_spell() -> void:
	var sel: Dictionary = main.selected_magic()
	if sel.is_empty() or String(sel.get("kind")) != "spell":
		return
	var sp: Dictionary = main.magic.records.record("spell", String(sel.id))
	if int(sp.get("spell_type", -1)) != main.magic.SPELL_SPELL:
		return
	var q := _t("sQuestionDeleteSpell", "Delete %s?").replace("%s", String(sp.get("name", sel.id)))
	main.confirm.ask(q, func(): delete_spell(String(sel.id)))

func delete_spell(spid: String) -> void:
	var st: Dictionary = main.player_stats()
	var list: Array = st.get("spells", [])
	list.erase(spid)
	st["spells"] = list
	if String(main.selected_magic().get("id", "")) == spid:
		main.select_magic("", "")
	_refresh_spells()

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
	b.tooltip_text = ""
	# SpellView::adjustSpellWidget: podpowiedź Spell (czary i moce) albo ItemPtr (przedmiot magiczny)
	b.set_meta("mw_tip", {"type": "item", "id": id} if kind == "item" else {"type": "spell", "id": id})
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
	# WindowManager::setSelectedSpell / unsetSelectedSpell: tytuł – nazwa wybranego czaru albo „None”
	_title("spells", main.selected_magic_name() if not sel.is_empty() else _t("sNone", "None"))
	var me: Dictionary = main.combat.player_fighter()
	# ikony efektów jak w HUD (SpellIcons) – także zdolności i inne stałe źródła
	for e in magic.effect_icon_list(me):
		var mg: Dictionary = magic.effect(int(e.id))
		var ic := TextureRect.new()
		ic.texture = UI.icon(String(mg.get("icon", "")))
		ic.custom_minimum_size = Vector2(16, 16) * scale_ui
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.set_meta("mw_tip", {"type": "effect_icon", "id": int(e.id)})   # SpellIcons: ToolTipInfo
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		_fx_box.add_child(ic)
	var flt := spell_filter.text.strip_edges().to_lower() if spell_filter != null else ""
	var cc := "%s/%s" % [_t("sCostCharge", "Cost"), _t("sChance", "Chance")]
	for g in spell_model(flt):
		_spell_list.add_child(UI.header(String(g.title)))
		for r in g.rows:
			_spell_button(String(r.name), String(r.right), String(r.kind), String(r.id),
				sel.get("kind") == r.kind and sel.get("id") == r.id, cc if String(g.group) == "spells" else "")

## SpellModel gracza: grupy mocy (sPowers), czarów (sSpells) i przedmiotów magicznych (sMagicItem – zaklęcie
## „przy użyciu” albo jednorazowe), nazwy posortowane; flt – filtr nazw. Wiersz: {kind, id, name, right}.
## Wspólne dla okna magii i MagicSelectionDialog (szybkie klawisze).
func spell_model(flt := "") -> Array:
	var magic = main.magic
	var me: Dictionary = main.combat.player_fighter()
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
	if not flt.is_empty():
		powers = powers.filter(func(x): return String(x[1].get("name", x[0])).to_lower().contains(flt))
		spells = spells.filter(func(x): return String(x[1].get("name", x[0])).to_lower().contains(flt))
	var by_name := func(a, b): return String(a[1].get("name", a[0])).to_lower() < String(b[1].get("name", b[0])).to_lower()
	powers.sort_custom(by_name)
	spells.sort_custom(by_name)
	var out := []
	if not powers.is_empty():
		var rows := []
		for p in powers:
			rows.append({"kind": "spell", "id": p[0], "name": String(p[1].get("name", p[0])),
				"right": "" if magic.can_use_power(me, p[0]) else "–"})
		out.append({"group": "powers", "title": _t("sPowers", "Powers"), "rows": rows})
	if not spells.is_empty():
		var rows2 := []
		for p in spells:
			rows2.append({"kind": "spell", "id": p[0], "name": String(p[1].get("name", p[0])),
				"right": "%d/%d" % [magic.spell_cost(p[1]), int(magic.spell_chance(p[1], me))]})
		out.append({"group": "spells", "title": _t("sSpells", "Spells"), "rows": rows2})
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
		items.append({"kind": "item", "id": String(e.id), "name": main.interaction.item_name(String(it.kind), String(e.id), it.rec), "right": right})
	if not flt.is_empty():
		items = items.filter(func(x): return String(x.name).to_lower().contains(flt))
	if not items.is_empty():
		out.append({"group": "items", "title": _t("sMagicItem", "Magic Items"), "rows": items})
	return out

# --- elementy przeciągania ------------------------------------------------------------------------------

## Komórka siatki ekwipunku: przeciąganie (ikona pod kursorem), dwuklik – użyj/załóż.
const _ItemCell := preload("res://scripts/mw/mw_menu_cell.gd")
const _DollDrop := preload("res://scripts/mw/mw_menu_doll.gd")
const _Backdrop := preload("res://scripts/mw/mw_menu_backdrop.gd")
const Inv := preload("res://scripts/mw/mw_inventory.gd")
