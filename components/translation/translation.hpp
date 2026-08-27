#ifndef COMPONENTS_TRANSLATION_DATA_H
#define COMPONENTS_TRANSLATION_DATA_H

#include <components/files/collections.hpp>
#include <components/toutf8/toutf8.hpp>

namespace Translation
{
    class Storage
    {
    public:
        Storage();

        void loadTranslationData(const Files::Collections& dataFileCollections, std::string_view esmFileName);

        std::string_view translateCellName(std::string_view cellName) const;

        // Display-only topic translation. Does not change the technical DIAL ID.
        std::string_view translateTopicName(std::string_view topicId) const;

        // Display-only INFO response translation. The source INFO record remains untouched.
        std::string_view translateInfoResponse(
            std::string_view topicId, std::string_view infoId, std::string_view sourceText) const;

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
        void addChoiceTranslation(std::string_view sourceText, std::string_view displayText);
        void addScriptStringTranslation(std::string_view sourceText, std::string_view displayText);

        void setEncoder(ToUTF8::Utf8Encoder* encoder);

    private:
        typedef std::map<std::string, std::string, std::less<>> ContainerType;

        void loadData(ContainerType& container, std::string_view fileNameNoExtension, std::string_view extension,
            const Files::Collections& dataFileCollections);

        void loadDataFromStream(ContainerType& container, std::istream& stream);

        ToUTF8::Utf8Encoder* mEncoder;
        ContainerType mCellNamesTranslations, mTopicNames, mInfoResponses, mChoiceTranslations, mScriptStrings, mKeywords, mPhraseForms;
    };
}

#endif
