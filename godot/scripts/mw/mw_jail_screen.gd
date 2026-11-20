extends CanvasLayer
## Więzienie jak OpenMW 0.51 (World::goToJail, JailScreen, TimeAdvancer, omw/playerskillhandlers.lua jailTimeServed):
##  1. GoToJail (skrypt): grzywna 0, przedmioty skradzione zabrane, dni = max(1, grzywna / iDaysinPrisonMod),
##     GetPCInJail = 1 – okno rozmowy zostaje, żeby dało się przeczytać odpowiedź (MWCrime.go_to_jail);
##  2. pierwsza klatka bez pauzy (World::update): broń/magia schowane, koniec rozmowy, tryb GM_Jail –
##     fadeScreenOut(0.5); po 0,5 s przeniesienie do najbliższego znacznika „prisonmarker” (teleportToClosestMarker),
##     zaciemnienie zostaje (fadeScreenOut(0) zastępuje rozjaśnienie po zmianie komórki), okno
##     openmw_jail_screen.layout (MW_Dialog 300 × 48, sInPrisonTitle, pasek MW_ProgressScroll_Loading 260 × 6)
##     i postęp 100 kroków co 1/60 s;
##  3. koniec: zdjęcie trybu, fadeScreenIn(0.5), odpoczynek dni × 24 h ze snem, upływ czasu, odsiadka – losowa
##     umiejętność na każdy dzień (skillLevelUp ze źródłem Jail), okno z pytaniem: ReleasedFromPrison
##     (sNotifyMessage42/43) i zmiany umiejętności (sNotifyMessage39/44).
## GetPCInJail wraca do 0, gdy nie ma trybu GM_Jail ani oczekującego przeniesienia (World::update).

const UI := preload("res://scripts/mw/mw_ui.gd")
const STEP := 1.0 / 60.0         # TimeAdvancer: kProgressStepDelay

var main
var days := 1
var fade_remaining := 0.0
var running := false
var cur := 0
var total := 100
var _remaining := STEP
var win: Control = null
var bar_fill: ColorRect = null
var title: Label = null
var history: Array = []          # testy: etapy

func _ready() -> void:
	layer = 59                   # warstwa LoadingScreen – nad oknami gry
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	if main == null or main.get("dialogue") == null or main.dialogue == null:
		return fb
	var v: String = main.dialogue.gmst_text(gm, fb)
	return v if not v.is_empty() else fb

func is_open() -> bool:
	return main != null and main.gui.contains("jail")

## WindowManager::goToJail → pushGuiMode(GM_Jail) + JailScreen::goToJail.
func go_to_jail(n: int) -> void:
	days = maxi(1, n)
	main.gui.push("jail", [self], func(): pass)       # brak wyjścia klawiszem (okno bez exit)
	if main.fader != null:
		main.fader.fade_screen_out(0.5)
	fade_remaining = 0.5
	visible = false
	running = false
	cur = 0
	_build()
	_set_progress(0)
	history.append("fade_out")

func _build() -> void:
	if win != null and is_instance_valid(win):
		win.queue_free()
	var s: float = UI.ui_scale()
	win = Panel.new()
	win.name = "JailScreen"
	win.add_theme_stylebox_override("panel", UI.window_box())
	win.size = Vector2(300, 48) * s
	var vp := get_viewport().get_visible_rect().size
	win.position = ((vp - win.size) / 2.0).floor()
	win.theme = UI.theme(s)
	add_child(win)
	var c := Control.new()
	c.position = Vector2(4, 4) * s
	c.size = win.size - Vector2(8, 8) * s
	win.add_child(c)
	title = Label.new()
	title.name = "LoadingText"
	title.text = _t("sInPrisonTitle", "In prison")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(16, 4) * s
	title.size = Vector2(260, 18) * s
	c.add_child(title)
	var bg := Panel.new()
	bg.name = "ProgressBar"
	bg.add_theme_stylebox_override("panel", UI.bar_back())
	bg.position = Vector2(16, 26) * s
	bg.size = Vector2(260, 6) * s
	c.add_child(bg)
	bar_fill = ColorRect.new()
	bar_fill.color = UI.color("health")
	bar_fill.position = Vector2(1, 1) * s
	bar_fill.size = Vector2(0, 4) * s
	bg.add_child(bar_fill)

