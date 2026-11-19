extends RefCounted
## Przestępstwa, świadkowie i strażnicy (etap 8) – OpenMW 0.51 MechanicsManager: isOwned/isAllowedToUse,
## itemTaken (kradzież, rejestr skradzionych), unlockAttempted (wtargnięcie), commitCrime (świadkowie w
## fAlarmRadius: linia wzroku + awarenessCheck; ofiara świadoma; morderstwo widzą wszyscy), reportCrime (grzywny
## iCrimeAttack/iCrimeKilling/iCrimeTresspass/iCrimePickPocket/fCrimeStealing × wartość, zgłasza świadek z Alarm ≥
## 100, strażnik z Alarm ≥ 100 – pościg, pozostali – walka wg Fight i iFightAttacking/iFightKilling…, wydalenie
## z frakcji ofiary), actorAttacked/actorKilled (canCommitCrimeAgainst), Actors::updateCrimePursuit (strażnik widzi
## gracza z grzywną ≥ iCrimeThreshold: pościg, ≥ × iCrimeThresholdMultiplier – atak), PayFine, GoToJail
## (iDaysinPrisonMod, odsiadka – jailTimeServed, znacznik więzienia), Security (wytrychy i sondy).
##
## Stan: postać gracza "bounty", "stolen" {przedmiot: {właściciel: liczba}}; aktorzy: "alarmed", "crime_id".

const ASSAULT := "assault"
const MURDER := "murder"
const THEFT := "theft"
const TRESPASS := "trespass"
const PICKPOCKET := "pickpocket"

var main
var rng := RandomNumberGenerator.new()
var test_roll := -1
var _timer := 0.0
var markers = null

func _init(game_main) -> void:
	main = game_main

func _gmst(id: String, def) -> Variant:
	var g: Dictionary = main.builder.actors.record("gmst", id.to_lower())
	return g.get("value", def) if not g.is_empty() else def

func _roll() -> int:
	return test_roll if test_roll >= 0 else rng.randi() % 100

func st() -> Dictionary:
	return main.player_stats()

func bounty() -> int:
	return int(st().get("bounty", 0))

func set_bounty(v: int) -> void:
	st()["bounty"] = maxi(0, v)
	if v <= 0:
		record_crime_id()

## Identyfikatory przestępstw (Player::getNewCrimeId / recordCrimeId / getCrimeId): świadkowie i ofiary dostają
## identyfikator zgłoszenia; po spłacie grzywny (grzywna 0) uspokajają się (Actors::updateCrimePursuit).
func new_crime_id() -> int:
	st()["crime_id_current"] = int(st().get("crime_id_current", -1)) + 1
	return int(st().crime_id_current)

func record_crime_id() -> void:
	st()["crime_id_paid"] = int(st().get("crime_id_current", -1))

## Świadek ze spłaconym przestępstwem: koniec pościgu (strażnik) i walki, GetAttacked/alarm 0, Fight z rekordu.
func calm_witnesses() -> void:
	var paid := int(st().get("crime_id_paid", -1))
	for n in main.ai.actor_nodes():
		var a: Dictionary = main.combat._actor_state(main.combat.fighter_of(n)) if main.state.actors.has(String(n.get_meta("mw_sid", ""))) else {}
		if a.is_empty() or not a.has("crime_id") or int(a.crime_id) > paid:
			continue
		if _is_guard(n):
			var ast: Dictionary = main.ai.ai_state(n)
			ast.packages = (ast.packages as Array).filter(func(x): return String(x.get("type", "")) != "pursue")
		main.ai.stop_combat(n)
		a.erase("attacked")
		a.erase("alarmed")
		a.erase("crime_id")
		a.erase("crime_disp")                    # setCrimeDispositionModifier(0)
		var act: Dictionary = main.dialogue.make_actor(n)
		main.dialogue.set_ai_setting(act, "fight", int((act.rec.get("ai", {}) as Dictionary).get("fight", 0)))

# --- własność ------------------------------------------------------------------------------------------------

