extends CanvasLayer
## Podpowiedzi jak OpenMW 0.51 ToolTips (apps/openmw/mwgui/tooltips.cpp, openmw_tooltips.layout,
## MWClass::*::getToolTipInfo, Widgets::MWSpellEffect/MWEffectList):
##  - w trybie GUI kontrolka pod kursorem (albo jej przodek) z meta „mw_tip” – {type: "item", id, count} (ItemPtr /
##    ItemModelIndex), {type: "spell", id} (Spell), {type: "info", …} (ToolTipInfo); opóźnienie [GUI] tooltip
##    delay (domyślnie 0 – od razu); położenie ToolTips::position (32 px pod kursorem, przesunięcie w lewo proporcjonalne do x kursora,
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
		"layout":
			return tip
		"effect_icon":
			return effect_icon_info(int(tip.get("id", -1)))
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
	if info.has("layout"):
		return _create_layout(info)
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
	# notatki znacznika mapy (ToolTipInfo::notes): ikona MarkerButton 8 × 8 w kolorze (1; 0,3; 0,3) i pierwszy wiersz
	# notatki skrócony do 60 znaków („ ...”)
	var note_i := 0
	for note in info.get("notes", []):
		var ns := String(note)
		var cut := ns.substr(0, mini(60, ns.find("\n") if ns.find("\n") >= 0 else ns.length()))
		if cut.length() < ns.length():
			cut += " ..."
		var nsz := Vector2(ceilf(f.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x), roundf(18 * _s))
		var nl := _label(box, cut, Vector2(pad + 12.0 * _s, total.y + pad), nsz + Vector2(2, 0), false, "ToolTipNote%d" % note_i)
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		var ic: Control
		var dtex: Texture2D = UI.texture("textures/door_icon")
		if dtex != null:
			var itr := TextureRect.new()
			itr.texture = dtex
			itr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			itr.stretch_mode = TextureRect.STRETCH_SCALE
			ic = itr
		else:
			var icr := ColorRect.new()
			icr.color = Color.WHITE
			ic = icr
		ic.name = "ToolTipNoteIcon%d" % note_i
		note_i += 1
		ic.modulate = Color(1.0, 0.3, 0.3)
		ic.size = Vector2(8, 8) * _s
		ic.position = Vector2(pad, total.y + pad + floorf((nsz.y - 8.0 * _s) / 2.0))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
		total.y += maxf(nsz.y, 8.0 * _s)
		total.x = maxf(total.x, nsz.x + 12.0 * _s)
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

var delay := 0.0                  # [GUI] tooltip delay (s)
var _remaining_delay := 0.0
var _last_mouse := Vector2(-1, -1)

func _process(_dt: float) -> void:
	if not enabled or main == null or main.get("gui") == null:
		return
	var gui_mode: bool = main.gui.is_gui_mode() or (main.get("script_host") != null and main.script_host != null
		and main.script_host.menu_mode())       # isGuiMode – także kreator postaci i okna poza stosem trybów
	if not gui_mode or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if box.visible:
			hide_tip()
		return
	var vpt := get_viewport()
	# ToolTips::onFrame: podpowiedź po „tooltip delay” s bez ruchu myszy (ruch – od nowa)
	var mp := vpt.get_mouse_position()
	if mp == _last_mouse:
		_remaining_delay -= _dt
	else:
		_remaining_delay = delay
	_last_mouse = mp
	if _remaining_delay > 0.0:
		if box.visible:
			hide_tip()
		return
	var c := vpt.gui_get_hovered_control()
	var tip := tip_of(c)
	if tip.is_empty() or vpt.gui_is_dragging():
		if box.visible:
			hide_tip()
		return
	show_for(tip, vpt.get_mouse_position())

# --- podpowiedzi układów (openmw_tooltips.layout, typ „Layout”) ------------------------------------------------

const SKILL_ICONS := ["combat_block", "combat_armor", "combat_mediumarmor", "combat_heavyarmor", "combat_blunt",
	"combat_longblade", "combat_axe", "combat_spear", "combat_athletics", "magic_enchant", "magic_destruction",
	"magic_alteration", "magic_illusion", "magic_conjuration", "magic_mysticism", "magic_restoration", "magic_alchemy",
	"magic_unarmored", "stealth_security", "stealth_sneak", "stealth_acrobatics", "stealth_lightarmor",
	"stealth_shortblade", "stealth_marksman", "stealth_mercantile", "stealth_speechcraft", "stealth_handtohand"]
