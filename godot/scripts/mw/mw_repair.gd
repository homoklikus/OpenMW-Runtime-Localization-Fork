extends RefCounted
## Naprawa przedmiotów jak OpenMW 0.51:
##   gracz z narzędziem – MWMechanics::Repair::repair (apps/openmw/mwmechanics/repair.cpp), okno MWGui::Repair;
##   usługa NPC – MWGui::MerchantRepair (apps/openmw/mwgui/merchantrepair.cpp).
## Stan egzemplarza: stos „id#c:N” w ekwipunku (mw_inventory.gd, CellRef::charge OpenMW).

const SK_ARMORER := 1
const ATTR_STRENGTH := 0
const ATTR_LUCK := 7

var main
var test_roll := -1                  # testy: stały wynik roll0to99

func _init(m) -> void:
	main = m

func _inv():
	return main.interaction.inventory

func _gmst(id: String, def) -> Variant:
	var g: Dictionary = main.builder.actors.record("gmst", id.to_lower())
	return g.get("value", def) if not g.is_empty() else def

func _text(id: String, fb: String) -> String:
	return main.dialogue.gmst_text(id, fb)

func _roll() -> int:
	return test_roll if test_roll >= 0 else randi() % 100

func _name(id: String) -> String:
	var it: Dictionary = _inv().item(id)
	return main.interaction.item_name(String(it.kind), id, it.rec) if not it.is_empty() else id

## SortFilterItemModel::Filter_OnlyRepairable: broń i pancerz gracza ze stanem niższym niż największy;
## ItemChargeView – kolejność wg nazwy (bez rozróżniania wielkości liter).
func repairable() -> Array:
	var out := []
	for e in _inv().contents("player", {}):
		if int(e.count) <= 0:
			continue
		var id := String(e.id)
		var it: Dictionary = _inv().item(id)
		if it.is_empty() or not String(it.kind) in ["weapon", "armor"]:
			continue
		var mx: float = _inv().max_charge(it.rec)
		var cur: float = _inv().item_charge(id)
		if mx <= 0.0 or cur >= mx:
			continue
		out.append({"id": id, "name": _name(id), "charge": cur, "max": mx})
	out.sort_custom(func(a, b): return String(a.name).to_lower() < String(b.name).to_lower())
	return out

## Filter_OnlyRepairTools: narzędzia naprawcze gracza (stosy).
func tools() -> Array:
	var out := []
	for e in _inv().contents("player", {}):
		if int(e.count) > 0 and String(_inv().item(String(e.id)).get("kind", "")) == "repair":
			out.append(String(e.id))
	return out

## Repair::repair: narzędzie traci jedno użycie (osobny egzemplarz), szansa x = (0,1 Siła + 0,1 Szczęście +
## Płatnerstwo) × fatigueTerm; przy roll0to99 ≤ x naprawa o max(1, int(fRepairAmountMult × jakość × roll)),
## OnPCRepair, rozwój Płatnerstwa, dźwięk „Repair” i sRepairSuccess; inaczej „Repair Fail” i sRepairFailed.
## Zużyte narzędzie znika (sNotifyMessage51) i zastępuje je następne o tym samym rekordzie („Item Repair Up”).
## → {"ok", "tool": identyfikator narzędzia po użyciu albo "", "item": identyfikator przedmiotu, "messages", "sounds"}
func repair(tool_id: String, item_id: String, roll := -1) -> Dictionary:
	var inv = _inv()
	var res := {"ok": false, "tool": tool_id, "item": item_id, "messages": [], "sounds": []}
	var tool: Dictionary = inv.item(tool_id)
	var target: Dictionary = inv.item(item_id)
	if tool.is_empty() or target.is_empty() or inv.count_of("player", {}, tool_id) <= 0 \
			or inv.count_of("player", {}, item_id) <= 0:
		return res
	if main.has_method("break_invisibility"):
		main.break_invisibility()
	# unstack + setCharge(uses − 1)
	var uses := maxf(0.0, inv.item_charge(tool_id) - 1.0)
	var new_tool: String = inv.charged_id(tool_id, uses, inv.max_charge(tool.rec)) if uses > 0.0 else "%s#c:0" % inv.base_id(tool_id)
	inv.remove("player", {}, tool_id, 1)
	inv.add("player", {}, new_tool, 1)
	res.tool = new_tool
	var me: Dictionary = main.combat.player_fighter()
	var at: Array = main.combat.attributes(me)
	var x := (0.1 * float(at[ATTR_STRENGTH]) + 0.1 * float(at[ATTR_LUCK]) + float(main.combat.skill(me, SK_ARMORER))) \
			* float(main.combat.fatigue_term(me))
	var r := roll if roll >= 0 else _roll()
	if float(r) <= x:
		var y := maxi(1, int(float(_gmst("fRepairAmountMult", 3.0)) * float(tool.rec.get("quality", 1.0)) * r))
		var mx: float = inv.max_charge(target.rec)
		var charge := minf(inv.item_charge(item_id) + y, mx)
		var new_item: String = inv.charged_id(item_id, charge, mx)
		if new_item != item_id:
			_replace_stack(item_id, new_item)
		res.item = new_item
		if main.get("scripts") != null and main.scripts != null:
			main.scripts.item_repaired(new_item)
		main.skill_used(SK_ARMORER, "armorer_repair")
		res.ok = true
		res.sounds.append("Repair")
		res.messages.append(_text("sRepairSuccess", "You have successfully repaired the item."))
	else:
		res.sounds.append("Repair Fail")
		res.messages.append(_text("sRepairFailed", "You failed to repair the item."))
	if uses <= 0.0:
		inv.remove("player", {}, new_tool, 1)
		res.messages.append(_text("sNotifyMessage51", "Your %s has been used up.").replace("%s", _name(tool_id)))
		res.tool = ""
		var base: String = inv.base_id(tool_id)
		for e in inv.contents("player", {}):
			if int(e.count) > 0 and inv.base_id(String(e.id)) == base:
				res.tool = String(e.id)
				res.sounds.append("Item Repair Up")
				break
	return res

