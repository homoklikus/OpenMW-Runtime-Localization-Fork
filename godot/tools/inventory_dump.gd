extends SceneTree
## Diagnostyka inwentarzy (etap 3): zawartość NPC/pojemników z listami poziomowanymi dla kilku ziaren,
## ekwipunek NPC. godot --headless --path godot -s res://tools/inventory_dump.gd -- --data=… --ids=a,b --seeds=5 --level=1

func arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return def

func _init() -> void:
	var data := arg("data")
	var db := MWWorldDB.new(data)
	var models := MWModelCache.new(data)
	var av = load("res://scripts/mw/mw_actor_visual.gd").new(db, models)
	var st = load("res://scripts/mw/mw_game_state.gd").new()
	var inv = load("res://scripts/mw/mw_inventory.gd").new(av, st)
	inv.player_level = int(arg("level", "1"))
	var eq = load("res://scripts/mw/mw_equipment.gd").new(av)
	var out := {}
	for id in arg("ids").split(",", false):
		var rec: Dictionary = av.record("npc", id)
		var kind := "npc"
		if rec.is_empty():
			rec = av.record("container", id)
			kind = "container"
		if rec.is_empty():
			out[id] = "brak rekordu"
			continue
		var runs := []
		for s in int(arg("seeds", "5")):
			st.seed = s
			var items: Array = inv.base_contents(rec, "dump#" + id)
			var row := {"items": items.map(func(e): return "%s×%d" % [e.id, e.count])}
			if kind == "npc":
				var slots: Dictionary = eq.auto_equip(rec, items, false)
				var ks := slots.keys()
				ks.sort()
				row["slots"] = ks.map(func(k): return "%d:%s" % [k, slots[k].id])
			runs.append(row)
		out[id] = runs
	print("MWGODOT_INV ", JSON.stringify(out))
	quit()
