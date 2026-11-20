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
const L10n := preload("res://scripts/mw/mw_l10n.gd")
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
const UI := preload("res://scripts/mw/mw_ui.gd")
var events = Events.new()           # szyna zdarzeń (etap 0)
var native_mods = null               # mw_native_mods.gd – natywne mody (eksperyment first-fish)
var interaction = null                # MWInteraction (etap 3)
var item_window = null                # okno pojemnika / ekwipunku
var quick_keys = null                 # mw_quick_keys.gd – QuickKeysMenu (F1, klawisze 1–0)
var audio = null                      # MWAudio (etap 3)
var music = null                      # MWMusic (etap 10)
var anim_sounds = null                # etap 10: dźwięki z kluczy animacji (kroki NPC, stworzenia)
var book_window = null                # etap 10: książki i zwoje
var local_map = null                  # etap 10: mapa lokalna (segmenty, mgła wojny)
var map_window = null                 # etap 10: okno mapy (N)
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
var service_window = null          # zakup zaklęć, podróże, trening, naprawa u NPC (układy OpenMW)
var repair = null                  # mw_repair.gd – Repair::repair, MerchantRepair
var repair_window = null           # okno naprawy narzędziem (MWGui::Repair)
var alchemy_window = null          # okno alchemii (MWGui::AlchemyWindow)
var combat = null                     # etap 7: walka
var enchanting_window = null          # EnchantingDialog (GM_Enchanting)
var spellcreation_window = null       # SpellCreationDialog (GM_SpellCreation)
var recharge_window = null            # Recharge (GM_Recharge)
var levelup_window = null             # LevelupDialog (GM_Levelup)
var message_boxes = null              # MessageBoxManager (komunikaty i okna z pytaniem)
var gui = preload("res://scripts/mw/mw_gui_modes.gd").new(self)    # stos trybów GUI (WindowManager)
var data_dir := ""                    # katalog przekonwertowanych danych
var navmesh = null                    # siatka nawigacji AI (mw_navmesh.gd)
var doors = null                      # drzwi obrotowe (World::activateDoor/processDoors)
var menu_mode = null                  # etap 10: tryb menu (statystyki, ekwipunek, magia, mapa)
var ai = null                         # etap 8: AI aktorów (mw_ai.gd)
var crime = null                      # etap 8: przestępstwa i strażnicy (mw_crime.gd)
var magic_ready := false              # przygotowana magia (klawisz R) – lewy przycisk rzuca
var state = GameStateScript.new()   # różnice stanu gry względem danych bazowych (zapis gry)
var pause_menu = null                  # menu główne w trybie gry (MainMenu)
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
	var pump := preload("res://scripts/mw/mw_script_pump.gd").new()
	pump.name = "ScriptPump"
	pump.main = self
	add_child(pump)
	mk.name = "MenuKey"
	mk.main = self
	add_child(mk)
	var data := arg("data", ProjectSettings.get_setting("mwgodot/data_root", "user://mwdata"))
	data_dir = data
	var base := arg("base")
	if not base.is_empty():
		MWModelCache.base_roots = PackedStringArray([ProjectSettings.globalize_path(base)])
	settings = _load_settings(arg("settings"))
	UI.gui_scaling = clampf(float(settings.get("gui_scaling_factor", 1.0)), 0.5, 8.0)
	# tekstury interfejsu (ramki MW_Box/MW_Dialog, przyciski) dostępne przed budową okien w _ready – bez tego
	# texture() zapamiętuje brak pliku i okna dostają zapasowe płaskie ramki zamiast menu_thin_border_*
	UI.setup(data_dir)
	# paski przewijania jak MW_VScroll: krok 36 px i MoveToClick w każdym oknie (także listy i pola tekstu)
	get_tree().node_added.connect(_on_node_added_scroll)
	# [General] preferred locales (OpenMW, domyślnie „en”) – teksty silnika z l10n OMWEngine/Calendar
	preload("res://scripts/mw/mw_l10n.gd").set_locales(String(settings.get("preferred_locales", "en")))   # [GUI] scaling factor
	settings.merge(_load_ingame_settings(), true)      # etap 10: zmiany z „Ustawienia” w grze (nowsze)
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
	# natywne mody OpenMWGodot (eksperyment first-fish): mods/ obok projektu, --mods=KATALOG, --mods= wyłącza
	var mods_dir := arg("mods", String(settings.get("native_mods_dir",
			ProjectSettings.globalize_path("res://").path_join("../mods").simplify_path())))
	native_mods = preload("res://scripts/mw/mw_native_mods.gd").new(self, mods_dir)
	events.cell_loaded.connect(native_mods.on_cell_loaded)
	tree_exiting.connect(native_mods.free_cache)
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
	chargen.main = self
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
	navmesh = preload("res://scripts/mw/mw_navmesh.gd").new(self)
	doors = preload("res://scripts/mw/mw_doors.gd").new(self)
	ai.enabled = arg("ai", "1") != "0"
	crime = preload("res://scripts/mw/mw_crime.gd").new(self)
	interaction.crime = crime
	interaction.main_scripts = scripts
	trade_window = TradeWindowScript.new()
	trade_window.main = self
	trade_window.trade = trade
	service_window = preload("res://scripts/mw/mw_service_window.gd").new()
	service_window.name = "ServiceWindow"
	service_window.main = self
	service_window.trade = trade
	add_child(service_window)
	repair = preload("res://scripts/mw/mw_repair.gd").new(self)
	repair_window = preload("res://scripts/mw/mw_repair_window.gd").new()
	repair_window.name = "RepairWindow"
	repair_window.main = self
	add_child(repair_window)
	alchemy_window = preload("res://scripts/mw/mw_alchemy_window.gd").new()
	alchemy_window.name = "AlchemyWindow"
	alchemy_window.main = self
	add_child(alchemy_window)
	add_child(trade_window)
	rest_window = RestWindowScript.new()
	rest_window.main = self
	rest_window.character = character
	add_child(rest_window)
	enchanting_window = preload("res://scripts/mw/mw_enchanting_window.gd").new()
	enchanting_window.name = "EnchantingDialog"
	enchanting_window.main = self
	add_child(enchanting_window)
	spellcreation_window = preload("res://scripts/mw/mw_spellcreation_window.gd").new()
	spellcreation_window.name = "SpellCreationDialog"
	spellcreation_window.main = self
	add_child(spellcreation_window)
	levelup_window = preload("res://scripts/mw/mw_levelup_window.gd").new()
	levelup_window.name = "LevelupDialog"
	levelup_window.main = self
	levelup_window.character = character
	add_child(levelup_window)
	recharge_window = preload("res://scripts/mw/mw_recharge_window.gd").new()
	recharge_window.name = "RechargeWindow"
	recharge_window.main = self
	add_child(recharge_window)
	journal_window = JournalWindowScript.new()
	journal_window.dialogue = dialogue
	journal_window.main = self
	journal_window.data_root = data
	add_child(journal_window)
	book_window = preload("res://scripts/mw/mw_book_window.gd").new()
	book_window.name = "BookWindow"
	book_window.main = self
	book_window.data_root = data
	book_window.closed.connect(_on_book_closed)
	add_child(book_window)
	local_map = preload("res://scripts/mw/mw_local_map.gd").new()
	local_map.name = "LocalMap"
	local_map.main = self
	local_map.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(local_map)
	map_window = preload("res://scripts/mw/mw_map_window.gd").new()
	map_window.name = "MapWindow"
	map_window.main = self
	map_window.lmap = local_map
	map_window.data_root = data
	add_child(map_window)
	events.game_loaded.connect(func(_p, _w): local_map.reset_fog())
	audio = preload("res://scripts/mw/mw_audio.gd").new()
	audio.name = "Audio"
	audio.setup(data, builder.actors)
	audio.enabled = arg("screenshot").is_empty() and bool(settings.get("sound", true))
	add_child(audio)
	anim_sounds = preload("res://scripts/mw/mw_anim_sounds.gd").new()
	anim_sounds.name = "AnimSounds"
	anim_sounds.main = self
	add_child(anim_sounds)
	music = preload("res://scripts/mw/mw_music.gd").new()
	music.name = "Music"
	music.setup(data)
	music.enabled = audio.enabled and bool(settings.get("music", true))
	add_child(music)
	quick_keys = preload("res://scripts/mw/mw_quick_keys.gd").new()
	quick_keys.name = "QuickKeysMenu"
	quick_keys.main = self
	add_child(quick_keys)
	item_window = ItemWindowScript.new()
	item_window.interaction = interaction
	item_window.main = self
	add_child(item_window)
	menu_mode = preload("res://scripts/mw/mw_menu_mode.gd").new()
	menu_mode.name = "MenuModeLayer"
	menu_mode.main = self
	add_child(menu_mode)
	if db.cell_index().is_empty():
		push_error("Brak danych świata w %s – uruchom konwerter (README)." % data)
		_add_message("No world data in:\n%s\nRun the mwconv converter (see docs/DEBIAN13.md)." % data)
		if launched_by_launcher:
			printerr("MWGODOT_ERROR brak danych świata: ", data)
			get_tree().quit(2)  # launcher pokaże błąd z kodem wyjścia
		return
	MWEnvironment.water_mode = "shader" if bool(settings.get("water_shader", true)) else "simple"
	envr = MWEnvironment.new()
	envr.name = "Environment"
	envr.main = self
	envr.data_root = data
	envr.fog_distance = float(settings.get("view_distance", 1500))
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
	mw_hud = preload("res://scripts/mw/mw_hud.gd").new()
	mw_hud.name = "MWHud"
	mw_hud.main = self
	add_child(mw_hud)
	mw_hud.build()
	_apply_settings()
	_setup_start_ui()
	if menu_start_wanted():
		_enter_nogame()
		_startup_sequence.call_deferred()
		return
	game_state = "running"
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
		# World::startNewGame(bypass): nowa gra z pominięciem skryptowego kreatora – CharGenState = −1 (w ESM 0),
		# bez tego zapis i „Zapisz grę” w menu głównym (isSavingAllowed, sCharGenState == −1) były zablokowane
		scripts.set_global("chargenstate", -1.0)
		scripts.start_new_game()          # skrypty startowe nowej gry („main”, SSCR)
	# nowa gra: kreator postaci (gra z launchera, bez wczytywania zapisu); tryby zrzutu/testów – postać domyślna
	if not (state.player.get("character", {}) as Dictionary).is_empty():
		pass
	elif scripted_start:
		_new_player_character()
	elif launched_by_launcher and lp.is_empty() and arg("screenshot").is_empty() and arg("autotest-frames", "0") == "0" \
			and bool(settings.get("character_creation", true)) and builder.actors.available():
		chargen.open(default_choice())
	else:
		_new_player_character()
	if lp.is_empty():
		_init_player_items()

func _on_node_added_scroll(n: Node) -> void:
	if n is ScrollContainer:
		UI.setup_scroll(n)
	elif n is ScrollBar:
		UI.setup_scroll_bar(n)

