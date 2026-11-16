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

const ATTR_NAMES := ["Siła", "Inteligencja", "Siła woli", "Zręczność", "Szybkość", "Wytrzymałość", "Osobowość", "Szczęście"]
const ATTR_GMST := ["sAttributeStrength", "sAttributeIntelligence", "sAttributeWillpower", "sAttributeAgility",
	"sAttributeSpeed", "sAttributeEndurance", "sAttributePersonality", "sAttributeLuck"]

func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "RestWindow"
	panel.custom_minimum_size = Vector2(460, 180)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info)
	hours = HSlider.new()
	hours.min_value = 1
	hours.max_value = 24
	hours.step = 1
	hours.value = 1
	hours.value_changed.connect(func(v): hours_label.text = "%d h" % int(v))
	box.add_child(hours)
	hours_label = Label.new()
	hours_label.text = "1 h"
	hours_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hours_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	rest_btn = _btn(row, "Odpocznij", func(): rest(int(hours.value)))
	heal_btn = _btn(row, "Do wyleczenia", func(): rest(hours_until_healed()))
	_btn(row, "Anuluj", close)
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
		return {"ok": false, "message": _t("sNotifyMessage1", "Nie możesz tu odpoczywać.")}
	var can_sleep := true
	if not main.interior.is_empty():
		var c: Dictionary = main.db.get_cell("int:" + main.interior.to_lower())
		can_sleep = (int(c.get("flags", 0)) & 0x4) == 0
	return {"ok": true, "sleep": can_sleep}

func open() -> bool:
	var rs := rest_state()
	if not bool(rs.get("ok", false)):
		if rs.has("message"):
			main._toast(String(rs.message))
		return false
	sleeping = bool(rs.sleep)
	info.text = _t("sRestMenu3", "Ile godzin chcesz odpoczywać?") if sleeping else _t("sRestIllegal", "Nie możesz tu spać – możesz tylko czekać.")
	rest_btn.text = _t("sRest", "Odpocznij") if sleeping else _t("sWait", "Czekaj")
	heal_btn.visible = sleeping and hours_until_healed() > 0
	visible = true
	panel.position = (get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0
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
	if mp > 0.0:
		h = maxf(h, (float(d.magicka.modified) - float(st.get("magicka", 0))) / mp)
	return clampi(int(ceilf(h)), 0, 24)

## Odpoczynek: n godzin; po śnie – awans, jeśli możliwy.
func rest(n: int) -> void:
	var st: Dictionary = main.player_stats()
	var w: float = main.player_weight()
	for i in maxi(1, n):
		character.rest_hour(st, sleeping, character.normalized_encumbrance(st, w))
		main.envr.advance(1.0)
		if main.has_method("pass_magic_time"):
			main.pass_magic_time(3600.0)          # czary wygasają, przedmioty się ładują (Actors::rest)
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
