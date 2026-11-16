extends RefCounted
## Handel i usługi NPC (etap 7), jak OpenMW 0.51:
##   MechanicsManager::getBarterOffer (cena wg postawy, handlu, szczęścia, osobowości, zmęczenia obu stron),
##   TradeWindow (oferta z ograniczeniem 75% ceny bazowej, haggle – targowanie z rzutem, postawa po transakcji,
##   złoto kupca – pula odnawiana co fBarterGoldResetDelay godzin, postęp handlu), TradeItemModel (towar: inwentarz
##   kupca i pojemniki, których jest właścicielem, wg usług – NPC::Services, bez założonych rzeczy i złota),
##   SpellBuyingWindow (zaklęcia kupca typu „spell”, bez mocy rasy i znanych graczowi; cena calcSpellCost ×
##   fSpellValueMult), TrainingWindow (3 najlepsze umiejętności, cena umiejętność × iTrainingMod, warunki,
##   2 godziny), TravelWindow (cel z rekordu, cena odległość / fTravelMult albo fMagesGuildTravel we wnętrzu,
##   czas odległość / fTravelTimeMult), Service Refusal (filtr dialogu z odwróconą postawą).
## Stan: pula złota kupca i czas odnowy w state.dialogue.npcs[sid] ("gold_pool", "restock").

const SVC := {"weapon": 0x1, "armor": 0x2, "clothing": 0x4, "book": 0x8, "ingredient": 0x10, "lockpick": 0x20,
	"probe": 0x40, "light": 0x80, "apparatus": 0x100, "repair": 0x200, "misc": 0x400, "potion": 0x2000}
const SVC_SPELLS := 0x800
const SVC_MAGIC_ITEMS := 0x1000
const SVC_TRAINING := 0x4000
const SVC_SPELLMAKING := 0x8000
const SVC_ENCHANTING := 0x10000
const SVC_REPAIR := 0x20000
const ALL_ITEMS := 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80 | 0x100 | 0x200 | 0x400 | 0x2000
# typy usług dla „Service Refusal” (DialogueManager::ServiceType – wartość Choice w filtrze)
const REFUSAL := {"barter": 1, "repair": 2, "spells": 3, "training": 4, "travel": 5, "spellmaking": 6, "enchanting": 7}
const A_LUCK := 7
const A_PERSONALITY := 6
const SK_MERCANTILE := 24

var main
var records

func _init(game_main) -> void:
	main = game_main
	records = game_main.builder.actors

func _gmst(id: String, def) -> Variant:
	var g: Dictionary = records.record("gmst", id.to_lower())
	return g.get("value", def) if not g.is_empty() else def

func _dl():
	return main.dialogue

# --- usługi -----------------------------------------------------------------------------------------------

## Npc::getServices: NPC z flagą autoobliczania – usługi klasy, inaczej z AIDT; stworzenia – AIDT.
func services(a: Dictionary) -> int:
	if a.is_empty():
		return 0
	if a.npc and bool(a.rec.get("autocalc_flag", false)):
		return int(records.record("class", String(a.rec.get("class", ""))).get("services", 0))
	return int((a.rec.get("ai", {}) as Dictionary).get("services", 0))

func has_travel(a: Dictionary) -> bool:
	return not (a.rec.get("travel", []) as Array).is_empty()

## Pozycje usług w oknie rozmowy (kolejność jak DialogueWindow::updateTopicsPane; tylko wdrożone usługi).
func service_entries(a: Dictionary) -> Array:
	var s := services(a)
	var out := []
	if s & ALL_ITEMS:
		out.append(["barter", _dl().gmst_text("sBarter", "Handel")])
	if s & SVC_SPELLS:
		out.append(["spells", _dl().gmst_text("sSpells", "Zaklęcia")])
	if has_travel(a):
		out.append(["travel", _dl().gmst_text("sTravel", "Podróż")])
	if s & SVC_ENCHANTING:
		out.append(["enchanting", _dl().gmst_text("sEnchanting", "Zaklinanie")])
	if s & SVC_TRAINING:
		out.append(["training", _dl().gmst_text("sServiceTrainingTitle", "Trening")])
	return out

