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

const UI := preload("res://scripts/mw/mw_ui.gd")

## Układ openmw_wait_dialog.layout: VBox w skórce MW_Dialog, Padding 8, Spacing 8, AutoResize – szerokość i wysokość
## z treści (600 w układzie to tylko rozmiar początkowy, VBox::setSize po wypełnieniu tekstów go zastępuje):
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
	visible = false

func _btn(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

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
	if enemies_nearby():                          # Rest_EnemiesAreNearby (Player::enemiesNearby)
		main._toast(_t("sNotifyMessage2", "You can't rest with enemies nearby."))
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
	main.gui.push("rest", [self])                # pushGuiMode(GM_...)
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

## Odpoczynek: n godzin (WaitDialog::startWaiting + TimeAdvancer): okno znika, ekran przyciemnia się (0,2 s), po
## 0,4 s pasek postępu (WaitDialogProgressBar) i co 1/60 s jedna godzina (restoreDynamicStats, upływ czasu, czary);
## skrypty działają w tym czasie (GetPCSleep = 1 podczas snu, WakeUpPC przerywa). Sen w świecie zewnętrznym
## w regionie z listą snu (BNAM): rzut rollDice(n) < fSleepRandMod × n – przerwanie po n − int(fSleepRestMod × n)
## godzinach: sSleepInterrupt i 1 + rollDice(iNumberCreatures) stworzeń z listy 220 j. przed graczem.
## Po śnie – awans, jeśli możliwy. Autozapis przed odpoczynkiem ([Saves] autosave) – brak w Godocie.
const STEP_DELAY := 1.0 / 60.0
var _rest := {}
var rng := RandomNumberGenerator.new()
var progress_win: Control = null          # WaitDialogProgressBar (MW_Dialog 219 × 40)
var _progress_bar: ProgressBar = null
var _progress_text: Label = null

func rest(n: int) -> void:
	panel.visible = false
	n = maxi(1, n)
	_rest = {"hours": n, "cur": 0, "fade": 0.4, "t": STEP_DELAY, "interrupt": -1, "list": ""}
	if main.get("fader") != null and main.fader != null:
		main.fader.fade_screen_out(0.2)
	if sleeping and String(main.interior).is_empty() and main.get("envr") != null and main.envr != null:
		var reg: Dictionary = main.envr.regions.get(String(main.current_region).to_lower(), {})
		var sl := String(reg.get("sleep_list", "")).to_lower()
		if not sl.is_empty():
			var x := rng.randi_range(0, n - 1)                       # Misc::Rng::rollDice(n)
			if x < character._gmst("fsleeprandmod", 0.25) * n:
				var at := int(character._gmst("fsleeprestmod", 0.3) * n)
				if at != 0:
					_rest.interrupt = n - at
					_rest.list = sl
	_set_progress(0, n)

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

## WaitDialog::stopWaiting: rozjaśnienie ekranu, pasek ukryty, okno zamknięte.
func _stop_rest() -> void:
	_rest = {}
	if main.get("fader") != null and main.fader != null:
		main.fader.fade_screen_in(0.2)
	_hide_progress()
	close()

## onWaitingInterrupted: sSleepInterrupt, spawnRandomCreature(lista snu regionu), stopWaiting (bez awansu).
func _interrupted() -> void:
	var list := String(_rest.get("list", ""))
	main._toast(_t("sSleepInterrupt", "Your rest has been interrupted."))
	spawn_random_creatures(list)
	sleeping = false
	_stop_rest()

## World::spawnRandomCreature: 1 + rollDice(iNumberCreatures) stworzeń z listy (getLevelledItem dla poziomu
## gracza), każde 220 j. przed graczem (safePlaceObject; przeszkoda – w miejscu gracza). → sid stworzeń
func spawn_random_creatures(list_id: String) -> Array:
	var out := []
	var list: Dictionary = main.builder.actors.record("leveledcreature", list_id) if main.get("builder") != null else {}
	if list.is_empty() or main.player == null:
		return out
	var count := 1 + rng.randi_range(0, maxi(1, int(character._gmst("inumbercreatures", 3))) - 1)
	var level := int(main.player_stats().get("level", 1))
	for i in count:
		var cid: String = main.builder._leveled_creature(list, rng, level, 0)
		if cid.is_empty():
			continue
		var n: Node3D = main.player
		var pos := MWCoords.godot_to_mw(n.global_position)
		var rz := -float(n.rotation.y)
		var place := pos + Vector3(sin(rz), cos(rz), 0.0) * 220.0
		var space: PhysicsDirectSpaceState3D = n.get_world_3d().direct_space_state if n.is_inside_tree() else null
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(n.global_position + Vector3.UP * 0.9, MWCoords.mw_to_godot(place) + Vector3.UP * 0.9)
			q.exclude = [n.get_rid()]
			if not space.intersect_ray(q).is_empty():
				place = pos
		var key: String = String(main.db.exterior_key(MWCoords.cell_of(MWCoords.mw_to_godot(place))))
		out.append(main.state.add_dynamic(cid, key, place, Vector3(0, 0, rz + PI), 1))
	return out

## Player::enemiesNearby → Actors::getEnemiesNearby: żywi aktorzy w zasięgu przetwarzania (bez stworzeń tylko
## wodnych) w walce z graczem albo agresywni wobec niego (isAggressive: bez Uspokojenia, getFightTerm ≥ 100),
## o ile nie podążają za graczem.
func enemies_nearby() -> bool:
	if main.get("ai") == null or main.ai == null or main.player == null:
		return false
	var range_mw := float(main.settings.get("actors_processing_range", 7168.0))
	var ppos := MWCoords.godot_to_mw(main.player.global_position)
	for n in main.ai.actor_nodes():
		if not is_instance_valid(n):
			continue
		var f: Dictionary = main.combat.fighter_of(n)
		if f.is_empty() or main.combat.is_dead(f):
			continue
		if MWCoords.godot_to_mw(n.global_position).distance_to(ppos) > range_mw:
			continue
		if f.kind == "creature":
			var fl := int(f.rec.get("flags", 0))
			if (fl & 0x10) != 0 and (fl & 0x01) == 0 and (fl & 0x20) == 0 and (fl & 0x40) == 0:
				continue                                   # isPureWaterCreature
		var follower := false
		var combat := false
		for p in main.ai.ai_state(n).packages:
			var t := String(p.get("type", ""))
			if String(p.get("target", "")) != "player":
				continue
			if t == "combat":
				combat = true
			elif t in ["follow", "escort"]:
				follower = true
		if combat:
			return true
		if follower:
			continue
		var calm: int = 49 if f.kind == "npc" else 50          # ESM::MagicEffect::CalmHumanoid / CalmCreature
		if main.magic.magnitude_of(f, calm) > 0.0:
			continue
		if main.ai.fight_term(n, main.player) >= 100.0:
			return true
	return false

## WaitDialogProgressBar (openmw_wait_dialog_progressbar.layout): MW_Dialog 219 × 40 na środku, pasek
## MW_Progress_Blue (5, 6, 199, 20) z tekstem „bieżące/wszystkie”.
func _set_progress(cur: int, total: int) -> void:
	if progress_win == null or not is_instance_valid(progress_win):
		var s: float = UI.ui_scale()
		progress_win = Panel.new()
		progress_win.name = "WaitDialogProgressBar"
		progress_win.add_theme_stylebox_override("panel", UI.window_box())
		progress_win.size = Vector2(219, 40) * s
		progress_win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(progress_win)
		_progress_bar = UI.progress_bar("magicka", s)
		_progress_bar.position = Vector2(4 + 5, 4 + 6) * s
		_progress_bar.size = Vector2(199, 20) * s
		progress_win.add_child(_progress_bar)
		_progress_text = Label.new()
		_progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_progress_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_progress_text.add_theme_color_override("font_color", UI.color("normal_pressed"))
		_progress_text.position = Vector2(0, 0)
		_progress_text.size = Vector2(199, 16) * s
		_progress_bar.add_child(_progress_text)
		progress_win.position = ((get_viewport().get_visible_rect().size - progress_win.size) / 2.0).floor()
		progress_win.visible = false
	_progress_bar.max_value = maxi(1, total)
	_progress_bar.value = cur
	_progress_text.text = "%d/%d" % [cur, total]

func _hide_progress() -> void:
	if progress_win != null and is_instance_valid(progress_win):
		progress_win.visible = false

func _process(dt: float) -> void:
	if _rest.is_empty():
		return
	if float(_rest.fade) > 0.0:
		_rest.fade = float(_rest.fade) - dt
		if float(_rest.fade) <= 0.0 and progress_win != null:
			progress_win.visible = true
		return
	if int(_rest.cur) == int(_rest.get("interrupt", -1)):     # TimeAdvancer: przerwanie przed kolejną godziną
		_interrupted()
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
	_set_progress(int(_rest.cur), int(_rest.hours))
	if main.combat != null and main.combat.is_dead(main.combat.player_fighter()):
		_stop_rest()
		return
	if int(_rest.cur) >= int(_rest.hours):
		_stop_rest()
		if sleeping and character.can_level_up(st):
			open_levelup()          # WaitDialog::stopWaiting → GM_Levelup (LevelupDialog)

func open_levelup() -> void:
	main.levelup_window.open()

func close() -> void:
	visible = false
	panel.visible = true
	main.gui.remove("rest")                       # removeGuiMode – powrót do poprzedniego trybu
	closed.emit()
