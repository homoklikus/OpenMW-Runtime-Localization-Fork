extends CanvasLayer
## Podpowiedzi jak OpenMW 0.51 ToolTips (apps/openmw/mwgui/tooltips.cpp, openmw_tooltips.layout,
## MWClass::*::getToolTipInfo, Widgets::MWSpellEffect/MWEffectList):
##  - w trybie GUI kontrolka pod kursorem (albo jej przodek) z meta „mw_tip” – {type: "item", id, count} (ItemPtr /
##    ItemModelIndex), {type: "spell", id} (Spell), {type: "info", …} (ToolTipInfo); bez opóźnienia ([GUI] tooltip
##    delay = 0); położenie ToolTips::position (32 px pod kursorem, przesunięcie w lewo proporcjonalne do x kursora,
##    przy prawej/dolnej krawędzi – dociągnięcie / nad kursorem);
##  - createToolTip: skórka HUD_Box_NoTransp (w trybie GUI), odstęp 8 px, nagłówek (NormalText) z ikoną 32 × 32 po
##    lewej, tekst (SandText, wyśrodkowany, zawijany przy 300 px), lista efektów (MW_EffectImage: ikona 16 × 16,
##    tekst od 24 px, wiersz 24 px; mikstury/składniki wyśrodkowane), zaklęcie przedmiotu (typ w tekście,
##    efekty, ładunek „#{sCharges}” + pasek MW_ChargeBar 204 × 18 dla „przy uderzeniu”/„przy użyciu”).
## Teksty „#{…}” rozwijane z GMST danych gry (zapas angielski tylko przy braku ustawienia).

