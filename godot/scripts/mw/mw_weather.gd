extends RefCounted
## Pogoda jak OpenMW WeatherManager (apps/openmw/mwworld/weather.cpp): wartości z Morrowind.ini (Fallback
## „Weather_*”) – z instalacji gracza (world/fallbacks.json), a brakujące z domyślnych OpenMW
## (res://data/openmw_fallback_defaults.json). Kolory nieba, mgły, światła otoczenia i słońca oraz głębokość mgły
## w 4 porach (wschód, dzień, zachód, noc) z przejściami TimeOfDayInterpolator; zmiana pogody co
## Weather_Hours_Between_Weather_Changes godzin (losowanie wg szans regionu) i płynne przejście
## (Transition_Delta na sekundę rzeczywistą; mieszanie chmur wg Clouds_Maximum_Percent); kierunek słońca jak
## w Morrowindzie (-400·orbita, 75, -100), tarcza słońca o zachodzie (Sun_Disc_Sunset_Color) i gaśnięcie.

const NAMES := ["clear", "cloudy", "foggy", "overcast", "rain", "thunder", "ash", "blight", "snow", "blizzard"]
const INI := ["Clear", "Cloudy", "Foggy", "Overcast", "Rain", "Thunderstorm", "Ashstorm", "Blight", "Snow", "Blizzard"]

var fb := {}                             # klucz fallback → tekst
var current := 0                         # indeks w NAMES
var next_w := -1
var queued := -1
var transition := 0.0                    # 1 → 0 w trakcie przejścia (mTransitionFactor)
var update_time := 20.0                  # godziny do następnej zmiany pogody
var region := ""
var change_index := 0
var result := {}

func load(data_root: String) -> void:
	fb = {}
	for p in ["res://data/openmw_fallback_defaults.json", data_root.path_join("world/fallbacks.json")]:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary and j.get("values") is Dictionary:
			for k in j["values"]:
				fb[String(k)] = String(j["values"][k])
	update_time = num("Weather_Hours_Between_Weather_Changes", 20.0)

func num(k: String, def := 0.0) -> float:
	var v := String(fb.get(k, ""))
	return float(v) if v.is_valid_float() else def

func colour(k: String) -> Color:
	var p := String(fb.get(k, "")).split(",")
	if p.size() < 3:
		return Color.BLACK
	return Color8(int(p[0]), int(p[1]), int(p[2]))

func text(k: String) -> String:
	return String(fb.get(k, ""))

func idx(name: String) -> int:
	return maxi(0, NAMES.find(name.to_lower()))

# --- pory dnia --------------------------------------------------------------------------------------

func times() -> Dictionary:
	var sunrise := num("Weather_Sunrise_Time", 6.0)
	var sunset := num("Weather_Sunset_Time", 18.0)
	return {"sunrise": sunrise, "sunset": sunset, "night_start": sunset + num("Weather_Sunset_Duration", 2.0),
		"night_end": sunrise, "day_start": sunrise + num("Weather_Sunrise_Duration", 2.0), "day_end": sunset,
		"sunrise_duration": num("Weather_Sunrise_Duration", 2.0)}

## Pre-/Post-Sunrise/Sunset_Time dla „Sky”, „Ambient”, „Fog”, „Sun” (brak klucza = 0).
func _setting(prefix: String) -> Array:
	return [num("Weather_%s_Pre-Sunrise_Time" % prefix), num("Weather_%s_Post-Sunrise_Time" % prefix),
		num("Weather_%s_Pre-Sunset_Time" % prefix), num("Weather_%s_Post-Sunset_Time" % prefix)]

