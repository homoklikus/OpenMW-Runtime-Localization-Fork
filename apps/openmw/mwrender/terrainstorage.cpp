#include "terrainstorage.hpp"

#include <algorithm>
#include <cmath>

#include <components/esm3/loadland.hpp>
#include <components/esm4/loadltex.hpp>
#include <components/esm4/loadtxst.hpp>
#include <components/esm4/loadwrld.hpp>

#include "../mwbase/environment.hpp"
#include "../mwworld/esmstore.hpp"

#include "landmanager.hpp"

namespace MWRender
{

    TerrainStorage::TerrainStorage(Resource::ResourceSystem* resourceSystem, std::string_view normalMapPattern,
        std::string_view normalHeightMapPattern, bool autoUseNormalMaps, std::string_view specularMapPattern,
        bool autoUseSpecularMaps)
        : ESMTerrain::Storage(resourceSystem->getVFS(), normalMapPattern, normalHeightMapPattern, autoUseNormalMaps,
            specularMapPattern, autoUseSpecularMaps)
        , mLandManager(new LandManager(
              ESM::Land::DATA_VCLR | ESM::Land::DATA_VHGT | ESM::Land::DATA_VNML | ESM::Land::DATA_VTEX))
        , mResourceSystem(resourceSystem)
    {
        mResourceSystem->addResourceManager(mLandManager.get());
    }

    TerrainStorage::~TerrainStorage()
    {
        mResourceSystem->removeResourceManager(mLandManager.get());
    }

    bool TerrainStorage::hasData(ESM::ExteriorCellLocation cellLocation)
    {
        const MWWorld::ESMStore& esmStore = *MWBase::Environment::get().getESMStore();

        if (ESM::isEsm4Ext(cellLocation.mWorldspace))
        {
            const ESM4::World* worldspace = esmStore.get<ESM4::World>().find(cellLocation.mWorldspace);
            if (!worldspace->mParent.isZeroOrUnset() && worldspace->mParentUseFlags & ESM4::World::UseFlag_Land)
                cellLocation.mWorldspace = worldspace->mParent;

            return esmStore.get<ESM4::Land>().search(cellLocation) != nullptr;
        }
        else
        {
            return esmStore.get<ESM::Land>().search(cellLocation.mX, cellLocation.mY) != nullptr;
        }
    }

    static void BoundUnion(float& minX, float& maxX, float& minY, float& maxY, float x, float y)
    {
        if (x < minX)
            minX = x;
        if (x > maxX)
            maxX = x;
        if (y < minY)
            minY = y;
        if (y > maxY)
            maxY = y;
    }

    void TerrainStorage::getBounds(float& minX, float& maxX, float& minY, float& maxY, ESM::RefId worldspace)
    {
        minX = 0;
        minY = 0;
        maxX = 0;
        maxY = 0;

        const MWWorld::ESMStore& esmStore = *MWBase::Environment::get().getESMStore();

        if (ESM::isEsm4Ext(worldspace))
        {
            const ESM4::World* worldRec = esmStore.get<ESM4::World>().find(worldspace);
            if (!worldRec->mParent.isZeroOrUnset() && worldRec->mParentUseFlags & ESM4::World::UseFlag_Land)
                worldspace = worldRec->mParent;

            const auto& lands = esmStore.get<ESM4::Land>().getLands();
            for (const auto& [landPos, _] : lands)
            {
                if (landPos.mWorldspace == worldspace)
                {
                    BoundUnion(minX, maxX, minY, maxY, static_cast<float>(landPos.mX), static_cast<float>(landPos.mY));
                }
            }
        }
        else
        {
            MWWorld::Store<ESM::Land>::iterator it = esmStore.get<ESM::Land>().begin();
            for (; it != esmStore.get<ESM::Land>().end(); ++it)
            {
                BoundUnion(minX, maxX, minY, maxY, static_cast<float>(it->mX), static_cast<float>(it->mY));
            }
        }
        // since grid coords are at cell origin, we need to add 1 cell
        maxX += 1;
        maxY += 1;
    }

    LandManager* TerrainStorage::getLandManager() const
    {
        return mLandManager.get();
    }

