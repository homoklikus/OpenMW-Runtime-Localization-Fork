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
var main = null                       # gra (stan: ModRegion)
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

## Widzenie w ciemności gracza (Player::update → RenderingManager::setNightEyeFactor: min(1, wielkość/100);
## updateAmbient: światło otoczenia + 0,7 × współczynnik).
var night_eye := 0.0:
	set(v):
		if not is_equal_approx(v, night_eye):
			night_eye = v
			if env != null:
				if interior:
					set_interior(_interior_cell)
				else:
					apply()

func _night_eye_add() -> Color:
	return Color(0.7, 0.7, 0.7, 0.0) * night_eye if night_eye > 0.0 else Color(0, 0, 0, 0)

## OpenMW liczy oświetlenie w przestrzeni gamma (bez framebuffera sRGB: wynik = tekstura × światło na wartościach
## zakodowanych), Godot – liniowo z kodowaniem sRGB na wyjściu. Przy potęgowej gammie 2,2 oba dają to samo, ale
## krzywa sRGB ma przy czerni odcinek liniowy (×12,92): ciemne wnętrza wychodziły ok. 2–3 × ciemniejsze (zmierzone na
## zrzutach OpenMW 0.51 – mediana luminancji 12 wobec 4–6/255; przy otoczeniu 0,1 i albedo 0,5: 0,027 zamiast 0,05).
## Korekcja kolorów środowiska zamienia kodowanie sRGB na czystą potęgę 1/2,2: s → (sRGB⁻¹(s))^(1/2,2) – bez
## przyciemniania ani rozjaśniania półtonów (0,5 × 0,5 → 0,247 zamiast 0,25). Działa w Forward+ i Mobile; renderer
## Compatibility stosuje tablicę w innym miejscu potoku (tablica tożsamościowa zmienia czernie) – tam bez korekcji.
static var _gamma_lut: ImageTexture = null

static func apply_gamma_space(e: Environment) -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return
	if _gamma_lut == null:
		var n := 4096
		var img := Image.create(n, 1, false, Image.FORMAT_RGBF)
		for i in n:
			var v := i / float(n - 1)
			var lin := v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
			var g := pow(lin, 1.0 / 2.2)
			img.set_pixel(i, 0, Color(g, g, g))
		_gamma_lut = ImageTexture.create_from_image(img)
	e.adjustment_enabled = true
	e.adjustment_color_correction = _gamma_lut

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
	# OpenMW nie stosuje tonemappingu (bez post-processingu HDR): wynik oświetlenia obcięty do [0, 1]
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	apply_gamma_space(env)
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	add_child(sun)
	wm.load(data_root)
	apply()

## Cienie słońca: kaskady PSSM (4 przy średniej i wysokiej), zasięg i rozdzielczość wg jakości, łagodne
## przejścia między kaskadami; we wnętrzach słońce bez cieni (kolor „sunlight” komórki, jak OpenMW).
const SHADOW_PRESETS := {"low": [1024, 60.0, 2], "medium": [2048, 120.0, 4], "high": [4096, 220.0, 4]}
var shadow_quality := "medium"

func configure_shadows(q: String) -> void:
	shadow_quality = q
	if sun == null:
		return
	sun.shadow_enabled = q != "off" and SHADOW_PRESETS.has(q)
	if not sun.shadow_enabled:
		return
	var p: Array = SHADOW_PRESETS[q]
	RenderingServer.directional_shadow_atlas_set_size(int(p[0]), true)
	sun.directional_shadow_max_distance = minf(float(p[1]), maxf(fog_distance, 30.0))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p[2]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = q == "high"
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0

## Ponowne wczytanie wartości pogody (po ustawieniu data_root).
func load_weather(root: String) -> void:
	data_root = root
	wm.load(root)
	_tex_cache.clear()
	apply()

