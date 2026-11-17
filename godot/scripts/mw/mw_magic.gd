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
const LATER := {49: "AI (etap 8)", 50: "AI (etap 8)", 51: "AI (etap 8)", 52: "AI (etap 8)", 53: "AI (etap 8)",
	54: "AI (etap 8)", 55: "AI (etap 8)", 56: "AI (etap 8)", 101: "AI (etap 8)", 118: "AI (etap 8)", 119: "AI (etap 8)",
	59: "telekineza (etap 8)", 62: "boska interwencja (etap 8)", 63: "interwencja Almsivi (etap 8)",
	71: "choroby (etap 8)", 126: "ExtraSpell", 132: "choroby (etap 8)", 133: "wampiryzm (etap 8)",
	135: "obrażenia od słońca (etap 8)"}
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
				continue                  # czasowe: tylko wartość bieżąca (adjustDynamicStat), maksimum bez zmian
			main.character.add_effect(fx, e, float(e.get("magnitude", 0.0)))

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
		return fx
	# zdolności rasy (Npc::getCreatureStats: addAllToInstance(race->mPowers)) i własne zaklęcia rekordu
	var own: Array = actor_spells(f).duplicate()
	if f.kind == "npc":
		own.append_array(records.record("race", String(f.rec.get("race", ""))).get("powers", []))
	for sid in own:
		var sp: Dictionary = records.record("spell", String(sid))
		if not sp.is_empty() and int(sp.get("spell_type", 0)) in main.character.CONSTANT_TYPES:
			for e in sp.get("effects", []):
				main.character.add_effect(fx, e, float(e.get("min", 0)))
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
	if f.kind == "creature":
		formula = float(f.rec.get("magicka", 0))
	elif not bool(f.rec.get("autocalc", false)) and f.rec.has("magicka"):
		formula = float(f.rec.magicka)
	return main.character.dyn_base_override(_combat()._actor_state(f), "magicka", [at[A_INTELLIGENCE], factor], formula)

func magicka(f: Dictionary) -> float:
	if f.kind == "player":
		return float(main.player_stats().get("magicka", 0.0))
	return float(_combat()._actor_state(f).get("magicka", max_magicka(f)))

