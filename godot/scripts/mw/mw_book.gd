extends RefCounted
## Tekst książek i zwojów (etap 10) jak OpenMW `MWGui::Formatting`: parser znaczników Morrowinda (BookTextParser:
## <BR>, <P>, <DIV ALIGN>, <FONT COLOR/FACE>, <IMG SRC WIDTH HEIGHT>; tekst po ostatnim <BR>/<P> nie jest
## pokazywany – shrinkTextAtLastTag) i znaczniki lokalizacji RLF ([c=#RRGGBB], [b], [i], [pagebreak]);
## BookFormatter: bloki tekstu i obrazy jeden pod drugim na „papierze” o szerokości strony i podział na strony
## (Paginator) – granice stron w wielokrotnościach wysokości linii, puste linie na początku strony pomijane.
## Wynik: elementy z pozycjami w pikselach interfejsu i lista stron [początek, koniec].

const EV_EOF := 0
const EV_BR := 1
const EV_P := 2
const EV_IMG := 3
const EV_DIV := 4
const EV_FONT := 5
const EV_PAGEBREAK := 6
const EV_COLOR_OPEN := 7
const EV_COLOR_CLOSE := 8
const EV_BOLD_OPEN := 9
const EV_BOLD_CLOSE := 10
const EV_ITALIC_OPEN := 11
const EV_ITALIC_CLOSE := 12

const TAGS := {"br": EV_BR, "p": EV_P, "img": EV_IMG, "div": EV_DIV, "font": EV_FONT}

# --- parser (BookTextParser) -----------------------------------------------------------------------------

var _text := ""
var _i := 0
var _plain_end := 0
var _buffer := ""
var _ready := ""
var _ignore_newline_tags := true
var _ignore_line_endings := true
var tag := ""
var closing := false
var attrs := {}
var runtime_colour := ""

func _init_parser(text: String, shrink: bool) -> void:
	_text = text.replace("\r", "")
	_i = 0
	_buffer = ""
	_ready = ""
	_ignore_newline_tags = true
	_ignore_line_endings = true
	if shrink:
		var low := _text.to_lower()
		var br := low.rfind("<br>")
		var p := low.rfind("<p>")
		_plain_end = 0
		if br != p:
			_plain_end = maxi(br, p)
	else:
		_plain_end = _text.length()

func _flush() -> void:
	_ready = _buffer
	_buffer = ""

