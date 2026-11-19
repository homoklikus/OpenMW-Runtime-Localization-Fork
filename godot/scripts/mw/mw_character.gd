extends RefCounted
## Postać gracza (etap 4): statystyki początkowe jak OpenMW (MechanicsManager::buildPlayer), wartości pochodne
## (NpcStats::updateHealth, CreatureStats::recalculateMagicka i zmęczenie), stałe efekty zdolności ras i znaków
## (wzmocnienia atrybutów, umiejętności, zdrowia, magii, kondycji, maksymalnej magii), obrażenia od upadku
## (character.cpp getFallDamage) i współczynnik zmęczenia (getFatigueTerm).
##
## Statystyki w GameState.player["character"]:
##   {"name","race","female","class","birthsign","head","hair","level",
##    "attributes": [8 wartości bazowych], "skills": [27 wartości bazowych], "spells": [id czarów],
##    "health","magicka","fatigue": wartości bieżące,
##    etap 7: "health_base" (zdrowie maksymalne po awansach), "skill_progress": [27 × 0..1], "level_progress",
##    "skill_increases": [8 – punkty atrybutów z podniesionych umiejętności], "spec_increases": [3]}
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
var magic = null     # MWMagic (etap 7d): efekty przedmiotów i działających czarów, ubytki atrybutów/umiejętności
# efekty z argumentem: atrybut (osłabienie, uszkodzenie, przywrócenie, wzmocnienie, pochłonięcie) i umiejętność
const ARG_ATTRIBUTE_EFFECTS := [17, 22, 74, 79, 85]
const ARG_SKILL_EFFECTS := [21, 26, 78, 83, 89]

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

## RaceDialog::getBodyParts: części grywalne (bez BPF_NotPlayable), typu „skóra”, danej części (głowa/włosy), płci
## i rasy, bez części pierwszoosobowych (id kończące się na „1st”); kolejność jak w magazynie rekordów OpenMW
## (kolejność wczytania), bez sortowania.
func heads_hairs(race: String, female: bool) -> Dictionary:
	var heads := []
	var hairs := []
	var all: Dictionary = records._all("bodypart")
	for id in all:
		var bp: Dictionary = all[id]
		if String(bp.get("race", "")).to_lower() != race.to_lower() or bool(bp.get("female", false)) != female:
			continue
		if not bool(bp.get("playable", true)) or int(bp.get("mesh_type", 0)) != 0 or String(id).to_lower().ends_with("1st"):
			continue
		if int(bp.get("part", -1)) == 0:
			heads.append(id)
		elif int(bp.get("part", -1)) == 1:
			hairs.append(id)
	return {"heads": heads, "hairs": hairs}

## Koszt czaru (calcSpellCost) – z modułu magii; bez niego koszt z rekordu.
func _spell_cost(sp: Dictionary) -> int:
	if magic != null:
		return magic.spell_cost(sp)
	return int(sp.get("cost", 0))

## calcWeakestSchool (autocalcspell.cpp): szkoła efektu o najmniejszej szansie (2 × umiejętność − koszt wg wzoru
## Morrowinda) → [skillTerm].
func _weakest_school_term(sp: Dictionary, skills: Array) -> float:
	var min_chance := INF
	var term := 0.0
	var mult := _gmst("feffectcostmult", 0.5)
	for e in sp.get("effects", []):
		var mg: Dictionary = records.record("magiceffect", str(int(e.get("effect", -1))))
		if mg.is_empty():
			continue
		var mn := 1
		var mx := 1
		if not bool(mg.get("no_magnitude", false)):
			mn = int(e.get("min", 0))
			mx = int(e.get("max", 0))
		var dur := 0
		if not bool(mg.get("no_duration", false)):
			dur = int(e.get("duration", 0))
		if not bool(mg.get("applied_once", false)):
			dur = maxi(1, dur)
		var base := float(mg.get("base_cost", 0.0))
		var x := 0.5 * (maxi(1, mn) + maxi(1, mx))
		x *= 0.1 * base
		x *= 1 + dur
		x += 0.05 * maxi(1, int(e.get("area", 0))) * base
		x *= mult
		if int(e.get("range", 0)) == 2:
			x *= 1.5
		var school := int(mg.get("school_skill", -1))
		var s := 2.0 * float(skills[school]) if school >= 0 and school < skills.size() else 0.0
		if s - x < min_chance:
			min_chance = s - x
			term = s
	return term

