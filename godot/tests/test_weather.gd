extends SceneTree
## Etap 10 – pogoda i niebo jak OpenMW: wartości domyślne Morrowind.ini (Fallback Weather_*), interpolacja pory dnia
## (TimeOfDayInterpolator), przejścia pogody (Transition_Delta, kolejka), losowanie z szans regionu, kierunek słońca
## (Morrowind: −400·orbita, 75, −100), mgła liniowa (głębokość × odległość), wnętrza (gęstość mgły komórki).
## godot --headless --path godot -s res://tests/test_weather.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900 --scripts=0

const W := preload("res://scripts/mw/mw_weather.gd")

var failures: Array[String] = []
var checks := 0
var report := {}

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

func _run() -> void:
	var w = W.new()
	w.load("")
	check(w.fb.size() > 300, "domyślne wartości pogody OpenMW (%d)" % w.fb.size())
	# pora dnia – niebo pogody bezchmurnej
	var day: Color = w.calc(0, 12.0).sky
	check(_near(day, Color8(95, 135, 203)), "niebo w dzień = Sky_Day_Color")
	check(_near(w.calc(0, 18.5).sky, Color8(56, 89, 129)), "niebo o 18:30 = Sky_Sunset_Color (środek przejścia)")
	check(_near(w.calc(0, 23.0).sky, Color8(9, 10, 11)), "niebo w nocy = Sky_Night_Color")
	var mid: Color = w.calc(0, 17.5).sky
	check(mid.b < day.b and mid.b > Color8(56, 89, 129).b, "płynne przejście dzień → zachód")
	check(_near(w.calc(0, 23.0).sun, Color8(59, 97, 176)), "światło nocą = Sun_Night_Color (księżyce)")
	check(is_equal_approx(float(w.calc(2, 12.0).fog_depth), 1.0), "mgła: głębokość Foggy 1,0")
	check(String(w.calc(0, 12.0).cloud_texture).to_lower() == "tx_sky_clear.dds", "tekstura chmur pogody")
	check(float(w.calc(0, 23.5).night_fade) > 0.9 and float(w.calc(0, 12.0).night_fade) == 0.0, "gwiazdy nocą, nie w dzień")
	check(float(w.calc(0, 12.0).sun_disc.a) == 1.0 and float(w.calc(0, 19.99).sun_disc.a) < 0.05, "tarcza słońca gaśnie po zachodzie")
	# słońce
	# OpenMW: orbita od wschodu (6:00) do początku nocy (20:00) – najwyżej o 13:00
	var noon: Vector3 = w.sun_direction_mw(13.0)
	check(absf(noon.x) < 1e-4 and noon.z > 0.0 and noon.y < 0.0, "słońce o 13:00 na południu (MW −y), nad horyzontem")
	var rise: Vector3 = w.sun_direction_mw(6.0)
	var dusk: Vector3 = w.sun_direction_mw(20.0)
	check(rise.x > 0.9 and dusk.x < -0.9, "wschód na wschodzie, zachód na zachodzie")
	report["sun_elev_noon"] = rad_to_deg(asin(noon.z))
	# przejścia
	w.force(0)
	w.add_transition(4)
	check(w.in_transition() and w.next_w == 4, "przejście clear → rain")
	w.add_transition(2)
	check(w.queued == 2, "kolejna zmiana w kolejce")
	var r0: Dictionary = w.compute(12.0)
	check(_near(r0.sky, day), "na początku przejścia kolor starej pogody")
	w.update_transition(0.5 / 0.015)
	var r1: Dictionary = w.compute(12.0)
	check(_near(r1.sky, day.lerp(w.calc(4, 12.0).sky, 0.5)), "w połowie przejścia mieszanie kolorów")
	check(absf(float(r1.cloud_blend) - 0.5 / 0.66) < 0.01, "mieszanie chmur wg Clouds_Maximum_Percent")
	w.update_transition(0.6 / 0.015)
	check(w.current == 4 and w.next_w == 2, "po przejściu: rain, następnie z kolejki foggy")
	# losowanie z szans
	var ch := {"clear": 50, "cloudy": 30, "rain": 20}
	check(W.choose(ch, 0) == "clear" and W.choose(ch, 49) == "clear" and W.choose(ch, 50) == "cloudy" and W.choose(ch, 99) == "rain", "rzut 0..99 wg szans")
	var w2 = W.new()
	w2.load("")
	var changed := 0
	for i in 50:
		if w2.advance_hours(1.0):
			changed += 1
	check(changed == 2, "zmiana pogody co 20 h gry (%d)" % changed)

	# środowisko w grze
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	var env = main.envr
	env.time_running = false
	env.forced_weather = "clear"
	env.pick_weather()
	env.game_hour = 12.0
	env.apply()
	check(env.env.fog_mode == Environment.FOG_MODE_DEPTH, "mgła liniowa (głębokość)")
	var fd: float = env.fog_distance
	var dep: float = w.calc(0, 12.0).fog_depth
	check(absf(env.env.fog_depth_end - fd) < 0.01 and absf(env.env.fog_depth_begin - fd * (1.0 - dep)) < 0.5, "mgła clear: początek = odległość × (1 − Land_Fog_Day_Depth) (%.0f–%.0f)" % [env.env.fog_depth_begin, env.env.fog_depth_end])
	check(_near(env.env.ambient_light_color, w.colour("Weather_Clear_Ambient_Day_Color")), "światło otoczenia z pogody")
	check(_near(env.sun.light_color, Color8(255, 252, 238)), "kolor słońca w dzień")
	var to_sun: Vector3 = env.sun.global_transform.basis.z
	check(absf(to_sun.y - sin(deg_to_rad(MWEnvironment.sun_elevation_deg(12.0)))) < 0.01 and to_sun.z > 0.0, "słońce w grze jak w MW (y %.2f, na południu)" % to_sun.y)
	check(float(env.sky_mat.get_shader_parameter("sun_disc").a) > 0.9, "tarcza słońca widoczna w dzień")
	env.forced_weather = "foggy"
	env.pick_weather()
	check(env.env.fog_depth_begin < 1.0, "foggy: mgła od kamery")
	# przejście z zewnątrz (ChangeWeather)
	env.forced_weather = ""
	env.weather = "rain"
	env.apply()
	check(env.wm.in_transition() and W.NAMES[env.wm.next_w] == "rain", "ChangeWeather → przejście")
	# woda i pod wodą
	var wn = MWEnvironment.water_plane(10.0, 0.0)
	main.add_child(wn)
	var wmat: ShaderMaterial = (wn.mesh as PlaneMesh).material
	check(MWEnvironment.water_mode == "shader" and wmat.shader.code.contains("fresnel_dielectric") and wmat.get_shader_parameter("normal_map") != null, "woda OpenMW (shader, mapa normalnych)")
	env.apply()
	var sv: Vector4 = wmat.get_shader_parameter("sun_spec")
	check(sv.w > 0.0 and sv.w <= 1.0, "odblask słońca wg Glare_View (%.2f)" % sv.w)
	env.set_water_mode("simple")
	var smat: ShaderMaterial = (wn.mesh as PlaneMesh).material
	check(smat != wmat and smat.shader.code.contains("8192.0 * 150.0 / 900.0") and is_equal_approx(float(smat.get_shader_parameter("alpha")), 0.75), "prosta woda OpenMW (Water_World_Alpha 0,75)")
	env.set_water_mode("shader")
	check((wn.mesh as PlaneMesh).material == wmat, "powrót do wody shader")
	env.forced_weather = "clear"
	env.pick_weather()
	var land_end: float = env.env.fog_depth_end
	env.set_underwater(true)
	var dmax: float = minf(fd, 7168.0 / MWCoords.UNITS_PER_METER)
	check(absf(env.env.fog_depth_end - dmax) < 0.01 and env.env.fog_depth_begin < 0.0, "pod wodą: mgła do 7168 j., gęsta przy kamerze (%.1f–%.1f)" % [env.env.fog_depth_begin, env.env.fog_depth_end])
	var uc := w.colour("Water_UnderwaterColor")
	check(env.env.fog_light_color.b < 0.5 and absf(env.env.fog_light_color.g - (uc.g * 0.85 + w.calc(0, 12.0).fog.g * 0.15)) < 0.02, "pod wodą: kolor Water_UnderwaterColor × 0,85")
	env.set_underwater(false)
	check(absf(env.env.fog_depth_end - land_end) < 0.01, "nad wodą: mgła lądowa")
	check(is_equal_approx(w.underwater_fog(12.0), 2.5) and is_equal_approx(w.underwater_fog(23.5), 4.0), "gęstość mgły pod wodą wg pory dnia")
	check(w.sun_visibility(1.0, 13.0) > 0.99 and w.sun_visibility(1.0, 22.0) == 0.0, "widoczność słońca: szczyt o 13:00, 0 nocą")
	env.configure_shadows("high")
	check(env.sun.shadow_enabled and env.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and env.sun.directional_shadow_blend_splits, "cienie wysokie: 4 kaskady")
	env.configure_shadows("off")
	check(not env.sun.shadow_enabled, "cienie wyłączone")
	env.configure_shadows("medium")
	# wnętrze
	env.set_interior({"interior": true, "ambient": {"ambient_rgb": [40, 50, 60], "fog_rgb": [10, 20, 30], "fog_density": 0.75,
		"sunlight_rgb": [87, 58, 13]}})
	# RenderingManager::configureAmbient: we wnętrzu słońce w kolorze „sunlight”, stały kierunek, bez cieni
	check(env.interior and env.sun.visible and env.sun.light_color.is_equal_approx(Color8(87, 58, 13)) and not env.sun.shadow_enabled
		and env.env.background_mode == Environment.BG_COLOR, "wnętrze: bez nieba, słońce w kolorze komórki")
	check((-env.sun.global_transform.basis.z).normalized().is_equal_approx(env.INTERIOR_SUN_DIR.normalized()), "wnętrze: kierunek słońca (−1, 45°, 45°)")
	env.apply()
	check(env.sun.visible and env.sun.light_color.is_equal_approx(Color8(87, 58, 13)), "wnętrze: aktualizacja pogody nie zmienia słońca wnętrza")
	# minimum interior brightness 0,08: ciemny ambient podnoszony do luminancji 0,08, czarny – do szarości 0,08
	var lo: Color = env.interior_ambient(Color8(10, 10, 20))
	check(absf(0.2126 * lo.r + 0.7152 * lo.g + 0.0722 * lo.b - 0.08) < 0.001, "minimum interior brightness: luminancja 0,08")
	check(env.interior_ambient(Color(0, 0, 0)).is_equal_approx(Color(0.08, 0.08, 0.08)) and env.interior_ambient(Color8(40, 50, 60)).is_equal_approx(Color8(40, 50, 60)),
		"minimum interior brightness: czarny → 0,08, jaśniejszy bez zmian")
	check(env.env.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "bez tonemappingu (jak OpenMW)")
	# światło punktowe: zasięg r × 1,75, zanik r/(3d) w gamma → (r/(3d))^2,2 liniowo
	var ol := OmniLight3D.new()
	MWCellBuilder.configure_light(ol, 256.0, Color.WHITE)
	var r_m := 256.0 / MWCoords.UNITS_PER_METER
	check(is_equal_approx(ol.omni_range, 1.75 * r_m) and is_equal_approx(ol.omni_attenuation, 2.2) and is_equal_approx(ol.light_energy, pow(r_m / 3.0, 2.2)),
		"światło punktowe: zasięg 1,75 r, zanik d^−2,2, energia (r/3)^2,2")
	ol.free()
	check(absf(env.env.fog_depth_begin - fd * 0.25) < 0.5, "wnętrze: mgła z gęstości komórki")
	env.set_interior({})
	check(not env.interior and env.sun.visible and env.sun.shadow_enabled, "powrót na zewnątrz (z cieniami)")
	main.queue_free()
	await _frames(2)
	report["checks"] = checks
	print("RESULT ", JSON.stringify({"ok": failures.is_empty(), "failures": failures, "report": report}))
	quit(0 if failures.is_empty() else 1)
