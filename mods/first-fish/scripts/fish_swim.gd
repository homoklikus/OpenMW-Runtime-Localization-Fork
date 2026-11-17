extends Node3D
## Pływanie rybki (first-fish): bardzo proste błądzenie w małym obszarze wody.
## * cel losowany w kole o promieniu `radius` wokół `home`, tylko tam, gdzie woda ma co najmniej
##   min_depth + min_clearance (inaczej losowanie powtarzane);
## * kurs zmienia się płynnie (ograniczona prędkość obrotu), prędkość lekko się waha;
## * wysokość zawsze między dnem + min_clearance a lustrem wody − min_depth (nie wyskakuje, nie wbija się w dno);
## * animacja swim_idle w pętli, tempo zależne od prędkości.
## Ustawiane przez ładowarkę modów: home, radius (m), water_y (m), ground (Callable(x, z) -> y), params, rng.

var home := Vector3.ZERO
var radius := 3.0
var water_y := 0.0
var ground: Callable
var params := {}
var rng := RandomNumberGenerator.new()

var speed := 0.25
var turn_rate := deg_to_rad(70.0)
var min_depth := 0.25
var min_clearance := 0.20
var _target := Vector3.ZERO
var _retarget_t := 0.0
var _yaw := 0.0
var _speed_k := 1.0
var _anim: AnimationPlayer
var travelled := 0.0          # do testów: przebyta droga (m)
var violations := 0           # do testów: klatki nad lustrem wody albo w dnie

func _ready() -> void:
	speed = float(params.get("speed", speed))
	turn_rate = deg_to_rad(float(params.get("turn_rate_deg", 70.0)))
	min_depth = float(params.get("min_depth", min_depth))
	min_clearance = float(params.get("min_clearance", min_clearance))
	_yaw = rng.randf() * TAU
	_pick_target()
	for ap in find_children("*", "AnimationPlayer", true, false):
		_anim = ap
		break
	if _anim != null:
		var name: String = String(params.get("animation", "swim_idle"))
		if _anim.has_animation(name):
			_anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
			_anim.play(name)
			_anim.seek(rng.randf(), true)            # każda rybka w innej fazie

func _band(x: float, z: float) -> Vector2:
	var g: float = float(ground.call(x, z)) if ground.is_valid() else water_y - 10.0
	return Vector2(g + min_clearance, water_y - min_depth)   # (dół, góra)

func _pick_target() -> void:
	for i in 12:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := home + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var b := _band(p.x, p.z)
		if b.y - b.x >= 0.15:
			p.y = lerpf(b.x, b.y, rng.randf_range(0.25, 0.75))
			_target = p
			_retarget_t = rng.randf_range(4.0, 9.0)
			_speed_k = rng.randf_range(0.7, 1.3)
			return
	_target = home
	_retarget_t = 2.0

func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	_retarget_t -= dt
	var to := _target - global_position
	if _retarget_t <= 0.0 or Vector2(to.x, to.z).length() < 0.3:
		_pick_target()
		to = _target - global_position
	# kurs: obrót w poziomie z ograniczoną prędkością (przód węzła to −Z)
	var want := atan2(-to.x, -to.z)
	var diff := wrapf(want - _yaw, -PI, PI)
	_yaw += clampf(diff, -turn_rate * dt, turn_rate * dt)
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var v := speed * _speed_k * (0.6 + 0.4 * clampf(1.0 - absf(diff) / PI, 0.0, 1.0))
	var p := global_position + fwd * v * dt
	p.y = move_toward(p.y, _target.y, 0.08 * dt)
	# nie wypływa poza obszar ani do zbyt płytkiej wody
	var off := Vector2(p.x - home.x, p.z - home.z)
	if off.length() > radius * 1.2:
		_pick_target()
		p = global_position
	var b := _band(p.x, p.z)
	if b.y - b.x < 0.05:
		_pick_target()                 # płycizna przed nosem – zawróć, nie wchodź
		p = global_position
		b = _band(p.x, p.z)
	p.y = clampf(p.y, b.x, maxf(b.x, b.y))
	if p.y > water_y - 0.05 or p.y < float(ground.call(p.x, p.z)) + 0.02 if ground.is_valid() else false:
		violations += 1                # nad wodą albo w dnie (tylko gdy pas wody jest pusty)
	travelled += (p - global_position).length()
	global_position = p
	var pitch := clampf((_target.y - p.y) * 0.8, -0.25, 0.25)
	rotation = Vector3(pitch, _yaw, 0.0)
	if _anim != null:
		_anim.speed_scale = 0.6 + 0.8 * v / maxf(speed, 0.01)
