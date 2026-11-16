extends RefCounted
## Postać gracza (etap 4): statystyki początkowe jak OpenMW (MechanicsManager::buildPlayer), wartości pochodne
## (NpcStats::updateHealth, CreatureStats::recalculateMagicka i zmęczenie), stałe efekty zdolności ras i znaków
## (wzmocnienia atrybutów, umiejętności, zdrowia, magii, kondycji, maksymalnej magii), obrażenia od upadku
## (character.cpp getFallDamage) i współczynnik zmęczenia (getFatigueTerm).
##
## Statystyki w GameState.player["character"]:
##   {"name","race","female","class","birthsign","head","hair","level",
##    "attributes": [8 wartości bazowych], "skills": [27 wartości bazowych], "spells": [id czarów],
##    "health","magicka","fatigue": wartości bieżące}
## Kolejność atrybutów i umiejętności jak w ESM (records/index.json).

const ATTR_STRENGTH := 0
const ATTR_INTELLIGENCE := 1
const ATTR_WILLPOWER := 2
const ATTR_AGILITY := 3
const ATTR_SPEED := 4
const ATTR_ENDURANCE := 5
const ATTR_PERSONALITY := 6
const ATTR_LUCK := 7
const SK_ACROBATICS := 20

# ESM::MagicEffect – stałe efekty, które zmieniają statystyki
const FX_FORTIFY_ATTRIBUTE := 79
const FX_FORTIFY_HEALTH := 80
const FX_FORTIFY_MAGICKA := 81
const FX_FORTIFY_FATIGUE := 82
const FX_FORTIFY_SKILL := 83
const FX_FORTIFY_MAX_MAGICKA := 84
const FX_JUMP := 9
# rodzaje czarów ze stałym efektem (zdolność, zaraza, choroba, klątwa) – zaklęcia i moce rzuca się (etap 7)
const CONSTANT_TYPES := [1, 2, 3, 4]

var records          # obiekt z record(file, id) i records_index()

func _init(records_source) -> void:
	records = records_source

func _gmst(id: String, def: float) -> float:
	var g: Dictionary = records.record("gmst", id)
	return float(g.get("value", def)) if not g.is_empty() else def

func skill_names() -> Array:
	return records.records_index().get("skills", [])

## Listy wyboru do kreatora: grywalne rasy, klasy, wszystkie znaki zodiaku, głowy i włosy rasy/płci.
func playable(file: String) -> Array:
	var out := []
	var all: Dictionary = records._all(file)
	for id in all:
		var r: Dictionary = all[id]
		if file == "birthsign" or bool(r.get("playable", false)):
			out.append(id)
	out.sort()
	return out

func heads_hairs(race: String, female: bool) -> Dictionary:
	var heads := []
	var hairs := []
	var all: Dictionary = records._all("bodypart")
	for id in all:
		var bp: Dictionary = all[id]
		if String(bp.get("race", "")).to_lower() != race.to_lower() or bool(bp.get("female", false)) != female:
			continue
		if not bool(bp.get("playable", true)) or bool(bp.get("vampire", false)) or int(bp.get("mesh_type", 0)) != 0:
			continue
		if int(bp.get("part", -1)) == 0:
			heads.append(id)
		elif int(bp.get("part", -1)) == 1:
			hairs.append(id)
	heads.sort()
	hairs.sort()
	return {"heads": heads, "hairs": hairs}

## buildPlayer: rasa (atrybuty wg płci, umiejętności 5 + premia, moce), znak (czary), klasa (+10 ulubionym atrybutom,
## +25 główne, +10 drugorzędne, +5 umiejętnościom specjalizacji). Wartości bieżące = maksymalne.
func build(choice: Dictionary) -> Dictionary:
	var player_rec: Dictionary = records.record("npc", "player")
	var race: Dictionary = records.record("race", String(choice.get("race", "")))
	var cls: Dictionary = records.record("class", String(choice.get("class", "")))
	var sign: Dictionary = records.record("birthsign", String(choice.get("birthsign", "")))
	var female := bool(choice.get("female", false))
	var attrs := []
	var skills := []
	var base_attrs: Array = player_rec.get("attributes", [])
	var base_skills: Array = player_rec.get("skills", [])
	for i in 8:
		attrs.append(float(base_attrs[i]) if i < base_attrs.size() else 0.0)
	for i in 27:
		skills.append(float(base_skills[i]) if i < base_skills.size() else 0.0)
	var spells := []
	if not race.is_empty():
		var ra: Array = (race.get("attributes", {}) as Dictionary).get("female" if female else "male", [])
		for i in mini(8, ra.size()):
			attrs[i] = float(ra[i])
		for i in 27:
			var bonus := 0
			for b in race.get("skill_bonuses", []):
				if int(b.get("skill", -1)) == i:
					bonus = int(b.get("bonus", 0))
					break
			skills[i] = 5.0 + bonus
		for p in race.get("powers", []):
			if not records.record("spell", String(p)).is_empty():
				spells.append(String(p).to_lower())
	for p in sign.get("spells", []):
		if not records.record("spell", String(p)).is_empty():
			spells.append(String(p).to_lower())
	if not cls.is_empty():
		for a in cls.get("attributes", []):
			if int(a) >= 0 and int(a) < 8:
				attrs[int(a)] += 10.0
		for sk in cls.get("minor_skills", []):
			if int(sk) >= 0 and int(sk) < 27:
				skills[int(sk)] += 10.0
		for sk in cls.get("major_skills", []):
			if int(sk) >= 0 and int(sk) < 27:
				skills[int(sk)] += 25.0
		var names := skill_names()
		var spec := int(cls.get("specialization", -1))
		for i in 27:
			var srec: Dictionary = records.record("skill", String(names[i]) if i < names.size() else "")
			if not srec.is_empty() and int(srec.get("specialization", -2)) == spec:
				skills[i] += 5.0
	var st := {"name": String(choice.get("name", "")), "race": String(choice.get("race", "")).to_lower(),
		"female": female, "class": String(choice.get("class", "")).to_lower(),
		"birthsign": String(choice.get("birthsign", "")).to_lower(),
		"head": String(choice.get("head", "")).to_lower(), "hair": String(choice.get("hair", "")).to_lower(),
		"level": maxi(1, int(player_rec.get("level", 1))), "attributes": attrs, "skills": skills, "spells": spells}
	var d := derived(st)
	st["health"] = d.health.modified
	st["magicka"] = d.magicka.modified
	st["fatigue"] = d.fatigue.modified
	return st

