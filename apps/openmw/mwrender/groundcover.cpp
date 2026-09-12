#include "groundcover.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <span>

#include <osg/AlphaFunc>
#include <osg/BlendFunc>
#include <osg/ComputeBoundsVisitor>
#include <osg/Geometry>
#include <osg/Program>
#include <osg/VertexAttribDivisor>
#include <osgUtil/CullVisitor>

#include <components/esm3/esmreader.hpp>
#include <components/esm3/loadacti.hpp>
#include <components/esm3/loadcont.hpp>
#include <components/esm3/loaddoor.hpp>
#include <components/esm3/loadland.hpp>
#include <components/esm3/loadpgrd.hpp>
#include <components/esm3/loadstat.hpp>
#include <components/esm3/readerscache.hpp>
#include <components/misc/coordinateconverter.hpp>
#include <components/misc/constants.hpp>
#include <components/misc/convert.hpp>
#include <components/misc/resourcehelpers.hpp>
#include <components/sceneutil/lightmanager.hpp>
#include <components/sceneutil/nodecallback.hpp>
#include <components/settings/values.hpp>
#include <components/shader/shadermanager.hpp>
#include <components/terrain/quadtreenode.hpp>

#include "../mwbase/environment.hpp"
#include "../mwbase/world.hpp"
#include "../mwworld/esmstore.hpp"
#include "../mwworld/groundcoverstore.hpp"

#include "terrainstorage.hpp"
#include "vismask.hpp"

namespace MWRender
{
    namespace
    {
        using value_type = osgUtil::CullVisitor::value_type;

        // From OSG's CullVisitor.cpp
        inline value_type distance(const osg::Vec3& coord, const osg::Matrix& matrix)
        {
            return -((value_type)coord[0] * (value_type)matrix(0, 2) + (value_type)coord[1] * (value_type)matrix(1, 2)
                + (value_type)coord[2] * (value_type)matrix(2, 2) + matrix(3, 2));
        }

        inline osg::Matrix computeInstanceMatrix(
            const Groundcover::GroundcoverEntry& entry, const osg::Vec3& chunkPosition)
        {
            return osg::Matrix::scale(entry.mScale, entry.mScale, entry.mScale)
                * osg::Matrix(Misc::Convert::makeOsgQuat(entry.mPos))
                * osg::Matrix::translate(entry.mPos.asVec3() - chunkPosition);
        }

        class InstancedComputeNearFarCullCallback : public osg::DrawableCullCallback
        {
        public:
            explicit InstancedComputeNearFarCullCallback(std::span<const Groundcover::GroundcoverEntry> instances,
                const osg::Vec3& chunkPosition, const osg::BoundingBox& instanceBounds)
                : mInstanceMatrices()
                , mInstanceBounds(instanceBounds)
            {
                mInstanceMatrices.reserve(instances.size());
                for (const Groundcover::GroundcoverEntry& instance : instances)
                    mInstanceMatrices.emplace_back(computeInstanceMatrix(instance, chunkPosition));
            }