func set_magicka(f: Dictionary, v: float) -> void:
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
func inflict(target: Dictionary, caster: Dictionary, source: Dictionary, list: Array, spell := {}, temporary := true) -> Dictionary:
	var res := {"applied": 0, "resisted": 0, "reflected": false, "absorbed": false}
	if target.is_empty() or list.is_empty() or _combat().is_dead(target):
		return res
	var self_cast: bool = not caster.is_empty() and caster.sid == target.sid
	# odbicie / pochłonięcie (cały czar) – tylko czary rzucane na innych
	if temporary and not self_cast and not caster.is_empty():
		var fx := effects(target)
		if float(fx.get(str(FX_REFLECT), 0.0)) > 0.0 and roll100() < float(fx.get(str(FX_REFLECT), 0.0)):
			var unref := list.filter(func(e): return not _flag(effect(int(e.get("effect", -1))), "unreflectable"))
			if not unref.is_empty():
				var r2 := inflict(caster, target, source, unref, {}, temporary)
				r2["reflected"] = true
				return r2
		var absorb := float(fx.get(str(FX_SPELL_ABSORPTION), 0.0))
		if absorb > 0.0 and roll100() < absorb:
			var cost := spell_cost(spell) if not spell.is_empty() else int(total_cost(list))
			adjust_dynamic(target, 1, float(cost))
			res["absorbed"] = true
			return res
	var entry := {"id": String(source.get("id", "")), "name": String(source.get("name", "")),
		"kind": String(source.get("kind", "spell")), "caster": String(caster.get("sid", "")) if not caster.is_empty() else "",
		"effects": []}
	var harmful := false
	for e in list:
		var id := int(e.get("effect", -1))
		var mg := effect(id)
		if mg.is_empty():
			continue
		if _flag(mg, "caster_linked") and caster.is_empty():
			continue
		var ae := {"effect": id, "skill": int(e.get("skill", -1)), "attribute": int(e.get("attribute", -1)),
			"min": float(e.get("min", 0)), "max": float(e.get("max", 0)), "duration": float(e.get("duration", 0)),
			"time_left": float(e.get("duration", 0)), "magnitude": 0.0, "applied": false}
		if _flag(mg, "no_magnitude"):
			ae.min = 1.0
			ae.max = 1.0
		if _flag(mg, "no_duration"):            # applyMagicEffects (Lua): bez czasu trwania → 1 s
			ae.duration = 1.0
			ae.time_left = 1.0
		if _flag(mg, "harmful"):
			harmful = true
		if not caster.is_empty() and has_resistance(id):
			var mult := 1.0 - effect_resistance(id, target, caster, spell) / 100.0
			if mult <= 0.0:
				res.resisted += 1
				if target.kind == "player":
					main._toast(_text("sMagicPCResisted", "Oparłeś się zaklęciu."), 2.0)
				elif caster.kind == "player":
					main._toast(_text("sMagicTargetResisted", "Cel oparł się zaklęciu."), 2.0)
				continue
			if not _flag(mg, "no_magnitude"):
				ae.min *= mult
				ae.max *= mult
		entry.effects.append(ae)
		res.applied += 1
	if harmful and not caster.is_empty() and not self_cast and caster.kind == "player" and target.kind != "player":
		_combat()._actor_state(target)["attacked"] = true
		main.on_actor_attacked(target)
	if entry.effects.is_empty():
		return res
	active(target).append(entry)
	_tick_entry(target, entry, 0.0)
	_cleanup(target)
	sync_dynamic(target)
	return res

## Jedno przejście applyMagicEffect dla efektu (dt = 0 – nałożenie przy rzuceniu).
func _apply_effect(f: Dictionary, entry: Dictionary, e: Dictionary, dt: float) -> void:
	var id := int(e.effect)
	var mg := effect(id)
	var once := _flag(mg, "applied_once")
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
				if not c2.is_empty():           # rzucający: wzmocnienie na czas efektu
					var fe := FX_FORTIFY_ATTRIBUTE if id == FX_ABSORB_ATTRIBUTE else FX_FORTIFY_SKILL
					active(c2).append({"id": entry.id, "name": entry.name, "kind": "absorb", "caster": "", "effects": [
						{"effect": fe, "skill": int(e.skill), "attribute": int(e.attribute), "min": amount, "max": amount,
						"duration": e.duration, "time_left": e.time_left, "magnitude": amount, "applied": true}]})
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
				main._toast(main.dialogue.gmst_text("sTeleportDisabled", "Teleportacja jest tu niemożliwa.") if main.dialogue != null else "")
			elif id == FX_MARK and f.kind == "player":
				main.state.player["mark"] = {"interior": main.interior, "pos": main.position_string()}
			elif id == FX_RECALL and f.kind == "player" and main.state.player.get("mark") is Dictionary and main.has_method("recall_to_mark"):
				main.recall_to_mark()
		_:
			if BOUND_ITEMS.has(id):
				_bound_item(f, id, true)
			elif LATER.has(id):
				unsupported[LATER[id]] = int(unsupported.get(LATER[id], 0)) + 1
	if id in [FX_FIRE, FX_SHOCK, FX_FROST, FX_DAMAGE_HEALTH, FX_POISON, FX_DRAIN_HEALTH, FX_ABSORB_HEALTH]:
		_check_death(f, entry)

## removeMagicEffect – cofnięcie efektów jednorazowych po wygaśnięciu.
func _remove_effect(f: Dictionary, e: Dictionary) -> void:
	if not bool(e.get("applied", false)):
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
		_:
			if BOUND_ITEMS.has(id):
				_bound_item(f, id, false)

