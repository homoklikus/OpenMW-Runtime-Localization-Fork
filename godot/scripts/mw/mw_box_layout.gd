extends RefCounted
## Układ Gui::HBox / Gui::VBox z OpenMW 0.51 (components/widgets/box.cpp) – wierne odwzorowanie rozkładu
## widżetów AutoSized* w okienkach z plików .layout (zaklinanie, tworzenie czarów, alchemia, edycja efektu).
##
## Węzeł to słownik:
##   {"type": "hbox"|"vbox", "children": [...], "padding": int, "spacing": int (domyślnie 4)}
##   {"type": "text", "control": Label}               – AutoSizedTextBox: rozmiar = rozmiar tekstu
##   {"type": "button", "control": Button}            – AutoSizedButton: tekst + TextPadding (24 × 8)
##   {"type": "spacer"}                               – Spacer: (0, 0), HStretch
##   {"type": "widget", "control": Control, "size": Vector2} – zwykły widżet: rozmiar z układu
## Wspólne klucze: "hstretch", "vstretch", "hidden" (UserString), "control" (opcjonalnie dla boxów –
## kontener, w którym umieszcza się dzieci; bez niego dzieci dostają współrzędne względem rodzica boxa).
## Rozmiary podaje się w jednostkach układu (przed skalowaniem); place() mnoży przez skalę.

const UI = preload("res://scripts/mw/mw_ui.gd")

var sc := 1.0
var font_size := 16

func _init(scale := 1.0) -> void:
	sc = scale
	font_size = roundi(16 * sc)

## getTextSize: szerokość – zaokrąglona w górę suma przesunięć znaków (TextView), wysokość – wysokość czcionki.
func text_size(s: String) -> Vector2:
	if s.is_empty():
		return Vector2.ZERO
	var w := ceilf(UI.font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / sc)
	return Vector2(w, 16)

func _caption(n: Dictionary) -> String:
	var c = n.get("control")
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	return String(n.get("text", ""))

## UserString „Hidden” (setVisible nie zmienia układu – jak w Gui::Box).
func _hidden(n: Dictionary) -> bool:
	return bool(n.get("hidden", false))

## AutoSizedWidget (także "auto": true – np. AutoSizedEditBox z rozmiarem podanym w "size").
func _is_auto(n: Dictionary) -> bool:
	return bool(n.get("auto", false)) or String(n.type) in ["hbox", "vbox", "text", "button", "spacer"]

## AutoSizedWidget::getRequestedSize (z błędem OpenMW: dopełnienie liczone przy każdym dziecku).
func requested(n: Dictionary) -> Vector2:
	match String(n.type):
		"text":
			var t := _caption(n)
			return Vector2.ZERO if t.is_empty() else text_size(t)
		"button":
			var pad: Vector2 = n.get("text_padding", Vector2(24, 8))
			return text_size(_caption(n)) + pad
		"spacer":
			return Vector2.ZERO
		"hbox", "vbox":
			var horiz := String(n.type) == "hbox"
			var sp := int(n.get("spacing", 4))
			var pd := int(n.get("padding", 0))
			var ch: Array = n.get("children", [])
			var size := Vector2.ZERO
			for i in ch.size():
				var c: Dictionary = ch[i]
				if _hidden(c):
					continue
				var r: Vector2 = requested(c) if _is_auto(c) else Vector2(c.get("size", Vector2.ZERO))
				if horiz:
					size.y = maxf(size.y, r.y)
					if _is_auto(c) or not _st(c, "hstretch"):
						size.x += r.x
					if i != ch.size() - 1:
						size.x += sp
				else:
					size.x = maxf(size.x, r.x)
					if _is_auto(c) or not _st(c, "vstretch"):
						size.y += r.y
					if i != ch.size() - 1:
						size.y += sp
				size += Vector2(pd * 2, pd * 2)
			return size
	return Vector2(n.get("size", Vector2.ZERO))