            bool cull(osg::NodeVisitor* nv, osg::Drawable* drawable, osg::RenderInfo* renderInfo) const override
            {
                osgUtil::CullVisitor& cullVisitor = *nv->asCullVisitor();
                osg::CullSettings::ComputeNearFarMode cnfMode = cullVisitor.getComputeNearFarMode();
                const osg::BoundingBox& boundingBox = drawable->getBoundingBox();
                osg::RefMatrix& matrix = *cullVisitor.getModelViewMatrix();

                if (cnfMode != osg::CullSettings::COMPUTE_NEAR_FAR_USING_PRIMITIVES
                    && cnfMode != osg::CullSettings::COMPUTE_NEAR_USING_PRIMITIVES)
                    return false;

                if (drawable->isCullingActive() && cullVisitor.isCulled(boundingBox))
                    return true;

                osg::Vec3 lookVector = cullVisitor.getLookVectorLocal();
                unsigned int bbCornerFar
                    = (lookVector.x() >= 0 ? 1 : 0) | (lookVector.y() >= 0 ? 2 : 0) | (lookVector.z() >= 0 ? 4 : 0);
                unsigned int bbCornerNear = (~bbCornerFar) & 7;
                value_type dNear = distance(boundingBox.corner(bbCornerNear), matrix);
                value_type dFar = distance(boundingBox.corner(bbCornerFar), matrix);

                if (dNear > dFar)
                    std::swap(dNear, dFar);

                if (dFar < 0)
                    return true;

                value_type computedZNear = cullVisitor.getCalculatedNearPlane();
                value_type computedZFar = cullVisitor.getCalculatedFarPlane();

                if (dNear < computedZNear || dFar > computedZFar)
                {
                    osg::Polytope frustum;
                    osg::Polytope::ClippingMask resultMask
                        = cullVisitor.getCurrentCullingSet().getFrustum().getResultMask();
                    if (resultMask)
                    {
                        // Other objects are likely cheaper and should let us skip all but a few groundcover instances
                        cullVisitor.computeNearPlane();
                        computedZNear = cullVisitor.getCalculatedNearPlane();
                        computedZFar = cullVisitor.getCalculatedFarPlane();

                        if (dNear < computedZNear)
                        {
                            dNear = computedZNear;
                            for (const auto& instanceMatrix : mInstanceMatrices)
                            {
                                osg::Matrix fullMatrix = instanceMatrix * matrix;
                                osg::Vec3d instanceLookVector(-fullMatrix(0, 2), -fullMatrix(1, 2), -fullMatrix(2, 2));
                                unsigned int instanceBbCornerFar = (instanceLookVector.x() >= 0 ? 1 : 0)
                                    | (instanceLookVector.y() >= 0 ? 2 : 0) | (instanceLookVector.z() >= 0 ? 4 : 0);
                                unsigned int instanceBbCornerNear = (~instanceBbCornerFar) & 7;
                                value_type instanceDNear
                                    = distance(mInstanceBounds.corner(instanceBbCornerNear), fullMatrix);
                                value_type instanceDFar
                                    = distance(mInstanceBounds.corner(instanceBbCornerFar), fullMatrix);

                                if (instanceDNear > instanceDFar)
                                    std::swap(instanceDNear, instanceDFar);

                                if (instanceDFar < 0 || instanceDNear > dNear)
                                    continue;

                                frustum.setAndTransformProvidingInverse(
                                    cullVisitor.getProjectionCullingStack().back().getFrustum(), fullMatrix);
                                osg::Polytope::PlaneList planes;
                                osg::Polytope::ClippingMask selectorMask = 0x1;
                                for (const auto& plane : frustum.getPlaneList())
                                {
                                    if (resultMask & selectorMask)
                                        planes.push_back(plane);
                                    selectorMask <<= 1;
                                }

                                value_type newNear
                                    = cullVisitor.computeNearestPointInFrustum(fullMatrix, planes, *drawable);
                                dNear = std::min(dNear, newNear);
                            }
                            if (dNear < computedZNear)
                                cullVisitor.setCalculatedNearPlane(dNear);
                        }

                        if (cnfMode == osg::CullSettings::COMPUTE_NEAR_FAR_USING_PRIMITIVES && dFar > computedZFar)
                        {
                            dFar = computedZFar;
                            for (const auto& instanceMatrix : mInstanceMatrices)
                            {
                                osg::Matrix fullMatrix = instanceMatrix * matrix;
                                osg::Vec3d instanceLookVector(-fullMatrix(0, 2), -fullMatrix(1, 2), -fullMatrix(2, 2));
                                unsigned int instanceBbCornerFar = (instanceLookVector.x() >= 0 ? 1 : 0)
                                    | (instanceLookVector.y() >= 0 ? 2 : 0) | (instanceLookVector.z() >= 0 ? 4 : 0);
                                unsigned int instanceBbCornerNear = (~instanceBbCornerFar) & 7;
                                value_type instanceDNear
                                    = distance(mInstanceBounds.corner(instanceBbCornerNear), fullMatrix);
                                value_type instanceDFar
                                    = distance(mInstanceBounds.corner(instanceBbCornerFar), fullMatrix);

                                if (instanceDNear > instanceDFar)
                                    std::swap(instanceDNear, instanceDFar);

                                if (instanceDFar < 0 || instanceDFar < dFar)
                                    continue;

                                frustum.setAndTransformProvidingInverse(
                                    cullVisitor.getProjectionCullingStack().back().getFrustum(), fullMatrix);
                                osg::Polytope::PlaneList planes;
                                osg::Polytope::ClippingMask selectorMask = 0x1;
                                for (const auto& plane : frustum.getPlaneList())
                                {
                                    if (resultMask & selectorMask)
                                        planes.push_back(plane);
                                    selectorMask <<= 1;
                                }

                                value_type newFar = cullVisitor.computeFurthestPointInFrustum(
                                    instanceMatrix * matrix, planes, *drawable);
                                dFar = std::max(dFar, newFar);
                            }
                            if (dFar > computedZFar)
                                cullVisitor.setCalculatedFarPlane(dFar);
                        }
                    }
                }

                return false;
            }

        private:
            std::vector<osg::Matrix> mInstanceMatrices;
            osg::BoundingBox mInstanceBounds;
        };

        class InstancingVisitor : public osg::NodeVisitor
        {
        public:
            explicit InstancingVisitor(
                std::span<const Groundcover::GroundcoverEntry> instances, osg::Vec3f& chunkPosition)
                : osg::NodeVisitor(TRAVERSE_ALL_CHILDREN)
                , mInstances(instances)
                , mChunkPosition(chunkPosition)
            {
            }

