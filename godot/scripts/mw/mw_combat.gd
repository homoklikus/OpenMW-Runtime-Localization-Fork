extends RefCounted
## Walka (etap 7) – wzory OpenMW 0.51: apps/openmw/mwmechanics/combat.cpp (getHitChance, blockMeleeAttack,
## adjustWeaponDamage, reduceWeaponCondition, resistNormalWeapon, getHandToHandDamage, applyFatigueLoss,
## getMeleeWeaponReach, projectileHit), mwclass/npc.cpp i creature.cpp (hit, onHit), CreatureStats::getEvasion,
## files/data-mw/scripts/omw/combat (pancerz: getArmorRating, adjustDamageForArmor, pickRandomArmor, zużycie
## pancerza, postęp umiejętności pancerza, powalenie – applyStagger, trudność).
##
## „Walczący” (fighter) to słownik: {"kind": "player"|"npc"|"creature", "sid", "base", "rec", "node"}.
## Stan aktorów (zdrowie, kondycja, magia bieżące, śmierć) – GameState.actors[sid]; gracz – state.player.character.
## Ekwipunek gracza: character.equipment {slot: {"id", "health"}} (stan przedmiotu; -1 = pełny).

const EQ := preload("res://scripts/mw/mw_equipment.gd")
const A_STRENGTH := 0
const A_AGILITY := 3
const A_ENDURANCE := 5
const A_LUCK := 7
const SK_BLOCK := 0
const SK_HAND := 26
const SK_UNARMORED := 17
const SK_MARKSMAN := 23
const SPEC_OF_SKILL_DEFAULT := 0
const FX_SHIELD := 3
const FX_SANCTUARY := 42
const FX_RESIST_NORMAL := 98
const FX_WEAK_NORMAL := 36
const FX_FORTIFY_ATTACK := 117
const FX_BLIND := 47
const FX_CHAMELEON := 40
const FX_INVISIBILITY := 39
const FX_PARALYZE := 45
# miejsca pancerza i wagi do oceny (getArmorRating)
const ARMOR_WEIGHTS := {EQ.SLOT_CUIRASS: 0.3, EQ.SLOT_CARRIED_LEFT: 0.1, EQ.SLOT_HELMET: 0.1, EQ.SLOT_GREAVES: 0.1,
	EQ.SLOT_BOOTS: 0.1, EQ.SLOT_LEFT_PAULDRON: 0.1, EQ.SLOT_RIGHT_PAULDRON: 0.1, EQ.SLOT_LEFT_GAUNTLET: 0.05,
	EQ.SLOT_RIGHT_GAUNTLET: 0.05}
const ATTACK_TYPES := ["chop", "slash", "thrust"]

var main
var records
var rng := RandomNumberGenerator.new()
var difficulty := 0                 # ustawienie gry (-100..100), domyślnie 0 – bez zmiany obrażeń
var hits := 0

func _init(game_main) -> void:
	main = game_main
	records = game_main.builder.actors

func _gmst(id: String, def) -> Variant:
	var g: Dictionary = records.record("gmst", id.to_lower())
	return g.get("value", def) if not g.is_empty() else def

var test_roll := -1                 # testy: stały rzut 0..99 (−1 – losowy)

func roll100() -> int:
	return test_roll if test_roll >= 0 else rng.randi() % 100

# --- walczący -------------------------------------------------------------------------------------------

func player_fighter() -> Dictionary:
	return {"kind": "player", "sid": "player", "base": "player", "rec": {}, "node": main.player}

func fighter_of(node: Node) -> Dictionary:
	if node == main.player:
		return player_fighter()
	var base := String(node.get_meta("mw_base", "")).to_lower()
	var t := String(main.db.get_object(base).get("type", ""))
	if t == "NPC_":
		return {"kind": "npc", "sid": String(node.get_meta("mw_sid", "")), "base": base, "node": node,
			"rec": records.record("npc", base)}
	if t == "CREA":
		return {"kind": "creature", "sid": String(node.get_meta("mw_sid", "")), "base": base, "node": node,
			"rec": records.record("creature", base)}
	return {}

## CreatureStats::getKnockedDown: powalenie (także gracza – stan postaci gracza).
func knocked_down(f: Dictionary) -> bool:
	if f.get("kind", "") == "player":
		return bool(main.player_stats().get("knocked_down", false))
	return f.has("sid") and bool(_actor_state(f).get("knocked_down", false))

func _actor_state(f: Dictionary) -> Dictionary:
	if not main.state.get("actors") is Dictionary:
		main.state.actors = {}
	var a: Dictionary = main.state.actors
	if not a.has(f.sid):
		a[f.sid] = {}
	return a[f.sid]

## Statystyki bazowe NPC/stworzenia: z rekordu (autoobliczane) albo zmienione skryptem (state.actors[sid]:
## "attributes", "skills" – kopia przy pierwszej zmianie, jak NpcStats po utworzeniu CustomData).
func _npc_stats(f: Dictionary) -> Dictionary:
	var st: Dictionary = main.state.actors.get(String(f.get("sid", "")), {}) if main.state.get("actors") is Dictionary else {}
	var out: Dictionary
	if f.kind == "npc":
		out = main.script_host.npc_autocalc(f.rec)
	else:
		out = {"attributes": f.rec.get("attributes", [0, 0, 0, 0, 0, 0, 0, 0]), "skills": []}
	if st.has("attributes") or st.has("skills"):
		out = out.duplicate()
		if st.has("attributes"):
			out["attributes"] = st.attributes
		if st.has("skills"):
			out["skills"] = st.skills
	return out

