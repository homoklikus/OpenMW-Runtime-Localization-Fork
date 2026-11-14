"""Porównania wizualne: uruchomienie silnika z ujęciami (Lua rlf_capture), zrzuty ekranu i porównanie obrazów.

Profile użytkownika pozostają nietknięte: każde uruchomienie dostaje własny katalog w Raporty/mcp/zrzuty/<run>/<profil>/
(cfg/ jako OSTATNI katalog konfiguracji — tam trafiają log, ustawienia i world.cfg; data/ ze skryptem Lua; userdata/).
Zrzut: akcja Screenshot silnika (F12, xdotool) — dokładny obraz z gry; gdy plik się nie pojawi, `import -window`.
Oba silniki pracują przez XWayland (SDL_VIDEODRIVER=x11; dla Flatpaka --socket=x11 tylko na czas uruchomienia).
"""

from __future__ import annotations

import datetime as dt
import json
import math
import os
import shutil
import subprocess
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Callable, Optional

from . import profiles
from .land import CELL, LandIndex

LUA_DIR = Path(__file__).resolve().parents[2] / "lua"
READY, SHOT, DONE = "RLF_CAPTURE READY ", "RLF_CAPTURE SHOT ", "RLF_CAPTURE DONE"
SETTINGS_OVERRIDES = {
    "Video": {"resolution x": "1920", "resolution y": "1080", "window mode": "2", "vsync mode": "0"},
    "General": {"screenshot format": "png"},
    "Camera": {"field of view": "60"},
}
COPY_USER_FILES = ("world.cfg", "shaders.yaml", "input_v3.xml")


@dataclass
class Shot:
    """yaw/pitch w konwencji API Lua openmw.camera (jak rot obiektu): yaw = kurs (0 = +Y, rośnie w stronę +X),
    pitch dodatni = w dół."""
    id: str
    cell: list
    camera: list
    player: list
    yaw: float
    pitch: float
    hour: float = 12.0
    weather: Optional[str] = "Clear"
    note: str = ""


def repeat_shots(shots: list[Shot], repeat: int = 1) -> list[Shot]:
    """Seria ujęć powtórzona `repeat` razy (kolejne przebiegi: id-r2, id-r3…). Drugi przebieg odwiedza te same
    miejsca przy już wczytanych zasobach — różnica między -r1 a -r2 wskazuje na opóźnione doładowanie."""
    if repeat < 1 or repeat > 5:
        raise ValueError("repeat musi być w zakresie 1–5")
    out = list(shots)
    for k in range(2, repeat + 1):
        out += [Shot(**{**s.__dict__, "id": f"{s.id}-r{k}"}) for s in shots]
    return out