            void apply(osg::Group& group) override
            {
                for (unsigned int i = 0; i < group.getNumChildren();)
                {
                    if (group.getChild(i)->asDrawable() && !group.getChild(i)->asGeometry())
                        group.removeChild(i);
                    else
                        ++i;
                }
                traverse(group);
            }

            void apply(osg::Geometry& geom) override
            {
                for (unsigned int i = 0; i < geom.getNumPrimitiveSets(); ++i)
                {
                    geom.getPrimitiveSet(i)->setNumInstances(static_cast<int>(mInstances.size()));
                }

                osg::ref_ptr<osg::Vec4Array> transforms = new osg::Vec4Array(static_cast<unsigned>(mInstances.size()));
                osg::BoundingBox box;
                osg::BoundingBox originalBox = geom.getBoundingBox();
                float radius = originalBox.radius();
                for (unsigned int i = 0; i < transforms->getNumElements(); i++)
                {
                    osg::Vec3f pos(mInstances[i].mPos.asVec3());
                    osg::Vec3f relativePos = pos - mChunkPosition;
                    (*transforms)[i] = osg::Vec4f(relativePos, mInstances[i].mScale);

                    // Use an additional margin due to groundcover animation
                    float instanceRadius = radius * mInstances[i].mScale * 1.1f;
                    osg::BoundingSphere instanceBounds(relativePos, instanceRadius);
                    box.expandBy(instanceBounds);
                }

                geom.setInitialBound(box);

                osg::ref_ptr<osg::Vec3Array> rotations = new osg::Vec3Array(static_cast<unsigned>(mInstances.size()));
                for (unsigned int i = 0; i < rotations->getNumElements(); i++)
                {
                    (*rotations)[i] = mInstances[i].mPos.asRotationVec3();
                }

                // Display lists do not support instancing in OSG 3.4
                geom.setUseDisplayList(false);
                geom.setUseVertexBufferObjects(true);

                geom.setVertexAttribArray(6, transforms.get(), osg::Array::BIND_PER_VERTEX);
                geom.setVertexAttribArray(7, rotations.get(), osg::Array::BIND_PER_VERTEX);

                geom.addCullCallback(new InstancedComputeNearFarCullCallback(mInstances, mChunkPosition, originalBox));
            }

        private:
            std::span<const Groundcover::GroundcoverEntry> mInstances;
            osg::Vec3f mChunkPosition;
        };

        class DensityCalculator
        {
        public:
            DensityCalculator(float density)
                : mDensity(density)
            {
            }

            bool isInstanceEnabled()
            {
                if (mDensity >= 1.f)
                    return true;

                mCurrentGroundcover += mDensity;
                if (mCurrentGroundcover < 1.f)
                    return false;

                mCurrentGroundcover -= 1.f;

                return true;
            }
            void reset() { mCurrentGroundcover = 0.f; }

        private:
            float mCurrentGroundcover = 0.f;
            float mDensity = 0.f;
        };

        class ViewDistanceCallback : public SceneUtil::NodeCallback<ViewDistanceCallback>
        {
        public:
            ViewDistanceCallback(float dist, const osg::BoundingBox& box)
                : mViewDistance(dist)
                , mBox(box)
            {
            }
            void operator()(osg::Node* node, osg::NodeVisitor* nv)
            {
                if (Terrain::distance(mBox, nv->getEyePoint()) <= mViewDistance)
                    traverse(node, nv);
            }

        private:
            float mViewDistance;
            osg::BoundingBox mBox;
        };

        inline bool isInChunkBorders(ESM::CellRef& ref, osg::Vec2f& minBound, osg::Vec2f& maxBound)
        {
            osg::Vec2f size = maxBound - minBound;
            if (size.x() >= 1 && size.y() >= 1)
                return true;

            osg::Vec3f pos = ref.mPos.asVec3();
            osg::Vec3f cellPos = pos / ESM::Land::REAL_SIZE;
            if ((minBound.x() > std::floor(minBound.x()) && cellPos.x() < minBound.x())
                || (minBound.y() > std::floor(minBound.y()) && cellPos.y() < minBound.y())
                || (maxBound.x() < std::ceil(maxBound.x()) && cellPos.x() >= maxBound.x())
                || (maxBound.y() < std::ceil(maxBound.y()) && cellPos.y() >= maxBound.y()))
                return false;

            return true;
        }

        bool isProceduralFloraSurfaceAllowed(VFS::Path::NormalizedView texture)
        {
            if (texture.empty() || texture == "_land_default.dds")
                return false;

            // Conservative first-pass rules. Dirt, grass, moss, mud and sand remain
            // eligible; obviously hard/artificial surfaces are rejected.
            constexpr std::array<std::string_view, 6> blockedKeywords = {
                "rock",
                "stone",
                "cliff",
                "road",
                "cobble",
                "lava",
            };

            for (const std::string_view keyword : blockedKeywords)
            {
                if (texture.value().find(keyword) != std::string_view::npos)
                    return false;
            }

            return true;
        }

