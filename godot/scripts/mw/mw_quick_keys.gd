extends CanvasLayer
## Szybkie klawisze jak OpenMW 0.51 (apps/openmw/mwgui/quickkeysmenu.cpp):
##  - QuickKeysMenu (GM_QuickKeysMenu, F1 – omw/input/playercontrols.lua): openmw_quickkeys_menu.layout,
##    MW_Dialog 380 × 224 (wysokość + przyrost zawiniętej instrukcji sQuickMenuInstruc), tytuł sQuickMenuTitle,
##    10 pól 60 × 60 (2 rzędy po 5, co 68 px), OK (#{Interface:OK}) przy prawej dolnej krawędzi;
##    pole 10 – zawsze walka wręcz (ikona icons\k\stealth_handtohand.dds), pola nieprzypisane – numer;
##  - QuickKeysMenuAssign (modalne, MW_DialogNoTransp): sQuickMenu1, sQuickMenu2 (przedmiot), sQuickMenu3 (magia),
##    sQuickMenu4 (usuń), Cancel – szerokość z najdłuższego tekstu + 24, przyciski na środku;
##  - ItemSelectionDialog (sQuickMenu6, Filter_OnlyUsableItems) i MagicSelectionDialog
##    (openmw_magicselection_dialog.layout 330 × 370, sMagicSelectTitle, SpellView bez kolumny kosztu);
##  - activateQuickKey(1…10): klawisze 1–9 i 0 poza trybem GUI (ActionManager::quickKey), po tworzeniu postaci,
##    nie jako wilkołak (sWerewolfRefusal); w trakcie ataku/czaru, powalenia – odroczone do następnej klatki
##    (mActivated, updateActivatedQuickKey), sparaliżowany/martwy – nic. Przedmiot: findReplacement (stos o najmniejszym
##    stanie), brak – „sQuickMenu5 nazwa”; użycie jak z ekwipunku (useItem), broń w prawej ręce – dobycie;
##    przedmiot magiczny – założenie i wybór jako magia, przygotowanie magii; czar – wybór, przygotowanie magii;
##    walka wręcz – zdjęcie broni z prawej ręki i dobycie (pięści).
##  - zapis (QuickKeysMenu::write/readRecord, REC_KEYS): 9 pól w state.player["quick_keys"] – {type, id}.

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const Selection := preload("res://scripts/mw/mw_item_selection.gd")
const HUD := preload("res://scripts/mw/mw_hud.gd")
const EQ := preload("res://scripts/mw/mw_equipment.gd")

const UNASSIGNED := "unassigned"
const ITEM := "item"
const MAGIC_ITEM := "magic_item"
const MAGIC := "magic"
const HAND_TO_HAND := "hand_to_hand"

var main
var ui = null
var _s := 1.0
var win: Control = null
var buttons: Array = []           # QuickKey1…10
var ok_button: Button = null
var instruction: Label = null
var assign_win: Control = null    # QuickKeysMenuAssign
var magic_win: Control = null     # MagicSelectionDialog
var magic_rows: Array = []        # testy: [rodzaj, id, nazwa]
var selection = null              # ItemSelectionDialog
var selected := -1                # mSelected (0…9)
var activated := -1               # mActivated: odroczone (0…9)
var history: Array = []           # testy: wykonane akcje

func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	if main == null or main.get("dialogue") == null or main.dialogue == null:
		return fb
	var v: String = main.dialogue.gmst_text(gm, fb)
	return v if not v.is_empty() else fb

# --- stan (ESM::QuickKeys) --------------------------------------------------------------------------------

## Pola 1…9 z zapisu gry; pole 10 – zawsze walka wręcz (nie zapisywane).
func keys() -> Array:
	var k = main.state.player.get("quick_keys", null)
	if not (k is Array) or (k as Array).size() != 9:
		k = []
		for i in 9:
			k.append({"type": UNASSIGNED, "id": ""})
		main.state.player["quick_keys"] = k
	return k

func key_data(i: int) -> Dictionary:
	if i == 9:
		return {"type": HAND_TO_HAND, "id": ""}
	return keys()[i]

