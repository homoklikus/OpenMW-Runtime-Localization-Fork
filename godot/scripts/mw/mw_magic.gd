extends RefCounted
## Magia (etap 7) – wzory i mechanika OpenMW 0.51:
##  - koszty: spellutil.cpp (calcEffectCost, calcSpellCost, getEffectiveEnchantmentCastCost, getEnchantmentCharge),
##  - szansa rzucenia: calcSpellBaseSuccessChance/getSpellSuccessChance, moce raz na dobę,
##  - odporność: spellresistance.cpp (getEffectResistance/getEffectMultiplier, mapa odporności i słabości z
##    components/esm3/loadmgef.cpp), odbicie i pochłanianie zaklęć (applyProtections),
##  - działające czary: activespells.cpp + spelleffects.cpp (applyMagicEffect: efekty jednorazowe i ciągłe
##    × dt, losowanie wielkości min…max, applyActorMagicEffect/removeMagicEffect),
##  - mikstury i składniki: CastSpell::cast(Potion/Ingredient), rollIngredientEffect, alchemy.cpp,
##  - przedmioty zaklęte: CastSpell::cast(item) (ładunek, zwój), recharge.cpp, enchanting.cpp (zaklinanie),
##  - pułapka dusz (Soultrap) i kamienie dusz.
## Efekty z rekordów MGEF (world/records/magiceffect.json, klucz = indeks efektu).
##
## Stan: gracz – character["active_spells"], ["magic_damage"] {"attributes": [8], "skills": [27]},
## ["item_charge"] {id: ładunek}, ["powers_used"] {id: godzina gry}, ["selected_magic"] {"kind", "id"},
## ["mark"]; NPC/stworzenia – GameState.actors[sid] (te same klucze).
## Działający czar: {"id", "name", "kind" (spell|potion|ingredient|enchantment), "caster", "effects": [{"effect",
## "skill", "attribute", "min", "max", "duration", "time_left", "magnitude", "applied"}]}.

const RT_SELF := 0
const RT_TOUCH := 1
const RT_TARGET := 2
const COST_GAME_SPELL := 0
const COST_PLAYER_SPELL := 1
const COST_GAME_ENCHANTMENT := 2
const COST_PLAYER_ENCHANTMENT := 3
const COST_GAME_POTION := 4

var records
var main = null                     # main.gd (walczący, inwentarz, komunikaty); bez main – tylko wzory
var rng := RandomNumberGenerator.new()
var test_disease_roll := -1                    # testy: stały rzut diseaseContact (0–9999)
var test_roll := -1                 # testy: stały rzut 0..99 (−1 – losowy)
var test_magnitude := -1            # testy: stałe losowanie wielkości (−1 – losowe; ≥ 0 – przesunięcie od min)
var unsupported := {}               # efekty bez implementacji (etap 8 i dalej) → licznik użyć

func _init(records_source, game_main = null) -> void:
	records = records_source
	main = game_main

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

# --- stałe efektów (ESM::MagicEffect) --------------------------------------------------------------------

const FX_WATER_BREATHING := 0
const FX_SWIFT_SWIM := 1
const FX_WATER_WALKING := 2
const FX_JUMP := 9
const FX_LEVITATE := 10
const FX_SLOW_FALL := 11
const FX_FIRE_SHIELD := 4
const FX_LIGHTNING_SHIELD := 5
const FX_FROST_SHIELD := 6
const FX_BURDEN := 7
const FX_FEATHER := 8
const FX_LOCK := 12
const FX_OPEN := 13
const FX_FIRE := 14
const FX_SHOCK := 15
const FX_FROST := 16
const FX_DRAIN_ATTRIBUTE := 17
const FX_DRAIN_HEALTH := 18
const FX_DRAIN_MAGICKA := 19
const FX_DRAIN_FATIGUE := 20
const FX_DRAIN_SKILL := 21
const FX_DAMAGE_ATTRIBUTE := 22
const FX_DAMAGE_HEALTH := 23
const FX_DAMAGE_MAGICKA := 24
const FX_DAMAGE_FATIGUE := 25
const FX_DAMAGE_SKILL := 26
const FX_POISON := 27
const FX_WEAK_MAGICKA := 31
const FX_DISINTEGRATE_WEAPON := 37
const FX_DISINTEGRATE_ARMOR := 38
const FX_PARALYZE := 45
const FX_SILENCE := 46
const FX_SOUND := 48
const FX_DISPEL := 57
const FX_SOULTRAP := 58
const FX_MARK := 60
const FX_RECALL := 61
const FX_DIVINE := 62
const FX_ALMSIVI := 63
const FX_INVISIBILITY := 39
const FX_TELEKINESIS := 59
const FX_LIGHT := 41
const FX_NIGHT_EYE := 43
const FX_SUN_DAMAGE := 135
const FX_STUNTED_MAGICKA := 136
const FX_CORPRUS := 132
const FX_CURE_CORPRUS := 71
const FX_CHARM := 44
const FX_TURN_UNDEAD := 101
const FX_COMMAND_CREATURE := 118
const FX_COMMAND_HUMANOID := 119
## Wielkość efektu trwałego czaru (zdolność, choroba, klątwa): losowana raz przy dodaniu czaru (min..max,
## ActiveSpells – jak OpenMW), zapamiętana w stanie aktora („spell_rolls”, zapis gry); min = max – bez zapisu.
func spell_store_magnitude(h: Dictionary, sid: String, idx: int, e: Dictionary) -> float:
	var mn := float(e.get("min", 0))
	var mx := float(e.get("max", 0))
	if mx <= mn:
		return mn
	var key := "%s|%d" % [sid.to_lower(), idx]
	var rolls = h.get("spell_rolls")
	if rolls is Dictionary and rolls.has(key):
		return float(rolls[key])
	if not rolls is Dictionary:
		rolls = {}
		h["spell_rolls"] = rolls
	var v := _roll_magnitude({"min": mn, "max": mx})
	rolls[key] = v
	return v

## Trwałe czary (Spells → ActiveSpells z Flag_SpellStore): choroby, zaraza, klątwy – efekty jednorazowe zmieniające
## pule (Wyssanie/Uszkodzenie atrybutu i umiejętności, Wyssanie zdrowia/magii/kondycji) nakładane raz przy dodaniu
## czaru; po usunięciu czaru Wyssanie wraca (removeMagicEffect), Uszkodzenie zostaje. Wzmocnienia i odporności –
## w mapie efektów (constant_effects). Zdolności (Flag_AffectsBaseValues) – bez zmian (mapa efektów).
const SPELL_STORE_TYPES := [2, 3, 4]
const SPELL_STORE_POOL := [17, 18, 19, 20, 21, 22, 26]

func _permanent_spells(f: Dictionary) -> Array:
	if f.kind == "player":
		return main.player_stats().get("spells", [])
	return actor_spells(f)

## Trwały czar z Korpusem wyleczony (CureCorprusDisease → removeMagicEffect(Corprus)): efekty czaru usunięte,
## czar zostaje na liście (GetSpell 1) bez efektów i bez dalszego pogarszania.
static func spell_store_cured(h: Dictionary, sid: String) -> bool:
	var st = h.get("spell_store")
	return st is Dictionary and (st as Dictionary).has(sid.to_lower()) and bool(st[sid.to_lower()].get("cured", false))

func has_spell_store(f: Dictionary) -> bool:
	if f.is_empty():
		return false
	if holder(f).get("spell_store") is Dictionary and not (holder(f).spell_store as Dictionary).is_empty():
		return true
	for sid in _permanent_spells(f):
		var sp: Dictionary = records.record("spell", String(sid).to_lower())
		if int(sp.get("spell_type", 0)) in SPELL_STORE_TYPES:
			return true
	return false

## Synchronizacja trwałych czarów z ich efektami jednorazowymi + pogarszanie Korpusu co 24 h gry
## (ActiveSpellParams::worsen/shouldWorsen: ponowne nałożenie efektów jednorazowych czaru, sMagicCorprusWorsens).
func _sync_spell_store(f: Dictionary) -> void:
	var h := holder(f)
	var store: Dictionary = h.get("spell_store", {}) if h.get("spell_store") is Dictionary else {}
	var now := _now_hours()
	var have := {}
	for sid0 in _permanent_spells(f):
		var sid := String(sid0).to_lower()
		var sp: Dictionary = records.record("spell", sid)
		if not int(sp.get("spell_type", 0)) in SPELL_STORE_TYPES:
			continue
		have[sid] = true
		if not store.has(sid):
			var applied := []
			var corprus := false
			var ei := -1
			for e in sp.get("effects", []):
				ei += 1
				var id := int(e.get("effect", -1))
				if id == FX_CORPRUS:
					corprus = true
				if id in SPELL_STORE_POOL:
					var ae := {"effect": id, "skill": int(e.get("skill", -1)), "attribute": int(e.get("attribute", -1)),
						"min": float(e.get("min", 0)), "max": float(e.get("max", 0))}
					var m := spell_store_magnitude(h, sid, ei, e)
					ae["magnitude"] = m
					_actor_effect(f, {"caster": ""}, ae, m)
					applied.append(ae)
			var rec := {"applied": applied}
			if corprus:
				rec["worsen"] = 0
				rec["next"] = now + 24.0
			store[sid] = rec
		elif store[sid].has("next") and not bool(store[sid].get("cured", false)) and now >= float(store[sid].next):
			var r: Dictionary = store[sid]
			r["worsen"] = int(r.worsen) + 1
			r["next"] = float(r.next) + 24.0
			for e in sp.get("effects", []):
				var id2 := int(e.get("effect", -1))
				if id2 == FX_CORPRUS or not _flag(effect(id2), "applied_once"):
					continue
				var we := {"effect": id2, "skill": int(e.get("skill", -1)), "attribute": int(e.get("attribute", -1)),
					"min": float(e.get("min", 0)), "max": float(e.get("max", 0))}
				var wm := _roll_magnitude(we)
				if id2 in SPELL_STORE_POOL:
					_actor_effect(f, {"caster": ""}, we, wm)
					we["magnitude"] = wm
					var wl: Array = r.get("worse_applied", [])
					wl.append(we)
					r["worse_applied"] = wl
				elif id2 in [FX_FORTIFY_ATTRIBUTE, FX_FORTIFY_SKILL]:
					_mod_adjust(f, "attributes" if id2 == FX_FORTIFY_ATTRIBUTE else "skills",
						int(we.attribute) if id2 == FX_FORTIFY_ATTRIBUTE else int(we.skill), wm)
			if f.kind == "player":
				main._toast(_text("sMagicCorprusWorsens", "Your Corprus worsens."), 3.0)
	for sid in store.keys():
		if have.has(sid):
			continue
		if bool(store[sid].get("cured", false)):
			store.erase(sid)
			continue
		for ae in store[sid].get("applied", []):
			var id3 := int(ae.effect)
			if id3 in [17, 18, 19, 20, 21]:
				ae["applied"] = true
				_remove_effect(f, ae)
		store.erase(sid)
	if store.is_empty():
		h.erase("spell_store")
	else:
		h["spell_store"] = store

func _mod_adjust(f: Dictionary, key: String, idx: int, d: float) -> void:
	if idx < 0:
		return
	var h := holder(f)
	if not h.get("mod_adjust") is Dictionary:
		h["mod_adjust"] = {}
	var n := 8 if key == "attributes" else 27
	var arr: Array = h.mod_adjust.get(key, [])
	while arr.size() < n:
		arr.append(0.0)
	arr[idx] = float(arr[idx]) + d
	h.mod_adjust[key] = arr

## Przywołania (summoning.cpp getSummonMap): efekt → GMST z identyfikatorem stworzenia
const SUMMONS := {102: "sMagicScampID", 103: "sMagicClannfearID", 104: "sMagicDaedrothID", 105: "sMagicDremoraID",
	106: "sMagicAncestralGhostID", 107: "sMagicSkeletalMinionID", 108: "sMagicLeastBonewalkerID",
	109: "sMagicGreaterBonewalkerID", 110: "sMagicBonelordID", 111: "sMagicWingedTwilightID", 112: "sMagicHungerID",
	113: "sMagicGoldenSaintID", 114: "sMagicFlameAtronachID", 115: "sMagicFrostAtronachID",
	116: "sMagicStormAtronachID", 134: "sMagicCenturionSphereID", 137: "sMagicFabricantID",
	138: "sMagicCreature01ID", 139: "sMagicCreature02ID", 140: "sMagicCreature03ID", 141: "sMagicCreature04ID",
	142: "sMagicCreature05ID"}
## modifyAiSetting: efekt → [ustawienie AI, znak zmiany, wariant dla stworzeń (true) / ludzi (false)]
const AI_EFFECTS := {49: ["fight", -1, false], 50: ["fight", -1, true], 51: ["fight", 1, false], 52: ["fight", 1, true],
	53: ["flee", 1, false], 54: ["flee", 1, true], 55: ["flee", -1, false], 56: ["flee", -1, true]}
const FX_SPELL_ABSORPTION := 67
const FX_REFLECT := 68
const FX_CURE_COMMON := 69
const FX_CURE_BLIGHT := 70
const FX_CURE_POISON := 72
const FX_CURE_PARALYZATION := 73
const FX_RESTORE_ATTRIBUTE := 74
const FX_RESTORE_HEALTH := 75
const FX_RESTORE_MAGICKA := 76
const FX_RESTORE_FATIGUE := 77
const FX_RESTORE_SKILL := 78
const FX_FORTIFY_ATTRIBUTE := 79
const FX_FORTIFY_HEALTH := 80
const FX_FORTIFY_MAGICKA := 81
const FX_FORTIFY_FATIGUE := 82
const FX_FORTIFY_SKILL := 83
const FX_ABSORB_ATTRIBUTE := 85
const FX_ABSORB_HEALTH := 86
const FX_ABSORB_MAGICKA := 87
const FX_ABSORB_FATIGUE := 88
const FX_ABSORB_SKILL := 89
const FX_RESIST_MAGICKA := 93
const FX_REMOVE_CURSE := 100
# getResistanceEffect / getWeaknessEffect (loadmgef.cpp)
const RESIST_MAGICKA_EFFECTS := [37, 38, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 85, 86, 87, 88, 89, 28, 29, 30, 31,
	32, 33, 34, 35, 36, 7, 44, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 101]
const RESISTANCE_OF := {14: 90, 16: 91, 15: 92, 133: 94, 132: 96, 27: 97, 45: 99}
const WEAKNESS_OF := {14: 28, 16: 29, 15: 30, 133: 32, 132: 34, 27: 35}
const SHIELD_OF := {14: FX_FIRE_SHIELD, 15: FX_LIGHTNING_SHIELD, 16: FX_FROST_SHIELD}
# zaklęte broń i zbroje przyzwane (getBoundItemsMap): efekt → GMST z id przedmiotu
const BOUND_ITEMS := {120: ["sMagicBoundDaggerID"], 121: ["sMagicBoundLongswordID"], 122: ["sMagicBoundMaceID"],
	123: ["sMagicBoundBattleAxeID"], 124: ["sMagicBoundSpearID"], 125: ["sMagicBoundLongbowID"],
	127: ["sMagicBoundCuirassID"], 128: ["sMagicBoundHelmID"], 129: ["sMagicBoundBootsID"],
	130: ["sMagicBoundShieldID"], 131: ["sMagicBoundLeftGauntletID", "sMagicBoundRightGauntletID"]}
# efekty tylko w mapie efektów (czytane przez walkę, ruch, dialogi itd.)
const MAP_ONLY := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 28, 29, 30, 31, 32, 33, 34, 35, 36, 39, 40, 41, 42, 43, 44, 45,
	46, 47, 48, 58, 64, 65, 66, 67, 68, 79, 83, 84, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 117, 136]
# efekty zależne od AI, przywołań, teleportacji po znacznikach itp. – etap 8 (w mapie efektów, bez działania)
const LATER := {
}
const SPELL_SPELL := 0
const SPELL_ABILITY := 1
const SPELL_POWER := 5
const ENCH_CAST_ONCE := 0
const ENCH_WHEN_STRIKES := 1
const ENCH_WHEN_USED := 2
const ENCH_CONSTANT := 3
const SK_ENCHANT := 9
const SK_ALCHEMY := 16
const A_INTELLIGENCE := 1
const A_WILLPOWER := 2
const A_LUCK := 7
const APP_MORTAR := 0
const APP_ALEMBIC := 1
const APP_CALCINATOR := 2
const APP_RETORT := 3

func roll100() -> int:
	return test_roll if test_roll >= 0 else rng.randi() % 100

func _flag(mg: Dictionary, name: String) -> bool:
	return bool(mg.get(name, false))

