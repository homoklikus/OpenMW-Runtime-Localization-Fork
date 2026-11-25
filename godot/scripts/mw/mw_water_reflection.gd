extends Node
## Odbicie wody jak OpenMW 0.51 (apps/openmw/mwrender/water.cpp, klasa Reflection): osobna kamera renderuje do
## tekstury (RTT, [Water] rtt size, domyślnie 512) świat odbity względem poziomu wody bieżącej komórki
## (mViewMatrix = scale(1, 1, −1) · translate(0, 0, 2 · poziom)), z odcięciem tego, co pod wodą (ClipCullNode), bez
## cieni; maska wg [Water] reflection detail (calcNodeMask: 0 – niebo, 1 – teren, 2 – świat (statyczne), 3 – obiekty,
## 4 – aktorzy i gracz, 5 – roślinność; we wnętrzach co najmniej 2). Shader wody próbkuje teksturę we współrzędnych
## ekranu z odwróconym Y (water.frag: screenCoords.y = 1 − y), z przesunięciem od fal.
## W Godocie kamera odbicia stoi w odbitym punkcie z odbitym kierunkiem (bez macierzy lustrzanej – obraz różni się
## tylko odwróceniem pionu, które usuwa próbkowanie 1 − y). Odcięcie pod wodą: teren odrzuca fragmenty poniżej
## poziomu wody w przebiegu odbicia (warstwa REFLECTION_PASS w CAMERA_VISIBLE_LAYERS); siatki statyczne z GLB nie mają
## płaszczyzny odcięcia (Godot nie ma ukośnej płaszczyzny bliskiej ani płaszczyzn obcinania).

const LAYER_DEFAULT := 1                 # statyczne, przedmioty, drzwi… (Mask_Static / Mask_Object)
const LAYER_WATER := 1 << 10
const LAYER_ACTOR := 1 << 11             # Mask_Actor / Mask_Player
const LAYER_GROUNDCOVER := 1 << 12       # Mask_Groundcover
const LAYER_TERRAIN := 1 << 13           # Mask_Terrain
const REFLECTION_PASS := 1 << 19         # znacznik przebiegu odbicia (shader terenu)
const MAIN_MASK := 0xFFFFF & ~REFLECTION_PASS

var main = null
var vp: SubViewport
var cam: Camera3D
var detail := 2                          # [Water] reflection detail
var rtt_size := 512                      # [Water] rtt size
var active := false
var water_y := -INF

func _ready() -> void:
	process_priority = 100               # po kamerze gracza (mw_camera.frame w _process kontrolera)
	vp = SubViewport.new()
	vp.name = "ReflectionViewport"
	vp.own_world_3d = false
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0  # disableShadowsForStateSet
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(rtt_size, rtt_size)
	add_child(vp)
	cam = Camera3D.new()
	cam.name = "ReflectionCamera"
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)

## calcNodeMask.
static func node_mask(reflection_detail: int, interior: bool) -> int:
	var d := clampi(reflection_detail, 2 if interior else 0, 5)
	var m := REFLECTION_PASS
	if d >= 1:
		m |= LAYER_TERRAIN
	if d >= 2:
		m |= LAYER_DEFAULT
	if d >= 4:
		m |= LAYER_ACTOR
	if d >= 5:
		m |= LAYER_GROUNDCOVER
	return m

## Warstwy renderowania wszystkich siatek węzła (aktorzy, roślinność, teren, woda).
static func set_layers(n: Node, bits: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = bits
	for c in n.find_children("*", "VisualInstance3D", true, false):
		if not (c is Light3D):
			(c as VisualInstance3D).layers = bits

func configure(reflection_detail: int, size: int) -> void:
	detail = clampi(reflection_detail, 0, 5)
	rtt_size = clampi(size, 128, 4096)

func _process(_dt: float) -> void:
	var Env = load("res://scripts/mw/mw_environment.gd")
	var on: bool = main != null and main.player != null and Env.water_mode == "shader" and Env.water_visible \
			and float(main.player.water_level) > -1e9 and String(main.get("game_state")) != "nogame"
	var view: Camera3D = main.view_camera() if on and main.has_method("view_camera") else null
	on = on and view != null
	if on != active:
		active = on
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	Env.set_reflection(vp.get_texture() if on else null)
	if not on:
		return
	water_y = float(main.player.water_level)
	RenderingServer.global_shader_parameter_set("mw_water_clip_y", water_y)
	var size: Vector2 = main.get_viewport().get_visible_rect().size
	var aspect: float = size.x / maxf(size.y, 1.0)
	var want := Vector2i(maxi(int(round(rtt_size * aspect)), 1), rtt_size)
	if vp.size != want:
		vp.size = want
	# Reflection::setWaterLevel: odbicie pozycji i kierunku względem płaszczyzny y = poziom wody
	var t := view.global_transform
	var p := t.origin
	var rp := Vector3(p.x, 2.0 * water_y - p.y, p.z)
	var f := -t.basis.z
	var rf := Vector3(f.x, -f.y, f.z)
	var up := Vector3.UP if absf(rf.normalized().y) < 0.999 else Vector3.FORWARD
	cam.look_at_from_position(rp, rp + rf, up)
	cam.fov = view.fov
	cam.near = view.near
	cam.far = view.far
	var interior := not String(main.get("interior")).is_empty()
	cam.cull_mask = node_mask(detail, interior) if view.cull_mask != 0 else REFLECTION_PASS     # ToggleWorld