## calcAutoCastChance (bez wskazanej szkoły).
func _auto_cast_chance(sp: Dictionary, skills: Array, attrs: Array) -> float:
	if int(sp.get("spell_type", 0)) != 0 or bool(sp.get("always_succeeds", false)):
		return 100.0
	return _weakest_school_term(sp, skills) - _spell_cost(sp) + 0.2 * float(attrs[ATTR_WILLPOWER]) + 0.1 * float(attrs[ATTR_LUCK])

## attrSkillCheck: efekty na umiejętność/atrybut wymagają wartości bazowej ≥ iAutoSpellAttSkillMin.
func _attr_skill_check(sp: Dictionary, skills: Array, attrs: Array) -> bool:
	var need := _gmst("iautospellattskillmin", 70.0)
	for e in sp.get("effects", []):
		var mg: Dictionary = records.record("magiceffect", str(int(e.get("effect", -1))))
		if bool(mg.get("target_skill", false)):
			var k := int(e.get("skill", -1))
			if k < 0 or k >= skills.size() or float(skills[k]) < need:
				return false
		if bool(mg.get("target_attribute", false)):
			var a := int(e.get("attribute", -1))
			if a < 0 or a >= attrs.size() or float(attrs[a]) < need:
				return false
	return true

## autoCalcPlayerSpells (autocalcspell.cpp): czary początkowe gracza – zaklęcia z flagą PCStart (kolejność rekordów),
## bez mocy rasy, na które starcza magii bazowej (fPCbaseMagickaMult × inteligencja), z szansą ≥ fAutoPCSpellChance
## i spełnionym attrSkillCheck; najwyżej iAutoPCSpellMax – po osiągnięciu limitu nowy czar wypiera najsłabszy.
func auto_player_spells(attrs: Array, skills: Array, race: Dictionary) -> Array:
	var base_magicka := _gmst("fpcbasemagickamult", 1.0) * float(attrs[ATTR_INTELLIGENCE])
	var chance_min := _gmst("fautopcspellchance", 80.0)
	var max_count := int(_gmst("iautopcspellmax", 100.0))
	var powers: Array = (race.get("powers", []) as Array).map(func(x): return String(x).to_lower())
	var reached := false
	var weakest := ""
	var min_cost := 1 << 30
	var out := []
	var all: Dictionary = records._all("spell")
	for id in all:
		var sp: Dictionary = all[id]
		if int(sp.get("spell_type", 0)) != 0 or not bool(sp.get("pc_start", false)):
			continue
		var cost := _spell_cost(sp)
		if reached and cost <= min_cost:
			continue
		if String(id).to_lower() in powers:
			continue
		if base_magicka < cost:
			continue
		if _auto_cast_chance(sp, skills, attrs) < chance_min:
			continue
		if not _attr_skill_check(sp, skills, attrs):
			continue
		out.append(String(id).to_lower())
		if reached:
			out.erase(weakest)
			min_cost = 1 << 30
			for t in out:
				var tc := _spell_cost(records.record("spell", t))
				if tc < min_cost:
					min_cost = tc
					weakest = t
		else:
			if cost < min_cost:
				weakest = String(id).to_lower()
				min_cost = cost
			if out.size() == max_count:
				reached = true
	return out