## TimeOfDayInterpolator::getValue: vals = [wschód, dzień, zachód, noc] (Color albo float).
func tod(vals: Array, hour: float, prefix: String):
	var t := times()
	var s := _setting(prefix)
	var pre_rise: float = s[0]
	var post_rise: float = s[1]
	var pre_set: float = s[2]
	var post_set: float = s[3]
	if hour < t.night_end - pre_rise or hour > t.night_start + post_set:
		return vals[3]
	if hour >= t.night_end - pre_rise and hour <= t.day_start + post_rise:
		var d: float = t.day_start + post_rise - t.night_end + pre_rise
		var mid: float = t.night_end - pre_rise + d / 2.0
		if hour <= mid:
			return lerp(vals[0], vals[3], (mid - hour) / d * 2.0 if d > 0 else 0.0)
		return lerp(vals[0], vals[1], (hour - mid) / d * 2.0 if d > 0 else 1.0)
	if hour > t.day_start + post_rise and hour < t.day_end - pre_set:
		return vals[1]
	var d2: float = t.night_start + post_set - t.day_end + pre_set
	var mid2: float = t.day_end - pre_set + d2 / 2.0
	if hour <= mid2:
		return lerp(vals[2], vals[1], (mid2 - hour) / d2 * 2.0 if d2 > 0 else 0.0)
	return lerp(vals[2], vals[3], (hour - mid2) / d2 * 2.0 if d2 > 0 else 1.0)

func _four(w: int, what: String) -> Array:
	var n: String = INI[w]
	return [colour("Weather_%s_%s_Sunrise_Color" % [n, what]), colour("Weather_%s_%s_Day_Color" % [n, what]),
		colour("Weather_%s_%s_Sunset_Color" % [n, what]), colour("Weather_%s_%s_Night_Color" % [n, what])]

## calculateResult dla jednej pogody.
func calc(w: int, hour: float) -> Dictionary:
	var n: String = INI[w]
	var t := times()
	var r := {}
	r.sky = tod(_four(w, "Sky"), hour, "Sky")
	r.fog = tod(_four(w, "Fog"), hour, "Fog")
	r.ambient = tod(_four(w, "Ambient"), hour, "Ambient")
	r.sun = tod(_four(w, "Sun"), hour, "Sun")
	var dd := num("Weather_%s_Land_Fog_Day_Depth" % n, 0.5)
	r.fog_depth = tod([dd, dd, dd, num("Weather_%s_Land_Fog_Night_Depth" % n, dd)], hour, "Fog")
	r.cloud_texture = text("Weather_%s_Cloud_Texture" % n)
	r.cloud_speed = num("Weather_%s_Cloud_Speed" % n, 1.0)
	r.wind_speed = num("Weather_%s_Wind_Speed" % n, 0.1)
	r.glare = num("Weather_%s_Glare_View" % n, 0.0)
	# gwiazdy (mNightFade): ustawienia „Stars”
	var sp := num("Weather_Stars_Post-Sunset_Start", 1.0)
	var spr := num("Weather_Stars_Pre-Sunrise_Finish", 2.0)
	var sfd := num("Weather_Stars_Fading_Duration", 2.0)
	r.night_fade = _stars(hour, t, [spr, sfd - spr, sp, sfd - sp])
	# tarcza słońca: kolor o zachodzie i przezroczystość (zachód/wschód)
	var pre := num("Weather_Sun_Pre-Sunset_Time", 0.0)
	var disc := Color.WHITE
	if hour >= t.day_end - pre:
		var f := minf(1.0, (hour - (t.day_end - pre)) / pre) if pre > 0 else 1.0
		disc = Color.WHITE.lerp(colour("Weather_%s_Sun_Disc_Sunset_Color" % n), f)
		var amb: Color = r.ambient
		disc = Color(minf(1.0, disc.r + disc.r * amb.r), minf(1.0, disc.g + disc.g * amb.g), minf(1.0, disc.b + disc.b * amb.b))
	var a := 1.0
	if hour >= t.day_end:
		var fade := minf(1.0, (hour - t.day_end) / (t.night_start - t.day_end))
		a = 1.0 - fade * fade
	elif hour >= t.night_end and hour <= t.night_end + t.sunrise_duration / 2.0:
		a = hour - t.night_end
	disc.a = clampf(a, 0.0, 1.0)
	r.sun_disc = disc
	return r