func _npc_node(base: String) -> Node3D:
	for n in main.ai.actor_nodes():
		if String(n.get_meta("mw_base", "")).to_lower() == base.to_lower():
			return n
	return null

## isOwned: właściciel (NPC ≠ gracz, żywy) albo frakcja (gracz poniżej wymaganej rangi); zmienna globalna = 1
## zwalnia. → {"owned": bool, "victim": węzeł NPC albo null, "owner", "faction"}
func ownership(extra: Dictionary) -> Dictionary:
	var owner := String(extra.get("owner", "")).to_lower()
	var faction := String(extra.get("faction", "")).to_lower()
	var out := {"owned": false, "victim": null, "owner": owner, "faction": faction}
	if owner == "player" or (owner.is_empty() and faction.is_empty()):
		return out
	var gv := String(extra.get("global", "")).to_lower()
	if not gv.is_empty() and int(main.state.globals.get(gv, 0)) == 1:
		return out
	if owner.is_empty():
		var fr: Dictionary = (st().get("factions", {}) as Dictionary).get(faction, {})
		if not fr.is_empty() and not bool(fr.get("expelled", false)) and int(fr.get("rank", -1)) >= int(extra.get("faction_rank", 0)):
			return out
	else:
		var v := _npc_node(owner)
		if v != null and main.combat.is_dead(main.combat.fighter_of(v)):
			return out
		out.victim = v
	out.owned = true
	return out

## itemTaken: przedmiot podniesiony ze świata albo wyjęty z pojemnika (extra – własność referencji/pojemnika).
func item_taken(extra: Dictionary, item: String, count: int) -> bool:
	var o := ownership(extra)
	if not bool(o.owned):
		return false
	var gold := item.begins_with("gold_")
	if not gold:
		if not st().get("stolen") is Dictionary:
			st()["stolen"] = {}
		var key := String(o.owner) if not String(o.owner).is_empty() else "faction:" + String(o.faction)
		var m: Dictionary = st().stolen.get(item, {})
		m[key] = int(m.get(key, 0)) + count
		st().stolen[item] = m
	var value := count if gold else count * int(main.trade.item_value(item))
	commit(o.victim, THEFT, String(o.faction), value)
	return true

## Wyjęcie z pojemnika (ContainerWindow → itemTaken z pojemnikiem): własność pojemnika; ciało martwego NPC – wolno.
func container_taken(sid: String, item: String, count: int) -> void:
	var r: Dictionary = main.base_ref(sid) if main.has_method("base_ref") else {}
	if r.is_empty():
		return
	var base: Dictionary = main.db.get_object(String(r.get("base", "")))
	if String(base.get("type", "")) in ["NPC_", "CREA"]:
		return                                 # ciało (kradzież kieszonkowa – później)
	item_taken(r.get("extra", {}), item, count)

## unlockAttempted: próba otwarcia cudzego zamka/pułapki (wytrych, sonda, czar Otwarcia).
func unlock_attempted(extra: Dictionary, locked: bool) -> void:
	var o := ownership(extra)
	if bool(o.owned) and locked:
		commit(o.victim, TRESPASS, String(o.faction), 0)

# --- zgłoszenia ----------------------------------------------------------------------------------------------

func _is_guard(n: Node) -> bool:
	var rec: Dictionary = main.builder.actors.record("npc", String(n.get_meta("mw_base", "")))
	return String(rec.get("class", "")).to_lower() == "guard"

func _alarm(n: Node) -> int:
	return int(main.dialogue.ai_setting(main.dialogue.make_actor(n), "alarm"))

func _fight(n: Node) -> int:
	return int(main.dialogue.ai_setting(main.dialogue.make_actor(n), "fight"))

## canReportCrime: żywy NPC, nie walczy z ofiarą, nie jest powalony.
func _can_report(n: Node, victim) -> bool:
	if String(n.get_meta("mw_actor", "")) != "npc":
		return false
	var f: Dictionary = main.combat.fighter_of(n)
	if f.is_empty() or main.combat.is_dead(f) or bool(main.combat._actor_state(f).get("knocked_down", false)):
		return false
	if victim != null and main.ai.in_combat(n) and String(main.ai.current_package(n).get("target", "")) == String((victim as Node).get_meta("mw_sid", "")):
		return false
	return true