## buildPlayer: rasa (atrybuty wg płci, umiejętności 5 + premia, moce), znak (czary), klasa (+10 ulubionym atrybutom,
## +25 główne, +10 drugorzędne, +5 umiejętnościom specjalizacji). Wartości bieżące = maksymalne.
## Postać gracza z rekordu „player” na starcie nowej gry (Npc::getNpcData, rekord bez autocalc): atrybuty,
## umiejętności i poziom z NPDT, zdrowie/magia/kondycja z NPDT (do pierwszego przeliczenia), czary rekordu
## i moce rasy z rekordu. Rasa i klasa nie są jeszcze naliczone – robi to dopiero buildPlayer (build()) po
## wyborze w kreatorze (MechanicsManager::setPlayerRace/Class/Birthsign).
func build_record(choice: Dictionary) -> Dictionary:
	var player_rec: Dictionary = records.record("npc", "player")
	var attrs := []
	var skills := []
	var base_attrs: Array = player_rec.get("attributes", [])
	var base_skills: Array = player_rec.get("skills", [])
	for i in 8:
		attrs.append(float(base_attrs[i]) if i < base_attrs.size() else 0.0)
	for i in 27:
		skills.append(float(base_skills[i]) if i < base_skills.size() else 0.0)
	var spells := []
	for sp in player_rec.get("spells", []):
		var sid := String(sp).to_lower()
		if not records.record("spell", sid).is_empty() and not sid in spells:
			spells.append(sid)
	var race: Dictionary = records.record("race", String(player_rec.get("race", "")))
	for p in race.get("powers", []):
		var pid := String(p).to_lower()
		if not records.record("spell", pid).is_empty() and not pid in spells:
			spells.append(pid)
	var st := {"name": String(choice.get("name", "")), "race": String(choice.get("race", "")).to_lower(),
		"female": bool(choice.get("female", false)), "class": String(choice.get("class", "")).to_lower(),
		"birthsign": "", "head": String(choice.get("head", "")).to_lower(), "hair": String(choice.get("hair", "")).to_lower(),
		"level": maxi(1, int(player_rec.get("level", 1))), "attributes": attrs, "skills": skills, "spells": spells,
		"race_selected": false, "class_selected": false}
	if player_rec.has("health"):
		st["health_base"] = float(player_rec.health)
	var keys: Dictionary = derived(st).dyn_keys
	st["dyn_base"] = {}
	for k in ["magicka", "fatigue"]:
		if player_rec.has(k):
			st.dyn_base[k] = [float(player_rec[k]), keys[k]]
	var d := derived(st)
	st["health"] = d.health.modified
	st["magicka"] = d.magicka.modified
	st["fatigue"] = d.fatigue.modified
	return st

## MechanicsManager::buildPlayer: od wartości rekordu, rasa tylko gdy wybrana (mRaceSelected), klasa tylko gdy
## wybrana (mClassSelected), znak gdy ustawiony; zdrowie updateHealth, magia/kondycja z atrybutów.
func build(choice: Dictionary, flags := {"race": true, "class": true}) -> Dictionary:
	var player_rec: Dictionary = records.record("npc", "player")
	var race: Dictionary = records.record("race", String(choice.get("race", ""))) if bool(flags.get("race", true)) else {}
	var cls: Dictionary = records.record("class", String(choice.get("class", ""))) if bool(flags.get("class", true)) else {}
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
	# czary początkowe gracza (F_PCStart) według statystyk bazowych po rasie, znaku i klasie
	for sid in auto_player_spells(attrs, skills, race):
		if not sid in spells:
			spells.append(sid)
	var st := {"name": String(choice.get("name", "")), "race": String(choice.get("race", "")).to_lower(),
		"female": female, "class": String(choice.get("class", "")).to_lower(),
		"birthsign": String(choice.get("birthsign", "")).to_lower(),
		"head": String(choice.get("head", "")).to_lower(), "hair": String(choice.get("hair", "")).to_lower(),
		"level": maxi(1, int(player_rec.get("level", 1))), "attributes": attrs, "skills": skills, "spells": spells,
		"race_selected": bool(flags.get("race", true)), "class_selected": bool(flags.get("class", true))}
	var d := derived(st)
	st["health"] = d.health.modified
	st["magicka"] = d.magicka.modified
	st["fatigue"] = d.fatigue.modified
	return st

## Suma wielkości efektów danego rodzaju (klucz: efekt; dla efektów na atrybut/umiejętność także „efekt:indeks”):
## zdolności i inne czary stałe z listy postaci, a z modułem magii (etap 7) – stałe zaklęcia założonych przedmiotów
## i działające czary (MagicEffects w OpenMW).
func constant_effects(st: Dictionary) -> Dictionary:
	var fx := {}
	for sid in st.get("spells", []):
		var sp: Dictionary = records.record("spell", String(sid))
		if sp.is_empty() or not int(sp.get("spell_type", 0)) in CONSTANT_TYPES:
			continue
		if magic != null and magic.spell_store_cured(st, String(sid)):
			continue
		var ei := 0
		for e in sp.get("effects", []):
			add_effect(fx, e, magic.spell_store_magnitude(st, String(sid), ei, e) if magic != null else float(e.get("min", 0)))
			ei += 1
	if magic != null:
		magic.add_extra_effects(st, fx)
	return fx