func _set_key(i: int, type: String, id: String) -> void:
	if i < 0 or i >= 9:
		return
	keys()[i] = {"type": type, "id": id.to_lower()}

## unassign: pole 10 zostaje walką wręcz.
func unassign(i: int) -> void:
	_set_key(i, UNASSIGNED, "")
	_refresh_button(i)

func assign_item(i: int, id: String) -> void:
	_set_key(i, ITEM, id)
	_refresh_button(i)

func assign_magic_item(i: int, id: String) -> void:
	_set_key(i, MAGIC_ITEM, id)
	_refresh_button(i)

func assign_magic(i: int, spell_id: String) -> void:
	var sp: Dictionary = main.magic.records.record("spell", spell_id.to_lower())
	if sp.is_empty():
		return
	_set_key(i, MAGIC, spell_id)
	_refresh_button(i)

## Nazwa przypisania (keyData::name): nazwa przedmiotu albo czaru.
func key_name(i: int) -> String:
	var k := key_data(i)
	match String(k.type):
		ITEM, MAGIC_ITEM:
			var it: Dictionary = main.interaction.inventory.item(String(k.id))
			return main.interaction.item_name(String(it.get("kind", "")), String(k.id), it.get("rec", {})) if not it.is_empty() else String(k.id)
		MAGIC:
			return String(main.magic.records.record("spell", String(k.id)).get("name", k.id))
	return ""

## ContainerStore::findReplacement: stos o tym samym rekordzie, z najmniejszym dodatnim stanem (zerowy – tylko
## gdy nie ma innego).
func find_replacement(id: String) -> String:
	var inv = main.interaction.inventory
	var base: String = inv.base_id(id)
	var best := ""
	var best_h := 1.0
	for e in inv.contents("player", {}):
		var eid := String(e.id)
		if int(e.count) <= 0 or inv.base_id(eid) != base:
			continue
		var it: Dictionary = inv.item(eid)
		var h := 1.0
		if not it.is_empty() and inv.max_charge(it.rec) > 0.0:
			h = inv.item_charge(eid)
		if best.is_empty() or (h > 0.0 and h < best_h) or (best_h <= 0.0 and h > 0.0):
			best = eid
			best_h = h
	return best

## validate: przypisany stos zniknął – zastępstwo z ekwipunku (gdy jest).
func validate(i: int) -> void:
	var k := key_data(i)
	if not String(k.type) in [ITEM, MAGIC_ITEM]:
		return
	if main.interaction.inventory.count_of("player", {}, String(k.id)) >= 1:
		return
	var r := find_replacement(String(k.id))
	if not r.is_empty():
		k["id"] = r

# --- okno ----------------------------------------------------------------------------------------------------

func is_open() -> bool:
	return visible and win != null and is_instance_valid(win)

## GM_QuickKeysMenu (F1): przełącznik – wierzchni tryb zamyka, inaczej otwiera (gdy wolno).
func toggle() -> void:
	if main.gui.get_mode() == "quickkeys":
		close()
		return
	if bool(main.player_stats().get("werewolf", false)):
		main._toast(_t("sWerewolfRefusal", "You cannot do this as a werewolf."))
		return
	if main.scripts != null and main.scripts.get_global("chargenstate") != -1.0:
		return                                   # Player.isCharGenFinished
	open()

func open() -> void:
	_s = UI.ui_scale()
	ui = CU.new(main, _s)
	if selection == null:
		selection = Selection.new(main, ui)
	else:
		selection.ui = ui
	_build()
	visible = true
	for i in 10:
		validate(i)                              # onOpen
		_refresh_button(i)
	main.gui.push("quickkeys", [self], escape)

## onOkButtonClicked: removeGuiMode(GM_QuickKeysMenu).
func close() -> void:
	if not visible:
		return
	_close_modals()                              # onClose
	visible = false
	if win != null and is_instance_valid(win):
		CU.close(win)
	win = null
	main.gui.remove("quickkeys")

