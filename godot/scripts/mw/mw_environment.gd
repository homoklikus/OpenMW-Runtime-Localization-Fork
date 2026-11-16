class_name MWEnvironment
extends Node3D
## Niebo, słońce, pora dnia, pogoda wg regionu i woda.
## Czas gry jak w Morrowindzie: skala 30 (1 s rzeczywista = 30 s gry, doba ≈ 48 min).
## Etap 10: pogoda jak OpenMW (mw_weather.gd – wartości Morrowind.ini): kolory nieba, mgły, otoczenia i słońca
## wg pory dnia, przejścia między pogodami, mgła liniowa jak FogManager (początek = odległość × (1 − głębokość),
## koniec = odległość widzenia), niebo z chmurami pogody (tekstury Tx_Sky_*, przesuw wg Cloud_Speed, mieszanie
## przy przejściu), tarcza słońca (tx_sun_05) i gwiazdy nocą; światło słońca nocą = światło księżyców (kolor
## „Sun_Night”), kierunek jak w Morrowindzie.

const TIMESCALE := 30.0
const WeatherScript := preload("res://scripts/mw/mw_weather.gd")

var game_hour := 9.0
var day := 0
var time_running := true
var weather := "clear"
var forced_weather := ""   # tryb zrzutu: stała pogoda (porównania z OpenMW)
var region := ""
var interior := false
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var regions := {}
var data_root := ""
var wm = WeatherScript.new()          # stan pogody (OpenMW WeatherManager)
var fog_distance := 7168.0 / MWCoords.UNITS_PER_METER   # koniec mgły (m) – ustawia gra (odległość widzenia)
var _cloud_offset := Vector2.ZERO
var _tex_cache := {}
var _weather_started := false
var _interior_cell := {}

const SKY_SHADER := "shader_type sky;
uniform vec3 sky_color : source_color = vec3(0.37, 0.53, 0.8);
uniform vec3 fog_color : source_color = vec3(0.8, 0.88, 1.0);
uniform sampler2D clouds_a : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D clouds_b : source_color, repeat_enable, filter_linear_mipmap;
uniform float has_a = 0.0;
uniform float has_b = 0.0;
uniform float cloud_blend = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform sampler2D sun_tex : source_color, filter_linear;
uniform float has_sun_tex = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_disc = vec4(1.0);
uniform float sun_radius = 0.045;
uniform float night_fade = 0.0;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(fog_color, sky_color, smoothstep(-0.02, 0.35, h));
	if (night_fade > 0.0 && h > 0.0) {
		vec3 c = floor(d * 220.0);
		float s = hash(c);
		float star = step(0.9965, s) * (0.5 + 0.5 * hash(c + 3.1));
		col += vec3(star) * night_fade * smoothstep(0.0, 0.25, h);
	}
	float cs = dot(d, sun_dir);
	if (sun_disc.a > 0.0 && cs > cos(sun_radius * 1.6)) {
		vec3 t1 = normalize(cross(sun_dir, abs(sun_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 t2 = cross(sun_dir, t1);
		vec2 uv = vec2(dot(d, t1), dot(d, t2)) / tan(sun_radius) * 0.5 + 0.5;
		vec4 st = has_sun_tex > 0.5 ? texture(sun_tex, uv) : vec4(1.0, 1.0, 1.0, 1.0 - smoothstep(0.35, 0.5, length(uv - 0.5)));
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0)
			col = mix(col, st.rgb * sun_disc.rgb, st.a * sun_disc.a);
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.18) * 0.45 + cloud_offset;
		vec4 ca = has_a > 0.5 ? texture(clouds_a, uv) : vec4(0.0);
		vec4 cb = has_b > 0.5 ? texture(clouds_b, uv) : ca;
		vec4 c = mix(ca, cb, cloud_blend);
		float a = c.a * smoothstep(0.0, 0.15, h);
		col = mix(col, c.rgb * min(fog_color + vec3(0.13), vec3(1.0)), a);   // OpenMW: emisja chmur = mgła + 0,13
	} else {
		col = fog_color;
	}
	COLOR = col;
}"

func _ready() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	env.fog_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	add_child(sun)
	wm.load(data_root)
	apply()

## Ponowne wczytanie wartości pogody (po ustawieniu data_root).
func load_weather(root: String) -> void:
	data_root = root
	wm.load(root)
	_tex_cache.clear()
	apply()

func _process(delta: float) -> void:
	if not interior:
		wm.update_transition(delta)
		_cloud_offset += Vector2(1.0, 0.35) * float(wm.result.get("cloud_speed", 1.0)) * delta * 0.004
	if time_running and not interior:
		advance(delta * TIMESCALE / 3600.0)
	elif not interior:
		apply()

func advance(hours: float) -> void:
	game_hour += hours
	while game_hour >= 24.0:
		game_hour -= 24.0
		day += 1
	if wm.advance_hours(hours):
		pick_weather()
	apply()

## Wysokość słońca w południe w Morrowindzie: kierunek (0, 75, 100) → atan(100 / 75) ≈ 53,13°.
static func sun_elevation_deg(hour: float) -> float:
	var w = WeatherScript.new()
	var d: Vector3 = w.sun_direction_mw(hour)
	return rad_to_deg(asin(clampf(d.z, -1.0, 1.0)))

func _tex(file: String) -> Texture2D:
	if file.is_empty():
		return null
	var rel := "textures/" + file.get_file().get_basename().to_lower() + ".png"
	if _tex_cache.has(rel):
		return _tex_cache[rel]
	var t: Texture2D = null
	var p := data_root.path_join(rel)
	if not data_root.is_empty() and FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_tex_cache[rel] = t
	return t

