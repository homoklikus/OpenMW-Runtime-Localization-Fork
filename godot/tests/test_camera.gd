extends SceneTree
## Etap 10: kamera gracza jak OpenMW 0.51 (MWRender::Camera, omw/camera/camera.lua, third_person.lua):
## TogglePOV (krótko – przełączenie widoku, przytrzymanie – podgląd), Zoom3rdPerson (192 j., 30–800, przejścia
## z/do pierwszej osoby), punkt śledzenia 124 j., kolizja kamery, obrót odroczony po podglądzie, vanity po
## fVanityDelay, celownik tylko w pierwszej osobie, promień aktywacji z kamery widoku z pominięciem gracza,
## postać gracza widoczna poza pierwszą osobą, zapis widoku i odległości, kamera śmierci, kolejka zmiany widoku.
## godot --headless --path godot -s res://tests/test_camera.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

var failures: Array[String] = []
var checks := 0
const UPM := 69.99125109

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

var pcref = null                       # kamera sterowana stałym krokiem (bez zależności od tempa klatek)

func _frames(n: int, dt := 1.0 / 60.0) -> void:
	for i in n:
		await process_frame
		if pcref != null:
			pcref.frame(dt)

func _seconds(t: float) -> void:
	await _frames(int(ceil(t * 60.0)))

func _tap(pc) -> void:
	Input.action_press("toggle_pov")
	await _frames(2)
	Input.action_release("toggle_pov")
	await _frames(2)

