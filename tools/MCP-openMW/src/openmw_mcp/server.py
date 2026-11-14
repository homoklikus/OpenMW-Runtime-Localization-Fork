"""Serwer MCP (stdio) — etap 1: tylko odczyt. Jedyny zapis: manifest testu (openmw_manifest_write) i cache SHA-256."""

from __future__ import annotations

import functools
import traceback
from pathlib import Path
from typing import Optional

try:                                   # mcp 2.x
    from mcp.server.mcpserver import MCPServer as _Server
except ImportError:                    # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

from . import environment, esp, flora, gcbaseline, land, manifest, mods, profiles
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
    return flora.classify(eff, eff["target"], vfs, pl, src, exps)


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


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
