extends RefCounted
## Teksty silnika jak l10n OpenMW (components/l10n): konteksty „OMWEngine” i „Calendar” z plików
## files/data/l10n/<kontekst>/*.yaml (część OpenMW, nie zasoby gry), skopiowanych do res://l10n. Język z ustawienia „preferred_locales” (OpenMW [General] preferred locales,
## domyślnie „en”); brakujący klucz – kolejne języki z listy, potem en.yaml, na końcu podany zapas.
## Obsługiwane: „Klucz: "tekst"”, bloki „|-” i podstawienia {nazwa}. Formy ICU (plural/select) – tylko gałąź
## „other”/pierwsza (w oknach używanych przez Godota nie występują).

const DIR := "res://l10n"

static var locales: PackedStringArray = ["en"]
static var _cache := {}
## Udawany język „gmst” (OpenMW: resources/vfs-mw/l10n/<kontekst>/gmst.yaml): klucz → GMST z danych gry.
## [General] gmst overrides l10n (domyślnie true): „gmst” przed preferowanymi językami, inaczej po nich
## (l10n::Manager::setPreferredLocales). gmst_lookup(id) → tekst GMST albo "" (brak rekordu).
static var gmst_first := true
static var gmst_lookup := Callable()

static func set_locales(spec: String) -> void:
	var out := PackedStringArray()
	for p in spec.split(",", false):
		var l := p.strip_edges().to_lower().replace("-", "_")
		if not l.is_empty():
			out.append(l)
			if l.contains("_"):
				out.append(l.split("_")[0])
	if not out.has("en"):
		out.append("en")
	locales = out

static func _load(ctx: String, lang: String) -> Dictionary:
	var ck := ctx + "/" + lang
	if _cache.has(ck):
		return _cache[ck]
	var d := {}
	var path := DIR.path_join(ctx).path_join(lang + ".yaml")
	if FileAccess.file_exists(path):
		d = parse_yaml(FileAccess.get_file_as_string(path), lang == "gmst")
	_cache[ck] = d
	return d

## Wartość skalarna YAML w cudzysłowach albo bez (komentarz „ # …” po wartości bez cudzysłowu pomijany).
static func _scalar(val: String) -> String:
	if val.begins_with("\""):
		var e := val.rfind("\"")
		if e > 0:
			return val.substr(1, e - 1).replace("\\\"", "\"").replace("\\n", "\n")
	elif val.begins_with("'"):
		var e2 := val.rfind("'")
		if e2 > 0:
			return val.substr(1, e2 - 1).replace("''", "'")
	var h := val.find(" #")
	return val.substr(0, h).strip_edges() if h >= 0 else val

## Minimalny parser YAML z plików l10n OpenMW: „Klucz: "tekst"”, bloki „|-”, a w gmst.yaml także mapy
## {pattern, variables} (MessageBundles::load). Wpis gmst: {"gmst": id} albo {"pattern": …, "variables": [[…], …]}.
static func parse_yaml(text: String, gmst := false) -> Dictionary:
	var d := {}
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		i += 1
		if ln.strip_edges().is_empty() or ln.strip_edges().begins_with("#") or ln.begins_with(" "):
			continue
		var c := ln.find(":")
		if c <= 0:
			continue
		var key := ln.substr(0, c).strip_edges()
		var val := ln.substr(c + 1).strip_edges()
		if val.is_empty():
			# mapa: pattern (wiersz albo blok |-) i variables (lista list)
			var m := {"pattern": "", "variables": []}
			while i < lines.size() and (lines[i].begins_with(" ") or lines[i].strip_edges().is_empty()):
				var sub := lines[i].strip_edges()
				i += 1
				if sub.begins_with("pattern:"):
					var pv := sub.substr(8).strip_edges()
					if pv == "|-" or pv == "|":
						var blk := PackedStringArray()
						var ind := -1
						while i < lines.size() and (lines[i].strip_edges().is_empty() or lines[i].length() - lines[i].lstrip(" ").length() > 2):
							if not lines[i].strip_edges().is_empty():
								if ind < 0:
									ind = lines[i].length() - lines[i].lstrip(" ").length()
								blk.append(lines[i].substr(mini(ind, lines[i].length() - lines[i].lstrip(" ").length())))
							i += 1
						m.pattern = "\n".join(blk)
					else:
						m.pattern = _scalar(pv)
				elif sub.begins_with("- ["):
					var arr := []
					for v in sub.substr(3, sub.rfind("]") - 3).split(",", false):
						arr.append(_scalar(v.strip_edges()))
					(m.variables as Array).append(arr)
			d[key] = m if gmst else String(m.pattern)
			continue
		if val == "|-" or val == "|":
			var block := PackedStringArray()
			while i < lines.size() and (lines[i].begins_with(" ") or lines[i].strip_edges().is_empty()):
				block.append(lines[i].strip_edges())
				i += 1
			while block.size() > 0 and block[block.size() - 1].is_empty():
				block.remove_at(block.size() - 1)
			d[key] = "\n".join(block)
			continue
		if val.length() >= 2 and val.begins_with("\"") and val.ends_with("\""):
			val = val.substr(1, val.length() - 2).replace("\\\"", "\"").replace("\\n", "\n")
		elif val.length() >= 2 and val.begins_with("'") and val.ends_with("'"):
			val = val.substr(1, val.length() - 2).replace("''", "'")
		d[key] = {"gmst": _scalar(val)} if gmst else val
	return d

