// Test porównawczy: rdzeń generatora (remirosgroundcovergen.hpp) na zrzucie terenu z MCP.
// Teren odwzorowuje openmw_mcp/land.py (wysokość „diamond” w double, tekstura floor(local·16)), więc wynik
// musi być identyczny z remirosrules.generate_cell(..., include_instances=True).
//
//   g++ -std=c++20 -O2 -I cpp -I <katalog_danych> cpp/remiros_harness.cpp <katalog_danych>/remirosgroundcoverdata.cpp
//   ./a.out teren.txt gestosc cx,cy [cx,cy ...]

#include "remirosgroundcovergen.hpp"

#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace
{
    constexpr double sCell = 8192.0;

    struct CellData
    {
        std::uint32_t mHash = 0;
        std::vector<double> mHeights;
        std::vector<std::string> mTextures;
    };

    double planeZ(const double a[3], const double b[3], const double c[3], double x, double y)
    {
        const double ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
        const double vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
        const double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        return a[2] - (nx * (x - a[0]) + ny * (y - a[1])) / nz;
    }

    struct DumpTerrain
    {
        std::map<std::pair<int, int>, CellData> mCells;

        const CellData* cell(int x, int y) const
        {
            const auto it = mCells.find({ x, y });
            return it == mCells.end() ? nullptr : &it->second;
        }

        bool hasLandTextures(int x, int y) const { return cell(x, y) != nullptr; }

        std::optional<std::uint32_t> landHash(int x, int y) const
        {
            const CellData* c = cell(x, y);
            if (c == nullptr)
                return std::nullopt;
            return c->mHash;
        }

        std::string textureKeyAt(float fx, float fy) const
        {
            const double wx = fx, wy = fy;
            const int cx = static_cast<int>(std::floor(wx / sCell));
            const int cy = static_cast<int>(std::floor(wy / sCell));
            const CellData* c = cell(cx, cy);
            if (c == nullptr)
                return {};
            const double lx = std::min(std::max(wx / sCell - cx, 0.0), 0.999999);
            const double ly = std::min(std::max(wy / sCell - cy, 0.0), 0.999999);
            const int tx = std::min(static_cast<int>(lx * 16), 15);
            const int ty = std::min(static_cast<int>(ly * 16), 15);
            const std::string& t = c->mTextures[ty * 16 + tx];
            return t == "-" ? std::string() : t;
        }

        float heightAt(float fx, float fy) const
        {
            const double wx = fx, wy = fy;
            const int cx = static_cast<int>(std::floor(wx / sCell));
            const int cy = static_cast<int>(std::floor(wy / sCell));
            const CellData* c = cell(cx, cy);
            if (c == nullptr)
                return -1.0e9f;
            const std::vector<double>& h = c->mHeights;
            const double nx = (wx - cx * sCell) / sCell, ny = (wy - cy * sCell) / sCell;
            const int f = 64;
            const int sx = std::min(std::max(static_cast<int>(nx * f), 0), 64);
            const int sy = std::min(std::max(static_cast<int>(ny * f), 0), 64);
            const int ex = std::min(sx + 1, 64), ey = std::min(sy + 1, 64);
            if (sx == ex || sy == ey)
                return static_cast<float>(h[sy * 65 + sx]);
            const double xp = nx * f - sx, yp = ny * f - sy;
            const double v0[3] = { 0, 0, h[sy * 65 + sx] }, v1[3] = { 1, 0, h[sy * 65 + ex] };
            const double v2[3] = { 1, 1, h[ey * 65 + ex] }, v3[3] = { 0, 1, h[ey * 65 + sx] };
            double z;
            if ((sx + sy) & 1)
                z = (1.0 - yp) > xp ? planeZ(v0, v1, v3, xp, yp) : planeZ(v1, v2, v3, xp, yp);
            else
                z = yp > xp ? planeZ(v0, v2, v3, xp, yp) : planeZ(v0, v1, v2, xp, yp);
            return static_cast<float>(z);
        }
    };
}

int main(int argc, char** argv)
{
    if (argc < 4)
    {
        std::fprintf(stderr, "użycie: %s teren.txt gestosc cx,cy [...]\n", argv[0]);
        return 2;
    }
    DumpTerrain terrain;
    std::ifstream in(argv[1]);
    std::string line;
    while (std::getline(in, line))
    {
        if (line.rfind("CELL ", 0) != 0)
            continue;
        std::istringstream head(line.substr(5));
        int x, y;
        std::uint32_t hash;
        head >> x >> y >> hash;
        CellData c;
        c.mHash = hash;
        std::getline(in, line);
        std::istringstream hs(line);
        double v;
        while (hs >> v)
            c.mHeights.push_back(v);
        std::getline(in, line);
        std::istringstream ts(line);
        std::string t;
        while (ts >> t)
            c.mTextures.push_back(t);
        if (c.mHeights.size() == 65 * 65 && c.mTextures.size() == 256)
            terrain.mCells[{ x, y }] = std::move(c);
    }
    const MWRender::RemirosGen::Model model(
        [](std::string_view m) { return std::optional<std::string>(std::string(m)); });
    const float density = std::stof(argv[2]);
    for (int i = 3; i < argc; ++i)
    {
        int cx, cy;
        if (std::sscanf(argv[i], "%d,%d", &cx, &cy) != 2)
            continue;
        MWRender::RemirosGen::collectCell(model, terrain, cx, cy, density, static_cast<float>(cx),
            static_cast<float>(cy), static_cast<float>(cx + 1), static_cast<float>(cy + 1),
            [&](const std::string& m, float x, float y, float z, float scale, float rot) {
                std::printf("%d %d %s %.9g %.9g %.9g %.9g %.9g\n", cx, cy, m.c_str(), x, y, z, scale, rot);
            });
    }
    return 0;
}