## Dopisuje wielkość efektu do mapy efektów (klucz efektu i „efekt:atrybut/umiejętność”).
static func add_effect(fx: Dictionary, e: Dictionary, m: float) -> void:
	var id := int(e.get("effect", -1))
	fx[str(id)] = float(fx.get(str(id), 0.0)) + m
	var arg := -1
	if id in ARG_ATTRIBUTE_EFFECTS:
		arg = int(e.get("attribute", -1))
	elif id in ARG_SKILL_EFFECTS:
		arg = int(e.get("skill", -1))
	if arg >= 0:
		var k := "%d:%d" % [id, arg]
		fx[k] = float(fx.get(k, 0.0)) + m

## Wartości zmodyfikowane i pochodne: atrybuty i umiejętności ze wzmocnieniami, zdrowie (z bazowych siły
## i wytrzymałości), magia (inteligencja × (fPCbaseMagickaMult + 0,1 × wzmocnienie maks. magii)), kondycja
## (siła + siła woli + zręczność + wytrzymałość, zmodyfikowane).
func derived(st: Dictionary) -> Dictionary:
	var fx := constant_effects(st)
	var a: Array = st.get("attributes", [])
	var s: Array = st.get("skills", [])
	var am := []
	var sm := []
	var dmg: Dictionary = st.get("magic_damage", {})       # ubytki (Damage/Drain – AttributeValue::damage)
	var da: Array = dmg.get("attributes", [])
	var ds: Array = dmg.get("skills", [])
	# korekta modyfikatora ze skryptów (Set*/Mod* atrybutu: AttributeValue::setBase(v, true) zeruje modyfikator)
	var adj: Dictionary = st.get("mod_adjust", {})
	var aa: Array = adj.get("attributes", [])
	var sa: Array = adj.get("skills", [])
	for i in 8:
		am.append(maxf(0.0, float(a[i]) + float(fx.get("%d:%d" % [FX_FORTIFY_ATTRIBUTE, i], 0.0))
			+ (float(aa[i]) if i < aa.size() else 0.0) - (float(da[i]) if i < da.size() else 0.0)))
	for i in 27:
		sm.append(maxf(0.0, float(s[i]) + float(fx.get("%d:%d" % [FX_FORTIFY_SKILL, i], 0.0))
			+ (float(sa[i]) if i < sa.size() else 0.0) - (float(ds[i]) if i < ds.size() else 0.0)))
	# zdrowie bazowe: przy tworzeniu ⌊(siła + wytrzymałość)/2⌋ (updateHealth), potem rośnie przy awansie
	var hb := float(st["health_base"]) if st.has("health_base") else floorf(0.5 * (float(a[ATTR_STRENGTH]) + float(a[ATTR_ENDURANCE])))
	var factor := _gmst("fpcbasemagickamult", 1.0) + float(fx.get(str(FX_FORTIFY_MAX_MAGICKA), 0.0)) * 0.1
	var mb: float = dyn_base_override(st, "magicka", [am[ATTR_INTELLIGENCE], factor], factor * float(am[ATTR_INTELLIGENCE]))
	var fb: float = dyn_base_override(st, "fatigue", [am[ATTR_STRENGTH], am[ATTR_WILLPOWER], am[ATTR_AGILITY], am[ATTR_ENDURANCE]],
		maxf(0.0, float(am[ATTR_STRENGTH]) + float(am[ATTR_WILLPOWER]) + float(am[ATTR_AGILITY]) + float(am[ATTR_ENDURANCE])))
	return {"attributes": am, "skills": sm,
		"health": {"base": hb, "modified": hb + float(fx.get(str(FX_FORTIFY_HEALTH), 0.0)) - float(fx.get("_tmp80", 0.0))},
		"magicka": {"base": mb, "modified": mb + float(fx.get(str(FX_FORTIFY_MAGICKA), 0.0)) - float(fx.get("_tmp81", 0.0))},
		"fatigue": {"base": fb, "modified": fb + float(fx.get(str(FX_FORTIFY_FATIGUE), 0.0)) - float(fx.get("_tmp82", 0.0))},
		"jump": float(fx.get(str(FX_JUMP), 0.0)),
		"dyn_keys": {"magicka": [am[ATTR_INTELLIGENCE], factor],
			"fatigue": [am[ATTR_STRENGTH], am[ATTR_WILLPOWER], am[ATTR_AGILITY], am[ATTR_ENDURANCE]]}}

