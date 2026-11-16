extends RefCounted
## Most między maszyną skryptów (mw_scripts.gd) a grą (main.gd): wyszukiwanie referencji we wczytanych komórkach,
## pozycje i obroty w jednostkach/stopniach Morrowinda, komunikaty, dźwięki, statystyki, umieszczanie obiektów.

var main
var _scripted := []          # referencje ze skryptem lokalnym we wczytanych komórkach
var _by_base := {}           # id obiektu → pierwsza referencja we wczytanych komórkach
var dirty := true

func _init(game_main) -> void:
	main = game_main

var player:
	get: return main.player
var envr:
	get: return main.envr
var interaction:
	get: return main.interaction

func _rebuild() -> void:
	_scripted.clear()
	_by_base.clear()
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			var b := String(n.get_meta("mw_base", "")).to_lower()
			if not _by_base.has(b):
				_by_base[b] = n
			if not String(main.db.get_object(b).get("script", "")).is_empty():
				_scripted.append(n)
	dirty = false

func scripted_refs() -> Array:
	if dirty:
		_rebuild()
	return _scripted

func find_ref_by_base(id: String) -> Node:
	if dirty:
		_rebuild()
	var n = _by_base.get(id.to_lower())
	return n if n != null and is_instance_valid(n) else null

func menu_mode() -> bool:
	for w in [main.item_window, main.chargen, main.pause_menu, main.msgbox, main.dialogue_window, main.journal_window, main.rest_window, main.trade_window, main.get("magic_window")]:
		if w != null and is_instance_valid(w) and w.visible:
			return true
	return false

func script_message_box(text: String, buttons: Array) -> void:
	main.show_message_box(text, buttons)

func activate_default(node: Node) -> void:
	main.activate(node, true)

# --- pozycje ---------------------------------------------------------------------------------------------

func _node(t: Dictionary) -> Node3D:
	var n = t.get("node")
	return n if n != null and is_instance_valid(n) else null

func _mw_pos(t: Dictionary) -> Variant:
	var n := _node(t)
	if n == null:
		return null
	return MWCoords.godot_to_mw(n.global_position)

func _mw_rot(t: Dictionary) -> Vector3:
	var n := _node(t)
	if n == null:
		return Vector3.ZERO
	if n == main.player:
		return Vector3(0, 0, -n.rotation.y)
	var sid := String(n.get_meta("mw_sid", ""))
	var ov: Dictionary = main.state.refs.get(sid, {})
	if ov.has("mw"):
		var r0: Array = ov.mw.rot
		return Vector3(r0[0], r0[1], r0[2])
	var r: Dictionary = main.base_ref(sid)
	if not r.is_empty():
		return Vector3(r.mw.rot[0], r.mw.rot[1], r.mw.rot[2])
	return Vector3.ZERO

func script_get_transform(t: Dictionary, fname: String, axis: int) -> float:
	if fname.begins_with("getstarting"):
		var n0 := _node(t)
		if n0 != null and n0.has_meta("mw_sid"):
			var r: Dictionary = main.base_ref(String(n0.get_meta("mw_sid")))
			if not r.is_empty():
				return float(r.mw.pos[axis]) if fname == "getstartingpos" else rad_to_deg(float(r.mw.rot[axis]))
	if fname.ends_with("pos"):
		var p = _mw_pos(t)
		return float(p[axis]) if p != null else 0.0
	return rad_to_deg(_mw_rot(t)[axis])

func _move(t: Dictionary, pos: Vector3, rot_z_deg: float, cell := "") -> void:
	var n := _node(t)
	if String(t.get("sid", "")) == "player" or n == main.player:
		if not cell.is_empty():
			main.travel_to_cell(cell, pos, rot_z_deg)
			return
		main.player.global_position = MWCoords.mw_to_godot(pos)
		if not is_nan(rot_z_deg):
			main.player.rotation.y = -deg_to_rad(rot_z_deg)
		main.player.velocity = Vector3.ZERO
		return
	var sid := String(t.get("sid", ""))
	if sid.is_empty():
		return
	var rot := _mw_rot(t)
	if not is_nan(rot_z_deg):
		rot.z = deg_to_rad(rot_z_deg)
	main.state.set_ref_mw(sid, pos, rot)