func _process(delta: float) -> void:
	if interior:
		_update_water({}, Vector3.UP)
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
		# DateTimeManager::advanceTime: nowy dzień – DaysPassed (day) i kalendarz (Day/Month/Year)
		if main != null and main.get("scripts") != null:
			main.scripts.calendar_add_days(1)
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
	var rel := "textures/" + file.replace("\\", "/").get_basename().to_lower() + ".png"
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
		return                      # słońce wnętrza ustawia set_interior (kolor komórki, stały kierunek)
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
	env.ambient_light_color = r.ambient + _night_eye_add()
	env.ambient_light_energy = 1.0
	env.background_mode = Environment.BG_SKY if sky_enabled else Environment.BG_COLOR
	env.background_color = r.fog
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
	_update_water(r, to_sun)
	_apply_underwater()

var underwater := false

## Kamera pod wodą: mgła jak FogManager – kolor Water_UnderwaterColor × waga + mgła × (1 − waga), koniec =
## min(odległość widzenia, 7168 j.), początek = koniec × (1 − gęstość) (Water_Underwater*Fog wg pory dnia albo
## Water_UnderwaterIndoorFog we wnętrzach; gęstość > 1 daje mgłę już przy kamerze).
func set_underwater(on: bool) -> void:
	if on == underwater:
		return
	underwater = on
	if interior:
		set_interior(_interior_cell)
	else:
		apply()

func _apply_underwater() -> void:
	if not underwater:
		return
	var w := wm.num("Water_UnderwaterColorWeight", 0.85)
	var uc := wm.colour("Water_UnderwaterColor")
	var fc := env.fog_light_color
	env.fog_light_color = Color(uc.r * w + fc.r * (1.0 - w), uc.g * w + fc.g * (1.0 - w), uc.b * w + fc.b * (1.0 - w))
	var f := wm.num("Water_UnderwaterIndoorFog", 3.0) if interior else wm.underwater_fog(game_hour)
	var d := minf(fog_distance, 7168.0 / MWCoords.UNITS_PER_METER)
	env.fog_depth_begin = d * (1.0 - f)
	env.fog_depth_end = d
	env.fog_density = 1.0
	if interior:
		env.background_color = env.fog_light_color

## WeatherManager::write (ESM::WeatherState): region, czas do zmiany, przejście (bieżąca, następna, w kolejce,
## mTransitionFactor) – zapis gry.
func weather_state() -> Dictionary:
	return {"name": weather, "region": region, "current": wm.current, "next": wm.next_w, "queued": wm.queued,
		"transition": wm.transition, "update_time": wm.update_time, "change_index": wm.change_index}

## WeatherManager::readRecord: stan pogody z zapisu bez nowego przejścia. Zapis bez stanu pogody (sprzed tej
## zmiany) – pogoda regionu od razu (jak początek gry), nie przejście od pogody poprzedniej sesji.
func restore_weather(st: Dictionary, region_id: String) -> void:
	if not forced_weather.is_empty():
		return
	if st.is_empty():
		region = region_id
		_weather_started = false
		pick_weather()
		return
	weather = String(st.get("name", "clear"))
	region = String(st.get("region", region_id))
	wm.current = clampi(int(st.get("current", wm.idx(weather))), 0, 9)
	wm.next_w = int(st.get("next", -1))
	wm.queued = int(st.get("queued", -1))
	wm.transition = float(st.get("transition", 0.0))
	wm.update_time = float(st.get("update_time", wm.update_time))
	wm.change_index = int(st.get("change_index", 0))
	_weather_started = true
	apply()

func set_region(region_id: String) -> void:
	if region_id.to_lower() == region.to_lower():
		return
	region = region_id
	pick_weather()

## Pogoda regionu: rzut 0..99 wg szans REGN (deterministyczny dla regionu i numeru zmiany pogody); na początku gry
## od razu, potem przejście (addWeatherTransition).
## Szanse pogód regionu: ModRegion (WeatherManager::modRegion – trwałe, w stanie gry) albo rekord regionu.
func region_chances(rid: String) -> Dictionary:
	var ov = main.state.player.get("region_weather", {}).get(rid.to_lower()) if main != null and main.state.player.get("region_weather") is Dictionary else null
	if ov is Dictionary:
		return ov
	return (regions.get(rid.to_lower(), {}) as Dictionary).get("weather", {"clear": 100})

