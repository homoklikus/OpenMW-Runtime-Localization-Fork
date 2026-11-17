extends RefCounted
## Statystyki aktorów dla MWScript – jedna warstwa nad danymi gracza (GameState.player.character) i stanem NPC/
## stworzeń (GameState.actors[sid]), z semantyką OpenMW (apps/openmw/mwscript/statsextensions.cpp,
## mwmechanics/stat.cpp, creaturestats.cpp):
##  - atrybuty/umiejętności: baza, modyfikator (efekty + korekta „mod_adjust”), ubytek („magic_damage”);
##    Set* = setBase(v, true) – modyfikator i ubytek wyzerowane; Mod* = modStat (obcinanie do 100, ujemne);
##    Set/Mod umiejętności tylko dla NPC i gracza (stworzenia: bez zmian, jak isNpc());
##  - zdrowie/magia/kondycja: baza (zdrowie – „health_base”, magia/kondycja – „dyn_base” do czasu przeliczenia),
##    bieżąca; SetHealth: baza = v, bieżąca = zmodyfikowana; ModHealth: baza + d (zdrowie/magia ≥ 0), bieżąca + d
##    bez ograniczeń; ModCurrentHealth: DynamicStat::setCurrent (wzrost do zmodyfikowanej, spadek do 0; kondycja
##    może zejść poniżej zera i powala);
##  - efekty magiczne (GetResistFire… – rodzina 24 efektów): wartość = efekt dodatni − słabość (+ tarcza żywiołu
##    dla ognia/mrozu/błyskawic), Set* = modifyBase(arg − wartość), Mod* = modifyBase(arg) – „effect_base”;
##  - poziom (SetLevel/GetLevel).
## Śmierć po zejściu zdrowia do zera przetwarza świat w następnej klatce (Actors::update) – tu odroczone wywołanie.

const ATTRS := ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
const SKILLS := ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear",
	"athletics", "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration",
	"alchemy", "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman",
	"mercantile", "speechcraft", "handtohand"]
const DYNAMICS := ["health", "magicka", "fatigue"]
## statsextensions.cpp sMagicEffects: nazwa → [efekt dodatni, efekt ujemny (−1 – brak)]
const MAGIC_EFFECTS := {"resistmagicka": [93, 31], "resistfire": [90, 28], "resistfrost": [91, 29],
	"resistshock": [92, 30], "resistdisease": [94, 32], "resistblight": [95, 33], "resistcorprus": [96, 34],
	"resistpoison": [97, 35], "resistparalysis": [99, -1], "resistnormalweapons": [98, 36],
	"waterbreathing": [0, -1], "chameleon": [40, -1], "waterwalking": [2, -1], "swimspeed": [1, -1],
	"superjump": [9, -1], "flying": [10, -1], "armorbonus": [3, -1], "castpenalty": [48, -1], "silence": [46, -1],
	"blindness": [47, -1], "paralysis": [45, -1], "invisible": [39, -1], "attackbonus": [117, -1],
	"defendbonus": [42, -1]}
const SHIELD_FOR := {90: 4, 92: 5, 91: 6}           # ResistFire → FireShield, ResistShock → LightningShield, …

var main

func _init(game_main) -> void:
	main = game_main

func _combat():
	return main.combat

func is_actor(f: Dictionary) -> bool:
	return not f.is_empty() and String(f.get("kind", "")) in ["player", "npc", "creature"]

func is_npc(f: Dictionary) -> bool:
	return not f.is_empty() and String(f.get("kind", "")) in ["player", "npc"]

## Słownik stanu: gracz – postać, NPC/stworzenie – GameState.actors[sid].
func holder(f: Dictionary) -> Dictionary:
	if f.kind == "player":
		return main.player_stats()
	return _combat()._actor_state(f)

func _arr(h: Dictionary, path: Array, n: int) -> Array:
	var d: Dictionary = h
	for i in path.size() - 1:
		if not d.get(path[i]) is Dictionary:
			d[path[i]] = {}
		d = d[path[i]]
	var k = path[path.size() - 1]
	if not d.get(k) is Array or (d[k] as Array).size() != n:
		var z := []
		z.resize(n)
		z.fill(0.0)
		d[k] = z
	return d[k]

