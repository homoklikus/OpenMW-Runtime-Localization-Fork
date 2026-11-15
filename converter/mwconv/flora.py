"""Roślinność – przeniesione z forka OpenMW RLF (GPL-3.0-or-later, jak OpenMWGodot).

Źródła (fork `0.5-world`, 3bfa4c3):
  apps/openmw/mwrender/groundcover.cpp       groundcover z wtyczek (DensityCalculator) + wywołanie reguł Remirosa
  apps/openmw/mwrender/remirosgroundcover*   trawa Remirosa generowana w grze BEZ jego ESP: tabela reguł tekstur LAND
                                             i liczników na pola 128 j. (pach75/pach76) wkompilowana w program,
                                             z moda potrzebne tylko modele i tekstury (meshes/grass/)
  apps/openmw/mwrender/terrainstorage.cpp    wysokość „diamond”, tekstura LAND w punkcie
  apps/openmw/mwrender/renderingmanager.cpp  mapowanie ustawień: source = automatic | groundcover | hybrid
  components/worldconfig                     [flora] enabled, source, density, exclusion_distance
Tabela: converter/mwconv/data/remiros_rules.json.gz = remirosgroundcoverdata.cpp forka (wygenerowana przez
MCP-openMW z Rem_*.esp; same agregaty, bez współrzędnych roślin). Kod generatora: remirosgroundcovergen.hpp.

Różnica architektury: OpenMW liczy rośliny w trakcie gry (chunki terenu). Tu konwerter liczy je raz, dla każdej
komórki zewnętrznej, i zapisuje world/flora/<x>_<y>.bin; gra tylko je rysuje (MultiMesh, bez kolizji).
Arytmetyka w float64 (fork: float32) – pojedyncze instancje na granicach progów mogą się różnić.

Format world/flora/<x>_<y>.bin (zlib): "MWFL" u16 wersja, u32 N, następnie kolumny po N:
  u16 model (indeks w index.json „models”), f32 x, f32 y, f32 z (jednostki MW, świat),
  i16 rx, i16 ry, i16 rz (radiany × 10000), u16 skala × 10000, u8 ranga (0–255, do zmniejszania gęstości w grze),
  u8 źródło (0 = wtyczka groundcover, 2 = Remiros).
"""
from __future__ import annotations

import collections
import hashlib
import json
import math
import os
import struct
import time
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np

CELL = 8192.0
LAND_SIZE = 65
TEX_SIZE = 16
UPM = 69.99125109
M32 = 0xFFFFFFFF
TWO_PI = 6.2831853071795864769
FORMAT_VERSION = 1

SOURCES = ("automatic", "groundcover", "hybrid")

# --- hash i losowanie (identyczne z forkiem) ------------------------------------------------------------


def hash32(v: int) -> int:
    v &= M32
    v ^= v >> 16
    v = (v * 0x7FEB352D) & M32
    v ^= v >> 15
    v = (v * 0x846CA68B) & M32
    v ^= v >> 16
    return v


def random01(seed: int) -> float:
    return (hash32(seed) & 0x00FFFFFF) / 16777216.0


def hash32_np(v) -> np.ndarray:
    v = np.asarray(v, dtype=np.uint32).copy()
    with np.errstate(over="ignore"):
        v ^= v >> np.uint32(16)
        v *= np.uint32(0x7FEB352D)
        v ^= v >> np.uint32(15)
        v *= np.uint32(0x846CA68B)
        v ^= v >> np.uint32(16)
    return v


def random01_np(seed) -> np.ndarray:
    return (hash32_np(seed) & np.uint32(0x00FFFFFF)).astype(np.float64) / 16777216.0


def _u32(x: int) -> np.uint32:
    return np.uint32(x & M32)


# --- teren (terrainstorage.cpp forka) --------------------------------------------------------------------

def texture_key(name: Optional[str]) -> str:
    """Nazwa pliku tekstury bez katalogu i rozszerzenia, małymi literami (jak RemirosGen::textureKey)."""
    if not name:
        return ""
    base = name.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return base.rsplit(".", 1)[0] if "." in base else base


