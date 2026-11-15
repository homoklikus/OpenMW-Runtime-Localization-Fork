"""Atomowy zapis i odporny odczyt JSON (konfiguracja, profile, manifesty)."""

from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any


def write_json(path: Path, obj: Any) -> None:
    """Zapis atomowy: plik tymczasowy w tym samym katalogu + fsync + os.replace."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def read_json(path: Path, default: Any = None) -> Any:
    """Brak pliku → default. Uszkodzony plik → odłożony jako *.bad-<czas> i default (bez wyjątku)."""
    path = Path(path)
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        try:
            path.replace(path.with_name(f"{path.name}.bad-{int(time.time())}"))
        except OSError:
            pass
        return default
