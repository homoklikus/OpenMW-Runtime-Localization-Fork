"""Interfejs wiersza poleceń: `python -m mwconv <polecenie>`.

  convert   – konwersja instalacji (openmw.cfg / katalog Morrowinda / ręcznie: --data, --content)
  nif2glb   – pojedynczy plik NIF → GLB (+ raport diagnostyczny)
  synth     – zapis syntetycznych danych testowych („Synthville”)
  inspect   – podgląd pliku NIF/ESM/BSA
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def _grid(s: str) -> tuple:
    x, y = s.split(",")
    return int(x), int(y)


def cmd_convert(a):
    from .install import InstallConfig, from_morrowind_dir, from_openmw_cfg
    from .pipeline import Options, run
    if a.openmw_cfg:
        cfg = from_openmw_cfg(a.openmw_cfg)
    elif a.morrowind:
        cfg = from_morrowind_dir(a.morrowind)
    else:
        cfg = InstallConfig(origin="cli")
    if a.data:
        cfg.data_dirs += [str(Path(d).resolve()) for d in a.data]
    for arc in a.archive or []:
        cfg.archives.append(str(Path(arc).resolve()))
    for c in a.content or []:
        p = Path(c)
        if not p.is_absolute():
            for d in reversed(cfg.data_dirs):
                if (Path(d) / c).exists():
                    p = Path(d) / c
                    break
        cfg.content.append(str(p.resolve()))
    if not cfg.content:
        print("Brak plików ESM/ESP (użyj --content, --openmw-cfg albo --morrowind)", file=sys.stderr)
        return 2
    grids = [_grid(g) for g in a.grid or []]
    if a.grid_range:
        x0, y0, x1, y1 = (int(v) for v in a.grid_range.split(","))
        grids += [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    opts = Options(out=Path(a.out).resolve(), cells=a.cell or [], grids=grids, all_cells=a.all_cells,
                   all_models=a.all_models, all_textures=a.all_textures, jobs=a.jobs, verify_hash=a.verify_hash)
    print("Instalacja:", json.dumps(cfg.to_dict(), ensure_ascii=False, indent=1))
    stats = run(cfg, opts)
    print(json.dumps({k: stats[k] for k in ("models", "textures", "world_export", "total_seconds") if k in stats},
                     ensure_ascii=False, indent=1))
    return 0


def cmd_nif2glb(a):
    from .nif.reader import read_file
    from .nif2gltf import NifToGltf, TextureRef
    from .textures import convert_texture

    src = Path(a.input)
    out = Path(a.output) if a.output else src.with_suffix(".glb")
    tex_dirs = [Path(d) for d in (a.textures or [])]
    tex_out = out.parent / "textures"

    def resolve(name):
        base = os.path.splitext(name.replace("\\", "/").split("/")[-1])[0].lower()
        for d in tex_dirs:
            for ext in (".dds", ".tga", ".bmp", ".png"):
                for p in d.rglob("*"):
                    if p.is_file() and p.stem.lower() == base and p.suffix.lower() == ext:
                        dst = tex_out / (base + ".png")
                        if not dst.exists():
                            convert_texture(p.read_bytes(), dst)
                        return TextureRef(uri=os.path.relpath(dst, out.parent), source_path=str(p))
        return None

    nif = read_file(src)
    glb, rep = NifToGltf(nif, src.name, resolve).convert()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(glb)
    rp = out.with_suffix(".report.json")
    rp.write_text(json.dumps(rep.to_dict(), ensure_ascii=False, indent=1))
    print(json.dumps(rep.to_dict(), ensure_ascii=False, indent=1))
    return 0


def cmd_synth(a):
    from .synthetic_world import write_patch2, write_world
    info = write_world(Path(a.out))
    if a.patch2:
        info["esp2"] = write_patch2(Path(a.out))
    print(json.dumps(info, indent=1))
    return 0


def _hexdump(data: bytes, start: int, length: int = 96, mark: int | None = None) -> str:
    lines = []
    start = max(0, start)
    for off in range(start - start % 16, min(len(data), start + length), 16):
        chunk = data[off:off + 16]
        hx = " ".join(("[" if mark is not None and off + i == mark else "") + f"{b:02x}" for i, b in enumerate(chunk))
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{off:08x}  {hx:<50s} {asc}")
    return "\n".join(lines)


def cmd_inspect(a):
    p = Path(a.input)
    ext = p.suffix.lower()
    if ext in (".nif", ".kf"):
        from .nif.reader import NifError, parse
        data = p.read_bytes()
        try:
            nf = parse(data, p.name)
        except NifError as e:
            print("BŁĄD:", e)
            print(f"blok: {e.block_index} typu {e.block_type}, początek bloku @ {e.block_start}, błąd @ {e.offset}")
            for b in e.partial[-5:]:
                print(f"  poprawnie odczytany: {b.index:4d} {b.type:28s} {b.get('name', '')}")
            if e.block_start is not None:
                print("bajty od początku błędnego bloku ([ = miejsce błędu):")
                print(_hexdump(data, e.block_start, 128, e.offset))
            return 1
        for b in nf.blocks:
            nm = b.get("name", "")
            extra = ""
            if b.type in ("NiTriShapeData", "NiTriStripsData"):
                extra = f"  v={b['num_vertices']} uv={len(b['uvs'])}"
            elif b.type == "NiSourceTexture":
                extra = f"  {b.get('file')}"
            elif "Controller" in b.type:
                extra = f"  target={b.get('target')} data={b.get('data', '-')}"
            print(f"{b.index:4d} {b.type:28s} {nm}{extra}")
        print("korzenie:", nf.roots, "nadmiarowe bajty:", nf.trailing)
        if a.convert:
            from .nif2gltf import NifToGltf
            _glb, rep = NifToGltf(nf, p.name).convert()
            print(json.dumps({k: rep.to_dict()[k] for k in ("nodes", "meshes", "triangles", "lossy", "unsupported",
                                                           "missing_textures", "skipped_shapes")},
                             ensure_ascii=False, indent=1))
    elif ext in (".esm", ".esp", ".omwaddon"):
        from .esm.reader import read_esm
        f = read_esm(p)
        counts = {}
        for r in f.records:
            counts[r.type] = counts.get(r.type, 0) + 1
        print(json.dumps({"header": f.header.__dict__, "sha256": f.sha256, "records": counts}, indent=1,
                         ensure_ascii=False))
    elif ext == ".bsa":
        from .vfs import BsaArchive
        arc = BsaArchive(p)
        for k, e in sorted(arc.entries.items()):
            print(f"{e.size:10d} {k}")
    return 0


def cmd_scan(a):
    from .install import InstallConfig, from_morrowind_dir, from_openmw_cfg
    from .scan import scan
    cfg = from_openmw_cfg(a.openmw_cfg) if a.openmw_cfg else from_morrowind_dir(a.morrowind) if a.morrowind \
        else InstallConfig()
    cfg.data_dirs += [str(Path(d).resolve()) for d in a.data or []]
    cfg.archives += [str(Path(x).resolve()) for x in a.archive or []]
    res = scan(cfg.data_dirs, cfg.archives, a.jobs, a.limit)
    Path(a.out).write_text(json.dumps(res, ensure_ascii=False, indent=1))
    print(f"plików {res['files']}, poprawnych {res['ok']}, błędnych {res['failed']} w {res['seconds']} s → {a.out}")
    for g, v in list(res["error_groups"].items())[:10]:
        print(f"  {v['count']:5d} × {g}")
    return 0 if res["failed"] == 0 else 1


def main(argv=None):
    ap = argparse.ArgumentParser(prog="mwconv", description="Konwerter danych Morrowinda dla projektu MWGodot")
    sp = ap.add_subparsers(dest="cmd", required=True)
    c = sp.add_parser("convert", help="konwersja instalacji")
    c.add_argument("--openmw-cfg")
    c.add_argument("--morrowind", help="katalog gry (z 'Data Files' i Morrowind.ini)")
    c.add_argument("--data", action="append", help="katalog danych (można powtarzać)")
    c.add_argument("--archive", action="append", help="archiwum BSA (można powtarzać)")
    c.add_argument("--content", action="append", help="ESM/ESP w kolejności ładowania")
    c.add_argument("--cell", action="append", help="nazwa komórki, np. Balmora (dopasowuje też 'Balmora, ...')")
    c.add_argument("--grid", action="append", help="komórka zewnętrzna x,y")
    c.add_argument("--grid-range", help="x0,y0,x1,y1")
    c.add_argument("--all-cells", action="store_true")
    c.add_argument("--all-models", action="store_true", help="konwertuj wszystkie NIF z VFS")
    c.add_argument("--all-textures", action="store_true", help="konwertuj wszystkie tekstury z VFS")
    c.add_argument("--out", required=True)
    c.add_argument("--jobs", type=int, default=0, help="liczba procesów (domyślnie min(4, CPU))")
    c.add_argument("--verify-hash", action="store_true", help="zawsze licz SHA-256 (bez skrótu rozmiar+mtime)")
    c.set_defaults(fn=cmd_convert)
    n = sp.add_parser("nif2glb", help="jeden NIF → GLB")
    n.add_argument("input")
    n.add_argument("-o", "--output")
    n.add_argument("--textures", action="append", help="katalog z teksturami")
    n.set_defaults(fn=cmd_nif2glb)
    s = sp.add_parser("synth", help="syntetyczne dane testowe")
    s.add_argument("--out", required=True)
    s.add_argument("--patch2", action="store_true", help="dodatkowy plugin (test ponownego importu)")
    s.set_defaults(fn=cmd_synth)
    i = sp.add_parser("inspect", help="podgląd pliku (NIF/KF/ESM/ESP/BSA); przy błędzie NIF – lokalizacja i zrzut bajtów")
    i.add_argument("input")
    i.add_argument("--convert", action="store_true", help="NIF: pokaż też raport konwersji")
    sc = sp.add_parser("scan", help="odczyt i konwersja w pamięci wszystkich NIF/KF z VFS → raport problemów")
    sc.add_argument("--openmw-cfg")
    sc.add_argument("--morrowind")
    sc.add_argument("--data", action="append")
    sc.add_argument("--archive", action="append")
    sc.add_argument("--jobs", type=int, default=0)
    sc.add_argument("--limit", type=int, default=0)
    sc.add_argument("--out", default="nif_scan.json")
    sc.set_defaults(fn=cmd_scan)
    i.set_defaults(fn=cmd_inspect)
    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