class Terrain:
    """Wysokość, nachylenie i tekstura LAND w punkcie świata (jednostki MW)."""

    def __init__(self, lands: dict):
        self.lands = lands          # (x, y) → (Land, ltex_map, source)
        self._keys: dict = {}

    def has_textures(self, cx: int, cy: int) -> bool:
        e = self.lands.get((cx, cy))
        return e is not None and e[0].textures is not None

    def texel_keys(self, cx: int, cy: int) -> Optional[list]:
        """16×16 kluczy tekstur komórki ([ty][tx], ty od południa)."""
        k = (cx, cy)
        if k not in self._keys:
            e = self.lands.get(k)
            if e is None or e[0].textures is None:
                self._keys[k] = None
            else:
                ld, ltex = e[0], e[1] or {}
                t = ld.textures
                self._keys[k] = [[texture_key("_land_default.dds" if int(t[y, x]) == 0 else ltex.get(int(t[y, x]) - 1))
                                  for x in range(TEX_SIZE)] for y in range(TEX_SIZE)]
        return self._keys[k]

    def texture_key_at(self, wx: float, wy: float) -> str:
        cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
        keys = self.texel_keys(cx, cy)
        if keys is None:
            return ""
        lx = min(max(wx / CELL - cx, 0.0), 0.999999)
        ly = min(max(wy / CELL - cy, 0.0), 0.999999)
        return keys[min(int(ly * TEX_SIZE), 15)][min(int(lx * TEX_SIZE), 15)]

    def heights(self, cx: int, cy: int) -> Optional[np.ndarray]:
        e = self.lands.get((cx, cy))
        return None if e is None else e[0].heights

    def height_np(self, wx: np.ndarray, wy: np.ndarray) -> np.ndarray:
        """getProceduralHeightAt forka: triangulacja „diamond” jak renderer. NaN = brak LAND."""
        wx = np.asarray(wx, dtype=np.float64)
        wy = np.asarray(wy, dtype=np.float64)
        out = np.full(wx.shape, np.nan)
        cxs = np.floor(wx / CELL).astype(np.int64)
        cys = np.floor(wy / CELL).astype(np.int64)
        for cx, cy in set(zip(cxs.ravel().tolist(), cys.ravel().tolist())):
            h = self.heights(cx, cy)
            if h is None:
                continue
            m = (cxs == cx) & (cys == cy)
            nx = (wx[m] - cx * CELL) / CELL
            ny = (wy[m] - cy * CELL) / CELL
            f = LAND_SIZE - 1
            sx = np.clip((nx * f).astype(np.int64), 0, LAND_SIZE - 1)
            sy = np.clip((ny * f).astype(np.int64), 0, LAND_SIZE - 1)
            ex = np.minimum(sx + 1, LAND_SIZE - 1)
            ey = np.minimum(sy + 1, LAND_SIZE - 1)
            xp = nx * f - sx
            yp = ny * f - sy
            h00 = h[sy, sx]
            h10 = h[sy, ex]
            h11 = h[ey, ex]
            h01 = h[ey, sx]
            odd = ((sx + sy) & 1) == 1
            # parzysty kwadrat: przekątna v0–v2; nieparzysty: v1–v3 (jak _plane_z w MCP)
            even_upper = yp > xp
            v_even = np.where(even_upper, h00 + xp * (h11 - h01) + yp * (h01 - h00),
                              h00 + xp * (h10 - h00) + yp * (h11 - h10))
            odd_lower = (1.0 - yp) > xp     # nieparzysty: przekątna v1–v3
            v_odd = np.where(odd_lower, h00 + xp * (h10 - h00) + yp * (h01 - h00),
                             h11 + (1.0 - xp) * (h01 - h11) + (1.0 - yp) * (h10 - h11))
            v = np.where(odd, v_odd, v_even)
            edge = (sx == ex) | (sy == ey)
            out[m] = np.where(edge, h00, v)
        return out

    def height_at(self, wx: float, wy: float) -> Optional[float]:
        v = float(self.height_np(np.array([wx]), np.array([wy]))[0])
        return None if math.isnan(v) else v

    def slope_np(self, wx: np.ndarray, wy: np.ndarray) -> np.ndarray:
        d = CELL / (LAND_SIZE - 1)
        left = self.height_np(wx - d, wy)
        right = self.height_np(wx + d, wy)
        down = self.height_np(wx, wy - d)
        up = self.height_np(wx, wy + d)
        g = np.hypot((right - left) / (2 * d), (up - down) / (2 * d))
        return np.degrees(np.arctan(g))

    def land_hash(self, cx: int, cy: int) -> Optional[int]:
        """FNV-1a po int32(lround(h)) 65×65 wierzchołków (jak RemirosGen::landHash)."""
        h = self.heights(cx, cy)
        if h is None:
            return None
        q = np.where(h >= 0, np.floor(h + 0.5), -np.floor(-h + 0.5)).astype(np.int64).astype(np.uint32)
        b = q.astype("<u4").tobytes()
        v = 2166136261
        for byte in b:
            v ^= byte
            v = (v * 16777619) & M32
        return v