func _neighbours(victim) -> Array:
	var r := float(_gmst("fAlarmRadius", 2000.0))
	var pp: Vector3 = main.ai.mw_pos(main.player)
	var out := []
	for n in main.ai.actor_nodes():
		if main.ai.mw_pos(n).distance_to(pp) <= r:
			out.append(n)
	if victim != null and not victim in out:
		out.append(victim)
	return out

## commitCrime → zgłoszone (ktoś widział). arg – wartość (kradzież) albo grzywna (inne).
func commit(victim, type: String, faction := "", arg := 0, victim_aware := false) -> bool:
	if type == ASSAULT:
		victim_aware = true
	var seen := false
	for n in _neighbours(victim):
		if not _can_report(n, victim):
			continue
		if (n == victim and victim_aware) or (type == MURDER and n != victim) \
				or (main.ai._los(main.player, n) and main.ai.awareness(main.player, n, test_roll)):
			if type in [THEFT, PICKPOCKET] and main.dialogue != null:
				main.dialogue.say_voice(n, "thief")     # narzeka na kradzież, nawet jeśli nic nie zrobi
			seen = true
	if seen:
		report(victim, type, faction, arg)
	elif type == ASSAULT and victim != null:
		if _is_guard(victim) and not _in_pursuit(victim):
			if not report(victim, type, "", arg):
				main.ai.start_combat(victim, main.player)
		else:
			main.ai.start_combat(victim, main.player)
	return seen

func _in_pursuit(n: Node) -> bool:
	for p in main.ai.ai_state(n).packages:
		if String(p.get("type", "")) == "pursue":
			return true
	return false

