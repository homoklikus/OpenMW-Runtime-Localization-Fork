"""Widoczność z kamery: promienie w polu widzenia vs teren, woda i trójkąty obiektów (bez osobnego silnika 3D).

Kamera jak w OpenMW: pionowe pole widzenia [Camera] field of view (MCP ustawia 60°), proporcje okna (16:9),
kąty w konwencji Lua `openmw.camera`: yaw = kurs (0 = +Y, rośnie ku +X), pitch > 0 = w dół.

Metody (deterministyczne):
* teren: marsz wzdłuż promienia co `step` j. po siatce wysokości (scene.HeightGrid) + bisekcja; woda: z = 0;
* obiekty: test promień–AABB, potem Möller–Trumbore na trójkątach rysowanych kształtów (nif.model_geometry);
* trójkąty z alpha test/blend (liście, szyby) liczone osobno — zasłaniają częściowo, obniżają pewność.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

import numpy as np

SKY, TERRAIN, WATER, OBJECT, OBJECT_ALPHA = 0, 1, 2, 3, 4
CLASS_NAMES = {SKY: "niebo/daleko", TERRAIN: "teren", WATER: "woda", OBJECT: "obiekt", OBJECT_ALPHA: "obiekt (alfa)"}


@dataclass
class Camera:
    x: float
    y: float
    z: float
    yaw: float
    pitch: float
    vfov_deg: float = 60.0
    aspect: float = 16 / 9

    def basis(self):
        h, p = self.yaw, self.pitch
        f = np.array([math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), -math.sin(p)])
        r = np.array([math.cos(h), -math.sin(h), 0.0])
        u = np.cross(r, f)
        return f, r, u

    @property
    def origin(self) -> np.ndarray:
        return np.array([self.x, self.y, self.z], dtype=np.float64)

    def rays(self, w: int = 64, h: int = 36) -> np.ndarray:
        f, r, u = self.basis()
        tv = math.tan(math.radians(self.vfov_deg) / 2)
        th = tv * self.aspect
        xs = (2 * (np.arange(w) + 0.5) / w - 1) * th
        ys = (1 - 2 * (np.arange(h) + 0.5) / h) * tv
        gx, gy = np.meshgrid(xs, ys)
        d = f[None, None, :] + gx[..., None] * r[None, None, :] + gy[..., None] * u[None, None, :]
        d /= np.linalg.norm(d, axis=-1, keepdims=True)
        return d.reshape(-1, 3)

    def project(self, pts: np.ndarray) -> np.ndarray:
        """Punkty świata → (u, v, głębokość); |u|,|v| ≤ 1 = w kadrze."""
        f, r, u = self.basis()
        d = pts - self.origin
        z = d @ f
        tv = math.tan(math.radians(self.vfov_deg) / 2)
        with np.errstate(divide="ignore", invalid="ignore"):
            px = (d @ r) / (z * tv * self.aspect)
            py = (d @ u) / (z * tv)
        return np.stack([px, py, z], axis=-1)


def terrain_hits(grid, origin: np.ndarray, dirs: np.ndarray, max_dist: float = 6000.0, step: float = 24.0):
    """Odległość do terenu lub wody dla każdego promienia (inf = brak). Zwraca (t, klasa)."""
    ts = np.arange(step, max_dist + step, step)
    n = len(dirs)
    t_hit = np.full(n, np.inf)
    cls = np.full(n, SKY, dtype=np.int64)
    chunk = max(1, 400_000 // len(ts))
    for a in range(0, n, chunk):
        d = dirs[a:a + chunk]
        p = origin[None, None, :] + d[:, None, :] * ts[None, :, None]
        hz = grid.height(p[..., 0], p[..., 1])
        below_land = np.nan_to_num(p[..., 2] - hz, nan=np.inf) <= 0
        below_water = p[..., 2] <= 0
        hit = below_land | below_water
        anyhit = hit.any(axis=1)
        rows = np.nonzero(anyhit)[0]
        if not len(rows):
            continue
        i = hit[rows].argmax(axis=1)
        lo = np.where(i > 0, ts[np.maximum(i - 1, 0)], 0.0)
        hi = ts[i]
        dd = d[rows]
        for _ in range(10):                      # bisekcja (wektorowo): teren albo woda, co pierwsze
            mid = (lo + hi) / 2
            q = origin + dd * mid[:, None]
            hq = grid.height(q[:, 0], q[:, 1])
            below = (np.nan_to_num(q[:, 2] - hq, nan=np.inf) <= 0) | (q[:, 2] <= 0)
            hi = np.where(below, mid, hi)
            lo = np.where(below, lo, mid)
        q = origin + dd * hi[:, None]
        hq = grid.height(q[:, 0], q[:, 1])
        land = ~np.isnan(hq) & (hq > 0) & (q[:, 2] <= hq + 1.0)
        t_hit[a + rows] = hi
        cls[a + rows] = np.where(land, TERRAIN, WATER)
    return t_hit, cls


def _ray_aabb(origin, dirs, lo, hi):
    with np.errstate(divide="ignore", invalid="ignore"):
        inv = 1.0 / dirs
        t1 = (lo - origin) * inv
        t2 = (hi - origin) * inv
    tmin = np.nanmax(np.minimum(t1, t2), axis=1)
    tmax = np.nanmin(np.maximum(t1, t2), axis=1)
    return (tmax >= np.maximum(tmin, 0)), np.maximum(tmin, 0)


def _moller_trumbore(origin, dirs, tris, eps=1e-9):
    """Jeden początek, (R,) kierunków × (T,3,3) trójkątów → najmniejsze t na promień i indeks trójkąta."""
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    pvec = np.cross(dirs[:, None, :], e2[None, :, :])                  # (R,T,3)
    det = np.einsum("tk,rtk->rt", e1, pvec)
    ok = np.abs(det) > eps
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    tvec = origin[None, :] - v0                                        # (T,3)
    u = np.einsum("tk,rtk->rt", tvec, pvec) * inv
    qvec = np.cross(tvec, e1)                                          # (T,3)
    v = (dirs @ qvec.T) * inv
    t = (e2 * qvec).sum(axis=1)[None, :] * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-3)
    t = np.where(hit, t, np.inf)
    idx = t.argmin(axis=1)
    return t[np.arange(len(dirs)), idx], idx


def object_hits(objs: list, origin: np.ndarray, dirs: np.ndarray, max_dist: float = 6000.0, budget: int = 1_500_000,
                opaque_only: bool = False):
    """Najbliższy obiekt na każdym promieniu: (t, indeks obiektu, czy alfa). opaque_only: pomija trójkąty z alfą."""
    n = len(dirs)
    best_t = np.full(n, np.inf)
    best_o = np.full(n, -1, dtype=np.int64)
    best_a = np.zeros(n, dtype=bool)
    for oi, so in enumerate(objs):
        if so.triangles is None or so.aabb is None:
            continue
        lo, hi = so.aabb
        if np.linalg.norm(np.clip(origin, lo, hi) - origin) > max_dist:
            continue
        cand, tmin = _ray_aabb(origin, dirs, lo, hi)
        cand &= tmin < best_t
        ridx = np.nonzero(cand)[0]
        if not len(ridx):
            continue
        tris, alpha = so.triangles, so.alpha
        if opaque_only:
            keep = alpha == 0
            tris, alpha = tris[keep], alpha[keep]
            if not len(tris):
                continue
        step = max(1, budget // max(len(ridx), 1))
        t_obj = np.full(len(ridx), np.inf)
        a_obj = np.zeros(len(ridx), dtype=bool)
        for s0 in range(0, len(tris), step):
            t, idx = _moller_trumbore(origin, dirs[ridx], tris[s0:s0 + step])
            better = t < t_obj
            t_obj[better] = t[better]
            a_obj[better] = alpha[s0 + idx[better]] > 0
        upd = t_obj < best_t[ridx]
        best_t[ridx[upd]] = t_obj[upd]
        best_o[ridx[upd]] = oi
        best_a[ridx[upd]] = a_obj[upd]
    return best_t, best_o, best_a


def frame(cam: Camera, grid, objs: list, w: int = 64, h: int = 36, max_dist: float = 6000.0) -> dict:
    """Klasyfikacja każdego promienia kadru."""
    o = cam.origin
    dirs = cam.rays(w, h)
    tt, tc = terrain_hits(grid, o, dirs, max_dist)
    ot, oo, oa = object_hits(objs, o, dirs, max_dist)
    use_obj = ot < tt
    cls = np.where(use_obj, np.where(oa, OBJECT_ALPHA, OBJECT), tc)
    dist = np.where(use_obj, ot, tt)
    hit_z = o[2] + dirs[:, 2] * np.where(np.isfinite(dist), dist, 0.0)
    out = {"w": w, "h": h, "class": cls.reshape(h, w), "dist": dist.reshape(h, w),
           "object": np.where(use_obj, oo, -1).reshape(h, w), "hit_z": hit_z.reshape(h, w),
           "camera_z": float(o[2])}
    if (cls == OBJECT_ALPHA).any():
        # wariant „alfa przepuszcza”: górna granica widoczności tego, co za liśćmi/kratami
        ot2, oo2, _ = object_hits(objs, o, dirs, max_dist, opaque_only=True)
        use2 = ot2 < tt
        out["class_alpha_transparent"] = np.where(use2, OBJECT, tc).reshape(h, w)
    else:
        out["class_alpha_transparent"] = out["class"]
    return out


def target_points(grid, tx: float, ty: float, radius: float = 300.0, n: int = 7, lift: float = 20.0) -> np.ndarray:
    xs = np.linspace(-radius, radius, n)
    gx, gy = np.meshgrid(xs, xs)
    keep = gx ** 2 + gy ** 2 <= radius ** 2 + 1e-6
    px, py = tx + gx[keep], ty + gy[keep]
    pz = grid.height(px, py)
    ok = ~np.isnan(pz) & (pz > 0)
    return np.stack([px[ok], py[ok], pz[ok] + lift], axis=-1)


def target_visibility(cam: Camera, grid, objs: list, pts: np.ndarray, margin: float = 8.0) -> dict:
    """Ile punktów obszaru celu jest w kadrze i nie jest zasłonięte (teren/obiekty); kto zasłania."""
    if not len(pts):
        return {"points": 0, "in_frame": 0, "visible": 0, "visible_fraction": 0.0, "blockers": {}}
    o = cam.origin
    proj = cam.project(pts)
    in_frame = (proj[:, 2] > 1) & (np.abs(proj[:, 0]) <= 1) & (np.abs(proj[:, 1]) <= 1)
    d = pts - o
    dist = np.linalg.norm(d, axis=1)
    dirs = d / dist[:, None]
    tt, _ = terrain_hits(grid, o, dirs, float(dist.max()) + 50)
    terrain_block = tt < dist - margin
    ot, oo, oa = object_hits(objs, o, dirs, float(dist.max()) + 50)
    obj_block = ot < dist - margin
    blockers: dict = {}
    for k in np.nonzero(in_frame & obj_block & ~terrain_block)[0]:
        lab = objs[oo[k]].label
        b = blockers.setdefault(lab, {"points": 0, "alpha": 0})
        b["points"] += 1
        b["alpha"] += int(oa[k])
    visible = in_frame & ~terrain_block & ~obj_block
    alpha_only = in_frame & ~terrain_block & obj_block & oa
    return {"points": int(len(pts)), "in_frame": int(in_frame.sum()), "visible": int(visible.sum()),
            "visible_fraction": round(float(visible.sum() / len(pts)), 3),
            "blocked_by_terrain": int((in_frame & terrain_block).sum()),
            "blocked_by_objects": int((in_frame & obj_block & ~terrain_block).sum()),
            "blocked_only_by_alpha": int(alpha_only.sum()),
            "blockers": dict(sorted(blockers.items(), key=lambda kv: -kv[1]["points"]))}


def frame_summary(fr: dict, objs: list, near: float = 200.0, eye: float = 128.0) -> dict:
    """near_occlusion_share: część kadru zasłonięta bliżej niż `near` przez obiekt albo teren wznoszący się
    powyżej połowy wysokości oczu (zwykły grunt u stóp kamery się nie liczy)."""
    cls, dist, obj = fr["class"], fr["dist"], fr["object"]
    total = cls.size
    shares = {CLASS_NAMES[c]: round(float((cls == c).sum() / total), 3) for c in CLASS_NAMES}
    rising = (cls == TERRAIN) & (fr["hit_z"] > fr["camera_z"] - eye * 0.5)
    near_block = round(float(((dist < near) & ((cls == OBJECT) | (cls == OBJECT_ALPHA) | rising)).sum()
                             / total), 3)
    occ: dict = {}
    for i in np.unique(obj[obj >= 0]):
        so = objs[int(i)]
        m = obj == i
        occ[so.label] = {"share": round(float(m.sum() / total), 3),
                         "min_dist": round(float(dist[m].min()), 0), "type": so.type}
    lower = cls[cls.shape[0] // 3:]
    return {"shares": shares, "near_occlusion_share": near_block,
            "lower_two_thirds_ground_share": round(float(((lower == TERRAIN)).sum() / lower.size), 3),
            "objects_in_frame": dict(sorted(occ.items(), key=lambda kv: -kv[1]["share"])[:12])}


def ascii_mask(fr: dict, cols: int = 64) -> list[str]:
    chars = {SKY: " ", TERRAIN: ".", WATER: "~", OBJECT: "#", OBJECT_ALPHA: "%"}
    cls = fr["class"]
    step = max(1, cls.shape[1] // cols)
    return ["".join(chars[int(c)] for c in row[::step]) for row in cls[::step * 2]]


def confidence(objs_in_view: list, frame_sum: dict, errors: int) -> dict:
    """Pewność oceny: obniżają ją modele nieodczytane, alfa, billboardy/animacje, obiekty dynamiczne."""
    score, notes = 1.0, []
    if errors:
        score -= min(0.4, 0.1 * errors)
        notes.append(f"{errors} obiektów bez geometrii (brak modelu lub błąd NIF)")
    alpha = frame_sum["shares"].get(CLASS_NAMES[OBJECT_ALPHA], 0.0)
    if alpha > 0.02:
        score -= min(0.2, alpha)
        notes.append(f"{alpha:.0%} kadru to geometria z alfą (liście, kraty) — zasłania częściowo")
    anim = [so.label for so in objs_in_view if so.geometry and (so.geometry.stats["billboard_shapes"]
                                                                or so.geometry.stats["animated_shapes"])]
    if anim:
        score -= 0.05
        notes.append(f"{len(anim)} obiektów z billboardem/animacją — kształt zależny od czasu/kamery")
    notes.append("pominięte: postacie, stworzenia, przedmioty, obiekty włączane skryptem, trawa, efekty pogody")
    return {"score": round(max(score, 0.0), 2), "notes": notes}


# --- wybór punktu obserwacji -------------------------------------------------------------------------------

def _inside_object(objs: list, p: np.ndarray, margin: float = 16.0) -> Optional[str]:
    for so in objs:
        if so.aabb is None or so.triangles is None:
            continue
        lo, hi = so.aabb
        if np.all(p >= lo - margin) and np.all(p <= hi + margin):
            # wewnątrz AABB: sprawdzamy, czy pionowy promień w górę przecina geometrię (dach, korona, nawis)
            t, _ = _moller_trumbore(p, np.array([[0.0, 0.0, 1.0]]), so.triangles)
            if np.isfinite(t[0]):
                return so.label
    return None


def score(tv: dict, fs: dict) -> float:
    """Ocena kadru (deterministyczna): widoczność obszaru celu, kara za bliskie zasłonięcia, obiekty, nadmiar nieba."""
    sh = fs["shares"]
    obj = sh[CLASS_NAMES[OBJECT]] + 0.5 * sh[CLASS_NAMES[OBJECT_ALPHA]]
    sky = sh[CLASS_NAMES[SKY]]
    return round(tv["visible_fraction"] - 0.6 * fs["near_occlusion_share"] - 0.4 * obj
                 - 0.3 * max(0.0, sky - 0.4) + 0.2 * fs["lower_two_thirds_ground_share"], 4)


def suggest(grid, objs: list, target: tuple, distances=(600.0, 800.0, 1000.0), eyes=(128.0,), headings: int = 16,
            keep: int = 6, w: int = 64, h: int = 36) -> dict:
    """Przegląd kandydatów (kurs × odległość × wysokość oczu): najpierw widoczność punktów celu (tanio),
    potem pełny kadr dla najlepszych. Zwraca najlepszy punkt, alternatywy i odrzucone kandydatury."""
    tx, ty = target
    th = float(grid.height(np.array([tx]), np.array([ty]))[0])
    if np.isnan(th):
        th = 0.0
    pts = target_points(grid, tx, ty)
    cands, rejected = [], {"woda/brak terenu": 0, "w obiekcie": 0}
    for d in distances:
        for k in range(headings):
            a = k * 2 * math.pi / headings
            camx, camy = tx - math.sin(a) * d, ty - math.cos(a) * d
            gh = float(grid.height(np.array([camx]), np.array([camy]))[0])
            if np.isnan(gh) or gh <= 0:
                rejected["woda/brak terenu"] += 1
                continue
            for eye in eyes:
                camz = gh + eye
                pitch = max(math.atan2(camz - (th + 30.0), d), 0.08)
                if _inside_object(objs, np.array([camx, camy, camz])):
                    rejected["w obiekcie"] += 1
                    continue
                cam = Camera(camx, camy, camz, a, pitch)
                tv = target_visibility(cam, grid, objs, pts)
                cands.append((tv["visible_fraction"], -pitch, -d, cam, tv))
    if not cands:
        return {"error": "brak kandydatów (woda, brak terenu albo kamera w obiektach)", "rejected": rejected}
    cands.sort(key=lambda c: (c[0], c[1], c[2]), reverse=True)
    full = []
    for vf, _, _, cam, tv in cands[:keep]:
        fr = frame(cam, grid, objs, w, h)
        fs = frame_summary(fr, objs)
        full.append({"camera": cam, "frame": fr, "summary": fs, "target": tv, "score": score(tv, fs)})
    full.sort(key=lambda r: r["score"], reverse=True)
    return {"best": full[0], "alternatives": full[1:], "candidates": len(cands), "rejected": rejected,
            "target": [tx, ty, th], "target_points": int(len(pts))}