func _combat():
	return main.combat

# --- stan aktora -------------------------------------------------------------------------------------------

func holder(f: Dictionary) -> Dictionary:
	if f.kind == "player":
		return main.player_stats()
	return _combat()._actor_state(f)

func active(f: Dictionary) -> Array:
	var h := holder(f)
	if not h.get("active_spells") is Array:
		h["active_spells"] = []
	return h.active_spells

func pools(f: Dictionary) -> Dictionary:
	var h := holder(f)
	if not h.get("magic_damage") is Dictionary:
		h["magic_damage"] = {}
	var d: Dictionary = h.magic_damage
	for k in [["attributes", 8], ["skills", 27]]:
		if not d.get(k[0]) is Array or (d[k[0]] as Array).size() != int(k[1]):
			var z := []
			z.resize(int(k[1]))
			z.fill(0.0)
			d[k[0]] = z
	return d

# --- mapa efektów (MagicEffects) ----------------------------------------------------------------------------

## Zaklęcie przedmiotu (rekord ENCH) albo {}.
func item_enchantment(it: Dictionary) -> Dictionary:
	if it.is_empty():
		return {}
	var en := String(it.rec.get("enchant", ""))
	return records.record("enchantment", en) if not en.is_empty() else {}

## Efekty stałe przedmiotów założonych przez gracza i działających czarów (dla MWCharacter.constant_effects).
func add_extra_effects(st: Dictionary, fx: Dictionary) -> void:
	if main == null or main.interaction == null:
		return
	var eq: Dictionary = st.get("equipment", {})
	for s in eq:
		var it: Dictionary = main.interaction.inventory.item(String(eq[s].id))
		_add_constant_item(fx, it)
	_add_active(fx, st.get("active_spells", []))
	_add_effect_base(fx, st)

## Zmiany podstawy efektów ze skryptów (SetResistFire, ModWaterWalking… – MagicEffects::modifyBase).
static func _add_effect_base(fx: Dictionary, h: Dictionary) -> void:
	var eb: Dictionary = h.get("effect_base", {})
	for k in eb:
		fx[str(k)] = float(fx.get(str(k), 0.0)) + float(eb[k])

func _add_constant_item(fx: Dictionary, it: Dictionary) -> void:
	var en := item_enchantment(it)
	if en.is_empty() or int(en.get("type", -1)) != ENCH_CONSTANT:
		return
	for e in en.get("effects", []):
		var mg := effect(int(e.get("effect", -1)))
		main.character.add_effect(fx, e, 1.0 if _flag(mg, "no_magnitude") else float(e.get("min", 0)))

func _add_active(fx: Dictionary, list) -> void:
	if not list is Array:
		return
	for sp in list:
		for e in sp.get("effects", []):
			if not bool(e.get("applied", false)):
				continue
			var id := int(e.get("effect", -1))
			if id in [FX_FORTIFY_HEALTH, FX_FORTIFY_MAGICKA, FX_FORTIFY_FATIGUE]:
				# czasowe: w mapie efektów (GetEffect, Lua), ale maksimum bez zmian (adjustDynamicStat – tylko
				# wartość bieżąca) – część czasowa osobno („_tmp…”, odejmowana przy liczeniu maksimum)
				var k := "_tmp%d" % id
				fx[k] = float(fx.get(k, 0.0)) + float(e.get("magnitude", 0.0))
			main.character.add_effect(fx, e, float(e.get("magnitude", 0.0)))

## Spells::add (AddSpell, zarażenie chorobą): gracz – lista zaklęć postaci; NPC/stworzenie – lista w stanie aktora,
## zdolności i choroby działają od razu. false, gdy aktor już ma zaklęcie albo rekord nie istnieje.
func add_spell(f: Dictionary, spid: String) -> bool:
	spid = spid.to_lower()
	if records.record("spell", spid).is_empty():
		return false
	if f.kind == "player":
		var sp: Array = main.player_stats().get("spells", [])
		if spid in sp:
			return false
		sp.append(spid)
		main.player_stats()["spells"] = sp
		return true
	var ast: Dictionary = _combat()._actor_state(f)
	if not ast.get("spells") is Array:
		ast["spells"] = (f.rec.get("spells", []) as Array).map(func(x): return String(x).to_lower())
	if spid in ast.spells:
		return false
	ast.spells.append(spid)
	sync_dynamic(f)
	return true

## diseaseContact (mwmechanics/disease.hpp): aktor zetknął się z nosicielem (trafienie wręcz, przeszukanie zwłok).
## Każda choroba nosiciela, której aktor nie ma: szansa fDiseaseXferChance × 100 × (1 − 0,01 × (odporność −
## słabość)) na 10 000 (Korpus – odporność/słabość na Korpus, choroba zwykła – na choroby, zaraza – na zarazy).
## Gracz nie zaraża.
func disease_contact(actor: Dictionary, carrier: Dictionary) -> Array:
	var got := []
	if actor.is_empty() or carrier.is_empty() or carrier.kind == "player":
		return got
	var chance := float(_gmst("fDiseaseXferChance", 2.5))
	var fx := effects(actor)
	var have: Array = main.player_stats().get("spells", []) if actor.kind == "player" else actor_spells(actor)
	for sid in actor_spells(carrier).duplicate():
		var spid := String(sid).to_lower()
		if spid in have:
			continue
		var sp: Dictionary = records.record("spell", spid)
		if sp.is_empty():
			continue
		var corprus := false
		for e in sp.get("effects", []):
			if int(e.get("effect", -1)) == 132:
				corprus = true
		var typ := int(sp.get("spell_type", 0))
		var res_w := []
		if corprus:
			res_w = ["96", "34"]
		elif typ == 3:
			res_w = ["94", "32"]
		elif typ == 2:
			res_w = ["95", "33"]
		else:
			continue
		var resist := 1.0 - 0.01 * (float(fx.get(res_w[0], 0.0)) - float(fx.get(res_w[1], 0.0)))
		var x := int(chance * 100.0 * resist)
		var roll := test_disease_roll if test_disease_roll >= 0 else rng.randi() % 10000
		if roll < x and add_spell(actor, spid):
			got.append(spid)
			if actor.kind == "player":
				var g: Dictionary = records.record("gmst", "smagiccontractdisease")
				var msg := String(g.get("value", "You have contracted %s.")) if not g.is_empty() else "You have contracted %s."
				main.call("_toast", msg.replace("%s", String(sp.get("name", spid))))
	return got

## SpellIcons::updateWidgets: efekty gracza do ikon (HUD, okno magii) – z działających czarów, także stałych źródeł
## (zdolności, choroby, klątwy, stałe zaklęcia przedmiotów – w OpenMW wszystkie w ActiveSpells), w kolejności
## pierwszego wystąpienia. → [{"id", "left" (−1: stały), "names": [źródła]}]
func effect_icon_list(f: Dictionary) -> Array:
	var order := []
	var info := {}
	for sp in active(f):
		for x in sp.effects:
			var id := int(x.effect)
			if not info.has(id):
				info[id] = {"id": id, "left": -2.0, "names": []}
				order.append(id)
			var left := float(x.time_left) if float(x.get("duration", 0.0)) > 0.0 else -1.0
			if float(info[id].left) != -1.0:
				info[id].left = -1.0 if left < 0.0 else maxf(float(info[id].left), left)
			info[id].names.append(String(sp.get("name", "")))
	var fxmap: Dictionary = effects(f)
	for k in fxmap:
		var id2 := int(String(k).split(":")[0])
		if float(fxmap[k]) == 0.0 or info.has(id2) or effect(id2).is_empty():
			continue
		info[id2] = {"id": id2, "left": -1.0, "names": []}
		order.append(id2)
	return order.map(func(i): return info[i])

## Zaklęcia aktora (Spells): po AddSpell/RemoveSpell lista w stanie aktora, inaczej z rekordu.
func actor_spells(f: Dictionary) -> Array:
	var st = main.state.actors.get(String(f.get("sid", ""))) if main != null and main.state.get("actors") is Dictionary else null
	if st is Dictionary and st.get("spells") is Array:
		return st.spells
	return (f.get("rec", {}) as Dictionary).get("spells", []) as Array

## Mapa efektów walczącego: gracz – MWCharacter.constant_effects; NPC/stworzenie – zdolności z rekordu, stałe
## zaklęcia ekwipunku, działające czary.
func effects(f: Dictionary) -> Dictionary:
	if f.kind == "player":
		return main.character.constant_effects(main.player_stats())
	var fx := {}
	# martwy (killDeadActors po animacji śmierci: ActiveSpells::clear) – bez zdolności, zaklęć przedmiotów i czarów;
	# zostają zmiany podstawy ze skryptów (Set/Mod…)
	if _combat().is_dead(f):
		_add_effect_base(fx, _combat()._actor_state(f))
		# Actors::killDeadActors: po ActiveSpells::clear wielkość Wampiryzmu zostaje w mapie efektów
		var vamp := 0.0
		for sid in actor_spells(f):
			for e in records.record("spell", String(sid)).get("effects", []):
				if int(e.get("effect", -1)) == 133:
					vamp += float(e.get("min", 0))
		if vamp != 0.0:
			fx["133"] = float(fx.get("133", 0.0)) + vamp
		return fx
	# zdolności rasy (Npc::getCreatureStats: addAllToInstance(race->mPowers)) i własne zaklęcia rekordu
	var own: Array = actor_spells(f).duplicate()
	if f.kind == "npc":
		own.append_array(records.record("race", String(f.rec.get("race", ""))).get("powers", []))
	var hold: Dictionary = _combat()._actor_state(f)
	for sid in own:
		var sp: Dictionary = records.record("spell", String(sid))
		if not sp.is_empty() and int(sp.get("spell_type", 0)) in main.character.CONSTANT_TYPES \
				and not spell_store_cured(hold, String(sid)):
			var ei := 0
			for e in sp.get("effects", []):
				main.character.add_effect(fx, e, spell_store_magnitude(hold, String(sid), ei, e))
				ei += 1
	var eq: Dictionary = _combat().equipment(f)
	for s in eq:
		_add_constant_item(fx, {"rec": eq[s].rec})
	_add_active(fx, _combat()._actor_state(f).get("active_spells", []))
	_add_effect_base(fx, _combat()._actor_state(f))
	return fx

func magnitude_of(f: Dictionary, fx: int) -> float:
	return float(effects(f).get(str(fx), 0.0))

## Atrybuty/umiejętności NPC: wzmocnienia z mapy efektów, ubytki z puli (gracz – MWCharacter.derived).
func npc_modified(f: Dictionary, base: Array, kind: String) -> Array:
	var st: Dictionary = _combat()._actor_state(f)
	var has_fx: bool = st.has("active_spells") or st.has("magic_damage") or st.has("mod_adjust") or st.has("effect_base")
	if not has_fx and actor_spells(f).is_empty() \
			and (records.record("race", String(f.rec.get("race", ""))).get("powers", []) as Array).is_empty():
		return base
	var fx := effects(f)
	var dmg: Array = (st.get("magic_damage", {}) as Dictionary).get(kind, [])
	var adj: Array = (st.get("mod_adjust", {}) as Dictionary).get(kind, [])
	var fid := FX_FORTIFY_ATTRIBUTE if kind == "attributes" else FX_FORTIFY_SKILL
	var out := []
	for i in base.size():
		out.append(maxf(0.0, float(base[i]) + float(fx.get("%d:%d" % [fid, i], 0.0)) + (float(adj[i]) if i < adj.size() else 0.0)
			- (float(dmg[i]) if i < dmg.size() else 0.0)))
	return out

# --- odporność (spellresistance.cpp) ------------------------------------------------------------------------

func resistance_attribute(id: int, fx: Dictionary) -> float:
	var r := 0.0
	if id in RESIST_MAGICKA_EFFECTS:
		r += float(fx.get(str(FX_RESIST_MAGICKA), 0.0))
		r -= float(fx.get(str(FX_WEAK_MAGICKA), 0.0))
	if RESISTANCE_OF.has(id):
		r += float(fx.get(str(RESISTANCE_OF[id]), 0.0))
	if WEAKNESS_OF.has(id):
		r -= float(fx.get(str(WEAKNESS_OF[id]), 0.0))
	if SHIELD_OF.has(id):
		r += float(fx.get(str(SHIELD_OF[id]), 0.0))
	return r

func has_resistance(id: int) -> bool:
	return id in RESIST_MAGICKA_EFFECTS or RESISTANCE_OF.has(id)

## getEffectResistance: 0..100 (100 = całkowita); spell – rekord czaru (szansa rzucającego), roll 0..99.
func effect_resistance(id: int, target: Dictionary, caster: Dictionary, spell: Dictionary, roll := -1) -> float:
	if not has_resistance(id):
		return 0.0
	var mg := effect(id)
	var fx := effects(target)
	var resistance := resistance_attribute(id, fx)
	var at: Array = _combat().attributes(target)
	var x := (float(at[A_WILLPOWER]) + 0.1 * float(at[A_LUCK])) * float(_combat().fatigue_term(target))
	var cast_chance := 100.0
	if not spell.is_empty() and not caster.is_empty():
		cast_chance = spell_chance(spell, caster, false, false)
	if cast_chance > 0.0:
		x *= 50.0 / cast_chance
	var r := float(roll if roll >= 0 else roll100())
	if _flag(mg, "no_magnitude"):
		r -= resistance
	if x <= r:
		x = 0.0
	elif _flag(mg, "no_magnitude"):
		x = 100.0
	else:
		x = r / minf(x, 100.0)
	return minf(x + resistance, 100.0)

# --- szansa rzucenia (spellutil.cpp) ----------------------------------------------------------------------

func school_skill(id: int) -> int:
	return int(effect(id).get("school_skill", 11))

## calcSpellBaseSuccessChance → {"chance", "school" (indeks umiejętności)}.
func spell_base_chance(sp: Dictionary, f: Dictionary) -> Dictionary:
	var y := INF
	var lowest := 0.0
	var school := 11
	for e in sp.get("effects", []):
		var mg := effect(int(e.get("effect", -1)))
		if mg.is_empty():
			continue
		var x := float(e.get("duration", 0))
		if not _flag(mg, "applied_once"):
			x = maxf(1.0, x)
		x *= 0.1 * float(mg.get("base_cost", 0.0))
		x *= 0.5 * (int(e.get("min", 0)) + int(e.get("max", 0)))
		x += int(e.get("area", 0)) * 0.05 * float(mg.get("base_cost", 0.0))
		if int(e.get("range", 0)) == RT_TARGET:
			x *= 1.5
		x *= _gmst("fEffectCostMult", 0.5)
		var sk := int(mg.get("school_skill", 11))
		var s := 2.0 * float(_combat().skill(f, sk))
		if s - x < y:
			y = s - x
			school = sk
			lowest = s
	var at: Array = _combat().attributes(f)
	return {"chance": lowest - spell_cost(sp) + 0.2 * float(at[A_WILLPOWER]) + 0.1 * float(at[A_LUCK]), "school": school}

## getSpellSuccessChance: moce – 100 albo 0 (raz na dobę), Cisza – 0, inne niż zaklęcia – 100, brak magii – 0
## (check_magicka), „zawsze się udaje” – 100; (bazowa − Dźwięk) × współczynnik zmęczenia.
func spell_chance(sp: Dictionary, f: Dictionary, cap := true, check_magicka := false) -> float:
	var base: float = spell_base_chance(sp, f).chance
	var typ := int(sp.get("spell_type", 0))
	if typ == SPELL_POWER:
		return 100.0 if can_use_power(f, String(sp.get("id", ""))) else 0.0
	var fx := effects(f)
	if float(fx.get(str(FX_SILENCE), 0.0)) > 0.0:
		return 0.0
	if typ != SPELL_SPELL:
		return 100.0
	var cost := spell_cost(sp)
	if check_magicka and cost > 0 and magicka(f) < cost:
		return 0.0
	if bool(sp.get("always_succeeds", false)):
		return 100.0
	var c := (base - float(fx.get(str(FX_SOUND), 0.0))) * float(_combat().fatigue_term(f))
	return clampf(c, 0.0, 100.0) if cap else maxf(c, 0.0)

func _now_hours() -> float:
	if main == null or main.envr == null:
		return 0.0
	return float(main.envr.day) * 24.0 + float(main.envr.game_hour)

func can_use_power(f: Dictionary, id: String) -> bool:
	var used: Dictionary = holder(f).get("powers_used", {})
	return not used.has(id.to_lower()) or _now_hours() - float(used[id.to_lower()]) >= 24.0

# --- magia (wartość bieżąca) -------------------------------------------------------------------------------

