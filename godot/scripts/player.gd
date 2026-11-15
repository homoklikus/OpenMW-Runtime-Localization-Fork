extends CharacterBody3D
## Prosta postać pierwszoosobowa: WASD, mysz, spacja (skok), Shift (bieg), F (latanie/kamera swobodna).

@export var walk_speed := 3.2      # m/s (ok. 230 jedn./s – prędkość chodu w grze to ~100–200 jedn./s)
@export var run_speed := 6.5
@export var fly_speed := 25.0
@export var jump_velocity := 4.5
@export var mouse_sens := 0.0025
var fly := false
var cam: Camera3D

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position.y = 1.65
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * mouse_sens)
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * mouse_sens, -1.5, 1.5)
	elif e.is_action_pressed("toggle_fly"):
		fly = not fly
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var dir2 := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if fly:
		var basis_cam := cam.global_transform.basis
		var d := (basis_cam * Vector3(dir2.x, 0, dir2.y))
		velocity = d * fly_speed * (3.0 if Input.is_action_pressed("run") else 1.0)
		global_position += velocity * delta
		return
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	var wish := (transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized() * speed
	velocity.x = wish.x
	velocity.z = wish.z
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	move_and_slide()