# --- wtyczki groundcover (GroundcoverStore + DensityCalculator) ----------------------------------------

@dataclass
class GcRef:
    file: int
    refnum: int
    id: str
    pos: tuple
    rot: tuple
    scale: float
    deleted: bool


@dataclass
class GroundcoverIndex:
    files: list = field(default_factory=list)
    statics: dict = field(default_factory=dict)        # id → model (ścieżka z ESP)
    cells: dict = field(default_factory=dict)          # (x, y) → [(file_idx, [GcRef])]

    @classmethod
    def load(cls, paths: list) -> "GroundcoverIndex":
        from .esm.reader import open_esm_stream, parse_cell
        g = cls()
        for fi, path in enumerate(paths):
            g.files.append(str(path))
            _f, records = open_esm_stream(path)
            for rec in records:
                if rec.type == "STAT":
                    sid = rec.zstr("NAME")
                    if sid:
                        g.statics[sid.lower()] = rec.zstr("MODL") or ""
                elif rec.type == "CELL":
                    c = parse_cell(rec)
                    if c.interior:
                        continue
                    refs = [GcRef(fi, r.refnum if isinstance(r.refnum, int) else hash(r.refnum), r.base.lower(),
                                  tuple(r.pos), tuple(r.rot), float(r.scale), bool(r.deleted)) for r in c.refs]
                    g.cells.setdefault(tuple(c.grid), []).append((fi, refs))
        return g

    def instances(self, cx: int, cy: int, density: float = 1.0) -> list:
        """Jak Groundcover::collectInstances (część wtyczek): DensityCalculator, usuwanie, kolejność RefNum."""
        dens = float(np.float32(density))
        cur = 0.0
        refs: dict = {}
        for fi, lst in self.cells.get((cx, cy), []):
            for r in lst:
                key = (r.refnum, fi)
                deleted = r.deleted
                if not deleted and key not in refs:
                    if dens < 1.0:
                        cur = float(np.float32(cur + dens))
                        if cur < 1.0:
                            deleted = True
                        else:
                            cur = float(np.float32(cur - 1.0))
                if deleted:
                    refs.pop(key, None)
                    continue
                refs[key] = r
        out = []
        for key in sorted(refs):
            r = refs[key]
            model = self.statics.get(r.id, "")
            if model:
                out.append((model, r))
        return out


def is_groundcover_plugin(path) -> bool:
    """Wtyczka roślinności: tylko TES3, STAT i CELL, a statyki to głównie trawa (meshes …grass…).
    Heurystyka dla modów instalowanych w launcherze (np. Remiros' Groundcover: Rem_*.esp)."""
    from .esm.reader import open_esm_stream
    try:
        _f, records = open_esm_stream(path)
        n_stat = n_grass = n_cell = 0
        for rec in records:
            if rec.type == "STAT":
                n_stat += 1
                m = (rec.zstr("MODL") or "").lower()
                if "grass" in m or "groundcover" in m or Path(m.replace("\\", "/")).name.startswith(("rem_", "grs_")):
                    n_grass += 1
            elif rec.type == "CELL":
                n_cell += 1
            elif rec.type not in ("TES3",):
                return False
        return n_stat > 0 and n_cell > 0 and n_grass >= 0.8 * n_stat
    except Exception:  # noqa: BLE001
        return False


