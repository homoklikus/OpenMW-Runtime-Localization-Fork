extends Node3D
## Gra: strumieniowanie komórek wokół gracza z przekonwertowanych danych.
## Argumenty (po "--"): --data=KATALOG  --project=KATALOG  --cell="Nazwa wnętrza"  --pos=x,y,z (MW)
## Domyślne wartości: ustawienia projektu mwgodot/*.

var db: MWWorldDB
var models: MWModelCache
var builder: MWCellBuilder
var player: CharacterBody3D
var loaded := {}  # key → Node3D
var radius := 1
var interior := ""
var envr: MWEnvironment
var hud: RichTextLabel
## preload zamiast class_name: gra działa też bez ponownego importu projektu po aktualizacji skryptów
const Loc := preload("res://scripts/mw/mw_localization.gd")
const Flora := preload("res://scripts/mw/mw_flora.gd")
const GameStateScript := preload("res://scripts/mw/mw_game_state.gd")
const Events := preload("res://scripts/mw/mw_events.gd")
const MWInput := preload("res://scripts/mw/mw_input.gd")
const InteractionScript := preload("res://scripts/mw/mw_interaction.gd")
const InventoryScript := preload("res://scripts/mw/mw_inventory.gd")
const ItemWindowScript := preload("res://scripts/mw/mw_item_window.gd")
const CharacterScript := preload("res://scripts/mw/mw_character.gd")
const ChargenScript := preload("res://scripts/mw/mw_chargen_window.gd")
const ScriptsVM := preload("res://scripts/mw/mw_scripts.gd")
const ScriptHost := preload("res://scripts/mw/mw_script_host.gd")
const DialogueScript := preload("res://scripts/mw/mw_dialogue.gd")
const DialogueWindowScript := preload("res://scripts/mw/mw_dialogue_window.gd")
const JournalWindowScript := preload("res://scripts/mw/mw_journal_window.gd")
const RestWindowScript := preload("res://scripts/mw/mw_rest_window.gd")
const MagicScript := preload("res://scripts/mw/mw_magic.gd")
const TradeScript := preload("res://scripts/mw/mw_trade.gd")
const TradeWindowScript := preload("res://scripts/mw/mw_trade_window.gd")
const CombatScript := preload("res://scripts/mw/mw_combat.gd")
const EQ := preload("res://scripts/mw/mw_equipment.gd")
var events = Events.new()           # szyna zdarzeń (etap 0)
var interaction = null                # MWInteraction (etap 3)
var item_window = null                # okno pojemnika / ekwipunku
var audio = null                      # MWAudio (etap 3)
var character = null                  # MWCharacter (etap 4) – statystyki w state.player["character"]
var chargen = null                    # kreator postaci
var scripts = null                    # MWScripts (etap 5)
var script_host = null
var msgbox = null                     # okno MessageBox z przyciskami
var dialogue = null                   # MWDialogue (etap 6)
var dialogue_window = null
var journal_window = null
var rest_window = null                # etap 7: odpoczynek i awans
var magic = null                      # etap 7: wzory magii (koszty, efekty)
var trade = null                      # etap 7: handel i usługi
var trade_window = null
var combat = null                     # etap 7: walka
var magic_window = null               # etap 7d: magia, alchemia, zaklinanie
var ai = null                         # etap 8: AI aktorów (mw_ai.gd)
var crime = null                      # etap 8: przestępstwa i strażnicy (mw_crime.gd)
var magic_ready := false              # przygotowana magia (klawisz R) – lewy przycisk rzuca
var state = GameStateScript.new()   # różnice stanu gry względem danych bazowych (zapis gry)
var pause_menu: Control
var loc  # Loc
var current_region := ""
var settings := {}
var launched_by_launcher := false

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	# te same argumenty z override.cfg ([mwgodot] cli/<nazwa>=…) – start bez wiersza poleceń (np. przez MCP Godota)
	var ps := "mwgodot/cli/" + name
	if ProjectSettings.has_setting(ps):
		return str(ProjectSettings.get_setting(ps))
	return def

func _ready() -> void:
	MWInput.register_defaults()
	var mk := preload("res://scripts/mw/mw_menu_key.gd").new()
	mk.name = "MenuKey"
	mk.main = self
	add_child(mk)
	var data := arg("data", ProjectSettings.get_setting("mwgodot/data_root", "user://mwdata"))
	var base := arg("base")
	if not base.is_empty():
		MWModelCache.base_roots = PackedStringArray([ProjectSettings.globalize_path(base)])
	settings = _load_settings(arg("settings"))
	launched_by_launcher = not arg("profile").is_empty()
	var project := arg("project", ProjectSettings.get_setting("mwgodot/project_root", "user://mw_project"))
	data = ProjectSettings.globalize_path(data)
	project = ProjectSettings.globalize_path(project)
	radius = int(settings.get("load_radius", ProjectSettings.get_setting("mwgodot/load_radius", 1)))
	interior = arg("cell", ProjectSettings.get_setting("mwgodot/start_cell", ""))
	db = MWWorldDB.new(data, project)
	models = MWModelCache.new(data)
	builder = MWCellBuilder.new(db, models)
	builder.state = state
	state.ref_changed.connect(_on_ref_changed)
	state.dynamic_changed.connect(_on_dynamic_changed)
	state.inventory_changed.connect(_on_inventory_changed)
	# etap 3: ziarno list poziomowanych tej rozgrywki (tryb zrzutu/testów: stałe), inwentarze, interakcje
	state.seed = int(arg("seed", "0" if not arg("screenshot").is_empty() else str(randi())))
	builder.actors.inventory = InventoryScript.new(builder.actors, state)
	interaction = InteractionScript.new(db, state, builder.actors, builder.actors.inventory)
	if bool(settings.get("grass", true)):
		var fl = Flora.new(models, data, MWModelCache.base_roots)
		if fl.is_active():
			fl.distance = float(settings.get("grass_distance", 90))
			fl.density = float(settings.get("grass_density", 1.0))
			builder.flora = fl
			print("MWGODOT_FLORA tryb=", fl.index.get("mode", ""), " komórki=", fl.index.get("cells", {}).size())
	loc = Loc.create(data, MWModelCache.base_roots, String(settings.get("game_language", "auto")),
			String(settings.get("language", "")), String(settings.get("qa_source", "")))
	if loc.is_active():
		print("MWGODOT_LOCALIZATION ", ",".join(loc.languages), " (dostępne: ", ",".join(loc.available), ")")
	builder.with_water = bool(settings.get("water", true))
	interaction.loc = loc
	character = CharacterScript.new(builder.actors)
	chargen = ChargenScript.new()
	chargen.character = character
	chargen.loc = loc
	add_child(chargen)
	chargen.created.connect(_on_character_created)
	chargen.step_done.connect(_on_chargen_step)
	script_host = ScriptHost.new(self)
	scripts = ScriptsVM.new(builder.actors, state, script_host, db)
	dialogue = DialogueScript.new(builder.actors, state, self)
	dialogue_window = DialogueWindowScript.new()
	dialogue_window.dialogue = dialogue
	dialogue_window.main = self
	add_child(dialogue_window)
	magic = MagicScript.new(builder.actors, self)
	character.magic = magic
	builder.actors.dynamic = state.created
	db.created = state.created
	trade = TradeScript.new(self)
	combat = CombatScript.new(self)
	ai = preload("res://scripts/mw/mw_ai.gd").new(self)
	ai.enabled = arg("ai", "1") != "0"
	crime = preload("res://scripts/mw/mw_crime.gd").new(self)
	interaction.crime = crime
	interaction.main_scripts = scripts
	trade_window = TradeWindowScript.new()
	trade_window.main = self
	trade_window.trade = trade
	add_child(trade_window)
	rest_window = RestWindowScript.new()
	rest_window.main = self
	rest_window.character = character
	add_child(rest_window)
	magic_window = preload("res://scripts/mw/mw_magic_window.gd").new()
	magic_window.main = self
	magic_window.magic = magic
	add_child(magic_window)
	journal_window = JournalWindowScript.new()
	journal_window.dialogue = dialogue
	journal_window.main = self
	add_child(journal_window)
	audio = preload("res://scripts/mw/mw_audio.gd").new()
	audio.name = "Audio"
	audio.setup(data, builder.actors)
	audio.enabled = arg("screenshot").is_empty() and bool(settings.get("sound", true))
	add_child(audio)
	item_window = ItemWindowScript.new()
	item_window.interaction = interaction
	item_window.main = self
	add_child(item_window)
	if db.cell_index().is_empty():
		push_error("Brak danych świata w %s – uruchom konwerter (README)." % data)
		_add_message("Brak danych świata w:\n%s\nUruchom konwerter mwconv (patrz docs/DEBIAN13.md)." % data)
		if launched_by_launcher:
			printerr("MWGODOT_ERROR brak danych świata: ", data)
			get_tree().quit(2)  # launcher pokaże błąd z kodem wyjścia
		return
	envr = MWEnvironment.new()
	envr.name = "Environment"
	var regs = MWWorldDB._read_json(data.path_join("world/regions.json"))
	if regs is Dictionary:
		envr.regions = regs
	add_child(envr)
	_setup_hud()
	player = preload("res://scripts/player.gd").new() as CharacterBody3D
	player.name = "Player"
	player.mouse_sens = float(settings.get("mouse_sensitivity", player.mouse_sens))
	player.invert_y = bool(settings.get("invert_y", false))
	add_child(player)
	if player.controller != null:
		player.controller.allowed = control_allowed       # blokady sterowania ze skryptów (CharGen)
	_apply_settings()
	var start_t := _start_transform()
	player.global_position = start_t.origin
	player.rotation.y = start_t.basis.get_euler().y
	_apply_capture()
	var lp := arg("load")
	if not lp.is_empty():
		var lw := load_game(lp)
		print("MWGODOT_LOADED ", lp, " ", JSON.stringify(lw))
		if not lw.is_empty():
			_toast("\n".join(lw), 8.0)
	if not interior.is_empty():
		var key := "int:" + interior.to_lower()
		_load(key)
		envr.set_interior(db.get_cell(key))
	else:
		_update_streaming(true)
	player.landed.connect(_on_player_landed)
	player.jumped.connect(_on_player_jumped)
	var scripted_start := lp.is_empty() and scripts != null and _scripted_chargen_wanted()
	if scripted_start:
		_start_scripted_chargen()          # nowa gra jak w Morrowindzie: statek więzienny i CharGen ze skryptów
	elif lp.is_empty() and scripts != null:
		scripts.start_new_game()          # skrypty startowe nowej gry („main”, SSCR)
	# nowa gra: kreator postaci (gra z launchera, bez wczytywania zapisu); tryby zrzutu/testów – postać domyślna
	if not (state.player.get("character", {}) as Dictionary).is_empty():
		pass
	elif scripted_start:
		state.player["character"] = character.build(default_choice())
	elif launched_by_launcher and lp.is_empty() and arg("screenshot").is_empty() and arg("autotest-frames", "0") == "0" \
			and bool(settings.get("character_creation", true)) and builder.actors.available():
		chargen.open(default_choice())
	else:
		state.player["character"] = character.build(default_choice())