## checkServiceRefused: odpowiedź z „Service Refusal” (choice = usługa, postawa odwrócona) – wpis w historii.
func refused(service: String) -> bool:
	var dl = _dl()
	var a: Dictionary = dl.actor
	if a.is_empty():
		return false
	for choice in [-1, int(REFUSAL.get(service, 0))]:
		var saved: int = dl.choice
		dl.choice = choice
		var l: Array = dl.list_infos("service refusal", a, false, false, true)
		dl.choice = saved
		if not l.is_empty():
			var info: Dictionary = l[0][1]
			dl.add_topics_from_text(String(info.get("text", "")))
			dl.history.append({"kind": "response", "title": dl.gmst_text("sServiceRefusal", "Odmowa"),
				"text": dl.info_text("service refusal", info, a)})
			dl._run_result(info)
			return true
	return false

# --- ceny -------------------------------------------------------------------------------------------------

func _npc_stats(a: Dictionary) -> Dictionary:
	return main.script_host.npc_autocalc(a.rec) if a.npc else {"attributes": a.rec.get("attributes", []), "skills": []}

func _npc_terms(a: Dictionary) -> Array:
	var s := _npc_stats(a)
	var at: Array = s.get("attributes", [])
	var sk: Array = s.get("skills", [])
	var merc := float(sk[SK_MERCANTILE]) if sk.size() > SK_MERCANTILE else 0.0
	var luck := float(at[A_LUCK]) if at.size() > A_LUCK else 0.0
	var pers := float(at[A_PERSONALITY]) if at.size() > A_PERSONALITY else 0.0
	return [merc, luck, pers, float(_gmst("fFatigueBase", 1.25))]      # NPC z pełną kondycją (walka – osobno)

func _pc_terms() -> Array:
	var st: Dictionary = main.player_stats()
	var d: Dictionary = main.character.derived(st)
	return [float(d.skills[SK_MERCANTILE]), float(d.attributes[A_LUCK]), float(d.attributes[A_PERSONALITY]),
		main.character.fatigue_term(st, d)]

## getBarterOffer: cena dla gracza kupującego (buying) albo sprzedającego.
func barter_offer(a: Dictionary, base_price: int, buying: bool) -> int:
	if base_price == 0 or not a.npc:
		return base_price
	var disp: int = _dl().derived_disposition(a)
	var p := _pc_terms()
	var n := _npc_terms(a)
	var pa := minf(float(p[0]), 100.0)
	var pb := minf(0.1 * float(p[1]), 10.0)
	var pc := minf(0.2 * float(p[2]), 10.0)
	var nd := minf(float(n[0]), 100.0)
	var ne := minf(0.1 * float(n[1]), 10.0)
	var nf := minf(0.2 * float(n[2]), 10.0)
	var pc_term := (disp - 50 + pa + pb + pc) * float(p[3])
	var npc_term := (nd + ne + nf) * float(n[3])
	var buy_term := 0.01 * (100.0 - 0.5 * (pc_term - npc_term))
	var sell_term := 0.01 * (50.0 - 0.5 * (npc_term - pc_term))
	return maxi(1, int(base_price * (buy_term if buying else sell_term)))

## Wartość przedmiotu (getEffectiveValue; stan przedmiotów – pełny, zużycie w walce osobno).
func item_value(id: String) -> int:
	var it: Dictionary = main.interaction.inventory.item(id)
	return int((it.get("rec", {}) as Dictionary).get("value", 0))

func item_kind(id: String) -> String:
	return String(main.interaction.inventory.item(id).get("kind", ""))

## canSell (klasy przedmiotów): usługa typu albo przedmiot zaklęty u kupca „magic items”; klucze i złoto nie.
func can_sell(id: String, svc: int) -> bool:
	var k := item_kind(id)
	if k.is_empty() or id.begins_with("gold_"):
		return false
	var rec: Dictionary = records.record(k, id)
	if k == "misc" and bool(rec.get("key", false)):
		return false
	if svc & int(SVC.get(k, 0)):
		return true
	if k in ["weapon", "armor", "clothing", "book"] and (svc & SVC_MAGIC_ITEMS) and not String(rec.get("enchant", "")).is_empty():
		return true
	return false

# --- złoto kupca --------------------------------------------------------------------------------------------

func _now_hours() -> float:
	return float(main.envr.day) * 24.0 + float(main.envr.game_hour) if main.envr != null else 0.0

## DialogueWindow::restock: pula złota = złoto z rekordu co fBarterGoldResetDelay godzin.
func restock(a: Dictionary) -> void:
	var n: Dictionary = _dl()._npc_state(a)
	var delay := float(_gmst("fBarterGoldResetDelay", 24.0))
	if not n.has("restock") or _now_hours() >= float(n.restock) + delay:
		n["gold_pool"] = int(a.rec.get("gold", 0))
		n["restock"] = _now_hours()