@dataclass
class Settings:
    """world.cfg forka ([flora]) + „legacy” [Groundcover] OpenMW."""
    enabled: bool = False
    source: str = "automatic"
    density: float = 1.0              # 0–2: trawa Remirosa i mnożnik gęstości wtyczek
    exclusion_distance: float = 3.0   # metry (w forku tylko dla flory ogólnej, której tu nie ma – zachowane w ustawieniach)
    groundcover_enabled: bool = False
    groundcover_density: float = 1.0

    def normalized(self) -> "Settings":
        s = Settings(**self.__dict__)
        s.source = s.source if s.source in SOURCES else "automatic"
        s.density = min(max(float(s.density), 0.0), 2.0)
        s.exclusion_distance = min(max(float(s.exclusion_distance), 0.0), 20.0)
        s.groundcover_density = min(max(float(s.groundcover_density), 0.0), 1.0)
        return s

    def modes(self) -> tuple[bool, bool, float]:
        """(wtyczki groundcover, trawa proceduralna, gęstość wtyczek) – jak RenderingManager forka."""
        procedural = self.enabled and self.source in ("automatic", "hybrid")
        configured_gc = self.enabled and self.source in ("groundcover", "hybrid")
        legacy = (not self.enabled) and self.groundcover_enabled
        plugin = configured_gc or legacy
        dens = self.groundcover_density
        if self.enabled and plugin:
            dens = min(max(dens * self.density, 0.0), 1.0)
        return plugin, procedural, dens


# --- reguły Remirosa (fork: remirosgroundcoverdata.cpp + remirosgroundcovergen.hpp, pach75/pach76) ----------
#
# Jak w forku: tabela reguł i liczników jest częścią programu (converter/mwconv/data/remiros_rules.json.gz – ta sama
# tabela, którą MCP-openMW wygenerował dla forka; agregaty bez współrzędnych roślin). W grze potrzebne są wyłącznie
# modele i tekstury Remirosa (meshes/grass/…), BEZ jego wtyczek ESP – trawa jest generowana na teksturach LAND.

DATA_FILE = Path(__file__).with_name("data") / "remiros_rules.json.gz"
SRC_PLUGIN, SRC_REMIROS = 0, 2


class RemirosTable:
    """remirosgroundcoverdata.{hpp,cpp} forka: statyki, reguły tekstur, nazwy tekstur, komórki, wpisy, grupy."""

    def __init__(self, path: Path = DATA_FILE, data: Optional[dict] = None):
        import base64
        import gzip
        d = data if data is not None else json.loads(gzip.open(path).read())
        self.info = d["source_info"]
        self.spread = float(d["spread_texels"])
        self.underwater = float(d["underwater_max_height"])
        self.retries = int(d["retries"])
        self.sub = int(d["subdivisions"])
        self.statics = d["statics"]                 # [share, model, scale_min, scale_max, z_offset]
        self.textures = d["textures"]               # [texture, density_per_texel, first_static, static_count]
        self.names = d["texture_names"]
        self.cells = {(c[0], c[1]): c[2:] for c in d["cells"]}   # (x, y) → [land_hash, first_entry, n_entries, first_group]
        if "entries" in d:          # postać rozpakowana (testy)
            self.entries = np.array(d["entries"], dtype="<u4")
            self.groups = np.array(d["groups"], dtype="<u4")
        else:
            self.entries = np.frombuffer(base64.b64decode(d["entries_u32_b64"]), dtype="<u4")
            self.groups = np.frombuffer(base64.b64decode(d["groups_u32_b64"]), dtype="<u4")


_TABLE: Optional[RemirosTable] = None


def remiros_table() -> RemirosTable:
    global _TABLE
    if _TABLE is None:
        _TABLE = RemirosTable()
    return _TABLE


