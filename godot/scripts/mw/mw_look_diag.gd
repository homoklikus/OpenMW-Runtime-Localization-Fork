extends Node
## Diagnostyka obrotu kamery gracza (etap 10, zgłoszenie: samoczynny obrót po wczytaniu gry).
## Co klatkę: zmiana odchylenia gracza (yaw) i pochylenia kamery (pitch) rozdzielona na źródła zgłoszone przez
## wejście – „mouse” (InputEventMouseMotion w trybie przechwyconym), „pad” (prawa gałka), „script” (SetAngle,
## Position…), „state” (wczytanie zapisu, podróż, zmiana komórki – ustawienie orientacji) – oraz resztę „other”
## (obrót bez zgłoszonego źródła: logika kamery, fizyka, AI). Włączenie: argument --look-diag (wypisuje
## MWGODOT_LOOK co sekundę, gdy coś obróciło kamerę); sumy zawsze dostępne dla testów (totals, frames_moving).

var main
var verbose := false
var totals := {}                 # źródło → [|yaw|, |pitch|]
var frames_moving := 0           # klatki z obrotem
var frames_other := 0            # klatki z obrotem bez źródła
var _frame := {}
var _last_yaw := NAN
var _last_pitch := NAN
var _t := 0.0
var _info := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000         # po kontrolerach i padzie

func reset() -> void:
	totals = {}
	frames_moving = 0
	frames_other = 0
	_frame = {}
	_last_yaw = NAN

## Zgłoszenie obrotu przez źródło (rad); info – szczegóły do wypisania (np. osie pada, urządzenie).
func add(source: String, yaw: float, pitch: float, info := {}) -> void:
	var f: Array = _frame.get(source, [0.0, 0.0])
	_frame[source] = [f[0] + yaw, f[1] + pitch]
	if not info.is_empty():
		_info[source] = info

## Orientacja ustawiona wprost (wczytanie, podróż, skrypt) – bez liczenia jako ruch.
func mark(source: String) -> void:
	_frame[source] = _frame.get(source, [0.0, 0.0])
	_last_yaw = NAN

func _current() -> Vector2:
	var pl = main.player if main != null else null
	if pl == null:
		return Vector2(NAN, NAN)
	var cam: Node3D = pl.get_node_or_null("Camera3D")
	return Vector2(pl.rotation.y, cam.rotation.x if cam != null else 0.0)

func _physics_process(dt: float) -> void:
	_step(dt)

func _step(dt: float) -> void:
	var c := _current()
	if is_nan(c.x):
		return
	if not is_nan(_last_yaw):
		var dyaw := wrapf(c.x - _last_yaw, -PI, PI)
		var dpitch := c.y - _last_pitch
		var known_yaw := 0.0
		var known_pitch := 0.0
		for src in _frame:
			known_yaw += absf(float(_frame[src][0]))
			known_pitch += absf(float(_frame[src][1]))
		var other_yaw := maxf(0.0, absf(dyaw) - known_yaw)
		var other_pitch := maxf(0.0, absf(dpitch) - known_pitch)
		if absf(dyaw) > 1e-6 or absf(dpitch) > 1e-6:
			frames_moving += 1
			if other_yaw > 1e-5 or other_pitch > 1e-5:
				frames_other += 1
				_frame["other"] = [other_yaw, other_pitch]
		for src in _frame:
			var t: Array = totals.get(src, [0.0, 0.0])
			totals[src] = [t[0] + absf(float(_frame[src][0])), t[1] + absf(float(_frame[src][1]))]
	_last_yaw = c.x
	_last_pitch = c.y
	_frame = {}
	if verbose:
		_t += dt
		if _t >= 1.0:
			_t = 0.0
			if frames_moving > 0:
				var parts := []
				for src in totals:
					parts.append("%s=%.4f/%.4f" % [src, totals[src][0], totals[src][1]])
				print("MWGODOT_LOOK frames=%d other_frames=%d %s pads=%s info=%s" % [frames_moving, frames_other, " ".join(parts),
					_pads(), JSON.stringify(_info)])
				reset()

static func _pads() -> Array:
	var out := []
	for id in Input.get_connected_joypads():
		var ax := []
		for a in 6:
			ax.append(snappedf(Input.get_joy_axis(id, a), 0.01))
		out.append({"id": id, "name": Input.get_joy_name(id), "known": Input.is_joy_known(id), "axes": ax})
	return out
