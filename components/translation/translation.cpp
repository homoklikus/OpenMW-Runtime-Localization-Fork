#include "translation.hpp"

#include <algorithm>
#include <fstream>
#include <set>

#include <yaml-cpp/eventhandler.h>
#include <yaml-cpp/parser.h>
#include <yaml-cpp/yaml.h>

#include <components/debug/debuglog.hpp>
#include <components/misc/pathhelpers.hpp>
#include <components/misc/strings/lower.hpp>

namespace Translation
{
    namespace
    {
        std::string normalizeLocale(std::string_view locale)
        {
            std::string result;
            result.reserve(locale.size());

            for (const unsigned char c : locale)
            {
                if (c == '-')
                    result.push_back('_');
                else if (c >= 'A' && c <= 'Z')
                    result.push_back(static_cast<char>(c - 'A' + 'a'));
                else
                    result.push_back(static_cast<char>(c));
            }

            return result;
        }

        std::string normalizeRuntimeLocalizationSourceName(std::string_view sourceName)
        {
            std::string result(sourceName);

            const std::size_t separator = result.find_last_of("/\\");
            if (separator != std::string::npos)
                result.erase(0, separator + 1);

            for (char& c : result)
            {
                if (c >= 'A' && c <= 'Z')
                    c = static_cast<char>(c - 'A' + 'a');
            }

            constexpr std::string_view extensions[] = {
                ".yaml", ".esp", ".esm", ".omwaddon", ".omwgame"
            };
            for (const std::string_view extension : extensions)
            {
                if (result.ends_with(extension))
                {
                    result.resize(result.size() - extension.size());
                    break;
                }
            }

            return result;
        }

        std::string_view baseLocale(std::string_view locale)
        {
            const std::size_t separator = locale.find('_');
            if (separator == std::string_view::npos)
                return locale;
            return locale.substr(0, separator);
        }

        std::string makeRuntimeSlotKey(std::string_view kind, std::string_view key)
        {
            std::string result;
            result.reserve(kind.size() + key.size() + 1);
            result.append(kind);
            result.push_back('\0');
            result.append(key);
            return result;
        }

        std::string yamlLanguageKey(std::string_view locale)
        {
            std::string key;
            key.reserve(locale.size());
            for (const unsigned char c : locale)
            {
                if (c == '-')
                    key.push_back('_');
                else if (c >= 'a' && c <= 'z')
                    key.push_back(static_cast<char>(c - 'a' + 'A'));
                else
                    key.push_back(static_cast<char>(c));
            }
            return key;
        }

        std::vector<std::string> makeYamlLanguageKeys(const std::vector<std::string>& locales)
        {
            std::vector<std::string> result;
            std::set<std::string> seen;

            const auto append = [&](std::string key) {
                if (!key.empty() && seen.insert(key).second)
                    result.push_back(std::move(key));
            };

            for (const std::string& locale : locales)
            {
                std::string exact = yamlLanguageKey(locale);
                if (exact == "GMST")
                    continue;

                append(exact);

                const std::size_t separator = exact.find('_');
                if (separator != std::string::npos)
                    append(exact.substr(0, separator));
            }

            if (result.empty())
                result.emplace_back("EN");

            return result;
        }

        bool parseInfoLocalizationKey(
            std::string_view key, std::string_view& topicId, std::string_view& infoId)
        {
            constexpr std::string_view prefix = "INFO|";
            constexpr std::string_view suffix = "|NAME";

            if (!key.starts_with(prefix) || !key.ends_with(suffix)
                || key.size() <= prefix.size() + suffix.size())
                return false;

            const std::string_view payload
                = key.substr(prefix.size(), key.size() - prefix.size() - suffix.size());
            const std::size_t separator = payload.rfind('|');
            if (separator == std::string_view::npos || separator == 0 || separator + 1 >= payload.size())
                return false;

            topicId = payload.substr(0, separator);
            infoId = payload.substr(separator + 1);
            return true;
        }

        std::string makeInfoKey(std::string_view topicId, std::string_view infoId)
        {
            // ESM::RefId::serializeText() canonicalizes string RefIds to lowercase.
            // Normalize only INFO IDs here so Lua/YAML callers do not have to match
            // the source plugin's letter case exactly. Topic IDs are intentionally
            // left untouched because the runtime lookup uses Dialogue::mStringId.
            const std::string normalizedInfoId = Misc::StringUtils::lowerCase(infoId);

            std::string key;
            key.reserve(topicId.size() + normalizedInfoId.size() + 1);
            key.append(topicId);
            key.push_back('\0');
            key.append(normalizedInfoId);
            return key;
        }
    }

    Storage::Storage()
        : mEncoder(nullptr)
    {
    }

    void Storage::setPreferredLocales(const std::vector<std::string>& locales)
    {
        mPreferredLocales.clear();
        mRuntimeLocaleClaims.clear();

        for (const std::string& locale : locales)
        {
            const std::string normalized = normalizeLocale(locale);
            if (normalized.empty())
                continue;

            if (std::find(mPreferredLocales.begin(), mPreferredLocales.end(), normalized) == mPreferredLocales.end())
                mPreferredLocales.push_back(normalized);
        }

        // OpenMW's normal language default is English when no explicit locale is stored.
        if (mPreferredLocales.empty())
            mPreferredLocales.emplace_back("en");
    }

    const std::vector<std::string>& Storage::getPreferredLocales() const
    {
        return mPreferredLocales;
    }

    std::optional<std::size_t> Storage::localePriority(std::string_view locale) const
    {
        const std::string normalized = normalizeLocale(locale);
        if (normalized.empty())
            return std::nullopt;

        const std::string_view normalizedBase = baseLocale(normalized);

        for (std::size_t i = 0; i < mPreferredLocales.size(); ++i)
        {
            const std::string& preferred = mPreferredLocales[i];

            // Exact locale is preferred over a base-language match at the same position.
            if (normalized == preferred)
                return i * 2;

            if (!normalizedBase.empty() && normalizedBase == baseLocale(preferred))
                return i * 2 + 1;
        }

        return std::nullopt;
    }

