extends Node
## Kamera gracza jak OpenMW 0.51 – MWRender::Camera (camera.cpp) i skrypty omw/camera (camera.lua, third_person.lua):
##  - tryby FirstPerson / ThirdPerson / Preview / Vanity, tryb główny (primaryMode: pierwsza albo trzecia osoba);
##  - TogglePOV (Tab, prawa gałka): krótkie wciśnięcie (≤ 0,25 s) przełącza widok, przytrzymanie – podgląd (Preview,
##    mysz obraca kamerę wokół gracza); w trzeciej osobie podgląd od razu po wciśnięciu;
##  - Zoom3rdPerson (kółko myszy: ZoomIn ±10 j. na ząbek; pad – spusty przy wciśniętym TogglePOV, 100 j./s):
##    odległość bazowa 192 j. w zakresie 30–800, przybliżenie przy 30 → pierwsza osoba, oddalenie w pierwszej → trzecia
##    osoba z odległością 30 (camera.lua zoom, z poprawką o przeszkodę);
##  - Vanity: bezczynność dłuższa niż fVanityDelay (+0,5 s InputManager::isIdle) – kamera obraca się wokół gracza
##    (3°/s), dowolne wejście wraca do trybu głównego; blokada DisableVanityMode;
##  - punkt śledzenia: początek aktora + mHeight (124 j.) × skala, w pierwszej osobie – oko (węzeł „Camera3D”);
##  - kolizja (Camera::updatePosition): punkt ogniskowy sprawdzany sferą 10 j. w górę (+10 j. – głowa ponad kapsułą),
##    kamera – sferą 5 j. od punktu do pozycji docelowej; kolizje bez aktorów (CollisionType_Default & ~Actor);
##  - obrót odroczony po podglądzie (deferredPreviewRotation = false – mDeferredRotationDisabled): kamera wraca za
##    gracza z prędkością min(Δ, (Δ + 1) · 3 · dt);
##  - celownik (updateCrosshair): tylko w pierwszej osobie (viewOverShoulder = false), nie w trybie GUI.
## Ustawienia strony „Camera” z omw/camera/settings.lua (viewOverShoulder, previewIfStandStill, move360, head bobbing…)
## mają wartości domyślne OpenMW (wyłączone) – port nie ma strony ustawień skryptów Lua, więc nie są przełączalne.

const UPM := 69.99125109                  # MWCoords.UNITS_PER_METER
const HEIGHT := 124.0                     # Camera::mHeight
const CAMERA_OBSTACLE_LIMIT := 5.0
const FOCAL_OBSTACLE_LIMIT := 10.0
const MIN_DISTANCE := 30.0                # camera.lua minDistance / maxDistance
const MAX_DISTANCE := 800.0
const SWITCH_LIMIT := 0.25                # updatePOV switchLimit
const PITCH_LIMIT := PI / 2.0 - 0.000001  # Camera::setPitch

var actor: CharacterBody3D
var eye: Camera3D                         # oko gracza (pierwsza osoba; kierunek celowania, pociski, linia wzroku)
var view: Camera3D                        # kamera trzeciej osoby / podglądu / vanity
var main = null                           # main.gd (GMST, blokady, efekty, tryb GUI)
var mode := "first"                       # first | third | preview | vanity
var primary := "first"
var first_person_view := true             # mFirstPersonView
var base_distance := 192.0                # third_person.baseDistance (zapisywane – onSave)
var preferred_distance := 0.0             # third_person.preferredDistance
var camera_distance := 0.0                # mCameraDistance (po kolizji)
var _pref_camera_distance := 0.0          # mPreferredCameraDistance
var yaw := 0.0                            # obrót kamery wokół Y (jak rotation.y w Godocie)
var pitch := 0.0                          # pochylenie kamery (jak rotation.x – dodatnie w górę)
var deferred := Vector2.ZERO              # mDeferredRotation (x – pochylenie, y – obrót)
var deferred_disabled := false
var deferred_allowed := false             # allowCharacterDeferredRotation(deferredPreviewRotation = false)
var preview_timer := 0.0
var idle_input := 0.0                     # ActionManager::mTimeIdle
var idle_timer := 0.0                     # camera.lua idleTimer
var zoom_input := 0.0                     # zebrane ZoomIn/ZoomOut (×10) do następnej klatki
var cam_position := Vector3.ZERO          # mPosition
var tracked := Vector3.ZERO               # mTrackedPosition
var queued := ""                          # mQueuedMode – zmiana z/na pierwszą osobę czeka na upperBodyReady
var listener: AudioListener3D            # World::updateSoundListener poza pierwszą osobą
var _no_tpp_last_frame := true
var _exclude: Array[RID] = []
var _exclude_t := 0.0
var _sphere_cam := SphereShape3D.new()
var _sphere_focal := SphereShape3D.new()

