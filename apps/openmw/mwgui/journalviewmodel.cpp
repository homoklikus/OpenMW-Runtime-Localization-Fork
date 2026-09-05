#include "journalviewmodel.hpp"

#include <unordered_map>

#include <MyGUI_LanguageManager.h>

#include <components/esm3/loaddial.hpp>
#include <components/misc/strings/algorithm.hpp>
#include <components/translation/translation.hpp>

#include "../mwbase/environment.hpp"
#include "../mwbase/journal.hpp"
#include "../mwbase/windowmanager.hpp"
#include "../mwbase/world.hpp"

#include "../mwdialogue/keywordsearch.hpp"
#include "../mwworld/datetimemanager.hpp"
#include "../mwworld/esmstore.hpp"

namespace MWGui
{

    struct JournalViewModelImpl;

    struct JournalViewModelImpl : JournalViewModel
    {
        mutable bool mKeywordSearchLoaded;
        mutable MWDialogue::KeywordSearch mKeywordSearch;

        mutable std::unordered_map<std::string, const MWDialogue::Topic*> mTopics;

        JournalViewModelImpl() { mKeywordSearchLoaded = false; }

        virtual ~JournalViewModelImpl() = default;

        void load() override {}

        void unload() override
        {
            mKeywordSearch.clear();
            mTopics.clear();
            mKeywordSearchLoaded = false;
        }

        void ensureKeyWordSearchLoaded() const
        {
            if (!mKeywordSearchLoaded)
            {
                MWBase::Journal* journal = MWBase::Environment::get().getJournal();
                MWBase::WindowManager& windowManager = *MWBase::Environment::get().getWindowManager();
                const Translation::Storage& translationStorage = windowManager.getTranslationDataStorage();

                for (const auto& [_, topic] : journal->getTopics())
                {
                    const std::string topicId = Misc::StringUtils::lowerCase(topic.getName());
                    mTopics[topicId] = &topic;
                    mKeywordSearch.seed(translationStorage.topicKeyword(topic.getName()), topicId);
                }

                mKeywordSearchLoaded = true;
            }
        }

        bool isEmpty() const override
        {
            MWBase::Journal* journal = MWBase::Environment::get().getJournal();

            return journal->getEntries().empty();
        }

        static bool containsPotentialDefine(std::string_view text)
        {
            for (std::size_t i = 0; i + 1 < text.size(); ++i)
            {
                const char marker = text[i];
                const char next = text[i + 1];

                if ((marker == '%' || marker == '^')
                    && ((next >= 'A' && next <= 'Z') || (next >= 'a' && next <= 'z') || next == '_'))
                    return true;
            }

            return false;
        }

        std::string localizedEntryText(
            const ESM::RefId& topicId, const ESM::RefId& infoId, const std::string& savedText) const
        {
            const auto& dialogues = MWBase::Environment::get().getESMStore()->get<ESM::Dialogue>();
            const ESM::Dialogue* dialogue = dialogues.search(topicId);
            if (dialogue == nullptr)
                return savedText;

            const ESM::DialInfo* info = nullptr;
            for (const ESM::DialInfo& candidate : dialogue->mInfo)
            {
                if (candidate.mId == infoId)
                {
                    info = &candidate;
                    break;
                }
            }

            if (info == nullptr)
                return savedText;

            const Translation::Storage& translations
                = MWBase::Environment::get().getWindowManager()->getTranslationDataStorage();

            // Old JOUR records contain topic/info/text, but not enough stable actor
            // context to reproduce a historical gender choice. Preserve the saved
            // rendered text instead of selecting default or guessing a variant.
            if (translations.hasInfoResponseGenderVariants(dialogue->mStringId, info->mId.serializeText()))
                return savedText;

            const std::string_view translated
                = translations.translateInfoResponse(dialogue->mStringId, info->mId.serializeText(), savedText);

            // translateInfoResponse returns sourceText itself when no translation exists.
            if (translated.data() == savedText.data() && translated.size() == savedText.size())
                return savedText;

            // Saved journal text already contains define expansion. Old saves do not
            // retain enough actor context to safely expand a newly selected translation.
            if (containsPotentialDefine(translated))
                return savedText;

            return std::string(translated);
        }