## Npc::getNpcData dla gracza (World::setupPlayer): ekwipunek z rekordu NPC „player” (ContainerStore::fill)
## i InventoryStore::autoEquip – raz, przy nowej grze; stan zapisu ma już własny inwentarz.
func _init_player_items() -> void:
	if builder == null or not builder.actors.available():
		return
	var rec: Dictionary = builder.actors.record("npc", "player")
	if rec.is_empty():
		return
	if not state.has_inventory("player"):
		state.set_inventory("player", interaction.inventory.base_contents(rec, "player"))
		_weight_cache = -1.0
	if player_stats().is_empty() or bool(state.player.get("record_equipped", false)):
		return
	state.player["record_equipped"] = true
	var eq := _equipment()
	var av = builder.actors
	if av.equipment == null:
		av.equipment = av.Equipment.new(av)
	var slots: Dictionary = av.equipment.auto_equip(rec, state.inventory("player"))
	for sl in slots:
		eq[str(sl)] = {"id": String(slots[sl].id).to_lower(), "health": -1.0}
	_rebuild_player_visual()

# --- nowa gra ze skryptami CharGen (etap 9) -------------------------------------------------------------------

const CHARGEN_MENUS := ["inventory", "magic", "map", "stats", "rest"]   # WindowManager::disallowAll (też odpoczynek)

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
	if book_window != null:
		book_window.set_inventory_allowed(false)
	state.player["chargen_choice"] = default_choice()
	if chargen != null:
		chargen.reset()
	scripts.set_global("chargenstate", 1.0)
	scripts.start_new_game()
	for i in 5:
		scripts.tick(0.0, [])

func menu_allowed(kind: String) -> bool:
	# setWerewolf: wilkołak nie ma dostępu do ekwipunku i magii (forceHide GW_Inventory, GW_Magic)
	if kind in ["inventory", "magic"] and bool(player_stats().get("werewolf", false)):
		return false
	var m: Dictionary = state.player.get("menus", {})
	if kind == "rest" and not bool(m.get("rest", true)) and scripts != null and scripts.get_global("chargenstate") == -1.0:
		m["rest"] = true                       # getRestEnabled: po zakończeniu tworzenia postaci
		state.player["menus"] = m
	return bool(m.get(kind, true))

func control_allowed(kind: String) -> bool:
	return script_host == null or script_host.control_enabled(kind)

## Menu tworzenia postaci wywołane skryptem: imię, rasa (z płcią, głową, włosami), klasa, znak, przegląd.
func open_chargen_step(step: String) -> void:
	if chargen == null:
		return
	var ch: Dictionary = state.player.get("chargen_choice", default_choice())
	chargen.open_step(step, ch)

## Nowa gra: gracz z rekordu „player” (surowe NPDT), rasa i klasa jeszcze niewybrane (mRaceSelected/mClassSelected).
func _new_player_character() -> void:
	state.player["character"] = character.build_record(default_choice())
	state.player["chargen_flags"] = {"race": false, "class": false}

## Krok kreatora jak MechanicsManager: setPlayerName – tylko imię; setPlayerRace/Class/Birthsign – buildPlayer
## z dotychczas wybranymi elementami (rasa tylko po jej wyborze, klasa tylko po jej wyborze), potem
## unequipAll + autoEquip (np. buty po zmianie na rasę zwierzęcą). Bez znaczników (wczytany zapis) –
## wszystko wybrane, jak MechanicsManager::playerLoaded.
func _on_chargen_step(step: String, ch: Dictionary) -> void:
	var merged: Dictionary = state.player.get("chargen_choice", default_choice())
	merged.merge(ch, true)
	state.player["chargen_choice"] = merged
	var old: Dictionary = state.player.get("character", {})
	if step == "name" and not old.is_empty():
		old["name"] = String(ch.get("name", old.get("name", "")))
		return
	var flags: Dictionary = state.player.get("chargen_flags", {"race": true, "class": true})
	if step == "race":
		flags["race"] = true
	elif step == "class":
		flags["class"] = true
	state.player["chargen_flags"] = flags
	var st: Dictionary = character.build(merged, flags)
	if String(st.get("name", "")).is_empty():
		st["name"] = String(old.get("name", "")) if not String(old.get("name", "")).is_empty() else "Outlander"
	state.player["character"] = st
	_reequip_player(String(st.get("race", "")))
	_rebuild_player_visual()

## buildPlayer: unequipAll, potem autoEquip z bieżącego ekwipunku (rasa decyduje np. o butach).
func _reequip_player(race: String) -> void:
	if builder == null or not builder.actors.available() or not state.has_inventory("player"):
		return
	var av = builder.actors
	if av.equipment == null:
		av.equipment = av.Equipment.new(av)
	var npc: Dictionary = av.record("npc", "player").duplicate()
	if not race.is_empty():
		npc["race"] = race
	var eq := _equipment()
	eq.clear()
	var slots: Dictionary = av.equipment.auto_equip(npc, state.inventory("player"))
	for sl in slots:
		eq[str(sl)] = {"id": String(slots[sl].id).to_lower(), "health": -1.0}
	_weight_cache = -1.0

## Czy otwarte jest jakieś okno (wtedy klawisze trybu menu nie działają).
func _no_window_open() -> bool:
	for w in [item_window, map_window, journal_window, rest_window, dialogue_window, menu_mode,
			get("repair_window"), get("service_window"), get("alchemy_window"), get("enchanting_window"),
			get("spellcreation_window"), get("recharge_window"), get("levelup_window")]:
		if w != null and w.visible and not (w.get("pinned_mode") == true):     # przypięta mapa nie jest oknem GUI
			return false
	return not get_tree().paused and not gui.is_gui_mode()

## Postać gracza do podglądu w ekwipunku: rekord NPC „player” z wyglądem z kreatora i założonymi rzeczami.
func player_doll() -> Node3D:
	var av = builder.actors if builder != null else null
	if av == null or not av.available():
		return null
	var npc: Dictionary = av.record("npc", "player").duplicate()
	if npc.is_empty():
		return null
	var st := player_stats()
	for k in ["race", "head", "hair"]:
		if not String(st.get(k, "")).is_empty():
			npc[k] = st[k]
	npc["female"] = bool(st.get("female", npc.get("female", false)))
	npc["spells"] = (st.get("spells", []) as Array).duplicate()    # wampiryzm gracza – głowa wampira
	var slots := {}
	var eq := _equipment()
	for sl in eq:
		var it: Dictionary = interaction.inventory.item(String(eq[sl].id))
		if not it.is_empty():
			slots[int(sl)] = {"kind": String(it.kind), "rec": it.rec}
	return av.build_npc_rec(npc, "player", 0, "", slots)

func _rebuild_player_visual() -> void:
	if player != null and player.has_method("rebuild_visual"):
		player.rebuild_visual()

## Napis kwestii (Say) – bez okna, nie wstrzymuje gry.
var _subtitle: Label = null
## Warstwa komunikatów i napisów nad oknami (książki, dialog, mapa) – jak okna komunikatów OpenMW zawsze na wierzchu.
var _overlay: CanvasLayer = null

func overlay() -> CanvasLayer:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.name = "Overlay"
		_overlay.layer = 30
		_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_overlay)
	return _overlay

func subtitle(text: String, seconds: float) -> void:
	print("MWGODOT_SAY ", text.length())
	if not bool(settings.get("subtitles", true)):
		return
	if _subtitle == null:
		_subtitle = Label.new()
		_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_subtitle.anchor_left = 0.15
		_subtitle.anchor_right = 0.85
		_subtitle.anchor_top = 0.78
		_subtitle.anchor_bottom = 0.9
		_subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
		_subtitle.add_theme_constant_override("outline_size", 6)
		_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay().add_child(_subtitle)
	if _subtitle != null:
		_subtitle.text = text
		_subtitle.visible = true
		var t := get_tree().create_timer(seconds, true)    # głos gra także przy otwartym oknie (pauza)
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
	var old: Dictionary = state.player.get("character", {})
	if old.get("equipment") is Dictionary and not st.has("equipment"):
		st["equipment"] = old.equipment
	state.player["character"] = st
	_init_player_items()

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
		var tmpl: String = dialogue.gmst_text("sNotifyMessage39", "Your %s skill increased to %d.") if dialogue != null else "%s: %d"
		_toast(tmpl.replace("%s", sname).replace("%d", str(int(m.level))) if tmpl.contains("%s") else "%s: %d" % [sname, int(m.level)])
		if audio != null:
			audio.play("skillraise")
	elif m.kind == "levelup_ready":
		_toast(dialogue.gmst_text("sLevelUpMsg", "You should rest and reflect on what you have learned.") if dialogue != null else "Rest to level up.")

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
	if (magic != null and magic.magnitude_of(combat.player_fighter(), magic.FX_PARALYZE) > 0.0) \
			or bool(st.get("knocked_down", false)):
		player.walk_speed = 0.0                    # paraliż / powalenie: bez ruchu i skoku (animacja – etap 10)
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
	var k := id.to_lower()
	for s in eq:
		if String(eq[s].id) == k:
			return int(s)
	if not k.contains("#"):                  # identyfikator rekordu (skrypty): też egzemplarz o niepełnym stanie
		for s in eq:
			if interaction.inventory.base_id(String(eq[s].id)) == k:
				return int(s)
	return -1