## reportCrime: grzywna, reakcje świadków (strażnik – pościg, inni – walka wg Fight), wydalenie z frakcji.
func report(victim, type: String, faction := "", arg := 0) -> bool:
	var b := arg
	var id := new_crime_id()
	if type == MURDER and victim != null:
		main.combat._actor_state(main.combat.fighter_of(victim))["murdered"] = true     # notifyMurder (OnMurder)
	var fight := 0
	var fight_victim := 0
	var disp := 0.0
	var disp_victim := 0.0
	match type:
		TRESPASS:
			b = int(_gmst("iCrimeTresspass", 5))
			fight = int(_gmst("iFightTrespass", 30))
			fight_victim = fight
			disp = float(_gmst("iDispTresspass", -20))
			disp_victim = disp
		PICKPOCKET:
			b = int(_gmst("iCrimePickPocket", 25))
			fight = int(_gmst("iFightPickpocket", 20))
			fight_victim = fight * 4
			disp = float(_gmst("fDispPickPocketMod", -25))
			disp_victim = disp
		ASSAULT:
			b = int(_gmst("iCrimeAttack", 40))
			fight = int(_gmst("iFightAttacking", 50))
			fight_victim = int(_gmst("iFightAttack", 100))
			disp = float(_gmst("iDispAttackMod", -20))
			disp_victim = float(_gmst("fDispAttacking", -10))
		MURDER:
			b = int(_gmst("iCrimeKilling", 1000))
			fight = int(_gmst("iFightKilling", 50))
			fight_victim = fight
			disp = float(_gmst("iDispKilling", -50))
			disp_victim = disp
		THEFT:
			b = maxi(1, int(arg * float(_gmst("fCrimeStealing", 0.5))))
			fight = int(float(_gmst("fFightStealing", 50)) * arg)
			fight_victim = fight
			disp = float(_gmst("fDispStealing", -0.5)) * arg
			disp_victim = disp
	var neighbours := _neighbours(victim)
	var reported := false
	for n in neighbours:
		if _can_report(n, victim) and _alarm(n) >= 100:
			reported = true
			if type == TRESPASS and main.dialogue != null:
				main.dialogue.say_voice(n, "intruder")
	for n in neighbours:
		if not _can_report(n, victim):
			continue
		var alarm := _alarm(n)
		var a: Dictionary = main.combat._actor_state(main.combat.fighter_of(n))
		var alarm_term := 0.01 * alarm
		var is_victim: bool = n == victim
		# reportCrime: zmiana postawy świadka/ofiary (trwała – podstawa; inaczej modyfikator przestępstwa do spłaty)
		var disp_term := disp_victim if is_victim else disp
		var guard := _is_guard(n)
		var dmod := 0
		var permanent := false
		var only_hostile := false
		match type:
			THEFT:
				dmod = int(disp_term * alarm_term)
			PICKPOCKET:
				if alarm >= 100 and guard:
					dmod = int(disp_term)
				elif is_victim and guard:
					permanent = true
					dmod = int(disp_term * alarm_term)
				elif is_victim:
					permanent = true
					dmod = int(disp_term)
			ASSAULT:
				if is_victim and not guard:
					permanent = true
					dmod = int(disp_term)
				elif alarm >= 100:
					dmod = int(disp_term)
				elif is_victim and guard:
					permanent = true
					dmod = int(disp_term * alarm_term)
				else:
					only_hostile = true
					dmod = int(disp_term * alarm_term)
		var da: Dictionary = main.dialogue.make_actor(n) if main.dialogue != null else {}
		if dmod != 0 and not only_hostile and not da.is_empty():
			var cur := int(main.dialogue.derived_disposition(da))
			dmod = clampi(dmod, -cur, 100 - cur)
			if permanent:
				main.dialogue.set_base_disposition(da, main.dialogue.base_disposition(da) + dmod)
			else:
				a["crime_disp"] = int(a.get("crime_disp", 0)) + dmod
			a["crime_id"] = id
		if guard and alarm >= 100:
			a["alarmed"] = true
			a["crime_id"] = id
			if not _in_pursuit(n) and not main.ai.in_combat(n):
				main.ai.stack(n, {"type": "pursue", "target": "player", "priority": 2}, false)
			continue
		if type == PICKPOCKET:
			alarm_term = (1.0 if alarm_term == 0.0 else alarm_term) if is_victim else 0.0
		var ft := float(fight_victim if is_victim else fight)
		var d: float = main.ai.mw_pos(n).distance_to(main.ai.mw_pos(main.player))
		ft += (50.0 - disp_term) * float(_gmst("fFightDispMult", 0.2))       # getFightDispositionBias
		ft += float(_gmst("iFightDistanceBase", 20)) - float(_gmst("fFightDistanceMultiplier", 0.005)) * d
		ft *= alarm_term
		var of := _fight(n)
		if of + ft > 100.0:
			ft = 100.0 - of
		ft = maxf(0.0, ft)
		if of + ft >= 100.0:
			if dmod != 0 and only_hostile and not da.is_empty():
				var cur2 := int(main.dialogue.derived_disposition(da))
				a["crime_disp"] = int(a.get("crime_disp", 0)) + clampi(dmod, -cur2, 100 - cur2)
			main.ai.start_combat(n, main.player)
			main.dialogue.set_ai_setting(main.dialogue.make_actor(n), "fight", of + int(ft))
			a["alarmed"] = true
			a["crime_id"] = id
	if reported:
		set_bounty(bounty() + b)
		var vf := ""
		if victim != null:
			vf = String(main.builder.actors.record("npc", String((victim as Node).get_meta("mw_base", ""))).get("faction", "")).to_lower()
		if vf.is_empty():
			vf = faction.to_lower()
		var facs: Dictionary = st().get("factions", {})
		if not vf.is_empty() and facs.has(vf):
			facs[vf]["expelled"] = true
	if type == ASSAULT and victim != null:
		if not main.ai.in_combat(victim) and not _in_pursuit(victim):
			main.ai.start_combat(victim, main.player)
		main.combat._actor_state(main.combat.fighter_of(victim))["crime_id"] = id
	return reported

