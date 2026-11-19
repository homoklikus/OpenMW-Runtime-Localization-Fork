extends RefCounted
## Teksty silnika jak l10n OpenMW (components/l10n): konteksty „OMWEngine” i „Calendar” z plików
## files/data/l10n/<kontekst>/*.yaml (część OpenMW, nie zasoby gry), skopiowanych do res://l10n. Język z ustawienia „preferred_locales” (OpenMW [General] preferred locales,
## domyślnie „en”); brakujący klucz – kolejne języki z listy, potem en.yaml, na końcu podany zapas.
## Obsługiwane: „Klucz: "tekst"”, bloki „|-” i podstawienia {nazwa}. Formy ICU (plural/select) – tylko gałąź
## „other”/pierwsza (w oknach używanych przez Godota nie występują).

const DIR := "res://l10n"

static var locales: PackedStringArray = ["en"]
static var _cache := {}

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
		d = parse_yaml(FileAccess.get_file_as_string(path))
	_cache[ck] = d
	return d

## Minimalny parser płaskiego YAML z plików l10n OpenMW.
static func parse_yaml(text: String) -> Dictionary:
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
		d[key] = val
	return d

## Tekst klucza kontekstu OMWEngine w pierwszym dostępnym języku; args – podstawienia {nazwa}.
static func text(key: String, fallback := "", args := {}) -> String:
	return ctx_text("OMWEngine", key, fallback, args)

## Tekst klucza z dowolnego kontekstu (#{Kontekst:klucz}).
static func ctx_text(ctx: String, key: String, fallback := "", args := {}) -> String:
	var s := ""
	for l in locales:
		var d := _load(ctx, l)
		if d.has(key):
			s = String(d[key])
			break
	if s.is_empty():
		s = fallback if not fallback.is_empty() else key
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