# --- nowa gra ze skryptami CharGen (etap 9) -------------------------------------------------------------------

const CHARGEN_MENUS := ["inventory", "magic", "map", "stats", "rest"]

## Nowa gra jak w Morrowindzie (World::startNewGame bez pomijania): gdy są skrypty CharGen i tryb nie jest
## „szybki” (ustawienie chargen_mode, argument --newgame=morrowind|quick).
func _scripted_chargen_wanted() -> bool:
	var mode := arg("newgame", String(settings.get("chargen_mode", "morrowind")) if launched_by_launcher else "")
	if mode != "morrowind" or not arg("cell").is_empty() or not arg("pos").is_empty():
		return false
	return not scripts.script_rec("chargen").is_empty() and not scripts.script_rec("main").is_empty()

## CharGenState = 1, okna zablokowane (setNewGame), skrypty startowe uruchomione 5 razy przed pierwszą klatką
## („main” uruchamia CharGen, który przenosi gracza na statek PositionCell i ustawia CharGenState 10).
func _start_scripted_chargen() -> void:
	state.player["menus"] = {}
	for m in CHARGEN_MENUS:
		state.player["menus"][m] = false
	state.player["chargen_choice"] = default_choice()
	scripts.set_global("chargenstate", 1.0)
	scripts.start_new_game()
	for i in 5:
		scripts.tick(0.0, [])

func menu_allowed(kind: String) -> bool:
	return bool((state.player.get("menus", {}) as Dictionary).get(kind, true))

func control_allowed(kind: String) -> bool:
	return script_host == null or script_host.control_enabled(kind)

## Menu tworzenia postaci wywołane skryptem: imię, rasa (z płcią, głową, włosami), klasa, znak, przegląd.
func open_chargen_step(step: String) -> void:
	if chargen == null:
		return
	var ch: Dictionary = state.player.get("chargen_choice", default_choice())
	chargen.open_step(step, ch)

func _on_chargen_step(step: String, ch: Dictionary) -> void:
	var merged: Dictionary = state.player.get("chargen_choice", default_choice())
	merged.merge(ch, true)
	state.player["chargen_choice"] = merged
	var old: Dictionary = state.player.get("character", {})
	var st: Dictionary = character.build(merged)
	if String(st.get("name", "")).is_empty():
		st["name"] = String(old.get("name", "")) if not String(old.get("name", "")).is_empty() else "Przybysz"
	state.player["character"] = st
	_rebuild_player_visual()

func _rebuild_player_visual() -> void:
	if player != null and player.has_method("rebuild_visual"):
		player.rebuild_visual()

## Napis kwestii (Say) – bez okna, nie wstrzymuje gry.
var _subtitle: Label = null
func subtitle(text: String, seconds: float) -> void:
	print("MWGODOT_SAY ", text.length())
	if _subtitle == null and hud != null:
		_subtitle = Label.new()
		_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle.anchor_left = 0.15
		_subtitle.anchor_right = 0.85
		_subtitle.anchor_top = 0.78
		_subtitle.anchor_bottom = 0.9
		_subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
		_subtitle.add_theme_constant_override("outline_size", 6)
		hud.get_parent().add_child(_subtitle)
	if _subtitle != null:
		_subtitle.text = text
		_subtitle.visible = true
		var t := get_tree().create_timer(seconds, false)
		t.timeout.connect(func(): if _subtitle != null and _subtitle.text == text: _subtitle.visible = false)

# --- postać gracza (etap 4) ---------------------------------------------------------------------------------

## Domyślny wybór z rekordu NPC „player” (Morrowind.esm): rasa, klasa, płeć, głowa, włosy.
func default_choice() -> Dictionary:
	var p: Dictionary = builder.actors.record("npc", "player")
	return {"name": "", "race": p.get("race", ""), "class": p.get("class", ""), "female": p.get("female", false),
		"head": p.get("head", ""), "hair": p.get("hair", ""), "birthsign": ""}

func player_stats() -> Dictionary:
	return state.player.get("character", {})

func _on_character_created(st: Dictionary) -> void:
	state.player["character"] = st
	_toast("Utworzono postać: %s" % st.get("name", ""))

## Obrażenia od upadku (OpenMW getFallDamage; w wodzie bez obrażeń). Śmierć i jej skutki – etap 7.
func _on_player_landed(height: float) -> void:
	var st := player_stats()
	if st.is_empty() or player.swimming or player.fly:
		return
	var dd: Dictionary = character.derived(st)
	var lost0: float = character.fall_damage(st, dd, height)
	var lost: float = character.apply_fall(st, height)
	if lost0 > 0.0 and lost0 <= float(dd.skills[character.SK_ACROBATICS]) * character.fatigue_term(st, dd):
		skill_used(character.SK_ACROBATICS, "acrobatics_fall")      # bez powalenia – postęp akrobatyki
	if lost > 0.0:
		if audio != null:
			audio.play("Health Damage")
		if float(st.health) <= 0.0:
			st["health"] = 0.0
			_player_died()
		else:
			_toast("Upadek: −%d zdrowia" % roundi(lost))

# --- etap 7: rozwój umiejętności, ruch wg statystyk, kondycja ----------------------------------------------

var _weight_cache := -1.0

func _on_inventory_changed(sid: String) -> void:
	if sid == "player":
		_weight_cache = -1.0
		_check_equipment()
var _run_secs := 0.0
var _swim_secs := 0.0

## Waga ekwipunku gracza (obciążenie); odświeżana po zmianie inwentarza.
func player_weight() -> float:
	if _weight_cache < 0.0 and interaction != null:
		var inv = interaction.inventory
		_weight_cache = float(inv.total_weight(inv.contents("player", {})))
	var w := maxf(_weight_cache, 0.0)
	var st := player_stats()
	if magic != null and not st.is_empty() and (st.has("active_spells") or st.has("equipment")):
		var fx: Dictionary = character.constant_effects(st)      # getEncumbrance: + Ciężar − Lekkość
		w = maxf(0.0, w + float(fx.get("7", 0.0)) - float(fx.get("8", 0.0)))
	return w

## Użycie umiejętności gracza (skillUsageSucceeded): komunikaty o wzroście i gotowości do awansu.
func skill_used(skill: int, use: String, scale := 1.0) -> void:
	var st := player_stats()
	if st.is_empty() or character == null:
		return
	for m in character.use_skill(st, skill, int(character.SKILL_USE.get(use, 0)), scale):
		_skill_message(m)

func _skill_message(m: Dictionary) -> void:
	if m.kind == "skill":
		var names: Array = builder.actors.records_index().get("skills", [])
		var sid := String(names[int(m.skill)]) if int(m.skill) < names.size() else ""
		var sname := sid
		var gm := "sSkill" + sid.capitalize().replace(" ", "")
		if dialogue != null:
			sname = dialogue.gmst_text(gm, sid)
		var tmpl: String = dialogue.gmst_text("sNotifyMessage39", "Twoja umiejętność %s wzrosła do %d.") if dialogue != null else "%s: %d"
		_toast(tmpl.replace("%s", sname).replace("%d", str(int(m.level))) if tmpl.contains("%s") else "%s: %d" % [sname, int(m.level)])
		if audio != null:
			audio.play("skillraise")
	elif m.kind == "levelup_ready":
		_toast(dialogue.gmst_text("sLevelUpMsg", "Powinieneś odpocząć i przemyśleć to, czego się nauczyłeś.") if dialogue != null else "Awans po odpoczynku.")

func _on_player_jumped() -> void:
	var st := player_stats()
	if st.is_empty():
		return
	st["fatigue"] = float(st.get("fatigue", 0.0)) - character.jump_fatigue(st, player_weight())
	skill_used(character.SK_ACROBATICS, "acrobatics_jump")

## Co klatkę: prędkości i skok wg statystyk (OpenMW getWalkSpeed/getRunSpeed/getJump), utrata kondycji za
## bieg/pływanie, odnowa kondycji, postęp atletyki za każdą sekundę biegu/pływania.
func _update_player_rpg(dt: float) -> void:
	var st := player_stats()
	if st.is_empty() or player == null or player.fly:
		return
	var w := player_weight()
	var mv: Dictionary = character.movement(st, w, player.want_run)
	var upm := MWCoords.UNITS_PER_METER
	player.walk_speed = float(mv.walk) / upm
	player.run_speed = float(mv.run) / upm
	player.swim_speed = float(mv.swim) / upm
	player.jump_velocity = float(mv.jump) / upm
	player.air_factor = float(mv.air_factor)
	if player.want_sneak:                      # fSneakSpeedMultiplier (chód skradając się)
		player.walk_speed *= float(combat._gmst("fSneakSpeedMultiplier", 0.75))
	if magic != null and magic.magnitude_of(combat.player_fighter(), magic.FX_PARALYZE) > 0.0:
		player.walk_speed = 0.0                    # paraliż: bez ruchu i skoku (animacja – etap 10)
		player.run_speed = 0.0
		player.swim_speed = 0.0
		player.jump_velocity = 0.0
	var moving: bool = player.move_input.length() > 0.01
	if moving:
		var fat := float(st.get("fatigue", 0.0))
		var loss: float = character.movement_fatigue(st, w, dt, player.want_run, player.swimming)
		if loss > 0.0:
			st["fatigue"] = fat - loss if fat < 0.0 else maxf(0.0, fat - loss)
		if player.swimming:
			_swim_secs += dt
			while _swim_secs > 1.0:
				skill_used(character.SK_ATHLETICS, "athletics_swim")
				_swim_secs -= 1.0
		elif player.want_run:
			_run_secs += dt
			while _run_secs > 1.0:
				skill_used(character.SK_ATHLETICS, "athletics_run")
				_run_secs -= 1.0
	character.restore_fatigue(st, dt)

# --- etap 7c: ekwipunek gracza i walka --------------------------------------------------------------------

