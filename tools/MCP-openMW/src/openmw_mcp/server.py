"""Serwer MCP (stdio) — etap 1: tylko odczyt. Jedyny zapis: manifest testu (openmw_manifest_write) i cache SHA-256."""

from __future__ import annotations

import collections
import functools
import os
import traceback
from pathlib import Path
from typing import Optional

try:                                   # mcp 2.x
    from mcp.server.mcpserver import MCPServer as _Server
except ImportError:                    # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

from . import environment, esp, fflora, flora, gcbaseline, land, manifest, mods, profiles, remirosrules
from .util import vfs_key

mcp = _Server(
    "openmw-rlf",
    instructions=(
        "Narzędzia tylko do odczytu dla dwóch silników: 'official' (OpenMW 0.51.0, Flatpak) i 'fork' "
        "(OpenMW RLF, gałąź 0.5-world). Profile: 'official-ref' i 'fork-test'. Zawsze rozróżniaj: oficjalny "
        "Groundcover z pluginów ESP, proceduralną florę forka i niezatwierdzony eksperyment Azura's Coast. "
        "Przed porównaniem wyników sprawdź etykietę manifestu i openmw_profile_diff."),
)

_ENV: Optional[environment.Env] = None


def env() -> environment.Env:
    global _ENV
    if _ENV is None:
        _ENV = environment.load_env()
    return _ENV


def tool(fn):
    @functools.wraps(fn)
    def wrapper(*a, **kw):
        try:
            return fn(*a, **kw)
        except (profiles.ProfileError, KeyError, FileNotFoundError, ValueError) as e:
            return {"error": str(e)}
        except Exception as e:  # noqa: BLE001 — zwracamy diagnostykę zamiast zrywać sesję MCP
            return {"error": f"{type(e).__name__}: {e}", "traceback": traceback.format_exc(limit=5)}
    return mcp.tool()(wrapper)


@tool
def openmw_env_status(hash_binaries: bool = True) -> dict:
    """Wykrywa obie instalacje: wersje, commity źródeł i repo, binarki (SHA-256, ELF build-id), stan eksperymentów."""
    from . import srcmanifest
    e = env()
    return {"mcp": srcmanifest.info(), "project_root": str(e.project_root), "config": str(e.config_path),
            "fork": environment.detect_fork(e, hash_binaries),
            "official": environment.detect_official(e, hash_binaries)}


@tool
def openmw_git_info(target: str) -> dict:
    """Stan Git repo celu ('fork' lub 'official'): HEAD, gałąź, tag, zmiany, upstream (bez fetch)."""
    e = env()
    return environment.git_info(e, e.p(e.target(target)["repo"]))


@tool
def openmw_list_profiles() -> dict:
    """Lista zdefiniowanych profili testowych i ich celów."""
    return {k: {"target": v["target"], "description": v.get("description", "")}
            for k, v in env().cfg.get("profiles", {}).items()}


def _strip_eff(eff: dict) -> dict:
    eff = dict(eff)
    eff["settings"] = {"files": eff["settings"]["files"], "user_overrides": eff["settings"]["user_overrides"]}
    return eff


@tool
def openmw_profile_effective(profile: str) -> dict:
    """Efektywna konfiguracja: łańcuch configów, kolejność data=, content=, groundcover=, archiwa, ustawienia, world.cfg, izolacja."""
    return _strip_eff(profiles.effective(env(), profile))


@tool
def openmw_setting(profile: str, section: str, key: str) -> dict:
    """Efektywna wartość ustawienia (defaults + settings.cfg wg kolejności OpenMW)."""
    from .cfgparse import setting
    eff = profiles.effective(env(), profile)
    return {"profile": profile, "section": section, "key": key,
            "value": setting(eff["settings"]["merged"], section, key),
            "user_override": setting(eff["settings"]["user_overrides"], section, key)}


@tool
def openmw_vfs_resolve(profile: str, path: str) -> dict:
    """Który katalog/archiwum dostarcza plik VFS (np. 'meshes/grass/rem_ac_grass_03.nif') i kto go nadpisuje."""
    e = env()
    idx = profiles.vfs_index(profiles.effective(e, profile))
    prov = idx["index"].get(vfs_key(path), [])
    for p in prov:
        if p["file"]:
            p["sha256"] = e.cache.sha256(Path(p["file"]))
    e.cache.save()
    return {"profile": profile, "path": vfs_key(path), "found": bool(prov),
            "winner": prov[-1] if prov else None, "providers_low_to_high": prov}


