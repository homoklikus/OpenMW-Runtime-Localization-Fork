#include "contentbindings.hpp"

#include <vector>

#include <components/esm/attr.hpp>
#include <components/esm3/loadacti.hpp>
#include <components/esm3/loadalch.hpp>
#include <components/esm3/loadappa.hpp>
#include <components/esm3/loadarmo.hpp>
#include <components/esm3/loadbsgn.hpp>
#include <components/esm3/loadclot.hpp>
#include <components/esm3/loadcont.hpp>
#include <components/esm3/loadbook.hpp>
#include <components/esm3/loadclas.hpp>
#include <components/esm3/loadcrea.hpp>
#include <components/esm3/loadfact.hpp>
#include <components/esm3/loadnpc.hpp>
#include <components/esm3/loadrace.hpp>
#include <components/esm3/loaddoor.hpp>
#include <components/esm3/loadench.hpp>
#include <components/esm3/loadingr.hpp>
#include <components/esm3/loadligh.hpp>
#include <components/esm3/loadlock.hpp>
#include <components/esm3/loadmgef.hpp>
#include <components/esm3/loadmisc.hpp>
#include <components/esm3/loadprob.hpp>
#include <components/esm3/loadregn.hpp>
#include <components/esm3/loadrepa.hpp>
#include <components/esm3/loadskil.hpp>
#include <components/esm3/loadsoun.hpp>
#include <components/esm3/loadspel.hpp>
#include <components/esm3/loadstat.hpp>
#include <components/esm3/loadweap.hpp>
#include <components/translation/translation.hpp>
#include <components/fallback/fallback.hpp>
#include <components/lua/util.hpp>

#include "context.hpp"
#include "magictypebindings.hpp"
#include "soundbindings.hpp"
#include "types/modelproperty.hpp"
#include "types/types.hpp"

#include "../mwbase/environment.hpp"
#include "../mwbase/windowmanager.hpp"
#include "../mwworld/esmstore.hpp"

namespace
{
    template <class T>
    struct MutableStore
    {
        MWWorld::Store<T>& mStore;
    };

    template <class T>
    using TableToRecord = T (*)(const sol::table&);

    ESM::RefId validateId(std::string_view value)
    {
        if (value.empty())
            throw std::runtime_error("ID cannot be empty");
        if (auto id = ESM::StringRefId::deserializeExisting(value))
            return *id;
        // Check if this ID would be interpreted as something other than a StringRefId
        ESM::RefId id = ESM::RefId::deserializeText(value);
        if (!id.empty())
            throw std::runtime_error("Non-string ID not allowed");
        return ESM::RefId::stringRefId(value);
    }

    template <class T, class Update>
    bool updateLocalizedStaticRecord(MWWorld::Store<T>& store, std::string_view idText, Update&& update)
    {
        const ESM::RefId id = ESM::RefId::deserializeText(idText);
        const T* found = store.search(id);
        if (found == nullptr)
            return false;

        T record = *found;
        update(record);
        store.insertStatic(record);
        return true;
    }
}

namespace sol
{
    template <class T>
    struct is_automagical<MutableStore<T>> : std::false_type
    {
    };

    template <class T>
    struct is_automagical<MWLua::MutableRecord<T>> : std::false_type
    {
    };
}