## ModRegion: nowe szanse; bieżący region bez obecnej pogody wśród możliwych – zmiana pogody
## (regionalWeatherChanged).
func mod_region(rid: String, chances: Dictionary) -> void:
	if not main.state.player.get("region_weather") is Dictionary:
		main.state.player["region_weather"] = {}
	main.state.player.region_weather[rid.to_lower()] = chances
	if rid.to_lower() == region.to_lower() and forced_weather.is_empty() and int(chances.get(weather, 0)) <= 0:
		pick_weather()

func pick_weather() -> void:
	if not forced_weather.is_empty():
		weather = forced_weather
		wm.force(wm.idx(weather))
		_weather_started = true
		apply()
		return
	var chances := region_chances(region)
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

## Kierunek padania słońca we wnętrzu: pozycja (−1, 0,785, 0,785) w układzie MW → kierunek do sceny w Godocie.
const INTERIOR_SUN_DIR := Vector3(1.0, -0.785398, 0.785398)
const MIN_INTERIOR_BRIGHTNESS := 0.08          # [Shaders] minimum interior brightness (OpenMW, domyślnie)

## RenderingManager::configureAmbient: ambient wnętrza podniesiony do luminancji 0,08 (współczynniki Rec. 709
## na wartościach z rekordu), czarny – do szarości 0,08.
static func interior_ambient(c: Color) -> Color:
	var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	if lum >= MIN_INTERIOR_BRIGHTNESS:
		return c
	if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
		return Color(MIN_INTERIOR_BRIGHTNESS, MIN_INTERIOR_BRIGHTNESS, MIN_INTERIOR_BRIGHTNESS)
	var k := MIN_INTERIOR_BRIGHTNESS / lum
	return Color(c.r * k, c.g * k, c.b * k)

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
		env.ambient_light_color = interior_ambient(Color8(amb[0], amb[1], amb[2])) + _night_eye_add()
		# RenderingManager::configureAmbient: we wnętrzu słońce w kolorze „sunlight” komórki, stały kierunek
		# (−1, 45°, 45°) – „total nonsense but it's what Morrowind uses”
		var sl: Array = a.get("sunlight_rgb", [0, 0, 0])
		sun.light_color = Color8(sl[0], sl[1], sl[2])
		sun.light_energy = 1.0
		sun.look_at_from_position(Vector3.ZERO, INTERIOR_SUN_DIR, Vector3.UP)
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
		sun.visible = true
		sun.shadow_enabled = false
		_update_water({}, Vector3.UP)
		_apply_underwater()
	else:
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		configure_shadows(shadow_quality)
		apply()

