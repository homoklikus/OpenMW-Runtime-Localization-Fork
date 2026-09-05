#include "journalentry.hpp"

#include <stdexcept>

#include <components/esm3/journalentry.hpp>
#include <components/esm3/loadnpc.hpp>

#include <components/interpreter/defines.hpp>
#include <components/translation/translation.hpp>

#include "../mwbase/environment.hpp"
#include "../mwbase/windowmanager.hpp"
#include "../mwbase/world.hpp"

#include "../mwworld/class.hpp"
#include "../mwworld/esmstore.hpp"
#include "../mwworld/globals.hpp"

#include "../mwscript/interpretercontext.hpp"

namespace MWDialogue
{
    Entry::Entry(const ESM::RefId& topic, const ESM::RefId& infoId, const MWWorld::Ptr& actor)
        : mInfoId(infoId)
    {
        const ESM::Dialogue* dialogue = MWBase::Environment::get().getESMStore()->get<ESM::Dialogue>().find(topic);

        for (ESM::Dialogue::InfoContainer::const_iterator iter(dialogue->mInfo.begin()); iter != dialogue->mInfo.end();
             ++iter)
            if (iter->mId == mInfoId)
            {
                // Translate INFO before journal define expansion.
                const auto& translations
                    = MWBase::Environment::get().getWindowManager()->getTranslationDataStorage();

                Translation::Storage::NpcGender npcGender = Translation::Storage::NpcGender::None;
                if (!actor.isEmpty() && actor.getClass().isNpc())
                {
                    const auto* npc = actor.get<ESM::NPC>();
                    npcGender = npc->mBase->isMale() ? Translation::Storage::NpcGender::Male
                                                     : Translation::Storage::NpcGender::Female;
                }

                Translation::Storage::PlayerGender playerGender = Translation::Storage::PlayerGender::None;
                const MWWorld::Ptr player = MWBase::Environment::get().getWorld()->getPlayerPtr();
                if (!player.isEmpty() && player.getClass().isNpc())
                {
                    const auto* playerNpc = player.get<ESM::NPC>();
                    playerGender = playerNpc->mBase->isMale() ? Translation::Storage::PlayerGender::Male
                                                              : Translation::Storage::PlayerGender::Female;
                }

                const std::string_view response = translations.translateInfoResponse(
                    dialogue->mStringId, iter->mId.serializeText(), iter->mResponse, npcGender, playerGender);

                if (actor.isEmpty())
                {
                    MWScript::InterpreterContext interpreterContext(nullptr, MWWorld::Ptr());
                    mText = Interpreter::fixDefinesDialog(response, interpreterContext);
                }
                else
                {
                    MWScript::InterpreterContext interpreterContext(&actor.getRefData().getLocals(), actor);
                    mText = Interpreter::fixDefinesDialog(response, interpreterContext);
                }

                return;
            }

        throw std::runtime_error("unknown info ID " + mInfoId.toDebugString() + " for topic " + topic.toDebugString());
    }

    Entry::Entry(const ESM::JournalEntry& record)
        : mInfoId(record.mInfo)
        , mText(record.mText)
        , mActorName(record.mActorName)
    {
    }

    const std::string& Entry::getText() const
    {
        return mText;
    }

    void Entry::write(ESM::JournalEntry& entry) const
    {
        entry.mInfo = mInfoId;
        entry.mText = mText;
        entry.mActorName = mActorName;
    }

    JournalEntry::JournalEntry(const ESM::RefId& topic, const ESM::RefId& infoId, const MWWorld::Ptr& actor)
        : Entry(topic, infoId, actor)
        , mTopic(topic)
    {
    }

    JournalEntry::JournalEntry(const ESM::JournalEntry& record)
        : Entry(record)
        , mTopic(record.mTopic)
    {
    }

    void JournalEntry::write(ESM::JournalEntry& entry) const
    {
        Entry::write(entry);
        entry.mTopic = mTopic;
    }

    JournalEntry JournalEntry::makeFromQuest(const ESM::RefId& topic, int index)
    {
        return JournalEntry(topic, idFromIndex(topic, index), MWWorld::Ptr());
    }

    const ESM::RefId& JournalEntry::idFromIndex(const ESM::RefId& topic, int index)
    {
        const ESM::Dialogue* dialogue = MWBase::Environment::get().getESMStore()->get<ESM::Dialogue>().find(topic);

        for (ESM::Dialogue::InfoContainer::const_iterator iter(dialogue->mInfo.begin()); iter != dialogue->mInfo.end();
             ++iter)
            if (iter->mData.mJournalIndex == index)
            {
                return iter->mId;
            }

        throw std::runtime_error("unknown journal index for topic " + topic.toDebugString());
    }

    StampedJournalEntry::StampedJournalEntry()
        : mDay(0)
        , mMonth(0)
        , mDayOfMonth(0)
    {
    }

    StampedJournalEntry::StampedJournalEntry(const ESM::RefId& topic, const ESM::RefId& infoId, int day, int month,
        int dayOfMonth, const MWWorld::Ptr& actor)
        : JournalEntry(topic, infoId, actor)
        , mDay(day)
        , mMonth(month)
        , mDayOfMonth(dayOfMonth)
    {
    }

    StampedJournalEntry::StampedJournalEntry(const ESM::JournalEntry& record)
        : JournalEntry(record)
        , mDay(record.mDay)
        , mMonth(record.mMonth)
        , mDayOfMonth(record.mDayOfMonth)
    {
    }

    void StampedJournalEntry::write(ESM::JournalEntry& entry) const
    {
        JournalEntry::write(entry);
        entry.mDay = mDay;
        entry.mMonth = mMonth;
        entry.mDayOfMonth = mDayOfMonth;
    }

    StampedJournalEntry StampedJournalEntry::makeFromQuest(
        const ESM::RefId& topic, int index, const MWWorld::Ptr& actor)
    {
        const int day = MWBase::Environment::get().getWorld()->getGlobalInt(MWWorld::Globals::sDaysPassed);
        const int month = MWBase::Environment::get().getWorld()->getGlobalInt(MWWorld::Globals::sMonth);
        const int dayOfMonth = MWBase::Environment::get().getWorld()->getGlobalInt(MWWorld::Globals::sDay);

        return StampedJournalEntry(topic, idFromIndex(topic, index), day, month, dayOfMonth, actor);
    }
}