# --- atrybuty i umiejętności ------------------------------------------------------------------------------

func _kind_size(kind: String) -> int:
	return 8 if kind == "attributes" else 27

## Tablica wartości bazowych (zapisywalna): gracz – postać; NPC/stworzenie – kopia przy pierwszej zmianie.
func _base_array(f: Dictionary, kind: String) -> Array:
	var h := holder(f)
	if f.kind != "player" and not h.get(kind) is Array:
		var src: Array = _combat()._npc_stats(f).get(kind, [])
		var copy := []
		for i in _kind_size(kind):
			copy.append(float(src[i]) if i < src.size() else 0.0)
		h[kind] = copy
	return h[kind]

func base_value(f: Dictionary, kind: String, i: int) -> float:
	if f.kind == "creature" and kind == "skills":
		return float(_combat().skill(f, i))
	if f.kind == "player":
		var a: Array = main.player_stats().get(kind, [])
		return float(a[i]) if i < a.size() else 0.0
	var b: Array = _combat()._npc_stats(f).get(kind, [])
	return float(b[i]) if i < b.size() else 0.0

func modified_value(f: Dictionary, kind: String, i: int) -> float:
	if f.kind == "player":
		var d: Dictionary = main.character.derived(main.player_stats())
		return float(d[kind][i])
	if kind == "attributes":
		return float(_combat().attributes(f)[i])
	return float(_combat().skill(f, i))

## Efekt wzmocnienia (z czarów/zdolności/przedmiotów) bieżący – część modyfikatora poza korektą skryptów.
func _effect_mod(f: Dictionary, kind: String, i: int) -> float:
	var fx: Dictionary = main.character.constant_effects(main.player_stats()) if f.kind == "player" \
		else (main.magic.effects(f) if main.magic != null else {})
	var fid: int = 79 if kind == "attributes" else 83
	return float(fx.get("%d:%d" % [fid, i], 0.0))

## Set*: AttributeValue::setBase(v, true) – baza = v, modyfikator i ubytek wyzerowane (wzmocnienie z działającego
## czaru przestaje się liczyć; po jego wygaśnięciu OpenMW odejmuje je – stąd korekta = −efekt).
func set_base(f: Dictionary, kind: String, i: int, v: float) -> void:
	if not is_actor(f) or (kind == "skills" and not is_npc(f)):
		return
	var b := _base_array(f, kind)
	b[i] = v
	var h := holder(f)
	_arr(h, ["mod_adjust", kind], _kind_size(kind))[i] = -_effect_mod(f, kind, i)
	_arr(h, ["magic_damage", kind], _kind_size(kind))[i] = 0.0
	_after_attribute_change(f, kind, i)

## Mod*: modStat (statsextensions.cpp).
func mod_stat(f: Dictionary, kind: String, i: int, amount: float) -> void:
	if not is_actor(f) or (kind == "skills" and not is_npc(f)):
		return
	var b := _base_array(f, kind)
	var h := holder(f)
	var adj := _arr(h, ["mod_adjust", kind], _kind_size(kind))
	var dmg := _arr(h, ["magic_damage", kind], _kind_size(kind))
	var base := float(b[i])
	var fxm := _effect_mod(f, kind, i)
	var modifier := fxm + float(adj[i]) - float(dmg[i])
	var modified := base + modifier
	if (modifier <= 0.0 or base >= 100.0) and amount > 0.0:
		amount = clampf(100.0 - modified, 0.0, amount)
	var new_modified := modified + amount
	if new_modified < 0.0:
		if modified >= 0.0:
			new_modified = 0.0
		elif new_modified < modified:
			new_modified = modified
	var new_base := clampf(base + amount, 0.0, 100.0)
	b[i] = new_base
	var new_mod := new_modified - new_base
	# AttributeValue::setModifier: ujemny modyfikator staje się ubytkiem
	if new_mod < 0.0:
		dmg[i] = -new_mod
		adj[i] = -fxm
	else:
		dmg[i] = 0.0
		adj[i] = new_mod - fxm
	_after_attribute_change(f, kind, i)

