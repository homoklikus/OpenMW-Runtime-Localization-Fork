"""Plik animacji .kf (NiSequenceStreamHelper) → JSON biblioteki animacji dla Godota.

Struktura .kf w Morrowindzie: korzeń NiSequenceStreamHelper; łańcuch extra: NiTextKeyExtraData, a po nim
NiStringExtraData z nazwami węzłów; łańcuch kontrolerów: NiKeyframeController – i-ty kontroler animuje
węzeł o i-tej nazwie. Klucze tekstowe „Grupa: Start/Stop/Loop Start/Loop Stop” wyznaczają klipy.

Wynik (`*.anim.json`):
  {"format": "mwgodot-anim", "version": 1, "source": ..., "duration": s,
   "clips": {"idle": {"start": s, "stop": s, "loop_start": s|null, "loop_stop": s|null}, ...},
   "text_keys": [[t, "tekst"], ...],
   "tracks": [{"node": "Bip01 Spine", "rotation": {"times": [...], "values": [[x,y,z,w], ...]},
               "translation": {...}, "scale": {...}}]}
Wartości w układzie Godota (metry, Y w górę), interpolacja liniowa (krzywe Hermite/TBC próbkowane).
"""

from __future__ import annotations

import numpy as np

from .nif.reader import NifFile, controller_chain, extra_chain
from .nif2gltf import NifToGltf, Report, scene_time


def parse_text_keys(keys: list) -> tuple[dict, list]:
    clips: dict[str, dict] = {}
    flat = []
    for t, text in keys:
        for line in str(text).replace("\r", "\n").split("\n"):
            line = line.strip()
            if not line:
                continue
            flat.append([float(t), line])
            if ":" not in line:
                continue
            group, ev = (x.strip() for x in line.split(":", 1))
            g = clips.setdefault(group.lower(), {"start": None, "stop": None, "loop_start": None, "loop_stop": None})
            ev = ev.lower()
            if ev == "start":
                g["start"] = float(t)
            elif ev == "stop":
                g["stop"] = float(t)
            elif ev == "loop start":
                g["loop_start"] = float(t)
            elif ev == "loop stop":
                g["loop_stop"] = float(t)
    clips = {k: v for k, v in clips.items() if v["start"] is not None and v["stop"] is not None}
    return clips, flat


def _resample_cubic(times: np.ndarray, out: np.ndarray, ncomp: int) -> np.ndarray:
    return out.reshape(len(times), 3, ncomp)[:, 1, :]


def convert_kf(nif: NifFile, name: str) -> tuple[dict, Report]:
    rep = Report(model=name)
    root = nif.block(nif.roots[0]) if nif.roots else None
    if root is None or root.type != "NiSequenceStreamHelper":
        raise ValueError(f"{name}: korzeń nie jest NiSequenceStreamHelper")
    extras = extra_chain(nif, root.get("extra", -1))
    text = [e for e in extras if e.type == "NiTextKeyExtraData"]
    names = [e.get("string", "") for e in extras if e.type == "NiStringExtraData"]
    ctrls = [c for c in controller_chain(nif, root.get("controller", -1))]
    helper = NifToGltf(nif, name)
    helper.rep = rep
    tracks = []
    tmax = 0.0
    for i, c in enumerate(ctrls):
        if c.type != "NiKeyframeController":
            rep.note("unsupported", f"kontroler {c.type} w .kf – pominięty")
            continue
        if i >= len(names):
            rep.note("unsupported", "więcej kontrolerów niż nazw węzłów w .kf")
            break
        d = nif.block(c.get("data", -1))
        if d is None:
            continue
        tr = {"node": names[i]}
        for path, ts, vals, interp in helper._kf_tracks(d, root):
            if ts is None or len(ts) == 0:
                continue
            ncomp = 4 if path == "rotation" else 3
            v = np.asarray(vals, np.float64)
            if interp == "CUBICSPLINE":
                v = _resample_cubic(ts, v, ncomp)
                rep.note("lossy", "krzywe Hermite/TBC w .kf uproszczone do liniowych")
            ts2 = scene_time(np.asarray(ts, np.float64), c)
            tmax = max(tmax, float(ts2.max()))
            tr[path] = {"interp": "step" if interp == "STEP" else "linear",
                        "times": [round(float(t), 5) for t in ts2],
                        "values": [[round(float(x), 6) for x in row] for row in v.reshape(len(ts2), ncomp)]}
        if len(tr) > 1:
            tracks.append(tr)
    clips, flat = parse_text_keys(text[0]["keys"]) if text else ({}, [])
    rep.text_keys = flat
    rep.animations = len(clips)
    doc = {"format": "mwgodot-anim", "version": 1, "source": name, "duration": tmax,
           "clips": clips, "text_keys": flat, "tracks": tracks}
    return doc, rep