static func _is_hex(c: String) -> bool:
	return (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")

func next_event() -> int:
	var n := _text.length()
	while _i < n:
		var ch := _text[_i]
		if ch == "[":
			var rest := _text.substr(_i, 12)
			if rest.begins_with("[pagebreak]\n"):
				_i += 12
				_flush()
				_ignore_newline_tags = false
				return EV_PAGEBREAK
			if rest.length() >= 11 and rest.begins_with("[c=#") and rest[10] == "]":
				var ok := true
				for k in range(4, 10):
					if not _is_hex(rest[k]):
						ok = false
						break
				if ok:
					runtime_colour = rest.substr(4, 6)
					_i += 11
					_flush()
					return EV_COLOR_OPEN
			if rest.begins_with("[/c]"):
				_i += 4
				_flush()
				return EV_COLOR_CLOSE
			if rest.begins_with("[b]"):
				_i += 3
				_flush()
				return EV_BOLD_OPEN
			if rest.begins_with("[/b]"):
				_i += 4
				_flush()
				return EV_BOLD_CLOSE
			if rest.begins_with("[i]"):
				_i += 3
				_flush()
				return EV_ITALIC_OPEN
			if rest.begins_with("[/i]"):
				_i += 4
				_flush()
				return EV_ITALIC_CLOSE
		if ch == "<":
			var end := _text.find(">", _i + 1)
			if end < 0:
				# niezamknięty znacznik (OpenMW zgłasza błąd) – reszta jako zwykły tekst
				_text = _text.substr(0, _i) + _text.substr(_i + 1)
				n = _text.length()
				continue
			_parse_tag(_text.substr(_i + 1, end - _i - 1))
			_i = end
			if TAGS.has(tag):
				var t: int = TAGS[tag]
				if t == EV_BR or t == EV_P:
					if not _ignore_newline_tags:
						_buffer += "\n" if t == EV_BR else "\n\n"
					_ignore_line_endings = true
					if t == EV_P and not attrs.is_empty():
						_flush()
				else:
					_flush()
				if t == EV_IMG:
					_ignore_newline_tags = false
				_i += 1
				return t
		else:
			if not _ignore_line_endings or ch != "\n":
				if _i < _plain_end:
					_buffer += ch
				_ignore_line_endings = false
				_ignore_newline_tags = false
		_i += 1
	_flush()
	return EV_EOF

func _parse_tag(t: String) -> void:
	attrs = {}
	var sp := t.find(" ")
	tag = (t if sp < 0 else t.substr(0, sp)).to_lower()
	if tag.is_empty():
		closing = false
		return
	closing = tag[0] == "/"
	if closing:
		tag = tag.substr(1)
		return
	if sp < 0:
		return
	var rest := t.substr(sp + 1)
	while not rest.is_empty():
		var eq := rest.find("=")
		if eq < 0:
			return
		var key := rest.substr(0, eq).strip_edges().to_lower()
		rest = rest.substr(eq + 1)
		if rest.is_empty():
			return
		var value := ""
		if rest[0] == "\"" or rest[0] == "'":
			var q := rest.find(rest[0], 1)
			if q < 0:
				return
			value = rest.substr(1, q - 1)
			rest = rest.substr(q + 2)
		else:
			var ve := rest.find(" ")
			if ve < 0:
				value = rest
				rest = ""
			else:
				value = rest.substr(0, ve)
				rest = rest.substr(ve + 1)
		attrs[key] = value

# --- formatowanie (BookFormatter + Paginator) -------------------------------------------------------------

## Czcionki: domyślna (MysticCards – „Journalbook DefaultFont”) i daedryjska (FACE="Daedric" – ScrollFont).
static var _fonts := {}

static func font(face: String, bold := false, italic := false) -> Font:
	var k := "%s|%s|%s" % [face, bold, italic]
	if _fonts.has(k):
		return _fonts[k]
	var file := "res://fonts/DemonicLetters.ttf" if face == "daedric" else "res://fonts/MysticCards.ttf"
	var base: Font = null
	var ff := FontFile.new()
	if ff.load_dynamic_font(file) == OK:
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		base = ff
	else:
		base = ThemeDB.fallback_font
	var f: Font = base
	if bold or italic:
		var fv := FontVariation.new()
		fv.base_font = base
		if bold:
			fv.variation_embolden = 0.7
		if italic:
			fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
		f = fv
	_fonts[k] = f
	return f

## Elementy: {"kind": "text", "text", "y", "h", "lines", "color", "face", "bold", "italic", "align"} albo
## {"kind": "img", "src", "y", "w", "h", "align"}; strony: [[od, do], …] (piksele interfejsu przed skalą).
var elements: Array = []
var pages: Array = []
var page_w := 250.0
var page_h := 328.0
var font_size := 16
var line_h := 16.0
var paper_h := 0.0
var _start := 0.0
var _cur := 0.0
var _ignore_leading := false
var image_exists: Callable          # (src: String, w: int, h: int) -> String (ścieżka) albo ""

## width/height/size – w pikselach ekranu (okno mnoży wymiary interfejsu przez skalę), img_scale – skala obrazów.
func format(markup: String, width: float, height: float, size := 16, shrink := true, img_scale := 1.0) -> void:
	page_w = width
	page_h = height
	font_size = size
	line_h = font("default").get_height(size)
	elements = []
	pages = []
	_start = 0.0
	_cur = 0.0
	_ignore_leading = false
	var style := {"color": Color.BLACK, "face": "default", "bold": false, "italic": false}
	var align := "left"
	_init_parser(markup, shrink)
	var br_before_last := false
	var prev_img := false
	var colour_stack: Array = []
	var bold_depth := 0
	var italic_depth := 0
	while true:
		var ev := next_event()
		if ev == EV_BR or (ev == EV_P and attrs.is_empty()):
			continue
		var plain := _ready
		if _ignore_leading:
			while not plain.is_empty() and plain[0] == "\n":
				plain = plain.substr(1)
			if not plain.is_empty():
				_ignore_leading = false
		var runtime_style := ev >= EV_COLOR_OPEN and ev <= EV_ITALIC_CLOSE
		if plain.is_empty():
			if not runtime_style:
				br_before_last = true
		else:
			var br_start := plain[0] == "\n"
			var br_end := plain[plain.length() - 1] == "\n"
			if br_start and not br_before_last and not prev_img:
				plain = plain.substr(1)
			if not plain.is_empty() and br_end:
				plain = plain.substr(0, plain.length() - 1)
			if not plain.is_empty() or br_before_last or prev_img:
				_text_element(plain, style, align)
			br_before_last = br_end
		if ev == EV_EOF:
			break
		prev_img = ev == EV_IMG
		match ev:
			EV_PAGEBREAK:
				pages.append([_start, _cur])
				_start = _cur
			EV_IMG:
				var src := String(attrs.get("src", ""))
				var w := int(attrs.get("width", "0"))
				var h := int(attrs.get("height", "0"))
				if src.is_empty() or src.begins_with("img://") or w == 0 or h == 0:
					continue
				var path := String(image_exists.call(src, w, h)) if image_exists.is_valid() else ""
				if path.is_empty():
					continue
				_ignore_leading = false
				elements.append({"kind": "img", "src": path, "y": _cur, "w": w * img_scale, "h": h * img_scale, "align": align})
				_paginate(h * img_scale, [])
			EV_FONT:
				if closing:
					style = {"color": Color.BLACK, "face": "default", "bold": false, "italic": false}
				else:
					style = style.duplicate()
					if attrs.has("color"):
						var c := String(attrs.color).hex_to_int() if String(attrs.color).is_valid_hex_number() else 0
						style.color = Color8((c >> 16) & 255, (c >> 8) & 255, c & 255)
					if attrs.has("face"):
						style.face = "daedric" if String(attrs.face).to_lower() == "daedric" else "default"
			EV_COLOR_OPEN:
				colour_stack.append(style.color)
				style = style.duplicate()
				var rc := runtime_colour.hex_to_int()
				style.color = Color8((rc >> 16) & 255, (rc >> 8) & 255, rc & 255)
			EV_COLOR_CLOSE:
				if not colour_stack.is_empty():
					style = style.duplicate()
					style.color = colour_stack.pop_back()
			EV_BOLD_OPEN:
				bold_depth += 1
				style = style.duplicate()
				style.bold = true
			EV_BOLD_CLOSE:
				bold_depth = maxi(0, bold_depth - 1)
				style = style.duplicate()
				style.bold = bold_depth != 0
			EV_ITALIC_OPEN:
				italic_depth += 1
				style = style.duplicate()
				style.italic = true
			EV_ITALIC_CLOSE:
				italic_depth = maxi(0, italic_depth - 1)
				style = style.duplicate()
				style.italic = italic_depth != 0
			EV_P, EV_DIV:
				var al := String(attrs.get("align", "")).to_lower()
				if al in ["center", "left", "right"]:
					align = al
	if _start != _cur:
		pages.append([_start, _start + page_h])
	paper_h = _cur

## Wiersze tekstu przy szerokości strony (jak zawijanie EditBox): szerokości (0 = pusta linia).
func line_widths(text: String, style: Dictionary) -> Array:
	var para := TextParagraph.new()
	para.width = page_w
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	para.add_string(text, font(style.face, style.bold, style.italic), font_size)
	var out := []
	for i in para.get_line_count():
		out.append(para.get_line_width(i))
	return out

func _text_element(text: String, style: Dictionary, align: String) -> void:
	var widths := line_widths(text, style) if not text.is_empty() else [0.0]
	var h := widths.size() * line_h
	elements.append({"kind": "text", "text": text, "y": _cur, "h": h, "lines": widths.size(), "color": style.color,
		"face": style.face, "bold": style.bold, "italic": style.italic, "align": align})
	_paginate(h, widths)

## GraphicElement::paginate + TextElement::pageSplit: dzielenie na stronach w granicach linii.
func _paginate(h: float, widths: Array) -> void:
	var new_top := _cur + h
	var guard := 0
	while new_top - _start > page_h and guard < 10000:
		guard += 1
		var split := _start + page_h
		if not widths.is_empty():
			var last := int((_start + page_h - _cur) / line_h) if line_h > 0.0 else 0
			split = _cur + last * line_h
			_ignore_leading = true
			for i in range(last, widths.size()):
				if float(widths[i]) == 0.0:
					split += line_h
				else:
					_ignore_leading = false
					break
		if split <= _start:
			split = _start + page_h        # zabezpieczenie: wiersz wyższy niż strona
		pages.append([_start, split])
		_start = split
	_cur = new_top

## Ścieżka ilustracji jak correctBookartPath: bookart/<src> (.dds → PNG po konwersji), bez rozmiaru → z
## przyrostkiem _<szer>_<wys>, na końcu sama nazwa pliku w bookart/. root – katalog wyników konwersji.
static func bookart_path(root: String, src: String, w: int, h: int) -> String:
	var s := src.replace("\\", "/").to_lower()
	var i := s.find("bookart/")
	var rel := s.substr(i) if i >= 0 else "bookart/" + s
	var cands := [rel, "%s_%d_%d.%s" % [rel.get_basename(), w, h, rel.get_extension()], "bookart/" + rel.get_file()]
	for c in cands:
		var png := root.path_join(String(c).get_basename() + ".png")
		if FileAccess.file_exists(png):
			return png
	return ""
