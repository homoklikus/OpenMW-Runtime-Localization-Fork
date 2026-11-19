extends CanvasLayer
## Odpoczynek/czekanie i awans (etap 7, prosty interfejs – wygląd w etapie 10), jak WaitDialog i LevelupDialog
## w OpenMW: T otwiera okno; nie można odpoczywać w powietrzu ani pod wodą; sen tylko tam, gdzie wolno spać
## (wnętrze bez flagi „spanie zabronione” albo świat zewnętrzny), inaczej tylko czekanie (bez odnowy zdrowia
## i magii). Każda godzina: odnowa (restoreDynamicStats) i upływ czasu. Po śnie, gdy postęp awansu ≥
## iLevelUpTotal – okno awansu: wybór 3 atrybutów z mnożnikami (iLevelUpXXMult).
## Przerywanie snu przez stworzenia z listy regionu (fSleepRandMod) – etap 8 (AI).

signal closed

var main
var character
var panel: PanelContainer
var info: Label
var hours: HSlider
var hours_label: Label
var rest_btn: Button
var heal_btn: Button
var sleeping := false
var levelup: PanelContainer
var lv_title: Label
var lv_buttons: Array = []
var lv_info: Label
var chosen: Array = []

const UI := preload("res://scripts/mw/mw_ui.gd")
const ATTR_NAMES := ["Siła", "Inteligencja", "Siła woli", "Zręczność", "Szybkość", "Wytrzymałość", "Osobowość", "Szczęście"]
const ATTR_GMST := ["sAttributeStrength", "sAttributeIntelligence", "sAttributeWillpower", "sAttributeAgility",
	"sAttributeSpeed", "sAttributeEndurance", "sAttributePersonality", "sAttributeLuck"]

## Układ openmw_wait_dialog.layout: VBox w skórce MW_Dialog, 600 px, Padding 8, Spacing 8 (wysokość z treści):
## data i godzina (DateTimeText), tekst odpoczynku (RestText), „N sRestMenu2” (HourText), pasek MW_HScroll
## (24 pozycje, MoveToClick, kółko o 1), przyciski przy prawej: sUntilHealed, sRest/sWait, Cancel.
var date_label: Label
var slider: HScrollBar

func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	var s: float = UI.ui_scale()
	panel = PanelContainer.new()
	panel.name = "RestWindow"
	panel.theme = UI.theme(s)
	var sb: StyleBox = UI.window_box().duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, 8 * s + 4 * s)               # Client MW_Dialog (4) + Padding 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size.x = 600 * s
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(8 * s))
	panel.add_child(box)
	date_label = Label.new()
	date_label.name = "DateTimeText"
	date_label.add_theme_color_override("font_color", UI.color("normal"))
	box.add_child(date_label)
	info = Label.new()
	info.name = "RestText"
	info.add_theme_color_override("font_color", UI.color("normal"))
	box.add_child(info)
	hours_label = Label.new()
	hours_label.name = "HourText"
	hours_label.add_theme_color_override("font_color", UI.color("normal"))
	box.add_child(hours_label)
	# HourSlider: Range 24, Page 1 – pozycja 0..23 = 1..24 godzin; „hours” trzyma wartość w godzinach
	slider = HScrollBar.new()
	slider.name = "HourSlider"
	slider.min_value = 0
	slider.max_value = 24
	slider.page = 1
	slider.step = 1
	slider.custom_minimum_size.y = 18 * s
	box.add_child(slider)
	hours = HSlider.new()
	hours.min_value = 1
	hours.max_value = 24
	hours.step = 1
	hours.value = 1
	hours.visible = false
	box.add_child(hours)
	slider.value_changed.connect(func(v): hours.value = int(v) + 1)
	hours.value_changed.connect(func(v):
		hours_label.text = "%d %s" % [int(v), _t("sRestMenu2", "hours")]
		slider.set_value_no_signal(int(v) - 1))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	heal_btn = _btn(row, "Until Healed", func(): rest(hours_until_healed()))
	heal_btn.name = "UntilHealedButton"
	rest_btn = _btn(row, "Rest", func(): rest(int(hours.value)))
	rest_btn.name = "WaitButton"
	var cb := _btn(row, "Cancel", close)
	cb.name = "CancelButton"
	_build_levelup()
	visible = false

