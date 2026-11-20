extends CharacterBody3D
## MWActor – wspólna podstawa gracza, NPC i stworzeń (plan, rewizja 2.0, §2.5).
##
## Aktor ma wspólny ruch (chód, bieg, skok, latanie, grawitacja, kolizja kapsułą) i dane (rekord, sid,
## statystyki – etap 4, wygląd – etap 2). Różnice między rodzajami realizują KONTROLERY: węzeł z metodą
## control(actor, delta), który ustawia intencje aktora (move_input, want_run, want_jump, obrót).
## Gracz: mw_player_controller.gd (wejście + kamera); NPC/stworzenia: kontrolery AI (etap 8).

signal controller_changed(controller: Node)
## Lądowanie po upadku: wysokość w jednostkach MW (obrażenia od upadku – etap 4, gdy aktor ma statystyki).
signal landed(fall_height_mw: float)
## Początek skoku (etap 7: kondycja i akrobatyka jak OpenMW PhysicsSystem – handleJump).
signal jumped

@export var walk_speed := 3.2      # m/s (ok. 230 jedn./s – prędkość chodu w grze to ~100–200 jedn./s)
@export var run_speed := 6.5
@export var fly_speed := 25.0
@export var jump_velocity := 4.5
## Grawitacja i największa prędkość spadania jak w Morrowindzie (Constants::GravityUnits = 9,8 × 64 jedn./s²,
## MaxFallSpeed 4005,5 jedn./s) – w metrach Godota.
var gravity := 9.8 * 64.0 / MWCoords.UNITS_PER_METER
var max_fall_speed := 4005.5 / MWCoords.UNITS_PER_METER
## Sterowanie w powietrzu (fJumpMoveBase + fJumpMoveMult × akrobatyka) – ustawia gra wg statystyk.
var air_factor := 1.0
var kind := "npc"                  # player | npc | creature
var record_id := ""                # id rekordu NPC_/CREA (gracz: "player")
var sid := ""                      # stabilny id referencji w świecie ("" dla gracza)
var stats := {}                    # etap 4: atrybuty, umiejętności, zdrowie…
var fly := false
var collide := true
## Pływanie (etap 3, jak OpenMW World::isSwimming): poziom wody (y w Godocie; -INF = brak wody) ustawia gra;
## aktor pływa, gdy punkt na wysokości fSwimHeightScale (0,9) jego wzrostu jest pod wodą.
var water_level := -INF
var swim_height_scale := 0.9
var height := 1.8
var swim_speed := 2.2
var swimming := false
var _fall_start := NAN
## Efekty magii w ruchu (etap magii, jak OpenMW World::isFlying / PhysicsSystem::prepareSimulation) – ustawia
## MWMagic.apply_movement co klatkę: Lewitacja (lot bez grawitacji z prędkością Npc::getSpeed), Powolne opadanie
## (inercja pionowa w dół × (1 − wielkość × 0,005), bez obrażeń od upadku), Chodzenie po wodzie (kolizja
## z powierzchnią wody; aktor pod wodą przenoszony na powierzchnię, jeśli droga w górę jest wolna).
var levitate := false
var levitate_speed := 0.0
var slow_fall := 1.0
var water_walk := false
var on_water := false
## Kapsuła kolizji (NPC: stała; stworzenia: z wymiarów modelu – etap 8).
var capsule_radius := 0.35
var capsule_height := 1.8
## Środek kształtu względem początku aktora (Actor::mMeshTranslation z „Bounding Box”); NAN – połowa wysokości.
var capsule_center := Vector3(NAN, NAN, NAN)
## Półwymiary prostopadłościanu z „Bounding Box” (x, wysokość, z – niezależne jak Actor::mHalfExtents); zero – z
## capsule_radius/capsule_height.
var capsule_extents := Vector3.ZERO
## Lot bez grawitacji – World::isFlying dla stworzeń: canFly (flaga Flies) i żywe, niesparaliżowane
## (ustawiane co klatkę przez MWMagic.apply_movement z can_fly). Stworzenia wodne NIE są zwolnione z grawitacji:
## w OpenMW (MovementSolver) poza wodą spadają jak każdy aktor, a pod wodą nie mogą „wypłynąć w powietrze”.
var can_fly := false
var no_gravity := false
## Pochylenie ruchu aktora sterowanego przez AI (rotation x w OpenMW: smoothTurn w AiPackage::pathTo i walce),
## używane tylko gdy aktor może się poruszać w osi Z (canActorMoveByZAxis: pływa albo leci). Dodatnie = w górę.
var ai_pitch := 0.0
## Bezwładny (ActorFrameData::mInert): martwy albo sparaliżowany – pod wodą wypływa na powierzchnię
## (CharacterController mFloatToSurface: 25 j./s), poza wodą spada. Ustawiane przez MWMagic.apply_movement.
var inert := false
## World::adjustPosition przy pierwszej aktualizacji aktora po wczytaniu komórki (Actors::update –
## !getPositionAdjusted): z = max(z, wysokość terenu) + 20 j., potem – gdy nie leci i nie pływa – na podłoże
## (traceDown). Dotyczy aktorów z referencji (mw_actor); gracz – osobno (travel/_place_on_ground).
var terrain_height := -INF
var position_adjusted := false
var _adjust_wait := 2                    # kolizje Jolt dostępne dla zapytań po kroku fizyki
## Wchodzenie na stopnie (jak OpenMW Stepper: Constants::sStepSizeUp = 34 jedn., sMaxSlope = 46°) – bez tego
## kapsuła zatrzymuje się na każdej krawędzi wyższej niż kilka cm (np. trap okrętu więziennego, progi, schody).
var step_height := 34.0 / MWCoords.UNITS_PER_METER

