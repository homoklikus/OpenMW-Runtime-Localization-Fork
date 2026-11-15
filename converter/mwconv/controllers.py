"""Opis kontrolerów NIF, których glTF nie wyraża bezpośrednio → `extras` czytane przez loader Godota.

Loader (godot/scripts/mw/mw_controllers.gd) buduje z tego ścieżki Animation (widoczność, przesuw UV,
alfa i kolor materiału, animacja tekstur) oraz systemy cząsteczek CPUParticles3D.
Czasy w sekundach, długości w metrach, kierunki w układzie Godota.
"""

from __future__ import annotations

import math

import numpy as np

from . import coords

CYCLE = {0: "loop", 1: "reverse", 2: "clamp"}
COLOR_TARGET = {0: "ambient", 1: "diffuse", 2: "specular", 3: "emissive"}


def timing(c) -> dict:
    fl = c.get("flags", 0)
    return {"frequency": float(c.get("frequency", 1.0)), "phase": float(c.get("phase", 0.0)),
            "start": float(c.get("start", 0.0)), "stop": float(c.get("stop", 0.0)),
            "cycle": CYCLE.get((fl >> 1) & 3, "loop"), "active": bool(fl & 8)}


def keys_json(g: dict, conv=None) -> dict | None:
    """KeyGroup → {interp, times, values}. Interpolacja kwadratowa/TBC uproszczona do liniowej."""
    if g is None or g.get("times") is None or len(g["times"]) == 0:
        return None
    vals = np.asarray(g["values"], dtype=np.float64)
    if conv is not None:
        vals = conv(vals)
    interp = "step" if g.get("interp") == 5 else "linear"
    return {"interp": interp, "times": [round(float(t), 6) for t in g["times"]],
            "values": [[round(float(x), 6) for x in np.atleast_1d(v)] for v in vals]}


def vis(c, data) -> dict | None:
    if data is None or not data.get("keys"):
        return None
    return {"type": "vis", **timing(c), "times": [float(t) for t, _ in data["keys"]],
            "values": [int(v) for _, v in data["keys"]]}


def uv(c, data) -> dict | None:
    if data is None:
        return None
    names = ("u_offset", "v_offset", "u_tiling", "v_tiling")
    out = {"type": "uv", **timing(c), "uv_set": int(c.get("uv_set", 0))}
    for n, g in zip(names, data.get("groups", [])):
        k = keys_json(g)
        if k:
            out[n] = k
    return out


def alpha(c, data) -> dict | None:
    k = keys_json(data.get("keys")) if data is not None else None
    return {"type": "alpha", **timing(c), "keys": k} if k else None


def mat_color(c, data) -> dict | None:
    k = keys_json(data.get("keys")) if data is not None else None
    if not k:
        return None
    return {"type": "color", **timing(c), "target": COLOR_TARGET[(c.get("flags", 0) >> 4) & 3], "keys": k}


def flip(c, uris: list) -> dict:
    return {"type": "flip", **timing(c), "slot": int(c.get("texture_slot", 0)), "delta": float(c.get("delta", 0.0)),
            "start_time": float(c.get("start_time", 0.0)), "textures": uris}


def sample_keys(g: dict, t: float, ncomp: int) -> np.ndarray:
    times = np.asarray(g["times"])
    vals = np.asarray(g["values"], dtype=np.float64).reshape(len(times), ncomp)
    if t <= times[0]:
        return vals[0]
    if t >= times[-1]:
        return vals[-1]
    i = int(np.searchsorted(times, t) - 1)
    x = (t - times[i]) / (times[i + 1] - times[i]) if times[i + 1] > times[i] else 0.0
    return vals[i] + (vals[i + 1] - vals[i]) * x


def path_track(c, path_data, percent_data, fps: float = 30.0):
    """NiPathController → próbkowana ścieżka translacji (czas → pozycja w układzie NIF rodzica)."""
    pk = path_data.get("keys") if path_data else None
    ck = percent_data.get("keys") if percent_data else None
    if not pk or pk.get("times") is None or not ck or ck.get("times") is None:
        return None
    t0, t1 = float(ck["times"][0]), float(ck["times"][-1])
    p0, p1 = float(pk["times"][0]), float(pk["times"][-1])
    n = max(2, int(math.ceil((t1 - t0) * fps)) + 1)
    ts = np.linspace(t0, t1, n)
    pos = []
    for t in ts:
        perc = float(sample_keys(ck, t, 1)[0])
        s = p0 + max(0.0, min(1.0, perc)) * (p1 - p0)
        pos.append(sample_keys(pk, s, 3))
    return ts, np.array(pos)


def particles(ctrl, node_block, emitter_name: str, texture_uri: str | None, blend: str, modifiers: list,
              color_keys: dict | None) -> dict:
    """Parametry emitera (NiParticleSystemController) → opis dla CPUParticles3D."""
    S = coords.SCALE
    vd, va = float(ctrl.get("vertical_direction", 0.0)), float(ctrl.get("vertical_angle", 0.0))
    hd = float(ctrl.get("horizontal_direction", 0.0))
    dir_mw = np.array([math.sin(vd) * math.cos(hd), math.sin(vd) * math.sin(hd), math.cos(vd)])
    rnd = [float(x) * S for x in ctrl.get("start_random", (0, 0, 0))]
    out = {
        **timing(ctrl),
        "emitter": emitter_name,
        "amount": int(max(1, ctrl.get("num_particles", 1))),
        "emit_rate": float(ctrl.get("emit_rate", 0.0)),
        "use_rate": bool(ctrl.get("emit_flags", 0) & 1),
        "emit_start": float(ctrl.get("emit_start", 0.0)),
        "emit_stop": float(ctrl.get("emit_stop", 0.0)),
        "lifetime": float(ctrl.get("lifetime", 1.0)),
        "lifetime_random": float(ctrl.get("lifetime_random", 0.0)),
        "speed": float(ctrl.get("speed", 0.0)) * S,
        "speed_random": float(ctrl.get("speed_random", 0.0)) * S,
        "direction": [float(x) for x in coords.dir_to_godot(dir_mw)],
        "spread_deg": math.degrees(va),
        "horizontal_angle_deg": math.degrees(float(ctrl.get("horizontal_angle", 0.0))),
        "size": float(ctrl.get("size", 1.0)) * S,
        "emission_box_extents": [abs(v) for v in coords.dir_to_godot(rnd)],
        "texture": texture_uri,
        "blend": blend,
        "color_keys": color_keys,
        "modifiers": modifiers,
    }
    return out


def modifier_json(m, nif) -> dict | None:
    t = m.type
    if t == "NiGravity":
        return {"type": "gravity", "force": float(m["force"]) * coords.SCALE * 100.0,  # przybliżenie skali siły
                "kind": "point" if m["type"] == 1 else "wind",
                "direction": [float(x) for x in coords.dir_to_godot(m["direction"])],
                "position": [float(x) for x in coords.pos_to_godot(m["position"])], "decay": float(m["decay"])}
    if t == "NiParticleGrowFade":
        return {"type": "growfade", "grow": float(m["grow"]), "fade": float(m["fade"])}
    if t == "NiParticleRotation":
        return {"type": "rotation", "speed": float(m["rotation_speed"])}
    if t == "NiParticleColorModifier":
        return {"type": "color"}
    if t in ("NiPlanarCollider", "NiSphericalCollider", "NiParticleBomb"):
        return {"type": t, "supported": False}
    return None