## Suma wielkości stałych efektów danego rodzaju (klucz: efekt, a dla atrybutów/umiejętności – indeks).
func constant_effects(st: Dictionary) -> Dictionary:
	var fx := {}
	for sid in st.get("spells", []):
		var sp: Dictionary = records.record("spell", String(sid))
		if sp.is_empty() or not int(sp.get("spell_type", 0)) in CONSTANT_TYPES:
			continue
		for e in sp.get("effects", []):
			var id := int(e.get("effect", -1))
			var key := str(id)
			if id == FX_FORTIFY_ATTRIBUTE:
				key = "%d:%d" % [id, int(e.get("attribute", -1))]
			elif id == FX_FORTIFY_SKILL:
				key = "%d:%d" % [id, int(e.get("skill", -1))]
			fx[key] = float(fx.get(key, 0.0)) + float(e.get("min", 0))
	return fx

## Wartości zmodyfikowane i pochodne: atrybuty i umiejętności ze wzmocnieniami, zdrowie (z bazowych siły
## i wytrzymałości), magia (inteligencja × (fPCbaseMagickaMult + 0,1 × wzmocnienie maks. magii)), kondycja
## (siła + siła woli + zręczność + wytrzymałość, zmodyfikowane).
func derived(st: Dictionary) -> Dictionary:
	var fx := constant_effects(st)
	var a: Array = st.get("attributes", [])
	var s: Array = st.get("skills", [])
	var am := []
	var sm := []
	for i in 8:
		am.append(maxf(0.0, float(a[i]) + float(fx.get("%d:%d" % [FX_FORTIFY_ATTRIBUTE, i], 0.0))))
	for i in 27:
		sm.append(maxf(0.0, float(s[i]) + float(fx.get("%d:%d" % [FX_FORTIFY_SKILL, i], 0.0))))
	var hb := floorf(0.5 * (float(a[ATTR_STRENGTH]) + float(a[ATTR_ENDURANCE])))
	var factor := _gmst("fpcbasemagickamult", 1.0) + float(fx.get(str(FX_FORTIFY_MAX_MAGICKA), 0.0)) * 0.1
	var mb: float = factor * float(am[ATTR_INTELLIGENCE])
	var fb: float = maxf(0.0, float(am[ATTR_STRENGTH]) + float(am[ATTR_WILLPOWER]) + float(am[ATTR_AGILITY]) + float(am[ATTR_ENDURANCE]))
	return {"attributes": am, "skills": sm,
		"health": {"base": hb, "modified": hb + float(fx.get(str(FX_FORTIFY_HEALTH), 0.0))},
		"magicka": {"base": mb, "modified": mb + float(fx.get(str(FX_FORTIFY_MAGICKA), 0.0))},
		"fatigue": {"base": fb, "modified": fb + float(fx.get(str(FX_FORTIFY_FATIGUE), 0.0))},
		"jump": float(fx.get(str(FX_JUMP), 0.0))}

## getFatigueTerm: fFatigueBase − fFatigueMult × (1 − bieżąca/maksymalna kondycja).
func fatigue_term(st: Dictionary, d: Dictionary) -> float:
	var mx: float = d.fatigue.modified
	var norm := 1.0 if floorf(mx) == 0.0 else maxf(0.0, float(st.get("fatigue", mx)) / mx)
	return _gmst("ffatiguebase", 1.25) - _gmst("ffatiguemult", 0.5) * (1.0 - norm)

## getFallDamage (wysokość w jednostkach MW): 0 poniżej fFallDamageDistanceMin; akrobatyka i Skok zmniejszają.
func fall_damage(st: Dictionary, d: Dictionary, height: float) -> float:
	var dmin := _gmst("ffalldamagedistancemin", 400.0)
	if height < dmin:
		return 0.0
	var acro: float = float(d.skills[SK_ACROBATICS])
	var x := maxf(0.0, height - dmin - (1.5 * acro + float(d.get("jump", 0.0))))
	var a := _gmst("ffallacrobase", 0.25) + _gmst("ffallacromult", 0.01) * (100.0 - acro)
	x = _gmst("ffalldistancebase", 0.0) + _gmst("ffalldistancemult", 0.07) * x
	return x * a

## Upadek: obrażenia × (1 − 0,25 × współczynnik zmęczenia), jak CharacterController (bez obrażeń w wodzie).
## Zwraca utracone zdrowie (i zmienia st["health"]).
func apply_fall(st: Dictionary, height: float) -> float:
	var d := derived(st)
	var lost := fall_damage(st, d, height)
	if lost <= 0.0:
		return 0.0
	var real := lost * (1.0 - 0.25 * fatigue_term(st, d))
	st["health"] = float(st.get("health", d.health.modified)) - real
	return real
