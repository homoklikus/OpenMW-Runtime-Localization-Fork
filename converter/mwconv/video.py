"""Filmy Morrowinda (Video/*.bik) → Ogg Theora + Vorbis (<out>/video/<nazwa>.ogv) – konwersja LOKALNA przez ffmpeg
gracza (dekoder Bink jest w ffmpeg; Godot odtwarza Theorę). Wyniki zostają w katalogu danych gracza – nie trafiają
do repozytorium ani wydań.

Ścieżka aktualizacji: <out>/video/index.json zapamiętuje rozmiar, czas modyfikacji i SHA-256 źródła oraz wersję
ustawień kodowania; film jest kodowany ponownie tylko, gdy źródło albo ustawienia się zmieniły, a wynik zniknął.
Błędy (brak ffmpeg, brak kodera Theora/Vorbis, uszkodzony plik, przerwanie) nie przerywają konwersji świata – są
zapisywane w raporcie i w index.json („error”), a gra pomija brakujący film (jak OpenMW, gdy pliku nie ma).
Zapis atomowy: kodowanie do pliku tymczasowego w tym samym katalogu, potem zamiana nazwy."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Callable, Optional

# Wersja ustawień kodowania: zmiana wymusza ponowne kodowanie filmów.
ENCODE_VERSION = 1
# Theora q 7 (0–10) i Vorbis q 5 – obraz bez widocznych bloków przy rozdzielczości filmów Morrowinda (640×480 / 800×600),
# dźwięk 44,1 kHz stereo; znaczniki czasu Binka przechodzą bez zmian (synchronizacja obrazu z dźwiękiem).
FFMPEG_ARGS = ["-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "5", "-ar", "44100", "-ac", "2",
               "-f", "ogg"]
TIMEOUT_S = 1800


def out_name(key: str) -> str:
    """'video/mw_intro.bik' → 'video/mw_intro.ogv' (małe litery jak klucze VFS)."""
    base, _ = os.path.splitext(key.lower())
    return base + ".ogv"


def find_ffmpeg() -> Optional[str]:
    return shutil.which("ffmpeg")


def _encoders(ffmpeg: str) -> set:
    try:
        p = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return set()
    names = set()
    for line in p.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and len(parts[0]) == 6:
            names.add(parts[1])
    return names


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_index(path: Path) -> dict:
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) and isinstance(d.get("videos"), dict) else {"videos": {}}
    except (OSError, ValueError):
        return {"videos": {}}


def _write_index(path: Path, idx: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(idx, indent=1, sort_keys=True), encoding="utf-8")
    os.replace(tmp, path)


def has_audio(ffmpeg: str, src: Path, runner=subprocess.run) -> bool:
    """Czy film ma ścieżkę dźwięku (WindowManager::playVideo wycisza inne dźwięki tylko wtedy)."""
    try:
        p = runner([ffmpeg, "-hide_banner", "-nostdin", "-i", str(src)], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return "Audio:" in (p.stderr or "")


def encode(ffmpeg: str, src: Path, dst: Path, runner=subprocess.run) -> str:
    """Koduje jeden film; zwraca "" albo opis błędu. Argumenty przekazywane listą (bez powłoki)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(f".{dst.stem}.{os.getpid()}.tmp.ogv")
    cmd = [ffmpeg, "-hide_banner", "-nostdin", "-y", "-v", "error", "-i", str(src), *FFMPEG_ARGS, str(tmp)]
    try:
        p = runner(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        tmp.unlink(missing_ok=True)
        return f"przekroczono czas kodowania ({TIMEOUT_S} s)"
    except OSError as e:
        tmp.unlink(missing_ok=True)
        return f"nie można uruchomić ffmpeg: {e}"
    if p.returncode != 0 or not tmp.is_file() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        msg = (p.stderr or "").strip().splitlines()
        return "ffmpeg: " + (msg[-1][:300] if msg else f"kod {p.returncode}")
    os.replace(tmp, dst)
    return ""


def convert_all(vfs, out: Path, log: Callable[[str], None] = print, emit: Optional[Callable] = None,
                ffmpeg: Optional[str] = None, runner=subprocess.run, base_out: Optional[Path] = None) -> dict:
    """Wszystkie Video/*.bik z VFS → <out>/video/*.ogv. base_out: konwersja bazowa profilu – film aktualny tam
    (ten sam rozmiar i czas modyfikacji źródła) nie jest kodowany drugi raz; gra szuka filmów także w bazie."""
    out = Path(out)
    base_idx = _read_index(Path(base_out) / "video" / "index.json") if base_out else {"videos": {}}
    keys = sorted(k for k in vfs.list("video/") if k.lower().endswith(".bik"))
    res = {"found": len(keys), "encoded": 0, "unchanged": 0, "failed": [], "error": ""}
    if not keys:
        return res
    idx_path = out / "video" / "index.json"
    idx = _read_index(idx_path)
    ffmpeg = ffmpeg or find_ffmpeg()
    if not ffmpeg:
        res["error"] = "brak programu ffmpeg – filmy pominięte (zainstaluj ffmpeg i uruchom aktualizację)"
        log("Filmy: " + res["error"])
        idx["error"] = res["error"]
        _write_index(idx_path, idx)
        return res
    enc = _encoders(ffmpeg)
    missing = [e for e in ("libtheora", "libvorbis") if e not in enc]
    if missing:
        res["error"] = "ffmpeg bez koderów: " + ", ".join(missing) + " – filmy pominięte"
        log("Filmy: " + res["error"])
        idx["error"] = res["error"]
        _write_index(idx_path, idx)
        return res
    idx.pop("error", None)
    for n, key in enumerate(keys):
        info = vfs.info(key)
        if info is None:
            continue
        rel = out_name(key)
        dst = out / rel
        prev = idx["videos"].get(key, {})
        current = prev.get("encode_version") == ENCODE_VERSION and not prev.get("error") and dst.is_file()
        same_src = prev.get("size") == info.size and abs(float(prev.get("mtime", -1)) - info.mtime) < 1e-3
        if current and same_src:
            res["unchanged"] += 1
            continue
        bprev = base_idx["videos"].get(key, {})
        if base_out and bprev.get("encode_version") == ENCODE_VERSION and not bprev.get("error") \
                and bprev.get("size") == info.size and abs(float(bprev.get("mtime", -1)) - info.mtime) < 1e-3 \
                and (Path(base_out) / rel).is_file():
            res.setdefault("in_base", 0)
            res["in_base"] += 1
            continue
        tmp_src = None
        if info.kind == "dir":
            src = Path(info.real)
        else:                                   # film w archiwum BSA (mody) – kopia tymczasowa obok wyników
            tmp_src = out / "video" / f".src.{os.getpid()}.bik"
            tmp_src.parent.mkdir(parents=True, exist_ok=True)
            tmp_src.write_bytes(vfs.read(key))
            src = tmp_src
        try:
            sha = _sha256_file(src)
            if current and prev.get("sha256") == sha:
                prev.update(size=info.size, mtime=info.mtime)    # tylko dotknięty plik – bez kodowania
                res["unchanged"] += 1
                _write_index(idx_path, idx)
                continue
            if emit:
                emit("video", key=key, index=n + 1, total=len(keys))
            log(f"Filmy: kodowanie {key} ({n + 1}/{len(keys)})")
            err = encode(ffmpeg, src, dst, runner)
            audio = has_audio(ffmpeg, src, runner) if not err else False
        finally:
            if tmp_src is not None:
                tmp_src.unlink(missing_ok=True)
        entry = {"size": info.size, "mtime": info.mtime, "sha256": sha, "encode_version": ENCODE_VERSION,
                 "out": rel, "audio": audio}
        if err:
            entry["error"] = err
            res["failed"].append({"key": key, "error": err})
            log(f"Filmy: błąd {key}: {err}")
        else:
            res["encoded"] += 1
        idx["videos"][key] = entry
        _write_index(idx_path, idx)                               # postęp zachowany przy przerwaniu
    # wpisy filmów, których już nie ma w danych – plik wyniku zostaje do „clean”, wpis usuwamy
    for k in list(idx["videos"]):
        if k not in keys:
            del idx["videos"][k]
    idx["format"] = "mwgodot-video"
    idx["version"] = 1
    _write_index(idx_path, idx)
    if res["encoded"] or res["failed"]:
        log(f"Filmy: zakodowano {res['encoded']}, bez zmian {res['unchanged']}, błędy {len(res['failed'])}")
    return res