## actorAttacked (gracz zaatakował NPC): napaść, jeśli NPC nie był wrogi (canCommitCrimeAgainst).
func on_assault(victim: Node) -> void:
	if victim == null or String(victim.get_meta("mw_actor", "")) != "npc":
		return
	if main.ai.in_combat(victim) or _in_pursuit(victim) or main.ai.fight_term(victim, main.player) >= 100.0:
		return
	if not can_commit_against(victim):
		return
	main.combat._actor_state(main.combat.fighter_of(victim))["crime_id"] = int(st().get("crime_id_current", -1)) + 1
	commit(victim, ASSAULT)

## canCommitCrimeAgainst (część niezależna od walki): ofiara nie jest wilkołakiem ani wampirem (Vampirism > 0).
func can_commit_against(victim: Node) -> bool:
	var f: Dictionary = main.combat.fighter_of(victim)
	if f.is_empty():
		return false
	if bool(main.combat._actor_state(f).get("werewolf", false)):
		return false
	return main.magic == null or main.magic.magnitude_of(f, 133) <= 0.0

## actorKilled: morderstwo, gdy gracz zaczął (crime_id) albo ofiara nie była wroga.
func on_killed(victim: Node) -> void:
	if victim == null or String(victim.get_meta("mw_actor", "")) != "npc":
		return
	var a: Dictionary = main.combat._actor_state(main.combat.fighter_of(victim))
	var hostile: bool = main.ai.fight_term(victim, main.player) >= 100.0 and not a.has("crime_id")
	if hostile and not a.has("crime_id"):
		return
	if not can_commit_against(victim):
		return
	commit(victim, MURDER)

# --- strażnicy -----------------------------------------------------------------------------------------------

## updateCrimePursuit co 0,25 s: strażnik widzi gracza z grzywną ≥ iCrimeThreshold.
func tick(dt: float) -> void:
	_timer += dt
	if _timer < 0.25 or main.player == null:
		return
	_timer = 0.0
	if bool(st().get("werewolf", false)):
		return                      # updateCrimePursuit: wobec wilkołaka bez pościgu i bez uspokajania świadków
	calm_witnesses()
	var b := bounty()
	var cut := int(_gmst("iCrimeThreshold", 1000))
	if b < cut:
		return
	for n in main.ai.actor_nodes():
		if not _is_guard(n) or _in_pursuit(n) or main.ai.in_combat(n) or main.combat.is_dead(main.combat.fighter_of(n)):
			continue
		if main.magic.magnitude_of(main.combat.fighter_of(n), 49) > 0.0:
			continue
		if not (main.ai._los(n, main.player) and main.ai.awareness(main.player, n, test_roll)):
			continue
		if b >= cut * int(_gmst("iCrimeThresholdMultiplier", 10)):
			main.ai.start_combat(n, main.player)
		else:
			main.ai.stack(n, {"type": "pursue", "target": "player", "priority": 2}, false)
		main.combat._actor_state(main.combat.fighter_of(n))["alarmed"] = true
		main.combat._actor_state(main.combat.fighter_of(n))["crime_id"] = new_crime_id()

## AiPursue: strażnik biegnie do gracza; na 100 jednostek i w linii wzroku – rozmowa (grzywna, więzienie, opór).
func pursue(n: CharacterBody3D, p: Dictionary, dt: float) -> bool:
	if bounty() <= 0 or main.combat.is_dead(main.combat.player_fighter()):
		return true
	var reached: bool = main.ai.path_to(n, main.ai.mw_pos(main.player), dt, 100.0, true)
	if reached and main.ai._los(main.player, n):
		main.ai._stop(n)
		if main.dialogue_window != null and not main.dialogue_window.visible:
			main.open_dialogue(n)
		return true
	return false

# --- grzywna i więzienie ---------------------------------------------------------------------------------------

## Zabranie skradzionych rzeczy (confiscateStolenItems): do właściciela – tu: usunięte z ekwipunku gracza.
func confiscate() -> int:
	var inv = main.interaction.inventory
	var n := 0
	for item in (st().get("stolen", {}) as Dictionary).keys():
		var owners: Dictionary = st().stolen[item]
		var total := 0
		for k in owners:
			total += int(owners[k])
		var have: int = inv.count_of("player", {}, String(item))
		var take := mini(total, have)
		if take > 0:
			inv.remove("player", {}, String(item), take)
			n += take
	st()["stolen"] = {}
	return n