func merchant_gold(a: Dictionary) -> int:
	return int(_dl()._ds().npcs.get(a.sid, {}).get("gold_pool", a.rec.get("gold", 0)))

func set_merchant_gold(a: Dictionary, v: int) -> void:
	_dl()._npc_state(a)["gold_pool"] = v

func player_gold() -> int:
	return int(main.interaction.inventory.count_of("player", {}, "gold_001"))

# --- towar ------------------------------------------------------------------------------------------------

## Źródła towaru: kupiec, potem pojemniki we wczytanych komórkach, których jest właścicielem.
func sources(a: Dictionary) -> Array:
	var out := [{"sid": a.sid, "rec": a.rec, "merchant": true}]
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for nd in refs.get_children():
			var ex: Dictionary = nd.get_meta("mw_extra", {}) if nd.has_meta("mw_extra") else main.interaction.extra_of(nd)
			if String(ex.get("owner", "")).to_lower() != a.base:
				continue
			var b := String(nd.get_meta("mw_base", "")).to_lower()
			if String(main.db.get_object(b).get("type", "")) != "CONT":
				continue
			out.append({"sid": String(nd.get_meta("mw_sid", "")), "rec": main.interaction.container_record(b), "merchant": false})
	return out

## Towar kupca: [{id, count}] – suma źródeł, bez złota, przedmiotów spoza usług i założonych przez kupca.
func merchant_items(a: Dictionary) -> Array:
	var svc := services(a)
	var inv = main.interaction.inventory
	var equipped := {}
	if a.npc:
		var own: Array = inv.contents(a.sid, a.rec)
		var eq = main.builder.actors
		if eq.equipment == null:
			eq.equipment = eq.Equipment.new(eq)
		var slots: Dictionary = eq.equipment.auto_equip(a.rec, own)
		for slot in slots:
			var e: Dictionary = slots[slot]
			equipped[String(e.id)] = int(equipped.get(String(e.id), 0)) + 1
	var total := {}
	var order := []
	for src in sources(a):
		for it in inv.contents(String(src.sid), src.rec):
			var id := String(it.id).to_lower()
			var c := int(it.count)
			if src.merchant and equipped.has(id):
				c -= int(equipped[id])
			if c <= 0 or not can_sell(id, svc):
				continue
			if not total.has(id):
				order.append(id)
			total[id] = int(total.get(id, 0)) + c
	return order.map(func(id): return {"id": id, "count": int(total[id])})

## Przedmioty gracza do sprzedania temu kupcowi.
func player_items(a: Dictionary) -> Array:
	var svc := services(a)
	var out := []
	for it in main.interaction.inventory.contents("player", {}):
		var id := String(it.id).to_lower()
		if can_sell(id, svc):
			out.append({"id": id, "count": int(it.count)})
	return out

## TradeWindow::updateOffer: oferta kupca (ujemna – gracz płaci).
func merchant_offer(a: Dictionary, buy: Dictionary, sell: Dictionary) -> int:
	var offer := 0
	for id in buy:
		var base := item_value(id) * int(buy[id])
		var cap := int(maxf(1.0, 0.75 * base))
		offer -= maxi(cap, barter_offer(a, base, true))
	for id in sell:
		var base2 := item_value(id) * int(sell[id])
		var cap2 := int(maxf(1.0, 0.75 * base2))
		var price := barter_offer(a, base2, false)
		offer += mini(cap2, price) if a.npc else price
	return offer

## haggle: oferta gracza (saldo) wobec oferty kupca; roll 1..100 (test: stały). → {ok, skill_gain}
func haggle(a: Dictionary, player_offer: int, merch_offer: int, roll := -1) -> Dictionary:
	if player_offer <= merch_offer:
		return {"ok": true, "gain": 0.0}
	if not a.npc:
		return {"ok": false}
	var buying := merch_offer < 0
	var x1 := absi(merch_offer)
	var x2 := absi(player_offer)
	var d := int(100 * (x1 - x2) / x1) if buying else int(100 * (x2 - x1) / x2)
	var disp: int = _dl().derived_disposition(a)
	var p := _pc_terms()
	var n := _npc_terms(a)
	var disp_term := float(_gmst("fDispositionMod", 1.0)) * (disp - 50)
	var pc_term := (disp_term + float(p[0]) + 0.1 * float(p[1]) + 0.2 * float(p[2])) * float(p[3])
	var npc_term := (float(n[0]) + 0.1 * float(n[1]) + 0.2 * float(n[2])) * float(n[3])
	var x := float(_gmst("fBargainOfferMulti", -4.0)) * d + float(_gmst("fBargainOfferBase", 50.0)) + int(pc_term - npc_term)
	var r := roll if roll >= 0 else randi() % 100 + 1
	if r > x or (merch_offer < 0 and 0 < player_offer):
		return {"ok": false}
	var gain := 0.0
	var final := absi(player_offer)
	var initial := absi(merch_offer)
	if not buying and final > initial:
		gain = floorf(100.0 * (final - initial) / final)
	elif buying and final < initial:
		gain = floorf(100.0 * (initial - final) / initial)
	return {"ok": true, "gain": gain}