func setup(a: CharacterBody3D, e: Camera3D) -> void:
	actor = a
	eye = e
	view = Camera3D.new()
	view.name = "ViewCamera"
	view.top_level = true
	view.far = eye.far
	view.fov = eye.fov
	a.add_child(view)
	listener = AudioListener3D.new()
	listener.name = "Listener"
	a.add_child(listener)
	_sphere_cam.radius = CAMERA_OBSTACLE_LIMIT / UPM
	_sphere_focal.radius = FOCAL_OBSTACLE_LIMIT / UPM
	yaw = a.rotation.y
	pitch = eye.rotation.x

func is_first_person() -> bool:
	return mode == "first"

## Kamera, przez którą widać świat (bieżąca kamera widoku).
func render_camera() -> Camera3D:
	return eye if mode == "first" else view

func make_current() -> void:
	var c := render_camera()
	var other := view if c == eye else eye
	if not c.current:
		c.cull_mask = other.cull_mask          # TCL/TW z konsoli działa na bieżącą kamerę
		c.current = true

func _allowed(kind: String) -> bool:
	return main == null or not main.has_method("control_allowed") or bool(main.control_allowed(kind))

func _gmst(id: String, def: float) -> float:
	if main != null and main.get("combat") != null and main.combat != null:
		return float(main.combat._gmst(id, def))
	return def

func _gui_or_paused() -> bool:
	if actor.get_tree().paused:
		return true
	return main != null and main.get("gui") != null and main.gui != null and main.gui.is_gui_mode()

func _paralyzed() -> bool:
	if main == null or bool(main.get("god_mode")) or main.get("magic") == null or main.magic == null or main.combat == null:
		return false
	return float(main.magic.magnitude_of(main.combat.player_fighter(), main.magic.FX_PARALYZE)) > 0.0

# --- Camera::setMode / instantTransition / obrót odroczony -----------------------------------------------------

func set_mode(new_mode: String, force := false) -> void:
	if mode == new_mode:
		queued = ""
		return
	var old := mode
	if not force and (new_mode == "first" or old == "first") and not _upper_body_ready():
		queued = new_mode                  # zmiana widoku przerwałaby ważną animację (śmierć, powalenie…)
		return
	queued = ""
	mode = new_mode
	if new_mode == "first":
		first_person_view = true
	elif new_mode == "third":
		first_person_view = false
	_calculate_deferred_rotation()
	if old == "first" or new_mode == "first":
		instant_transition()
	make_current()
	_view_changed()

## Camera::toggleViewMode (TogglePOV ze skryptu, PCForce1st/3rdPerson).
func toggle_view_mode(force := false) -> void:
	set_mode("third" if first_person_view else "first", force)
	primary = mode if mode in ["first", "third"] else primary

## Camera::toggleVanityMode (ToggleVanityMode ze skryptu).
func toggle_vanity_mode(enable: bool) -> bool:
	if not enable:
		set_mode("first" if first_person_view else "third")
	elif _allowed("vanitymode"):
		set_mode("vanity")
	return (mode == "vanity") == enable

## World::useDeathCamera: animacje pierwszej osoby nie mają śmierci – przełączenie na trzecią osobę.
func use_death_camera() -> void:
	set_mode("third", true)

## Animation::upperBodyReady: brak animacji o priorytecie trafienia, broni, powalenia albo śmierci.
func _upper_body_ready() -> bool:
	return actor == null or not actor.has_method("upper_body_ready") or bool(actor.upper_body_ready())

func instant_transition() -> void:
	deferred_disabled = false
	deferred = Vector2.ZERO
	_no_tpp_last_frame = true
	rotate_to_player()

## Camera::rotateCameraToTrackingPtr.
func rotate_to_player() -> void:
	pitch = clampf(eye.rotation.x - deferred.x, -PITCH_LIMIT, PITCH_LIMIT)
	yaw = wrapf(actor.rotation.y - deferred.y, -PI, PI)

func _calculate_deferred_rotation() -> void:
	if mode in ["preview", "vanity"]:
		return
	if first_person_view:
		instant_transition()
		return
	deferred = Vector2(wrapf(eye.rotation.x - pitch, -PI, PI), wrapf(actor.rotation.y - yaw, -PI, PI))
	if not deferred_allowed:
		deferred_disabled = true

