class_name MWEnvironment
extends Node3D
## Niebo, słońce, pora dnia, pogoda wg regionu i woda.
## Czas gry jak w Morrowindzie: skala 30 (1 s rzeczywista = 30 s gry, doba ≈ 48 min).

const TIMESCALE := 30.0
const WEATHER_FOG := {"clear": 0.0008, "cloudy": 0.0015, "foggy": 0.02, "overcast": 0.003, "rain": 0.006,
	"thunder": 0.008, "ash": 0.012, "blight": 0.015, "snow": 0.008, "blizzard": 0.03}
const WEATHER_TINT := {"clear": Color(0.55, 0.7, 1.0), "cloudy": Color(0.6, 0.65, 0.72), "foggy": Color(0.7, 0.72, 0.74),
	"overcast": Color(0.5, 0.52, 0.56), "rain": Color(0.4, 0.43, 0.48), "thunder": Color(0.3, 0.32, 0.36),
	"ash": Color(0.55, 0.42, 0.32), "blight": Color(0.6, 0.35, 0.3), "snow": Color(0.8, 0.82, 0.86),
	"blizzard": Color(0.85, 0.86, 0.88)}

var game_hour := 9.0
var day := 0
var time_running := true
var weather := "clear"
var region := ""
var interior := false
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ProceduralSkyMaterial
var regions := {}

func _ready() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	add_child(sun)
	apply()

func _process(delta: float) -> void:
	if time_running and not interior:
		advance(delta * TIMESCALE / 3600.0)

func advance(hours: float) -> void:
	game_hour += hours
	while game_hour >= 24.0:
		game_hour -= 24.0
		day += 1
		pick_weather()
	apply()

## Słońce: wschód 6:00, zachód 18:00 (uproszczenie); azymut od wschodu (+X) przez południe (+Z Godota).
static func sun_elevation_deg(hour: float) -> float:
	return sin((hour - 6.0) / 12.0 * PI) * 70.0

func apply() -> void:
	if sun == null:
		return
	if interior:
		sun.visible = false
		return
	var elev := sun_elevation_deg(game_hour)
	var azim := (game_hour - 6.0) / 12.0 * 180.0
	sun.visible = elev > -5.0
	sun.rotation_degrees = Vector3(-elev, 90.0 - azim, 0.0)
	var day_f := clampf((elev + 5.0) / 25.0, 0.0, 1.0)
	var tint: Color = WEATHER_TINT.get(weather, Color.WHITE)
	sun.light_energy = 1.1 * day_f * (0.45 if weather in ["overcast", "rain", "thunder", "foggy", "ash", "blight", "blizzard"] else 1.0)
	sun.light_color = Color(1.0, 0.75 + 0.25 * day_f, 0.55 + 0.45 * day_f)
	sky_mat.sky_top_color = tint.darkened(0.15) * (0.08 + 0.92 * day_f)
	sky_mat.sky_horizon_color = tint.lightened(0.3) * (0.1 + 0.9 * day_f)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	env.ambient_light_energy = 0.15 + 0.6 * day_f
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = WEATHER_FOG.get(weather, 0.001)

func set_region(region_id: String) -> void:
	if region_id.to_lower() == region.to_lower():
		return
	region = region_id
	pick_weather()

## Pogoda losowana deterministycznie (dzień + region) wg szans z rekordu REGN.
func pick_weather() -> void:
	var r: Dictionary = regions.get(region.to_lower(), {})
	var chances: Dictionary = r.get("weather", {"clear": 100})
	var total := 0
	for k in chances:
		total += int(chances[k])
	if total <= 0:
		weather = "clear"
		apply()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [region.to_lower(), day])
	var roll := rng.randi_range(0, total - 1)
	for k in chances:
		roll -= int(chances[k])
		if roll < 0:
			weather = k
			break
	apply()

## Wnętrze: światło otoczenia z rekordu komórki (AMBI), bez słońca i nieba.
func set_interior(cell: Dictionary) -> void:
	interior = not cell.is_empty() and cell.get("interior", false) and not cell.get("behave_like_exterior", false)
	if interior:
		var a: Dictionary = cell.get("ambient", {})
		var amb: Array = a.get("ambient_rgb", [60, 60, 60])
		var fog: Array = a.get("fog_rgb", [20, 20, 20])
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color8(fog[0], fog[1], fog[2])
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color8(amb[0], amb[1], amb[2])
		env.ambient_light_energy = 1.0
		env.fog_light_color = env.background_color
		env.fog_density = clampf(float(a.get("fog_density", 0.0)) * 0.02, 0.0, 0.05)
		sun.visible = false
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		apply()

# --- woda -----------------------------------------------------------------------------------------
const WATER_SHADER := "shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.05, 0.18, 0.25, 0.75);
uniform vec4 shallow : source_color = vec4(0.15, 0.35, 0.4, 0.6);
void vertex() {
	VERTEX.y += sin(TIME * 0.8 + VERTEX.x * 0.15) * 0.03 + cos(TIME * 0.6 + VERTEX.z * 0.12) * 0.03;
}
void fragment() {
	float w = 0.5 + 0.5 * sin(TIME * 0.7 + UV.x * 40.0) * cos(TIME * 0.5 + UV.y * 37.0);
	ALBEDO = mix(deep.rgb, shallow.rgb, w * 0.4);
	ALPHA = deep.a;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}"
static var _water_mat: ShaderMaterial

static func water_plane(size_m: float, height_m: float) -> MeshInstance3D:
	if _water_mat == null:
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(size_m, size_m)
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	pm.material = _water_mat
	mi.mesh = pm
	mi.position.y = height_m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("mw_water", true)
	return mi