    bool Storage::claimRuntimeLocale(std::string_view locale, std::string_view slotKey)
    {
        const std::optional<std::size_t> priority = localePriority(locale);
        if (!priority)
            return false;

        auto [it, inserted]
            = mRuntimeLocaleClaims.try_emplace(std::string(slotKey), *priority);

        if (inserted)
            return true;

        if (*priority <= it->second)
        {
            it->second = *priority;
            return true;
        }

        return false;
    }

    void Storage::setRegistrationLocale(std::string_view locale)
    {
        mRegistrationLocale = normalizeLocale(locale);
    }

    void Storage::clearRegistrationLocale()
    {
        mRegistrationLocale.clear();
    }

    bool Storage::claimActiveRuntimeLocale(std::string_view slotKey)
    {
        if (mRegistrationLocale.empty())
            return true;
        return claimRuntimeLocale(mRegistrationLocale, slotKey);
    }

    std::size_t Storage::loadRuntimeLocalizationYaml(std::istream& stream, std::string_view sourceName,
        const RuntimeLocalizationScalarHandler& scalarHandler,
        const RuntimeLocalizationFallbackHandler& fallbackHandler)
    {
        Log(Debug::Info) << "Runtime localization: streaming parse " << sourceName;

        const std::vector<std::string> languageKeys = makeYamlLanguageKeys(mPreferredLocales);

        {
            Log localeLog(Debug::Info);
            localeLog << "Runtime localization: " << sourceName << " YAML language preference:";
            for (const std::string& key : languageKeys)
                localeLog << " " << key;
        }

        class StreamingHandler final : public YAML::EventHandler
        {
        public:
            StreamingHandler(Storage& storage, const std::vector<std::string>& languageKeys,
                std::string_view sourceName, const RuntimeLocalizationScalarHandler& scalarHandler,
                const RuntimeLocalizationFallbackHandler& fallbackHandler)
                : mStorage(storage)
                , mLanguageKeys(languageKeys)
                , mSourceName(sourceName)
                , mScalarHandler(scalarHandler)
                , mFallbackHandler(fallbackHandler)
            {
            }

            std::size_t applied() const { return mApplied; }
            std::size_t skipped() const { return mSkipped; }
            std::size_t malformed() const { return mMalformed; }

            void OnDocumentStart(const YAML::Mark&) override {}
            void OnDocumentEnd() override {}

            void OnNull(const YAML::Mark&, YAML::anchor_t) override
            {
                consumeNullOrAlias();
            }

            void OnAlias(const YAML::Mark&, YAML::anchor_t) override
            {
                consumeNullOrAlias();
            }

            void OnScalar(const YAML::Mark&, const std::string&, YAML::anchor_t, const std::string& value) override
            {
                if (mStack.empty())
                    return;

                Frame& frame = mStack.back();
                if (frame.mType == Frame::Type::Sequence)
                    return;

                if (frame.mExpectingKey)
                {
                    frame.mPendingKey = value;
                    frame.mExpectingKey = false;
                    return;
                }

                std::vector<std::string> path = frame.mPath;
                path.push_back(frame.mPendingKey);
                frame.mPendingKey.clear();
                frame.mExpectingKey = true;

                handleScalar(path, value);
            }

            void OnSequenceStart(
                const YAML::Mark&, const std::string&, YAML::anchor_t, YAML::EmitterStyle::value) override
            {
                pushContainer(Frame::Type::Sequence);
            }

            void OnSequenceEnd() override
            {
                if (!mStack.empty())
                    mStack.pop_back();
            }

            void OnMapStart(
                const YAML::Mark&, const std::string&, YAML::anchor_t, YAML::EmitterStyle::value) override
            {
                std::vector<std::string> path = childContainerPath();

                if (path.size() == 2 && path[0] == "strings")
                    beginStringEntry(path[1]);
                else if (mEntry.mActive && path.size() == 3 && path[0] == "strings"
                    && path[1] == mEntry.mYamlKey)
                {
                    beginLanguageMap(path[2]);
                }
                else if (mEntry.mActive && isSelectedLanguagePath(path))
                {
                    validateSelectedMapStart(path);
                }

                if (path.size() == 3 && path[0] == "fallbacks")
                    beginFallbackEntry(path[1], path[2]);
                else if (mFallback.mActive && path.size() == 4 && path[0] == "fallbacks"
                    && path[1] == mFallback.mSection && path[2] == mFallback.mValueName)
                {
                    const std::optional<std::size_t> rank = languageRank(path[3]);
                    if (rank && (!mFallback.mHasLanguage || *rank <= mFallback.mBestRank))
                    {
                        ++mMalformed;
                        mFallback.mHasLanguage = true;
                        mFallback.mBestRank = *rank;
                        mFallback.mValue.reset();
                        Log(Debug::Warning) << "Runtime localization: fallback language value must be scalar: "
                                            << mFallback.mSection << "/" << mFallback.mValueName
                                            << " (" << mSourceName << ")";
                    }
                }

                mStack.push_back(Frame{ Frame::Type::Map, std::move(path), true, {} });
            }

            void OnMapEnd() override
            {
                if (mStack.empty())
                    return;

                const std::vector<std::string> path = mStack.back().mPath;

                if (mEntry.mActive && path.size() == 2 && path[0] == "strings"
                    && path[1] == mEntry.mYamlKey)
                    finalizeStringEntry();

                if (mFallback.mActive && path.size() == 3 && path[0] == "fallbacks"
                    && path[1] == mFallback.mSection && path[2] == mFallback.mValueName)
                    finalizeFallbackEntry();

                mStack.pop_back();
            }

        private:
            struct Frame
            {
                enum class Type
                {
                    Map,
                    Sequence
                };

                Type mType;
                std::vector<std::string> mPath;
                bool mExpectingKey = true;
                std::string mPendingKey;
            };

            struct Entry
            {
                bool mActive = false;
                std::string mYamlKey;

                bool mIsInfoName = false;
                std::string mTopicId;
                std::string mInfoId;

                std::size_t mBestRank = 0;
                bool mHasLanguage = false;
                std::string mSelectedLanguage;
                bool mSelectedIsMap = false;

                std::optional<std::string> mEnglishScalar;
                std::optional<std::string> mScalarValue;

                std::optional<std::string> mDefault;
                std::optional<std::string> mNpcMale;
                std::optional<std::string> mNpcFemale;
                std::optional<std::string> mPlayerMale;
                std::optional<std::string> mPlayerFemale;
                std::optional<std::string> mNpcMalePlayerMale;
                std::optional<std::string> mNpcMalePlayerFemale;
                std::optional<std::string> mNpcFemalePlayerMale;
                std::optional<std::string> mNpcFemalePlayerFemale;
            };

            struct FallbackEntry
            {
                bool mActive = false;
                std::string mSection;
                std::string mValueName;
                std::size_t mBestRank = 0;
                bool mHasLanguage = false;
                std::optional<std::string> mValue;
            };

            Storage& mStorage;
            const std::vector<std::string>& mLanguageKeys;
            std::string mSourceName;
            const RuntimeLocalizationScalarHandler& mScalarHandler;
            const RuntimeLocalizationFallbackHandler& mFallbackHandler;

            std::vector<Frame> mStack;
            Entry mEntry;
            FallbackEntry mFallback;

            std::size_t mApplied = 0;
            std::size_t mSkipped = 0;
            std::size_t mMalformed = 0;

            std::vector<std::string> childContainerPath()
            {
                if (mStack.empty())
                    return {};

                Frame& parent = mStack.back();
                std::vector<std::string> path = parent.mPath;

                if (parent.mType == Frame::Type::Map && !parent.mExpectingKey)
                {
                    path.push_back(parent.mPendingKey);
                    parent.mPendingKey.clear();
                    parent.mExpectingKey = true;
                }

                return path;
            }

            void pushContainer(Frame::Type type)
            {
                std::vector<std::string> path = childContainerPath();
                mStack.push_back(Frame{ type, std::move(path), type == Frame::Type::Map, {} });
            }

            void consumeNullOrAlias()
            {
                if (mStack.empty())
                    return;

                Frame& frame = mStack.back();
                if (frame.mType == Frame::Type::Map && !frame.mExpectingKey)
                {
                    frame.mPendingKey.clear();
                    frame.mExpectingKey = true;
                }
            }

            std::optional<std::size_t> languageRank(std::string_view language) const
            {
                const std::string normalized = yamlLanguageKey(language);
                for (std::size_t i = 0; i < mLanguageKeys.size(); ++i)
                {
                    if (mLanguageKeys[i] == normalized)
                        return i;
                }
                return std::nullopt;
            }

            void resetSelectedBranch(std::size_t rank, std::string_view language)
            {
                mEntry.mBestRank = rank;
                mEntry.mHasLanguage = true;
                mEntry.mSelectedLanguage = yamlLanguageKey(language);
                mEntry.mSelectedIsMap = false;

                mEntry.mScalarValue.reset();
                mEntry.mDefault.reset();
                mEntry.mNpcMale.reset();
                mEntry.mNpcFemale.reset();
                mEntry.mPlayerMale.reset();
                mEntry.mPlayerFemale.reset();
                mEntry.mNpcMalePlayerMale.reset();
                mEntry.mNpcMalePlayerFemale.reset();
                mEntry.mNpcFemalePlayerMale.reset();
                mEntry.mNpcFemalePlayerFemale.reset();
            }

            void beginStringEntry(const std::string& yamlKey)
            {
                mEntry = Entry{};
                mEntry.mActive = true;
                mEntry.mYamlKey = yamlKey;
                mEntry.mBestRank = mLanguageKeys.size();

                const std::size_t first = yamlKey.find('|');
                const std::size_t last = yamlKey.rfind('|');

                if (first == std::string::npos || last == std::string::npos || first == last)
                    return;

                const std::string_view key(yamlKey);
                const std::string_view recordType = key.substr(0, first);
                const std::string_view recordId = key.substr(first + 1, last - first - 1);
                const std::string_view field = key.substr(last + 1);

                if (recordType != "INFO" || field != "NAME")
                    return;

                const std::size_t infoSeparator = recordId.rfind('|');
                if (infoSeparator == std::string_view::npos)
                {
                    ++mMalformed;
                    Log(Debug::Warning) << "Runtime localization: malformed INFO key " << yamlKey
                                        << " (" << mSourceName << ")";
                    return;
                }

                mEntry.mIsInfoName = true;
                mEntry.mTopicId = std::string(recordId.substr(0, infoSeparator));
                mEntry.mInfoId = std::string(recordId.substr(infoSeparator + 1));
            }

            void beginLanguageMap(const std::string& language)
            {
                const std::optional<std::size_t> rank = languageRank(language);
                if (!rank)
                    return;

                if (!mEntry.mHasLanguage || *rank <= mEntry.mBestRank)
                {
                    resetSelectedBranch(*rank, language);
                    mEntry.mSelectedIsMap = true;
                }
            }

            bool isSelectedLanguagePath(const std::vector<std::string>& path) const
            {
                return mEntry.mActive && mEntry.mHasLanguage && path.size() >= 3 && path[0] == "strings"
                    && path[1] == mEntry.mYamlKey
                    && yamlLanguageKey(path[2]) == mEntry.mSelectedLanguage;
            }

            void validateSelectedMapStart(const std::vector<std::string>& path)
            {
                if (!mEntry.mIsInfoName)
                    return;

                bool shouldBeScalar = false;

                if (path.size() == 4 && path[3] == "default")
                    shouldBeScalar = true;
                else if (path.size() == 5
                    && (path[3] == "npc" || path[3] == "player")
                    && (path[4] == "male" || path[4] == "female"))
                    shouldBeScalar = true;
                else if (path.size() == 6 && path[3] == "npc_player"
                    && (path[4] == "male" || path[4] == "female")
                    && (path[5] == "male" || path[5] == "female"))
                    shouldBeScalar = true;

                if (shouldBeScalar)
                {
                    ++mMalformed;
                    Log(Debug::Warning) << "Runtime localization: expected scalar in "
                                        << mEntry.mYamlKey << " (" << mSourceName << ")";
                }
            }

            void beginFallbackEntry(const std::string& section, const std::string& valueName)
            {
                mFallback = FallbackEntry{};
                mFallback.mActive = true;
                mFallback.mSection = section;
                mFallback.mValueName = valueName;
                mFallback.mBestRank = mLanguageKeys.size();
            }

            void handleFallbackScalar(const std::vector<std::string>& path, const std::string& value)
            {
                if (!mFallback.mActive || path.size() != 4 || path[0] != "fallbacks"
                    || path[1] != mFallback.mSection || path[2] != mFallback.mValueName)
                    return;

                const std::optional<std::size_t> rank = languageRank(path[3]);
                if (!rank)
                    return;

                if (!mFallback.mHasLanguage || *rank <= mFallback.mBestRank)
                {
                    mFallback.mHasLanguage = true;
                    mFallback.mBestRank = *rank;
                    mFallback.mValue = value;
                }
            }

            void handleScalar(const std::vector<std::string>& path, const std::string& value)
            {
                if (!path.empty() && path[0] == "fallbacks")
                {
                    handleFallbackScalar(path, value);
                    return;
                }

                if (!mEntry.mActive || path.size() < 3 || path[0] != "strings"
                    || path[1] != mEntry.mYamlKey)
                    return;

                if (path.size() == 3)
                {
                    const std::string normalizedLanguage = yamlLanguageKey(path[2]);

                    if (normalizedLanguage == "EN")
                        mEntry.mEnglishScalar = value;

                    const std::optional<std::size_t> rank = languageRank(path[2]);
                    if (!rank)
                        return;

                    if (!mEntry.mHasLanguage || *rank <= mEntry.mBestRank)
                    {
                        resetSelectedBranch(*rank, path[2]);
                        mEntry.mScalarValue = value;
                    }
                    return;
                }

                if (!isSelectedLanguagePath(path))
                    return;

                mEntry.mSelectedIsMap = true;

                if (!mEntry.mIsInfoName)
                    return;

                if (path.size() == 4)
                {
                    if (path[3] == "default")
                        mEntry.mDefault = value;
                    else if (path[3] == "npc" || path[3] == "player" || path[3] == "npc_player")
                    {
                        ++mMalformed;
                        Log(Debug::Warning) << "Runtime localization: " << mEntry.mYamlKey << "."
                                            << path[3] << " must be a map in " << mSourceName;
                    }
                    return;
                }

                if (path.size() == 5)
                {
                    if (path[3] == "npc" && path[4] == "male")
                        mEntry.mNpcMale = value;
                    else if (path[3] == "npc" && path[4] == "female")
                        mEntry.mNpcFemale = value;
                    else if (path[3] == "player" && path[4] == "male")
                        mEntry.mPlayerMale = value;
                    else if (path[3] == "player" && path[4] == "female")
                        mEntry.mPlayerFemale = value;
                    else if (path[3] == "npc_player")
                    {
                        ++mMalformed;
                        Log(Debug::Warning) << "Runtime localization: " << mEntry.mYamlKey
                                            << ".npc_player." << path[4] << " must be a map in "
                                            << mSourceName;
                    }
                    return;
                }

                if (path.size() == 6 && path[3] == "npc_player")
                {
                    if (path[4] == "male" && path[5] == "male")
                        mEntry.mNpcMalePlayerMale = value;
                    else if (path[4] == "male" && path[5] == "female")
                        mEntry.mNpcMalePlayerFemale = value;
                    else if (path[4] == "female" && path[5] == "male")
                        mEntry.mNpcFemalePlayerMale = value;
                    else if (path[4] == "female" && path[5] == "female")
                        mEntry.mNpcFemalePlayerFemale = value;
                }
            }

            void finalizeInfoEntry()
            {
                bool applied = false;

                const auto prepareInfo = [&](std::string_view displayText) {
                    std::string plain
                        = mStorage.prepareRuntimeLocalizationInfoText(mEntry.mYamlKey, displayText);
                    mStorage.recordRuntimeLocalizationInfoSource(
                        mEntry.mYamlKey, plain, mSourceName);
                    return plain;
                };

                if (!mEntry.mSelectedIsMap && mEntry.mScalarValue)
                {
                    mStorage.addInfoResponseTranslation(mEntry.mTopicId, mEntry.mInfoId,
                        prepareInfo(*mEntry.mScalarValue));
                    applied = true;
                }
                else
                {
                    if (mEntry.mDefault)
                    {
                        mStorage.addInfoResponseTranslation(mEntry.mTopicId, mEntry.mInfoId,
                            prepareInfo(*mEntry.mDefault));
                        applied = true;
                    }
                    if (mEntry.mNpcMale)
                    {
                        mStorage.addInfoResponseNpcTranslation(mEntry.mTopicId, mEntry.mInfoId, NpcGender::Male,
                            prepareInfo(*mEntry.mNpcMale));
                        applied = true;
                    }
                    if (mEntry.mNpcFemale)
                    {
                        mStorage.addInfoResponseNpcTranslation(mEntry.mTopicId, mEntry.mInfoId, NpcGender::Female,
                            prepareInfo(*mEntry.mNpcFemale));
                        applied = true;
                    }
                    if (mEntry.mPlayerMale)
                    {
                        mStorage.addInfoResponsePlayerTranslation(mEntry.mTopicId, mEntry.mInfoId, PlayerGender::Male,
                            prepareInfo(*mEntry.mPlayerMale));
                        applied = true;
                    }
                    if (mEntry.mPlayerFemale)
                    {
                        mStorage.addInfoResponsePlayerTranslation(mEntry.mTopicId, mEntry.mInfoId, PlayerGender::Female,
                            prepareInfo(*mEntry.mPlayerFemale));
                        applied = true;
                    }
                    if (mEntry.mNpcMalePlayerMale)
                    {
                        mStorage.addInfoResponseNpcPlayerTranslation(mEntry.mTopicId, mEntry.mInfoId,
                            NpcGender::Male, PlayerGender::Male,
                            prepareInfo(*mEntry.mNpcMalePlayerMale));
                        applied = true;
                    }
                    if (mEntry.mNpcMalePlayerFemale)
                    {
                        mStorage.addInfoResponseNpcPlayerTranslation(mEntry.mTopicId, mEntry.mInfoId,
                            NpcGender::Male, PlayerGender::Female,
                            prepareInfo(*mEntry.mNpcMalePlayerFemale));
                        applied = true;
                    }
                    if (mEntry.mNpcFemalePlayerMale)
                    {
                        mStorage.addInfoResponseNpcPlayerTranslation(mEntry.mTopicId, mEntry.mInfoId,
                            NpcGender::Female, PlayerGender::Male,
                            prepareInfo(*mEntry.mNpcFemalePlayerMale));
                        applied = true;
                    }
                    if (mEntry.mNpcFemalePlayerFemale)
                    {
                        mStorage.addInfoResponseNpcPlayerTranslation(mEntry.mTopicId, mEntry.mInfoId,
                            NpcGender::Female, PlayerGender::Female,
                            prepareInfo(*mEntry.mNpcFemalePlayerFemale));
                        applied = true;
                    }
                }

                if (applied)
                    ++mApplied;
                else
                {
                    ++mMalformed;
                    Log(Debug::Warning) << "Runtime localization: selected language has no valid INFO value: "
                                        << mEntry.mYamlKey << " (" << mSourceName << ")";
                }
            }

            void finalizeStringEntry()
            {
                if (!mEntry.mHasLanguage)
                {
                    ++mSkipped;
                    Log(Debug::Warning) << "Runtime localization: SKIPPED string key=" << mEntry.mYamlKey
                                        << " reason=no matching preferred/fallback language"
                                        << " source=" << mSourceName;
                    mEntry = Entry{};
                    return;
                }

                if (mEntry.mIsInfoName)
                {
                    finalizeInfoEntry();
                    mEntry = Entry{};
                    return;
                }

                if (mEntry.mSelectedIsMap || !mEntry.mScalarValue)
                {
                    ++mMalformed;
                    Log(Debug::Warning) << "Runtime localization: non-INFO language value must be scalar: "
                                        << mEntry.mYamlKey << " (" << mSourceName << ")";
                    mEntry = Entry{};
                    return;
                }

                if (mScalarHandler
                    && mScalarHandler(mEntry.mYamlKey, mEntry.mEnglishScalar.value_or(""), *mEntry.mScalarValue))
                {
                    mStorage.recordRuntimeLocalizationSource(mEntry.mYamlKey, mSourceName);
                    ++mApplied;
                }
                else
                {
                    ++mSkipped;
                    Log(Debug::Warning) << "Runtime localization: SKIPPED string key=" << mEntry.mYamlKey
                                        << " reason=runtime target rejected or not found"
                                        << " language=" << mEntry.mSelectedLanguage
                                        << " source=" << mSourceName;
                }

                mEntry = Entry{};
            }

            void finalizeFallbackEntry()
            {
                if (!mFallback.mHasLanguage || !mFallback.mValue)
                {
                    ++mSkipped;
                    Log(Debug::Warning) << "Runtime localization: SKIPPED fallback section=" << mFallback.mSection
                                        << " value=" << mFallback.mValueName
                                        << " reason="
                                        << (!mFallback.mHasLanguage
                                                ? "no matching preferred/fallback language"
                                                : "selected language has no scalar value")
                                        << " source=" << mSourceName;
                    mFallback = FallbackEntry{};
                    return;
                }

                if (mFallbackHandler
                    && mFallbackHandler(mFallback.mSection, mFallback.mValueName, *mFallback.mValue))
                    ++mApplied;
                else
                {
                    ++mSkipped;
                    Log(Debug::Warning) << "Runtime localization: SKIPPED fallback section=" << mFallback.mSection
                                        << " value=" << mFallback.mValueName
                                        << " reason=fallback target rejected or unsupported"
                                        << " source=" << mSourceName;
                }

                mFallback = FallbackEntry{};
            }
        };

        StreamingHandler handler(*this, languageKeys, sourceName, scalarHandler, fallbackHandler);

        try
        {
            YAML::Parser parser(stream);
            if (!parser.HandleNextDocument(handler))
            {
                Log(Debug::Warning) << "Runtime localization: empty YAML " << sourceName;
                return 0;
            }
        }
        catch (const YAML::Exception& e)
        {
            Log(Debug::Error) << "Runtime localization: cannot parse " << sourceName << ": " << e.what();
            return 0;
        }

        Log(Debug::Info) << "Runtime localization: native YAML loader finished " << sourceName
                         << ", applied=" << handler.applied()
                         << ", skipped=" << handler.skipped()
                         << ", malformed=" << handler.malformed();
        return handler.applied();
    }

