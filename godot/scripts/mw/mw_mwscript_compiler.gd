extends RefCounted
## Kompilator MWScript w grze (konsola, Console::compile): wiersze źródła → drzewo składni takie samo jak z konwertera
## (converter/mwconv/mwscript.py, COMPILER_VERSION 4) – wykonywane przez mw_scripts._exec. Port 1:1 parsera Pythona:
## tokenizer, wyrażenia (porównania, +−, */, minus jednoargumentowy, nawiasy), argumenty według sygnatur OpenMW
## (ExprParser::parseArguments), odniesienia „obiekt->Funkcja”, „"obiekt".zmienna”, instrukcje set/if/elseif/else/
## endif/while/endwhile/return i deklaracje short/long/float.

const S := preload("res://scripts/mw/mw_mwscript_sig.gd")

const _CMP := {"==": "==", "=": "==", "!=": "!=", "<>": "!=", "<": "<", "<=": "<=", ">": ">", ">=": ">="}

class Tok:
	var kind := ""
	var text := ""
	func _init(k: String, t: String) -> void:
		kind = k
		text = t

class P:
	var toks: Array = []
	var i := 0
	var locals: Dictionary = {}
	var used: Dictionary = {}
	var warnings: Array = []
	func peek(k := 0) -> Tok:
		var j := i + k
		return toks[j] if j < toks.size() else null
	func next() -> Tok:
		var t := peek()
		i += 1
		return t
	func at_end() -> bool:
		return i >= toks.size()

class ParseError:
	var msg := ""
	func _init(m: String) -> void:
		msg = m

var _err: ParseError = null      # pierwszy błąd bieżącego wiersza (GDScript bez wyjątków)

static var _re_tok: RegEx = null
static var _re_digit: RegEx = null

static func _token_re() -> RegEx:
	if _re_tok == null:
		_re_tok = RegEx.new()
		_re_tok.compile("\\s*(?:(?<str>\"[^\"]*\"?)|(?<arrow>->)|(?<dot>\\.[A-Za-z_][\\w']*)|(?<op>==|!=|<=|>=|<>|<|>|=|\\+|-|\\*|/|\\(|\\)|\\[|\\]|,)|(?<num>(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?(?![\\w]))|(?<id>[A-Za-z_][\\w'.\\-]*|\\d+[A-Za-z_][\\w'.\\-]*)|(?<other>\\S))")
		_re_digit = RegEx.new()
		_re_digit.compile("^\\d")
	return _re_tok

static func tokenize(line: String) -> Array:
	var re := _token_re()
	var out := []
	var pos := 0
	line = line.rstrip(" \t")
	while pos < line.length():
		var m := re.search(line, pos)
		if m == null or m.get_start() != pos or m.get_end() == pos:
			break
		pos = m.get_end()
		var k := ""
		for g in ["str", "arrow", "dot", "op", "num", "id", "other"]:
			if m.get_start(g) >= 0:
				k = g
				break
		if k.is_empty():
			continue
		var t := m.get_string(k)
		if k == "other" and t == ":":
			continue                                   # „:” jak biały znak
		if k == "op" and t in ["[", "]"]:
			t = "(" if t == "[" else ")"
		if k == "dot":
			k = "id"
		if k == "str":
			t = t.substr(1, t.length() - 2) if t.ends_with("\"") and t.length() > 1 else t.substr(1)
		elif k == "id":
			if t.ends_with("-") and line.substr(pos, 1) == ">":
				t = t.left(-1)
				pos -= 1
		out.append(Tok.new(k, t))
	return out

static func strip_comment(line: String) -> String:
	var q := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			q = not q
		elif ch == ";" and not q:
			return line.left(i)
	return line

static func _is(t: Tok, kind: String, text = null) -> bool:
	return t != null and t.kind == kind and (text == null or t.text.to_lower() == String(text))

func _fail(m: String) -> void:
	if _err == null:
		_err = ParseError.new(m)

func _skip_commas(p: P) -> void:
	while _is(p.peek(), "op", ","):
		p.next()

