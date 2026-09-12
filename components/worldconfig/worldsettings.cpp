#include "worldsettings.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <string>

#include <components/debug/debuglog.hpp>

namespace
{
    std::string trim(std::string value)
    {
        auto notSpace = [](unsigned char c) { return !std::isspace(c); };

        value.erase(value.begin(), std::find_if(value.begin(), value.end(), notSpace));
        value.erase(std::find_if(value.rbegin(), value.rend(), notSpace).base(), value.end());
        return value;
    }

    std::string lower(std::string value)
    {
        std::transform(value.begin(), value.end(), value.begin(),
            [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return value;
    }

    bool parseBool(const std::string& value, bool fallback)
    {
        const std::string normalized = lower(trim(value));

        if (normalized == "true" || normalized == "1" || normalized == "yes" || normalized == "on")
            return true;
        if (normalized == "false" || normalized == "0" || normalized == "no" || normalized == "off")
            return false;

        return fallback;
    }

    int parseInt(const std::string& value, int fallback)
    {
        try
        {
            const std::string normalized = trim(value);
            std::size_t parsed = 0;
            const int result = std::stoi(normalized, &parsed);
            if (parsed == normalized.size())
                return result;
        }
        catch (...)
        {
        }
        return fallback;
    }

    float parseFloat(const std::string& value, float fallback)
    {
        try
        {
            const std::string normalized = trim(value);
            std::size_t parsed = 0;
            const float result = std::stof(normalized, &parsed);
            if (parsed == normalized.size())
                return result;
        }
        catch (...)
        {
        }
        return fallback;
    }

    WorldConfig::FloraSource parseFloraSource(
        const std::string& value, WorldConfig::FloraSource fallback)
    {
        const std::string normalized = lower(trim(value));

        if (normalized == "automatic")
            return WorldConfig::FloraSource::Automatic;
        if (normalized == "groundcover")
            return WorldConfig::FloraSource::Groundcover;
        if (normalized == "hybrid")
            return WorldConfig::FloraSource::Hybrid;

        return fallback;
    }
}

namespace WorldConfig
{
    Settings load(const std::filesystem::path& path)
    {
        Settings result;

        std::ifstream stream(path);
        if (!stream)
        {
            Log(Debug::Info) << "World config not found at " << path
                             << "; using built-in defaults.";
            return result;
        }

        std::string section;
        std::string line;
        std::size_t lineNumber = 0;

        while (std::getline(stream, line))
        {
            ++lineNumber;
            std::string text = trim(line);

            if (text.empty() || text[0] == '#' || text[0] == ';')
                continue;

            if (text.front() == '[' && text.back() == ']')
            {
                section = lower(trim(text.substr(1, text.size() - 2)));
                continue;
            }

            const std::size_t separator = text.find('=');
            if (separator == std::string::npos)
            {
                Log(Debug::Warning) << "World config: ignoring malformed line "
                                    << lineNumber << " in " << path;
                continue;
            }

            const std::string key = lower(trim(text.substr(0, separator)));
            const std::string value = trim(text.substr(separator + 1));

            if (section == "world")
            {
                if (key == "version")
                    result.mVersion = std::max(1, parseInt(value, result.mVersion));
            }
            else if (section == "flora")
            {
                if (key == "enabled")
                    result.mFlora.mEnabled = parseBool(value, result.mFlora.mEnabled);
                else if (key == "source")
                    result.mFlora.mSource = parseFloraSource(value, result.mFlora.mSource);
                else if (key == "density")
                    result.mFlora.mDensity
                        = std::clamp(parseFloat(value, result.mFlora.mDensity), 0.f, 2.f);
            }
            else if (section == "fauna")
            {
                if (key == "enabled")
                    result.mFauna.mEnabled = parseBool(value, result.mFauna.mEnabled);
            }
        }

        return result;
    }

    std::string_view toString(FloraSource source)
    {
        switch (source)
        {
            case FloraSource::Automatic:
                return "automatic";
            case FloraSource::Groundcover:
                return "groundcover";
            case FloraSource::Hybrid:
                return "hybrid";
        }

        return "automatic";
    }
}