const ATTR_ICONS := ["attribute_strength", "attribute_int", "attribute_wilpower", "attribute_agility",
	"attribute_speed", "attribute_endurance", "attribute_personality", "attribute_luck"]
const ATTR_EN := ["Strength", "Intelligence", "Willpower", "Agility", "Speed", "Endurance", "Personality", "Luck"]
const ATTR_DESC := ["sStrDesc", "sIntDesc", "sWilDesc", "sAgiDesc", "sSpdDesc", "sEndDesc", "sPerDesc", "sLucDesc"]
const ATTR_GMST := ["sAttributeStrength", "sAttributeIntelligence", "sAttributeWillpower", "sAttributeAgility",
	"sAttributeSpeed", "sAttributeEndurance", "sAttributePersonality", "sAttributeLuck"]
const SPEC_GMST := ["sSpecializationCombat", "sSpecializationMagic", "sSpecializationStealth"]

## Opis rekordu z warstwą tłumaczeń (gdy aktywna).
func _desc(rtype: String, id: String, fb: String) -> String:
	var loc = main.get("loc") if main != null else null
	if loc != null and loc.has_method("is_active") and loc.is_active():
		return loc.plain(loc.key(rtype, id, "DESC"), fb)
	return fb

func _skill_rec(i: int) -> Dictionary:
	var names: Array = main.character.skill_names() if main.get("character") != null else []
	return main.character.records.record("skill", String(names[i])) if i >= 0 and i < names.size() else {}

## createSkillToolTip / StatsWindow: SkillToolTip (z postępem: progress 0…100 albo -1 – bez paska, maxed – osiągnięto
## maksimum) albo SkillNoProgressToolTip.
func skill_tip(i: int, progress := -2, maxed := false) -> Dictionary:
	var rec := _skill_rec(i)
	var att := int(rec.get("attribute", 0))
	var t := {"type": "layout", "layout": "skill" if progress > -2 else "skill_np", "name": _skill_name(i),
		"attribute": "%s: %s" % [_t("sGoverningAttribute", "Governing Attribute"), _t(ATTR_GMST[clampi(att, 0, 7)], ATTR_EN[clampi(att, 0, 7)])],
		"description": _desc("SKIL", String(rec.get("id", "")), String(rec.get("description", ""))),
		"image": "k/%s.dds" % SKILL_ICONS[clampi(i, 0, 26)]}
	if progress > -2:
		t["maxed"] = maxed
		t["progress"] = maxi(progress, 0)
	return t

func attribute_tip(i: int) -> Dictionary:
	return {"type": "layout", "layout": "attribute", "name": _t(ATTR_GMST[i], ATTR_EN[i]), "description": _t(ATTR_DESC[i], ""),
		"image": "k/%s.dds" % ATTR_ICONS[i]}

## HealthToolTip (pasek zdrowia/magii/kondycji w statystykach): opis GMST + „bieżące / największe”.
func health_tip(kind: String, cur: int, mx: int) -> Dictionary:
	var d: String = {"health": _t("sHealthDesc", ""), "magic": _t("sMagDesc", ""), "fatigue": _t("sFatDesc", "")}.get(kind, "")
	var img: String = {"health": "k/health.dds", "magic": "k/magicka.dds", "fatigue": "k/fatigue.dds"}.get(kind, "")
	return {"type": "layout", "layout": "health", "description": "%s\n%d / %d" % [d, cur, mx], "image": img}

func class_tip(cls: Dictionary) -> Dictionary:
	if String(cls.get("name", "")).is_empty():
		return {}
	return {"type": "layout", "layout": "class", "name": String(cls.get("name", "")),
		"description": _desc("CLAS", String(cls.get("id", "")), String(cls.get("description", ""))),
		"footer": "%s: %s" % [_t("sSpecialization", "Specialization"), _t(SPEC_GMST[clampi(int(cls.get("specialization", 0)), 0, 2)], ["Combat", "Magic", "Stealth"][clampi(int(cls.get("specialization", 0)), 0, 2)])]}