## Sumy z Box::align (totalWidth, totalHeight) – rozmiar obszaru klienta przy AutoResize to sumy + 2 × Padding.
func totals(n: Dictionary) -> Vector2:
	var horiz := String(n.type) == "hbox"
	var sp := int(n.get("spacing", 4))
	var ch: Array = n.get("children", [])
	var total := Vector2.ZERO
	for i in ch.size():
		var w: Dictionary = ch[i]
		if _hidden(w):
			continue
		var r: Vector2 = requested(w) if _is_auto(w) else Vector2(w.get("size", Vector2.ZERO))
		if horiz:
			total.x += r.x
			if _is_auto(w) or not _st(w, "vstretch"):
				total.y = maxf(total.y, r.y)
		else:
			total.y += r.y
			if _is_auto(w) or not _st(w, "hstretch"):
				total.x = maxf(total.x, r.x)
		if i != ch.size() - 1:
			if horiz:
				total.x += sp
			else:
				total.y += sp
	return total

## Box::align dla węzła o współrzędnych rect (jednostki układu, względem rodzica kontrolki boxa).
## origin – przesunięcie układu współrzędnych dzieci (gdy box nie ma własnej kontrolki).
func place(n: Dictionary, rect: Rect2, origin := Vector2.ZERO) -> void:
	var c = n.get("control")
	if c is Control:
		(c as Control).position = (origin + rect.position) * sc
		(c as Control).size = rect.size * sc
	if not String(n.type) in ["hbox", "vbox"]:
		return
	var child_origin := Vector2.ZERO if c is Control else origin + rect.position
	var horiz := String(n.type) == "hbox"
	var sp := int(n.get("spacing", 4))
	var pd := int(n.get("padding", 0))
	var ch: Array = n.get("children", [])
	var sizes := []
	var total := Vector2.ZERO
	var n_st := 0
	for i in ch.size():
		var w: Dictionary = ch[i]
		var hidden := _hidden(w)
		var st: bool = _st(w, "hstretch") if horiz else _st(w, "vstretch")
		var r: Vector2 = Vector2.ZERO
		if not hidden:
			r = requested(w) if _is_auto(w) else Vector2(w.get("size", Vector2.ZERO))
			if st:
				n_st += 1
			if horiz:
				total.x += r.x
				if _is_auto(w) or not _st(w, "vstretch"):
					total.y = maxf(total.y, r.y)
				if i != ch.size() - 1:
					total.x += sp
			else:
				total.y += r.y
				if _is_auto(w) or not _st(w, "hstretch"):
					total.x = maxf(total.x, r.x)
				if i != ch.size() - 1:
					total.y += sp
		sizes.append([r, st, hidden])
	var cw := rect.size.x
	var chh := rect.size.y
	var cur := float(pd)
	for i in ch.size():
		var w: Dictionary = ch[i]
		if sizes[i][2]:
			continue
		var r: Vector2 = sizes[i][0]
		var wr := Rect2()
		if horiz:
			var hh := (chh - pd * 2) if _st(w, "vstretch") else r.y
			var ww := r.x + (floorf((cw - pd * 2 - total.x) / n_st) if sizes[i][1] else 0.0)
			wr = Rect2(cur, pd + _idiv(chh - pd * 2 - hh), ww, hh)
			cur += ww
		else:
			var ww2 := (cw - pd * 2) if _st(w, "hstretch") else r.x
			var hh2 := r.y + (floorf((chh - pd * 2 - total.y) / n_st) if sizes[i][1] else 0.0)
			wr = Rect2(pd + _idiv(cw - pd * 2 - ww2), cur, ww2, hh2)
			cur += hh2
		if i != ch.size() - 1:
			cur += sp
		place(w, wr, child_origin)

## Zawijanie wierszy jak MyGUI::TextView (WordWrap): przekroczenie szerokości cofa do ostatniej spacji (spacja
## znika), wymuszone \n; szerokość w jednostkach układu. Zwraca wiersze.
func wrap_lines(text: String, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var f := UI.font()
	var limit := max_w * sc
	for para in text.split("\n"):
		var words := para.split(" ")
		var line := ""
		for i in words.size():
			var cand: String = words[i] if i == 0 else line + " " + words[i]
			if i > 0 and f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > limit:
				out.append(line)
				line = words[i]
			else:
				line = cand
		out.append(line)
	return out

## UserString HStretch/VStretch; Spacer ustawia oba w konstruktorze.
static func _st(w: Dictionary, key: String) -> bool:
	return bool(w.get(key, String(w.get("type", "")) == "spacer"))

## Dzielenie całkowite przez 2 jak w C++ (obcięcie w stronę zera).
static func _idiv(v: float) -> float:
	return float(int(v) / 2)