func apply() -> void:
	if sun == null:
		return
	if interior:
		sun.visible = false
		return
	# pogoda ustawiona z zewnątrz (ChangeWeather, nadpisanie regionu) – przejście jak addWeatherTransition
	var want: int = wm.idx(weather)
	if (wm.in_transition() and want != wm.next_w) or (not wm.in_transition() and want != wm.current):
		wm.add_transition(want)
	var r: Dictionary = wm.compute(game_hour)
	var d_mw: Vector3 = wm.sun_direction_mw(game_hour)
	var to_sun := Vector3(d_mw.x, d_mw.z, -d_mw.y).normalized()
	sun.visible = true
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.FORWARD if absf(to_sun.y) > 0.99 else Vector3.UP)
	sun.light_color = r.sun
	sun.light_energy = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = r.ambient
	env.ambient_light_energy = 1.0
	env.background_mode = Environment.BG_SKY
	env.fog_light_color = r.fog
	var depth: float = r.fog_depth
	if depth <= 0.0:
		env.fog_depth_begin = 0.0
		env.fog_depth_end = 1e6
	else:
		env.fog_depth_begin = fog_distance * (1.0 - depth)
		env.fog_depth_end = fog_distance
	env.fog_density = 1.0
	sky_mat.set_shader_parameter("sky_color", r.sky)
	sky_mat.set_shader_parameter("fog_color", r.fog)
	var ca := _tex(String(r.cloud_texture))
	var cb := _tex(String(r.get("next_cloud_texture", "")))
	sky_mat.set_shader_parameter("clouds_a", ca)
	sky_mat.set_shader_parameter("has_a", 1.0 if ca != null else 0.0)
	sky_mat.set_shader_parameter("clouds_b", cb)
	sky_mat.set_shader_parameter("has_b", 1.0 if cb != null else 0.0)
	sky_mat.set_shader_parameter("cloud_blend", float(r.get("cloud_blend", 0.0)))
	sky_mat.set_shader_parameter("cloud_offset", _cloud_offset)
	var st := _tex("tx_sun_05.dds")
	sky_mat.set_shader_parameter("sun_tex", st)
	sky_mat.set_shader_parameter("has_sun_tex", 1.0 if st != null else 0.0)
	sky_mat.set_shader_parameter("sun_dir", to_sun)
	var disc: Color = r.sun_disc
	if wm.is_night(game_hour):
		disc.a = 0.0                     # sunDisable w nocy
	sky_mat.set_shader_parameter("sun_disc", disc)
	sky_mat.set_shader_parameter("night_fade", float(r.night_fade))

func set_region(region_id: String) -> void:
	if region_id.to_lower() == region.to_lower():
		return
	region = region_id
	pick_weather()

## Pogoda regionu: rzut 0..99 wg szans REGN (deterministyczny dla regionu i numeru zmiany pogody); na początku gry
## od razu, potem przejście (addWeatherTransition).
func pick_weather() -> void:
	if not forced_weather.is_empty():
		weather = forced_weather
		wm.force(wm.idx(weather))
		_weather_started = true
		apply()
		return
	var r: Dictionary = regions.get(region.to_lower(), {})
	var chances: Dictionary = r.get("weather", {"clear": 100})
	var total := 0
	for k in chances:
		total += int(chances[k])
	if total <= 0:
		weather = "clear"
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|%d" % [region.to_lower(), int(wm.change_index)])
		var roll := rng.randi_range(0, total - 1)
		weather = WeatherScript.choose(chances, roll)
	if not _weather_started:
		wm.force(wm.idx(weather))
		_weather_started = true
	apply()

## Wnętrze: światło otoczenia z rekordu komórki (AMBI), mgła liniowa z gęstości komórki (FogManager::configure),
## bez słońca i nieba.
func set_interior(cell: Dictionary) -> void:
	interior = not cell.is_empty() and cell.get("interior", false) and not cell.get("behave_like_exterior", false)
	_interior_cell = cell
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
		var dens := clampf(float(a.get("fog_density", 0.0)), 0.0, 1.0)
		if dens <= 0.0:
			env.fog_depth_begin = 0.0
			env.fog_depth_end = 1e6
		else:
			env.fog_depth_begin = fog_distance * (1.0 - dens)
			env.fog_depth_end = fog_distance
		env.fog_density = 1.0
		sun.visible = false
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		apply()

# --- woda -----------------------------------------------------------------------------------------
## Woda: falowanie i wzór liczone ze współrzędnych ŚWIATA – sąsiednie komórki mają na wspólnej krawędzi identyczne
## wychylenie i kolor (wcześniej współrzędne lokalne płaszczyzny dawały szczeliny i szwy na łączeniach komórek).
const WATER_SHADER := "shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.05, 0.18, 0.25, 0.75);
uniform vec4 shallow : source_color = vec4(0.15, 0.35, 0.4, 0.6);
varying vec2 world_xz;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = wp.xz;
	VERTEX.y += sin(TIME * 0.8 + wp.x * 0.15) * 0.03 + cos(TIME * 0.6 + wp.z * 0.12) * 0.03;
}
void fragment() {
	float w = 0.5 + 0.5 * sin(TIME * 0.7 + world_xz.x * 0.34) * cos(TIME * 0.5 + world_xz.y * 0.316);
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