func script_set_transform(t: Dictionary, fname: String, args: Array, c, vm) -> void:
	if t.is_empty():
		return
	var p = _mw_pos(t)
	var pos: Vector3 = p if p != null else Vector3.ZERO
	match fname:
		"setpos":
			var ax := int(vm.AXES.get(vm._str(args, 0).to_lower(), 0))
			pos[ax] = vm._num(args, 1, c)
			_move(t, pos, NAN)
		"setangle":
			var ax2 := int(vm.AXES.get(vm._str(args, 0).to_lower(), 2))
			if ax2 == 2:
				_move(t, pos, vm._num(args, 1, c))
			else:
				vm._unsupported("setangle x/y")
		"position":
			_move(t, Vector3(vm._num(args, 0, c), vm._num(args, 1, c), vm._num(args, 2, c)), vm._num(args, 3, c))
		"positioncell":
			_move(t, Vector3(vm._num(args, 0, c), vm._num(args, 1, c), vm._num(args, 2, c)), vm._num(args, 3, c),
					vm._str(args, 4))
		"setatstart":
			var n := _node(t)
			if n != null and n.has_meta("mw_sid"):
				var r: Dictionary = main.base_ref(String(n.get_meta("mw_sid")))
				if not r.is_empty():
					main.state.set_ref_mw(String(n.get_meta("mw_sid")), Vector3(r.mw.pos[0], r.mw.pos[1], r.mw.pos[2]),
							Vector3(r.mw.rot[0], r.mw.rot[1], r.mw.rot[2]))

func script_distance(a: Dictionary, b: Dictionary) -> float:
	var pa = _mw_pos(a)
	var pb = _mw_pos(b)
	if pa == null or pb == null:
		return 1e9          # nieobecny obiekt – „daleko”
	return (pa as Vector3).distance_to(pb)

func player_cell_name() -> String:
	if not main.interior.is_empty():
		return main.interior
	var c: Dictionary = main.db.get_cell(main.db.exterior_key(MWCoords.cell_of(main.player.global_position)))
	var n := String(c.get("name", ""))
	return n if not n.is_empty() else String(c.get("region", ""))

func script_sound(id: String, t: Dictionary) -> void:
	if main.audio == null:
		return
	var n := _node(t)
	main.audio.play(id, n.global_position if n != null and n != main.player else null)

# --- statystyki ------------------------------------------------------------------------------------------

func character_stat_names() -> Array:
	return main.builder.actors.records_index().get("attributes", []).map(func(s): return String(s).to_lower()) \
			+ main.builder.actors.records_index().get("skills", []).map(func(s): return String(s).to_lower())

func script_stat(t: Dictionary, fname: String) -> float:
	var name := fname.substr(3)
	if String(t.get("sid", "")) == "player" or t.is_empty():
		var st: Dictionary = main.player_stats()
		if st.is_empty():
			return 0.0
		var d: Dictionary = main.character.derived(st)
		match name:
			"level": return float(st.get("level", 1))
			"health": return float(st.get("health", 0))
			"magicka": return float(st.get("magicka", 0))
			"fatigue": return float(st.get("fatigue", 0))
		var attrs: Array = main.builder.actors.records_index().get("attributes", []).map(func(s): return String(s).to_lower())
		var skills: Array = main.builder.actors.records_index().get("skills", []).map(func(s): return String(s).to_lower())
		if name in attrs:
			return float(d.attributes[attrs.find(name)])
		if name in skills:
			return float(d.skills[skills.find(name)])
		return 0.0
	var base := String(t.get("base", ""))
	var rec: Dictionary = main.builder.actors.record("npc", base)
	if rec.is_empty():
		var cr: Dictionary = main.builder.actors.record("creature", base)
		match name:
			"level": return float(cr.get("level", 1))
			"health": return float(main.state.actors.get(String(t.get("sid", "")), {}).get("health", cr.get("health", 0)))
		return 0.0
	match name:
		"level": return float(rec.get("level", 1))
		"health": return float(main.state.actors.get(String(t.get("sid", "")), {}).get("health", npc_health(rec)))
	return 0.0

## Zdrowie NPC: z rekordu albo autoobliczone jak OpenMW (npc.cpp autoCalculateAttributes).
func npc_health(rec: Dictionary) -> float:
	if not bool(rec.get("autocalc", false)) and rec.has("health"):
		return float(rec["health"])
	return float(npc_autocalc(rec).health)

## Zaokrąglenie jak round_ieee_754 w OpenMW (npc.cpp): połówki do parzystej.
static func round_even(f: float) -> float:
	var i := floorf(f)
	var r := f - i
	if r < 0.5:
		return i
	if r > 0.5:
		return i + 1.0
	return i if fmod(i, 2.0) == 0.0 else i + 1.0

