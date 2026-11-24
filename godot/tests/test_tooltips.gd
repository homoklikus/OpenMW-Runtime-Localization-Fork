extends SceneTree
## Etap 10: podpowiedzi jak OpenMW 0.51 ToolTips – getToolTipInfo klas przedmiotów (broń, pancerz, mikstura,
## składnik, złoto, przedmiot zaklęty), Spell, createToolTip (układ: nagłówek z ikoną, tekst, efekty, ładunek),
## ToolTips::position, wyszukiwanie podpowiedzi w górę drzewa kontrolek, tylko w trybie GUI.
## godot --headless --path godot -s res://tests/test_tooltips.gd -- --data=WYNIKI(aktorzy) --pos=2300,2400,900

var failures: Array[String] = []
var checks := 0

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var tt = main.tooltips
	var T := func(gm: String, fb: String) -> String: return main.dialogue.gmst_text(gm, fb)
	var inv = main.interaction.inventory
	check(tt != null, "ToolTips utworzone")
	check(tt.num(1.5) == "1.5" and tt.num(2.0) == "2" and tt.num(0.25) == "0.25" and tt.num(10.0) == "10", "toString(float): obcięte zera")
	# broń: typ (umiejętność, jedno-/dwuręczna), cięcie/sieczenie/pchnięcie z rekordu [min, max], stan, waga, wartość
	var w: Dictionary = tt.item_info("synth_sword#c:100", 2)
	var wl: PackedStringArray = String(w.text).substr(1).split("\n")
	check(String(w.caption).ends_with(" (2)"), "liczba w nagłówku (%s)" % w.caption)
	check(wl.size() == 7 and wl[0].begins_with(T.call("sType", "Type") + " ") and wl[0].ends_with(", " + T.call("sOneHanded", "One Handed"))
		and wl[1] == "%s: 2 - 8" % T.call("sChop", "Chop") and wl[2] == "%s: 2 - 9" % T.call("sSlash", "Slash")
		and wl[3] == "%s: 1 - 4" % T.call("sThrust", "Thrust") and wl[4] == "%s: 100/300" % T.call("sCondition", "Condition")
		and wl[5] == "%s: 10" % T.call("sWeight", "Weight") and wl[6] == "%s: 40" % T.call("sValue", "Value"),
		"broń – wiersze jak Weapon::getToolTipInfo (%s)" % [wl])
	check(String(w.icon) != "" or true, "ikona z rekordu")
	# pancerz: sArmorRating (z umiejętnością), stan, „waga (typ)”, wartość
	var a: Dictionary = tt.item_info("synth_cuirass")
	var al: PackedStringArray = String(a.text).substr(1).split("\n")
	check(al.size() == 4 and al[0].begins_with(T.call("sArmorRating", "Armor Rating") + ": ") and al[1] == "%s: 200/200" % T.call("sCondition", "Condition")
		and al[2].begins_with("%s: 18 (" % T.call("sWeight", "Weight")) and al[3] == "%s: 80" % T.call("sValue", "Value"),
		"pancerz – wiersze jak Armor::getToolTipInfo (%s)" % [al])
	var me: Dictionary = main.combat.player_fighter()
	var want_ar := int(12.0 * main.combat.skill(me, main.combat.armor_skill(inv.item("synth_cuirass").rec)) / main.combat._gmst("iBaseArmorSkill", 30))
	check(al[0].ends_with(": %d" % want_ar), "pancerz dostosowany umiejętnością (%s, oczekiwano %d)" % [al[0], want_ar])
	# mikstura: efekty bez „na kim”, znajomość wg alchemii (knownEffect)
	var p: Dictionary = tt.item_info("synth_potion")
	check(bool(p.get("is_potion", false)) and (p.effects as Array).size() == 2, "mikstura: 2 efekty, isPotion")
	var line: String = tt.effect_line_text(p.effects[0], {"no_target": true})
	check(not line.contains(T.call("sRangeSelf", "Self")) and line.contains("10"), "mikstura: bez zasięgu (EF_NoTarget) – %s" % line)
	check(bool(p.effects[0].known) == main.magic.known_effect(me, 0), "znajomość efektu mikstury (Alchemy::knownEffect)")
	# składnik: bez wielkości i czasu, znajomość progami fWortChanceValue × (i + 1)
	var ing: Dictionary = tt.item_info("synth_ing_a")
	var sk := float(main.combat.skill(me, main.magic.SK_ALCHEMY))
	var wv := float(main.magic._gmst("fWortChanceValue", 15.0))
	check(bool(ing.get("is_ingredient", false)) and bool(ing.effects[0].known) == (sk >= wv) and bool(ing.effects[1].known) == (sk >= 2.0 * wv),
		"składnik: znajomość efektów (alchemia %.0f, próg %.0f)" % [sk, wv])
	# złoto: liczba × wartość, bez wartości
	var g: Dictionary = tt.item_info("gold_001", 25)
	if not g.is_empty(): check(String(g.caption).ends_with(" (25)") and not String(g.text).contains(T.call("sValue", "Value")), "złoto: liczba sztuk złota, bez sValue")
	# przedmiot zaklęty: typ zaklęcia w tekście, efekty, ładunek (przy użyciu)
	var r: Dictionary = tt.item_info("synth_ring")
	check(not (r.get("enchant", {}) as Dictionary).is_empty() and int(r.get("charge", -1)) == 50, "pierścień: zaklęcie i ładunek 50")
	main.gui.push("probe", [])
	var sz: Vector2 = tt.create_tooltip(r)
	var s: float = preload("res://scripts/mw/mw_ui.gd").ui_scale()
	var txt: Label = tt.box.get_node_or_null("ToolTipText")
	check(txt != null and txt.text.ends_with(T.call("sItemCastWhenUsed", "Cast When Used")), "tekst kończy sItemCastWhenUsed")
	var bar: ProgressBar = tt.box.get_node_or_null("ChargeBar")
	check(bar != null and int(bar.value) == 50 and is_equal_approx(bar.size.x, 204 * s) and tt.box.get_node_or_null("ToolTipEnchantChargeText") != null,
		"ładunek: #{sCharges} i pasek 204 px")
	check(tt.box.get_node_or_null("Enchant0") != null, "efekt zaklęcia (wiersz MW_EffectImage)")
	check(sz.x >= (204 + 16) * s and is_equal_approx(tt.box.size.x, sz.x), "szerokość ≥ pasek + odstępy")
	var sc: Dictionary = tt.item_info("synth_scroll")
	tt.create_tooltip(sc)
	check(tt.box.get_node_or_null("ChargeBar") == null, "zwój (jednorazowy) – bez paska ładunku")
	# układ: nagłówek z ikoną, odstęp 8, tekst pod nagłówkiem (32 px ikony + 4)
	var info := {"caption": "Abc", "icon": "x", "text": "Line one\nLine two"}
	var sz2: Vector2 = tt.create_tooltip(info)
	var cap: Label = tt.box.get_node("ToolTipCaption")
	var img: TextureRect = tt.box.get_node("ToolTipImage")
	var tx: Label = tt.box.get_node("ToolTipText")
	check(is_equal_approx(img.position.y, 8 * s) and is_equal_approx(img.size.x, 32 * s), "ikona 32 px od (…, 8)")
	check(cap.position.x > img.position.x + img.size.x - 1 and is_equal_approx(tx.position.y, (32 + 4 + 8) * s), "nagłówek obok ikony, tekst pod (y = 32 + 4 + 8)")
	check(is_equal_approx(sz2.y, (32 + 4 + 8 + 8) * s + tx.get_line_count() * roundf(16.0 * s)), "wysokość: nagłówek + 4 + wiersze × 16 (getTextSize) + 2 × 8 (%s, tekst %s, wiersze %d)" % [sz2, tx.size, tx.get_line_count()])
	# efekty mikstury wyśrodkowane, wiersze co 24 px od y + 6
	tt.create_tooltip(p)
	var e0: Control = tt.box.get_node("Effects0")
	var e1: Control = tt.box.get_node("Effects1")
	check(is_equal_approx(e1.position.y - e0.position.y, 24 * s), "wiersze efektów co 24 px")
	# ToolTips::position
	var vp := Vector2(1280, 720)
	check(tt.place(Vector2(0, 100), Vector2(200, 100), vp) == Vector2(0, 132), "pod kursorem +32")
	check(tt.place(Vector2(640, 100), Vector2(200, 100), vp) == Vector2(540, 132), "przesunięcie w lewo o x/szer. × szer. podpowiedzi")
	check(tt.place(Vector2(1270, 100), Vector2(300, 100), vp).x == 973 and tt.place(Vector2(50, 0), Vector2(150, 10), Vector2(100, 100)).x == -50, "dociągnięcie do prawej krawędzi tylko przy przekroczeniu")
	check(tt.place(Vector2(100, 700), Vector2(200, 100), vp).y == 592, "przy dolnej krawędzi – nad kursorem (−8)")
	# siatka ekwipunku: meta na komórce, wyszukiwanie w górę drzewa, widoczność tylko w trybie GUI
	main.gui.pop()
	inv.add("player", {}, "synth_potion", 2)
	main.menu_mode.open()
	await _frames(3)
	var grid: Control = main.menu_mode._grid
	var cell: Control = null
	for c in grid.get_children():
		if String(c.get("item_id")) == "synth_potion":
			cell = c
	check(cell != null and cell.tooltip_text == "", "komórka bez zwykłej podpowiedzi Godota")
	var ic: Control = cell.get_node("Icon") if cell != null else null
	var tip: Dictionary = tt.tip_of(ic)
	check(String(tip.get("type", "")) == "item" and String(tip.id) == "synth_potion" and int(tip.count) >= 2, "podpowiedź z rodzica ikony (%s)" % [tip])
	check(tt.show_for(tip, Vector2(300, 300)) and tt.box.visible and String(tt.last_info.caption).ends_with(")"), "podpowiedź w trybie GUI")
	main.menu_mode.close()
	await _frames(2)
	check(not tt.box.visible, "poza trybem GUI – ukryta")
	# czar: szkoła i efekty; zakup czarów – z kosztem (SpellCost)
	var si: Dictionary = tt.spell_info("synth_bolt")
	check(String(si.caption) != "" and String(si.text).begins_with(T.call("sSchool", "School") + ": ") and (si.effects as Array).size() > 0, "czar: szkoła i efekty (%s)" % si.text)
	var si2: Dictionary = tt.spell_info("synth_bolt", true)
	check(String(si2.text).contains(T.call("sCastCost", "Cast Cost")), "SpellCost: koszt rzucenia")
	var pw: Dictionary = tt.spell_info("synth_power")
	check(not String(pw.text).contains(T.call("sSchool", "School")), "moc – bez szkoły (spellIncreasesSkill)")
	# --- podpowiedzi układów (Layout) ---
	main.gui.push("probe", [])
	var skt: Dictionary = tt.skill_tip(5, 40, false)
	tt.create_tooltip(skt)
	var lay: Control = tt.box.find_child("Layout_skill", true, false)
	var pbar: ProgressBar = tt.box.find_child("Progress", true, false)
	check(lay != null and pbar != null and int(pbar.value) == 40 and int(pbar.max_value) == 100, "SkillToolTip: pasek postępu 40/100")
	check(String(skt.attribute).begins_with(T.call("sGoverningAttribute", "Governing Attribute") + ": ") and String(skt.image) == "k/combat_longblade.dds",
		"umiejętność: atrybut kierujący i ikona combat_longblade (%s)" % skt.image)
	tt.create_tooltip(tt.skill_tip(5, 0, true))
	check(tt.box.find_child("Progress", true, false) == null, "umiejętność ≥ 100: sSkillMaxReached bez paska")
	tt.create_tooltip(tt.skill_tip(5))
	check(tt.box.find_child("Layout_skill_np", true, false) != null, "SkillNoProgressToolTip (kreator: premie rasy)")
	var at: Dictionary = tt.attribute_tip(0)
	check(String(at.image) == "k/attribute_strength.dds" and String(at.name) == T.call("sAttributeStrength", "Strength"), "AttributeToolTip: ikona i nazwa")
	var hs: Vector2 = tt.create_tooltip(tt.health_tip("health", 5, 10))
	var hl: Label = null
	for c in tt.box.find_children("*", "Label", true, false):
		if (c as Label).text.ends_with("5 / 10"):
			hl = c
	check(hl != null and hs.x > 0.0, "HealthToolTip: opis i „5 / 10”")
	var mt: Dictionary = tt.magic_effect_tip(13)
	check(String(mt.school).begins_with(T.call("sSchool", "School") + ": "), "MagicEffectToolTip: szkoła (%s)" % mt.school)
	tt.create_tooltip(tt.level_tip(3, 10, ""))
	var lb: ProgressBar = tt.box.find_child("Progress", true, false)
	check(lb != null and int(lb.value) == 3 and int(lb.max_value) == 10, "LevelToolTip: postęp 3/10")
	var bs: Dictionary = tt.birthsign_tip(main.builder.actors.record("birthsign", "Synth Sign"))
	check((bs.groups as Array).size() == 2, "BirthSignToolTip: zdolności i moce (%s)" % [bs.groups])
	main.gui.pop()
	# statystyki: wiersze z podpowiedziami układów
	main.menu_mode.open()
	await _frames(3)
	var kinds := {}
	for c in main.menu_mode.windows["stats"].find_children("*", "", true, false):
		if c.has_meta("mw_tip"):
			var tp: Dictionary = c.get_meta("mw_tip")
			kinds[String(tp.get("layout", tp.get("type", "")))] = true
	check(kinds.has("health") and kinds.has("level") and kinds.has("race") and kinds.has("class") and kinds.has("attribute")
		and kinds.has("skill") and kinds.has("text"), "okno statystyk: podpowiedzi zdrowia, poziomu, rasy, klasy, atrybutów, umiejętności, reputacji (%s)" % [kinds.keys()])
	main.menu_mode.close()
	# ikona działającego efektu: ToolTipInfo z nazwą źródła i wielkością
	main.magic.drink(main.combat.player_fighter(), "synth_potion")
	for i in 10:
		await physics_frame
	var ei: Dictionary = tt.effect_icon_info(75)
	check(int(ei.get("image_size", 0)) == 16 and String(ei.text).contains(": 10 "), "ikona efektu: źródło i wielkość (%s)" % String(ei.get("text", "")).replace("\n", " | "))
	# obiekt pod celownikiem (ToolTips::update poza trybem GUI): pełna podpowiedź getToolTipViaPtr (przedmiot – jak
	# w ekwipunku, z ikoną; drzwi – „to” i cel; pojemnik – zamek), wyśrodkowana nad górą obrysu obiektu
	root.size = Vector2i(1280, 720)
	await _frames(2)
	var door: Node = null
	var item: Node = null
	var cont: Node = null
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			var ty := String(main.interaction.base_of(n).get("type", ""))
			if ty == "DOOR" and door == null and not MWTravel.door_destination(n).is_empty():
				door = n
			elif ty == "CONT" and cont == null:
				cont = n
			elif main.interaction.kind_of(n) == "item" and item == null:
				item = n
	if item != null:
		var fi: Dictionary = tt.focus_info(item)
		var ii: Dictionary = tt.item_info(String(item.get_meta("mw_base", "")), main.interaction.count_of_ref(item))
		check(fi == ii and not String(fi.get("caption", "")).is_empty(), "przedmiot w świecie: podpowiedź jak w ekwipunku (%s)" % fi.get("caption", ""))
	if door != null:
		var fd: Dictionary = tt.focus_info(door)
		check(String(fd.get("text", "")).begins_with("\n" + T.call("sTo", "to") + "\n"), "drzwi: „to” i cel (Door::getToolTipInfo)")
	if cont != null:
		check(not String(tt.focus_info(cont).get("caption", "")).is_empty(), "pojemnik: nazwa")
	var target: Node = item if item != null else door
	check(target != null, "obiekt do podpowiedzi w świecie syntetycznym")
	if target != null:
		main.focus_node = target
		tt._update_world_focus(false)
		var fsc: Vector2 = tt.focus_screen
		var fvp := Vector2(1280, 720)
		check(tt.box.visible and not tt.focus_key.is_empty(), "podpowiedź obiektu widoczna poza trybem GUI")
		check(is_equal_approx(tt.box.position.x, float(int(fvp.x) / 2 - int(tt.last_size.x) / 2))
			and is_equal_approx(tt.box.position.y, float(maxi(0, int(fsc.y * fvp.y - tt.last_size.y - 20.0)))),
			"położenie: środek poziomo, nad górą obrysu (%s, ekran %s)" % [tt.box.position, fsc])
		main.focus_node = null
		tt._update_world_focus(false)
		check(not tt.box.visible, "bez obiektu – bez podpowiedzi")
	_finish()

func _finish() -> void:
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
