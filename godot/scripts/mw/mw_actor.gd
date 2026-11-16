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
## Kapsuła kolizji (NPC: stała; stworzenia: z wymiarów modelu – etap 8) i aktorzy bez grawitacji (stworzenia
## latające/wodne, które nie chodzą – jak isPureFlyingCreature/isPureWaterCreature).
var capsule_radius := 0.35
var capsule_height := 1.8
var no_gravity := false

# intencje ustawiane przez kontroler w każdej klatce fizyki
var move_input := Vector2.ZERO     # x: w prawo, y: do tyłu (jak Input.get_vector)
var want_run := false
var want_jump := false
var want_sneak := false            # skradanie (etap 8: wykrywanie)

var controller: Node = null:
	set(c):
		controller = c
		controller_changed.emit(c)

func _ready() -> void:
	if not collide:
		return
	var col := CollisionShape3D.new()
	col.name = "Capsule"
	var cap := CapsuleShape3D.new()
	cap.radius = capsule_radius
	cap.height = maxf(capsule_height, capsule_radius * 2.0)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)

## Baza kierunku latania: kamera, jeśli aktor ją ma (gracz), inaczej sam aktor.
func look_basis() -> Basis:
	var cam := get_node_or_null("Camera3D") as Node3D
	return cam.global_transform.basis if cam else global_transform.basis

func _physics_process(delta: float) -> void:
	if controller != null and controller.has_method("control"):
		controller.control(self, delta)
	step(delta)

## Ruch z bieżących intencji (wspólny dla wszystkich aktorów).
func step(delta: float) -> void:
	if fly:
		var d := look_basis() * Vector3(move_input.x, 0, move_input.y)
		velocity = d * fly_speed * (3.0 if want_run else 1.0)
		global_position += velocity * delta
		want_jump = false
		return
	swimming = global_position.y + height * swim_height_scale < water_level
	if swimming:
		_fall_start = NAN
		# kierunek ruchu wg patrzenia (także w górę/w dół), skok = w górę; nie wyżej niż powierzchnia
		var d := look_basis() * Vector3(move_input.x, 0, move_input.y)
		if want_jump:
			d += Vector3.UP
		velocity = d.normalized() * swim_speed * (1.5 if want_run else 1.0) if d.length() > 0.01 else Vector3.ZERO
		var max_y := water_level - height * swim_height_scale - 0.01     # przy powierzchni nadal pływa
		if global_position.y + velocity.y * delta > max_y and velocity.y > 0.0:
			velocity.y = maxf(0.0, (max_y - global_position.y) / maxf(delta, 1e-4))
		want_jump = false
		move_and_slide()
		return
	var speed := run_speed if want_run else walk_speed
	var wish := (transform.basis * Vector3(move_input.x, 0, move_input.y)).normalized() * speed
	if not is_on_floor():
		wish *= air_factor
	velocity.x = wish.x
	velocity.z = wish.z
	if no_gravity:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	elif want_jump and jump_velocity > 0.0:
		# skok w ruchu: wektor (kierunek, 1) × wysokość × 0,707 (character.cpp) – pionowo 0,707 prędkości skoku
		velocity.y = jump_velocity * (0.707 if move_input.length() > 0.01 else 1.0)
		jumped.emit()
	want_jump = false
	var was_floor := is_on_floor()
	move_and_slide()
	if not is_on_floor():
		if is_nan(_fall_start) or global_position.y > _fall_start:
			_fall_start = global_position.y
	elif not was_floor and not is_nan(_fall_start):
		landed.emit((_fall_start - global_position.y) * MWCoords.UNITS_PER_METER)
		_fall_start = NAN