    std::string Storage::prepareRuntimeLocalizationText(std::string_view key, std::string_view displayText)
    {
        const auto normalizeKey = [](std::string_view value) {
            std::string result(value);
            for (char& c : result)
            {
                if (c >= 'A' && c <= 'Z')
                    c = static_cast<char>(c - 'A' + 'a');
            }
            return result;
        };

        const auto isHexDigit = [](char c) {
            return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        };

        const auto isColourOpen = [&](std::size_t pos) {
            if (pos + 11 > displayText.size())
                return false;
            if (displayText.substr(pos, 4) != "[c=#" || displayText[pos + 10] != ']')
                return false;
            for (std::size_t i = pos + 4; i < pos + 10; ++i)
            {
                if (!isHexDigit(displayText[i]))
                    return false;
            }
            return true;
        };

        const auto closingTag = [&](std::size_t pos, char& kind, std::size_t& length) {
            if (displayText.substr(pos, 4) == "[/c]")
            {
                kind = 'c';
                length = 4;
                return true;
            }
            if (displayText.substr(pos, 4) == "[/b]")
            {
                kind = 'b';
                length = 4;
                return true;
            }
            if (displayText.substr(pos, 4) == "[/i]")
            {
                kind = 'i';
                length = 4;
                return true;
            }
            return false;
        };

        const auto openingTag = [&](std::size_t pos, char& kind, std::size_t& length) {
            if (isColourOpen(pos))
            {
                kind = 'c';
                length = 11;
                return true;
            }
            if (displayText.substr(pos, 3) == "[b]")
            {
                kind = 'b';
                length = 3;
                return true;
            }
            if (displayText.substr(pos, 3) == "[i]")
            {
                kind = 'i';
                length = 3;
                return true;
            }
            return false;
        };

        std::vector<char> stack;
        bool hasMarkup = false;
        bool malformed = false;

        for (std::size_t i = 0; i < displayText.size();)
        {
            char kind = 0;
            std::size_t length = 0;

            if (openingTag(i, kind, length))
            {
                stack.push_back(kind);
                hasMarkup = true;
                i += length;
                continue;
            }

            if (closingTag(i, kind, length))
            {
                if (stack.empty() || stack.back() != kind)
                {
                    malformed = true;
                    break;
                }
                stack.pop_back();
                hasMarkup = true;
                i += length;
                continue;
            }

            ++i;
        }

        if (!stack.empty())
            malformed = true;

        const std::string normalizedKey = normalizeKey(key);
        if (!hasMarkup || malformed)
        {
            mRuntimeLocalizationMarkup.erase(normalizedKey);
            if (malformed)
                Log(Debug::Warning) << "Runtime localization: malformed display markup for " << key;
            return std::string(displayText);
        }

        std::string plain;
        plain.reserve(displayText.size());

        for (std::size_t i = 0; i < displayText.size();)
        {
            char kind = 0;
            std::size_t length = 0;
            if (openingTag(i, kind, length) || closingTag(i, kind, length))
            {
                i += length;
                continue;
            }

            plain.push_back(displayText[i]);
            ++i;
        }

        mRuntimeLocalizationMarkup[normalizedKey] = std::string(displayText);
        return plain;
    }

