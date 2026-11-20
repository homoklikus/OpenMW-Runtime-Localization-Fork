#!/usr/bin/env python3
"""Generuje godot/scripts/mw/mw_mwscript_sig.gd z converter/mwconv/mwscript_sig.py i mwscript.py (tabele sygnatur
OpenMW, arność funkcji w wyrażeniach) – dla kompilatora MWScript konsoli w grze (mw_mwscript_compiler.gd).
Użycie: python3 tools/gen_gd_mwscript_sig.py"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "converter"))
from mwconv.mwscript_sig import SIG
from mwconv.mwscript import EXPR_ARITY, OPTIONAL_STR, VARIABLE_EVENTS, KEYWORDS

def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

out = ["# Plik generowany: tools/gen_gd_mwscript_sig.py – nie edytować ręcznie.",
       "# Sygnatury instrukcji i funkcji MWScript z OpenMW 0.51 (components/compiler/extensions0.cpp):",
       "# nazwa → [rodzaj \"f\"|\"i\", typ wyniku, argumenty]; EXPR_ARITY – stała liczba argumentów funkcji w wyrażeniach.",
       "extends RefCounted", "", "const SIG := {"]
for k in sorted(SIG):
    a, b, c = SIG[k]
    out.append("\t%s: [%s, %s, %s]," % (q(k), q(a), q(b), q(c)))
out.append("}")
out.append("")
out.append("const EXPR_ARITY := {")
for k in sorted(EXPR_ARITY):
    out.append("\t%s: %d," % (q(k), EXPR_ARITY[k]))
out.append("}")
out.append("")
out.append("const OPTIONAL_STR := [%s]" % ", ".join(q(x) for x in sorted(OPTIONAL_STR)))
out.append("const VARIABLE_EVENTS := [%s]" % ", ".join(q(x) for x in sorted(VARIABLE_EVENTS)))
out.append("const KEYWORDS := [%s]" % ", ".join(q(x) for x in sorted(KEYWORDS)))
path = os.path.join(ROOT, "godot", "scripts", "mw", "mw_mwscript_sig.gd")
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
os.replace(tmp, path)
print(path, len(SIG), len(EXPR_ARITY))