func attributes(f: Dictionary) -> Array:
	if f.kind == "player":
		return main.character.derived(main.player_stats()).attributes
	var at: Array = _npc_stats(f).get("attributes", [])
	return main.magic.npc_modified(f, at, "attributes") if main.magic != null and main.magic.main != null else at

## Umiejętność: gracz – zmodyfikowana; NPC – autoobliczona/z rekordu; stworzenie – walka/magia/skradanie wg
## specjalizacji umiejętności (combat.common getSkill).
func skill(f: Dictionary, i: int) -> float:
	if f.kind == "player":
		return float(main.character.derived(main.player_stats()).skills[i])
	if f.kind == "creature":
		var names: Array = main.character.skill_names()
		var sk: Dictionary = records.record("skill", String(names[i]) if i < names.size() else "")
		match int(sk.get("specialization", 0)):
			1: return float(f.rec.get("magic", 0))
			2: return float(f.rec.get("stealth", 0))
		return float(f.rec.get("combat", 0))
	var s: Array = _npc_stats(f).get("skills", [])
	if main.magic != null and main.magic.main != null:
		s = main.magic.npc_modified(f, s, "skills")
	return float(s[i]) if i < s.size() else 0.0

func max_health(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.character.derived(main.player_stats()).health.modified)
	var st: Dictionary = _actor_state(f)
	if st.has("health_base"):
		return float(st.health_base)
	if f.kind == "creature":
		return float(f.rec.get("health", 1))
	return float(main.script_host.npc_health(f.rec))

func max_fatigue(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.character.derived(main.player_stats()).fatigue.modified)
	var at := attributes(f)
	var key := [at[0], at[2], at[3], at[5]]
	var formula := float(at[0]) + float(at[2]) + float(at[3]) + float(at[5])
	# CreatureStats::setAttribute: zmiana siły/SW/zręczności/wytrzymałości przelicza podstawę kondycji na ich sumę
	# (zmodyfikowane); bez zmiany – wartość z rekordu (stworzenia, NPC bez autoobliczania)
	var ra: Array = f.rec.get("attributes", [])
	var changed: bool = ra.size() >= 6 and (float(ra[0]) != float(at[0]) or float(ra[2]) != float(at[2])
		or float(ra[3]) != float(at[3]) or float(ra[5]) != float(at[5]))
	if f.kind == "creature":
		return maxf(0.0, formula) if changed else float(f.rec.get("fatigue", 1))
	if not bool(f.rec.get("autocalc", false)) and f.rec.has("fatigue") and not changed:
		formula = float(f.rec.fatigue)
	return main.character.dyn_base_override(_actor_state(f), "fatigue", key, formula)

func health(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.player_stats().get("health", 0.0))
	return float(_actor_state(f).get("health", max_health(f)))

## Wartość ponad maksimum (wzmocnienie zdrowia z czaru) nie jest obcinana przy obrażeniach.
func set_health(f: Dictionary, v: float) -> void:
	var cap := maxf(max_health(f), health(f))
	if f.kind == "player":
		if bool(main.get("god_mode")) and v < health(f):
			return                                       # TGM: gracz nie traci zdrowia
		main.player_stats()["health"] = minf(v, cap)
	else:
		_actor_state(f)["health"] = minf(v, cap)

func fatigue(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.player_stats().get("fatigue", 0.0))
	return float(_actor_state(f).get("fatigue", max_fatigue(f)))

func set_fatigue(f: Dictionary, v: float) -> void:
	if f.kind == "player":
		if bool(main.get("god_mode")) and v < fatigue(f):
			return                                       # TGM: bez kosztu kondycji
		main.player_stats()["fatigue"] = v
	else:
		_actor_state(f)["fatigue"] = v

func is_dead(f: Dictionary) -> bool:
	if f.kind == "player":
		return float(main.player_stats().get("health", 1.0)) <= 0.0
	return bool(main.state.get("actors").get(f.sid, {}).get("dead", false)) if main.state.get("actors") is Dictionary else false

## getFatigueTerm: fFatigueBase − fFatigueMult × (1 − bieżąca/maksymalna).
func fatigue_term(f: Dictionary) -> float:
	var mx := max_fatigue(f)
	var norm := 1.0 if floorf(mx) == 0.0 else maxf(0.0, fatigue(f) / mx)
	return float(_gmst("fFatigueBase", 1.25)) - float(_gmst("fFatigueMult", 0.5)) * (1.0 - norm)

func magic_effect(f: Dictionary, fx: int) -> float:
	if main.magic != null and main.magic.main != null:
		return float(main.magic.magnitude_of(f, fx))
	if f.kind == "player":
		return float(main.character.constant_effects(main.player_stats()).get(str(fx), 0.0))
	return 0.0

