"""Efekty magiczne (MGEF) – tabele z OpenMW 0.51 (components/esm3/loadmgef.cpp): nazwy (GMST „sEffect<Nazwa>”)
i stałe flagi efektów (HardcodedFlags – w formacie TES3 pliki mogą zmieniać tylko AllowSpellmaking,
AllowEnchanting i NegativeLight)."""

EFFECT_NAMES = [
    'WaterBreathing', 'SwiftSwim', 'WaterWalking', 'Shield', 'FireShield', 'LightningShield', 'FrostShield',
    'Burden', 'Feather', 'Jump', 'Levitate', 'SlowFall', 'Lock', 'Open', 'FireDamage', 'ShockDamage', 'FrostDamage',
    'DrainAttribute', 'DrainHealth', 'DrainSpellpoints', 'DrainFatigue', 'DrainSkill', 'DamageAttribute',
    'DamageHealth', 'DamageMagicka', 'DamageFatigue', 'DamageSkill', 'Poison', 'WeaknesstoFire', 'WeaknesstoFrost',
    'WeaknesstoShock', 'WeaknesstoMagicka', 'WeaknesstoCommonDisease', 'WeaknesstoBlightDisease',
    'WeaknesstoCorprusDisease', 'WeaknesstoPoison', 'WeaknesstoNormalWeapons', 'DisintegrateWeapon',
    'DisintegrateArmor', 'Invisibility', 'Chameleon', 'Light', 'Sanctuary', 'NightEye', 'Charm', 'Paralyze',
    'Silence', 'Blind', 'Sound', 'CalmHumanoid', 'CalmCreature', 'FrenzyHumanoid', 'FrenzyCreature',
    'DemoralizeHumanoid', 'DemoralizeCreature', 'RallyHumanoid', 'RallyCreature', 'Dispel', 'Soultrap',
    'Telekinesis', 'Mark', 'Recall', 'DivineIntervention', 'AlmsiviIntervention', 'DetectAnimal',
    'DetectEnchantment', 'DetectKey', 'SpellAbsorption', 'Reflect', 'CureCommonDisease', 'CureBlightDisease',
    'CureCorprusDisease', 'CurePoison', 'CureParalyzation', 'RestoreAttribute', 'RestoreHealth',
    'RestoreSpellPoints', 'RestoreFatigue', 'RestoreSkill', 'FortifyAttribute', 'FortifyHealth',
    'FortifySpellpoints', 'FortifyFatigue', 'FortifySkill', 'FortifyMagickaMultiplier', 'AbsorbAttribute',
    'AbsorbHealth', 'AbsorbSpellPoints', 'AbsorbFatigue', 'AbsorbSkill', 'ResistFire', 'ResistFrost', 'ResistShock',
    'ResistMagicka', 'ResistCommonDisease', 'ResistBlightDisease', 'ResistCorprusDisease', 'ResistPoison',
    'ResistNormalWeapons', 'ResistParalysis', 'RemoveCurse', 'TurnUndead', 'SummonScamp', 'SummonClannfear',
    'SummonDaedroth', 'SummonDremora', 'SummonAncestralGhost', 'SummonSkeletalMinion', 'SummonLeastBonewalker',
    'SummonGreaterBonewalker', 'SummonBonelord', 'SummonWingedTwilight', 'SummonHunger', 'SummonGoldenSaint',
    'SummonFlameAtronach', 'SummonFrostAtronach', 'SummonStormAtronach', 'FortifyAttackBonus', 'CommandCreatures',
    'CommandHumanoids', 'BoundDagger', 'BoundLongsword', 'BoundMace', 'BoundBattleAxe', 'BoundSpear',
    'BoundLongbow', 'ExtraSpell', 'BoundCuirass', 'BoundHelm', 'BoundBoots', 'BoundShield', 'BoundGloves', 'Corpus',
    'Vampirism', 'SummonCenturionSphere', 'SunDamage', 'StuntedMagicka', 'SummonFabricant', 'SummonCreature01',
    'SummonCreature02', 'SummonCreature03', 'SummonCreature04', 'SummonCreature05']

HARDCODED_FLAGS = [
    0x11c8, 0x11c0, 0x11c8, 0x11e0, 0x11e0, 0x11e0, 0x11e0, 0x11d0, 0x11c0, 0x11c0, 0x11e0, 0x11c0, 0x11184,
    0x11184, 0x1f0, 0x1f0, 0x1f0, 0x11d2, 0x11f0, 0x11d0, 0x11d0, 0x11d1, 0x1d2, 0x1f0, 0x1d0, 0x1d0, 0x1d1, 0x1f0,
    0x11d0, 0x11d0, 0x11d0, 0x11d0, 0x11d0, 0x11d0, 0x11d0, 0x11d0, 0x11d0, 0x1d0, 0x1d0, 0x11c8, 0x31c0, 0x11c0,
    0x11c0, 0x11c0, 0x1180, 0x11d8, 0x11d8, 0x11d0, 0x11d0, 0x11180, 0x11180, 0x11180, 0x11180, 0x11180, 0x11180,
    0x11180, 0x11180, 0x11c4, 0x111b8, 0x1040, 0x104c, 0x104c, 0x104c, 0x104c, 0x1040, 0x1040, 0x1040, 0x11c0,
    0x11c0, 0x1cc, 0x1cc, 0x1cc, 0x1cc, 0x1cc, 0x1c2, 0x1c0, 0x1c0, 0x1c0, 0x1c1, 0x11c2, 0x11c0, 0x11c0, 0x11c0,
    0x11c1, 0x11c0, 0x21192, 0x20190, 0x20190, 0x20190, 0x21191, 0x11c0, 0x11c0, 0x11c0, 0x11c0, 0x11c0, 0x11c0,
    0x11c0, 0x11c0, 0x11c0, 0x11c0, 0x1c0, 0x11190, 0x9048, 0x9048, 0x9048, 0x9048, 0x9048, 0x9048, 0x9048, 0x9048,
    0x9048, 0x9048, 0x9048, 0x9048, 0x9048, 0x9048, 0x9048, 0x11c0, 0x1180, 0x1180, 0x5048, 0x5048, 0x5048, 0x5048,
    0x5048, 0x5048, 0x1188, 0x5048, 0x5048, 0x5048, 0x5048, 0x5048, 0x1048, 0x104c, 0x1048, 0x40, 0x11c8, 0x1048,
    0x1048, 0x1048, 0x1048, 0x1048, 0x1048]

MODIFIABLE = 0x200 | 0x400 | 0x800
FLAG_NAMES = {0x1: "target_skill", 0x2: "target_attribute", 0x4: "no_duration", 0x8: "no_magnitude",
              0x10: "harmful", 0x20: "continuous_vfx", 0x40: "cast_self", 0x80: "cast_touch", 0x100: "cast_target",
              0x200: "spellmaking", 0x400: "enchanting", 0x800: "negative_light", 0x1000: "applied_once",
              0x4000: "non_recastable", 0x10000: "unreflectable", 0x20000: "caster_linked"}
# szkoła (MEDT) → indeks umiejętności: przemiana, przywołanie, zniszczenie, iluzja, mistycyzm, przywrócenie
SCHOOL_SKILLS = [11, 13, 10, 12, 14, 15]