func parse_expr(p: P):
	var a = _additive(p)
	var t := p.peek()
	if t != null and t.kind == "op" and _CMP.has(t.text):
		p.next()
		var b = _additive(p)
		return ["bin", _CMP[t.text], a, b]
	return a

func _additive(p: P):
	var a = _term(p)
	while _is(p.peek(), "op", "+") or _is(p.peek(), "op", "-"):
		var op := p.next().text
		a = ["bin", op, a, _term(p)]
	return a

func _term(p: P):
	var a = _unary(p)
	while _is(p.peek(), "op", "*") or _is(p.peek(), "op", "/"):
		var op := p.next().text
		a = ["bin", op, a, _unary(p)]
	return a

func _unary(p: P):
	if _is(p.peek(), "op", "-"):
		p.next()
		var v = _unary(p)
		return ["num", -float(v[1])] if v[0] == "num" else ["neg", v]
	return _primary(p)

static func _member_or_id(text: String) -> Array:
	_token_re()
	if "." in text and _re_digit.search(text) == null:
		var k := text.rfind(".")
		var obj := text.left(k)
		var v := text.substr(k + 1)
		if not obj.is_empty() and not v.is_empty():
			return ["member", obj.to_lower(), v.to_lower()]
	return ["id", text]

func _primary(p: P):
	var t := p.next()
	if t == null:
		_fail("incomplete expression")
		return ["num", 0.0]
	if t.kind == "num":
		return ["num", float(t.text)]
	if t.kind == "op" and t.text == "(":
		var e = parse_expr(p)
		if _is(p.peek(), "op", ")"):
			p.next()
		return e
	if t.kind == "str" or t.kind == "id":
		if _is(p.peek(), "arrow"):
			p.next()
			if _is(p.peek(), "op", "("):
				return ["ref", t.text.to_lower(), _primary(p)]
			var f := p.next()
			if f == null or f.kind != "id":
				_fail("missing function after ->")
				return ["num", 0.0]
			var fl := f.text.to_lower()
			if not S.SIG.has(fl) and not S.EXPR_ARITY.has(fl):
				p.warnings.append("stray explicit reference before '%s'" % f.text)
				return ["id", f.text] if p.locals.has(fl) else _member_or_id(f.text)
			return _expr_call(p, t.text.to_lower(), fl)
		if t.kind == "str":
			if _is(p.peek(), "id") and p.peek().text.begins_with("."):
				var v := p.next().text.substr(1)
				return ["member", t.text.to_lower(), v.to_lower()]
			return ["str", t.text]
		var low := t.text.to_lower()
		if p.locals.has(low):
			return ["id", t.text]
		if S.SIG.has(low) and String(S.SIG[low][0]) == "f":
			return _expr_call(p, null, low)
		if S.SIG.has(low):
			return _member_or_id(t.text)
		if S.EXPR_ARITY.has(low) and not low in S.VARIABLE_EVENTS:
			return _expr_call(p, null, low)
		return _member_or_id(t.text)
	_fail("unexpected symbol '%s'" % t.text)
	return ["num", 0.0]

func _arg(p: P):
	if p.peek() == null:
		return null
	var a = _arg_operand(p)
	while _is(p.peek(), "op", "*") or _is(p.peek(), "op", "/"):
		var op := p.next().text
		a = ["bin", op, a, _arg_operand(p)]
	return a

func _arg_operand(p: P):
	var t := p.peek()
	if t == null:
		_fail("missing argument")
		return ["num", 0.0]
	if _is(t, "op", "("):
		return _primary(p)
	if _is(t, "op", "-"):
		p.next()
		var v = _arg_operand(p)
		return ["num", -float(v[1])] if v[0] == "num" else ["neg", v]
	if _is(t, "op", "+"):
		p.next()
		return _arg_operand(p)
	if t.kind == "num":
		p.next()
		return ["num", float(t.text)]
	if t.kind == "str" and not _is(p.peek(1), "arrow"):
		p.next()
		if _is(p.peek(), "id") and p.peek().text.begins_with("."):
			return ["member", t.text.to_lower(), p.next().text.substr(1).to_lower()]
		return ["str", t.text]
	if t.kind in ["id", "str"]:
		return _primary(p)
	p.next()
	_fail("unexpected argument '%s'" % t.text)
	return ["num", 0.0]

