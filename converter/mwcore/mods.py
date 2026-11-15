"""Mody: instalacja z archiwów jako osobne warstwy danych, kolejność, zależności ESM/ESP, konflikty.

Każdy mod leży w <data>/mods/<id>/ (rozpakowane archiwum + mod.json). Mody nigdy nie są kopiowane do
katalogu gry ani do konwersji – profil składa listę warstw: instalacja bazowa → mody w kolejności
profilu (późniejszy wygrywa). Z tej listy powstaje konfiguracja konwertera (InstallConfig).
"""

from __future__ import annotations

import hashlib
import re
import shutil
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from mwconv.esm.header import read_header
from mwconv.install import InstallConfig

from .archive import ArchiveError, Limits, extract
from .jsonio import read_json, write_json
from .paths import AppPaths

DATA_DIRS = {"meshes", "textures", "icons", "bookart", "sound", "music", "fonts", "splash", "video", "distantland", "localization"}
PLUGIN_EXT = (".esm", ".esp", ".omwaddon")


class ModError(Exception):
    pass


@dataclass
class ModInfo:
    id: str
    name: str
    data_root: str                       # względem katalogu moda
    plugins: list = field(default_factory=list)   # [{"file", "masters", "is_master"}]
    archives: list = field(default_factory=list)  # pliki BSA moda
    files: int = 0
    archive_name: str = ""
    archive_sha256: str = ""
    installed: float = 0.0
    version: int = 1

    def to_dict(self) -> dict:
        return dict(self.__dict__)


def _sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_data_root(root: Path) -> Path:
    """Najpłytszy katalog wyglądający na „Data Files” (podkatalogi danych lub pliki ESP/ESM/BSA)."""
    best = None
    for d in [root, *sorted((p for p in root.rglob("*") if p.is_dir()), key=lambda x: len(x.parts))]:
        names = {e.name.lower() for e in d.iterdir()}
        if d.name.lower() == "data files" or names & DATA_DIRS or any(n.endswith(PLUGIN_EXT + (".bsa",)) for n in names):
            best = d
            break
    if best is None:
        raise ModError("archiwum nie zawiera danych gry (brak meshes/textures/…, ESP/ESM ani BSA)")
    return best


def norm_rel(p: str) -> str:
    return p.replace("\\", "/").lower().lstrip("/")


class ModStore:
    def __init__(self, paths: AppPaths, limits: Limits | None = None):
        self.paths = paths
        self.dir = paths.mods_dir
        self.dir.mkdir(parents=True, exist_ok=True)
        self.limits = limits or Limits()

    def list(self) -> list[ModInfo]:
        out = []
        for d in sorted(self.dir.iterdir()):
            m = self.get(d.name)
            if m:
                out.append(m)
        return out

    def get(self, mod_id: str) -> ModInfo | None:
        if not re.match(r"^[a-z0-9][a-z0-9_.-]{0,80}$", mod_id):
            return None
        d = read_json(self.dir / mod_id / "mod.json")
        if not isinstance(d, dict):
            return None
        keys = ModInfo.__dataclass_fields__.keys()
        return ModInfo(**{k: d[k] for k in keys if k in d})

    def data_path(self, m: ModInfo) -> Path:
        p = (self.dir / m.id / m.data_root).resolve()
        if not str(p).startswith(str((self.dir / m.id).resolve())):
            raise ModError(f"mod {m.id}: data_root poza katalogiem moda")  # ochrona przed złym manifestem
        return p

    def install(self, archive: Path, name: str | None = None) -> ModInfo:
        archive = Path(archive)
        if not archive.is_file():
            raise ModError(f"brak pliku: {archive}")
        base = re.sub(r"[^a-z0-9]+", "-", (name or archive.stem).lower()).strip("-")[:40] or "mod"
        mod_id = base
        k = 2
        while (self.dir / mod_id).exists():
            mod_id = f"{base}-{k}"
            k += 1
        stage = self.paths.staging / f"{mod_id}-{uuid.uuid4().hex[:8]}"
        try:
            n = extract(archive, stage / "files", self.limits)
            root = find_data_root(stage / "files")
            plugins = []
            for f in sorted(root.iterdir()):
                if f.is_file() and f.suffix.lower() in (".esm", ".esp"):
                    try:
                        h = read_header(f)
                        plugins.append({"file": f.name, "masters": [m for m, _ in h.masters],
                                        "is_master": f.suffix.lower() == ".esm" or bool(h.flags & 1)})
                    except Exception as e:  # noqa: BLE001
                        raise ModError(f"uszkodzony plugin {f.name}: {e}") from None
            archives = sorted(f.name for f in root.iterdir() if f.is_file() and f.suffix.lower() == ".bsa")
            info = ModInfo(mod_id, name or archive.stem, (Path("files") / root.relative_to(stage / "files")).as_posix(),
                           plugins, archives, n, archive.name, _sha256(archive), time.time())
            write_json(stage / "mod.json", info.to_dict())
            stage.rename(self.dir / mod_id)  # atomowo (ten sam system plików: <data> i <cache> mogą się różnić)
        except OSError as e:
            if e.errno == 18:  # EXDEV – przeniesienie między systemami plików
                shutil.move(str(stage), str(self.dir / mod_id))
            else:
                shutil.rmtree(stage, ignore_errors=True)
                raise ModError(str(e)) from None
        except (ArchiveError, ModError):
            shutil.rmtree(stage, ignore_errors=True)
            raise
        return self.get(mod_id)

    def remove(self, mod_id: str) -> None:
        m = self.get(mod_id)
        if m is None:
            raise ModError(f"nie ma moda {mod_id}")
        shutil.rmtree(self.dir / m.id)

    def file_list(self, m: ModInfo) -> list[str]:
        """Pliki danych moda (znormalizowane ścieżki) – luźne pliki i zawartość jego archiwów BSA."""
        cache = self.dir / m.id / "files_index.json"
        idx = read_json(cache)
        if isinstance(idx, list):
            return idx
        root = self.data_path(m)
        out = []
        for p in root.rglob("*"):
            if p.is_file():
                rel = p.relative_to(root).as_posix()
                top = rel.split("/", 1)[0].lower()
                if top in DATA_DIRS:
                    out.append(norm_rel(rel))
        from mwconv.vfs import BsaArchive
        for a in m.archives:
            try:
                out.extend(BsaArchive(root / a).entries.keys())
            except Exception:  # noqa: BLE001
                pass
        out = sorted(set(out))
        write_json(cache, out)
        return out