## Załóż przedmiot gracza. Broń dwuręczna zdejmuje tarczę i odwrotnie (okno ekwipunku – InventoryWindow::useItem);
## resolve = false – jak sama ActionEquip (przedmioty przywołane): bez zdejmowania kolidującej broni/tarczy.
## → komunikat ("" = gotowe)
func equip_item(id: String, resolve := true) -> String:
	var k := id.to_lower()
	if interaction.inventory.count_of("player", {}, k) <= 0 and not k.contains("#"):
		# identyfikator rekordu: egzemplarz o niepełnym stanie („id#c:N”), jeśli tylko taki jest
		for e in interaction.inventory.contents("player", {}):
			if int(e.count) > 0 and interaction.inventory.base_id(String(e.id)) == k:
				k = String(e.id)
				break
	if interaction.inventory.count_of("player", {}, k) <= 0:
		return "You do not have this item."
	var slots := item_slots(k)
	if slots.is_empty():
		return "This item cannot be equipped."
	var eq := _equipment()
	var slot: int = slots[0]
	if slots.size() > 1 and eq.has(str(slots[0])) and not eq.has(str(slots[1])):
		slot = slots[1]
	var it: Dictionary = interaction.inventory.item(k)
	if resolve and slot == EQ.SLOT_CARRIED_RIGHT and int(it.rec.get("weapon_type", 0)) in EQ.WEAPON_TWO_HANDED:
		eq.erase(str(EQ.SLOT_CARRIED_LEFT))
	if resolve and slot == EQ.SLOT_CARRIED_LEFT and eq.has(str(EQ.SLOT_CARRIED_RIGHT)):
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
	if bool(player_stats().get("knocked_down", false)):
		return {"success": false}                 # powalony gracz nie atakuje (CharacterController)
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
	if magic != null:
		magic.break_invisibility(att)             # CharacterController: zwolnienie ataku
	var ammo := w
	if wt != 11:
		var a: Dictionary = combat.equipment(att).get(EQ.SLOT_AMMUNITION, {})
		if a.is_empty() or int(a.rec.get("weapon_type", -1)) != (12 if wt == 9 else 13):
			_toast(dialogue.gmst_text("sNotifyMessage60", "You have no ammunition."))
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
		# actorAttacked: aktor z OnPCHitMe w skrypcie i Fight 0 nie oddaje graczowi (chyba że StartCombat)
		var sc: String = String(db.get_object(String(f.get("base", "")).to_lower()).get("script", "")).to_lower()
		if not sc.is_empty() and scripts != null and scripts._var_type(sc, "onpchitme") != "" \
				and dialogue != null and int(dialogue.ai_setting(dialogue.make_actor(f.node), "fight")) == 0:
			return
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
	if magic != null:
		magic.break_invisibility(att)
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
		player_stats()["has_died"] = true      # notifyDied (OnDeath)
		_player_died()
		return
	if dialogue != null and f.get("node") != null and f.kind == "npc":
		dialogue.say_voice(f.node, "hit")    # ostatnie słowa (Actors::killDeadActors)
	if magic != null:
		magic.soul_trap(f)                 # Pułapka dusz: dusza stworzenia do kamienia gracza
	if crime != null and not _att.is_empty() and _att.get("kind", "") == "player" and f.get("node") != null:
		crime.on_killed(f.node)            # actorKilled: morderstwo (etap 8)
	# Npc::onHit/actorKilled: zabicie NPC przez gracza-wilkołaka – GetWerewolfKills
	if f.kind == "npc" and not _att.is_empty() and _att.get("kind", "") == "player" and bool(player_stats().get("werewolf", false)):
		player_stats()["werewolf_kills"] = int(player_stats().get("werewolf_kills", 0)) + 1
	var a: Dictionary = combat._actor_state(f)
	a["dead"] = true
	if magic != null:
		magic.clear_on_death(f)            # ActiveSpells::clear: przywołania znikają, efekty cofnięte
		magic.purge_caster(String(f.sid))  # purgeSpellEffects: czary zmarłego na innych aktorach usunięte
	a["health"] = 0.0
	var ds: Dictionary = dialogue._ds()
	ds.deaths[f.base] = int(ds.deaths.get(f.base, 0)) + 1
	# notifyDied: OnDeath do odczytu przez skrypt (OpenMW – po animacji śmierci; tu bez animacji, od razu)
	a["has_died"] = true
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
	_update_knockdown(player_stats(), dt)      # powalenie i nokaut gracza (kondycja < 0) – jak NPC
	if player != null:
		player.move_flags = player_stats().get("move_flags", {})
		magic.apply_movement(combat.player_fighter(), player)
		magic.update_drowning(combat.player_fighter(), player, dt)
	for key in loaded:
		var refs: Node = loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.has_meta("mw_actor"):
				continue
			var a = state.actors.get(String(n.get_meta("mw_sid", "")))
			var fa: Dictionary = combat.fighter_of(n)
			if (a is Dictionary and not (a.get("active_spells", []) as Array).is_empty()) or magic.has_constant_tick(fa) \
					or magic.has_spell_store(fa):
				magic.tick(fa, dt)
			magic.apply_movement(fa, n)
			magic.update_drowning(fa, n, dt)
			if a is Dictionary and a.has("fatigue") and not bool(a.get("dead", false)):
				_restore_actor_fatigue(combat.fighter_of(n), a, dt)
			if a is Dictionary and not bool(a.get("dead", false)):
				_update_knockdown(a, dt)
			if a is Dictionary and "move_flags" in n:
				n.move_flags = a.get("move_flags", {})
	_recharge_acc += dt
	if _recharge_acc >= 1.0:
		magic.recharge(player_stats(), _recharge_acc)
		_recharge_acc = 0.0

const KNOCKDOWN_TIME := 2.0     # czas powalenia (bez animacji knockdown – jak dotąd w AI walki)

## Powalenie (CharacterController::refreshHitRecoilAnims, Actors::update): kondycja < 0 – nieprzytomny (knockout,
## trwa do odzyskania kondycji), powalenie od ciosu – KNOCKDOWN_TIME. OnKnockout: dokładnie jedna klatka po
## powaleniu (knockedDownOneFrame → knockedDownOverOneFrame); wstanie kasuje oba.
func _update_knockdown(a: Dictionary, dt: float) -> void:
	var knockout := a.has("fatigue") and float(a.fatigue) < 0.0
	if knockout and not bool(a.get("knocked_down", false)):
		a["knocked_down"] = true
	if not bool(a.get("knocked_down", false)):
		return
	a["knocked_down_t"] = float(a.get("knocked_down_t", 0.0)) + dt
	if bool(a.get("knocked_one", false)) and not bool(a.get("knocked_over", false)):
		a.erase("knocked_one")
		a["knocked_over"] = true
	elif not bool(a.get("knocked_one", false)) and not bool(a.get("knocked_over", false)):
		a["knocked_one"] = true
	if not knockout and float(a.knocked_down_t) >= KNOCKDOWN_TIME:
		for k in ["knocked_down", "knocked_down_t", "knocked_one", "knocked_over"]:
			a.erase(k)

## Odnawianie kondycji NPC/stworzeń we wczytanych komórkach (Actors::calculateRestoration, co klatkę):
## (fFatigueReturnBase + fFatigueReturnMult × wytrzymałość) × czas, tylko poniżej podstawy (wzmocnienie – bez zmian).
## Dotyczy aktorów ze zmienioną kondycją (walka, ModCurrentFatigue) – pozostali mają pełną.
func _restore_actor_fatigue(f: Dictionary, a: Dictionary, dt: float) -> void:
	if f.is_empty():
		return
	var cur := float(a.fatigue)
	var base: float = combat.max_fatigue(f)
	if cur >= base:
		return
	var en: float = float(combat.attributes(f)[5])
	var x: float = float(character._gmst("ffatiguereturnbase", 2.5)) + float(character._gmst("ffatiguereturnmult", 0.02)) * en
	a["fatigue"] = minf(cur + dt * x, base)

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
	travel_to_cell(String(m.get("interior", "")), pos, float(m.get("rot", rad_to_deg(-player.rotation.y))))

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
	if bool(player_stats().get("knocked_down", false)):
		return {"success": false}                 # powalony gracz nie rzuca czarów
	var sel := selected_magic()
	if sel.is_empty():
		_toast(dialogue.gmst_text("sNoSpellSelected", "No spell selected.") if dialogue != null else "No spell selected.", 2.0)
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

## applyMagicEffect (spelleffects.cpp) dla obiektu: Zamknięcie – gdy poziom < wielkość, zamyka na wielkość;
## Otwarcie – unlockAttempted (przestępstwo na rzecz gracza), otwiera przy poziomie ≤ wielkość. Tylko canLock
## (drzwi, pojemniki nieorganiczne); inne obiekty – efekt nieprawidłowy. Zwraca true, gdy efekt zadziałał.
func _lock_effect(node: Node, e: Dictionary, caster_is_player := true) -> bool:
	var id := int(e.get("effect", -1))
	if id != magic.FX_OPEN and id != magic.FX_LOCK:
		return false
	var k := String(interaction.kind_of(node))
	if not (k == "door" or (k == "container" and not bool(interaction.container_record(
			String(node.get_meta("mw_base", ""))).get("organic", false)))):
		return false
	var sid: String = interaction.sid_of(node)
	var lvl: int = interaction.lock_level(node)
	var mag := int(magic._roll_magnitude({"min": float(e.get("min", 0)), "max": float(e.get("max", 0))}))
	if id == magic.FX_OPEN:
		if crime != null:
			crime.unlock_attempted(interaction.extra_of(node), lvl > 0 or not interaction.trap(node).is_empty())
		if lvl <= mag:
			if lvl > 0:
				state.set_lock(sid, 0)
				if caster_is_player:
					_toast(dialogue.gmst_text("sMagicOpenSuccess", "The lock is open."), 2.0)
				if audio != null:
					audio.play("Open Lock")
		elif audio != null:
			audio.play("Open Lock Fail")
	elif lvl < mag:
		state.set_lock(sid, mag)
		if caster_is_player:
			_toast(dialogue.gmst_text("sMagicLockSuccess", "The lock is closed."), 2.0)
		if audio != null:
			audio.play("Open Lock")
	return true

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

var death_screen = null                 # zgodność: dawny ekran śmierci (zastąpiony askLoadRecent)
var _death_handled := false

## Śmierć gracza jak OpenMW: Engine – StateManager::endGame (stan „Ended”, bez zapisu i powrotu do gry), po końcu
## animacji śmierci Actors → StateManager::askLoadRecent: bez zapisów – menu główne; inaczej pytanie
## „Ostatni zapis to ''…''. Czy chcesz go wczytać?” (Tak – wczytanie, Nie – menu główne).
func _player_died() -> void:
	player_stats()["health"] = 0.0
	if music != null and not _death_handled:
		music.player_died()
	if _death_handled:
		return
	_death_handled = true
	game_state = "ended"
	# czas animacji śmierci gracza (CharacterController::Result_DeathAnimJustFinished) – u nas stały
	get_tree().create_timer(DEATH_ANIM_SECONDS, true, false, true).timeout.connect(ask_load_recent)

const DEATH_ANIM_SECONDS := 3.0

## Resurrect na graczu (StateManager::resumeGame): koniec gry cofnięty, pytanie o wczytanie już się nie pojawi.
func resume_after_death() -> void:
	if game_state == "ended":
		game_state = "running"
	_death_handled = false

func ask_load_recent() -> void:
	if game_state != "ended":
		return
	if main_menu != null and main_menu.is_open():
		return
	if last_savegame.is_empty() or not FileAccess.file_exists(last_savegame):
		open_main_menu()
		return
	var desc := last_savegame.get_file().get_basename()
	var h = saves.read_header(last_savegame) if saves != null else null
	if h != null:
		desc = String(h.get("description", desc))
	show_message_box(L10n.text("AskLoadLastSave", "The most recent save is ''{save}''. Do you want to load it?", {"save": desc}),
			[dialogue.gmst_text("sYes", "Yes") if dialogue != null else "Yes", dialogue.gmst_text("sNo", "No") if dialogue != null else "No"], func(i):
		if i == 0:
			load_slot(saves.current, last_savegame)
		else:
			open_main_menu(), true)

static func _load_settings(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## Ustawienia z launchera (plik --settings): tylko opcje obsługiwane przez Runtime.
## Etap 10: ustawienia zmienione w grze – plik obok ustawień z launchera (albo w katalogu zapisów).
func ingame_settings_path() -> String:
	var sp := arg("settings")
	return (sp.get_base_dir() if not sp.is_empty() else saves_dir()).path_join("ingame_settings.json")

func _load_ingame_settings() -> Dictionary:
	var p := ingame_settings_path()
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return (d.get("values", {}) as Dictionary) if d is Dictionary and d.get("values") is Dictionary else {}

## Zapis atomowy (plik tymczasowy + zamiana): dotychczasowe zmiany z gry + nowe.
func save_ingame_settings(changes: Dictionary) -> bool:
	var vals := _load_ingame_settings()
	vals.merge(changes, true)
	var p := ingame_settings_path()
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"format": "mwgodot-ingame-settings", "version": 1, "values": vals}, " "))
	f.close()
	return DirAccess.rename_absolute(tmp, p) == OK

# --- [Windows]: ustawienia okien poza zapisem gry (OpenMW: settings.cfg użytkownika) ---------------------------
## Położenie i rozmiar (ułamki ekranu), przypięcie, ukrycie i maksymalizacja okien trybu menu są globalne jak
## sekcja [Windows] w OpenMW – nie zależą od zapisu. Plik window_settings.json obok ustawień z gry (zapis
## atomowy przy każdej zmianie); --window-settings=PLIK wskazuje inny plik; przebiegi testowe (-s) bez pliku
## trzymają ustawienia tylko w pamięci. Zgodność: dawne zapisy z kluczami ui_* w postaci – przy pierwszym
## wczytaniu, gdy pliku jeszcze nie ma, ustawienia są przejmowane do pliku; klucze usuwane z postaci.
const WINDOW_KEYS := ["ui_windows", "ui_pins", "ui_hidden", "ui_max"]
var window_settings := {}
var _window_settings_loaded := false

