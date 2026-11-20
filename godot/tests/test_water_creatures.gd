extends SceneTree
## Regresje stworzeń wodnych i latających (etap 10, „latający Slaughterfish”) – sceny syntetyczne, bez danych gry.
## OpenMW MovementSolver / World::isFlying / World::isUnderwater:
## * pływak pod wodą nie wypływa ponad poziom pływania (także przy poślizgu po stoku brzegu),
## * stworzenie wodne poza wodą podlega grawitacji (spada na ziemię – nie wisi w powietrzu),
## * poziom pływania z wymiarów fizycznych aktora (płytka woda: mała ryba nadal pływa),
## * tylko canFly (Flies) leci bez grawitacji; martwy/sparaliżowany latający spada,
## * Lewitacja działa także na stworzenie wodne poza wodą,
## * pochylenie AI (ai_pitch) zmienia głębokość tylko w wodzie / w locie,
## * mw_cell_builder._fit_capsule: Swims nie daje braku grawitacji, Flies – tak.
## godot --headless --path godot -s res://tests/test_water_creatures.gd

const ACTOR := preload("res://scripts/mw/mw_actor.gd")
const BUILDER := preload("res://scripts/mw/mw_cell_builder.gd")

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _box(parent: Node3D, size: Vector3, pos: Vector3, rot_x := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = pos
	b.rotation.x = rot_x
	return b

## Ryba: kapsuła 0,4 m (jak mała ryba z granic modelu), poziom wody 0.
const SLAUGHTERFISH := {"swims": true, "walks": false, "flies": false, "bipedal": false}

func _fish(world: Node3D, pos: Vector3, water := 0.0) -> CharacterBody3D:
	var a: CharacterBody3D = ACTOR.new()
	var m := Node3D.new()
	BUILDER._fit_capsule(a, m, SLAUGHTERFISH)     # flagi rekordu jak przy wczytaniu komórki
	m.free()
	a.capsule_radius = 0.15
	a.capsule_height = 0.4
	a.water_level = water
	a.swim_speed = 2.0
	a.walk_speed = 2.0
	a.run_speed = 2.0
	world.add_child(a)
	a.global_position = pos
	return a

func _frames(a: CharacterBody3D, n: int, input := Vector2.ZERO, track := []) -> void:
	for i in n:
		a.move_input = input
		await physics_frame
		if not track.is_empty():
			track[0] = maxf(float(track[0]), a.global_position.y)

func _world() -> Node3D:
	var w := Node3D.new()
	root.add_child(w)
	return w

func _free(w: Node3D) -> void:
	w.queue_free()
	await process_frame

# 1–2: ryba w wodzie, ruch w górę (pochylenie AI) – zatrzymuje się pod powierzchnią
func _test_in_water() -> void:
	var w := _world()
	_box(w, Vector3(40, 1, 40), Vector3(0, -10.5, 0))           # dno y = −10
	var a := _fish(w, Vector3(0, -3, 0))
	await _frames(a, 5)
	check(a.swimming, "ryba 3 m pod wodą pływa")
	a.ai_pitch = deg_to_rad(60.0)
	var top := [-INF]
	await _frames(a, 240, Vector2(0, -1), top)
	var max_y: float = a.water_level - a.height * a.swim_height_scale
	check(float(top[0]) <= max_y + 0.02, "ryba płynąca w górę nie wychodzi ponad poziom pływania (maks. %.3f, granica %.3f)" % [top[0], max_y])
	check(a.swimming and a.global_position.y < 0.0, "ryba pozostaje w wodzie (y %.3f)" % a.global_position.y)
	# w dół – zmienia głębokość (pochylenie działa w wodzie)
	a.ai_pitch = deg_to_rad(-60.0)
	var y0 := a.global_position.y
	await _frames(a, 60, Vector2(0, -1))
	check(a.global_position.y < y0 - 0.5, "ryba z pochyleniem w dół schodzi głębiej (%.3f → %.3f)" % [y0, a.global_position.y])
	await _free(w)

# 3: brzeg – stok wychodzący z wody; ryba płynie poziomo w stronę lądu
func _test_shore() -> void:
	var w := _world()
	_box(w, Vector3(40, 1, 40), Vector3(0, -6.5, 0))            # dno y = −6
	# stok 30° wznoszący się w kierunku −Z, wyłania się z wody przy z ≈ −8
	_box(w, Vector3(40, 1, 30), Vector3(0, -2.0, -12.0), deg_to_rad(30.0))
	var a := _fish(w, Vector3(0, -1.0, 0))
	await _frames(a, 5)
	var top := [-INF]
	await _frames(a, 400, Vector2(0, -1), top)
	var max_y: float = a.water_level - a.height * a.swim_height_scale
	check(float(top[0]) <= maxf(-1.0, max_y) + 0.03, "ryba przy brzegu nie wjeżdża po stoku ponad wodę (maks. %.3f)" % top[0])
	check(a.global_position.y < 0.0, "ryba po dopłynięciu do brzegu nadal w wodzie (y %.3f)" % a.global_position.y)
	await _free(w)

# 4: płytka i głęboka woda – poziom pływania z wymiarów fizycznych
func _test_shallow() -> void:
	var w := _world()
	_box(w, Vector3(40, 1, 40), Vector3(0, -1.0, 0))            # dno y = −0,5 (woda 0,5 m)
	var a := _fish(w, Vector3(0, -0.45, 0))
	await _frames(a, 30)
	check(absf(a.height - 0.4) < 0.01, "wysokość pływania = wysokość kapsuły (%.2f)" % a.height)
	check(a.swimming, "mała ryba w płytkiej wodzie (0,5 m) pływa")
	await _frames(a, 60, Vector2(0, -1))
	check(a.swimming and a.global_position.y < 0.0, "ryba w płytkiej wodzie płynie i nie wychodzi (y %.3f)" % a.global_position.y)
	await _free(w)

# 5: ryba poza wodą (umieszczona przez dane/skrypt w powietrzu) – spada na ziemię jak w OpenMW
func _test_out_of_water() -> void:
	var w := _world()
	_box(w, Vector3(40, 1, 40), Vector3(0, -0.5, 0))            # ląd y = 0, woda daleko niżej
	var a := _fish(w, Vector3(0, 4.0, 0), -20.0)
	await _frames(a, 120)
	check(not a.swimming and a.global_position.y < 0.1, "ryba poza wodą spada na ziemię (y %.3f)" % a.global_position.y)
	# komórka bez wody (water_level −INF)
	var b := _fish(w, Vector3(3, 3.0, 0), -INF)
	await _frames(b, 120, Vector2(0, -1))
	check(b.global_position.y < 0.1, "ryba w komórce bez wody nie lata (y %.3f)" % b.global_position.y)
	await _free(w)

# 6: latające – bez grawitacji; martwe/sparaliżowane (no_gravity = false) spada; Lewitacja
func _test_flying_and_effects() -> void:
	var w := _world()
	_box(w, Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	var f := _fish(w, Vector3(0, 5.0, 0), -20.0)
	f.can_fly = true
	f.no_gravity = true
	await _frames(f, 60, Vector2(0, -1))
	check(absf(f.global_position.y - 5.0) < 0.05, "latające (Flies) nie spada (y %.3f)" % f.global_position.y)
	f.ai_pitch = deg_to_rad(30.0)
	await _frames(f, 30, Vector2(0, -1))
	check(f.global_position.y > 5.3, "latające z pochyleniem wznosi się (y %.3f)" % f.global_position.y)
	f.no_gravity = false                 # World::isFlying = false (martwe / Paraliż)
	await _frames(f, 150)
	check(f.global_position.y < 0.1, "martwe/sparaliżowane latające spada (y %.3f)" % f.global_position.y)
	# Lewitacja: stworzenie wodne poza wodą nie spada
	var l := _fish(w, Vector3(4, 3.0, 0), -20.0)
	l.levitate = true
	l.levitate_speed = 1.0
	await _frames(l, 60)
	check(absf(l.global_position.y - 3.0) < 0.05, "lewitujące stworzenie wodne nie spada (y %.3f)" % l.global_position.y)
	l.levitate = false
	await _frames(l, 120)
	check(l.global_position.y < 0.1, "po końcu Lewitacji spada (y %.3f)" % l.global_position.y)
	# pochylenie AI poza wodą bez lotu nie unosi aktora
	var g := _fish(w, Vector3(-4, 0.05, 0), -20.0)
	g.ai_pitch = deg_to_rad(60.0)
	await _frames(g, 60, Vector2(0, -1))
	check(g.global_position.y < 0.1, "pochylenie AI na lądzie nie unosi (y %.3f)" % g.global_position.y)
	await _free(w)

# 7: flagi rekordu → grawitacja (mw_cell_builder._fit_capsule)
func _test_record_flags() -> void:
	var m := Node3D.new()
	var cases := [
		[{"swims": true, "walks": false, "flies": false, "bipedal": false}, false, "Swims (Slaughterfish)"],
		[{"swims": true, "walks": true, "flies": false, "bipedal": false}, false, "Swims + Walks (Mudcrab)"],
		[{"swims": false, "walks": false, "flies": true, "bipedal": false}, true, "Flies (Cliff Racer)"],
		[{"swims": true, "walks": false, "flies": true, "bipedal": false}, true, "Swims + Flies"],
		[{"swims": false, "walks": true, "flies": false, "bipedal": false}, false, "Walks"],
	]
	for c in cases:
		var a: CharacterBody3D = ACTOR.new()
		BUILDER._fit_capsule(a, m, c[0])
		check(bool(a.no_gravity) == bool(c[1]) and bool(a.can_fly) == bool((c[0] as Dictionary).flies),
			"flagi %s → brak grawitacji %s (jest %s)" % [c[2], c[1], a.no_gravity])
		a.free()
	m.free()

# 8: kształt aktora z węzła „Bounding Box” modelu (Actor: mCollisionBox, mMeshTranslation) – poziom pływania
func _test_bounding_box() -> void:
	var m := Node3D.new()
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 2.5, 1.0)                   # siatka (np. ogon, płetwy) większa niż kolizja
	mesh.mesh = bm
	m.add_child(mesh)
	var bbn := Node3D.new()
	bbn.set_meta("extras", {"mw_name": "Bounding Box", "mw_bounding_box": {"center": [0.0, 0.3, 0.0], "extents": [0.4, 0.5, 0.9]}})
	m.add_child(bbn)
	var a: CharacterBody3D = ACTOR.new()
	BUILDER._fit_capsule(a, m, SLAUGHTERFISH)
	check(absf(a.capsule_height - 1.0) < 0.001 and absf(a.capsule_radius - 0.9) < 0.001 and a.capsule_center.is_equal_approx(Vector3(0, 0.3, 0)),
		"Bounding Box: wysokość 2 × półwymiar, środek przesunięty (h %.2f r %.2f c %s)" % [a.capsule_height, a.capsule_radius, a.capsule_center])
	check(not a.no_gravity, "Bounding Box: Swims nadal z grawitacją")
	var w := _world()
	w.add_child(a)
	a.water_level = 0.0
	a.global_position = Vector3(0, -1.0, 0)            # 1 m pod wodą: pływa (1,0 × 0,9 < 1); z siatki (2,5 m) – nie
	await _frames(a, 3)
	check(a.swimming and absf(a.height - 1.0) < 0.001, "Bounding Box: poziom pływania z prostopadłościanu (pływa 1 m pod wodą)")
	var col := a.get_node("Capsule") as CollisionShape3D
	check(col.position.is_equal_approx(Vector3(0, 0.3, 0)), "Bounding Box: kształt kolizji w środku z modelu")
	await _free(w)
	m.free()

# 9: World::adjustPosition przy pierwszej aktualizacji aktora z referencji
func _test_adjust_position() -> void:
	var u := 1.0 / MWCoords.UNITS_PER_METER
	var w := _world()
	_box(w, Vector3(40, 1, 40), Vector3(0, -6.5, 0))            # dno / ziemia y = −6
	# poza wodą (woda −20): z + 20 j., potem traceDown na podłoże – od razu, bez spadania
	var a := _fish(w, Vector3(0, 3.0, 0), -20.0)
	a.set_meta("mw_actor", "creature")
	await _frames(a, 3)
	check(a.position_adjusted and absf(a.global_position.y - (-6.0)) < 0.05, "adjustPosition: poza wodą na podłoże (y %.2f)" % a.global_position.y)
	# pod wodą (woda 0): pływa – tylko z + 20 j., bez stawiania na dnie
	var b := _fish(w, Vector3(3, -3.0, 0), 0.0)
	b.set_meta("mw_actor", "creature")
	await _frames(b, 3)
	check(absf(b.global_position.y - (-3.0 + 20.0 * u)) < 0.02, "adjustPosition: pływający tylko + 20 j. (y %.3f)" % b.global_position.y)
	# poniżej terenu: podniesiony na teren + 20 j. (getTerrainHeightAt)
	var c := _fish(w, Vector3(-3, -8.0, 0), 0.0)
	c.set_meta("mw_actor", "creature")
	c.terrain_height = -6.0
	await _frames(c, 3)
	check(c.global_position.y > -6.0 and c.global_position.y < -5.5, "adjustPosition: spod terenu ponad teren (y %.3f)" % c.global_position.y)
	await _free(w)

func _run() -> void:
	await _test_in_water()
	await _test_shore()
	await _test_shallow()
	await _test_out_of_water()
	await _test_flying_and_effects()
	_test_record_flags()
	await _test_bounding_box()
	await _test_adjust_position()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	for f in failures:
		print("  - ", f)
	quit(1 if failures.size() > 0 else 0)
