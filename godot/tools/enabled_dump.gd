extends SceneTree
## Etap 5 (regresja): stan włączenia obiektów ze skryptem lokalnym we wczytanych komórkach po N klatkach
## (skrypty startowe i lokalne działają), do porównania z RLF_ENABLED z OpenMW (lua/scripts/rlf_capture).
## godot --headless --path godot -s res://tools/enabled_dump.gd -- --data=DANE --pos=x,y,z --scripts=1
##     --frames=300 --out=wynik.json
## Wynik: {"cells": [...], "objects": [{"sid", "base", "script", "pos": [x, y, z], "enabled"}]} – tylko id i liczby.

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
	for i in int(_arg("frames", "300")):
		await process_frame
	var objs := []
	var cells := []
	for key in main.loaded:
		cells.append(String(key))
		for r in main.db.get_cell(String(key)).get("refs", []):
			var o: Dictionary = main.db.get_object(String(r.get("base", "")))
			var scr := String(o.get("script", ""))
			if scr.is_empty():
				continue
			var sid := String(r.get("sid", ""))
			var p: Array = (r.get("mw", {}) as Dictionary).get("pos", [0, 0, 0])
			objs.append({"sid": sid, "base": String(r.base).to_lower(), "script": scr.to_lower(),
				"pos": [float(p[0]), float(p[1]), float(p[2])], "enabled": main.state.is_enabled(sid)})
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"cells": cells, "objects": objs}, " "))
	f.close()
	print("ENABLED_DUMP ", objs.size())
	quit(0)