    osg::ref_ptr<const ESMTerrain::LandObject> TerrainStorage::getLand(ESM::ExteriorCellLocation cellLocation)
    {
        return mLandManager->getLand(cellLocation);
    }

    const std::string* TerrainStorage::getLandTexture(std::uint16_t index, int plugin)
    {
        const MWWorld::ESMStore& esmStore = *MWBase::Environment::get().getESMStore();
        return esmStore.get<ESM::LandTexture>().search(index, plugin);
    }

    VFS::Path::Normalized TerrainStorage::getLandTextureAt(
        const osg::Vec3f& worldPos, ESM::RefId worldspace)
    {
        if (ESM::isEsm4Ext(worldspace))
            return {};

        const float cellSize = static_cast<float>(ESM::Land::REAL_SIZE);
        const int cellX = static_cast<int>(std::floor(worldPos.x() / cellSize));
        const int cellY = static_cast<int>(std::floor(worldPos.y() / cellSize));

        const osg::ref_ptr<const ESMTerrain::LandObject> land
            = getLand(ESM::ExteriorCellLocation(cellX, cellY, worldspace));
        if (!land)
            return {};

        const ESM::LandData* data = land->getData(ESM::Land::DATA_VTEX);
        if (data == nullptr)
            return {};

        const float localX = std::clamp(worldPos.x() / cellSize - static_cast<float>(cellX), 0.f, 0.999999f);
        const float localY = std::clamp(worldPos.y() / cellSize - static_cast<float>(cellY), 0.f, 0.999999f);

        const int texX = std::clamp(
            static_cast<int>(localX * ESM::Land::LAND_TEXTURE_SIZE), 0, ESM::Land::LAND_TEXTURE_SIZE - 1);
        const int texY = std::clamp(
            static_cast<int>(localY * ESM::Land::LAND_TEXTURE_SIZE), 0, ESM::Land::LAND_TEXTURE_SIZE - 1);

        const std::uint16_t textureIndex
            = data->getTextures()[texY * ESM::Land::LAND_TEXTURE_SIZE + texX];

        if (textureIndex == 0)
            return VFS::Path::Normalized("_land_default.dds");

        // LAND VTEX ids are +1 compared to LTEX ids.
        const std::string* texture = getLandTexture(textureIndex - 1, land->getPlugin());
        if (texture == nullptr)
            return {};

        return VFS::Path::Normalized(*texture);
    }

    float TerrainStorage::getSlopeDegreesAt(const osg::Vec3f& worldPos, ESM::RefId worldspace)
    {
        // One vanilla LAND height vertex is 128 world units apart.
        const float sampleDistance
            = static_cast<float>(ESM::Land::REAL_SIZE) / static_cast<float>(ESM::Land::LAND_SIZE - 1);

        const float left = getHeightAt(
            osg::Vec3f(worldPos.x() - sampleDistance, worldPos.y(), 0.f), worldspace);
        const float right = getHeightAt(
            osg::Vec3f(worldPos.x() + sampleDistance, worldPos.y(), 0.f), worldspace);
        const float down = getHeightAt(
            osg::Vec3f(worldPos.x(), worldPos.y() - sampleDistance, 0.f), worldspace);
        const float up = getHeightAt(
            osg::Vec3f(worldPos.x(), worldPos.y() + sampleDistance, 0.f), worldspace);

        const float dzdx = (right - left) / (2.f * sampleDistance);
        const float dzdy = (up - down) / (2.f * sampleDistance);
        const float gradient = std::sqrt(dzdx * dzdx + dzdy * dzdy);

        constexpr float radiansToDegrees = 57.29577951308232f;
        return std::atan(gradient) * radiansToDegrees;
    }

    const ESM4::LandTexture* TerrainStorage::getEsm4LandTexture(ESM::RefId ltexId) const
    {
        const MWWorld::ESMStore& esmStore = *MWBase::Environment::get().getESMStore();
        return esmStore.get<ESM4::LandTexture>().search(ltexId);
    }

    const ESM4::TextureSet* TerrainStorage::getEsm4TextureSet(ESM::RefId txstId) const
    {
        const MWWorld::ESMStore& esmStore = *MWBase::Environment::get().getESMStore();
        return esmStore.get<ESM4::TextureSet>().search(txstId);
    }
}