var weapon_drawn := false
var _attack_hold := -1.0          # czas przytrzymania ataku (−1 – brak ataku)
var projectiles: Array = []       # [{"node", "vel", "att", "launcher", "ammo", "strength", "life"}]
const ATTACK_WINDUP_SECONDS := 0.6  # pełny zamach (OpenMW: klucze „min/max attack” animacji × szybkość broni)

func player_ready_to_block() -> bool:
	return weapon_drawn and _attack_hold < 0.0

func _equipment() -> Dictionary:
	var st := player_stats()
	if not st.get("equipment") is Dictionary:
		st["equipment"] = {}
	return st.equipment

## Miejsca dla przedmiotu (InventoryStore: broń w prawej ręce, amunicja, zbroja wg typu, tarcza i światło w lewej,
## ubrania wg typu, pierścienie – lewy, potem prawy).
func item_slots(id: String) -> Array:
	var it: Dictionary = interaction.inventory.item(id)
	if it.is_empty():
		return []
	match String(it.kind):
		"weapon":
			var t := int(it.rec.get("weapon_type", 0))
			return [EQ.SLOT_AMMUNITION] if t in [12, 13] else [EQ.SLOT_CARRIED_RIGHT]
		"armor":
			var at := int(it.rec.get("armor_type", -1))
			return [EQ.ARMOR_SLOTS[at]] if EQ.ARMOR_SLOTS.has(at) else []
		"clothing":
			return EQ.CLOTHING_SLOTS.get(int(it.rec.get("clothing_type", -1)), [])
		"light":
			return [EQ.SLOT_CARRIED_LEFT] if bool(it.rec.get("carry", false)) else []
		"lockpick", "probe":
			return [EQ.SLOT_CARRIED_RIGHT]              # wytrych/sonda w prawej ręce (etap 8: Security)
	return []

func equipped_slot_of(id: String) -> int:
	var eq := _equipment()
	for s in eq:
		if String(eq[s].id) == id.to_lower():
			return int(s)
	return -1

## Załóż przedmiot gracza. Broń dwuręczna zdejmuje tarczę i odwrotnie. → komunikat ("" = gotowe)
func equip_item(id: String) -> String:
	var k := id.to_lower()
	if interaction.inventory.count_of("player", {}, k) <= 0:
		return "Nie masz tego przedmiotu."
	var slots := item_slots(k)
	if slots.is_empty():
		return "Tego przedmiotu nie można założyć."
	var eq := _equipment()
	var slot: int = slots[0]
	if slots.size() > 1 and eq.has(str(slots[0])) and not eq.has(str(slots[1])):
		slot = slots[1]
	var it: Dictionary = interaction.inventory.item(k)
	if slot == EQ.SLOT_CARRIED_RIGHT and int(it.rec.get("weapon_type", 0)) in EQ.WEAPON_TWO_HANDED:
		eq.erase(str(EQ.SLOT_CARRIED_LEFT))
	if slot == EQ.SLOT_CARRIED_LEFT and eq.has(str(EQ.SLOT_CARRIED_RIGHT)):
		var w: Dictionary = interaction.inventory.item(String(eq[str(EQ.SLOT_CARRIED_RIGHT)].id))
		if not w.is_empty() and int(w.rec.get("weapon_type", 0)) in EQ.WEAPON_TWO_HANDED:
			eq.erase(str(EQ.SLOT_CARRIED_RIGHT))
	var prev := equipped_slot_of(k)
	if prev >= 0 and interaction.inventory.count_of("player", {}, k) <= 1:
		eq.erase(str(prev))
	eq[str(slot)] = {"id": k, "health": -1.0}
	_weight_cache = -1.0
	if scripts != null:
		scripts.item_equipped(k)             # OnPCEquip
	return ""

func unequip_slot(slot: int) -> void:
	_equipment().erase(str(slot))

## Zdejmuje założone rzeczy, których gracz już nie ma (sprzedane, odłożone).
func _check_equipment() -> void:
	var eq := _equipment()
	for s in eq.keys():
		if interaction.inventory.count_of("player", {}, String(eq[s].id)) <= 0:
			eq.erase(s)

## Cel ataku wręcz (getHitContact): najbliższy żywy aktor w zasięgu, przed graczem (kąty fCombatAngleXY/Z),
## w linii wzroku.
func melee_target(reach_units: float) -> Dictionary:
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return {}
	var upm := MWCoords.UNITS_PER_METER
	var pmw := MWCoords.godot_to_mw(player.global_position)
	var fwd := -cam.global_transform.basis.z
	var dir_xy := Vector2(fwd.x, -fwd.z).normalized()           # MW: x, y (y = −z Godota)
	var vert := fwd.y
	var axy := float(combat._gmst("fCombatAngleXY", 60.0)) / 90.0
	var az := float(combat._gmst("fCombatAngleZ", 60.0)) / 90.0
	var eye := pmw + Vector3(0, 0, 128.0 * 0.85)
	var best := {}
	var best_d := INF
	for key in loaded:
		var refs: Node = loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.has_meta("mw_actor") or n.get_meta("mw_disabled", false):
				continue
			var f: Dictionary = combat.fighter_of(n)
			if f.is_empty() or combat.is_dead(f):
				continue
			var tmw := MWCoords.godot_to_mw((n as Node3D).global_position)
			var he := _half_extents(n)
			var dist := tmw.distance_to(pmw) - 29.0 - he.y
			if dist >= best_d or absf(pmw.z - tmw.z) >= reach_units or dist >= reach_units:
				continue
			var to := Vector2(tmw.x - pmw.x, tmw.y - pmw.y).normalized()
			if to.dot(dir_xy) <= 0.0 or absf(to.x * dir_xy.y - to.y * dir_xy.x) > axy:
				continue
			var feet := (tmw - eye).normalized()
			var head := (tmw + Vector3(0, 0, he.z * 2.0) - eye).normalized()
			if vert - head.z > az or vert - feet.z < -az:
				continue
			if not _line_of_sight(cam.global_position, (n as Node3D).global_position + Vector3(0, he.z / upm, 0), n):
				continue
			best_d = dist
			best = f
	return best

## Połowa wymiarów aktora w jednostkach MW (OpenMW: kształt kolizji; tu: NPC – stałe, stworzenie – z modelu).
func _half_extents(n: Node) -> Vector3:
	if String(n.get_meta("mw_actor", "")) == "npc":
		return Vector3(29.0, 29.0, 64.0)
	var aabb := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		return Vector3(32.0, 32.0, 48.0)
	var s := aabb.size * MWCoords.UNITS_PER_METER * 0.5
	return Vector3(s.x, s.z, s.y)

func _line_of_sight(from: Vector3, to: Vector3, target: Node) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var r := MWTravel.ref_of(hit.collider)
	return r == target or (r != null and r.has_meta("mw_actor"))

func _attack_strength() -> float:
	return clampf(_attack_hold / ATTACK_WINDUP_SECONDS, 0.0, 1.0)

## Atak gracza po puszczeniu przycisku: broń biała/wręcz albo strzał (łuk, kusza, broń rzucana).
func player_attack(roll := -1) -> Dictionary:
	var strength := _attack_strength()
	_attack_hold = -1.0
	var att: Dictionary = combat.player_fighter()
	var w: Dictionary = combat.weapon(att)
	var wt := int(w.rec.get("weapon_type", -1)) if not w.is_empty() else -1
	if wt in [9, 10, 11]:
		return _shoot(att, w, wt, strength)
	var mv: Vector2 = player.move_input
	var at := 0
	if absf(mv.y) > absf(mv.x) + 0.2:
		at = 2
	elif absf(mv.x) > absf(mv.y) + 0.2:
		at = 1
	var target := melee_target(combat.reach(att, w))
	if audio != null:
		audio.play("Weapon Swish")
	var r: Dictionary = combat.melee(att, target, at, strength, roll)
	r["target"] = target.get("sid", "")
	return r

## Strzał: łuk/kusza zużywa amunicję z miejsca amunicji, broń rzucana – siebie; pocisk leci prosto z grawitacją
## 0,1 × (ProjectileManager), prędkość fProjectileMin…MaxSpeed (rzucana: fThrownWeaponMin…MaxSpeed) × siła.
func _shoot(att: Dictionary, w: Dictionary, wt: int, strength: float) -> Dictionary:
	var ammo := w
	if wt != 11:
		var a: Dictionary = combat.equipment(att).get(EQ.SLOT_AMMUNITION, {})
		if a.is_empty() or int(a.rec.get("weapon_type", -1)) != (12 if wt == 9 else 13):
			_toast(dialogue.gmst_text("sNotifyMessage60", "Brak amunicji."))
			return {"success": false, "no_ammo": true}
		ammo = a
	interaction.inventory.remove("player", {}, String(ammo.id), 1)
	set_fatigue_after_attack(att, w, strength)
	var mn := float(combat._gmst("fThrownWeaponMinSpeed" if wt == 11 else "fProjectileMinSpeed", 400.0))
	var mx := float(combat._gmst("fThrownWeaponMaxSpeed" if wt == 11 else "fProjectileMaxSpeed", 3000.0))
	var speed := (mn + (mx - mn) * strength) / MWCoords.UNITS_PER_METER
	var cam := player.get_node("Camera3D") as Camera3D
	var nd := Node3D.new()
	nd.name = "Projectile"
	add_child(nd)
	nd.global_position = cam.global_position - cam.global_transform.basis.z * 0.5
	projectiles.append({"node": nd, "vel": -cam.global_transform.basis.z * speed, "att": att, "launcher": w if wt != 11 else {},
		"ammo": ammo, "strength": strength, "life": 10.0})
	return {"success": true, "shot": true}

func set_fatigue_after_attack(att: Dictionary, w: Dictionary, strength: float) -> void:
	combat.set_fatigue(att, combat.fatigue(att) - combat.attack_fatigue(att, w, strength))