# intencje ustawiane przez kontroler w każdej klatce fizyki
var move_input := Vector2.ZERO     # x: w prawo, y: do tyłu (jak Input.get_vector)
var want_run := false
var want_jump := false
var want_sneak := false            # skradanie (etap 8: wykrywanie)
var jumping := false               # od skoku do lądowania (Player::setJumping – GetPCJumping)
var move_flags: Dictionary = {}    # ForceSneak/ForceRun/ForceJump/ForceMoveJump (CreatureStats::mMovementFlags)

var controller: Node = null:
	set(c):
		controller = c
		controller_changed.emit(c)

func _ready() -> void:
	floor_max_angle = deg_to_rad(46.0)
	if not collide:
		return
	var col := CollisionShape3D.new()
	col.name = "Capsule"
	# prostopadłościan jak w OpenMW (btBoxShape z połówek wymiarów aktora): płaski spód stoi pewnie na krawędziach
	# stopni i trapów; walec w fizyce Godota zaczepiał krawędzią dolnej podstawy o brzeg podłogi (zerowy ruch
	# u szczytu schodów statku więziennego), kapsuła zsuwała się z krawędzi
	var box := BoxShape3D.new()
	var h := maxf(capsule_height, capsule_radius * 2.0)
	box.size = Vector3(capsule_radius * 2.0, h, capsule_radius * 2.0)
	if capsule_extents != Vector3.ZERO:
		box.size = capsule_extents * 2.0
		h = box.size.y
	col.shape = box
	col.position = capsule_center if not is_nan(capsule_center.x) else Vector3(0, h * 0.5, 0)
	add_child(col)
	# World::isUnderwater / MovementSolver: poziom pływania z połówek wymiarów fizycznych aktora (halfExtents.z × 2),
	# nie ze stałego wzrostu – płytko pływająca ryba (kapsuła ~0,4 m) bez tego „nie pływała” i wychodziła z wody
	height = h

## Baza kierunku latania: kamera, jeśli aktor ją ma (gracz), inaczej sam aktor.
func look_basis() -> Basis:
	var cam := get_node_or_null("Camera3D") as Node3D
	if cam:
		return cam.global_transform.basis
	if ai_pitch != 0.0:
		return global_transform.basis * Basis(Vector3.RIGHT, ai_pitch)
	return global_transform.basis