# --- woda -----------------------------------------------------------------------------------------
## Woda jak OpenMW (apps/openmw/mwrender/water.cpp):
## * „shader” – port files/shaders/compatibility/water.frag: 6 warstw mapy normalnych (water_nm z OpenMW) przesuwanych
##   wiatrem, Fresnel, załamanie (tekstura ekranu) z barwą głębi (VISIBILITY 2500 j.), rozpraszanie światła słońca,
##   odblask słońca (kolor słońca × Glare_View), „chwiejne brzegi”; deszcz wzmacnia fale. Odbicie: samo niebo
##   (jak „reflection detail = 0” w OpenMW – bez drugiej kamery).
## * „simple” – domyślna woda OpenMW: animowane tekstury textures/water/water00–31 (Water_SurfaceFPS), jedno
##   powtórzenie na 8192 × 150 / 900 j., przezroczystość Water_World_Alpha, oświetlenie słońcem i otoczeniem.
## Współrzędne liczone w układzie świata – sąsiednie komórki łączą się bez szwów.
const WATER_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_map : repeat_enable, filter_linear_mipmap;
uniform float upm = 70.0;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec4 sun_spec = vec4(1.0);
uniform vec3 ambient = vec3(0.5);
uniform vec3 sky_color = vec3(0.37, 0.53, 0.8);
uniform vec3 fog_color = vec3(0.8, 0.88, 1.0);
uniform float rain = 0.0;
uniform bool refraction_on = true;
uniform bool scattering_on = true;
uniform bool wobbly_on = true;
varying vec3 wpos;
const float VISIBILITY = 2500.0;
const float VISIBILITY_DEPTH = VISIBILITY * 1.5;
const float DEPTH_FADE = 0.15;
const vec2 BIG_WAVES = vec2(0.1, 0.1);
const vec2 MID_WAVES = vec2(0.1, 0.1);
const vec2 MID_WAVES_RAIN = vec2(0.2, 0.2);
const vec2 SMALL_WAVES = vec2(0.1, 0.1);
const vec2 SMALL_WAVES_RAIN = vec2(0.3, 0.3);
const float WAVE_CHOPPYNESS = 0.05;
const float WAVE_SCALE = 75.0;
const float BUMP = 0.5;
const float BUMP_RAIN = 2.5;
const float REFL_BUMP = 0.10;
const float SCATTER_AMOUNT = 0.3;
const vec3 SCATTER_COLOUR = vec3(0.0, 1.0, 0.95);
const vec3 SUN_EXT = vec3(0.45, 0.55, 0.68);
const float SUN_SPEC_FADING_THRESHOLD = 0.15;
const float SPEC_HARDNESS = 256.0;
const float SPEC_BUMPINESS = 5.0;
const float SPEC_BRIGHTNESS = 1.5;
const float BUMP_SUPPRESS_DEPTH = 300.0;
const float REFR_FOG_DISTORT_DISTANCE = 3000.0;
const vec2 WIND_DIR = vec2(0.5, -0.8);
const float WIND_SPEED = 0.2;
const vec3 WATER_COLOR = vec3(0.090195, 0.115685, 0.12745);
const float WOBBLY_SHORE_FADE_DISTANCE = 6200.0;
vec2 normal_coords(vec2 uv, float scale, float speed, float time, float t1, float t2, vec3 prev) {
	return uv * (WAVE_SCALE * scale) + WIND_DIR * time * (WIND_SPEED * speed) - (prev.xy / prev.zz) * WAVE_CHOPPYNESS + vec2(time * t1, time * t2);
}
vec3 nm(vec2 c) { return 2.0 * texture(normal_map, c).rgb - 1.0; }
float fresnel_dielectric(vec3 incoming, vec3 normal, float eta) {
	float c = abs(dot(incoming, normal));
	float g = eta * eta - 1.0 + c * c;
	if (g > 0.0) {
		g = sqrt(g);
		float A = (g - c) / (g + c);
		float B = (c * (g + c) - 1.0) / (c * (g - c) + 1.0);
		return 0.5 * A * A * (1.0 + B * B);
	}
	return 1.0;
}
vec3 to_srgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }
vec3 to_linear(vec3 c) { return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 mw(vec3 g) { return vec3(g.x, -g.z, g.y); }
float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w * upm;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 p = mw(wpos) * upm;
	vec3 cam = mw(CAMERA_POSITION_WORLD) * upm;
	float water_z = MODEL_MATRIX[3].y * upm;
	bool above = cam.z > water_z;
	vec2 wuv = p.xy / (8192.0 * 5.0) * 3.0;
	float t = TIME;
	vec3 n0 = nm(normal_coords(wuv, 0.05, 0.04, t, -0.015, -0.005, vec3(0.0)));
	vec3 n1 = nm(normal_coords(wuv, 0.1, 0.08, t, 0.02, 0.015, n0));
	vec3 n2 = nm(normal_coords(wuv, 0.25, 0.07, t, -0.04, -0.03, n1));
	vec3 n3 = nm(normal_coords(wuv, 0.5, 0.09, t, 0.03, 0.04, n2));
	vec3 n4 = nm(normal_coords(wuv, 1.0, 0.4, t, -0.02, 0.1, n3));
	vec3 n5 = nm(normal_coords(wuv, 2.0, 0.7, t, 0.1, -0.06, n4));
	vec2 mid_w = mix(MID_WAVES, MID_WAVES_RAIN, rain);
	vec2 small_w = mix(SMALL_WAVES, SMALL_WAVES_RAIN, rain);
	float bump = mix(BUMP, BUMP_RAIN, rain);
	vec3 n = n0 * BIG_WAVES.x + n1 * BIG_WAVES.y + n2 * mid_w.x + n3 * mid_w.y + n4 * small_w.x + n5 * small_w.y;
	n = normalize(vec3(-n.x * bump, -n.y * bump, n.z));
	vec3 sun_w = normalize(mw(sun_dir));
	vec3 view_dir = normalize(p - cam);
	float sun_fade = length(ambient);
	float ior = above ? 1.333 : (1.0 / 1.333);
	float fresnel = clamp(fresnel_dielectric(view_dir, n, ior), 0.0, 1.0);
	vec2 off = n.xy * REFL_BUMP;
	float surf = -VERTEX.z * upm;
	float real_depth = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - surf;
	float ddist = max(lin_depth(SCREEN_UV - off, INV_PROJECTION_MATRIX) - surf, 0.0);
	if (refraction_on)
		off *= clamp(real_depth / BUMP_SUPPRESS_DEPTH, 0.0, 1.0);
	// odbicie: niebo w kierunku odbitym (mgła przy horyzoncie → kolor nieba)
	vec3 rdir = reflect(view_dir, n);
	vec3 reflection = mix(fog_color, sky_color, smoothstep(-0.02, 0.35, abs(rdir.z)));
	vec3 water_color = WATER_COLOR * sun_fade;
	vec4 ss = sun_spec;
	ss.a = min(1.0, ss.a / SUN_SPEC_FADING_THRESHOLD);
	vec3 spec_n = normalize(vec3(n.x * SPEC_BUMPINESS, n.y * SPEC_BUMPINESS, n.z));
	float phong = max(dot(reflect(view_dir, spec_n), sun_w), 0.0);
	float specular = clamp(pow(atan(phong * 1.55), SPEC_HARDNESS) * SPEC_BRIGHTNESS, 0.0, 1.0) * ss.a;
	vec3 col;
	float alpha_out = 1.0;
	// [Water] refraction (@waterRefraction): bez załamania – kolor wody z odbiciem i przezroczystość waterTransparency
	if (refraction_on) {
		if (above && real_depth <= VISIBILITY_DEPTH && ddist > VISIBILITY_DEPTH)
			off = vec2(0.0);
		ddist = max(lin_depth(SCREEN_UV - off, INV_PROJECTION_MATRIX) - surf, 0.0);
		ddist = mix(ddist, real_depth, min(surf / REFR_FOG_DISTORT_DISTANCE, 1.0));
		vec3 raw_refr = to_srgb(textureLod(screen_tex, SCREEN_UV - off, 0.0).rgb);
		vec3 refraction = raw_refr;
		if (!above) {
			refraction = clamp(refraction * 1.5, 0.0, 1.0);
		} else {
			float dc = sqrt(1.0 + 4.0 * DEPTH_FADE * DEPTH_FADE);
			float factor = DEPTH_FADE * DEPTH_FADE / (-0.5 * dc + 0.5 - ddist / VISIBILITY) + 0.5 * dc + 0.5;
			refraction = mix(refraction, water_color, clamp(factor, 0.0, 1.0));
		}
		if (scattering_on) {
		vec3 sn = n0 * BIG_WAVES.x * 0.5 + n1 * BIG_WAVES.y * 0.5 + n2 * mid_w.x * 0.2 + n3 * mid_w.y * 0.2 + n4 * small_w.x * 0.1 + n5 * small_w.y * 0.1;
		sn = normalize(vec3(-sn.xy * bump, sn.z));
		float sun_h = sun_w.z;
		vec3 scol = mix(SCATTER_COLOUR * vec3(1.0, 0.4, 0.0), SCATTER_COLOUR, max(1.0 - exp(-sun_h * SUN_EXT), 0.0));
		float sl = max(dot(sun_w, sn) * 0.7 + 0.3, 0.0);
		float sra = max(dot(reflect(sun_w, sn), view_dir) * 2.0 - 1.2, 0.0);
		refraction = mix(refraction, scol, sl * sra * SCATTER_AMOUNT * sun_fade * ss.a * max(1.0 - exp(-sun_h), 0.0));
		}
		col = mix(refraction, reflection, fresnel) + specular * ss.rgb;
		// chwiejne brzegi: na płyciźnie przejście w czyste załamanie
		if (wobbly_on) {
		vec3 sr = texture(normal_map, normal_coords(wuv, 2.0, 2.7, -t, 0.05, 0.1, n3)).rgb - 0.5 + texture(normal_map, normal_coords(wuv, 2.0, 2.7, t, 0.04, -0.13, n4)).rgb - 0.5;
		float vf = mix(abs(view_dir.z), 1.0, 0.2);
		float shore = real_depth * vf - (n2.r + mix(0.0, sr.r, rain) + 0.15) * 8.0;
		shore *= min(1.0, 1000.0 / max(surf, 1.0)) * vf;
		shore = clamp(mix(shore, 1.0, clamp(surf / WOBBLY_SHORE_FADE_DISTANCE, 0.0, 1.0)), 0.0, 1.0);
		col = mix(raw_refr, col, shore);
		}
	} else {
		col = mix(water_color, reflection, (1.0 + fresnel) * 0.5) + specular * ss.rgb;
		alpha_out = clamp(fresnel * 6.0 + specular, 0.0, 1.0);
	}
	ALBEDO = to_linear(clamp(col, 0.0, 1.0));
	ALPHA = alpha_out;
}"

