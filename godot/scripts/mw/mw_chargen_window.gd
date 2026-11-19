extends CanvasLayer
## Tworzenie postaci jak OpenMW CharacterCreation (apps/openmw/mwgui/charactercreation.cpp): osobne okna
## – imię (TextInputDialog, openmw_text_input.layout), rasa (RaceDialog, openmw_chargen_race.layout: podgląd
## głowy 3D z obrotem, płeć, twarz, włosy, lista ras, premie umiejętności, moce), klasa (ClassChoiceDialog
## i okna klas – mw_chargen_class.gd), znak urodzenia (BirthDialog, openmw_chargen_birth.layout: lista, obraz,
## zdolności, moce i czary z efektami) i przegląd (ReviewDialog, openmw_chargen_review.layout: imię, rasa, klasa,
## znak z przyciskami powrotu, zdrowie/magia/kondycja, atrybuty, umiejętności główne/drugorzędne/pozostałe,
## zdolności, moce, czary).
##
## Etapy jak CSE_*: kolejne okno otwiera się po zatwierdzeniu tylko wtedy, gdy postać już przeszła dany etap
## (handleDialogDone); inaczej okno się zamyka i dalszy przebieg prowadzą skrypty (EnableRaceMenu itd.).
## „Wstecz” – rasa → imię, klasa/znak → wybór sposobu klasy, przegląd → znak (ReviewBack: potem znów przegląd);
## przyciski przeglądu otwierają dane okno (ReviewNext: po zatwierdzeniu powrót do przeglądu).
## Każdy wybór trafia od razu do postaci (setPlayerName/Race/Class/Birthsign) przez sygnał step_done – statystyki
## liczy wyłącznie MWCharacter.build od zera (rasa, znak, klasa), więc powroty nie dublują premii.
## Tryb szybki (open(): kreator bez skryptów CharGen) – okna kolejno, na końcu przegląd i sygnał created.

signal created(stats: Dictionary)
signal step_done(step: String, choice: Dictionary)

const CUI := preload("res://scripts/mw/mw_chargen_ui.gd")
const UI := preload("res://scripts/mw/mw_ui.gd")

# etapy CharacterCreation::CSE
const CSE_NOT_STARTED := 0
const CSE_NAME := 1
const CSE_RACE := 2
const CSE_CLASS := 3
const CSE_BIRTH := 4
const CSE_REVIEW_BACK := 5
const CSE_REVIEW_NEXT := 6

const STEP_OF_MODE := {"name": "name", "race": "race", "class": "class", "class_pick": "class",
	"class_create": "class", "class_generate": "class", "birth": "birth", "review": "statreview"}
const MODE_OF_STEP := {"name": "name", "race": "race", "class": "class", "birth": "birth", "statreview": "review"}

var character          # MWCharacter
var loc = null
var main = null
var stage := CSE_NOT_STARTED
var quick := false               # kreator bez skryptów: okna jedno po drugim
var mode := ""                   # bieżący tryb okna (GuiMode): name, race, class, class_pick, class_create, class_generate, birth, review
var step := ""                   # name/race/class/birth/statreview – do sond i testów; "" gdy zamknięte
var cur := {}                    # wybory postaci (imię, rasa, płeć, głowa, włosy, klasa, znak)
var ui                           # MWChargenUI (skala, teksty)
var win: Control = null          # bieżące okno
var class_dialog                 # okna klas (mw_chargen_class.gd)
var history: Array = []          # przebieg trybów (diagnostyka i testy)

# okno imienia
var name_edit: LineEdit = null
var ok_button: Button = null
var back_button: Button = null
# okno rasy
var race_list: ItemList = null
var races: Array = []            # id ras w kolejności listy (według nazwy)
var race_id := ""
var female := false
var heads: Array = []
var hairs: Array = []
var face_index := 0
var hair_index := 0
var head_rotate: HScrollBar = null
var preview_vp: SubViewport = null
var preview_rect: TextureRect = null
var _doll: Node3D = null
var _cam: Camera3D = null
var angle := 0.0
var skill_box: Control = null
var power_box: Control = null
# okno znaku
var birth_list: ItemList = null
var signs: Array = []
var sign_id := ""
var birth_image: TextureRect = null
var spell_area: Control = null
# okno przeglądu
var review_values := {}          # do testów: {"name","race","class","sign","health","magicka","fatigue","attributes","skills","spells"}

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	class_dialog = preload("res://scripts/mw/mw_chargen_class.gd").new()
	class_dialog.name = "ClassDialogs"
	class_dialog.cg = self
	add_child(class_dialog)

func _scale() -> float:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	return UI.ui_scale()

func _make_ui() -> void:
	ui = CUI.new(main, _scale())

# --- przebieg (CharacterCreation) ---------------------------------------------------------------------------