## PayFine: złoto za grzywnę, skradzione przedmioty zabrane; PayFineThief – bez zabierania (OpenMW: oba zerują).
func pay_fine(confiscate_items := true) -> void:
	var inv = main.interaction.inventory
	inv.remove("player", {}, "gold_001", mini(bounty(), inv.count_of("player", {}, "gold_001")))
	set_bounty(0)
	if confiscate_items:
		confiscate()

func _markers() -> Dictionary:
	if markers == null:
		var d = MWWorldDB._read_json(main.db.data_root.path_join("world/markers.json"))
		markers = d if d is Dictionary else {}
	return markers

## Najbliższy znacznik (World::getClosestMarker): na zewnątrz – siatka komórek wokół pozycji gracza
## (getClosestMarkerFromExteriorPosition); we wnętrzu – przeszukanie wnętrz przez drzwi (każde przejście = 1):
## znacznik w odwiedzanym wnętrzu, a po drzwiach prowadzących na zewnątrz – siatka wokół celu tych drzwi.
## Wnętrza spoza przekonwertowanych komórek: przybliżenie pozycją wejścia do wnętrza (pole „exterior”).
func closest_marker(kind: String) -> Dictionary:
	var lst: Array = _markers().get(kind, [])
	if main.interior.is_empty():
		return marker_grid(lst, main.ai.mw_pos(main.player))
	var checked := {}
	var nxt: Array = [String(main.interior).to_lower()]
	while not nxt.is_empty():
		var cur: Array = nxt
		nxt = []
		for cname in cur:
			checked[cname] = true
			for m in lst:
				if not String(m.cell).begins_with("ext:") and String(m.name).to_lower() == cname:
					return m
			var c: Dictionary = main.db.get_cell("int:" + String(cname))
			if c.is_empty():
				var le = main.state.player.get("last_exterior")
				if cname == String(main.interior).to_lower() and le is Array and le.size() >= 3:
					return marker_grid(lst, Vector3(float(le[0]), float(le[1]), float(le[2])))
				continue
			for r in c.get("refs", []):
				var ex: Dictionary = r.get("extra", {})
				if not ex.has("door_dest"):
					continue
				var dc := String(ex.get("door_dest_cell", "")).to_lower()
				if dc.is_empty():
					var o: Array = (ex.door_dest as Dictionary).get("godot", {}).get("origin", [0, 0, 0])
					return marker_grid(lst, MWCoords.godot_to_mw(Vector3(float(o[0]), float(o[1]), float(o[2]))))
				if not checked.has(dc) and not dc in cur and not dc in nxt:
					nxt.append(dc)
	return {}

## getClosestMarkerFromExteriorPosition: znaczniki zewnętrzne na brzegu najmniejszego kwadratu komórek wokół
## pozycji; remis – pierwszy na drodze SW → SE → NE → NW → SW.
static func marker_grid(lst: Array, pos: Vector3) -> Dictionary:
	var cs := 8192.0
	var px := floori(pos.x / cs)
	var py := floori(pos.y / cs)
	var valid := []
	var min_grid := 1 << 30
	for m in lst:
		if not String(m.cell).begins_with("ext:"):
			continue
		var dx := floori(float(m.pos[0]) / cs) - px
		var dy := floori(float(m.pos[1]) / cs) - py
		var g := maxi(absi(dx), absi(dy)) * 2
		if g == 0:
			return m
		if g <= min_grid:
			if g < min_grid:
				valid.clear()
				min_grid = g
			valid.append([m, (g >> 1) + dx, (g >> 1) + dy])
	if valid.is_empty():
		return {}
	if valid.size() == 1:
		return valid[0][0]
	var best: Dictionary = {}
	var earliest := 1 << 30
	for v in valid:
		var col: int = v[1]
		var row: int = v[2]
		var d := 0
		if row == 0:
			d = col
		elif col == min_grid:
			d = min_grid + row
		elif row == min_grid:
			d = min_grid * 3 - col
		else:
			d = min_grid * 4 - row
		if d < earliest:
			earliest = d
			best = v[0]
	return best