# --- ekwipunek ------------------------------------------------------------------------------------------

## Założone przedmioty: {slot: {"id", "kind", "rec", "health"}}.
func equipment(f: Dictionary) -> Dictionary:
	var out := {}
	if f.kind == "player":
		var eq: Dictionary = main.player_stats().get("equipment", {})
		for s in eq:
			var e: Dictionary = eq[s]
			var it: Dictionary = main.interaction.inventory.item(String(e.id))
			if it.is_empty():
				continue
			out[int(s)] = {"id": it.id, "kind": it.kind, "rec": it.rec, "health": float(e.get("health", -1.0))}
		return out
	if f.kind == "creature" and not bool(f.rec.get("weapon_and_shield", false)):
		return out
	var av = records
	if av.equipment == null:
		av.equipment = av.Equipment.new(av)
	var items: Array = main.interaction.inventory.contents(f.sid, f.rec)
	# wilkołak (setWerewolf: unequipAll + szata) – tylko szata, bez automatycznego doboru
	if main.state.actors.has(f.sid) and bool(_actor_state(f).get("werewolf", false)):
		var robe: Dictionary = main.interaction.inventory.item("werewolfrobe")
		var only := {}
		for e in items:
			if String(e.id).to_lower() == "werewolfrobe" and not robe.is_empty():
				only[11] = {"id": "werewolfrobe", "kind": robe.kind, "rec": robe.rec, "health": -1.0}
		return only
	var slots: Dictionary = av.equipment.auto_equip(f.rec, items)
	# Equip ze skryptu (InventoryStore::equip): wybrany przedmiot w slocie, jeśli aktor nadal go ma
	var ov: Dictionary = _actor_state(f).get("equip_override", {}) if main.state.actors.has(f.sid) else {}
	for sk in ov:
		var oid := String(ov[sk])
		for e in items:
			if String(e.id).to_lower() == oid:
				var oit: Dictionary = main.interaction.inventory.item(oid)
				if not oit.is_empty():
					slots[int(sk)] = {"id": oid, "kind": oit.kind, "rec": oit.rec}
				break
	var cond: Dictionary = _actor_state(f).get("condition", {})
	# ExtraSpell (applyActorMagicEffect): NPC zdejmuje wszystko poza bronią, amunicją, spodniami i nie-pancerzem
	# w lewej ręce (pochodnia); po wygaśnięciu – autoEquip
	var extra := false
	for sp in (_actor_state(f).get("active_spells", []) as Array):
		for x in sp.get("effects", []):
			if int(x.get("effect", -1)) == 126 and bool(x.get("applied", false)) and not bool(x.get("invalid", false)):
				extra = true
	for s in slots:
		var e2: Dictionary = slots[s]
		if extra and not int(s) in [EQ.SLOT_CARRIED_RIGHT, EQ.SLOT_AMMUNITION, EQ.SLOT_PANTS] \
				and not (int(s) == EQ.SLOT_CARRIED_LEFT and String(e2.kind) != "armor"):
			continue
		out[int(s)] = {"id": e2.id, "kind": e2.kind, "rec": e2.rec, "health": float(cond.get(str(s), -1.0))}
	return out

func weapon(f: Dictionary) -> Dictionary:
	var e: Dictionary = equipment(f).get(EQ.SLOT_CARRIED_RIGHT, {})
	return e if not e.is_empty() and e.kind == "weapon" else {}

func item_health(e: Dictionary) -> float:
	var h := float(e.get("health", -1.0))
	if h < 0.0:
		var c: float = main.interaction.inventory.charge_of(String(e.get("id", ""))) if main != null and main.get("interaction") != null else -1.0
		if c >= 0.0:
			return c
	return float(e.rec.get("health", 0)) if h < 0.0 else h

## Stan przedmiotu w miejscu ekwipunku. Gracz: stan należy do egzemplarza w inwentarzu (CellRef::charge) – założony
## stos zmienia identyfikator na „id#c:N” (pełny – bez przyrostka), więc po zdjęciu uszkodzenie zostaje w ekwipunku.
func _set_item_health(f: Dictionary, slot: int, h: float) -> void:
	if f.kind == "player":
		var eq: Dictionary = main.player_stats().get("equipment", {})
		var key = str(slot) if eq.has(str(slot)) else (slot if eq.has(slot) else null)
		if key == null:
			return
		var inv = main.interaction.inventory
		var old_id := String(eq[key].id)
		var it: Dictionary = inv.item(old_id)
		var new_id: String = inv.charged_id(old_id, h, inv.max_charge(it.rec) if not it.is_empty() else 0.0)
		if new_id != old_id and inv.count_of("player", {}, old_id) > 0:
			eq[key]["id"] = new_id                 # najpierw miejsce ekwipunku, potem stosy
			inv.add("player", {}, new_id, 1)
			inv.remove("player", {}, old_id, 1)
		eq[key]["health"] = -1.0
	else:
		var st := _actor_state(f)
		if not st.get("condition") is Dictionary:
			st["condition"] = {}
		st.condition[str(slot)] = h

