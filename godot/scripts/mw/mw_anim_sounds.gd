extends Node
## Dźwięki z kluczy animacji (etap 10) jak OpenMW CharacterController::handleTextKey: „Sound: <id>” – dźwięk 3D
## przy aktorze; „SoundGen: <rodzaj> [głośność] [wysokość]” – NPC: kroki wg butów (Npc::getSoundIdFromSndGen:
## bez butów pancernych – boso, lekkie/średnie/ciężkie wg wagi, pływanie „Swim Left/Right”, w wodzie
## „FootWater…”), stworzenia: rekordy SNDG (Creature::getSoundIdFromSndGen – własne stworzenia, potem
## stworzenia o tym samym modelu, potem ogólne; losowo spośród pasujących). Kroki – głośność kroków.
## Także kroki gracza (zamiast stałego „boso”) wg tych samych zasad.

const RANGE := 40.0                    # m – dalej nie śledzimy kluczy (dźwięki i tak niesłyszalne)
const SOUNDGEN_TYPES := ["left", "right", "swimleft", "swimright", "moan", "roar", "scream", "land"]

var main
var _state := {}                       # instance_id węzła → [animacja, pozycja]
var _boots := {}                       # sid → [umiejętność butów, czas]
var _sndg: Array = []                  # rekordy SNDG
var _sndg_loaded := false
var played: Array = []                 # testy: [sid, id dźwięku]
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func _soundgens() -> Array:
	if not _sndg_loaded:
		_sndg_loaded = true
		var all: Dictionary = main.builder.actors._all("soundgen") if main.builder.actors.has_method("_all") else {}
		_sndg = all.values()
	return _sndg

func tick(_delta: float) -> void:
	if main == null or main.ai == null or main.audio == null or main.player == null:
		return
	var pp: Vector3 = main.player.global_position
	var seen := {}
	for n in main.ai.actor_nodes():
		if not is_instance_valid(n) or (n as Node3D).global_position.distance_to(pp) > RANGE:
			continue
		var ap: AnimationPlayer = main.ai._player_of(n)
		if ap == null or not ap.is_playing():
			continue
		var id: int = n.get_instance_id()
		seen[id] = true
		var anim := String(ap.current_animation)
		var pos := ap.current_animation_position
		var prev: Array = _state.get(id, ["", 0.0])
		_state[id] = [anim, pos]
		var a := ap.get_animation(anim)
		if a == null:
			continue
		var keys: Array = a.get_meta("mw_keys", [])
		if keys.is_empty():
			continue
		var from := -0.001
		if String(prev[0]) == anim:
			from = float(prev[1])
		for k in keys:
			var t := float(k[0])
			var hit := (t > from and t <= pos) if pos >= from else (t > from or t <= pos)   # zapętlenie
			if hit:
				handle_key(n, String(k[1]))
	for id in _state.keys():
		if not seen.has(id):
			_state.erase(id)

## Obsługa jednego klucza tekstowego (małe litery).
func handle_key(n: Node3D, key: String) -> void:
	var sid := String(n.get_meta("mw_sid", ""))
	if key.begins_with("sound:"):
		var snd := key.substr(6).strip_edges()
		_play(sid, snd, n, 1.0, 1.0, false)
		return
	if not key.begins_with("soundgen:"):
		return
	var parts := key.substr(9).strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var gen := String(parts[0])
	var vol := float(parts[1]) if parts.size() > 1 and String(parts[1]).is_valid_float() else 1.0
	var pitch := float(parts[2]) if parts.size() > 2 and String(parts[2]).is_valid_float() else 1.0
	var snd := sound_for(n, gen)
	if not snd.is_empty():
		_play(sid, snd, n, vol, pitch, gen == "left" or gen == "right")

func _play(sid: String, snd: String, n: Node3D, vol: float, pitch: float, foot: bool) -> void:
	var v: float = vol * (main.audio.footsteps_volume / maxf(main.audio.sfx_volume, 0.01) if foot else 1.0)
	main.audio.play_on(sid + "|anim", snd, n.global_position + Vector3(0, 0.1 if foot else 1.0, 0), v, pitch)
	played.append([sid, snd])
	if played.size() > 50:
		played.pop_front()