func window_settings_path() -> String:
	var p := arg("window-settings")
	if not p.is_empty():
		return p
	var a := OS.get_cmdline_args()
	if "-s" in a or "--script" in a:
		return ""
	return ingame_settings_path().get_base_dir().path_join("window_settings.json")

func _ensure_window_settings() -> void:
	if _window_settings_loaded:
		return
	_window_settings_loaded = true
	var p := window_settings_path()
	if p.is_empty() or not FileAccess.file_exists(p):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if d is Dictionary and d.get("windows") is Dictionary:
		for k in WINDOW_KEYS:
			if (d.windows as Dictionary).get(k) is Dictionary:
				window_settings[k] = (d.windows[k] as Dictionary).duplicate(true)

## Słownik jednego rodzaju ustawień okien (ui_windows / ui_pins / ui_hidden / ui_max).
func window_store(key: String) -> Dictionary:
	_ensure_window_settings()
	if not window_settings.get(key) is Dictionary:
		window_settings[key] = {}
	return window_settings[key]

func save_window_settings() -> bool:
	_ensure_window_settings()
	var p := window_settings_path()
	if p.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"format": "mwgodot-window-settings", "version": 1, "windows": window_settings}, " "))
	f.close()
	return DirAccess.rename_absolute(tmp, p) == OK

## Zapis sprzed etapu 9 z ustawieniami okien w postaci gracza: przejęcie (tylko gdy globalnych jeszcze nie ma).
func migrate_window_settings_from_save() -> void:
	_ensure_window_settings()
	var found := false
	for k in WINDOW_KEYS:
		if state.player.has(k):
			found = true
	if not found:
		return
	var p := window_settings_path()
	var have_global := (not p.is_empty() and FileAccess.file_exists(p)) or not window_settings.is_empty()
	if not have_global:
		for k in WINDOW_KEYS:
			if state.player.get(k) is Dictionary:
				window_settings[k] = (state.player[k] as Dictionary).duplicate(true)
	for k in WINDOW_KEYS:
		state.player.erase(k)
	if not have_global:
		save_window_settings()

## Opcje zmieniane w trakcie gry: dźwięk, napisy, mysz, pole widzenia, odległość widzenia, cienie, mgła,
## V-Sync, limit FPS (bez przebudowy świata).
func apply_live_settings() -> void:
	if audio != null:
		audio.voice_volume = float(settings.get("voice_volume", 0.8))
		audio.sfx_volume = float(settings.get("sfx_volume", 1.0))
		audio.footsteps_volume = float(settings.get("footsteps_volume", 0.2))
	if music != null:
		music.volume = float(settings.get("music_volume", 0.5))
		if music.is_playing() and music._fade <= 0.0:
			music._player.volume_db = linear_to_db(maxf(music.volume, 0.0001))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("master_volume", 1.0)), 0.0001)))
	if _subtitle != null and not bool(settings.get("subtitles", true)):
		_subtitle.visible = false
	if player != null:
		player.mouse_sens = float(settings.get("mouse_sensitivity", 0.0025))
		player.invert_y = bool(settings.get("invert_y", false))
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam != null and arg("fov").is_empty():
			cam.fov = float(settings.get("fov", 60))
			cam.far = float(settings.get("view_distance", 1500))
			if envr != null:
				envr.fog_distance = cam.far
	Engine.max_fps = int(settings.get("max_fps", 0))
	if envr != null:
		envr.configure_shadows(String(settings.get("shadows", "medium")))
		envr.env.fog_enabled = bool(settings.get("fog", true))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.get("vsync", true) else DisplayServer.VSYNC_DISABLED)

func _apply_settings() -> void:
	apply_live_settings()
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
	envr.configure_shadows(String(settings.get("shadows", "medium")))
	envr.set_water_mode("shader" if bool(settings.get("water_shader", true)) else "simple")
	envr.env.fog_enabled = bool(settings.get("fog", true))
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.far = float(settings.get("view_distance", 1500))
		envr.fog_distance = cam.far

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
	if not interior.is_empty():
		var ip = find_interior_position(interior)
		if ip != null:
			return ip
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

## World::findInteriorPosition (start w komórce wewnętrznej, COC): drzwi teleportujące z tej komórki posortowane
## wg identyfikatora i komórki docelowej; w komórce, do której prowadzą, szukane są dowolne drzwi z celem w naszej
## komórce – ich miejsce docelowe (bez obrotu). Bez takich drzwi – miejsce pierwszego obiektu statycznego.
## (Znaczniki cocmarkerheading/xmarkerheading OpenMW szuka tylko wśród obiektów ESM4.) → Transform3D albo null
func find_interior_position(name: String) -> Variant:
	var cell := db.get_cell("int:" + name.to_lower())
	if cell.is_empty():
		return null
	var doors := []
	for r in cell.get("refs", []):
		var ex: Dictionary = r.get("extra", {}) if r.get("extra") is Dictionary else {}
		if ex.get("door_dest") is Dictionary:
			doors.append(r)
	doors.sort_custom(func(a, b):
		var ia := String(a.base).to_lower()
		var ib := String(b.base).to_lower()
		if ia != ib:
			return ia < ib
		return String(a.extra.get("door_dest_cell", "")).to_lower() < String(b.extra.get("door_dest_cell", "")).to_lower())
	for d in doors:
		var dc := String(d.extra.get("door_dest_cell", ""))
		var dd: Dictionary = d.extra.door_dest
		var src := {}
		if not dc.is_empty():
			src = db.get_cell("int:" + dc.to_lower())
		elif dd.get("godot") is Dictionary:
			var o: Array = dd.godot.origin
			src = db.get_cell(db.exterior_key(MWCoords.cell_of(Vector3(o[0], o[1], o[2]))))
		for r2 in src.get("refs", []):
			var ex2: Dictionary = r2.get("extra", {}) if r2.get("extra") is Dictionary else {}
			if String(ex2.get("door_dest_cell", "")).to_lower() == name.to_lower() and ex2.get("door_dest") is Dictionary:
				var o2: Array = ex2.door_dest.godot.origin
				return Transform3D(Basis(), Vector3(o2[0], o2[1], o2[2]))
	for r in cell.get("refs", []):
		if String(db.get_object(String(r.base)).get("type", "")) == "STAT":
			var o3: Array = r.godot.origin
			return Transform3D(Basis(), Vector3(o3[0], o3[1], o3[2]))
	return null

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
	# wygląd Morrowinda dla wszystkich okien gry (motyw okna głównego dziedziczą wszystkie kontrolki)
	UI.setup(data_dir)
	var th: Theme = UI.theme(UI.ui_scale())
	var dt := ThemeDB.get_default_theme()       # domyślny motyw (dziedziczą go wszystkie kontrolki, także pod CanvasLayer)
	dt.merge_with(th)
	dt.default_font = th.default_font
	dt.default_font_size = th.default_font_size
	ThemeDB.fallback_font = th.default_font
	ThemeDB.fallback_font_size = th.default_font_size
	var cl := CanvasLayer.new()
	hud = RichTextLabel.new()      # BBCode: formatowanie z tłumaczeń ([c] [b] [i]) i znacznik QA
	hud.bbcode_enabled = true
	hud.fit_content = true
	hud.scroll_active = false
	hud.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.position = Vector2(12, 8)
	hud.size = Vector2(1600, 120)
	hud.visible = show_coords
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
		if mw_hud != null:
			mw_hud.set_hud_visible(false)

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
	if game_state == "nogame":
		return
	if player != null and audio != null:
		var moved: float = Vector2(player.global_position.x - _last_pos.x, player.global_position.z - _last_pos.z).length()
		_last_pos = player.global_position
		if moved < 2.0 and not player.fly:
			audio.footsteps(player, moved, player.is_on_floor(), player.swimming, _player_step_sound)
	_perf_mark("")
	_update_torches(_d)
	_update_water_level()
	_update_sound_world(_d)
	_update_map(_d)
	_perf_mark("torches+water+sound+map")
	if not get_tree().paused:
		_update_player_rpg(_d)
		_update_combat(_d)
		_update_magic(_d)
		_perf_mark("rpg+combat+magic")
		if doors != null:
			doors.process(_d)                     # World::processDoors
		if ai != null and arg("screenshot").is_empty():
			ai.tick(_d)
			if ai.enabled:
				crime.tick(_d)
		_perf_mark("ai+crime")
	if scripts != null and player != null and not get_tree().paused and arg("scripts", "1") != "0":
		scripts.tick(_d, script_host.scripted_refs())
	_perf_mark("scripts")
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
	_perf_mark("streaming")
	var hint := ""
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		for ch in player.get_children():
			if ch is Camera3D:
				cam = ch
	if cam:
		var r := activation_pick(cam)
		# podpowiedź tylko dla tego, co klawisz E faktycznie obsługuje (drzwi, przedmioty, pojemniki)
		var h: String = interaction.hint(r) if r and interaction != null else ""
		if h.is_empty() and r and dialogue != null and dialogue.is_actor_node(r) and dialogue.available():
			h = dialogue.actor_name(dialogue.make_actor(r))     # ToolTips::getToolTipViaPtr: aktor – sama nazwa
		if not h.is_empty():
			hint = "\n[lb]E] %s" % Loc.escape_bbcode(h)
		_focus_hint = h if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless" else ""
	var stats_line := ""
	var pst := player_stats()
	if not pst.is_empty() and character != null:
		var dd: Dictionary = character.derived(pst)
		stats_line = "\n%s  |  health %d/%d  |  magicka %d/%d  |  fatigue %d/%d" % [Loc.escape_bbcode(String(pst.get("name", ""))),
				roundi(float(pst.get("health", 0))), roundi(dd.health.modified), roundi(float(pst.get("magicka", 0))),
				roundi(dd.magicka.modified), roundi(float(pst.get("fatigue", 0))), roundi(dd.fatigue.modified)]
		var sm := selected_magic_name()
		if not sm.is_empty():
			stats_line += "  |  %s: %s" % ["magic ready" if magic_ready else "[lb]R] magic", Loc.escape_bbcode(sm)]
		elif weapon_drawn:
			stats_line += "  |  weapon drawn"
	var rname := display_location()
	hud.text = "%s  |  day %d, %02d:%02d  |  %s%s%s" % [rname, envr.day + 1, int(envr.game_hour), int(fmod(envr.game_hour, 1.0) * 60), envr.weather, coords_text() + stats_line, hint]
	_perf_mark("hud")
	_perf_report(_d)

## Pomiar czasu podsystemów w klatce (--perf=1): co 5 s średni i największy czas każdej części (ms) oraz
## najdłuższa klatka – do szukania przycięć (MWGODOT_PERF w logu).
var _perf_on := -1
var _perf_t := 0
var _perf_acc := {}
var _perf_time := 0.0
var _perf_n := 0
var _perf_worst := 0.0

func _perf_mark(label: String) -> void:
	if _perf_on < 0:
		_perf_on = 1 if arg("perf", "0") != "0" else 0
	if _perf_on == 0:
		return
	var now := Time.get_ticks_usec()
	if not label.is_empty():
		var a: Array = _perf_acc.get(label, [0.0, 0.0])
		var dt := (now - _perf_t) / 1000.0
		_perf_acc[label] = [a[0] + dt, maxf(a[1], dt)]
	_perf_t = now

