#!/usr/bin/env python3
"""Wektory testowe kompilatora MWScript w grze: własne źródła (bez tekstów gry) skompilowane kompilatorem
konwertera (mwscript.compile_script) → godot/tests/data/mwscript_vectors.json. test_console porównuje z tym
wynik mw_mwscript_compiler.gd. Użycie: python3 tools/gen_mwscript_vectors.py"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "converter"))
from mwconv.mwscript import compile_script

SOURCES = {
    "basic": 'begin t\nshort a\nfloat b ; komentarz\nset a to 1 + 2 * 3\nset b to ( a - 1 ) / 2\nif ( a == 7 )\n  set a to -a\nelseif a >= 3\n  return\nelse\n  set b to 0\nendif\nend t\n',
    "calls": 'begin c\nshort s\nif ( OnActivate == 1 )\n  "foo_npc"->AddItem "gold_001" 25\n  player->ModCurrentHealth -10\n  MessageBox "Got %g gold" s\n  set s to player->GetItemCount "gold_001"\n  Journal "q_x" 20\nendif\nset s to GetDistance player\nset "foo".state to 5\nset foo.state to s * 2\nwhile ( s > 0 )\n  set s to s - 1\nendwhile\nend\n',
    "console1": 'player->additem gold_001 100',
    "console2": 'coc "Seyda Neen"',
    "console3": 'set foo to GetPos x',
    "console4": 'player->setpos, x, 100',
    "console5": 'tgm',
    "console6": 'getpcrank "Fighters Guild"',
    "console7": 'if ( GetJournalIndex "A1_1" >= 10 ) \n startscript foo\nendif',
    "console8": 'player->setstrength 50\nplayer->getstrength',
    "console9": 'AddSpell "fire bite"\nCast "fire bite" player',
    "console10": '"sid"->(GetHealth) + 1',
    "errors": 'set\nset a\nendwhile\nfoo->\n',
}
out = {k: compile_script(v, k) for k, v in SOURCES.items()}
for v in out.values():
    v["functions"] = sorted(v["functions"])
path = os.path.join(ROOT, "godot", "tests", "data", "mwscript_vectors.json")
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"sources": SOURCES, "compiled": out}, f, ensure_ascii=False, indent=1)
os.replace(tmp, path)
print(path, len(out))
