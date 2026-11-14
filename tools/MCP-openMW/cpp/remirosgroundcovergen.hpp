#ifndef OPENMW_MWRENDER_REMIROSGROUNDCOVERGEN_H
#define OPENMW_MWRENDER_REMIROSGROUNDCOVERGEN_H

// Generator trawy według reguł Remirosa (tekstura LAND -> gęstość, statyki, skala, wysokość) z mapą liczników
// na teksel. Rdzeń bez zależności od OSG/OpenMW — ten sam kod kompiluje się w silniku i w teście porównawczym MCP.
//
// Wzorzec: tools/MCP-openMW/cpp/remirosgroundcovergen.hpp (MCP-openMW, etap 2c + pach76). Odpowiednik w Pythonie:
// openmw_mcp/remirosrules.py::generate_cell — oba muszą dawać identyczne instancje dla tego samego terenu.
//
// Zasady (z analizy pluginów Remirosa):
//  * teksel z zapisanymi licznikami, zgodnym odciskiem terenu komórki i tą samą teksturą -> dla każdej grupy
//    (pole podsiatki 4x4 = 128x128 j., statyka) dokładnie tyle roślin tej statyki, pozycje losowe w polu
//    (do sRetries prób, gdy pod wodą) — odtwarza miks modeli i luki autora bez kopiowania współrzędnych roślin;
//  * pozostałe teksele (inny teren, inna tekstura, brak wpisu) -> reguła tekstury: gęstość na teksel, pozycje
//    w tekselu poszerzonym o sSpreadTexels z każdej strony;
//  * bez filtru zbocza i bez omijania obiektów (Remiros ich nie stosuje); teren <= sUnderwaterMaxHeight -> brak;
//  * dane zawierają wyłącznie agregaty (liczby w polach 128 j., reguły) — żadnych współrzędnych roślin z ESP.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "remirosgroundcoverdata.hpp"

namespace MWRender::RemirosGen
{
    constexpr float sCellSize = 8192.f;
    constexpr float sTwoPi = 6.2831853071795864769f;

    inline std::uint32_t hash32(std::uint32_t value)
    {
        value ^= value >> 16;
        value *= 0x7feb352du;
        value ^= value >> 15;
        value *= 0x846ca68bu;
        value ^= value >> 16;
        return value;
    }

    inline float random01(std::uint32_t seed)
    {
        return static_cast<float>(hash32(seed) & 0x00ffffffu) / static_cast<float>(0x01000000u);
    }

    /// Nazwa pliku tekstury bez katalogu i rozszerzenia, małymi literami.
    inline std::string textureKey(std::string_view name)
    {
        const std::size_t slash = name.find_last_of("/\\");
        if (slash != std::string_view::npos)
            name.remove_prefix(slash + 1);
        const std::size_t dot = name.rfind('.');
        if (dot != std::string_view::npos)
            name = name.substr(0, dot);
        std::string out(name);
        for (char& ch : out)
            if (ch >= 'A' && ch <= 'Z')
                ch = static_cast<char>(ch - 'A' + 'a');
        return out;
    }

    /// FNV-1a (32 bit) po int32(lround(h)) wszystkich wierzchołków LAND (bajty little-endian).
    template <class Heights>
    std::uint32_t landHash(const Heights& heights)
    {
        std::uint32_t hash = 2166136261u;
        for (const float h : heights)
        {
            const std::uint32_t q = static_cast<std::uint32_t>(static_cast<std::int32_t>(std::lround(h)));
            for (int k = 0; k < 4; ++k)
            {
                hash ^= (q >> (8 * k)) & 0xffu;
                hash *= 16777619u;
            }
        }
        return hash;
    }

    struct Entry
    {
        float mCumulative;
        std::string mModel;
        float mScaleMin;
        float mScaleMax;
        float mZOffset;
    };

    struct Rule
    {
        float mDensity = 0.f;
        std::vector<Entry> mEntries;
    };

    /// Statyka wg indeksu globalnego (RemirosRules::statics()); pusty mModel = brak modelu w VFS.
    struct StaticInfo
    {
        std::string mModel;
        float mScaleMin = 1.f;
        float mScaleMax = 1.f;
        float mZOffset = 0.f;
    };

    class Model
    {
    public:
        /// resolve(nazwa_pliku_modelu) -> std::optional<std::string> (ścieżka VFS albo brak, gdy modelu nie ma).
        template <class Resolve>
        explicit Model(Resolve&& resolve)
        {
            const auto statics = RemirosRules::statics();
            mStatics.reserve(statics.size());
            for (const RemirosRules::StaticRule& rule : statics)
            {
                std::optional<std::string> path = resolve(rule.mModel);
                if (!path)
                    ++mMissingStatics;
                mStatics.push_back(StaticInfo{ path ? std::move(*path) : std::string(), rule.mScaleMin,
                    rule.mScaleMax, rule.mZOffset });
            }
            for (const RemirosRules::TextureRule& texture : RemirosRules::textures())
            {
                double total = 0.0;
                for (unsigned i = 0; i < texture.mStaticCount; ++i)
                    if (!mStatics[texture.mFirstStatic + i].mModel.empty())
                        total += statics[texture.mFirstStatic + i].mShare;
                if (total <= 0.0)
                    continue;
                Rule rule;
                rule.mDensity = texture.mDensityPerTexel;
                double accumulated = 0.0;
                for (unsigned i = 0; i < texture.mStaticCount; ++i)
                {
                    const StaticInfo& info = mStatics[texture.mFirstStatic + i];
                    if (info.mModel.empty())
                        continue;
                    accumulated += statics[texture.mFirstStatic + i].mShare / total;
                    rule.mEntries.push_back(Entry{ static_cast<float>(std::min(accumulated, 1.0)), info.mModel,
                        info.mScaleMin, info.mScaleMax, info.mZOffset });
                }
                mRules.emplace(std::string(texture.mTexture), std::move(rule));
            }
        }

