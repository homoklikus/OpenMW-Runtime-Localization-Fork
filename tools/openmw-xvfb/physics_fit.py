"""Dopasowanie prędkości początkowej skoku do klatek OpenMW (MWFRAME z przypadku z "framelog": true).

OpenMW przy niskim fps (Xvfb, 5–7 kl./s) wykonuje w jednej klatce kilka kroków fizyki 1/60 s
(PhysicsTaskScheduler::calculateStepConfig), a MovementSolver::move w każdym kroku po oderwaniu od ziemi
dodaje ruch klatki do bezwładności (velocity = movement + inertia). Wysokość skoku zależy więc od fps
i nie da się jej porównać bezpośrednio z Godotem (krok 1/60 s). Skrypt odtwarza ten schemat kroków
(wraz z interpolacją położenia) i szuka v0 (jednostki/s), które najlepiej odtwarza zapisane wysokości;
v0 jest wartością Npc::getJump, porównywalną z Godotem (mw_character.movement().jump).
Użycie: python3 physics_fit.py openmw.out [openmw.out…]
        python3 physics_fit.py --slowfall WIELKOŚĆ openmw.out – ustalona prędkość opadania (Powolne opadanie:
        mInertia.z *= 1 − 0,005 × wielkość w każdym kroku fizyki): model kroków OpenMW dla zapisanych dt
        (najlepsze max_steps) wobec pomiaru i wartość przy 60 Hz (krok Godota)."""
import re
import sys

G = 8.96 * 69.99125          # Constants::GravityUnits
H = 1.0 / 60.0               # domyślny krok fizyki


def frames(path):
    out = []
    for line in open(path, errors="replace"):
        m = re.search(r"MWFRAME (\S+) (\S+) (\S+) (\S+) (\S+)", line)
        if m:
            out.append((float(m.group(2)), float(m.group(5))))
    return out


def sim(fr, v0, jf, maxs, ground):
    z = prev = ground
    inert, on, acc, out = 0.0, True, 0.0, []
    for k, (dt, _) in enumerate(fr):
        acc += dt
        n, d = int(acc / H), H
        if n > maxs:
            n = maxs
            d = max(acc / (n + 1), H)
        acc -= n * d
        mz = v0 if k == jf else 0.0
        for _ in range(n):
            prev = z
            if mz > 0 and on:
                inert = vel = mz
            elif not on:
                vel = mz + inert
            else:
                vel = 0.0
            z += vel * d
            if z <= ground:
                z, on, inert = ground, True, 0.0
            else:
                on = False
                inert -= G * d
        out.append(prev + (z - prev) * min(max(acc / d, 0.0), 1.0) if n else z)
    return out


def fit(fr):
    ground = fr[0][1]
    obs = [z for _, z in fr]
    best = None
    rise = next((i for i, z in enumerate(obs) if z > ground + 1), None)
    if rise is None:
        return {"v0": 0, "peak": 0.0}
    for jf in (j for j in (rise - 2, rise - 1, rise) if j >= 0):
        for lag in (0, 1):
            for maxs in range(1, 11):
                for v in range(100, 1200):
                    o = sim(fr, float(v), jf, maxs, ground)
                    pred = o if lag == 0 else [ground] + o[:-1]
                    e = sum((a - b) ** 2 for a, b in zip(pred, obs))
                    if best is None or e < best[0]:
                        best = (e, v, jf, maxs, lag)
    e, v, jf, maxs, lag = best
    return {"v0": v, "frame": jf, "max_steps": maxs, "lag": lag, "rms": round((e / len(fr)) ** 0.5, 2),
            "peak": round(max(obs) - ground, 1)}


def slowfall_steady(dt, s, maxs, frames=300):
    """Średnie przesunięcie na klatkę w stanie ustalonym (kroki jak calculateStepConfig)."""
    acc, v, disp = 0.0, 0.0, []
    for _ in range(frames):
        acc += dt
        n, d = int(acc / H), H
        if n > maxs:
            n = maxs
            d = max(acc / (n + 1), H)
        acc -= n * d
        dz = 0.0
        for _ in range(n):
            dz += v * d
            v -= G * d
            if v < 0:
                v *= s
        disp.append(dz)
    return sum(disp[-50:]) / 50


def slowfall_report(path, mag):
    s = 1.0 - min(max(mag * 0.005, 0.0), 1.0)
    fr = [f for f in frames(path) if f[0] > 0]
    drops = [(fr[i][1] - fr[i + 1][1], fr[i + 1][0]) for i in range(len(fr) - 1)]
    steady = [(dz, dt) for dz, dt in drops if dz > 0.5]
    steady = steady[len(steady) // 3: -2] if len(steady) > 6 else steady   # bez rozbiegu i lądowania
    if not steady:
        return {"error": "brak opadania"}
    dt = sum(d for _, d in steady) / len(steady)
    obs = sum(z for z, _ in steady) / len(steady)
    best = min(range(1, 13), key=lambda m: abs(-slowfall_steady(dt, s, m) - obs))
    v60 = 0.0
    for _ in range(2000):
        v60 = (v60 - G * H) * s
    return {"dt": round(dt, 4), "drop_per_frame": round(obs, 2), "model_max_steps": best,
            "model_drop": round(-slowfall_steady(dt, s, best), 2), "v_omw": round(obs / dt, 1),
            "v_60hz": round(-v60, 1)}


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--slowfall":
        for p in sys.argv[3:]:
            print(p, slowfall_report(p, float(sys.argv[2])))
        sys.exit(0)
    for p in sys.argv[1:]:
        fr = [f for f in frames(p) if f[0] > 0]
        obs = [z for _, z in fr]
        if fr:
            r = next((i for i, z in enumerate(obs) if z > obs[0] + 1), 0)
            land = next((i for i in range(r + 1, len(obs)) if obs[i] <= obs[0] + 1), len(obs) - 1)
            fr = fr[max(0, r - 3):land + 2]
        print(p, fit(fr) if fr else "brak klatek MWFRAME")