func _btn(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _build_levelup() -> void:
	levelup = PanelContainer.new()
	levelup.name = "LevelUp"
	levelup.visible = false
	add_child(levelup)
	var box := VBoxContainer.new()
	levelup.add_child(box)
	lv_title = Label.new()
	lv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lv_title)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for i in 8:
		var b := Button.new()
		b.toggle_mode = true
		var idx := i
		b.toggled.connect(func(on): _toggle_attr(idx, on))
		grid.add_child(b)
		lv_buttons.append(b)
	lv_info = Label.new()
	box.add_child(lv_info)
	_btn(box, "OK", func(): confirm_levelup())

func _t(gm: String, fb: String) -> String:
	if main == null or main.dialogue == null:
		return fb
	return main.dialogue.gmst_text(gm, fb)

## Czy można odpoczywać i czy to sen (World::canRest + WaitDialog::setPtr).
func rest_state() -> Dictionary:
	var p = main.player
	if p == null:
		return {"ok": false}
	if p.swimming or (not p.is_on_floor() and p.collide) or p.fly:
		return {"ok": false, "message": _t("sNotifyMessage1", "You can't rest now.")}
	var can_sleep := not bool(main.player_stats().get("werewolf", false))     # WaitDialog::setCanRest – wilkołak czeka
	# World::canRest: flaga komórki NoSleep (0x4) – także komórki zewnętrzne (np. miasta: Seyda Neen)
	var key: String = ("int:" + main.interior.to_lower()) if not main.interior.is_empty() \
			else String(main.db.exterior_key(MWCoords.cell_of(p.global_position)))
	var c: Dictionary = main.db.get_cell(key)
	can_sleep = can_sleep and (int(c.get("flags", 0)) & 0x4) == 0
	return {"ok": true, "sleep": can_sleep}