func max_magicka(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.character.derived(main.player_stats()).magicka.modified)
	var at: Array = _combat().attributes(f)
	var factor := _gmst("fNPCbaseMagickaMult", 2.0) + magnitude_of(f, 84) * 0.1
	var formula := float(at[A_INTELLIGENCE]) * factor
	# recalculateMagicka (zmiana inteligencji, Wzmocnienie maks. magii): inteligencja × współczynnik; bez zmian –
	# wartość z rekordu (stworzenia, NPC bez autoobliczania)
	var ra: Array = f.rec.get("attributes", [])
	var recalc: bool = magnitude_of(f, 84) != 0.0 or (ra.size() > A_INTELLIGENCE and float(ra[A_INTELLIGENCE]) != float(at[A_INTELLIGENCE]))
	if f.kind == "creature" and not recalc:
		formula = float(f.rec.get("magicka", 0))
	elif f.kind != "creature" and not bool(f.rec.get("autocalc", false)) and f.rec.has("magicka") and not recalc:
		formula = float(f.rec.magicka)
	return main.character.dyn_base_override(_combat()._actor_state(f), "magicka", [at[A_INTELLIGENCE], factor], formula)

func magicka(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.player_stats().get("magicka", 0.0))
	return float(_combat()._actor_state(f).get("magicka", max_magicka(f)))

func set_magicka(f: Dictionary, v: float) -> void:
	if f.kind == "player" and bool(main.get("god_mode")) and v < float(holder(f).get("magicka", 0.0)):
		return                                           # TGM: bez kosztu magii
	holder(f)["magicka"] = v

## adjustDynamicStat: 0 zdrowie, 1 magia, 2 kondycja. allow_below – osłabienie (poniżej zera); allow_above –
## wzmocnienie czasowe (ponad maksimum).
func adjust_dynamic(f: Dictionary, stat: int, delta: float, allow_below := false, allow_above := false) -> void:
	var cb = _combat()
	var cur := 0.0
	var mx := 0.0
	match stat:
		0:
			cur = float(cb.health(f))
			mx = float(cb.max_health(f))
		1:
			cur = magicka(f)
			mx = max_magicka(f)
		_:
			cur = float(cb.fatigue(f))
			mx = float(cb.max_fatigue(f))
	var v := cur + delta
	if delta > 0.0 and not allow_above:
		v = minf(v, maxf(mx, cur))            # wartość ponad maksimum (wzmocnienie) nie jest obcinana przy leczeniu
	if delta < 0.0 and not allow_below:
		v = maxf(v, minf(0.0, cur))
	var h := holder(f)
	h[["health", "magicka", "fatigue"][clampi(stat, 0, 2)]] = v

# --- działające czary ---------------------------------------------------------------------------------------

func _roll_magnitude(e: Dictionary) -> float:
	var mn := float(e.get("min", 0.0))
	var mx := float(e.get("max", 0.0))
	if mn == mx:
		return mn
	var n := int(mx - mn + 1.0)
	if n <= 0:
		return mn
	return mn + float(test_magnitude if test_magnitude >= 0 else rng.randi() % n)

## Nakłada efekty (inflict + applyProtections). source: {"id", "name", "kind"}; effects – lista ENAM (min, max,
## duration…); spell – rekord czaru (odporność zależy od szansy rzucającego) albo {}; ignore_resist – mikstury
## nie (Morrowind: trucizny można odeprzeć), własne czary też podlegają odporności (jak OpenMW).
## → {"applied", "resisted", "reflected", "absorbed"}
func inflict(target: Dictionary, caster: Dictionary, source: Dictionary, list: Array, spell := {}, temporary := true, ignore_reflect := false) -> Dictionary:
	var res := {"applied": 0, "resisted": 0, "reflected": false, "absorbed": false}
	if target.is_empty() or list.is_empty() or _combat().is_dead(target):
		return res
	var self_cast: bool = not caster.is_empty() and caster.sid == target.sid
	var entry := {"id": String(source.get("id", "")), "name": String(source.get("name", "")),
		"kind": String(source.get("kind", "spell")), "caster": String(caster.get("sid", "")) if not caster.is_empty() else "",
		"effects": []}
	var harmful := false
	var reflected := []
	# applyProtections (dla każdego efektu osobno): odbicie i pochłonięcie – czary tymczasowe rzucone na innych;
	# rzut k100 dla każdego działającego efektu Odbicia/Pochłonięcia celu po kolei
	var prot := []
	if temporary and not self_cast:
		var fx0 := effects(target)
		if float(fx0.get(str(FX_REFLECT), 0.0)) > 0.0 or float(fx0.get(str(FX_SPELL_ABSORPTION), 0.0)) > 0.0:
			prot = _protection_effects(target)
	for e in list:
		var id := int(e.get("effect", -1))
		var mg := effect(id)
		if mg.is_empty():
			continue
		if _flag(mg, "caster_linked") and caster.is_empty():
			continue
		var can_reflect := not ignore_reflect and not _flag(mg, "unreflectable") and not caster.is_empty()
		var stop := ""
		for x in prot:
			if int(x[0]) == FX_REFLECT and can_reflect and roll100() < float(x[1]):
				stop = "reflect"
				break
			if int(x[0]) == FX_SPELL_ABSORPTION and roll100() < float(x[1]):
				stop = "absorb"
				break
		if stop == "reflect":
			reflected.append(e)
			res["reflected"] = true
			continue
		if stop == "absorb":
			# absorbSpell: magia celu + koszt czaru (zaklęcie przedmiotu – efektywny koszt rzucenia)
			var cost := 0.0
			if not spell.is_empty():
				cost = float(spell_cost(spell))
			elif String(source.get("kind", "")) == "enchantment":
				var en := item_enchantment(main.interaction.inventory.item(String(source.get("id", ""))))
				cost = float(effective_cast_cost(en, caster)) if not en.is_empty() and not caster.is_empty() else 0.0
			adjust_dynamic(target, 1, cost)
			res["absorbed"] = true
			continue
		var src_list: Array = spell.get("effects", list) if not spell.is_empty() else list
		var ae := {"effect": id, "skill": int(e.get("skill", -1)), "attribute": int(e.get("attribute", -1)),
			"min": float(e.get("min", 0)), "max": float(e.get("max", 0)), "duration": float(e.get("duration", 0)),
			"time_left": float(e.get("duration", 0)), "magnitude": 0.0, "applied": false, "index": src_list.find(e)}
		if _flag(mg, "no_magnitude"):
			ae.min = 1.0
			ae.max = 1.0
		if _flag(mg, "no_duration"):            # applyMagicEffects (Lua): bez czasu trwania → 1 s
			ae.duration = 1.0
			ae.time_left = 1.0
		if _flag(mg, "harmful"):
			harmful = true
		# odporności – zawsze (także bez rzucającego: szansa rzucenia 100)
		if has_resistance(id) and not bool(e.get("ignore_resist", false)):
			var mult := 1.0 - effect_resistance(id, target, caster, spell if temporary else {}) / 100.0
			if mult <= 0.0:
				res.resisted += 1
				if target.kind == "player":
					main._toast(_text("sMagicPCResisted", "You resisted the spell."), 2.0)
				elif not caster.is_empty() and caster.kind == "player":
					main._toast(_text("sMagicTargetResisted", "The target resisted the spell."), 2.0)
				continue
			if not _flag(mg, "no_magnitude"):
				ae.min *= mult
				ae.max *= mult
		entry.effects.append(ae)
		res.applied += 1
	if not reflected.is_empty() and not caster.is_empty():
		inflict(caster, target, source, reflected, spell, temporary, true)
	if harmful and not caster.is_empty() and not self_cast and caster.kind == "player" and target.kind != "player":
		_combat()._actor_state(target)["attacked"] = true
		main.on_actor_attacked(target)
	if entry.effects.is_empty():
		return res
	# ActiveSpells::addSpell: nowy czar trafia do kolejki – aktywny od następnego ActiveSpells::update; usuwanie
	# efektów w tej samej klatce (breakInvisibility, leczenie) go nie widzi
	entry["queued_frame"] = Engine.get_process_frames()
	# ActiveSpells::addToSpells: czary i zaklęcia przedmiotów nie kumulują się (Flag_Stackable – tylko mikstury
	# i składniki): ten sam czar od tego samego rzucającego – dołączenie efektów o innych indeksach (merge) albo
	# zastąpienie poprzedniego wystąpienia
	var stackable: bool = bool(source.get("stackable", String(entry.kind) in ["potion", "ingredient"]))
	if not stackable:
		for old in active(target):
			if String(old.get("id", "")) != String(entry.id) or String(old.get("caster", "")) != String(entry.caster) \
					or String(old.get("kind", "")) != String(entry.kind):
				continue
			var idx := {}
			for x in old.effects:
				idx[int(x.get("index", -1))] = true
			var clash := false
			for x in entry.effects:
				if idx.has(int(x.get("index", -1))):
					clash = true
			if not clash:
				old.effects.append_array(entry.effects)
				_tick_entry(target, old, 0.0)
				_cleanup(target)
				sync_dynamic(target)
				return res
			for x in old.effects:
				x.time_left = 0.0
				if not bool(x.get("applied", false)):
					x["applied"] = true
			break
	active(target).append(entry)
	_tick_entry(target, entry, 0.0)
	_cleanup(target)
	sync_dynamic(target)
	return res

## Działające efekty Odbicia / Pochłonięcia celu ([efekt, wielkość]): czary i stałe źródła (zdolności, przedmioty).
func _protection_effects(f: Dictionary) -> Array:
	var out := []
	for sp in active(f):
		for x in sp.effects:
			if bool(x.get("applied", false)) and int(x.effect) in [FX_REFLECT, FX_SPELL_ABSORPTION]:
				out.append([int(x.effect), float(x.get("magnitude", 0.0))])
	var spells: Array = (main.player_stats().get("spells", []) as Array).duplicate() if f.kind == "player" else actor_spells(f).duplicate()
	if f.kind == "npc":
		spells.append_array(records.record("race", String(f.rec.get("race", ""))).get("powers", []))
	for sid in spells:
		var sp2: Dictionary = records.record("spell", String(sid))
		if not sp2.is_empty() and int(sp2.get("spell_type", 0)) in main.character.CONSTANT_TYPES:
			for e in sp2.get("effects", []):
				if int(e.get("effect", -1)) in [FX_REFLECT, FX_SPELL_ABSORPTION]:
					out.append([int(e.effect), float(e.get("min", 0))])
	var eq: Dictionary = _combat().equipment(f)
	for sl in eq:
		var en := item_enchantment({"rec": eq[sl].rec})
		if not en.is_empty() and int(en.get("type", -1)) == ENCH_CONSTANT:
			for e in en.get("effects", []):
				if int(e.get("effect", -1)) in [FX_REFLECT, FX_SPELL_ABSORPTION]:
					out.append([int(e.effect), float(e.get("min", 0))])
	return out

## Jedno przejście applyMagicEffect dla efektu (dt = 0 – nałożenie przy rzuceniu).
func _apply_effect(f: Dictionary, entry: Dictionary, e: Dictionary, dt: float) -> void:
	var id := int(e.effect)
	var mg := effect(id)
	if _should_remove(f, e):
		e.time_left = 0.0
		e.applied = true
		e.magnitude = 0.0
		return
	var once := _flag(mg, "applied_once")
	# applyMagicEffect: Przywołanie, interwencje i Niewidzialność nie działają w chwili nałożenia (dt = 0),
	# dopiero w pierwszej klatce (Morrowind.exe nie stosuje efektów przy otwartym menu)
	if dt == 0.0 and not bool(e.applied) and id in [FX_RECALL, FX_DIVINE, FX_ALMSIVI, FX_INVISIBILITY]:
		return
	if bool(e.applied):
		if once:
			e.time_left = float(e.time_left) - dt
			return
		if dt == 0.0:
			return
	var magnitude := _roll_magnitude(e)
	var amount := magnitude
	if not (_flag(mg, "no_magnitude") or once):
		if float(e.duration) != 0.0:
			amount *= minf(float(e.time_left), dt)
		if amount == 0.0:
			e.applied = true
			e.time_left = float(e.time_left) - dt
			return
	_actor_effect(f, entry, e, amount)
	e.magnitude = magnitude
	e.applied = true
	e.time_left = float(e.time_left) - dt
	if bool(e.get("invalid", false)):
		e.time_left = 0.0                         # Flag_Invalid: mTimeLeft = 0 (usunięte w następnej aktualizacji)

## shouldRemoveEffect: Lewitacja przy wyłączonej lewitacji (DisableLevitation – sLevitateDisabled), Chodzenie po
## wodzie nałożone zbyt głęboko pod wodą (isWaterWalkingCastableOnTarget – sMagicInvalidEffect).
func _should_remove(f: Dictionary, e: Dictionary) -> bool:
	var id := int(e.effect)
	if id == FX_LEVITATE and not levitation_enabled():
		if f.kind == "player" and float(e.get("magnitude", 0.0)) >= 0.0:
			main._toast(_text("sLevitateDisabled", "Levitation is not possible here."), 2.0)
		return true
	if id == FX_WATER_WALKING and not bool(e.get("applied", false)) and not water_walking_castable(f):
		if f.kind == "player":
			main._toast(_text("sMagicInvalidEffect", "This spell cannot be cast."), 2.0)
		return true
	return false

func levitation_enabled() -> bool:
	return main == null or bool(main.state.player.get("levitation_enabled", true))

## World::isWaterWalkingCastableOnTarget: niemożliwe, gdy punkt na wysokości (fSwimHeightScale + 1) × wzrost
## aktora jest pod wodą albo aktor pod wodą nie ma wolnej drogi na powierzchnię.
func water_walking_castable(f: Dictionary) -> bool:
	var n = f.get("node")
	if n == null or not "water_level" in n or float(n.water_level) == -INF:
		return true
	var wl := float(n.water_level)
	var y: float = n.global_position.y
	if y + float(n.height) * (float(n.swim_height_scale) + 1.0) < wl:
		return false
	if y < wl and n.has_method("test_move") and n.test_move(n.global_transform, Vector3.UP * (wl - y)):
		return false
	return true

var _wcache := {}          # sid → [klatka, waga ekwipunku] (bez zapisu)

## Actor::getEncumbrance: waga ekwipunku + Ciężar − Lekkość (≥ 0).
func encumbrance(f: Dictionary, fx := {}) -> float:
	if f.kind == "player":
		return main.player_weight()
	if fx.is_empty():
		fx = effects(f)
	var inv = main.interaction.inventory if main.interaction != null else null
	var w := 0.0
	if inv != null:
		var frame := Engine.get_process_frames()
		var c: Array = _wcache.get(String(f.sid), [-1, 0.0])
		if int(c[0]) == frame:
			w = float(c[1])
		else:
			w = float(inv.total_weight(inv.contents(String(f.sid), f.get("rec", {}))))
			_wcache[String(f.sid)] = [frame, w]
	return maxf(0.0, w - float(fx.get(str(FX_FEATHER), 0.0)) + float(fx.get(str(FX_BURDEN), 0.0)))

## getNormalizedEncumbrance: obciążenie / udźwig (NPC: siła × fEncumbranceStrMult, stworzenie: siła × 5).
func normalized_encumbrance(f: Dictionary, fx := {}) -> float:
	if f.kind == "player":
		var st: Dictionary = main.player_stats()
		return main.character.normalized_encumbrance(st, main.player_weight())
	var w := encumbrance(f, fx)
	if w == 0.0:
		return 0.0
	var strength := float(_combat().attributes(f)[0])
	var cap := strength * (5.0 if f.kind == "creature" else _gmst("fEncumbranceStrMult", 5.0))
	return w / cap if cap > 0.0 else INF

## Npc::getSpeed / Creature::getSpeed przy lewitacji (j./s): fMinFlySpeed + 0,01 × (szybkość + wielkość) ×
## (fMaxFlySpeed − fMinFlySpeed), × (1 − fEncumberedMoveEffect × obciążenie); przeciążony (> 1) – 0.
func fly_speed(f: Dictionary, levitate: float, fx := {}) -> float:
	var enc := normalized_encumbrance(f, fx)
	if enc > 1.0:
		return 0.0
	var speed := float(_combat().attributes(f)[4])
	var x := 0.01 * (speed + levitate)
	x = _gmst("fMinFlySpeed", 5.0) + x * (_gmst("fMaxFlySpeed", 20.0) - _gmst("fMinFlySpeed", 5.0))
	x *= 1.0 - _gmst("fEncumberedMoveEffect", 0.3) * enc
	return maxf(0.0, x)

