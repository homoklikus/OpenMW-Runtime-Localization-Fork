"""Proceduralna flora forka offline — emulacja Groundcover::collectInstances w wersji SPRZED pach75 (profile
regionalne AI/AL/BC/GL/WG, commit 5629d385). Po pach75 trawę Remirosa emuluje remirosrules.py.

Źródło: Fork/repo/apps/openmw/mwrender/groundcover.cpp (gałąź procedural) i terrainstorage.cpp.
Odwzorowane: ziarna i hash32, siatka ceil(√N) z jitterem, liczba kandydatów (32768 / AI 4096 / AL,BC,GL,WG 8192
× gęstość), regiony Remirosa (RGNN komórki; AL i GL z zapasowym próbkowaniem tekstur LAND), wysokość
„diamond” > 1, limit nachylenia (45° AI/AL/GL, inaczej 28°), wagi powierzchni (ogólna, AI, AL) i dwa
losowania akceptacji (miejsce bazowe i klaster o promieniu 0), wybór modelu i skala profili.

NIE odwzorowane (wynik jest górną granicą): wykluczenia obiektów sceny (collectFloraExclusions — wymaga
granic modeli z NIF) i ścieżek PGRD (collectPathgridExclusions). Kandydaci na teksturach, dla których silnik
sprawdza ścieżki, są liczeni osobno (`pathgrid_check_candidates`).
Arytmetyka: pozycje kandydatów i losowania jak w float32; teren liczony w float64 — przypadki graniczne
(np. nachylenie dokładnie na progu) mogą się różnić pojedynczymi instancjami.
"""

from __future__ import annotations

import collections
import math
import struct
from dataclasses import dataclass, field
from typing import Optional

from .land import CELL, LandIndex

M32 = 0xFFFFFFFF
TWO_PI = 6.2831853071795864769
_F = struct.Struct("<f")

REGION_AI = "Ascadian Isles Region"
REGION_AL = "Ashlands Region"
REGION_BC = "Bitter Coast Region"
REGION_GL = "Grazelands Region"
REGION_WG = "West Gash Region"
FORK_PROFILE_REGIONS = {"AI": REGION_AI, "AL": REGION_AL, "BC": REGION_BC, "GL": REGION_GL, "WG": REGION_WG}

POOL_REQUIREMENTS = {
    "AI": ("rem_ai_grass_01.nif", "rem_ai_grass_01b.nif", "rem_ai_grass_01c.nif", "rem_ai_grass_02.nif"),
    "AL": ("rem_al_grass.nif", "rem_al_grass_b.nif", "rem_al_rock.nif"),
    "BC": ("rem_bc_grass_01.nif", "rem_bc_grass_02.nif", "rem_bc_grass_03.nif"),
    "GL": ("rem_gl_grass_01.nif", "rem_gl_grass_01b.nif", "rem_gl_grass_01c.nif"),
    "WG": ("rem_wg_grass_01.nif", "rem_wg_grass_01b.nif", "rem_wg_grass_02.nif", "rem_wg_grass_02b.nif",
           "rem_wg_grass_03.nif", "rem_wg_grass_04.nif"),
}
CANDIDATES = {"AI": 4096.0, "AL": 8192.0, "BC": 8192.0, "GL": 8192.0, "WG": 8192.0, None: 32768.0}


def f32(x: float) -> float:
    return _F.unpack(_F.pack(x))[0]


def hash32(v: int) -> int:
    v &= M32
    v ^= v >> 16
    v = (v * 0x7FEB352D) & M32
    v ^= v >> 15
    v = (v * 0x846CA68B) & M32
    v ^= v >> 16
    return v


def random01(seed: int) -> float:
    return (hash32(seed) & 0x00FFFFFF) / 16777216.0          # dokładnie reprezentowalne w float32


def lround(x: float) -> int:                                    # std::lround: połówki od zera
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def norm_path(p: Optional[str]) -> str:
    return (p or "").replace("\\", "/").lower()


# --- wagi powierzchni (groundcover.cpp) ---------------------------------------------------------------

