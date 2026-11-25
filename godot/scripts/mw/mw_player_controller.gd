extends Node
## Kontroler gracza dla MWActor: akcje wejścia (ruch, bieg, skok, latanie), rozglądanie myszą i kamera (mw_camera.gd:
## pierwsza i trzecia osoba, podgląd, vanity – jak OpenMW 0.51).

const CameraScript := preload("res://scripts/mw/mw_camera.gd")

var actor: CharacterBody3D
var cam: Camera3D
var mouse_sens := 0.0025
var invert_y := false
var invert_x := false               # [Input] invert x axis
var diag = null                     # mw_look_diag.gd (main.look_diag)
var allowed: Callable = Callable()   # etap 9: blokady sterowania ze skryptów (main.control_allowed)
var always_run := false             # ustawienie alwaysRun (playercontrols.lua: run = Run ~= alwaysRun)
var auto_move := false              # A_AutoMove (playercontrols.lua: ruch do przodu do pierwszego ruchu przód/tył)
var camera = null                   # mw_camera.gd

func _ok(kind: String) -> bool:
	return not allowed.is_valid() or bool(allowed.call(kind))

func attach(a: CharacterBody3D) -> void:
	actor = a
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position.y = 1.65
	cam.far = 4000.0
	a.add_child(cam)
	cam.current = true
	camera = CameraScript.new()
	camera.name = "Camera"
	add_child(camera)
	camera.setup(a, cam)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func control(a, _delta: float) -> void:
	if not _ok("controls"):          # DisablePlayerControls: bez ruchu i skoku (rozglądanie wg …Looking)
		a.move_input = Vector2.ZERO
		a.want_run = false
		a.want_jump = false
		return
	a.move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# processMovement: ruch przód/tył wyłącza AutoMove; bez niego AutoMove daje pełny ruch do przodu
	if a.move_input.y != 0.0:
		auto_move = false
	elif auto_move:
		a.move_input.y = -1.0
	a.want_run = Input.is_action_pressed("run") != always_run
	a.want_sneak = InputMap.has_action("sneak") and Input.is_action_pressed("sneak")
	if a.want_sneak:
		a.want_run = false
	if Input.is_action_just_pressed("jump") and _ok("jumping") and not pad_cycle_combo():
		a.want_jump = true

## BindingsManager::actionValueChanged: z padem skok przy wciśniętym „broń”/„magia” to Cycle*Left, nie skok.
static func pad_cycle_combo() -> bool:
	var pad := false
	for d in Input.get_connected_joypads():
		if Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.6 or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.6:
			pad = true
	return pad and (Input.is_action_pressed("ready_weapon") or Input.is_action_pressed("ready_magic"))

func _process(delta: float) -> void:
	if camera != null:
		camera.frame(delta)

## Obrót widoku (mysz, prawa gałka): w podglądzie i vanity obraca kamerę (World::vanityRotateCamera), inaczej gracza.
func look(yaw: float, pitch: float) -> void:
	if camera != null and camera.rotate_view(-yaw, -pitch):
		return
	if not _ok("looking"):
		return
	actor.rotate_y(-yaw)
	cam.rotation.x = clampf(cam.rotation.x - pitch, -1.5, 1.5)

func _input(e: InputEvent) -> void:
	# MouseManager::mouseMoved, BindingsManager::actionValueChanged: każde wejście zeruje czas bezczynności
	if camera != null and (e is InputEventMouseMotion or e is InputEventKey or e is InputEventMouseButton \
			or e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.2)):
		camera.note_input()

func _unhandled_input(e: InputEvent) -> void:
	if actor == null:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var yaw: float = e.relative.x * (-1.0 if invert_x else 1.0) * mouse_sens
		var dy: float = e.relative.y * (-1.0 if invert_y else 1.0)
		var p0 := cam.rotation.x
		look(yaw, dy * mouse_sens)
		if diag != null:
			diag.add("mouse", yaw, cam.rotation.x - p0, {"relative": e.relative})
	elif camera != null and e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e.is_action("zoom_in") or e.is_action("zoom_out")):
		# ZoomIn / ZoomOut (kółko): zoomInOut ± 1 na ząbek
		camera.add_zoom(1.0 if e.is_action("zoom_in") else -1.0)
	elif camera != null and e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo \
			and (e.is_action("zoom_in") or e.is_action("zoom_out")):
		camera.add_zoom(1.0 if e.is_action("zoom_in") else -1.0)
	elif e.is_action_pressed("toggle_fly"):
		actor.fly = not actor.fly