## Wartość bazowa magii/kondycji ustawiona skryptem (SetMagicka/ModFatigue…): obowiązuje, dopóki nie zmienią się
## dane, z których OpenMW ją przelicza (CreatureStats::setAttribute – inteligencja/wzmocnienie maks. magii dla
## magii, siła + siła woli + zręczność + wytrzymałość dla kondycji); potem wraca wzór.
static func dyn_base_override(holder: Dictionary, kind: String, key: Array, formula: float) -> float:
	var o: Dictionary = holder.get("dyn_base", {})
	if not o.has(kind):
		return formula
	var e: Array = o[kind]
	if e.size() >= 2 and str(e[1]) == str(key):
		return float(e[0])
	o.erase(kind)
	return formula

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


# --- rozwój umiejętności i awans (etap 7; OpenMW: files/data-mw/scripts/omw/playerskillhandlers.lua,
# NpcStats::levelUp, LevelupDialog, Actors::restoreDynamicStats) -----------------------------------------------

const SKILL_USE := {"armor_hit": 0, "block": 0, "spellcast": 0, "weapon_hit": 0, "alchemy_create": 0,
	"alchemy_use": 1, "enchant_recharge": 0, "enchant_use": 1, "enchant_create": 2, "enchant_strike": 3,
	"acrobatics_jump": 0, "acrobatics_fall": 1, "mercantile_success": 0, "mercantile_bribe": 1,
	"security_trap": 0, "security_lock": 1, "sneak_avoid": 0, "sneak_pickpocket": 1, "speechcraft_success": 0,
	"speechcraft_fail": 1, "armorer_repair": 0, "athletics_run": 0, "athletics_swim": 1}

func _class_of(st: Dictionary) -> Dictionary:
	return records.record("class", String(st.get("class", "")))

static func _has(arr: Array, i: int) -> bool:
	return i in arr or float(i) in arr

func _ensure_progress(st: Dictionary) -> void:
	if not st.get("skill_progress") is Array or (st.skill_progress as Array).size() != 27:
		var z := []
		z.resize(27)
		z.fill(0.0)
		st["skill_progress"] = z
	if not st.get("skill_increases") is Array or (st.skill_increases as Array).size() != 8:
		st["skill_increases"] = [0, 0, 0, 0, 0, 0, 0, 0]
	if not st.get("spec_increases") is Array or (st.spec_increases as Array).size() != 3:
		st["spec_increases"] = [0, 0, 0]
	if not st.has("level_progress"):
		st["level_progress"] = 0
	if not st.has("health_base"):
		var a: Array = st.get("attributes", [])
		st["health_base"] = floorf(0.5 * (float(a[ATTR_STRENGTH]) + float(a[ATTR_ENDURANCE]))) if a.size() >= 8 else 0.0

## getSkillProgressRequirement: (wartość bazowa + 1) × współczynnik (główna/drugorzędna/inna) × specjalizacja.
func skill_requirement(st: Dictionary, i: int) -> float:
	var cls := _class_of(st)
	var f := _gmst("fmiscskillbonus", 1.25)
	if _has(cls.get("major_skills", []), i):
		f = _gmst("fmajorskillbonus", 0.75)
	elif _has(cls.get("minor_skills", []), i):
		f = _gmst("fminorskillbonus", 1.0)
	var sk: Dictionary = records.record("skill", String(skill_names()[i]) if i < skill_names().size() else "")
	if not sk.is_empty() and not cls.is_empty() and int(sk.get("specialization", -1)) == int(cls.get("specialization", -2)):
		f *= _gmst("fspecialskillbonus", 0.8)
	return (float(st.skills[i]) + 1.0) * f

