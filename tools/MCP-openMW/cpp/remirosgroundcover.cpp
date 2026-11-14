#include "remirosgroundcover.hpp"

#include <algorithm>
#include <cmath>
#include <optional>
#include <sstream>

#include <osg/Vec3f>

#include <components/esm/exteriorcelllocation.hpp>
#include <components/esm3/loadcell.hpp>
#include <components/esm3/loadland.hpp>
#include <components/vfs/manager.hpp>

#include "remirosgroundcoverdata.hpp"
#include "remirosgroundcovergen.hpp"
#include "terrainstorage.hpp"

namespace MWRender
{
    namespace
    {
        struct StorageTerrain
        {
            TerrainStorage* mStorage;
            ESM::RefId mWorldspace = ESM::Cell::sDefaultWorldspaceId;

            osg::ref_ptr<const ESMTerrain::LandObject> land(int x, int y) const
            {
                return mStorage->getLand(ESM::ExteriorCellLocation(x, y, mWorldspace));
            }

            bool hasLandTextures(int x, int y) const
            {
                const osg::ref_ptr<const ESMTerrain::LandObject> object = land(x, y);
                return object != nullptr && object->getData(ESM::Land::DATA_VTEX) != nullptr;
            }

            std::optional<std::uint32_t> landHash(int x, int y) const
            {
                const osg::ref_ptr<const ESMTerrain::LandObject> object = land(x, y);
                if (object == nullptr)
                    return std::nullopt;
                const ESM::LandData* data = object->getData(ESM::Land::DATA_VHGT);
                if (data == nullptr || data->getLandSize() != 65)
                    return std::nullopt;
                return RemirosGen::landHash(data->getHeights());
            }

            std::string textureKeyAt(float x, float y) const
            {
                return RemirosGen::textureKey(mStorage->getLandTextureAt(osg::Vec3f(x, y, 0.f), mWorldspace).value());
            }

            float heightAt(float x, float y) const
            {
                return mStorage->getProceduralHeightAt(osg::Vec3f(x, y, 0.f), mWorldspace);
            }
        };

        // Remiros: rotX = asin(n.y), rotY = atan2(-n.x, n.z) dla normalnej z różnic centralnych co 128 j.
        void alignToTerrain(ESM::Position& position, const StorageTerrain& terrain)
        {
            constexpr float d = 8192.f / 64.f;
            const float x = position.pos[0];
            const float y = position.pos[1];
            const float dzdx = (terrain.heightAt(x + d, y) - terrain.heightAt(x - d, y)) / (2.f * d);
            const float dzdy = (terrain.heightAt(x, y + d) - terrain.heightAt(x, y - d)) / (2.f * d);
            osg::Vec3f normal(-dzdx, -dzdy, 1.f);
            normal.normalize();
            position.rot[0] = std::asin(std::clamp(normal.y(), -1.f, 1.f));
            position.rot[1] = std::atan2(-normal.x(), normal.z());
        }
    }

    RemirosGroundcover::RemirosGroundcover(const VFS::Manager* vfs)
    {
        mModel = std::make_unique<RemirosGen::Model>([&](std::string_view file) -> std::optional<std::string> {
            if (vfs == nullptr)
                return std::nullopt;
            VFS::Path::Normalized path("meshes/grass/" + std::string(file));
            if (!vfs->exists(path))
                return std::nullopt;
            std::string key(path.value());
            mPaths.emplace(key, std::move(path));
            return key;
        });
    }

    RemirosGroundcover::~RemirosGroundcover() = default;

    bool RemirosGroundcover::isActive() const
    {
        return mModel != nullptr && !mModel->empty();
    }

    void RemirosGroundcover::collect(
        TerrainStorage* storage, float size, const osg::Vec2f& center, float density, const Sink& sink) const
    {
        if (!isActive() || storage == nullptr || density <= 0.f)
            return;
        const osg::Vec2f minBound = center - osg::Vec2f(size / 2.f, size / 2.f);
        const osg::Vec2f maxBound = center + osg::Vec2f(size / 2.f, size / 2.f);
        const int startX = static_cast<int>(std::floor(center.x() - size / 2.f));
        const int startY = static_cast<int>(std::floor(center.y() - size / 2.f));
        StorageTerrain terrain{ storage };
        for (int cellX = startX; cellX < startX + size; ++cellX)
        {
            for (int cellY = startY; cellY < startY + size; ++cellY)
            {
                RemirosGen::collectCell(*mModel, terrain, cellX, cellY, density, minBound.x(), minBound.y(),
                    maxBound.x(), maxBound.y(),
                    [&](const std::string& model, float x, float y, float z, float scale, float rotZ) {
                        const auto it = mPaths.find(model);
                        if (it == mPaths.end())
                            return;
                        ESM::Position position;
                        position.pos[0] = x;
                        position.pos[1] = y;
                        position.pos[2] = z;
                        position.rot[0] = 0.f;
                        position.rot[1] = 0.f;
                        position.rot[2] = rotZ;
                        alignToTerrain(position, terrain);
                        sink(it->second, position, scale);
                    });
            }
        }
    }

    std::string RemirosGroundcover::describe() const
    {
        std::ostringstream out;
        out << RemirosRules::sourceInfo() << "; usable textures=" << (mModel ? mModel->ruleCount() : 0)
            << ", resolved models=" << mPaths.size()
            << ", statics without model=" << (mModel ? mModel->missingStatics() : 0);
        return out.str();
    }
}