const SIMPLE_WATER_SHADER := "shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, diffuse_lambert, specular_disabled;
uniform sampler2D frame_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float has_tex = 0.0;
uniform float alpha = 0.75;
uniform float upm = 70.0;
varying vec2 uvw;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	uvw = vec2(wp.x, -wp.z) * upm / (8192.0 * 150.0 / 900.0);
}
void fragment() {
	vec4 c = has_tex > 0.5 ? texture(frame_tex, uvw) : vec4(0.12, 0.25, 0.3, 1.0);
	ALBEDO = c.rgb;
	ALPHA = c.a * alpha;
	ROUGHNESS = 1.0;
}"

static var water_mode := "shader"      # „shader” albo „simple” (ustawienie gry „water”)
static var water_root := ""            # katalog danych (tekstury wody)
static var _water_mat: ShaderMaterial
static var _simple_mat: ShaderMaterial
static var _simple_frames: Array = []
static var _simple_fps := 12.0
static var _nm_tex: Texture2D

static func _water_material() -> ShaderMaterial:
	if water_mode == "simple":
		if _simple_mat == null:
			var sh := Shader.new()
			sh.code = SIMPLE_WATER_SHADER
			_simple_mat = ShaderMaterial.new()
			_simple_mat.shader = sh
			_simple_mat.render_priority = -1
			_simple_mat.set_shader_parameter("upm", MWCoords.UNITS_PER_METER)
		return _simple_mat
	if _water_mat == null:
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = sh
		_water_mat.render_priority = -1
		_water_mat.set_shader_parameter("upm", MWCoords.UNITS_PER_METER)
		if _nm_tex == null:
			const NM := "res://data/water_nm.png"
			if ResourceLoader.exists(NM):            # zaimportowana (edytor, wydanie)
				_nm_tex = load(NM) as Texture2D
			else:                                    # uruchomienie bez importu (testy)
				var img := Image.load_from_file(ProjectSettings.globalize_path(NM))
				if img != null and not img.is_empty():
					img.generate_mipmaps()
					_nm_tex = ImageTexture.create_from_image(img)
		_water_mat.set_shader_parameter("normal_map", _nm_tex)
		_apply_water_features(_water_mat)
	return _water_mat