## Esc: najpierw okno modalne (exitCurrentModal), potem tryb.
func escape() -> void:
	if selection != null and selection.is_open():
		selection.close()
	elif magic_win != null and is_instance_valid(magic_win):
		_close_magic()
	elif assign_win != null and is_instance_valid(assign_win):
		_close_assign()
	else:
		close()

func _close_modals() -> void:
	if selection != null:
		selection.close()
	_close_magic()
	_close_assign()

func _build() -> void:
	if win != null and is_instance_valid(win):
		CU.close(win)
	buttons = []
	# wysokość: 224 + (wysokość zawiniętej instrukcji − 18)
	var instr := _t("sQuickMenuInstruc", "Use the number keys 1-9 to use the assigned item or magic. Key 0 is reserved for hand-to-hand.")
	var th: float = ui.wrapped_height(instr, 354)
	var dh := roundf(th) - 18.0
	win = ui.modal(self, 380, 224 + dh, false)
	win.name = "QuickKeysMenu"
	(win.get_meta("layer") as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE    # tryb GUI, nie okno modalne
	var c: Control = win.get_meta("client")
	ui.label(c, 8, 7, 356, 18, _t("sQuickMenuTitle", "Quick Keys"), "sand", HORIZONTAL_ALIGNMENT_CENTER)
	instruction = ui.wrap_label(c, 23, 26, 354, instr)
	instruction.name = "InstructionLabel"
	var grid: Control = ui.group(c, 20, 49 + dh, 332, 128)
	grid.name = "Keys"
	for i in 10:
		var b := Button.new()
		b.name = "QuickKey%d" % (i + 1)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		ui.at(b, grid, (i % 5) * 68, (i / 5) * 68, 60, 60)
		b.pressed.connect(_on_key_clicked.bind(i))
		buttons.append(b)
	ok_button = ui.button(L10n.ctx_text("Interface", "OK", "OK"), close)
	ok_button.name = "OKButton"
	c.add_child(ok_button)
	var bw: float = maxf(32 * _s, ok_button.size.x)          # ExpandDirection Left od 362
	ok_button.position = Vector2(362 * _s - bw, (185 + dh) * _s)
	ok_button.size = Vector2(bw, 24 * _s)

## ItemWidget pola: przedmiot – ikona z tłem menu_icon[_magic]_barter (setItem(…, Barter)), przedmiot magiczny –
## ramka menu_icon_select_magic_magic, czar – menu_icon_select_magic z wielką ikoną pierwszego efektu,
## nieprzypisane – numer (SandText, środek), pole 10 – ikona walki wręcz (14, 13, 32 × 32).
func _refresh_button(i: int) -> void:
	if i < 0 or i >= buttons.size() or not is_instance_valid(buttons[i]):
		return
	var b: Button = buttons[i]
	for ch in b.get_children():
		ch.queue_free()
		b.remove_child(ch)
	# MW_ItemIconBox: ramka MW_Box_Overlay na całym polu (nad zawartością, bez myszy)
	var ov := Panel.new()
	ov.name = "BoxOverlay"
	ov.add_theme_stylebox_override("panel", UI.inner_box())
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.z_index = 1
	b.add_child(ov)
	b.tooltip_text = ""
	if b.has_meta("mw_tip"):
		b.remove_meta("mw_tip")
	var k := key_data(i)
	match String(k.type):
		HAND_TO_HAND:
			_image(b, UI.icon("k/stealth_handtohand.dds"), Vector2(14, 13), Vector2(32, 32), "Item")
		UNASSIGNED:
			var l := Label.new()
			l.name = "Number"
			l.text = str(i + 1)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.set_anchors_preset(Control.PRESET_FULL_RECT)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
		ITEM, MAGIC_ITEM:
			var it: Dictionary = main.interaction.inventory.item(String(k.id))
			if it.is_empty():
				return
			var frame: Texture2D
			if String(k.type) == ITEM:
				frame = UI.icon_frame(not String(it.rec.get("enchant", "")).is_empty(), "barter")
			else:
				frame = _select_frame("textures/menu_icon_select_magic_magic")
			_image(b, frame, Vector2(9, 9), Vector2(42, 42), "Frame")
			_image(b, UI.icon(String(it.rec.get("icon", ""))), Vector2(14, 14), Vector2(32, 32), "Item")
			main.menu_mode.set_item_tip(b, String(k.id))
		MAGIC:
			var sp: Dictionary = main.magic.records.record("spell", String(k.id))
			var effs: Array = sp.get("effects", [])
			var icon := ""
			if not effs.is_empty():
				icon = String(main.magic.effect(int(effs[0].get("effect", -1))).get("icon", ""))
			_image(b, _select_frame("textures/menu_icon_select_magic"), Vector2(9, 9), Vector2(42, 42), "Frame")
			_image(b, UI.icon(HUD.big_icon(icon)) if not icon.is_empty() else null, Vector2(14, 14), Vector2(32, 32), "Item")
			b.set_meta("mw_tip", {"type": "spell", "id": String(k.id)})

## Ramka menu_icon_select_magic*: część 44 × 44 obrazu 64 × 64 (proporcjonalnie dla innych rozmiarów),
## wyświetlana w polu 42 × 42 (Frame skórki MW_ItemIconBox).
func _select_frame(path: String) -> Texture2D:
	var t: Texture2D = UI.texture(path)
	if t == null:
		return null
	var a := AtlasTexture.new()
	a.atlas = t
	var k := t.get_height() / 64.0
	a.region = Rect2(0, 0, 44.0 * k, 44.0 * k)
	return a

func _image(b: Control, tex: Texture2D, pos: Vector2, size: Vector2, n: String) -> void:
	var r := TextureRect.new()
	r.name = n
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = pos * _s
	r.size = size * _s
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)

