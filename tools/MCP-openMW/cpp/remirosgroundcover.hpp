#ifndef OPENMW_MWRENDER_REMIROSGROUNDCOVER_H
#define OPENMW_MWRENDER_REMIROSGROUNDCOVER_H

// Adapter generatora trawy Remirosa (remirosgroundcovergen.hpp) do silnika: modele z VFS (meshes/grass/<nazwa>),
// teren z TerrainStorage, pozycje ESM::Position z obrotem według normalnej terenu.
// Wzorzec: tools/MCP-openMW/cpp/remirosgroundcover.hpp.

#include <functional>
#include <memory>
#include <string>
#include <unordered_map>

#include <osg/Vec2f>

#include <components/esm/position.hpp>
#include <components/vfs/pathutil.hpp>

namespace VFS
{
    class Manager;
}

namespace MWRender
{
    class TerrainStorage;

    namespace RemirosGen
    {
        class Model;
    }

    class RemirosGroundcover
    {
    public:
        using Sink = std::function<void(VFS::Path::NormalizedView model, const ESM::Position& position, float scale)>;

        explicit RemirosGroundcover(const VFS::Manager* vfs);
        ~RemirosGroundcover();

        /// Czy w VFS jest przynajmniej jeden model z tabeli (inaczej fork używa ogólnej flory proceduralnej).
        bool isActive() const;

        /// Instancje dla chunku (size, center w jednostkach komórek — jak Groundcover::collectInstances).
        void collect(TerrainStorage* storage, float size, const osg::Vec2f& center, float density, const Sink& sink) const;

        std::string describe() const;

    private:
        std::unique_ptr<RemirosGen::Model> mModel;
        std::unordered_map<std::string, VFS::Path::Normalized> mPaths;
    };
}

#endif
