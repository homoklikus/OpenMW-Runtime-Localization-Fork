extends RefCounted
## Magia (etap 7) – wzory OpenMW 0.51 (apps/openmw/mwmechanics/spellutil.cpp): koszt efektu (calcEffectCost),
## koszt zaklęcia (calcSpellCost, autoobliczanie), koszt i ładunek zaklęć przedmiotów, efekty z rekordów MGEF
## (world/records/magiceffect.json, klucz = indeks efektu).

const RT_SELF := 0
const RT_TOUCH := 1
const RT_TARGET := 2
const COST_GAME_SPELL := 0
const COST_PLAYER_SPELL := 1
const COST_GAME_ENCHANTMENT := 2
const COST_PLAYER_ENCHANTMENT := 3
const COST_GAME_POTION := 4

var records

func _init(records_source) -> void:
	records = records_source

func _gmst(id: String, def: float) -> float:
	var g: Dictionary = records.record("gmst", id.to_lower())
	return float(g.get("value", def)) if not g.is_empty() else def

func effect(index: int) -> Dictionary:
	return records.record("magiceffect", str(index))

## calcEffectCost: (min+max)/2 × 0,1 × koszt bazowy × (czas [+1 dla czarów gracza]) + 0,05 × obszar × koszt;
## × fEffectCostMult (mikstury: iAlchemyMod).
func effect_cost(e: Dictionary, method := COST_GAME_SPELL) -> float:
	var mg := effect(int(e.get("effect", -1)))
	if mg.is_empty():
		return 0.0
	var has_mag := not bool(mg.get("no_magnitude", false))
	var has_dur := not bool(mg.get("no_duration", false))
	var once := bool(mg.get("applied_once", false))
	var mn := int(e.get("min", 0)) if has_mag else 1
	var mx := int(e.get("max", 0)) if has_mag else 1
	if method == COST_PLAYER_SPELL or method == COST_GAME_SPELL:
		mn = maxi(1, mn)
		mx = maxi(1, mx)
	var dur := int(e.get("duration", 0)) if has_dur else 1
	if not once:
		dur = maxi(1, dur)
	var dur_off := 0
	var min_area := 0
	var mult := _gmst("fEffectCostMult", 0.5)
	if method == COST_PLAYER_SPELL:
		dur_off = 1
		min_area = 1
	elif method == COST_GAME_POTION:
		min_area = 1
		mult = _gmst("iAlchemyMod", 2.0)
	var base := float(mg.get("base_cost", 0.0))
	var x := 0.5 * (mn + mx)
	x *= 0.1 * base
	x *= dur_off + dur
	x += 0.05 * maxi(min_area, int(e.get("area", 0))) * base
	return x * mult

## getTotalCost: suma kosztów efektów (zasięg „cel” × 1,5).
func total_cost(effects: Array, method := COST_GAME_SPELL) -> float:
	var c := 0.0
	for e in effects:
		var ec := maxf(0.0, effect_cost(e, method))
		if int(e.get("range", 0)) == RT_TARGET:
			ec *= 1.5
		c += ec
	return c

## calcSpellCost: koszt z rekordu albo autoobliczony (zaokrąglenie).
func spell_cost(sp: Dictionary) -> int:
	if not bool(sp.get("autocalc", false)):
		return int(sp.get("cost", 0))
	return int(roundf(total_cost(sp.get("effects", []))))
