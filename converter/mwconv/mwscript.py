"""MWScript (etap 5): kompilator źródeł skryptów Morrowinda (SCTX) do drzewa składni (JSON) wykonywanego przez grę.

Składnia jak w OpenMW (components/compiler): wielkość liter bez znaczenia, komentarze „;”, instrukcje w wierszach:
  begin/end, short|long|float <nazwa>, set <cel> to <wyrażenie>, if/elseif/else/endif, while/endwhile, return,
  wywołania funkcji z opcjonalnym odniesieniem: [<obiekt> ->] Funkcja arg arg … (argumenty oddzielane spacjami
  lub przecinkami). W wyrażeniach funkcje mają stałą liczbę argumentów (tabela EXPR_ARITY); nieznane – 0.
  Tolerancja jak w OpenMW: „=” w warunku znaczy „==”, nawiasy przy if/while opcjonalne, nadmiarowe przecinki.

Węzły (listy JSON):
  instrukcje: ["set", cel, wyr], ["if", [[warunek, [instr]], …], [instr_else]], ["while", warunek, [instr]],
              ["return"], ["call", odniesienie|None, nazwa, [argumenty]]
  wyrażenia:  ["num", v], ["str", s], ["id", nazwa] (zmienna albo identyfikator – rozstrzyga gra),
              ["member", obiekt, zmienna], ["call", odniesienie|None, nazwa, [argumenty]], ["bin", op, a, b],
              ["neg", a]
  cel:        ["id", nazwa] albo ["member", obiekt, zmienna]
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

_ATTRS = ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
_SKILLS = ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear", "athletics",
           "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration", "alchemy",
           "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman", "mercantile",
           "speechcraft", "handtohand"]
_RESIST = ["resistblight", "resistcorprus", "resistdisease", "resistfire", "resistfrost", "resistmagicka",
           "resistnormalweapons", "resistparalysis", "resistpoison", "resistshock"]

# funkcje używane w wyrażeniach: liczba argumentów (stała); OPTIONAL_STR – opcjonalny argument tekstowy
EXPR_ARITY: dict[str, int] = {
    "getjournalindex": 1, "getitemcount": 1, "getdistance": 1, "getpos": 1, "getangle": 1, "getstartingpos": 1,
    "getstartingangle": 1, "scriptrunning": 1, "getpccell": 1, "getdeadcount": 1, "getspell": 1,
    "getspelleffects": 1, "getrace": 1, "getlineofsight": 1, "getlos": 1, "getdetected": 1, "random": 1,
    "getsquareroot": 1, "hasitemequipped": 1, "hassoulgem": 1, "getarmortype": 1, "getweapontype": 0,
    "getfactionreaction": 2, "getitemcountd": 1, "getsoundplaying": 1, "getcurrentaipackage": 0,
    "getpcrank": 0, "getpcfacrep": 0, "pcexpelled": 0, "getreputation": 0, "samefaction": 0, "getdisposition": 0,
    "getlevel": 0, "gethealth": 0, "getmagicka": 0, "getfatigue": 0, "gethealthgetratio": 0,
    "getbuttonpressed": 0, "getsecondspassed": 0, "getdisabled": 0, "getlocked": 0, "onactivate": 0,
    "ondeath": 0, "onknockout": 0, "onmurder": 0, "onpcadd": 0, "onpcdrop": 0, "onpcequip": 0, "onpchitme": 0,
    "onpcsoulgemuse": 0, "onpcrepair": 0, "menumode": 0, "cellchanged": 0, "getpcsleep": 0, "getpcjumping": 0,
    "getpcrunning": 0, "getpcsneaking": 0, "getforcesneak": 0, "getforcerun": 0, "getforcejump": 0,
    "getforcemovejump": 0, "getcommondisease": 0, "getblightdisease": 0, "getcurrenttime": 0,
    "getcurrentweather": 0, "getmasserphase": 0, "getsecundaphase": 0, "getwaterwalking": 0, "getwaterlevel": 0,
    "getstandingpc": 0, "getstandingactor": 0, "getcollidingpc": 0, "getcollidingactor": 0, "getpcinjail": 0,
    "getpctraveling": 0, "getplayercontrolsdisabled": 0, "getplayerfightingdisabled": 0,
    "getplayermagicdisabled": 0, "getplayerviewswitch": 0, "getvanitymodedisabled": 0, "getattacked": 0,
    "getscale": 0, "getwerewolfkills": 0, "iswerewolf": 0, "getpcvisionbonus": 0, "getinterior": 0,
    "getpccrimelevel": 0, "getweapondrawn": 0, "getspellreadied": 0, "getsilence": 0, "getsuperjump": 0,
    "getflee": 0, "getfight": 0, "gethello": 0, "getalarm": 0, "getdefaultlevel": 0, "getpcvisionbonus": 0,
    "getcastpenalty": 0, "getcurrentmagicka": 0,
}
for _a in _ATTRS + _SKILLS + _RESIST:
    EXPR_ARITY["get" + _a] = 0
OPTIONAL_STR = {"getpcrank", "getpcfacrep", "pcexpelled"}

KEYWORDS = {"begin", "end", "short", "long", "float", "set", "to", "if", "elseif", "else", "endif", "while",
            "endwhile", "return"}

_TOKEN = re.compile(r'''
    \s*(?:
      (?P<str>"[^"]*"?)
    | (?P<arrow>->)
    | (?P<op>==|!=|<=|>=|<>|<|>|=|\+|-|\*|/|\(|\)|,)
    | (?P<num>(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?(?![\w]))
    | (?P<id>[A-Za-z_][\w'.\-]*|\d+[A-Za-z_][\w'.\-]*)
    | (?P<other>\S)
    )''', re.X)


@dataclass
class Tok:
    kind: str
    text: str


def tokenize(line: str) -> list[Tok]:
    out = []
    pos = 0
    line = line.rstrip()
    while pos < len(line):
        m = _TOKEN.match(line, pos)
        if not m or m.end() == pos:
            break
        pos = m.end()
        k = m.lastgroup
        if k is None:
            continue
        t = m.group(k)
        if k == "str":
            t = t[1:-1] if t.endswith('"') and len(t) > 1 else t[1:]
        elif k == "id":
            # identyfikator zakończony „-” przed „>” to strzałka („obj->F”)
            if t.endswith("-") and line[pos:pos + 1] == ">":
                t = t[:-1]
                pos -= 1
        out.append(Tok(k, t))
    return out


def strip_comment(line: str) -> str:
    q = False
    for i, ch in enumerate(line):
        if ch == '"':
            q = not q
        elif ch == ";" and not q:
            return line[:i]
    return line


class ParseError(Exception):
    pass


@dataclass
class _P:
    toks: list
    i: int = 0
    used: set = field(default_factory=set)

    def peek(self, k=0) -> Optional[Tok]:
        j = self.i + k
        return self.toks[j] if j < len(self.toks) else None

    def next(self) -> Optional[Tok]:
        t = self.peek()
        self.i += 1
        return t

    def at_end(self) -> bool:
        return self.i >= len(self.toks)


def _is(t: Optional[Tok], kind: str, text: Optional[str] = None) -> bool:
    return t is not None and t.kind == kind and (text is None or t.text.lower() == text)


def _skip_commas(p: _P):
    while _is(p.peek(), "op", ","):
        p.next()


_CMP = {"==": "==", "=": "==", "!=": "!=", "<>": "!=", "<": "<", "<=": "<=", ">": ">", ">=": ">="}


def parse_expr(p: _P):
    a = _additive(p)
    t = p.peek()
    if t is not None and t.kind == "op" and t.text in _CMP:
        p.next()
        b = _additive(p)
        return ["bin", _CMP[t.text], a, b]
    return a


def _additive(p: _P):
    a = _term(p)
    while _is(p.peek(), "op", "+") or _is(p.peek(), "op", "-"):
        op = p.next().text
        a = ["bin", op, a, _term(p)]
    return a


def _term(p: _P):
    a = _unary(p)
    while _is(p.peek(), "op", "*") or _is(p.peek(), "op", "/"):
        op = p.next().text
        a = ["bin", op, a, _unary(p)]
    return a


def _unary(p: _P):
    if _is(p.peek(), "op", "-"):
        p.next()
        v = _unary(p)
        return ["num", -v[1]] if v[0] == "num" else ["neg", v]
    return _primary(p)


def _member_or_id(text: str):
    if "." in text and not re.match(r"^\d", text):
        obj, _, var = text.rpartition(".")
        if obj and var:
            return ["member", obj.lower(), var.lower()]
    return ["id", text]


def _primary(p: _P):
    t = p.next()
    if t is None:
        raise ParseError("niepełne wyrażenie")
    if t.kind == "num":
        return ["num", float(t.text)]
    if t.kind == "op" and t.text == "(":
        e = parse_expr(p)
        if _is(p.peek(), "op", ")"):
            p.next()
        return e
    if t.kind == "str" or t.kind == "id":
        # odniesienie: "obiekt"->Funkcja / obiekt->Funkcja
        if _is(p.peek(), "arrow"):
            p.next()
            f = p.next()
            if f is None or f.kind != "id":
                raise ParseError("brak funkcji po ->")
            return _expr_call(p, t.text.lower(), f.text.lower())
        if t.kind == "str":
            # "obiekt".zmienna
            if _is(p.peek(), "id") and p.peek().text.startswith("."):
                v = p.next().text[1:]
                return ["member", t.text.lower(), v.lower()]
            return ["str", t.text]
        low = t.text.lower()
        if low in EXPR_ARITY:
            return _expr_call(p, None, low)
        return _member_or_id(t.text)
    raise ParseError(f"nieoczekiwany symbol {t.text!r}")


def _arg(p: _P):
    """Argument funkcji: liczba, tekst, identyfikator (bez rozwijania wywołań) albo wyrażenie w nawiasach."""
    t = p.peek()
    if t is None:
        return None
    if _is(t, "op", "("):
        return _primary(p)
    if _is(t, "op", "-") and p.peek(1) is not None and p.peek(1).kind == "num":
        p.next()
        return ["num", -float(p.next().text)]
    p.next()
    if t.kind == "num":
        return ["num", float(t.text)]
    if t.kind == "str":
        return ["str", t.text]
    if t.kind == "id":
        return _member_or_id(t.text)
    raise ParseError(f"nieoczekiwany argument {t.text!r}")


def _expr_call(p: _P, ref, name: str):
    p.used.add(name)
    args = []
    n = EXPR_ARITY.get(name, 0)
    for _ in range(n):
        _skip_commas(p)
        a = _arg(p)
        if a is None:
            break
        args.append(a)
    if name in OPTIONAL_STR and p.peek() is not None and p.peek().kind == "str":
        args.append(["str", p.next().text])
    return ["call", ref, name, args]


def _stmt_call(p: _P, ref, name: str):
    p.used.add(name)
    args = []
    while not p.at_end():
        _skip_commas(p)
        if p.at_end():
            break
        a = _arg(p)
        if a is None:
            break
        args.append(a)
    return ["call", ref, name, args]


def compile_script(src: str, name: str = "") -> dict:
    """Źródło skryptu → {"name", "locals": {nazwa: typ}, "body": [...], "errors": [...], "functions": [...]}."""
    locals_: dict = {}
    errors: list = []
    used: set = set()
    root: list = []
    stack: list = [("root", root)]          # (rodzaj, lista instrukcji | węzeł)
    sname = name
    for ln, raw in enumerate(src.replace("\r", "").split("\n"), 1):
        line = strip_comment(raw).strip()
        if not line:
            continue
        toks = tokenize(line)
        if not toks:
            continue
        p = _P(toks, used=used)
        first = toks[0]
        kw = first.text.lower() if first.kind == "id" else ""
        cur = _stmts_ref(stack[-1])
        try:
            if kw == "begin":
                if len(toks) > 1:
                    sname = toks[1].text
                continue
            if kw == "end" and len(stack) == 1:
                continue
            if kw in ("short", "long", "float") and len(toks) >= 2 and toks[1].kind == "id":
                for t in toks[1:]:
                    if t.kind == "id":
                        locals_[t.text.lower()] = kw
                continue
            if kw == "set":
                p.next()
                tgt = p.next()
                if tgt is None or tgt.kind not in ("id", "str"):
                    raise ParseError("set: brak celu")
                if tgt.kind == "str" and _is(p.peek(), "id") and p.peek().text.startswith("."):
                    target = ["member", tgt.text.lower(), p.next().text[1:].lower()]
                else:
                    target = _member_or_id(tgt.text)
                    if target[0] == "id":
                        target[1] = target[1].lower()
                if _is(p.peek(), "arrow"):              # set obiekt->zmienna to …
                    p.next()
                    v = p.next()
                    target = ["member", tgt.text.lower(), v.text.lower()]
                if not _is(p.peek(), "id", "to"):
                    raise ParseError("set: brak „to”")
                p.next()
                cur.append(["set", target, parse_expr(p)])
                continue
            if kw == "if":
                p.next()
                node = ["if", [[parse_expr(p), []]], []]
                cur.append(node)
                stack.append(("if", node))
                continue
            if kw == "elseif":
                p.next()
                if stack[-1][0] != "if":
                    raise ParseError("elseif bez if")
                stack[-1][1][1].append([parse_expr(p), []])
                continue
            if kw == "else":
                if stack[-1][0] != "if":
                    raise ParseError("else bez if")
                stack[-1] = ("ifelse", stack[-1][1])
                continue
            if kw == "endif":
                if stack[-1][0] not in ("if", "ifelse"):
                    raise ParseError("endif bez if")
                stack.pop()
                continue
            if kw == "while":
                p.next()
                node = ["while", parse_expr(p), []]
                cur.append(node)
                stack.append(("while", node))
                continue
            if kw == "endwhile":
                if stack[-1][0] != "while":
                    raise ParseError("endwhile bez while")
                stack.pop()
                continue
            if kw == "return":
                cur.append(["return"])
                continue
            # wywołanie z odniesieniem albo bez
            t0 = p.next()
            if _is(p.peek(), "arrow"):
                p.next()
                f = p.next()
                if f is None or f.kind != "id":
                    raise ParseError("brak funkcji po ->")
                cur.append(_stmt_call(p, t0.text.lower(), f.text.lower()))
            elif t0.kind == "id":
                cur.append(_stmt_call(p, None, t0.text.lower()))
            else:
                raise ParseError(f"nieznana instrukcja {t0.text!r}")
        except ParseError as e:
            errors.append(f"{sname or name}:{ln}: {e} | {raw.strip()[:80]}")
    if len(stack) > 1:
        errors.append(f"{sname or name}: niezamknięte bloki ({len(stack) - 1})")
    return {"name": sname or name, "locals": locals_, "body": root, "errors": errors,
            "functions": sorted(used)}


def _stmts_ref(stack_top):
    kind, node = stack_top
    if kind == "root":
        return node
    if kind == "if":
        return node[1][-1][1]
    if kind == "ifelse":
        return node[2]
    if kind == "while":
        return node[2]
    return node