## canActorMoveByZAxis: (canSwim i pływa) albo leci (World::isFlying, także Lewitacja).
func can_move_by_z() -> bool:
	return swimming or no_gravity or levitate or fly

func _physics_process(delta: float) -> void:
	if controller != null and controller.has_method("control"):
		controller.control(self, delta)
	step(delta)

func _adjust_position() -> void:
	position_adjusted = true
	var u := 1.0 / MWCoords.UNITS_PER_METER
	var p := global_position
	p.y = maxf(p.y, terrain_height) + 20.0 * u          # „place slightly above terrain”
	global_position = p
	var swims := p.y + height * swim_height_scale < water_level
	if no_gravity or swims:
		return
	var q := PhysicsRayQueryParameters3D.create(p, p - Vector3(0, MWCoords.CELL_SIZE * u, 0))
	q.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	for i in 8:                                          # traceDown: tylko świat (inni aktorzy pomijani)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return
		if hit.collider is CharacterBody3D:
			q.exclude = q.exclude + [hit.rid]
			continue
		p.y = minf(p.y, float(hit.position.y))
		global_position = p
		velocity = Vector3.ZERO
		return

## Ruch z bieżących intencji (wspólny dla wszystkich aktorów).
func step(delta: float) -> void:
	if not position_adjusted and collide and has_meta("mw_actor"):
		_adjust_wait -= 1
		if _adjust_wait <= 0:
			_adjust_position()
	if has_meta("mw_dead") and collide:
		_corpse_step(delta)
		return
	# CreatureStats::getStance: postawa = klawisz/AI albo flaga wymuszenia; ForceJump – skok przy każdym kontakcie
	# z podłożem, ForceMoveJump – tylko w ruchu (CharacterController::update, poza wodą i lotem)
	if not move_flags.is_empty():
		if bool(move_flags.get("force_sneak", false)):
			want_sneak = true
			want_run = false
		if bool(move_flags.get("force_run", false)):
			want_run = true
		if bool(move_flags.get("force_jump", false)) or bool(move_flags.get("force_move_jump", false)) \
				and move_input.length() > 0.5:
			want_jump = true
	if fly:
		jumping = false
		var d := look_basis() * Vector3(move_input.x, 0, move_input.y)
		velocity = d * fly_speed * (3.0 if want_run else 1.0)
		global_position += velocity * delta
		want_jump = false
		return
	if levitate:
		# lot: kierunek wg patrzenia (z pochyleniem kamery gracza), bez skoku (character.cpp: vec.z = 0 w locie)
		jumping = false
		swimming = false
		on_water = false
		_fall_start = NAN
		var dl := look_basis() * Vector3(move_input.x, 0, move_input.y)
		velocity = dl.normalized() * levitate_speed if dl.length() > 0.01 else Vector3.ZERO
		want_jump = false
		move_and_slide()
		return
	if water_walk and water_level > -INF and global_position.y < water_level:
		# PhysicsTaskScheduler: chodzący po wodzie pod powierzchnią → na powierzchnię (canMoveToWaterSurface)
		var up := water_level - global_position.y
		if not test_move(global_transform, Vector3.UP * up):
			global_position.y = water_level
			velocity.y = maxf(velocity.y, 0.0)
	swimming = global_position.y + height * swim_height_scale < water_level
	if swimming:
		_fall_start = NAN
		jumping = false
		# kierunek ruchu wg patrzenia (także w górę/w dół), skok = w górę; nie wyżej niż powierzchnia
		var d := look_basis() * Vector3(move_input.x, 0, move_input.y)
		if want_jump:
			d += Vector3.UP
		if inert:
			d = Vector3.ZERO                         # MovementSolver: bezwładny pod wodą tylko wypływa
		# getSwimSpeedImpl: swim_speed już uwzględnia bieg (getRunSpeed przy biegu) – bez dodatkowego mnożnika
		velocity = d.normalized() * swim_speed if d.length() > 0.01 else Vector3.ZERO
		if inert:
			velocity = Vector3.UP * 25.0 / MWCoords.UNITS_PER_METER
		var max_y := water_level - height * swim_height_scale - 0.01     # przy powierzchni nadal pływa
		if no_gravity:
			pass                                    # MovementSolver: latający może wynurzyć się z wody
		elif global_position.y + velocity.y * delta > max_y and velocity.y > 0.0:
			velocity.y = maxf(0.0, (max_y - global_position.y) / maxf(delta, 1e-4))
		want_jump = false
		var y0 := global_position.y
		move_and_slide()
		# MovementSolver: „If not able to fly, don't allow to swim up into the air” – składowa w górę odrzucana
		# także po poślizgu po zboczu dna/brzegu (bez tego pływak wjeżdżał po stoku ponad wodę)
		if not no_gravity and global_position.y > maxf(y0, max_y):
			global_position.y = maxf(y0, max_y)
			velocity.y = minf(velocity.y, 0.0)
		return
	var speed := run_speed if want_run else walk_speed
	var wish := (transform.basis * Vector3(move_input.x, 0, move_input.y)).normalized() * speed
	on_water = water_walk and water_level > -INF and global_position.y <= water_level + 0.005 and velocity.y <= 0.0
	var grounded := is_on_floor() or on_water
	if not grounded:
		wish *= air_factor
	velocity.x = wish.x
	velocity.z = wish.z
	if no_gravity:
		# MovementSolver (mFlying): prędkość wg obrotu z pochyleniem (rot x/z), bez grawitacji i bez spowolnienia
		# w powietrzu
		var d3 := look_basis() * Vector3(move_input.x, 0, move_input.y)
		velocity = d3.normalized() * speed if d3.length() > 0.01 else Vector3.ZERO
		wish = Vector3(velocity.x, 0.0, velocity.z)
	elif not grounded:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
		if velocity.y < 0.0:
			velocity.y *= slow_fall              # MovementSolver: mInertia.z *= mSlowFall
	elif on_water and not want_jump:
		velocity.y = 0.0
	elif want_jump and jump_velocity > 0.0:
		# skok w ruchu: wektor (kierunek, 1) × wysokość × 0,707 (character.cpp) – pionowo 0,707 prędkości skoku
		velocity.y = jump_velocity * (0.707 if move_input.length() > 0.01 else 1.0)
		jumping = true
		jumped.emit()
	want_jump = false
	var was_floor := grounded
	var start := global_position
	move_and_slide()
	if water_walk and water_level > -INF and global_position.y < water_level and velocity.y <= 0.0:
		global_position.y = water_level         # powierzchnia wody jak podłoże (kolizja z wodą)
		velocity.y = 0.0
		on_water = true
	if slow_fall < 1.0:
		_fall_start = NAN                       # PhysicsTaskScheduler: stats.land() przy mSlowFall < 1
	if was_floor and Vector2(wish.x, wish.z).length() > 0.01:
		_try_step(start, Vector3(wish.x, 0.0, wish.z) * delta)
	var now_ground := is_on_floor() or on_water
	if not now_ground:
		if slow_fall >= 1.0 and (is_nan(_fall_start) or global_position.y > _fall_start):
			_fall_start = global_position.y
	elif not was_floor:
		jumping = false
		if not is_nan(_fall_start):
			landed.emit((_fall_start - global_position.y) * MWCoords.UNITS_PER_METER)
		_fall_start = NAN