static func weapon_skill(w: Dictionary) -> int:
	if w.is_empty():
		return SK_HAND
	return int(EQ.WEAPON_SKILL.get(int(w.rec.get("weapon_type", 0)), 5))

## Umiejętność pancerza wg wagi (combat.common getArmorSkill; fLightMaxMod, fMedMaxMod).
func armor_skill(rec: Dictionary) -> int:
	if rec.is_empty():
		return SK_UNARMORED
	var wg := float(_gmst(String(EQ.ARMOR_WEIGHT_GMST.get(int(rec.get("armor_type", 1)), "icuirassweight")), 30))
	var w := float(rec.get("weight", 0.0))
	if w <= wg * float(_gmst("fLightMaxMod", 0.6)) + 0.0005:
		return 21
	if w <= wg * float(_gmst("fMedMaxMod", 0.9)) + 0.0005:
		return 2
	return 3

## getArmorRating: suma ważona miejsc (pancerz × umiejętność / iBaseArmorSkill × stan; bez pancerza –
## (fUnarmoredBase1 × bez pancerza) × (fUnarmoredBase2 × bez pancerza)) + efekt Tarcza; stworzenia – tylko Tarcza.
func armor_rating(f: Dictionary) -> float:
	var shield := magic_effect(f, FX_SHIELD)
	if f.kind == "creature":
		return shield
	var eq := equipment(f)
	var un := skill(f, SK_UNARMORED)
	var bare := (float(_gmst("fUnarmoredBase1", 0.1)) * un) * (float(_gmst("fUnarmoredBase2", 0.065)) * un)
	var total := 0.0
	for slot in ARMOR_WEIGHTS:
		var e: Dictionary = eq.get(slot, {})
		var r := bare
		if not e.is_empty() and e.kind == "armor":
			r = effective_armor(e, f)
		total += r * float(ARMOR_WEIGHTS[slot])
	return total + shield

func effective_armor(e: Dictionary, f: Dictionary) -> float:
	var rec: Dictionary = e.rec
	var r := float(rec.get("armor", 0))
	if float(rec.get("weight", 0.0)) != 0.0:
		r = r * skill(f, armor_skill(rec)) / float(_gmst("iBaseArmorSkill", 30))
	var mh := float(rec.get("health", 0))
	if mh != 0.0:
		r *= item_health(e) / mh
	return r

func adjust_for_armor(damage: float, f: Dictionary) -> float:
	var armor := armor_rating(f)
	var x := damage / (damage + armor)
	return damage * maxf(x, float(_gmst("fCombatArmorMinMult", 0.25)))

## pickRandomArmor: miejsce trafienia wg rzutu 0..99.
static func armor_slot_for_roll(r: int) -> int:
	if r >= 90:
		return EQ.SLOT_CARRIED_LEFT
	if r >= 85:
		return EQ.SLOT_RIGHT_GAUNTLET
	if r >= 80:
		return EQ.SLOT_LEFT_GAUNTLET
	if r >= 70:
		return EQ.SLOT_RIGHT_PAULDRON
	if r >= 60:
		return EQ.SLOT_LEFT_PAULDRON
	if r >= 50:
		return EQ.SLOT_BOOTS
	if r >= 40:
		return EQ.SLOT_GREAVES
	if r >= 30:
		return EQ.SLOT_HELMET
	return EQ.SLOT_CUIRASS

# --- wzory ataku ----------------------------------------------------------------------------------------

## getEvasion: (zręczność/5 + szczęście/10) × zmęczenie + Schronienie.
func evasion(f: Dictionary) -> float:
	var at := attributes(f)
	return (float(at[A_AGILITY]) / 5.0 + float(at[A_LUCK]) / 10.0) * fatigue_term(f) + minf(100.0, magic_effect(f, FX_SANCTUARY))

## getHitChance: unik ofiary (zręczność, szczęście, Schronienie) pomijany, gdy ofiara jest powalona,
## sparaliżowana albo nieświadoma ataku gracza (nie walczy i awarenessCheck(gracz, ofiara) zawodzi).
func hit_chance(att: Dictionary, vic: Dictionary, skill_value: float, victim_helpless := false) -> float:
	var defense := 0.0
	if fatigue(vic) >= 0.0:
		var helpless := victim_helpless
		if not helpless and vic.has("sid"):
			helpless = knocked_down(vic) or magic_effect(vic, FX_PARALYZE) > 0.0
		if not helpless and att.get("kind", "") == "player" and vic.get("kind", "") != "player" \
				and main.get("ai") != null and main.ai != null and vic.get("node") != null \
				and is_instance_valid(vic.node) and not main.ai.in_combat(vic.node):
			helpless = not main.ai.awareness(main.player, vic.node)
		if not helpless:
			defense = evasion(vic)
		var inviso := float(_gmst("fCombatInvisoMult", 0.2))
		defense += minf(100.0, inviso * magic_effect(vic, FX_CHAMELEON))
		defense += minf(100.0, inviso * magic_effect(vic, FX_INVISIBILITY))
	var at := attributes(att)
	var attack := skill_value + float(at[A_AGILITY]) / 5.0 + float(at[A_LUCK]) / 10.0
	attack *= fatigue_term(att)
	attack += magic_effect(att, FX_FORTIFY_ATTACK) - magic_effect(att, FX_BLIND)
	return roundf(attack - defense)