class RemirosModel:
    """RemirosGen::Model: statyki z modelem w VFS (meshes/grass/<plik>), reguły z udziałami tylko istniejących modeli."""

    def __init__(self, table: RemirosTable, resolve):
        self.t = table
        self.statics = []
        self.missing = 0
        for share, model, smin, smax, dz in table.statics:
            path = resolve(model)
            if not path:
                self.missing += 1
            self.statics.append((path, smin, smax, dz))
        self.rules = {}
        for tex, dens, first, count in table.textures:
            total = sum(table.statics[first + i][0] for i in range(count) if self.statics[first + i][0])
            if total <= 0:
                continue
            acc, entries = 0.0, []
            for i in range(count):
                path, smin, smax, dz = self.statics[first + i]
                if not path:
                    continue
                acc += table.statics[first + i][0] / total
                entries.append((min(acc, 1.0), path, smin, smax, dz))
            self.rules[tex] = (dens, entries)

    def active(self) -> bool:
        return bool(self.rules)


def remiros_generate_cell(terrain: Terrain, model: RemirosModel, cx: int, cy: int, density: float = 1.0) -> list:
    """RemirosGen::collectCell (komórka = chunk) → [(model, pos, rot, skala, źródło)]."""
    t = model.t
    keys = terrain.texel_keys(cx, cy)
    if keys is None or density <= 0:
        return []
    rec_tex = [-1] * 256
    first_group = [0] * 256
    group_count = [0] * 256
    c = t.cells.get((cx, cy))
    if c is not None and terrain.land_hash(cx, cy) == c[0]:
        nxt = c[3]
        for i in range(c[2]):
            e = int(t.entries[c[1] + i])
            texel = e & 0xFF
            rec_tex[texel] = (e >> 8) & 0xFF
            first_group[texel] = nxt
            group_count[texel] = (e >> 16) & 0xFF
            nxt += group_count[texel]
    cxu, cyu = (cx * 0x9E3779B9) & M32, (cy * 0x85EBCA6B) & M32
    sub = float(t.sub)
    out = []

    def count_of(d: float, seed: int) -> int:
        whole = math.floor(d)
        return int(whole) + (1 if random01(seed ^ 0x2545F491) < d - whole else 0)

    def place(s0: int, attempts: int, offset):
        for attempt in range(attempts):
            s = s0 if attempt == 0 else hash32(s0 ^ ((attempt * 0x632BE5AB) & M32))
            px, py = offset(s)
            wx, wy = px * CELL, py * CELL
            h = terrain.height_at(wx, wy)
            if h is not None and h > t.underwater:
                return wx, wy, h, s
        return None

    def emit(p, mdl, smin, smax, dz):
        wx, wy, h, s = p
        sc = smin + random01(s ^ 0x63D83595) * (smax - smin)
        rz = random01(s ^ 0xA511E9B3) * TWO_PI
        # alignToTerrain forka: normalna z różnic centralnych co 128 j.; rotX = asin(n.y), rotY = atan2(-n.x, n.z)
        d = CELL / 64.0
        hx0, hx1 = terrain.height_at(wx - d, wy), terrain.height_at(wx + d, wy)
        hy0, hy1 = terrain.height_at(wx, wy - d), terrain.height_at(wx, wy + d)
        rx = ry = 0.0
        if None not in (hx0, hx1, hy0, hy1):
            nx, ny, nz = -(hx1 - hx0) / (2 * d), -(hy1 - hy0) / (2 * d), 1.0
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            nx, ny, nz = nx / ln, ny / ln, nz / ln
            rx = math.asin(max(-1.0, min(1.0, ny)))
            ry = math.atan2(-nx, nz)
        out.append((mdl, (wx, wy, h + dz), (rx, ry, rz), sc, SRC_REMIROS))

    for ty in range(16):
        for tx in range(16):
            texel = ty * 16 + tx
            key = keys[ty][tx]
            tseed = hash32(cxu ^ cyu ^ ((texel * 0xC2B2AE35) & M32))
            if rec_tex[texel] >= 0 and t.names[rec_tex[texel]] == key:
                for gi in range(group_count[texel]):
                    g = int(t.groups[first_group[texel] + gi])
                    st = (g >> 4) & 0xFF
                    if st >= len(model.statics):
                        continue
                    mdl, smin, smax, dz = model.statics[st]
                    if not mdl:
                        continue
                    fx, fy = float(g & 3), float((g >> 2) & 3)
                    gseed = hash32(tseed ^ (((gi + 1) * 0x165667B1) & M32))
                    for k in range(count_of(float((g >> 12) & 0xFF) * density, gseed)):
                        p = place(hash32(gseed ^ ((0x9E3779B9 * (k + 1)) & M32)), t.retries,
                                  lambda s: (cx + (tx + (fx + random01(s ^ 0x68BC21EB)) / sub) / 16.0,
                                             cy + (ty + (fy + random01(s ^ 0x02E5BE93)) / sub) / 16.0))
                        if p is not None:
                            emit(p, mdl, smin, smax, dz)
                continue
            rule = model.rules.get(key)
            if rule is None:
                continue
            dd = rule[0] * density
            if dd <= 0:
                continue
            width = 1.0 + 2.0 * t.spread
            for k in range(count_of(dd, tseed)):
                p = place(hash32(tseed ^ ((0x9E3779B9 * (k + 1)) & M32)), 1,
                          lambda s: (cx + (tx + (random01(s ^ 0x68BC21EB) * width - t.spread)) / 16.0,
                                     cy + (ty + (random01(s ^ 0x02E5BE93) * width - t.spread)) / 16.0))
                if p is not None:
                    pick = random01(p[3] ^ 0x91E10DA5)
                    e = next((e for e in rule[1] if pick < e[0]), rule[1][-1])
                    emit(p, e[1], e[2], e[3], e[4])
    return out