func _perf_report(delta: float) -> void:
	if _perf_on != 1:
		return
	_perf_n += 1
	_perf_time += delta
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	if _perf_time < 5.0:
		return
	var parts := {}
	for k in _perf_acc:
		parts[k] = [snappedf(_perf_acc[k][0] / _perf_n, 0.01), snappedf(_perf_acc[k][1], 0.01)]
	print("MWGODOT_PERF ", JSON.stringify({"fps": snappedf(_perf_n / _perf_time, 0.1), "worst_frame_ms": snappedf(_perf_worst, 0.1),
			"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
			"parts_avg_max_ms": parts, "pos": position_string(), "cells": loaded.size()}))
	_perf_acc.clear()
	_perf_n = 0
	_perf_time = 0.0
	_perf_worst = 0.0

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
var show_coords := false                 # pasek z informacjami (F3) – domyślnie ukryty, jak w Morrowindzie
var _focus_hint := ""
var mw_hud = null                        # etap 10: HUD jak w Morrowindzie (paski, broń, czar, minimapa)

## Podpowiedź nad celem (HUD): co obsłuży klawisz aktywacji.
func focus_text() -> String:
	return _focus_hint

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
		cell = "cell %d,%d" % [g.x, g.y]
	else:
		cell = "interior \"%s\"" % interior
	var yaw := fposmod(-rad_to_deg(player.rotation.y), 360.0)
	return "\n%s  |  position %s  |  heading %d°  [lb]F3 hide, F4 copy]" % [Loc.escape_bbcode(cell), position_string(), roundi(yaw)]

func _unhandled_input(e: InputEvent) -> void:
	if game_state == "nogame":
		return
	if e.is_action_pressed("quick_save"):
		quick_save()                     # InputManager: StateManager::quickSave („Quicksave”)
	elif e.is_action_pressed("quick_load"):
		quick_load()                     # StateManager::quickLoad – najnowszy zapis bieżącej postaci
	elif e.is_action_pressed("toggle_coords"):
		show_coords = not show_coords
		if hud != null:
			hud.visible = show_coords
	elif e.is_action_pressed("toggle_hud") and mw_hud != null:
		mw_hud.set_hud_visible(not mw_hud.hud_visible)     # F11 (OpenMW A_ToggleHUD)
	elif e.is_action_pressed("copy_position") and player:
		var line := "--pos=%s" % position_string()
		if not interior.is_empty():
			line = "--cell=\"%s\" %s" % [interior, line]
		DisplayServer.clipboard_set(line)
		print("MWGODOT_POS ", line)
	if e.is_action_pressed("ready_weapon") and player and control_allowed("fighting"):
		weapon_drawn = not weapon_drawn
		if weapon_drawn:
			magic_ready = false
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ready_magic") and player and control_allowed("magic"):
		magic_ready = not magic_ready
		if magic_ready:
			weapon_drawn = false
		get_viewport().set_input_as_handled()
		return
	if (e.is_action_pressed("magic_menu") or e.is_action_pressed("map_menu") or e.is_action_pressed("inventory") \
			or e.is_action_pressed("menu_mode")) and player and menu_mode != null and not menu_mode.visible and _no_window_open() \
			and (menu_allowed("magic") or menu_allowed("map") or menu_allowed("inventory") or menu_allowed("stats")):
		menu_mode.open()                       # etap 10: tryb menu – statystyki, ekwipunek, magia, mapa naraz
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
	if e.is_action_pressed("activate") and player and control_allowed("controls"):
		for ch in player.get_children():
			if ch is Camera3D:
				var r := activation_pick(ch)
				if r:
					activate(r)

## Obiekt w zasięgu aktywacji (World::getFacedObject): iMaxActivateDist + Telekineza (wielkość w stopach ×
## 21,33 j.); poza zwykłym zasięgiem tylko obiekty pozwalające na telekinezę (nie aktorzy, nie otwarte drzwi
## teleportujące bez pułapki – Class::allowTelekinesis).
func activation_pick(cam: Camera3D) -> Node3D:
	var upm := MWCoords.UNITS_PER_METER
	var base := float(combat._gmst("iMaxActivateDist", 192)) / upm
	var tk: float = magic.magnitude_of(combat.player_fighter(), magic.FX_TELEKINESIS) if magic != null else 0.0
	var hit := MWTravel.pick_hit(cam, base + tk * (64.0 / 3.0) / upm)
	var r = hit.node
	if r == null or tk <= 0.0 or float(hit.dist) <= base:
		return r
	if r.has_meta("mw_actor") or dialogue != null and dialogue.is_actor_node(r):
		return null
	if not MWTravel.door_destination(r).is_empty() and interaction != null and interaction.lock_level(r) <= 0 \
			and interaction.trap(r).is_empty():
		return null
	return r

## ActionTeleport::getFollowers (drzwi): aktorzy z AiFollow/AiEscort za graczem, nie dalej niż 800 j., nie
## walczący z graczem. Przenoszone są referencje dynamiczne (przywołane stworzenia, PlaceAt…); stałe referencje
## komórek nie zmieniają dziś komórki (brak mechanizmu przenoszenia referencji między komórkami).
func _door_followers() -> Array:
	var out := []
	if ai == null or player == null:
		return out
	var pp := MWCoords.godot_to_mw(player.global_position)
	for n in ai.actor_nodes():
		var sid := String(n.get_meta("mw_sid", ""))
		if not state.dynamic.has(sid) or combat.is_dead(combat.fighter_of(n)):
			continue
		var follows := false
		var fights := false
		for pk in ai.ai_state(n).packages:
			var ty := String(pk.get("type", ""))
			if ty in ["follow", "escort"] and String(pk.get("target", "")).to_lower() == "player":
				follows = true
			if ty == "combat" and String(pk.get("target", "player")) == "player":
				fights = true
		if follows and not fights and MWCoords.godot_to_mw(n.global_position).distance_to(pp) <= 800.0:
			out.append(sid)
	return out

func _move_followers(sids: Array, dest: Dictionary) -> void:
	if sids.is_empty():
		return
	var t: Transform3D = dest["transform"]
	var key := String(dest.get("cell_key", ""))
	if key.is_empty():
		key = String(db.exterior_key(MWCoords.cell_of(t.origin)))
	var pos := MWCoords.godot_to_mw(t.origin)
	for sid in sids:
		var d: Dictionary = state.dynamic.get(sid, {})
		if d.is_empty():
			continue
		d["cell"] = key
		d.mw["pos"] = [pos.x, pos.y, pos.z]
		state.dynamic_changed.emit(sid)

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
			if magic != null:
				magic.disease_contact(combat.player_fighter(), f)   # ActionOpen: diseaseContact
			menu_mode.open_container(f.sid, f.rec, dialogue.actor_name(dialogue.make_actor(r)), true)
			return true
		# Npc::activate: gracz-wilkołak nie rozmawia z NPC (sWerewolfRefusal, dźwięk WolfNPC); NPC-wilkołak też nie
		var fa: Dictionary = combat.fighter_of(r) if combat != null else {}
		if String(r.get_meta("mw_actor", "")) == "npc" and bool(player_stats().get("werewolf", false)):
			_toast(dialogue.gmst_text("sWerewolfRefusal", ""))
			if audio != null:
				audio.play("wolfnpc", (r as Node3D).global_position)
			return true
		if not fa.is_empty() and state.actors.has(String(fa.sid)) and bool(state.actors[String(fa.sid)].get("werewolf", false)):
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
	if String(snap.kind) == "item" and String(db.get_object(String(snap.base)).get("type", "")) == "BOOK":
		return read_book(String(snap.base), r)     # ActionRead: okno z przyciskiem „Weź”
	var res: Dictionary = interaction.activate(r)
	if not String(snap.trap).is_empty() and String(interaction.trap(r)).is_empty() and magic != null:
		_trap_spell(String(snap.trap))           # pułapka: czar na gracza (etap 7/8)
	if not String(res.get("message", "")).is_empty():
		_toast(String(res["message"]))
	if audio != null and not String(res.get("sound", "")).is_empty():
		audio.play(String(res["sound"]), null if res.get("action") == "take" else at)
	match String(res.get("action", "")):
		"travel":
			var fol := _door_followers()
			travel(res["dest"])
			_move_followers(fol, res["dest"])
		"open_container":
			menu_mode.open_container(String(res["sid"]), interaction.container_record(String(res["base"])),
					String(res.get("name", "")))
		"door":
			if doors != null:
				doors.activate(r)              # dźwięk otwarcia/zamknięcia wybiera Door::activate
		"take", "locked":
			pass
		_:
			return false
	return true

## ActionRead (etap 10): okno książki albo zwoju; node – referencja w świecie (przycisk „Weź”), null – z ekwipunku.
## W walce nie można czytać z ekwipunku (sInventoryMessage4). Pierwsze przeczytanie książki z umiejętnością
## podnosi ją o 1 (skillLevelUp „book”, flagAsUsed – player.books_read).
var _book_node: Node = null

func read_book(id: String, node: Node = null) -> bool:
	if book_window == null:
		return false
	var rid := id.to_lower()
	var rec: Dictionary = interaction.records.record("book", rid)
	if rec.is_empty():
		return false
	if node == null and _player_in_combat():
		_toast(dialogue.gmst_text("sInventoryMessage4", "You cannot do that during combat.") if dialogue != null else "You cannot do that during combat.")
		return false
	_book_node = node
	book_window.open(rid, rec, node != null)
	var skill := int(rec.get("skill", -1))
	var read: Dictionary = state.player.get("books_read", {})
	if skill >= 0 and not read.has(rid) and character != null and not player_stats().is_empty():
		read[rid] = true
		state.player["books_read"] = read
		for m in character.skill_level_up(player_stats(), skill, "book"):
			_skill_message(m)
	return true

func _player_in_combat() -> bool:
	if ai == null:
		return false
	for n in ai.actor_nodes():
		for p in ai.ai_state(n).packages:
			if String(p.get("type", "")) == "combat" and String(p.get("target", "")) == "player":
				return true
	return false

func _on_book_closed(taken: bool) -> void:
	if taken and _book_node != null and is_instance_valid(_book_node):
		var snap: Dictionary = interaction.snapshot(_book_node)
		interaction.take_ref(snap)
	_book_node = null
	if item_window != null and item_window.visible:
		get_tree().paused = true             # powrót do ekwipunku (okno książki było nad nim)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	if scripts != null and not sid.is_empty():
		scripts.item_dropped(id, sid)            # World::PCDropped: zmienne skryptu z przedmiotem, OnPCDrop = 1
	return sid