@tool
def openmw_vfs_overrides(profile: str, prefix: str = "", limit: int = 100, compare_bytes: bool = True) -> dict:
    """Ścieżki VFS dostarczane przez wiele warstw (kolejność nadpisywania, zwycięzca, czy bajty różne)."""
    e = env()
    idx = profiles.vfs_index(profiles.effective(e, profile))
    return {"layers": idx["layers"], "errors": idx["errors"],
            **mods.overrides(idx, prefix, limit, compare_bytes, e if compare_bytes else None)}


@tool
def openmw_vfs_compare(profile_a: str, profile_b: str, prefix: str = "meshes/grass/", limit: int = 100) -> dict:
    """Porównuje efektywne pliki pod prefiksem w dwóch profilach: brakujące i ta sama ścieżka z innym SHA-256."""
    return manifest.vfs_compare(env(), profile_a, profile_b, prefix, limit)


@tool
def openmw_mods_identify(profile: str, max_files_per_dir: Optional[int] = None) -> dict:
    """Odciski SHA-256 katalogów data= i identyfikacja wariantów (np. Remiros Core OpenMW + 01b) wg katalogów sum."""
    e = env()
    eff = profiles.effective(e, profile)
    dd = mods.data_dir_report(e, eff, True, True, max_files_per_dir)
    for d in dd:
        d.pop("_files", None)
    return {"profile": profile, "data_dirs": dd, "name_conflicts": mods.name_conflicts(dd)}


@tool
def openmw_mod_identify_dir(path: str) -> dict:
    """Identyfikuje wariant dowolnego katalogu moda (ścieżka względna do projektu lub bezwzględna)."""
    e = env()
    root = e.p(path)
    if not root.is_dir():
        return {"error": f"nie istnieje katalog: {root}"}
    m = mods.dir_manifest(e, root)
    return {"path": str(root), "file_count": m["file_count"], "fingerprint": m["fingerprint"],
            "identification": mods.identify(m["files"], mods.load_catalogs(e))}


@tool
def openmw_groundcover_mode(profile: str, pool: Optional[str] = None) -> dict:
    """Jaki mechanizm roślinności działa w profilu: oficjalne pluginy ESP / proceduralna flora forka / eksperyment.
    pool (fork): None = domyślna pula z run-flora-test.sh, 'ac' = RLF_FLORA_POOL=ac, 'none' = bez zmiennej,
    'list:a.nif,b.nif' = własna lista ścieżek VFS."""
    e = env()
    eff = profiles.effective(e, profile)
    exps = environment.detect_fork(e, False).get("experiments") if eff["target"] == "fork" else None
    pl, src = manifest.pool_for(e, profile, pool) if eff["target"] == "fork" else (None, "")
    vfs = profiles.vfs_index(eff) if eff["target"] == "fork" else None
    res = flora.classify(eff, eff["target"], vfs, pl, src, exps)
    if eff["target"] == "fork":
        st = _pach75_state()
        res["remiros_texture_rules"] = st
        if st["in_binary"] and res.get("procedural"):
            models = [m for m in (vfs or {}).get("index", {}) if m.startswith("meshes/grass/rem_")]
            res["procedural_profile"] = {"mode": "reguły tekstur Remirosa + mapa liczników ("
                                                 + ("pola 4×4 teksela i statyki, pach76)" if st.get(
                                                     "pach76_subtexel_counts_in_binary") else "na teksel, pach75)"),
                                         "remiros_models_in_vfs": len(models),
                                         "note": "stare profile regionalne usunięte; emulacja: openmw_remiros_compare"}
            res["mechanism"] = res["mechanism"].replace("proceduralna flora forka",
                                                        "proceduralna flora forka (trawa Remirosa, pach75)")
        elif st["in_source"] and not st["in_binary"]:
            res["notes"].append("pach75 jest w źródłach forka, ale binarka go nie zawiera — przebuduj fork")
    return res


@tool
def openmw_groundcover_stats(profile: str, cell_x: Optional[int] = None, cell_y: Optional[int] = None) -> dict:
    """Statystyka pluginów groundcover= (komórki, statyki, referencje) — porównywalna z 'Loaded N cells, M statics';
    opcjonalnie referencje w komórce (x,y)."""
    eff = profiles.effective(env(), profile)
    files = [Path(g["file"]) for g in eff["groundcover"] if g["file"]]
    out = esp.groundcover_stats(files)
    if cell_x is not None and cell_y is not None:
        out["cell"] = [esp.cell_references(f, (cell_x, cell_y)) for f in files]
    return out