## Kreator bez skryptów (szybka nowa gra): imię → rasa → klasa → znak → przegląd.
func open(defaults: Dictionary = {}) -> void:
	quick = true
	stage = CSE_NOT_STARTED
	cur = defaults.duplicate()
	class_dialog.reset()
	_push("name")

## Nowa gra (CharacterCreation tworzone od nowa): etap początkowy, okno własnej klasy bez zapamiętanych wyborów.
func reset() -> void:
	_pop()
	stage = CSE_NOT_STARTED
	quick = false
	history = []
	class_dialog.reset()
	_finish_if_closed()

## Menu wywołane skryptem (EnableNameMenu, EnableRaceMenu, EnableClassMenu, EnableBirthMenu, EnableStatReviewMenu).
func open_step(s: String, defaults: Dictionary) -> void:
	quick = false
	cur = defaults.duplicate()
	_push(String(MODE_OF_STEP.get(s, s)))

func is_open() -> bool:
	return visible and not mode.is_empty()

## pushGuiMode + spawnDialog.
func _push(m: String) -> void:
	_close_window()
	_make_ui()
	mode = m
	step = String(STEP_OF_MODE.get(m, m))
	history.append(m)
	visible = true
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match m:
		"name":
			_spawn_name()
		"race":
			_spawn_race()
			stage = maxi(stage, CSE_NAME)
		"class":
			class_dialog.spawn_choice()
			stage = maxi(stage, CSE_RACE)
		"class_pick":
			class_dialog.spawn_pick()
			stage = maxi(stage, CSE_RACE)
		"class_create":
			class_dialog.spawn_create()
			stage = maxi(stage, CSE_RACE)
		"class_generate":
			class_dialog.spawn_generate()
			stage = maxi(stage, CSE_RACE)
		"birth":
			_spawn_birth()
			stage = maxi(stage, CSE_CLASS)
		"review":
			_spawn_review()
			stage = maxi(stage, CSE_BIRTH)

## popGuiMode: zamknięcie okna; gdy nic nie zostaje otwarte – powrót do gry.
func _pop() -> void:
	_close_window()
	mode = ""
	step = ""

func _close_window() -> void:
	if win != null:
		CUI.close(win)
		win = null
	class_dialog.close_all()
	_free_preview()
	name_edit = null
	ok_button = null
	back_button = null

func _finish_if_closed() -> void:
	if not mode.is_empty():
		return
	visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## handleDialogDone(currentStage, nextMode).
func handle_done(current_stage: int, next_mode: String) -> void:
	_pop()
	if stage == CSE_REVIEW_NEXT:
		_push("review")
	elif stage >= current_stage or quick:
		stage = maxi(stage, current_stage)
		_push(next_mode)
	else:
		stage = current_stage
	_finish_if_closed()

## Natychmiastowe zastosowanie wyboru do postaci (MechanicsManager::setPlayer*).
func apply(s: String, part: Dictionary) -> void:
	cur.merge(part, true)
	step_done.emit(s, part)

func next_shown(min_stage: int) -> bool:
	return stage >= min_stage

## Zatwierdzenie bieżącego okna (OK) – sondy i testy. Przy wyborze sposobu klasy: lista klas i jej OK.
func accept() -> bool:
	match mode:
		"name":
			return _name_ok()
		"race":
			return _race_ok()
		"class":
			class_dialog.choice_selected(1)
			return class_dialog.pick_ok()
		"class_pick":
			return class_dialog.pick_ok()
		"class_create":
			return class_dialog.create_ok()
		"class_generate":
			return class_dialog.generate_ok()
		"birth":
			return _birth_ok()
		"review":
			_review_done()
			return true
	return false

## Zgodność z sondami (dawny kreator).
func _create() -> void:
	if mode == "name" and name_edit != null and name_edit.text.strip_edges().is_empty():
		name_edit.text = String(cur.get("name", "")) if not String(cur.get("name", "")).is_empty() else "Przybysz"
	accept()

## „Wstecz” w bieżącym oknie.
func back() -> void:
	match mode:
		"race":
			_race_back()
		"class":
			class_dialog.choice_selected(3)
		"class_pick":
			class_dialog.pick_back()
		"class_create":
			class_dialog.create_back()
		"class_generate":
			class_dialog.generate_back()
		"birth":
			_birth_back()
		"review":
			_review_back()

## Wybór na liście bieżącego okna (testy): race / class / birthsign.
func choose(kind: String, id: String) -> bool:
	match kind:
		"race":
			if mode != "race":
				return false
			var i := races.find(id.to_lower())
			if i < 0:
				return false
			race_list.select(i)
			_on_race_selected(i)
			return true
		"class":
			return class_dialog.choose_class(id)
		"birthsign":
			if mode != "birth":
				return false
			var j := signs.find(id.to_lower())
			if j < 0:
				return false
			birth_list.select(j)
			_on_sign_selected(j)
			return true
	return false