## Co klatkę: skutki efektów w ruchu aktora (World::isFlying, isSlowFalling, PhysicsSystem – chodzenie po wodzie).
func apply_movement(f: Dictionary, n: Node) -> void:
	if f.is_empty() or n == null or not "levitate" in n:
		return
	var fx := effects(f)
	var dead: bool = f.kind != "player" and _combat().is_dead(f)
	var paralyzed := float(fx.get(str(FX_PARALYZE), 0.0)) > 0.0
	var lev := float(fx.get(str(FX_LEVITATE), 0.0))
	n.levitate = lev > 0.0 and levitation_enabled() and not paralyzed and not dead
	if "can_fly" in n:
		# World::isFlying: martwy albo sparaliżowany nie leci (spada pod wpływem grawitacji)
		n.no_gravity = bool(n.can_fly) and not paralyzed and not dead
	if "inert" in n:
		n.inert = dead or paralyzed
	n.levitate_speed = fly_speed(f, lev, fx) / MWCoords.UNITS_PER_METER if n.levitate else 0.0
	n.slow_fall = 1.0 - clampf(float(fx.get(str(FX_SLOW_FALL), 0.0)) * 0.005, 0.0, 1.0)
	n.water_walk = float(fx.get(str(FX_WATER_WALKING), 0.0)) > 0.0 and bool(n.get("collide"))
	# Światło (Animation::setLightEffect): 1 pkt = 1 stopa promienia (22 j.), zasięg × 3, tylko światło otoczenia
	_light_effect(n, 0.0 if dead else float(fx.get(str(FX_LIGHT), 0.0)))
	# Widzenie w ciemności gracza (setNightEyeFactor)
	if f.kind == "player" and main.envr != null:
		# Player::update: static_cast<int>(wielkość) / 100, maks. 1 (ujemne – bez efektu)
		main.envr.night_eye = minf(1.0, maxf(0.0, float(int(float(fx.get(str(FX_NIGHT_EYE), 0.0))))) / 100.0)
	# Dźwięk na graczu: pętla „magic sound” o głośności wielkość/100 (applyActorMagicEffect / removeMagicEffect)
	if f.kind == "player" and main.audio != null:
		var snd := float(fx.get(str(FX_SOUND), 0.0))
		var on: bool = main.audio.is_playing_on("player", "magic sound")
		if snd > 0.0 and not on:
			main.audio.play_on("player", "magic sound", null, clampf(snd / 100.0, 0.0, 1.0), 1.0, true)
		elif snd <= 0.0 and on:
			main.audio.stop_on("player", "magic sound")

func _light_effect(n: Node, mag: float) -> void:
	var l := n.get_node_or_null("MagicLight") as OmniLight3D
	if mag <= 0.0:
		if l != null:
			l.queue_free()
		return
	if l == null:
		l = OmniLight3D.new()
		l.name = "MagicLight"
		l.light_color = Color(1, 1, 1)
		l.light_energy = 1.5                 # ambient 1,5 (bez światła rozproszonego w OpenMW – przybliżenie)
		l.shadow_enabled = false
		l.position = Vector3(0, 1.0, 0)
		n.add_child(l)
	l.omni_range = mag * ceilf(64.0 / 3.0) * 3.0 / MWCoords.UNITS_PER_METER

## Actors::updateDrowning: pod wodą (punkt 1/fSwimHeightScale wzrostu pod powierzchnią) bez Oddychania pod wodą
## ubywa czasu (fHoldBreathTime), po nim fSuffocationDamage zdrowia na sekundę; poza wodą czas wraca do pełna.
func update_drowning(f: Dictionary, n: Node, dt: float) -> void:
	if f.is_empty() or n == null or not "water_level" in n or dt <= 0.0:
		return
	var h := holder(f)
	if h.is_empty() or (f.kind != "player" and _combat().is_dead(f)):
		return
	var hold := _gmst("fHoldBreathTime", 20.0)
	var wl := float(n.water_level)
	var submerged: bool = wl > -INF and n.global_position.y + float(n.height) / float(n.swim_height_scale) < wl
	if not submerged or magnitude_of(f, FX_WATER_BREATHING) != 0.0:
		h.erase("drown_time")
		return
	var left := maxf(0.0, float(h.get("drown_time", hold)) - dt)
	h["drown_time"] = left
	if left == 0.0:
		adjust_dynamic(f, 0, -_gmst("fSuffocationDamage", 3.0) * dt, true)
		var who := String(f.get("sid", "player"))
		if main.audio != null and not main.audio.is_playing_on(who, "drown"):
			main.audio.play_on(who, "drown", n.global_position if f.kind != "player" else null)
		_check_death(f, {})

func _caster_of(entry: Dictionary) -> Dictionary:
	var sid := String(entry.get("caster", ""))
	if sid.is_empty():
		return {}
	if sid == "player":
		return _combat().player_fighter()
	return main.fighter_by_sid(sid) if main.has_method("fighter_by_sid") else {}

## applyActorMagicEffect – zmiany statystyk.
func _actor_effect(f: Dictionary, entry: Dictionary, e: Dictionary, amount: float) -> void:
	var id := int(e.effect)
	var p := pools(f) if id in [17, 21, 22, 26, 74, 78, 85, 89] else {}
	match id:
		FX_FIRE, FX_SHOCK, FX_FROST, FX_DAMAGE_HEALTH, FX_POISON:
			adjust_dynamic(f, 0, -amount)
		FX_DAMAGE_MAGICKA:
			adjust_dynamic(f, 1, -amount)
		FX_DAMAGE_FATIGUE:
			adjust_dynamic(f, 2, -amount)
		FX_RESTORE_HEALTH:
			adjust_dynamic(f, 0, amount)
		FX_RESTORE_MAGICKA:
			adjust_dynamic(f, 1, amount)
		FX_RESTORE_FATIGUE:
			adjust_dynamic(f, 2, amount)
		FX_DRAIN_HEALTH:
			adjust_dynamic(f, 0, -amount, true)
		FX_DRAIN_MAGICKA:
			adjust_dynamic(f, 1, -amount, true)
		FX_DRAIN_FATIGUE:
			adjust_dynamic(f, 2, -amount, true)
		FX_FORTIFY_HEALTH:
			adjust_dynamic(f, 0, amount, false, true)
		FX_FORTIFY_MAGICKA:
			adjust_dynamic(f, 1, amount, false, true)
		FX_FORTIFY_FATIGUE:
			adjust_dynamic(f, 2, amount, false, true)
		FX_DAMAGE_ATTRIBUTE, FX_DRAIN_ATTRIBUTE:
			var a := int(e.attribute)
			if a >= 0 and a < 8:
				var m := amount
				if id == FX_DAMAGE_ATTRIBUTE:
					m = minf(float(_combat().attributes(f)[a]), amount)
				p.attributes[a] = float(p.attributes[a]) + m
		FX_DAMAGE_SKILL, FX_DRAIN_SKILL:
			var s := int(e.skill)
			if s >= 0 and s < 27 and f.kind != "creature":
				var m2 := amount
				if id == FX_DAMAGE_SKILL:
					m2 = minf(float(_combat().skill(f, s)), amount)
				p.skills[s] = float(p.skills[s]) + m2
		FX_RESTORE_ATTRIBUTE:
			var a2 := int(e.attribute)
			if a2 >= 0 and a2 < 8:
				p.attributes[a2] = maxf(0.0, float(p.attributes[a2]) - amount)
		FX_RESTORE_SKILL:
			var s2 := int(e.skill)
			if s2 >= 0 and s2 < 27:
				p.skills[s2] = maxf(0.0, float(p.skills[s2]) - amount)
		FX_ABSORB_HEALTH, FX_ABSORB_MAGICKA, FX_ABSORB_FATIGUE:
			var stat := id - FX_ABSORB_HEALTH
			adjust_dynamic(f, stat, -amount)
			var c := _caster_of(entry)
			if not c.is_empty():
				adjust_dynamic(c, stat, amount)
		FX_ABSORB_ATTRIBUTE, FX_ABSORB_SKILL:
			var idx := int(e.attribute) if id == FX_ABSORB_ATTRIBUTE else int(e.skill)
			var key := "attributes" if id == FX_ABSORB_ATTRIBUTE else "skills"
			if idx >= 0 and idx < (p[key] as Array).size():
				p[key][idx] = float(p[key][idx]) + amount
				var c2 := _caster_of(entry)
				if not c2.is_empty():           # fortifyAttribute/Skill rzucającego: modyfikator (poza mapą efektów)
					_mod_adjust(c2, key, idx, amount)
					e["caster_sid"] = String(c2.sid) if c2.kind != "player" else "player"
		FX_SUN_DAMAGE:
			# tylko na zewnątrz: wielkość × clamp(max(widoczność słońca × wschód, fMagicSunBlockedMult × wschód))
			if main.interior.is_empty() or (main.envr != null and not bool(main.envr.interior)):
				var risen: float = main.envr.wm.sun_percentage(float(main.envr.game_hour)) if main.envr != null else 0.0
				var vis: float = main.envr.wm.glare_view() if main.envr != null else 0.0
				var scale := clampf(maxf(vis * risen, _gmst("fMagicSunBlockedMult", 0.5) * risen), 0.0, 1.0)
				adjust_dynamic(f, 0, -amount * scale)
		FX_CURE_CORPRUS:
			_purge_effect(f, FX_CORPRUS)
			_cure_corprus_store(f)
		FX_CURE_POISON:
			_purge_effect(f, FX_POISON)
		FX_CURE_PARALYZATION:
			_purge_effect(f, FX_PARALYZE)
		FX_CURE_COMMON, FX_CURE_BLIGHT, FX_REMOVE_CURSE:
			_purge_permanent(f, {FX_CURE_COMMON: 3, FX_CURE_BLIGHT: 2, FX_REMOVE_CURSE: 4}[id])
		FX_DISPEL:
			for sp in active(f):
				if sp != entry and String(sp.get("kind", "")) == "spell" and roll100() < amount:
					for x in sp.effects:
						x.time_left = 0.0
		FX_DISINTEGRATE_WEAPON, FX_DISINTEGRATE_ARMOR:
			_disintegrate(f, id == FX_DISINTEGRATE_WEAPON, amount)
		FX_MARK, FX_RECALL:
			# DisableTeleporting (World::isTeleportingEnabled): Znakowanie/Przywołanie nie działają, komunikat
			if f.kind == "player" and not bool(main.state.player.get("teleport_enabled", true)):
				main._toast(main.dialogue.gmst_text("sTeleportDisabled", "Teleportation is not possible here.") if main.dialogue != null else "")
			elif id == FX_MARK and f.kind == "player":
				# Player::markPosition: komórka i pozycja z obrotem (Recall – ActionTeleport do tej pozycji)
				main.state.player["mark"] = {"interior": main.interior, "pos": main.position_string(),
					"rot": rad_to_deg(-main.player.rotation.y)}
			elif id == FX_RECALL and f.kind == "player" and main.state.player.get("mark") is Dictionary and main.has_method("recall_to_mark"):
				main.recall_to_mark()
		FX_DIVINE, FX_ALMSIVI:
			# tylko gracz (applyActorMagicEffect); teleportToClosestMarker „divinemarker”/„templemarker”
			if f.kind == "player":
				if not bool(main.state.player.get("teleport_enabled", true)):
					main._toast(_text("sTeleportDisabled", "Teleportation is not possible here."))
				elif main.crime != null:
					main.crime.teleport_to_marker("divinemarker" if id == FX_DIVINE else "templemarker")
		49, 50, 51, 52, 53, 54, 55, 56:
			# modifyAiSetting: nie na gracza; wariant „Creature” tylko dla stworzeń, „Humanoid” – dla NPC
			var spec: Array = AI_EFFECTS[id]
			if f.kind == "player" or bool(spec[2]) != (f.kind == "creature"):
				e["invalid"] = true
			else:
				_ai_mod(f, String(spec[0]), float(spec[1]) * amount)
				if id in [49, 50] and amount > 0.0 and main.ai != null and f.get("node") != null:
					main.ai.stop_combat(f.node)         # Calm: getAiSequence().stopCombat()
		FX_TURN_UNDEAD:
			# tylko nieumarli (Creature::Undead = 2): ucieczka + wielkość
			if f.kind != "creature" or int(f.rec.get("creature_type", -1)) != 2:
				e["invalid"] = true
			else:
				_ai_mod(f, "flee", amount)
		FX_COMMAND_CREATURE, FX_COMMAND_HUMANOID:
			# rzucający aktor, cel nie gracz, rodzaj zgodny, wielkość ≥ poziom celu → AiFollow(rzucający, rozkaz)
			var c3 := _caster_of(entry)
			var lvl := float(main.scripts.stats().get_level(f)) if main.scripts != null else float(f.rec.get("level", 1))
			if c3.is_empty() or f.kind == "player" or (id == FX_COMMAND_HUMANOID) != (f.kind == "npc"):
				e["invalid"] = true
			elif amount >= lvl and main.ai != null and f.get("node") != null:
				main.ai.stack(f.node, {"type": "follow", "target": "player" if c3.kind == "player" else String(c3.base),
					"duration": 0, "commanded": true})
		FX_CHARM:
			if f.kind != "npc":
				e["invalid"] = true
		126:
			# ExtraSpell: tylko aktorzy z ekwipunkiem (NPC); gracz – bez zmian (rozbieranie – MWCombat.equipment)
			if f.kind == "creature" and (int(f.rec.get("flags", 0)) & 4) == 0:   # hasInventoryStore (broń i tarcza)
				e["invalid"] = true
		102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 134, 137, 138, 139, 140, 141, 142:
			e["actor"] = summon_creature(id, f)
		_:
			if BOUND_ITEMS.has(id):
				_bound_item(f, id, true)
			elif LATER.has(id):
				unsupported[LATER[id]] = int(unsupported.get(LATER[id], 0)) + 1
	if id in [FX_FIRE, FX_SHOCK, FX_FROST, FX_DAMAGE_HEALTH, FX_POISON, FX_DRAIN_HEALTH, FX_ABSORB_HEALTH, FX_SUN_DAMAGE]:
		_check_death(f, entry)

## removeMagicEffect – cofnięcie efektów jednorazowych po wygaśnięciu.
func _remove_effect(f: Dictionary, e: Dictionary) -> void:
	if not bool(e.get("applied", false)) or bool(e.get("invalid", false)):
		return
	var id := int(e.effect)
	var m := float(e.get("magnitude", 0.0))
	match id:
		FX_DRAIN_HEALTH:
			adjust_dynamic(f, 0, m)
		FX_DRAIN_MAGICKA:
			adjust_dynamic(f, 1, m)
		FX_DRAIN_FATIGUE:
			adjust_dynamic(f, 2, m)
		FX_FORTIFY_HEALTH:
			adjust_dynamic(f, 0, -m, true)
			_check_death(f, {})
		FX_FORTIFY_MAGICKA:
			adjust_dynamic(f, 1, -m, true)
		FX_FORTIFY_FATIGUE:
			adjust_dynamic(f, 2, -m, true)
		FX_DRAIN_ATTRIBUTE:
			var p := pools(f)
			var a := int(e.attribute)
			if a >= 0 and a < 8:
				p.attributes[a] = maxf(0.0, float(p.attributes[a]) - m)
		FX_DRAIN_SKILL:
			var p2 := pools(f)
			var s := int(e.skill)
			if s >= 0 and s < 27:
				p2.skills[s] = maxf(0.0, float(p2.skills[s]) - m)
		FX_ABSORB_ATTRIBUTE, FX_ABSORB_SKILL:
			# removeMagicEffect: przywrócenie celu i cofnięcie modyfikatora rzucającego
			var key3 := "attributes" if id == FX_ABSORB_ATTRIBUTE else "skills"
			var i3 := int(e.attribute) if id == FX_ABSORB_ATTRIBUTE else int(e.skill)
			var p3 := pools(f)
			if i3 >= 0 and i3 < (p3[key3] as Array).size():
				p3[key3][i3] = maxf(0.0, float(p3[key3][i3]) - m)
			var csid := String(e.get("caster_sid", ""))
			if not csid.is_empty():
				var cf: Dictionary = _combat().player_fighter() if csid == "player" else _combat().fighter_of(_node_by_sid(csid))
				if not cf.is_empty():
					_mod_adjust(cf, key3, i3, -m)
		49, 50, 51, 52, 53, 54, 55, 56:
			var spec: Array = AI_EFFECTS[id]
			_ai_mod(f, String(spec[0]), -float(spec[1]) * m)
		FX_TURN_UNDEAD:
			_ai_mod(f, "flee", -m)
		102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 134, 137, 138, 139, 140, 141, 142:
			cleanup_summon(f, String(e.get("actor", "")))
		FX_COMMAND_CREATURE, FX_COMMAND_HUMANOID:
			# removeMagicEffect: gdy łączna wielkość ≤ 0 – usunięcie rozkazanych AiFollow
			if magnitude_of(f, id) - m <= 0.0 and main.ai != null and f.get("node") != null:
				var st: Dictionary = main.ai.ai_state(f.node)
				st.packages = (st.packages as Array).filter(func(x):
					return not (String(x.get("type", "")) == "follow" and bool(x.get("commanded", false))))
		_:
			if BOUND_ITEMS.has(id):
				_bound_item(f, id, false)