@tool
def openmw_esp_info(profile: str, plugin: str) -> dict:
    """Nagłówek pluginu (mastery, autor, opis) i liczba rekordów wg typu."""
    eff = profiles.effective(env(), profile)
    for p in eff["content"] + eff["groundcover"]:
        if p["name"].lower() == plugin.lower() and p["file"]:
            return esp.esp_info(Path(p["file"]))
    return {"error": f"plugin {plugin} nie jest aktywny w profilu {profile} albo nie znaleziono pliku"}


@tool
def openmw_manifest_build(profile: str, hash_mods: bool = True, pool: Optional[str] = None) -> dict:
    """Buduje manifest testu (silnik, commit, binarka, konfiguracja, aktywne mody z SHA-256, flora) bez zapisu."""
    return manifest.build(env(), profile, hash_mods, pool)


@tool
def openmw_manifest_write(profile: str, name: Optional[str] = None, pool: Optional[str] = None) -> dict:
    """Buduje i zapisuje manifest testu do Raporty/mcp/manifesty/ (jedyna operacja zapisu w etapie 1)."""
    e = env()
    man = manifest.build(e, profile, True, pool)
    path = manifest.write(e, man, name)
    return {"written": str(path), "label": man["label"], "issues": man["issues"]}


@tool
def openmw_profile_diff(profile_a: str = "fork-test", profile_b: str = "official-ref", hash_mods: bool = True) -> dict:
    """Diagnostyka różnic dwóch profili: silnik, mody (po zawartości), pluginy (SHA-256), ustawienia, mechanizm flory."""
    e = env()
    return manifest.diff(manifest.build(e, profile_a, hash_mods), manifest.build(e, profile_b, hash_mods))


# --- etap 2: teren i oficjalny Groundcover offline ------------------------------------------------
_WORLD_CACHE: dict = {}


def _files_key(files):
    out = []
    for f in files:
        st = Path(f).stat()
        out.append((str(f), st.st_size, st.st_mtime_ns))
    return tuple(out)


def _land_index(profile: str) -> "land.LandIndex":
    eff = profiles.effective(env(), profile)
    files = [Path(c["file"]) for c in eff["content"] if c["file"]]
    key = ("land", _files_key(files))
    if key not in _WORLD_CACHE:
        _WORLD_CACHE[key] = land.LandIndex.load(files)
    return _WORLD_CACHE[key]


def _gc_index(profile: str) -> "gcbaseline.GroundcoverIndex":
    eff = profiles.effective(env(), profile)
    files = [Path(g["file"]) for g in eff["groundcover"] if g["file"]]
    key = ("gc", _files_key(files))
    if key not in _WORLD_CACHE:
        _WORLD_CACHE[key] = gcbaseline.GroundcoverIndex.load(files)
    return _WORLD_CACHE[key]


@tool
def openmw_land_cell(profile: str, cell_x: int, cell_y: int, texture_grid: bool = False) -> dict:
    """Teren komórki z content= profilu: plugin LAND (i nadpisania), wysokości, nachylenie (jak fork), tekstury LTEX.
    texture_grid=True dodaje siatkę 16×16 nazw tekstur (wiersz 0 = północ)."""
    li = _land_index(profile)
    s = li.cell_summary(cell_x, cell_y)
    if s is None:
        return {"error": f"brak LAND dla komórki ({cell_x},{cell_y}) w profilu {profile}"}
    if texture_grid:
        s["texture_grid"] = li.texture_grid(cell_x, cell_y)
    return s


