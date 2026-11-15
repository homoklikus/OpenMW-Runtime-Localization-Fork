"""Weryfikacja, naprawa i czyszczenie katalogu wyników konwersji.

verify – sprawdza (szybko) obecność wyników zapisanych w cache, a w trybie --deep także ich strukturę
         (nagłówek GLB + JSON, sygnaturę PNG, poprawność JSON świata). Uszkodzone wpisy oznacza w cache
         jako „invalid”, więc kolejne `convert` je odtworzy (= naprawa). Uszkodzony eksport świata
         unieważnia stan eksportu.
clean  – znajduje pliki nieużywane (nieobecne w cache, pozostałości *.tmp) i usuwa je WYŁĄCZNIE z --yes.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

from .cache import Cache

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _check_png(b: bytes) -> str | None:
    """Sygnatura, sumy CRC wszystkich bloków i blok IEND (wykrywa pliki sklejone/ucięte)."""
    import zlib
    if b[:8] != PNG_SIG:
        return "zła sygnatura PNG"
    i = 8
    while i + 12 <= len(b):
        ln, typ = struct.unpack_from(">I4s", b, i)
        end = i + 12 + ln
        if end > len(b):
            return "ucięty PNG"
        crc, = struct.unpack_from(">I", b, i + 8 + ln)
        if zlib.crc32(b[i + 4:i + 8 + ln]) & 0xFFFFFFFF != crc:
            return f"błąd CRC bloku {typ.decode('latin-1')}"
        if typ == b"IEND":
            return None if end == len(b) else "dane po IEND"
        i = end
    return "brak bloku IEND"


def _check_file(p: Path, deep: bool) -> str | None:
    if not p.exists():
        return "brak pliku"
    if p.stat().st_size == 0:
        return "pusty plik"
    if not deep:
        return None
    try:
        if p.suffix == ".glb":
            with open(p, "rb") as fh:
                head = fh.read(20)
                magic, ver, total = struct.unpack_from("<III", head, 0)
                if magic != 0x46546C67 or ver != 2:
                    return "zły nagłówek GLB"
                if total != p.stat().st_size:
                    return "niezgodna długość GLB (ucięty plik?)"
                ln, typ = struct.unpack_from("<II", head, 12)
                json.loads(fh.read(ln).decode("utf-8"))
        elif p.suffix == ".png":
            prob = _check_png(p.read_bytes())
            if prob:
                return prob
        elif p.suffix == ".json":
            json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return f"uszkodzony: {type(e).__name__}"
    return None


def verify(out: Path, deep: bool = False, mark: bool = True) -> dict:
    out = Path(out)
    res = {"checked": 0, "bad": [], "world_ok": True, "world_problems": []}
    dbp = out / ".mwconv" / "cache.sqlite"
    if not dbp.exists():
        res["world_ok"] = False
        res["world_problems"].append("brak cache konwersji – konwersja nie była uruchamiana")
        return res
    cache = Cache(dbp)
    if cache.recovered_from:
        res["world_problems"].append(f"cache uszkodzony – odłożony jako {cache.recovered_from}")
    for e in cache.all():
        if e["status"] != "ok":
            continue
        for o in e["outputs"]:
            res["checked"] += 1
            prob = _check_file(out / o, deep)
            if prob:
                res["bad"].append({"kind": e["kind"], "key": e["key"], "file": o, "problem": prob})
                if mark:
                    cache.set_status(e["kind"], e["key"], "invalid", prob)
    cache.close()
    # świat
    for rel in ("world/manifest.json", "world/index.json", "world/objects.json"):
        prob = _check_file(out / rel, True)
        if prob:
            res["world_problems"].append(f"{rel}: {prob}")
    idx = out / "world" / "index.json"
    if idx.exists() and not res["world_problems"]:
        try:
            for c in json.loads(idx.read_text()).get("cells", []):
                prob = _check_file(out / "world" / c["file"], deep)
                if prob:
                    res["world_problems"].append(f"{c['file']}: {prob}")
        except Exception as e:  # noqa: BLE001
            res["world_problems"].append(f"index.json: {e}")
    state = out / ".mwconv" / "export_state.json"
    if not state.exists():
        res["world_problems"].append("eksport świata niekompletny (przerwana konwersja?)")
    if res["world_problems"]:
        res["world_ok"] = False
        if mark and state.exists():
            state.unlink()  # wymusza ponowny eksport świata przy naprawie
    res["ok"] = res["world_ok"] and not res["bad"]
    return res


def find_orphans(out: Path) -> list[str]:
    out = Path(out)
    dbp = out / ".mwconv" / "cache.sqlite"
    used: set[str] = set()
    if dbp.exists():
        cache = Cache(dbp)
        for e in cache.all():
            if e["status"] == "ok":
                used.update(e["outputs"])
        cache.close()
    orphans = []
    for sub in ("meshes", "textures"):
        base = out / sub
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_file():
                rel = p.relative_to(out).as_posix()
                if rel not in used or p.name.endswith(".tmp") or ".tmp." in p.name:
                    orphans.append(rel)
    baked = out / "baked" / "meshes"
    if baked.exists():
        for p in baked.rglob("*.scn"):
            glb = out / ("meshes" / p.relative_to(baked)).with_suffix(".glb")
            if not glb.exists():
                orphans.append(p.relative_to(out).as_posix())
    for p in out.rglob("*.tmp"):
        rel = p.relative_to(out).as_posix()
        if rel not in orphans:
            orphans.append(rel)
    return sorted(orphans)


def clean(out: Path, yes: bool = False) -> dict:
    orphans = find_orphans(out)
    freed = 0
    if yes:
        for rel in orphans:
            p = Path(out) / rel
            try:
                freed += p.stat().st_size
                p.unlink()
            except FileNotFoundError:
                pass
    return {"orphans": orphans, "deleted": yes, "freed_bytes": freed}