func race_tip(race: Dictionary) -> Dictionary:
	return {"type": "layout", "layout": "race", "name": String(race.get("name", "")),
		"description": _desc("RACE", String(race.get("id", "")), String(race.get("description", "")))}

## createSpecializationToolTip: nazwa i umiejętności specjalizacji (w kolejności rekordów).
func specialization_tip(spec: int) -> Dictionary:
	var lines := []
	for i in 27:
		if int(_skill_rec(i).get("specialization", -1)) == spec:
			lines.append(_skill_name(i))
	return {"type": "layout", "layout": "specialization", "name": _t(SPEC_GMST[clampi(spec, 0, 2)], ["Combat", "Magic", "Stealth"][clampi(spec, 0, 2)]), "description": "\n".join(lines)}

## createBirthsignToolTip: obraz znaku (MW_Box 263 × 137), nazwa, opis, zdolności / moce / czary.
func birthsign_tip(sign: Dictionary) -> Dictionary:
	var cats := {"abilities": [], "powers": [], "spells": []}
	for spid in sign.get("spells", []):
		var sp: Dictionary = main.magic.records.record("spell", String(spid).to_lower())
		match int(sp.get("spell_type", -1)):
			1: cats.abilities.append(String(sp.get("name", spid)))
			5: cats.powers.append(String(sp.get("name", spid)))
			0: cats.spells.append(String(sp.get("name", spid)))
	var groups := []
	for g in [["abilities", "sBirthsignmenu1", "Abilities"], ["powers", "sPowers", "Powers"], ["spells", "sBirthsignmenu2", "Spells"]]:
		if not (cats[g[0]] as Array).is_empty():
			groups.append([_t(g[1], g[2]), " ".join(cats[g[0]])])
	return {"type": "layout", "layout": "birthsign", "name": String(sign.get("name", "")),
		"description": _desc("BSGN", String(sign.get("id", "")), String(sign.get("description", ""))),
		"texture": String(sign.get("texture", "")), "groups": groups}

## createMagicEffectToolTip: wielka ikona, nazwa, szkoła, opis.
func magic_effect_tip(id: int) -> Dictionary:
	var mg: Dictionary = main.magic.effect(id)
	var icon := String(mg.get("icon", ""))
	return {"type": "layout", "layout": "magic_effect", "name": _t("sEffect" + String(mg.get("name", "")).replace(" ", ""), String(mg.get("name", ""))),
		"school": "%s: %s" % [_t("sSchool", "School"), _skill_name(int(mg.get("school_skill", 11)))],
		"description": _desc("MGEF", str(id), String(mg.get("description", ""))),
		"image": preload("res://scripts/mw/mw_hud.gd").big_icon(icon) if not icon.is_empty() else ""}

## LevelToolTip: sLevelProgress, pasek postępu do awansu, mnożniki atrybutów (> 1).
func level_tip(progress: int, total: int, detail: String) -> Dictionary:
	return {"type": "layout", "layout": "level", "progress": progress, "total": total, "description": detail}

func text_tip(text: String) -> Dictionary:
	return {"type": "layout", "layout": "text", "description": text}

## FactionToolTip: wiersze [kolor, tekst] (fontcolourhtml=header/normal).
func faction_tip(lines: Array) -> Dictionary:
	return {"type": "layout", "layout": "faction", "lines": lines}

## SpellIcons: ToolTipInfo ikony działającego efektu – nazwa, ikona 16 px, wiersze źródeł z wielkością.
func effect_icon_info(id: int) -> Dictionary:
	var mg: Dictionary = main.magic.effect(id)
	if mg.is_empty():
		return {}
	var me: Dictionary = main.combat.player_fighter()
	var lines := []
	for sp in main.magic.active(me):
		for x in sp.effects:
			if int(x.effect) == id:
				lines.append(String(sp.get("name", "")) + _arg_name(mg, x) + _magnitude_text(mg, float(x.get("magnitude", 0.0)), id))
	# zdolności i stałe zaklęcia założonych przedmiotów (w OpenMW też aktywne czary)
	for src in _constant_sources(me):
		for x in src.effects:
			if int(x.get("effect", -1)) == id:
				lines.append(String(src.name) + _arg_name(mg, x) + _magnitude_text(mg, float(x.get("min", 0)), id))
	return {"caption": _t("sEffect" + String(mg.get("name", "")).replace(" ", ""), String(mg.get("name", ""))),
		"icon": String(mg.get("icon", "")), "image_size": 16, "text": "\n".join(lines), "word_wrap": false}

