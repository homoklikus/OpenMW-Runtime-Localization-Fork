"""Oficjalny Groundcover offline — emulacja apps/openmw/mwrender/groundcover.cpp (OpenMW 0.51.0), tylko odczyt.

* GroundcoverStore: statyki z plików groundcover= (później wczytany wygrywa), komórki zewnętrzne.
* collectInstances: dla komórki — referencje ze wszystkich plików w kolejności, mapa po RefNum
  (RefNum = indeks w pliku + plik ⇒ brak kolizji między plikami), DensityCalculator (float32) przed filtrem chunku.
* isInChunkBorders: przy chunku ≥ 1 komórki brak filtru pozycji; przy mniejszych filtr tylko na granicach
  wewnętrznych ⇒ suma po chunkach komórki = wszystkie referencje PRZYPISANE do CELL (również leżące poza nią).
"""

from __future__ import annotations

import collections
import math
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from .land import CELL, LandIndex, _records, _subs

UNITS_PER_METER = 69.99125109                     # components/misc/constants.hpp (Constants::UnitsPerMeter)


def _f32(x: float) -> float:
    return struct.unpack("<f", struct.pack("<f", x))[0]


class DensityCalculator:
    def __init__(self, density: float):
        self.density = _f32(density)
        self.cur = _f32(0.0)

    def reset(self):
        self.cur = _f32(0.0)

    def enabled(self) -> bool:
        if self.density >= 1.0:
            return True
        self.cur = _f32(self.cur + self.density)
        if self.cur < 1.0:
            return False
        self.cur = _f32(self.cur - 1.0)
        return True


@dataclass
class Ref:
    file: int
    refnum: int
    id: str
    x: float
    y: float
    z: float
    scale: float
    deleted: bool


@dataclass
class GroundcoverIndex:
    files: list[str] = field(default_factory=list)
    statics: dict = field(default_factory=dict)            # id -> model
    cells: dict = field(default_factory=dict)              # (x, y) -> [(file_idx, [Ref])]
    interiors: dict = field(default_factory=dict)          # nazwa -> liczba plików

    @classmethod
    def load(cls, files: list[Path]) -> "GroundcoverIndex":
        g = cls()
        for fi, path in enumerate(files):
            g.files.append(str(path))
            data = path.read_bytes()
            for t, start, size in _records(data):
                if t == b"STAT":
                    sid = model = None
                    for st, so, sn in _subs(data, start, size):
                        if st == b"NAME":
                            sid = data[so:so + sn].split(b"\0")[0].decode("latin-1").lower()
                        elif st == b"MODL":
                            model = data[so:so + sn].split(b"\0")[0].decode("latin-1")
                    if sid:
                        g.statics[sid] = model or ""
                elif t == b"CELL":
                    flags = gx = gy = None
                    name = ""
                    refs: list[Ref] = []
                    cur = None
                    for st, so, sn in _subs(data, start, size):
                        if st == b"NAME" and cur is None and not name:
                            name = data[so:so + sn].split(b"\0")[0].decode("latin-1")
                        elif st == b"DATA" and cur is None and gx is None and sn == 12:
                            flags, gx, gy = struct.unpack_from("<Iii", data, so)
                        elif st == b"FRMR":
                            cur = Ref(fi, struct.unpack_from("<I", data, so)[0], "", 0, 0, 0, 1.0, False)
                            refs.append(cur)
                        elif cur is not None and st == b"NAME":
                            cur.id = data[so:so + sn].split(b"\0")[0].decode("latin-1").lower()
                        elif cur is not None and st == b"XSCL":
                            cur.scale = struct.unpack_from("<f", data, so)[0]
                        elif cur is not None and st == b"DATA" and sn == 24:
                            cur.x, cur.y, cur.z = struct.unpack_from("<3f", data, so)
                        elif cur is not None and st == b"DELE":
                            cur.deleted = True
                    if flags is None:
                        continue
                    if flags & 1:
                        g.interiors[name.lower()] = g.interiors.get(name.lower(), 0) + 1
                    else:
                        g.cells.setdefault((gx, gy), []).append((fi, refs))
        return g

    def instances(self, cx: int, cy: int, density: float = 1.0) -> list[dict]:
        """Instancje renderowane dla komórki (wszystkie chunki razem), kolejność jak w OpenMW."""
        calc = DensityCalculator(density)
        calc.reset()
        refs: dict = {}
        for fi, lst in self.cells.get((cx, cy), []):
            for r in lst:
                key = (r.refnum, fi)
                deleted = r.deleted
                if not deleted and key not in refs and not calc.enabled():
                    deleted = True
                if deleted:
                    refs.pop(key, None)
                    continue
                refs[key] = r
        out = []
        for key in sorted(refs):
            r = refs[key]
            model = self.statics.get(r.id, "")
            if not model:
                continue
            out.append({"id": r.id, "model": model.replace("\\", "/").lower(), "file": Path(self.files[r.file]).name,
                        "x": r.x, "y": r.y, "z": r.z, "scale": r.scale})
        return out


