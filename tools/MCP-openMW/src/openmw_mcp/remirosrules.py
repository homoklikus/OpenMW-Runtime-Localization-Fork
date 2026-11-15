"""Reguły Remirosa — tabela „tekstura LAND → gęstość, statyki, skale, wysokość” wyliczona z pluginów groundcover,
emulacja algorytmu tekstur (do wkompilowania w fork) i generator nagłówka C++.

Ustalenia z danych (Remiros 4.1, Core OpenMW + 01b Thicker Grass; MCP etap 2c):
* każda statyka należy do jednej tekstury (≈90% referencji na swoim tekselu, reszta ≤0,3 teksela od krawędzi,
  właściwa tekstura zawsze w sąsiednim tekselu) ⇒ pozycje rozrzucone o ±0,3 teksela wokół teksela-właściciela;
* gęstość na teksel stała dla tekstury (CV między komórkami 1–30%), pozycje losowe (NN = rozkład Poissona);
* brak filtru zbocza (akceptacja ≈1 do 60°), brak omijania obiektów, brak pomijanych komórek nad wodą,
  pod wodą 8 z 836 265 referencji;
* skala równomierna w zakresie statyki; z = teren + 23 (10 statyk AL: +25); obrót wg normalnej terenu + losowy Z.
"""

from __future__ import annotations

import collections
import hashlib
import math
import re
from pathlib import Path
from typing import Optional

from .fflora import M32, TWO_PI, f32, hash32, random01
from .land import CELL, LandIndex

SPREAD = 0.3                    # rozrzut poza teksel (w tekselach) — z analizy krawędzi
UNDERWATER = -23.0              # teren ≤ −23 (z = teren + 23 ≤ 0) ⇒ brak trawy; Remiros ma rośliny do ok. −15
RETRIES = 4                     # tryb liczników: próby pozycji w tekselu częściowo pod wodą
SUB = 4                         # pach76: podsiatka teksela SUB×SUB pól (128 j.) — liczniki per pole i statyka


def texture_key(name: Optional[str]) -> str:
    """Klucz tekstury: nazwa pliku bez katalogu i rozszerzenia, małymi literami (odporny na .tga/.dds i prefiksy)."""
    if not name:
        return ""
    base = name.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return base.rsplit(".", 1)[0] if "." in base else base


def model_key(model: str) -> str:
    return model.replace("\\", "/").rsplit("/", 1)[-1].lower()