def _lua_value(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(_lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {_lua_value(x)}" for k, x in v.items()) + " }"
    raise TypeError(f"nieobsługiwany typ w scenariuszu: {type(v)}")


def scenario_lua(shots: list[Shot], timing: dict) -> str:
    lines = ["-- Wygenerowano przez MCP-openMW (capture.py). Scenariusz ujęć porównawczych.", "return {"]
    for k in ("initialDelay", "settleSeconds", "renderSeconds", "captureSeconds", "fastTimeScale"):
        lines.append(f"    {k} = {_lua_value(float(timing[k]))},")
    lines.append("    shots = {")
    for s in shots:
        d = asdict(s)
        d.pop("note", None)
        lines.append("        " + _lua_value(d) + ",")
    lines += ["    },", "}", ""]
    return "\n".join(lines)


DEFAULT_TIMING = {"initialDelay": 6.0, "settleSeconds": 5.0, "renderSeconds": 5.0, "captureSeconds": 6.0,
                  "fastTimeScale": 3000.0}


# --- punkt widzenia ---------------------------------------------------------------------------------------

def _occlusion(land: LandIndex, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float,
               samples: int = 24, margin: float = 20.0) -> int:
    """Liczba punktów na odcinku kamera→cel (bez końców), w których teren wystaje ponad linię wzroku − margin.
    Wykrywa zbocze przed kamerą, które zasłania kadr (MCP 0.6.0: ujęcie (15,−9) z drugiego przebiegu)."""
    hidden = 0
    for i in range(1, samples):
        t = i / samples
        h = land.height_at(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        if h is not None and h > z0 + (z1 - z0) * t - margin:
            hidden += 1
    return hidden


def _view_blocked(land: LandIndex, camx: float, camy: float, camz: float, heading: float, distance: float,
                  target_z: float, half_fov_deg: float = 40.0, rays: int = 5) -> int:
    """_occlusion dla kilku promieni w poziomym polu widzenia (±half_fov_deg) z tym samym pochyleniem co oś kamery.
    Zbocze z boku kadru też go zasłania (drugi przebieg, (15,−9): skała w prawej połowie obrazu)."""
    total = 0
    for i in range(rays):
        a = heading + math.radians(-half_fov_deg + 2.0 * half_fov_deg * i / (rays - 1))
        total += _occlusion(land, camx, camy, camz, camx + math.sin(a) * distance, camy + math.cos(a) * distance,
                            target_z)
    return total


def viewpoint(land: LandIndex, cx: int, cy: int, target: Optional[tuple[float, float]] = None,
              distance: float = 700.0, eye: float = 128.0, hour: float = 12.0, weather: Optional[str] = "Clear",
              shot_id: Optional[str] = None, density: Optional[Callable[[float, float], float]] = None) -> Shot:
    """Kamera patrzy na `target` (domyślnie: najgęstszy teksel komórki wg `density`, inaczej środek komórki)
    z odległości `distance`, z kierunku (co 22,5°), w którym kamera stoi nad wodą, teren nie zasłania celu
    i kamera jest jak najniżej względem celu."""
    if target is None:
        best, tx, ty = -1.0, (cx + 0.5) * CELL, (cy + 0.5) * CELL
        if density is not None:
            for j in range(2, 14):
                for i in range(2, 14):
                    x, y = (cx + (i + 0.5) / 16) * CELL, (cy + (j + 0.5) / 16) * CELL
                    v = density(x, y)
                    if v > best:
                        best, tx, ty = v, x, y
        target = (tx, ty)
    tx, ty = target
    th = land.height_at(tx, ty) or 0.0
    best_dir = None
    for k in range(16):
        a = k * math.pi / 8
        dx, dy = math.sin(a), math.cos(a)                     # kurs 0 = +Y (północ), rośnie w stronę +X
        camx, camy = tx - dx * distance, ty - dy * distance
        h = land.height_at(camx, camy)
        if h is None or h <= 0:
            continue
        score = (th - h) * 3.0 if h < th else (h - th)    # kamera poniżej celu patrzy w zbocze — kara
        score += 500.0 * _view_blocked(land, camx, camy, h + eye, a, distance, th + 30.0)
        if best_dir is None or score < best_dir[0]:
            best_dir = (score, a, camx, camy, h)
    if best_dir is None:
        best_dir = (0.0, 0.0, tx, ty - distance, max(th, 0.0))
    _, heading, camx, camy, h = best_dir
    camz = h + eye
    down = max(math.atan2(camz - (th + 30.0), distance), 0.08)   # zawsze lekko w dół (trawa w kadrze)
    px, py = camx - math.sin(heading) * 250.0, camy - math.cos(heading) * 250.0
    # Konwencja API Lua (camerabindings.cpp: setYaw(v) → Camera::setYaw(−v), setPitch(v) → Camera::setPitch(−v);
    # Camera: setYaw(−rot[2]), setPitch(−rot[0])), czyli jak rot obiektu: yaw = kurs, pitch > 0 = w dół.
    # MCP 0.5.0–0.5.1 negował oba kąty drugi raz (kamera patrzyła lustrzanie względem osi Y i w górę).
    yaw, pitch = heading, down
    return Shot(id=shot_id or f"c{cx}_{cy}", cell=[cx, cy], camera=[round(camx, 1), round(camy, 1), round(camz, 1)],
                player=[round(px, 1), round(py, 1), round((land.height_at(px, py) or h) + 10.0, 1)],
                yaw=round(yaw, 5), pitch=round(pitch, 5), hour=hour, weather=weather,
                note=f"cel ({tx:.0f}, {ty:.0f}, {th:.0f}), odległość {distance:.0f}")


# --- przygotowanie uruchomienia ---------------------------------------------------------------------------

def _write_settings(path: Path, overrides: dict) -> None:
    out = []
    for sec, kv in overrides.items():
        out.append(f"[{sec}]")
        out += [f"{k} = {v}" for k, v in kv.items()]
        out.append("")
    path.write_text("\n".join(out), encoding="utf-8")


def prepare(env, profile: str, shots: list[Shot], run_dir: Path, timing: Optional[dict] = None,
            start_cell: str = "Balmora") -> dict:
    eff = profiles.effective(env, profile)
    prof = env.cfg["profiles"][profile]
    base = run_dir / profile
    cfg, data, ud = base / "cfg", base / "data", base / "userdata"
    for d in (cfg, data / "scripts/rlf_capture", ud / "data", ud / "screenshots"):
        d.mkdir(parents=True, exist_ok=True)
    shutil.copy2(LUA_DIR / "rlf_capture.omwscripts", data / "rlf_capture.omwscripts")
    for f in ("global.lua", "player.lua"):
        shutil.copy2(LUA_DIR / "scripts/rlf_capture" / f, data / "scripts/rlf_capture" / f)
    (data / "scripts/rlf_capture/scenario.lua").write_text(scenario_lua(shots, {**DEFAULT_TIMING, **(timing or {})}),
                                                           encoding="utf-8")
    (cfg / "openmw.cfg").write_text(f'data="{data}"\ncontent=rlf_capture.omwscripts\n', encoding="utf-8")
    _write_settings(cfg / "settings.cfg", SETTINGS_OVERRIDES)
    user_cfg = Path(eff["user_config_dir"])
    copied = []
    for name in COPY_USER_FILES:
        if (user_cfg / name).is_file():
            shutil.copy2(user_cfg / name, cfg / name)
            copied.append(name)
    common = ["--skip-menu", f"--start={start_cell}", "--no-sound", f"--user-data={ud}"]
    run_env = {"SDL_VIDEODRIVER": "x11"}
    if eff["target"] == "official":
        cli = prof.get("cli", {})
        cfgs = [str(env.p(c)) for c in cli.get("config", [])] + [str(cfg)]
        # fallback-x11 w uprawnieniach aplikacji ukrywa X11 w sesji Wayland mimo --socket=x11 — wyłączamy go
        # (i Wayland) tylko na czas tego uruchomienia; bez 'flatpak override'.
        cmd = ["flatpak", "run", "--nosocket=wayland", "--nosocket=fallback-x11", "--socket=x11",
               "--env=SDL_VIDEODRIVER=x11", "--command=openmw",
               env.target("official")["app_id"], "--replace=config"] + [f"--config={c}" for c in cfgs] + common
        if cli.get("data-local"):
            cmd.append(f"--data-local={env.p(cli['data-local'])}")
        cwd = str(base)
    else:
        bin_dir = env.p(prof["binary_dir"])
        dirs = [str(Path(d)) for d in eff["active_config_dirs"]] + [str(cfg)]
        cmd = [str(bin_dir / "openmw"), "--replace=config"] + [f"--config={d}" for d in dirs] + common
        cwd = str(bin_dir)
    plan = {"profile": profile, "target": eff["target"], "cmd": cmd, "cwd": cwd, "env": run_env,
            "run_dir": str(base), "log": str(cfg / "openmw.log"), "screenshots": str(ud / "screenshots"),
            "copied_user_files": copied, "shots": [asdict(s) for s in shots]}
    (base / "plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
    return plan


# --- uruchomienie i zrzuty --------------------------------------------------------------------------------

def _x(cmd: list[str], timeout: float = 10.0) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def find_window(timeout: float = 15.0) -> Optional[str]:
    end = time.time() + timeout
    while time.time() < end:
        r = _x(["xdotool", "search", "--onlyvisible", "--name", "^OpenMW"], 5)
        ids = [w for w in r.stdout.split() if w.strip()]
        if ids:
            return ids[-1]
        time.sleep(0.5)
    return None


def grab(window: Optional[str], shots_dir: Path, dest: Path, wait: float = 5.0) -> str:
    """F12 w oknie gry (zrzut silnika); gdy plik się nie pojawi — import -window. Zwraca użytą metodę."""
    before = set(shots_dir.glob("*"))
    if window:
        _x(["xdotool", "windowactivate", "--sync", window], 5)
        time.sleep(0.3)
        _x(["xdotool", "key", "--clearmodifiers", "F12"], 5)
        end = time.time() + wait
        while time.time() < end:
            new = [p for p in set(shots_dir.glob("*")) - before if p.stat().st_size > 0]
            if new:
                time.sleep(0.5)                                # dokończenie zapisu
                shutil.move(str(max(new, key=lambda p: p.stat().st_mtime)), dest)
                return "engine-F12"
            time.sleep(0.2)
        r = _x(["import", "-window", window, str(dest)], 15)
        if r.returncode == 0 and dest.is_file():
            return "import-window"
    return "failed"


def run(plan: dict, timeout: float = 300.0, popen=subprocess.Popen, grabber=grab, window_finder=find_window) -> dict:
    log = Path(plan["log"])
    if log.exists():
        log.unlink()
    base = Path(plan["run_dir"])
    out = open(base / "stdout.log", "w", encoding="utf-8")
    proc = popen(plan["cmd"], cwd=plan["cwd"], env={**os.environ, **plan["env"]}, stdout=out,
                 stderr=subprocess.STDOUT)
    results, seen, window, status = [], 0, None, "timeout"
    end = time.time() + timeout
    try:
        while time.time() < end:
            if log.is_file():
                lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
                for line in lines[seen:]:
                    if READY in line:
                        sid = line.split(READY, 1)[1].strip()
                        window = window or window_finder()
                        dest = base / f"shot-{sid}.png"
                        method = grabber(window, Path(plan["screenshots"]), dest)
                        results.append({"id": sid, "file": str(dest) if dest.is_file() else None, "method": method})
                    elif DONE in line:
                        status = "done"
                seen = len(lines)
            if status == "done" or proc.poll() is not None:
                if status != "done":
                    status = f"process exited ({proc.returncode})"
                break
            time.sleep(0.25)
    finally:
        if proc.poll() is None:
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.terminate()
        out.close()
    errors = []
    if log.is_file():
        errors = [l for l in log.read_text(encoding="utf-8", errors="replace").splitlines()
                  if " E] " in l or "RLF_CAPTURE WARN" in l or "Lua error" in l or "[E]" in l][:20]
    res = {"profile": plan["profile"], "status": status, "shots": results, "log": str(log), "errors": errors}
    (base / "result.json").write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    return res


def new_run_dir(env, label: str = "") -> Path:
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    d = env.p("Raporty/mcp/zrzuty") / (stamp + (f"-{label}" if label else ""))
    d.mkdir(parents=True, exist_ok=True)
    return d


# --- porównanie obrazów -----------------------------------------------------------------------------------

def _vegetation_ratio(img) -> float:
    """Udział pikseli „roślinnych” (zieleń/oliwka: G dominuje, umiarkowana jasność) w dolnych 2/3 obrazu."""
    w, h = img.size
    raw = img.crop((0, h // 3, w, h)).convert("RGB").resize((320, max(1, int(320 * (h * 2 / 3) / w)))).tobytes()
    n = len(raw) // 3
    veg = 0
    for i in range(0, n * 3, 3):
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        if g > r * 0.95 and g > b * 1.08 and 25 < g < 235:
            veg += 1
    return veg / max(n, 1)


def compare(a: Path, b: Path, out: Path, labels=("official", "fork")) -> dict:
    try:
        from PIL import Image, ImageChops, ImageDraw, ImageStat
    except ImportError:
        return {"error": "brak Pillow — zainstaluj: .venv/bin/pip install -e '.[capture]'"}
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ib = ib.resize(ia.size)
    diff = ImageChops.difference(ia, ib)
    stat = ImageStat.Stat(diff)
    w, h = ia.size
    sheet = Image.new("RGB", (w * 2, h + 40), (20, 20, 20))
    sheet.paste(ia, (0, 40))
    sheet.paste(ib, (w, 40))
    d = ImageDraw.Draw(sheet)
    d.text((10, 10), f"{labels[0]}: {a.name}", fill=(255, 255, 255))
    d.text((w + 10, 10), f"{labels[1]}: {b.name}", fill=(255, 255, 255))
    sheet.save(out)
    va, vb = _vegetation_ratio(ia), _vegetation_ratio(ib)
    return {"sheet": str(out), "size": [w, h], "mean_abs_diff_rgb": [round(x, 2) for x in stat.mean],
            "vegetation_ratio": {labels[0]: round(va, 4), labels[1]: round(vb, 4)},
            "vegetation_delta": round(vb - va, 4)}


# --- przebieg w tle: python -m openmw_mcp.capture <run_dir> ---------------------------------------------

def run_all(run_dir: Path, timeout: float = 300.0) -> dict:
    """Uruchamia kolejno plany z run_dir/*/plan.json (najpierw official, potem fork), potem porównuje pary."""
    plans = sorted((json.loads(p.read_text(encoding="utf-8")) for p in run_dir.glob("*/plan.json")),
                   key=lambda p: 0 if p["target"] == "official" else 1)
    progress = run_dir / "progress.json"
    done = {}
    for plan in plans:
        progress.write_text(json.dumps({"running": plan["profile"], "finished": list(done)}), encoding="utf-8")
        done[plan["profile"]] = run(plan, timeout)
    comparisons = []
    if len(plans) == 2:
        a, b = plans[0]["profile"], plans[1]["profile"]
        fa = {s["id"]: s["file"] for s in done[a]["shots"] if s["file"]}
        fb = {s["id"]: s["file"] for s in done[b]["shots"] if s["file"]}
        for sid in sorted(set(fa) & set(fb)):
            comparisons.append({"id": sid, **compare(Path(fa[sid]), Path(fb[sid]), run_dir / f"compare-{sid}.png",
                                                     labels=(a, b))})
    summary = {"run_dir": str(run_dir), "results": done, "comparisons": comparisons,
               "finished": dt.datetime.now().isoformat(timespec="seconds")}
    (run_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
    progress.write_text(json.dumps({"running": None, "finished": list(done)}), encoding="utf-8")
    return summary


def status(run_dir: Path) -> dict:
    out = {"run_dir": str(run_dir)}
    for name in ("progress.json", "summary.json"):
        p = run_dir / name
        if p.is_file():
            out[name.split(".")[0]] = json.loads(p.read_text(encoding="utf-8"))
    out["files"] = sorted(str(p.relative_to(run_dir)) for p in run_dir.rglob("*.png"))
    return out


if __name__ == "__main__":
    import sys
    rd = Path(sys.argv[1])
    print(json.dumps(run_all(rd, float(sys.argv[2]) if len(sys.argv) > 2 else 300.0), ensure_ascii=False, indent=1))