func _update_combat(dt: float) -> void:
	if _attack_hold >= 0.0:
		_attack_hold += dt
	if projectiles.is_empty():
		return
	var g := 9.8 * 64.0 * 0.1 / MWCoords.UNITS_PER_METER
	for p in projectiles.duplicate():
		var nd: Node3D = p.node
		var from := nd.global_position
		if not p.has("bolt"):
			p.vel.y -= g * dt
		var to: Vector3 = from + p.vel * dt
		p.life -= dt
		var shooter: Node = p.get("shooter", player)
		var hit_actor := _projectile_actor(from, to, shooter)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [player.get_rid()] if shooter == player else ([(shooter as CollisionObject3D).get_rid()] if shooter is CollisionObject3D else [])
		var wall := player.get_world_3d().direct_space_state.intersect_ray(q)
		if p.has("bolt"):
			if not hit_actor.is_empty() or not wall.is_empty() or p.life <= 0.0:
				explode_bolt(p, wall.get("position", to) if hit_actor.is_empty() else to, hit_actor)
				_end_projectile(p)
			else:
				nd.global_position = to
			continue
		if not hit_actor.is_empty():
			combat.projectile_hit(p.att, hit_actor, p.launcher, p.ammo, float(p.strength))
			_end_projectile(p)
		elif not wall.is_empty() or p.life <= 0.0:
			_end_projectile(p)
		else:
			nd.global_position = to

## Aktor na odcinku lotu pocisku (odległość od osi aktora < połowa szerokości, na wysokości aktora).
func _projectile_actor(a: Vector3, b: Vector3, shooter: Node = null) -> Dictionary:
	if shooter != null and shooter != player and player != null:
		var pc := player.global_position + Vector3(0, 0.9, 0)
		var pp := Geometry3D.get_closest_point_to_segment(pc, a, b)
		if Vector2(pp.x - pc.x, pp.z - pc.z).length() <= 0.4 and absf(pp.y - pc.y) <= 0.95:
			return combat.player_fighter()
	for key in loaded:
		var refs: Node = loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.has_meta("mw_actor") or n.get_meta("mw_disabled", false) or n == shooter:
				continue
			var he := _half_extents(n) / MWCoords.UNITS_PER_METER
			var c := (n as Node3D).global_position + Vector3(0, he.z, 0)
			var p := Geometry3D.get_closest_point_to_segment(c, a, b)
			if Vector2(p.x - c.x, p.z - c.z).length() <= he.x and absf(p.y - c.y) <= he.z:
				var f: Dictionary = combat.fighter_of(n)
				if not f.is_empty() and not combat.is_dead(f):
					return f
	return {}

func _end_projectile(p: Dictionary) -> void:
	projectiles.erase(p)
	if is_instance_valid(p.node):
		p.node.queue_free()

## Aktor zaatakowany przez gracza (MechanicsManager::actorAttacked): odpowiada walką (etap 8c); napaść jako
## przestępstwo – etap 8d (on_assault).
func on_actor_attacked(f: Dictionary) -> void:
	if ai == null or f.get("node") == null or not is_instance_valid(f.node) or combat.is_dead(f):
		return
	if not ai.in_combat(f.node):
		if has_method("on_assault"):
			call("on_assault", f)
		ai.start_combat(f.node, player)

func on_assault(f: Dictionary) -> void:
	if crime != null:
		crime.on_assault(f.node)

## Pakiety AI spoza mw_ai.gd: pościg strażnika (AiPursue – mw_crime.gd).
func ai_package(n: Node, p: Dictionary, dt: float) -> bool:
	if String(p.get("type", "")) == "pursue" and crime != null:
		return crime.pursue(n, p, dt)
	return true

## Pułapka (CastSpell z obiektu na aktywującego): wszystkie efekty czaru na gracza (z odpornością).
func _trap_spell(id: String) -> void:
	var sp: Dictionary = builder.actors.record("spell", id.to_lower())
	if sp.is_empty():
		return
	var me: Dictionary = combat.player_fighter()
	magic.inflict(me, {}, {"id": id, "name": String(sp.get("name", id)), "kind": "spell"},
		sp.get("effects", []), sp)

func player_sneaking() -> bool:
	return player != null and bool(player.get("want_sneak")) and player.is_on_floor()

## Pocisk czaru NPC (cel: gracz albo aktor) – jak launch_bolt, z głowy rzucającego w stronę celu.
func launch_bolt_from(n: Node3D, target: Node3D, caster: Dictionary, list: Array, source: Dictionary, spell := {}) -> void:
	var from := n.global_position + Vector3(0, 1.5, 0)
	var to := target.global_position + Vector3(0, 1.0, 0)
	var mg: Dictionary = magic.effect(int((list[0] as Dictionary).get("effect", -1)))
	var speed := float(combat._gmst("fTargetSpellMaxSpeed", 1000.0)) * float(mg.get("speed", 1.0)) / MWCoords.UNITS_PER_METER
	var nd := MeshInstance3D.new()
	nd.name = "MagicBolt"
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	nd.mesh = sm
	add_child(nd)
	var dir := (to - from).normalized()
	nd.global_position = from + dir * 0.6
	projectiles.append({"node": nd, "vel": dir * speed, "att": caster, "bolt": list, "source": source, "spell": spell,
		"life": 10.0, "shooter": n})

## Strzał NPC z łuku/kuszy/broni rzucanej do celu (bez celowania z wyprzedzeniem; poprawka na grawitację 0,1 ×).
func npc_shoot(n: Node3D, target: Node3D, att: Dictionary) -> void:
	var w: Dictionary = combat.weapon(att)
	if w.is_empty():
		return
	var wt := int(w.rec.get("weapon_type", -1))
	var ammo := w
	if wt != 11:
		ammo = combat.equipment(att).get(EQ.SLOT_AMMUNITION, {})
		if ammo.is_empty():
			return
	interaction.inventory.remove(String(att.sid), att.rec, String(ammo.id), 1)
	var from := n.global_position + Vector3(0, 1.5, 0)
	var to := target.global_position + Vector3(0, 1.2, 0)
	var speed := float(combat._gmst("fThrownWeaponMaxSpeed" if wt == 11 else "fProjectileMaxSpeed", 3000.0)) / MWCoords.UNITS_PER_METER
	var dir := (to - from).normalized()
	var t := from.distance_to(to) / speed
	var g := 9.8 * 64.0 * 0.1 / MWCoords.UNITS_PER_METER
	var vel := dir * speed + Vector3(0, 0.5 * g * t, 0)
	var nd := Node3D.new()
	nd.name = "Projectile"
	add_child(nd)
	nd.global_position = from + dir * 0.6
	projectiles.append({"node": nd, "vel": vel, "att": att, "launcher": w if wt != 11 else {}, "ammo": ammo,
		"strength": 1.0, "life": 10.0, "shooter": n})

## Śmierć: aktor – stan, licznik zabitych (Dead w dialogach, GetDeadCount), OnDeath, ciało do przeszukania;
## gracz – koniec gry (wczytanie zapisu).
func on_actor_died(f: Dictionary, _att: Dictionary) -> void:
	if f.kind == "player":
		_player_died()
		return
	if magic != null:
		magic.soul_trap(f)                 # Pułapka dusz: dusza stworzenia do kamienia gracza
	if crime != null and not _att.is_empty() and _att.get("kind", "") == "player" and f.get("node") != null:
		crime.on_killed(f.node)            # actorKilled: morderstwo (etap 8)
	var a: Dictionary = combat._actor_state(f)
	a["dead"] = true
	a["health"] = 0.0
	var ds: Dictionary = dialogue._ds()
	ds.deaths[f.base] = int(ds.deaths.get(f.base, 0)) + 1
	if scripts != null:
		scripts.died[f.sid] = true
	if f.node != null and is_instance_valid(f.node):
		apply_dead_pose(f.node)

## Ciało: leży (obrót o 90°), bez kolizji kapsuły (animacja śmierci – etap 10).
func apply_dead_pose(n: Node) -> void:
	if n.get_meta("mw_dead", false):
		return
	n.set_meta("mw_dead", true)
	var cap := n.get_node_or_null("Capsule") as CollisionShape3D
	if cap != null:
		cap.disabled = true
	var t := (n as Node3D).transform
	t.basis = t.basis * Basis(Vector3.RIGHT, -PI / 2.0)
	(n as Node3D).transform = t.translated_local(Vector3(0, 0.3, 0))

func _apply_dead_poses() -> void:
	if not state.get("actors") is Dictionary:
		return
	for key in loaded:
		var refs: Node = loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if bool(state.actors.get(String(n.get_meta("mw_sid", "")), {}).get("dead", false)):
				apply_dead_pose(n)

# --- etap 7d: magia gracza -------------------------------------------------------------------------------

var _recharge_acc := 0.0

## Co klatkę: działające czary gracza i aktorów we wczytanych komórkach (śmierć od czarów), ładowanie przedmiotów.
func _update_magic(dt: float) -> void:
	if magic == null or combat == null or player_stats().is_empty():
		return
	magic.tick(combat.player_fighter(), dt)
	for key in loaded:
		var refs: Node = loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.has_meta("mw_actor"):
				continue
			var a = state.actors.get(String(n.get_meta("mw_sid", "")))
			if a is Dictionary and not (a.get("active_spells", []) as Array).is_empty():
				magic.tick(combat.fighter_of(n), dt)
	_recharge_acc += dt
	if _recharge_acc >= 1.0:
		magic.recharge(player_stats(), _recharge_acc)
		_recharge_acc = 0.0

## Upływ czasu (odpoczynek, podróż): czary i ładowanie przedmiotów gracza (Actors::rest, rechargeItems).
func pass_magic_time(seconds: float) -> void:
	if magic == null or player_stats().is_empty():
		return
	var steps := maxi(1, int(ceilf(seconds / 60.0)))
	for i in steps:
		magic.tick(combat.player_fighter(), seconds / steps)
	magic.recharge(player_stats(), seconds)

func fighter_by_sid(sid: String) -> Dictionary:
	if sid == "player":
		return combat.player_fighter()
	for key in loaded:
		var refs: Node = loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				return combat.fighter_of(n)
	return {}

## Przywołanie (Recall): miejsce Znaku (Mark) – wnętrze albo świat zewnętrzny.
func recall_to_mark() -> void:
	var m: Dictionary = state.player.get("mark", {})
	var p: PackedStringArray = String(m.get("pos", "")).split(",")
	if p.size() != 3:
		return
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
	travel_to_cell(String(m.get("interior", "")), pos, rad_to_deg(-player.rotation.y))

## Wybrana magia: {"kind": "spell"|"item", "id"}.
func selected_magic() -> Dictionary:
	var sel = player_stats().get("selected_magic", {})
	return sel if sel is Dictionary else {}

func select_magic(kind: String, id: String) -> void:
	player_stats()["selected_magic"] = {"kind": kind, "id": id.to_lower()}

func selected_magic_name() -> String:
	var sel := selected_magic()
	if sel.is_empty():
		return ""
	if sel.kind == "spell":
		var sp: Dictionary = builder.actors.record("spell", String(sel.id))
		return String(sp.get("name", sel.id))
	var it: Dictionary = interaction.inventory.item(String(sel.id))
	return interaction.item_name(String(it.get("kind", "")), String(sel.id), it.get("rec", {})) if not it.is_empty() else ""

