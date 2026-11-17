#!/usr/bin/env python3
"""Tabela sygnatur MWScript z kodu OpenMW (components/compiler/extensions0.cpp, opcodes.hpp) →
converter/mwconv/mwscript_sig.py. Uruchomienie: python3 tools/gen_mwscript_signatures.py ŚCIEŻKA_DO_OPENMW

Znaczenie znaków argumentów (ExprParser::parseArguments): c – nazwa/identyfikator (małe litery), S – tekst,
l/s – liczba całkowita (wyrażenie), f – liczba rzeczywista (wyrażenie), / – dalej argumenty opcjonalne,
x – opcjonalny tekst pomijany, X – opcjonalne wyrażenie pomijane, z – opcjonalny argument pomijany,
j – śmieć pomijany (Choice). Funkcje (kind "f") zwracają wartość typu ret (l/f), instrukcje (kind "i") nie."""
import re
import sys
from pathlib import Path


def build(root: Path) -> dict:
    src = re.sub(r"\s+", " ", (root / "components/compiler/extensions0.cpp").read_text())
    ops = (root / "components/compiler/opcodes.hpp").read_text()
    sig = {}
    for m in re.finditer(r'registerFunction\(\s*"(\w+)",\s*\'(\w)\',\s*"([^"]*)"', src):
        sig[m.group(1)] = ("f", m.group(2), m.group(3))
    for m in re.finditer(r'registerInstruction\(\s*"(\w+)",\s*"([^"]*)"', src):
        sig[m.group(1)] = ("i", "", m.group(2))

    def arr(name, text):
        m = re.search(name + r"\[[^\]]*\]\s*=\s*\{([^}]*)\}", text)
        return re.findall(r'"(\w+)"', m.group(1)) if m else []
    for c in arr("controls", ops):
        sig["enable" + c] = ("i", "", "")
        sig["disable" + c] = ("i", "", "")
        sig["get" + c + "disabled"] = ("f", "l", "")
    stats = (root / "components/compiler/extensions0.cpp").read_text()
    for a in arr("attributes", stats):
        sig["get" + a] = ("f", "f", "")
        sig["set" + a] = ("i", "", "f")
        sig["mod" + a] = ("i", "", "f")
    for d in arr("dynamics", stats):
        sig["get" + d] = ("f", "f", "x")
        sig["set" + d] = ("i", "", "f")
        sig["mod" + d] = ("i", "", "f")
        sig["modcurrent" + d] = ("i", "", "f")
        sig["get" + d + "getratio"] = ("f", "f", "")
    for s in arr("skills", stats):
        sig["get" + s] = ("f", "f", "")
        sig["set" + s] = ("i", "", "f")
        sig["mod" + s] = ("i", "", "f")
    for e in arr("magicEffects", stats):
        sig["get" + e] = ("f", "l", "")
        sig["set" + e] = ("i", "", "l")
        sig["mod" + e] = ("i", "", "l")
    return sig


def build_refs(root: Path, sig: dict) -> dict:
    """Odniesienie do obiektu: nazwa → "r" (wymagane – bez jawnego odniesienia w skrypcie globalnym
    MissingImplicitRefError przerywa skrypt) albo "o" (opcjonalne: R()(runtime, false) / !R::implicit).
    Funkcje bez wariantu z odniesieniem (opcode…Explicit) nie mają wpisu."""
    ext = re.sub(r"\s+", " ", (root / "components/compiler/extensions0.cpp").read_text())
    op_of = {}
    for m in re.finditer(r'register(?:Function|Instruction)\(\s*"(\w+)",[^;]*?,\s*(opcode\w+),\s*(opcode\w+Explicit)\s*\)', ext):
        op_of[m.group(2)] = m.group(1)
    cls_of = {}
    bodies = {}
    for f in sorted((root / "apps/openmw/mwscript").glob("*.cpp")):
        t = f.read_text()
        for m in re.finditer(r"install\w+<(\w+)<ImplicitRef>\s*>\(\s*Compiler::\w+::(opcode\w+)", t):
            cls_of[m.group(2)] = m.group(1)
        for m in re.finditer(r"class (Op\w+) : public Interpreter::Opcode\d", t):
            end = t.find("\n        };", m.end())
            bodies[m.group(1)] = t[m.end():end if end > 0 else m.end() + 4000]
    refs = {}
    for op, name in op_of.items():
        body = bodies.get(cls_of.get(op, ""), "")
        refs[name] = "o" if ("R()(runtime, false)" in body or "R()(runtime, !R::implicit)" in body) else "r"
    # rodziny statystyk (pętle w extensions0: opcodeGet/Set/Mod… + i) – zawsze R()(runtime)
    for k, v in sig.items():
        if k not in refs and re.match(r"(get|set|mod|modcurrent)(\w+)$", k) and v[0] in ("f", "i"):
            fam = k
            for pre in ("modcurrent", "get", "set", "mod"):
                if k.startswith(pre):
                    fam = k[len(pre):]
                    break
            if fam.endswith("getratio") or fam in _FAMILY:
                refs[k] = "r"
    return refs


_FAMILY = set()


def main(argv):
    root = Path(argv[1] if len(argv) > 1 else ".")
    sig = build(root)
    stats = (root / "components/compiler/extensions0.cpp").read_text()
    for name in ("attributes", "dynamics", "skills", "magicEffects"):
        m = re.search(name + r"\[[^\]]*\]\s*=\s*\{([^}]*)\}", stats)
        _FAMILY.update(re.findall(r'"(\w+)"', m.group(1)) if m else [])
    refs = build_refs(root, sig)
    gd = Path(__file__).resolve().parents[1] / "godot/scripts/mw/mw_script_refs.gd"
    gl = ['extends RefCounted', '## Odniesienie do obiektu w funkcjach MWScript (z kodu OpenMW: extensions0.cpp + mwscript/*.cpp) –',
          '## plik generowany: tools/gen_mwscript_signatures.py. "r" – wymagane (bez obiektu w skrypcie globalnym',
          '## MissingImplicitRefError przerywa i zatrzymuje skrypt), "o" – opcjonalne.', 'const REF := {']
    gl += [f'\t"{k}": "{refs[k]}",' for k in sorted(refs)]
    gl += ['}', '']
    gd.write_text("\n".join(gl), encoding="utf-8")
    out = Path(__file__).resolve().parents[1] / "converter/mwconv/mwscript_sig.py"
    lines = ['"""Sygnatury instrukcji i funkcji MWScript z OpenMW (components/compiler/extensions0.cpp) – plik',
             'generowany: tools/gen_mwscript_signatures.py. nazwa → (rodzaj "f"|"i", typ wyniku, argumenty)."""',
             "", "SIG = {"]
    for k in sorted(sig):
        lines.append(f"    {k!r}: {sig[k]!r},")
    lines.append("}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(sig)} sygnatur → {out}")


if __name__ == "__main__":
    main(sys.argv)
