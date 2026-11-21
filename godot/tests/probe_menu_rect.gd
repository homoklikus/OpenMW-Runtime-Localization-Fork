extends SceneTree
## Położenie przycisków menu głównego (do współrzędnych kliknięć w porównaniach z OpenMW).
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.open_main_menu()
	for i in 5:
		await process_frame
	var vp := root.get_visible_rect().size
	for b in main.main_menu.find_children("*", "BaseButton", true, false):
		if (b as Control).is_visible_in_tree():
			var r: Rect2 = (b as Control).get_global_rect()
			print("MENUBTN ", b.name, " ", r.get_center().round(), " vp=", vp)
	quit(0)