# --- zapis --------------------------------------------------------------------------------------------------

def write_cell(path: Path, items: list, model_index: dict):
    """items: [(model_vfs, pos, rot, skala, źródło)] → plik .bin (opis w nagłówku modułu)."""
    n = len(items)
    mi = np.array([model_index[m] for m, *_ in items], dtype="<u2")
    pos = np.array([p for _m, p, *_ in items], dtype="<f4").reshape(n, 3)
    rot = np.array([r for _m, _p, r, *_ in items], dtype=np.float64).reshape(n, 3)
    rot = np.clip(np.round(((rot + math.pi) % TWO_PI - math.pi) * 10000), -32767, 32767).astype("<i2")
    sc = np.clip(np.round(np.array([s for *_x, s, _src in items]) * 10000), 0, 65535).astype("<u2")
    src = np.array([x[4] for x in items], dtype="u1")
    # ranga: deterministyczna z pozycji – gra zmniejsza gęstość bez ponownej konwersji
    with np.errstate(over="ignore"):
        q = (np.round(pos[:, 0]).astype(np.int64).astype(np.uint32) * np.uint32(0x9E3779B9)) ^ \
            (np.round(pos[:, 1]).astype(np.int64).astype(np.uint32) * np.uint32(0x85EBCA6B))
    rank = (hash32_np(q) >> np.uint32(24)).astype("u1")
    payload = (mi.tobytes() + pos[:, 0].tobytes() + pos[:, 1].tobytes() + pos[:, 2].tobytes()
               + rot[:, 0].tobytes() + rot[:, 1].tobytes() + rot[:, 2].tobytes() + sc.tobytes()
               + rank.tobytes() + src.tobytes())
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_bytes(b"MWFL" + struct.pack("<HI", FORMAT_VERSION, n) + zlib.compress(payload, 6))
    os.replace(tmp, path)


def read_cell(path: Path) -> dict:
    b = Path(path).read_bytes()
    assert b[:4] == b"MWFL"
    ver, n = struct.unpack_from("<HI", b, 4)
    p = zlib.decompress(b[10:])
    o = 0

    def take(dt, cnt):
        nonlocal o
        a = np.frombuffer(p, dtype=dt, count=cnt, offset=o)
        o += a.nbytes
        return a
    return {"model": take("<u2", n), "x": take("<f4", n), "y": take("<f4", n), "z": take("<f4", n),
            "rx": take("<i2", n), "ry": take("<i2", n), "rz": take("<i2", n), "scale": take("<u2", n),
            "rank": take("u1", n), "source": take("u1", n)}


# --- etap konwersji -----------------------------------------------------------------------------------------

def remiros_models(vfs) -> set:
    """Modele Remirosa obecne w VFS (meshes/grass/<plik z tabeli>)."""
    out = set()
    for _share, model, *_r in remiros_table().statics:
        k = f"meshes/grass/{model}"
        if vfs.exists(k):
            out.add(k)
    return out