func travel(dest: Dictionary) -> void:
	if scripts != null:
		scripts.cell_changed = true
	if ai != null:
		ai.store_positions()
	if interior.is_empty() and player != null:          # ostatnia pozycja zewnętrzna (najbliższy znacznik – więzienie)
		var lp := MWCoords.godot_to_mw(player.global_position)
		state.player["last_exterior"] = [lp.x, lp.y, lp.z]
	# Scene::changeToInteriorCell/changeToExteriorCell: fadeScreenOut(0.5), gdy była już wczytana komórka – zaciemnienie
	# postępuje w klatkach rysowanych przez ekran ładowania (długie ładowanie → czerń), po wczytaniu fadeScreenIn(0.5)
	var had_cell := not loaded.is_empty()
	if had_cell and fader != null:
		fader.fade_screen_out(0.5)
	if loading != null:                       # ekran ładowania obejmuje też odsłonięcie świata (_begin_reveal)
		loading.loading_on()
	for key in loaded.keys():
		events.cell_unloaded.emit(key)
		loaded[key].hide()                    # stara scena znika od razu (zwolnienie po klatce – queue_free)
		loaded[key].queue_free()
	loaded.clear()
	var t: Transform3D = dest["transform"]
	if String(dest.get("cell_key", "")) != "":
		interior = String(dest["cell_name"])
		if loading != null:                   # Scene::changeToInteriorCell: „Wczytywanie obszaru wewnętrznego”
			loading.set_label(L10n.text("LoadingInterior", "Loading Area"))
			loading.set_progress_range(1)
		_load(dest["cell_key"])
		if loading != null:
			loading.increase_progress()
		envr.set_interior(db.get_cell(dest["cell_key"]))
	else:
		interior = ""
		envr.set_interior({})
		player.global_position = t.origin
		_update_streaming(true)
	player.global_position = t.origin
	player.rotation.y = t.basis.get_euler().y
	player.velocity = Vector3.ZERO
	_place_on_ground_frames = 2              # World::adjustPosition: postawienie na podłożu po wczytaniu kolizji
	player.set_physics_process(false)
	player._fall_start = NAN
	_begin_reveal(had_cell)
	if loading != null:
		loading.loading_off()                 # zostaje zagnieżdżenie odsłonięcia – ekran do gotowości świata

# --- odsłonięcie świata po przejściu (gotowość pierwszej klatki) -------------------------------------------
## OpenMW wczytuje komórki synchronicznie i rysuje nową scenę od razu kompletną. W Godocie ta sama klatka może być
## jeszcze niegotowa: kolizje Jolt są widoczne dla zapytań dopiero po kroku fizyki (postawienie gracza na podłożu
## – World::adjustPosition), a potoki shaderów nowych materiałów kompilują się w trakcie rysowania. Ekran ładowania
## (zamrożona klatka) zostaje więc, dopóki: gracz nie stoi na podłożu i jedna klatka z nową kamerą nie zostanie
## narysowana bez nowych kompilacji potoków (gotowość wizualna). Mechanika i AI działają dalej normalnie; nawigacja
## i mapa lokalna mogą kończyć się po odsłonięciu. Limit REVEAL_MAX_FRAMES chroni przed zawieszeniem (ostrzeżenie).
const REVEAL_MAX_FRAMES := 240
var _reveal := {}                            # {"fade": bool, "frames": int, "pipelines": int, "drawn": int}

func _pipeline_compilations() -> int:
	var n := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(k)
	return n

func _begin_reveal(fade: bool) -> void:
	if loading == null:
		return
	if _reveal.is_empty():
		loading.loading_on()
		loading.hold()                       # zamrożona klatka zasłania scenę, także przy szybkim ładowaniu
		if not RenderingServer.frame_post_draw.is_connected(_on_reveal_frame_drawn):
			RenderingServer.frame_post_draw.connect(_on_reveal_frame_drawn)
	_reveal = {"fade": fade or bool(_reveal.get("fade", false)), "frames": 0, "pipelines": _pipeline_compilations(),
		"drawn": 0}

## Po każdej narysowanej klatce: czy po postawieniu gracza powstała klatka bez nowych kompilacji potoków.
func _on_reveal_frame_drawn() -> void:
	if _reveal.is_empty():
		return
	var p := _pipeline_compilations()
	if _place_on_ground_frames <= 0:
		_reveal.drawn = int(_reveal.drawn) + 1 if p == int(_reveal.pipelines) else 0
	_reveal.pipelines = p

## Wołane co klatkę przez ekran ładowania (PROCESS_MODE_ALWAYS) – działa także w pauzie (film, okna).
func _update_reveal() -> void:
	if _reveal.is_empty():
		return
	_reveal.frames = int(_reveal.frames) + 1
	if get_tree().paused:
		_place_on_ground_step()              # przejście w trybie GUI (np. podróż z rozmowy)
	var headless := DisplayServer.get_name() == "headless"
	var ready := _place_on_ground_frames <= 0 and (int(_reveal.drawn) >= 1 or headless)
	if not ready and int(_reveal.frames) < REVEAL_MAX_FRAMES:
		return
	if not ready:
		push_warning("Odsłonięcie świata po %d klatkach bez pełnej gotowości (potoki: %d)" % [_reveal.frames, _reveal.pipelines])
	var fade := bool(_reveal.fade)
	reveal_frames_last = int(_reveal.frames)
	_reveal = {}
	if loading != null:
		loading.loading_off()
	if fade and fader != null:
		fader.fade_screen_in(0.5)            # Scene: fadeScreenIn(0.5) po zmianie komórki

var reveal_frames_last := 0                  # testy i sonda: ile klatek trwało odsłonięcie

func is_revealing() -> bool:
	return not _reveal.is_empty()

var _place_on_ground_frames := 0

## Po teleporcie (drzwi, podróż, skrypt): gracz stawiany na podłożu pod celem (promień z wysokości), bez obrażeń
## od upadku – jak World::adjustPosition w OpenMW (cel drzwi bywa w schodach albo tuż pod/nad podłogą).
func _physics_process(_delta: float) -> void:
	_place_on_ground_step()

## Krok postawienia gracza (klatki fizyki; w pauzie – z odsłaniania świata, bo serwer fizyki kroczy dalej).
func _place_on_ground_step() -> void:
	if _place_on_ground_frames <= 0 or player == null:
		return
	_place_on_ground_frames -= 1
	if _place_on_ground_frames > 0:
		return
	var space := player.get_world_3d().direct_space_state
	var from: Vector3 = player.global_position + Vector3(0, 0.6, 0)   # nie wyżej – sufit, nadproże
	var q := PhysicsRayQueryParameters3D.create(from, player.global_position - Vector3(0, 6.0, 0))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and not player.swimming:
		player.global_position.y = float(hit.position.y) + 0.02
	player.velocity = Vector3.ZERO
	player._fall_start = NAN
	player.set_physics_process(true)
	# ActionTeleport: Chodzenie po wodzie usuwane, gdy w miejscu celu nie dałoby się go rzucić (za głęboko)
	_update_water_level()
	if magic != null and magic.magnitude_of(combat.player_fighter(), magic.FX_WATER_WALKING) > 0.0 \
			and not magic.water_walking_castable(combat.player_fighter()):
		magic._purge_effect(combat.player_fighter(), magic.FX_WATER_WALKING)

func _update_streaming(_force: bool) -> void:
	var g := MWCoords.cell_of(player.global_position)
	var want := {}
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var key := db.exterior_key(g + Vector2i(dx, dy))
			if not db.find_cell(key).is_empty():
				want[key] = true
	var todo := want.keys().filter(func(k): return not loaded.has(k))
	if not todo.is_empty() and loading != null:   # Scene::changeCellGrid: „Wczytywanie obszaru zewnętrznego”
		loading.loading_on()
		loading.set_label(L10n.text("LoadingExterior", "Loading Area"))
		loading.set_progress_range(todo.size())
	for key in todo:
		_load(key)
		if loading != null:
			loading.increase_progress()
	if not todo.is_empty() and loading != null:
		_begin_reveal(false)                  # nowe komórki pokazywane po gotowości pierwszej klatki (potoki shaderów)
		loading.loading_off()
	for key in loaded.keys():
		if not want.has(key):
			if ai != null:
				ai.store_positions(key)
			events.cell_unloaded.emit(key)
			loaded[key].queue_free()
			loaded.erase(key)
			if navmesh != null:
				navmesh.clear_cell(key)

func _load(key: String) -> void:
	if script_host != null:
		script_host.dirty = true
	if builder.actors != null:
		builder.actors.torches = use_torches(key)
	var n := builder.build_cell(key)
	if n:
		add_child(n)
		loaded[key] = n
		if navmesh != null:
			navmesh.bake_cell(key, n)          # siatka nawigacji AI (DetourNavigator) – w tle
		if doors != null:
			doors.resume_cell(key)             # Door::insertObject: dokończenie ruchu drzwi
		if not arg("screenshot").is_empty():
			# ujęcia porównawcze: aktorzy zamrożeni w pozycjach z danych – jak MCP zamraża aktorów w OpenMW
			for a in n.get_node("Refs").get_children():
				if a.has_meta("mw_actor"):
					a.set_physics_process(false)
		events.cell_loaded.emit(key)
		_apply_dead_poses()

## Poziom wody dla gracza (pływanie): komórka zewnętrzna albo wnętrze z wodą (water_height_m z konwertera).
## Etap 10: obszar mapy lokalnej (zewnętrze / wnętrze z NorthMarker), mgła wojny wokół gracza, odwiedzone
## nazwane komórki zewnętrzne (znaczniki mapy świata – WindowManager::changeCell → addVisitedLocation).
func _update_map(delta: float) -> void:
	if local_map == null or player == null or get_tree().paused:
		return
	var want := "ext" if interior.is_empty() else "int:" + interior.to_lower()
	if want != local_map.area:
		var refs: Node = null
		if loaded.has(want):
			refs = loaded[want].get_node_or_null("Refs")
		if want == "ext" or refs != null:
			local_map.set_area(want, refs)
	local_map.tick(delta, player.global_position)
	if interior.is_empty():
		var g := MWCoords.cell_of(player.global_position)
		var vk := "%d,%d" % [g.x, g.y]
		var visited: Dictionary = state.player.get("map_visited", {})
		if not visited.has(vk) and not String(db.get_cell(db.exterior_key(g)).get("name", "")).is_empty():
			visited[vk] = true
			state.player["map_visited"] = visited

## Etap 10: muzyka (walka, gdy któryś aktor w zasięgu walczy), dźwięki otoczenia regionu, pętle pogody,
## dźwięk pod wodą (głowa gracza pod powierzchnią).
func _update_sound_world(delta: float) -> void:
	if audio == null or player == null or get_tree().paused:
		return
	var fighting := false
	if ai != null:
		for n in ai.actor_nodes():
			if ai.in_combat(n) and combat.health(combat.fighter_of(n)) > 0.0:
				fighting = true
				break
	var dead: bool = combat != null and combat.is_dead(combat.player_fighter())
	if music != null:
		music.tick(delta, fighting, dead)
	if anim_sounds != null:
		anim_sounds.tick(delta)
	var exterior: bool = interior.is_empty() or bool(db.get_cell("int:" + interior.to_lower()).get("behave_like_exterior", false))
	audio.region_tick(delta, envr.regions.get(current_region.to_lower(), {}) if envr != null else {}, exterior)
	var cam := player.get_node_or_null("Camera3D") as Node3D
	var head_y: float = cam.global_position.y if cam != null else player.global_position.y + 1.6
	audio.ambient_tick(envr.weather if envr != null else "", exterior, head_y < float(player.water_level))
	if envr != null:
		envr.set_underwater(head_y < float(player.water_level))

func _player_step_sound(left: bool) -> String:
	if anim_sounds == null:
		return "FootBareLeft" if left else "FootBareRight"
	var cam := player.get_node_or_null("Camera3D") as Node3D
	var feet_in_water: bool = player.global_position.y < float(player.water_level)
	return anim_sounds.footstep(player, left, player.swimming, feet_in_water, player.is_on_floor())

func _update_water_level() -> void:
	if player == null or db == null:
		return
	var key := ("int:" + interior.to_lower()) if not interior.is_empty() else db.exterior_key(MWCoords.cell_of(player.global_position))
	player.water_level = cell_water_m(key)

