extends RefCounted
## Ekwipunek NPC (etap 2c): automatyczne zakładanie przedmiotów z inwentarza jak w OpenMW
## (apps/openmw/mwworld/inventorystore.cpp: autoEquipWeapon, autoEquipArmor; mwclass/armor.cpp, clothing.cpp;
## umiejętności NPC z autoobliczaniem: mwclass/npc.cpp autoCalculateSkills).
## Moduł danych bez węzłów – przyda się też w etapie 3 (inwentarz gracza, stan gry).
##
## Pominięte na razie (opisane w docs/PLAN-WDROZENIA.md, etap 3): listy poziomowane w inwentarzu (LEVI –
## losowanie przy pojawieniu się NPC), światła w lewej ręce (Actors::updateEquippedLight – pochodnie nocą).

const SLOT_HELMET := 0
const SLOT_CUIRASS := 1
const SLOT_GREAVES := 2
const SLOT_LEFT_PAULDRON := 3
const SLOT_RIGHT_PAULDRON := 4
const SLOT_LEFT_GAUNTLET := 5
const SLOT_RIGHT_GAUNTLET := 6
const SLOT_BOOTS := 7
const SLOT_SHIRT := 8
const SLOT_PANTS := 9
const SLOT_SKIRT := 10
const SLOT_ROBE := 11
const SLOT_LEFT_RING := 12
const SLOT_RIGHT_RING := 13
const SLOT_AMULET := 14
const SLOT_BELT := 15
const SLOT_CARRIED_RIGHT := 16
const SLOT_CARRIED_LEFT := 17
const SLOT_AMMUNITION := 18

# ESM::Armor::Type → slot (Armor::getEquipmentSlots)
const ARMOR_SLOTS := {0: SLOT_HELMET, 1: SLOT_CUIRASS, 2: SLOT_LEFT_PAULDRON, 3: SLOT_RIGHT_PAULDRON, 4: SLOT_GREAVES,
	5: SLOT_BOOTS, 6: SLOT_LEFT_GAUNTLET, 7: SLOT_RIGHT_GAUNTLET, 8: SLOT_CARRIED_LEFT, 9: SLOT_LEFT_GAUNTLET,
	10: SLOT_RIGHT_GAUNTLET}
# ESM::Armor::Type → GMST wagi (Armor::getEquipmentSkill)
const ARMOR_WEIGHT_GMST := {0: "ihelmweight", 1: "icuirassweight", 2: "ipauldronweight", 3: "ipauldronweight",
	4: "igreavesweight", 5: "ibootsweight", 6: "igauntletweight", 7: "igauntletweight", 8: "ishieldweight",
	9: "igauntletweight", 10: "igauntletweight"}
# ESM::Clothing::Type → sloty (Clothing::getEquipmentSlots); pierścień: lewy, potem prawy
const CLOTHING_SLOTS := {0: [SLOT_PANTS], 1: [SLOT_BOOTS], 2: [SLOT_SHIRT], 3: [SLOT_BELT], 4: [SLOT_ROBE],
	5: [SLOT_RIGHT_GAUNTLET], 6: [SLOT_LEFT_GAUNTLET], 7: [SLOT_SKIRT], 8: [SLOT_LEFT_RING, SLOT_RIGHT_RING],
	9: [SLOT_AMULET]}

# umiejętności (kolejność ESM)
const SK_MEDIUM_ARMOR := 2
const SK_HEAVY_ARMOR := 3
const SK_BLUNT := 4
const SK_LONG_BLADE := 5
const SK_AXE := 6
const SK_SPEAR := 7
const SK_UNARMORED := 17
const SK_LIGHT_ARMOR := 21
const SK_SHORT_BLADE := 22
const SK_MARKSMAN := 23
const WEAPON_SKILL_ORDER := [SK_LONG_BLADE, SK_AXE, SK_SPEAR, SK_SHORT_BLADE, SK_MARKSMAN, SK_BLUNT]
# ESM::Weapon::Type → umiejętność; amunicja: 12 strzała, 13 bełt
const WEAPON_SKILL := {0: SK_SHORT_BLADE, 1: SK_LONG_BLADE, 2: SK_LONG_BLADE, 3: SK_BLUNT, 4: SK_BLUNT, 5: SK_BLUNT,
	6: SK_SPEAR, 7: SK_AXE, 8: SK_AXE, 9: SK_MARKSMAN, 10: SK_MARKSMAN, 11: SK_MARKSMAN}