    std::string_view Storage::runtimeLocalizationMarkup(std::string_view key) const
    {
        std::string normalizedKey(key);
        for (char& c : normalizedKey)
        {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        }

        const auto it = mRuntimeLocalizationMarkup.find(normalizedKey);
        if (it == mRuntimeLocalizationMarkup.end())
            return {};
        return it->second;
    }

    std::string Storage::prepareRuntimeLocalizationInfoText(
        std::string_view key, std::string_view displayText)
    {
        const auto normalizeKey = [](std::string_view value) {
            std::string result(value);
            for (char& c : result)
            {
                if (c >= 'A' && c <= 'Z')
                    c = static_cast<char>(c - 'A' + 'a');
            }
            return result;
        };

        std::string temporaryKey = "__runtime_info_markup__|";
        temporaryKey.append(key);

        const std::string plain = prepareRuntimeLocalizationText(temporaryKey, displayText);
        const std::string normalizedTemporaryKey = normalizeKey(temporaryKey);
        const auto temporary = mRuntimeLocalizationMarkup.find(normalizedTemporaryKey);

        std::string compositeKey = normalizeKey(key);
        compositeKey.push_back('\x1f');
        compositeKey.append(plain);

        if (temporary != mRuntimeLocalizationMarkup.end())
        {
            mRuntimeLocalizationMarkup.insert_or_assign(compositeKey, temporary->second);
            mRuntimeLocalizationMarkup.erase(temporary);
        }
        else
            mRuntimeLocalizationMarkup.erase(compositeKey);

        return plain;
    }