def _slope_bin(s: Optional[float]) -> str:
    if s is None:
        return "brak LAND"
    for lim in (5, 10, 15, 20, 28, 35, 45, 60, 70):
        if s < lim:
            return f"<{lim}°"
    return "≥70°"


def baseline_cell(gc: GroundcoverIndex, land: Optional[LandIndex], cx: int, cy: int, density: float = 1.0,
                  include_instances: bool = False) -> dict:
    inst = gc.instances(cx, cy, density)
    inside = sum(1 for i in inst if cx * CELL <= i["x"] < (cx + 1) * CELL and cy * CELL <= i["y"] < (cy + 1) * CELL)
    area_m2 = (CELL / UNITS_PER_METER) ** 2
    res = {"cell": [cx, cy], "density": density, "instances": len(inst), "position_inside_cell": inside,
           "position_outside_cell": len(inst) - inside, "per_m2": round(len(inst) / area_m2, 4),
           "by_plugin": dict(collections.Counter(i["file"] for i in inst).most_common()),
           "by_model": dict(collections.Counter(i["model"] for i in inst).most_common()),
           "scale": _stats([i["scale"] for i in inst])}
    if land is not None:
        tf = collections.Counter(); tr = collections.Counter(); slopes = collections.Counter(); diff = 0
        for i in inst:
            a, b = land.texture_at(i["x"], i["y"], "fork"), land.texture_at(i["x"], i["y"], "render")
            tf[a] += 1; tr[b] += 1; diff += a != b
            slopes[_slope_bin(land.slope_at(i["x"], i["y"]))] += 1
            if include_instances:
                i["texture_fork"], i["texture_render"] = a, b
                i["slope_deg"] = land.slope_at(i["x"], i["y"])
        res.update({"land_texture_fork_mapping": dict(tf.most_common()),
                    "land_texture_render_mapping": dict(tr.most_common()),
                    "instances_where_mappings_differ": diff,
                    "slope_histogram": dict(sorted(slopes.items(), key=lambda kv: _bin_order(kv[0])))})
    if include_instances:
        res["instance_list"] = inst
    return res


def _bin_order(b: str) -> float:
    if b.startswith("<"):
        return float(b[1:-1])
    return 999.0 if b.startswith("≥") else 1000.0


def _stats(v: list[float]) -> dict:
    if not v:
        return {}
    return {"min": round(min(v), 3), "max": round(max(v), 3), "mean": round(sum(v) / len(v), 3)}


def texture_mapping_check(gc: GroundcoverIndex, land: LandIndex, max_refs: Optional[int] = None) -> dict:
    """Badanie hipotezy przesunięcia tekstur: rozkład tekstur LAND pod referencjami każdego modelu w trybach
    'fork' (floor(local·16)) i 'render' (wyprowadzony z renderera). Wyższa koncentracja (udział najczęstszej
    tekstury) wskazuje mapowanie bliższe temu, względem którego autor rozmieszczał roślinność."""
    per = collections.defaultdict(lambda: {"fork": collections.Counter(), "render": collections.Counter()})
    n = 0
    differ = 0
    all_refs = (r for lst in gc.cells.values() for _, refs in lst for r in refs if not r.deleted)
    for r in all_refs:
        model = gc.statics.get(r.id, "")
        a, b = land.texture_at(r.x, r.y, "fork"), land.texture_at(r.x, r.y, "render")
        per[model]["fork"][a] += 1
        per[model]["render"][b] += 1
        differ += a != b
        n += 1
        if max_refs and n >= max_refs:
            break
    models = []
    tot = {"fork": 0, "render": 0}
    for m, d in per.items():
        cnt = sum(d["fork"].values())
        row = {"model": m, "refs": cnt}
        for mode in ("fork", "render"):
            top, c = d[mode].most_common(1)[0]
            row[f"top_{mode}"] = top
            row[f"top_share_{mode}"] = round(c / cnt, 4)
            tot[mode] += c
        models.append(row)
    models.sort(key=lambda r: -r["refs"])
    return {"refs": n, "refs_where_mappings_differ": differ,
            "weighted_top_share": {k: round(v / n, 4) if n else None for k, v in tot.items()},
            "models": models,
            "interpretation": "większy weighted_top_share = mapowanie zgodniejsze z rozmieszczeniem autora pluginów"}