        struct FloraExclusion
        {
            osg::Vec2f mCenter;
            float mRadius = 0.f;
        };

        bool isFloraBlockingType(int type)
        {
            switch (type)
            {
                case ESM::REC_STAT:
                case ESM::REC_ACTI:
                case ESM::REC_DOOR:
                case ESM::REC_CONT:
                    return true;
                default:
                    return false;
            }
        }

        std::string_view getFloraBlockingModel(int type, ESM::RefId id, const MWWorld::ESMStore& store)
        {
            switch (type)
            {
                case ESM::REC_STAT:
                {
                    const ESM::Static* record = store.get<ESM::Static>().searchStatic(id);
                    return record != nullptr ? std::string_view(record->mModel) : std::string_view();
                }
                case ESM::REC_ACTI:
                {
                    const ESM::Activator* record = store.get<ESM::Activator>().searchStatic(id);
                    return record != nullptr ? std::string_view(record->mModel) : std::string_view();
                }
                case ESM::REC_DOOR:
                {
                    const ESM::Door* record = store.get<ESM::Door>().searchStatic(id);
                    return record != nullptr ? std::string_view(record->mModel) : std::string_view();
                }
                case ESM::REC_CONT:
                {
                    const ESM::Container* record = store.get<ESM::Container>().searchStatic(id);
                    return record != nullptr ? std::string_view(record->mModel) : std::string_view();
                }
                default:
                    return {};
            }
        }

        bool isNaturalStaticModel(int type, VFS::Path::NormalizedView model)
        {
            if (type != ESM::REC_STAT)
                return false;

            constexpr std::array<std::string_view, 8> naturalKeywords = {
                "flora",
                "tree",
                "plant",
                "mushroom",
                "kelp",
                "fern",
                "bush",
                "shrub",
            };

            for (const std::string_view keyword : naturalKeywords)
            {
                if (model.value().find(keyword) != std::string_view::npos)
                    return true;
            }

            return false;
        }

        std::vector<FloraExclusion> collectFloraExclusions(
            float size, const osg::Vec2f& center, Resource::SceneManager* sceneManager, float exclusionDistance)
        {
            std::vector<FloraExclusion> result;
            const MWBase::World* world = MWBase::Environment::get().getWorld();
            if (world == nullptr || sceneManager == nullptr)
                return result;

            const MWWorld::ESMStore& store = world->getStore();

            const osg::Vec2f minBound = center - osg::Vec2f(size / 2.f, size / 2.f);
            const osg::Vec2f maxBound = center + osg::Vec2f(size / 2.f, size / 2.f);

            // One neighbour-cell ring catches large statics crossing cell borders.
            const int minCellX = static_cast<int>(std::floor(minBound.x())) - 1;
            const int minCellY = static_cast<int>(std::floor(minBound.y())) - 1;
            const int maxCellX = static_cast<int>(std::ceil(maxBound.x())) + 1;
            const int maxCellY = static_cast<int>(std::ceil(maxBound.y())) + 1;

            std::map<ESM::RefNum, ESM::CellRef> refs;
            ESM::ReadersCache readers;

            for (int cellX = minCellX; cellX < maxCellX; ++cellX)
            {
                for (int cellY = minCellY; cellY < maxCellY; ++cellY)
                {
                    const ESM::Cell* cell = store.get<ESM::Cell>().searchStatic(cellX, cellY);
                    if (cell == nullptr)
                        continue;

                    for (std::size_t i = 0; i < cell->mContextList.size(); ++i)
                    {
                        try
                        {
                            const std::size_t index = static_cast<std::size_t>(cell->mContextList[i].index);
                            const ESM::ReadersCache::BusyItem reader = readers.get(index);
                            cell->restore(*reader, i);

                            ESM::CellRef ref;
                            ESM::MovedCellRef movedRef;
                            bool deleted = false;
                            bool moved = false;

                            while (ESM::Cell::getNextRef(
                                *reader, ref, deleted, movedRef, moved, ESM::Cell::GetNextRefMode::LoadOnlyNotMoved))
                            {
                                if (moved)
                                    continue;

                                if (std::find(cell->mMovedRefs.begin(), cell->mMovedRefs.end(), ref.mRefNum)
                                    != cell->mMovedRefs.end())
                                    continue;

                                const int type = store.findStatic(ref.mRefID);
                                if (!isFloraBlockingType(type))
                                    continue;

                                if (deleted)
                                {
                                    refs.erase(ref.mRefNum);
                                    continue;
                                }

                                refs.insert_or_assign(ref.mRefNum, ref);
                            }
                        }
                        catch (const std::exception& e)
                        {
                            Log(Debug::Warning) << "Procedural flora: failed to collect exclusion refs from cell "
                                                << cell->getDescription() << ": " << e.what();
                        }
                    }

                    for (const auto& [ref, deleted] : cell->mLeasedRefs)
                    {
                        if (deleted)
                        {
                            refs.erase(ref.mRefNum);
                            continue;
                        }

                        const int type = store.findStatic(ref.mRefID);
                        if (!isFloraBlockingType(type))
                            continue;

                        refs.insert_or_assign(ref.mRefNum, ref);
                    }
                }
            }

            std::map<VFS::Path::Normalized, float, std::less<>> footprintCache;

            for (const auto& [refNum, ref] : refs)
            {
                if (Misc::ResourceHelpers::isHiddenMarker(ref.mRefID))
                    continue;

                const int type = store.findStatic(ref.mRefID);
                const std::string_view rawModel = getFloraBlockingModel(type, ref.mRefID, store);
                if (rawModel.empty())
                    continue;

                const VFS::Path::Normalized model
                    = Misc::ResourceHelpers::correctMeshPath(VFS::Path::Normalized(rawModel));

                // Trees and plants should coexist with generated grass.
                if (isNaturalStaticModel(type, model))
                    continue;

                float footprintRadius = 0.f;
                const auto cached = footprintCache.find(model);
                if (cached != footprintCache.end())
                {
                    footprintRadius = cached->second;
                }
                else
                {
                    try
                    {
                        const osg::ref_ptr<const osg::Node> node = sceneManager->getTemplate(model, false);
                        osg::ComputeBoundsVisitor boundsVisitor;
                        const_cast<osg::Node*>(node.get())->accept(boundsVisitor);
                        const osg::BoundingBox bounds = boundsVisitor.getBoundingBox();

                        if (bounds.valid())
                        {
                            const float xExtent = std::max(std::abs(bounds.xMin()), std::abs(bounds.xMax()));
                            const float yExtent = std::max(std::abs(bounds.yMin()), std::abs(bounds.yMax()));
                            footprintRadius = std::hypot(xExtent, yExtent);
                        }
                    }
                    catch (const std::exception& e)
                    {
                        Log(Debug::Warning) << "Procedural flora: unable to inspect exclusion model "
                                            << model << ": " << e.what();
                    }

                    footprintCache.emplace(model, footprintRadius);
                }

                const float scale = std::abs(ref.mScale);
                const float radius = footprintRadius * scale + exclusionDistance;
                if (radius <= 0.f)
                    continue;

                result.push_back(FloraExclusion{
                    .mCenter = osg::Vec2f(ref.mPos.pos[0], ref.mPos.pos[1]),
                    .mRadius = radius,
                });
            }

            return result;
        }