## Modyfikator ustawienia AI aktora (Stat<int>::mModifier; GetFight itd. – podstawa + modyfikator).
func _ai_mod(f: Dictionary, setting: String, delta: float) -> void:
	var h := holder(f)
	if not h.get("ai_mod") is Dictionary:
		h["ai_mod"] = {}
	h.ai_mod[setting] = int(h.ai_mod.get(setting, 0)) + int(delta)
	if int(h.ai_mod[setting]) == 0:
		h.ai_mod.erase(setting)
	if (h.ai_mod as Dictionary).is_empty():
		h.erase("ai_mod")

## summonCreature: stworzenie z GMST efektu (dane gry/modów) umieszczone 120 j. przed przywołującym
## (safePlaceObject – bez wolnego miejsca: w miejscu przywołującego), AiFollow za przywołującym; → sid stworzenia
## (referencja dynamiczna: zapis, zmiana komórki z przywołującym przez drzwi) albo "" (nie udało się).
func summon_creature(id: int, summoner: Dictionary) -> String:
	var cid := String(records.record("gmst", String(SUMMONS[id]).to_lower()).get("value", "")).to_lower()
	var n = summoner.get("node")
	if cid.is_empty() or records.record("creature", cid).is_empty() or n == null or not is_instance_valid(n):
		return ""
	var pos := MWCoords.godot_to_mw(n.global_position)
	var rz := -float(n.rotation.y)
	var fwd := Vector3(sin(rz), cos(rz), 0.0)
	var place := pos + fwd * 120.0
	var space: PhysicsDirectSpaceState3D = n.get_world_3d().direct_space_state if n.is_inside_tree() else null
	if space != null:
		var from: Vector3 = n.global_position + Vector3.UP * 0.9
		var q := PhysicsRayQueryParameters3D.create(from, MWCoords.mw_to_godot(place) + Vector3.UP * 0.9)
		q.exclude = [n.get_rid()]
		if not space.intersect_ray(q).is_empty():
			place = pos                          # safePlaceObject: przeszkoda – w miejscu przywołującego
	var key: String = ("int:" + String(main.interior).to_lower()) if not String(main.interior).is_empty() \
			else String(main.db.exterior_key(MWCoords.cell_of(MWCoords.mw_to_godot(place))))
	var sid: String = main.state.add_dynamic(cid, key, place, Vector3(0, 0, rz), 1)
	var cn = _node_by_sid(sid)
	if cn != null and main.ai != null:
		var target := "player" if summoner.kind == "player" else String(summoner.base)
		main.ai.stack(cn, {"type": "follow", "target": target, "duration": 0, "summoned": true})
	var h := holder(summoner)
	if not h.get("summons") is Dictionary:
		h["summons"] = {}
	h.summons[sid] = id
	return sid

## cleanupSummonedCreature: usunięcie przywołanego stworzenia (koniec efektu, śmierć przywołującego).
func cleanup_summon(summoner: Dictionary, sid: String) -> void:
	if sid.is_empty():
		return
	purge_caster(sid)                          # Actors::cleanupSummonedCreature → purgeSpellEffects
	var h := holder(summoner)
	if h.get("summons") is Dictionary:
		h.summons.erase(sid)
		if (h.summons as Dictionary).is_empty():
			h.erase("summons")
	if main.state.dynamic.has(sid):
		main.state.remove_dynamic(sid)
	if main.state.get("actors") is Dictionary:
		main.state.actors.erase(sid)

## updateSummons: martwe przywołane stworzenie – efekt usunięty (można przywołać ponownie), ciało znika.
func _update_summons(f: Dictionary) -> void:
	var h := holder(f)
	if not h.get("summons") is Dictionary:
		return
	for sid in (h.summons as Dictionary).keys():
		var st = main.state.actors.get(sid) if main.state.get("actors") is Dictionary else null
		var gone: bool = not main.state.dynamic.has(sid)
		if gone or (st is Dictionary and bool(st.get("dead", false))):
			for sp in active(f):
				for x in sp.effects:
					if String(x.get("actor", "")) == sid:
						x.time_left = 0.0

func _node_by_sid(sid: String) -> Node:
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for c in refs.get_children():
			if String(c.get_meta("mw_sid", "")) == sid:
				return c
	return null

## ActiveSpells::clear po śmierci (Actors::killDeadActors): wszystkie czary aktora usunięte z cofnięciem
## skutków (m.in. przywołane stworzenia znikają, rozkazy wygasają).
func clear_on_death(f: Dictionary) -> void:
	var list := active(f)
	for sp in list.duplicate():
		for x in sp.effects:
			_remove_effect(f, x)
	list.clear()

## Actors::purgeSpellEffects: czary rzucone przez aktora (zmarłego po animacji śmierci, usuniętego przywołania)
## znikają z działających czarów gracza i aktorów wczytanych komórek – z cofnięciem skutków (np. Pochłanianie
## wraca do celu od razu, nie po czasie trwania).
func purge_caster(caster_sid: String) -> void:
	if caster_sid.is_empty() or main == null:
		return
	var targets: Array = [_combat().player_fighter()]
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			var nsid := String(n.get_meta("mw_sid", ""))
			var st = main.state.actors.get(nsid) if main.state.get("actors") is Dictionary else null
			# tylko aktorzy z działającymi czarami (bez tworzenia stanu pozostałym)
			if n.has_meta("mw_actor") and nsid != caster_sid and st is Dictionary \
					and not (st.get("active_spells", []) as Array).is_empty():
				targets.append(_combat().fighter_of(n))
	for t in targets:
		if t.is_empty():
			continue
		var list := active(t)
		for sp in list.duplicate():
			if String(sp.get("caster", "")) == caster_sid:
				for x in sp.effects:
					_remove_effect(t, x)
				list.erase(sp)

## getStuntedMagickaDuration: −1 – stałe źródło (zdolność, przedmiot), inaczej najdłuższy pozostały czas (s).
func stunted_magicka_remaining(f: Dictionary) -> float:
	if magnitude_of(f, FX_STUNTED_MAGICKA) <= 0.0:
		return 0.0
	var rem := 0.0
	var any := false
	for sp in active(f):
		for x in sp.effects:
			if int(x.effect) == FX_STUNTED_MAGICKA:
				any = true
				rem = maxf(rem, float(x.time_left))
	return rem if any else -1.0

## World::listDetectedReferences: obiekty aktywnych komórek w promieniu wielkość × 22 j. (feetToGameUnits) od gracza:
## „creature” – żywe stworzenia (wilkołak: NPC), „key” – klucze, „enchantment” – przedmioty zaklęte; pojemniki
## i aktorzy z takim przedmiotem w inwentarzu też (AddDetectedReferenceVisitor). → węzły.
const DETECT_EFFECT := {"creature": 64, "enchantment": 65, "key": 66}

func detected_references(kind: String) -> Array:
	var out := []
	if main == null or main.player == null or not DETECT_EFFECT.has(kind):
		return out
	var dist := magnitude_of(_combat().player_fighter(), int(DETECT_EFFECT[kind]))
	if dist <= 0.0:
		return out
	dist *= ceilf(64.0 / 3.0)
	var pp := MWCoords.godot_to_mw(main.player.global_position)
	var werewolf := bool(main.player_stats().get("werewolf", false))
	var inv = main.interaction.inventory if main.interaction != null else null
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.has_meta("mw_base") or not (n is Node3D) or not (n as Node3D).visible:
				continue
			if MWCoords.godot_to_mw((n as Node3D).global_position).distance_squared_to(pp) > dist * dist:
				continue
			var base := String(n.get_meta("mw_base")).to_lower()
			var sid := String(n.get_meta("mw_sid", ""))
			var actor_kind := String(n.get_meta("mw_actor", ""))
			if kind == "creature":
				if actor_kind == ("npc" if werewolf else "creature") and not _combat().is_dead(_combat().fighter_of(n)):
					out.append(n)
				continue
			if inv == null:
				continue
			if _detect_item(inv.item(base), kind):
				out.append(n)
				continue
			var crec: Dictionary = {}
			if actor_kind != "":
				crec = _combat().fighter_of(n).get("rec", {})
			elif not records.record("container", base).is_empty():
				crec = records.record("container", base)
			else:
				continue
			for e in inv.contents(sid, crec):
				if _detect_item(inv.item(String(e.id)), kind):
					out.append(n)
					break
	return out

func _detect_item(it: Dictionary, kind: String) -> bool:
	if it.is_empty():
		return false
	if kind == "key":
		return String(it.kind) == "misc" and bool(it.rec.get("key", false))
	return not String(it.rec.get("enchant", "")).is_empty()

## World::breakInvisibility: usuwa Niewidzialność (atak, rzucanie, użycie przedmiotu, wypicie, alchemia…).
func break_invisibility(f: Dictionary) -> void:
	if f.is_empty():
		return
	var any := false
	var frame := Engine.get_process_frames()
	for sp in active(f):
		if int(sp.get("queued_frame", -1)) == frame:
			continue
		for x in sp.effects:
			if int(x.effect) == FX_INVISIBILITY and float(x.time_left) > 0.0:
				x.time_left = 0.0
				any = true
	if any:
		_cleanup(f)

func _check_death(f: Dictionary, entry: Dictionary) -> void:
	var cb = _combat()
	if float(cb.health(f)) <= 0.0 and not cb.is_dead(f):
		var c := _caster_of(entry) if not entry.is_empty() else {}
		main.on_actor_died(f, c)

func _purge_effect(f: Dictionary, fx_id: int) -> void:
	var frame := Engine.get_process_frames()
	for sp in active(f):
		if int(sp.get("queued_frame", -1)) == frame:
			continue
		for x in sp.effects:
			if int(x.effect) == fx_id:
				x.time_left = 0.0

## removeMagicEffect(Corprus) dla trwałego czaru: pogorszenia efektów szkodliwych cofnięte (tyle razy, ile było),
## potem wszystkie efekty czaru usunięte raz (Wyssanie wraca; Uszkodzenie i nadwyżka Wzmocnień z pogorszeń
## zostają – jak w OpenMW), czar zostaje bez efektów.
func _cure_corprus_store(f: Dictionary) -> void:
	_sync_spell_store(f)
	var h := holder(f)
	var store: Dictionary = h.get("spell_store", {}) if h.get("spell_store") is Dictionary else {}
	for sid in store.keys():
		var rec: Dictionary = store[sid]
		if not rec.has("worsen") or bool(rec.get("cured", false)):
			continue
		for ae in rec.get("worse_applied", []) + rec.get("applied", []):
			if int(ae.effect) in [17, 18, 19, 20, 21]:
				ae["applied"] = true
				_remove_effect(f, ae)
		rec["cured"] = true

## Leczenie chorób i klątw: usuwa z listy czarów gracza rodzaje 2 (zaraza), 3 (choroba), 4 (klątwa).
func _purge_permanent(f: Dictionary, spell_type: int) -> void:
	if f.kind != "player":
		# NPC/stworzenie: lista zaklęć aktora w stanie (jak po RemoveSpell) bez chorób/klątw danego rodzaju
		var own: Array = actor_spells(f).filter(func(x):
			return int(records.record("spell", String(x).to_lower()).get("spell_type", 0)) != spell_type)
		if own.size() != actor_spells(f).size():
			var ast: Dictionary = _combat()._actor_state(f)
			ast["spells"] = own
		return
	var st: Dictionary = main.player_stats()
	st["spells"] = (st.get("spells", []) as Array).filter(func(s):
		return int(records.record("spell", String(s)).get("spell_type", 0)) != spell_type)

## disintegrateSlot: stan przedmiotu całkowity (CellRef charge), ułamek wielkości zbierany jak
## applyChargeRemainderToBeSubtracted; przedmiot o stanie 0 pomijany (następny slot pancerza), zniszczony –
## gracz zdejmuje (NPC: stan trzymany per slot, bez ponownego autoEquip – zależność od stanu przedmiotów NPC).
var _charge_rem := {}

func _disintegrate(f: Dictionary, weapon: bool, amount: float) -> void:
	var cb = _combat()
	var eq: Dictionary = cb.equipment(f)
	var slots := [cb.EQ.SLOT_CARRIED_RIGHT] if weapon else [cb.EQ.SLOT_CARRIED_LEFT, cb.EQ.SLOT_CUIRASS,
		cb.EQ.SLOT_LEFT_PAULDRON, cb.EQ.SLOT_RIGHT_PAULDRON, cb.EQ.SLOT_LEFT_GAUNTLET, cb.EQ.SLOT_RIGHT_GAUNTLET,
		cb.EQ.SLOT_HELMET, cb.EQ.SLOT_GREAVES, cb.EQ.SLOT_BOOTS]
	for s in slots:
		var it: Dictionary = eq.get(s, {})
		if it.is_empty() or float(it.rec.get("health", 0)) <= 0.0 or not (it.kind == "weapon" or it.kind == "armor"):
			continue
		var charge := int(cb.item_health(it))
		if charge == 0:
			continue
		var key := "%s:%d" % [String(f.get("sid", "player")) if f.kind != "player" else "player", s]
		var rem: float = float(_charge_rem.get(key, 0.0)) - absf(amount - floorf(amount))
		if rem <= -1.0:
			var whole := ceilf(rem)                  # modf: część całkowita (ujemna)
			charge = maxi(0, charge + int(whole))
			rem -= whole
		_charge_rem[key] = rem
		charge -= mini(int(amount), charge)
		cb._set_item_health(f, s, float(charge))
		if charge == 0 and f.kind == "player":
			main.unequip_slot(s)
		return

func _bound_item(f: Dictionary, id: int, add: bool) -> void:
	var inv = main.interaction.inventory
	var sid := "player" if f.kind == "player" else String(f.sid)
	for g in BOUND_ITEMS[id]:
		var item_id := String(records.record("gmst", String(g).to_lower()).get("value", "")).to_lower()
		if item_id.is_empty() or not inv.is_item(item_id):
			continue
		if add:
			inv.add(sid, f.rec, item_id, 1)
			if f.kind == "player":
				main.equip_item(item_id, false)      # addBoundItem: ActionEquip (bez rozwiązywania kolizji okna)
			else:
				var slots: Array = main.item_slots(item_id) if main.has_method("item_slots") else []
				if not slots.is_empty():
					var st: Dictionary = _combat()._actor_state(f)
					if not st.get("equip_override") is Dictionary:
						st["equip_override"] = {}
					var sl: int = int(slots[0])
					if slots.size() > 1 and st.equip_override.has(str(slots[0])) and not st.equip_override.has(str(slots[1])):
						sl = int(slots[1])
					st.equip_override[str(sl)] = item_id
		else:
			if f.kind != "player":
				var st2: Dictionary = _combat()._actor_state(f)
				if st2.get("equip_override") is Dictionary:
					for k in (st2.equip_override as Dictionary).keys():
						if String(st2.equip_override[k]) == item_id:
							st2.equip_override.erase(k)
			if f.kind == "player":
				var slot: int = main.equipped_slot_of(item_id)
				if slot >= 0:
					main.unequip_slot(slot)
			inv.remove(sid, f.rec, item_id, 1)

func _tick_entry(f: Dictionary, entry: Dictionary, dt: float) -> void:
	for e in entry.effects:
		_apply_effect(f, entry, e, dt)

func _cleanup(f: Dictionary) -> void:
	var list := active(f)
	for sp in list.duplicate():
		var keep := []
		for e in sp.effects:
			if bool(e.get("applied", false)) and float(e.time_left) <= 0.0:
				_remove_effect(f, e)
			else:
				keep.append(e)
		sp.effects = keep
		if keep.is_empty():
			list.erase(sp)

## Co klatkę: działające czary, ciągłe efekty stałych źródeł (zdolności, zaklęcia przedmiotów) – np. regeneracja.
func tick(f: Dictionary, dt: float) -> void:
	if f.is_empty() or _combat().is_dead(f):
		return
	var list := active(f)
	for sp in list.duplicate():
		_tick_entry(f, sp, dt)
	_tick_constant(f, dt)
	if has_spell_store(f):
		_sync_spell_store(f)
	_update_summons(f)
	_cleanup(f)
	sync_dynamic(f)

