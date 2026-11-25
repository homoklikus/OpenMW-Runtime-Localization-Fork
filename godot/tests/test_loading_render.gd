extends SceneTree
## Etap 10 cz. 25 – test regresyjny „brak ekranu ładowania, tylko glicze” (z wyświetlaczem: Xvfb/GPU, nie headless).
## Wczytanie zapisu z menu głównego jest synchroniczne; klatki ekranu ładowania rysuje RenderingServer.force_draw.
## Kontrolki Godota rysują się dopiero przy opróżnieniu kolejki komunikatów na końcu klatki, więc nowo zbudowany
## ekran ładowania był w tych klatkach pusty – widać było menu, a potem budowany świat. Sprawdza odczyt obrazu
## w każdej zasłoniętej klatce: piksel w rogu (poza tapetą 4:3 / czarne tło) czarny, a w okienku z paskiem
## (dół, środek) – ramka okienka, nie świat.
## xvfb-run godot --path godot -s res://tests/test_loading_render.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

var failures: Array[String] = []
var checks := 0
var main
var covered := 0
var corner_bad := 0
var box_bad := 0
var world_seen := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _post() -> void:
	if main == null or main.loading == null or not main.loading.visible:
		return
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		return
	covered += 1
	var w := img.get_width()
	var h := img.get_height()
	var c := img.get_pixel(3, 3)
	if c.get_luminance() > 0.03:
		corner_bad += 1
	var box: Rect2 = Rect2(main.loading._box.position, main.loading._box.get_combined_minimum_size())
	var bp := img.get_pixel(int(box.position.x + 1), int(box.get_center().y))
	if bp.get_luminance() < 0.02:     # ramka MW_Box jest jasna – czarny piksel to brak okienka
		box_bad += 1

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RESULT ", JSON.stringify({"checks": 0, "failures": [], "skipped": "headless"}))
		quit(0)
		return
	var dir := ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join("loading_render.mwsave")
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	check(main.save_game(p) == "", "zapis")
	main.cleanup()
	main._enter_nogame()
	main.open_main_menu()
	for i in 10:
		await process_frame
	# pierwsze użycie ekranu ładowania w sesji (gra z launchera: menu główne od startu) – świeżo budowane kontrolki
	if main.loading._root != null:
		main.loading._root.free()
		main.loading._root = null
		if main.loading.get("_ci") != null and main.loading._ci.is_valid():
			RenderingServer.free_rid(main.loading._ci)
			main.loading._ci = RID()
	RenderingServer.frame_post_draw.connect(_post)
	main.close_main_menu()             # SaveGameDialog::accept
	var w: Array = main.load_slot(null, p)
	check(w.is_empty() or not String(w[0]).begins_with("BŁĄD"), "wczytanie (%s)" % [w])
	for i in 120:
		await process_frame
		if not main.loading.visible and not main.is_revealing():
			break
	RenderingServer.frame_post_draw.disconnect(_post)
	check(covered >= 1, "klatki z ekranem ładowania (%d)" % covered)
	check(corner_bad == 0, "zasłonięte klatki: czarne tło ekranu ładowania, nie menu ani świat (%d/%d)" % [corner_bad, covered])
	check(box_bad == 0, "zasłonięte klatki: okienko z paskiem postępu narysowane (%d/%d)" % [box_bad, covered])
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