const UI := preload("res://scripts/mw/mw_ui.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const EQ := preload("res://scripts/mw/mw_equipment.gd")

const PADDING := 8.0
const MAX_WRAP := 300.0
const ICON_OFFSET := 24.0       # MWSpellEffect::sIconOffset
const CHARGE_W := 204.0

var main
var box: Panel = null           # DynamicToolTipBox
var current_key := ""
var last_info: Dictionary = {}  # testy: ostatnia podpowiedź (info)
var last_size := Vector2.ZERO
var enabled := true
var _s := 1.0
var _cu = null

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	box = Panel.new()
	box.name = "DynamicToolTipBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	add_child(box)

func _t(gm: String, fb: String) -> String:
	if main == null or main.get("dialogue") == null or main.dialogue == null:
		return fb
	var v: String = main.dialogue.gmst_text(gm, fb)
	return v if not v.is_empty() else fb

## ToolTips::toString(float): dwa miejsca po przecinku, końcowe zera i kropka obcięte.
static func num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.left(-1)
	if s.ends_with("."):
		s = s.left(-1)
	return s

func _weight(w: float) -> String:
	return "" if w == 0.0 else "\n%s: %s" % [_t("sWeight", "Weight"), num(w)]

func _value(v: int) -> String:
	return "" if v == 0 else "\n%s: %d" % [_t("sValue", "Value"), v]

static func count_string(n: int) -> String:
	return "" if n == 1 else " (%d)" % n

# --- dane podpowiedzi (getToolTipInfo) ---------------------------------------------------------------------

## ToolTipInfo przedmiotu z ekwipunku/pojemnika: caption, icon, text, effects, enchant, charge, is_potion, …
func item_info(id: String, count := 1) -> Dictionary:
	var inv = main.interaction.inventory
	var it: Dictionary = inv.item(id)
	if it.is_empty():
		return {}
	var rec: Dictionary = it.rec
	var kind := String(it.kind)
	var info := {"caption": main.interaction.item_name(kind, id, rec) + count_string(count),
		"icon": String(rec.get("icon", "")), "text": ""}
	var text := ""
	match kind:
		"weapon":
			var wt := int(rec.get("weapon_type", 0))
			if wt < 12:                                    # amunicja: [Game] show projectile damage = false
				var sk := int(EQ.WEAPON_SKILL.get(wt, EQ.SK_LONG_BLADE))
				text += "\n%s %s" % [_t("sType", "Type"), _skill_name(sk)]
				if wt <= 8:
					text += ", " + (_t("sTwoHanded", "Two Handed") if wt in EQ.WEAPON_TWO_HANDED else _t("sOneHanded", "One Handed"))
				if wt == 11:                               # rzucana – obrażenia × 2
					text += "\n%s: %d - %d" % [_t("sAttack", "Attack"), int(_dmg(rec, "chop", 0) * 2.0), int(_dmg(rec, "chop", 1) * 2.0)]
				elif wt <= 8:
					text += "\n%s: %d - %d" % [_t("sChop", "Chop"), int(_dmg(rec, "chop", 0)), int(_dmg(rec, "chop", 1))]
					text += "\n%s: %d - %d" % [_t("sSlash", "Slash"), int(_dmg(rec, "slash", 0)), int(_dmg(rec, "slash", 1))]
					text += "\n%s: %d - %d" % [_t("sThrust", "Thrust"), int(_dmg(rec, "thrust", 0)), int(_dmg(rec, "thrust", 1))]
				else:
					text += "\n%s: %d - %d" % [_t("sAttack", "Attack"), int(_dmg(rec, "chop", 0)), int(_dmg(rec, "chop", 1))]
			if inv.max_charge(rec) > 0.0:                 # hasItemHealth
				text += "\n%s: %d/%d" % [_t("sCondition", "Condition"), int(inv.item_charge(id)), int(inv.max_charge(rec))]
			text += _weight(float(rec.get("weight", 0.0))) + _value(int(rec.get("value", 0)))
			_add_enchant(info, it, id)
		"armor":
			var type_text := ""
			if float(rec.get("weight", 0.0)) != 0.0:
				match main.combat.armor_skill(rec):
					EQ.SK_LIGHT_ARMOR: type_text = _t("sLight", "Light")
					EQ.SK_MEDIUM_ARMOR: type_text = _t("sMedium", "Medium")
					_: type_text = _t("sHeavy", "Heavy")
			text += "\n%s: %d" % [_t("sArmorRating", "Armor Rating"), int(_adjusted_armor(rec))]
			text += "\n%s: %d/%d" % [_t("sCondition", "Condition"), int(inv.item_charge(id)), int(rec.get("health", 0))]
			if not type_text.is_empty():
				text += "\n%s: %s (%s)" % [_t("sWeight", "Weight"), num(float(rec.get("weight", 0.0))), type_text]
			text += _value(int(rec.get("value", 0)))
			_add_enchant(info, it, id)
		"clothing", "book":
			text += _weight(float(rec.get("weight", 0.0))) + _value(int(rec.get("value", 0)))
			_add_enchant(info, it, id, kind == "clothing")
		"misc":
			var gold: bool = inv.base_id(id) in ["gold_001", "gold_005", "gold_010", "gold_025", "gold_100"]   # isGold
			if gold:
				info.caption = main.interaction.item_name(kind, id, rec) + count_string(count * int(rec.get("value", 1)))
			text += _weight(float(rec.get("weight", 0.0)))
			if not gold and not bool(rec.get("key", false)):
				text += _value(int(rec.get("value", 0)))
		"apparatus":
			text += "\n%s: %s" % [_t("sQuality", "Quality"), num(float(rec.get("quality", 0.0)))]
			text += _weight(float(rec.get("weight", 0.0))) + _value(int(rec.get("value", 0)))
		"lockpick", "probe", "repair":
			text += "\n%s: %d" % [_t("sUses", "Uses"), int(inv.item_charge(id))]
			text += "\n%s: %s" % [_t("sQuality", "Quality"), num(float(rec.get("quality", 0.0)))]
			text += _weight(float(rec.get("weight", 0.0))) + _value(int(rec.get("value", 0)))
		"light":
			text += _weight(float(rec.get("weight", 0.0))) + _value(int(rec.get("value", 0)))
		"potion":
			text += "\n%s: %s" % [_t("sWeight", "Weight"), num(float(rec.get("weight", 0.0)))]
			text += _value(int(rec.get("value", 0)))
			var me: Dictionary = main.combat.player_fighter()
			var effs := []
			var i := 0
			for e in rec.get("effects", []):
				var d: Dictionary = (e as Dictionary).duplicate()
				d["known"] = main.magic.known_effect(me, i)
				effs.append(d)
				i += 1
			info["effects"] = effs
			info["is_potion"] = true
		"ingredient":
			text += _weight(float(rec.get("weight", 0.0))) + _value(int(rec.get("value", 0)))
			var me2: Dictionary = main.combat.player_fighter()
			var sk2 := float(main.combat.skill(me2, main.magic.SK_ALCHEMY))
			var w := float(main.magic._gmst("fWortChanceValue", 15.0))
			var effs2 := []
			var j := 0
			for e in rec.get("effects", []):
				if int((e as Dictionary).get("effect", -1)) < 0:
					continue
				var d2: Dictionary = (e as Dictionary).duplicate()
				d2["known"] = sk2 >= w * float(j + 1)
				effs2.append(d2)
				j += 1
			info["effects"] = effs2
			info["is_ingredient"] = true
	info["text"] = text
	return info

## Obrażenia broni z rekordu (WPDT: chop/slash/thrust = [min, max]).
static func _dmg(rec: Dictionary, k: String, i: int) -> float:
	var a = rec.get(k, null)
	if a is Array and (a as Array).size() > i:
		return float(a[i])
	return float(rec.get("%s_%s" % [k, "min" if i == 0 else "max"], 0))

## getSkillAdjustedArmorRating: pancerz × umiejętność / iBaseArmorSkill (pancerz bez wagi – bez zmian).
func _adjusted_armor(rec: Dictionary) -> float:
	var r := float(rec.get("armor", 0))
	if float(rec.get("weight", 0.0)) == 0.0:
		return r
	var me: Dictionary = main.combat.player_fighter()
	return r * float(main.combat.skill(me, main.combat.armor_skill(rec))) / float(main.combat._gmst("iBaseArmorSkill", 30))

func _skill_name(sk: int) -> String:
	if _cu == null:
		_cu = CU.new(main, 1.0)
	return _cu.skill_name(sk)

## info.enchant i pozostały ładunek (CellRef::getEnchantmentCharge; −1 – pełny). Książki: bez ładunku.
func _add_enchant(info: Dictionary, it: Dictionary, id: String, with_charge := true) -> void:
	var en: Dictionary = main.magic.item_enchantment(it)
	if en.is_empty():
		return
	info["enchant"] = en
	if with_charge and String(it.kind) != "book":
		info["charge"] = int(main.magic.item_charge(main.combat.player_fighter(), id, en))

## Spell: nazwa, szkoła (spellIncreasesSkill – czary), efekty (zdolność – stałe).
func spell_info(spid: String, show_cost := false) -> Dictionary:
	var sp: Dictionary = main.magic.records.record("spell", spid.to_lower())
	if sp.is_empty():
		return {}
	var info := {"caption": String(sp.get("name", spid)), "text": "", "icon": ""}
	var constant := int(sp.get("spell_type", -1)) == 1
	var effs := []
	for e in sp.get("effects", []):
		var d: Dictionary = (e as Dictionary).duplicate()
		d["constant"] = constant
		effs.append(d)
	info["effects"] = effs
	# spellIncreasesSkill: czar bez flagi „zawsze się udaje” (F_Always 0x4) – szkoła (getSpellSchool)
	if int(sp.get("spell_type", -1)) == main.magic.SPELL_SPELL and (int(sp.get("flags", 0)) & 4) == 0:
		var school: int = int(main.magic.spell_base_chance(sp, main.combat.player_fighter()).get("school", -1))
		if school >= 0:
			info.text = "%s: %s" % [_t("sSchool", "School"), _skill_name(school)]
	if show_cost:
		var c: int = main.magic.spell_cost(sp)
		if c != 0:
			info.text += "\n%s: %d" % [_t("sCastCost", "Cast Cost"), c]
	return info

func info_for(tip: Dictionary) -> Dictionary:
	match String(tip.get("type", "")):
		"item":
			var info := item_info(String(tip.get("id", "")), int(tip.get("count", 1)))
			if not info.is_empty() and not String(tip.get("extra", "")).is_empty():
				info.text = String(info.text) + "\n" + String(tip.extra)
			return info
		"spell":
			return spell_info(String(tip.get("id", "")), bool(tip.get("cost", false)))
		"info":
			return tip
	return {}

# --- MWSpellEffect::updateWidgets -------------------------------------------------------------------------

func effect_line_text(e: Dictionary, flags: Dictionary) -> String:
	if _cu == null:
		_cu = CU.new(main, 1.0)
	var d := e.duplicate()
	if bool(flags.get("no_magnitude", false)):
		d["min"] = 0
		d["max"] = 0
	var constant := bool(flags.get("constant", false)) or bool(e.get("constant", false))
	var line: String = _cu.effect_text(d, constant)
	if bool(flags.get("no_target", false)) and not constant:
		# mikstury: bez „na kim” (mNoTarget) – usuwa końcowe „sonword zasięg”
		var tail: String = " " + _t("sonword", "on") + " "
		var k := line.rfind(tail)
		if k >= 0:
			line = line.left(k)
	return line

# --- createToolTip ------------------------------------------------------------------------------------------

func _font_size() -> int:
	return roundi(16 * _s)

func _text_size(t: String, wrap: float) -> Vector2:
	if t.is_empty():
		return Vector2.ZERO
	var f: Font = UI.font()
	var sz: Vector2 = f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, wrap, _font_size(), -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var lines := maxi(1, int(roundf(sz.y / f.get_height(_font_size()))))
	return Vector2(ceilf(sz.x), _lines_height(lines))

## Wysokość n wierszy tekstu w etykiecie (jak Label rysuje tekst, z odstępami czcionki interfejsu).
func _lines_height(n: int) -> float:
	var l := Label.new()
	l.text = "\n".join(PackedStringArray(range(n).map(func(_i): return "X")))
	l.add_theme_font_override("font", UI.font())
	l.add_theme_font_size_override("font_size", _font_size())
	l.add_theme_constant_override("line_spacing", 0)
	var h := l.get_minimum_size().y
	l.free()
	return h

func _label(parent: Control, text: String, pos: Vector2, size: Vector2, center := true, n := "", wrap := true) -> Label:
	var l := Label.new()
	if not n.is_empty():
		l.name = n
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_color", UI.color("normal"))
	l.add_theme_font_override("font", UI.font())
	l.add_theme_font_size_override("font_size", _font_size())
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = size
	parent.add_child(l)
	return l

## Buduje zawartość podpowiedzi w box; zwraca rozmiar (z odstępami).
func create_tooltip(info: Dictionary) -> Vector2:
	_s = UI.ui_scale()
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var gui: bool = main != null and main.get("gui") != null and main.gui.is_gui_mode()
	box.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 1) if gui else UI.WINDOW_BG))
	var caption := String(info.get("caption", ""))
	var image := String(info.get("icon", ""))
	var img := float(info.get("image_size", 32)) * _s if not image.is_empty() else 0.0
	var text := String(info.get("text", ""))
	var extra := String(info.get("extra", ""))
	if text.begins_with("\n"):
		text = text.substr(1)
	if extra.begins_with("\n"):
		extra = extra.substr(1)
	var en: Dictionary = info.get("enchant", {})
	if not en.is_empty():
		var key: String = ["sItemCastOnce", "sItemCastWhenStrikes", "sItemCastWhenUsed", "sItemCastConstant"][clampi(int(en.get("type", 0)), 0, 3)]
		var fb: String = ["Cast Once", "Cast When Strikes", "Cast When Used", "Constant Effect"][clampi(int(en.get("type", 0)), 0, 3)]
		text += "\n" + _t(key, fb)
		if text.begins_with("\n"):
			text = text.substr(1)
	var pad := PADDING * _s
	var hpad := (8.0 * _s) if not caption.is_empty() else 0.0
	var vpad := (4.0 * _s) if not caption.is_empty() else 0.0
	var vp := get_viewport().get_visible_rect().size
	var max_w := vp.x - hpad * 2.0
	var f: Font = UI.font()
	var cap_size := Vector2(ceilf(f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x), roundf(18 * _s)) if not caption.is_empty() else Vector2.ZERO
	var cap_h := maxf(cap_size.y, img)
	var tsize := _text_size(text, MAX_WRAP * _s)
	var cap_with_img := cap_size + Vector2(img, 0)
	var total := Vector2(minf(maxf(tsize.x, cap_with_img.x + (hpad if not image.is_empty() else 0.0)), max_w),
		(tsize.y + vpad if not text.is_empty() else 0.0) + cap_h)
	var lines_nodes := []
	# efekty (MWEffectList::createEffectWidgets)
	var effs: Array = info.get("effects", [])
	if not effs.is_empty():
		var flags := {"no_target": bool(info.get("is_potion", false)), "no_magnitude": bool(info.get("is_ingredient", false)),
			"constant": bool(info.get("is_ingredient", false))}
		var r := _effect_list(effs, flags, Vector2(pad, total.y), total.x,
			bool(info.get("is_potion", false)) or bool(info.get("is_ingredient", false)), "Effects")
		total.y += r.y
		total.x = maxf(total.x, r.x)
	if not en.is_empty():
		var flags2 := {"constant": int(en.get("type", 0)) == 3}
		var area_y := total.y
		var r2 := _effect_list(en.get("effects", []), flags2, Vector2(pad, area_y), total.x, false, "Enchant")
		total.y += r2.y
		total.x = maxf(total.x, r2.x)
		if int(en.get("type", 0)) in [1, 2] and info.has("charge"):
			var mx: int = main.magic.enchantment_charge(en)
			var ch := int(info.get("charge", mx))
			var cw := CHARGE_W * _s
			var ct := _t("sCharges", "Charges")
			var ctw := ceilf(f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x) + 5.0 * _s
			total.x = maxf(total.x, cw + ctw)
			var y := area_y + r2.y + 6.0 * _s
			_label(box, ct, Vector2(pad + floorf((total.x - cw - ctw) / 2.0), y), Vector2(ctw, 18 * _s), false, "ToolTipEnchantChargeText")
			var bar := UI.progress_bar("health", _s)
			bar.name = "ChargeBar"
			bar.max_value = maxi(1, mx)
			bar.value = ch
			bar.position = Vector2(pad + floorf((total.x - cw - ctw) / 2.0) + ctw, y)
			bar.size = Vector2(cw, 18 * _s)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(bar)
			var bt := _label(bar, "%d/%d" % [ch, mx], Vector2.ZERO, Vector2(cw, 16 * _s), true, "BarText")
			bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bt.autowrap_mode = TextServer.AUTOWRAP_OFF
			total.y += 24.0 * _s
	if not extra.is_empty():
		var es := _text_size(extra, MAX_WRAP * _s)
		_label(box, extra, Vector2(pad - 1.0, total.y + 12.0 * _s), Vector2(maxf(es.x, total.x) + 2.0, es.y), true, "ToolTipExtraText")
		total.y += es.y + 4.0 * _s
		total.x = maxf(total.x, es.x)
	# nagłówek, ikona, tekst
	if not caption.is_empty():
		var cl := _label(box, caption, Vector2(floorf((total.x - cap_with_img.x) / 2.0) + img, floorf((cap_h - cap_size.y) / 2.0)) + Vector2(pad, pad),
			cap_size + Vector2(2, 0), false, "ToolTipCaption")
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cl.add_theme_color_override("font_color", UI.color("normal"))
	if not text.is_empty():
		# szerokość z zapasem 2 px: etykieta zawija tekst równy dokładnie swojej szerokości
		# wiersze krótsze od granicy zawijania – bez zawijania (etykieta zawija tekst równy swojej szerokości)
		_label(box, text, Vector2(pad - 1.0, cap_h + vpad + pad), Vector2(total.x + 2.0, tsize.y), true, "ToolTipText",
			tsize.x >= MAX_WRAP * _s - 1.0)
	if not image.is_empty():
		var tr := TextureRect.new()
		tr.name = "ToolTipImage"
		tr.texture = UI.icon(image)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(floorf((total.x - cap_with_img.x - hpad) / 2.0), 0) + Vector2(pad, pad)
		tr.size = Vector2(img, img)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	total += Vector2(pad * 2.0, pad * 2.0)
	box.size = total
	last_info = info
	last_size = total
	return total