        template <typename EntryType, typename Interface>
        struct BaseEntry : Interface
        {
            const EntryType* mEntry;
            JournalViewModelImpl const* mModel;
            ESM::RefId mTopicId;

            BaseEntry(JournalViewModelImpl const* model, const EntryType& entry, const ESM::RefId& topicId)
                : mEntry(&entry)
                , mModel(model)
                , mTopicId(topicId)
            {
            }

            virtual ~BaseEntry() = default;

            mutable bool mLoaded{ false };
            mutable std::string mText;

            struct Token
            {
                size_t mStart;
                size_t mEnd;
                const MWDialogue::Topic* mTopic;
            };

            mutable std::vector<Token> mTokens;

            void ensureLoaded() const
            {
                if (!mLoaded)
                {
                    using namespace MWDialogue;

                    mModel->ensureKeyWordSearchLoaded();
                    MWBase::WindowManager& windowManager = *MWBase::Environment::get().getWindowManager();
                    const Translation::Storage& translationStorage = windowManager.getTranslationDataStorage();

                    const std::string text
                        = mModel->localizedEntryText(mTopicId, mEntry->mInfoId, mEntry->getText());
                    mText.reserve(text.size());

                    auto matches = mModel->mKeywordSearch.parseHyperText(text, translationStorage);
                    mTokens.reserve(matches.size());

                    // Generate the displayed text and a more convenient token list.
                    // The matches we got provide positions in the original text and must be recalculated.
                    KeywordSearch::Point pos = text.begin();
                    for (const KeywordSearch::Match& token : matches)
                    {
                        const std::string_view displayName(token.getDisplayName());
                        mText.append(pos, token.mBeg);
                        mText.append(displayName);
                        pos = token.mEnd;

                        auto value = mModel->mTopics.find(token.mTopicId);
                        if (value != mModel->mTopics.end())
                            mTokens.emplace_back(mText.size() - displayName.size(), mText.size(), value->second);
                    }
                    mText.append(pos, text.end());

                    mLoaded = true;
                }
            }

            std::string_view body() const override
            {
                ensureLoaded();

                return mText;
            }

            void visitSpans(std::function<void(const MWDialogue::Topic*, size_t, size_t)> visitor) const override
            {
                ensureLoaded();

                size_t i = 0;
                for (const Token& token : mTokens)
                {
                    if (i < token.mStart)
                        visitor(nullptr, i, token.mStart);
                    visitor(token.mTopic, token.mStart, token.mEnd);
                    i = token.mEnd;
                }
                if (i < mText.size())
                    visitor(nullptr, i, mText.size());
            }
        };

        void visitQuestNames(bool activeOnly, std::function<void(std::string_view, bool)> visitor) const override
        {
            MWBase::Journal* journal = MWBase::Environment::get().getJournal();

            std::set<std::string_view, Misc::StringUtils::CiComp> visitedQuests;

            // Note that for purposes of the journal GUI, quests are identified by the name, not the ID, so several
            // different quest IDs can end up in the same quest log. A quest log should be considered finished
            // when any quest ID in that log is finished.
            for (const auto& [_, quest] : journal->getQuests())
            {
                // Unfortunately Morrowind.esm has no quest names, since the quest book was added with tribunal.
                // Note that even with Tribunal, some quests still don't have quest names. I'm assuming those are not
                // supposed to appear in the quest book.
                const std::string_view questName = quest.getName();
                if (questName.empty())
                    continue;
                // Don't list the same quest name twice
                if (!visitedQuests.insert(questName).second)
                    continue;

                bool isFinished = std::ranges::find_if(journal->getQuests(), [&](const auto& pair) {
                    return pair.second.isFinished() && Misc::StringUtils::ciEqual(questName, pair.second.getName());
                }) != journal->getQuests().end();

                if (activeOnly && isFinished)
                    continue;

                visitor(questName, isFinished);
            }
        }