        bool isInsideFloraExclusion(const osg::Vec3f& worldPos, std::span<const FloraExclusion> exclusions)
        {
            const osg::Vec2f point(worldPos.x(), worldPos.y());

            for (const FloraExclusion& exclusion : exclusions)
            {
                const osg::Vec2f delta = point - exclusion.mCenter;
                if (delta.length2() <= exclusion.mRadius * exclusion.mRadius)
                    return true;
            }

            return false;
        }

        struct FloraPathSegment
        {
            osg::Vec2f mStart;
            osg::Vec2f mEnd;
        };

        std::vector<FloraPathSegment> collectPathgridExclusions(float size, const osg::Vec2f& center)
        {
            std::vector<FloraPathSegment> result;

            const MWBase::World* world = MWBase::Environment::get().getWorld();
            if (world == nullptr)
                return result;

            const MWWorld::ESMStore& store = world->getStore();

            const osg::Vec2f minBound = center - osg::Vec2f(size / 2.f, size / 2.f);
            const osg::Vec2f maxBound = center + osg::Vec2f(size / 2.f, size / 2.f);

            const int minCellX = static_cast<int>(std::floor(minBound.x())) - 1;
            const int minCellY = static_cast<int>(std::floor(minBound.y())) - 1;
            const int maxCellX = static_cast<int>(std::ceil(maxBound.x())) + 1;
            const int maxCellY = static_cast<int>(std::ceil(maxBound.y())) + 1;

            for (int cellX = minCellX; cellX < maxCellX; ++cellX)
            {
                for (int cellY = minCellY; cellY < maxCellY; ++cellY)
                {
                    const ESM::Cell* cell = store.get<ESM::Cell>().searchStatic(cellX, cellY);
                    if (cell == nullptr)
                        continue;

                    const ESM::Pathgrid* pathgrid = store.get<ESM::Pathgrid>().search(*cell);
                    if (pathgrid == nullptr || pathgrid->mPoints.empty())
                        continue;

                    const Misc::CoordinateConverter converter = Misc::makeCoordinateConverter(*cell);

                    for (const ESM::Pathgrid::Edge& edge : pathgrid->mEdges)
                    {
                        if (edge.mV0 >= pathgrid->mPoints.size() || edge.mV1 >= pathgrid->mPoints.size())
                            continue;

                        const ESM::Pathgrid::Point a = converter.toWorldPoint(pathgrid->mPoints[edge.mV0]);
                        const ESM::Pathgrid::Point b = converter.toWorldPoint(pathgrid->mPoints[edge.mV1]);

                        result.push_back(FloraPathSegment{
                            .mStart = osg::Vec2f(static_cast<float>(a.mX), static_cast<float>(a.mY)),
                            .mEnd = osg::Vec2f(static_cast<float>(b.mX), static_cast<float>(b.mY)),
                        });
                    }

                    if (pathgrid->mEdges.empty())
                    {
                        for (const ESM::Pathgrid::Point& point : pathgrid->mPoints)
                        {
                            const ESM::Pathgrid::Point worldPoint = converter.toWorldPoint(point);
                            const osg::Vec2f p(
                                static_cast<float>(worldPoint.mX), static_cast<float>(worldPoint.mY));
                            result.push_back(FloraPathSegment{ .mStart = p, .mEnd = p });
                        }
                    }
                }
            }

            return result;
        }