# ------------------------------------------------------------------------------------------------
# składanie warstw profilu
# ------------------------------------------------------------------------------------------------

@dataclass
class Resolution:
    config: InstallConfig                       # konfiguracja dla konwertera (bazowa + mody)
    content: list = field(default_factory=list)  # nazwy pluginów w kolejności ładowania
    missing_masters: list = field(default_factory=list)   # [{"plugin", "mod", "missing": [...]}]
    missing_mods: list = field(default_factory=list)      # mody z profilu, których nie ma w magazynie
    conflicts: list = field(default_factory=list)         # [{"file", "providers": [...], "winner"}]
    signature: str = ""                          # zmienia się przy każdej zmianie zestawu/kolejności modów

    @property
    def ok(self) -> bool:
        return not self.missing_masters and not self.missing_mods


def resolve(base: InstallConfig, enabled_mod_ids: list[str], store: ModStore,
            base_files: set[str] | None = None) -> Resolution:
    """Kolejność: pliki ESM (baza, potem mody), następnie ESP (baza, potem mody) – jak w grze."""
    cfg = InstallConfig(list(base.data_dirs), list(base.archives), [], origin=base.origin)
    esm, esp = [], []
    for c in base.content:
        (esm if c.lower().endswith(".esm") else esp).append(c)
    res = Resolution(cfg)
    sig = hashlib.sha256()
    providers: dict[str, list[str]] = {}
    if base_files:
        for f in base_files:
            providers[f] = ["(gra)"]
    mods = []
    for mid in enabled_mod_ids:
        m = store.get(mid)
        if m is None:
            res.missing_mods.append(mid)
            continue
        mods.append(m)
        root = store.data_path(m)
        cfg.data_dirs.append(str(root))
        cfg.archives.extend(str(root / a) for a in m.archives)
        for p in m.plugins:
            (esm if p["is_master"] else esp).append(str(root / p["file"]))
        sig.update(f"{m.id}:{m.archive_sha256};".encode())
        for f in store.file_list(m):
            providers.setdefault(f, []).append(m.id)
    cfg.content = esm + esp
    res.content = [Path(c).name for c in cfg.content]
    seen: list[str] = []
    owner = {str(store.data_path(m) / p["file"]): m.id for m in mods for p in m.plugins}
    for c in cfg.content:
        name = Path(c).name
        if c in owner:
            m = store.get(owner[c])
            plug = next(p for p in m.plugins if p["file"] == name)
            missing = [x for x in plug["masters"] if x.lower() not in seen]
            if missing:
                res.missing_masters.append({"plugin": name, "mod": m.id, "missing": missing})
        seen.append(name.lower())
    for f, prov in sorted(providers.items()):
        if len(prov) > 1:
            res.conflicts.append({"file": f, "providers": prov, "winner": prov[-1]})
    res.signature = sig.hexdigest()
    return res
