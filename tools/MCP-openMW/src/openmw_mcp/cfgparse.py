"""Parsery plików konfiguracyjnych OpenMW: openmw.cfg, settings.cfg, world.cfg (fork)."""

from __future__ import annotations

from dataclasses import dataclass, field

# Opcje wielokrotne (composing) w OpenMW 0.51.0: components/files/configurationmanager.cpp
# i apps/openmw/options.cpp.
COMPOSING = {"config", "replace", "data", "fallback-archive", "content", "groundcover", "fallback"}
PATH_OPTIONS = {"config", "data", "data-local", "user-data", "resources", "load-savegame"}


def unquote_path(value: str) -> str:
    """Files::MaybeQuotedPath: "..." z escape '&&' i '&"'."""
    v = value.strip()
    if len(v) >= 2 and v[0] == '"':
        out, i = [], 1
        while i < len(v):
            c = v[i]
            if c == "&" and i + 1 < len(v) and v[i + 1] in '&"':
                out.append(v[i + 1]); i += 2; continue
            if c == '"':
                break
            out.append(c); i += 1
        return "".join(out)
    return v


@dataclass
class CfgEntry:
    key: str
    value: str
    line: int


@dataclass
class OpenmwCfg:
    path: str
    entries: list[CfgEntry] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def values(self, key: str) -> list[str]:
        return [e.value for e in self.entries if e.key == key]


def parse_openmw_cfg(text: str, path: str = "<text>") -> OpenmwCfg:
    cfg = OpenmwCfg(path=path)
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            cfg.errors.append(f"{path}:{n}: wiersz bez '=': {raw!r}")
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key in PATH_OPTIONS:
            value = unquote_path(value)
        cfg.entries.append(CfgEntry(key, value, n))
    return cfg


def parse_settings_cfg(text: str) -> dict[str, dict[str, str]]:
    """settings.cfg: [Sekcja] + 'klucz = wartość'. Klucze sekcji/opcji zachowują wielkość liter."""
    result: dict[str, dict[str, str]] = {}
    section = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            result.setdefault(section, {})
            continue
        if "=" in line and section is not None:
            k, v = line.split("=", 1)
            result[section][k.strip()] = v.strip()
    return result


def merge_settings(*layers: dict[str, dict[str, str]]) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for layer in layers:
        for sec, kv in layer.items():
            out.setdefault(sec, {}).update(kv)
    return out


def setting(settings: dict, section: str, key: str, default=None):
    for s, kv in settings.items():
        if s.lower() == section.lower():
            for k, v in kv.items():
                if k.lower() == key.lower():
                    return v
    return default


def parse_bool(v, default=False) -> bool:
    if v is None:
        return default
    s = str(v).strip().lower()
    if s in ("true", "1", "yes", "on"):
        return True
    if s in ("false", "0", "no", "off"):
        return False
    return default


def _float(v, default):
    try:
        return float(str(v).strip())
    except (TypeError, ValueError):
        return default


def parse_world_cfg(text: str | None) -> dict:
    """Odwzorowanie components/worldconfig/worldsettings.cpp (fork 0.5-world)."""
    res = {"present": text is not None, "version": 1,
           "flora": {"enabled": False, "source": "automatic", "density": 1.0, "exclusion_distance": 3.0},
           "fauna": {"enabled": False}, "warnings": []}
    if text is None:
        return res
    section = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if "=" not in line:
            continue
        k, v = (x.strip() for x in line.split("=", 1))
        k = k.lower()
        if section == "world" and k == "version":
            try:
                res["version"] = max(1, int(v))
            except ValueError:
                res["warnings"].append(f"world.version: nieprawidłowa wartość {v!r}")
        elif section == "flora":
            if k == "enabled":
                res["flora"]["enabled"] = parse_bool(v, False)
            elif k == "source":
                s = v.lower()
                if s in ("automatic", "groundcover", "hybrid"):
                    res["flora"]["source"] = s
                else:
                    res["warnings"].append(f"flora.source: nieznana wartość {v!r} (zostaje 'automatic')")
            elif k == "density":
                res["flora"]["density"] = min(2.0, max(0.0, _float(v, 1.0)))
            elif k in ("exclusion_distance", "exclusion%20distance"):
                res["flora"]["exclusion_distance"] = min(20.0, max(0.0, _float(v, 3.0)))
        elif section == "fauna" and k == "enabled":
            res["fauna"]["enabled"] = parse_bool(v, False)
    return res
