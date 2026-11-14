#ifndef OPENMW_MWRENDER_REMIROSGROUNDCOVERGEN_H
#define OPENMW_MWRENDER_REMIROSGROUNDCOVERGEN_H

// Generator trawy według reguł Remirosa (tekstura LAND -> gęstość, statyki, skala, wysokość) z mapą liczników
// na teksel. Rdzeń bez zależności od OSG/OpenMW — ten sam kod kompiluje się w silniku i w teście porównawczym MCP.
//
// Wzorzec: tools/MCP-openMW/cpp/remirosgroundcovergen.hpp (MCP-openMW, etap 2c). Odpowiednik w Pythonie:
// openmw_mcp/remirosrules.py::generate_cell — oba muszą dawać identyczne instancje dla tego samego terenu.
//
// Zasady (z analizy pluginów Remirosa):
//  * teksel z zapisanym licznikiem, zgodnym odciskiem terenu komórki i tą samą teksturą -> dokładnie tyle roślin,
//    pozycje losowe w tekselu (do sRetries prób, gdy pod wodą), model wg tekstury w punkcie przesuniętym o ±0,3 teksela;
//  * pozostałe teksele (inny teren, inna tekstura, brak wpisu) -> reguła tekstury: gęstość na teksel, pozycje
//    w tekselu poszerzonym o sSpreadTexels z każdej strony;
//  * bez filtru zbocza i bez omijania obiektów (Remiros ich nie stosuje); teren <= sUnderwaterMaxHeight -> brak;
//  * dane zawierają wyłącznie agregaty (liczby na teksel, reguły) — żadnych współrzędnych roślin z ESP.

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

    class Model
    {
    public:
        /// resolve(nazwa_pliku_modelu) -> std::optional<std::string> (ścieżka VFS albo brak, gdy modelu nie ma).
        template <class Resolve>
        explicit Model(Resolve&& resolve)
        {
            const auto statics = RemirosRules::statics();
            for (const RemirosRules::TextureRule& texture : RemirosRules::textures())
            {
                std::vector<const RemirosRules::StaticRule*> usable;
                std::vector<std::string> paths;
                double total = 0.0;
                for (unsigned i = 0; i < texture.mStaticCount; ++i)
                {
                    const RemirosRules::StaticRule& rule = statics[texture.mFirstStatic + i];
                    std::optional<std::string> path = resolve(rule.mModel);
                    if (!path)
                    {
                        ++mMissingStatics;
                        continue;
                    }
                    usable.push_back(&rule);
                    paths.push_back(std::move(*path));
                    total += rule.mShare;
                }
                if (usable.empty() || total <= 0.0)
                    continue;
                Rule rule;
                rule.mDensity = texture.mDensityPerTexel;
                double accumulated = 0.0;
                for (std::size_t i = 0; i < usable.size(); ++i)
                {
                    accumulated += usable[i]->mShare / total;
                    rule.mEntries.push_back(Entry{ static_cast<float>(std::min(accumulated, 1.0)), paths[i],
                        usable[i]->mScaleMin, usable[i]->mScaleMax, usable[i]->mZOffset });
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
        std::array<int, 256> recordedCount{};
        if (countsValid)
        {
            const auto entries = RemirosRules::entries();
            for (unsigned i = 0; i < counts->mEntryCount; ++i)
            {
                const std::uint32_t e = entries[counts->mFirstEntry + i];
                recordedTexture[e & 0xffu] = static_cast<int>((e >> 8) & 0xffu);
                recordedCount[e & 0xffu] = static_cast<int>((e >> 16) & 0xffu);
            }
        }
        stats.mCountsUsed = countsValid;
        const auto names = RemirosRules::textureNames();
        const bool filter = (maxX - minX) < 1.f || (maxY - minY) < 1.f;
        const std::uint32_t cxu = static_cast<std::uint32_t>(cellX) * 0x9e3779b9u;
        const std::uint32_t cyu = static_cast<std::uint32_t>(cellY) * 0x85ebca6bu;

        for (int ty = 0; ty < 16; ++ty)
        {
            for (int tx = 0; tx < 16; ++tx)
            {
                const int texel = ty * 16 + tx;
                const float sx = (static_cast<float>(cellX) + (static_cast<float>(tx) + 0.5f) / 16.f) * sCellSize;
                const float sy = (static_cast<float>(cellY) + (static_cast<float>(ty) + 0.5f) / 16.f) * sCellSize;
                const std::string key = terrain.textureKeyAt(sx, sy);
                const Rule* own = model.find(key);

                float baseCount = 0.f;
                float spread = 0.f;
                if (recordedTexture[texel] >= 0 && names[recordedTexture[texel]] == key)
                {
                    baseCount = static_cast<float>(recordedCount[texel]);
                    ++stats.mCountTexels;
                }
                else
                {
                    if (own == nullptr)
                        continue;
                    baseCount = own->mDensity;
                    spread = RemirosRules::sSpreadTexels;
                    ++stats.mRuleTexels;
                }

                const float d = baseCount * density;
                if (d <= 0.f)
                    continue;
                const std::uint32_t texelSeed = hash32(cxu ^ cyu ^ (static_cast<std::uint32_t>(texel) * 0xc2b2ae35u));
                const float whole = std::floor(d);
                const int n = static_cast<int>(whole) + (random01(texelSeed ^ 0x2545f491u) < d - whole ? 1 : 0);
                const float width = 1.f + 2.f * spread;
                const int attempts = spread == 0.f ? RemirosRules::sRetries : 1;

                for (int k = 0; k < n; ++k)
                {
                    const std::uint32_t s0 = hash32(texelSeed ^ (0x9e3779b9u * static_cast<std::uint32_t>(k + 1)));
                    std::uint32_t s = s0;
                    float px = 0.f, py = 0.f, wx = 0.f, wy = 0.f, h = 0.f;
                    bool placed = false;
                    for (int attempt = 0; attempt < attempts; ++attempt)
                    {
                        s = attempt == 0 ? s0 : hash32(s0 ^ (static_cast<std::uint32_t>(attempt) * 0x632be5abu));
                        const float u = random01(s ^ 0x68bc21ebu) * width - spread;
                        const float v = random01(s ^ 0x02e5be93u) * width - spread;
                        px = static_cast<float>(cellX) + (static_cast<float>(tx) + u) / 16.f;
                        py = static_cast<float>(cellY) + (static_cast<float>(ty) + v) / 16.f;
                        wx = px * sCellSize;
                        wy = py * sCellSize;
                        h = terrain.heightAt(wx, wy);
                        if (h > RemirosRules::sUnderwaterMaxHeight)
                        {
                            placed = true;
                            break;
                        }
                    }
                    if (!placed)
                        continue;
                    if (filter
                        && ((minX > std::floor(minX) && px < minX) || (minY > std::floor(minY) && py < minY)
                            || (maxX < std::ceil(maxX) && px >= maxX) || (maxY < std::ceil(maxY) && py >= maxY)))
                        continue;

                    const Rule* rule = own;
                    if (spread == 0.f)
                    {
                        const float jx = (random01(s ^ 0x7f4a7c15u) * 2.f - 1.f) * RemirosRules::sSpreadTexels;
                        const float jy = (random01(s ^ 0x3c6ef372u) * 2.f - 1.f) * RemirosRules::sSpreadTexels;
                        const Rule* shifted
                            = model.find(terrain.textureKeyAt((px + jx / 16.f) * sCellSize, (py + jy / 16.f) * sCellSize));
                        rule = shifted != nullptr ? shifted : own;
                        if (rule == nullptr)
                        {
                            constexpr int dirs[4][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };
                            for (const auto& dir : dirs)
                            {
                                rule = model.find(terrain.textureKeyAt(wx + static_cast<float>(dir[0]) * (sCellSize / 16.f),
                                    wy + static_cast<float>(dir[1]) * (sCellSize / 16.f)));
                                if (rule != nullptr)
                                    break;
                            }
                        }
                        if (rule == nullptr)
                            continue;
                    }

                    const float pick = random01(s ^ 0x91e10da5u);
                    const Entry* entry = &rule->mEntries.back();
                    for (const Entry& e : rule->mEntries)
                    {
                        if (pick < e.mCumulative)
                        {
                            entry = &e;
                            break;
                        }
                    }
                    const float scale
                        = entry->mScaleMin + random01(s ^ 0x63d83595u) * (entry->mScaleMax - entry->mScaleMin);
                    sink(entry->mModel, wx, wy, h + entry->mZOffset, scale, random01(s ^ 0xa511e9b3u) * sTwoPi);
                    ++stats.mInstances;
                }
            }
        }
        return stats;
    }
}

#endif
