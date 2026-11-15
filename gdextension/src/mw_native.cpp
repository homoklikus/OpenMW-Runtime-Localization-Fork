#include "mw_native.h"
#include <godot_cpp/core/class_db.hpp>
#include <cstring>

using namespace godot;
namespace mwgodot {

void MWNative::_bind_methods() {
    ClassDB::bind_method(D_METHOD("decode_vhgt", "vhgt"), &MWNative::decode_vhgt);
    ClassDB::bind_method(D_METHOD("version"), &MWNative::version);
}

PackedFloat32Array MWNative::decode_vhgt(const PackedByteArray &vhgt) const {
    PackedFloat32Array out;
    if (vhgt.size() < 4 + 65 * 65)
        return out;
    out.resize(65 * 65);
    const uint8_t *p = vhgt.ptr();
    float offset;
    std::memcpy(&offset, p, 4);
    const int8_t *d = reinterpret_cast<const int8_t *>(p + 4);
    float *o = out.ptrw();
    float row = offset;
    for (int y = 0; y < 65; ++y) {
        row += d[y * 65];
        float col = row;
        o[y * 65] = col * 8.0f;
        for (int x = 1; x < 65; ++x) {
            col += d[y * 65 + x];
            o[y * 65 + x] = col * 8.0f;
        }
    }
    return out;
}
}
