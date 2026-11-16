"""Transformacja korzenia NIF jest stosowana jak w OpenMW (nifloader.cpp: MatrixTransform(mTransform)),
także gdy korzeniem jest kształt – np. części ciała z modów (NiTriShape jako korzeń, obrót 90°).
Wpisy pamięci podręcznej nif2gltf-0.1.0 (zerowało korzeń) są zgodne tylko dla korzenia jednostkowego."""
import json
import struct

import numpy as np

from mwconv.nif.reader import parse
from mwconv.nif.writer import NifBuilder
from mwconv.nif2gltf import NifToGltf, root_is_identity
from mwconv.synthetic import box

ROT_Y90 = [[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0]]   # oś X modelu → oś −Z (pion w MW)


def _leg(rotated: bool) -> bytes:
    nb = NifBuilder()
    V, N, UV, T = box((40, 10, 10), (20, 0, 0))                    # wydłużone wzdłuż X
    sd = nb.add("NiTriShapeData", vertices=V, normals=N, uvs=[UV], triangles=T)
    kw = {"rotation": ROT_Y90} if rotated else {}
    nb.roots = [nb.add("NiTriShape", name="Leg", data=sd, **kw)]
    return nb.to_bytes()


def _extent(glb: bytes) -> np.ndarray:
    """Rozmiar siatki po transformacjach węzłów (glTF: Y w górę)."""
    n = struct.unpack("<I", glb[12:16])[0]
    j = json.loads(glb[20:20 + n])
    a = j["accessors"][j["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    lo, hi = np.array(a["min"]), np.array(a["max"])
    node = next(nd for nd in j["nodes"] if "mesh" in nd)
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        corners = np.array([[a_, b_, c_] for a_ in (lo[0], hi[0]) for b_ in (lo[1], hi[1]) for c_ in (lo[2], hi[2])])
        p = corners @ R.T
        return p.max(0) - p.min(0)
    return hi - lo


def _convert(data: bytes) -> bytes:
    conv = NifToGltf(parse(data, "leg.nif"), "leg.nif")
    out = conv.convert()
    return out[0] if isinstance(out, tuple) else out


def test_root_shape_rotation_applied():
    e = _extent(_convert(_leg(True)))
    assert e[1] > 0.5 and e[0] < 0.2, f"noga pionowo (oś Y w Godocie): {e}"
    e0 = _extent(_convert(_leg(False)))
    assert e0[0] > 0.5 and e0[1] < 0.2


def test_compat_only_for_identity_root():
    assert root_is_identity(parse(_leg(False), "a.nif"))
    assert not root_is_identity(parse(_leg(True), "b.nif"))