def generic_surface_weight(t: str) -> float:
    if not t or t == "_land_default.dds":
        return 0.0
    if any(k in t for k in ("rock", "stone", "cliff", "road", "cobble", "lava")):
        return 0.0
    grass, dirt = "grass" in t, "dirt" in t
    if grass and dirt:
        return 0.5
    if grass or "clover" in t or "moss" in t:
        return 1.0
    if "mud" in t or "swamp" in t:
        return f32(0.55)
    if dirt:
        return f32(0.35)
    if "sand" in t:
        return f32(0.2)
    if "ash" in t:
        return f32(0.15)
    return f32(0.4)


def ai_surface_weight(t: str, generic: float) -> float:
    if generic > 0.0 or not t:
        return generic
    rock = "rock" in t
    natural = "grass" in t or "moss" in t or "clover" in t
    return f32(0.65) if rock and natural else generic


def al_surface_weight(t: str, generic: float) -> float:
    if not t:
        return generic
    if "tx_al_" not in t and "tx_ashlands_" not in t:
        return generic
    if "road" in t or "cobble" in t or "lava" in t:
        return 0.0
    if "rock" in t or "stone" in t or "cliff" in t:
        return 0.25
    if "tx_ashlands_" in t:
        return 1.0
    if "ash" in t:
        return max(generic, f32(0.35))
    return generic


def uses_pathgrid_exclusion(t: str) -> bool:
    if not t:
        return False
    if "road" in t or "path" in t or "cobble" in t:
        return True
    return "dirt" in t and not ("grass" in t or "clover" in t or "moss" in t)


# --- pula i wybór modeli ----------------------------------------------------------------------------

def _find(models: list[str], suffix: str) -> Optional[str]:
    for m in models:
        if m.endswith("/" + suffix):
            return m
    return None


def pool_profiles(models: list[str]) -> dict[str, bool]:
    return {k: all(_find(models, s) for s in req) for k, req in POOL_REQUIREMENTS.items()}


def choose_ai(models, texture: str, sel: int) -> Optional[str]:
    g01, g01b, g01c, g02 = (_find(models, s) for s in POOL_REQUIREMENTS["AI"])
    if None in (g01, g01b, g01c, g02):
        return None
    if "clover" in texture:
        return g02
    if "grass" in texture and "dirt" in texture:
        slot = sel % 15508
        return g01 if slot < 6079 else (g01c if slot < 10867 else g01b)
    if "grass_02" in texture:
        slot = sel % 14359
        return g01 if slot < 6998 else (g01c if slot < 11514 else g01b)
    slot = sel % 61648
    return g01 if slot < 45651 else (g01c if slot < 55460 else g01b)


def choose_al(models, sel: int) -> Optional[str]:
    grass, grass_b, rock = (_find(models, s) for s in POOL_REQUIREMENTS["AL"])
    if None in (grass, grass_b, rock):
        return None
    slot = sel % 100
    return grass if slot < 45 else (grass_b if slot < 90 else rock)


def choose_bc(models, sel: int) -> Optional[str]:
    ms = [_find(models, s) for s in POOL_REQUIREMENTS["BC"]]
    return None if None in ms else ms[sel % 3]


def choose_gl(models, sel: int) -> Optional[str]:
    return _find(models, POOL_REQUIREMENTS["GL"][sel % 3])


def choose_wg(models, sel: int) -> Optional[str]:
    return _find(models, POOL_REQUIREMENTS["WG"][sel % 6])


def _stylized_role(model: str) -> str:
    name = model.rsplit("/", 1)[-1]
    if len(name) < 3 or name[2] != "_" or not (name[0].isdigit() and name[1].isdigit()):
        return "other"
    n = int(name[:2])
    return "base" if 1 <= n <= 8 else ("accent" if 9 <= n <= 12 else "other")


def _vanilla_family(model: str) -> str:
    if "/flora_bc_grass_" in model:
        return "bc"
    if "/flora_ash_grass_" in model:
        return "ash"
    if "/flora_bm_grass_" in model:
        return "sol"
    return "generic"


