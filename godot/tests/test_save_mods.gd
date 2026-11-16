extends SceneTree
## Etap 9: zapis gry przy zmianach modów – faza save (zestaw A: esm + patch), faza add (doszła wtyczka patch2),
## faza missing (brak wtyczki patch): ostrzeżenia zgodności, stan obiektów i dziennik zachowane, obiekty brakującej
## wtyczki nie znikają z zapisu po ponownym zapisie (bez cichego usuwania).
## godot --headless --path godot -s res://tests/test_save_mods.gd -- --data=DANE --project=KATALOG --phase=save|add|missing

const SID := "mwg_synthtown_patch.esp#1"

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var path := _arg("project").path_join("mods_test.mwsave")
	var phase := _arg("phase", "save")
	var w: Array = []
	match phase:
		"save":
			main.state.set_enabled(SID, false)
			main.state.journal["synth_quest"] = 20
			main.state.globals["synthstate"] = 5.0
			check(main.save_game(path) == "", "zapis z zestawem A")
		"add":
			w = main.load_game(path)
			check(w.any(func(x): return String(x).contains("nowa wtyczka mwg_synthtown_patch2.esp")), "ostrzeżenie: nowa wtyczka (%s)" % [w])
			check(not main.state.is_enabled(SID), "stan obiektu z pluginu zachowany po dodaniu wtyczki")
			check(int(main.state.journal.get("synth_quest", 0)) == 20 and float(main.state.globals.get("synthstate", 0)) == 5.0, "dziennik i zmienne zachowane")
			check(main.save_game(path) == "", "ponowny zapis z zestawem B")
		"missing":
			w = main.load_game(path)
			check(w.any(func(x): return String(x).contains("brak wtyczki mwg_synthtown_patch.esp")), "ostrzeżenie: brak wtyczki (%s)" % [w])
			check(main.state.refs.has(SID), "obiekt brakującej wtyczki zostaje w stanie gry")
			check(main.save_game(path) == "", "zapis bez wtyczki")
			main.state.refs.clear()
			main.load_game(path)
			check(main.state.refs.has(SID) and not main.state.is_enabled(SID), "po ponownym zapisie i odczycie – nadal zachowany (bez cichego usuwania)")
			check(int(main.state.journal.get("synth_quest", 0)) == 20, "dziennik zachowany")
	print("RESULT ", JSON.stringify({"phase": phase, "checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