## Transakcja (onOfferButtonClicked): sprawdzenia złota, targowanie, postawa, przeniesienie towaru i złota.
## balance – oferta gracza (dodatnia: kupiec płaci). → {ok, message}
func offer(a: Dictionary, buy: Dictionary, sell: Dictionary, balance: int, roll := -1) -> Dictionary:
	if buy.is_empty() and sell.is_empty():
		return {"ok": false, "message": _dl().gmst_text("sBarterDialog11", "Nic nie wybrano.")}
	if balance < 0 and player_gold() < -balance:
		return {"ok": false, "message": _dl().gmst_text("sBarterDialog1", "Nie masz dość złota.")}
	if balance > 0 and merchant_gold(a) < balance:
		return {"ok": false, "message": _dl().gmst_text("sBarterDialog2", "Kupiec nie ma dość złota.")}
	var mo := merchant_offer(a, buy, sell)
	var h := haggle(a, balance, mo, roll)
	if a.npc:
		var delta := int(_gmst("iBarterSuccessDisposition", 1)) if bool(h.ok) else int(_gmst("iBarterFailDisposition", -1))
		var dl = _dl()
		dl._update_original_disposition()
		dl.current_disp += delta
		dl.set_base_disposition(a, dl.current_disp)
	if not bool(h.ok):
		return {"ok": false, "message": _dl().gmst_text("sNotifyMessage9", "Kupiec odrzucił ofertę.")}
	var inv = main.interaction.inventory
	for id in buy:
		var left := int(buy[id])
		for src in sources(a):
			if left <= 0:
				break
			left -= int(inv.transfer(String(src.sid), src.rec, "player", {}, id, left))
	for id in sell:
		inv.transfer("player", {}, a.sid, a.rec, id, int(sell[id]))
	if balance > 0:
		inv.add("player", {}, "gold_001", balance)
	elif balance < 0:
		inv.remove("player", {}, "gold_001", -balance)
	set_merchant_gold(a, merchant_gold(a) - balance)
	main.skill_used(SK_MERCANTILE, "mercantile_success", float(h.get("gain", 0.0)))
	if main.audio != null:
		main.audio.play("Item Gold Up")
	return {"ok": true, "message": ""}

# --- zaklęcia, trening, podróż ------------------------------------------------------------------------------

## Zaklęcia na sprzedaż: [{id, name, price}] (posortowane wg nazwy).
func spells_for_sale(a: Dictionary) -> Array:
	var st: Dictionary = main.player_stats()
	var known: Array = st.get("spells", [])
	var race: Dictionary = records.record("race", String(a.rec.get("race", "")))
	var powers: Array = (race.get("powers", []) as Array).map(func(x): return String(x).to_lower())
	var out := []
	for sid in a.rec.get("spells", []):
		var k := String(sid).to_lower()
		var sp: Dictionary = records.record("spell", k)
		if sp.is_empty() or int(sp.get("spell_type", -1)) != 0 or k in powers or k in known:
			continue
		var price := maxi(1, int(main.magic.spell_cost(sp) * float(_gmst("fSpellValueMult", 10.0))))
		out.append({"id": k, "name": String(sp.get("name", k)), "price": barter_offer(a, price, true)})
	out.sort_custom(func(x, y): return String(x.name).to_lower() < String(y.name).to_lower())
	return out

func buy_spell(a: Dictionary, id: String) -> bool:
	for s in spells_for_sale(a):
		if s.id == id and player_gold() >= int(s.price):
			main.interaction.inventory.remove("player", {}, "gold_001", int(s.price))
			set_merchant_gold(a, merchant_gold(a) + int(s.price))
			(main.player_stats()["spells"] as Array).append(id)
			if main.audio != null:
				main.audio.play("Item Gold Up")
			return true
	return false