## Zmiana maksimum magii/kondycji (atrybuty, wzmocnienie maks. magii, ekwipunek) zachowuje stosunek wartości
## bieżącej do maksymalnej – CreatureStats::setAttribute / recalculateMagicka.
func sync_dynamic(f: Dictionary) -> void:
	var h := holder(f)
	var cb = _combat()
	for k in [["magicka", "_max_magicka"], ["fatigue", "_max_fatigue"]]:
		var mx: float = max_magicka(f) if k[0] == "magicka" else float(cb.max_fatigue(f))
		var old := float(h.get(k[1], -1.0))
		if old > 0.0 and absf(mx - old) > 0.0001 and h.has(k[0]):
			h[k[0]] = float(h[k[0]]) * mx / old
		h[k[1]] = mx

const CONSTANT_TICK := [14, 15, 16, 23, 24, 25, 27, 75, 76, 77, 135]

## Czy aktor ma stałe źródło efektu działającego co klatkę (zdolność, stałe zaklęcie ekwipunku – np. regeneracja,
## obrażenia od słońca wampira): wtedy tick także bez działających czarów (Actors::updateActor dla każdego aktora).
func has_constant_tick(f: Dictionary) -> bool:
	if f.is_empty() or f.kind == "player":
		return false
	var key := String(f.get("base", ""))
	var own_list: bool = main.state.actors.get(String(f.sid), {}).has("spells")
	var any := false
	if _const_tick_cache.has(key) and not own_list:
		any = bool(_const_tick_cache[key])
	else:
		for sid in actor_spells(f):
			var sp: Dictionary = records.record("spell", String(sid))
			if not sp.is_empty() and int(sp.get("spell_type", 0)) in main.character.CONSTANT_TYPES:
				for e in sp.get("effects", []):
					if int(e.get("effect", -1)) in CONSTANT_TICK:
						any = true
		if not own_list:
			_const_tick_cache[key] = any
	if not any:
		var eq: Dictionary = _combat().equipment(f)
		for s in eq:
			var en := item_enchantment({"rec": eq[s].rec})
			if not en.is_empty() and int(en.get("type", -1)) == ENCH_CONSTANT:
				for e in en.get("effects", []):
					if int(e.get("effect", -1)) in CONSTANT_TICK:
						any = true
	return any

var _const_tick_cache := {}

func _tick_constant(f: Dictionary, dt: float) -> void:
	if dt <= 0.0:
		return
	var src := []
	var mags := []
	var hold := holder(f)
	var spells: Array = main.player_stats().get("spells", []) if f.kind == "player" else actor_spells(f)
	for sid in spells:
		var sp: Dictionary = records.record("spell", String(sid))
		if not sp.is_empty() and int(sp.get("spell_type", 0)) in main.character.CONSTANT_TYPES \
				and not spell_store_cured(hold, String(sid)):
			var ei := 0
			for e in sp.get("effects", []):
				src.append(e)
				mags.append(spell_store_magnitude(hold, String(sid), ei, e))
				ei += 1
	var eq: Dictionary = _combat().equipment(f)
	for s in eq:
		var en := item_enchantment({"rec": eq[s].rec})
		if not en.is_empty() and int(en.get("type", -1)) == ENCH_CONSTANT:
			for e in en.get("effects", []):
				src.append(e)
				mags.append(float(e.get("min", 0)))
	for k in src.size():
		var e: Dictionary = src[k]
		var id := int(e.get("effect", -1))
		if id in CONSTANT_TICK:
			var ae := {"effect": id, "skill": int(e.get("skill", -1)), "attribute": int(e.get("attribute", -1)),
				"min": float(e.get("min", 0)), "max": float(e.get("max", 0)), "duration": 0.0, "time_left": 0.0}
			_actor_effect(f, {"caster": ""}, ae, float(mags[k]) * dt)

## Ładowanie przedmiotów gracza (Recharge: fMagicItemRechargePerSecond × czas, do pełnego ładunku).
func recharge(st: Dictionary, seconds: float) -> void:
	var ch: Dictionary = st.get("item_charge", {})
	var rate := _gmst("fMagicItemRechargePerSecond", 0.05)
	for id in ch.keys():
		var it: Dictionary = main.interaction.inventory.item(String(id))
		var en := item_enchantment(it)
		if en.is_empty():
			ch.erase(id)
			continue
		ch[id] = minf(float(ch[id]) + rate * seconds, float(enchantment_charge(en)))

func _text(gm: String, def: String) -> String:
	return main.dialogue.gmst_text(gm, def) if main != null and main.dialogue != null else def

# --- rzucanie zaklęć ---------------------------------------------------------------------------------------

static func by_range(list: Array, rt: int) -> Array:
	return list.filter(func(e): return int(e.get("range", 0)) == rt)

func _fail_sound(school: int) -> void:
	if main == null or main.audio == null:
		return
	var names := {11: "alteration", 13: "conjuration", 10: "destruction", 12: "illusion", 14: "mysticism", 15: "restoration"}
	main.audio.play("Spell Failure " + String(names.get(school, "alteration")).capitalize())

## Rzucenie zaklęcia lub mocy (CastSpell::cast(Spell); magia pobierana przy rozpoczęciu rzucania – jak
## CharacterController). touch – walczący w zasięgu dotyku (albo {}). Efekty „cel” zwracane w "bolt" (pocisk
## tworzy main.launch_bolt). → {"success", "chance", "cost", "school", "message", "bolt", "source", "spell"}
func cast_spell(caster: Dictionary, spell_id: String, touch := {}, roll := -1) -> Dictionary:
	var sp: Dictionary = records.record("spell", spell_id.to_lower())
	if sp.is_empty():
		return {"success": false, "message": "Unknown spell."}
	var typ := int(sp.get("spell_type", 0))
	if typ != SPELL_SPELL and typ != SPELL_POWER:
		return {"success": false, "message": _text("sMagicInvalidEffect", "This spell cannot be cast.")}
	var cost := spell_cost(sp) if typ == SPELL_SPELL else 0
	var base := spell_base_chance(sp, caster)
	var school := int(base.school)
	if typ == SPELL_SPELL and magicka(caster) < float(cost):
		return {"success": false, "cost": cost, "message": _text("sMagicInsufficientSP", "You do not have enough magicka.")}
	if typ == SPELL_POWER and not can_use_power(caster, spell_id):
		return {"success": false, "message": _text("sPowerAlreadyUsed", "You have already used this power today.")}
	break_invisibility(caster)               # CharacterController: rzucanie (także nieudane) zdejmuje niewidzialność
	if cost > 0:
		set_magicka(caster, magicka(caster) - float(cost))
	var chance := spell_chance(sp, caster, true, false)
	var r := roll if roll >= 0 else roll100()
	if float(r) >= chance:
		_fail_sound(school)
		return {"success": false, "chance": chance, "cost": cost, "school": school,
			"message": _text("sMagicSkillFail", "You failed to cast the spell.")}
	if typ == SPELL_POWER:
		var h := holder(caster)
		if not h.get("powers_used") is Dictionary:
			h["powers_used"] = {}
		h.powers_used[spell_id.to_lower()] = _now_hours()
	if caster.kind == "player":
		main.skill_used(school, "spellcast")
	var src := {"id": spell_id.to_lower(), "name": String(sp.get("name", spell_id)), "kind": "spell"}
	var list: Array = sp.get("effects", [])
	inflict(caster, caster, src, by_range(list, RT_SELF), sp)
	if not touch.is_empty():
		inflict(touch, caster, src, by_range(list, RT_TOUCH), sp)
	return {"success": true, "chance": chance, "cost": cost, "school": school, "bolt": by_range(list, RT_TARGET),
		"source": src, "spell": sp, "message": ""}

## Trafienie pociskiem czaru (efekty „cel”) – walczący trafiony; obszar obsługuje main (explode).
func bolt_hit(caster: Dictionary, target: Dictionary, source: Dictionary, list: Array, spell := {}) -> Dictionary:
	return inflict(target, caster, source, list, spell)

# --- mikstury i składniki ----------------------------------------------------------------------------------

## Wypicie mikstury (CastSpell::cast(Potion)): wszystkie efekty na pijącego, bez względu na zasięg.
func drink(f: Dictionary, id: String) -> Dictionary:
	var it: Dictionary = main.interaction.inventory.item(id)
	if it.is_empty() or it.kind != "potion":
		return {"success": false}
	var sid := "player" if f.kind == "player" else String(f.sid)
	if main.interaction.inventory.remove(sid, f.rec, it.id, 1) <= 0:
		return {"success": false}
	break_invisibility(f)                    # Actor::consume: breakInvisibility po udanym rzuceniu
	var r := inflict(f, f, {"id": it.id, "name": String(it.rec.get("name", it.id)), "kind": "potion"}, it.rec.get("effects", []))
	if main.audio != null and f.kind == "player":
		main.audio.play("Drink")
	r["success"] = true
	return r

## rollIngredientEffect: pierwszy efekt składnika; x = (alchemia + 0,2 int + 0,1 szczęście) × zmęczenie;
## rzut > x – brak efektu; czas = rzut/min(x,100) × 0,25x, wielkość z kosztu bazowego.
func ingredient_effect(f: Dictionary, rec: Dictionary, roll := -1) -> Dictionary:
	var list: Array = rec.get("effects", [])
	if list.is_empty():
		return {}
	var e: Dictionary = (list[0] as Dictionary).duplicate()
	var mg := effect(int(e.get("effect", -1)))
	if mg.is_empty():
		return {}
	var at: Array = _combat().attributes(f)
	var x := (float(_combat().skill(f, SK_ALCHEMY)) + 0.2 * float(at[A_INTELLIGENCE]) + 0.1 * float(at[A_LUCK])) \
		* float(_combat().fatigue_term(f))
	var r := roll if roll >= 0 else roll100()
	if float(r) > x:
		return {}
	var y := float(r) / minf(x, 100.0)
	y *= 0.25 * x
	var dur := 1 if _flag(mg, "no_duration") else int(y)
	var mag := 1.0
	if not _flag(mg, "no_magnitude"):
		var bc := float(mg.get("base_cost", 1.0))
		mag = floorf((0.05 * y) / (0.1 * bc)) if not _flag(mg, "no_duration") else floorf(y / (0.1 * bc))
		mag = maxf(1.0, mag)
	e["duration"] = dur
	e["min"] = int(mag)
	e["max"] = int(mag)
	e["range"] = RT_SELF
	e["area"] = 0
	return e

## Zjedzenie składnika (ActionEat): umiejętność alchemii (użycie), efekt wg rollIngredientEffect.
func eat(f: Dictionary, id: String, roll := -1) -> Dictionary:
	var it: Dictionary = main.interaction.inventory.item(id)
	if it.is_empty() or it.kind != "ingredient":
		return {"success": false}
	var sid := "player" if f.kind == "player" else String(f.sid)
	if main.interaction.inventory.remove(sid, f.rec, it.id, 1) <= 0:
		return {"success": false}
	if f.kind == "player":
		main.skill_used(SK_ALCHEMY, "alchemy_use")
	var e := ingredient_effect(f, it.rec, roll)
	if e.is_empty():
		var msg := _text("sNotifyMessage50", "%s has no effect on you.").replace("%s", String(it.rec.get("name", it.id)))
		return {"success": true, "effect": {}, "message": msg}
	break_invisibility(f)
	inflict(f, f, {"id": it.id, "name": String(it.rec.get("name", it.id)), "kind": "ingredient"}, [e])
	return {"success": true, "effect": e, "message": ""}

# --- alchemia (alchemy.cpp) -------------------------------------------------------------------------------

## Najlepsze aparaty każdego rodzaju z inwentarza (setAlchemist): {rodzaj: {"id", "quality"}}.
func alchemy_tools(f: Dictionary) -> Dictionary:
	var out := {}
	var sid := "player" if f.kind == "player" else String(f.sid)
	for e in main.interaction.inventory.contents(sid, f.rec):
		var it: Dictionary = main.interaction.inventory.item(String(e.id))
		if it.is_empty() or it.kind != "apparatus" or int(e.count) <= 0:
			continue
		var t := int(it.rec.get("apparatus_type", -1))
		var q := float(it.rec.get("quality", 0.0))
		if t >= 0 and t < 4 and (not out.has(t) or q > float(out[t].quality)):
			out[t] = {"id": it.id, "quality": q}
	return out

func alchemy_factor(f: Dictionary) -> float:
	var at: Array = _combat().attributes(f)
	return float(_combat().skill(f, SK_ALCHEMY)) + 0.1 * float(at[A_INTELLIGENCE]) + 0.1 * float(at[A_LUCK])

static func _ing_key(e: Dictionary) -> String:
	var arg := int(e.get("skill", -1))
	if arg < 0:
		arg = int(e.get("attribute", -1))
	return "%d:%d" % [int(e.get("effect", -1)), arg]

## listEffects: efekty wspólne dla par składników, w kolejności miejsc.
func common_effects(ings: Array) -> Array:
	var keys := []
	for i in ings.size():
		for j in range(i + 1, ings.size()):
			var b: Array = (ings[j] as Dictionary).get("effects", []).map(func(x): return _ing_key(x))
			for e in (ings[i] as Dictionary).get("effects", []):
				var k := _ing_key(e)
				if not k in keys and k in b:
					keys.append(k)
	return keys

## applyTools: retorta (dobroczynne) / alembik (szkodliwe) i kalcynator.
static func apply_tools(mg: Dictionary, tools: Dictionary, value: float) -> float:
	var magnitude: bool = not bool(mg.get("no_magnitude", false))
	var duration: bool = not bool(mg.get("no_duration", false))
	var negative: bool = bool(mg.get("harmful", false))
	var tool := APP_ALEMBIC if negative else APP_RETORT
	var setup := 0
	if tools.has(tool) and tools.has(APP_CALCINATOR):
		setup = 1
	elif tools.has(tool):
		setup = 2
	elif tools.has(APP_CALCINATOR):
		setup = 3
	else:
		return value
	var tq: float = float(tools[tool].quality) if setup == 1 or setup == 2 else 0.0
	var cq: float = float(tools[APP_CALCINATOR].quality) if setup == 1 or setup == 3 else 0.0
	var quality := 1.0
	match setup:
		1:
			quality = 2.0 * tq + 3.0 * cq if negative else (2.0 * tq + cq if magnitude and duration else 2.0 / 3.0 * (tq + cq) + 0.5)
		2:
			quality = 1.0 + tq if negative else (tq if magnitude and duration else tq + 0.5)
		3:
			quality = cq if magnitude and duration else cq + 0.5
	if setup == 3 or not negative:
		return value + quality
	return value / quality if quality != 0.0 else value

## updateEffects: {"effects": [ENAM], "value": wartość mikstury, "x": siła}; pusty – < 2 składników/brak moździerza.
func alchemy_result(f: Dictionary, ingredient_ids: Array, tools := {}) -> Dictionary:
	if tools.is_empty():
		tools = alchemy_tools(f)
	var ings := []
	for id in ingredient_ids:
		var it: Dictionary = main.interaction.inventory.item(String(id))
		if not it.is_empty() and it.kind == "ingredient":
			ings.append(it.rec)
	if ings.size() < 2 or not tools.has(APP_MORTAR):
		return {}
	var x := alchemy_factor(f) * float(tools[APP_MORTAR].quality) * _gmst("fPotionStrengthMult", 0.5)
	var value := int(x * _gmst("iAlchemyMod", 2.0))
	var out := []
	for k in common_effects(ings):
		var parts: PackedStringArray = String(k).split(":")
		var id := int(parts[0])
		var arg := int(parts[1])
		var mg := effect(id)
		var bc := float(mg.get("base_cost", 0.0))
		if mg.is_empty() or bc <= 0.0:
			continue
		var magnitude := 1.0 if _flag(mg, "no_magnitude") else (x / _gmst("fPotionT1MagMult", 1.5)) / bc
		var duration := 1.0 if _flag(mg, "no_duration") else (x / _gmst("fPotionT1DurMult", 0.5)) / bc
		if not _flag(mg, "no_magnitude"):
			magnitude = apply_tools(mg, tools, magnitude)
		if not _flag(mg, "no_duration"):
			duration = apply_tools(mg, tools, duration)
		duration = roundf(duration)
		magnitude = roundf(magnitude)
		if magnitude > 0.0 and duration > 0.0:
			out.append({"effect": id, "skill": arg if _flag(mg, "target_skill") else -1,
				"attribute": arg if _flag(mg, "target_attribute") else -1, "range": RT_SELF, "area": 0,
				"duration": int(duration), "min": int(magnitude), "max": int(magnitude)})
	return {"effects": out, "value": value, "x": x}