## Obrażenia bronią (Npc::hit): min + (max − min) × siła ataku, × stan broni, × (fDamageStrengthBase +
## siła × fDamageStrengthMult × 0,1).
func weapon_damage(att: Dictionary, w: Dictionary, attack_type: int, strength: float) -> float:
	var arr: Array = w.rec.get(ATTACK_TYPES[clampi(attack_type, 0, 2)], [0, 0])
	var dmg := float(arr[0]) + (float(arr[1]) - float(arr[0])) * strength
	return adjust_weapon_damage(dmg, att, w)

func adjust_weapon_damage(dmg: float, att: Dictionary, w: Dictionary) -> float:
	var mh := float(w.rec.get("health", 0))
	if mh > 0.0:
		dmg *= item_health(w) / mh
	var at := attributes(att)
	return dmg * (float(_gmst("fDamageStrengthBase", 0.5)) + float(at[A_STRENGTH]) * float(_gmst("fDamageStrengthMult", 0.1)) * 0.1)

## getHandToHandDamage: walka wręcz × (fMinHandToHandMult … fMaxHandToHandMult); w kondycję, chyba że ofiara
## jest powalona/sparaliżowana (wtedy zdrowie × fHandtoHandHealthPer). Siła bez wpływu (domyślne ustawienie).
func hand_damage(att: Dictionary, vic_helpless: bool, strength: float) -> Dictionary:
	var mn := float(_gmst("fMinHandToHandMult", 0.1))
	var mx := float(_gmst("fMaxHandToHandMult", 0.5))
	var d := skill(att, SK_HAND) * (mn + (mx - mn) * strength)
	if vic_helpless:
		d *= float(_gmst("fHandtoHandHealthPer", 0.1))
	return {"damage": d, "health": vic_helpless}

func reach(att: Dictionary, w: Dictionary) -> float:
	var cd := float(_gmst("fCombatDistance", 128.0))
	if not w.is_empty():
		return cd * float(w.rec.get("reach", 1.0))
	if att.kind != "creature":
		return cd * float(_gmst("fHandToHandReach", 1.0))
	return cd

## applyFatigueLoss: fFatigueAttackBase + obciążenie × fFatigueAttackMult (+ waga broni × siła × fWeaponFatigueMult).
func attack_fatigue(att: Dictionary, w: Dictionary, strength: float) -> float:
	var enc := 0.0
	if att.kind == "player":
		enc = main.character.normalized_encumbrance(main.player_stats(), main.player_weight())
	var loss := float(_gmst("fFatigueAttackBase", 2.0)) + enc * float(_gmst("fFatigueAttackMult", 0.0))
	if not w.is_empty():
		loss += float(w.rec.get("weight", 0.0)) * strength * float(_gmst("fWeaponFatigueMult", 0.25))
	return loss

func reduce_weapon_condition(att: Dictionary, damage: float, hit: bool) -> void:
	var w := weapon(att)
	if w.is_empty() or float(w.rec.get("health", 0)) <= 0.0:
		return
	var x := maxf(1.0, float(_gmst("fWeaponDamageMult", 0.1)) * (damage if hit else 0.0))
	var h := item_health(w)
	h -= minf(float(int(x)), h)
	_set_item_health(att, EQ.SLOT_CARRIED_RIGHT, h)
	if h <= 0.0 and att.kind == "player":
		main.unequip_slot(EQ.SLOT_CARRIED_RIGHT)         # broń zniszczona – zdjęta

func resist_normal(vic: Dictionary, w: Dictionary, damage: float) -> float:
	if w.is_empty() or bool(w.rec.get("silver", false)) or bool(w.rec.get("magical", false)) \
			or not String(w.rec.get("enchant", "")).is_empty():
		return damage
	var res := magic_effect(vic, FX_RESIST_NORMAL) / 100.0
	var weak := magic_effect(vic, FX_WEAK_NORMAL) / 100.0
	return damage * (1.0 - minf(1.0, res - weak))

# --- trafienie ------------------------------------------------------------------------------------------