## Poziom wody komórki w metrach Godota (−INF – bez wody): SetWaterLevel/ModWaterLevel (CellStore::setWaterLevel,
## zapisywane ze stanem gry w player.cell_water, jednostki MW), potem dane komórki.
## Komórka bez wody (Cell::hasWater) pozostaje bez wody także po SetWaterLevel (zapamiętany sam poziom).
func cell_water_m(key: String) -> float:
	var c := db.get_cell(key)
	if not c.get("has_water", false):
		return -INF
	var ov: Dictionary = state.player.get("cell_water", {})
	if ov.has(key):
		return float(ov[key]) / MWCoords.UNITS_PER_METER
	return float(c.get("water_height_m", 0.0))

## Nowy poziom wody wnętrza (jednostki MW): stan, płaszczyzna wody i poziom dla pływania gracza i aktorów.
func set_cell_water(key: String, level_mw: float) -> void:
	if not state.player.get("cell_water") is Dictionary:
		state.player["cell_water"] = {}
	state.player.cell_water[key] = level_mw
	var h := level_mw / MWCoords.UNITS_PER_METER
	if loaded.has(key):
		var root: Node = loaded[key]
		var w := root.get_node_or_null("Water") as Node3D
		if w != null:
			w.position.y = h
		var refs: Node = root.get_node_or_null("Refs")
		if refs != null and db.get_cell(key).get("has_water", false):
			for n in refs.get_children():
				if n.has_meta("mw_actor") and "water_level" in n:
					n.water_level = h
	_update_water_level()

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

## WindowManager::messageBox (MessageBoxManager::createMessageBox) – komunikat u dołu ekranu.
func _toast(text: String, _seconds := 3.0) -> void:
	if text.is_empty():
		return
	if message_boxes == null:
		message_boxes = preload("res://scripts/mw/mw_message_boxes.gd").new()
		message_boxes.name = "MessageBoxManager"
		message_boxes.main = self
		add_child(message_boxes)
	message_boxes.create(text)

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

## Ścieżka szybkiego zapisu bieżącej postaci (zgodność z dawnymi wywołaniami; F5 używa quick_save()).
func quicksave_path() -> String:
	if saves != null and saves.current != null:
		var q = saves.quick_slot(saves.current, "Quicksave")
		if q != null:
			return String(q.path)
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
		"created": Time.get_datetime_string_from_system(), "created_unix": Time.get_unix_time_from_system(), "game": "OpenMWGodot"}

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
func save_game(path: String, profile := {}) -> String:
	if player == null:
		return "the game is not running"
	capture_state()
	var header := save_header()
	if profile.is_empty():
		profile = save_profile(path.get_file().get_basename())
	header.merge(profile, true)
	header["character"] = String(header.get("player_name", ""))
	var err := GameStateScript.write_file(path, state.to_dict(header))
	if err != OK:
		return "error %d" % err
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
	state.player["chargen_flags"] = {"race": true, "class": true}    # MechanicsManager::playerLoaded
	migrate_window_settings_from_save()
	if scripts != null:
		scripts.inactive.clear()           # ScriptManager::clear przy wczytaniu: wyłączone po błędzie – znowu aktywne
	game_state = "running"
	_death_handled = false
	if player != null:
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.visible = true
	if mw_hud != null:
		mw_hud.visible = true
	time_played = float((d.get("header", {}) as Dictionary).get("time_played", 0.0))
	last_savegame = path
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
		# nazwa z rekordu komórki (kompilator zamienia nazwy w argumentach „c” na małe litery jak OpenMW;
		# findCell nie rozróżnia wielkości liter)
		var nm := String(db.find_cell(key).get("name", cell))
		travel({"cell_key": key, "cell_name": nm if not nm.is_empty() else cell, "transform": t})

## MessageBox ze skryptu: bez przycisków – komunikat; z przyciskami – okno (tryb menu), wybór → GetButtonPressed.
func show_message_box(text: String, buttons: Array, on_button := Callable(), engine := false) -> void:
	if buttons.is_empty():
		_toast(text)
		return
	if message_boxes == null:
		message_boxes = preload("res://scripts/mw/mw_message_boxes.gd").new()
		message_boxes.name = "MessageBoxManager"
		message_boxes.main = self
		add_child(message_boxes)
	var gui_mode: bool = get_tree().paused or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	var box: Control = message_boxes.create_interactive(text, buttons, func(idx: int):
		if not engine:
			scripts.button_pressed = idx
		msgbox = null
		var resume: bool = game_state == "running" and not (main_menu != null and main_menu.is_open())
		if resume:
			gui.update_visible()             # pauza i kursor wg stosu trybów GUI
		if on_button.is_valid():
			on_button.call(idx), gui_mode)
	msgbox = box.get_meta("layer")
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
var settings_window = null

func open_settings() -> void:
	if settings_window == null:
		settings_window = preload("res://scripts/mw/mw_settings_window.gd").new()
		settings_window.name = "SettingsWindow"
		settings_window.main = self
		add_child(settings_window)
	settings_window.open()

## Esc w grze (bez otwartych okien): menu główne w trybie gry (OpenMW GM_MainMenu – „Wróć”, zapis, wczytanie…).
func toggle_pause_menu() -> void:
	if main_menu == null:
		return
	if main_menu.is_open():
		if game_state == "running" and not save_dialog.visible and not confirm.is_open():
			close_main_menu()
	else:
		open_main_menu()


# --- start gry, menu główne, zapisy (etap: pełny start gry – OpenMW Engine::go, StateManager, MainMenu) ----------

const SavesScript := preload("res://scripts/mw/mw_saves.gd")
const UIStyle := preload("res://scripts/mw/mw_ui.gd")
const MONTH_GMST := ["sMonthMorningstar", "sMonthSunsdawn", "sMonthFirstseed", "sMonthRainshand", "sMonthSecondseed",
	"sMonthMidyear", "sMonthSunsheight", "sMonthLastseed", "sMonthHeartfire", "sMonthFrostfall", "sMonthSunsdusk",
	"sMonthEveningstar"]

## Stan jak MWBase::StateManager: "nogame" (menu główne bez gry), "running", "ended" (gracz nie żyje).
var game_state := "running"
var video = null                      # mw_video.gd – WindowManager::playVideo
var fader = null                      # mw_fader.gd – ScreenFader (FadeIn/FadeOut/FadeTo)
var loading = null                    # mw_loading_screen.gd – LoadingScreen
var main_menu = null                  # mw_main_menu.gd – MainMenu (także menu pauzy)
var save_dialog = null                # mw_save_dialog.gd – SaveGameDialog
var confirm = null                    # mw_confirm_dialog.gd – ConfirmationDialog
var count_dialog = null               # mw_count_dialog.gd – CountDialog (WindowManager::getCountDialog)

func get_count_dialog():
	if count_dialog == null or not is_instance_valid(count_dialog):
		count_dialog = preload("res://scripts/mw/mw_count_dialog.gd").new()
		count_dialog.name = "CountDialog"
		count_dialog.main = self
		add_child(count_dialog)
	return count_dialog
var saves = null                      # mw_saves.gd – CharacterManager
var time_played := 0.0                # StateManager::mTimePlayed (s)
var last_savegame := ""               # StateManager::mLastSavegame
var quit_requested := false
var startup_log: Array = []           # sondy/testy: kolejność kroków startu

func _data_roots() -> Array:
	var r := [data_dir]
	for b in MWModelCache.base_roots:
		if String(b) != data_dir:
			r.append(String(b))
	return r

func _setup_start_ui() -> void:
	video = preload("res://scripts/mw/mw_video.gd").new()
	video.name = "Video"
	video.main = self
	video.data_roots = _data_roots()
	add_child(video)
	fader = preload("res://scripts/mw/mw_fader.gd").new()
	fader.name = "ScreenFader"
	add_child(fader)
	loading = preload("res://scripts/mw/mw_loading_screen.gd").new()
	loading.name = "LoadingScreen"
	loading.main = self
	loading.data_roots = _data_roots()
	add_child(loading)
	loading.find_splash_screens()
	confirm = preload("res://scripts/mw/mw_confirm_dialog.gd").new()
	confirm.name = "ConfirmationDialog"
	confirm.main = self
	add_child(confirm)
	save_dialog = preload("res://scripts/mw/mw_save_dialog.gd").new()
	save_dialog.name = "SaveGameDialog"
	save_dialog.main = self
	add_child(save_dialog)
	main_menu = preload("res://scripts/mw/mw_main_menu.gd").new()
	main_menu.name = "MainMenu"
	main_menu.main = self
	main_menu.version_text = "OpenMWGodot %s" % String(ProjectSettings.get_setting("application/config/version", ""))
	add_child(main_menu)
	pause_menu = main_menu                 # tryb menu dla skryptów (MenuMode)
	var content := []
	var man = MWWorldDB._read_json(db.data_root.path_join("world/manifest.json"))
	if man is Dictionary:
		content = man.get("content", [])
	saves = SavesScript.new(saves_dir(), SavesScript.first_game_file(content))
	saves.max_quicksaves = int(settings.get("max_quicksaves", 1))
	saves.refresh()
	var lc := _read_saves_character()
	if not lc.is_empty():
		settings["saves_character"] = lc

## Start przez menu główne (OpenMW bez --skip-menu): gra z launchera bez wczytywania zapisu, wskazanego miejsca
## ani wymuszonej nowej gry; --menu=1 wymusza (sondy/testy), --skip-menu=1 pomija.
func menu_start_wanted() -> bool:
	if arg("menu") == "1":
		return true
	if not launched_by_launcher or arg("skip-menu", "0") == "1":
		return false
	return arg("load").is_empty() and arg("cell").is_empty() and arg("pos").is_empty() and arg("newgame").is_empty() \
		and arg("screenshot").is_empty() and arg("autotest-frames", "0") == "0"

## Wartość Fallback::Map (world/fallbacks.json gracza, brakujące – domyślne OpenMW).
func fallback(key: String) -> String:
	var fb = UIStyle._fallbacks()
	return String(fb.fb.get(key, "")) if fb != null else ""

func set_scene_visible(on: bool) -> void:
	if player != null:
		var cam := player.get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			cam.current = on or cam.current

## Brak gry: świat pusty, gracz i HUD ukryte (MWState::StateManager::State_NoGame).
func _enter_nogame() -> void:
	game_state = "nogame"
	if player != null:
		player.visible = false
		player.set_physics_process(false)
		player.process_mode = Node.PROCESS_MODE_DISABLED
	if mw_hud != null:
		mw_hud.visible = false
	if hud != null:
		hud.visible = false
	get_tree().paused = false

## Engine::go: logo firmy (Movies_Company_Logo) w trakcie wczytywania danych, potem menu główne, muzyka tytułowa
## (music/special/morrowind title.mp3) i logo Morrowinda (Movies_Morrowind_Logo, bez wyciszania dźwięków).
func _startup_sequence() -> void:
	var logo := fallback("Movies_Company_Logo")
	startup_log.append("company_logo:" + logo)
	if not logo.is_empty():
		await video.play(logo, true)
	open_main_menu()
	startup_log.append("main_menu")
	if music != null:
		music.play_title()
		startup_log.append("title_music:" + String(music.track))
	var mwlogo := fallback("Movies_Morrowind_Logo")
	startup_log.append("morrowind_logo:" + mwlogo)
	if not mwlogo.is_empty():
		await video.play(mwlogo, true, false)

func open_main_menu() -> void:
	if main_menu == null:
		return
	main_menu.open()
	if game_state != "nogame":
		get_tree().paused = true