const POTION_MESHES := ["standard", "bargain", "cheap", "fresh", "exclusive", "quality"]

## Alchemy::getReadyStatus: kolejność jak OpenMW – moździerz, co najmniej dwa składniki, nazwa, wspólne efekty.
func alchemy_ready(ingredient_ids: Array, name: String, tools: Dictionary) -> String:
	if not tools.has(APP_MORTAR):
		return "no_mortar"
	var ids := ingredient_ids.filter(func(x): return not String(x).is_empty())
	if ids.size() < 2:
		return "few_ingredients"
	if name.is_empty():
		return "no_name"
	var ings := []
	for id in ids:
		var it: Dictionary = main.interaction.inventory.item(String(id))
		if not it.is_empty():
			ings.append(it.rec)
	if common_effects(ings).is_empty():
		return "no_effects"
	return "success"

## Alchemy::countPotionsToBrew: najmniejsza liczba sztuk wśród użytych składników (0, gdy nie gotowe).
func potions_to_brew(f: Dictionary, ingredient_ids: Array, name: String, tools: Dictionary) -> int:
	if alchemy_ready(ingredient_ids, name, tools) != "success":
		return 0
	var sid := "player" if f.kind == "player" else String(f.sid)
	var n := -1
	for id in ingredient_ids:
		if String(id).is_empty():
			continue
		var c: int = main.interaction.inventory.count_of(sid, f.rec, String(id))
		if (c > 0 and c < n) or n < 0:
			n = c
	return maxi(n, 0)

## Alchemy::knownEffect: efekt o indeksie i widoczny przy umiejętności ≥ fWortChanceValue × (i / 2 + 1).
func known_effect(f: Dictionary, index: int) -> bool:
	var sk := float(_combat().skill(f, SK_ALCHEMY))
	var w := _gmst("fWortChanceValue", 15.0)
	return (index <= 1 and sk >= w) or (index <= 3 and sk >= w * 2.0) or (index <= 5 and sk >= w * 3.0) \
			or (index <= 7 and sk >= w * 4.0)

## Alchemy::effectsDescription: efekty składnika widoczne przy umiejętności ≥ fWortChanceValue × (i + 1)
## (klucze „efekt:argument” do opisu i filtra okna alchemii).
func ingredient_known_effects(rec: Dictionary, skill: float) -> Array:
	var out := []
	var effs: Array = rec.get("effects", [])
	var w := _gmst("fWortChanceValue", 15.0)
	for i in mini(4, effs.size()):
		if skill < w * float(i + 1):
			break
		var e: Dictionary = effs[i]
		if int(e.get("effect", -1)) >= 0:
			out.append(e)
	return out

## Warzenie jak Alchemy::create(name, count): getReadyStatus (bez wspólnych efektów składniki znikają raz,
## sNotifyMessage8), potem count razy createSingle – bez efektów po zaokrągleniu albo przy czynniku alchemii
## < roll0to99 porażka, inaczej mikstura (addPotion: waga = średnia wag składników, wartość z czynnika, jeden
## z sześciu modeli, rekord dynamiczny o tych samych polach użyty ponownie) i rozwój Alchemii; za każdym razem
## po sztuce każdego składnika. tools – aparaty z okna (puste – najlepsze z ekwipunku).
## → {"result": "success"|"failure"|"no_effects"|"no_mortar"|"few_ingredients"|"no_name", "count", "potion",
##    "message", "sound"}
func brew(f: Dictionary, ingredient_ids: Array, name: String, roll := -1, count := 1, tools := {}) -> Dictionary:
	if tools.is_empty():
		tools = alchemy_tools(f)
	var slots: Array = ingredient_ids.duplicate()
	var nm := name.strip_edges()
	var status := alchemy_ready(slots, nm, tools)
	var sid := "player" if f.kind == "player" else String(f.sid)
	match status:
		"no_mortar":
			return {"result": status, "count": 0, "message": _text("sNotifyMessage45", "You need a mortar and pestle.")}
		"few_ingredients":
			return {"result": status, "count": 0, "message": _text("sNotifyMessage6a", "You need at least two ingredients.")}
		"no_name":
			return {"result": status, "count": 0, "message": _text("sNotifyMessage37", "You need to enter a name.")}
		"no_effects":
			_remove_ingredients(f, sid, slots)
			if main.audio != null:
				main.audio.play("potion fail")
			return {"result": status, "count": 0, "message": _text("sNotifyMessage8", "Your potion failed."), "sound": "potion fail"}
	break_invisibility(f)
	var brewed := 0
	var pid := ""
	for i in maxi(1, count):
		var ids := slots.filter(func(x): return not String(x).is_empty())
		if ids.size() < 2:
			break
		var res := alchemy_result(f, ids, tools)
		var weight := 0.0
		for id in ids:
			weight += float(main.interaction.inventory.item(String(id)).rec.get("weight", 0.0))
		weight /= ids.size()
		var r := roll if roll >= 0 else roll100()
		if (res.get("effects", []) as Array).is_empty() or alchemy_factor(f) < float(r):
			_remove_ingredients(f, sid, slots)
			continue
		var mesh: String = POTION_MESHES[rng.randi() % 6 if test_roll < 0 else 0]
		var rec := {"name": nm, "weight": weight, "value": int(res.value), "autocalc": false,
			"model": "m\\misc_potion_%s_01.nif" % mesh, "icon": "m\\tx_potion_%s_01.dds" % mesh, "effects": res.effects}
		pid = find_or_create("potion", rec, ["name", "weight", "value", "effects"])
		main.interaction.inventory.add(sid, f.rec, pid, 1)
		_remove_ingredients(f, sid, slots)
		if f.kind == "player":
			main.skill_used(SK_ALCHEMY, "alchemy_create")
		brewed += 1
	if brewed == 0:
		if main.audio != null:
			main.audio.play("potion fail")
		return {"result": "failure", "count": 0, "message": _text("sNotifyMessage8", "Your potion failed."), "sound": "potion fail"}
	if main.audio != null:
		main.audio.play("potion success")
	var msg := _text("sPotionSuccess", "You created a potion.")
	if brewed > 1:
		msg += " %s (%d)" % [nm, brewed]                 # AlchemyWindow::createPotions
	return {"result": "success", "count": brewed, "potion": pid, "message": msg, "sound": "potion success"}

## removeIngredients: po sztuce z każdego miejsca; miejsce pustoszeje, gdy składnika zabraknie.
func _remove_ingredients(f: Dictionary, sid: String, slots: Array) -> void:
	for i in slots.size():
		var id := String(slots[i])
		if id.is_empty():
			continue
		main.interaction.inventory.remove(sid, f.rec, id, 1)
		if main.interaction.inventory.count_of(sid, f.rec, id) < 1:
			slots[i] = ""

# --- rekordy tworzone w grze (ESMStore::insert – mikstury, zaklęcia, przedmioty zaklęte) -----------------

## state.created[plik][id] = rekord; istniejący rekord dynamiczny o tych samych polach jest używany ponownie
## (Alchemy::getRecord, Enchanting::getRecord).
func find_or_create(file: String, rec: Dictionary, compare: Array) -> String:
	var created: Dictionary = main.state.created
	if not created.has(file):
		created[file] = {}
	for id in created[file]:
		var o: Dictionary = created[file][id]
		var same := true
		for k in compare:
			if JSON.stringify(o.get(k)) != JSON.stringify(rec.get(k)):
				same = false
				break
		if same:
			return String(id)
	var nid := "mwg_generated_%d" % int(main.state.created_next)
	main.state.created_next = int(main.state.created_next) + 1
	var r := rec.duplicate(true)
	r["id"] = nid
	created[file][nid] = r
	return nid

# --- przedmioty zaklęte -----------------------------------------------------------------------------------

## getEnchantmentCharge: autoobliczany – koszt × iMagicItemCharge(Once/Strike/Use/Const), inaczej z rekordu.
func enchantment_charge(en: Dictionary) -> int:
	if bool(en.get("autocalc", false)):
		var c := int(roundf(total_cost(en.get("effects", []), COST_GAME_ENCHANTMENT)))
		var g: String = ["iMagicItemChargeOnce", "iMagicItemChargeStrike", "iMagicItemChargeUse", "iMagicItemChargeConst"][clampi(int(en.get("type", 0)), 0, 3)]
		return c * int(_gmst(g, 1.0))
	return int(en.get("charge", 0))

## getEffectiveEnchantmentCastCost: koszt − koszt/100 × (zaklinanie − 10), co najmniej 1.
func effective_cast_cost(en: Dictionary, f: Dictionary) -> int:
	var c := total_cost(en.get("effects", []), COST_GAME_ENCHANTMENT) if bool(en.get("autocalc", false)) else float(en.get("cost", 0))
	var sk := float(_combat().skill(f, SK_ENCHANT))
	var r := c - (c / 100.0) * (sk - 10.0)
	return int(1.0 if r < 1.0 else r)

func item_charge(f: Dictionary, id: String, en: Dictionary) -> float:
	var ch: Dictionary = holder(f).get("item_charge", {})
	return float(ch.get(id.to_lower(), enchantment_charge(en)))

func _set_item_charge(f: Dictionary, id: String, v: float) -> void:
	var h := holder(f)
	if not h.get("item_charge") is Dictionary:
		h["item_charge"] = {}
	h.item_charge[id.to_lower()] = v

## Użycie przedmiotu zaklętego (CastSpell::cast(item)): „po użyciu” – ładunek, „raz” (zwój) – zużyty.
## Przedmioty nie wymagają testu umiejętności. → jak cast_spell.
func use_item(caster: Dictionary, id: String, touch := {}) -> Dictionary:
	var it: Dictionary = main.interaction.inventory.item(id)
	var en := item_enchantment(it)
	if en.is_empty():
		return {"success": false, "message": "This item is not enchanted."}
	var typ := int(en.get("type", -1))
	if typ != ENCH_WHEN_USED and typ != ENCH_CAST_ONCE:
		return {"success": false, "message": _text("sMagicInvalidEffect", "This spell cannot be cast.")}
	var sid := "player" if caster.kind == "player" else String(caster.sid)
	break_invisibility(caster)               # użycie zaklętego przedmiotu (castSpell)
	if typ == ENCH_WHEN_USED:
		var cost := effective_cast_cost(en, caster)
		var ch := item_charge(caster, it.id, en)
		if ch < float(cost):
			_fail_sound(school_skill(int((en.get("effects", [{}]) as Array)[0].get("effect", -1))) if not (en.get("effects", []) as Array).is_empty() else 11)
			return {"success": false, "message": _text("sMagicInsufficientCharge", "The item does not have enough charge.")}
		_set_item_charge(caster, it.id, ch - float(cost))
		if caster.kind == "player":
			main.skill_used(SK_ENCHANT, "enchant_use")
	else:
		main.interaction.inventory.remove(sid, caster.rec, it.id, 1)
	var src := {"id": it.id, "name": String(it.rec.get("name", it.id)), "kind": "enchantment"}
	var list: Array = en.get("effects", [])
	inflict(caster, caster, src, by_range(list, RT_SELF))
	if not touch.is_empty():
		inflict(touch, caster, src, by_range(list, RT_TOUCH))
	return {"success": true, "bolt": by_range(list, RT_TARGET), "source": src, "spell": {}, "message": ""}

## Zaklęcie „przy uderzeniu” po trafieniu bronią (CastSpell::cast(item) z celem): broń biała – ładunek
## i postęp zaklinania; amunicja/broń rzucana – bez ładunku, efekty „na siebie” też na cel.
func on_strike(att: Dictionary, vic: Dictionary, w: Dictionary, projectile := false) -> bool:
	var en := item_enchantment(w)
	if en.is_empty() or int(en.get("type", -1)) != ENCH_WHEN_STRIKES or vic.is_empty():
		return false
	if not projectile:
		var cost := effective_cast_cost(en, att)
		var ch := item_charge(att, w.id, en)
		if ch < float(cost):
			if att.kind == "player":
				main._toast(_text("sMagicInsufficientCharge", "The item does not have enough charge."), 2.0)
			return false
		_set_item_charge(att, w.id, ch - float(cost))
		if att.kind == "player":
			main.skill_used(SK_ENCHANT, "enchant_strike")
	var src := {"id": w.id, "name": String(w.rec.get("name", w.id)), "kind": "enchantment"}
	var list: Array = en.get("effects", [])
	inflict(vic if projectile else att, att, src, by_range(list, RT_SELF))
	inflict(vic, att, src, by_range(list, RT_TOUCH))
	inflict(vic, att, src, by_range(list, RT_TARGET))
	return true

# --- kamienie dusz i pułapka dusz -------------------------------------------------------------------------

static func is_soul_gem(id: String) -> bool:
	return id.to_lower().get_slice("@", 0).begins_with("misc_soulgem")

static func soul_of(id: String) -> String:
	return id.get_slice("@", 1) if id.contains("@") else ""

## Pojemność kamienia (SoulGem: wartość × fSoulGemMult).
func gem_capacity(id: String) -> float:
	var it: Dictionary = main.interaction.inventory.item(id.get_slice("@", 0))
	return float(it.get("rec", {}).get("value", 0)) * _gmst("fSoulGemMult", 3.0)

## getGemCharge: dusza stworzenia w kamieniu (CREA soul).
func gem_charge(id: String) -> int:
	var s := soul_of(id)
	return int(records.record("creature", s).get("soul", 0)) if not s.is_empty() else 0

## Śmierć pod wpływem Pułapki dusz (Actors::killDeadActors → soulTrap): najmniejszy pusty kamień gracza
## mieszczący duszę stworzenia (NPC – tylko czarny kamień dusz) – „misc_soulgem_x@<stworzenie>”.
func soul_trap(victim: Dictionary) -> String:
	if victim.kind == "player" or magnitude_of(victim, FX_SOULTRAP) <= 0.0:
		return ""
	var soul := int(victim.rec.get("soul", 0)) if victim.kind == "creature" else 0
	if victim.kind == "creature" and soul <= 0:
		return ""
	var best := ""
	var best_cap := INF
	for e in main.interaction.inventory.contents("player", {}):
		var id := String(e.id)
		if int(e.count) <= 0 or not is_soul_gem(id) or not soul_of(id).is_empty():
			continue
		if victim.kind == "npc" and not id.begins_with("misc_soulgem_black"):
			continue
		var cap := gem_capacity(id)
		if (victim.kind == "npc" or cap >= float(soul)) and cap < best_cap:
			best_cap = cap
			best = id
	if best.is_empty():
		return ""
	var filled := best + "@" + String(victim.base)
	main.interaction.inventory.remove("player", {}, best, 1)
	main.interaction.inventory.add("player", {}, filled, 1)
	main._toast(_text("sSoultrapSuccess", "You trapped a soul."), 2.0)
	if main.audio != null:
		main.audio.play("conjuration hit")
	return filled

# --- zaklinanie (enchanting.cpp) --------------------------------------------------------------------------

## getEffectCosts: koszty narastające (każdy kolejny efekt zawiera poprzednie – jak w Morrowindzie).
func enchant_effect_costs(list: Array, cast_type: int) -> Array:
	var costs := []
	var mult := _gmst("fEffectCostMult", 0.5)
	var cdm := _gmst("fEnchantmentConstantDurationMult", 100.0)
	var cost := 0.0
	for e in list:
		var bc := float(effect(int(e.get("effect", -1))).get("base_cost", 0.0))
		var mn := maxi(1, int(e.get("min", 0)))
		var mx := maxi(1, int(e.get("max", 0)))
		var area := maxi(1, int(e.get("area", 0)))
		var dur := float(e.get("duration", 0))
		if cast_type == ENCH_CONSTANT:
			dur = cdm
		cost += ((mn + mx) * dur + area) * bc * mult * 0.05
		cost = maxf(1.0, cost)
		if int(e.get("range", 0)) == RT_TARGET:
			cost *= 1.5
		costs.append(cost)
	return costs

func enchant_points(list: Array, cast_type: int, precise := true) -> float:
	var t := 0.0
	for c in enchant_effect_costs(list, cast_type):
		t += float(c) if precise else floorf(float(c))
	return t

func enchant_cast_cost(list: Array, cast_type: int) -> int:
	return 0 if cast_type == ENCH_CONSTANT else int(enchant_points(list, cast_type, false))