namespace MWLua
{
    namespace
    {
        template <class LuaType, class Record, class Mapper = LuaType (*)(const Record*, sol::this_state)>
        void addESMVariantStore(
            sol::state_view& lua, MWWorld::Store<Record>& store, std::string_view name, Mapper mapper, auto&& newIndex)
        {
            using Store = MutableStore<Record>;
            sol::usertype<Store> storeT = lua.new_usertype<Store>(name);
            storeT[sol::meta_function::length] = [](const Store& self) { return self.mStore.getSize(); };
            storeT[sol::meta_function::index] = sol::overload(
                [=](const Store& self, size_t index, sol::this_state state) -> LuaType {
                    if (index == 0 || index > self.mStore.getSize())
                        return mapper(nullptr, state);
                    const Record* rec = self.mStore.at(LuaUtil::fromLuaIndex(index));
                    return mapper(rec, state);
                },
                [=](const Store& self, std::string_view id, sol::this_state state) -> LuaType {
                    const Record* rec = self.mStore.search(ESM::RefId::deserializeText(id));
                    return mapper(rec, state);
                });
            storeT[sol::meta_function::new_index] = std::move(newIndex);
            storeT[sol::meta_function::ipairs] = lua["ipairsForArray"].template get<sol::function>();
            storeT[sol::meta_function::pairs] = [=](const Store& self) {
                return sol::as_function(
                    [&, index = std::size_t(0)](
                        sol::this_state state) mutable -> std::pair<std::optional<ESM::RefId>, LuaType> {
                        if (index >= self.mStore.getSize())
                            return { {}, mapper(nullptr, state) };
                        const Record* rec = self.mStore.at(index++);
                        return { rec->mId, mapper(rec, state) };
                    });
            };
        }