        struct JournalEntryImpl : BaseEntry<MWDialogue::StampedJournalEntry, JournalEntry>
        {
            mutable std::string mTimestamp;

            JournalEntryImpl(JournalViewModelImpl const* model, const MWDialogue::StampedJournalEntry& entry)
                : BaseEntry(model, entry, entry.mTopic)
            {
            }

            std::string_view timestamp() const override
            {
                if (mTimestamp.empty())
                {
                    std::string dayStr = MyGUI::LanguageManager::getInstance().replaceTags("#{sDay}");

                    std::ostringstream os;

                    os << mEntry->mDayOfMonth << ' '
                       << MWBase::Environment::get().getWorld()->getTimeManager()->getMonthName(mEntry->mMonth) << " ("
                       << dayStr << " " << (mEntry->mDay) << ')';

                    mTimestamp = os.str();
                }

                return mTimestamp;
            }
        };

        void visitJournalEntries(
            std::string_view questName, std::function<void(JournalEntry const&)> visitor) const override
        {
            MWBase::Journal* journal = MWBase::Environment::get().getJournal();

            if (!questName.empty())
            {
                std::vector<MWDialogue::Quest const*> quests;
                for (const auto& [_, quest] : journal->getQuests())
                {
                    if (Misc::StringUtils::ciEqual(quest.getName(), questName))
                        quests.push_back(&quest);
                }

                for (const MWDialogue::StampedJournalEntry& journalEntry : journal->getEntries())
                {
                    for (const MWDialogue::Quest* quest : quests)
                    {
                        if (quest->getTopic() != journalEntry.mTopic)
                            continue;
                        for (const MWDialogue::Entry& questEntry : *quest)
                        {
                            if (journalEntry.mInfoId == questEntry.mInfoId)
                            {
                                visitor(JournalEntryImpl(this, journalEntry));
                                break;
                            }
                        }
                    }
                }
            }
            else
            {
                for (const MWDialogue::StampedJournalEntry& journalEntry : journal->getEntries())
                    visitor(JournalEntryImpl(this, journalEntry));
            }
        }

        void visitTopicName(
            const MWDialogue::Topic& topic, std::function<void(std::string_view)> visitor) const override
        {
            const Translation::Storage& translationStorage
                = MWBase::Environment::get().getWindowManager()->getTranslationDataStorage();
            visitor(translationStorage.translateTopicName(topic.getName()));
        }

        void visitTopicNamesStartingWith(
            Utf8Stream::UnicodeChar character, std::function<void(std::string_view)> visitor) const override
        {
            MWBase::Journal* journal = MWBase::Environment::get().getJournal();

            const Translation::Storage& translationStorage
                = MWBase::Environment::get().getWindowManager()->getTranslationDataStorage();

            for (const auto& [_, topic] : journal->getTopics())
            {
                std::string_view translatedName = translationStorage.translateTopicName(topic.getName());
                Utf8Stream stream(translatedName);
                Utf8Stream::UnicodeChar first = Utf8Stream::toLowerUtf8(stream.peek());

                if (first != Utf8Stream::toLowerUtf8(character))
                    continue;

                visitor(translatedName);
            }
        }

        struct TopicEntryImpl : BaseEntry<MWDialogue::Entry, TopicEntry>
        {
            MWDialogue::Topic const& mTopic;

            TopicEntryImpl(
                JournalViewModelImpl const* model, MWDialogue::Topic const& topic, const MWDialogue::Entry& entry)
                : BaseEntry(model, entry, topic.getTopic())
                , mTopic(topic)
            {
            }

            std::string_view source() const override { return mEntry->mActorName; }
        };

        void visitTopicEntries(
            const MWDialogue::Topic& topic, std::function<void(TopicEntry const&)> visitor) const override
        {
            for (const MWDialogue::Entry& entry : topic)
                visitor(TopicEntryImpl(this, topic, entry));
        }
    };

    std::shared_ptr<JournalViewModel> JournalViewModel::create()
    {
        return std::make_shared<JournalViewModelImpl>();
    }

}