## Camera::applyDeferredPreviewRotationToPlayer (tylko trzecia osoba).
func _apply_deferred(dt: float) -> void:
	if mode != "third":
		return
	var rot := deferred
	var delta := rot.length()
	if delta > 0.0:
		rot /= delta
	delta = minf(delta, (delta + 1.0) * 3.0 * dt)
	rot *= delta
	deferred -= rot
	if deferred_disabled:
		deferred_disabled = delta > 0.0001
		rotate_to_player()
		return
	actor.rotate_y(rot.y)                  # movement.mRotation – obrót gracza (deferredPreviewRotation = true)
	eye.rotation.x = clampf(eye.rotation.x + rot.x, -1.5, 1.5)

## World::vanityRotateCamera: w podglądzie i vanity mysz obraca kamerę zamiast gracza.
func rotate_view(dyaw: float, dpitch: float) -> bool:
	if not (mode in ["preview", "vanity"]):
		return false
	pitch = clampf(pitch + dpitch, -PITCH_LIMIT, PITCH_LIMIT)
	yaw = wrapf(yaw + dyaw, -PI, PI)
	return true

## Wejście gracza (MouseManager/BindingsManager::resetIdleTime).
func note_input() -> void:
	idle_input = 0.0

## ZoomIn / ZoomOut (actionbindings.lua: zoomInOut × 10).
func add_zoom(clicks: float) -> void:
	zoom_input += clicks * 10.0

# --- camera.lua -------------------------------------------------------------------------------------------------

func _update_pov(dt: float) -> void:
	if Input.is_action_pressed("toggle_pov") and _allowed("viewswitch"):
		preview_timer += dt
		if primary == "third" or preview_timer >= SWITCH_LIMIT:
			set_mode("preview")
	elif preview_timer > 0.0:
		if preview_timer <= SWITCH_LIMIT:
			primary = "third" if primary == "first" else "first"
		set_mode(primary)
		if mode == "preview":
			# zmiana Preview → pierwsza osoba w kolejce: najpierw wyjście z podglądu do trzeciej osoby
			set_mode("third")
			set_mode("first")
		preview_timer = 0.0

func _update_vanity(dt: float) -> void:
	var allowed := _allowed("vanitymode")
	if allowed and idle_timer > _gmst("fVanityDelay", 30.0) and mode != "vanity":
		set_mode("vanity")
	if mode == "vanity":
		if not allowed or idle_timer == 0.0:
			set_mode(primary)
		else:
			yaw = wrapf(yaw - deg_to_rad(3.0) * dt, -PI, PI)     # camera.setYaw(getYaw() + 3°·dt) – yaw Lua rośnie w prawo

func _update_idle(dt: float) -> void:
	var moving: bool = actor.get("move_input") != Vector2.ZERO or bool(actor.get("want_jump"))
	for act in ["move_forward", "move_back", "move_left", "move_right", "jump", "sneak", "toggle_pov"]:
		if InputMap.has_action(act) and Input.is_action_pressed(act):
			idle_input = 0.0
	if idle_input <= 0.5:                  # !input.isIdle()
		idle_timer = 0.0
	elif moving:
		idle_timer = 0.0
	else:
		idle_timer += dt
	idle_input += dt

func zoom(delta: float) -> void:
	if not _allowed("viewswitch") or not _allowed("controls"):
		return
	if mode != "first":
		var obstacle_delta := preferred_distance - camera_distance
		if delta > 0.0 and base_distance == MIN_DISTANCE and mode != "preview":
			primary = "first"
			set_mode(primary)
		elif delta > 0.0 or obstacle_delta < -delta:
			base_distance = clampf(base_distance - delta - obstacle_delta, MIN_DISTANCE, MAX_DISTANCE)
	elif delta < 0.0:
		primary = "third"
		set_mode(primary)
		base_distance = MIN_DISTANCE

func _pad_zoom(dt: float) -> float:
	if not Input.is_action_pressed("toggle_pov"):
		return 0.0
	var GP = load("res://scripts/mw/mw_gamepad.gd")
	var dev: int = GP.active_device
	if dev == GP.NO_DEVICE:
		return 0.0
	return (Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)) * 100.0 * dt

