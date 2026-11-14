"""Efektywna konfiguracja profilu OpenMW: łańcuch openmw.cfg, scalanie opcji, ustawienia, world.cfg, VFS.

Odwzorowuje OpenMW 0.51.0 (components/files/configurationmanager.cpp, components/settings/settings.cpp):
* pierwszy config: lokalny (katalog binarki) albo globalny;
* dalej katalogi `config=` z wiersza poleceń, a bez `--replace=config` także z pierwszego configu (rekursywnie);
* `replace=config` w późniejszym configu odrzuca wcześniejsze poza pierwszym;
* opcje wielokrotne: kolejność od pierwszego configu do ostatniego, na końcu wiersz poleceń; `replace=X` kasuje wcześniejsze X;
* opcje pojedyncze: wiersz poleceń > ostatni config > … > pierwszy;
* ścieżki względne liczone od katalogu pliku .cfg; tokeny ?local? ?global? ?userdata? ?userconfig? → stałe ścieżki;
* defaults z pierwszego katalogu configu, settings.cfg pozostałych jako dodatkowe domyślne, ostatniego jako użytkownika;
* VFS: archiwa BSA (fallback-archive) < resources/vfs < data=… < data-local; późniejsza warstwa wygrywa.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from . import cfgparse
from .bsa import BsaError, list_tes3_bsa
from .environment import Env, flatpak_location
from .util import map_path, vfs_key


class ProfileError(Exception):
    pass


@dataclass
class Item:
    value: str
    source: str


@dataclass
class Resolved:
    name: str
    target: str
    flatpak_location: Optional[Path]
    active_config_dirs: list[str] = field(default_factory=list)
    config_files: list[str] = field(default_factory=list)
    composing: dict[str, list[Item]] = field(default_factory=dict)
    single: dict[str, Item] = field(default_factory=dict)
    issues: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def _profile_def(env: Env, name: str) -> dict:
    prof = env.cfg.get("profiles", {}).get(name)
    if prof is None:
        raise ProfileError(f"nieznany profil '{name}'; dostępne: {sorted(env.cfg.get('profiles', {}))}")
    return prof


class _Ctx:
    """Translacja ścieżek: /app/... w sandboxie → pliki wdrożenia Flatpaka; ~ i mapowanie ścieżek."""

    def __init__(self, env: Env, prof: dict, loc: Optional[Path]):
        self.env, self.loc = env, loc
        prof = dict(prof)
        for k in ("binary_dir", "global_config_dir"):
            v = os.path.expanduser(prof[k])
            if not os.path.isabs(v):
                v = str(env.project_root / v)
            prof[k] = os.path.normpath(v)
        self.prof = prof

    def host(self, p: str | Path) -> Path:
        s = os.path.expanduser(str(p))
        if self.loc is not None and (s == "/app" or s.startswith("/app/")):
            return self.loc / "files" / s[len("/app/"):] if s != "/app" else self.loc / "files"
        path = Path(s)
        if not path.is_absolute():
            path = self.env.project_root / path
        return map_path(path)

    @property
    def tokens(self) -> dict[str, str]:
        p = self.prof
        return {"?local?": p["binary_dir"], "?global?": p["global_config_dir"],
                "?userdata?": p.get("user_data_default", ""), "?userconfig?": p.get("user_config_default", "")}

    def resolve_path(self, value: str, base: str) -> str:
        if value.startswith("?"):
            end = value.find("?", 1)
            token = value[:end + 1] if end > 0 else value
            if token not in self.tokens:
                return ""
            rest = value[end + 1:]
            root = os.path.expanduser(self.tokens[token])
            return os.path.normpath(os.path.join(root, rest)) if rest else os.path.normpath(root)
        if not os.path.isabs(os.path.expanduser(value)):
            return os.path.normpath(os.path.join(base, value))
        return os.path.normpath(os.path.expanduser(value))


def _load_cfg(ctx: _Ctx, cfg_dir: str) -> Optional[cfgparse.OpenmwCfg]:
    f = ctx.host(cfg_dir) / "openmw.cfg"
    if not f.is_file():
        return None
    cfg = cfgparse.parse_openmw_cfg(f.read_text(encoding="utf-8", errors="replace"), str(f))
    for e in cfg.entries:
        if e.key in cfgparse.PATH_OPTIONS:
            e.value = ctx.resolve_path(e.value, cfg_dir)
    return cfg


def _has_replace_config(values: list[str]) -> bool:
    return any(v == "config" for v in values)


def resolve(env: Env, name: str) -> Resolved:
    prof = _profile_def(env, name)
    loc = None
    if prof.get("flatpak"):
        app = env.target(prof["target"])["app_id"]
        loc, err = flatpak_location(env, app)
        if err:
            raise ProfileError(f"profil {name}: {err}")
    ctx = _Ctx(env, prof, loc)
    res = Resolved(name=name, target=prof["target"], flatpak_location=loc)

    # wiersz poleceń (z definicji profilu = sposób uruchamiania przez nasze skrypty)
    cli = prof.get("cli", {})
    cli_comp: dict[str, list[Item]] = {}
    cli_single: dict[str, Item] = {}
    for k, v in cli.items():
        vals = v if isinstance(v, list) else [v]
        if k in cfgparse.PATH_OPTIONS:
            # ścieżki z definicji profilu: względne liczone od katalogu projektu
            vals = [ctx.resolve_path(os.path.expanduser(str(x)), str(env.project_root)) for x in vals]
        else:
            vals = [str(x) for x in vals]
        if k in cfgparse.COMPOSING:
            cli_comp[k] = [Item(x, "<wiersz poleceń>") for x in vals]
        else:
            cli_single[k] = Item(vals[-1], "<wiersz poleceń>")

    # pierwszy config
    local_dir, global_dir = ctx.prof["binary_dir"], ctx.prof["global_config_dir"]
    first_dir = local_dir if (ctx.host(local_dir) / "openmw.cfg").is_file() else global_dir
    first = _load_cfg(ctx, first_dir)
    if first is None:
        raise ProfileError(f"profil {name}: brak lokalnego ({ctx.host(local_dir)}/openmw.cfg) "
                           f"i globalnego ({ctx.host(global_dir)}/openmw.cfg) configu")
    parsed = [(first_dir, first)]
    active = [first_dir]
    stack: list[str] = []
    for d in reversed([i.value for i in cli_comp.get("config", [])]):
        stack.append(d)
    if not _has_replace_config([i.value for i in cli_comp.get("replace", [])]):
        for d in reversed(first.values("config")):
            stack.append(d)
    seen = {os.path.normpath(first_dir)}
    while stack:
        d = stack.pop()
        nd = os.path.normpath(d)
        if nd in seen:
            res.warnings.append(f"powtórzony katalog configu: {d}")
            continue
        seen.add(nd)
        cfg = _load_cfg(ctx, d)
        if cfg is not None and _has_replace_config(cfg.values("replace")) and len(parsed) > 1:
            parsed, active = parsed[:1], active[:1]
            res.warnings.append(f"replace=config w {d}: pominięto wcześniejsze configi poza pierwszym")
        active.append(d)
        if cfg is None:
            res.warnings.append(f"katalog configu bez openmw.cfg: {d}")
            continue
        for x in reversed(cfg.values("config")):
            stack.append(x)
        parsed.append((d, cfg))
    for _, cfg in parsed:
        res.config_files.append(cfg.path)
        res.issues.extend(cfg.errors)
    res.active_config_dirs = active

    # scalanie (od ostatniego do pierwszego, jak OpenMW)
    acc_comp = dict(cli_comp)
    single = dict(cli_single)
    for d, cfg in reversed(parsed):
        cur: dict[str, list[Item]] = {}
        for e in cfg.entries:
            item = Item(e.value, f"{cfg.path}:{e.line}")
            if e.key in cfgparse.COMPOSING:
                cur.setdefault(e.key, []).append(item)
            elif e.key not in single:
                single[e.key] = item
        replaced = {i.value for i in acc_comp.get("replace", [])}
        merged: dict[str, list[Item]] = {}
        for k in set(cur) | set(acc_comp):
            first_v, second_v = cur.get(k, []), acc_comp.get(k, [])
            if k == "fallback":
                m = {}
                for it in first_v + second_v:
                    m[it.value.split(",", 1)[0]] = it
                merged[k] = list(m.values())
            elif not first_v or k in replaced:
                merged[k] = second_v
            elif not second_v:
                merged[k] = first_v
            else:
                merged[k] = first_v + second_v
        acc_comp = merged
    res.composing, res.single = acc_comp, single
    return res


# --- widok efektywny ------------------------------------------------------------

def _settings(ctx: _Ctx, res: Resolved, defaults_file: Optional[Path]) -> dict:
    layers, files = [], []
    if defaults_file and defaults_file.is_file():
        layers.append(cfgparse.parse_settings_cfg(defaults_file.read_text(encoding="utf-8", errors="replace")))
        files.append(str(defaults_file) + " (settings-default.cfg ≙ defaults.bin)")
    elif defaults_file:
        res.warnings.append(f"brak pliku domyślnych ustawień: {defaults_file}")
    for d in res.active_config_dirs:
        f = ctx.host(d) / "settings.cfg"
        if f.is_file():
            layers.append(cfgparse.parse_settings_cfg(f.read_text(encoding="utf-8", errors="replace")))
            files.append(str(f))
    user_file = ctx.host(res.active_config_dirs[-1]) / "settings.cfg"
    user = cfgparse.parse_settings_cfg(user_file.read_text(encoding="utf-8", errors="replace")) if user_file.is_file() else {}
    return {"files": files, "merged": cfgparse.merge_settings(*layers), "user_overrides": user}


def _locate(ctx: _Ctx, name: str, dirs: list[Path]) -> dict:
    """Jak Files::MultiDirCollection (0.51.0): dopasowanie bez wielkości liter, późniejszy katalog wygrywa.
    W JEDNYM katalogu kilka nazw różniących się wielkością liter → silnik wybiera wg kolejności
    directory_iterator (zależnej od systemu plików). MCP wybiera deterministycznie (dokładna nazwa, potem
    alfabetycznie) i zgłasza niejednoznaczność."""
    providers, ambiguous = [], []
    low = name.lower()
    for d in dirs:
        try:
            matches = sorted(e.path for e in os.scandir(d) if e.is_file() and e.name.lower() == low)
        except OSError:
            continue
        if not matches:
            continue
        exact = [m for m in matches if os.path.basename(m) == name]
        chosen = exact[0] if exact else matches[0]
        if len(matches) > 1:
            ambiguous.append({"dir": str(d), "candidates": matches, "mcp_choice": chosen})
        providers.append(chosen)
    return {"name": name, "providers": providers, "file": providers[-1] if providers else None,
            "case_ambiguous": ambiguous}


def effective(env: Env, name: str) -> dict:
    prof = _profile_def(env, name)
    res = resolve(env, name)
    ctx = _Ctx(env, prof, res.flatpak_location)
    s = res.single
    resources = s.get("resources")
    user_data = s.get("user-data")
    data_local = s.get("data-local")
    data_items = res.composing.get("data", [])

    dirs: list[dict] = []
    if resources:
        dirs.append({"path": os.path.join(resources.value, "vfs"), "source": "resources/vfs (wbudowane)"})
    for it in data_items:
        dirs.append({"path": it.value, "source": it.source})
    if data_local and data_local.value:
        dirs.append({"path": data_local.value, "source": f"data-local ({data_local.source})"})
    for d in dirs:
        d["host_path"] = str(ctx.host(d["path"]))
        d["exists"] = Path(d["host_path"]).is_dir()
        if not d["exists"]:
            res.issues.append(f"nieistniejący katalog danych (OpenMW go pominie): {d['path']}")
    existing = [Path(d["host_path"]) for d in dirs if d["exists"]]

    archives = []
    for it in res.composing.get("fallback-archive", []):
        loc = _locate(ctx, it.value, existing)
        archives.append({"name": it.value, "source": it.source, "file": loc["file"], "providers": loc["providers"]})
        if not loc["file"]:
            res.issues.append(f"nie znaleziono archiwum {it.value} w katalogach danych")

    def plugins(key):
        out = []
        for it in res.composing.get(key, []):
            loc = _locate(ctx, it.value, existing)
            ent = {"name": it.value, "source": it.source, "file": loc["file"], "providers": loc["providers"]}
            if not loc["file"]:
                res.issues.append(f"{key}={it.value}: plik nie znaleziony w katalogach danych")
            for amb in loc["case_ambiguous"]:
                ent.setdefault("case_ambiguous", []).append(amb)
                res.issues.append(f"{key}={it.value}: w {amb['dir']} są pliki różniące się tylko wielkością liter "
                                  f"{[os.path.basename(c) for c in amb['candidates']]} — OpenMW wybierze zależnie od "
                                  f"kolejności systemu plików; MCP przyjął {os.path.basename(amb['mcp_choice'])}")
            if len(loc["providers"]) > 1:
                res.warnings.append(f"{key}={it.value} występuje w {len(loc['providers'])} katalogach — wygrywa ostatni")
            out.append(ent)
        return out

    content = plugins("content")
    groundcover = plugins("groundcover")
    both = {c["name"].lower() for c in content} & {g["name"].lower() for g in groundcover}
    for n in sorted(both):
        res.warnings.append(f"{n} jednocześnie w content= i groundcover=")

    t = env.target(prof["target"])
    defaults = env.p(prof.get("settings_defaults") or t.get("settings_defaults"))
    settings = _settings(ctx, res, defaults)
    user_cfg_dir = ctx.host(res.active_config_dirs[-1])
    world = None
    if prof.get("world_cfg"):
        wf = user_cfg_dir / "world.cfg"
        world = cfgparse.parse_world_cfg(wf.read_text(encoding="utf-8", errors="replace") if wf.is_file() else None)
        world["file"] = str(wf)

    # izolacja od profilu użytkownika
    iso = {"user_config_default": prof.get("user_config_default"), "user_data_default": prof.get("user_data_default"),
           "violations": []}
    ucd = os.path.normpath(os.path.expanduser(prof.get("user_config_default", "") or "/nonexistent-ucd"))
    udd = os.path.normpath(os.path.expanduser(prof.get("user_data_default", "") or "/nonexistent-udd"))
    for d in res.active_config_dirs:
        if os.path.normpath(os.path.expanduser(d)) == ucd:
            iso["violations"].append(f"aktywny katalog configu = profil użytkownika: {d}")
    for label, it in (("user-data", user_data), ("data-local", data_local)):
        if it and (os.path.normpath(it.value) == udd or os.path.normpath(it.value).startswith(udd + os.sep)):
            iso["violations"].append(f"{label} wskazuje dane użytkownika: {it.value}")
    for d in dirs:
        if os.path.normpath(d["path"]).startswith(udd + os.sep) or os.path.normpath(d["path"]) == udd:
            iso["violations"].append(f"katalog danych w danych użytkownika: {d['path']}")
    iso["isolated"] = not iso["violations"]
    if not iso["isolated"]:
        res.issues.extend(iso["violations"])

    return {
        "profile": name, "target": prof["target"], "flatpak_location": str(res.flatpak_location) if res.flatpak_location else None,
        "config_files": res.config_files, "active_config_dirs": res.active_config_dirs,
        "user_config_dir": str(user_cfg_dir),
        "single": {k: {"value": v.value, "source": v.source} for k, v in sorted(res.single.items())},
        "data_dirs": dirs, "fallback_archives": archives, "content": content, "groundcover": groundcover,
        "fallback_count": len(res.composing.get("fallback", [])),
        "encoding": s["encoding"].value if "encoding" in s else "win1252 (domyślne)",
        "settings": settings, "world_cfg": world, "isolation": iso,
        "issues": res.issues, "warnings": res.warnings,
    }


# --- VFS ----------------------------------------------------------------------------

def vfs_index(eff: dict, include_archives: bool = True) -> dict:
    """Mapa klucz_vfs -> lista dostawców w kolejności priorytetu (ostatni wygrywa)."""
    index: dict[str, list[dict]] = {}
    layers = []
    if include_archives:
        for a in eff["fallback_archives"]:
            if a["file"]:
                layers.append(("bsa", a["file"]))
    for d in eff["data_dirs"]:
        if d["exists"]:
            layers.append(("dir", d["host_path"]))
    errors = []
    for prio, (kind, path) in enumerate(layers):
        if kind == "bsa":
            try:
                for key in list_tes3_bsa(Path(path)):
                    index.setdefault(key, []).append({"layer": prio, "kind": "bsa", "root": path, "file": None})
            except (OSError, BsaError) as e:
                errors.append(str(e))
            continue
        for root, dirnames, files in os.walk(path):
            dirnames.sort()
            for f in sorted(files):
                full = os.path.join(root, f)
                key = vfs_key(os.path.relpath(full, path))
                index.setdefault(key, []).append({"layer": prio, "kind": "dir", "root": path, "file": full})
    return {"layers": [{"priority": i, "kind": k, "path": p} for i, (k, p) in enumerate(layers)],
            "index": index, "errors": errors}