func _is_creature(n: Node) -> bool:
	return String(n.get_meta("mw_actor", "")) == "creature"

## Npc::getSoundIdFromSndGen / Creature::getSoundIdFromSndGen.
func sound_for(n: Node3D, gen: String) -> String:
	var swimming := bool(n.get("swimming"))
	var on_floor: bool = (n as CharacterBody3D).is_on_floor() if n is CharacterBody3D else true
	var in_water := float(n.get("water_level")) > n.global_position.y if n.get("water_level") != null else false
	if _is_creature(n):
		var type := -1
		match gen:
			"left", "right":
				if bool(n.get("fly")):
					return ""
				if in_water or swimming:
					type = 2 if gen == "left" else 3
				elif on_floor:
					type = 0 if gen == "left" else 1
			_:
				type = SOUNDGEN_TYPES.find(gen)
		return creature_sound(String(n.get_meta("mw_base", "")).to_lower(), type) if type >= 0 else ""
	match gen:
		"left", "right":
			return footstep(n, gen == "left", swimming, in_water, on_floor)
		"swimleft":
			return "Swim Left"
		"swimright":
			return "Swim Right"
	return ""                              # land, moan… – NPC mówią kwestiami głosowymi

## Kroki NPC i gracza wg butów (skill pancerza butów).
func footstep(n: Node3D, left: bool, swimming: bool, in_water: bool, on_floor: bool) -> String:
	if swimming:
		return "Swim Left" if left else "Swim Right"
	if in_water:
		return "FootWaterLeft" if left else "FootWaterRight"
	if not on_floor:
		return ""
	var sk := boots_skill(n)
	var side := "Left" if left else "Right"
	match sk:
		21: return "footLight" + side
		2: return "FootMed" + side
		3: return "FootHeavy" + side
	return "FootBare" + side

func boots_skill(n: Node) -> int:
	var f: Dictionary = main.combat.fighter_of(n) if n != main.player else main.combat.player_fighter()
	var key := String(f.get("sid", "player"))
	var now := Time.get_ticks_msec()
	var c: Array = _boots.get(key, [-1, -100000])
	if now - int(c[1]) < 3000:
		return int(c[0])
	var boots: Dictionary = main.combat.equipment(f).get(main.combat.EQ.SLOT_BOOTS, {})
	var sk := -1
	if not boots.is_empty() and String(boots.get("kind", "")) == "armor":
		sk = main.combat.armor_skill(boots.rec)
	_boots[key] = [sk, now]
	return sk

## Rekordy SNDG: najpierw stworzenie (albo jego „oryginał”), potem stworzenia o tym samym modelu, potem ogólne.
var _pools := {}                       # "stworzenie|typ" → lista rekordów SNDG (pamięć podręczna)

func creature_sound(base: String, type: int) -> String:
	var ck := "%s|%d" % [base, type]
	if not _pools.has(ck):
		_pools[ck] = _creature_pool(base, type)
	var pool: Array = _pools[ck]
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)].get("sound", ""))

func _creature_pool(base: String, type: int) -> Array:
	var rec: Dictionary = main.builder.actors.record("creature", base)
	var our := String(rec.get("original", "")).to_lower()
	if our.is_empty():
		our = base
	var own := []
	var generic := []
	for g in _soundgens():
		if int(g.get("type", -1)) != type:
			continue
		var cr := String(g.get("creature", ""))
		if cr.is_empty():
			generic.append(g)
		elif cr == our:
			own.append(g)
	if own.is_empty():
		var model := String(main.db.get_object(base).get("model", "")).to_lower()
		if not model.is_empty():
			for id in (main.builder.actors._all("creature") as Dictionary):
				var cr2: Dictionary = main.builder.actors._all("creature")[id]
				if id == our or String(cr2.get("original", "")).to_lower() == our:
					continue
				if String(main.db.get_object(String(id)).get("model", "")).to_lower() == model:
					var fid := String(cr2.get("original", "")).to_lower()
					if fid.is_empty():
						fid = String(id)
					for g in _soundgens():
						if int(g.get("type", -1)) == type and String(g.get("creature", "")) == fid:
							own.append(g)
					break
	return own if not own.is_empty() else generic