        bool empty() const { return mRules.empty(); }
        std::size_t ruleCount() const { return mRules.size(); }
        std::size_t missingStatics() const { return mMissingStatics; }

        const Rule* find(const std::string& key) const
        {
            const auto it = mRules.find(key);
            return it == mRules.end() ? nullptr : &it->second;
        }

        const StaticInfo* staticAt(std::size_t index) const
        {
            return index < mStatics.size() ? &mStatics[index] : nullptr;
        }

        static const RemirosRules::CellCounts* findCell(int x, int y)
        {
            const auto cells = RemirosRules::cells();
            const auto it = std::lower_bound(cells.begin(), cells.end(), std::make_pair(x, y),
                [](const RemirosRules::CellCounts& c, const std::pair<int, int>& key) {
                    return std::make_pair(static_cast<int>(c.mX), static_cast<int>(c.mY)) < key;
                });
            if (it == cells.end() || it->mX != x || it->mY != y)
                return nullptr;
            return &*it;
        }

    private:
        std::unordered_map<std::string, Rule> mRules;
        std::vector<StaticInfo> mStatics;
        std::size_t mMissingStatics = 0;
    };

    struct CellStats
    {
        bool mCountsUsed = false;
        int mCountTexels = 0;
        int mRuleTexels = 0;
        int mInstances = 0;
    };

