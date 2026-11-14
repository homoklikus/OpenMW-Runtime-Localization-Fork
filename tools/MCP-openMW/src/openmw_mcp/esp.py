"""Nagłówek, statystyka rekordów i komórki pluginów TES3 (.esm/.esp/.omwaddon) — tylko odczyt."""

from __future__ import annotations

import collections
import struct
from pathlib import Path


def _records(data: bytes):
    o = 0
    while o + 16 <= len(data):
        t = data[o:o + 4].decode("latin-1")
        n = struct.unpack_from("<I", data, o + 4)[0]
        yield t, data[o + 16:o + 16 + n]
        o += 16 + n


def _subs(rec: bytes):
    o = 0
    while o + 8 <= len(rec):
        t = rec[o:o + 4].decode("latin-1")
        n = struct.unpack_from("<I", rec, o + 4)[0]
        yield t, rec[o + 8:o + 8 + n]
        o += 8 + n


def esp_info(path: Path, count_records: bool = True) -> dict:
    data = path.read_bytes()
    if data[:4] != b"TES3":
        return {"file": path.name, "error": "to nie jest plik TES3"}
    info = {"file": path.name, "size": len(data), "masters": [], "author": "", "description": "", "records": {}}
    for t, sub in _subs(next(_records(data))[1]):
        if t == "HEDR" and len(sub) >= 296:
            info["format_version"] = round(struct.unpack_from("<f", sub, 0)[0], 2)
            info["author"] = sub[8:40].split(b"\0")[0].decode("latin-1")
            info["description"] = sub[40:296].split(b"\0")[0].decode("latin-1")
        elif t == "MAST":
            info["masters"].append(sub.split(b"\0")[0].decode("latin-1"))
    if count_records:
        info["records"] = dict(collections.Counter(t for t, _ in _records(data)))
    return info


def groundcover_stats(paths: list[Path]) -> dict:
    """Odpowiednik linii OpenMW 'Loaded N cells, M statics' dla plików groundcover=, + referencje per plik."""
    cells: set = set()          # wszystkie CELL jak w OpenMW: zewnętrzne po (x,y), wnętrza po nazwie
    exterior: set = set()
    statics: set = set()
    per_file = []
    for p in paths:
        data = p.read_bytes()
        fc, fs, refs, fi = set(), 0, 0, set()
        for t, rec in _records(data):
            if t == "STAT":
                for st, sd in _subs(rec):
                    if st == "NAME":
                        statics.add(sd.split(b"\0")[0].decode("latin-1").lower())
                        fs += 1
                        break
            elif t == "CELL":
                flags = gx = gy = None
                name = ""
                for st, sd in _subs(rec):
                    if st == "NAME" and not name:
                        name = sd.split(b"\0")[0].decode("latin-1")
                    elif st == "DATA" and gx is None and len(sd) == 12:
                        flags, gx, gy = struct.unpack("<Iii", sd)
                    elif st == "FRMR":
                        refs += 1
                if flags is not None and not flags & 1:
                    fc.add((gx, gy))
                else:
                    fi.add(name.lower())
        cells |= {("ext", c) for c in fc} | {("int", n) for n in fi}
        exterior |= fc
        per_file.append({"file": p.name, "exterior_cells": len(fc), "interior_cells": sorted(fi),
                         "statics": fs, "references": refs})
    return {"cells": len(cells), "exterior_cells": len(exterior), "statics": len(statics), "files": per_file,
            "note": "'cells' liczone jak w logu OpenMW 'Loaded N cells' (wszystkie rekordy CELL)"}


def cell_references(path: Path, cell: tuple[int, int]) -> dict:
    """Liczba referencji przypisanych do komórki zewnętrznej i z pozycją w jej granicach."""
    cx, cy = cell
    assigned = inside = 0
    for t, rec in _records(path.read_bytes()):
        if t != "CELL":
            continue
        gx = gy = flags = None
        pending = False
        refs = []
        for st, sd in _subs(rec):
            if st == "DATA" and gx is None and len(sd) == 12:
                flags, gx, gy = struct.unpack("<Iii", sd)
            elif st == "FRMR":
                pending = True
            elif st == "DATA" and len(sd) == 24 and pending:
                refs.append(struct.unpack("<3f", sd[:12])); pending = False
        if (gx, gy) == (cx, cy) and flags is not None and not flags & 1:
            assigned += len(refs)
            inside += sum(1 for x, y, _ in refs if cx * 8192 <= x < (cx + 1) * 8192 and cy * 8192 <= y < (cy + 1) * 8192)
    return {"file": path.name, "cell": [cx, cy], "assigned": assigned, "position_inside": inside}