def derive(gc, land: LandIndex) -> dict:
    """Tabela reguł z GroundcoverIndex (pluginy Remirosa) i LandIndex (content=)."""
    by_static = collections.defaultdict(lambda: {"n": 0, "tex": collections.Counter(), "smin": 1e9, "smax": -1e9,
                                                 "dz": [], "plugin": None})
    for (cx, cy), lst in gc.cells.items():
        for fi, refs in lst:
            for k, r in enumerate(refs):
                if r.deleted or not gc.statics.get(r.id):
                    continue
                s = by_static[r.id]
                s["n"] += 1
                s["plugin"] = Path(gc.files[fi]).name
                s["tex"][texture_key(land.texture_at(r.x, r.y, "fork"))] += 1
                s["smin"] = min(s["smin"], r.scale)
                s["smax"] = max(s["smax"], r.scale)
                if k % 7 == 0 and len(s["dz"]) < 4000:
                    h = land.height_at(r.x, r.y)
                    if h is not None:
                        s["dz"].append(r.z - h)
    owner = {sid: s["tex"].most_common(1)[0][0] for sid, s in by_static.items()}
    # powierzchnia tekstur nad wodą (środki tekseli) w całym świecie content=
    area = collections.Counter()
    for (cx, cy), ld in land.lands.items():
        tex = ld.textures()
        if not tex:
            continue
        for ty in range(16):
            for tx in range(16):
                key = texture_key(land.texture_name(ld, tex[ty * 16 + tx]))
                if not key:
                    continue
                h = land.height_at((cx + (tx + 0.5) / 16) * CELL, (cy + (ty + 0.5) / 16) * CELL)
                if h is not None and h > UNDERWATER:
                    area[key] += 1
    textures = collections.defaultdict(lambda: {"refs": 0, "statics": []})
    for sid, s in by_static.items():
        t = textures[owner[sid]]
        t["refs"] += s["n"]
        dz = sorted(s["dz"])
        t["statics"].append({"id": sid, "model": model_key(gc.statics[sid]), "refs": s["n"],
                             "scale_min": round(s["smin"], 4), "scale_max": round(s["smax"], 4),
                             "z_offset": round(dz[len(dz) // 2], 1) if dz else 23.0, "plugin": s["plugin"],
                             "on_own_texture": round(s["tex"][owner[sid]] / s["n"], 4)})
    rules = []
    for key, t in sorted(textures.items()):
        a = area.get(key, 0)
        tot = t["refs"]
        statics = sorted(t["statics"], key=lambda x: (-x["refs"], x["id"]))
        for st in statics:
            st["share"] = round(st["refs"] / tot, 6)
        rules.append({"texture": key, "texels_above_water": a, "refs": tot,
                      "density_per_texel": round(tot / a, 4) if a else 0.0,
                      "plugins": sorted({s["plugin"] for s in statics}), "statics": statics})
    rules.sort(key=lambda r: -r["refs"])
    src = [{"file": Path(f).name, "sha256": hashlib.sha256(Path(f).read_bytes()).hexdigest()} for f in gc.files]
    return {"rules": rules, "textures": len(rules), "statics": len(by_static),
            "refs": sum(r["refs"] for r in rules), "source_plugins": src,
            "constants": {"spread_texels": SPREAD, "underwater_max_height": UNDERWATER}}


# --- odcisk terenu (identyczny z C++) -------------------------------------------------------------------

FNV_OFFSET, FNV_PRIME = 2166136261, 16777619


def heights_f32(vhgt: bytes) -> list[float]:
    """Wysokości LAND jak components/esm3/loadland.cpp (kumulacja w float32)."""
    import struct as _s
    off = _s.unpack_from("<f", vhgt, 0)[0]
    d = _s.unpack_from(f"<{65 * 65}b", vhgt, 4)
    out = [0.0] * (65 * 65)
    row = f32(off)
    for y in range(65):
        row = f32(row + d[y * 65])
        out[y * 65] = f32(row * 8.0)
        col = row
        for x in range(1, 65):
            col = f32(col + d[y * 65 + x])
            out[y * 65 + x] = f32(col * 8.0)
    return out


def _lround(x: float) -> int:
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def land_hash(heights: list[float]) -> int:
    """FNV-1a (32 bit) po int32(lround(h)) wszystkich 65×65 wierzchołków, bajty little-endian."""
    h = FNV_OFFSET
    for v in heights:
        q = _lround(v) & M32
        for k in range(4):
            h ^= (q >> (8 * k)) & 0xFF
            h = (h * FNV_PRIME) & M32
    return h


# --- mapa liczników na teksel (agregaty, bez współrzędnych roślin) -------------------------------------

def static_order(rules: dict) -> list[dict]:
    """Statyki w kolejności tablicy sStatics w C++ (reguły po kolei, w regule wg udziału) — indeks globalny."""
    return [st for r in rules["rules"] for st in r["statics"]]


def build_counts(gc, land: LandIndex, rules: dict) -> dict:
    """Liczniki Remirosa (pach76): na teksel tekstura i grupy (pole podsiatki SUB×SUB, statyka, liczba roślin).
    Wpisy: teksele z teksturą-regułą (także bez roślin = wycięcie autora) oraz teksele z roślinami.
    Zapisywane są wyłącznie liczby w polach 128×128 j. — bez współrzędnych pojedynczych roślin."""
    owners = {r["texture"] for r in rules["rules"]}
    sidx = {st["id"]: i for i, st in enumerate(static_order(rules))}
    per_texel: dict = collections.defaultdict(collections.Counter)
    for (cx, cy) in gc.cells:
        for i in gc.instances(cx, cy, 1.0):
            if i["id"] not in sidx:
                continue
            gx, gy = math.floor(i["x"] / CELL * 16 * SUB), math.floor(i["y"] / CELL * 16 * SUB)
            sub = (gy % SUB) * SUB + (gx % SUB)
            per_texel[(gx // SUB, gy // SUB)][(sub, sidx[i["id"]])] += 1
    cells_with = {(tx // 16, ty // 16) for tx, ty in per_texel}
    names: list[str] = []
    name_idx: dict[str, int] = {}
    cells = []
    for (cx, cy) in sorted(cells_with | {xy for xy in land.lands if xy in gc.cells}):
        ld = land.lands.get((cx, cy))
        if ld is None or ld.vhgt is None or ld.textures() is None:
            continue
        entries = []
        for ty in range(16):
            for tx in range(16):
                key = texture_key(land.texture_at((cx + (tx + 0.5) / 16) * CELL, (cy + (ty + 0.5) / 16) * CELL, "fork"))
                g = per_texel.get((cx * 16 + tx, cy * 16 + ty))
                if not g and key not in owners:
                    continue
                if key not in name_idx:
                    name_idx[key] = len(names)
                    names.append(key)
                groups = sorted((sub, st, min(k, 255)) for (sub, st), k in (g or {}).items())
                entries.append((ty * 16 + tx, name_idx[key], sum(k for _, _, k in groups), groups))
        cells.append({"cell": [cx, cy], "land_hash": land_hash(heights_f32(ld.vhgt)), "entries": entries})
    return {"texture_names": names, "cells": cells, "entries": sum(len(c["entries"]) for c in cells),
            "groups": sum(len(e[3]) for c in cells for e in c["entries"]),
            "refs": sum(e[2] for c in cells for e in c["entries"]), "sub": SUB}


# --- algorytm (identyczny z wersją C++) -----------------------------------------------------------------

class Model:
    """Reguły + liczniki przygotowane do generowania (modele dopasowane do puli po nazwie pliku)."""

    def __init__(self, rules: dict, counts: Optional[dict] = None, pool: Optional[list[str]] = None):
        have = None if pool is None else {model_key(m): m for m in pool}
        self.rules = {}
        for r in rules["rules"]:
            sts = [s for s in r["statics"] if have is None or s["model"] in have]
            tot = sum(s["share"] for s in sts)
            if not sts or tot <= 0:
                continue
            acc, entries = 0.0, []
            for s in sts:
                acc += s["share"] / tot
                entries.append((f32(min(acc, 1.0)), have[s["model"]] if have else s["model"], f32(s["scale_min"]),
                                f32(s["scale_max"]), f32(s["z_offset"])))
            self.rules[r["texture"]] = (f32(r["density_per_texel"]), entries)
        # pach76: statyki wg indeksu globalnego (None = modelu brak w puli)
        self.statics = [((have[st["model"]] if have else st["model"]) if have is None or st["model"] in have else None,
                         f32(st["scale_min"]), f32(st["scale_max"]), f32(st["z_offset"])) for st in static_order(rules)]
        self.counts = {}
        if counts:
            for c in counts["cells"]:
                self.counts[tuple(c["cell"])] = (c["land_hash"],
                                                 {e[0]: (counts["texture_names"][e[1]], e[3]) for e in c["entries"]})


def _texel_key(land: LandIndex, cx: int, cy: int, tx: int, ty: int) -> str:
    return texture_key(land.texture_at(f32(f32(float(cx) + f32((tx + 0.5) / 16.0)) * CELL),
                                       f32(f32(float(cy) + f32((ty + 0.5) / 16.0)) * CELL), "fork"))


def _choose(rule, pick: float):
    for e in rule[1]:
        if pick < e[0]:
            return e
    return rule[1][-1]


def generate_cell(land: LandIndex, model: Model, cx: int, cy: int, density: float = 1.0,
                  bounds: Optional[tuple[float, float, float, float]] = None, include_instances: bool = False,
                  use_counts: bool = True) -> dict:
    """Instancje dla komórki. Tryb liczników (pach76), gdy komórka ma wpis i odcisk terenu się zgadza: w tekselu
    o zapisanej teksturze dokładne liczby per pole podsiatki i statyka; w tekselu z inną teksturą — reguły.
    bounds: filtr jak isInChunkBorders (None = komórka jako chunk, bez filtru)."""
    ld = land.lands.get((cx, cy))
    out = {"cell": [cx, cy], "instances": 0, "mode": "none"}
    if ld is None or ld.textures() is None:
        out["reason"] = "brak LAND/VTEX"
        return out
    cnt = model.counts.get((cx, cy)) if use_counts else None
    hash_ok = cnt is not None and ld.vhgt is not None and land_hash(heights_f32(ld.vhgt)) == cnt[0]
    out["mode"] = "counts" if hash_ok else ("rules (inny teren)" if cnt is not None else "rules")
    dmul = f32(density)
    cxu, cyu = (cx & M32) * 0x9E3779B9 & M32, (cy & M32) * 0x85EBCA6B & M32
    by_model, rej, src = collections.Counter(), collections.Counter(), collections.Counter()
    inst = []
    filt = False
    if bounds is not None:
        mnx, mny, mxx, mxy = (f32(b / CELL) for b in bounds)
        filt = (mxx - mnx) < 1.0 or (mxy - mny) < 1.0          # jak isInChunkBorders: chunk ≥ 1 komórki bez filtru

    def count_of(d: float, seed: int) -> int:
        return int(math.floor(d)) + (1 if random01(seed ^ 0x2545F491) < f32(d - math.floor(d)) else 0)

    def place(s0: int, attempts: int, offset):
        """Pozycja (px, py, wx, wy, h, s) albo None (pod wodą / poza chunkiem). offset(s) -> (px, py)."""
        for attempt in range(attempts):
            s = s0 if attempt == 0 else hash32(s0 ^ ((attempt * 0x632BE5AB) & M32))
            px, py = offset(s)
            wx, wy = f32(px * CELL), f32(py * CELL)
            h = land.height_at(wx, wy)
            h = None if h is None else f32(h)                  # silnik: getProceduralHeightAt zwraca float
            if h is not None and h > UNDERWATER:
                break
        else:
            rej["underwater_or_no_land"] += 1
            return None
        if filt and ((mnx > math.floor(mnx) and px < mnx) or (mny > math.floor(mny) and py < mny)
                     or (mxx < math.ceil(mxx) and px >= mxx) or (mxy < math.ceil(mxy) and py >= mxy)):
            rej["chunk_bounds"] += 1
            return None
        return px, py, wx, wy, h, s

    def emit(pos, mdl, smin, smax, dz):
        _, _, wx, wy, h, s = pos
        scale = f32(smin + f32(random01(s ^ 0x63D83595) * f32(smax - smin)))
        by_model[mdl] += 1
        if include_instances:
            inst.append({"x": wx, "y": wy, "z": f32(h + dz), "model": mdl, "scale": scale,
                         "rot_z": f32(random01(s ^ 0xA511E9B3) * f32(TWO_PI))})

    for ty in range(16):
        for tx in range(16):
            t = ty * 16 + tx
            key = _texel_key(land, cx, cy, tx, ty)
            rec = cnt[1].get(t) if hash_ok else None
            tseed = hash32(cxu ^ cyu ^ ((t * 0xC2B2AE35) & M32))
            if rec is not None and rec[0] == key:
                src["counts"] += 1
                for gi, (sub, st, k) in enumerate(rec[1]):
                    mdl, smin, smax, dz = model.statics[st]
                    if mdl is None:
                        rej["no_model"] += k
                        continue
                    gseed = hash32(tseed ^ (((gi + 1) * 0x165667B1) & M32))
                    sxf, syf = float(sub % SUB), float(sub // SUB)
                    for kk in range(count_of(f32(f32(float(k)) * dmul), gseed)):
                        pos = place(hash32(gseed ^ ((0x9E3779B9 * (kk + 1)) & M32)), RETRIES,
                                    lambda s: (f32(float(cx) + f32(f32(float(tx) + f32(f32(sxf + random01(s ^ 0x68BC21EB))
                                                                                       / SUB)) / 16.0)),
                                               f32(float(cy) + f32(f32(float(ty) + f32(f32(syf + random01(s ^ 0x02E5BE93))
                                                                                       / SUB)) / 16.0))))
                        if pos is not None:
                            emit(pos, mdl, smin, smax, dz)
                continue
            own_rule = model.rules.get(key)
            if own_rule is None:
                continue
            src["rules" if rec is None else "rules (inna tekstura)"] += 1
            d = f32(own_rule[0] * dmul)
            if d <= 0.0:
                continue
            width = f32(1.0 + 2.0 * SPREAD)
            for k in range(count_of(d, tseed)):
                pos = place(hash32(tseed ^ ((0x9E3779B9 * (k + 1)) & M32)), 1,
                            lambda s: (f32(float(cx) + f32(f32(float(tx) + f32(f32(random01(s ^ 0x68BC21EB) * width)
                                                                                - f32(SPREAD))) / 16.0)),
                                       f32(float(cy) + f32(f32(float(ty) + f32(f32(random01(s ^ 0x02E5BE93) * width)
                                                                                - f32(SPREAD))) / 16.0))))
                if pos is not None:
                    _, mdl, smin, smax, dz = _choose(own_rule, random01(pos[5] ^ 0x91E10DA5))
                    emit(pos, mdl, smin, smax, dz)
    out.update({"instances": sum(by_model.values()), "rejected": dict(rej), "texel_sources": dict(src),
                "by_model": dict(by_model.most_common())})
    if include_instances:
        out["instance_list"] = inst
    return out


# --- pliki C++ dla forka -----------------------------------------------------------------------------

DATA_HEADER = """#ifndef OPENMW_MWRENDER_REMIROSGROUNDCOVERDATA_H
#define OPENMW_MWRENDER_REMIROSGROUNDCOVERDATA_H

// Tabela reguł i mapa liczników Remirosa — deklaracje. Dane: remirosgroundcoverdata.cpp (generowany przez MCP).

#include <cstdint>
#include <span>
#include <string_view>

namespace MWRender::RemirosRules
{
    struct StaticRule
    {
        double mShare;
        std::string_view mModel; // nazwa pliku modelu (szukany jako meshes/grass/<nazwa>)
        float mScaleMin;
        float mScaleMax;
        float mZOffset;
    };

    struct TextureRule
    {
        std::string_view mTexture; // nazwa pliku tekstury LAND bez rozszerzenia, małe litery
        float mDensityPerTexel;
        std::uint16_t mFirstStatic;
        std::uint16_t mStaticCount;
    };

    struct CellCounts
    {
        std::int16_t mX;
        std::int16_t mY;
        std::uint32_t mLandHash; // odcisk wysokości LAND — liczniki tylko dla zgodnego terenu
        std::uint32_t mFirstEntry;
        std::uint16_t mEntryCount;
        std::uint32_t mFirstGroup; // grupy wpisów komórki leżą kolejno od mFirstGroup (w kolejności wpisów)
    };

    // wpis  = teksel (bity 0-7) | indeks nazwy tekstury (8-15) | liczba grup teksela (16-23)
    // grupa = pole podsiatki sSubdivisions×sSubdivisions (bity 0-3, wiersz·4+kolumna) | indeks statyki w statics()
    //         (4-11) | liczba roślin (12-19). Liczby w polach 128×128 j., bez współrzędnych pojedynczych roślin.

    constexpr float sSpreadTexels = 0.3f;
    constexpr float sUnderwaterMaxHeight = -23.f;
    constexpr int sRetries = 4;
    constexpr int sSubdivisions = 4; // pach76

    std::span<const StaticRule> statics();
    std::span<const TextureRule> textures();
    std::span<const std::string_view> textureNames();
    std::span<const CellCounts> cells();
    std::span<const std::uint32_t> entries();
    std::span<const std::uint32_t> groups();
    std::string_view sourceInfo();
}

#endif
"""


def emit_cpp_files(rules: dict, counts: dict, mcp_info: dict) -> dict:
    """remirosgroundcoverdata.hpp (stały) i remirosgroundcoverdata.cpp (dane). Zawiera tylko agregaty."""
    head = ["// Wygenerowano przez MCP-openMW (openmw_remiros_export). NIE EDYTOWAĆ RĘCZNIE.",
            f"// MCP {mcp_info.get('version')} tree_sha256={mcp_info.get('tree_sha256')}",
            "// Źródło (statystyka rozmieszczenia, bez zasobów moda i bez współrzędnych pojedynczych roślin):"]
    head += [f"//   {p['file']} sha256={p['sha256']}" for p in rules["source_plugins"]]
    src = head + ["", '#include "remirosgroundcoverdata.hpp"', "", "#include <array>", "",
                  "namespace MWRender::RemirosRules", "{", "    namespace", "    {"]
    statics, textures = [], []
    for r in rules["rules"]:
        first = len(statics)
        for st in r["statics"]:
            statics.append(f'            StaticRule{{ {st["share"]:.6f}, "{st["model"]}", {st["scale_min"]:.4f}f, '
                           f'{st["scale_max"]:.4f}f, {st["z_offset"]:.1f}f }}, // {st["id"]}')
        textures.append(f'            TextureRule{{ "{r["texture"]}", {r["density_per_texel"]:.4f}f, {first}, '
                        f'{len(r["statics"])} }}, // {",".join(r["plugins"])}')
    src.append(f"        constexpr std::array<StaticRule, {len(statics)}> sStatics = {{ {{")
    src += statics + ["        } };", ""]
    src.append(f"        constexpr std::array<TextureRule, {len(textures)}> sTextures = {{ {{")
    src += textures + ["        } };", ""]
    names = counts["texture_names"]
    src.append(f"        constexpr std::array<std::string_view, {len(names)}> sTextureNames = {{ {{")
    src += [f'            "{n}",' for n in names] + ["        } };", ""]
    if counts.get("sub", SUB) != SUB or len(statics) > 256 or len(names) > 256:
        raise ValueError("format liczników pach76: podsiatka 4×4, ≤256 statyk i nazw tekstur")
    cell_lines, entries, groups = [], [], []
    for c in counts["cells"]:
        cx, cy = c["cell"]
        cell_lines.append(f"            CellCounts{{ {cx}, {cy}, {c['land_hash']}u, {len(entries)}u, "
                          f"{len(c['entries'])}, {len(groups)}u }},")
        for t, n, _, gl in c["entries"]:
            if len(gl) > 255:
                raise ValueError(f"teksel {t} komórki {c['cell']}: {len(gl)} grup > 255")
            entries.append(t | (n << 8) | (len(gl) << 16))
            groups += [sub | (st << 4) | (k << 12) for sub, st, k in gl]
    src.append(f"        constexpr std::array<CellCounts, {len(cell_lines)}> sCells = {{ {{")
    src += cell_lines + ["        } };", ""]
    src.append(f"        constexpr std::array<std::uint32_t, {len(entries)}> sEntries = {{ {{")
    for i in range(0, len(entries), 12):
        src.append("            " + ", ".join(f"{e}u" for e in entries[i:i + 12]) + ",")
    src += ["        } };", ""]
    src.append(f"        constexpr std::array<std::uint32_t, {max(len(groups), 1)}> sGroups = {{ {{")
    for i in range(0, len(groups), 12):
        src.append("            " + ", ".join(f"{e}u" for e in groups[i:i + 12]) + ",")
    if not groups:
        src.append("            0u,")
    src += ["        } };", "    }", "",
            "    std::span<const StaticRule> statics() { return sStatics; }",
            "    std::span<const TextureRule> textures() { return sTextures; }",
            "    std::span<const std::string_view> textureNames() { return sTextureNames; }",
            "    std::span<const CellCounts> cells() { return sCells; }",
            "    std::span<const std::uint32_t> entries() { return sEntries; }",
            f"    std::span<const std::uint32_t> groups() {{ return std::span<const std::uint32_t>(sGroups).first({len(groups)}); }}",
            f'    std::string_view sourceInfo() {{ return "Remiros 4.1 texture rules: {len(textures)} textures, '
            f'{len(statics)} statics, {len(cell_lines)} count cells, {len(groups)} count groups (4x4 sub-texel, '
            f'per static, pach76); MCP {mcp_info.get("version")}"; }}',
            "}", ""]
    return {"remirosgroundcoverdata.hpp": DATA_HEADER, "remirosgroundcoverdata.cpp": "\n".join(src)}


def terrain_dump(land: LandIndex, cells: list) -> str:
    """Tekstowy zrzut terenu dla testu porównawczego C++ (wysokości 65×65 jak w land.py, tekstury 16×16)."""
    out = []
    for (cx, cy) in cells:
        ld = land.lands.get((cx, cy))
        if ld is None or ld.heights() is None or ld.textures() is None:
            continue
        texs = [texture_key(land.texture_name(ld, v)) or "-" for v in ld.textures()]
        out.append(f"CELL {cx} {cy} {land_hash(heights_f32(ld.vhgt))}")
        out.append(" ".join(repr(float(h)) for h in ld.heights()))
        out.append(" ".join(texs))
    return "\n".join(out) + "\n"