func close_main_menu() -> void:
	if main_menu == null:
		return
	main_menu.close()
	if game_state == "running" and not (msgbox != null and is_instance_valid(msgbox) and msgbox.visible):
		get_tree().paused = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func settings_window_open() -> bool:
	return settings_window != null and settings_window.visible

func close_settings() -> void:
	if settings_window != null and settings_window.visible:
		settings_window.close()

func request_quit() -> void:
	quit_requested = true
	get_tree().quit(0)

func message_box(text: String) -> void:
	show_message_box(text, ["OK"], Callable(), true)

func message_count() -> int:
	return 1 if msgbox != null and is_instance_valid(msgbox) and msgbox.visible else 0

func month_name(m: int) -> String:
	var id: String = MONTH_GMST[clampi(m, 0, 11)]
	return dialogue.gmst_text(id, id.substr(6)) if dialogue != null else id.substr(6)

## StateManager::quickSave / saveGame warunek: gra trwa, CharGenState −1, WindowManager::isSavingAllowed (bez okien
## poza menu głównym i odpoczynkiem).
func saving_allowed() -> bool:
	if game_state != "running" or scripts == null or scripts.get_global("chargenstate") != -1.0:
		return false
	for w in [item_window, chargen, msgbox, dialogue_window, journal_window, trade_window, get("book_window"),
			get("map_window"), get("repair_window"), get("service_window"), get("alchemy_window"),
			get("enchanting_window"), get("spellcreation_window"), get("recharge_window"), get("levelup_window")]:
		if w != null and is_instance_valid(w) and w.visible and not (w.get("pinned_mode") == true):
			return false
	if menu_mode != null and menu_mode.visible:
		return false
	return true

## StateManager::cleanup – stan gry wyczyszczony przed nową grą / wczytaniem.
func cleanup() -> void:
	for key in loaded.keys():
		events.cell_unloaded.emit(key)
		loaded[key].free()
		if navmesh != null:
			navmesh.clear_cell(key)
	loaded.clear()
	state.from_dict({"format": GameStateScript.FORMAT, "version": GameStateScript.VERSION})
	if ai != null:
		ai.rt.clear()
		ai.graphs.clear()
	if doors != null:
		doors.moving.clear()
	if fader != null:
		fader.clear()
	for w in [item_window, dialogue_window, journal_window, trade_window, get("book_window"),
			get("map_window"), menu_mode, rest_window, get("repair_window"), get("service_window"), get("alchemy_window"),
			get("enchanting_window"), get("spellcreation_window"), get("recharge_window"), get("levelup_window")]:
		if w != null and is_instance_valid(w) and w.visible and w.has_method("close"):
			w.close()
	if msgbox != null and is_instance_valid(msgbox):
		msgbox.queue_free()
		msgbox = null
	if message_boxes != null:
		message_boxes.clear()
	if saves != null:
		saves.current = null
	time_played = 0.0
	last_savegame = ""
	_death_handled = false
	weapon_drawn = false
	magic_ready = false
	interior = ""

## StateManager::newGame: cleanup, skrypty startowe, World::startNewGame (komórka startowa, film
## Movies_New_Game – mw_intro.bik), stan „running”, fadeScreenOut(0) i fadeScreenIn(1).
func new_game() -> void:
	var from_menu := game_state == "nogame"
	cleanup()
	if loading != null:
		loading.loading_on()
		loading.set_label(L10n.text("InitializingData", "Initializing Data..."))
	state.seed = randi()
	_new_player_character()           # gracz istnieje od razu (rekord „player”, Npc::getNpcData)
	game_state = "running"
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	if mw_hud != null:
		mw_hud.visible = true
	var t := _start_transform()
	player.global_position = t.origin
	player.rotation.y = t.basis.get_euler().y
	player.velocity = Vector3.ZERO
	_update_streaming(true)
	if scripts != null and _scripted_chargen_wanted_menu():
		_start_scripted_chargen()
	else:
		if scripts != null:
			scripts.start_new_game()
		if bool(settings.get("character_creation", true)) and builder.actors.available():
			chargen.open(default_choice())
		else:
			_new_player_character()
	_init_player_items()
	if loading != null:
		loading.loading_off()
	startup_log.append("new_game" + (" (z menu)" if from_menu else ""))
	var intro := fallback("Movies_New_Game")
	startup_log.append("new_game_video:" + intro)
	if not intro.is_empty():
		if music != null:
			music.stop_music()          # bez muzyki tytułowej po filmie nowej gry
		await video.play(intro, true)
	if fader != null:
		fader.fade_screen_out(0)
		fader.fade_screen_in(1)
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _scripted_chargen_wanted_menu() -> bool:
	var mode := String(settings.get("chargen_mode", "morrowind"))
	if arg("newgame") in ["morrowind", "quick"]:
		mode = arg("newgame")
	return mode == "morrowind" and not scripts.script_rec("chargen").is_empty() and not scripts.script_rec("main").is_empty()

## Nazwa komórki do zapisu (World::getCellName: wnętrze, nazwa komórki zewnętrznej albo regionu).
func cell_name_for_save() -> String:
	if not interior.is_empty():
		return loc.plain(Loc.key("CELL", interior, "NAME"), interior) if loc != null else interior
	var c: Dictionary = db.get_cell(db.exterior_key(MWCoords.cell_of(player.global_position)))
	var n := String(c.get("name", ""))
	if not n.is_empty():
		return n
	var reg := String(c.get("region", current_region)).to_lower()
	return String(envr.regions.get(reg, {}).get("name", reg))

## Zrzut do zapisu jak StateManager::writeScreenshot (518×266, JPEG): sama scena, bez interfejsu.
func save_screenshot_b64() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var hidden := []
	for c in get_children():
		if c is CanvasLayer and c.visible:
			c.visible = false
			hidden.append(c)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	for c in hidden:
		c.visible = true
	if img == null or img.is_empty():
		return ""
	var want := 518.0 / 266.0
	var w := img.get_width()
	var h := img.get_height()
	if float(w) / h > want:
		var nw := int(h * want)
		img = img.get_region(Rect2i((w - nw) / 2, 0, nw, h))
	else:
		var nh := int(w / want)
		img = img.get_region(Rect2i(0, (h - nh) / 2, w, nh))
	img.resize(518, 266, Image.INTERPOLATE_BILINEAR)
	return Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.85))

## ESM::SavedGame: opis slotu w nagłówku zapisu.
func save_profile(description: String) -> Dictionary:
	var st := player_stats()
	var cls_id := String(st.get("class", ""))
	var cls_rec: Dictionary = builder.actors.record("class", cls_id.to_lower()) if not cls_id.is_empty() else {}
	var d: Dictionary = character.derived(st) if character != null and not st.is_empty() else {}
	return {"description": description, "player_name": String(st.get("name", "")),
		"player_level": int(st.get("level", 1)), "player_class_id": cls_id,
		"player_class_name": String(cls_rec.get("name", st.get("class_name", cls_id))),
		"cell_name": cell_name_for_save(),
		"game_time": {"day": int(scripts.get_global("day")) if scripts != null else 1,
			"month": int(scripts.get_global("month")) if scripts != null else 0,
			"year": int(scripts.get_global("year")) if scripts != null else 427,
			"hour": float(envr.game_hour) if envr != null else 9.0},
		"current_day": int(scripts.get_global("dayspassed")) if scripts != null else 0,
		"health": float(st.get("health", 0.0)),
		"max_health": float(d.health.modified) if d.has("health") else 0.0,
		"time_played": time_played, "screenshot": save_screenshot_b64()}

## StateManager::saveGame(description, slot): postać tworzona przy pierwszym zapisie, slot nadpisywany albo nowy.
func save_to_slot(description: String, slot = null) -> String:
	if not saving_allowed():
		message_box(L10n.text("SaveGameDenied", "The game cannot be saved right now."))
		return "saving is not allowed"
	var ch = saves.current
	if ch == null or bool(ch.get("legacy", false)):
		ch = saves.create_character(String(player_stats().get("name", "")))
		saves.current = ch
	var path: String = String(slot.path) if slot != null else saves.new_slot_path(ch, description)
	if loading != null:
		loading.loading_on()
		loading.set_label(L10n.text("SavingInProgress", "Saving..."), true)
	var err := save_game(path, save_profile(description))
	if loading != null:
		loading.loading_off()
	if not err.is_empty():
		show_message_box(L10n.text("SavingFailed", "Failed to save game") + ": " + err, ["OK"], Callable(), true)
		return err
	last_savegame = path
	_write_saves_character(String(ch.dir))
	saves.forget(path)
	saves.refresh()
	var f = saves.find_slot(path)
	if not f.is_empty():
		saves.current = f[0]
	return ""

## StateManager::quickSave: opis „Quicksave”, najstarszy z max quicksaves nadpisywany.
func quick_save() -> String:
	if not saving_allowed():
		message_box(L10n.text("SaveGameDenied", "The game cannot be saved right now."))
		return "saving is not allowed"
	return save_to_slot("Quicksave", saves.quick_slot(saves.current, "Quicksave"))

## StateManager::quickLoad: najnowszy zapis bieżącej postaci.
func quick_load() -> Array:
	var p: String = saves.latest(saves.current) if saves != null else ""
	if p.is_empty():
		return []
	return load_slot(saves.current, p)

## StateManager::loadGame(character, path): ekran ładowania, odczyt; błąd – stan wyczyszczony, menu główne
## i komunikat (printSavegameFormatError); oryginalny plik zostaje bez zmian.
func load_slot(ch, path: String) -> Array:
	if loading != null:
		loading.loading_on()
		loading.set_label(L10n.text("LoadingInProgress", "Loading Save Game"))
	var raw_ok := not GameStateScript.read_file(path).has("error")
	var prev_state := game_state
	if raw_ok:
		cleanup()
	var w := load_game(path)
	if not (not w.is_empty() and String(w[0]).begins_with("BŁĄD")):
		_begin_reveal(false)                 # świat z zapisu odsłaniany po gotowości pierwszej klatki
	if loading != null:
		loading.loading_off()
	if not w.is_empty() and String(w[0]).begins_with("BŁĄD"):
		if prev_state != "nogame" or raw_ok:
			cleanup()
		_enter_nogame()
		open_main_menu()
		show_message_box(L10n.text("LoadingFailed", "Failed to load saved game") + ": " + String(w[0]).substr(6), ["OK"], Callable(), true)
		return w
	var f = saves.find_slot(path) if saves != null else []
	saves.current = f[0] if not f.is_empty() and not bool(f[0].get("legacy", false)) else null
	if saves.current != null:
		_write_saves_character(String(saves.current.dir))
	if not w.is_empty():
		_toast("\n".join(w), 8.0)
	return w

func delete_save(ch, slot) -> void:
	var p := String(slot.path)
	saves.delete_slot(ch, slot)
	if last_savegame == p:                 # StateManager::deleteGame
		last_savegame = saves.latest(ch) if ch != null and saves.characters.has(ch) else ""

func _saves_character_file() -> String:
	return saves_dir().path_join("character.json")

func _read_saves_character() -> String:
	var p := _saves_character_file()
	if not FileAccess.file_exists(p):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return String(d.get("character", "")) if d is Dictionary else ""

## [Saves] character – ostatnio używana postać (wybierana w oknie wczytywania).
func _write_saves_character(dir: String) -> void:
	settings["saves_character"] = dir
	DirAccess.make_dir_recursive_absolute(saves_dir())
	var p := _saves_character_file()
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"character": dir}))
		f.close()
		DirAccess.rename_absolute(p + ".tmp", p)