func choice() -> Dictionary:
	return cur.duplicate()

# --- imię (TextInputDialog, 320 × 97) -----------------------------------------------------------------------

func _spawn_name() -> void:
	win = ui.modal(self, 320, 97)
	var c: Control = win.get_meta("client")
	var lbl: Label = ui.label(c, 6, 6, 300, 18, ui.t("sName", "Imię"), "header")
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_edit = LineEdit.new()
	name_edit.name = "TextEdit"
	name_edit.text = String(cur.get("name", ""))
	name_edit.add_theme_stylebox_override("normal", UI.inner_box(Color(0, 0, 0, 0)))
	name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	name_edit.add_theme_color_override("font_color", UI.color("normal"))
	name_edit.text_submitted.connect(func(_t): _name_ok())
	ui.at(name_edit, c, 6, 28, 300, 30)
	var cap: String = ui.t("sNext", "Dalej") if next_shown(CSE_NAME) else ui.t("sOK", "OK")
	ok_button = ui.button(cap, func(): _name_ok())
	ok_button.name = "OKButton"
	# OKButton 264,60 (ExpandDirection Left: prawy brzeg w 306)
	ok_button.position = Vector2(306 * ui.sc - ok_button.size.x, 60 * ui.sc)
	c.add_child(ok_button)
	name_edit.grab_focus.call_deferred()
	name_edit.caret_column = name_edit.text.length()

## TextInputDialog::onOkClicked: puste imię – komunikat sNotifyMessage37, okno zostaje.
func _name_ok() -> bool:
	if name_edit == null:
		return false
	var n := name_edit.text.strip_edges()
	if n.is_empty():
		if main != null and main.has_method("show_message_box"):
			main.show_message_box(ui.t("sNotifyMessage37", "Musisz podać imię."), [])
		name_edit.grab_focus()
		return false
	apply("name", {"name": n})
	handle_done(CSE_NAME, "race")
	return true

# --- rasa (RaceDialog, 640 × 433) ---------------------------------------------------------------------------

func _race_ids() -> Array:
	var out: Array = character.playable("race")
	out.sort_custom(func(a, b): return ui.rec_name("race", "RACE", a).naturalnocasecmp_to(ui.rec_name("race", "RACE", b)) < 0)
	return out