func _check_death(f: Dictionary, entry: Dictionary) -> void:
	var cb = _combat()
	if float(cb.health(f)) <= 0.0 and not cb.is_dead(f):
		var c := _caster_of(entry) if not entry.is_empty() else {}
		main.on_actor_died(f, c)

func _purge_effect(f: Dictionary, fx_id: int) -> void:
	for sp in active(f):
		for x in sp.effects:
			if int(x.effect) == fx_id:
				x.time_left = 0.0

## Leczenie chorób i klątw: usuwa z listy czarów gracza rodzaje 2 (zaraza), 3 (choroba), 4 (klątwa).
func _purge_permanent(f: Dictionary, spell_type: int) -> void:
	if f.kind != "player":
		return
	var st: Dictionary = main.player_stats()
	st["spells"] = (st.get("spells", []) as Array).filter(func(s):
		return int(records.record("spell", String(s)).get("spell_type", 0)) != spell_type)

func _disintegrate(f: Dictionary, weapon: bool, amount: float) -> void:
	var cb = _combat()
	var eq: Dictionary = cb.equipment(f)
	var slots := [cb.EQ.SLOT_CARRIED_RIGHT] if weapon else [cb.EQ.SLOT_CARRIED_LEFT, cb.EQ.SLOT_CUIRASS,
		cb.EQ.SLOT_LEFT_PAULDRON, cb.EQ.SLOT_RIGHT_PAULDRON, cb.EQ.SLOT_LEFT_GAUNTLET, cb.EQ.SLOT_RIGHT_GAUNTLET,
		cb.EQ.SLOT_HELMET, cb.EQ.SLOT_GREAVES, cb.EQ.SLOT_BOOTS]
	for s in slots:
		var it: Dictionary = eq.get(s, {})
		if it.is_empty() or float(it.rec.get("health", 0)) <= 0.0 or (weapon and it.kind != "weapon") or (not weapon and it.kind != "armor"):
			continue
		var h: float = cb.item_health(it) - amount
		cb._set_item_health(f, s, maxf(0.0, h))
		if h <= 0.0 and f.kind == "player":
			main.unequip_slot(s)
		break

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
				main.equip_item(item_id)
		else:
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

const CONSTANT_TICK := [14, 15, 16, 23, 24, 25, 27, 75, 76, 77]

func _tick_constant(f: Dictionary, dt: float) -> void:
	if dt <= 0.0:
		return
	var src := []
	var spells: Array = main.player_stats().get("spells", []) if f.kind == "player" else actor_spells(f)
	for sid in spells:
		var sp: Dictionary = records.record("spell", String(sid))
		if not sp.is_empty() and int(sp.get("spell_type", 0)) in main.character.CONSTANT_TYPES:
			src.append_array(sp.get("effects", []))
	var eq: Dictionary = _combat().equipment(f)
	for s in eq:
		var en := item_enchantment({"rec": eq[s].rec})
		if not en.is_empty() and int(en.get("type", -1)) == ENCH_CONSTANT:
			src.append_array(en.get("effects", []))
	for e in src:
		var id := int(e.get("effect", -1))
		if id in CONSTANT_TICK:
			var ae := {"effect": id, "skill": int(e.get("skill", -1)), "attribute": int(e.get("attribute", -1)),
				"min": float(e.get("min", 0)), "max": float(e.get("max", 0)), "duration": 0.0, "time_left": 0.0}
			_actor_effect(f, {"caster": ""}, ae, _roll_magnitude(ae) * dt)

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
		return {"success": false, "message": "Nieznane zaklęcie."}
	var typ := int(sp.get("spell_type", 0))
	if typ != SPELL_SPELL and typ != SPELL_POWER:
		return {"success": false, "message": "Tego nie można rzucić."}
	var cost := spell_cost(sp) if typ == SPELL_SPELL else 0
	var base := spell_base_chance(sp, caster)
	var school := int(base.school)
	if typ == SPELL_SPELL and magicka(caster) < float(cost):
		return {"success": false, "cost": cost, "message": _text("sMagicInsufficientSP", "Za mało magii.")}
	if typ == SPELL_POWER and not can_use_power(caster, spell_id):
		return {"success": false, "message": _text("sPowerAlreadyUsed", "Tej mocy już dziś użyłeś.")}
	if cost > 0:
		set_magicka(caster, magicka(caster) - float(cost))
	var chance := spell_chance(sp, caster, true, false)
	var r := roll if roll >= 0 else roll100()
	if float(r) >= chance:
		_fail_sound(school)
		return {"success": false, "chance": chance, "cost": cost, "school": school,
			"message": _text("sMagicSkillFail", "Nie udało ci się rzucić zaklęcia.")}
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
		var msg := _text("sNotifyMessage50", "%s nie działa na ciebie.").replace("%s", String(it.rec.get("name", it.id)))
		return {"success": true, "effect": {}, "message": msg}
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