## skillUsed: postęp += przyrost z rekordu SKIL (use_values[typ]) × skala / wymaganie; ≥ 1 → umiejętność +1.
## Zwraca komunikaty (podniesienie umiejętności, gotowość do awansu).
func use_skill(st: Dictionary, i: int, use_type: int, scale := 1.0) -> Array:
	if st.is_empty() or i < 0 or i >= 27:
		return []
	_ensure_progress(st)
	var sk: Dictionary = records.record("skill", String(skill_names()[i]) if i < skill_names().size() else "")
	var uv: Array = sk.get("use_values", [])
	if use_type < 0 or use_type > 3 or use_type >= uv.size():
		return []
	var gain := float(uv[use_type]) * scale
	var base := float(st.skills[i])
	if (base >= 100.0 and gain > 0.0) or (base <= 0.0 and gain < 0.0):
		return []
	st.skill_progress[i] = float(st.skill_progress[i]) + gain / skill_requirement(st, i)
	if float(st.skill_progress[i]) >= 1.0:
		return skill_level_up(st, i, "usage")
	return []

## skillLevelUp (domyślna obsługa Morrowinda): +1 (więzienie: −1 poza skradaniem i bezpieczeństwem),
## postęp awansu (iLevelUpMajorMult/MinorMult), punkty atrybutu umiejętności i specjalizacji.
func skill_level_up(st: Dictionary, i: int, source := "usage") -> Array:
	_ensure_progress(st)
	var names := skill_names()
	var sid := String(names[i]) if i < names.size() else ""
	var sk: Dictionary = records.record("skill", sid)
	var cls := _class_of(st)
	var inc := 1
	var lvl := 0
	var attr_inc := int(_gmst("ilevelupmiscmultattriubte", 1))
	if _has(cls.get("minor_skills", []), i):
		lvl = int(_gmst("ilevelupminormult", 1))
		attr_inc = int(_gmst("ilevelupminormultattribute", 1))
	elif _has(cls.get("major_skills", []), i):
		lvl = int(_gmst("ilevelupmajormult", 1))
		attr_inc = int(_gmst("ilevelupmajormultattribute", 1))
	var jail := source == "jail" and not sid in ["security", "sneak"]
	if jail:
		inc = -1
	var base := float(st.skills[i])
	if (base >= 100.0 and inc > 0) or (base <= 0.0 and inc < 0):
		return []
	st.skills[i] = base + inc
	var msgs := []
	if not jail:
		st.level_progress = int(st.level_progress) + lvl
		var ai := int(sk.get("attribute", -1))
		if ai >= 0 and ai < 8:
			st.skill_increases[ai] = int(st.skill_increases[ai]) + attr_inc
		var sp := int(sk.get("specialization", -1))
		if sp >= 0 and sp < 3:
			st.spec_increases[sp] = int(st.spec_increases[sp]) + int(_gmst("ilevelupspecialization", 1))
	if source != "jail":
		msgs.append({"kind": "skill", "skill": i, "level": int(st.skills[i])})
		if int(st.level_progress) >= int(_gmst("iLevelUpTotal".to_lower(), 10)):
			msgs.append({"kind": "levelup_ready"})
		if source == "usage":
			st.skill_progress[i] = 0.0
	return msgs

func can_level_up(st: Dictionary) -> bool:
	_ensure_progress(st)
	return int(st.level_progress) >= int(_gmst("ilevelupTotal".to_lower(), 10))

## getLevelupAttributeMultiplier: iLevelUp01Mult…iLevelUp10Mult wg punktów atrybutu (0 → ×1).
func levelup_multiplier(st: Dictionary, attr: int) -> int:
	_ensure_progress(st)
	var n := clampi(int(st.skill_increases[attr]), 0, 10)
	if n == 0:
		return 1
	var g: Dictionary = records.record("gmst", "ilevelup%02dmult" % n)
	return int(g.get("value", 1)) if not g.is_empty() else 1

## Liczba atrybutów do wyboru (3, mniej gdy atrybuty mają już 100).
func levelup_coins(st: Dictionary) -> int:
	var n := 0
	for i in 8:
		if float(st.attributes[i]) < 100.0:
			n += 1
	return mini(3, n)