## onJailProgressChanged: długość suwaka = cur / zakres (101) × długość paska.
func _set_progress(n: int) -> void:
	if bar_fill == null or not is_instance_valid(bar_fill):
		return
	var s: float = UI.ui_scale()
	bar_fill.size.x = floorf(float(n) / 101.0 * 258.0 * s)

func _process(dt: float) -> void:
	if main == null:
		return
	# World::update (bez pauzy): oczekujące przeniesienie do więzienia, koniec stanu „w więzieniu”
	if not get_tree().paused and main.get("crime") != null and main.crime != null:
		if main.state.player.has("go_to_jail"):
			var n := int(main.state.player["go_to_jail"])
			main.state.player.erase("go_to_jail")
			main.weapon_drawn = false            # setDrawState(Nothing)
			main.magic_ready = false
			if main.dialogue_window != null and main.dialogue_window.visible:
				main.dialogue_window.close(true)  # removeGuiMode(GM_Dialogue)
			go_to_jail(n)
		elif bool(main.state.player.get("in_jail", false)) and not main.gui.contains("jail"):
			main.state.player["in_jail"] = false
	# JailScreen::onFrame
	_advance(dt)
	if fade_remaining <= 0.0:
		return
	fade_remaining -= dt
	if fade_remaining <= 0.0:
		_teleport()

func _teleport() -> void:
	var m: Dictionary = main.crime.closest_marker("prisonmarker")
	if not m.is_empty():
		var pos := Vector3(float(m.pos[0]), float(m.pos[1]), float(m.pos[2]))
		var cell := String(m.name) if not String(m.cell).begins_with("ext:") else ""
		main.travel_to_cell(cell, pos, rad_to_deg(float(m.rot[2])))
	if main.has_method("cancel_reveal_fade"):
		main.cancel_reveal_fade()                # „override fade-in caused by cell transition”
	if main.fader != null:
		main.fader.fade_screen_out(0.0)
	visible = true
	running = true
	cur = 0
	total = 100
	_remaining = STEP
	history.append("teleport")

## TimeAdvancer::onFrame.
func _advance(dt: float) -> void:
	if not running:
		return
	_remaining -= dt
	while _remaining <= 0.0:
		_remaining += STEP
		cur += 1
		if cur <= total:
			_set_progress(cur)
		else:
			running = false
			_finished()
			return

## onJailFinished.
func _finished() -> void:
	visible = false
	main.gui.remove("jail")
	if main.fader != null:
		main.fader.fade_screen_in(0.5)
	var r: Dictionary = main.crime.serve_jail_time(days)
	history.append("finished")
	var lines := [_released_text(days)]
	for d in r.get("changes", []):
		var key := "sNotifyMessage39" if int(d.diff) > 0 else "sNotifyMessage44"
		var fb := "Your %s skill increased to %d." if int(d.diff) > 0 else "Your %s skill decreased to %d."
		lines.append(_fmt(_t(key, fb), [String(d.name), int(d.level)]))
	main.show_message_box("\n".join(lines), [preload("res://scripts/mw/mw_l10n.gd").ctx_text("Interface", "OK", "OK")], Callable(), true)   # I.UI.showInteractiveMessage

func _released_text(n: int) -> String:
	if n == 1:
		return _fmt(_t("sNotifyMessage42", "You've been released from prison after %d day."), [n])
	return _fmt(_t("sNotifyMessage43", "You've been released from prison after %d days."), [n])

## Podstawienie argumentów GMST w kolejności (%d, %s) jak l10n „{gmst:…}” ze zmiennymi.
static func _fmt(text: String, args: Array) -> String:
	var out := ""
	var i := 0
	var a := 0
	while i < text.length():
		var ch := text[i]
		if ch == "%" and i + 1 < text.length() and text[i + 1] in ["d", "s", "i"] and a < args.size():
			out += str(args[a])
			a += 1
			i += 2
			continue
		out += ch
		i += 1
	return out