    std::string_view Storage::runtimeLocalizationInfoMarkup(
        std::string_view key, std::string_view plainText) const
    {
        std::string normalizedKey(key);
        for (char& c : normalizedKey)
        {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        }

        normalizedKey.push_back('\x1f');
        normalizedKey.append(plainText);

        const auto it = mRuntimeLocalizationMarkup.find(normalizedKey);
        if (it == mRuntimeLocalizationMarkup.end())
            return {};
        return it->second;
    }

    void Storage::recordRuntimeLocalizationSource(std::string_view key, std::string_view sourceName)
    {
        if (mRuntimeLocalizationQaSource.empty())
            return;

        std::string normalizedKey(key);
        for (char& c : normalizedKey)
        {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        }

        const auto existing = mRuntimeLocalizationSource.find(normalizedKey);
        if (existing != mRuntimeLocalizationSource.end() && existing->second != sourceName)
        {
            Log(Debug::Verbose) << "Runtime localization: source override key=" << key
                             << " old=" << existing->second << " new=" << sourceName;
        }

        mRuntimeLocalizationSource.insert_or_assign(normalizedKey, std::string(sourceName));
    }

    std::string_view Storage::runtimeLocalizationSource(std::string_view key) const
    {
        std::string normalizedKey(key);
        for (char& c : normalizedKey)
        {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        }

        const auto it = mRuntimeLocalizationSource.find(normalizedKey);
        if (it == mRuntimeLocalizationSource.end())
            return {};
        return it->second;
    }