@tool
def openmw_land_point(profile: str, x: float, y: float) -> dict:
    """Wysokość (triangulacja forka/OpenMW), nachylenie i tekstura LAND w punkcie świata (oba tryby mapowania)."""
    li = _land_index(profile)
    return {"x": x, "y": y, "cell": [int(x // land.CELL), int(y // land.CELL)], "height": li.height_at(x, y),
            "slope_deg": li.slope_at(x, y), "texture_fork": li.texture_at(x, y, "fork"),
            "texture_render_hypothesis": li.texture_at(x, y, "render")}


@tool
def openmw_groundcover_baseline(profile: str = "official-ref", cell_x: int = 15, cell_y: int = -9,
                                density: Optional[float] = None, include_instances: bool = False,
                                land_profile: Optional[str] = None) -> dict:
    """Offline emulacja oficjalnego Groundcover (groundcover.cpp 0.51.0) dla komórki: liczba instancji
    przy gęstości (domyślnie [Groundcover] density z profilu), podział na pliki/modele, skala, tekstury LAND
    i nachylenie pod instancjami. land_profile: profil, z którego brać teren (domyślnie ten sam)."""
    from .cfgparse import setting, _float
    eff = profiles.effective(env(), profile)
    if density is None:
        density = _float(setting(eff["settings"]["merged"], "Groundcover", "density"), 1.0)
    gc = _gc_index(profile)
    li = _land_index(land_profile or profile)
    out = gcbaseline.baseline_cell(gc, li, cell_x, cell_y, density, include_instances)
    out["engine_source"] = "apps/openmw/mwrender/groundcover.cpp (OpenMW 0.51.0) — emulacja, nie pomiar w silniku"
    return out


@tool
def openmw_groundcover_region(profile: str, x0: float, y0: float, x1: float, y1: float,
                              density: Optional[float] = None, include_instances: bool = False) -> dict:
    """Liczba instancji oficjalnego Groundcover, których pozycja leży w prostokącie [x0,x1)×[y0,y1) (jednostki świata,
    komórka = 8192), łącznie z referencjami przypisanymi do sąsiednich komórek. Gęstość domyślnie z profilu."""
    from .cfgparse import setting, _float
    if density is None:
        eff = profiles.effective(env(), profile)
        density = _float(setting(eff["settings"]["merged"], "Groundcover", "density"), 1.0)
    return gcbaseline.region_count(_gc_index(profile), x0, y0, x1, y1, density, include_instances)


@tool
def openmw_land_texture_mapping_check(profile: str = "official-ref", max_refs: Optional[int] = None) -> dict:
    """Test hipotezy przesunięcia tekstur LAND: koncentracja tekstur pod referencjami groundcover
    w mapowaniu forka vs wyprowadzonym z renderera."""
    return gcbaseline.texture_mapping_check(_gc_index(profile), _land_index(profile), max_refs)


@tool
def openmw_groundcover_height_offset(profile: str = "official-ref", per_cell: int = 40) -> dict:
    """Różnica wysokości referencji groundcover względem terenu (z − h) per plugin — kalibracja proceduralnej flory."""
    return gcbaseline.height_offset_check(_gc_index(profile), _land_index(profile), per_cell)


# --- etap 2c: proceduralna flora forka offline i porównanie z Remirosem ------------------------------
BUILTIN_VANILLA_POOL = [f"meshes/f/flora_grass_0{i}.nif" for i in range(1, 8)] + [
    "meshes/f/flora_bc_grass_01.nif", "meshes/f/flora_bc_grass_02.nif", "meshes/f/flora_ash_grass_b_01.nif",
    "meshes/f/flora_ash_grass_r_01.nif", "meshes/f/flora_ash_grass_w_01.nif"] + [
    f"meshes/f/flora_bm_grass_0{i}.nif" for i in range(1, 7)]


def _fork_params(profile: str, pool: Optional[str], density: Optional[float]) -> "fflora.ForkFloraParams":
    e = env()
    eff = profiles.effective(e, profile)
    if eff["target"] != "fork":
        raise ValueError(f"profil {profile} nie jest profilem forka")
    wf = (eff.get("world_cfg") or {}).get("flora") or {}
    raw, src = manifest.pool_for(e, profile, pool)
    vfs = profiles.vfs_index(eff)["index"]
    if raw:
        models = []
        for m in raw:
            k = vfs_key(m)
            if k in vfs and k not in models:
                models.append(k)
        if not models:
            raw, src = None, src + " — żaden model nie istnieje w VFS, silnik wraca do puli vanilla"
    if not raw:
        models = [m for m in BUILTIN_VANILLA_POOL if m in vfs]
        src = src or "pula wbudowana (vanilla)"
    return fflora.ForkFloraParams(density=float(density if density is not None else wf.get("density", 1.0)),
                                  exclusion_distance_m=float(wf.get("exclusion_distance", 0.0)),
                                  models=models, pool_source=src)


def _fork_world_status(profile: str) -> dict:
    eff = profiles.effective(env(), profile)
    wf = (eff.get("world_cfg") or {}).get("flora") or {}
    proc = bool(wf.get("enabled")) and wf.get("source") in ("automatic", "hybrid")
    return {"world_cfg_flora": wf, "procedural_enabled_in_profile": proc}


@tool
def openmw_fork_flora_cell(profile: str = "fork-test", cell_x: int = 0, cell_y: int = 0,
                           density: Optional[float] = None, pool: Optional[str] = None,
                           include_instances: bool = False) -> dict:
    """[Generator SPRZED pach75 — profile regionalne AI/AL/BC/GL/WG] Proceduralna flora forka w komórce — offline emulacja collectInstances (fork 0.5-world): profil
    regionalny, liczba kandydatów, odrzucenia (wysokość, nachylenie, waga powierzchni, losowania), modele, skale.
    Bez wykluczeń obiektów i ścieżek ⇒ górna granica. Gęstość domyślnie z world.cfg [Flora]."""
    params = _fork_params(profile, pool, density)
    out = fflora.generate_cell(_land_index(profile), params, cell_x, cell_y, None, include_instances)
    out["generator"] = params.as_dict()
    out.update(_fork_world_status(profile))
    return out


@tool
def openmw_fork_flora_region(profile: str, x0: float, y0: float, x1: float, y1: float,
                             density: Optional[float] = None, pool: Optional[str] = None,
                             include_instances: bool = False) -> dict:
    """[Generator SPRZED pach75] Proceduralna flora forka w prostokącie świata [x0,x1)×[y0,y1) (te same granice co openmw_groundcover_region)."""
    params = _fork_params(profile, pool, density)
    out = fflora.generate_region(_land_index(profile), params, x0, y0, x1, y1, include_instances)
    out["generator"] = params.as_dict()
    return out


def _remiros_cell_plugins(gc, cx: int, cy: int) -> dict:
    out = {}
    for fi, refs in gc.cells.get((cx, cy), []):
        out[Path(gc.files[fi]).name] = sum(1 for r in refs if not r.deleted)
    return out


@tool
def openmw_flora_compare(cell_x: int, cell_y: int, fork_profile: str = "fork-test",
                         official_profile: str = "official-ref", density_fork: Optional[float] = None,
                         density_official: Optional[float] = None, pool: Optional[str] = None) -> dict:
    """[Generator SPRZED pach75; po pach75: openmw_remiros_compare] Komórka obok siebie: oficjalny Groundcover (Remiros, pozycje w granicach komórki) i proceduralna flora forka
    (emulacja, górna granica) — region, profil forka, pluginy Remirosa pokrywające komórkę, liczby, gęstość na m², modele."""
    from .cfgparse import setting, _float
    x0, y0 = cell_x * land.CELL, cell_y * land.CELL
    if density_official is None:
        eff = profiles.effective(env(), official_profile)
        density_official = _float(setting(eff["settings"]["merged"], "Groundcover", "density"), 1.0)
    gc = _gc_index(official_profile)
    off = gcbaseline.region_count(gc, x0, y0, x0 + land.CELL, y0 + land.CELL, density_official)
    params = _fork_params(fork_profile, pool, density_fork)
    fk = fflora.generate_cell(_land_index(fork_profile), params, cell_x, cell_y)
    ratio = round(fk["instances"] / off["instances"], 3) if off["instances"] else None
    return {"cell": [cell_x, cell_y], "region": fk.get("region"),
            "fork_profiles": fk.get("profiles"), "fork_generates": fk.get("generated"),
            "fork_reason": fk.get("reason"), "remiros_plugins_assigned": _remiros_cell_plugins(gc, cell_x, cell_y),
            "official": {"instances": off["instances"], "per_m2": off["per_m2"], "density": density_official,
                         "by_plugin": off["by_plugin"], "by_model": off["by_model"],
                         "by_assigned_cell": off["by_assigned_cell"]},
            "fork": {k: fk.get(k) for k in ("instances", "candidates", "rejected", "pathgrid_check_candidates",
                                             "by_model", "scale", "max_slope_deg")},
            "fork_per_m2": round(fk["instances"] / off["area_m2"], 4) if off["area_m2"] else None,
            "ratio_fork_to_official": ratio, "generator": params.as_dict(),
            "caveats": ["fork: emulacja bez wykluczeń obiektów i ścieżek (górna granica)",
                        "official: emulacja groundcover.cpp 0.51.0; pozycje w granicach komórki, także z sąsiednich CELL"]}


@tool
def openmw_flora_coverage(fork_profile: str = "fork-test", official_profile: str = "official-ref",
                          density_official: Optional[float] = None, top: int = 15) -> dict:
    """Pokrycie świata: dla każdej komórki z referencjami Remirosa — region, czy fork ma dla niej profil;
    sumy instancji oficjalnego Groundcover w komórkach obsługiwanych i nieobsługiwanych przez fork."""
    from .cfgparse import setting, _float
    if density_official is None:
        eff = profiles.effective(env(), official_profile)
        density_official = _float(setting(eff["settings"]["merged"], "Groundcover", "density"), 1.0)
    gc = _gc_index(official_profile)
    li = _land_index(fork_profile)
    params = _fork_params(fork_profile, None, None)
    by_region = collections.defaultdict(lambda: {"cells": 0, "official_instances": 0, "fork_cells_with_profile": 0})
    missing = []
    tot = {"cells": 0, "official_instances": 0, "covered_cells": 0, "covered_instances": 0}
    for (cx, cy) in sorted(gc.cells):
        n = len(gc.instances(cx, cy, density_official))
        cp = fflora.cell_profile(li, params, cx, cy)
        reg = cp["region"] or ("(brak CELL)" if not cp["cell_record"] else "(brak regionu)")
        b = by_region[reg]
        b["cells"] += 1; b["official_instances"] += n
        tot["cells"] += 1; tot["official_instances"] += n
        if cp["generates"]:
            b["fork_cells_with_profile"] += 1
            tot["covered_cells"] += 1; tot["covered_instances"] += n
        else:
            missing.append({"cell": [cx, cy], "region": reg, "official_instances": n,
                            "plugins": _remiros_cell_plugins(gc, cx, cy)})
    missing.sort(key=lambda m: -m["official_instances"])
    return {"totals": tot, "by_region": dict(sorted(by_region.items(), key=lambda kv: -kv[1]["official_instances"])),
            "uncovered_cells": len(missing), "uncovered_official_instances": sum(m["official_instances"] for m in missing),
            "top_uncovered": missing[:top], "generator": params.as_dict(), "density_official": density_official,
            "note": "komórki zewnętrzne z pluginów groundcover=; 'pokryta' = fork generuje tam florę (profil regionalny)"}


# --- etap 2c: trawa Remirosa w forku (reguły tekstur + liczniki, pach75) --------------------------------
PACH75_MARKER = b"Remiros texture rules (pach75)"
PACH76_MARKER = b"sub-texel, per static, pach76"


def _pach75_state() -> dict:
    e = env()
    t = e.target("fork")
    repo = e.p(t["repo"])
    binary = e.p(t["binary"])
    in_source = bool(repo) and (repo / "apps/openmw/mwrender/remirosgroundcover.cpp").is_file()
    in_binary = pach76 = False
    if binary and binary.is_file():
        import mmap
        with open(binary, "rb") as fh, mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            in_binary = mm.find(PACH75_MARKER) >= 0
            pach76 = mm.find(PACH76_MARKER) >= 0
    out = {"in_source": in_source, "in_binary": in_binary}
    if pach76:
        out["pach76_subtexel_counts_in_binary"] = True     # liczniki per pole 4×4 teksela i statyka
    return out


def _remiros_model(official_profile: str, land_profile: str, with_counts: bool = True):
    key = ("remiros", official_profile, land_profile, with_counts,
           _files_key([Path(g["file"]) for g in profiles.effective(env(), official_profile)["groundcover"] if g["file"]]))
    if key not in _WORLD_CACHE:
        gc, li = _gc_index(official_profile), _land_index(land_profile)
        rules = remirosrules.derive(gc, li)
        counts = remirosrules.build_counts(gc, li, rules) if with_counts else None
        _WORLD_CACHE[key] = (rules, counts, remirosrules.Model(rules, counts))
    return _WORLD_CACHE[key]


@tool
def openmw_remiros_rules(official_profile: str = "official-ref", land_profile: str = "fork-test",
                         texture: Optional[str] = None, top: int = 40) -> dict:
    """Reguły Remirosa wyliczone z pluginów groundcover=: tekstura LAND → gęstość na teksel, statyki (model, udział,
    zakres skali, wysokość nad terenem), pluginy. Plus statystyka mapy liczników. Bez współrzędnych roślin."""
    rules, counts, _ = _remiros_model(official_profile, land_profile)
    rows = [r for r in rules["rules"] if texture is None or r["texture"] == remirosrules.texture_key(texture)]
    return {"textures": rules["textures"], "statics": rules["statics"], "refs": rules["refs"],
            "constants": rules["constants"], "source_plugins": rules["source_plugins"],
            "counts": {"cells": len(counts["cells"]), "entries": counts["entries"], "groups": counts.get("groups"),
                       "refs": counts["refs"], "sub_texel_grid": counts.get("sub")},
            "rules": rows[:top]}


@tool
def openmw_remiros_compare(cell_x: int, cell_y: int, official_profile: str = "official-ref",
                           land_profile: str = "fork-test", density: float = 1.0, use_counts: bool = True) -> dict:
    """Komórka: Remiros (oficjalny Groundcover) vs trawa Remirosa w forku po pach75 (emulacja identyczna z rdzeniem C++),
    w tych samych granicach komórki. use_counts=False pokazuje same reguły tekstur (teren zmieniony modami)."""
    rules, counts, model = _remiros_model(official_profile, land_profile)
    li = _land_index(land_profile)
    x0, y0 = cell_x * land.CELL, cell_y * land.CELL
    off = gcbaseline.region_count(_gc_index(official_profile), x0, y0, x0 + land.CELL, y0 + land.CELL, density)
    inside, modes, models = 0, {}, collections.Counter()
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            r = remirosrules.generate_cell(li, model, cell_x + dx, cell_y + dy, density, None, True, use_counts)
            if dx == 0 and dy == 0:
                modes = {"mode": r.get("mode"), "texel_sources": r.get("texel_sources"), "rejected": r.get("rejected")}
            for i in r.get("instance_list", []):
                if x0 <= i["x"] < x0 + land.CELL and y0 <= i["y"] < y0 + land.CELL:
                    inside += 1
                    models[i["model"]] += 1
    return {"cell": [cell_x, cell_y], "region": li.regions.get((cell_x, cell_y)), "density": density,
            "remiros": {"instances": off["instances"], "by_model": off["by_model"]},
            "fork_pach75": {"instances": inside, "by_model": dict(models.most_common()), **modes},
            "ratio": round(inside / off["instances"], 4) if off["instances"] else None,
            "pach75": _pach75_state()}


@tool
def openmw_remiros_export(official_profile: str = "official-ref", land_profile: str = "fork-test",
                          dest: str = "Fork/experiments/remiros-subtexel-2026-11-14/files") -> dict:
    """Zapisuje pliki C++ dla pach76 (format liczników: pola 4×4 teksela × statyka): dane
    (remirosgroundcoverdata.{hpp,cpp}) i kopie wzorców z cpp/ MCP. Jedyny zapis tego narzędzia; katalog docelowy
    względem projektu (domyślnie eksperyment pach76; katalog pach75 zostaje jako zapis historyczny)."""
    import hashlib
    from . import srcmanifest
    rules, counts, _ = _remiros_model(official_profile, land_profile)
    out_dir = env().p(dest)
    out_dir.mkdir(parents=True, exist_ok=True)
    files = remirosrules.emit_cpp_files(rules, counts, srcmanifest.info())
    for name in ("remirosgroundcovergen.hpp", "remirosgroundcover.hpp", "remirosgroundcover.cpp"):
        files[name] = (srcmanifest.ROOT / "cpp" / name).read_text(encoding="utf-8")
    written = {}
    for name, text in files.items():
        (out_dir / name).write_text(text, encoding="utf-8")
        written[name] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return {"dest": str(out_dir), "files": written}


# --- etap 3: porównania wizualne (uruchamia silniki; zapis tylko w Raporty/mcp/zrzuty/) -------------------

def _parse_cells(cells) -> list:
    out = []
    for c in cells:
        if isinstance(c, str):
            x, y = c.replace("(", "").replace(")", "").split(",")
            out.append((int(x), int(y)))
        else:
            out.append((int(c[0]), int(c[1])))
    return out


def _capture_plans(cells, profiles_list, hour, weather, distance, label, repeat=1, settle_seconds=None,
                   render_seconds=None):
    from . import capture
    e = env()
    li = _land_index(profiles_list[-1] if profiles_list else "fork-test")
    density = None
    try:
        _, counts, _ = _remiros_model("official-ref", "fork-test")
        tex = {}
        for c in counts["cells"]:
            cx, cy = c["cell"]
            for ent in c["entries"]:
                t, k = ent[0], ent[2]
                tex[(cx * 16 + t % 16, cy * 16 + t // 16)] = k
        density = lambda x, y: tex.get((int(x // (land.CELL / 16)), int(y // (land.CELL / 16))), 0)  # noqa: E731
    except Exception:  # noqa: BLE001 — bez mapy liczników kamera celuje w środek komórki
        density = None
    shots = [capture.viewpoint(li, cx, cy, None, distance, 128.0, hour, weather, f"c{cx}_{cy}", density)
             for cx, cy in _parse_cells(cells)]
    shots = capture.repeat_shots(shots, repeat)
    timing = {k: v for k, v in (("settleSeconds", settle_seconds), ("renderSeconds", render_seconds)) if v is not None}
    run_dir = capture.new_run_dir(e, label)
    plans = [capture.prepare(e, p, shots, run_dir, timing) for p in profiles_list]
    return run_dir, shots, plans


def _capture_prereq(profiles_list) -> list:
    import shutil as _sh
    issues = []
    for tool_name in ("xdotool", "import"):
        if not _sh.which(tool_name):
            issues.append(f"brak programu {tool_name}")
    if not os.environ.get("DISPLAY"):
        issues.append("brak zmiennej DISPLAY (XWayland) w środowisku serwera MCP")
    if any(profiles.effective(env(), p)["target"] == "official" for p in profiles_list) and not _sh.which("flatpak"):
        issues.append("brak flatpak")
    return issues


@tool
def openmw_capture_plan(cells: list[str], profile_list: Optional[list[str]] = None, hour: float = 12.0,
                        weather: str = "Clear", distance: float = 700.0, repeat: int = 1,
                        settle_seconds: Optional[float] = None, render_seconds: Optional[float] = None) -> dict:
    """Przygotowuje (bez uruchamiania) ujęcia porównawcze: punkty kamery dla komórek (np. ["-5,-3","15,-9"]),
    katalogi uruchomienia w Raporty/mcp/zrzuty/ i polecenia dla każdego profilu. Do sprawdzenia przed startem.
    repeat>1: po pełnej serii ujęć powtarza ją (id z sufiksem -r2, -r3…) — test, czy różnica wynika z asynchronicznego
    doładowania (Groundcover/paging) zamiast z danych. settle_seconds/render_seconds nadpisują czasy oczekiwania."""
    pl = profile_list or ["official-ref", "fork-test"]
    run_dir, shots, plans = _capture_plans(cells, pl, hour, weather, distance, "plan", repeat, settle_seconds,
                                           render_seconds)
    return {"run_dir": str(run_dir), "prerequisites": _capture_prereq(pl),
            "shots": [s.__dict__ for s in shots], "commands": {p["profile"]: p["cmd"] for p in plans}}


@tool
def openmw_capture_start(cells: list[str], profile_list: Optional[list[str]] = None, hour: float = 12.0,
                         weather: str = "Clear", distance: float = 700.0, timeout_per_engine: float = 300.0,
                         repeat: int = 1, settle_seconds: Optional[float] = None,
                         render_seconds: Optional[float] = None) -> dict:
    """URUCHAMIA silniki (najpierw oficjalny, potem fork) w tle: każdy dostaje własny tymczasowy profil uruchomienia,
    skrypt Lua ustawia kamerę, MCP robi zrzut (F12/import). Wynik: openmw_capture_status(run_dir).
    repeat/settle_seconds/render_seconds jak w openmw_capture_plan."""
    import subprocess as _sp
    import sys as _sys
    pl = profile_list or ["official-ref", "fork-test"]
    issues = _capture_prereq(pl)
    if issues:
        return {"error": "nie spełnione warunki: " + "; ".join(issues)}
    run_dir, shots, plans = _capture_plans(cells, pl, hour, weather, distance, "porownanie", repeat, settle_seconds,
                                           render_seconds)
    log = open(run_dir / "runner.log", "w", encoding="utf-8")
    proc = _sp.Popen([_sys.executable, "-m", "openmw_mcp.capture", str(run_dir), str(timeout_per_engine)],
                     stdout=log, stderr=_sp.STDOUT, start_new_session=True)
    return {"run_dir": str(run_dir), "pid": proc.pid, "shots": [s.id for s in shots],
            "profiles": pl, "note": "silniki uruchamiają się kolejno; nie używaj w tym czasie myszy/klawiatury w oknie gry"}


@tool
def openmw_capture_status(run_dir: str) -> dict:
    """Postęp i wyniki przebiegu openmw_capture_start: zrzuty, błędy z logów, porównania (arkusze obok siebie,
    różnica obrazów, udział pikseli roślinności)."""
    from . import capture
    p = Path(run_dir)
    if not p.is_absolute():
        p = env().p(run_dir)
    return capture.status(p)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