def height_offset_check(gc: GroundcoverIndex, land: LandIndex, per_cell: int = 40) -> dict:
    """Różnica z referencji − wysokość terenu (triangulacja forka) w punkcie referencji, osobno dla każdego pliku.
    Stała wartość dodatnia oznacza, że autor umieszczał punkt wstawienia modelu nad terenem (przesunięcie modelu),
    a nie losowe odchylenia — wartość potrzebna do kalibracji wysokości proceduralnej flory."""
    per = collections.defaultdict(list)
    for lst in gc.cells.values():
        for fi, refs in lst:
            for r in refs[:per_cell] if per_cell else refs:
                if r.deleted:
                    continue
                h = land.height_at(r.x, r.y)
                if h is not None:
                    per[Path(gc.files[fi]).name].append(r.z - h)
    out = {}
    for name, d in per.items():
        s = sorted(d)
        a = sorted(abs(x) for x in d)
        out[name] = {"samples": len(d), "median_dz": round(s[len(s) // 2], 2),
                     "p10_dz": round(s[int(len(s) * 0.1)], 2), "p90_dz": round(s[int(len(s) * 0.9)], 2),
                     "median_abs_dz": round(a[len(a) // 2], 2)}
    return {"per_plugin": out, "per_cell_sample": per_cell}


def region_count(gc: GroundcoverIndex, x0: float, y0: float, x1: float, y1: float, density: float = 1.0,
                 include_instances: bool = False) -> dict:
    """Instancje oficjalnego Groundcover, których POZYCJA leży w prostokącie [x0, x1) × [y0, y1) jednostek świata.
    Uwzględnia referencje przypisane do sąsiednich komórek (silnik rysuje je w ich komórkach, ale leżą w obszarze).
    Te same granice można potem zastosować do instancji proceduralnych forka — porównanie „w identycznym obszarze”."""
    if x1 <= x0 or y1 <= y0:
        raise ValueError("pusty prostokąt: wymagane x1 > x0 i y1 > y0")
    cx0, cx1 = math.floor(x0 / CELL) - 1, math.floor((x1 - 1e-6) / CELL) + 1
    cy0, cy1 = math.floor(y0 / CELL) - 1, math.floor((y1 - 1e-6) / CELL) + 1
    if (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > 400:
        raise ValueError("obszar zbyt duży (limit ok. 18×18 komórek)")
    hits = []
    per_cell = collections.Counter()
    for cx in range(cx0, cx1 + 1):
        for cy in range(cy0, cy1 + 1):
            for i in gc.instances(cx, cy, density):
                if x0 <= i["x"] < x1 and y0 <= i["y"] < y1:
                    i["assigned_cell"] = [cx, cy]
                    hits.append(i)
                    per_cell[f"{cx},{cy}"] += 1
    area_m2 = ((x1 - x0) / UNITS_PER_METER) * ((y1 - y0) / UNITS_PER_METER)
    out = {"bounds": {"x0": x0, "y0": y0, "x1": x1, "y1": y1}, "density": density, "instances": len(hits),
           "area_m2": round(area_m2, 1), "per_m2": round(len(hits) / area_m2, 4) if area_m2 else None,
           "by_assigned_cell": dict(per_cell.most_common()),
           "by_plugin": dict(collections.Counter(i["file"] for i in hits).most_common()),
           "by_model": dict(collections.Counter(i["model"] for i in hits).most_common())}
    if include_instances:
        out["instance_list"] = hits
    return out