func _stars(hour: float, t: Dictionary, s: Array) -> float:
	# TimeOfDayInterpolator<float>(0, 0, 0, 1) z ustawieniami „Stars”
	var pre_rise: float = s[0]
	var post_rise: float = s[1]
	var pre_set: float = s[2]
	var post_set: float = s[3]
	if hour < t.night_end - pre_rise or hour > t.night_start + post_set:
		return 1.0
	if hour >= t.night_end - pre_rise and hour <= t.day_start + post_rise:
		var d: float = t.day_start + post_rise - t.night_end + pre_rise
		var mid: float = t.night_end - pre_rise + d / 2.0
		return lerpf(0.0, 1.0, (mid - hour) / d * 2.0) if hour <= mid and d > 0 else 0.0
	if hour > t.day_start + post_rise and hour < t.day_end - pre_set:
		return 0.0
	var d2: float = t.night_start + post_set - t.day_end + pre_set
	var mid2: float = t.day_end - pre_set + d2 / 2.0
	return 0.0 if hour <= mid2 or d2 <= 0 else lerpf(0.0, 1.0, (hour - mid2) / d2 * 2.0)

## Wynik z uwzględnieniem przejścia (calculateTransitionResult).
func compute(hour: float) -> Dictionary:
	if next_w < 0:
		result = calc(current, hour)
		result.next_cloud_texture = ""
		result.cloud_blend = 0.0
		return result
	var f := 1.0 - transition
	var a := calc(current, hour)
	var b := calc(next_w, hour)
	result = a.duplicate()
	for k in ["sky", "fog", "ambient", "sun", "sun_disc"]:
		result[k] = (a[k] as Color).lerp(b[k], f)
	for k in ["fog_depth", "cloud_speed", "wind_speed", "glare", "night_fade"]:
		result[k] = lerpf(a[k], b[k], f)
	result.next_cloud_texture = b.cloud_texture
	result.cloud_blend = clampf(f / maxf(num("Weather_%s_Clouds_Maximum_Percent" % INI[next_w], 1.0), 0.001), 0.0, 1.0)
	return result

## Kierunek DO słońca w układzie MW (x wschód, y północ, z góra): pozycja światła = −(−400·orbita, 75, −100).
func sun_direction_mw(hour: float) -> Vector3:
	var t := times()
	var h := hour
	var ns: float = t.night_start
	if h < t.sunrise:
		h += 24.0
	if ns < t.sunrise:
		ns += 24.0
	var orbit := 0.0
	if h < ns:
		orbit = 1.0 - 2.0 * (h - t.sunrise) / (ns - t.sunrise)
	else:
		orbit = 2.0 * (h - ns) / (24.0 - (ns - t.sunrise)) - 1.0
	return Vector3(400.0 * orbit, -75.0, 100.0).normalized()

func is_night(hour: float) -> bool:
	var t := times()
	return hour >= t.night_start or hour <= t.sunrise

# --- zmiany pogody ----------------------------------------------------------------------------------

func in_transition() -> bool:
	return next_w >= 0

## addWeatherTransition: od razu, gdy nie ma przejścia; inaczej w kolejce.
func add_transition(w: int) -> void:
	if not in_transition() and w != current:
		next_w = w
		transition = 1.0
	elif in_transition() and w != next_w:
		queued = w

## Natychmiast (początek gry, wczytanie, tryb zrzutu).
func force(w: int) -> void:
	current = w
	next_w = -1
	queued = -1
	transition = 0.0

## updateWeatherTransitions: realne sekundy × Transition_Delta pogody docelowej.
func update_transition(real_seconds: float) -> void:
	if not in_transition():
		if queued >= 0:
			add_transition(queued)
			queued = -1
		return
	var delta := num("Weather_%s_Transition_Delta" % INI[next_w], 0.015)
	transition -= real_seconds * delta
	if transition <= 0.0:
		current = next_w
		next_w = -1
		transition = 0.0
		if queued >= 0:
			var q := queued
			queued = -1
			add_transition(q)

## Losowanie pogody regionu (RegionWeather::chooseNewWeather) – rzut 0..99 wg skumulowanych szans.
static func choose(chances: Dictionary, roll: int) -> String:
	var sum := 0
	for k in ["clear", "cloudy", "foggy", "overcast", "rain", "thunder", "ash", "blight", "snow", "blizzard"]:
		sum += int(chances.get(k, 0))
		if roll < sum:
			return k
	return "clear"

## Upływ czasu gry (godziny): co Hours_Between_Weather_Changes nowa pogoda regionu.
func advance_hours(hours: float) -> bool:
	update_time -= hours
	if update_time <= 0.0:
		update_time += maxf(num("Weather_Hours_Between_Weather_Changes", 20.0), 1.0)
		change_index += 1
		return true
	return false