func _string_arg(p: P, lower: bool):
	var t := p.peek()
	if t == null or not t.kind in ["id", "str", "num"]:
		return null
	p.next()
	return ["str", t.text.to_lower() if lower else t.text]

func _starts_operand(p: P, allow_sign: bool) -> bool:
	var t := p.peek()
	if t == null:
		return false
	if t.kind in ["num", "id", "str"]:
		return true
	return _is(t, "op", "(") or (allow_sign and (_is(t, "op", "-") or _is(t, "op", "+")))

func _args_by_sig(p: P, spec: String) -> Array:
	var args := []
	var optional := false
	for ch in spec:
		_skip_commas(p)
		if ch == "/":
			optional = true
			continue
		if ch in ["c", "S", "x"]:
			var a = _string_arg(p, ch == "c")
			if a == null:
				if optional or ch == "x":
					break
				_fail("missing string argument")
				break
			if ch != "x":
				args.append(a)
			continue
		if ch in ["X", "z"]:
			if not _starts_operand(p, false):
				break
			if ch == "X":
				_arg(p)
			else:
				p.next()
			continue
		if ch == "j":
			continue
		if not _starts_operand(p, true):
			if optional:
				break
			_fail("missing numeric argument")
			break
		args.append(_arg(p))
	return args

func _expr_call(p: P, ref, name: String) -> Array:
	p.used[name] = true
	if S.SIG.has(name):
		return ["call", ref, name, _args_by_sig(p, String(S.SIG[name][2]))]
	var args := []
	for _i in int(S.EXPR_ARITY.get(name, 0)):
		_skip_commas(p)
		if p.at_end():
			break
		var a = _arg(p)
		if a == null:
			break
		args.append(a)
	if name in S.OPTIONAL_STR and p.peek() != null and p.peek().kind == "str":
		args.append(["str", p.next().text])
	return ["call", ref, name, args]

func _stmt_call(p: P, ref, name: String) -> Array:
	p.used[name] = true
	if S.SIG.has(name) and name != "messagebox":
		return ["call", ref, name, _args_by_sig(p, String(S.SIG[name][2]))]
	var args := []
	while not p.at_end():
		_skip_commas(p)
		if p.at_end():
			break
		var t := p.peek()
		if t.kind == "num":
			p.next()
			args.append(["num", float(t.text)])
		elif t.kind == "str":
			p.next()
			args.append(["str", t.text])
		elif t.kind == "id":
			p.next()
			args.append(_member_or_id(t.text))
		elif _is(t, "op", "-") and p.peek(1) != null and p.peek(1).kind == "num":
			p.next()
			args.append(["num", -float(p.next().text)])
		elif _is(t, "op", "("):
			args.append(_primary(p))
		else:
			p.next()
			_fail("unexpected argument '%s'" % t.text)
			break
	return ["call", ref, name, args]

static func _stmts_ref(top: Array) -> Array:
	var kind: String = top[0]
	var node = top[1]
	match kind:
		"root": return node
		"if": return node[1][node[1].size() - 1][1]
		"ifelse": return node[2]
		"while": return node[2]
	return node

