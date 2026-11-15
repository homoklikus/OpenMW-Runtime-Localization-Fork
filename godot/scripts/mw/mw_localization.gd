class_name MWLocalization
extends RefCounted
## Lokalizacja runtime – przeniesione z forka OpenMW RLF (components/translation, apps/openmw/engine.cpp).
## Konwerter zapisuje world/localization/<JĘZYK>/{names,texts,fallbacks}.json z plików-towarzyszy YAML
## (localization/language/<wtyczka>.yaml) w kolejności ładowania. Gra wybiera język w trakcie działania:
## lista preferencji („pl,en”), dla każdego klucza pierwszy język, który ma wartość; brak → tekst oryginalny.
##
## Znaczniki formatowania z YAML ([c=#RRGGBB] [b] [i]) nie trafiają do danych gry: plain() zwraca czysty
## tekst (logika, porównania), bbcode() wersję do wyświetlenia (RichTextLabel). Błędne znaczniki →
## tekst wyświetlany bez formatowania (jak w forku). QA: tekst z wybranego modułu dostaje znacznik „QA:”.

const QA_COLOR := "#ff40ff"

var languages: PackedStringArray = []     # klucze językowe YAML w kolejności preferencji (PL, PL_PL…)
var qa_source := ""                       # znormalizowana nazwa modułu (bez rozszerzenia, małe litery)
var _roots: Array[String] = []
var _parts := {}                          # "names"/"texts"/"fallbacks" → Array (po jednym na język) [{strings, sources}]
var available: PackedStringArray = []     # języki w konwersji

## preferred: „auto”, „original” albo lista kodów („pl” / „pl,en”); ui_language: język launchera (dla „auto”).
static func create(data_root: String, base_roots: Array, preferred: String, ui_language := "", qa := "") -> RefCounted:
	var l = load("res://scripts/mw/mw_localization.gd").new()
	l._roots.append(data_root)
	for r in base_roots:
		l._roots.append(String(r))
	var idx = l._read_json("world/localization/index.json")
	if idx is Dictionary:
		for x in idx.get("languages", []):
			l.available.append(String(x))
	var p := preferred.strip_edges().to_lower()
	if p == "" or p == "auto":
		p = ui_language
	if p != "original":
		l.languages = language_keys(p)
	l.qa_source = normalize_source(qa)
	return l

