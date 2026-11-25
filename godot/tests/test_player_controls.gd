extends SceneTree
## Etap 10 cz. 26: akcje sterowania OpenMW 0.51 – domyślne klawisze (BindingsManager::loadKeyDefaults: Aktywacja
## Spacja, Skok E, AlwaysRun Caps Lock, AutoMove Q, Cycle - = [ ], Screenshot F12), kolejność listy (getActionKeySorting),
## AlwaysRun (playercontrols.lua: bieg = Run ≠ alwaysRun, zapis ustawienia), AutoMove (ruch do przodu do pierwszego
## ruchu przód/tył), Cycle Weapon (InventoryWindow::cycle) i Cycle Spell (SpellWindow::cycle), blokada w trybie GUI.
## godot --headless --path godot -s res://tests/test_player_controls.gd -- --data=WYNIKI(aktorzy) --scripts=0

const MWInput := preload("res://scripts/mw/mw_input.gd")
const EQ := preload("res://scripts/mw/mw_equipment.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _press(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e

func _right(main) -> String:
	return String((main._equipment().get(str(EQ.SLOT_CARRIED_RIGHT), {}) as Dictionary).get("id", ""))

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	# --- domyślne klawisze ---
	var want := {"activate": KEY_SPACE, "jump": KEY_E, "always_run": KEY_CAPSLOCK, "auto_move": KEY_Q,
		"cycle_spell_left": KEY_MINUS, "cycle_spell_right": KEY_EQUAL, "cycle_weapon_left": KEY_BRACKETLEFT,
		"cycle_weapon_right": KEY_BRACKETRIGHT, "screenshot": KEY_F12, "run": KEY_SHIFT, "sneak": KEY_CTRL}
	for a in want:
		check(MWInput.default_code(a) == int(want[a]), "domyślny klawisz %s (%d)" % [a, MWInput.default_code(a)])
		check(InputMap.has_action(a) and MWInput.binding_code(a) == int(want[a]), "przypisanie %s w InputMap (%d)" % [a, MWInput.binding_code(a)])
	var order: Array = MWInput.CONFIGURABLE.map(func(x): return String(x[0]))
	check(order.slice(0, 17) == ["move_forward", "move_back", "move_left", "move_right", "run", "always_run", "sneak",
		"activate", "attack", "ready_weapon", "ready_magic", "cycle_spell_left", "cycle_spell_right",
		"cycle_weapon_left", "cycle_weapon_right", "auto_move", "jump"], "kolejność getActionKeySorting (%s)" % [order.slice(0, 17)])
	check(order.find("screenshot") == order.find("toggle_hud") + 1, "Screenshot po ToggleHUD")
	var pc = main.player.controller
	var a = main.player
	# --- AlwaysRun ---
	main.settings.erase("always_run")
	pc.always_run = false
	main._unhandled_input(_press("always_run"))
	check(pc.always_run and bool(main.settings.get("always_run", false)), "AlwaysRun włącza bieg na stałe")
	check(bool(main._load_ingame_settings().get("always_run", false)), "AlwaysRun zapisany w ustawieniach (jak alwaysRun w SettingsOMWControls)")
	pc.control(a, 0.016)
	check(a.want_run, "bez Shift – bieg (Run ≠ alwaysRun)")
	Input.action_press("run")
	pc.control(a, 0.016)
	check(not a.want_run, "z Shift – chód")
	Input.action_release("run")
	main._unhandled_input(_press("always_run"))
	check(not pc.always_run, "AlwaysRun ponownie – wyłączony")
	# --- AutoMove ---
	main._unhandled_input(_press("auto_move"))
	check(pc.auto_move, "AutoMove włączony")
	pc.control(a, 0.016)
	check(a.move_input.y == -1.0, "AutoMove: ruch do przodu (%s)" % a.move_input)
	Input.action_press("move_left")
	pc.control(a, 0.016)
	check(a.move_input.y == -1.0 and a.move_input.x < 0.0 and pc.auto_move, "ruch w bok nie wyłącza AutoMove")
	Input.action_release("move_left")
	Input.action_press("move_back")
	pc.control(a, 0.016)
	check(not pc.auto_move and a.move_input.y > 0.0, "ruch przód/tył wyłącza AutoMove")
	Input.action_release("move_back")
	pc.control(a, 0.016)
	check(a.move_input == Vector2.ZERO, "po wyłączeniu AutoMove – stoi")
	# --- Cycle Weapon ---
	var inv = main.interaction.inventory
	for w in ["synth_sword", "synth_cg_dagger", "synth_bow", "synth_arrow"]:
		inv.add("player", {}, w, 1)
	inv.add("player", {}, "misc_synth_spoon", 1)
	var order_w := []
	var items: Array = main.menu_mode.sorted_items("player")
	for it in items:
		it["stype"] = 2
	items.sort_custom(main.menu_mode.item_less)
	for it in items:
		if String(it.kind) == "weapon" and int(main.item_slots(String(it.id))[0]) == EQ.SLOT_CARRIED_RIGHT:
			order_w.append(String(it.id))
	check(order_w.size() >= 3 and not order_w.has("synth_arrow"), "bronie prawej ręki bez strzał (%s)" % [order_w])
	main.unequip_slot(EQ.SLOT_CARRIED_RIGHT)
	main.cycle_weapon(true)
	check(_right(main) == order_w[0], "bez broni – pierwsza broń (%s)" % _right(main))
	main.cycle_weapon(true)
	check(_right(main) == order_w[1], "następna broń (%s)" % _right(main))
	main.cycle_weapon(false)
	check(_right(main) == order_w[0], "poprzednia broń (%s)" % _right(main))
	main.cycle_weapon(false)
	check(_right(main) == order_w[-1], "z pierwszej do ostatniej (zawinięcie) (%s)" % _right(main))
	# tryb GUI – WindowManager::cycleWeapon: tylko bez trybu GUI
	main.menu_mode.open()
	var before := _right(main)
	main.cycle_weapon(true)
	check(_right(main) == before, "w trybie menu bez zmiany broni")
	main.menu_mode.close()
	await process_frame
	# --- Cycle Spell ---
	var st: Dictionary = main.player_stats()
	for sid in ["synth_bolt", "synth_heal", "synth_power"]:
		if not sid in st.spells:
			st.spells.append(sid)
	st.erase("selected_magic")
	var rows := []
	for g in main.menu_mode.spell_model():
		rows.append_array(g.rows)
	main.cycle_spell(true)
	check(main.selected_magic().get("id", "") == String(rows[0].id), "bez wyboru – pierwsza pozycja SpellModel (%s)" % [main.selected_magic()])
	main.cycle_spell(true)
	check(main.selected_magic().get("id", "") == String(rows[1].id), "następny czar (%s)" % [main.selected_magic()])
	main.cycle_spell(false)
	main.cycle_spell(false)
	check(main.selected_magic().get("id", "") == String(rows[-1].id), "zawinięcie do ostatniej pozycji (%s)" % [main.selected_magic()])
	# wilkołak – sWerewolfRefusal, bez zmiany
	st["werewolf"] = true
	var s0: Dictionary = main.selected_magic().duplicate()
	main.cycle_spell(true)
	check(main.selected_magic() == s0, "wilkołak: bez zmiany czaru")
	st["werewolf"] = false
	# --- zrzut ekranu: katalog i nazwa ---
	check(main.screenshots_dir().ends_with("screenshots"), "katalog zrzutów „screenshots” (%s)" % main.screenshots_dir())
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