## Klatki prostej wody: textures/water/<Water_SurfaceTexture>NN (Water_SurfaceFrameCount, FPS z fallbacków).
func _load_simple_frames() -> void:
	_simple_frames.clear()
	var name := wm.text("Water_SurfaceTexture")
	if name.is_empty():
		name = "water"
	var count := clampi(int(wm.num("Water_SurfaceFrameCount", 32.0)), 0, 320)
	_simple_fps = maxf(wm.num("Water_SurfaceFPS", 12.0), 0.1)
	for i in count:
		var t := _tex("water/%s%02d.dds" % [name, i])
		if t == null:
			break
		_simple_frames.append(t)

## ToggleSky (World::toggleSky → setSkyEnabled): bez nieba tło w kolorze mgły (kolor czyszczenia OpenMW).
var sky_enabled := true
## ToggleWater (Render_Water): płaszczyzny wody ukryte – także w komórkach wczytanych później.
static var water_visible := true

func toggle_sky() -> bool:
	sky_enabled = not sky_enabled
	apply()
	return sky_enabled

func toggle_water() -> bool:
	water_visible = not water_visible
	for n in get_tree().root.find_children("Water", "MeshInstance3D", true, false):
		if n.has_meta("mw_water"):
			(n as MeshInstance3D).visible = water_visible
	return water_visible

