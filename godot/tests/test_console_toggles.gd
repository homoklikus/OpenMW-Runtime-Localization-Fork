extends SceneTree
## Etap 10 cz. 26 (P4): polecenia konsoli i funkcje MWScript dodane wg OpenMW 0.51 – ToggleSky, ToggleWater,
## ToggleWireframe, ToggleWorld, ToggleScripts, ToggleFullHelp (pełna pomoc w podpowiedziach: Owner, Owner Faction,
## Rank, Global, Script), User1–4, GetPCRunning, GetWindSpeed (0 we wnętrzu), Get/Set/ModPCVisionBonus (Night Eye,
## [0, 1]), PCGet3rdPerson (0 – widok pierwszoosobowy); zależne od nieprzeniesionych części – w raporcie „missing”.
## godot --headless --path godot -s res://tests/test_console_toggles.gd -- --data=WYNIKI(aktorzy) --scripts=0

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _last(con) -> String:
	var lines: PackedStringArray = String(con.plain_log).strip_edges().split("\n")
	return lines[lines.size() - 1] if lines.size() > 0 else ""

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

var vm

func call_(fname: String, args := []):
	return vm._call(null, fname, args.map(func(a): return ["num", a]), vm.Ctx.new())

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var con = main.console
	con.history_path = "user://test_console_toggles_history.txt"
	# --- przełączniki ---
	con.execute("ts")
	check(_last(con) == "Sky -> Off" and not main.envr.sky_enabled and main.envr.env.background_mode == Environment.BG_COLOR, "ToggleSky: niebo wyłączone, tło w kolorze mgły (%s)" % _last(con))
	con.execute("togglesky")
	check(_last(con) == "Sky -> On" and main.envr.env.background_mode == Environment.BG_SKY, "ToggleSky ponownie")
	con.execute("twa")
	var waters: Array = main.get_tree().root.find_children("Water", "MeshInstance3D", true, false).filter(func(n): return n.has_meta("mw_water"))
	check(_last(con) == "Water -> Off" and waters.all(func(n): return not n.visible), "ToggleWater: woda ukryta (%d płaszczyzn)" % waters.size())
	check(not main.envr.water_plane(10.0, 0.0).visible, "nowa płaszczyzna wody też ukryta")
	con.execute("twa")
	check(_last(con) == "Water -> On" and waters.all(func(n): return n.visible), "ToggleWater ponownie")
	con.execute("twf")
	check(_last(con) == "Wireframe Rendering -> On" and main.get_viewport().debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "ToggleWireframe")
	con.execute("twf")
	check(_last(con) == "Wireframe Rendering -> Off" and main.get_viewport().debug_draw == Viewport.DEBUG_DRAW_DISABLED, "ToggleWireframe ponownie")
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	var mask0 := cam.cull_mask
	con.execute("tw")
	check(_last(con) == "World -> Off" and cam.cull_mask == 0, "ToggleWorld: świat niewidoczny")
	con.execute("tw")
	check(_last(con) == "World -> On" and cam.cull_mask == mask0, "ToggleWorld ponownie")
	con.execute("togglescripts")
	check(_last(con) == "Scripts -> Off" and not main.scripts_enabled, "ToggleScripts")
	con.execute("togglescripts")
	check(main.scripts_enabled, "ToggleScripts ponownie")
	con.execute("tfow")
	check(_last(con) == "Fog of war -> Off" and not main.fog_of_war, "ToggleFogOfWar")
	con.execute("tfow")
	check(_last(con) == "Fog of war -> On" and main.fog_of_war, "ToggleFogOfWar ponownie")
	# --- listy poziomowane (AddToLev*/RemoveFromLev*) ---
	con.execute("AddToLevCreature synth_lev_creature synth_guard 5")
	var lc: Dictionary = main.builder.actors.record("leveledcreature", "synth_lev_creature")
	check(lc.items.size() == 2 and String(lc.items[1].id) == "synth_guard" and int(lc.items[1].level) == 5, "AddToLevCreature: pozycja dopisana (%s)" % [lc.items])
	con.execute("AddToLevCreature synth_lev_creature synth_guard 5")
	check(main.builder.actors.record("leveledcreature", "synth_lev_creature").items.size() == 2, "bez duplikatu id + poziom")
	check(main.state.to_dict({}).created.leveledcreature.has("synth_lev_creature"), "zmieniona lista w zapisie gry (overrideRecord)")
	con.execute("RemoveFromLevCreature synth_lev_creature synth_guard -1")
	check(main.builder.actors.record("leveledcreature", "synth_lev_creature").items.size() == 1, "RemoveFromLevCreature −1 – wszystkie pozycje id")
	con.execute("AddToLevItem l_synth_helm synth_sword 10")
	con.execute("RemoveFromLevItem l_synth_helm synth_helm 2")
	var li: Array = main.builder.actors.record("leveleditem", "l_synth_helm").items
	check(li.size() == 3, "RemoveFromLevItem z innym poziomem – bez zmian (%s)" % [li])
	con.execute("RemoveFromLevItem l_synth_helm synth_helm 1")
	li = main.builder.actors.record("leveleditem", "l_synth_helm").items
	check(li.size() == 2 and li.all(func(x): return String(x.id) != "synth_helm"), "RemoveFromLevItem – usunięta pozycja z poziomem 1")
	# --- przełączniki debugowe i informacje o referencji ---
	con.execute("tpg")
	check(_last(con) == "Path Grid rendering -> On" and main.debug_render.find_child("Pathgrid", false, false) != null, "TogglePathGrid: romby siatki ścieżek")
	con.execute("tpg")
	check(_last(con) == "Path Grid Rendering -> Off" and main.debug_render.get_child_count() == 0, "TogglePathGrid ponownie")
	con.execute("tb")
	check(_last(con) == "Border Rendering -> On" and main.debug_render.find_child("CellBorder", false, false) != null, "ToggleBorders: granice komórek")
	con.execute("tb")
	con.execute("tcb")
	check(_last(con) == "Collision Mesh Rendering -> On" and main.debug_render.find_child("Collision", false, false) != null, "ToggleCollisionBoxes")
	con.execute("tcg")
	check(_last(con) == "Collision Mesh Rendering -> Off", "ToggleCollisionGrid – ten sam tryb (Render_CollisionDebug)")
	var villager := _ref(main, "synth_villager")
	con.set_selected(villager)
	con.execute("ori")
	var txt := String(con.plain_log)
	check(txt.contains("RefID: synth_villager") and txt.contains("RefNum: ") and txt.contains("Coordinates: ") and txt.contains("Report time: "), "ORI/BetaComment: informacje o referencji")
	con.set_selected(villager)
	con.execute("testcells")
	check(_last(con) == "Use TestCells from the main menu, when there is no active game session.", "TestCells w trakcie gry – komunikat")
	con.execute("t3d")
	check(_last(con).begins_with("Attempted to load models for "), "TestModels (%s)" % _last(con))
	con.execute("menutest 4")
	check(main.menu_mode.is_pinned("inventory"), "MenuTest 4 – przypięty ekwipunek")
	main.menu_mode.toggle_pin("inventory")
	con.execute("user2")
	check(_last(con) == "user2: not in use", "User2")
	# --- pełna pomoc ---
	var spoon: Node = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_sid", "")) == "mwg_actors.esp#9014":
				spoon = n
	check(spoon != null, "łyżka kupca w świecie")
	var tt = main.tooltips
	check(not String(tt.focus_info(spoon).get("extra", "")).contains("Owner"), "bez pełnej pomocy – bez właściciela")
	con.execute("tfh")
	check(_last(con) == "Full help -> On" and main.full_help, "ToggleFullHelp")
	check(String(tt.focus_info(spoon).get("extra", "")).contains("Owner: synth_trader"), "pełna pomoc: Owner (%s)" % tt.focus_info(spoon).get("extra", ""))
	var npc := _ref(main, "synth_villager")
	var scr := String(main.builder.actors.record("npc", "synth_villager").get("script", ""))
	if npc != null and not scr.is_empty():
		check(String(tt.focus_info(npc).get("extra", "")) == "\nScript: " + scr, "pełna pomoc NPC: tylko skrypt (%s)" % tt.focus_info(npc).get("extra", ""))
	check(tt.cellref_string({"owner": "x", "faction": "synth guild", "faction_rank": 1, "global": "g"})
		== "\nOwner: x\nOwner Faction: Gildia Testowa\nRank: Czeladnik\nGlobal: g", "getCellRefString: właściciel, frakcja, ranga, globalna")
	con.execute("tfh")
	# --- funkcje ---
	vm = main.scripts
	var sc = self
	check(float(sc.call_("getpcrunning", [])) == 0.0, "GetPCRunning – stoi")
	main.player.want_run = true
	main.player.move_input = Vector2(0, -1)
	check(float(sc.call_("getpcrunning", [])) == 1.0, "GetPCRunning – bieg")
	main.player.move_input = Vector2.ZERO
	main.player.want_run = false
	check(float(sc.call_("getwindspeed", [])) == float(main.envr.wm.result.get("wind_speed", -1.0)), "GetWindSpeed z wyniku pogody")
	check(float(sc.call_("getpcvisionbonus", [])) == 0.0, "GetPCVisionBonus bez Night Eye")
	sc.call_("setpcvisionbonus", [0.5])
	check(is_equal_approx(float(sc.call_("getpcvisionbonus", [])), 0.5), "SetPCVisionBonus 0,5 (%s)" % sc.call_("getpcvisionbonus", []))
	sc.call_("modpcvisionbonus", [0.75])
	check(is_equal_approx(float(sc.call_("getpcvisionbonus", [])), 1.0), "ModPCVisionBonus – ograniczenie do 1")
	sc.call_("modpcvisionbonus", [-2.0])
	check(is_equal_approx(float(sc.call_("getpcvisionbonus", [])), 0.0), "ModPCVisionBonus – ograniczenie do 0")
	check(float(sc.call_("pcget3rdperson", [])) == 0.0, "PCGet3rdPerson = 0 (pierwsza osoba)")
	sc.call_("pcforce3rdperson", [])
	check(float(sc.call_("pcget3rdperson", [])) == 1.0 and not main.player_camera().is_first_person(),
		"PCForce3rdPerson – trzecia osoba, PCGet3rdPerson = 1")
	sc.call_("pcforce1stperson", [])
	check(float(sc.call_("pcget3rdperson", [])) == 0.0 and main.player_camera().is_first_person(), "PCForce1stPerson")
	# --- ustawienia: [General] anisotropy, [Water] refraction / sunlight scattering / wobbly shores ---
	var ENV := preload("res://scripts/mw/mw_environment.gd")
	check(main.get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_4X, "anisotropy 4 (domyślnie) → 4×")
	main.settings["anisotropy"] = 16
	main.apply_live_settings()
	check(main.get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_16X, "anisotropy 16 → 16×")
	main.settings["anisotropy"] = 0
	main.apply_live_settings()
	check(main.get_viewport().anisotropic_filtering_level == Viewport.ANISOTROPY_DISABLED, "anisotropy 0 – wyłączone")
	check(not bool(ENV.water_features.refraction) and bool(ENV.water_features.scattering) and bool(ENV.water_features.wobbly),
		"domyślnie jak settings-default.cfg: refraction = false, sunlight scattering = true, wobbly shores = true")
	main.settings["water_refraction"] = true
	main.apply_live_settings()
	var wm: ShaderMaterial = ENV._water_material()
	check(bool(ENV.water_features.refraction) and bool(wm.get_shader_parameter("refraction_on")), "refraction – parametr shadera wody")
	main.settings["sunlight_scattering"] = false
	main.apply_live_settings()
	check(not bool(wm.get_shader_parameter("scattering_on")), "sunlight scattering wyłączone")
	# --- [Shaders] maximum light distance / light fade start / minimum interior brightness ---
	var ol := OmniLight3D.new()
	MWCellBuilder.configure_light(ol, 256.0, Color.WHITE)
	var upm := MWCoords.UNITS_PER_METER
	check(ol.distance_fade_enabled and is_equal_approx(ol.distance_fade_begin, 8192.0 * 0.85 / upm)
		and is_equal_approx(ol.distance_fade_begin + ol.distance_fade_length, 8192.0 / upm), "wygaszanie świateł 0,85 × 8192 … 8192 j.")
	main.settings["maximum_light_distance"] = 0.0
	main.apply_live_settings()
	var ol2 := OmniLight3D.new()
	MWCellBuilder.configure_light(ol2, 256.0, Color.WHITE)
	check(not ol2.distance_fade_enabled, "maximum light distance 0 – bez wygaszania")
	main.settings["minimum_interior_brightness"] = 0.2
	main.apply_live_settings()
	var amb: Color = ENV.interior_ambient(Color(0, 0, 0))
	check(is_equal_approx(amb.r, 0.2), "minimum interior brightness 0,2 (%s)" % amb)
	ol.free()
	ol2.free()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
