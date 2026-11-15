extends SceneTree
## Launcher: rozpoznawanie instalacji, Python, konwersja w tle z postępem, gotowość danych, ustawienia.
## godot --headless --path godot -s res://tests/test_launcher.gd -- --install=DIR_Z_DATA_FILES --out=KATALOG

var failures: Array[String] = []
var checks := 0
var report := {}

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var inst_dir := arg("install")   # katalog „gry”: zawiera „Data Files” z syntetycznym ESM nazwanym jak w grze
	var out := arg("out")
	var L := MWLauncher.new()
	var c := MWLauncher.classify(inst_dir)
	check(c["kind"] == "morrowind" and c["ok"], "rozpoznano katalog gry (%s)" % str(c))
	check(not MWLauncher.classify("/nie/istnieje")["ok"], "odrzucono złą ścieżkę")
	var py := L.check_python()
	report["python"] = py
	check(py["ok"], "Python + numpy + Pillow dostępne")
	var stages := {}
	L.progress.connect(func(st, d, t): stages[st] = [d, t])
	var res := {}
	L.finished.connect(func(ok, info): res["ok"] = ok; res["info"] = info)
	var err := L.start(c, out, {"cells": ["Synthville"], "jobs": 1})
	check(err == OK, "konwerter uruchomiony (%s)" % error_string(err))
	var t0 := Time.get_ticks_msec()
	while L.is_running() and Time.get_ticks_msec() - t0 < 120000:
		L.poll()
		await process_frame
	report["stages"] = stages
	report["result"] = res
	check(res.get("ok", false), "konwersja zakończona (zdarzenie done)")
	check(stages.has("models") and stages["models"][0] == stages["models"][1] and stages["models"][1] > 0, "postęp modeli do 100%")
	check(MWLauncher.data_ready(out), "dane gotowe do gry")
	MWLauncher.save_settings({"data_root": out, "install_path": inst_dir})
	check(MWLauncher.load_settings().get("data_root") == out, "ustawienia zapisane")
	var args := L.build_args(c, out, {"cells": ["Balmora"], "grid_range": "-4,-4,-1,-1", "bake": true})
	check(args.has("--morrowind") and args.has("--grid-range=-4,-4,-1,-1") and args.has("--bake-godot"), "argumenty dla Balmory z wypiekaniem")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