    void Storage::recordRuntimeLocalizationInfoSource(
        std::string_view key, std::string_view plainText, std::string_view sourceName)
    {
        if (mRuntimeLocalizationQaSource.empty())
            return;

        std::string normalizedKey(key);
        for (char& c : normalizedKey)
        {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        }

        normalizedKey.push_back('\x1f');
        normalizedKey.append(plainText);

        const auto existing = mRuntimeLocalizationSource.find(normalizedKey);
        if (existing != mRuntimeLocalizationSource.end() && existing->second != sourceName)
        {
            Log(Debug::Verbose) << "Runtime localization: INFO source override key=" << key
                             << " old=" << existing->second << " new=" << sourceName;
        }

        mRuntimeLocalizationSource.insert_or_assign(normalizedKey, std::string(sourceName));
    }

    std::string_view Storage::runtimeLocalizationInfoSource(
        std::string_view key, std::string_view plainText) const
    {
        std::string normalizedKey(key);
        for (char& c : normalizedKey)
        {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        }

        normalizedKey.push_back('\x1f');
        normalizedKey.append(plainText);

        const auto it = mRuntimeLocalizationSource.find(normalizedKey);
        if (it == mRuntimeLocalizationSource.end())
            return {};
        return it->second;
    }

    void Storage::setRuntimeLocalizationQaSource(std::string_view sourceName)
    {
        mRuntimeLocalizationQaSource = normalizeRuntimeLocalizationSourceName(sourceName);
        mRuntimeLocalizationSource.clear();
    }