        sol::table initGameSettingBindings(sol::state_view& lua, MWWorld::Store<ESM::GameSetting>& store)
        {
            addESMVariantStore<sol::object>(
                lua, store, "GameSettingsContentStore",
                [](const ESM::GameSetting* gmst, sol::this_state state) -> sol::object {
                    if (gmst == nullptr)
                        return sol::nil;
                    if (gmst->mValue.getType() == ESM::VT_String)
                        return sol::make_object(state, gmst->mValue.getString());
                    else if (gmst->mValue.getType() == ESM::VT_None)
                        return sol::make_object(state, std::string_view{});
                    else if (gmst->mValue.getType() == ESM::VT_Int)
                        return sol::make_object(state, gmst->mValue.getInteger());
                    return sol::make_object(state, gmst->mValue.getFloat());
                },
                [](MutableStore<ESM::GameSetting>& self, std::string_view idString, const sol::object& obj) {
                    ESM::RefId id = validateId(idString);
                    if (obj == sol::nil)
                    {
                        self.mStore.eraseStatic(id);
                        return;
                    }
                    bool preferFloat = false;
                    ESM::GameSetting gmst;
                    if (auto* found = self.mStore.search(id))
                    {
                        gmst = *found;
                        preferFloat = gmst.mValue.getType() == ESM::VT_Float;
                    }
                    else
                    {
                        gmst.blank();
                        gmst.mId = id;
                        preferFloat = id.startsWith("f");
                    }
                    if (obj.is<std::string_view>())
                    {
                        gmst.mValue.setType(ESM::VT_String);
                        gmst.mValue.setString(obj.as<std::string>());
                    }
                    else
                    {
                        const double value = LuaUtil::cast<double>(obj);
                        const int32_t intV = static_cast<int32_t>(value);
                        const float floatV = static_cast<float>(value);
                        if (intV == value && (!preferFloat || floatV != value))
                        {
                            gmst.mValue.setType(ESM::VT_Int);
                            gmst.mValue.setInteger(intV);
                        }
                        else
                        {
                            gmst.mValue.setType(ESM::VT_Float);
                            gmst.mValue.setFloat(floatV);
                        }
                    }
                    self.mStore.insertStatic(gmst);
                });
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::GameSetting>{ store };
            api["getFallbacks"] = [](sol::this_state state) {
                sol::table out(state, sol::create);
                for (auto& [key, value] : Fallback::Map::getIntFallbackMap())
                    out[key] = sol::make_object(state, value);
                for (auto& [key, value] : Fallback::Map::getFloatFallbackMap())
                    out[key] = sol::make_object(state, value);
                for (auto& [key, value] : Fallback::Map::getNonNumericFallbackMap())
                    out[key] = sol::make_object(state, value);
                return out;
            };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initGlobalVariableBindings(sol::state_view& lua, MWWorld::Store<ESM::Global>& store)
        {
            addESMVariantStore<std::optional<float>>(
                lua, store, "GlobalsContentStore",
                [](const ESM::Global* global, sol::this_state) -> std::optional<float> {
                    if (global == nullptr)
                        return {};
                    return global->mValue.getFloat();
                },
                [](MutableStore<ESM::Global>& self, std::string_view idString, const sol::object& obj) {
                    ESM::RefId id = validateId(idString);
                    if (obj == sol::nil)
                    {
                        self.mStore.eraseStatic(id);
                        return;
                    }
                    float value = LuaUtil::cast<float>(obj);
                    bool preferFloat = false;
                    ESM::Global global;
                    if (auto* found = self.mStore.search(id))
                    {
                        global = *found;
                        preferFloat = global.mValue.getType() == ESM::VT_Float;
                    }
                    else
                    {
                        global.blank();
                        global.mId = id;
                    }
                    int32_t intV = static_cast<int32_t>(value);
                    if (intV == value && !preferFloat)
                    {
                        global.mValue.setType(ESM::VT_Long);
                        global.mValue.setInteger(intV);
                    }
                    else
                    {
                        global.mValue.setType(ESM::VT_Float);
                        global.mValue.setFloat(value);
                    }
                    self.mStore.insertStatic(global);
                });
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Global>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        template <class T>
        void addRecordStoreBindings(sol::state_view& lua, TableToRecord<T> parseRecord)
        {
            using Store = MutableStore<T>;
            sol::usertype<Store> storeT = lua.new_usertype<Store>(std::string(T::getRecordType()) + "sContentStore");
            storeT[sol::meta_function::length] = [](const Store& self) { return self.mStore.getSize(); };
            storeT[sol::meta_function::ipairs] = lua["ipairsForArray"].template get<sol::function>();
            storeT[sol::meta_function::pairs] = lua["ipairsForArray"].template get<sol::function>();
            storeT[sol::meta_function::index] = sol::overload(
                [](const Store& self, size_t index) -> std::optional<MutableRecord<T>> {
                    if (index == 0 || index > self.mStore.getSize())
                        return {};
                    return MutableRecord<T>{ self.mStore, self.mStore.at(LuaUtil::fromLuaIndex(index))->mId };
                },
                [](const Store& self, std::string_view id) -> std::optional<MutableRecord<T>> {
                    const auto* record = self.mStore.search(ESM::RefId::deserializeText(id));
                    if (record == nullptr)
                        return {};
                    return MutableRecord<T>{ self.mStore, record->mId };
                });
            storeT[sol::meta_function::new_index] = sol::overload(
                [](Store& self, std::string_view idString, const MutableRecord<T>& otherRecord) {
                    ESM::RefId id = validateId(idString);
                    T record = otherRecord.find();
                    record.mId = id;
                    self.mStore.insertStatic(record);
                },
                [parseRecord](Store& self, std::string_view idString, sol::lua_table table) {
                    ESM::RefId id = validateId(idString);
                    T record = parseRecord(table);
                    record.mId = id;
                    self.mStore.insertStatic(record);
                },
                [](Store& self, std::string_view idString, const sol::nil_t&) {
                    self.mStore.eraseStatic(validateId(idString));
                });
        }

        sol::table initActivatorBindings(sol::state_view& lua, MWWorld::Store<ESM::Activator>& store)
        {
            addRecordStoreBindings<ESM::Activator>(lua, &MWLua::tableToActivator);
            addMutableActivatorType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Activator>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initBookBindings(sol::state_view& lua, MWWorld::Store<ESM::Book>& store)
        {
            addRecordStoreBindings<ESM::Book>(lua, &MWLua::tableToBook);
            addMutableBookType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Book>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initDoorBindings(sol::state_view& lua, MWWorld::Store<ESM::Door>& store)
        {
            addRecordStoreBindings<ESM::Door>(lua, &MWLua::tableToDoor);
            addMutableDoorType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Door>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initEnchantmentBindings(sol::state_view& lua, MWWorld::Store<ESM::Enchantment>& store)
        {
            addRecordStoreBindings<ESM::Enchantment>(lua, &MWLua::tableToEnchantment);
            addMutableEnchantmentType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Enchantment>{ store };
            api["TYPE"]
                = LuaUtil::makeStrictReadOnly(LuaUtil::tableFromPairs<std::string_view, ESM::Enchantment::Type>(lua,
                    {
                        { "CastOnce", ESM::Enchantment::Type::CastOnce },
                        { "CastOnStrike", ESM::Enchantment::Type::WhenStrikes },
                        { "CastOnUse", ESM::Enchantment::Type::WhenUsed },
                        { "ConstantEffect", ESM::Enchantment::Type::ConstantEffect },
                    }));
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initIngredientBindings(sol::state_view& lua, MWWorld::Store<ESM::Ingredient>& store)
        {
            addRecordStoreBindings<ESM::Ingredient>(lua, &MWLua::tableToIngredient);
            addMutableIngredientType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Ingredient>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initLightBindings(sol::state_view& lua, MWWorld::Store<ESM::Light>& store)
        {
            addRecordStoreBindings<ESM::Light>(lua, &MWLua::tableToLight);
            addMutableLightType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Light>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initMagicEffectBindings(sol::state_view& lua, MWWorld::Store<ESM::MagicEffect>& store)
        {
            addRecordStoreBindings<ESM::MagicEffect>(lua, &MWLua::tableToMagicEffect);
            addMutableMagicEffectType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::MagicEffect>{ store };
            // We can't get rid of the GMST table engine side because mwscript needs it, so intead of copying it into a
            // Lua file we've got this hidden function to generate it
            api["_getGMSTs"] = [](sol::this_state state) {
                sol::table gmsts(state, sol::create);
                for (int i = 0; i < ESM::MagicEffect::Length; ++i)
                {
                    const ESM::RefId effect = ESM::MagicEffect::indexToRefId(i);
                    const std::string_view gmst = ESM::MagicEffect::refIdToGmstString(effect);
                    gmsts[effect] = gmst;
                }
                return gmsts;
            };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initMiscBindings(sol::state_view& lua, MWWorld::Store<ESM::Miscellaneous>& store)
        {
            addRecordStoreBindings<ESM::Miscellaneous>(lua, &MWLua::tableToMisc);
            addMutableMiscType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Miscellaneous>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initPotionBindings(sol::state_view& lua, MWWorld::Store<ESM::Potion>& store)
        {
            addRecordStoreBindings<ESM::Potion>(lua, &MWLua::tableToPotion);
            addMutablePotionType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Potion>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initProbeBindings(sol::state_view& lua, MWWorld::Store<ESM::Probe>& store)
        {
            addRecordStoreBindings<ESM::Probe>(lua, &MWLua::tableToProbe);
            addMutableProbeType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Probe>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initSpellBindings(sol::state_view& lua, MWWorld::Store<ESM::Spell>& store)
        {
            addRecordStoreBindings<ESM::Spell>(lua, &MWLua::tableToSpell);
            addMutableSpellType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Spell>{ store };
            api["TYPE"]
                = LuaUtil::makeStrictReadOnly(LuaUtil::tableFromPairs<std::string_view, ESM::Spell::SpellType>(lua,
                    {
                        { "Spell", ESM::Spell::ST_Spell },
                        { "Ability", ESM::Spell::ST_Ability },
                        { "Blight", ESM::Spell::ST_Blight },
                        { "Disease", ESM::Spell::ST_Disease },
                        { "Curse", ESM::Spell::ST_Curse },
                        { "Power", ESM::Spell::ST_Power },
                    }));
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initTranslationBindings(sol::state_view& lua, MWWorld::ESMStore& esmStore)
        {
            auto& storage
                = MWBase::Environment::get().getWindowManager()->getWritableTranslationDataStorage();

            auto* factionStore = &esmStore.getWritable<ESM::Faction>();
            auto* classStore = &esmStore.getWritable<ESM::Class>();
            auto* raceStore = &esmStore.getWritable<ESM::Race>();
            auto* npcStore = &esmStore.getWritable<ESM::NPC>();
            auto* creatureStore = &esmStore.getWritable<ESM::Creature>();
            auto* weaponStore = &esmStore.getWritable<ESM::Weapon>();

            auto* armorStore = &esmStore.getWritable<ESM::Armor>();
            auto* clothingStore = &esmStore.getWritable<ESM::Clothing>();
            auto* containerStore = &esmStore.getWritable<ESM::Container>();
            auto* apparatusStore = &esmStore.getWritable<ESM::Apparatus>();
            auto* repairStore = &esmStore.getWritable<ESM::Repair>();
            auto* lockpickStore = &esmStore.getWritable<ESM::Lockpick>();
            auto* skillStore = &esmStore.getWritable<ESM::Skill>();
            auto* birthSignStore = &esmStore.getWritable<ESM::BirthSign>();
            auto* regionStore = &esmStore.getWritable<ESM::Region>();
            auto* magicEffectStore = &esmStore.getWritable<ESM::MagicEffect>();
            auto* attributeStore = &esmStore.getWritable<ESM::Attribute>();
            auto* gameSettingStore = &esmStore.getWritable<ESM::GameSetting>();

            sol::table api(lua, sol::create);

            api["setCellName"] = [&storage](std::string_view sourceName, std::string_view displayName) {
                storage.addCellNameTranslation(sourceName, displayName);
            };
            api["setTopicName"] = [&storage](std::string_view topicId, std::string_view displayName) {
                storage.addTopicNameTranslation(topicId, displayName);
            };
            api["setTopicForm"] = [&storage](std::string_view phrase, std::string_view topicId) {
                storage.setPhraseForm(phrase, topicId);
            };
            api["setTopicKeyword"] = [&storage](std::string_view topicId, std::string_view keyword) {
                storage.addTopicKeyword(topicId, keyword);
            };
            api["setInfoResponse"]
                = [&storage](std::string_view topicId, std::string_view infoId, std::string_view response) {
                      storage.addInfoResponseTranslation(topicId, infoId, response);
                  };
            api["setChoiceText"] = [&storage](std::string_view sourceText, std::string_view displayText) {
                storage.addChoiceTranslation(sourceText, displayText);
            };
            api["setScriptString"] = [&storage](std::string_view sourceText, std::string_view displayText) {
                storage.addScriptStringTranslation(sourceText, displayText);
            };

            api["setFactionName"] = [factionStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*factionStore, id, [&](ESM::Faction& record) {
                    record.mName = std::string(name);
                });
            };
            api["setFactionRankName"]
                = [factionStore](std::string_view id, std::size_t rankIndex, std::string_view name) {
                      if (rankIndex >= 10)
                          return false;
                      return updateLocalizedStaticRecord(*factionStore, id, [&](ESM::Faction& record) {
                          record.mRanks[rankIndex] = std::string(name);
                      });
                  };

            api["setClassName"] = [classStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*classStore, id, [&](ESM::Class& record) {
                    record.mName = std::string(name);
                });
            };
            api["setClassDescription"] = [classStore](std::string_view id, std::string_view description) {
                return updateLocalizedStaticRecord(*classStore, id, [&](ESM::Class& record) {
                    record.mDescription = std::string(description);
                });
            };

            api["setRaceName"] = [raceStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*raceStore, id, [&](ESM::Race& record) {
                    record.mName = std::string(name);
                });
            };
            api["setRaceDescription"] = [raceStore](std::string_view id, std::string_view description) {
                return updateLocalizedStaticRecord(*raceStore, id, [&](ESM::Race& record) {
                    record.mDescription = std::string(description);
                });
            };

            api["setNpcName"] = [npcStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*npcStore, id, [&](ESM::NPC& record) {
                    record.mName = std::string(name);
                });
            };
            api["setCreatureName"] = [creatureStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*creatureStore, id, [&](ESM::Creature& record) {
                    record.mName = std::string(name);
                });
            };
            api["setWeaponName"] = [weaponStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*weaponStore, id, [&](ESM::Weapon& record) {
                    record.mName = std::string(name);
                });
            };

            api["setArmorName"] = [armorStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*armorStore, id, [&](ESM::Armor& record) {
                    record.mName = std::string(name);
                });
            };
            api["setClothingName"] = [clothingStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*clothingStore, id, [&](ESM::Clothing& record) {
                    record.mName = std::string(name);
                });
            };
            api["setContainerName"] = [containerStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*containerStore, id, [&](ESM::Container& record) {
                    record.mName = std::string(name);
                });
            };
            api["setApparatusName"] = [apparatusStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*apparatusStore, id, [&](ESM::Apparatus& record) {
                    record.mName = std::string(name);
                });
            };
            api["setRepairName"] = [repairStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*repairStore, id, [&](ESM::Repair& record) {
                    record.mName = std::string(name);
                });
            };
            api["setLockpickName"] = [lockpickStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*lockpickStore, id, [&](ESM::Lockpick& record) {
                    record.mName = std::string(name);
                });
            };

            api["setSkillDescription"]
                = [skillStore](std::size_t skillIndex, std::string_view description) {
                      if (skillIndex >= static_cast<std::size_t>(ESM::Skill::Length))
                          return false;

                      const ESM::RefId id = ESM::Skill::indexToRefId(static_cast<int>(skillIndex));
                      const ESM::Skill* found = skillStore->search(id);
                      if (found == nullptr)
                          return false;

                      ESM::Skill record = *found;
                      record.mDescription = std::string(description);
                      skillStore->insertStatic(record);
                      return true;
                  };

            api["setBirthSignName"] = [birthSignStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*birthSignStore, id, [&](ESM::BirthSign& record) {
                    record.mName = std::string(name);
                });
            };
            api["setBirthSignDescription"]
                = [birthSignStore](std::string_view id, std::string_view description) {
                      return updateLocalizedStaticRecord(*birthSignStore, id, [&](ESM::BirthSign& record) {
                          record.mDescription = std::string(description);
                      });
                  };
            api["setRegionName"] = [regionStore](std::string_view id, std::string_view name) {
                return updateLocalizedStaticRecord(*regionStore, id, [&](ESM::Region& record) {
                    record.mName = std::string(name);
                });
            };

            api["setMagicEffectDescription"]
                = [magicEffectStore](std::size_t effectIndex, std::string_view description) {
                      if (effectIndex >= static_cast<std::size_t>(ESM::MagicEffect::Length))
                          return false;

                      const ESM::RefId id = ESM::MagicEffect::indexToRefId(static_cast<int>(effectIndex));
                      const ESM::MagicEffect* found = magicEffectStore->search(id);
                      if (found == nullptr)
                          return false;

                      ESM::MagicEffect record = *found;
                      record.mDescription = std::string(description);
                      magicEffectStore->insertStatic(record);
                      return true;
                  };

            api["refreshDerivedLocalization"]
                = [gameSettingStore, skillStore, attributeStore, magicEffectStore]() {
                      // Skill names and magic-school names are derived from GMST at startup.
                      skillStore->setUp(*gameSettingStore);

                      // Attribute names/descriptions are derived from GMST too.
                      attributeStore->setUp(*gameSettingStore);

                      // MGEF display names are derived from sEffect* GMSTs.
                      std::vector<ESM::RefId> effectIds;
                      effectIds.reserve(magicEffectStore->getSize());
                      for (const ESM::MagicEffect& effect : *magicEffectStore)
                          effectIds.push_back(effect.mId);

                      std::size_t updated = 0;
                      for (const ESM::RefId& id : effectIds)
                      {
                          const std::string_view gmstId = ESM::MagicEffect::refIdToGmstString(id);
                          const ESM::GameSetting* gmst = gameSettingStore->search(gmstId);
                          const ESM::MagicEffect* found = magicEffectStore->search(id);
                          if (gmst == nullptr || found == nullptr || gmst->mValue.getType() != ESM::VT_String)
                              continue;

                          ESM::MagicEffect record = *found;
                          record.mName = gmst->mValue.getString();
                          magicEffectStore->insertStatic(record);
                          ++updated;
                      }

                      return updated;
                  };

            return LuaUtil::makeReadOnly(api);
        }