const WEAPON_TWO_HANDED := [2, 4, 5, 6, 8, 9, 10]
const PRT_HEAD := 0
const PRT_LFOOT := 16
const PRT_RFOOT := 15

var av        # MWActorVisual – dostęp do rekordów
var stats := {"leveled_skipped": 0, "missing_items": 0}

func _init(actor_visual) -> void:
	av = actor_visual

func _gmst(id: String, def := 0.0) -> float:
	var g: Dictionary = av.record("gmst", id)
	return float(g.get("value", def)) if not g.is_empty() else def

## round_ieee_754 z OpenMW (połówki od zera).
static func _round(x: float) -> float:
	return floor(x + 0.5) if x >= 0.0 else ceil(x - 0.5)

## Umiejętności NPC: z rekordu albo autoobliczone (klasa, rasa, specjalizacja, poziom).
func npc_skills(npc: Dictionary) -> Array:
	if not bool(npc.get("autocalc", false)) and npc.get("skills") is Array and (npc["skills"] as Array).size() >= 27:
		return npc["skills"]
	var out := []
	out.resize(27)
	out.fill(0.0)
	var cls: Dictionary = av.record("class", String(npc.get("class", "")))
	var race: Dictionary = av.record("race", String(npc.get("race", "")))
	var level := int(npc.get("level", 1))
	var major: Array = cls.get("major_skills", [])
	var minor: Array = cls.get("minor_skills", [])
	for s in minor:
		if int(s) >= 0 and int(s) < 27:
			out[int(s)] += 10
	for s in major:
		if int(s) >= 0 and int(s) < 27:
			out[int(s)] += 25
	var names: Array = av.records_index().get("skills", [])
	var spec := int(cls.get("specialization", -1))
	for i in 27:
		var race_bonus := 0
		for b in race.get("skill_bonuses", []):
			if int(b.get("skill", -1)) == i:
				race_bonus = int(b.get("bonus", 0))
				break
		var mm := 1.0 if (i in major or i in minor or float(i) in major or float(i) in minor) else 0.1
		var sm := 0.0
		var sb := 0
		var sk: Dictionary = av.record("skill", String(names[i]) if i < names.size() else "")
		if not sk.is_empty() and int(sk.get("specialization", -2)) == spec:
			sm = 0.5
			sb = 5
		out[i] = minf(_round(out[i] + 5 + race_bonus + sb + (level - 1) * (mm + sm)), 100.0)
	return out

func _item(id: String) -> Dictionary:
	for kind in ["armor", "clothing", "weapon"]:
		var r: Dictionary = av.record(kind, id)
		if not r.is_empty():
			return {"kind": kind, "id": id.to_lower(), "rec": r}
	return {}

## Kolejność jak w ContainerStore: listy według typu (zbroje, ubrania, …, broń), w każdej kolejność z rekordu.
func inventory(npc: Dictionary) -> Dictionary:
	var by_kind := {"armor": [], "clothing": [], "weapon": []}
	var seen := {}
	for e in npc.get("inventory", []):
		var id := String(e.get("item", "")).to_lower()
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		var it := _item(id)
		if it.is_empty():
			if not av.record("leveleditem", id).is_empty() or id.begins_with("l_"):
				stats.leveled_skipped += 1
			continue
		by_kind[it.kind].append(it)
	return by_kind

func armor_skill(rec: Dictionary) -> int:
	var g := String(ARMOR_WEIGHT_GMST.get(int(rec.get("armor_type", -1)), ""))
	if g.is_empty():
		return -1
	var w := floorf(_gmst(g))
	var weight := float(rec.get("weight", 0.0))
	if weight <= w * _gmst("flightmaxmod", 0.6) + 0.0005:
		return SK_LIGHT_ARMOR
	if weight <= w * _gmst("fmedmaxmod", 0.9) + 0.0005:
		return SK_MEDIUM_ARMOR
	return SK_HEAVY_ARMOR

func armor_rating(rec: Dictionary, skills: Array) -> float:
	if float(rec.get("weight", 0.0)) == 0.0:
		return float(rec.get("armor", 0))
	var s := armor_skill(rec)
	var v := float(skills[s]) if s >= 0 else 0.0
	return float(rec.get("armor", 0)) * v / maxf(_gmst("ibasearmorskill", 30.0), 1.0)