## World::teleportToClosestMarker (ActionTeleport bez towarzyszy): → false, gdy brak znacznika.
func teleport_to_marker(kind: String) -> bool:
	var m := closest_marker(kind)
	if m.is_empty():
		return false
	var pos := Vector3(float(m.pos[0]), float(m.pos[1]), float(m.pos[2]))
	var cell := String(m.name) if not String(m.cell).begins_with("ext:") else ""
	main.travel_to_cell(cell, pos, rad_to_deg(float(m.rot[2])))
	return true

## GoToJail: dni = max(1, grzywna / iDaysinPrisonMod), grzywna 0, przedmioty zabrane, przeniesienie do znacznika
## więzienia, upływ czasu (odpoczynek), odsiadka (jailTimeServed: losowe umiejętności −1, Security/Sneak +1).
func go_to_jail() -> Dictionary:
	main.state.player["in_jail"] = true              # World::goToJail – GetPCInJail (bez okna więzienia: klatka)
	var days := maxi(1, int(bounty() / maxi(1, int(_gmst("iDaysinPrisonMod", 100)))))
	set_bounty(0)
	confiscate()
	var m := closest_marker("prisonmarker")
	if not m.is_empty():
		var pos := Vector3(float(m.pos[0]), float(m.pos[1]), float(m.pos[2]))
		var cell := String(m.name) if not String(m.cell).begins_with("ext:") else ""
		main.travel_to_cell(cell, pos, rad_to_deg(float(m.rot[2])))
	var ch = main.character
	var names: Array = main.builder.actors.records_index().get("skills", [])
	var changed := []
	for d in days:
		var i := rng.randi() % maxi(1, names.size())
		ch.skill_level_up(st(), i, "jail")
		changed.append(i)
	for h in days * 24:
		ch.rest_hour(st(), true, 0.0)
	main.envr.advance(days * 24.0)
	if main.has_method("pass_magic_time"):
		main.pass_magic_time(days * 24.0 * 3600.0)
	return {"days": days, "skills": changed, "marker": m}

# --- Security: wytrychy i sondy --------------------------------------------------------------------------------