## Atrybuty, umiejętności i zdrowie NPC (rekord z NPDT 52 B – wartości z rekordu; autoobliczanie jak OpenMW:
## autoCalculateAttributes – rasa + 10 ulubionym klasy + (poziom − 1) × suma mnożników umiejętności atrybutu
## (główne 1, drugorzędne 0,5, pozostałe 0,2); autoCalculateSkills – 5 + premia rasy + 5 specjalizacji
## (+10 drugorzędne, +25 główne) + (poziom − 1) × (1 główne/drugorzędne, 0,1 pozostałe; +0,5 specjalizacji);
## zdrowie = ⌊(siła + wytrzymałość) / 2⌋ + mnożnik × (poziom − 1), mnożnik 3 (+2 walka, +1 skradanie,
## +1 gdy wytrzymałość jest ulubionym atrybutem).
func npc_autocalc(rec: Dictionary) -> Dictionary:
	if not bool(rec.get("autocalc", false)) and rec.has("attributes"):
		return {"attributes": rec.attributes, "skills": rec.get("skills", []), "health": float(rec.get("health", 0))}
	var av = main.builder.actors
	var race: Dictionary = av.record("race", String(rec.get("race", "")))
	var cls: Dictionary = av.record("class", String(rec.get("class", "")))
	var female := bool(rec.get("female", false))
	var level := int(rec.get("level", 1))
	var ra: Array = (race.get("attributes", {}) as Dictionary).get("female" if female else "male", [])
	var attrs := []
	for i in 8:
		attrs.append(float(ra[i]) if i < ra.size() else 0.0)
	var fav: Array = cls.get("attributes", []).map(func(x): return int(x))
	for a in fav:
		if a >= 0 and a < 8:
			attrs[a] += 10.0
	var major: Array = cls.get("major_skills", []).map(func(x): return int(x))
	var minor: Array = cls.get("minor_skills", []).map(func(x): return int(x))
	var names: Array = av.records_index().get("skills", [])
	var spec := int(cls.get("specialization", -1))
	for ai in 8:
		var mod := 0.0
		for si in names.size():
			var sk: Dictionary = av.record("skill", String(names[si]))
			if int(sk.get("attribute", -1)) != ai:
				continue
			mod += 1.0 if si in major else (0.5 if si in minor else 0.2)
		attrs[ai] = minf(round_even(attrs[ai] + (level - 1) * mod), 100.0)
	var skills := []
	for si in names.size():
		var base := 0.0
		if si in minor:
			base += 10.0
		if si in major:
			base += 25.0
		var bonus := 0
		for b in race.get("skill_bonuses", []):
			if int(b.get("skill", -1)) == si:
				bonus = int(b.get("bonus", 0))
		var sk2: Dictionary = av.record("skill", String(names[si]))
		var mm := 1.0 if (si in major or si in minor) else 0.1
		var sm := 0.0
		var sb := 0
		if int(sk2.get("specialization", -2)) == spec:
			sm = 0.5
			sb = 5
		skills.append(minf(round_even(base + 5 + bonus + sb + (level - 1) * (mm + sm)), 100.0))
	var mult := 3
	match spec:
		0: mult += 2
		2: mult += 1
	if 5 in fav:
		mult += 1
	return {"attributes": attrs, "skills": skills, "health": floorf(0.5 * (attrs[0] + attrs[5])) + mult * (level - 1)}

# --- umieszczanie obiektów -------------------------------------------------------------------------------

func script_place(fname: String, id: String, count: int, t: Dictionary, args: Array, c, vm) -> void:
	var key: String = ("int:" + String(main.interior).to_lower()) if not String(main.interior).is_empty() \
			else String(main.db.exterior_key(MWCoords.cell_of(main.player.global_position)))
	var pos: Vector3 = MWCoords.godot_to_mw(main.player.global_position)
	var rot_z: float = -float(main.player.rotation.y)
	match fname:
		"placeatpc", "placeatme":
			if fname == "placeatme":
				var p = _mw_pos(t)
				if p != null:
					pos = p
			var dist: float = vm._num(args, 2, c, 0.0)
			var dir: int = int(vm._num(args, 3, c, 0.0))             # 0 przód, 1 tył, 2 lewo, 3 prawo
			var ang: float = rot_z + [0.0, PI, -PI / 2.0, PI / 2.0][clampi(dir, 0, 3)]
			pos += Vector3(sin(ang), cos(ang), 0.0) * dist
		"placeitem":
			pos = Vector3(vm._num(args, 1, c), vm._num(args, 2, c), vm._num(args, 3, c))
			rot_z = deg_to_rad(vm._num(args, 4, c))
			count = 1
	for i in maxi(1, count):
		main.state.add_dynamic(id, key, pos, Vector3(0, 0, rot_z), 1)
	dirty = true

# --- etap 9: tworzenie postaci przez skrypty, sterowanie, menu, pogoda, głosy ------------------------------

## Blokady sterowania gracza (Disable/EnablePlayerControls, …Fighting, …Jumping, …Magic, …ViewSwitch,
## VanityMode, …Looking) – w stanie gracza (zapis), brak wpisu = dozwolone.
func set_control(kind: String, on: bool) -> void:
	var c: Dictionary = main.state.player.get("controls", {})
	c[kind] = on
	main.state.player["controls"] = c

