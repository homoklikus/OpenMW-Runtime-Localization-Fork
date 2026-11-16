extends SceneTree
## Etap 5: MWScript – skrypty startowe („main”, SSCR), lokalne skrypty obiektów, zmienne globalne i lokalne,
## Enable/Disable (obiekt wyłączony na starcie jak w Raven Rock), OnActivate, dziennik, przedmioty,
## raport nieobsługiwanych funkcji, zapis i odczyt stanu skryptów.
## godot --headless --path godot -s res://tests/test_scripts.gd -- --data=WYNIKI(aktorzy)

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var vm = main.scripts
	var st = main.state
	check(vm != null and st.scripts.get("started", false), "skrypty startowe uruchomione przy nowej grze")
	check("main" in st.scripts.running and "synth_start" in st.scripts.running, "„main” i SSCR wśród skryptów globalnych (%s)" % [st.scripts.get("running")])
	await _frames(5)
	check(vm.get_global("SynthTicks") >= 5.0, "skrypt „main” co klatkę (SynthTicks = %s)" % vm.get_global("SynthTicks"))
	check(main.interaction.inventory.count_of("player", {}, "misc_synth_spoon") == 2, "player->AddItem z skryptu startowego")
	check(int(st.journal.get("synth_q", 0)) == 10, "Journal ustawia indeks zadania")
	check(vm.unsupported.has("synthunknownfunction"), "nieobsługiwana funkcja zgłoszona (%s)" % [vm.unsupported])
	var banner := _ref(main, "synth_banner")
	var bsid := String(banner.get_meta("mw_sid")) if banner else ""
	check(banner != null and not st.is_enabled(bsid) and _ref(main, "synth_banner").get_meta("mw_disabled", false),
			"obiekt wyłączony przez skrypt lokalny na starcie (jak Raven Rock)")
	# OnActivate przejmuje aktywację; dźwignia ustawia zmienną globalną → skrypt chorągwi ją włącza
	var lever := _ref(main, "synth_lever")
	check(lever != null and main.activate(lever), "aktywacja dźwigni (OnActivate)")
	await _frames(3)
	var lsid := String(lever.get_meta("mw_sid")) if is_instance_valid(lever) else String(_ref(main, "synth_lever").get_meta("mw_sid"))
	check(vm.get_global("SynthState") == 3.0 and float(st.scripts.locals.get(lsid, {}).get("uses", 0)) == 1.0,
			"OnActivate: zmienna globalna i lokalna (%s, %s)" % [vm.get_global("SynthState"), st.scripts.locals.get(lsid)])
	check(int(st.journal.get("synth_q", 0)) == 20 and st.is_enabled(bsid), "dziennik 20, chorągiew włączona przez swój skrypt")
	await _frames(2)
	check(int(st.scripts.locals.get(lsid, {}).get("uses", 0)) == 1, "OnActivate tylko w klatce aktywacji")
	# zapis → zmiany → odczyt
	var path := ProjectSettings.globalize_path("user://test_saves/skrypty.mwsave")
	check(main.save_game(path) == "", "zapis")
	st.globals["synthstate"] = 0.0
	st.journal["synth_q"] = 0
	st.scripts.running.erase("synth_start")
	var w: Array = main.load_game(path)
	check(not str(w).contains("BŁĄD") and vm.get_global("SynthState") == 3.0 and int(st.journal.synth_q) == 20
			and "synth_start" in st.scripts.running and float(st.scripts.locals[lsid]["uses"]) == 1.0,
			"odczyt: zmienne globalne, dziennik, skrypty globalne, zmienne lokalne")
	await _frames(3)
	check(st.is_enabled(bsid), "po odczycie chorągiew pozostaje włączona")
	var rep: Dictionary = vm.report()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": {"unsupported": rep.unsupported, "errors": rep.errors.keys().slice(0, 5)}}))
	quit(1 if failures.size() > 0 else 0)