        sol::table initStaticBindings(sol::state_view& lua, MWWorld::Store<ESM::Static>& store)
        {
            addRecordStoreBindings<ESM::Static>(lua, &MWLua::tableToStatic);
            addMutableStaticType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Static>{ store };
            return LuaUtil::makeReadOnly(api);
        }

        sol::table initSoundBindings(sol::state_view& lua, MWWorld::Store<ESM::Sound>& store)
        {
            addRecordStoreBindings<ESM::Sound>(lua, &MWLua::tableToSound);
            addMutableSoundType(lua);
            sol::table api(lua, sol::create);
            api["records"] = MutableStore<ESM::Sound>{ store };
            return LuaUtil::makeReadOnly(api);
        }
    }

    sol::table initContentPackage(const Context& context)
    {
        auto lua = context.sol();
        sol::table api(lua, sol::create);
        MWWorld::ESMStore& esmStore = *MWBase::Environment::get().getESMStore();
        api["activators"] = initActivatorBindings(lua, esmStore.getWritable<ESM::Activator>());
        api["books"] = initBookBindings(lua, esmStore.getWritable<ESM::Book>());
        api["doors"] = initDoorBindings(lua, esmStore.getWritable<ESM::Door>());
        api["enchantments"] = initEnchantmentBindings(lua, esmStore.getWritable<ESM::Enchantment>());
        api["gameSettings"] = initGameSettingBindings(lua, esmStore.getWritable<ESM::GameSetting>());
        api["globals"] = initGlobalVariableBindings(lua, esmStore.getWritable<ESM::Global>());
        api["ingredients"] = initIngredientBindings(lua, esmStore.getWritable<ESM::Ingredient>());
        api["lights"] = initLightBindings(lua, esmStore.getWritable<ESM::Light>());
        api["magicEffects"] = initMagicEffectBindings(lua, esmStore.getWritable<ESM::MagicEffect>());
        api["miscs"] = initMiscBindings(lua, esmStore.getWritable<ESM::Miscellaneous>());
        api["potions"] = initPotionBindings(lua, esmStore.getWritable<ESM::Potion>());
        api["probes"] = initProbeBindings(lua, esmStore.getWritable<ESM::Probe>());
        api["spells"] = initSpellBindings(lua, esmStore.getWritable<ESM::Spell>());
        api["translations"] = initTranslationBindings(lua, esmStore);
        api["statics"] = initStaticBindings(lua, esmStore.getWritable<ESM::Static>());
        api["sounds"] = initSoundBindings(lua, esmStore.getWritable<ESM::Sound>());
        api["RANGE"] = LuaUtil::makeStrictReadOnly(LuaUtil::tableFromPairs<std::string_view, ESM::RangeType>(lua,
            {
                { "Self", ESM::RT_Self },
                { "Touch", ESM::RT_Touch },
                { "Target", ESM::RT_Target },
            }));
        return LuaUtil::makeReadOnly(api);
    }
}