## onFrame (camera.lua) + Camera::update.
func frame(dt: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var gui := _gui_or_paused()
	if not queued.is_empty() and _upper_body_ready():
		set_mode(queued)
	if not gui and dt > 0.0:
		_update_idle(dt)
		if mode in ["first", "third"] and queued.is_empty():
			primary = mode
		if not _paralyzed():
			_update_pov(dt)
			_update_vanity(dt)
		var z := zoom_input + _pad_zoom(dt)
		zoom_input = 0.0
		if z != 0.0:
			zoom(z)
		# third_person.update (viewOverShoulder = false): odległość = odległość bazowa
		if mode == "first":
			_no_tpp_last_frame = true
		else:
			preferred_distance = base_distance
			_pref_camera_distance = base_distance
			_no_tpp_last_frame = false
		_apply_deferred(dt)
	else:
		zoom_input = 0.0
	if mode in ["first", "third"]:
		rotate_to_player()                 # RenderingManager::rotateObject → rotateCameraToTrackingPtr
	_update_position()
	_update_crosshair(gui)
	_update_listener()

## World::updateSoundListener ([Sound] camera listener = false): w pierwszej osobie – kamera, inaczej gracz na
## wysokości 1,85 × połowy wysokości kształtu, z obrotem gracza.
func _update_listener() -> void:
	if listener == null:
		return
	if mode == "first":
		if listener.is_current():
			listener.clear_current()
		return
	listener.position = Vector3(0, 1.85 * float(actor.get("height")) * 0.5, 0)
	listener.rotation = Vector3(eye.rotation.x, 0, 0)
	if not listener.is_current():
		listener.make_current()

func _update_crosshair(gui: bool) -> void:
	var hud = main.get("mw_hud") if main != null else null
	if hud != null and hud.get("camera_crosshair") != null:
		hud.camera_crosshair = mode == "first" and not gui

func _view_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

func _actor_scale() -> float:
	return actor.global_transform.basis.get_scale().y

## Camera::calculateTrackedPosition.
func tracked_position() -> Vector3:
	if mode == "first":
		return eye.global_position
	return actor.global_position + Vector3.UP * HEIGHT * _actor_scale() / UPM

func _refresh_exclude(space: PhysicsDirectSpaceState3D) -> void:
	_exclude_t -= get_process_delta_time()
	if _exclude_t > 0.0 and not _exclude.is_empty():
		return
	_exclude_t = 0.5
	_exclude.clear()
	_exclude.append(actor.get_rid())
	var scene := actor.get_parent()
	if scene == null:
		return
	for n in scene.find_children("*", "CharacterBody3D", true, false):
		_exclude.append((n as CharacterBody3D).get_rid())

## Część drogi [0, 1] do pierwszej przeszkody sferą (btCollisionWorld::convexSweepTest), 1 – bez przeszkody.
func _sweep(shape: SphereShape3D, from: Vector3, motion: Vector3) -> float:
	if motion.length_squared() < 1e-10:
		return 1.0
	var space := actor.get_world_3d().direct_space_state
	_refresh_exclude(space)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), from)
	q.motion = motion
	q.exclude = _exclude
	q.collide_with_areas = false
	var r := space.cast_motion(q)
	return float(r[0]) if r.size() > 0 else 1.0

## Camera::updatePosition.
func _update_position() -> void:
	tracked = tracked_position()
	if mode == "first":
		cam_position = tracked
		camera_distance = 0.0
		return
	var focal := tracked
	var focal_offset := Vector3(0, FOCAL_OBSTACLE_LIMIT / UPM, 0)      # przesunięcie ogniskowej 0 + 10 j. w górę
	var f := _sweep(_sphere_focal, focal - focal_offset, focal_offset)
	if f < 1.0:
		focal = focal - focal_offset + focal_offset * f
	camera_distance = _pref_camera_distance
	var b := _view_basis()
	var offset := b.z * camera_distance / UPM                          # orient · (0, −d, 0): za kamerą
	var c := _sweep(_sphere_cam, focal, offset)
	if c < 1.0:
		camera_distance *= c
		offset = b.z * camera_distance / UPM
	cam_position = focal + offset
	view.global_transform = Transform3D(b, cam_position)
	view.fov = eye.fov
	view.far = eye.far
	view.near = eye.near

func _view_changed() -> void:
	if actor != null and actor.has_method("camera_view_changed"):
		actor.camera_view_changed(mode == "first")

# --- zapis (REC_CAM_ FIRS + camera.lua onSave: distance) ---------------------------------------------------------

func save_data() -> Dictionary:
	return {"first_person": first_person_view, "distance": base_distance}

## StateManager::loadGame: toggleVanityMode(false), potem togglePOV, gdy zapis ma inny widok.
func load_data(d: Dictionary) -> void:
	queued = ""
	preview_timer = 0.0
	idle_timer = 0.0
	idle_input = 0.0
	if d.has("distance"):
		base_distance = clampf(float(d.distance), MIN_DISTANCE, MAX_DISTANCE)
	toggle_vanity_mode(false)
	if mode == "preview":
		set_mode("first" if first_person_view else "third")
	var fp := bool(d.get("first_person", true))
	if fp != first_person_view:
		toggle_view_mode(true)
	primary = "first" if first_person_view else "third"
	instant_transition()
	make_current()