## getMaxEnchantValue dla przedmiotu (it z MWInventory.item).
func max_enchant_value(it: Dictionary) -> int:
	return int(float(it.get("rec", {}).get("enchant_capacity", 0)) * _gmst("fEnchantmentMult", 0.1))

## getEnchantChance dla samodzielnego zaklinania zwykłego przedmiotu (mnożnik typu 1, jedna sztuka).
func enchant_chance(f: Dictionary, list: Array, cast_type: int) -> int:
	var at: Array = _combat().attributes(f)
	var x := (float(_combat().skill(f, SK_ENCHANT)) - enchant_points(list, cast_type) * _gmst("fEnchantmentChanceMult", 3.0)
		+ 0.2 * float(at[A_INTELLIGENCE]) + 0.1 * float(at[A_LUCK])) * float(_combat().fatigue_term(f))
	if cast_type == ENCH_CONSTANT:
		x *= _gmst("fEnchantmentConstantChanceMult", 0.5)
	return int(x)

## EnchantingDialog::onBuyButtonClicked + Enchanting::create bez okna (testy, skrypty): komunikaty w kolejności
## OpenMW; a – zaklinacz (NPC) albo {} – samodzielnie. → {"success", "item", "message", "failed"}
func enchant(f: Dictionary, item_id: String, gem_id: String, list: Array, cast_type: int, name: String, a := {}, roll := -1) -> Dictionary:
	var inv = main.interaction.inventory
	var st := {"item": item_id if inv.count_of("player", {}, item_id) > 0 else "", "gem": gem_id if inv.count_of("player", {}, gem_id) > 0 else "",
		"cast": cast_type, "effects": list, "enchanter": a, "self": a.is_empty(), "name": name}
	if list.is_empty():
		return {"success": false, "message": _text("sEnchantmentMenu11", "")}
	if name.is_empty():
		return {"success": false, "message": _text("sNotifyMessage10", "")}
	if String(st.gem).is_empty():
		return {"success": false, "message": _text("sNotifyMessage52", "")}
	if String(st.item).is_empty() or not ench_enchantable_entry({"kind": String(inv.item(item_id).get("kind", "")),
			"rec": inv.item(item_id).get("rec", {}), "magic": not item_enchantment(inv.item(item_id)).is_empty()}):
		return {"success": false, "message": _text("sNotifyMessage11", "")}
	if int(ench_points(st, false)) > ench_max_value(st):
		return {"success": false, "message": _text("sNotifyMessage29", "")}
	if not a.is_empty() and ench_price(st) > inv.count_of("player", {}, "gold_001"):
		return {"success": false, "message": _text("sNotifyMessage18", "")}
	var r := ench_create(f, st, roll)
	if not bool(r.ok):
		if main.audio != null:
			main.audio.play("enchant fail")
		return {"success": false, "failed": true, "message": _text("sNotifyMessage34", "")}
	if main.audio != null:
		main.audio.play("enchant success")
	return {"success": true, "item": r.item, "price": r.price, "message": _text("sEnchantmentMenu12", "")}

# --- zaklinanie (MWMechanics::Enchanting, apps/openmw/mwmechanics/enchanting.cpp) ---------------------------
## Stan okna st: {"item", "gem", "cast", "effects", "enchanter" (aktor rozmowy albo {}), "self", "name"}.

## ESM::WeaponType::Class (weapontype.hpp): łuk i kusza – Ranged, rzucana – Thrown, strzały i bełty – Ammo.
static func weapon_class(wt: int) -> String:
	if wt == 9 or wt == 10:
		return "ranged"
	if wt == 11:
		return "thrown"
	if wt == 12 or wt == 13:
		return "ammo"
	return "melee"

func _ench_item(st: Dictionary) -> Dictionary:
	var id := String(st.get("item", ""))
	return main.interaction.inventory.item(id) if not id.is_empty() else {}

func _ench_wclass(st: Dictionary) -> String:
	var it := _ench_item(st)
	if it.is_empty() or String(it.kind) != "weapon":
		return ""
	return weapon_class(int(it.rec.get("weapon_type", 0)))

func ench_points(st: Dictionary, precise := true) -> float:
	return enchant_points(st.get("effects", []), int(st.get("cast", ENCH_CAST_ONCE)), precise)

## getGemCharge: dusza stworzenia z kamienia (brak kamienia lub duszy – 0).
func ench_gem_charge(st: Dictionary) -> int:
	var g := String(st.get("gem", ""))
	return gem_charge(g) if not g.is_empty() else 0

## nextCastStyle.
func ench_next_cast_style(st: Dictionary) -> int:
	var cur := int(st.get("cast", ENCH_CAST_ONCE))
	var it := _ench_item(st)
	if it.is_empty():
		return cur
	var powerful := ench_gem_charge(st) >= int(_gmst("iSoulAmountForConstantEffect", 400.0))
	var kind := String(it.kind)
	if kind == "armor" or kind == "clothing":
		if cur == ENCH_WHEN_USED:
			return ENCH_CONSTANT if powerful else cur
		return ENCH_WHEN_USED
	if kind == "weapon":
		var wc := weapon_class(int(it.rec.get("weapon_type", 0)))
		match cur:
			ENCH_WHEN_STRIKES:
				return ENCH_WHEN_USED if wc == "melee" or wc == "ranged" else cur
			ENCH_WHEN_USED:
				if powerful and wc != "ammo" and wc != "thrown":
					return ENCH_CONSTANT
				if wc != "ranged":
					return ENCH_WHEN_STRIKES
				return cur
			_:
				return ENCH_WHEN_STRIKES if wc != "ranged" else ENCH_WHEN_USED
	return ENCH_CAST_ONCE

## getMaxEnchantValue: pojemność × fEnchantmentMult.
func ench_max_value(st: Dictionary) -> int:
	var it := _ench_item(st)
	if it.is_empty():
		return 0
	return int(float(it.rec.get("enchant_capacity", 0)) * _gmst("fEnchantmentMult", 0.1))

## getTypeMultiplier: [Game] projectiles enchant multiplier > 0 – broń rzucana i amunicja × 0,125.
func ench_type_mult(st: Dictionary) -> float:
	var pm := float(main.settings.get("projectiles_enchant_multiplier", 0.0)) if main != null else 0.0
	var wc := _ench_wclass(st)
	if pm > 0.0 and not wc.is_empty() and ench_points(st) > 0.0 and (wc == "thrown" or wc == "ammo"):
		return 0.125
	return 1.0

## getEnchantItemsCount: rzucana broń / amunicja – ile sztuk obejmie dusza (co najmniej 1, najwyżej tyle, ile ma gracz).
func ench_items_count(st: Dictionary) -> int:
	var count := 1
	var pts := ench_points(st)
	var wc := _ench_wclass(st)
	if not wc.is_empty() and pts > 0.0 and (wc == "thrown" or wc == "ammo"):
		var have: int = main.interaction.inventory.count_of("player", {}, String(st.item))
		var pm := float(main.settings.get("projectiles_enchant_multiplier", 0.0))
		count = clampi(int(ench_gem_charge(st) * pm / pts), 1, have)
	return count

func _ench_enchanter(st: Dictionary) -> Dictionary:
	var a: Dictionary = st.get("enchanter", {})
	if bool(st.get("self", true)) or a.is_empty() or not (a.get("node") is Node) or not is_instance_valid(a.node):
		return _combat().player_fighter()
	return _combat().fighter_of(a.node)

## getEnchantChance: (Zaklinanie − punkty × fEnchantmentChanceMult × mnożnik typu × sztuki + 0,2 Int + 0,1 Szczęście)
## × współczynnik zmęczenia; stały efekt × fEnchantmentConstantChanceMult.
func ench_chance(st: Dictionary) -> int:
	var f := _ench_enchanter(st)
	var at: Array = _combat().attributes(f)
	var x := (float(_combat().skill(f, SK_ENCHANT)) - ench_points(st) * _gmst("fEnchantmentChanceMult", 3.0)
		* ench_type_mult(st) * ench_items_count(st) + 0.2 * float(at[A_INTELLIGENCE]) + 0.1 * float(at[A_LUCK])) \
		* float(_combat().fatigue_term(f))
	if int(st.get("cast", 0)) == ENCH_CONSTANT:
		x *= _gmst("fEnchantmentConstantChanceMult", 0.5)
	return int(x)

## getBaseCastCost / getEffectiveCastCost (gracz).
func ench_base_cast_cost(st: Dictionary) -> int:
	if int(st.get("cast", 0)) == ENCH_CONSTANT:
		return 0
	return int(ench_points(st, false))

func ench_effective_cast_cost(st: Dictionary) -> int:
	return effective_cast_cost({"cost": ench_base_cast_cost(st)}, _combat().player_fighter())

## getEnchantPrice(getEnchantItemsCount()): koszt ostatniego efektu × fEnchantmentValueMult, oferta targowa,
## × (sztuki × mnożnik typu), co najmniej 1; bez zaklinacza – 0.
func ench_price(st: Dictionary) -> int:
	var a: Dictionary = st.get("enchanter", {})
	if bool(st.get("self", true)) or a.is_empty():
		return 0
	var costs := enchant_effect_costs(st.get("effects", []), int(st.get("cast", 0)))
	var last := float(costs.back()) if not costs.is_empty() else 0.0
	var price: int = main.trade.barter_offer(a, int(last * _gmst("fEnchantmentValueMult", 1000.0)), true)
	price *= int(ench_items_count(st) * ench_type_mult(st))
	return maxi(1, price)

## Filter_OnlyEnchantable: zbroja, ubranie, broń, zwój (książka z flagą scroll), bez zaklęcia.
func ench_enchantable_entry(e: Dictionary) -> bool:
	if bool(e.get("magic", false)):
		return false
	var k := String(e.get("kind", ""))
	if not k in ["armor", "clothing", "weapon", "book"]:
		return false
	return k != "book" or bool((e.get("rec", {}) as Dictionary).get("scroll", false))

## Filter_OnlyChargedSoulstones: przedmiot różny z duszą istniejącego stworzenia.
func ench_soulstone_entry(e: Dictionary) -> bool:
	if String(e.get("kind", "")) != "misc":
		return false
	var s := soul_of(String(e.get("id", "")))
	return not s.is_empty() and not records.record("creature", s).is_empty()

## Nowy rekord przedmiotu (ESMStore::insert – zawsze nowy identyfikator).
func create_record(file: String, rec: Dictionary) -> String:
	var created: Dictionary = main.state.created
	if not created.has(file):
		created[file] = {}
	var nid := "mwg_generated_%d" % int(main.state.created_next)
	main.state.created_next = int(main.state.created_next) + 1
	var r := rec.duplicate(true)
	r["id"] = nid
	created[file][nid] = r
	return nid

## Enchanting::create: kamień zużyty (Gwiazda Azury wraca pusta); samodzielnie – rzut 0–99 wobec szansy, postęp
## Enchant_CreateMagicItem; rekord zaklęcia (dynamiczny o tych samych danych albo nowy), applyEnchantment
## (kopia rekordu: nazwa, zaklęcie, pojemność = ładunek kamienia; broń – Magical, książka – zwój); u zaklinacza
## zapłata (złoto do puli kupca); stary przedmiot zastąpiony nowym. → {"ok", "item"}
func ench_create(_f: Dictionary, st: Dictionary, roll := -1) -> Dictionary:
	var inv = main.interaction.inventory
	var cast := int(st.get("cast", 0))
	var list: Array = st.get("effects", [])
	var gem := String(st.get("gem", ""))
	var charge := ench_gem_charge(st)
	var count := ench_items_count(st)
	var price := ench_price(st)
	var en := {"flags": 0, "type": cast, "cost": ench_base_cast_cost(st), "autocalc": false}
	inv.remove("player", {}, gem, 1)
	if inv.base_id(gem).get_slice("@", 0) == "misc_soulgem_azura":
		inv.add("player", {}, "misc_soulgem_azura", 1)
	if bool(st.get("self", true)):
		var r := roll if roll >= 0 else roll100()
		if ench_chance(st) <= r:
			return {"ok": false, "roll": r}
		main.skill_used(SK_ENCHANT, "enchant_create")
	en["effects"] = list.duplicate(true)
	en["charge"] = 0 if cast == ENCH_CONSTANT else int(charge / count)
	var eid := find_or_create("enchantment", en, ["flags", "type", "cost", "charge", "effects"])
	var it := _ench_item(st)
	var rec: Dictionary = (it.rec as Dictionary).duplicate(true)
	rec.erase("id")
	rec["source_object"] = String(rec.get("source_object", main.interaction.inventory.base_id(String(st.item)).to_lower()))
	rec["name"] = String(st.get("name", ""))
	rec["enchant"] = eid
	match String(it.kind):
		"weapon":
			rec["enchant_capacity"] = charge & 0xFFFF
			rec["flags"] = int(rec.get("flags", 0)) | 1
			rec["magical"] = true
		"book":
			rec["enchant_capacity"] = charge
			rec["scroll"] = true
		_:
			rec["enchant_capacity"] = charge
	var nid := create_record(String(it.kind), rec)
	if not bool(st.get("self", true)):
		var a: Dictionary = st.enchanter
		inv.remove("player", {}, "gold_001", price)
		main.trade.set_merchant_gold(a, main.trade.merchant_gold(a) + price)
	var old := String(st.item)
	if main.equipped_slot_of(old) >= 0 and inv.count_of("player", {}, old) <= count:
		main.unequip_slot(main.equipped_slot_of(old))
	inv.remove("player", {}, old, count)
	inv.add("player", {}, nid, count)
	return {"ok": true, "item": nid, "enchantment": eid, "price": price, "count": count}

# --- ładowanie przedmiotów (MWMechanics::rechargeItem, apps/openmw/mwmechanics/recharge.cpp) -----------------

## Filter_OnlyRechargable: przedmiot zaklęty, ładunek ustawiony (nie −1) i mniejszy od pełnego.
func rechargeable_entry(e: Dictionary) -> bool:
	if not bool(e.get("magic", false)):
		return false
	var it: Dictionary = main.interaction.inventory.item(String(e.get("id", "")))
	var en := item_enchantment(it)
	if en.is_empty():
		return false
	var ch: Dictionary = holder(_combat().player_fighter()).get("item_charge", {})
	var key := String(e.id).to_lower()
	return ch.has(key) and float(ch[key]) >= 0.0 and float(ch[key]) < float(enchantment_charge(en))

## rechargeItem(item, gem): x = (Zaklinanie + 0,2 Int [1..20] + 0,1 Szczęście [1..10, inaczej 1]) × zmęczenie;
## rzut 0–99 < x – ładunek + dusza × rzut / x (do pełnego), „Enchant Success”, inaczej „Enchant Fail”; zawsze
## postęp Enchant_Recharge i zużycie kamienia (ostatni – sNotifyMessage51, Gwiazda Azury wraca pusta).
func recharge_item(item_id: String, gem_id: String, roll := -1) -> Dictionary:
	var inv = main.interaction.inventory
	if inv.count_of("player", {}, gem_id) <= 0:
		return {"ok": false}
	var me: Dictionary = _combat().player_fighter()
	break_invisibility(me)
	var at: Array = _combat().attributes(me)
	var luck := 0.1 * float(at[A_LUCK])
	if luck < 1.0 or luck > 10.0:
		luck = 1.0
	var intel := clampf(0.2 * float(at[A_INTELLIGENCE]), 1.0, 20.0)
	var x := (float(_combat().skill(me, SK_ENCHANT)) + intel + luck) * float(_combat().fatigue_term(me))
	var r := roll if roll >= 0 else roll100()
	var sounds := []
	var success := float(r) < x
	if success:
		var restored := float(gem_charge(gem_id)) * (float(r) / x)
		var en := item_enchantment(inv.item(item_id))
		var mx := float(enchantment_charge(en))
		_set_item_charge(me, item_id, minf(item_charge(me, item_id, en) + restored, mx))
		sounds.append("Enchant Success")
	else:
		sounds.append("Enchant Fail")
	if main.audio != null:
		for s in sounds:
			main.audio.play(s)
	main.skill_used(SK_ENCHANT, "enchant_recharge")
	var gem_name: String = main.interaction.item_name("misc", gem_id, inv.item(gem_id).get("rec", {}))
	inv.remove("player", {}, gem_id, 1)
	var messages := []
	if inv.count_of("player", {}, gem_id) <= 0:
		messages.append(_text("sNotifyMessage51", "%s").replace("%s", gem_name))
		if gem_id.get_slice("@", 0) == "misc_soulgem_azura":
			inv.add("player", {}, "misc_soulgem_azura", 1)
	for m in messages:
		main._toast(m)
	return {"ok": true, "success": success, "roll": r, "x": x, "messages": messages}
