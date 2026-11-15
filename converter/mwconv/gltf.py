"""Minimalny, zależny tylko od numpy zapis glTF 2.0 / GLB."""

from __future__ import annotations

import json
import struct
from typing import Any, Optional

import numpy as np

FLOAT = 5126
UINT = 5125
USHORT = 5123
UBYTE = 5121

ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963

_TYPES = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4", 16: "MAT4"}


class GltfBuilder:
    def __init__(self, generator: str = "mwconv"):
        self.doc: dict[str, Any] = {
            "asset": {"version": "2.0", "generator": generator},
            "scenes": [{"nodes": []}],
            "scene": 0,
        }
        self.bin = bytearray()

    def _list(self, key: str) -> list:
        return self.doc.setdefault(key, [])

    def _append(self, key: str, obj: dict) -> int:
        lst = self._list(key)
        lst.append(obj)
        return len(lst) - 1

    # --- dane binarne --------------------------------------------------------------------------
    def buffer_view(self, data: bytes, target: Optional[int] = None) -> int:
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin.extend(data)
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            bv["target"] = target
        return self._append("bufferViews", bv)

    def accessor(self, arr: np.ndarray, ctype: int = FLOAT, target: Optional[int] = None,
                 minmax: bool = False, normalized: bool = False) -> int:
        arr = np.ascontiguousarray(arr)
        n = arr.shape[0]
        comps = 1 if arr.ndim == 1 else int(np.prod(arr.shape[1:]))
        dt = {FLOAT: "<f4", UINT: "<u4", USHORT: "<u2", UBYTE: "u1"}[ctype]
        data = arr.astype(dt).reshape(n, comps) if comps > 1 else arr.astype(dt)
        bv = self.buffer_view(data.tobytes(), target)
        acc = {"bufferView": bv, "componentType": ctype, "count": n, "type": _TYPES[comps]}
        if normalized:
            acc["normalized"] = True
        if minmax and n:
            d2 = data.reshape(n, comps)
            if ctype == FLOAT:
                acc["min"] = [float(x) for x in d2.min(axis=0)]
                acc["max"] = [float(x) for x in d2.max(axis=0)]
            else:
                acc["min"] = [int(x) for x in d2.min(axis=0)]
                acc["max"] = [int(x) for x in d2.max(axis=0)]
        return self._append("accessors", acc)

    # --- obiekty ------------------------------------------------------------------------------
    def node(self, **kw) -> int:
        return self._append("nodes", {k: v for k, v in kw.items() if v is not None})

    def mesh(self, name: str, primitives: list[dict], extras: Optional[dict] = None) -> int:
        m = {"name": name, "primitives": primitives}
        if extras:
            m["extras"] = extras
        return self._append("meshes", m)

    def material(self, mat: dict) -> int:
        return self._append("materials", mat)

    def sampler(self, smp: dict) -> int:
        lst = self._list("samplers")
        for i, s in enumerate(lst):
            if s == smp:
                return i
        return self._append("samplers", smp)

    def image_uri(self, uri: str, name: str = "") -> int:
        for i, im in enumerate(self._list("images")):
            if im.get("uri") == uri:
                return i
        return self._append("images", {"uri": uri, "name": name or uri})

    def image_bytes(self, data: bytes, mime: str = "image/png", name: str = "") -> int:
        bv = self.buffer_view(data)
        return self._append("images", {"bufferView": bv, "mimeType": mime, "name": name})

    def texture(self, image: int, sampler: int) -> int:
        for i, t in enumerate(self._list("textures")):
            if t["source"] == image and t["sampler"] == sampler:
                return i
        return self._append("textures", {"source": image, "sampler": sampler})

    def skin(self, skin: dict) -> int:
        return self._append("skins", skin)

    def animation(self, anim: dict) -> int:
        return self._append("animations", anim)

    def add_root(self, node: int):
        self.doc["scenes"][0]["nodes"].append(node)

    # --- zapis --------------------------------------------------------------------------------
    def to_glb(self) -> bytes:
        doc = dict(self.doc)
        while len(self.bin) % 4:
            self.bin.append(0)
        if self.bin:
            doc["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + (8 + len(self.bin) if self.bin else 0)
        out = bytearray()
        out += struct.pack("<III", 0x46546C67, 2, total)
        out += struct.pack("<II", len(js), 0x4E4F534A) + js
        if self.bin:
            out += struct.pack("<II", len(self.bin), 0x004E4942) + self.bin
        return bytes(out)


def read_glb(data: bytes) -> tuple[dict, bytes]:
    """Odczyt GLB (do testów): (json, bin)."""
    magic, ver, total = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or ver != 2:
        raise ValueError("to nie jest GLB 2.0")
    pos = 12
    js, binc = None, b""
    while pos < total:
        ln, typ = struct.unpack_from("<II", data, pos)
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif typ == 0x004E4942:
            binc = bytes(chunk)
        pos += 8 + ln
    return js, binc


def accessor_array(doc: dict, binc: bytes, idx: int) -> np.ndarray:
    acc = doc["accessors"][idx]
    bv = doc["bufferViews"][acc["bufferView"]]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    dt = {FLOAT: "<f4", UINT: "<u4", USHORT: "<u2", UBYTE: "u1"}[acc["componentType"]]
    a = np.frombuffer(binc, dtype=dt, count=acc["count"] * comps, offset=bv.get("byteOffset", 0) + acc.get("byteOffset", 0))
    return a.reshape(acc["count"], comps) if comps > 1 else a