    /// Terrain: bool hasLandTextures(int, int); std::optional<std::uint32_t> landHash(int, int);
    ///          std::string textureKeyAt(float x, float y); float heightAt(float x, float y)  (jednostki świata).
    /// Sink: (const std::string& model, float x, float y, float z, float scale, float rotZ).
    /// min/max: granice chunku w jednostkach komórek (filtr jak isInChunkBorders dla chunków < 1 komórki).
    template <class Terrain, class Sink>
    CellStats collectCell(const Model& model, Terrain& terrain, int cellX, int cellY, float density, float minX,
        float minY, float maxX, float maxY, Sink&& sink)
    {
        CellStats stats;
        if (!terrain.hasLandTextures(cellX, cellY))
            return stats;

        const RemirosRules::CellCounts* counts = Model::findCell(cellX, cellY);
        bool countsValid = false;
        if (counts != nullptr)
        {
            const std::optional<std::uint32_t> hash = terrain.landHash(cellX, cellY);
            countsValid = hash.has_value() && *hash == counts->mLandHash;
        }
        std::array<int, 256> recordedTexture;
        recordedTexture.fill(-1);
        std::array<std::uint32_t, 256> firstGroup{};
        std::array<int, 256> groupCount{};
        const auto groups = RemirosRules::groups();
        if (countsValid)
        {
            const auto entries = RemirosRules::entries();
            std::uint32_t next = counts->mFirstGroup;
            for (unsigned i = 0; i < counts->mEntryCount; ++i)
            {
                const std::uint32_t e = entries[counts->mFirstEntry + i];
                const int texel = static_cast<int>(e & 0xffu);
                recordedTexture[texel] = static_cast<int>((e >> 8) & 0xffu);
                firstGroup[texel] = next;
                groupCount[texel] = static_cast<int>((e >> 16) & 0xffu);
                next += static_cast<std::uint32_t>(groupCount[texel]);
            }
        }
        stats.mCountsUsed = countsValid;
        const auto names = RemirosRules::textureNames();
        const bool filter = (maxX - minX) < 1.f || (maxY - minY) < 1.f;
        const std::uint32_t cxu = static_cast<std::uint32_t>(cellX) * 0x9e3779b9u;
        const std::uint32_t cyu = static_cast<std::uint32_t>(cellY) * 0x85ebca6bu;
        constexpr float sub = static_cast<float>(RemirosRules::sSubdivisions);

        const auto countOf = [](float d, std::uint32_t seed) {
            const float whole = std::floor(d);
            return static_cast<int>(whole) + (random01(seed ^ 0x2545f491u) < d - whole ? 1 : 0);
        };

        struct Placed
        {
            float mWorldX, mWorldY, mHeight;
            std::uint32_t mSeed;
        };
        // offset(seed, px, py): pozycja w jednostkach komórek; nullopt = pod wodą (po próbach) lub poza chunkiem.
        const auto place = [&](std::uint32_t s0, int attempts, auto&& offset) -> std::optional<Placed> {
            for (int attempt = 0; attempt < attempts; ++attempt)
            {
                const std::uint32_t s
                    = attempt == 0 ? s0 : hash32(s0 ^ (static_cast<std::uint32_t>(attempt) * 0x632be5abu));
                float px = 0.f, py = 0.f;
                offset(s, px, py);
                const float wx = px * sCellSize;
                const float wy = py * sCellSize;
                const float h = terrain.heightAt(wx, wy);
                if (h <= RemirosRules::sUnderwaterMaxHeight)
                    continue;
                if (filter
                    && ((minX > std::floor(minX) && px < minX) || (minY > std::floor(minY) && py < minY)
                        || (maxX < std::ceil(maxX) && px >= maxX) || (maxY < std::ceil(maxY) && py >= maxY)))
                    return std::nullopt;
                return Placed{ wx, wy, h, s };
            }
            return std::nullopt;
        };
        const auto emit = [&](const Placed& p, const std::string& modelPath, float scaleMin, float scaleMax,
                              float zOffset) {
            const float scale = scaleMin + random01(p.mSeed ^ 0x63d83595u) * (scaleMax - scaleMin);
            sink(modelPath, p.mWorldX, p.mWorldY, p.mHeight + zOffset, scale, random01(p.mSeed ^ 0xa511e9b3u) * sTwoPi);
            ++stats.mInstances;
        };

        for (int ty = 0; ty < 16; ++ty)
        {
            for (int tx = 0; tx < 16; ++tx)
            {
                const int texel = ty * 16 + tx;
                const float sx = (static_cast<float>(cellX) + (static_cast<float>(tx) + 0.5f) / 16.f) * sCellSize;
                const float sy = (static_cast<float>(cellY) + (static_cast<float>(ty) + 0.5f) / 16.f) * sCellSize;
                const std::string key = terrain.textureKeyAt(sx, sy);
                const std::uint32_t texelSeed = hash32(cxu ^ cyu ^ (static_cast<std::uint32_t>(texel) * 0xc2b2ae35u));

                if (recordedTexture[texel] >= 0 && names[recordedTexture[texel]] == key)
                {
                    ++stats.mCountTexels;
                    for (int gi = 0; gi < groupCount[texel]; ++gi)
                    {
                        const std::uint32_t g = groups[firstGroup[texel] + static_cast<std::uint32_t>(gi)];
                        const StaticInfo* info = model.staticAt((g >> 4) & 0xffu);
                        if (info == nullptr || info->mModel.empty())
                            continue;
                        const float fx = static_cast<float>(g & 3u);
                        const float fy = static_cast<float>((g >> 2) & 3u);
                        const std::uint32_t groupSeed
                            = hash32(texelSeed ^ (static_cast<std::uint32_t>(gi + 1) * 0x165667b1u));
                        const int n = countOf(static_cast<float>((g >> 12) & 0xffu) * density, groupSeed);
                        for (int k = 0; k < n; ++k)
                        {
                            const auto p = place(hash32(groupSeed ^ (0x9e3779b9u * static_cast<std::uint32_t>(k + 1))),
                                RemirosRules::sRetries, [&](std::uint32_t s, float& px, float& py) {
                                    px = static_cast<float>(cellX)
                                        + (static_cast<float>(tx) + (fx + random01(s ^ 0x68bc21ebu)) / sub) / 16.f;
                                    py = static_cast<float>(cellY)
                                        + (static_cast<float>(ty) + (fy + random01(s ^ 0x02e5be93u)) / sub) / 16.f;
                                });
                            if (p)
                                emit(*p, info->mModel, info->mScaleMin, info->mScaleMax, info->mZOffset);
                        }
                    }
                    continue;
                }

                const Rule* own = model.find(key);
                if (own == nullptr)
                    continue;
                ++stats.mRuleTexels;
                const float d = own->mDensity * density;
                if (d <= 0.f)
                    continue;
                constexpr float spread = RemirosRules::sSpreadTexels;
                const float width = 1.f + 2.f * spread;
                const int n = countOf(d, texelSeed);
                for (int k = 0; k < n; ++k)
                {
                    const auto p = place(hash32(texelSeed ^ (0x9e3779b9u * static_cast<std::uint32_t>(k + 1))), 1,
                        [&](std::uint32_t s, float& px, float& py) {
                            px = static_cast<float>(cellX)
                                + (static_cast<float>(tx) + (random01(s ^ 0x68bc21ebu) * width - spread)) / 16.f;
                            py = static_cast<float>(cellY)
                                + (static_cast<float>(ty) + (random01(s ^ 0x02e5be93u) * width - spread)) / 16.f;
                        });
                    if (!p)
                        continue;
                    const float pick = random01(p->mSeed ^ 0x91e10da5u);
                    const Entry* entry = &own->mEntries.back();
                    for (const Entry& e : own->mEntries)
                    {
                        if (pick < e.mCumulative)
                        {
                            entry = &e;
                            break;
                        }
                    }
                    emit(*p, entry->mModel, entry->mScaleMin, entry->mScaleMax, entry->mZOffset);
                }
            }
        }
        return stats;
    }
}

#endif