## onQuickKeyButtonClicked: pole 10 bez zmian, inne – okno przypisania.
func _on_key_clicked(i: int) -> void:
	selected = i
	if i == 9:
		return
	_open_assign()

# --- QuickKeysMenuAssign ------------------------------------------------------------------------------------

func _open_assign() -> void:
	_close_assign()
	var texts := [_t("sQuickMenu1", "Assign which?"), _t("sQuickMenu2", "Item"), _t("sQuickMenu3", "Magic"),
		_t("sQuickMenu4", "Delete"), L10n.ctx_text("Interface", "Cancel", "Cancel")]
	var mw := 0.0
	for tx in texts:
		mw = maxf(mw, ui.text_width(tx) / _s + 24.0)
	mw = floorf(mw)
	assign_win = ui.modal(self, mw + 24, 154, true)
	assign_win.name = "QuickKeysMenuAssign"
	var c: Control = assign_win.get_meta("client")
	ui.label(c, 8, 8, mw, 18, texts[0], "sand", HORIZONTAL_ALIGNMENT_CENTER).name = "Label"
	var cbs := [assign_item_clicked, assign_magic_clicked, unassign_clicked, _close_assign]
	var names := ["ItemButton", "MagicButton", "UnassignButton", "CancelButton"]
	for j in 4:
		var b: Button = ui.button(texts[j + 1], cbs[j])
		b.name = names[j]
		c.add_child(b)
		var bw: float = floorf(ui.text_width(texts[j + 1]) / _s) + 24.0
		b.position = Vector2(floorf((mw - bw) / 2.0) + 8.0, 28 + 28 * j) * _s
		b.size = Vector2(bw, 24) * _s

func _close_assign() -> void:
	if assign_win != null and is_instance_valid(assign_win):
		CU.close(assign_win)
	assign_win = null

## onItemButtonClicked: ItemSelectionDialog z przedmiotami do użycia.
func assign_item_clicked() -> void:
	_close_assign()
	selection.open(self, _t("sQuickMenu6", "Select an item"), usable_entry, _item_selected, func(): selection.close())