## Warzenie (Alchemy::create, jedna mikstura): składniki zużyte zawsze; porażka, gdy brak efektów albo
## czynnik alchemii < rzut. → {"result": "success"|"failure"|"no_mortar"|"few_ingredients"|"no_name", "potion"}
func brew(f: Dictionary, ingredient_ids: Array, name: String, roll := -1) -> Dictionary:
	if name.strip_edges().is_empty():
		return {"result": "no_name", "message": _text("sNotifyMessage37", "Podaj nazwę mikstury.")}
	var tools := alchemy_tools(f)
	if not tools.has(APP_MORTAR):
		return {"result": "no_mortar", "message": _text("sNotifyMessage45", "Potrzebujesz moździerza i tłuczka.")}
	var ids := []
	for id in ingredient_ids:
		if not String(id).is_empty() and not String(id) in ids:
			ids.append(String(id))
	if ids.size() < 2:
		return {"result": "few_ingredients", "message": _text("sNotifyMessage6a", "Potrzebujesz co najmniej dwóch składników.")}
	var res := alchemy_result(f, ids, tools)
	var sid := "player" if f.kind == "player" else String(f.sid)
	var weight := 0.0
	for id in ids:
		weight += float(main.interaction.inventory.item(id).rec.get("weight", 0.0))
		main.interaction.inventory.remove(sid, f.rec, id, 1)
	weight /= ids.size()
	var r := roll if roll >= 0 else roll100()
	if (res.get("effects", []) as Array).is_empty() or alchemy_factor(f) < float(r):
		if main.audio != null:
			main.audio.play("potion fail")
		return {"result": "failure", "message": _text("sNotifyMessage8", "Nie udało ci się stworzyć mikstury.")}
	var mesh: String = POTION_MESHES[rng.randi() % 6 if test_roll < 0 else 0]
	var rec := {"name": name.strip_edges(), "weight": weight, "value": int(res.value), "autocalc": false,
		"model": "m\\misc_potion_%s_01.nif" % mesh, "icon": "m\\tx_potion_%s_01.dds" % mesh, "effects": res.effects}
	var pid := find_or_create("potion", rec, ["name", "weight", "value", "effects"])
	main.interaction.inventory.add(sid, f.rec, pid, 1)
	if f.kind == "player":
		main.skill_used(SK_ALCHEMY, "alchemy_create")
	if main.audio != null:
		main.audio.play("potion success")
	return {"result": "success", "potion": pid, "message": _text("sPotionSuccess", "Stworzyłeś miksturę.")}

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
		return {"success": false, "message": "Ten przedmiot nie jest zaklęty."}
	var typ := int(en.get("type", -1))
	if typ != ENCH_WHEN_USED and typ != ENCH_CAST_ONCE:
		return {"success": false, "message": "Tego zaklęcia nie można użyć."}
	var sid := "player" if caster.kind == "player" else String(caster.sid)
	if typ == ENCH_WHEN_USED:
		var cost := effective_cast_cost(en, caster)
		var ch := item_charge(caster, it.id, en)
		if ch < float(cost):
			_fail_sound(school_skill(int((en.get("effects", [{}]) as Array)[0].get("effect", -1))) if not (en.get("effects", []) as Array).is_empty() else 11)
			return {"success": false, "message": _text("sMagicInsufficientCharge", "Przedmiot ma za mało ładunku.")}
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
				main._toast(_text("sMagicInsufficientCharge", "Przedmiot ma za mało ładunku."), 2.0)
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
	main._toast(_text("sSoultrapSuccess", "Uwięziłeś duszę."), 2.0)
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

