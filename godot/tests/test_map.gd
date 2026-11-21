extends SceneTree
## Etap 10 – mapa: segmenty mapy lokalnej (komórka zewnętrzna = segment, wnętrze obrócone wg NorthMarker),
## mgła wojny (odkrywanie wokół gracza jak LocalMap::updatePlayer, zapis i odczyt), okno mapy (lokalna/świat,
## pauza, tryb menu), mapa świata z konwertera (world/map), odwiedzone nazwane komórki i ShowMap.
## godot --headless --path godot -s res://tests/test_map.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

const UI := preload("res://scripts/mw/mw_ui.gd")
var failures: Array[String] = []
var checks := 0
var report := {}

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(10)
	var lm = main.local_map
	check(lm != null and lm.area == "ext", "mapa lokalna – obszar zewnętrzny")
	var pp: Vector3 = main.player.global_position
	var L: Dictionary = lm.locate(pp)
	var g := MWCoords.cell_of(pp)
	check(L.seg.x == g.x and L.seg.y == -(g.y + 1), "segment = komórka (oś y w dół) %s / %s" % [L.seg, g])
	var mw := MWCoords.godot_to_mw(pp)
	var exp_uv := Vector2(fposmod(mw.x, 8192.0) / 8192.0, 1.0 - fposmod(mw.y, 8192.0) / 8192.0)
	check(L.uv.distance_to(exp_uv) < 0.01, "położenie w segmencie (%s ≈ %s)" % [L.uv, exp_uv])
	# mgła (odkrywanie co 0,2 s w _process – w teście wywołanie bezpośrednie, niezależne od tempa klatek)
	lm.update_player(pp)
	check(lm.explored(L.seg, L.uv), "mgła odkryta pod graczem")
	var far_uv := Vector2(fmod(L.uv.x + 0.5, 1.0), fmod(L.uv.y + 0.5, 1.0))
	check(not lm.explored(L.seg, far_uv), "pół segmentu dalej – nadal mgła")
	check((main.state.player.get("map_fog", {}) as Dictionary).has(lm.seg_key(L.seg)), "mgła w stanie gry (zapis)")
	var saved_fog: PackedByteArray = lm.fog(L.seg).duplicate()
	lm.reset_fog()
	check(lm.fog(L.seg) == saved_fog, "mgła odtworzona ze stanu gry")
	# wnętrze obrócone wg NorthMarker: kierunek „na północ” znacznika = góra mapy
	var fake := Node3D.new()
	root.add_child(fake)
	var nm := Node3D.new()
	nm.set_meta("mw_base", "NorthMarker")
	fake.add_child(nm)
	nm.rotation.y = deg_to_rad(90.0)
	var other := Node3D.new()
	other.position = Vector3(30, 0, -10)
	fake.add_child(other)
	await _frames(1)
	lm.set_area("int:test", fake)
	var north: Vector3 = nm.global_transform.basis * Vector3(0, 0, -1)
	var q: Vector2 = lm.to_q(north)
	check(q.distance_to(Vector2(0, -1)) < 0.01, "wnętrze: północ znacznika = góra mapy (%s)" % q)
	check(lm.seg_max.x >= 0 and lm.seg_max.y >= 0, "wnętrze: zakres segmentów")
	lm.set_area("ext")
	fake.queue_free()
	# odwiedzone miejsca
	var visited: Dictionary = main.state.player.get("map_visited", {})
	check(visited.has("%d,%d" % [g.x, g.y]), "odwiedzona nazwana komórka (%s)" % str(visited))
	# okno mapy
	var mwin = main.map_window
	mwin.open()
	await _frames(3)
	check(mwin.visible and get_root().get_tree().paused and main.script_host.menu_mode(), "okno mapy: widoczne, pauza, tryb menu")
	check(not mwin.world_mode, "domyślnie mapa lokalna")
	check(lm.rendered >= 0, "segmenty zlecone do narysowania")
	check(is_equal_approx(mwin._seg_px, 512.0 * UI.ui_scale()), "okno mapy: segment 512 px ([Map] local map widget size, zoom 1) – %s" % mwin._seg_px)
	if main.mw_hud != null:
		main.mw_hud.update_minimap()
		var fogs: Array = main.mw_hud.minimap_tiles.find_children("Fog", "TextureRect", true, false)
		check(fogs.size() > 0 and fogs.all(func(f): return f.texture == null), "minimapa HUD bez mgły (local map hud fog of war = false)")
	# znaczniki drzwi: wszystkie drzwi z celem (także pod mgłą), podpowiedź tylko w odkrytej części
	var doors := 0
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs != null:
			for n in refs.get_children():
				if not MWTravel.door_destination(n).is_empty():
					doors += 1
	var dms: Array = mwin.find_children("DoorMarker", "", true, false)
	check(doors > 0 and dms.size() == doors and mwin.door_markers.size() == doors, "znaczniki wszystkich drzwi z celem (%d / %d)" % [dms.size(), doors])
	var tips_ok := true
	for dm in dms:
		var dl: Dictionary = lm.locate(mwin.view_to_world(dm.position + dm.size / 2.0))
		if dm.has_meta("mw_tip") != lm.explored(dl.seg, dl.uv):
			tips_ok = false
	check(tips_ok, "podpowiedź znacznika drzwi tylko w odkrytej części mapy")
	mwin.set_world(true)
	await _frames(2)
	check(mwin._world_tex != null and int(mwin._world_info.get("cell_px", 0)) == 18, "mapa świata z konwertera (18 px na komórkę)")
	var names: Array = mwin.place_markers.map(func(e): return e[0])
	check("Synthville" in names, "znacznik odwiedzonego miejsca (%s)" % str(names))
	var px: Vector2 = mwin._world_px(Vector3(0.5 * 8192, 0.5 * 8192, 0))
	var mx: Array = mwin._world_info.max
	check(px.distance_to(Vector2((0.5 - float(mwin._world_info.min[0])) * 18, (float(mx[1]) + 0.5) * 18)) < 0.01, "współrzędne mapy świata (północ u góry)")
	mwin.close()
	await _frames(2)
	check(not mwin.visible and not get_root().get_tree().paused, "zamknięcie mapy")
	# ShowMap: znacznik po prefiksie nazwy
	main.state.player["map_visited"] = {}
	main.dialogue._ds()["map_markers"] = ["Synth"]
	check(mwin.known_places().size() >= 1, "ShowMap „Synth” – miejsca o tej nazwie znane")
	main.dialogue._ds()["map_markers"] = []
	check(mwin.known_places().is_empty(), "bez odwiedzin i ShowMap – brak znaczników")
	report["fog_bytes"] = String((main.state.player.get("map_fog", {}) as Dictionary).values()[0]).length()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": report}))
	quit(1 if failures.size() > 0 else 0)