## Rzucenie wybranej magii (lewy przycisk przy gotowej magii): zaklęcie/moc albo przedmiot; dotyk – aktor
## w zasięgu fCombatDistance (getHitContact) albo obiekt (Otwarcie/Zamknięcie); cel – pocisk czaru.
func player_cast(roll := -1) -> Dictionary:
	var sel := selected_magic()
	if sel.is_empty():
		_toast(dialogue.gmst_text("sNoSpellSelected", "Nie wybrano zaklęcia.") if dialogue != null else "Nie wybrano zaklęcia.", 2.0)
		return {"success": false}
	var me: Dictionary = combat.player_fighter()
	var touch := melee_target(float(combat._gmst("fCombatDistance", 128.0)))
	var r: Dictionary
	if sel.kind == "spell":
		if not String(sel.id) in (player_stats().get("spells", []) as Array):
			return {"success": false}
		r = magic.cast_spell(me, String(sel.id), touch, roll)
	else:
		if interaction.inventory.count_of("player", {}, String(sel.id)) <= 0:
			player_stats().erase("selected_magic")
			return {"success": false}
		r = magic.use_item(me, String(sel.id), touch)
	if not String(r.get("message", "")).is_empty():
		_toast(String(r.message), 2.0)
	if not bool(r.get("success", false)):
		return r
	if audio != null:
		audio.play("%s cast" % _school_name(int(r.get("school", 11))))
	if touch.is_empty():
		_touch_object(r)
	if not (r.get("bolt", []) as Array).is_empty():
		launch_bolt(me, r.bolt, r.source, r.get("spell", {}))
	return r

static func _school_name(skill: int) -> String:
	return {11: "alteration", 13: "conjuration", 10: "destruction", 12: "illusion", 14: "mysticism", 15: "restoration"}.get(skill, "alteration")

## Dotyk obiektu (World::castSpell – promień do odległości aktywacji): Otwarcie/Zamknięcie zamków.
func _touch_object(r: Dictionary) -> void:
	var src: Dictionary = r.get("spell", {})
	var list: Array = src.get("effects", []) if not src.is_empty() else []
	if src.is_empty():
		var it: Dictionary = interaction.inventory.item(String(r.get("source", {}).get("id", "")))
		list = magic.item_enchantment(it).get("effects", []) if not it.is_empty() else []
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	var node := MWTravel.pick(cam)
	if node == null or node.has_meta("mw_actor"):
		return
	for e in magic.by_range(list, magic.RT_TOUCH):
		_lock_effect(node, e)

func _lock_effect(node: Node, e: Dictionary) -> void:
	var id := int(e.get("effect", -1))
	if id != magic.FX_OPEN and id != magic.FX_LOCK:
		return
	var sid: String = interaction.sid_of(node)
	var lvl: int = interaction.lock_level(node)
	var mag := int(magic._roll_magnitude({"min": float(e.get("min", 0)), "max": float(e.get("max", 0))}))
	if id == magic.FX_OPEN:
		if lvl > 0 and lvl <= mag:
			state.set_lock(sid, 0)
			_toast(dialogue.gmst_text("sMagicOpenSuccess", "Zamek otwarty."), 2.0)
			if audio != null:
				audio.play("Open Lock")
		elif lvl > 0 and audio != null:
			audio.play("Open Lock Fail")
	elif lvl < mag and String(interaction.kind_of(node)) in ["door", "container"]:
		state.set_lock(sid, mag)
		_toast(dialogue.gmst_text("sMagicLockSuccess", "Zamek zamknięty."), 2.0)

## Pocisk czaru (ProjectileManager::launchMagicBolt): prędkość fTargetSpellMaxSpeed × szybkość efektu, bez grawitacji.
func launch_bolt(caster: Dictionary, list: Array, source: Dictionary, spell := {}) -> void:
	var cam := player.get_node("Camera3D") as Camera3D
	var mg: Dictionary = magic.effect(int((list[0] as Dictionary).get("effect", -1)))
	var speed := float(combat._gmst("fTargetSpellMaxSpeed", 1000.0)) * float(mg.get("speed", 1.0)) / MWCoords.UNITS_PER_METER
	var nd := MeshInstance3D.new()
	nd.name = "MagicBolt"
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	nd.mesh = sm
	var mat := StandardMaterial3D.new()
	var col: Array = mg.get("color", [255, 128, 64])
	mat.albedo_color = Color8(int(col[0]), int(col[1]), int(col[2]))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nd.material_override = mat
	add_child(nd)
	nd.global_position = cam.global_position - cam.global_transform.basis.z * 0.6
	projectiles.append({"node": nd, "vel": -cam.global_transform.basis.z * speed, "att": caster, "bolt": list,
		"source": source, "spell": spell, "life": 10.0})

## Wybuch czaru (explodeSpell): efekty z obszarem na aktorów w promieniu obszar × 22 jednostki (stopy).
func explode_bolt(p: Dictionary, at: Vector3, hit: Dictionary) -> void:
	var direct := []
	for e in p.bolt:
		if int(e.get("area", 0)) <= 0:
			direct.append(e)
	if not hit.is_empty() and not direct.is_empty():
		magic.bolt_hit(p.att, hit, p.source, direct, p.spell)
	for e in p.bolt:
		var area := int(e.get("area", 0))
		if area <= 0:
			continue
		var radius := area * 22.0 / MWCoords.UNITS_PER_METER
		var targets := []
		if player.global_position.distance_to(at) <= radius:
			targets.append(combat.player_fighter())
		for key in loaded:
			var refs: Node = loaded[key].get_node_or_null("Refs")
			if refs == null:
				continue
			for n in refs.get_children():
				if n.has_meta("mw_actor") and not n.get_meta("mw_disabled", false) and (n as Node3D).global_position.distance_to(at) <= radius:
					targets.append(combat.fighter_of(n))
		for t in targets:
			if not t.is_empty():
				magic.bolt_hit(p.att, t, p.source, [e], p.spell)
	if audio != null:
		audio.play("%s hit" % _school_name(int(magic.school_skill(int((p.bolt[0] as Dictionary).get("effect", -1))))))

var death_screen: CanvasLayer = null

func _player_died() -> void:
	player_stats()["health"] = 0.0
	if death_screen != null and is_instance_valid(death_screen):
		return
	death_screen = CanvasLayer.new()
	death_screen.layer = 40
	death_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var l := Label.new()
	l.text = "Nie żyjesz."
	box.add_child(l)
	if FileAccess.file_exists(quicksave_path()):
		var b := Button.new()
		b.text = "Wczytaj szybki zapis"
		b.pressed.connect(func():
			death_screen.queue_free()
			death_screen = null
			get_tree().paused = false
			load_game(quicksave_path()))
		box.add_child(b)
	var q := Button.new()
	q.text = "Zakończ grę"
	q.pressed.connect(func(): get_tree().quit(0))
	box.add_child(q)
	death_screen.add_child(panel)
	add_child(death_screen)
	panel.position = (get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func _load_settings(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## Ustawienia z launchera (plik --settings): tylko opcje obsługiwane przez Runtime.
func _apply_settings() -> void:
	if settings.is_empty():
		return
	var mode := String(settings.get("window_mode", "windowed"))
	if DisplayServer.get_name() != "headless":
		match mode:
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"exclusive":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var r := String(settings.get("resolution", "1280x720")).split("x")
				if r.size() == 2:
					var want := Vector2i(int(r[0]), int(r[1]))
					var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
					DisplayServer.window_set_size(want)
					if scr.size.x > 0:   # wyśrodkuj na bieżącym ekranie (okno 3440x1440 na całą szerokość)
						DisplayServer.window_set_position(scr.position + (scr.size - want).max(Vector2i.ZERO) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.get("max_fps", 0))
	get_viewport().scaling_3d_scale = float(settings.get("scale_3d", 1.0))
	var sh := String(settings.get("shadows", "medium"))
	envr.sun.shadow_enabled = sh != "off"
	RenderingServer.directional_shadow_atlas_set_size({"low": 1024, "medium": 2048, "high": 4096}.get(sh, 2048), true)
	envr.env.fog_enabled = bool(settings.get("fog", true))
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.far = float(settings.get("view_distance", 1500))

func _start_position() -> Vector3:
	return _start_transform().origin

## Miejsce startu. Kolejność: --pos (jednostki MW) → nazwane miejsce (--start, ustawienie „start_location”,
## potem Balmora i Seyda Neen) → środek pierwszej komórki zewnętrznej.
## Nazwane miejsce: punkt wyjścia z budynku tego miasta (cel drzwi wnętrza „<miasto>, …” prowadzących na
## zewnątrz) najbliższy środka komórek miasta – ulica przed drzwiami, nie dach ani rzeka.
func _start_transform() -> Transform3D:
	var p := arg("pos")
	if not p.is_empty():
		var v := p.split(",")
		return Transform3D(Basis(), MWCoords.mw_to_godot(Vector3(float(v[0]), float(v[1]), float(v[2]))))
	if interior.is_empty():
		for name in [arg("start"), String(settings.get("start_location", "")), "Balmora", "Seyda Neen"]:
			if name.is_empty():
				continue
			var t = _named_start(name)
			if t != null:
				start_name = name
				return t
	# środek pierwszej komórki zewnętrznej z indeksu, nad terenem
	for c in db.cell_index():
		if not c.get("interior", false) and interior.is_empty():
			var g: Array = c["grid"]
			var mw := Vector3((g[0] + 0.5) * MWCoords.CELL_SIZE, (g[1] + 0.5) * MWCoords.CELL_SIZE, 0)
			var pos := MWCoords.mw_to_godot(mw)
			var cell := db.get_cell(c["key"])
			if cell.get("terrain") != null:
				var t := db.get_terrain(cell["terrain"])
				var o: Array = t["origin_godot"]
				pos.y = MWTerrain.height_at(t, pos - Vector3(o[0], o[1], o[2])) + 2.0
			return Transform3D(Basis(), pos)
	return Transform3D(Basis(), Vector3(0, 2, 0))

var start_name := ""

func _named_start(name: String) -> Variant:
	var lname := name.to_lower()
	var centre := Vector3.ZERO
	var n_ext := 0
	for c in db.cell_index():
		if not c.get("interior", false) and String(c.get("name", "")).to_lower() == lname:
			var g: Array = c["grid"]
			centre += MWCoords.mw_to_godot(Vector3((g[0] + 0.5) * MWCoords.CELL_SIZE, (g[1] + 0.5) * MWCoords.CELL_SIZE, 0))
			n_ext += 1
	# punkty wyjścia z budynków miasta (cele drzwi wnętrz „<miasto>, …” prowadzących na zewnątrz)
	var exits: Array[Transform3D] = []
	for c in db.cell_index():
		if not c.get("interior", false) or not String(c.get("name", "")).to_lower().begins_with(lname + ","):
			continue
		for r in db.get_cell(c["key"]).get("refs", []):
			var ex: Dictionary = r.get("extra", {})
			if not ex.has("door_dest") or not String(ex.get("door_dest_cell", "")).is_empty():
				continue  # tylko drzwi prowadzące na zewnątrz
			var g: Dictionary = ex["door_dest"].get("godot", {})
			var o: Array = g.get("origin", [0, 0, 0])
			var q: Array = g.get("quat", [0, 0, 0, 1])
			var pos := Vector3(o[0], o[1], o[2])
			if db.find_cell(db.exterior_key(MWCoords.cell_of(pos))).is_empty():
				continue  # komórka poza przekonwertowanym zakresem
			exits.append(Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), pos + Vector3(0, 0.1, 0)))
	if n_ext > 0:
		centre /= n_ext
	elif not exits.is_empty():
		for t in exits:
			centre += t.origin
		centre /= exits.size()
	else:
		return null
	if not exits.is_empty():
		var best: Transform3D = exits[0]
		var best_d := INF
		for t in exits:
			var d := Vector2(t.origin.x - centre.x, t.origin.z - centre.z).length()
			if d < best_d:
				best_d = d
				best = t
		return best
	# brak wnętrz: środek komórek miasta, nad terenem (może wypaść na dachu – lepsze niż góry obok)
	var cell := db.get_cell(db.exterior_key(MWCoords.cell_of(centre)))
	if cell.is_empty() or cell.get("terrain") == null:
		return null
	var tr := db.get_terrain(cell["terrain"])
	var to: Array = tr["origin_godot"]
	centre.y = MWTerrain.height_at(tr, centre - Vector3(to[0], to[1], to[2])) + 2.0
	return Transform3D(Basis(), centre)