## „pl_PL,en” → [PL_PL, PL, EN] (dokładny język przed bazowym, jak makeYamlLanguageKeys w forku).
static func language_keys(pref: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for part in pref.split(",", false):
		var k := part.strip_edges().replace("-", "_").to_upper()
		if k.is_empty() or k == "GMST":
			continue
		if not out.has(k):
			out.append(k)
		var base := k.get_slice("_", 0)
		if base != k and not out.has(base):
			out.append(base)
	return out

static func normalize_source(s: String) -> String:
	var r := s.strip_edges().get_file().to_lower()
	for ext in [".yaml", ".esp", ".esm", ".omwaddon", ".omwgame"]:
		if r.ends_with(ext):
			return r.substr(0, r.length() - ext.length())
	return r

static func key(rtype: String, id: String, field: String) -> String:
	return "%s|%s|%s" % [rtype.to_upper(), id.to_lower(), field.to_upper()]

func is_active() -> bool:
	return not languages.is_empty() and not available.is_empty()

## [tekst ze znacznikami, źródło] lub [] – pierwszy język z listy preferencji, który ma wpis.
func lookup(k: String, part := "") -> Array:
	if languages.is_empty():
		return []
	if part.is_empty():
		part = "texts" if k.begins_with("INFO|") else "names"
	var stack: Array = _load_part(part)
	for d in stack:
		var e = d["strings"].get(k)
		if e != null:
			return [e[0], String(d["sources"][int(e[1])])]
	return []

## Czysty tekst (bez znaczników) albo fallback (tekst oryginalny z ESM).
func plain(k: String, fallback: String) -> String:
	var e := lookup(k)
	if e.is_empty() or not (e[0] is String):
		return fallback
	return strip_markup(e[0])

## Tekst do wyświetlenia w RichTextLabel: znaczniki YAML → BBCode, opcjonalny znacznik QA.
func bbcode(k: String, fallback: String) -> String:
	var e := lookup(k)
	if e.is_empty() or not (e[0] is String):
		return escape_bbcode(fallback)
	var txt := to_bbcode(e[0])
	if not qa_source.is_empty() and normalize_source(e[1]) == qa_source:
		txt = "[color=%s]QA:[/color] %s" % [QA_COLOR, txt]
	return txt

## Nazwa rekordu bazowego (typ z objects.json) – czysty tekst.
func object_name(obj: Dictionary, fallback := "") -> String:
	var fb := String(obj.get("name", fallback))
	if not is_active():
		return fb
	return plain(key(String(obj.get("type", "")), String(obj.get("id", "")), "FNAM"), fb)

func object_name_bbcode(obj: Dictionary, fallback := "") -> String:
	var fb := String(obj.get("name", fallback))
	if not is_active():
		return escape_bbcode(fb)
	return bbcode(key(String(obj.get("type", "")), String(obj.get("id", "")), "FNAM"), fb)

## INFO z wariantami płci (npc_player > npc / player > default), jak w forku.
func info_text(topic: String, info_id: String, fallback: String, npc_female := false, player_female := false) -> String:
	var e := lookup("INFO|%s|%s|NAME" % [topic.to_lower(), info_id.to_lower()], "texts")
	if e.is_empty():
		return fallback
	var v = e[0]
	if v is String:
		return v
	if not (v is Dictionary):
		return fallback
	var ns := "female" if npc_female else "male"
	var ps := "female" if player_female else "male"
	if v.has("npc_player") and v["npc_player"] is Dictionary and v["npc_player"].get(ns) is Dictionary \
			and v["npc_player"][ns].has(ps):
		return String(v["npc_player"][ns][ps])
	if v.has("npc") and v["npc"] is Dictionary and v["npc"].has(ns):
		return String(v["npc"][ns])
	if v.has("player") and v["player"] is Dictionary and v["player"].has(ps):
		return String(v["player"][ps])
	return String(v.get("default", fallback))

## Wartość z Morrowind.ini (sekcja „fallbacks” w YAML).
func fallback_value(section: String, k: String, fallback: String) -> String:
	var e := lookup("%s|%s" % [section, k], "fallbacks")
	return fallback if e.is_empty() else String(e[0])

# --- znaczniki -------------------------------------------------------------------------------------

static var _tag_re: RegEx

static func _re() -> RegEx:
	if _tag_re == null:
		_tag_re = RegEx.new()
		_tag_re.compile("\\[(/?)(c|b|i)(=#[0-9A-Fa-f]{6})?\\]")
	return _tag_re

## Poprawne zagnieżdżenie i zamknięcie [c=#RRGGBB] [b] [i].
static func markup_valid(t: String) -> bool:
	var stack: Array[String] = []
	for m in _re().search_all(t):
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2)
		var arg := m.get_string(3)
		if closing:
			if not arg.is_empty() or stack.is_empty() or stack.back() != tag:
				return false
			stack.pop_back()
		else:
			if (tag == "c") != (not arg.is_empty()):
				return false
			stack.append(tag)
	return stack.is_empty()

static func strip_markup(t: String) -> String:
	if not t.contains("[") or not markup_valid(t):
		return t
	return _re().sub(t, "", true)

static func escape_bbcode(t: String) -> String:
	return t.replace("[", "[lb]")

static func to_bbcode(t: String) -> String:
	if not t.contains("[") or not markup_valid(t):
		return escape_bbcode(t)
	var out := ""
	var pos := 0
	for m in _re().search_all(t):
		out += escape_bbcode(t.substr(pos, m.get_start() - pos))
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2)
		if tag == "c":
			out += "[/color]" if closing else "[color=%s]" % m.get_string(3).substr(1)
		else:
			out += "[/%s]" % tag if closing else "[%s]" % tag
		pos = m.get_end()
	return out + escape_bbcode(t.substr(pos))

# --- pliki -----------------------------------------------------------------------------------------

func _load_part(part: String) -> Array:
	if _parts.has(part):
		return _parts[part]
	var stack: Array = []
	for L in languages:
		if not available.has(L):
			continue
		var j = _read_json("world/localization/%s/%s.json" % [L, part])
		if j is Dictionary:
			stack.append({"strings": j.get("strings", {}), "sources": j.get("sources", [])})
	_parts[part] = stack
	return stack

func _read_json(rel: String) -> Variant:
	for r in _roots:
		var p := r.path_join(rel)
		if FileAccess.file_exists(p):
			return JSON.parse_string(FileAccess.get_file_as_string(p))
	return null