## getMaxEnchantValue: pojemność przedmiotu × fEnchantmentMult.
func max_enchant_value(it: Dictionary) -> int:
	return int(float(it.get("rec", {}).get("enchant_capacity", 0)) * _gmst("fEnchantmentMult", 0.1))

## getEnchantChance (zaklinanie samodzielne).
func enchant_chance(f: Dictionary, list: Array, cast_type: int) -> int:
	var at: Array = _combat().attributes(f)
	var x := (float(_combat().skill(f, SK_ENCHANT)) - enchant_points(list, cast_type) * _gmst("fEnchantmentChanceMult", 3.0)
		+ 0.2 * float(at[A_INTELLIGENCE]) + 0.1 * float(at[A_LUCK])) * float(_combat().fatigue_term(f))
	if cast_type == ENCH_CONSTANT:
		x *= _gmst("fEnchantmentConstantChanceMult", 0.5)
	return int(x)

## getEnchantPrice: koszt ostatniego efektu × fEnchantmentValueMult, oferta targowa kupca (a – aktor rozmowy).
func enchant_price(a: Dictionary, list: Array, cast_type: int) -> int:
	var costs := enchant_effect_costs(list, cast_type)
	var last := float(costs.back()) if not costs.is_empty() else 0.0
	var p: int = main.trade.barter_offer(a, int(last * _gmst("fEnchantmentValueMult", 1000.0)), true)
	return maxi(1, p)

## Dozwolone sposoby rzucania dla przedmiotu (nextCastStyle): zbroja/ubranie – po użyciu, stały (silna dusza);
## broń – przy uderzeniu (nie dystansowa), po użyciu (nie amunicja/rzucana… jak OpenMW), stały; książka – raz.
func cast_types_for(it: Dictionary, gem_id: String) -> Array:
	if it.is_empty():
		return []
	var powerful := gem_charge(gem_id) >= int(_gmst("iSoulAmountForConstantEffect", 400.0))
	match String(it.kind):
		"armor", "clothing":
			return [ENCH_WHEN_USED, ENCH_CONSTANT] if powerful else [ENCH_WHEN_USED]
		"book":
			return [ENCH_CAST_ONCE]
		"weapon":
			var wt := int(it.rec.get("weapon_type", 0))
			var out := []
			if not wt in [9, 10]:
				out.append(ENCH_WHEN_STRIKES)
			if wt in [9, 10] or not wt in [11, 12, 13]:
				out.append(ENCH_WHEN_USED)
			if powerful and not wt in [11, 12, 13]:
				out.append(ENCH_CONSTANT)
			return out
	return []

## Efekty, które gracz może nałożyć (znane z czarów, flaga „enchanting”).
func known_enchant_effects(st: Dictionary) -> Array:
	var out := []
	for sid in st.get("spells", []):
		for e in records.record("spell", String(sid)).get("effects", []):
			var id := int(e.get("effect", -1))
			if _flag(effect(id), "enchanting") and not id in out:
				out.append(id)
	out.sort()
	return out