func open() -> bool:
	var rs := rest_state()
	if not bool(rs.get("ok", false)):
		if rs.has("message"):
			main._toast(String(rs.message))
		return false
	sleeping = bool(rs.sleep)
	var werewolf := bool(main.player_stats().get("werewolf", false))
	# WaitDialog::setCanRest
	info.text = _t("sRestMenu3", "How long do you wish to rest?") if sleeping else \
		(_t("sWerewolfRestMessage", "You cannot rest in beast form.") if werewolf else _t("sRestIllegal", "You can't rest here."))
	rest_btn.text = _t("sRest", "Rest") if sleeping else _t("sWait", "Wait")
	heal_btn.text = _t("sUntilHealed", "Until Healed")
	heal_btn.visible = sleeping and hours_until_healed() > 0
	(panel.find_child("CancelButton", true, false) as Button).text = preload("res://scripts/mw/mw_l10n.gd").ctx_text("Interface", "Cancel", "Cancel")
	# WaitDialog::onOpen: „dzień miesiąc (#{Calendar:day} N) godzina”, suwak na 1 godzinę
	var sc = main.scripts
	var dom := int(sc.get_global("day")) if sc != null else 1
	var mon := int(sc.get_global("month")) if sc != null else 0
	var passed := int(sc.get_global("dayspassed")) if sc != null else int(main.envr.day) + 1
	date_label.text = "%d %s (%s %d) %s" % [dom, main.month_name(mon),
		preload("res://scripts/mw/mw_l10n.gd").ctx_text("Calendar", "day", "Day"), passed,
		preload("res://scripts/mw/mw_l10n.gd").time_of_day(float(main.envr.game_hour))]
	hours.value = 1
	hours_label.text = "%d %s" % [1, _t("sRestMenu2", "hours")]
	slider.set_value_no_signal(0)
	visible = true
	panel.reset_size()
	panel.position = ((get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0).floor()
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

## Godziny do pełnego zdrowia i magii (WaitDialog::onUntilHealedButtonClicked: ceil(max(braki / odnowa))).
func hours_until_healed() -> int:
	var st: Dictionary = main.player_stats()
	if st.is_empty():
		return 0
	var d: Dictionary = character.derived(st)
	var hp := 0.1 * float(d.attributes[5])
	var mp: float = character._gmst("frestmagicmult", 0.15) * float(d.attributes[1])
	var h := 0.0
	if hp > 0.0:
		h = maxf(h, (float(d.health.modified) - float(st.get("health", 0))) / hp)
	var stunted: bool = main.magic != null and main.magic.magnitude_of(main.combat.player_fighter(), main.magic.FX_STUNTED_MAGICKA) > 0.0
	if mp > 0.0 and not stunted:                 # getHoursToRest: przy Osłabionej magii magia się nie liczy
		h = maxf(h, (float(d.magicka.modified) - float(st.get("magicka", 0))) / mp)
	return clampi(int(ceilf(h)), 0, 24)

## Odpoczynek: n godzin (WaitDialog + TimeAdvancer): okno znika, po wygaszeniu (0,4 s) co 1/60 s jedna godzina
## (restoreDynamicStats, upływ czasu, czary); skrypty działają w tym czasie (GetPCSleep = 1 podczas snu,
## WakeUpPC przerywa). Po śnie – awans, jeśli możliwy. Przerwanie snu przez stworzenia z listy regionu – brak.
const STEP_DELAY := 1.0 / 60.0
var _rest := {}

func rest(n: int) -> void:
	panel.visible = false
	_rest = {"hours": maxi(1, n), "cur": 0, "fade": 0.4, "t": STEP_DELAY}

func is_resting() -> bool:
	return not _rest.is_empty()

## getPlayerSleeping: odliczanie trwa i to sen (nie czekanie).
func player_sleeping() -> bool:
	return is_resting() and sleeping and float(_rest.fade) <= 0.0

## WakeUpPC (WaitDialog::wakeUp): koniec snu bez awansu.
func wake_up() -> void:
	if not is_resting():
		return
	sleeping = false
	_stop_rest()

func _stop_rest() -> void:
	_rest = {}
	close()

func _process(dt: float) -> void:
	if _rest.is_empty():
		return
	if float(_rest.fade) > 0.0:
		_rest.fade = float(_rest.fade) - dt
		return
	_rest.t = float(_rest.t) - dt
	while not _rest.is_empty() and float(_rest.t) <= 0.0:
		_rest.t = float(_rest.t) + STEP_DELAY
		_rest_hour()

func _rest_hour() -> void:
	var st: Dictionary = main.player_stats()
	character.rest_hour(st, sleeping, character.normalized_encumbrance(st, main.player_weight()))
	main.envr.advance(1.0)
	if main.has_method("pass_magic_time"):
		main.pass_magic_time(3600.0)          # czary wygasają, przedmioty się ładują (Actors::rest)
	_rest.cur = int(_rest.cur) + 1
	if main.combat != null and main.combat.is_dead(main.combat.player_fighter()):
		_stop_rest()
		return
	if int(_rest.cur) >= int(_rest.hours):
		_rest = {}
		visible = false
		if sleeping and character.can_level_up(st):
			open_levelup()
			return
		close()

func open_levelup() -> void:
	var st: Dictionary = main.player_stats()
	chosen = []
	lv_title.text = "%s %d" % [_t("sLevelUpMenu1", "Osiągasz poziom"), int(st.get("level", 1)) + 1]
	for i in 8:
		var b: Button = lv_buttons[i]
		var m: int = mini(character.levelup_multiplier(st, i), int(100 - float(st.attributes[i])))
		b.set_pressed_no_signal(false)
		b.disabled = float(st.attributes[i]) >= 100.0
		b.text = "%s %d%s" % [_t(ATTR_GMST[i], ATTR_NAMES[i]), int(st.attributes[i]), ("  ×%d" % m) if m > 1 else ""]
	_update_lv_info()
	levelup.visible = true
	visible = true
	levelup.position = (get_viewport().get_visible_rect().size - levelup.get_combined_minimum_size()) / 2.0
	panel.visible = false
	get_tree().paused = true

func _toggle_attr(i: int, on: bool) -> void:
	var coins: int = character.levelup_coins(main.player_stats())
	if on:
		if chosen.size() >= coins:
			var last: int = chosen.pop_back()
			(lv_buttons[last] as Button).set_pressed_no_signal(false)
		chosen.append(i)
	else:
		chosen.erase(i)
	_update_lv_info()

func _update_lv_info() -> void:
	lv_info.text = "Wybierz %d atrybuty (wybrano %d)." % [character.levelup_coins(main.player_stats()), chosen.size()]

## OK w oknie awansu: za mało wyborów – komunikat sNotifyMessage36 (jak OpenMW), inaczej awans.
func confirm_levelup() -> bool:
	var st: Dictionary = main.player_stats()
	if not character.level_up(st, chosen):
		main._toast(_t("sNotifyMessage36", "Musisz wybrać atrybuty do zwiększenia."))
		return false
	levelup.visible = false
	panel.visible = true
	main._toast("Poziom %d" % int(st.level))
	close()
	return true

func close() -> void:
	visible = false
	levelup.visible = false
	panel.visible = true
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