## CreatureStats::setAttribute: zmiana inteligencji przelicza magię, siły/siły woli/zręczności/wytrzymałości –
## kondycję (z zachowaniem stosunku wartości bieżącej do maksymalnej) – tu przez magic.sync_dynamic.
func _after_attribute_change(f: Dictionary, kind: String, _i: int) -> void:
	if kind == "attributes" and main.magic != null:
		main.magic.sync_dynamic(f)

# --- zdrowie, magia, kondycja -----------------------------------------------------------------------------

func dyn_current(f: Dictionary, k: int) -> float:
	match k:
		0: return float(_combat().health(f))
		1: return float(main.magic.magicka(f))
	return float(_combat().fatigue(f))

func dyn_modified(f: Dictionary, k: int) -> float:
	match k:
		0: return float(_combat().max_health(f))
		1: return float(main.magic.max_magicka(f))
	return float(_combat().max_fatigue(f))

## Wzmocnienie stałe maksimum (Fortify Health/Magicka/Fatigue z efektów stałych) – modyfikator DynamicStat.
func _dyn_modifier(f: Dictionary, k: int) -> float:
	if f.kind != "player":
		return 0.0
	var d: Dictionary = main.character.derived(main.player_stats())
	var key: String = DYNAMICS[k]
	return float(d[key].modified) - float(d[key].base)

func dyn_base(f: Dictionary, k: int) -> float:
	return dyn_modified(f, k) - _dyn_modifier(f, k)

func _set_dyn_base(f: Dictionary, k: int, v: float) -> void:
	var h := holder(f)
	if k == 0:
		h["health_base"] = v
		return
	if not h.get("dyn_base") is Dictionary:
		h["dyn_base"] = {}
	var key: Array
	if f.kind == "player":
		key = main.character.derived(main.player_stats()).dyn_keys[DYNAMICS[k]]
	else:
		var at: Array = _combat().attributes(f)
		if k == 1:
			key = [at[1], main.magic._gmst("fNPCbaseMagickaMult", 2.0) + main.magic.magnitude_of(f, 84) * 0.1]
		else:
			key = [at[0], at[2], at[3], at[5]]
	h.dyn_base[DYNAMICS[k]] = [v, key]
	h["_max_" + DYNAMICS[k]] = v + _dyn_modifier(f, k)        # bez przeskalowania bieżącej (sync_dynamic)

func _write_current(f: Dictionary, k: int, v: float) -> void:
	var h := holder(f)
	h[DYNAMICS[k]] = v
	if k == 0 and v <= 0.0:
		_queue_death(f)

## DynamicStat::setCurrent(value, allowDecreaseBelowZero, allowIncreaseAboveModified).
func _set_current(f: Dictionary, k: int, value: float, below_zero: bool, above_modified: bool) -> void:
	var cur := dyn_current(f, k)
	var mx := dyn_modified(f, k)
	var v := cur
	if value > cur:
		if value <= mx or above_modified:
			v = value
		elif cur > mx:
			return
		else:
			v = mx
	elif value > 0.0 or below_zero:
		v = value
	elif cur > 0.0:
		v = 0.0
	_write_current(f, k, v)

## SetHealth/SetMagicka/SetFatigue: baza = v, bieżąca = zmodyfikowana (może przekroczyć maksimum).
func set_dynamic(f: Dictionary, k: int, v: float) -> void:
	if not is_actor(f):
		return
	_set_dyn_base(f, k, v)
	_set_current(f, k, dyn_modified(f, k), true, true)

## ModHealth/…: baza + d (zdrowie i magia nie poniżej 0), bieżąca + d (bez ograniczeń).
func mod_dynamic(f: Dictionary, k: int, d: float) -> void:
	if not is_actor(f):
		return
	var cur := dyn_current(f, k)
	var base := d + dyn_base(f, k)
	if k != 2:
		base = maxf(base, 0.0)
	_set_dyn_base(f, k, base)
	_set_current(f, k, d + cur, true, true)

## ModCurrentHealth/…: kondycja może zejść poniżej zera (powalenie przy ≤ 0).
func mod_current(f: Dictionary, k: int, d: float) -> void:
	if not is_actor(f):
		return
	var cur := dyn_current(f, k)
	var below := k == 2
	if k == 2 and d + cur <= 0.0 and f.kind != "player":
		holder(f)["knocked_down"] = true
	_set_current(f, k, d + cur, below, false)

