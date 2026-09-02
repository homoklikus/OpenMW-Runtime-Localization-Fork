#ifndef COMPONENTS_TRANSLATION_DATA_H
#define COMPONENTS_TRANSLATION_DATA_H

#include <components/files/collections.hpp>
#include <components/toutf8/toutf8.hpp>

#include <cstddef>
#include <functional>
#include <iosfwd>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace Translation
{
    class Storage
    {
    public:
        enum class NpcGender
        {
            None,
            Male,
            Female
        };

        enum class PlayerGender
        {
            None,
            Male,
            Female
        };

        Storage();

        // Engine-side language selection for runtime localization.
        // Locales use the same preference order as OpenMW's General/preferred locales.
        void setPreferredLocales(const std::vector<std::string>& locales);
        const std::vector<std::string>& getPreferredLocales() const;

        // Returns the preference rank for a locale, including base-language matching
        // (for example pl_PL <-> pl), or std::nullopt when the locale is not selected.
        std::optional<std::size_t> localePriority(std::string_view locale) const;

        // Claims one logical runtime-localization slot for a locale.
        // Higher-priority locales win regardless of registration order.
        // Equal priority is accepted so later content layers can overwrite earlier ones.
        bool claimRuntimeLocale(std::string_view locale, std::string_view slotKey);

        void setRegistrationLocale(std::string_view locale);
        void clearRegistrationLocale();
        bool claimActiveRuntimeLocale(std::string_view slotKey);

        // Native runtime-localization YAML loader. The language is selected in C++
        // from OpenMW General/preferred locales; Lua is not involved.
        using RuntimeLocalizationScalarHandler
            = std::function<bool(std::string_view key, std::string_view sourceText, std::string_view displayText)>;
        using RuntimeLocalizationFallbackHandler
            = std::function<bool(std::string_view section, std::string_view valueName, std::string_view displayText)>;

        std::size_t loadRuntimeLocalizationYaml(std::istream& stream, std::string_view sourceName,
            const RuntimeLocalizationScalarHandler& scalarHandler = {},
            const RuntimeLocalizationFallbackHandler& fallbackHandler = {});

        std::string prepareRuntimeLocalizationText(std::string_view key, std::string_view displayText);
        std::string_view runtimeLocalizationMarkup(std::string_view key) const;
        std::string prepareRuntimeLocalizationInfoText(std::string_view key, std::string_view displayText);
        std::string_view runtimeLocalizationInfoMarkup(std::string_view key, std::string_view plainText) const;

        // QA provenance for runtime-localized display text. The loader records the
        // sidecar that successfully supplied the currently effective value.
        void recordRuntimeLocalizationSource(std::string_view key, std::string_view sourceName);
        std::string_view runtimeLocalizationSource(std::string_view key) const;
        void recordRuntimeLocalizationInfoSource(
            std::string_view key, std::string_view plainText, std::string_view sourceName);
        std::string_view runtimeLocalizationInfoSource(
            std::string_view key, std::string_view plainText) const;

        // QA highlighting is display-only. The selected source may be given as a
        // content filename, YAML filename, path, or just a matching stem.
        void setRuntimeLocalizationQaSource(std::string_view sourceName);
        bool runtimeLocalizationQaHighlight(std::string_view key) const;
        bool runtimeLocalizationInfoQaHighlight(
            std::string_view key, std::string_view plainText) const;

        void loadTranslationData(const Files::Collections& dataFileCollections, std::string_view esmFileName);

        std::string_view translateCellName(std::string_view cellName) const;

        // Display-only topic translation. Does not change the technical DIAL ID.
        std::string_view translateTopicName(std::string_view topicId) const;

        // Display-only INFO response translation. The source INFO record remains untouched.
        std::string_view translateInfoResponse(std::string_view topicId, std::string_view infoId,
            std::string_view sourceText, NpcGender npcGender = NpcGender::None,
            PlayerGender playerGender = PlayerGender::None) const;

        // Display-only translation of Choice labels from INFO result scripts.
        std::string_view translateChoice(std::string_view sourceText) const;

        // Display-only translation of selected strings from MWScript source (Say/MessageBox).
        std::string_view translateScriptString(std::string_view sourceText) const;

        // Standard form usually means nominative case
        std::string_view topicStandardForm(std::string_view phrase) const;

        // The phrase that will act as the hyperlink for the given topic ID
        std::string_view topicKeyword(std::string_view phrase) const;

        // Runtime population used by content scripts.
        void addCellNameTranslation(std::string_view cellName, std::string_view displayName);
        void addTopicNameTranslation(std::string_view topicId, std::string_view displayName);
        void addPhraseForm(std::string_view phrase, std::string_view topicId);
        void setPhraseForm(std::string_view phrase, std::string_view topicId);
        void addTopicKeyword(std::string_view topicId, std::string_view keyword);
        void addInfoResponseTranslation(
            std::string_view topicId, std::string_view infoId, std::string_view response);
        void addInfoResponseNpcTranslation(
            std::string_view topicId, std::string_view infoId, NpcGender gender, std::string_view response);
        void addInfoResponsePlayerTranslation(
            std::string_view topicId, std::string_view infoId, PlayerGender gender, std::string_view response);
        void addInfoResponseNpcPlayerTranslation(std::string_view topicId, std::string_view infoId,
            NpcGender npcGender, PlayerGender playerGender, std::string_view response);
        void addChoiceTranslation(std::string_view sourceText, std::string_view displayText);
        void addScriptStringTranslation(std::string_view sourceText, std::string_view displayText);

        void setEncoder(ToUTF8::Utf8Encoder* encoder);

    private:
        typedef std::map<std::string, std::string, std::less<>> ContainerType;

        void loadData(ContainerType& container, std::string_view fileNameNoExtension, std::string_view extension,
            const Files::Collections& dataFileCollections);

        void loadDataFromStream(ContainerType& container, std::istream& stream);

        ToUTF8::Utf8Encoder* mEncoder;
        std::map<std::string, std::string, std::less<>> mRuntimeLocalizationMarkup;
        std::map<std::string, std::string, std::less<>> mRuntimeLocalizationSource;
        std::string mRuntimeLocalizationQaSource;

        std::vector<std::string> mPreferredLocales;
        std::map<std::string, std::size_t, std::less<>> mRuntimeLocaleClaims;
        std::string mRegistrationLocale;

        ContainerType mCellNamesTranslations, mTopicNames, mInfoResponses, mInfoResponsesNpcMale,
            mInfoResponsesNpcFemale, mInfoResponsesPlayerMale, mInfoResponsesPlayerFemale,
            mInfoResponsesNpcMalePlayerMale, mInfoResponsesNpcMalePlayerFemale,
            mInfoResponsesNpcFemalePlayerMale, mInfoResponsesNpcFemalePlayerFemale,
            mChoiceTranslations, mScriptStrings, mKeywords, mPhraseForms;
    };
}

#endif
