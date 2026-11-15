// Minimalne rozszerzenie GDExtension (test łańcucha narzędzi C++): natywne dekodowanie VHGT.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace mwgodot {
class MWNative : public godot::RefCounted {
    GDCLASS(MWNative, godot::RefCounted)
protected:
    static void _bind_methods();
public:
    // VHGT (4 B offset + 65×65 int8) → 65×65 wysokości w jednostkach gry
    godot::PackedFloat32Array decode_vhgt(const godot::PackedByteArray &vhgt) const;
    godot::String version() const { return "mw_native 0.1"; }
};
}