## Atak wręcz/bronią białą: attack_type 0 chop, 1 slash, 2 thrust; strength 0..1. roll – test (0..99).
## → {"success", "damage", "health", "victim_dead"}
func melee(att: Dictionary, vic: Dictionary, attack_type: int, strength: float, roll := -1) -> Dictionary:
	var w := weapon(att)
	if main.magic != null and main.magic.main != null:
		main.magic.break_invisibility(att)        # CharacterController: zwolnienie ataku (AttackRelease)
	set_fatigue(att, fatigue(att) - attack_fatigue(att, w, strength))
	if vic.is_empty() or is_dead(vic):
		return {"success": false}
	if att.kind == "player":
		_set_enemy(vic)                          # Npc::hit: WindowManager::setEnemy przed rzutem na trafienie
	var helpless := knocked_down(vic)        # Npc::hit: fCombatKODamageMult – także powalony gracz
	var chance := hit_chance(att, vic, skill(att, weapon_skill(w)), helpless)
	var r := roll if roll >= 0 else roll100()
	if r >= chance:
		reduce_weapon_condition(att, 0.0, false)
		on_hit(vic, att, {}, false)
		return {"success": false, "chance": chance}
	var damage := 0.0
	var health_dmg := true
	if not w.is_empty():
		damage = weapon_damage(att, w, attack_type, strength)
		reduce_weapon_condition(att, damage, true)
		damage = resist_normal(vic, w, damage)
	elif att.kind == "creature":                 # Creature::hit: obrażenia ataku z rekordu (zdrowie)
		var atk: Array = att.rec.get("attack", [[0, 0], [0, 0], [0, 0]])
		var pr: Array = atk[clampi(attack_type, 0, atk.size() - 1)] if not atk.is_empty() else [0, 0]
		damage = float(pr[0]) + (float(pr[1]) - float(pr[0])) * strength
	else:
		var hd := hand_damage(att, helpless, strength)
		damage = float(hd.damage)
		health_dmg = bool(hd.health)
	if att.kind == "player":
		main.skill_used(weapon_skill(w), "weapon_hit")
	if helpless:
		damage *= float(_gmst("fCombatKODamageMult", 1.5))
	# Npc::hit / Creature::hit: zaklęcie broni przy uderzeniu i tarcze żywiołów ofiary – przed blokiem
	var ench := false
	if not w.is_empty() and main.magic != null and main.magic.main != null and not is_dead(vic):
		ench = main.magic.on_strike(att, vic, w)     # applyOnStrikeEnchantment
	if main.magic != null and main.magic.main != null:
		elemental_shields(att, vic)
	var blocked := block(att, vic, w, damage, strength)
	if blocked:
		damage = 0.0
	# Npc::hit / Creature::hit: diseaseContact(ofiara, atakujący) po bloku, także przy zablokowanym ciosie
	if main.magic != null and main.magic.main != null:
		main.magic.disease_contact(vic, att)
	var res := on_hit(vic, att, {"health": damage} if health_dmg else {"fatigue": damage}, true)
	if ench:
		res["enchanted"] = true
	res["chance"] = chance
	res["blocked"] = blocked
	return res

## applyElementalShields: każda tarcza żywiołu ofiary rani atakującego: rzut obronny (zniszczenie + 0,2 SW +
## 0,1 szczęście) × 1,25 × kondycja − k100, + odporność atakującego na żywioł (≤ 100);
## fElementalShieldMult × wielkość × (1 − 0,01 × x), skalowane trudnością (z zamienionymi stronami).
func elemental_shields(att: Dictionary, vic: Dictionary) -> void:
	if att.is_empty() or vic.is_empty():
		return
	var fxv: Dictionary = main.magic.effects(vic)
	for pair in [[4, 14], [5, 15], [6, 16]]:
		var mag := float(fxv.get(str(pair[0]), 0.0))
		if mag == 0.0:
			continue
		var at := attributes(att)
		var save := skill(att, 10) + 0.2 * float(at[2]) + 0.1 * float(at[7])
		var fmax := max_fatigue(att)
		var nf := 1.0 if floorf(fmax) == 0.0 else maxf(0.0, fatigue(att) / fmax)
		save *= 1.25 * nf
		var x := maxf(0.0, save - float(roll100()))
		x = minf(100.0, x + main.magic.resistance_attribute(int(pair[1]), main.magic.effects(att)))
		x = float(_gmst("fElementalShieldMult", 0.1)) * mag * (1.0 - 0.01 * x)
		x = _difficulty(x, vic, att)
		set_health(att, health(att) - x)
		if main.audio != null:
			main.audio.play("Health Damage", att.node.global_position if att.get("node") != null and att.kind != "player" else null)
		if health(att) <= 0.0:
			if att.kind == "player":
				if main.has_method("_player_died"):
					main._player_died()
			elif not is_dead(att):
				main.on_actor_died(att, vic)

## blockMeleeAttack: tylko ofiara gotowa do bloku (dobyta broń, tarcza, nie atakuje) – gracz; NPC (AI) – etap 8.
func block(att: Dictionary, vic: Dictionary, w: Dictionary, damage: float, strength: float, roll := -1) -> bool:
	if vic.kind != "player" or not main.player_ready_to_block():
		return false
	var sh: Dictionary = equipment(vic).get(EQ.SLOT_CARRIED_LEFT, {})
	if sh.is_empty() or sh.kind != "armor":
		return false
	var vat := attributes(vic)
	var block_term := skill(vic, SK_BLOCK) + 0.2 * float(vat[A_AGILITY]) + 0.1 * float(vat[A_LUCK])
	var swing := strength * float(_gmst("fSwingBlockMult", 1.0)) + float(_gmst("fSwingBlockBase", 1.0))
	var bt := block_term * swing
	if main.player.move_input.y >= 0.0:
		bt *= float(_gmst("fBlockStillBonus", 1.25))
	bt *= fatigue_term(vic)
	var aat := attributes(att)
	var at_term := (skill(att, weapon_skill(w)) + 0.2 * float(aat[A_AGILITY]) + 0.1 * float(aat[A_LUCK])) * fatigue_term(att)
	var x := clampi(int(bt - at_term), int(_gmst("iBlockMinChance", 10)), int(_gmst("iBlockMaxChance", 50)))
	if (roll if roll >= 0 else roll100()) >= x:
		return false
	var sh_h := item_health(sh) - minf(item_health(sh), float(int(damage)))
	_set_item_health(vic, EQ.SLOT_CARRIED_LEFT, sh_h)
	if sh_h <= 0.0:
		main.unequip_slot(EQ.SLOT_CARRIED_LEFT)
	var enc := minf(1.0, main.character.normalized_encumbrance(main.player_stats(), main.player_weight()))
	var loss := float(_gmst("fFatigueBlockBase", 4.0)) + enc * float(_gmst("fFatigueBlockMult", 0.0))
	if not w.is_empty():
		loss += float(w.rec.get("weight", 0.0)) * strength * float(_gmst("fWeaponFatigueBlockMult", 1.0))
	set_fatigue(vic, fatigue(vic) - loss)
	main.skill_used(SK_BLOCK, "block")
	return true