def _preferred_family(texture: str) -> str:
    i = texture.find("tx_")
    region = ""
    if i >= 0:
        end = texture.find("_", i + 3)
        if end > i + 3:
            region = texture[i + 3:end]
    if region == "bc":
        return "bc"
    if region in ("al", "rr", "rm"):
        return "ash"
    if region in ("sol", "bm"):
        return "sol"
    return "generic"


def choose_generic(models: list[str], texture: str, sel: int) -> str:
    base = [m for m in models if _stylized_role(m) == "base"]
    accent = [m for m in models if _stylized_role(m) == "accent"]
    if base or accent:
        want = base if base else accent
        if base and accent and sel % 100 >= 88:
            want = accent
        return want[(sel // 100) % len(want)]
    fam = _preferred_family(texture)
    match = [m for m in models if _vanilla_family(m) == fam]
    if match:
        return match[sel % len(match)]
    return models[sel % len(models)]


def reference_scale(profile: Optional[str], model: str, texture: str, r: float) -> float:
    if profile == "AI":
        if model.endswith("/rem_ai_grass_02.nif"):
            return f32(f32(1.24) + r * f32(0.26))
        if "grass" in texture and "dirt" in texture:
            return f32(1.0 + r * f32(0.34))
        return f32(f32(1.25) + r * f32(0.37))
    if profile == "AL":
        if model.endswith(("/rem_al_grass.nif", "/rem_al_grass_b.nif")):
            return f32(f32(1.35) + r * f32(0.30))
        if model.endswith("/rem_al_rock.nif"):
            return f32(1.0 + r * f32(0.25))
        return 1.0
    return f32(f32(0.8) + r * f32(0.35))


# --- generator --------------------------------------------------------------------------------------

@dataclass
class ForkFloraParams:
    density: float = 1.0
    exclusion_distance_m: float = 0.0
    models: list = field(default_factory=list)            # pula po filtrze VFS, w kolejności
    pool_source: str = ""

    def profiles(self) -> dict[str, bool]:
        return pool_profiles(self.models)

    def as_dict(self) -> dict:
        prof = self.profiles()
        return {"density": self.density, "exclusion_distance_m": self.exclusion_distance_m,
                "pool_source": self.pool_source, "pool_models": len(self.models),
                "active_profiles": [k for k, v in prof.items() if v],
                "regional_mode": any(prof.values()),
                "candidates_per_cell": {k or "generic": max(1, lround(f32(v * f32(self.density))))
                                        for k, v in CANDIDATES.items()},
                "seed_formula": "base = cellX·0x9e3779b9 ^ cellY·0x85ebca6b ^ index·0xc2b2ae35 (uint32); hash32/random01",
                "model_scale_note": "profile Remirosa: skala profilu modelu 1.0; modele spoza profili wymagają granic NIF (nieodwzorowane)"}


def _sample_profile_texture(land: LandIndex, cx: int, cy: int, needles: tuple[str, ...]) -> int:
    n = 0
    for ox in (0.2, 0.5, 0.8):
        for oy in (0.2, 0.5, 0.8):
            x = f32(f32(float(cx) + f32(ox)) * CELL)
            y = f32(f32(float(cy) + f32(oy)) * CELL)
            t = norm_path(land.texture_at(x, y, "fork"))
            if any(s in t for s in needles):
                n += 1
    return n


def cell_profile(land: LandIndex, params: ForkFloraParams, cx: int, cy: int) -> dict:
    """Który profil regionalny forka obsługuje komórkę (kolejność priorytetów jak w silniku)."""
    prof = params.profiles()
    region = land.regions.get((cx, cy))
    has_cell = (cx, cy) in land.cell_records
    flags = {"AI": False, "AL": False, "BC": False, "GL": False, "WG": False}
    via_fallback = []
    if has_cell:
        flags["AI"] = prof["AI"] and region == REGION_AI
        flags["BC"] = prof["BC"] and region == REGION_BC
        flags["WG"] = prof["WG"] and region == REGION_WG
        if prof["AL"]:
            flags["AL"] = region == REGION_AL or _sample_profile_texture(land, cx, cy, ("tx_al_", "tx_ashlands_")) >= 2
            if flags["AL"] and region != REGION_AL:
                via_fallback.append("AL")
        if prof["GL"]:
            flags["GL"] = region == REGION_GL or _sample_profile_texture(land, cx, cy, ("tx_gl_",)) >= 2
            if flags["GL"] and region != REGION_GL:
                via_fallback.append("GL")
    active = [k for k in ("AI", "AL", "BC", "GL", "WG") if flags[k]]
    regional = any(prof.values())
    return {"cell": [cx, cy], "region": region, "cell_record": has_cell, "profiles": active,
            "profiles_via_texture_fallback": via_fallback, "regional_mode": regional,
            "generates": (bool(active) or not regional) and bool(params.models)}


def generate_cell(land: LandIndex, params: ForkFloraParams, cx: int, cy: int,
                  bounds: Optional[tuple[float, float, float, float]] = None,
                  include_instances: bool = False) -> dict:
    """Instancje proceduralne jednej komórki. bounds = (x0, y0, x1, y1) w jednostkach świata — granice chunku
    (domyślnie cała komórka). Zwraca liczniki odrzuceń, modele, skale i (opcjonalnie) listę instancji."""
    cp = cell_profile(land, params, cx, cy)
    out = {"cell": [cx, cy], "region": cp["region"], "profiles": cp["profiles"],
           "profiles_via_texture_fallback": cp["profiles_via_texture_fallback"]}
    if not params.models or params.density <= 0.0:
        out.update({"generated": False, "reason": "brak puli modeli albo gęstość 0", "instances": 0})
        return out
    if cp["regional_mode"] and not cp["profiles"]:
        out.update({"generated": False, "instances": 0,
                    "reason": "tryb regionalnych profili Remirosa, a komórka nie należy do żadnego profilu"})
        return out
    flags = set(cp["profiles"])
    first = next((k for k in ("AI", "AL", "BC", "GL", "WG") if k in flags), None)
    n = max(1, lround(f32(CANDIDATES[first] * f32(params.density))))
    side = int(math.ceil(math.sqrt(f32(float(n)))))
    max_slope = 45.0 if flags & {"AI", "AL", "GL"} else 28.0
    if bounds is None:
        mnx, mny, mxx, mxy = float(cx), float(cy), float(cx + 1), float(cy + 1)
    else:
        mnx, mny, mxx, mxy = (f32(b / CELL) for b in bounds)
    rej = collections.Counter()
    by_model = collections.Counter()
    textures = collections.Counter()
    scales = []
    pathgrid_check = 0
    inst = []
    cxu, cyu = (cx & M32) * 0x9E3779B9 & M32, (cy & M32) * 0x85EBCA6B & M32
    fside = float(side)
    for index in range(n):
        base = cxu ^ cyu ^ ((index * 0xC2B2AE35) & M32)
        gx, gy = index % side, index // side
        nx = f32(f32(float(gx) + random01(base ^ 0x68BC21EB)) / fside)
        ny = f32(f32(float(gy) + random01(base ^ 0x02E5BE93)) / fside)
        px, py = f32(float(cx) + nx), f32(float(cy) + ny)
        if px < mnx or px >= mxx or py < mny or py >= mxy:
            rej["chunk_bounds"] += 1
            continue
        wx, wy = f32(px * CELL), f32(py * CELL)
        z = land.height_at(wx, wy)
        if z is None or z <= 1.0:
            rej["height_le_1"] += 1
            continue
        slope = land.slope_at(wx, wy)
        if slope is None or slope > max_slope:
            rej["slope"] += 1
            continue
        tex = norm_path(land.texture_at(wx, wy, "fork"))
        gw = generic_surface_weight(tex)
        w = ai_surface_weight(tex, gw) if "AI" in flags else (al_surface_weight(tex, gw) if "AL" in flags else gw)
        if w <= 0.0:
            rej["surface_weight_0"] += 1
            continue
        if w < 1.0 and random01(base ^ 0x4F1BBCDC) >= w:
            rej["surface_random_site"] += 1
            continue
        # klaster: rozmiar 1, promień 0 ⇒ ten sam punkt, ale osobne ziarno i drugie losowanie wagi
        cseed = hash32(base ^ 0x9E3779B9)
        if w < 1.0 and random01(cseed ^ 0x4F1BBCDC) >= w:
            rej["surface_random_cluster"] += 1
            continue
        if uses_pathgrid_exclusion(tex):
            pathgrid_check += 1
        sel = hash32(cseed ^ 0x91E10DA5)
        model = None
        for k, fn in (("AI", lambda: choose_ai(params.models, tex, sel)), ("AL", lambda: choose_al(params.models, sel)),
                      ("BC", lambda: choose_bc(params.models, sel)), ("GL", lambda: choose_gl(params.models, sel)),
                      ("WG", lambda: choose_wg(params.models, sel))):
            if k in flags:
                model = fn()
                if model:
                    break
        if model is None:
            model = choose_generic(params.models, tex, sel)
        scale_profile = "AI" if "AI" in flags else ("AL" if "AL" in flags else None)
        scale = reference_scale(scale_profile, model, tex, random01(cseed ^ 0x63D83595))
        by_model[model] += 1
        textures[tex] += 1
        scales.append(scale)
        if include_instances:
            inst.append({"x": wx, "y": wy, "z": z, "model": model, "scale": scale, "texture": tex,
                         "slope_deg": round(slope, 3), "rot_z": f32(random01(cseed ^ 0xA511E9B3) * f32(TWO_PI))})
    accepted = sum(by_model.values())
    out.update({"generated": True, "candidates": n, "grid_side": side, "max_slope_deg": max_slope,
                "instances": accepted, "rejected": dict(rej), "pathgrid_check_candidates": pathgrid_check,
                "by_model": dict(by_model.most_common()), "land_textures": dict(textures.most_common(10)),
                "scale": {"min": round(min(scales), 3), "max": round(max(scales), 3),
                          "mean": round(sum(scales) / len(scales), 3)} if scales else {},
                "upper_bound": True,
                "not_emulated": ["wykluczenia obiektów sceny (exclusion_distance, NIF)", "wykluczenia ścieżek PGRD"]})
    if include_instances:
        out["instance_list"] = inst
    return out


def generate_region(land: LandIndex, params: ForkFloraParams, x0: float, y0: float, x1: float, y1: float,
                    include_instances: bool = False) -> dict:
    """Instancje proceduralne w prostokącie świata — te same granice co gcbaseline.region_count."""
    if x1 <= x0 or y1 <= y0:
        raise ValueError("pusty prostokąt: wymagane x1 > x0 i y1 > y0")
    cxs = range(math.floor(x0 / CELL), math.floor((x1 - 1e-6) / CELL) + 1)
    cys = range(math.floor(y0 / CELL), math.floor((y1 - 1e-6) / CELL) + 1)
    if len(cxs) * len(cys) > 100:
        raise ValueError("obszar zbyt duży (limit 100 komórek)")
    total = 0
    per_cell = {}
    by_model = collections.Counter()
    inst = []
    for cx in cxs:
        for cy in cys:
            r = generate_cell(land, params, cx, cy, (x0, y0, x1, y1), include_instances)
            total += r["instances"]
            per_cell[f"{cx},{cy}"] = {"instances": r["instances"], "profiles": r["profiles"], "region": r["region"]}
            by_model.update(r.get("by_model", {}))
            inst.extend(r.get("instance_list", []))
    from .gcbaseline import UNITS_PER_METER
    area = ((x1 - x0) / UNITS_PER_METER) * ((y1 - y0) / UNITS_PER_METER)
    out = {"bounds": {"x0": x0, "y0": y0, "x1": x1, "y1": y1}, "instances": total,
           "per_m2": round(total / area, 4) if area else None, "per_cell": per_cell,
           "by_model": dict(by_model.most_common()), "upper_bound": True}
    if include_instances:
        out["instance_list"] = inst
    return out
