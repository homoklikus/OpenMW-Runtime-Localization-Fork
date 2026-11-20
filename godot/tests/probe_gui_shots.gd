extends SceneTree
## Sonda: zrzuty nowych okien etapu 10 (okno ilości, szybkie klawisze, przypisanie, wybór magii) do --out.
## Zrzuty z prawdziwymi danymi zawierają obraz gry – tylko lokalnie, poza repozytorium.
## godot --path godot -s res://tests/probe_gui_shots.gd -- --data=… --out=KATALOG [--pos=…]

func _init() -> void:
	_run.call_deferred()

func _arg(n: String, d := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % n):
			return a.substr(n.length() + 3)
	return d

func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_arg("out", "/tmp").path_join(name + ".png"))
	print("PROBE_SHOT ", name, " ", img.get_size())

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	if main.scripts != null:
		main.scripts.set_global("chargenstate", -1.0)
	var inv = main.interaction.inventory
	var item := _arg("item", "misc_synth_spoon")
	if inv.count_of("player", {}, item) < 2:
		inv.add("player", {}, item, 5)
	main.menu_mode.open()
	await _shot("menu")
	# podpowiedzi (ToolTips) dla kilku przedmiotów
	for tid in _arg("tips", "synth_sword,synth_potion,synth_ring").split(","):
		if inv.count_of("player", {}, tid) <= 0 and not inv.item(tid).is_empty():
			inv.add("player", {}, tid, 1)
		main.menu_mode.refresh()
		main.tooltips.enabled = false
		main.tooltips.show_for({"type": "item", "id": tid, "count": inv.count_of("player", {}, tid)}, Vector2(400, 300))
		await _shot("tooltip_" + tid.replace("#", "_"))
	main.tooltips.enabled = true
	main.menu_mode.drop_to_world(item, "inventory", {})
	await _shot("count_dialog")
	main.count_dialog.press_cancel()
	main.menu_mode.close()
	main.quick_keys.open()
	await _shot("quickkeys")
	main.quick_keys._on_key_clicked(0)
	await _shot("quickkeys_assign")
	main.quick_keys.assign_magic_clicked()
	await _shot("magicselection")
	main.quick_keys.escape()
	main.quick_keys.close()
	quit(0)