## compile_script: źródło → {"name", "locals", "body", "errors", "warnings", "functions"}.
## locals_in – zmienne lokalne skryptu wybranego obiektu (Console: getLocals(script)).
func compile(src: String, name := "", locals_in := {}) -> Dictionary:
	var locals_: Dictionary = locals_in.duplicate()
	var errors := []
	var warnings := []
	var used := {}
	var root := []
	var stack := [["root", root]]
	var sname := name
	var ln := 0
	for raw in src.replace("\r", "").split("\n"):
		ln += 1
		var line := strip_comment(raw).strip_edges()
		if line.is_empty():
			continue
		var toks := tokenize(line)
		if toks.is_empty():
			continue
		var p := P.new()
		p.toks = toks
		p.locals = locals_
		p.used = used
		_err = null
		var first: Tok = toks[0]
		var kw := first.text.to_lower() if first.kind == "id" else ""
		var cur := _stmts_ref(stack.back())
		match kw:
			"begin":
				if toks.size() > 1:
					sname = (toks[1] as Tok).text
				continue
			"end":
				if stack.size() == 1:
					continue
		if kw in ["short", "long", "float"] and toks.size() >= 2 and (toks[1] as Tok).kind == "id":
			for t in toks.slice(1):
				if (t as Tok).kind == "id":
					locals_[(t as Tok).text.to_lower()] = kw
			continue
		if kw == "set":
			p.next()
			var tgt := p.next()
			if tgt == null or not tgt.kind in ["id", "str"]:
				_fail("set: missing target")
			else:
				var target: Array
				if tgt.kind == "str" and _is(p.peek(), "id") and p.peek().text.begins_with("."):
					target = ["member", tgt.text.to_lower(), p.next().text.substr(1).to_lower()]
				else:
					target = _member_or_id(tgt.text)
					if target[0] == "id":
						target[1] = String(target[1]).to_lower()
				if _is(p.peek(), "arrow"):
					p.next()
					var v := p.next()
					target = ["member", tgt.text.to_lower(), v.text.to_lower() if v != null else ""]
				if not _is(p.peek(), "id", "to"):
					_fail("set: missing 'to'")
				else:
					p.next()
					var e = parse_expr(p)
					if _err == null:
						cur.append(["set", target, e])
		elif kw == "if":
			p.next()
			var node := ["if", [[parse_expr(p), []]], []]
			if _err == null:
				cur.append(node)
				stack.append(["if", node])
		elif kw == "elseif":
			p.next()
			if String(stack.back()[0]) != "if":
				warnings.append("%s:%d: elseif without if – ignored" % [sname, ln])
			else:
				var ce = parse_expr(p)
				if _err == null:
					stack.back()[1][1].append([ce, []])
		elif kw == "else":
			if String(stack.back()[0]) != "if":
				warnings.append("%s:%d: else without if – ignored" % [sname, ln])
			else:
				stack[stack.size() - 1] = ["ifelse", stack.back()[1]]
		elif kw == "endif":
			if not String(stack.back()[0]) in ["if", "ifelse"]:
				warnings.append("%s:%d: superfluous endif – ignored" % [sname, ln])
			else:
				stack.pop_back()
		elif kw == "while":
			p.next()
			var wn := ["while", parse_expr(p), []]
			if _err == null:
				cur.append(wn)
				stack.append(["while", wn])
		elif kw == "endwhile":
			if String(stack.back()[0]) != "while":
				_fail("endwhile without while")
			else:
				stack.pop_back()
		elif kw == "return":
			cur.append(["return"])
		else:
			var t0 := p.next()
			if _is(p.peek(), "arrow"):
				p.next()
				var f := p.next()
				if f == null or f.kind != "id":
					_fail("missing function after ->")
				else:
					var st := _stmt_call(p, t0.text.to_lower(), f.text.to_lower())
					if _err == null:
						cur.append(st)
			elif t0.kind == "id" and locals_.has(t0.text.to_lower()) and not S.SIG.has(t0.text.to_lower()):
				warnings.append("%s:%d: variable without 'set' – line ignored" % [sname, ln])
			elif t0.kind == "id":
				var st2 := _stmt_call(p, null, t0.text.to_lower())
				if _err == null:
					cur.append(st2)
			elif _is(t0, "op", "("):
				warnings.append("%s:%d: bare expression without instruction – ignored" % [sname, ln])
			else:
				_fail("unknown instruction '%s'" % t0.text)
		if _err != null:
			errors.append("%s:%d: %s | %s" % [sname, ln, _err.msg, raw.strip_edges().left(80)])
		for w in p.warnings:
			warnings.append("%s:%d: %s" % [sname, ln, w])
	if stack.size() > 1:
		errors.append("%s: unclosed blocks (%d)" % [sname, stack.size() - 1])
	return {"name": sname, "locals": locals_, "body": root, "errors": errors, "warnings": warnings, "functions": used.keys()}