func _beast_blocked(it: Dictionary, beast: bool) -> bool:
	if not beast:
		return false
	for p in it.rec.get("parts", []):
		var prt := int(p.get("part", -1))
		if prt == PRT_HEAD or prt == PRT_LFOOT or prt == PRT_RFOOT:
			return true
	return false

func _equip_weapon(slots: Dictionary, weapons: Array, skills: Array) -> void:
	var arrow = null
	var bolt = null
	var arrow_max := 0
	var bolt_max := 0
	for it in weapons:
		var t := int(it.rec.get("weapon_type", -1))
		var chop := int((it.rec.get("chop", [0, 0]) as Array)[1])
		if t == 12 and chop >= arrow_max:
			arrow_max = chop
			arrow = it
		elif t == 13 and chop >= bolt_max:
			bolt_max = chop
			bolt = it
	var visited := {}
	for _i in WEAPON_SKILL_ORDER.size():
		var mx := 0.0
		var best := -1
		for j in WEAPON_SKILL_ORDER.size():
			var sv := float(skills[WEAPON_SKILL_ORDER[j]])
			if sv > mx and not visited.has(j):
				mx = sv
				best = j
		if best < 0:
			break
		var wmax := 0
		var weapon = null
		for it in weapons:
			var t := int(it.rec.get("weapon_type", -1))
			if t == 12 or t == 13:
				continue
			if WEAPON_SKILL.get(t, -1) == WEAPON_SKILL_ORDER[best]:
				for k in ["chop", "slash", "thrust"]:
					var v := int((it.rec.get(k, [0, 0]) as Array)[1])
					if v >= wmax:
						wmax = v
						weapon = it
		if weapon != null and int(weapon.rec.get("health", 1)) > 0:
			var t := int(weapon.rec.get("weapon_type", -1))
			var ok := true
			if t == 9:
				ok = arrow != null
				if ok:
					slots[SLOT_AMMUNITION] = arrow
			elif t == 10:
				ok = bolt != null
				if ok:
					slots[SLOT_AMMUNITION] = bolt
			if ok:
				slots[SLOT_CARRIED_RIGHT] = weapon
				if t != 9 and t != 10:
					slots.erase(SLOT_AMMUNITION)
				break
		visited[best] = true

## Sloty → przedmiot {"kind", "id", "rec"} (InventoryStore::autoEquip dla NPC).
func auto_equip(npc: Dictionary) -> Dictionary:
	var slots := {}
	var inv := inventory(npc)
	var skills := npc_skills(npc)
	var race: Dictionary = av.record("race", String(npc.get("race", "")))
	var beast := bool(race.get("beast", false))
	_equip_weapon(slots, inv.weapon, skills)
	var us := float(skills[SK_UNARMORED])
	var unarmored := maxf((_gmst("funarmoredbase1", 0.1) * us) * (_gmst("funarmoredbase2", 0.065) * us), 0.0)
	for it in inv.armor + inv.clothing:
		var is_armor: bool = it.kind == "armor"
		if is_armor:
			if armor_rating(it.rec, skills) <= unarmored:
				continue
			if int(it.rec.get("health", 1)) == 0:
				continue
		if _beast_blocked(it, beast):
			continue
		var item_slots: Array = [ARMOR_SLOTS[int(it.rec.get("armor_type", -1))]] if is_armor and ARMOR_SLOTS.has(int(it.rec.get("armor_type", -1))) \
				else (CLOTHING_SLOTS.get(int(it.rec.get("clothing_type", -1)), []) if not is_armor else [])
		for slot in item_slots:
			if slots.has(slot):
				var old: Dictionary = slots[slot]
				if not is_armor:
					if old.kind != "clothing":
						continue
					if slot == SLOT_LEFT_RING:
						if not slots.has(SLOT_RIGHT_RING):
							continue
						if int(slots[SLOT_RIGHT_RING].rec.get("value", 0)) <= int(old.rec.get("value", 0)):
							continue
					if int(it.rec.get("value", 0)) <= int(old.rec.get("value", 0)):
						continue
				elif old.kind == "armor":
					var ot := int(old.rec.get("armor_type", -1))
					var nt := int(it.rec.get("armor_type", -1))
					if ot == nt:
						if armor_rating(it.rec, skills) <= armor_rating(old.rec, skills):
							continue
					elif ot < nt:
						continue
			slots[slot] = it
			break
	return slots
