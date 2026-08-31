#include "translation.hpp"

#include <fstream>

#include <components/misc/pathhelpers.hpp>

namespace Translation
{
    namespace
    {
        std::string makeInfoKey(std::string_view topicId, std::string_view infoId)
        {
            std::string key;
            key.reserve(topicId.size() + infoId.size() + 1);
            key.append(topicId);
            key.push_back('\0');
            key.append(infoId);
            return key;
        }
    }

    Storage::Storage()
        : mEncoder(nullptr)
    {
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
        mInfoResponses.insert_or_assign(makeInfoKey(topicId, infoId), std::string(response));
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
            target->insert_or_assign(makeInfoKey(topicId, infoId), std::string(response));
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
            target->insert_or_assign(makeInfoKey(topicId, infoId), std::string(response));
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
            target->insert_or_assign(makeInfoKey(topicId, infoId), std::string(response));
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