func _spawn_race() -> void:
	win = ui.modal(self, 640, 433)
	var c: Control = win.get_meta("client")
	var hdr: Label = ui.label(c, 8, 16, 241, 18, ui.t("sRaceMenu1", "Wygląd"), "header")
	hdr.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# podgląd głowy (RaceSelectionPreview 512 × 512 w obrazie 237 × 216)
	ui.box(c, 8, 39, 241, 220)
	preview_rect = TextureRect.new()
	preview_rect.name = "PreviewImage"
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
	preview_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_rect.gui_input.connect(_on_preview_input)
	ui.at(preview_rect, c, 10, 41, 237, 216)
	head_rotate = HScrollBar.new()
	head_rotate.name = "HeadRotate"
	head_rotate.min_value = 0
	head_rotate.max_value = 1000
	head_rotate.page = 1
	head_rotate.step = 1
	_style_scroll(head_rotate)
	ui.at(head_rotate, c, 8, 270, 241, 14)
	var rows := [["sRaceMenu2", "Zmień płeć", 298, 294, _gender_prev, _gender_next],
		["sRaceMenu3", "Zmień twarz", 320, 316, _face_prev, _face_next],
		["sRaceMenu4", "Zmień włosy", 342, 338, _hair_prev, _hair_next]]
	for r in rows:
		ui.box(c, 8, r[2], 15, 14)
		ui.arrow(c, 10, r[2] + 2, 10, 10, "left", r[4])
		var l: Label = ui.label(c, 25, r[3], 205, 18, ui.t(r[0], r[1]), "header", HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ui.box(c, 234, r[2], 15, 14)
		ui.arrow(c, 236, r[2] + 2, 10, 10, "right", r[5])
	var rt: Label = ui.label(c, 261, 16, 160, 18, ui.t("sRaceMenu5", "Rasa"), "header")
	rt.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	race_list = ui.list(c, 264, 39, 160, 150)
	race_list.name = "RaceList"
	races = _race_ids()
	for id in races:
		race_list.add_item(ui.rec_name("race", "RACE", id))
	race_list.item_selected.connect(_on_race_selected)
	race_list.item_activated.connect(func(_i): _race_ok())
	var st: Label = ui.label(c, 261, 210, 160, 18, ui.t("sRaceMenu7", "Specjalne"), "header")
	st.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	power_box = ui.group(c, 261, 230, 350, 140)
	var sk: Label = ui.label(c, 432, 39, 190, 18, ui.t("sBonusSkillTitle", "Premie umiejętności"), "header")
	sk.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	skill_box = ui.group(c, 432, 59, 190, 360)
	back_button = ui.button(ui.t("sBack", "Wstecz"), func(): _race_back())
	back_button.name = "BackButton"
	ok_button = ui.button(ui.t("sNext", "Dalej") if next_shown(CSE_RACE) else ui.t("sOK", "OK"), func(): _race_ok())
	ok_button.name = "OKButton"
	ui.button_row(c, 0, 393, 626, 28, [back_button, ok_button])
	# onOpen: wybór z postaci (prototyp gracza), części ciała, obrót początkowy 500 + 100
	_build_preview()
	set_race(String(cur.get("race", "")))
	female = bool(cur.get("female", false))
	_recount_parts()
	var hi := heads.find(String(cur.get("head", "")).to_lower())
	if hi >= 0:
		face_index = hi
	var ri := hairs.find(String(cur.get("hair", "")).to_lower())
	if ri >= 0:
		hair_index = ri
	head_rotate.value_changed.connect(_on_head_rotate)
	head_rotate.value = 1000 / 2 + 1000 / 10
	_on_head_rotate(head_rotate.value)
	_update_preview()
	race_list.grab_focus.call_deferred()

func _style_scroll(sb: HScrollBar) -> void:
	ui.style_vscroll(sb)
	sb.custom_step = 50

## setRaceId: zaznaczenie na liście (nieznana rasa – bez zaznaczenia), aktualizacja premii i mocy.
func set_race(id: String) -> void:
	race_id = id.to_lower()
	race_list.deselect_all()
	var i := races.find(race_id)
	if i >= 0:
		race_list.select(i)
		race_list.ensure_current_is_visible()
	else:
		race_id = ""
	_update_skills()
	_update_powers()

func _on_race_selected(i: int) -> void:
	if i < 0 or i >= races.size():
		return
	var id: String = races[i]
	if id == race_id:
		return
	race_id = id
	_recount_parts()
	_update_skills()
	_update_powers()
	_update_preview()

func _recount_parts() -> void:
	var hh: Dictionary = character.heads_hairs(race_id, female) if not race_id.is_empty() else {"heads": [], "hairs": []}
	heads = (hh.heads as Array).map(func(x): return String(x).to_lower())
	hairs = (hh.hairs as Array).map(func(x): return String(x).to_lower())
	face_index = 0
	hair_index = 0

static func _wrap(i: int, n: int) -> int:
	if n <= 0:
		return 0
	return ((i % n) + n) % n

func _gender_prev() -> void:
	female = not female
	_recount_parts()
	_update_preview()

func _gender_next() -> void:
	_gender_prev()

func _face_prev() -> void:
	face_index = _wrap(face_index - 1, heads.size())
	_update_preview()

func _face_next() -> void:
	face_index = _wrap(face_index + 1, heads.size())
	_update_preview()

func _hair_prev() -> void:
	hair_index = _wrap(hair_index - 1, hairs.size())
	_update_preview()

func _hair_next() -> void:
	hair_index = _wrap(hair_index + 1, hairs.size())
	_update_preview()

## getResult: rasa, płeć, głowa i włosy wybrane w oknie.
func race_result() -> Dictionary:
	return {"race": race_id, "female": female,
		"head": heads[face_index] if face_index < heads.size() else String(cur.get("head", "")),
		"hair": hairs[hair_index] if hair_index < hairs.size() else String(cur.get("hair", ""))}

func _select_race() -> void:
	if not race_id.is_empty():
		apply("race", race_result())

func _race_ok() -> bool:
	if race_list == null or race_list.get_selected_items().is_empty() or race_id.is_empty():
		return false
	_select_race()
	handle_done(CSE_RACE, "class")
	return true

func _race_back() -> void:
	_select_race()
	_pop()
	_push("name")

## updateSkills: premie rasy (MW_StatNameValue, wiersz co fontSize + 2).
func _update_skills() -> void:
	for ch in skill_box.get_children():
		ch.queue_free()
	if race_id.is_empty():
		return
	var race: Dictionary = character.records.record("race", race_id)
	var y := 0.0
	for b in race.get("skill_bonuses", []):
		var si := int(b.get("skill", -1))
		if si < 0 or si >= 27:
			continue
		ui.stat_row(skill_box, 0, y, 190, ui.skill_name(si), str(int(b.get("bonus", 0))))
		y += 18.0

## updateSpellPowers: moce i zdolności rasy (MW_StatName).
func _update_powers() -> void:
	for ch in power_box.get_children():
		ch.queue_free()
	if race_id.is_empty():
		return
	var race: Dictionary = character.records.record("race", race_id)
	var y := 0.0
	for p in race.get("powers", []):
		var l: Label = ui.label(power_box, 0, y, 350, 18, ui.rec_name("spell", "SPEL", String(p).to_lower()))
		l.tooltip_text = _spell_tooltip(String(p).to_lower())
		y += 18.0

func _spell_tooltip(id: String) -> String:
	var sp: Dictionary = character.records.record("spell", id)
	var lines := [ui.rec_name("spell", "SPEL", id)]
	var constant := int(sp.get("spell_type", 0)) in [1, 2, 3, 4]
	for e in sp.get("effects", []):
		lines.append(ui.effect_text(e, constant))
	return "\n".join(lines)

# podgląd 3D (MWRender::RaceSelectionPreview): kamera z przesunięciem (0, 125, 8) od kości głowy, patrzy na
# głowę + (0, 0, 8), pole widzenia 12,3°, światło kierunkowe z Inventory_Directional*, tło przezroczyste.
func _build_preview() -> void:
	preview_vp = SubViewport.new()
	preview_vp.name = "RacePreview"
	preview_vp.size = Vector2i(512, 512)
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = true
	preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_vp.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(preview_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _fb_color("Inventory_DirectionalAmbient", Color(0.0, 0.0, 0.0))
	e.ambient_light_energy = 1.0
	preload("res://scripts/mw/mw_environment.gd").apply_gamma_space(e)     # oświetlenie w gammie jak OpenMW
	env.environment = e
	preview_vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.light_color = _fb_color("Inventory_DirectionalDiffuse", Color(1.0, 1.0, 1.0))
	var az := deg_to_rad(_fb_float("Inventory_DirectionalRotationX", 110.0))
	var alt := deg_to_rad(_fb_float("Inventory_DirectionalRotationY", 90.0))
	# kierunek do światła w osiach MW: (−cos az · sin alt, sin az · sin alt, cos alt) → Godot (x, z, −y)
	var to_light_mw := Vector3(-cos(az) * sin(alt), sin(az) * sin(alt), cos(alt))
	var to_light := Vector3(to_light_mw.x, to_light_mw.z, -to_light_mw.y).normalized()
	if to_light.length() > 0.0:
		light.look_at_from_position(Vector3.ZERO, -to_light, Vector3.UP if absf(to_light.y) < 0.99 else Vector3.FORWARD)
	preview_vp.add_child(light)
	_cam = Camera3D.new()
	_cam.fov = 12.3
	_cam.near = 0.05
	_cam.far = 100.0
	preview_vp.add_child(_cam)
	_cam.current = true
	preview_rect.texture = preview_vp.get_texture()

func _fb_value(key: String) -> String:
	if main != null and main.has_method("fallback"):
		return String(main.fallback(key))
	return ""

func _fb_float(key: String, def: float) -> float:
	var v := _fb_value(key)
	return float(v) if v.is_valid_float() else def

func _fb_color(prefix: String, def: Color) -> Color:
	var r := _fb_value(prefix + "R")
	var g := _fb_value(prefix + "G")
	var b := _fb_value(prefix + "B")
	if not (r.is_valid_float() and g.is_valid_float() and b.is_valid_float()):
		return def
	return Color(float(r), float(g), float(b))

func _free_preview() -> void:
	if preview_vp != null and is_instance_valid(preview_vp):
		preview_vp.queue_free()
	preview_vp = null
	_doll = null
	_cam = null

## updatePreview: prototyp NPC gracza z wybraną rasą, płcią, głową i włosami – tylko głowa i włosy (VM_HeadOnly).
func _update_preview() -> void:
	if preview_vp == null or main == null or main.get("builder") == null:
		return
	var av = main.builder.actors
	if av == null or not av.available():
		return
	if _doll != null and is_instance_valid(_doll):
		_doll.queue_free()
		_doll = null
	var npc: Dictionary = av.record("npc", "player").duplicate()
	var r := race_result()
	npc["race"] = r.race
	npc["female"] = r.female
	npc["head"] = r.head
	npc["hair"] = r.hair
	_doll = av.build_npc_rec(npc, "player", 0, "", {}, true)
	if _doll == null:
		return
	_doll.process_mode = Node.PROCESS_MODE_ALWAYS
	preview_vp.add_child(_doll)
	_apply_angle()

## setAngle: pochylenie 6° i obrót wokół osi pionowej.
func _apply_angle() -> void:
	if _doll == null:
		return
	# MW: Quat(6°, X) · Quat(angle, Z); postać zwrócona do +Y MW (−Z Godota)
	_doll.basis = Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, deg_to_rad(6.0))

func _on_head_rotate(v: float) -> void:
	angle = (v / 999.0 - 0.5) * TAU
	_apply_angle()

func _on_preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			head_rotate.value = clampf(head_rotate.value + 50, 0, 999)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			head_rotate.value = clampf(head_rotate.value - 50, 0, 999)

func _process(_dt: float) -> void:
	if _doll == null or _cam == null or not is_instance_valid(_doll):
		return
	# UpdateCameraCallback: położenie kości „Bip01 Head” w świecie
	var head := _head_position()
	var off := Vector3(0, 8, -125) / MWCoords.UNITS_PER_METER     # MW (0, 125, 8)
	var look := Vector3(0, 8, 0) / MWCoords.UNITS_PER_METER
	_cam.look_at_from_position(head + off, head + look, Vector3.UP)

func _head_position() -> Vector3:
	var sk := _find_skeleton(_doll)
	if sk != null:
		var bi := sk.find_bone("Bip01 Head")
		if bi >= 0:
			return sk.global_transform * sk.get_bone_global_pose(bi).origin
	return _doll.global_position + Vector3(0, 1.7, 0)

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for ch in n.get_children():
		var s := _find_skeleton(ch)
		if s != null:
			return s
	return null

# --- znak urodzenia (BirthDialog, 527 × 378) ----------------------------------------------------------------

func _sign_ids() -> Array:
	var out: Array = character.playable("birthsign")
	out.sort_custom(func(a, b): return ui.rec_name("birthsign", "BSGN", a).naturalnocasecmp_to(ui.rec_name("birthsign", "BSGN", b)) < 0)
	return out

func _spawn_birth() -> void:
	win = ui.modal(self, 527, 378)
	var c: Control = win.get_meta("client")
	birth_list = ui.list(c, 8, 8, 232, 137)
	birth_list.name = "BirthsignList"
	signs = _sign_ids()
	for id in signs:
		birth_list.add_item(ui.rec_name("birthsign", "BSGN", id))
	birth_list.item_selected.connect(_on_sign_selected)
	birth_list.item_activated.connect(func(i): _on_sign_selected(i); _birth_ok())
	birth_image = ui.image_box(c, 248, 8, 263, 137)
	birth_image.name = "BirthsignImage"
	spell_area = ui.scroll_view(c, 8, 160, 507, 170)
	back_button = ui.button(ui.t("sBack", "Wstecz"), func(): _birth_back())
	back_button.name = "BackButton"
	ok_button = ui.button(ui.t("sNext", "Dalej") if next_shown(CSE_BIRTH) else ui.t("sOK", "OK"), func(): _birth_ok())
	ok_button.name = "OKButton"
	ui.button_row(c, 0, 338, 511, 28, [back_button, ok_button])
	# updateBirths: bez znaku postaci – pierwszy z listy; onOpen: znak postaci
	sign_id = ""
	var want := String(cur.get("birthsign", "")).to_lower()
	var idx := signs.find(want)
	if idx < 0 and not signs.is_empty():
		idx = 0
	if idx >= 0:
		birth_list.select(idx)
		birth_list.ensure_current_is_visible()
		sign_id = signs[idx]
	_update_spells()
	birth_list.grab_focus.call_deferred()

func _on_sign_selected(i: int) -> void:
	if i < 0 or i >= signs.size():
		return
	if String(signs[i]) == sign_id:
		return
	sign_id = signs[i]
	_update_spells()

## updateSpells: obraz znaku, zdolności (efekty stałe), moce, czary – z efektami (MW_EffectImage).
func _update_spells() -> void:
	for ch in spell_area.get_children():
		ch.queue_free()
	if sign_id.is_empty():
		birth_image.texture = null
		return
	var sign: Dictionary = character.records.record("birthsign", sign_id)
	var tex := String(sign.get("texture", ""))
	birth_image.texture = UI.texture("textures/" + tex.replace("\\", "/")) if not tex.is_empty() else null
	var cats := {1: [], 5: [], 0: []}
	for sid in sign.get("spells", []):
		var sp: Dictionary = character.records.record("spell", String(sid).to_lower())
		if sp.is_empty():
			continue
		var ty := int(sp.get("spell_type", 0))
		if cats.has(ty):
			cats[ty].append(String(sid).to_lower())
	var labels := {1: ["sBirthsignmenu1", "Zdolności:"], 5: ["sPowers", "Moce"], 0: ["sBirthsignmenu2", "Czary:"]}
	var y := 0.0
	for ty in [1, 5, 0]:
		if (cats[ty] as Array).is_empty():
			continue
		ui.label(spell_area, 0, y, 507, 18, ui.t(labels[ty][0], labels[ty][1]), "header")
		y += 18.0
		for sid in cats[ty]:
			var nl: Label = ui.label(spell_area, 0, y, 507, 18, ui.rec_name("spell", "SPEL", sid))
			nl.tooltip_text = _spell_tooltip(sid)
			y += 18.0
			var sp: Dictionary = character.records.record("spell", sid)
			for e in sp.get("effects", []):
				var mg: Dictionary = character.records.record("magiceffect", str(int(e.get("effect", -1))))
				ui.effect_line(spell_area, 0, y, 507, String(mg.get("icon", "")), ui.effect_text(e, ty == 1))
				y += 24.0
	ui.finish_canvas(spell_area, y)

func _select_sign() -> void:
	if not sign_id.is_empty():
		apply("birth", {"birthsign": sign_id})

func _birth_ok() -> bool:
	if birth_list == null or birth_list.get_selected_items().is_empty():
		return false
	_select_sign()
	handle_done(CSE_BIRTH, "review")
	return true

func _birth_back() -> void:
	_select_sign()
	_pop()
	_push("class")

# --- przegląd (ReviewDialog, 541 × 428) ---------------------------------------------------------------------

func _spawn_review() -> void:
	win = ui.modal(self, 541, 428)
	var c: Control = win.get_meta("client")
	# bieżąca postać gracza (wybory stosowane od razu przez step_done); bez gry – zbudowana z wyborów
	var st: Dictionary = character.build(cur)
	if main != null and main.has_method("player_stats") and not (main.player_stats() as Dictionary).is_empty():
		st = (main.player_stats() as Dictionary).duplicate(true)
	var d: Dictionary = character.derived(st)
	review_values = {"name": String(cur.get("name", st.get("name", ""))), "race": String(st.race),
		"class": String(st["class"]), "sign": String(st.birthsign)}
	# imię, rasa, klasa, znak
	ui.box(c, 8, 8, 265, 126)
	var bx = ui.group(c, 8, 8, 265, 126)
	var entries := [["NameButton", "sName", "Imię", 8, review_values.name, func(): _review_activate("name")],
		["RaceButton", "sRace", "Rasa", 37, ui.rec_name("race", "RACE", review_values.race), func(): _review_activate("race")],
		["ClassButton", "sClass", "Klasa", 66, _class_display_name(review_values["class"]), func(): _review_activate("class")],
		["SignButton", "sBirthSign", "Znak", 95, ui.rec_name("birthsign", "BSGN", review_values.sign), func(): _review_activate("birth")]]
	for en in entries:
		var b: Button = ui.button(ui.t(en[1], en[2]), en[5])
		b.name = en[0]
		b.size.y = 23 * ui.sc
		b.position = Vector2(8, en[3]) * ui.sc
		bx.add_child(b)
		ui.label(bx, 97, en[3] + 2, 161, 18, String(en[4]), "right")
	# zdrowie, magia, kondycja
	ui.box(c, 8, 144, 265, 72)
	var dyn = ui.group(c, 8, 144, 265, 72)
	var hp := [float(st.get("health", d.health.modified)), float(d.health.modified)]
	var mp := [float(st.get("magicka", d.magicka.modified)), float(d.magicka.modified)]
	var fp := [float(st.get("fatigue", d.fatigue.modified)), float(d.fatigue.modified)]
	review_values["health"] = [int(maxf(0, hp[0])), int(hp[1])]
	review_values["magicka"] = [int(maxf(0, mp[0])), int(mp[1])]
	review_values["fatigue"] = [int(fp[0]), int(fp[1])]
	_dyn_stat(dyn, 8, 8, ui.t("sHealth", "Zdrowie"), "health", review_values.health)
	_dyn_stat(dyn, 8, 27, ui.t("sMagic", "Magia"), "magic", review_values.magicka)
	_dyn_stat(dyn, 8, 46, ui.t("sFatigue", "Kondycja"), "fatigue", review_values.fatigue)
	# atrybuty
	ui.box(c, 8, 224, 265, 156)
	var at = ui.group(c, 8, 224, 265, 156)
	var attrs := []
	for i in 8:
		var base := float(st.attributes[i])
		var m := float(d.attributes[i])
		attrs.append(int(m))
		ui.stat_row(at, 8, 4 + 18 * i, 250, ui.attr_name(i), str(int(m)), _state(base, m))
	review_values["attributes"] = attrs
	# umiejętności i czary
	ui.box(c, 281, 7, 244, 372)
	var sv: Control = ui.scroll_view(c, 289, 13, 232, 362)
	var cls: Dictionary = character.records.record("class", review_values["class"])
	var major: Array = (cls.get("major_skills", []) as Array).map(func(x): return int(x))
	var minor: Array = (cls.get("minor_skills", []) as Array).map(func(x): return int(x))
	var misc := []
	for i in 27:
		if not i in major and not i in minor:
			misc.append(i)
	var y := 0.0
	var first := true
	var skills_out := {}
	for g in [["sSkillClassMajor", "Umiejętności główne", major], ["sSkillClassMinor", "Umiejętności drugorzędne", minor],
			["sSkillClassMisc", "Pozostałe umiejętności", misc]]:
		if (g[2] as Array).is_empty():
			continue
		if not first:
			y = _separator(sv, y)
		first = false
		ui.label(sv, 0, y, 198, 18, ui.t(g[0], g[1]), "header")
		y += 18.0
		for si in g[2]:
			var base2 := float(st.skills[si])
			var m2 := float(d.skills[si])
			skills_out[si] = int(m2)
			ui.label(sv, 10, y, 158, 18, ui.skill_name(si))
			var v: Label = ui.label(sv, 168, y, 40, 18, str(int(m2)), "right")
			var s2 := _state(base2, m2)
			if s2 == "increased":
				v.add_theme_color_override("font_color", UI.color("positive"))
			elif s2 == "decreased":
				v.add_theme_color_override("font_color", UI.color("negative"))
			y += 18.0
	review_values["skills"] = skills_out
	# zdolności, moce, czary (rasa, znak, czary początkowe)
	var spells: Array = st.get("spells", [])
	review_values["spells"] = spells.duplicate()
	for g2 in [[1, "sTypeAbility", "Zdolności"], [5, "sTypePower", "Moce"], [0, "sTypeSpell", "Czary"]]:
		y = _separator(sv, y)
		ui.label(sv, 0, y, 198, 18, ui.t(g2[1], g2[2]), "header")
		y += 18.0
		for sid in spells:
			var sp: Dictionary = character.records.record("spell", String(sid))
			if int(sp.get("spell_type", -1)) == int(g2[0]):
				var l: Label = ui.label(sv, 10, y, 198, 18, ui.rec_name("spell", "SPEL", String(sid)))
				l.tooltip_text = _spell_tooltip(String(sid))
				y += 18.0
	ui.finish_canvas(sv, y)
	back_button = ui.button(ui.t("sBack", "Wstecz"), func(): _review_back())
	back_button.name = "BackButton"
	ok_button = ui.button("OK", func(): _review_done())
	ok_button.name = "OKButton"
	ui.button_row(c, 0, 388, 525, 24, [back_button, ok_button])

func _class_display_name(id: String) -> String:
	return ui.rec_name("class", "CLAS", id)

func _state(base: float, mod: float) -> String:
	if mod > base:
		return "increased"
	if mod < base:
		return "decreased"
	return "normal"

func _separator(parent: Control, y: float) -> float:
	var line := ColorRect.new()
	line.color = UI.color("normal").darkened(0.45)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.at(line, parent, 10, y + 16, 194, 2)
	var t := UI.texture("textures/menu_thin_border_top")
	if t != null:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_TILE
		ui.at(tr, parent, 10, y + 16, 194, 2)
		line.visible = false
	return y + 18.0

## MWDynamicStat (MW_DynamicStat_*): napis 0..100, pasek od prawej 130 × 18, wartość „bieżąca/maks.”.
func _dyn_stat(parent: Control, x: float, y: float, title: String, kind: String, v: Array) -> void:
	var g = ui.group(parent, x, y, 249, 18)
	ui.label(g, 0, 0, 100, 18, title)
	var pb := UI.progress_bar(kind, ui.sc)
	pb.max_value = maxf(1.0, float(v[1]))
	pb.value = clampf(float(v[0]), 0.0, pb.max_value)
	ui.at(pb, g, 119, 0, 130, 18)
	var t: Label = ui.label(g, 119, 0, 130, 14, "%d/%d" % [int(v[0]), int(v[1])], "sand", HORIZONTAL_ALIGNMENT_CENTER)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	t.add_theme_constant_override("shadow_offset_x", 1)
	t.add_theme_constant_override("shadow_offset_y", 1)

func _review_done() -> void:
	_pop()
	_finish_if_closed()
	if quick:
		quick = false
		var st: Dictionary = character.build(cur)
		if main != null and not (main.player_stats() as Dictionary).is_empty():
			st = (main.player_stats() as Dictionary).duplicate(true)
		if String(st.get("name", "")).is_empty():
			st["name"] = String(cur.get("name", "Przybysz"))
		created.emit(st)

func _review_back() -> void:
	stage = CSE_REVIEW_BACK
	_pop()
	_push("birth")

## onReviewActivateDialog: ReviewNext – po zatwierdzeniu okna powrót do przeglądu.
func _review_activate(which: String) -> void:
	stage = CSE_REVIEW_NEXT
	_pop()
	_push(which)

# --- klawiatura ----------------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if not visible or mode.is_empty():
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).keycode
		if k in [KEY_ENTER, KEY_KP_ENTER] and mode in ["race", "birth", "class_pick"]:
			accept()
			get_viewport().set_input_as_handled()