func _constant_sources(me: Dictionary) -> Array:
	var out := []
	for spid in main.player_stats().get("spells", []):
		var sp: Dictionary = main.magic.records.record("spell", String(spid))
		if int(sp.get("spell_type", -1)) in [1, 2, 3, 4]:          # zdolność, plaga, choroba, plaga Corprus
			out.append({"name": String(sp.get("name", spid)), "effects": sp.get("effects", [])})
	var eq: Dictionary = main._equipment()
	for sl in eq:
		var it: Dictionary = main.interaction.inventory.item(String(eq[sl].id))
		var en: Dictionary = main.magic.item_enchantment(it)
		if not en.is_empty() and int(en.get("type", -1)) == main.magic.ENCH_CONSTANT:
			out.append({"name": main.interaction.item_name(String(it.kind), String(eq[sl].id), it.rec), "effects": en.get("effects", [])})
	return out

func _arg_name(mg: Dictionary, x: Dictionary) -> String:
	if bool(mg.get("target_skill", false)) and int(x.get("skill", -1)) >= 0:
		return " (%s)" % _skill_name(int(x.skill))
	if bool(mg.get("target_attribute", false)) and int(x.get("attribute", -1)) >= 0:
		return " (%s)" % _t(ATTR_GMST[clampi(int(x.attribute), 0, 7)], ATTR_EN[clampi(int(x.attribute), 0, 7)])
	return ""

## printEffectMagnitude.
func _magnitude_text(mg: Dictionary, m: float, id: int) -> String:
	var disp: String = CU.magnitude_display(id, bool(mg.get("no_magnitude", false)))
	if disp == "none":
		return ""
	var mi := int(m)
	var r := ""
	if disp == "times_int":
		r = " %.1f" % (mi / 10.0)
	else:
		r = ": %d" % mi + ("" if disp == "percent" else " ")
	var unit := ""
	match disp:
		"times_int": unit = _t("sXTimesINT", "x INT")
		"percent": unit = _t("sPercent", "%")
		"feet": unit = _t("sFeet", "ft")
		"level": unit = _t("sLevels", "levels") if mi > 1 else _t("sLevel", "level")
		_: unit = _t("sPoints", "pts") if mi > 1 else _t("sPoint", "pt")
	return r + unit

# budowanie układów (VBox/HBox z AutoResize, Padding, Spacing)

