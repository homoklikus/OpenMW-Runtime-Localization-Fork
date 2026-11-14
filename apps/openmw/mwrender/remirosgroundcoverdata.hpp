#ifndef OPENMW_MWRENDER_REMIROSGROUNDCOVERDATA_H
#define OPENMW_MWRENDER_REMIROSGROUNDCOVERDATA_H

// Tabela reguł i mapa liczników Remirosa — deklaracje. Dane: remirosgroundcoverdata.cpp (generowany przez MCP).

#include <cstdint>
#include <span>
#include <string_view>

namespace MWRender::RemirosRules
{
    struct StaticRule
    {
        double mShare;
        std::string_view mModel; // nazwa pliku modelu (szukany jako meshes/grass/<nazwa>)
        float mScaleMin;
        float mScaleMax;
        float mZOffset;
    };

    struct TextureRule
    {
        std::string_view mTexture; // nazwa pliku tekstury LAND bez rozszerzenia, małe litery
        float mDensityPerTexel;
        std::uint16_t mFirstStatic;
        std::uint16_t mStaticCount;
    };

    struct CellCounts
    {
        std::int16_t mX;
        std::int16_t mY;
        std::uint32_t mLandHash; // odcisk wysokości LAND — liczniki tylko dla zgodnego terenu
        std::uint32_t mFirstEntry;
        std::uint16_t mEntryCount;
        std::uint32_t mFirstGroup; // grupy wpisów komórki leżą kolejno od mFirstGroup (w kolejności wpisów)
    };

    // wpis  = teksel (bity 0-7) | indeks nazwy tekstury (8-15) | liczba grup teksela (16-23)
    // grupa = pole podsiatki sSubdivisions×sSubdivisions (bity 0-3, wiersz·4+kolumna) | indeks statyki w statics()
    //         (4-11) | liczba roślin (12-19). Liczby w polach 128×128 j., bez współrzędnych pojedynczych roślin.

    constexpr float sSpreadTexels = 0.3f;
    constexpr float sUnderwaterMaxHeight = -23.f;
    constexpr int sRetries = 4;
    constexpr int sSubdivisions = 4; // pach76

    std::span<const StaticRule> statics();
    std::span<const TextureRule> textures();
    std::span<const std::string_view> textureNames();
    std::span<const CellCounts> cells();
    std::span<const std::uint32_t> entries();
    std::span<const std::uint32_t> groups();
    std::string_view sourceInfo();
}

#endif