## LevelupDialog::onOkButtonClicked + NpcStats::levelUp: wybrane atrybuty += mnożnik (do 100), postęp −
## iLevelUpTotal, zdrowie bazowe i bieżące + wytrzymałość × fLevelUpHealthEndMult, poziom +1.
func level_up(st: Dictionary, chosen: Array) -> bool:
	_ensure_progress(st)
	if chosen.size() != levelup_coins(st):
		return false
	for a in chosen:
		var ai := int(a)
		st.attributes[ai] = minf(100.0, float(st.attributes[ai]) + levelup_multiplier(st, ai))
	st.level_progress = maxi(0, int(st.level_progress) - int(_gmst("ilevelupTotal".to_lower(), 10)))
	st.skill_increases = [0, 0, 0, 0, 0, 0, 0, 0]
	var gain := float(st.attributes[ATTR_ENDURANCE]) * _gmst("flevelupHealthEndMult".to_lower(), 0.1)
	st.health_base = float(st.health_base) + gain
	st.health = maxf(1.0, float(st.get("health", 0.0)) + gain)
	st.level = int(st.get("level", 1)) + 1
	return true

## restoreDynamicStats (godzina odpoczynku/czekania): sen – zdrowie 0,1 × wytrzymałość, magia fRestMagicMult ×
## inteligencja; zawsze kondycja (fFatigueReturnBase + fFatigueReturnMult × (1 − obciążenie)) × fEndFatigueMult ×
## wytrzymałość × 3600. Wartości nie przekraczają maksimum.
func rest_hour(st: Dictionary, sleep: bool, encumbrance := 0.0) -> void:
	var d := derived(st)
	if sleep:
		st.health = minf(float(d.health.modified), float(st.get("health", 0.0)) + 0.1 * float(d.attributes[ATTR_ENDURANCE]))
		# Actors::restoreDynamicStats: Osłabiona magia – bez odnowy magii (stałe źródło) albo tylko za część
		# godziny po wygaśnięciu (pozostały czas × skala czasu / 3600)
		var hours := 1.0
		if magic != null and magic.main != null:
			var rem: float = magic.stunted_magicka_remaining(magic._combat().player_fighter())
			if rem == -1.0:
				hours = 0.0
			elif rem > 0.0:
				var ts: float = float(magic.main.envr.TIMESCALE) if magic.main.envr != null else 30.0
				hours = maxf(0.0, 1.0 - rem * (ts if ts != 0.0 else 1.0) / 3600.0)
		if hours > 0.0:
			st.magicka = minf(float(d.magicka.modified), float(st.get("magicka", 0.0)) + _gmst("frestmagicmult", 0.15) * float(d.attributes[ATTR_INTELLIGENCE]) * hours)
	var fat := float(st.get("fatigue", 0.0))
	if fat >= float(d.fatigue.base):
		return
	var x := (_gmst("ffatiguereturnbase", 2.5) + _gmst("ffatiguereturnmult", 0.02) * (1.0 - minf(1.0, encumbrance))) \
		* (_gmst("fendfatiguemult", 0.04) * float(d.attributes[ATTR_ENDURANCE]))
	st.fatigue = minf(float(d.fatigue.modified), fat + 3600.0 * x)

## Odnawianie kondycji w czasie gry (Actors::calculateRestoration): (fFatigueReturnBase + fFatigueReturnMult ×
## wytrzymałość) × czas (sekundy).
func restore_fatigue(st: Dictionary, seconds: float) -> void:
	var d := derived(st)
	var fat := float(st.get("fatigue", 0.0))
	if fat >= float(d.fatigue.base):
		return
	var x := _gmst("ffatiguereturnbase", 2.5) + _gmst("ffatiguereturnmult", 0.02) * float(d.attributes[ATTR_ENDURANCE])
	st.fatigue = minf(float(d.fatigue.modified), fat + seconds * x)

# --- ruch (Npc::getWalkSpeed/getRunSpeed/getJump, getSwimSpeedImpl, character.cpp – zmęczenie) -------------

const SK_ATHLETICS := 8
const FX_SWIFT_SWIM := 1

func capacity(st: Dictionary) -> float:
	return float(derived(st).attributes[ATTR_STRENGTH]) * _gmst("fencumbrancestrmult", 5.0)