## Filter_OnlyUsableItems: Class::use daje akcję (założenie, wypicie, zjedzenie, czytanie, alchemia, naprawa,
## kamień dusz); zwykłe rzeczy różne i światła nie do niesienia – nie.
func usable_entry(e: Dictionary) -> bool:
	match String(e.get("kind", "")):
		"weapon", "armor", "clothing", "lockpick", "probe", "potion", "ingredient", "book", "apparatus", "repair":
			return true
		"light":
			return bool(e.get("rec", {}).get("carry", false))
		"misc":
			return main.magic.is_soul_gem(String(e.get("id", "")))
	return false

## onAssignItem: przypisanie i dźwięk odłożenia (getDownSoundId).
func _item_selected(id: String) -> void:
	assign_item(selected, id)
	selection.close()
	if main.get("audio") != null and main.audio != null:
		main.audio.play(main.interaction.item_sound(id, false))
	history.append(["assign_item", selected, id])

func unassign_clicked() -> void:
	unassign(selected)
	_close_assign()

# --- MagicSelectionDialog -----------------------------------------------------------------------------------

func assign_magic_clicked() -> void:
	_close_assign()
	_open_magic()

func _open_magic() -> void:
	_close_magic()
	magic_win = ui.modal(self, 330, 370, true)
	magic_win.name = "MagicSelectionDialog"
	var c: Control = magic_win.get_meta("client")
	ui.label(c, 8, 8, 292, 24, _t("sMagicSelectTitle", "Select Magic"))
	var lp := Panel.new()
	lp.add_theme_stylebox_override("panel", UI.inner_box())
	ui.at(lp, c, 8, 38, 306, 285)
	lp.name = "MagicList"
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 4 * _s
	sc.offset_top = 2 * _s
	sc.offset_right = -2 * _s
	sc.offset_bottom = -2 * _s
	UI.setup_scroll(sc, _s)
	lp.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	sc.add_child(list)
	magic_rows = []
	var groups: Array = main.menu_mode.spell_model() if main.get("menu_mode") != null else []
	for g in groups:
		if not list.get_children().is_empty():
			list.add_child(Control.new())                    # odstęp między grupami
		list.add_child(UI.header(String(g.title)))
		for r in g.rows:
			var b := Button.new()
			b.flat = true
			b.text = String(r.name)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.focus_mode = Control.FOCUS_NONE
			for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
				b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			b.pressed.connect(magic_selected.bind(String(r.kind), String(r.id)))
			b.set_meta("mw_tip", {"type": "item", "id": String(r.id)} if String(r.kind) == "item" else {"type": "spell", "id": String(r.id)})
			list.add_child(b)
			magic_rows.append([String(r.kind), String(r.id), String(r.name)])
	var cb: Button = ui.button(L10n.ctx_text("Interface", "Cancel", "Cancel"), _close_magic)
	cb.name = "CancelButton"
	c.add_child(cb)
	var bw: float = maxf(32 * _s, cb.size.x)                 # ExpandDirection Left od 316
	cb.position = Vector2(316 * _s - bw, 330 * _s)
	cb.size = Vector2(bw, 24 * _s)

func _close_magic() -> void:
	if magic_win != null and is_instance_valid(magic_win):
		CU.close(magic_win)
	magic_win = null

## onModelIndexSelected: przedmiot magiczny – onAssignMagicItem, czar/moc – onAssignMagic.
func magic_selected(kind: String, id: String) -> void:
	if kind == "item":
		assign_magic_item(selected, id)
	else:
		assign_magic(selected, id)
	_close_magic()
	history.append(["assign_magic", selected, kind, id])

# --- activateQuickKey ---------------------------------------------------------------------------------------

## Klawisz 1…0 (ActionManager::quickKey): przełączniki sterowania, wilkołak, tworzenie postaci, poza trybem GUI.
func quick_key(index: int) -> void:
	if not (main.control_allowed("controls") and main.control_allowed("fighting") and main.control_allowed("magic")):
		return
	if bool(main.player_stats().get("werewolf", false)):
		main._toast(_t("sWerewolfRefusal", "You cannot do this as a werewolf."))      # checkAllowedToUseItems
		return
	if main.scripts != null and main.scripts.get_global("chargenstate") != -1.0:
		return
	if main.gui.is_gui_mode():
		return
	activate(index)