## Egzemplarz zmienia stan: jedna sztuka ze stosu old_id do stosu new_id (także w założonym miejscu).
func _replace_stack(old_id: String, new_id: String) -> void:
	var inv = _inv()
	# najpierw miejsce ekwipunku (sprawdzenie założonych rzeczy po zmianie inwentarza nie może go zdjąć)
	var eq: Dictionary = main._equipment()
	for k in eq:
		if String(eq[k].id) == old_id:
			eq[k]["id"] = new_id
			break
	inv.add("player", {}, new_id, 1)
	inv.remove("player", {}, old_id, 1)

# --- usługa NPC ----------------------------------------------------------------------------------------------

## MerchantRepair::setPtr: broń i pancerz gracza ze stanem niższym niż największy; cena: p = max(1, wartość),
## r = max(1, int(największy / p)), x = max(1, int(fRepairMult × int((największy − bieżący) / r))),
## getBarterOffer(kupiec, x, kupno); pozycja „nazwa  - cena” + sgp; kolejność wg tekstu.
func merchant_offers(a: Dictionary) -> Array:
	var inv = _inv()
	var gp := _text("sgp", "gp")
	var gold: int = main.trade.player_gold()
	var out := []
	for e in inv.contents("player", {}):
		if int(e.count) <= 0:
			continue
		var id := String(e.id)
		var it: Dictionary = inv.item(id)
		if it.is_empty() or not String(it.kind) in ["weapon", "armor"]:
			continue
		var mx: float = inv.max_charge(it.rec)
		var cur: float = inv.item_charge(id)
		if mx <= 0.0 or cur >= mx:
			continue
		var p := float(maxi(1, int(it.rec.get("value", 0))))
		var r := float(maxi(1, int(mx / p)))
		var x := int((mx - cur) / r)
		x = maxi(1, int(float(_gmst("fRepairMult", 1.0)) * x))
		var price: int = main.trade.barter_offer(a, x, true)
		var text := "%s  - %d%s" % [_name(id), price, gp]
		out.append({"id": id, "text": text, "price": price, "ok": price <= gold})
	out.sort_custom(func(l, rr): return String(l.text).to_lower() < String(rr.text).to_lower())
	return out

## MerchantRepair::onRepairButtonClick: pełny stan, dźwięk „Repair”, złoto gracza do puli kupca.
func merchant_repair(a: Dictionary, item_id: String) -> bool:
	var inv = _inv()
	var offer := {}
	for o in merchant_offers(a):
		if String(o.id) == item_id:
			offer = o
	if offer.is_empty() or int(offer.price) > main.trade.player_gold():
		return false
	_replace_stack(item_id, inv.base_id(item_id))
	inv.remove("player", {}, "gold_001", int(offer.price))
	main.trade.set_merchant_gold(a, main.trade.merchant_gold(a) + int(offer.price))
	if main.get("audio") != null and main.audio != null:
		main.audio.play("Repair")
	return true