        float pointSegmentDistanceSquared(
            const osg::Vec2f& point, const osg::Vec2f& start, const osg::Vec2f& end)
        {
            const osg::Vec2f segment = end - start;
            const float lengthSquared = segment.length2();

            if (lengthSquared <= 0.0001f)
                return (point - start).length2();

            const float t = std::clamp(((point - start) * segment) / lengthSquared, 0.f, 1.f);
            const osg::Vec2f closest = start + segment * t;
            return (point - closest).length2();
        }

        bool isInsidePathgridExclusion(
            const osg::Vec3f& worldPos, std::span<const FloraPathSegment> segments, float pathClearance)
        {
            const float pathClearanceSquared = pathClearance * pathClearance;
            const osg::Vec2f point(worldPos.x(), worldPos.y());

            for (const FloraPathSegment& segment : segments)
            {
                if (pointSegmentDistanceSquared(point, segment.mStart, segment.mEnd) <= pathClearanceSquared)
                    return true;
            }

            return false;
        }

    }

    osg::ref_ptr<osg::Node> Groundcover::getChunk(float size, const osg::Vec2f& center, unsigned char lod,
        unsigned int lodFlags, bool activeGrid, const osg::Vec3f& viewPoint, bool compile)
    {
        if (lod > getMaxLodLevel())
            return nullptr;
        GroundcoverChunkId id = std::make_tuple(center, size);
        osg::ref_ptr<osg::Object> obj = mCache->getRefFromObjectCache(id);
        if (obj)
            return static_cast<osg::Node*>(obj.get());
        else
        {
            InstanceMap instances;
            collectInstances(instances, size, center);
            osg::ref_ptr<osg::Node> node = createChunk(instances, center);
            mCache->addEntryToObjectCache(id, node.get());
            return node;
        }
    }

    Groundcover::Groundcover(Resource::SceneManager* sceneManager, float density, float viewDistance,
        const MWWorld::GroundcoverStore& store, TerrainStorage* terrainStorage, bool includePluginGroundcover,
        bool proceduralEnabled, float proceduralDensity, float exclusionDistanceMeters)
        : GenericResourceManager<GroundcoverChunkId>(nullptr, Settings::cells().mCacheExpiryDelay)
        , mSceneManager(sceneManager)
        , mDensity(density)
        , mStateset(new osg::StateSet)
        , mGroundcoverStore(store)
        , mTerrainStorage(terrainStorage)
        , mIncludePluginGroundcover(includePluginGroundcover)
        , mProceduralEnabled(proceduralEnabled)
        , mProceduralDensity(std::clamp(proceduralDensity, 0.f, 2.f))
        , mExclusionDistance(std::clamp(exclusionDistanceMeters, 0.f, 20.f) * Constants::UnitsPerMeter)
        , mProceduralModel(store.getAnyGroundcoverModel())
    {
        setViewDistance(viewDistance);
        // MGE uses default alpha settings for groundcover, so we can not rely on alpha properties
        // Force a unified alpha handling instead of data from meshes
        osg::ref_ptr<osg::AlphaFunc> alpha = new osg::AlphaFunc(osg::AlphaFunc::GEQUAL, 128.f / 255.f);
        mStateset->setAttributeAndModes(alpha.get(), osg::StateAttribute::ON | osg::StateAttribute::OVERRIDE);
        mStateset->setAttributeAndModes(new osg::BlendFunc, osg::StateAttribute::OFF | osg::StateAttribute::OVERRIDE);
        mStateset->setRenderBinDetails(0, "RenderBin", osg::StateSet::OVERRIDE_RENDERBIN_DETAILS);
        mStateset->setAttribute(new osg::VertexAttribDivisor(6, 1));
        mStateset->setAttribute(new osg::VertexAttribDivisor(7, 1));

        mProgramTemplate = mSceneManager->getShaderManager().getProgramTemplate()
            ? Shader::ShaderManager::cloneProgram(mSceneManager->getShaderManager().getProgramTemplate())
            : osg::ref_ptr<osg::Program>(new osg::Program);
        mProgramTemplate->addBindAttribLocation("aOffset", 6);
        mProgramTemplate->addBindAttribLocation("aRotation", 7);

        if (mProceduralEnabled)
        {
            if (mProceduralModel.empty())
            {
                Log(Debug::Warning) << "Procedural flora PoC: no groundcover mesh is available; "
                                       "automatic placement is disabled for this run.";
            }
            else
            {
                Log(Debug::Info) << "Procedural flora PoC: model=" << mProceduralModel
                                 << ", density=" << mProceduralDensity
                                 << ", maxSlope=28deg, LAND texture filtering=on, object exclusions=on"
                                 << ", pathgrid exclusions=on, exclusionDistance="
                                 << mExclusionDistance / Constants::UnitsPerMeter << "m";
            }
        }
    }