## Ciało (kształt kolizji wyłączony po śmierci – enableActorCollision(false) w OpenMW wyłącza tylko zderzenia
## innych z ciałem, samo ciało nadal zderza się ze światem): pod wodą wypływa na poziom pływania (25 j./s), poza
## wodą spada z grawitacją do podłoża wyznaczonego promieniem w dół (bez tego martwy latający wisiał, a po
## włączeniu grawitacji spadał przez teren).
func _corpse_step(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var max_y := water_level - height * swim_height_scale
	if global_position.y < max_y:
		velocity.y = 0.0
		global_position.y = minf(max_y, global_position.y + 25.0 / MWCoords.UNITS_PER_METER * delta)
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 1000.0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var ground: float = hit.position.y if not hit.is_empty() else -INF
	if global_position.y <= ground + 0.01:
		velocity.y = 0.0
		return
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	if velocity.y < 0.0:
		velocity.y *= slow_fall
	var ny := global_position.y + velocity.y * delta
	if water_level > -INF:
		ny = maxf(ny, minf(global_position.y, max_y))     # wpada do wody – dalej wypływa
	if ny <= ground:
		ny = ground
		velocity.y = 0.0
	global_position.y = ny

## Stopień: gdy ruch poziomy zatrzymała ściana, spróbuj „w górę o step_height → do przodu → w dół na podłoże”
## (OpenMW MovementSolver/Stepper). Krok przyjmujemy, jeśli dalej sięga niż sam ruch z poślizgiem
## (trzy próby jak Stepper::step z sDoExtraStairHacks).
func _try_step(start: Vector3, motion: Vector3) -> void:
	# MovementSolver: każde zderzenie z obiektem (nie aktorem) poniżej wysokości stopnia → próba wejścia
	# (Stepper::step) – niezależnie od normalnej kontaktu (krawędź rampy schodów ma normalną „podłogową”,
	# a mimo to zatrzymuje ruch)
	var slid := global_position - start
	slid.y = 0.0
	if slid.length() >= motion.length() * 0.9:
		return
	var blocked := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is CharacterBody3D:
			continue
		if c.get_position().y - start.y < step_height:
			blocked = true
			break
	if not blocked:
		return
	# Stepper::step: w górę o sStepSizeUp (minus margines), do przodu (próba 1: zwykły ruch; 2: sMinStep = 10;
	# 3: sMinStep2 = 20 bez schodzenia poniżej startu), w dół; zejście tylko na nachylenie ≤ sMaxSlope i nie na aktora
	var u := 1.0 / MWCoords.UNITS_PER_METER
	var margin := 0.2 * u                                # sCollisionMargin
	var res := KinematicCollision3D.new()
	var up_d := step_height
	if test_move(Transform3D(global_transform.basis, start), Vector3.UP * step_height, res):
		up_d = res.get_travel().y - margin
		if up_d <= 0.0:
			return
	var tpos := start + Vector3.UP * up_d
	var dir := Vector3(motion.x, 0.0, motion.z)
	var mdist := dir.length()
	if mdist < 1e-6:
		return
	dir /= mdist
	var max_slope_cos := cos(deg_to_rad(46.0))         # sMaxSlope
	var newpos := Vector3.ZERO
	var ok := false
	for attempt in [1, 2, 3]:
		var dist: float = mdist if attempt == 1 else (10.0 * u if attempt == 2 else 20.0 * u)
		if test_move(Transform3D(global_transform.basis, tpos), dir * dist, res):
			var moved := res.get_travel().length()
			if moved <= margin:
				return
			dist = moved - margin
		var dest := tpos + dir * dist
		var down_size: float = up_d if attempt > 2 else dist + up_d + 62.0 * u   # sStepSizeDown
		var down_len := down_size
		if test_move(Transform3D(global_transform.basis, dest), Vector3.DOWN * down_size, res):
			down_len = res.get_travel().length()
			if res.get_normal().y > max_slope_cos and not (res.get_collider() is CharacterBody3D):
				newpos = dest + Vector3.DOWN * maxf(0.0, down_len - margin)
				ok = true
				break
		if attempt == 2 and dist > up_d - down_len:
			return
	if not ok or (newpos - start).length() < margin:
		return
	# krok tylko, gdy sięga dalej niż sam ruch z poślizgiem: wynik schodka krótszy od poślizgu cofał aktora
	# co klatkę do punktu tuż przed startem (zatrzymanie z prędkością ≠ 0 i bez kontaktu ze ścianą)
	var stepped := newpos - start
	stepped.y = 0.0
	if stepped.length() <= slid.length():
		return
	global_position = newpos
	velocity.y = 0.0
	apply_floor_snap()
