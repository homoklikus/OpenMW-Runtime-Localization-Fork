extends Node
## Kontroler gracza dla MWActor: akcje wejścia (ruch, bieg, skok, latanie) i kamera pierwszoosobowa z myszą.

var actor: CharacterBody3D
var cam: Camera3D
var mouse_sens := 0.0025
var invert_y := false

func attach(a: CharacterBody3D) -> void:
	actor = a
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position.y = 1.65
	cam.far = 4000.0
	a.add_child(cam)
	cam.current = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func control(a, _delta: float) -> void:
	a.move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	a.want_run = Input.is_action_pressed("run")
	if Input.is_action_just_pressed("jump"):
		a.want_jump = true

func _unhandled_input(e: InputEvent) -> void:
	if actor == null:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		actor.rotate_y(-e.relative.x * mouse_sens)
		var dy: float = e.relative.y * (-1.0 if invert_y else 1.0)
		cam.rotation.x = clampf(cam.rotation.x - dy * mouse_sens, -1.5, 1.5)
	elif e.is_action_pressed("toggle_fly"):
		actor.fly = not actor.fly