func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	hud = RichTextLabel.new()      # BBCode: formatowanie z tłumaczeń ([c] [b] [i]) i znacznik QA
	hud.bbcode_enabled = true
	hud.fit_content = true
	hud.scroll_active = false
	hud.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.position = Vector2(12, 8)
	hud.size = Vector2(1600, 120)
	cl.add_child(hud)
	add_child(cl)

var _frames := 0

## Tryb zrzutu (porównania z OpenMW, np. ujęcia MCP-openMW openmw_capture_plan):
##   --camera=x,y,z   pozycja kamery (jednostki MW)      --look=yaw,pitch  radiany jak w OpenMW
##                    (yaw 0 = północ/+Y, zgodnie z ruchem wskazówek; pitch > 0 = w dół)
##   --hour=12  --weather=clear  --fov=60 (pionowe, jak OpenMW)  --screenshot=PLIK.png  --shot-frames=120
##   --save=PLIK.mwsave (zapis gry w chwili zrzutu)   --load=PLIK.mwsave (także poza trybem zrzutu: wczytanie przy starcie)
## Kamera stoi w miejscu (latanie), czas zatrzymany, pasek ukryty; po zrzucie gra kończy się (--quit=0: zostaje).
func _apply_capture() -> void:
	var c := arg("camera")
	if not c.is_empty():
		var v := c.split(",")
		player.fly = true
		player.global_position = MWCoords.mw_to_godot(Vector3(float(v[0]), float(v[1]), float(v[2]))) - Vector3(0, 1.65, 0)
		player.velocity = Vector3.ZERO
	var look := arg("look")
	if not look.is_empty():
		var l := look.split(",")
		player.rotation.y = -float(l[0])
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam and l.size() > 1:
			cam.rotation.x = -float(l[1])
	var fov := arg("fov")
	if not fov.is_empty():
		var cam2 := player.get_node_or_null("Camera3D") as Camera3D
		if cam2:
			cam2.fov = float(fov)
	var hour := arg("hour")
	if not hour.is_empty():
		envr.time_running = false
		envr.game_hour = float(hour)
		envr.apply()
	var w := arg("weather").to_lower()
	if not w.is_empty():
		envr.forced_weather = w
		envr.pick_weather()
	if not arg("screenshot").is_empty() and hud:
		hud.visible = false

func _capture_tick() -> void:
	var shot := arg("screenshot")
	if shot.is_empty() or _frames != int(arg("shot-frames", "120")):
		return
	if player and player.fly:
		player.velocity = Vector3.ZERO
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
	var err := img.save_png(shot)
	print("MWGODOT_SHOT ", shot, " ", img.get_width(), "x", img.get_height(), " err=", err,
		" flora=", JSON.stringify(builder.flora.stats if builder.flora else {}))
	var sp := arg("save")
	if not sp.is_empty():
		print("MWGODOT_SAVED ", sp, " ", save_game(sp))
	if arg("quit", "1") != "0":
		get_tree().quit(0 if err == OK else 4)

var _last_pos := Vector3.ZERO
func _process(_d: float) -> void:
	_frames += 1
	if player != null and audio != null:
		var moved: float = Vector2(player.global_position.x - _last_pos.x, player.global_position.z - _last_pos.z).length()
		_last_pos = player.global_position
		if moved < 2.0 and not player.fly:
			audio.footsteps(player, moved, player.is_on_floor(), player.swimming)
	_update_torches(_d)
	_update_water_level()
	if not get_tree().paused:
		_update_player_rpg(_d)
		_update_combat(_d)
		_update_magic(_d)
		if ai != null and arg("screenshot").is_empty():
			ai.tick(_d)
			if ai.enabled:
				crime.tick(_d)
	if scripts != null and player != null and not get_tree().paused and arg("scripts", "1") != "0":
		scripts.tick(_d, script_host.scripted_refs())
	_capture_tick()
	var autotest := int(arg("autotest-frames", "0"))
	if autotest > 0 and _frames == autotest:
		# tryb testu integracyjnego (launcher): raport i wyjście z kodem zależnym od błędów ładowania
		var st := {"cells": loaded.size(), "models": models.stats if models else {}, "data": db.data_root if db else "",
			"base_roots": MWModelCache.base_roots, "settings_profile": settings.get("profile", ""),
			"max_fps": Engine.max_fps, "flora": builder.flora.stats if builder.flora else {}}
		print("MWGODOT_STATS ", JSON.stringify(st))
		get_tree().quit(0 if models and models.stats.failed == 0 and loaded.size() > 0 else 3)
	if player == null:
		return
	if interior.is_empty():
		_update_streaming(false)
		var g := MWCoords.cell_of(player.global_position)
		var c := db.get_cell(db.exterior_key(g))
		var reg := String(c.get("region", ""))
		if reg != current_region:
			current_region = reg
			envr.set_region(reg)
			var wo: Dictionary = state.player.get("weather_override", {})
			if wo.has(reg.to_lower()):                  # ChangeWeather ze skryptu ma pierwszeństwo przed losowaniem
				envr.weather = String(wo[reg.to_lower()])
				envr.apply()
	var hint := ""
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		for ch in player.get_children():
			if ch is Camera3D:
				cam = ch
	if cam:
		var r := MWTravel.pick(cam)
		# podpowiedź tylko dla tego, co klawisz E faktycznie obsługuje (drzwi, przedmioty, pojemniki)
		var h: String = interaction.hint(r) if r and interaction != null else ""
		if h.is_empty() and r and dialogue != null and dialogue.is_actor_node(r) and dialogue.available():
			h = "Rozmawiaj: " + dialogue.actor_name(dialogue.make_actor(r))
		if not h.is_empty():
			hint = "\n[lb]E] %s" % Loc.escape_bbcode(h)
	var stats_line := ""
	var pst := player_stats()
	if not pst.is_empty() and character != null:
		var dd: Dictionary = character.derived(pst)
		stats_line = "\n%s  |  zdrowie %d/%d  |  magia %d/%d  |  kondycja %d/%d" % [Loc.escape_bbcode(String(pst.get("name", ""))),
				roundi(float(pst.get("health", 0))), roundi(dd.health.modified), roundi(float(pst.get("magicka", 0))),
				roundi(dd.magicka.modified), roundi(float(pst.get("fatigue", 0))), roundi(dd.fatigue.modified)]
		var sm := selected_magic_name()
		if not sm.is_empty():
			stats_line += "  |  %s: %s" % ["magia gotowa" if magic_ready else "[lb]R] magia", Loc.escape_bbcode(sm)]
		elif weapon_drawn:
			stats_line += "  |  broń dobyta"
	var rname := display_location()
	hud.text = "%s  |  dzień %d, %02d:%02d  |  %s%s%s" % [rname, envr.day + 1, int(envr.game_hour), int(fmod(envr.game_hour, 1.0) * 60), envr.weather, coords_text() + stats_line, hint]

## Widok z ostatniej sesji – zapisywany lokalnie (katalog zapisów profilu), launcher pokazuje go na ekranie głównym.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		write_scripts_report()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and DisplayServer.get_name() != "headless":
		var saves := arg("saves")
		if not saves.is_empty() and player != null:
			var img := get_viewport().get_texture().get_image()
			if img:
				DirAccess.make_dir_recursive_absolute(saves)
				img.resize(640, int(640.0 * img.get_height() / max(1, img.get_width())), Image.INTERPOLATE_BILINEAR)
				img.save_png(saves.path_join("last_view.png"))

## Nazwa miejsca w pasku: wnętrze (CELL|nazwa|NAME) albo region (REGN|id|FNAM) – przetłumaczona, jeśli jest.
func display_location() -> String:
	if not interior.is_empty():
		return Loc.escape_bbcode(loc.plain(Loc.key("CELL", interior, "NAME"), interior))
	var reg := current_region.to_lower()
	var name := String(envr.regions.get(reg, {}).get("name", current_region))
	return Loc.escape_bbcode(loc.plain(Loc.key("REGN", reg, "FNAM"), name))

## Współrzędne do testów (F3 – pokaż/ukryj, F4 – kopiuj do schowka i zapisz w logu).
## Pozycja w jednostkach Morrowinda (jak w Construction Set i konsoli gry); „--pos=x,y,z” uruchamia grę w tym miejscu.
var show_coords := true