static func water_plane(size_m: float, height_m: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.visible = water_visible
	var pm := PlaneMesh.new()
	pm.size = Vector2(size_m, size_m)
	pm.material = _water_material()
	mi.mesh = pm
	mi.position.y = height_m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("mw_water", true)
	return mi

## [Water] refraction / sunlight scattering / wobbly shores (@waterRefraction, @sunlightScattering, @wobblyShores
## shadera wody OpenMW): rozpraszanie światła i chwiejne brzegi działają tylko z załamaniem.
static var water_features := {"refraction": false, "scattering": true, "wobbly": true}

static func set_water_features(refraction: bool, scattering: bool, wobbly: bool) -> void:
	water_features = {"refraction": refraction, "scattering": scattering, "wobbly": wobbly}
	if _water_mat != null:
		_apply_water_features(_water_mat)

static func _apply_water_features(m: ShaderMaterial) -> void:
	m.set_shader_parameter("refraction_on", bool(water_features.refraction))
	m.set_shader_parameter("scattering_on", bool(water_features.scattering))
	m.set_shader_parameter("wobbly_on", bool(water_features.wobbly))

## Zmiana rodzaju wody w trakcie gry (ustawienia): podmiana materiału istniejących płaszczyzn.
func set_water_mode(mode: String) -> void:
	mode = "simple" if mode == "simple" else "shader"
	if mode == water_mode:
		return
	water_mode = mode
	var mat := _water_material()
	for n in get_tree().root.find_children("Water", "MeshInstance3D", true, false):
		if n.has_meta("mw_water") and (n as MeshInstance3D).mesh is PlaneMesh:
			((n as MeshInstance3D).mesh as PlaneMesh).material = mat
	apply()

func _update_water(r: Dictionary, to_sun: Vector3) -> void:
	var m := _water_material()
	if water_mode == "simple":
		if _simple_frames.is_empty() and not data_root.is_empty():
			_load_simple_frames()
		if not _simple_frames.is_empty():
			var f := int(Time.get_ticks_msec() / 1000.0 * _simple_fps) % _simple_frames.size()
			m.set_shader_parameter("frame_tex", _simple_frames[f])
		m.set_shader_parameter("has_tex", 1.0 if not _simple_frames.is_empty() else 0.0)
		m.set_shader_parameter("alpha", wm.num("Water_World_Alpha", 0.75))
		return
	var sun_col: Color = r.get("sun", Color.WHITE)
	var vis := 0.0 if interior else wm.sun_visibility(float(r.get("glare", 0.0)), game_hour)
	m.set_shader_parameter("sun_dir", to_sun)
	m.set_shader_parameter("sun_spec", Vector4(sun_col.r, sun_col.g, sun_col.b, vis))
	var amb: Color = env.ambient_light_color
	m.set_shader_parameter("ambient", Vector3(amb.r, amb.g, amb.b))
	var sky: Color = r.get("sky", Color(0.37, 0.53, 0.8))
	var fog: Color = r.get("fog", env.fog_light_color)
	if interior:
		sky = env.background_color
		fog = env.background_color
	m.set_shader_parameter("sky_color", Vector3(sky.r, sky.g, sky.b))
	m.set_shader_parameter("fog_color", Vector3(fog.r, fog.g, fog.b))
	m.set_shader_parameter("rain", 1.0 if weather in ["rain", "thunder"] and not interior else 0.0)