func _lab(text: String, color := "normal", align := HORIZONTAL_ALIGNMENT_LEFT, wrap_w := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", UI.color(color))
	l.add_theme_font_override("font", UI.font())
	l.add_theme_font_size_override("font_size", _font_size())
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap_w > 0.0:
		# AutoSizedEditBox z WordWrap (i Shrink): szerokość z tekstu, nie większa niż w układzie
		var tw := _text_size(text, wrap_w * _s).x
		var w := minf(tw, wrap_w * _s) + 2.0
		l.custom_minimum_size.x = w
		if tw >= wrap_w * _s - 1.0:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _img(path: String, size: Vector2, texture_path := false) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = "Image"
	tr.texture = (UI.texture(path) if texture_path else UI.icon(path)) if not path.is_empty() else null
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = size * _s
	tr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _bar(value: int, mx: int, w: float, h: float) -> Control:
	var bar := UI.progress_bar("health", _s)
	bar.name = "Progress"
	bar.max_value = maxi(1, mx)
	bar.value = value
	bar.custom_minimum_size = Vector2(w, h) * _s
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _lab("%d/%d" % [value, mx], "normal", HORIZONTAL_ALIGNMENT_CENTER)
	t.name = "ProgressText"
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(t)
	return bar

func _vbox(sp: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", roundi(sp * _s))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

func _hbox(sp: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", roundi(sp * _s))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h * _s
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _create_layout(info: Dictionary) -> Vector2:
	var gui: bool = main != null and main.get("gui") != null and main.gui.is_gui_mode()
	box.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 1) if gui else UI.WINDOW_BG))
	var pad := 8.0
	var root: Container = null
	var lay := String(info.layout)
	match lay:
		"text":
			pad = 6.0
			root = _vbox(0)
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 268))
		"text_one_line":                                # TextToolTipOneLine: AutoSizedTextBox bez zawijania
			root = _vbox(0)
			root.add_child(_lab(String(info.description)))
		"faction":
			root = _vbox(0)
			for ln in info.get("lines", []):
				root.add_child(_lab(String(ln[1]), String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, 436))
		"race", "class":
			root = _vbox(8)
			root.add_child(_lab(String(info.name), "normal", HORIZONTAL_ALIGNMENT_CENTER))
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 430))
			if lay == "class":
				root.add_child(_lab(String(info.get("footer", "")), "normal", HORIZONTAL_ALIGNMENT_CENTER))
		"specialization":
			root = _vbox(0)
			var c := _lab(String(info.name), "normal", HORIZONTAL_ALIGNMENT_CENTER)
			c.custom_minimum_size.x = 140 * _s
			root.add_child(c)
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 140))
		"health":
			pad = 14.0
			root = _hbox(8)
			root.add_child(_img(String(info.image), Vector2(32, 32)))
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 392))
		"attribute":
			root = _vbox(8)
			var h := _hbox(8)
			h.add_child(_img(String(info.image), Vector2(32, 32)))
			var n := _lab(String(info.name))
			n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(n)
			root.add_child(h)
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 436))
		"skill", "skill_np", "magic_effect":
			root = _vbox(0)
			var h2 := _hbox(8)
			h2.add_child(_img(String(info.image), Vector2(32, 32)))
			var v2 := _vbox(0)
			v2.add_child(_lab(String(info.name)))
			v2.add_child(_lab(String(info.get("attribute", info.get("school", "")))))
			h2.add_child(v2)
			root.add_child(h2)
			if lay != "magic_effect":
				root.add_child(_gap(2))
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 436 if lay == "magic_effect" else 430))
			if lay == "skill":
				root.add_child(_gap(2))
				if bool(info.get("maxed", false)):
					root.add_child(_lab(_t("sSkillMaxReached", "Maximum skill reached"), "normal", HORIZONTAL_ALIGNMENT_CENTER))
				else:
					root.add_child(_lab(_t("sSkillProgress", "Progress to next level"), "normal", HORIZONTAL_ALIGNMENT_CENTER))
					root.add_child(_bar(int(info.get("progress", 0)), 100, 200, 20))
		"level":
			root = _vbox(0)
			var c2 := _lab(_t("sLevelProgress", "Level progress"), "normal", HORIZONTAL_ALIGNMENT_CENTER)
			c2.custom_minimum_size.x = 284 * _s
			root.add_child(c2)
			root.add_child(_bar(int(info.get("progress", 0)), int(info.get("total", 10)), 180, 20))
			if not String(info.get("description", "")).is_empty():
				root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_CENTER))
		"birthsign":
			pad = 10.0
			root = _vbox(0)
			var frame := PanelContainer.new()
			frame.add_theme_stylebox_override("panel", UI.inner_box())
			frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bi := _img(String(info.get("texture", "")), Vector2(259, 133), true)
			bi.name = "BirthSignImage"
			frame.add_child(bi)
			root.add_child(frame)
			root.add_child(_lab(String(info.name), "normal", HORIZONTAL_ALIGNMENT_CENTER))
			root.add_child(_lab(String(info.description), "normal", HORIZONTAL_ALIGNMENT_LEFT, 400))
			for g in info.get("groups", []):
				root.add_child(_lab("%s\n%s" % [g[0], g[1]], "normal", HORIZONTAL_ALIGNMENT_CENTER))
		_:
			return Vector2.ZERO
	root.name = "Layout_" + lay
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		m.add_theme_constant_override(side, roundi(pad * _s))
	m.add_child(root)
	box.add_child(m)
	var sz := m.get_combined_minimum_size()
	m.size = sz
	box.size = sz
	last_info = info
	last_size = sz
	return sz
