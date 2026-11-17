"""Etap 5: kompilator MWScript – składnia jak w OpenMW, tolerancja błędów spotykanych w Morrowind.esm."""
from mwconv.mwscript import compile_script, tokenize


def test_basic_tree():
    src = '''Begin Test ; komentarz
short doOnce
float timer, other
if ( GetDisabled == 0 )
    if ( ColonyState >= 3 )
        Disable
    elseif ( "fargoth"->GetItemCount "ring" > 0 )
        "fargoth"->AddItem gold_001, 10
    else
        set timer to timer + GetSecondsPassed * 2
    endif
endif
while ( doOnce < 3 )
    set doOnce to doOnce + 1
endwhile
set Fargoth.state to -1
set "Frald the White".days to "Frald the White".days + 1
MessageBox "Ile? %.0f;" timer "Ok"
End Test'''
    r = compile_script(src, "x")
    assert r["name"] == "Test" and r["errors"] == [] and r["locals"] == {"doonce": "short", "timer": "float", "other": "float"}
    b = r["body"]
    cond, inner = b[0][1][0]
    assert cond == ["bin", "==", ["call", None, "getdisabled", []], ["num", 0.0]]
    branches = inner[0][1]
    assert branches[0][1] == [["call", None, "disable", []]]
    assert branches[1][0] == ["bin", ">", ["call", "fargoth", "getitemcount", [["str", "ring"]]], ["num", 0.0]]
    assert branches[1][1] == [["call", "fargoth", "additem", [["str", "gold_001"], ["num", 10.0]]]]
    assert inner[0][2][0][0] == "set"
    assert b[1][0] == "while"
    assert b[2] == ["set", ["member", "fargoth", "state"], ["num", -1.0]]
    assert b[3][1] == ["member", "frald the white", "days"]
    assert b[4] == ["call", None, "messagebox", [["str", "Ile? %.0f;"], ["id", "timer"], ["str", "Ok"]]]
    assert "getitemcount" in r["functions"] and "messagebox" in r["functions"]


def test_signatures_like_openmw():
    """Argumenty według sygnatur OpenMW (extensions0.cpp): opcjonalne, pomijane, tryb argumentu (+/- kończą)."""
    r = compile_script("short a\nModHealth -10\nplayer->ModCurrentHealth a * 2\nGetDistance player\n"
                       "set a to GetDistance player + 5\nPlaceItemCell \"ring\" \"Seyda Neen\" 1 2 3 90 junk\n"
                       "Lock\nLock 50\nset a to Random 100 - 1\nAddItem gold_001 87 99\nOnPCAdd\n", "t")
    b = r["body"]
    assert b[0] == ["call", None, "modhealth", [["num", -10.0]]]
    assert b[1] == ["call", "player", "modcurrenthealth", [["bin", "*", ["id", "a"], ["num", 2.0]]]]
    assert b[2] == ["call", None, "getdistance", [["str", "player"]]]
    assert b[3][2] == ["bin", "+", ["call", None, "getdistance", [["str", "player"]]], ["num", 5.0]]
    assert b[4][3] == [["str", "ring"], ["str", "seyda neen"], ["num", 1.0], ["num", 2.0], ["num", 3.0], ["num", 90.0]]
    assert b[5][3] == [] and b[6][3] == [["num", 50.0]]
    assert b[7][2] == ["bin", "-", ["call", None, "random", [["num", 100.0]]], ["num", 1.0]]
    assert b[8][3] == [["str", "gold_001"], ["num", 87.0]]          # X – nadmiarowy argument pominięty
    r2 = compile_script("short OnPCAdd\nif ( OnPCAdd == 1 )\nset OnPCAdd to 0\nendif", "t")
    assert r2["body"][0][1][0][0] == ["bin", "==", ["id", "OnPCAdd"], ["num", 1.0]]   # zmienna, nie funkcja


def test_tolerance_like_openmw():
    r = compile_script('if [ CellChanged == 0]\nendif\nendif\n( GetDisabled == 1 )\nelse\nif x = 2\nendif', "t")
    assert r["errors"] == [] and len(r["warnings"]) == 3
    assert r["body"][1][1][0][0] == ["bin", "==", ["id", "x"], ["num", 2.0]]
    r = compile_script('if "ghost"->( OnDeath == 1 )\nendif\nset x to ( "a b"->GetAngle Z )', "t")
    assert r["body"][0][1][0][0][0] == "ref" and r["body"][1][2] == ["call", "a b", "getangle", [["str", "z"]]]


def test_tokens():
    t = [x.text for x in tokenize('player->AddItem "Gold_001" -5 ; x')]
    assert t[:3] == ["player", "->", "AddItem"]
    assert [x.kind for x in tokenize("a-> b")] == ["id", "arrow", "id"]


def test_colon_is_whitespace():
    r = compile_script('Choice: "Sell the item." 1 "Keep the item." 2', "d")
    assert r["errors"] == [] and r["body"] == [["call", None, "choice", [["str", "Sell the item."], ["num", 1.0],
                                                                       ["str", "Keep the item."], ["num", 2.0]]]]


def test_stray_explicit_reference_like_openmw():
    """ExprParser::parseName z mRefOp: obiekt->zmienna (nie funkcja) – odniesienie pominięte, zmienna lokalna."""
    r = compile_script("begin x\nshort fakeiswere\nif ( player->fakeiswere == 0 )\nset fakeiswere to 1\nendif\nend", "x")
    assert r["body"][0][1][0][0] == ["bin", "==", ["id", "fakeiswere"], ["num", 0.0]]
    assert r["warnings"] and "fakeiswere" not in r["functions"]