func _player_busy() -> bool:
	var st: Dictionary = main.player_stats()
	return bool(main.get("_attack_hold") != null and float(main._attack_hold) >= 0.0) \
		or bool(st.get("knocked_down", false)) or bool(st.get("hit_recovery", false))

func _player_blocked() -> bool:
	var me: Dictionary = main.combat.player_fighter()
	if main.combat.is_dead(me):
		return true
	var fx: Dictionary = main.magic.effects(me)
	return float(fx.get(str(main.magic.FX_PARALYZE), 0.0)) > 0.0

## activateQuickKey(1…10).
func activate(index: int) -> void:
	var i := index - 1
	if i < 0 or i > 9:
		return
	validate(i)
	if _player_blocked():
		return
	if _player_busy():
		activated = i                            # odroczenie (updateActivatedQuickKey)
		return
	activated = -1
	var k := key_data(i)
	var inv = main.interaction.inventory
	match String(k.type):
		ITEM, MAGIC_ITEM:
			var id := String(k.id)
			if inv.count_of("player", {}, id) <= 0:
				main._toast("%s %s" % [_t("sQuickMenu5", "You no longer have"), key_name(i)])
				history.append(["missing", index, id])
				return
			if String(k.type) == ITEM:
				if main.equipped_slot_of(id) < 0:
					_use_item(id)
				var right: Dictionary = main._equipment().get(str(EQ.SLOT_CARRIED_RIGHT), {})
				if String(right.get("id", "")) == id:
					_draw("weapon")              # broń w prawej ręce – dobycie
				history.append(["item", index, id])
			else:
				if not main.item_slots(id).is_empty() and main.equipped_slot_of(id) < 0:
					_use_item(id)
					if main.equipped_slot_of(id) < 0:
						return                   # nie udało się założyć
				main.select_magic("item", id)    # setSelectedEnchantItem
				_draw("spell")
				history.append(["magic_item", index, id])
		MAGIC:
			var spid := String(k.id)
			if not spid in main.player_stats().get("spells", []):
				main._toast("%s %s" % [_t("sQuickMenu5", "You no longer have"), key_name(i)])
				history.append(["missing", index, spid])
				return
			main.select_magic("spell", spid)
			_draw("spell")
			history.append(["magic", index, spid])
		HAND_TO_HAND:
			main.unequip_slot(EQ.SLOT_CARRIED_RIGHT)
			_draw("weapon")
			history.append(["hand_to_hand", index])
		_:
			return
	if main.get("menu_mode") != null and main.menu_mode.visible:
		main.menu_mode.refresh()                 # updateSpellWindow

## WindowManager::useItem → InventoryWindow::useItem (picie, jedzenie, czytanie, założenie…).
func _use_item(id: String) -> void:
	var iw = main.item_window
	iw.mode = "inventory"
	iw.refresh()
	var j: int = iw._right_ids.find(id)
	if j >= 0:
		iw.use_item(j)
	iw.visible = false

## Player::setDrawState: broń albo magia.
func _draw(what: String) -> void:
	if what == "weapon":
		main.weapon_drawn = true
		main.magic_ready = false
	else:
		main.magic_ready = true
		main.weapon_drawn = false

## updateActivatedQuickKey (co klatkę WindowManager::onFrame).
func _process(_dt: float) -> void:
	if activated >= 0 and main != null and not main.get_tree().paused:
		activate(activated + 1)

## Klawisze: F1 – menu szybkich klawiszy, 1…9, 0 – szybkie klawisze (poza trybem GUI).
func _unhandled_input(e: InputEvent) -> void:
	if main == null or String(main.get("game_state")) != "running" or main.player == null:
		return
	if e.is_action_pressed("quick_keys_menu"):
		if main.control_allowed("controls"):
			toggle()
		get_viewport().set_input_as_handled()
		return
	for n in 10:
		if e.is_action_pressed("quick_key_%d" % (n + 1)):
			quick_key(n + 1)
			get_viewport().set_input_as_handled()
			return