func _meshes_visible(body) -> bool:
	if body.model == null:
		return false
	for g in body.model.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).visible:
			return true
	return false

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(30)
	var pl: CharacterBody3D = main.player
	pl.fly = true                                    # bez opadania podczas testu
	pl.velocity = Vector3.ZERO
	var pc = main.player_camera()
	pl.controller.set_process(false)       # klatki kamery z testu: stały krok 1/60 s
	pcref = pc
	var eye: Camera3D = pl.get_node("Camera3D")
	var body = main.player_body
	check(pc != null and pc.mode == "first" and pc.primary == "first", "start: pierwsza osoba")
	check(main.view_camera() == eye and eye.current, "pierwsza osoba: widok z oka gracza")
	check(body != null and body.model != null, "postać gracza zbudowana (player_doll)")
	check(not _meshes_visible(body), "pierwsza osoba: siatki postaci ukryte")
	check(main.mw_hud.camera_crosshair, "pierwsza osoba: celownik")
	# --- TogglePOV krótko: trzecia osoba ---
	await _tap(pc)
	check(pc.mode == "third" and pc.primary == "third", "TogglePOV (krótko): trzecia osoba (%s/%s)" % [pc.mode, pc.primary])
	check(main.view_camera() == pc.view and pc.view.current, "trzecia osoba: kamera widoku bieżąca")
	check(_meshes_visible(body), "trzecia osoba: postać widoczna")
	await _frames(3)
	check(not main.mw_hud.camera_crosshair and not main.mw_hud.crosshair.visible, "trzecia osoba: bez celownika (viewOverShoulder = false)")
	var tr: Vector3 = pc.tracked
	check(absf((tr.y - pl.global_position.y) * UPM - 124.0) < 0.5, "punkt śledzenia 124 j. nad graczem (%.1f)" % ((tr.y - pl.global_position.y) * UPM))
	check(is_equal_approx(pc.base_distance, 192.0), "odległość bazowa 192 j.")
	var d_real: float = (pc.view.global_position - tr).length() * UPM
	print("distance ", pc.camera_distance, " real ", d_real)
	check(pc.camera_distance > 150.0 and absf(d_real - pc.camera_distance) < 15.0, "kamera za graczem w odległości kamery (%.1f / %.1f)" % [pc.camera_distance, d_real])
	var back: Vector3 = (pc.view.global_position - tr).normalized()
	var fwd := -pl.global_transform.basis.z
	check(back.dot(Vector3(fwd.x, 0, fwd.z).normalized()) < -0.5, "kamera za plecami gracza")
	check(absf(wrapf(pc.yaw - pl.rotation.y, -PI, PI)) < 0.001, "trzecia osoba: kamera obraca się z graczem")
	pl.rotate_y(0.4)
	await _frames(2)
	check(absf(wrapf(pc.yaw - pl.rotation.y, -PI, PI)) < 0.001, "obrót gracza – kamera za nim")
	# --- odległość: kolizja ze ścianą za graczem ---
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.2)
	cs.shape = box
	wall.add_child(cs)
	main.add_child(wall)
	var bz: Vector3 = pc._view_basis().z
	wall.global_transform = Transform3D(Basis(Vector3.UP, pc.yaw), tr + bz * (100.0 / UPM))
	await physics_frame
	await physics_frame
	await _frames(3)
	print("wall distance ", pc.camera_distance)
	check(pc.camera_distance < 100.0 and pc.camera_distance > 70.0, "ściana 100 j. za graczem – kamera przed nią (%.1f j.)" % pc.camera_distance)
	wall.free()
	await physics_frame
	await _frames(3)
	check(pc.camera_distance > 150.0, "bez ściany – pełna odległość (%.1f)" % pc.camera_distance)
	# --- promień aktywacji z kamery widoku, gracz pominięty ---
	var ref := Node3D.new()
	ref.set_meta("mw_sid", "test_camera_target")
	var sb := StaticBody3D.new()
	var cs2 := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(0.6, 0.6, 0.6)
	cs2.shape = b2
	sb.add_child(cs2)
	ref.add_child(sb)
	main.add_child(ref)
	pl.get_node("Camera3D").rotation.x = 0.0
	await _frames(2)
	var vfwd: Vector3 = -pc.view.global_transform.basis.z
	ref.global_position = pc.view.global_position + vfwd * (pc.view.global_position - tr).length() + vfwd * (120.0 / UPM)
	await physics_frame
	await physics_frame
	var hit = main.activation_pick(eye)
	check(hit == ref, "trzecia osoba: obiekt na wprost w zasięgu aktywacji (promień z kamery, bez gracza) – %s" % hit)
	ref.global_position += vfwd * (150.0 / UPM)
	await physics_frame
	await physics_frame
	check(main.activation_pick(eye) == null, "trzecia osoba: obiekt dalej niż iMaxActivateDist od gracza – brak")
	ref.free()
	# --- zoom ---
	pc.add_zoom(-1.0)                       # kółko w dół – ZoomOut
	await _frames(2)
	check(is_equal_approx(pc.base_distance, 202.0), "ZoomOut: +10 j. (%.1f)" % pc.base_distance)
	pc.add_zoom(1.0)
	await _frames(2)
	check(is_equal_approx(pc.base_distance, 192.0), "ZoomIn: −10 j. (%.1f)" % pc.base_distance)
	for i in 40:
		pc.zoom(10.0)
	check(pc.mode == "first" and pc.primary == "first", "ZoomIn przy 30 j. – pierwsza osoba (%s, %.1f)" % [pc.mode, pc.base_distance])
	pc.zoom(-10.0)
	check(pc.mode == "third" and is_equal_approx(pc.base_distance, 30.0), "ZoomOut w pierwszej osobie – trzecia osoba z 30 j.")
	for i in 100:
		pc.zoom(-10.0)
	check(is_equal_approx(pc.base_distance, 800.0), "odległość najwyżej 800 j. (%.1f)" % pc.base_distance)
	pc.base_distance = 192.0
	# --- podgląd (przytrzymanie) i obrót odroczony ---
	var y0 := pl.rotation.y
	Input.action_press("toggle_pov")
	await _frames(2)
	check(pc.mode == "preview", "trzecia osoba: TogglePOV wciśnięty – od razu podgląd")
	pl.controller.look(0.5, 0.0)
	check(is_equal_approx(pl.rotation.y, y0) and absf(wrapf(pc.yaw - (y0 - 0.5), -PI, PI)) < 0.001, "podgląd: mysz obraca kamerę, nie gracza")
	await _seconds(0.35)
	Input.action_release("toggle_pov")
	await _frames(1)
	check(pc.mode == "third" and pc.primary == "third", "podgląd > 0,25 s: powrót do trybu głównego bez przełączenia (%s)" % pc.mode)
	check(absf(wrapf(pc.yaw - pl.rotation.y, -PI, PI)) > 0.2, "obrót odroczony: kamera jeszcze nie za graczem")
	await _seconds(1.5)
	check(absf(wrapf(pc.yaw - pl.rotation.y, -PI, PI)) < 0.01, "obrót odroczony: kamera wraca za gracza (%.3f)" % wrapf(pc.yaw - pl.rotation.y, -PI, PI))
	# z trzeciej osoby krótko: podgląd → pierwsza osoba
	await _tap(pc)
	check(pc.mode == "first" and pc.primary == "first", "trzecia osoba, TogglePOV krótko – pierwsza osoba (%s)" % pc.mode)
	check(not _meshes_visible(body) and eye.current, "pierwsza osoba: postać ukryta, oko bieżące")
	# z pierwszej osoby przytrzymanie – podgląd po 0,25 s
	Input.action_press("toggle_pov")
	await _frames(2)
	check(pc.mode == "first", "pierwsza osoba: wciśnięcie < 0,25 s – jeszcze bez podglądu")
	await _seconds(0.35)
	check(pc.mode == "preview", "pierwsza osoba: przytrzymanie – podgląd")
	Input.action_release("toggle_pov")
	await _frames(2)
	check(pc.mode == "first", "koniec podglądu – pierwsza osoba")
	# --- blokada DisablePlayerViewSwitch ---
	main.script_host.set_control("viewswitch", false)
	await _tap(pc)
	check(pc.mode == "first", "DisablePlayerViewSwitch: TogglePOV nie działa")
	main.script_host.set_control("viewswitch", true)
	# --- vanity ---
	pc.idle_timer = 100.0
	pc.idle_input = 10.0
	pc._update_vanity(0.1)
	check(pc.mode == "vanity", "bezczynność > fVanityDelay – vanity (%s)" % pc.mode)
	var vy: float = pc.yaw
	pc._update_vanity(1.0)
	check(absf(wrapf(vy - pc.yaw, -PI, PI) - deg_to_rad(3.0)) < 1e-4, "vanity: 3°/s wokół gracza")
	pc.note_input()
	await _frames(3)
	check(pc.mode == "first", "wejście – koniec vanity, tryb główny (%s)" % pc.mode)
	# --- zapis i wczytanie widoku ---
	await _tap(pc)
	pc.base_distance = 333.0
	main.capture_state()
	var cd: Dictionary = main.state.player.get("camera", {})
	check(cd.get("first_person", true) == false and is_equal_approx(float(cd.get("distance", 0)), 333.0), "zapis: widok i odległość (%s)" % cd)
	pc.load_data({"first_person": true, "distance": 192.0})
	check(pc.mode == "first", "wczytanie zapisu z pierwszą osobą")
	pc.load_data(cd)
	check(pc.mode == "third" and is_equal_approx(pc.base_distance, 333.0), "wczytanie zapisu z trzecią osobą i odległością")
	pc.load_data({"first_person": true, "distance": 192.0})
	# --- śmierć: kamera trzeciej osoby, zmiana na pierwszą w kolejce do końca animacji śmierci ---
	main._player_died()
	await _frames(2)
	check(pc.mode == "third" and body.dead, "śmierć: World::useDeathCamera – trzecia osoba")
	check(main.game_state == "ended", "śmierć: stan Ended")
	await _tap(pc)                            # trzecia → podgląd → (krótko) pierwsza – w kolejce
	check(pc.mode != "first" and pc.queued == "first", "po śmierci zmiana na pierwszą osobę czeka (upperBodyReady) – %s/%s" % [pc.mode, pc.queued])
	main.resume_after_death()
	await _frames(2)
	check(pc.mode == "first" and pc.queued.is_empty(), "Resurrect: zaległa zmiana widoku wykonana (%s)" % pc.mode)
	print("RESULT ", JSON.stringify({"test": "camera", "ok": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