## Enchanting::create: kamień zużyty zawsze; samodzielnie – rzut wg szansy, postęp zaklinania; u zaklinacza
## (a – aktor rozmowy) – zapłata. Nowy rekord zaklęcia i przedmiotu (kopia z nazwą i zaklęciem).
## → {"success", "item", "message"}
func enchant(f: Dictionary, item_id: String, gem_id: String, list: Array, cast_type: int, name: String, a := {}, roll := -1) -> Dictionary:
	var inv = main.interaction.inventory
	var it: Dictionary = inv.item(item_id)
	if list.is_empty():
		return {"success": false, "message": _text("sEnchantmentMenu11", "Wybierz efekty.")}
	if name.strip_edges().is_empty():
		return {"success": false, "message": _text("sNotifyMessage10", "Podaj nazwę przedmiotu.")}
	if gem_charge(gem_id) <= 0 or inv.count_of("player", {}, gem_id) <= 0:
		return {"success": false, "message": _text("sNotifyMessage52", "Wybierz kamień dusz z duszą.")}
	if it.is_empty() or inv.count_of("player", {}, item_id) <= 0 or not item_enchantment(it).is_empty():
		return {"success": false, "message": _text("sNotifyMessage11", "Wybierz przedmiot do zaklęcia.")}
	if not cast_type in cast_types_for(it, gem_id):
		return {"success": false, "message": "Tego sposobu rzucania nie można użyć dla tego przedmiotu."}
	if int(enchant_points(list, cast_type, false)) > max_enchant_value(it):
		return {"success": false, "message": _text("sNotifyMessage29", "Zaklęcie jest zbyt silne dla tego przedmiotu.")}
	var price := 0
	if not a.is_empty():
		price = enchant_price(a, list, cast_type)
		if inv.count_of("player", {}, "gold_001") < price:
			return {"success": false, "message": _text("sNotifyMessage18", "Nie masz dość złota.")}
	var charge := gem_charge(gem_id)
	inv.remove("player", {}, gem_id, 1)
	if gem_id.get_slice("@", 0) == "misc_soulgem_azura":
		inv.add("player", {}, "misc_soulgem_azura", 1)
	if a.is_empty():
		if enchant_chance(f, list, cast_type) <= (roll if roll >= 0 else roll100()):
			if main.audio != null:
				main.audio.play("enchant fail")
			return {"success": false, "failed": true, "message": _text("sNotifyMessage34", "Nie udało ci się zakląć przedmiotu.")}
		main.skill_used(SK_ENCHANT, "enchant_create")
	var en := {"type": cast_type, "cost": enchant_cast_cost(list, cast_type), "charge": 0 if cast_type == ENCH_CONSTANT else charge,
		"autocalc": false, "flags": 0, "effects": list.duplicate(true)}
	var eid := find_or_create("enchantment", en, ["type", "cost", "charge", "effects"])
	var rec: Dictionary = (it.rec as Dictionary).duplicate(true)
	rec["name"] = name.strip_edges()
	rec["enchant"] = eid
	rec.erase("script")
	var nid := find_or_create(String(it.kind), rec, ["name", "enchant", "model"])
	if not a.is_empty():                          # payForEnchantment: złoto do kupca
		inv.remove("player", {}, "gold_001", price)
		main.trade.set_merchant_gold(a, main.trade.merchant_gold(a) + price)
	if main.equipped_slot_of(it.id) >= 0 and inv.count_of("player", {}, it.id) <= 1:
		main.unequip_slot(main.equipped_slot_of(it.id))
	inv.remove("player", {}, it.id, 1)
	inv.add("player", {}, nid, 1)
	if cast_type != ENCH_CONSTANT:
		_set_item_charge(f, nid, float(charge))
	if main.audio != null:
		main.audio.play("enchant success")
	return {"success": true, "item": nid, "price": price, "message": _text("sEnchantmentMenu12", "Przedmiot został zaklęty.")}