func normalized_encumbrance(st: Dictionary, weight: float) -> float:
	if weight == 0.0:
		return 0.0
	var c := capacity(st)
	return weight / c if c > 0.0 else INF

## Prędkości w jednostkach MW/s i prędkość skoku (pionowa, jednostki/s).
func movement(st: Dictionary, weight := 0.0, running := false) -> Dictionary:
	var d := derived(st)
	var enc := normalized_encumbrance(st, weight)
	var walk := _gmst("fminwalkspeed", 100.0) + 0.01 * float(d.attributes[ATTR_SPEED]) \
		* (_gmst("fmaxwalkspeed", 200.0) - _gmst("fminwalkspeed", 100.0))
	walk = maxf(0.0, walk * (1.0 - _gmst("fencumberedmoveeffect", 0.3) * enc))
	var athl := float(d.skills[SK_ATHLETICS])
	var run := walk * (0.01 * athl * _gmst("fathleticsrunbonus", 1.0) + _gmst("fbaserunmultiplier", 1.75))
	var fx := constant_effects(st)
	var swim_base := run if running else walk
	var swim := swim_base * (1.0 + 0.01 * float(fx.get(str(FX_SWIFT_SWIM), 0.0))) \
		* (_gmst("fswimrunbase", 0.5) + 0.01 * athl * _gmst("fswimrunathleticsmult", 0.1))
	var jump := 0.0
	if enc <= 1.0:
		var et := _gmst("fjumpencumbrancebase", 0.0) + _gmst("fjumpencumbrancemultiplier", 1.0) * (1.0 - enc)
		var a := float(d.skills[SK_ACROBATICS])
		var b := 0.0
		if a > 50.0:
			b = a - 50.0
			a = 50.0
		var x := _gmst("fjumpacrobaticsbase", 128.0) + pow(a / 15.0, _gmst("fjumpacromultiplier", 4.0))
		x += 3.0 * b * _gmst("fjumpacromultiplier", 4.0)
		x += float(d.get("jump", 0.0)) * 64.0
		x *= et
		if running:
			x *= _gmst("fjumprunmultiplier", 1.0)
		x *= fatigue_term(st, d)
		x -= -GRAVITY_UNITS
		x /= 3.0
		jump = x
	if enc > 1.0:                              # Npc::getMaxSpeed: przeciążony stoi (chód, bieg, pływanie)
		walk = 0.0
		run = 0.0
		swim = 0.0
	var air := minf(1.0, _gmst("fjumpmovebase", 0.5) + _gmst("fjumpmovemult", 0.5) * float(d.skills[SK_ACROBATICS]) / 100.0)
	return {"walk": walk, "run": run, "swim": swim, "jump": jump, "air_factor": air, "encumbrance": enc,
		"overburdened": enc > 1.0}

const GRAVITY_UNITS := 9.8 * 64.0          # Constants::GravityUnits (jardy jako metry – jak w Morrowindzie)
const MAX_FALL_SPEED := 4005.5

## Utrata kondycji za ruch w ciągu dt (character.cpp): bieg, pływanie (chód/bieg), skradanie; przy przeciążeniu – 0.
func movement_fatigue(st: Dictionary, weight: float, dt: float, running: bool, swimming: bool, sneaking := false) -> float:
	if weight > capacity(st):
		return 0.0
	var enc := normalized_encumbrance(st, weight)
	var loss := 0.0
	if sneaking:
		loss = _gmst("ffatiguesneakbase", 1.5) + enc * _gmst("ffatiguesneakmult", 1.5)
	elif swimming:
		loss = (_gmst("ffatigueswimrunbase", 7.0) + enc * _gmst("ffatigueswimrunmult", 7.0)) if running \
			else (_gmst("ffatigueswimwalkbase", 2.5) + enc * _gmst("ffatigueswimwalkmult", 2.5))
	elif running:
		loss = _gmst("ffatiguerunbase", 5.0) + enc * _gmst("ffatiguerunmult", 2.0)
	return loss * dt

func jump_fatigue(st: Dictionary, weight: float) -> float:
	var enc := minf(1.0, normalized_encumbrance(st, weight))
	return _gmst("ffatiguejumpbase", 5.0) + enc * _gmst("ffatiguejumpmult", 5.0)
