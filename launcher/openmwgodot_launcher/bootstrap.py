"""Ścieżki modułów: launcher korzysta z pakietów `mwcore` i `mwconv` (katalog converter/).

Układ repozytorium: <repo>/launcher/openmwgodot_launcher, <repo>/converter/{mwcore,mwconv}.
Układ wydania:      <app>/launcher/..., <app>/converter/... (ten sam względny układ).
"""

import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[2]


def ensure_paths() -> None:
    conv = APP_ROOT / "converter"
    if conv.is_dir() and str(conv) not in sys.path:
        sys.path.insert(0, str(conv))