## pickLock / probeTrap: x = 0,2 zręczność + 0,1 szczęście + bezpieczeństwo; wytrych: × jakość × zmęczenie
## + fPickLockMult × poziom zamka; sonda: + fTrapCostMult × koszt czaru pułapki, × jakość × zmęczenie;
## rzut 0..99 ≤ x – sukces; każda próba zużywa użycie. → {"ok", "message", "sound"}
func use_tool(node: Node, tool_id: String, kind: String, roll := -1) -> Dictionary:
	var ia = main.interaction
	var c: Dictionary = ia.snapshot(node)
	var me: Dictionary = main.combat.player_fighter()
	var at: Array = main.combat.attributes(me)
	var it: Dictionary = ia.inventory.item(tool_id)
	if it.is_empty():
		return {"ok": false, "message": ""}
	var x := 0.2 * float(at[3]) + 0.1 * float(at[7]) + float(main.combat.skill(me, 18))
	var q := float(it.rec.get("quality", 1.0))
	var ft := float(main.combat.fatigue_term(me))
	var res := {"ok": false, "message": "", "sound": ""}
	if kind == "lockpick":
		if int(c.lock) <= 0:
			return res
		x = x * q * ft + float(_gmst("fPickLockMult", -1.0)) * int(c.lock)
		unlock_attempted(c.extra, true)
		res.sound = "Open Lock Fail"
		if x <= 0.0:
			res.message = main.dialogue.gmst_text("sLockImpossible", "Ten zamek jest zbyt trudny.")
		elif float(roll if roll >= 0 else _roll()) <= x:
			main.state.set_lock(String(c.sid), 0)
			res.ok = true
			res.sound = "Open Lock"
			res.message = main.dialogue.gmst_text("sLockSuccess", "Otworzyłeś zamek.")
			main.skill_used(18, "security_lock")
		else:
			res.message = main.dialogue.gmst_text("sLockFail", "Nie udało się otworzyć zamka.")
	else:
		if String(c.trap).is_empty():
			return res
		var sp: Dictionary = main.builder.actors.record("spell", String(c.trap).to_lower())
		x += float(_gmst("fTrapCostMult", 0.0)) * float(main.magic.spell_cost(sp) if not sp.is_empty() else 0)
		x *= q * ft
		unlock_attempted(c.extra, true)
		res.sound = "Disarm Trap Fail"
		if x <= 0.0:
			res.message = main.dialogue.gmst_text("sTrapImpossible", "Tej pułapki nie da się rozbroić.")
		elif float(roll if roll >= 0 else _roll()) <= x:
			main.state.set_trap(String(c.sid), "")
			res.ok = true
			res.sound = "Disarm Trap"
			res.message = main.dialogue.gmst_text("sTrapSuccess", "Rozbroiłeś pułapkę.")
			main.skill_used(18, "security_trap")
		else:
			res.message = main.dialogue.gmst_text("sTrapFail", "Nie udało się rozbroić pułapki.")
	# zużycie (stan egzemplarza w ręce – CellRef::charge, „id#c:N”); po ostatnim użyciu przedmiot znika
	var slot: int = main.equipped_slot_of(tool_id)
	if slot >= 0:
		var eq: Dictionary = main._equipment()
		var cur_id := String(eq[str(slot)].id)
		var uses := int(ia.inventory.item_charge(cur_id)) - 1
		if uses <= 0:
			main.unequip_slot(slot)
			ia.inventory.remove("player", {}, cur_id, 1)
		else:
			main.combat._set_item_health(main.combat.player_fighter(), slot, float(uses))
	return res

## MechanicsManager::isItemStolenFrom: przedmiot skradziony temu aktorowi (właściciel – id bazowe) albo jego
## frakcji głównej. a – aktor rozmowy (make_actor).
func is_item_stolen_from(item: String, a: Dictionary) -> bool:
	var owners: Dictionary = (st().get("stolen", {}) as Dictionary).get(main.interaction.inventory.base_id(item), {})
	if owners.is_empty() or a.is_empty():
		return false
	if owners.has(String(a.get("base", "")).to_lower()):
		return true
	var fac := String((a.get("rec", {}) as Dictionary).get("faction", "")).to_lower() if bool(a.get("npc", false)) else ""
	return not fac.is_empty() and owners.has("faction:" + fac)

## confiscateStolenItemToOwner: zmniejsza licznik kradzieży (właściciel albo frakcja), przenosi przedmioty do
## ekwipunku ofiary i zgłasza kradzież (wartość × liczba).
func confiscate_to_owner(item: String, a: Dictionary, count: int) -> void:
	var base: String = main.interaction.inventory.base_id(item)
	var stolen: Dictionary = st().get("stolen", {})
	if not stolen.has(base):
		return
	var owners: Dictionary = stolen[base]
	var key := String(a.get("base", "")).to_lower()
	var fac := String((a.get("rec", {}) as Dictionary).get("faction", "")).to_lower() if bool(a.get("npc", false)) else ""
	if not owners.has(key) and not fac.is_empty() and owners.has("faction:" + fac):
		key = "faction:" + fac
	var take := mini(count, int(owners.get(key, 0)))
	owners[key] = int(owners.get(key, 0)) - take
	if int(owners[key]) <= 0:
		owners.erase(key)
	if owners.is_empty():
		stolen.erase(base)
	var inv = main.interaction.inventory
	inv.add(String(a.get("sid", "")), a.get("rec", {}), item, take)
	inv.remove("player", {}, item, take)
	commit(a.get("node"), THEFT, fac if key.begins_with("faction:") else "", take * int(main.trade.item_value(item)))
