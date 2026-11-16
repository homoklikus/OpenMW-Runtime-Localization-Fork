extends SceneTree
## Diagnostyka skryptów (etap 9): uruchamia grę w komórce/pozycji z argumentów na N klatek ze skryptami i wypisuje
## raport MWScript (wywołania, częściowe, nieobsługiwane, błędy, działające skrypty globalne) oraz zmienne
## globalne z --globals=a,b. Tylko nazwy funkcji i liczby.
## godot --headless --path godot -s res://tools/scripts_probe.gd -- --data=DANE --cell=KOMÓRKA --scripts=1
##     [--frames=600] [--globals=chargenstate] [--out=raport.json]

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
	for i in int(_arg("frames", "600")):
		await process_frame
	var rep: Dictionary = main.scripts.report()
	var g := {}
	for name in _arg("globals").split(",", false):
		g[name] = main.state.globals.get(name.to_lower(), null)
	rep["globals"] = g
	rep["cell"] = main.interior
	rep["journal"] = main.state.journal
	print("PROBE ", JSON.stringify({"unsupported": rep.get("unsupported"), "partial": rep.get("partial"), "errors": rep.get("errors"),
		"running": rep.get("running"), "globals": g}))
	if not _arg("out").is_empty():
		var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, " "))
		f.close()
	quit(0)