    Groundcover::~Groundcover() = default;

    void Groundcover::collectInstances(InstanceMap& instances, float size, const osg::Vec2f& center)
    {
        osg::Vec2f minBound = (center - osg::Vec2f(size / 2.f, size / 2.f));
        osg::Vec2f maxBound = (center + osg::Vec2f(size / 2.f, size / 2.f));
        osg::Vec2i startCell = osg::Vec2i(static_cast<int>(std::floor(center.x() - size / 2.f)),
            static_cast<int>(std::floor(center.y() - size / 2.f)));

        if (mIncludePluginGroundcover && mDensity > 0.f)
        {
            DensityCalculator calculator(mDensity);
            ESM::ReadersCache readers;

            for (int cellX = startCell.x(); cellX < startCell.x() + size; ++cellX)
            {
                for (int cellY = startCell.y(); cellY < startCell.y() + size; ++cellY)
                {
                    ESM::Cell cell;
                    mGroundcoverStore.initCell(cell, cellX, cellY);
                    if (cell.mContextList.empty())
                        continue;

                    calculator.reset();
                    std::map<ESM::RefNum, ESM::CellRef> refs;
                    for (size_t i = 0; i < cell.mContextList.size(); ++i)
                    {
                        const std::size_t index = static_cast<std::size_t>(cell.mContextList[i].index);
                        const ESM::ReadersCache::BusyItem reader = readers.get(index);
                        cell.restore(*reader, i);
                        ESM::CellRef ref;
                        bool deleted = false;
                        while (cell.getNextRef(*reader, ref, deleted))
                        {
                            if (!deleted && refs.find(ref.mRefNum) == refs.end() && !calculator.isInstanceEnabled())
                                deleted = true;
                            if (!deleted && !isInChunkBorders(ref, minBound, maxBound))
                                deleted = true;

                            if (deleted)
                            {
                                refs.erase(ref.mRefNum);
                                continue;
                            }
                            refs[ref.mRefNum] = std::move(ref);
                        }
                    }

                    for (auto& [refNum, cellRef] : refs)
                    {
                        const VFS::Path::NormalizedView model = mGroundcoverStore.getGroundcoverModel(cellRef.mRefID);
                        if (model.empty())
                            continue;
                        auto it = instances.find(model);
                        if (it == instances.end())
                            it = instances.emplace_hint(
                                it, VFS::Path::Normalized(model), std::vector<GroundcoverEntry>());
                        it->second.emplace_back(std::move(cellRef));
                    }
                }
            }
        }

        if (!mProceduralEnabled || mProceduralDensity <= 0.f || mProceduralModel.empty() || mTerrainStorage == nullptr)
            return;

        auto hash32 = [](std::uint32_t value) {
            value ^= value >> 16;
            value *= 0x7feb352du;
            value ^= value >> 15;
            value *= 0x846ca68bu;
            value ^= value >> 16;
            return value;
        };

        auto random01 = [&](std::uint32_t seed) {
            return static_cast<float>(hash32(seed) & 0x00ffffffu) / static_cast<float>(0x01000000u);
        };

        const std::vector<FloraExclusion> floraExclusions
            = collectFloraExclusions(size, center, mSceneManager, mExclusionDistance);
        const std::vector<FloraPathSegment> pathgridExclusions
            = collectPathgridExclusions(size, center);

        auto addProceduralInstance = [&](const ESM::Position& position, float scale) {
            auto proceduralIt = instances.find(mProceduralModel);
            if (proceduralIt == instances.end())
                proceduralIt = instances.emplace_hint(
                    proceduralIt, mProceduralModel, std::vector<GroundcoverEntry>());
            proceduralIt->second.emplace_back(position, scale);
        };

        const int candidatesPerCell
            = std::max(1, static_cast<int>(std::lround(24.f * mProceduralDensity)));
        constexpr float margin = 0.06f;
        constexpr float twoPi = 6.2831853071795864769f;


        for (int cellX = startCell.x(); cellX < startCell.x() + size; ++cellX)
        {
            for (int cellY = startCell.y(); cellY < startCell.y() + size; ++cellY)
            {
                for (int index = 0; index < candidatesPerCell; ++index)
                {
                    const std::uint32_t base
                        = static_cast<std::uint32_t>(cellX) * 0x9e3779b9u
                        ^ static_cast<std::uint32_t>(cellY) * 0x85ebca6bu
                        ^ static_cast<std::uint32_t>(index) * 0xc2b2ae35u;

                    const float fx = margin + (1.f - 2.f * margin) * random01(base ^ 0x68bc21ebu);
                    const float fy = margin + (1.f - 2.f * margin) * random01(base ^ 0x02e5be93u);

                    const float cellPosX = static_cast<float>(cellX) + fx;
                    const float cellPosY = static_cast<float>(cellY) + fy;
                    if (cellPosX < minBound.x() || cellPosX >= maxBound.x()
                        || cellPosY < minBound.y() || cellPosY >= maxBound.y())
                        continue;

                    ESM::Position position;
                    position.pos[0] = cellPosX * ESM::Land::REAL_SIZE;
                    position.pos[1] = cellPosY * ESM::Land::REAL_SIZE;
                    const osg::Vec3f samplePos(position.pos[0], position.pos[1], 0.f);
                    position.pos[2] = mTerrainStorage->getHeightAt(
                        samplePos, ESM::Cell::sDefaultWorldspaceId);

                    if (position.pos[2] <= 1.f)
                        continue;

                    constexpr float maxSlopeDegrees = 28.f;
                    const float slope = mTerrainStorage->getSlopeDegreesAt(
                        samplePos, ESM::Cell::sDefaultWorldspaceId);
                    if (slope > maxSlopeDegrees)
                        continue;

                    const VFS::Path::Normalized landTexture = mTerrainStorage->getLandTextureAt(
                        samplePos, ESM::Cell::sDefaultWorldspaceId);
                    if (!isProceduralFloraSurfaceAllowed(landTexture))
                        continue;

                    if (isInsideFloraExclusion(samplePos, floraExclusions))
                        continue;

                    if (isInsidePathgridExclusion(samplePos, pathgridExclusions, mExclusionDistance))
                        continue;

                    position.rot[0] = 0.f;
                    position.rot[1] = 0.f;
                    position.rot[2] = random01(base ^ 0xa511e9b3u) * twoPi;

                    const float scale = 0.85f + random01(base ^ 0x63d83595u) * 0.3f;
                    addProceduralInstance(position, scale);
                }
            }
        }
    }