## printf GMST (%s, %d, %.2f…) → {zmienna} w kolejności z „variables” (MessageBundles::load dla „gmst”).
static func _gmst_vars(t: String, vars: Array) -> String:
	if vars.is_empty():
		return t
	var re := RegEx.new()
	re.compile("%(?:\\.\\d+)?[sdif]")
	var out := ""
	var pos := 0
	var k := 0
	for m in re.search_all(t):
		out += t.substr(pos, m.get_start() - pos)
		out += ("{%s}" % vars[k]) if k < vars.size() else m.get_string()
		k += 1
		pos = m.get_end()
	return out + t.substr(pos)

## Tekst wpisu języka „gmst”; "" gdy brak GMST (wtedy następny język).
static func _gmst_entry(e) -> String:
	if not gmst_lookup.is_valid() or not (e is Dictionary):
		return ""
	if e.has("gmst"):
		return String(gmst_lookup.call(String(e.gmst)))
	var pat := String(e.get("pattern", ""))
	var vars: Array = e.get("variables", [])
	var re := RegEx.new()
	re.compile("\\{gmst:(\\w+)\\}")
	var out := ""
	var pos := 0
	var n := 0
	for m in re.search_all(pat):
		var g := String(gmst_lookup.call(m.get_string(1)))
		if g.is_empty():
			return ""
		out += pat.substr(pos, m.get_start() - pos) + _gmst_vars(g, vars[n] if n < vars.size() else [])
		n += 1
		pos = m.get_end()
	return out + pat.substr(pos)

## Kolejność języków: „gmst” na początku albo na końcu (gmst overrides l10n).
static func _order() -> PackedStringArray:
	var o := PackedStringArray()
	if gmst_first:
		o.append("gmst")
	o.append_array(locales)
	if not gmst_first:
		o.append("gmst")
	return o

## Formy ICU plural/select: {n, plural, one{…} other{…}} – gałąź z argumentu (one dla 1, inaczej other / =N).
static func _icu_choice(s: String, args: Dictionary) -> String:
	var re := RegEx.new()
	re.compile("\\{(\\w+),\\s*(plural|select),")
	var guard := 0
	while guard < 16:
		guard += 1
		var m := re.search(s)
		if m == null:
			break
		var name := m.get_string(1)
		# koniec całej formy (dopasowanie nawiasów)
		var depth := 0
		var end := -1
		for j in range(m.get_start(), s.length()):
			if s[j] == "{":
				depth += 1
			elif s[j] == "}":
				depth -= 1
				if depth == 0:
					end = j
					break
		if end < 0:
			break
		var body := s.substr(m.get_end(), end - m.get_end())
		var branches := {}
		var p := 0
		while p < body.length():
			var ob := body.find("{", p)
			if ob < 0:
				break
			var sel := body.substr(p, ob - p).strip_edges()
			var dd := 0
			var cb := -1
			for j in range(ob, body.length()):
				if body[j] == "{":
					dd += 1
				elif body[j] == "}":
					dd -= 1
					if dd == 0:
						cb = j
						break
			if cb < 0:
				break
			branches[sel] = body.substr(ob + 1, cb - ob - 1)
			p = cb + 1
		var v = args.get(name, null)
		var pick := ""
		if m.get_string(2) == "plural":
			var nv := float(v) if v != null else 0.0
			if branches.has("=%d" % int(nv)):
				pick = branches["=%d" % int(nv)]
			elif is_equal_approx(nv, 1.0) and branches.has("one"):
				pick = branches["one"]
			else:
				pick = String(branches.get("other", ""))
			pick = pick.replace("#", str(int(nv)) if is_equal_approx(nv, roundf(nv)) else str(nv))
		else:
			pick = String(branches.get(str(v), branches.get("other", "")))
		s = s.substr(0, m.get_start()) + pick + s.substr(end + 1)
	return s

## Tekst klucza kontekstu OMWEngine w pierwszym dostępnym języku; args – podstawienia {nazwa}.
static func text(key: String, fallback := "", args := {}) -> String:
	return ctx_text("OMWEngine", key, fallback, args)

## Tekst klucza z dowolnego kontekstu (#{Kontekst:klucz}).
static func ctx_text(ctx: String, key: String, fallback := "", args := {}) -> String:
	var s := ""
	for l in _order():
		var d := _load(ctx, l)
		if d.has(key):
			s = _gmst_entry(d[key]) if l == "gmst" else String(d[key])
			if not s.is_empty():
				break
	if s.is_empty():
		s = fallback if not fallback.is_empty() else key
	s = _icu_choice(s, args)
	for k in args:
		s = s.replace("{%s}" % k, str(args[k]))
	return s.replace("''", "'")

## DateTimeManager::formatTimeOfDay: Calendar „timeFormat” z {hour}, {hour12}, {minute}, {period} (am/pm).
static func time_of_day(hour: float) -> String:
	var minutes := int(hour * 60.0)
	var h24 := minutes / 60
	var period := ctx_text("Calendar", "am" if h24 < 12 else "pm")
	return ctx_text("Calendar", "timeFormat", "{hour12} {period}",
		{"hour": h24, "hour12": (h24 + 11) % 12 + 1, "minute": "%02d" % (minutes % 60), "period": period})