    bool Storage::runtimeLocalizationQaHighlight(std::string_view key) const
    {
        if (mRuntimeLocalizationQaSource.empty())
            return false;

        const std::string_view source = runtimeLocalizationSource(key);
        return !source.empty()
            && normalizeRuntimeLocalizationSourceName(source) == mRuntimeLocalizationQaSource;
    }

    bool Storage::runtimeLocalizationInfoQaHighlight(
        std::string_view key, std::string_view plainText) const
    {
        if (mRuntimeLocalizationQaSource.empty())
            return false;

        const std::string_view source = runtimeLocalizationInfoSource(key, plainText);
        return !source.empty()
            && normalizeRuntimeLocalizationSourceName(source) == mRuntimeLocalizationQaSource;
    }

    void Storage::loadTranslationData(const Files::Collections& dataFileCollections, std::string_view esmFileName)
    {
        std::string_view esmNameNoExtension = Misc::stemFile(esmFileName);

        loadData(mCellNamesTranslations, esmNameNoExtension, "cel", dataFileCollections);
        loadData(mPhraseForms, esmNameNoExtension, "top", dataFileCollections);
        loadData(mKeywords, esmNameNoExtension, "mrk", dataFileCollections);
    }

    void Storage::loadData(ContainerType& container, std::string_view fileNameNoExtension, std::string_view extension,
        const Files::Collections& dataFileCollections)
    {
        std::string fileName(fileNameNoExtension);
        fileName += '.';
        fileName += extension;

        const Files::MultiDirCollection& collection = dataFileCollections.getCollection(extension);
        if (collection.doesExist(fileName))
        {
            std::ifstream stream(collection.getPath(fileName));

            if (!stream.is_open())
                throw std::runtime_error("failed to open translation file: " + fileName);

            loadDataFromStream(container, stream);
        }
    }

    void Storage::loadDataFromStream(ContainerType& container, std::istream& stream)
    {
        std::string line;
        while (!stream.eof() && !stream.fail())
        {
            std::getline(stream, line);
            if (!line.empty() && *line.rbegin() == '\r')
                line.resize(line.size() - 1);

            if (!line.empty())
            {
                const std::string_view utf8 = mEncoder->getUtf8(line);

                size_t tabPos = utf8.find('\t');
                if (tabPos != std::string::npos && tabPos > 0 && tabPos < utf8.size() - 1)
                {
                    const std::string_view key = utf8.substr(0, tabPos);
                    const std::string_view value = utf8.substr(tabPos + 1);

                    if (!key.empty() && !value.empty())
                        container.emplace(key, value);
                }
            }
        }
    }

    std::string_view Storage::translateCellName(std::string_view cellName) const
    {
        auto entry = mCellNamesTranslations.find(cellName);

        if (entry == mCellNamesTranslations.end())
            return cellName;

        return entry->second;
    }

    std::string_view Storage::translateTopicName(std::string_view topicId) const
    {
        auto entry = mTopicNames.find(topicId);
        if (entry == mTopicNames.end())
            return topicId;
        return entry->second;
    }

    std::string_view Storage::translateInfoResponse(std::string_view topicId, std::string_view infoId,
        std::string_view sourceText, NpcGender npcGender, PlayerGender playerGender) const
    {
        const std::string key = makeInfoKey(topicId, infoId);

        // Most specific form first: exact NPC + player gender combination.
        const ContainerType* combinedGenderResponses = nullptr;
        if (npcGender == NpcGender::Male && playerGender == PlayerGender::Male)
            combinedGenderResponses = &mInfoResponsesNpcMalePlayerMale;
        else if (npcGender == NpcGender::Male && playerGender == PlayerGender::Female)
            combinedGenderResponses = &mInfoResponsesNpcMalePlayerFemale;
        else if (npcGender == NpcGender::Female && playerGender == PlayerGender::Male)
            combinedGenderResponses = &mInfoResponsesNpcFemalePlayerMale;
        else if (npcGender == NpcGender::Female && playerGender == PlayerGender::Female)
            combinedGenderResponses = &mInfoResponsesNpcFemalePlayerFemale;

        if (combinedGenderResponses != nullptr)
        {
            auto genderEntry = combinedGenderResponses->find(key);
            if (genderEntry != combinedGenderResponses->end())
                return genderEntry->second;
        }

        // Less specific NPC-only variant.
        const ContainerType* npcGenderResponses = nullptr;
        if (npcGender == NpcGender::Male)
            npcGenderResponses = &mInfoResponsesNpcMale;
        else if (npcGender == NpcGender::Female)
            npcGenderResponses = &mInfoResponsesNpcFemale;

        if (npcGenderResponses != nullptr)
        {
            auto genderEntry = npcGenderResponses->find(key);
            if (genderEntry != npcGenderResponses->end())
                return genderEntry->second;
        }

        const ContainerType* playerGenderResponses = nullptr;
        if (playerGender == PlayerGender::Male)
            playerGenderResponses = &mInfoResponsesPlayerMale;
        else if (playerGender == PlayerGender::Female)
            playerGenderResponses = &mInfoResponsesPlayerFemale;

        if (playerGenderResponses != nullptr)
        {
            auto genderEntry = playerGenderResponses->find(key);
            if (genderEntry != playerGenderResponses->end())
                return genderEntry->second;
        }

        auto entry = mInfoResponses.find(key);
        if (entry == mInfoResponses.end())
            return sourceText;
        return entry->second;
    }