    osg::ref_ptr<osg::Node> Groundcover::createChunk(InstanceMap& instances, const osg::Vec2f& center)
    {
        osg::ref_ptr<osg::Group> group = new osg::Group;
        osg::Vec3f worldCenter = osg::Vec3f(center.x(), center.y(), 0) * ESM::Land::REAL_SIZE;
        for (const auto& [model, entries] : instances)
        {
            const osg::Node* temp = mSceneManager->getTemplate(model);
            osg::ref_ptr<osg::Node> node = static_cast<osg::Node*>(temp->clone(osg::CopyOp::DEEP_COPY_NODES
                | osg::CopyOp::DEEP_COPY_DRAWABLES | osg::CopyOp::DEEP_COPY_USERDATA | osg::CopyOp::DEEP_COPY_ARRAYS
                | osg::CopyOp::DEEP_COPY_PRIMITIVES));

            // Keep link to original mesh to keep it in cache
            group->getOrCreateUserDataContainer()->addUserObject(new Resource::TemplateRef(temp));

            InstancingVisitor visitor(entries, worldCenter);
            node->accept(visitor);
            group->addChild(node);
        }

        osg::ComputeBoundsVisitor cbv;
        group->accept(cbv);
        osg::BoundingBox box = cbv.getBoundingBox();
        group->addCullCallback(new ViewDistanceCallback(getViewDistance(), box));

        group->setStateSet(mStateset);
        group->setNodeMask(Mask_Groundcover);
        if (Settings::groundcover().mPointLighting)
            group->addCullCallback(new SceneUtil::LightListCallback);
        mSceneManager->recreateShaders(group, "groundcover", mProgramTemplate);
        mSceneManager->shareState(group);
        group->getBound();
        return group;
    }

    unsigned int Groundcover::getNodeMask()
    {
        return Mask_Groundcover;
    }

    void Groundcover::reportStats(unsigned int frameNumber, osg::Stats* stats) const
    {
        Resource::reportStats("Groundcover Chunk", frameNumber, mCache->getStats(), *stats);
    }
}
