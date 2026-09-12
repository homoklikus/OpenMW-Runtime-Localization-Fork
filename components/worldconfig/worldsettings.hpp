#ifndef OPENMW_COMPONENTS_WORLDCONFIG_WORLDSETTINGS_H
#define OPENMW_COMPONENTS_WORLDCONFIG_WORLDSETTINGS_H

#include <filesystem>
#include <string_view>

namespace WorldConfig
{
    enum class FloraSource
    {
        Automatic,
        Groundcover,
        Hybrid
    };

    struct FloraSettings
    {
        bool mEnabled = false;
        FloraSource mSource = FloraSource::Automatic;
        float mDensity = 1.f;
        // Extra clearance around roads/pathgrids and blocking world objects, in metres.
        float mExclusionDistance = 3.f;
    };

    struct FaunaSettings
    {
        bool mEnabled = false;
    };

    struct Settings
    {
        int mVersion = 1;
        FloraSettings mFlora;
        FaunaSettings mFauna;
    };

    Settings load(const std::filesystem::path& path);
    std::string_view toString(FloraSource source);
}

#endif