## Wiersze efektów od y = area.y + 6; zwraca (największa szerokość, przyrost wysokości).
func _effect_list(effs: Array, flags: Dictionary, area: Vector2, width: float, center: bool, n: String) -> Vector2:
	var f: Font = UI.font()
	var rows := []
	var maxw := width
	var y := area.y + 6.0 * _s
	for e in effs:
		var known := bool((e as Dictionary).get("known", true))
		var t := effect_line_text(e, flags) if known else "?"
		var req := ceilf(f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x) + ICON_OFFSET * _s
		maxw = maxf(maxw, req)
		rows.append([e, t, req, known, y])
		y += 24.0 * _s
	var i := 0
	for r in rows:
		var g := Control.new()
		g.name = "%s%d" % [n, i]
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x := floorf((maxw - float(r[2])) / 2.0) if center and maxw > float(r[2]) else 0.0
		g.position = Vector2(area.x + x, float(r[4]))
		g.size = Vector2(float(r[2]), 24.0 * _s)
		box.add_child(g)
		if bool(r[3]):
			var ic := TextureRect.new()
			var mg: Dictionary = main.magic.effect(int((r[0] as Dictionary).get("effect", -1)))
			ic.texture = UI.icon(String(mg.get("icon", "")))
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_SCALE
			ic.position = Vector2(4, 4) * _s
			ic.size = Vector2(16, 16) * _s
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			g.add_child(ic)
		var l := _label(g, String(r[1]), Vector2((ICON_OFFSET if bool(r[3]) else ICON_OFFSET / 2.0) * _s, 0),
			Vector2(float(r[2]), 20 * _s), false, "Text")
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		i += 1
	return Vector2(maxw, rows.size() * 24.0 * _s)