def export(world, vfs, cfg, out: Path, settings: Settings, keys: list, glb_of, log=print,
           base_out: Optional[Path] = None) -> dict:
    """Roślinność dla wybranych komórek zewnętrznych → world/flora/. Pomija pracę bez zmian (odcisk)."""
    t0 = time.perf_counter()
    s = settings.normalized()
    plugin, procedural, pdens = s.modes()
    fdir = Path(out) / "world" / "flora"
    state_file = Path(out) / ".mwconv" / "flora_state.json"
    gc_files = list(cfg.groundcover)
    rem_present = sorted(remiros_models(vfs)) if procedural else []
    ext = [k for k in keys if k.startswith("ext:")]
    sig = {"v": FORMAT_VERSION, "table": remiros_table().info, "settings": s.__dict__,
           "gc": [(f, os.path.getsize(f)) for f in gc_files], "rem": rem_present, "cells": sorted(ext),
           "lands": hashlib.sha256(repr(sorted((g, e[2]) for g, e in world.lands.items())).encode()).hexdigest()}
    sig_key = hashlib.sha256(json.dumps(sig, sort_keys=True, default=str).encode()).hexdigest()
    import shutil
    if not plugin and not procedural:
        if fdir.exists():
            shutil.rmtree(fdir)
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_file.write_text(json.dumps({"key": sig_key}))
        return {"enabled": False}
    if state_file.exists() and (fdir / "index.json").exists():
        try:
            if json.loads(state_file.read_text()).get("key") == sig_key:
                return {"skipped": True}
        except ValueError:
            pass

    terrain = Terrain(world.lands)
    gc = GroundcoverIndex.load(gc_files) if (plugin and gc_files) else None
    remiros = None
    if procedural:
        remiros = RemirosModel(remiros_table(), lambda m: f"meshes/grass/{m}" if vfs.exists(f"meshes/grass/{m}") else None)
        if not remiros.active():
            log("Roślinność: brak modeli Remirosa (meshes/grass/) – trawa proceduralna wyłączona. "
                "Zainstaluj Remiros' Groundcover jako mod (wystarczą modele i tekstury, bez ESP).")
            remiros = None
        else:
            log(f"Roślinność: reguły Remirosa (tabela forka: {remiros_table().info}); modele: "
                f"{len(rem_present)}, statyk bez modelu: {remiros.missing}")

    if fdir.exists():
        shutil.rmtree(fdir)
    model_index: dict = {}
    models_list: list = []
    cells_out = {}
    stats = collections.Counter()
    counts_used = 0
    for k in ext:
        cx, cy = (int(v) for v in k[4:].split(","))
        items = []
        if gc is not None:
            for m, r in gc.instances(cx, cy, pdens):
                mk = vfs.resolve_mesh(m)
                if mk:
                    items.append((mk, r.pos, r.rot, r.scale, SRC_PLUGIN))
        if remiros is not None:
            c = remiros_table().cells.get((cx, cy))
            if c is not None and terrain.land_hash(cx, cy) == c[0]:
                counts_used += 1
            items += remiros_generate_cell(terrain, remiros, cx, cy, s.density)
        if not items:
            continue
        for m, *_ in items:
            if m not in model_index:
                model_index[m] = len(models_list)
                models_list.append(m)
        rel = f"{cx}_{cy}.bin"
        write_cell(fdir / rel, items, model_index)
        cells_out[k] = {"file": rel, "count": len(items)}
        for it in items:
            stats["plugin" if it[4] == SRC_PLUGIN else "remiros"] += 1
    mode = "+".join(x for x, on in (("plugins", gc is not None), ("remiros", remiros is not None)) if on) or "none"
    from .world import write_json
    write_json(fdir / "index.json", {
        "format": "mwgodot-flora", "version": FORMAT_VERSION, "settings": s.__dict__, "mode": mode,
        "models": [{"vfs": m, "glb": glb_of(m)} for m in models_list], "cells": cells_out})
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps({"key": sig_key}))
    return {"cells": len(cells_out), "instances": sum(stats.values()), "by_source": dict(stats),
            "models": len(models_list), "mode": mode, "count_cells_matched": counts_used,
            "seconds": round(time.perf_counter() - t0, 2)}