func position_string() -> String:
	if player == null:
		return ""
	var mw := MWCoords.godot_to_mw(player.global_position)
	return "%d,%d,%d" % [roundi(mw.x), roundi(mw.y), roundi(mw.z)]

func coords_text() -> String:
	if not show_coords or player == null:
		return ""
	var cell := ""
	if interior.is_empty():
		var g := MWCoords.cell_of(player.global_position)
		cell = "komórka %d,%d" % [g.x, g.y]
	else:
		cell = "wnętrze „%s”" % interior
	var yaw := fposmod(-rad_to_deg(player.rotation.y), 360.0)
	return "\n%s  |  pozycja %s  |  kierunek %d°  [lb]F3 ukryj, F4 kopiuj]" % [Loc.escape_bbcode(cell), position_string(), roundi(yaw)]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("quick_save"):
		var r := save_game(quicksave_path())
		_toast("Zapisano grę (szybki zapis)" if r.is_empty() else "Błąd zapisu: " + r)
	elif e.is_action_pressed("quick_load"):
		var w = load_game(quicksave_path())
		_toast(("Wczytano grę" + ("" if w.is_empty() else ":\n" + "\n".join(w))) if not (w.size() == 1 and String(w[0]).begins_with("BŁĄD")) else String(w[0]))
	elif e.is_action_pressed("toggle_coords"):
		show_coords = not show_coords
	elif e.is_action_pressed("copy_position") and player:
		var line := "--pos=%s" % position_string()
		if not interior.is_empty():
			line = "--cell=\"%s\" %s" % [interior, line]
		DisplayServer.clipboard_set(line)
		print("MWGODOT_POS ", line)
		_toast("Skopiowano do schowka: " + line)
	if e.is_action_pressed("ready_weapon") and player and control_allowed("fighting"):
		weapon_drawn = not weapon_drawn
		if weapon_drawn:
			magic_ready = false
		_toast("Broń dobyta" if weapon_drawn else "Broń schowana", 1.0)
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ready_magic") and player and control_allowed("magic"):
		magic_ready = not magic_ready
		if magic_ready:
			weapon_drawn = false
		_toast(("Magia gotowa: " + selected_magic_name()) if magic_ready else "Magia schowana", 1.5)
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("magic_menu") and player and magic_window != null and not magic_window.visible and menu_allowed("magic"):
		magic_window.open_spells()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("attack") and player and magic_ready and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player_cast()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("attack") and player and weapon_drawn and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_attack_hold = 0.0
		get_viewport().set_input_as_handled()
		return
	if e.is_action_released("attack") and _attack_hold >= 0.0:
		player_attack()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("rest") and player and rest_window != null and not rest_window.visible and menu_allowed("rest"):
		rest_window.open()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("inventory") and player and item_window != null and not item_window.visible and menu_allowed("inventory"):
		item_window.open_inventory()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("activate") and player:
		for ch in player.get_children():
			if ch is Camera3D:
				var r := MWTravel.pick(ch)
				if r:
					activate(r)

## Aktywacja referencji (etap 3): drzwi (zamki, pułapki, podróż), przedmioty (podnoszenie), pojemniki (okno).
func activate(r: Node, force_default := false) -> bool:
	events.activated.emit(String(r.get_meta("mw_sid", "")), String(r.get_meta("mw_base", "")), "player")
	# skrypt z OnActivate przejmuje aktywację (domyślna akcja tylko po „Activate” w skrypcie) – jak w Morrowindzie
	var scr := String(db.get_object(String(r.get_meta("mw_base", ""))).get("script", ""))
	if not force_default and scripts != null and not scr.is_empty() and scripts.uses(scr, "onactivate"):
		scripts.activated[String(r.get_meta("mw_sid", ""))] = true
		return true
	if dialogue != null and dialogue.is_actor_node(r):
		if combat != null and combat.is_dead(combat.fighter_of(r)):
			var f: Dictionary = combat.fighter_of(r)           # martwy aktor – przeszukanie (jak pojemnik)
			item_window.open_container(f.sid, f.rec, dialogue.actor_name(dialogue.make_actor(r)))
			return true
		open_dialogue(r)                  # ActionTalk (NPC, stworzenia); bez powitania okno się nie otwiera
		return true
	var at: Vector3 = (r as Node3D).global_position
	var snap: Dictionary = interaction.snapshot(r)
	# wytrych/sonda w ręce: próba na zamku/pułapce zamiast aktywacji (Security)
	var tool: Dictionary = _equipment().get(str(EQ.SLOT_CARRIED_RIGHT), {})
	var tool_it: Dictionary = interaction.inventory.item(String(tool.get("id", ""))) if not tool.is_empty() else {}
	if not tool_it.is_empty() and crime != null and snap.kind in ["door", "container"]:
		var use := ""
		if tool_it.kind == "probe" and not String(snap.trap).is_empty():
			use = "probe"
		elif tool_it.kind == "lockpick" and int(snap.lock) > 0:
			use = "lockpick"
		if not use.is_empty():
			var sr: Dictionary = crime.use_tool(r, String(tool.id), use)
			if not String(sr.get("message", "")).is_empty():
				_toast(String(sr.message))
			if audio != null and not String(sr.get("sound", "")).is_empty():
				audio.play(String(sr.sound), at)
			return true
	var res: Dictionary = interaction.activate(r)
	if not String(snap.trap).is_empty() and String(interaction.trap(r)).is_empty() and magic != null:
		_trap_spell(String(snap.trap))           # pułapka: czar na gracza (etap 7/8)
	if not String(res.get("message", "")).is_empty():
		_toast(String(res["message"]))
	if audio != null and not String(res.get("sound", "")).is_empty():
		audio.play(String(res["sound"]), null if res.get("action") == "take" else at)
	match String(res.get("action", "")):
		"travel":
			travel(res["dest"])
		"open_container":
			item_window.open_container(String(res["sid"]), interaction.container_record(String(res["base"])),
					String(res.get("name", "")))
		"take", "locked":
			pass
		_:
			return false
	return true

## Rozmowa (etap 6): okno dialogu, jeśli rozmówca ma powitanie.
func open_dialogue(node: Node) -> bool:
	if dialogue_window == null or dialogue_window.visible or not dialogue.available():
		return false
	return dialogue_window.open(node)

func on_dialogue_closed() -> void:
	if script_host != null:
		script_host.dirty = true

## Odłożenie przedmiotu z ekwipunku przed graczem (na ziemi pod punktem 0,8 m przed nim).
func drop_item(id: String, count: int) -> String:
	if player == null:
		return ""
	var fwd := -player.global_transform.basis.z
	fwd.y = 0
	var at := player.global_position + fwd.normalized() * 0.8 + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(at, at - Vector3(0, 6, 0))
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var ground: Vector3 = hit["position"] if not hit.is_empty() else player.global_position
	var key := ("int:" + interior.to_lower()) if not interior.is_empty() else db.exterior_key(MWCoords.cell_of(ground))
	var sid: String = interaction.drop(id, count, key, MWCoords.godot_to_mw(ground), -player.rotation.y)
	return sid

func travel(dest: Dictionary) -> void:
	if scripts != null:
		scripts.cell_changed = true
	if ai != null:
		ai.store_positions()
	if interior.is_empty() and player != null:          # ostatnia pozycja zewnętrzna (najbliższy znacznik – więzienie)
		var lp := MWCoords.godot_to_mw(player.global_position)
		state.player["last_exterior"] = [lp.x, lp.y, lp.z]
	for key in loaded.keys():
		events.cell_unloaded.emit(key)
		loaded[key].queue_free()
	loaded.clear()
	var t: Transform3D = dest["transform"]
	if String(dest.get("cell_key", "")) != "":
		interior = String(dest["cell_name"])
		_load(dest["cell_key"])
		envr.set_interior(db.get_cell(dest["cell_key"]))
	else:
		interior = ""
		envr.set_interior({})
		player.global_position = t.origin
		_update_streaming(true)
	player.global_position = t.origin
	player.rotation.y = t.basis.get_euler().y
	player.velocity = Vector3.ZERO

func _update_streaming(_force: bool) -> void:
	var g := MWCoords.cell_of(player.global_position)
	var want := {}
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var key := db.exterior_key(g + Vector2i(dx, dy))
			if not db.find_cell(key).is_empty():
				want[key] = true
	for key in want:
		if not loaded.has(key):
			_load(key)
	for key in loaded.keys():
		if not want.has(key):
			if ai != null:
				ai.store_positions(key)
			events.cell_unloaded.emit(key)
			loaded[key].queue_free()
			loaded.erase(key)

func _load(key: String) -> void:
	if script_host != null:
		script_host.dirty = true
	if builder.actors != null:
		builder.actors.torches = use_torches(key)
	var n := builder.build_cell(key)
	if n:
		add_child(n)
		loaded[key] = n
		if not arg("screenshot").is_empty():
			# ujęcia porównawcze: aktorzy zamrożeni w pozycjach z danych – jak MCP zamraża aktorów w OpenMW
			for a in n.get_node("Refs").get_children():
				if a.has_meta("mw_actor"):
					a.set_physics_process(false)
		events.cell_loaded.emit(key)
		_apply_dead_poses()

## Poziom wody dla gracza (pływanie): komórka zewnętrzna albo wnętrze z wodą (water_height_m z konwertera).
func _update_water_level() -> void:
	if player == null or db == null:
		return
	var key := ("int:" + interior.to_lower()) if not interior.is_empty() else db.exterior_key(MWCoords.cell_of(player.global_position))
	var c := db.get_cell(key)
	player.water_level = float(c.get("water_height_m", 0.0)) if c.get("has_water", false) else -INF

## World::useTorches: na zewnątrz po zmroku (przed 6:00 i po 20:00 – wschód 6, zachód 18 + 2 h zmierzchu) i bez
## opadów (pogody z „Using Precip”: deszcz, burza, śnieg, zamieć); we wnętrzach – gdy suma składowych światła
## otoczenia ≤ 201 i spanie nie jest zabronione.
func use_torches(key := "") -> bool:
	var k := key if not key.is_empty() else ("" if interior.is_empty() else "int:" + interior.to_lower())
	if k.begins_with("int:"):
		var c := db.get_cell(k)
		if c.get("behave_like_exterior", false):
			pass
		else:
			var amb: Array = (c.get("ambient", {}) as Dictionary).get("ambient_rgb", [255, 255, 255])
			return (int(c.get("flags", 0)) & 0x04) == 0 and int(amb[0]) + int(amb[1]) + int(amb[2]) <= 201
	var h := float(envr.game_hour)
	return (h < 6.0 or h > 20.0) and not String(envr.weather) in ["rain", "thunder", "snow", "blizzard"]