## ToolTips::position: 32 px pod kursorem, przesunięcie w lewo o (x kursora / szerokość ekranu) × szerokość podpowiedzi.
static func place(mouse: Vector2, size: Vector2, vp: Vector2) -> Vector2:
	var p := mouse + Vector2(0, 32) - Vector2(floorf(mouse.x / vp.x * size.x), 0)
	if p.x + size.x > vp.x:
		p.x = vp.x - size.x
	if p.y + size.y > vp.y:
		p.y = mouse.y - size.y - 8
	return p

# --- ToolTips::update ---------------------------------------------------------------------------------------

## Kontrolka z podpowiedzią pod kursorem (idąc w górę po przodkach – „1 level up until there is a widget that has
## tooltip”).
static func tip_of(c: Control) -> Dictionary:
	while c != null:
		if c.has_meta("mw_tip"):
			var v = c.get_meta("mw_tip")
			if v is Callable:
				v = (v as Callable).call()
			return v if v is Dictionary else {}
		c = c.get_parent() as Control
	return {}

func show_for(tip: Dictionary, mouse: Vector2) -> bool:
	var key := str(tip)
	if key != current_key:
		var info := info_for(tip)
		if info.is_empty():
			hide_tip()
			return false
		create_tooltip(info)
		current_key = key
	box.position = place(mouse, last_size, get_viewport().get_visible_rect().size)
	box.visible = true
	return true

func hide_tip() -> void:
	box.visible = false
	current_key = ""

func _process(_dt: float) -> void:
	if not enabled or main == null or main.get("gui") == null:
		return
	if not main.gui.is_gui_mode() or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if box.visible:
			hide_tip()
		return
	var vpt := get_viewport()
	var c := vpt.gui_get_hovered_control()
	var tip := tip_of(c)
	if tip.is_empty() or vpt.gui_is_dragging():
		if box.visible:
			hide_tip()
		return
	show_for(tip, vpt.get_mouse_position())