func control_enabled(kind: String) -> bool:
	return bool((main.state.player.get("controls", {}) as Dictionary).get(kind, true))

## Menu tworzenia postaci wywoływane skryptem (EnableNameMenu, …Race…, …Class…, …Birth…, …StatReview…).
func chargen_menu(step: String) -> void:
	main.open_chargen_step(step)

## Dostęp do okien (nowa gra w Morrowindzie: okna zablokowane, odblokowują je skrypty CharGen).
func enable_menu(kind: String) -> void:
	var m: Dictionary = main.state.player.get("menus", {})
	m[kind] = true
	main.state.player["menus"] = m

func disable_menu(kind: String) -> void:
	var m: Dictionary = main.state.player.get("menus", {})
	m[kind] = false
	main.state.player["menus"] = m

func show_rest_menu() -> void:
	if main.rest_window != null and not main.rest_window.visible:
		main.rest_window.open()

const WEATHER_NAMES := ["clear", "cloudy", "foggy", "overcast", "rain", "thunderstorm", "ashstorm", "blight", "snow", "blizzard"]

## ChangeWeather region typ – natychmiast, gdy gracz jest w tym regionie (WeatherManager::changeWeather).
func change_weather(region: String, idx: int) -> void:
	if idx < 0 or idx >= WEATHER_NAMES.size() or main.envr == null:
		return
	var over: Dictionary = main.state.player.get("weather_override", {})
	over[region.to_lower()] = WEATHER_NAMES[idx]
	main.state.player["weather_override"] = over
	if String(main.envr.region).to_lower() == region.to_lower():
		main.envr.weather = WEATHER_NAMES[idx]
		main.envr.apply()

## GetStandingPC: gracz stoi na tym obiekcie (kolizja podłoża po ruchu).
func player_standing_on(t: Dictionary) -> bool:
	var n := _node(t)
	var p: CharacterBody3D = main.player
	if n == null or p == null or not p.is_on_floor():
		return false
	for i in p.get_slide_collision_count():
		var col := p.get_slide_collision(i).get_collider() as Node
		while col != null:
			if col == n:
				return true
			col = col.get_parent()
	return false

var _say_until := {}         # sid → czas gry (MWScripts.clock) końca kwestii

## Say: napis jak w OpenMW przy włączonych napisach (nagrania głosów – etap 10); czas kwestii z długości tekstu.
func say(t: Dictionary, _file: String, text: String) -> void:
	var key := String(t.get("sid", ""))
	var secs := 1.0 + 0.06 * text.length()
	_say_until[key] = float(main.scripts.clock) + secs
	if not text.is_empty():
		var who := ""
		var n := _node(t)
		if n != null and main.dialogue != null and main.dialogue.is_actor_node(n):
			who = main.dialogue.actor_name(main.dialogue.make_actor(n)) + ": "
		main.subtitle(who + text, secs)

func say_done(t: Dictionary) -> bool:
	return float(main.scripts.clock) >= float(_say_until.get(String(t.get("sid", "")), 0.0))

## Przedmioty ze skryptem w ekwipunku gracza: [[id, skrypt, liczba]].
func player_scripted_items() -> Array:
	var out := []
	if main.interaction == null:
		return out
	for e in main.interaction.inventory.contents("player", {}):
		var it: Dictionary = main.interaction.inventory.item(String(e.id))
		var s := String((it.get("rec", {}) as Dictionary).get("script", "")) if not it.is_empty() else ""
		if s.is_empty():
			s = String(main.db.get_object(String(e.id).to_lower()).get("script", ""))
		if not s.is_empty():
			out.append([String(e.id).to_lower(), s.to_lower(), int(e.count)])
	return out

## Rotate/RotateWorld oś stopnie·s⁻¹ (× czas klatki): obrót wizualny obiektu (latarnie, statek kołyszą się).
func script_rotate(t: Dictionary, axis: String, deg: float) -> void:
	var n := _node(t)
	if n == null or n == main.player or deg == 0.0:
		return
	var a := deg_to_rad(deg)
	match axis:
		"z": n.rotate_y(-a)                     # MW Z (w górę) = Godot Y; kąt MW zgodnie ze wskazówkami
		"x": n.rotate_object_local(Vector3.RIGHT, a)
		"y": n.rotate_object_local(Vector3.FORWARD, a)

## PlayGroup/LoopGroup: animacja z biblioteki aktora albo obiektu (np. bezczynność skryptowa); bez grupy – nic.
func play_group(t: Dictionary, group: String, _mode: int, loop: bool, _count: int) -> void:
	var n := _node(t)
	if n == null:
		return
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		if a.has_animation(group):
			a.play(group)
			if loop:
				a.get_animation(group).loop_mode = Animation.LOOP_LINEAR
			return