## Co sekundę (jak Actors::update): zmiana pory/pogody → NPC biorą albo odkładają pochodnie.
var _torch_timer := 0.0
func _update_torches(delta: float) -> void:
	_torch_timer += delta
	if _torch_timer < 1.0 or builder == null or builder.actors == null:
		return
	_torch_timer = 0.0
	var t := use_torches()
	if t == builder.actors.torches:
		return
	builder.actors.torches = t
	for key in loaded:
		var refs_node: Node = loaded[key].get_node_or_null("Refs")
		if refs_node == null:
			continue
		for n in refs_node.get_children():
			if n.get_meta("mw_actor", "") == "npc":
				_on_ref_changed(String(n.get_meta("mw_sid", "")))

func _toast(text: String, seconds := 3.0) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(12, 90)
	var cl := CanvasLayer.new()
	cl.add_child(l)
	add_child(cl)
	get_tree().create_timer(seconds).timeout.connect(cl.queue_free)

func _add_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(20, 20)
	var cl := CanvasLayer.new()
	cl.add_child(l)
	add_child(cl)


# --- stan gry: zapis i odczyt (etap 0) ---------------------------------------------------------------

func saves_dir() -> String:
	var s := arg("saves")
	return s if not s.is_empty() else ProjectSettings.globalize_path("user://saves")

func quicksave_path() -> String:
	return saves_dir().path_join("quicksave.mwsave")

## Nagłówek zapisu: profil, lista treści z manifestu konwersji (wtyczki + SHA-256, kolejność ładowania),
## odcisk danych bazowych – do wykrywania niezgodności przy odczycie.
func save_header() -> Dictionary:
	var content := []
	var man = MWWorldDB._read_json(db.data_root.path_join("world/manifest.json"))
	if man is Dictionary:
		for c in man.get("content", []):
			content.append({"name": c.get("name", ""), "sha256": c.get("sha256", "")})
	return {"profile": arg("profile", "default"), "character": "", "content": content,
		"base_fingerprint": JSON.stringify(content).sha256_text(), "world_format": 1,
		"created": Time.get_datetime_string_from_system(), "game": "OpenMWGodot"}

func capture_state() -> void:
	if ai != null:
		ai.store_positions()
	state.time = {"day": envr.day, "hour": envr.game_hour}
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	var p := MWCoords.godot_to_mw(player.global_position)
	var keep: Dictionary = state.player.duplicate()      # np. poziom gracza (etap 4)
	keep.merge({"interior": interior, "fly": player.fly,
		"mw": {"pos": [p.x, p.y, p.z], "rot": [-(cam.rotation.x if cam else 0.0), 0.0, -player.rotation.y]}}, true)
	state.player = keep

## Zwraca "" albo opis błędu.
func save_game(path: String) -> String:
	if player == null:
		return "gra nie jest uruchomiona"
	capture_state()
	var err := GameStateScript.write_file(path, state.to_dict(save_header()))
	if err != OK:
		return "kod %d" % err
	print("MWGODOT_SAVE ", path)
	write_scripts_report()
	events.game_saved.emit(path)
	return ""

## Zwraca listę ostrzeżeń (pusta = zgodny); błąd jako jedyny element "BŁĄD: …". Oryginalny plik zostaje.
func load_game(path: String) -> Array:
	var raw := GameStateScript.read_file(path)
	if raw.has("error"):
		return ["BŁĄD: " + String(raw["error"])]
	var old_version := int(raw.get("version", 0))
	var m := GameStateScript.migrate(raw)
	if m.has("error"):
		return ["BŁĄD: " + String(m["error"])]
	if m.get("migrated", false):
		GameStateScript.backup_before_migration(path, old_version)
	var d: Dictionary = m["data"]
	var warnings := GameStateScript.compatibility(d.get("header", {}), save_header())
	warnings.append_array(state.from_dict(d))
	_apply_state()
	print("MWGODOT_LOAD ", path, " ostrzeżenia=", warnings.size())
	events.game_loaded.emit(path, warnings)
	return warnings

func _apply_state() -> void:
	builder.actors.dynamic = state.created         # rekordy utworzone w grze (etap 7d) – nowy słownik po wczytaniu
	db.created = state.created
	if character != null and (state.player.get("character", {}) as Dictionary).is_empty():
		state.player["character"] = character.build(default_choice())     # zapis sprzed etapu 4
	envr.day = int(state.time.get("day", 0))
	envr.game_hour = float(state.time.get("hour", 9.0))
	envr.apply()
	var pl: Dictionary = state.player
	var mw: Dictionary = pl.get("mw", {})
	var pos: Array = mw.get("pos", [])
	var rot: Array = mw.get("rot", [0, 0, 0])
	for key in loaded.keys():
		events.cell_unloaded.emit(key)
		loaded[key].free()
	loaded.clear()
	var inter := String(pl.get("interior", ""))
	interior = inter
	if pos.size() == 3:
		player.global_position = MWCoords.mw_to_godot(Vector3(pos[0], pos[1], pos[2]))
	player.rotation.y = -float(rot[2])
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.rotation.x = -float(rot[0])
	player.fly = bool(pl.get("fly", false))
	player.velocity = Vector3.ZERO
	if not inter.is_empty():
		var key := "int:" + inter.to_lower()
		_load(key)
		envr.set_interior(db.get_cell(key))
	else:
		envr.set_interior({})
		_update_streaming(true)

## Zmiana referencji w GameState → przebudowa tylko jej węzła w wczytanych komórkach.
func _on_ref_changed(sid: String) -> void:
	if script_host != null:
		script_host.dirty = true
	for key in loaded:
		var refs_node: Node = loaded[key].get_node_or_null("Refs")
		if refs_node == null:
			continue
		for n in refs_node.get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				for r in db.get_cell(key).get("refs", []):
					if String(r.get("sid", "")) == sid:
						var nn := builder.build_ref(state.apply_to_ref(r))
						refs_node.add_child(nn)
						refs_node.move_child(nn, n.get_index())
						n.free()
						_apply_dead_poses()
						return

## Raport skryptów (nieobsługiwane i częściowe funkcje, błędy) – w katalogu zapisów, dla MCP i diagnostyki.
func write_scripts_report() -> void:
	if scripts == null:
		return
	var path := saves_dir().path_join("scripts_report.json")
	DirAccess.make_dir_recursive_absolute(saves_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(scripts.report(), " "))
		f.close()
		DirAccess.rename_absolute(path + ".tmp", path)

## Referencja z danych bazowych (wczytane komórki) – pozycja startowa dla skryptów.
func base_ref(sid: String) -> Dictionary:
	for key in loaded:
		for r in db.get_cell(key).get("refs", []):
			if String(r.get("sid", "")) == sid:
				return r
	return {}

## PositionCell: przejście do wnętrza (albo świata zewnętrznego) i ustawienie gracza.
func travel_to_cell(cell: String, mw_pos: Vector3, rot_z_deg: float) -> void:
	var key := "int:" + cell.to_lower()
	var t := Transform3D(Basis(Vector3.UP, -deg_to_rad(rot_z_deg)), MWCoords.mw_to_godot(mw_pos))
	if db.find_cell(key).is_empty():
		travel({"cell_key": "", "cell_name": "", "transform": t})
	else:
		travel({"cell_key": key, "cell_name": cell, "transform": t})

## MessageBox ze skryptu: bez przycisków – komunikat; z przyciskami – okno (tryb menu), wybór → GetButtonPressed.
func show_message_box(text: String, buttons: Array) -> void:
	if buttons.is_empty():
		_toast(text, 4.0)
		return
	if msgbox != null and is_instance_valid(msgbox):
		msgbox.queue_free()
	var cl := CanvasLayer.new()
	cl.layer = 30
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(520, 0)
	box.add_child(l)
	for i in buttons.size():
		var b := Button.new()
		b.text = String(buttons[i])
		var idx := i
		b.pressed.connect(func():
			scripts.button_pressed = idx
			cl.visible = false
			cl.queue_free()
			get_tree().paused = false
			if DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
		box.add_child(b)
	cl.add_child(panel)
	add_child(cl)
	panel.position = (get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0
	msgbox = cl
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Automatyzacja/testy: naciśnięcie przycisku otwartego MessageBox (jak kliknięcie).
func press_message_button(i: int) -> bool:
	if msgbox == null or not is_instance_valid(msgbox) or not msgbox.visible:
		return false
	var btns: Array = msgbox.find_children("*", "Button", true, false)
	if i >= btns.size():
		return false
	(btns[i] as Button).pressed.emit()
	return true

## Przedmiot położony/podniesiony w świecie (dyn#N) → dodanie albo usunięcie węzła we wczytanej komórce.
func _on_dynamic_changed(sid: String) -> void:
	if script_host != null:
		script_host.dirty = true
	for key in loaded:
		var refs_node: Node = loaded[key].get_node_or_null("Refs")
		if refs_node == null:
			continue
		for n in refs_node.get_children():
			if String(n.get_meta("mw_sid", "")) == sid:
				n.free()
		for r in state.dynamic_refs(key):
			if String(r["sid"]) == sid:
				var nn := builder.build_ref(r)
				if nn:
					refs_node.add_child(nn)

## Menu pauzy (Esc): wróć, szybki zapis/odczyt, wyjście. Szkielet UI etapu 0.
func toggle_pause_menu() -> void:
	if pause_menu == null:
		pause_menu = _build_pause_menu()
	pause_menu.visible = not pause_menu.visible
	get_tree().paused = pause_menu.visible
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_menu.visible else Input.MOUSE_MODE_CAPTURED

func _build_pause_menu() -> Control:
	var cl := CanvasLayer.new()
	cl.layer = 10
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	var panel := PanelContainer.new()
	panel.name = "PauseMenu"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Pauza"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for item in [["Wróć do gry", func(): toggle_pause_menu()],
			["Szybki zapis (F5)", func(): _toast("Zapisano grę" if save_game(quicksave_path()).is_empty() else "Błąd zapisu")],
			["Szybki odczyt (F9)", func():
				var w = load_game(quicksave_path())
				toggle_pause_menu()
				_toast("Wczytano grę" if w.is_empty() else "\n".join(w))],
			["Wyjdź z gry", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		box.add_child(b)
	cl.add_child(panel)
	panel.position = (get_viewport().get_visible_rect().size - panel.get_combined_minimum_size()) / 2.0
	panel.visible = false
	return panel