## Npc/Creature::onHit – część przed obrażeniami: atakujący aktor, z którym ofiara jeszcze nie walczy → GetAttacked
## (stats.setAttacked), trafienie towarzysza przez gracza (friendlyHit: do 3 trafień bez reakcji) albo reakcja
## (actorAttacked: przestępstwo, walka – z wyjątkiem „pokojowych” z OnPCHitMe i Fight 0). OnPCHitMe = 1 przy
## każdym trafieniu/chybieniu przez gracza poza trafieniem towarzysza.
func _hit_reaction(vic: Dictionary, att: Dictionary) -> void:
	var ai = main.get("ai")
	var node = vic.get("node")
	var live: bool = node != null and is_instance_valid(node) and ai != null
	var att_id := "player" if att.kind == "player" else String(att.get("sid", ""))
	var set_hit := true
	if not (live and ai.in_combat_with(node, att_id)):
		_actor_state(vic)["attacked"] = true
		if att.kind == "player" and live and ai.sides_with_player(node):
			# friendlyHit: w walce – bez reakcji; poza nią licznik, od 4. trafienia reakcja
			if ai.in_combat(node):
				set_hit = false
			else:
				var st := _actor_state(vic)
				st["friendly_hits"] = int(st.get("friendly_hits", 0)) + 1
				if int(st.friendly_hits) < 4:
					set_hit = false
					if main.dialogue != null:
						main.dialogue.say_voice(node, "hit")
		if set_hit and att.kind == "player":
			main.on_actor_attacked(vic)
	if set_hit and att.kind == "player" and main.get("scripts") != null and main.scripts != null:
		main.scripts.actor_hit_by_player(String(vic.sid), String(vic.base))   # OnPCHitMe = 1

## onHit (Lua: pancerz, trudność, powalenie) + Npc::onHit (zdrowie, kondycja, śmierć).
## damages: {"health": x} albo {"fatigue": x}. → {"success", "damage", "health", "victim_dead"}
func on_hit(vic: Dictionary, att: Dictionary, damages: Dictionary, successful: bool, ignore_armor := false) -> Dictionary:
	if vic.kind != "player" and not att.is_empty():
		_hit_reaction(vic, att)
	# setLastHitAttemptObject / setLastHitObject (HitAttemptOnMe / HitOnMe): id broni (pocisku, czaru) ataku
	var obj := String(damages.get("object", ""))
	if obj.is_empty() and not att.is_empty():
		var aw := weapon(att)
		obj = String(aw.get("id", "")) if not aw.is_empty() else ""
	var vh: Dictionary = main.player_stats() if vic.kind == "player" else _actor_state(vic)
	if not obj.is_empty():
		vh["last_hit_attempt"] = obj.to_lower()
		if successful:
			vh["last_hit"] = obj.to_lower()
	if not successful:
		if not att.is_empty() and att.kind == "player" and main.audio != null:
			main.audio.play("miss", vic.node.global_position if vic.node != null else null)
		return {"success": false}
	hits += 1
	var raw := float(damages.get("health", 0.0))
	var hd := raw
	if hd > 0.0 and not ignore_armor:
		var adj := adjust_for_armor(hd, vic)
		var diff := floorf(adj - hd)
		hd = maxf(adj, 1.0)
		var slot := armor_slot_for_roll(roll100())
		var piece: Dictionary = equipment(vic).get(slot, {})
		var skid := armor_skill(piece.rec if not piece.is_empty() and piece.kind == "armor" else {})
		if vic.kind == "player":
			main.skill_used(skid, "armor_hit")
		if not piece.is_empty() and piece.kind == "armor":
			var unarmed_creature: bool = not att.is_empty() and att.kind == "creature" and weapon(att).is_empty()
			if not unarmed_creature and float(piece.rec.get("health", 0)) > 0.0:
				var nh := maxf(0.0, item_health(piece) + diff)
				_set_item_health(vic, slot, nh)
				if nh <= 0.0 and vic.kind == "player":
					main.unequip_slot(slot)
			if main.audio != null:
				main.audio.play({21: "Light Armor Hit", 2: "Medium Armor Hit", 3: "Heavy Armor Hit"}.get(skid, "Hand To Hand Hit"),
					vic.node.global_position if vic.node != null and vic.kind != "player" else null)
	if hd > 0.0:
		hd = _difficulty(hd, att, vic)
	var fd := float(damages.get("fatigue", 0.0))
	var dead := false
	if hd >= 0.001:
		set_health(vic, health(vic) - hd)
		if main.audio != null:
			main.audio.play("Health Damage", vic.node.global_position if vic.node != null and vic.kind != "player" else null)
		# Npc::onHit: kwestia „Hit” z szansą iVoiceHitOdds, gdy zadał ją ktoś (nie gracz-ofiara)
		if vic.kind == "npc" and not att.is_empty() and vic.get("node") != null and main.dialogue != null \
				and roll100() < int(_gmst("iVoiceHitOdds", 30)) and health(vic) > 0.0:
			main.dialogue.say_voice(vic.node, "hit")
	if fd >= 0.001:
		set_fatigue(vic, fatigue(vic) - fd)
	_stagger(vic, raw, hd + fd > 0.001)
	if health(vic) <= 0.0 and not is_dead(vic):
		dead = true
		main.on_actor_died(vic, att)
	return {"success": true, "damage": hd if hd > 0.0 else fd, "health": hd > 0.0, "victim_dead": dead}

