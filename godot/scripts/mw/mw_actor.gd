extends CharacterBody3D
## MWActor – wspólna podstawa gracza, NPC i stworzeń (plan, rewizja 2.0, §2.5).
##
## Aktor ma wspólny ruch (chód, bieg, skok, latanie, grawitacja, kolizja kapsułą) i dane (rekord, sid,
## statystyki – etap 4, wygląd – etap 2). Różnice między rodzajami realizują KONTROLERY: węzeł z metodą
## control(actor, delta), który ustawia intencje aktora (move_input, want_run, want_jump, obrót).
## Gracz: mw_player_controller.gd (wejście + kamera); NPC/stworzenia: kontrolery AI (etap 8).

signal controller_changed(controller: Node)

@export var walk_speed := 3.2      # m/s (ok. 230 jedn./s – prędkość chodu w grze to ~100–200 jedn./s)
@export var run_speed := 6.5
@export var fly_speed := 25.0
@export var jump_velocity := 4.5
var kind := "npc"                  # player | npc | creature
var record_id := ""                # id rekordu NPC_/CREA (gracz: "player")
var sid := ""                      # stabilny id referencji w świecie ("" dla gracza)
var stats := {}                    # etap 4: atrybuty, umiejętności, zdrowie…
var fly := false

# intencje ustawiane przez kontroler w każdej klatce fizyki
var move_input := Vector2.ZERO     # x: w prawo, y: do tyłu (jak Input.get_vector)
var want_run := false
var want_jump := false

var controller: Node = null:
	set(c):
		controller = c
		controller_changed.emit(c)

func _ready() -> void:
	var col := CollisionShape3D.new()
	col.name = "Capsule"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
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
	var speed := run_speed if want_run else walk_speed
	var wish := (transform.basis * Vector3(move_input.x, 0, move_input.y)).normalized() * speed
	velocity.x = wish.x
	velocity.z = wish.z
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	elif want_jump:
		velocity.y = jump_velocity
	want_jump = false
	move_and_slide()
