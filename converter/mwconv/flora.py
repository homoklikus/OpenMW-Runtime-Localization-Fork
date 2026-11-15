"""Roślinność – przeniesione z forka OpenMW RLF i z MCP-openMW (GPL-3.0-or-later, jak OpenMWGodot).

Źródła (fork `0.5-world`, 3bfa4c3):
  apps/openmw/mwrender/groundcover.cpp       groundcover z wtyczek + flora proceduralna (wagi tekstur, nachylenie,
                                             wykluczenia obiektów i ścieżek PGRD, wybór modelu, skala profilu)
  apps/openmw/mwrender/remirosgroundcover*   reguły Remirosa (pach75) z licznikami na pole 128 j. (pach76)
  apps/openmw/mwrender/terrainstorage.cpp    wysokość „diamond”, nachylenie, tekstura LAND w punkcie
  apps/openmw/mwrender/renderingmanager.cpp  mapowanie ustawień: source = automatic | groundcover | hybrid
  components/worldconfig                     [flora] enabled, source, density, exclusion_distance
MCP-openMW (tools/MCP-openMW): land.py, fflora.py, gcbaseline.py (DensityCalculator), remirosrules.py (derive,
build_counts, generate_cell) – pythonowe odpowiedniki kodu forka.

Różnica architektury: OpenMW liczy rośliny w trakcie gry (chunki terenu). Tu konwerter liczy je raz, dla każdej
komórki zewnętrznej, i zapisuje world/flora/<x>_<y>.bin; gra tylko je rysuje (MultiMesh, bez kolizji). Reguły
Remirosa są wyliczane LOKALNIE z zainstalowanych wtyczek Rem_*.esp (fork miał je wkompilowane) – repozytorium
nie zawiera żadnych danych moda. Arytmetyka w float64 (fork: float32) – pojedyncze instancje na granicach progów
mogą się różnić; rozkład i zasady są te same.

Format world/flora/<x>_<y>.bin (zlib): "MWFL" u16 wersja, u32 N, następnie kolumny po N:
  u16 model (indeks w index.json „models”), f32 x, f32 y, f32 z (jednostki MW, świat),
  i16 rx, i16 ry, i16 rz (radiany × 10000), u16 skala × 10000, u8 ranga (0–255, do zmniejszania gęstości w grze),
  u8 źródło (0 = wtyczka groundcover, 1 = proceduralna, 2 = Remiros).
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
SRC_PLUGIN, SRC_PROCEDURAL, SRC_REMIROS = 0, 1, 2

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


# --- flora proceduralna (groundcover.cpp forka, tryb ogólny) ---------------------------------------------

PROCEDURAL_CANDIDATES = (
    "meshes/f/flora_grass_01.nif", "meshes/f/flora_grass_02.nif", "meshes/f/flora_grass_03.nif",
    "meshes/f/flora_grass_04.nif", "meshes/f/flora_grass_05.nif", "meshes/f/flora_grass_06.nif",
    "meshes/f/flora_grass_07.nif", "meshes/f/flora_bc_grass_01.nif", "meshes/f/flora_bc_grass_02.nif",
    "meshes/f/flora_ash_grass_b_01.nif", "meshes/f/flora_ash_grass_r_01.nif", "meshes/f/flora_ash_grass_w_01.nif",
    "meshes/f/flora_bm_grass_01.nif", "meshes/f/flora_bm_grass_02.nif", "meshes/f/flora_bm_grass_03.nif",
    "meshes/f/flora_bm_grass_04.nif", "meshes/f/flora_bm_grass_05.nif", "meshes/f/flora_bm_grass_06.nif",
)
TARGET_FOOTPRINT = 60.0
REJECT_FOOTPRINT = 200.0
BASE_CANDIDATES = 32768.0
MAX_SLOPE = 28.0


def surface_weight(key: str) -> float:
    """getProceduralFloraSurfaceWeight forka (klucz = nazwa pliku tekstury bez rozszerzenia)."""
    if not key or key == "_land_default":
        return 0.0
    for kw in ("rock", "stone", "cliff", "road", "cobble", "lava"):
        if kw in key:
            return 0.0
    grass, dirt = "grass" in key, "dirt" in key
    if grass and dirt:
        return 0.5
    if grass or "clover" in key or "moss" in key:
        return 1.0
    if "mud" in key or "swamp" in key:
        return 0.55
    if dirt:
        return 0.35
    if "sand" in key:
        return 0.2
    if "ash" in key:
        return 0.15
    return 0.4


def uses_pathgrid_exclusion(key: str) -> bool:
    if not key:
        return False
    if "road" in key or "path" in key or "cobble" in key:
        return True
    dirt = "dirt" in key
    natural = "grass" in key or "clover" in key or "moss" in key
    return dirt and not natural


def region_family(key: str) -> str:
    i = key.find("tx_")
    if i < 0:
        return "generic"
    rest = key[i + 3:]
    j = rest.find("_")
    tok = rest[:j] if j > 0 else ""
    if tok == "bc":
        return "bc"
    if tok in ("al", "rr", "rm"):
        return "ash"
    if tok in ("sol", "bm"):
        return "bm"
    return "generic"


def model_family(model: str) -> str:
    m = model.replace("\\", "/").lower()
    if "/flora_bc_grass_" in m:
        return "bc"
    if "/flora_ash_grass_" in m:
        return "ash"
    if "/flora_bm_grass_" in m:
        return "bm"
    return "generic"


BLOCKING_TYPES = {"STAT", "ACTI", "DOOR", "CONT"}
NATURAL_KEYWORDS = ("flora", "tree", "plant", "mushroom", "kelp", "fern", "bush", "shrub", "rock", "boulder")
HIDDEN_MARKERS = {"prisonmarker", "divinemarker", "templemarker", "northmarker"}   # Misc::ResourceHelpers::isHiddenMarker


@dataclass
class Settings:
    enabled: bool = False
    source: str = "automatic"
    density: float = 1.0              # 0–2 (flora proceduralna) i mnożnik gęstości wtyczek
    exclusion_distance: float = 3.0   # metry
    groundcover_enabled: bool = False   # „legacy” [Groundcover] enabled (gdy [flora] wyłączona)
    groundcover_density: float = 1.0

    def normalized(self) -> "Settings":
        s = Settings(**self.__dict__)
        s.source = s.source if s.source in SOURCES else "automatic"
        s.density = min(max(float(s.density), 0.0), 2.0)
        s.exclusion_distance = min(max(float(s.exclusion_distance), 0.0), 20.0)
        s.groundcover_density = min(max(float(s.groundcover_density), 0.0), 1.0)
        return s

    def modes(self) -> tuple[bool, bool, float]:
        """(wtyczki groundcover, flora proceduralna, gęstość wtyczek) – jak RenderingManager forka."""
        procedural = self.enabled and self.source in ("automatic", "hybrid")
        configured_gc = self.enabled and self.source in ("groundcover", "hybrid")
        legacy = (not self.enabled) and self.groundcover_enabled
        plugin = configured_gc or legacy
        dens = self.groundcover_density
        if self.enabled and plugin:
            dens = min(max(dens * self.density, 0.0), 1.0)
        return plugin, procedural, dens


class ModelInfo:
    """Rozmiary modeli z GLB (granice POSITION) w jednostkach MW."""

    def __init__(self, out: Path, base_out: Optional[Path] = None):
        self.roots = [Path(out)] + ([Path(base_out)] if base_out else [])
        self._b: dict = {}

    def bounds(self, glb_rel: str) -> Optional[tuple]:
        """(xmin, xmax, ymin, ymax) MW lub None."""
        if glb_rel in self._b:
            return self._b[glb_rel]
        res = None
        for r in self.roots:
            p = r / glb_rel
            if p.exists():
                try:
                    with open(p, "rb") as fh:
                        head = fh.read(20)
                        ln, = struct.unpack_from("<I", head, 12)
                        j = json.loads(fh.read(ln))
                    mins, maxs = [], []
                    for me in j.get("meshes", []):
                        for pr in me.get("primitives", []):
                            a = j["accessors"][pr["attributes"]["POSITION"]]
                            if "min" in a and "max" in a:
                                mins.append(a["min"])
                                maxs.append(a["max"])
                    if mins:
                        mn = np.min(np.array(mins), axis=0)
                        mx = np.max(np.array(maxs), axis=0)
                        # Godot (x, y, z) = (mw_x, mw_z, -mw_y) / UPM
                        res = (mn[0] * UPM, mx[0] * UPM, -mx[2] * UPM, -mn[2] * UPM)
                except Exception:  # noqa: BLE001
                    res = None
                break
        self._b[glb_rel] = res
        return res


def procedural_pool(vfs, models: ModelInfo, glb_of) -> tuple[list, dict]:
    """Pula modeli trybu ogólnego (wanilia) i skale profilu: odrzucone > 200 j., zmniejszone do 60 j."""
    pool, scale = [], {}
    for c in PROCEDURAL_CANDIDATES:
        if not vfs.exists(c):
            continue
        b = models.bounds(glb_of(c))
        if b is None:
            continue
        fp = max(b[1] - b[0], b[3] - b[2])
        if fp > REJECT_FOOTPRINT:
            continue
        pool.append(c)
        scale[c] = TARGET_FOOTPRINT / fp if fp > TARGET_FOOTPRINT else 1.0
    return pool, scale


def generate_procedural(terrain: Terrain, cx: int, cy: int, density: float, pool: list, pscale: dict,
                        exclusions: np.ndarray, segments: np.ndarray, excl_dist: float) -> list:
    """Groundcover::collectInstances forka, tryb ogólny, dla jednej komórki (chunk = komórka)."""
    if not pool or density <= 0 or not terrain.has_textures(cx, cy):
        return []
    n = max(1, int(round(BASE_CANDIDATES * density)))
    side = int(math.ceil(math.sqrt(n)))
    idx = np.arange(n, dtype=np.uint32)
    with np.errstate(over="ignore"):
        base = (_u32(cx * 0x9E3779B9) ^ _u32(cy * 0x85EBCA6B)) ^ (idx * np.uint32(0xC2B2AE35))
    gx = (idx % side).astype(np.float64)
    gy = (idx // side).astype(np.float64)
    fx = (gx + random01_np(base ^ np.uint32(0x68BC21EB))) / side
    fy = (gy + random01_np(base ^ np.uint32(0x02E5BE93))) / side
    keep = (fx < 1.0) & (fy < 1.0)
    base, fx, fy = base[keep], fx[keep], fy[keep]
    wx = (cx + fx) * CELL
    wy = (cy + fy) * CELL
    h = terrain.height_np(wx, wy)
    keep = ~np.isnan(h) & (h > 1.0)
    base, wx, wy, h = base[keep], wx[keep], wy[keep], h[keep]
    if len(base) == 0:
        return []
    slope = terrain.slope_np(wx, wy)
    keep = ~(slope > MAX_SLOPE)
    base, wx, wy, h = base[keep], wx[keep], wy[keep], h[keep]
    keys = terrain.texel_keys(cx, cy)
    tx = np.clip(((wx / CELL - cx) * TEX_SIZE).astype(np.int64), 0, 15)
    ty = np.clip(((wy / CELL - cy) * TEX_SIZE).astype(np.int64), 0, 15)
    uniq = sorted({keys[y][x] for y in range(16) for x in range(16)})
    kid = {k: i for i, k in enumerate(uniq)}
    grid = np.array([[kid[keys[y][x]] for x in range(16)] for y in range(16)])
    tk = grid[ty, tx]
    wtab = np.array([surface_weight(k) for k in uniq])
    ptab = np.array([uses_pathgrid_exclusion(k) for k in uniq])
    ftab = [region_family(k) for k in uniq]
    w = wtab[tk]
    keep = (w > 0) & ((w >= 1.0) | (random01_np(base ^ np.uint32(0x4F1BBCDC)) < w))
    base, wx, wy, h, tk, w = base[keep], wx[keep], wy[keep], h[keep], tk[keep], w[keep]
    if len(exclusions):
        inside = np.zeros(len(wx), dtype=bool)
        for ex, ey, r in exclusions:
            inside |= (wx - ex) ** 2 + (wy - ey) ** 2 <= r * r
        keep = ~inside
        base, wx, wy, h, tk, w = base[keep], wx[keep], wy[keep], h[keep], tk[keep], w[keep]
    if len(segments) and ptab.any():
        chk = ptab[tk]
        hit = np.zeros(len(wx), dtype=bool)
        c2 = excl_dist * excl_dist
        for x0, y0, x1, y1 in segments:
            dx, dy = x1 - x0, y1 - y0
            l2 = dx * dx + dy * dy
            if l2 <= 1e-4:
                d2 = (wx - x0) ** 2 + (wy - y0) ** 2
            else:
                t = np.clip(((wx - x0) * dx + (wy - y0) * dy) / l2, 0.0, 1.0)
                d2 = (wx - (x0 + t * dx)) ** 2 + (wy - (y0 + t * dy)) ** 2
            hit |= chk & (d2 <= c2)
        keep = ~hit
        base, wx, wy, h, tk, w = base[keep], wx[keep], wy[keep], h[keep], tk[keep], w[keep]
    cs = hash32_np(base ^ np.uint32(0x9E3779B9))
    keep = (w >= 1.0) | (random01_np(cs ^ np.uint32(0x4F1BBCDC)) < w)
    cs, wx, wy, h, tk = cs[keep], wx[keep], wy[keep], h[keep], tk[keep]
    rz = random01_np(cs ^ np.uint32(0xA511E9B3)) * TWO_PI
    sel = hash32_np(cs ^ np.uint32(0x91E10DA5)).astype(np.int64)
    fam_models = collections.defaultdict(list)
    for m in pool:
        fam_models[model_family(m)].append(m)
    out = []
    rnd_scale = random01_np(cs ^ np.uint32(0x63D83595))
    for i in range(len(cs)):
        cand = fam_models.get(ftab[tk[i]]) or pool
        m = cand[sel[i] % len(cand)]
        sc = (0.8 + rnd_scale[i] * 0.35) * pscale[m]
        out.append((m, (wx[i], wy[i], h[i]), (0.0, 0.0, rz[i]), sc, SRC_PROCEDURAL))
    return out


def collect_exclusions(world, cx: int, cy: int, models: ModelInfo, glb_of, excl_dist: float) -> np.ndarray:
    """collectFloraExclusions: STAT/ACTI/DOOR/CONT z komórki i sąsiadów, bez znaczników i natury."""
    out = []
    for x in range(cx - 1, cx + 2):
        for y in range(cy - 1, cy + 2):
            mc = world.cells.get(f"ext:{x},{y}")
            if mc is None:
                continue
            for mr in mc.refs.values():
                r = mr.ref
                bid = r.base.lower()
                if bid in HIDDEN_MARKERS:
                    continue
                o = world.objects.get(bid)
                if o is None or o.get("type") not in BLOCKING_TYPES or not o.get("model"):
                    continue
                model = o["model"].replace("\\", "/").lower()
                if o.get("type") == "STAT" and any(k in model for k in NATURAL_KEYWORDS):
                    continue
                b = models.bounds(glb_of("meshes/" + model if not model.startswith("meshes/") else model))
                if b is None:
                    continue
                rad = math.hypot(max(abs(b[0]), abs(b[1])), max(abs(b[2]), abs(b[3])))
                rr = rad * abs(r.scale) + excl_dist
                if rr > 0:
                    out.append((r.pos[0], r.pos[1], rr))
    return np.array(out, dtype=np.float64).reshape(-1, 3)


def collect_segments(world, cx: int, cy: int) -> np.ndarray:
    out = []
    for x in range(cx - 1, cx + 2):
        for y in range(cy - 1, cy + 2):
            pg = world.pathgrids.get((x, y))
            if not pg:
                continue
            pts, edges = pg
            for i, j in edges:
                a, b = pts[i], pts[j]
                out.append((a[0], a[1], b[0], b[1]))
            if not edges:
                for p in pts:
                    out.append((p[0], p[1], p[0], p[1]))
    return np.array(out, dtype=np.float64).reshape(-1, 4)


# --- reguły Remirosa (remirosrules.py MCP / remirosgroundcovergen.hpp forka) ------------------------------

SPREAD = 0.3
UNDERWATER = -23.0
RETRIES = 4
SUB = 4


def is_remiros_plugin(path) -> bool:
    return Path(path).name.lower().startswith("rem_") and Path(path).suffix.lower() == ".esp"


def remiros_derive(gc: GroundcoverIndex, terrain: Terrain) -> dict:
    """Tabela „tekstura LAND → gęstość, statyki, skale, wysokość” (MCP derive)."""
    by_static = collections.defaultdict(lambda: {"n": 0, "tex": collections.Counter(), "smin": 1e9, "smax": -1e9,
                                                 "dz": []})
    for (cx, cy), lst in gc.cells.items():
        for fi, refs in lst:
            for k, r in enumerate(refs):
                if r.deleted or not gc.statics.get(r.id):
                    continue
                s = by_static[r.id]
                s["n"] += 1
                s["tex"][terrain.texture_key_at(r.pos[0], r.pos[1])] += 1
                s["smin"] = min(s["smin"], r.scale)
                s["smax"] = max(s["smax"], r.scale)
                if k % 7 == 0 and len(s["dz"]) < 4000:
                    h = terrain.height_at(r.pos[0], r.pos[1])
                    if h is not None:
                        s["dz"].append(r.pos[2] - h)
    owner = {sid: s["tex"].most_common(1)[0][0] for sid, s in by_static.items()}
    area = collections.Counter()
    for (cx, cy) in terrain.lands:
        keys = terrain.texel_keys(cx, cy)
        if keys is None:
            continue
        xs = (cx + (np.arange(16) + 0.5) / 16) * CELL
        ys = (cy + (np.arange(16) + 0.5) / 16) * CELL
        gxs, gys = np.meshgrid(xs, ys)
        hh = terrain.height_np(gxs, gys)
        for ty in range(16):
            for tx in range(16):
                if keys[ty][tx] and not math.isnan(hh[ty, tx]) and hh[ty, tx] > UNDERWATER:
                    area[keys[ty][tx]] += 1
    textures = collections.defaultdict(lambda: {"refs": 0, "statics": []})
    for sid, s in by_static.items():
        t = textures[owner[sid]]
        t["refs"] += s["n"]
        dz = sorted(s["dz"])
        t["statics"].append({"id": sid, "model": gc.statics[sid].replace("\\", "/").rsplit("/", 1)[-1].lower(),
                             "refs": s["n"], "scale_min": s["smin"], "scale_max": s["smax"],
                             "z_offset": dz[len(dz) // 2] if dz else 23.0})
    rules = []
    for key, t in sorted(textures.items()):
        a = area.get(key, 0)
        statics = sorted(t["statics"], key=lambda x: (-x["refs"], x["id"]))
        for st in statics:
            st["share"] = st["refs"] / t["refs"]
        rules.append({"texture": key, "density_per_texel": t["refs"] / a if a else 0.0, "refs": t["refs"],
                      "statics": statics})
    rules.sort(key=lambda r: -r["refs"])
    return {"rules": rules}


def remiros_counts(gc: GroundcoverIndex, terrain: Terrain, rules: dict) -> dict:
    """Liczniki na pole 128 j. i statykę (pach76) – agregaty, bez współrzędnych roślin (MCP build_counts)."""
    order = [st for r in rules["rules"] for st in r["statics"]]
    owners = {r["texture"] for r in rules["rules"]}
    sidx = {st["id"]: i for i, st in enumerate(order)}
    per_texel = collections.defaultdict(collections.Counter)
    for (cx, cy) in gc.cells:
        for _model, r in gc.instances(cx, cy, 1.0):
            if r.id not in sidx:
                continue
            gx, gy = math.floor(r.pos[0] / CELL * 16 * SUB), math.floor(r.pos[1] / CELL * 16 * SUB)
            sub = (gy % SUB) * SUB + (gx % SUB)
            per_texel[(gx // SUB, gy // SUB)][(sub, sidx[r.id])] += 1
    cells = {}
    cells_with = {(tx // 16, ty // 16) for tx, ty in per_texel}
    for (cx, cy) in sorted(cells_with | {xy for xy in terrain.lands if xy in gc.cells}):
        keys = terrain.texel_keys(cx, cy)
        lh = terrain.land_hash(cx, cy)
        if keys is None or lh is None:
            continue
        entries = {}
        for ty in range(16):
            for tx in range(16):
                key = keys[ty][tx]
                g = per_texel.get((cx * 16 + tx, cy * 16 + ty))
                if not g and key not in owners:
                    continue
                entries[ty * 16 + tx] = (key, sorted((sub, st, min(k, 255)) for (sub, st), k in (g or {}).items()))
        cells[(cx, cy)] = (lh, entries)
    return {"order": order, "cells": cells}


class RemirosModel:
    def __init__(self, rules: dict, counts: dict, resolve):
        """resolve(nazwa pliku modelu) → klucz VFS albo None (model nie istnieje: meshes/grass/<nazwa>)."""
        self.rules = {}
        for r in rules["rules"]:
            sts = [s for s in r["statics"] if resolve(s["model"])]
            tot = sum(s["share"] for s in sts)
            if not sts or tot <= 0:
                continue
            acc, entries = 0.0, []
            for s in sts:
                acc += s["share"] / tot
                entries.append((min(acc, 1.0), resolve(s["model"]), s["scale_min"], s["scale_max"], s["z_offset"]))
            self.rules[r["texture"]] = (r["density_per_texel"], entries)
        self.statics = [(resolve(st["model"]), st["scale_min"], st["scale_max"], st["z_offset"])
                        for st in counts["order"]]
        self.counts = counts["cells"]

    def active(self) -> bool:
        return bool(self.rules)


def remiros_generate_cell(terrain: Terrain, model: RemirosModel, cx: int, cy: int, density: float = 1.0) -> list:
    """RemirosGen::collectCell (komórka jako chunk) → [(model, pos, rot, skala, źródło)]."""
    keys = terrain.texel_keys(cx, cy)
    if keys is None:
        return []
    cnt = model.counts.get((cx, cy))
    hash_ok = cnt is not None and terrain.land_hash(cx, cy) == cnt[0]
    cxu, cyu = (cx * 0x9E3779B9) & M32, (cy * 0x85EBCA6B) & M32
    out = []

    def count_of(d: float, seed: int) -> int:
        return int(math.floor(d)) + (1 if random01(seed ^ 0x2545F491) < d - math.floor(d) else 0)

    def place(s0: int, attempts: int, offset):
        for attempt in range(attempts):
            s = s0 if attempt == 0 else hash32(s0 ^ ((attempt * 0x632BE5AB) & M32))
            px, py = offset(s)
            wx, wy = px * CELL, py * CELL
            h = terrain.height_at(wx, wy)
            if h is not None and h > UNDERWATER:
                return wx, wy, h, s
        return None

    def emit(p, mdl, smin, smax, dz):
        wx, wy, h, s = p
        sc = smin + random01(s ^ 0x63D83595) * (smax - smin)
        rz = random01(s ^ 0xA511E9B3) * TWO_PI
        # obrót wg normalnej terenu (różnice centralne co 128 j.): rotX = asin(n.y), rotY = atan2(-n.x, n.z)
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
            t = ty * 16 + tx
            key = keys[ty][tx]
            rec = cnt[1].get(t) if hash_ok else None
            tseed = hash32(cxu ^ cyu ^ ((t * 0xC2B2AE35) & M32))
            if rec is not None and rec[0] == key:
                for gi, (sub, st, k) in enumerate(rec[1]):
                    mdl, smin, smax, dz = model.statics[st]
                    if not mdl:
                        continue
                    gseed = hash32(tseed ^ (((gi + 1) * 0x165667B1) & M32))
                    sxf, syf = float(sub % SUB), float(sub // SUB)
                    for kk in range(count_of(k * density, gseed)):
                        p = place(hash32(gseed ^ ((0x9E3779B9 * (kk + 1)) & M32)), RETRIES,
                                  lambda s: (cx + (tx + (sxf + random01(s ^ 0x68BC21EB)) / SUB) / 16.0,
                                             cy + (ty + (syf + random01(s ^ 0x02E5BE93)) / SUB) / 16.0))
                        if p is not None:
                            emit(p, mdl, smin, smax, dz)
                continue
            rule = model.rules.get(key)
            if rule is None:
                continue
            dd = rule[0] * density
            if dd <= 0:
                continue
            width = 1.0 + 2.0 * SPREAD
            for k in range(count_of(dd, tseed)):
                p = place(hash32(tseed ^ ((0x9E3779B9 * (k + 1)) & M32)), 1,
                          lambda s: (cx + (tx + (random01(s ^ 0x68BC21EB) * width - SPREAD)) / 16.0,
                                     cy + (ty + (random01(s ^ 0x02E5BE93) * width - SPREAD)) / 16.0))
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

def candidate_models(vfs, cfg_groundcover: list, remiros_files: list, gc: Optional[GroundcoverIndex]) -> set:
    """Modele potrzebne roślinności (do konwersji NIF → GLB przed generowaniem)."""
    out = {c for c in PROCEDURAL_CANDIDATES if vfs.exists(c)}
    if gc is not None:
        for m in gc.statics.values():
            k = vfs.resolve_mesh(m) if m else None
            if k:
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
    rem_files = sorted({str(p) for d in cfg.data_dirs if Path(d).is_dir()
                        for p in Path(d).iterdir() if is_remiros_plugin(p)} | {f for f in gc_files if is_remiros_plugin(f)})
    ext = [k for k in keys if k.startswith("ext:")]
    sig = {"v": FORMAT_VERSION, "settings": s.__dict__, "gc": [(f, os.path.getsize(f)) for f in gc_files],
           "rem": [(f, os.path.getsize(f)) for f in rem_files], "cells": sorted(ext),
           "lands": hashlib.sha256(repr(sorted((g, e[2]) for g, e in world.lands.items())).encode()).hexdigest(),
           "content": [os.path.basename(c) for c in cfg.content]}
    sig_key = hashlib.sha256(json.dumps(sig, sort_keys=True, default=str).encode()).hexdigest()
    if not plugin and not procedural:
        if fdir.exists():
            import shutil
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
    models = ModelInfo(out, base_out)
    gc = GroundcoverIndex.load(gc_files) if (plugin and gc_files) else None
    remiros = None
    if procedural and rem_files:
        rg = GroundcoverIndex.load(rem_files)
        rules = remiros_derive(rg, terrain)
        counts = remiros_counts(rg, terrain, rules)

        def resolve(name, _c={}):
            if name not in _c:
                k = f"meshes/grass/{name}"
                _c[name] = k if vfs.exists(k) else None
            return _c[name]
        remiros = RemirosModel(rules, counts, resolve)
        if not remiros.active():
            remiros = None
        log(f"Roślinność: reguły Remirosa z {len(rem_files)} wtyczek – "
            f"{len(remiros.rules) if remiros else 0} tekstur, {len(counts['cells'])} komórek z licznikami")
    pool, pscale = ([], {})
    if procedural and remiros is None:
        pool, pscale = procedural_pool(vfs, models, glb_of)
    excl = s.exclusion_distance * UPM

    import shutil
    if fdir.exists():
        shutil.rmtree(fdir)
    model_index: dict = {}
    models_list: list = []
    cells_out = {}
    stats = collections.Counter()
    for k in ext:
        cx, cy = (int(v) for v in k[4:].split(","))
        items = []
        if gc is not None:
            for m, r in gc.instances(cx, cy, pdens):
                mk = vfs.resolve_mesh(m)
                if mk:
                    items.append((mk, r.pos, r.rot, r.scale, SRC_PLUGIN))
        if procedural:
            if remiros is not None:
                items += remiros_generate_cell(terrain, remiros, cx, cy, s.density)
            elif pool:
                items += generate_procedural(terrain, cx, cy, s.density, pool, pscale,
                                             collect_exclusions(world, cx, cy, models, glb_of, excl),
                                             collect_segments(world, cx, cy), excl)
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
            stats[("plugin", "procedural", "remiros")[it[4]]] += 1
    from .world import write_json
    write_json(fdir / "index.json", {
        "format": "mwgodot-flora", "version": FORMAT_VERSION,
        "settings": s.__dict__, "plugin_groundcover": plugin, "procedural": procedural,
        "mode": "remiros" if remiros else ("generic" if procedural else "plugins"),
        "models": [{"vfs": m, "glb": glb_of(m)} for m in models_list], "cells": cells_out})
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps({"key": sig_key}))
    return {"cells": len(cells_out), "instances": sum(stats.values()), "by_source": dict(stats),
            "models": len(models_list), "mode": "remiros" if remiros else ("generic" if procedural else "plugins"),
            "seconds": round(time.perf_counter() - t0, 2)}