func _difficulty(d: float, att: Dictionary, vic: Dictionary) -> float:
	var ap: bool = not att.is_empty() and att.kind == "player"
	var vp: bool = vic.kind == "player"
	if ap == vp or difficulty == 0:
		return d
	var mult := float(_gmst("fDifficultyMult", 5.0))
	var term := difficulty * 0.01
	var x := 0.0
	if vp:
		x = term * mult if term > 0.0 else term / mult
	else:
		x = -term / mult if term > 0.0 else -term * mult
	return d * (1.0 + x)

## applyStagger: powalenie, gdy obrażenia ≥ zręczność × fKnockDownMult i rzut ≥ iKnockDownOddsBase +
## zręczność × iKnockDownOddsMult × 0,01 (animacje i odzyskiwanie – etap 8/10; tu stan).
func _stagger(vic: Dictionary, raw: float, has_damage: bool) -> void:
	if not has_damage:
		return
	var at := attributes(vic)
	var agi := float(at[A_AGILITY])
	var agility_term := agi * float(_gmst("fKnockDownMult", 0.5))
	var kd := agi * float(_gmst("iKnockDownOddsMult", 50)) * 0.01 + float(_gmst("iKnockDownOddsBase", 50))
	if raw > 0.0 and agility_term <= raw and kd <= roll100():
		# Npc/Creature::onHit: powalenie każdego aktora, także gracza (CharacterController – brak ruchu do końca)
		if vic.kind == "player":
			main.player_stats()["knocked_down"] = true
		else:
			_actor_state(vic)["knocked_down"] = true

## Pocisk (projectileHit): łuk/kusza + strzała – obie wartości „chop”; broń rzucana – dwa razy (jak OpenMW).
## WindowManager::setEnemy → HUD (pasek zdrowia celu).
func _set_enemy(vic: Dictionary) -> void:
	var hud = main.get("mw_hud") if main != null else null
	if hud != null and hud.has_method("set_enemy") and vic.get("kind", "") != "player":
		hud.set_enemy(vic)

func projectile_hit(att: Dictionary, vic: Dictionary, launcher: Dictionary, ammo: Dictionary, strength: float, roll := -1) -> Dictionary:
	if att.kind == "player" and not vic.is_empty():
		_set_enemy(vic)                          # projectileHit: cel – aktor, setEnemy przed rzutem
	if vic.is_empty() or is_dead(vic):
		return {"success": false}
	var skid := weapon_skill(launcher) if not launcher.is_empty() else SK_MARKSMAN
	var chance := hit_chance(att, vic, skill(att, skid))
	if (roll if roll >= 0 else roll100()) >= chance:
		on_hit(vic, att, {}, false)
		return {"success": false, "chance": chance}
	var c1: Array = launcher.rec.get("chop", [0, 0]) if not launcher.is_empty() else [0, 0]
	var c2: Array = ammo.rec.get("chop", [0, 0])
	var dmg := float(c1[0]) + (float(c1[1]) - float(c1[0])) * strength
	dmg += float(c2[0]) + (float(c2[1]) - float(c2[0])) * strength
	if not launcher.is_empty():
		dmg = adjust_weapon_damage(dmg, att, launcher)
	reduce_weapon_condition(att, dmg, true)
	dmg = resist_normal(vic, ammo, dmg)
	if att.kind == "player":
		main.skill_used(skid, "weapon_hit")
	var res := on_hit(vic, att, {"health": dmg, "object": String(launcher.get("id", ammo.get("id", "")))}, true)
	if main.magic != null and main.magic.main != null and not is_dead(vic):
		res["enchanted"] = main.magic.on_strike(att, vic, ammo, true)
	res["chance"] = chance
	return res
