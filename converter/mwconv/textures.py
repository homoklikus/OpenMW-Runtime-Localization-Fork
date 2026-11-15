"""Konwersja tekstur gry (DDS/TGA/BMP) do PNG czytanego przez Godota (import edytora i runtime).

PNG jest formatem pośrednim (bezstratnym). Kompresję VRAM (BCn/ETC2) wykonuje Godot. Planowany
etap 2: bezpośredni zapis KTX2/BasisU przez nasz binarny Godot uruchamiany headless.
"""

from __future__ import annotations

import io
import os
from pathlib import Path

from PIL import Image


def texture_out_rel(vfs_key: str) -> str:
    """'textures/tx_a.dds' → 'textures/tx_a.png' (ścieżka względna w katalogu wyników)."""
    base, _ = os.path.splitext(vfs_key)
    return base + ".png"


def convert_texture(data: bytes, out_path: Path) -> dict:
    img = Image.open(io.BytesIO(data))
    img.load()
    has_alpha = False
    if img.mode in ("RGBA", "LA", "PA") or (img.mode == "P" and "transparency" in img.info):
        img = img.convert("RGBA")
        lo, _hi = img.getchannel("A").getextrema()
        has_alpha = lo < 255
        if not has_alpha:
            img = img.convert("RGB")
    elif img.mode != "RGB":
        img = img.convert("RGB")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(".tmp.png")
    img.save(tmp, "PNG", compress_level=3)
    os.replace(tmp, out_path)
    return {"width": img.width, "height": img.height, "has_alpha": has_alpha, "mode": img.mode}