## Trening: 3 najlepsze umiejętności trenera (kolejność rekordów SKIL przy remisie). [{skill, value, price}]
func training_offers(a: Dictionary) -> Array:
	var sk: Array = _npc_stats(a).get("skills", [])
	var best := []
	for i in sk.size():
		best.append([i, float(sk[i])])
	best.sort_custom(func(x, y): return x[1] > y[1] or (x[1] == y[1] and x[0] < y[0]))
	var st: Dictionary = main.player_stats()
	var out := []
	for e in best.slice(0, 3):
		var base := maxi(1, int(float(st.skills[int(e[0])]) * int(_gmst("iTrainingMod", 10))))
		out.append({"skill": int(e[0]), "value": float(e[1]), "price": barter_offer(a, base, true)})
	return out

## onTrainingSelected: → {ok, message}
func train(a: Dictionary, skill: int) -> Dictionary:
	var st: Dictionary = main.player_stats()
	for o in training_offers(a):
		if int(o.skill) != skill:
			continue
		if int(o.price) > player_gold():
			return {"ok": false, "message": ""}
		if float(o.value) <= float(st.skills[skill]):
			return {"ok": false, "message": _dl().gmst_text("sServiceTrainingWords", "Nie mogę cię już niczego nauczyć.")}
		var srec: Dictionary = records.record("skill", String(main.character.skill_names()[skill]))
		var attr := int(srec.get("attribute", -1))
		if attr >= 0 and float(st.skills[skill]) >= float(main.character.derived(st).attributes[attr]):
			return {"ok": false, "message": _dl().gmst_text("sNotifyMessage17", "Atrybut nadrzędny jest za niski.")}
		for m in main.character.skill_level_up(st, skill, "trainer"):
			main._skill_message(m)
		main.interaction.inventory.remove("player", {}, "gold_001", int(o.price))
		set_merchant_gold(a, merchant_gold(a) + int(o.price))
		for h in 2:
			main.character.rest_hour(st, false)
			main.envr.advance(1.0)
		return {"ok": true, "message": ""}
	return {"ok": false, "message": ""}

## Cele podróży: [{index, name, cell, pos, rot, price, hours}].
func travel_offers(a: Dictionary) -> Array:
	var out := []
	var pmw: Vector3 = MWCoords.godot_to_mw(main.player.global_position)
	var interior: bool = not main.interior.is_empty()
	var i := 0
	for t in a.rec.get("travel", []):
		var p: Array = t.get("pos", [0, 0, 0])
		var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var price: int
		var hours := 0
		if interior:
			price = int(_gmst("fMagesGuildTravel", 30))
		else:
			var d := pos.distance_to(pmw)
			var m := float(_gmst("fTravelMult", 4000.0))
			price = int(d / m) if m != 0.0 else int(d)
			hours = int(Vector2(pos.x - pmw.x, pos.y - pmw.y).length() / float(_gmst("fTravelTimeMult", 16000.0)))
		price = barter_offer(a, maxi(1, price), true)
		var cell := String(t.get("cell", ""))
		var name := cell
		if cell.is_empty():
			var c: Dictionary = main.db.get_cell(main.db.exterior_key(MWCoords.cell_of(MWCoords.mw_to_godot(pos))))
			name = String(c.get("name", "")) if not String(c.get("name", "")).is_empty() else String(c.get("region", ""))
		out.append({"index": i, "name": name, "cell": cell, "pos": pos, "rot": t.get("rot", [0, 0, 0]), "price": price, "hours": hours})
		i += 1
	return out

func travel(a: Dictionary, index: int) -> bool:
	for o in travel_offers(a):
		if int(o.index) != index or int(o.price) > player_gold():
			continue
		main.interaction.inventory.remove("player", {}, "gold_001", int(o.price))
		set_merchant_gold(a, merchant_gold(a) + int(o.price))
		var st: Dictionary = main.player_stats()
		for h in int(o.hours):
			main.character.rest_hour(st, true)
			main.envr.advance(1.0)
		if not main.interior.is_empty() and main.audio != null:
			main.audio.play("mysticism cast")
		var rot: Array = o.rot
		main.travel_to_cell(String(o.cell), o.pos, rad_to_deg(float(rot[2])) if rot.size() > 2 else 0.0)
		return true
	return false