    std::string_view Storage::translateChoice(std::string_view sourceText) const
    {
        auto entry = mChoiceTranslations.find(sourceText);
        if (entry == mChoiceTranslations.end())
            return sourceText;
        return entry->second;
    }

    std::string_view Storage::translateScriptString(std::string_view sourceText) const
    {
        auto entry = mScriptStrings.find(sourceText);
        if (entry == mScriptStrings.end())
            return sourceText;
        return entry->second;
    }

    std::string_view Storage::topicStandardForm(std::string_view phrase) const
    {
        auto phraseFormsIterator = mPhraseForms.find(phrase);

        if (phraseFormsIterator != mPhraseForms.end())
            return phraseFormsIterator->second;
        else
            return phrase;
    }

    std::string_view Storage::topicKeyword(std::string_view phrase) const
    {
        auto entry = mKeywords.find(phrase);

        if (entry == mKeywords.end())
            return phrase;

        return entry->second;
    }

    void Storage::addCellNameTranslation(std::string_view cellName, std::string_view displayName)
    {
        mCellNamesTranslations.insert_or_assign(std::string(cellName), std::string(displayName));
    }

    void Storage::addTopicNameTranslation(std::string_view topicId, std::string_view displayName)
    {
        mTopicNames.insert_or_assign(std::string(topicId), std::string(displayName));
    }

    void Storage::addPhraseForm(std::string_view phrase, std::string_view topicId)
    {
        mPhraseForms.emplace(phrase, topicId);
    }

    void Storage::setPhraseForm(std::string_view phrase, std::string_view topicId)
    {
        mPhraseForms.insert_or_assign(std::string(phrase), std::string(topicId));
    }

    void Storage::addTopicKeyword(std::string_view topicId, std::string_view keyword)
    {
        mKeywords.insert_or_assign(std::string(topicId), std::string(keyword));
    }

    void Storage::addInfoResponseTranslation(
        std::string_view topicId, std::string_view infoId, std::string_view response)
    {
        const std::string key = makeInfoKey(topicId, infoId);
        if (!claimActiveRuntimeLocale(makeRuntimeSlotKey("info-default", key)))
            return;
        mInfoResponses.insert_or_assign(key, std::string(response));
    }

    void Storage::addInfoResponseNpcTranslation(
        std::string_view topicId, std::string_view infoId, NpcGender gender, std::string_view response)
    {
        ContainerType* target = nullptr;
        if (gender == NpcGender::Male)
            target = &mInfoResponsesNpcMale;
        else if (gender == NpcGender::Female)
            target = &mInfoResponsesNpcFemale;

        if (target != nullptr)
        {
            const std::string key = makeInfoKey(topicId, infoId);
            const std::string_view kind
                = gender == NpcGender::Male ? "info-npc-male" : "info-npc-female";
            if (!claimActiveRuntimeLocale(makeRuntimeSlotKey(kind, key)))
                return;
            target->insert_or_assign(key, std::string(response));
        }
    }

    void Storage::addInfoResponsePlayerTranslation(
        std::string_view topicId, std::string_view infoId, PlayerGender gender, std::string_view response)
    {
        ContainerType* target = nullptr;
        if (gender == PlayerGender::Male)
            target = &mInfoResponsesPlayerMale;
        else if (gender == PlayerGender::Female)
            target = &mInfoResponsesPlayerFemale;

        if (target != nullptr)
        {
            const std::string key = makeInfoKey(topicId, infoId);
            const std::string_view kind
                = gender == PlayerGender::Male ? "info-player-male" : "info-player-female";
            if (!claimActiveRuntimeLocale(makeRuntimeSlotKey(kind, key)))
                return;
            target->insert_or_assign(key, std::string(response));
        }
    }

    void Storage::addInfoResponseNpcPlayerTranslation(std::string_view topicId, std::string_view infoId,
        NpcGender npcGender, PlayerGender playerGender, std::string_view response)
    {
        ContainerType* target = nullptr;

        if (npcGender == NpcGender::Male && playerGender == PlayerGender::Male)
            target = &mInfoResponsesNpcMalePlayerMale;
        else if (npcGender == NpcGender::Male && playerGender == PlayerGender::Female)
            target = &mInfoResponsesNpcMalePlayerFemale;
        else if (npcGender == NpcGender::Female && playerGender == PlayerGender::Male)
            target = &mInfoResponsesNpcFemalePlayerMale;
        else if (npcGender == NpcGender::Female && playerGender == PlayerGender::Female)
            target = &mInfoResponsesNpcFemalePlayerFemale;

        if (target != nullptr)
        {
            const std::string key = makeInfoKey(topicId, infoId);
            std::string_view kind = "info-npc-player";
            if (npcGender == NpcGender::Male && playerGender == PlayerGender::Male)
                kind = "info-npc-male-player-male";
            else if (npcGender == NpcGender::Male && playerGender == PlayerGender::Female)
                kind = "info-npc-male-player-female";
            else if (npcGender == NpcGender::Female && playerGender == PlayerGender::Male)
                kind = "info-npc-female-player-male";
            else if (npcGender == NpcGender::Female && playerGender == PlayerGender::Female)
                kind = "info-npc-female-player-female";

            if (!claimActiveRuntimeLocale(makeRuntimeSlotKey(kind, key)))
                return;
            target->insert_or_assign(key, std::string(response));
        }
    }

    void Storage::addChoiceTranslation(std::string_view sourceText, std::string_view displayText)
    {
        mChoiceTranslations.insert_or_assign(std::string(sourceText), std::string(displayText));
    }

    void Storage::addScriptStringTranslation(std::string_view sourceText, std::string_view displayText)
    {
        mScriptStrings.insert_or_assign(std::string(sourceText), std::string(displayText));
    }

    void Storage::setEncoder(ToUTF8::Utf8Encoder* encoder)
    {
        mEncoder = encoder;
    }
}