## Get…GetRatio: bieżąca / zmodyfikowana (zmodyfikowana 0 → 1).
func ratio(f: Dictionary, k: int) -> float:
	if not is_actor(f):
		return 0.0
	var mx := dyn_modified(f, k)
	return 1.0 if mx == 0.0 else dyn_current(f, k) / mx

## GetHealth/GetMagicka/GetFatigue: bieżąca (magia nie mniejsza niż 0).
func get_dynamic(f: Dictionary, k: int) -> float:
	if not is_actor(f):
		return 0.0
	var v := dyn_current(f, k)
	return maxf(v, 0.0) if k == 1 else v

func _queue_death(f: Dictionary) -> void:
	if _combat().is_dead(f):
		return
	main.call_deferred("on_actor_died", f, {})

# --- efekty magiczne (GetResist*, SetWaterWalking…) -------------------------------------------------------

func _effects(f: Dictionary) -> Dictionary:
	return main.character.constant_effects(main.player_stats()) if f.kind == "player" else main.magic.effects(f)

func effect_value(f: Dictionary, name: String) -> int:
	if not is_actor(f) or not MAGIC_EFFECTS.has(name):
		return 0
	var pair: Array = MAGIC_EFFECTS[name]
	var fx := _effects(f)
	var v := float(fx.get(str(pair[0]), 0.0))
	if int(pair[1]) >= 0:
		v -= float(fx.get(str(pair[1]), 0.0))
	if SHIELD_FOR.has(int(pair[0])):
		v += float(fx.get(str(SHIELD_FOR[int(pair[0])]), 0.0))
	return int(v)

func _modify_effect_base(f: Dictionary, idx: int, d: float) -> void:
	var h := holder(f)
	if not h.get("effect_base") is Dictionary:
		h["effect_base"] = {}
	h.effect_base[str(idx)] = float(h.effect_base.get(str(idx), 0.0)) + d
	if main.magic != null:
		main.magic.sync_dynamic(f)

func set_effect(f: Dictionary, name: String, arg: int) -> void:
	if not is_actor(f) or not MAGIC_EFFECTS.has(name):
		return
	_modify_effect_base(f, int(MAGIC_EFFECTS[name][0]), float(arg - effect_value(f, name)))

func mod_effect(f: Dictionary, name: String, arg: int) -> void:
	if not is_actor(f) or not MAGIC_EFFECTS.has(name):
		return
	_modify_effect_base(f, int(MAGIC_EFFECTS[name][0]), float(arg))

# --- poziom ------------------------------------------------------------------------------------------------

func get_level(f: Dictionary) -> int:
	if not is_actor(f):
		return -1
	if f.kind == "player":
		return int(main.player_stats().get("level", 1))
	var h := holder(f)
	return int(h.get("level", f.rec.get("level", 1)))

func set_level(f: Dictionary, v: int) -> void:
	if not is_actor(f):
		return
	holder(f)["level"] = v

# --- wilkołak (MechanicsManager::setWerewolf, Player::saveStats/setWerewolfStats/restoreStats) -------------

## AttributeValue/SkillValue::setModifier(m): zmodyfikowana = baza + m (m obejmuje też efekty czarów).
func set_modifier(f: Dictionary, kind: String, i: int, m: float) -> void:
	var h := holder(f)
	_base_array(f, kind)
	_arr(h, ["mod_adjust", kind], _kind_size(kind))[i] = m - _effect_mod(f, kind, i)
	_after_attribute_change(f, kind, i)

## restore(getDamage()): ubytek (Damage*/Drain*) usunięty.
func clear_damage(f: Dictionary, kind: String, i: int) -> void:
	_arr(holder(f), ["magic_damage", kind], _kind_size(kind))[i] = 0.0

## setBase(getBase(), true): modyfikator i ubytek wyzerowane, baza bez zmian.
func reset_to_base(f: Dictionary, kind: String, i: int) -> void:
	set_base(f, kind, i, base_value(f, kind, i))

## CreatureStats::setHealth(v): baza i bieżąca = v.
func set_health_plain(f: Dictionary, v: float) -> void:
	_set_dyn_base(f, 0, v)
	_write_current(f, 0, v)

