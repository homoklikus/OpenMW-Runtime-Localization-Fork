extends RefCounted
## Dialogi, zadania i dziennik (etap 6) – port logiki OpenMW 0.51 (apps/openmw/mwdialogue: filter.cpp,
## selectwrapper.cpp, dialoguemanagerimp.cpp, journalimp.cpp, quest.cpp, keywordsearch.cpp;
## components/interpreter/defines.cpp; mwmechanics: getDerivedDisposition, getPersuasionDispositionChange).
##
## Dane: world/records/dialogue.json (konwerter, kolejność odpowiedzi jak w OpenMW). Stan rozmów w GameState:
##   state.journal                 indeksy zadań (jak etap 5: GetJournalIndex/Journal)
##   state.dialogue.known          tematy znane graczowi (DialogueManager::mKnownTopics)
##   state.dialogue.quests         {id: {"finished": bool, "infos": [id odpowiedzi]}}
##   state.dialogue.entries        wpisy dziennika z datą: {quest, info, text, actor, day, month, day_of_month}
##   state.dialogue.topics         dziennik tematów: {temat: [{info, text, actor}]}
##   state.dialogue.npcs           {sid: {"disposition", "talked", "reputation", "fight", "flee", "alarm", "hello"}}
##   state.dialogue.reactions      zmienione reakcje frakcji {f1: {f2: wartość}}
##   state.dialogue.deaths         liczba zabitych wg id (walka – etap 7)
## Frakcje gracza: state.player.character.factions {id: {"rank", "expelled"}}, faction_reputation {id: wartość}.
## Funkcje zależne od późniejszych etapów (walka, choroby, przestępstwa) zwracają stan „spoczynku” i są liczone
## w raporcie (partial).

const Loc := preload("res://scripts/mw/mw_localization.gd")

const ATTRS := ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
const SKILLS := ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear",
	"athletics", "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration",
	"alchemy", "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman", "mercantile",
	"speechcraft", "handtohand"]
const A_PERSONALITY := 6
const A_LUCK := 7
const SK_MERCANTILE := 24
const SK_SPEECHCRAFT := 25

# SelectWrapper::getType
const T_INTEGER := ["journal", "item", "dead", "choice", "fight", "hello", "alarm", "flee", "friendhit", "pclevel",
	"pcgender", "pcclothingmodifier", "pccrimelevel", "rankrequirement", "level", "pcreputation", "weather",
	"reputation", "factionrankdifference", "pcwerewolfkills", "facreactionlowest", "facreactionhighest",
	"creaturetarget"]
const T_NUMERIC := ["global", "local", "notlocal", "pchealth", "pcmagicka", "pcfatigue", "pchealthpercent",
	"health_percent"]
const T_BOOLEAN := ["samesex", "samerace", "samefaction", "pccommondisease", "pcblightdisease", "pccorprus",
	"pcexpelled", "pcvampire", "talkedtopc", "alarmed", "detected", "attacked", "shouldattack", "werewolf"]
const T_INVERTED := ["notid", "notfaction", "notclass", "notrace", "notcell"]
const WEATHERS := ["clear", "cloudy", "foggy", "overcast", "rain", "thunder", "ash", "blight", "snow",
	"blizzard"]
const FX_CORPRUS := 132
const FX_VAMPIRISM := 133
const PERSUASION := ["admire", "intimidate", "taunt", "bribe10", "bribe100", "bribe1000"]

signal voice_said(sid: String, topic: String, info_id: String)   # etap 10: kwestia głosowa (testy)
var records            # record(file, id), _all(file)
var state              # MWGameState
var main               # main.gd
var _data := {}        # id_lower → dialog
var _order: Array = []
var _kw := {}          # wyszukiwanie słów kluczowych wszystkich dialogów (2 pierwsze litery → [[słowo, id]])
var partial := {}      # funkcje warunków bez pełnej mechaniki (raport)
var unknown_topics := {}

# --- bieżąca rozmowa (DialogueManager) ------------------------------------------------------------------
var actor := {}        # {"sid", "base", "node", "npc": bool, "rec", "script"}
var choice := -1
var in_choice := false
var goodbye_flag := false
var choices: Array = []          # [[tekst, numer]]
var last_topic := ""
var talked := false
var actor_known := {}            # temat → {"flags", "info"}
var _cand := {}                  # temat → odpowiedzi, które mogą pasować do aktora (testActor)
var history: Array = []          # [{"kind": "response"|"message", "title", "text"}]
var original_disp := 0
var current_disp := 0
var permanent_change := 0
var _greeting_ids: Array = []

const SPECIFIC := 1
const EXHAUSTED := 2

func _init(records_source, game_state, game_main) -> void:
	records = records_source
	state = game_state
	main = game_main

# --- dane ----------------------------------------------------------------------------------------------

func available() -> bool:
	return not _load().is_empty()

func _load() -> Dictionary:
	if _data.is_empty():
		var d = records._all("dialogue")
		if d is Dictionary and d.has("dialogues"):
			_data = d["dialogues"]
			_order = d.get("order", _data.keys())
			_greeting_ids = []
			for k in _order:
				if String(_data[k].get("type", "")) == "greeting":
					_greeting_ids.append(k)
			_build_keywords()
	return _data

func dialogue(id: String) -> Dictionary:
	return _load().get(id.to_lower(), {})

func _ds() -> Dictionary:
	if not state.get("dialogue") is Dictionary:
		state.dialogue = {}
	var d: Dictionary = state.dialogue
	for k in ["known", "quests", "topics", "npcs", "reactions", "deaths"]:
		if not d.has(k) or not d[k] is Dictionary:
			d[k] = {}
	if not d.has("entries") or not d["entries"] is Array:
		d["entries"] = []
	return d

func _gmst(id: String, def) -> Variant:
	var g: Dictionary = records.record("gmst", id.to_lower())
	return g.get("value", def) if not g.is_empty() else def

func gmst_text(id: String, def := "") -> String:
	var v := String(_gmst(id, def))
	return main.loc.plain(Loc.key("GMST", id, "STRV"), v) if main.loc != null else v

func topic_name(id: String) -> String:
	var d := dialogue(id)
	var n := String(d.get("id", id))
	return main.loc.plain(Loc.key("DIAL", id, "NAME"), n) if main.loc != null else n

# --- aktor i gracz --------------------------------------------------------------------------------------

func _pst() -> Dictionary:
	return main.player_stats()

func _pderived() -> Dictionary:
	var st := _pst()
	return main.character.derived(st) if not st.is_empty() else {"attributes": [], "skills": []}

func player_factions() -> Dictionary:
	var st := _pst()
	if not st.get("factions") is Dictionary:
		st["factions"] = {}
	return st["factions"]

func player_rank(fid: String) -> int:
	var f: Dictionary = player_factions().get(fid.to_lower(), {})
	return int(f.get("rank", -1)) if not f.is_empty() else -1

func in_faction(fid: String) -> bool:
	return not fid.is_empty() and player_factions().has(fid.to_lower())

func faction_reputation(fid: String) -> int:
	var st := _pst()
	return int((st.get("faction_reputation", {}) as Dictionary).get(fid.to_lower(), 0))

func set_faction_reputation(fid: String, v: int) -> void:
	var st := _pst()
	if not st.get("faction_reputation") is Dictionary:
		st["faction_reputation"] = {}
	st["faction_reputation"][fid.to_lower()] = v

func expelled(fid: String) -> bool:
	return bool(player_factions().get(fid.to_lower(), {}).get("expelled", false))

## Kontekst aktora z węzła referencji (NPC albo stworzenie).
func make_actor(node: Node) -> Dictionary:
	var base := String(node.get_meta("mw_base", "")).to_lower()
	var o: Dictionary = main.db.get_object(base)
	var npc := String(o.get("type", "")) == "NPC_"
	var rec: Dictionary = records.record("npc" if npc else "creature", base)
	return {"sid": String(node.get_meta("mw_sid", "")), "base": base, "node": node, "npc": npc, "rec": rec,
		"script": String(rec.get("script", o.get("script", ""))).to_lower()}

func is_actor_node(node: Node) -> bool:
	if node == null:
		return false
	var t := String(main.db.get_object(String(node.get_meta("mw_base", ""))).get("type", ""))
	return t == "NPC_" or t == "CREA"

func _npc_state(a: Dictionary) -> Dictionary:
	var n: Dictionary = _ds().npcs
	if not n.has(a.sid):
		n[a.sid] = {}
	return n[a.sid]

func faction_of(a: Dictionary) -> String:
	return String(a.rec.get("faction", "")).to_lower() if a.npc else ""

## Ranga NPC w jego frakcji: RaiseRank/LowerRank (stan rozmów) albo rekord.
func faction_rank_of(a: Dictionary) -> int:
	if faction_of(a).is_empty():
		return -1
	return int(_ds().npcs.get(a.sid, {}).get("rank", a.rec.get("rank", 0)))

func base_disposition(a: Dictionary) -> int:
	var s: Dictionary = _ds().npcs.get(a.sid, {})
	return int(s.get("disposition", a.rec.get("disposition", 0)))

func set_base_disposition(a: Dictionary, v: int) -> void:
	if a.npc:
		_npc_state(a)["disposition"] = v

func reputation_of(a: Dictionary) -> int:
	return int(_ds().npcs.get(a.sid, {}).get("reputation", a.rec.get("reputation", 0)))

## Ustawienie AI: podstawa (rekord / Set*/Mod* ze skryptów) + modyfikator efektów magii (Uspokojenie, Szał,
## Demoralizacja, Otucha, Odpędzenie nieumarłych – modifyAiSetting). capped: jak Stat::getModified() (≥ 0);
## GetFight itd. – bez obcięcia (getModified(false)); with_mod = false – sama podstawa (ModFight).
func ai_setting(a: Dictionary, name: String, with_mod := true, capped := true) -> int:
	var base := int(_ds().npcs.get(a.sid, {}).get(name, (a.rec.get("ai", {}) as Dictionary).get(name, 0)))
	if not with_mod:
		return base
	var st = main.state.actors.get(String(a.sid), {}) if main.state.get("actors") is Dictionary else {}
	var v := base + int((st.get("ai_mod", {}) as Dictionary).get(name, 0)) if st is Dictionary else base
	return maxi(0, v) if capped else v

func set_ai_setting(a: Dictionary, name: String, v: int) -> void:
	_npc_state(a)[name] = clampi(v, 0, 100)

func talked_to_player(a: Dictionary) -> bool:
	return bool(_ds().npcs.get(a.sid, {}).get("talked", false))

func actor_name(a: Dictionary) -> String:
	var o: Dictionary = main.db.get_object(a.base)
	var fb := String(a.rec.get("name", o.get("name", a.base)))
	return main.loc.object_name(o, fb) if main.loc != null and not o.is_empty() else fb

func faction_reaction(f1: String, f2: String) -> int:
	var ch: Dictionary = _ds().reactions.get(f1.to_lower(), {})
	if ch.has(f2.to_lower()):
		return int(ch[f2.to_lower()])
	var fr: Dictionary = records.record("faction", f1.to_lower()).get("reactions", {})
	for k in fr:
		if String(k).to_lower() == f2.to_lower():
			return int(fr[k])
	return 0

## getDerivedDisposition (z obcięciem do 0..100, jeśli clamp).
func derived_disposition(a: Dictionary, clamp := true) -> int:
	if not a.npc:
		return 0
	var st := _pst()
	var d := _pderived()
	var x := float(base_disposition(a))
	# getBaseDisposition + getCrimeDispositionModifier (zmiana postawy za przestępstwo do czasu spłaty)
	if main.state.get("actors") is Dictionary:
		x += float((main.state.actors.get(String(a.sid), {}) as Dictionary).get("crime_disp", 0))
	if String(a.rec.get("race", "")).to_lower() == String(st.get("race", "")).to_lower():
		x += float(_gmst("fDispRaceMod", 5.0))
	var pers := float(d.attributes[A_PERSONALITY]) if d.attributes.size() > A_PERSONALITY else 0.0
	x += float(_gmst("fDispPersonalityMult", 0.5)) * (pers - float(_gmst("fDispPersonalityBase", 50.0)))
	var reaction := 0.0
	var rank := 0
	var nf := faction_of(a)
	var pf := player_factions()
	if pf.has(nf):
		if not expelled(nf):
			reaction = float(faction_reaction(nf, nf))
			rank = int(pf[nf].get("rank", 0))
	elif not nf.is_empty():
		var first := true
		for f in _sorted_keys(pf):
			if expelled(f):
				continue
			var r := faction_reaction(nf, f)
			if first or r < reaction:
				reaction = float(r)
				rank = int(pf[f].get("rank", 0))
			first = false
	x += (float(_gmst("fDispFactionRankMult", 0.5)) * rank + float(_gmst("fDispFactionRankBase", 1.0))) \
		* float(_gmst("fDispFactionMod", 3.0)) * reaction
	x -= float(_gmst("fDispCrimeMod", 0.0)) * float(st.get("bounty", 0))
	if bool(st.get("common_disease", false)) or bool(st.get("blight_disease", false)):
		x += float(_gmst("fDispDiseaseMod", -10.0))
	if bool(st.get("weapon_drawn", false)):
		x += float(_gmst("fDispWeaponDrawn", -5.0))
	x += charm_of(a)                         # getDerivedDisposition: + Urok (Charm)
	if clamp:
		return clampi(int(x), 0, 100)
	return int(x)

## Wielkość efektu Urok na NPC (mapa efektów aktora).
func charm_of(a: Dictionary) -> float:
	if main.magic == null or main.combat == null:
		return 0.0
	var n = a.get("node")
	var f: Dictionary = main.combat.fighter_of(n) if n != null else {"kind": "npc", "sid": String(a.sid),
		"base": String(a.get("base", "")), "rec": a.rec, "node": null}
	if f.is_empty() or not (main.state.get("actors") is Dictionary and main.state.actors.has(String(f.sid))):
		return 0.0                       # bez stanu aktora – bez działających czarów (zdolności nie dają Uroku)
	return main.magic.magnitude_of(f, main.magic.FX_CHARM)

static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k

func _cell_name() -> String:
	return main.script_host.player_cell_name()

func _fx(st: Dictionary) -> Dictionary:
	return main.character.constant_effects(st)

# --- filtr (MWDialogue::Filter) ------------------------------------------------------------------------

func _test_actor(info: Dictionary, a: Dictionary) -> bool:
	var creature: bool = not a.npc
	var who := String(info.get("actor", ""))
	if not who.is_empty():
		if who.to_lower() != a.base:
			return false
	elif creature:
		return false
	if not String(info.get("race", "")).is_empty():
		if creature:
			return true
		if String(info.race).to_lower() != String(a.rec.get("race", "")).to_lower():
			return false
	if not String(info.get("class", "")).is_empty():
		if creature:
			return true
		if String(info["class"]).to_lower() != String(a.rec.get("class", "")).to_lower():
			return false
	if bool(info.get("factionless", false)):
		if creature:
			return true
		if not faction_of(a).is_empty():
			return false
	elif not String(info.get("faction", "")).is_empty():
		if creature:
			return true
		if faction_of(a) != String(info.faction).to_lower():
			return false
		if faction_rank_of(a) < int(info.get("rank", -1)):
			return false
	elif int(info.get("rank", -1)) != -1:
		if creature:
			return true
		if faction_rank_of(a) < int(info.rank):
			return false
	if not creature:
		var female := bool(a.rec.get("female", false))
		if int(info.get("gender", -1)) == (0 if female else 1):
			return false
	return true

func _test_player(info: Dictionary, a: Dictionary) -> bool:
	var pcf := String(info.get("pcfaction", "")).to_lower()
	var pcrank := int(info.get("pcrank", -1))
	if not pcf.is_empty():
		if not player_factions().has(pcf):
			return false
		if player_rank(pcf) < pcrank:
			return false
	elif pcrank != -1:
		var nf := faction_of(a)
		if not player_factions().has(nf):
			return false
		if player_rank(nf) < pcrank:
			return false
	var cell := String(info.get("cell", ""))
	if not cell.is_empty() and not _cell_name().to_lower().begins_with(cell.to_lower()):
		return false
	return true

func _test_selects(info: Dictionary, a: Dictionary) -> bool:
	for c in info.get("conditions", []):
		if not _test_select(c, a):
			return false
	return true

func _test_disposition(info: Dictionary, a: Dictionary, invert := false) -> bool:
	if not a.npc:
		return true
	var d := derived_disposition(a)
	var need := int(info.get("disposition", 0))
	return (need == 0 or d < need) if invert else d >= need

static func compare(c: Dictionary, v: float) -> bool:
	var w := float(c.get("value", 0))
	match String(c.get("cmp", "==")):
		"==": return v == w
		"!=": return v != w
		">": return v > w
		">=": return v >= w
		"<": return v < w
		"<=": return v <= w
	return false

func _test_select(c: Dictionary, a: Dictionary) -> bool:
	var f := String(c.get("func", ""))
	if f == "choice" and choice == -1:
		return false
	if f == "weather" and not main.interior.is_empty():
		return false
	if f in T_INTEGER:
		return compare(c, float(_select_int(c, a)))
	if f in T_NUMERIC:
		return _select_numeric(c, a)
	if f in T_BOOLEAN:
		return compare(c, 1.0 if _select_bool(c, a) else 0.0)
	if f in T_INVERTED:
		return _select_bool(c, a)
	return true

func _local_value(c: Dictionary, a: Dictionary) -> Variant:
	if a.script.is_empty():
		return null
	var name := String(c.get("name", "")).to_lower()
	var locs: Dictionary = main.scripts.script_rec(a.script).get("locals", {})
	if not locs.has(name):
		return null
	var l: Dictionary = (main.scripts._sc().locals as Dictionary).get(a.sid, {})
	return float(l.get(name, 0.0))

func _select_numeric(c: Dictionary, a: Dictionary) -> bool:
	var st := _pst()
	match String(c.func):
		"global":
			var g: Dictionary = records.record("global", String(c.get("name", "")).to_lower())
			if g.is_empty():
				return true
			return compare(c, main.scripts.get_global(String(c.name)))
		"local":
			var v = _local_value(c, a)
			return v != null and compare(c, float(v))
		"notlocal":
			var v2 = _local_value(c, a)
			return not (v2 != null and compare(c, float(v2)))
		"pchealthpercent":
			var d := _pderived()
			var mx := float(d.get("health", {}).get("modified", 1.0))
			return compare(c, float(int(float(st.get("health", mx)) / maxf(mx, 1e-6) * 100.0)))
		"pcmagicka", "pcfatigue", "pchealth":
			return compare(c, float(st.get(String(c.func).substr(2), 0.0)))
		"health_percent":
			return compare(c, 100.0)
	return true

func _select_int(c: Dictionary, a: Dictionary) -> int:
	var f := String(c.func)
	var st := _pst()
	var name := String(c.get("name", "")).to_lower()
	if f.begins_with("pc") and f.substr(2) in ATTRS:
		return int(_pderived().attributes[ATTRS.find(f.substr(2))])
	if f.begins_with("pc") and f.substr(2) in SKILLS:
		return int(_pderived().skills[SKILLS.find(f.substr(2))])
	match f:
		"journal": return int(state.journal.get(name, 0))
		"item": return int(main.interaction.inventory.count_of("player", {}, name))
		"dead": return int(_ds().deaths.get(name, 0))
		"choice": return choice
		"fight", "hello", "alarm", "flee": return ai_setting(a, f)
		"friendhit": return _partial(f, 0)
		"pclevel": return int(st.get("level", 1))
		"pcgender": return 1 if bool(st.get("female", false)) else 0
		"pcclothingmodifier": return _partial(f, 0)
		"pccrimelevel": return int(st.get("bounty", 0))
		"rankrequirement": return _rank_requirement(a)
		"level": return int(a.rec.get("level", 1))
		"pcreputation": return int(st.get("reputation", 0))
		"weather": return maxi(0, WEATHERS.find(String(main.envr.weather).to_lower()))
		"reputation": return reputation_of(a) if a.npc else 0
		"factionrankdifference":
			var nf := faction_of(a)
			return 0 if nf.is_empty() else player_rank(nf) - faction_rank_of(a)
		"pcwerewolfkills": return int(st.get("werewolf_kills", 0))
		"facreactionlowest", "facreactionhighest":
			var nf2 := faction_of(a)
			if nf2.is_empty():
				return 0
			var low := f == "facreactionlowest"
			var value := 0
			for pf in _sorted_keys(player_factions()):
				var r := faction_reaction(nf2, pf)
				if (r < value) if low else (r > value):
					value = r
			return value
		"creaturetarget":
			# Function_CreatureTarget: cel walki mówcy – wilkołak 2, stworzenie 1, inaczej 0
			var cn = a.get("node")
			if main.get("ai") == null or cn == null or not is_instance_valid(cn):
				return 0
			var tid: String = main.ai.combat_target(cn)
			if tid.is_empty():
				return 0
			if tid == "player":
				return 2 if bool(main.player_stats().get("werewolf", false)) else 0
			var tn: Node = main.ai._target_of({"target": tid})
			if tn == null:
				return 0
			if String(tn.get_meta("mw_actor", "")) == "creature":
				return 1
			return 2 if bool(_astate({"sid": tid}).get("werewolf", false)) else 0
	return 0

func _select_bool(c: Dictionary, a: Dictionary) -> bool:
	var st := _pst()
	var id := String(c.get("name", "")).to_lower()
	match String(c.func):
		"notid": return a.base != id
		"notfaction": return faction_of(a) != id
		"notclass": return not a.npc or String(a.rec.get("class", "")).to_lower() != id
		"notrace": return not a.npc or String(a.rec.get("race", "")).to_lower() != id
		"notcell": return not _cell_name().to_lower().begins_with(id)
		"samesex": return a.npc and bool(st.get("female", false)) == bool(a.rec.get("female", false))
		"samerace": return a.npc and String(a.rec.get("race", "")).to_lower() == String(st.get("race", "")).to_lower()
		"samefaction": return in_faction(faction_of(a))
		"pccommondisease": return bool(st.get("common_disease", false))
		"pcblightdisease": return bool(st.get("blight_disease", false))
		"pccorprus": return float(_fx(st).get(str(FX_CORPRUS), 0.0)) != 0.0
		"pcexpelled":
			var nf := faction_of(a)
			return not nf.is_empty() and expelled(nf)
		"pcvampire": return float(_fx(st).get(str(FX_VAMPIRISM), 0.0)) > 0.0
		"talkedtopc": return talked
		"alarmed": return bool(_astate(a).get("alarmed", false))
		"detected":
			var dn = a.get("node")
			if main.get("ai") == null or dn == null or not is_instance_valid(dn):
				return _partial("detected", 1) != 0
			return main.ai.awareness(main.player, dn)
		"attacked": return bool(_astate(a).get("attacked", false))
		"shouldattack":
			var sn = a.get("node")
			if main.get("ai") == null or sn == null or not is_instance_valid(sn):
				return _partial("shouldattack", 0) != 0
			return main.ai.in_combat(sn) or main.ai.fight_term(sn, main.player) >= 100.0
		"werewolf": return bool(a.get("npc", false)) and bool(_astate(a).get("werewolf", false))    # mówca (filter.cpp)
	return false

func _astate(a: Dictionary) -> Dictionary:
	var acts = main.state.get("actors") if main != null else null
	return acts.get(String(a.get("sid", "")), {}) if acts is Dictionary else {}

func _partial(f: String, v: int) -> int:
	partial[f] = int(partial.get(f, 0)) + 1
	return v

func _rank_requirement(a: Dictionary) -> int:
	var nf := faction_of(a)
	if nf.is_empty():
		return 0
	var rank := player_rank(nf)
	if rank >= 9:
		return 0
	var fac: Dictionary = records.record("faction", nf)
	var reqs: Array = fac.get("rank_requirements", [])
	if rank + 1 >= reqs.size():
		return 0
	var req: Dictionary = reqs[rank + 1]
	var st := _pst()
	var res := 0
	# hasSkillsForRank + atrybuty (wartości bazowe)
	var skills := []
	for s in fac.get("skills", []):
		if int(s) >= 0 and int(s) < 27:
			skills.append(int(float(st.skills[int(s)])))
	skills.sort()
	skills.reverse()
	var ok := true
	if not skills.is_empty():
		ok = skills[0] >= int(req.get("primary_skill", 0))
		if ok and skills.size() >= 2:
			ok = skills[1] >= int(req.get("favoured_skill", 0))
		if ok and skills.size() >= 3:
			ok = skills[2] >= int(req.get("favoured_skill", 0))
	var fattr: Array = fac.get("attributes", [0, 0])
	var rattr: Array = req.get("attributes", [0, 0])
	if ok:
		for i in 2:
			var ai := int(fattr[i]) if i < fattr.size() else -1
			if ai >= 0 and ai < 8 and float(st.attributes[ai]) < float(rattr[i]):
				ok = false
	if ok:
		res += 1
	if faction_reputation(nf) >= int(req.get("reputation", 0)):
		res += 2
	return res

## Filter::list – [[id dialogu, odpowiedź]]; fallback do „Info Refusal”, gdy odpowiedzi odrzuciła tylko postawa.
func list_infos(dial_id: String, a: Dictionary, fallback := false, search_all := false, invert := false) -> Array:
	var out := []
	var refusal := false
	var key := dial_id.to_lower()
	for info in _candidates(key, a):
		if _test_player(info, a) and _test_selects(info, a):
			if _test_disposition(info, a, invert):
				out.append([key, info])
				if not search_all:
					break
			else:
				refusal = true
	if out.is_empty() and refusal and fallback:
		for info2 in _candidates("info refusal", a):
			if _test_player(info2, a) and _test_selects(info2, a) and _test_disposition(info2, a, invert):
				out.append(["info refusal", info2])
				if not search_all:
					break
	return out

func search(dial_id: String, a: Dictionary, fallback := false) -> Array:
	var l := list_infos(dial_id, a, fallback)
	return l[0] if not l.is_empty() else []

## Odpowiedzi dialogu, które mogą pasować do aktora (testActor – stałe w czasie rozmowy).
func _candidates(key: String, a: Dictionary) -> Array:
	var ck: String = String(a.sid) + "|" + key
	if _cand.has(ck):
		return _cand[ck]
	var out := []
	for info in dialogue(key).get("infos", []):
		if _test_actor(info, a):
			out.append(info)
	_cand[ck] = out
	return out

# --- słowa kluczowe (KeywordSearch) --------------------------------------------------------------------

func _build_keywords() -> void:
	_kw = {}
	for k in _order:
		var name := topic_name(k).to_lower()
		_seed(_kw, name, k)

static func _seed(kw: Dictionary, word: String, id: String) -> void:
	if word.is_empty():
		return
	var b := word.substr(0, 2)
	if not kw.has(b):
		kw[b] = []
	for e in kw[b]:
		if e[0] == word:
			return
	kw[b].append([word, id])

const SEPARATORS := "\n\r \t'\"(["

## parseHyperText: [{beg, end, id, display, explicit}] – „@temat#” i słowa kluczowe (najdłuższe wygrywa).
static func parse_hypertext(text: String, kw: Dictionary) -> Array:
	var out := []
	var pos := 0
	while true:
		var b := text.find("@", pos)
		var e := text.find("#", b) if b >= 0 else -1
		if b >= 0 and e >= 0:
			if b != pos:
				out.append_array(_highlight(text, pos, b, kw))
			var name := text.substr(b + 1, e - b - 1)
			var clean := name.rstrip("\u007f")
			var tid := (clean + "*".repeat(name.length() - clean.length())).to_lower()
			out.append({"beg": b, "end": e + 1, "id": tid, "display": clean, "explicit": true})
			pos = e + 1
		else:
			if pos < text.length():
				out.append_array(_highlight(text, pos, text.length(), kw))
			break
	return out

static func _highlight(text: String, beg: int, end: int, kw: Dictionary) -> Array:
	var low := text.to_lower()
	var matches := []
	for i in range(beg, end):
		if i != beg and not SEPARATORS.contains(text[i - 1]):
			continue
		var keys := [low.substr(i, 2)]
		if keys[0].length() == 2:
			keys.append(low.substr(i, 1))
		for key in keys:
			for e in kw.get(key, []):
				var w: String = e[0]
				if (String(key).length() == 1) != (w.length() == 1) and String(key).length() == 1:
					continue
				if i + w.length() <= end and low.substr(i, w.length()) == w:
					matches.append({"beg": i, "end": i + w.length(), "id": e[1],
						"display": text.substr(i, w.length()), "explicit": false})
	matches.sort_custom(func(x, y): return x.beg < y.beg or (x.beg == y.beg and x.end < y.end))
	var out := []
	while not matches.is_empty():
		var longest := 0
		var longest_size := 0
		for j in matches.size():
			var m: Dictionary = matches[j]
			var size: int = m.end - m.beg
			if size > longest_size:
				longest_size = size
				longest = j
			if j + 1 >= matches.size():
				break
			if m.end <= matches[j + 1].beg:
				break
		var k: Dictionary = matches[longest]
		matches.remove_at(longest)
		out.append(k)
		matches = matches.filter(func(m): return not (m.beg < k.end and m.end > k.beg))
	out.sort_custom(func(x, y): return x.beg < y.beg)
	return out

func topic_ids_in(text: String) -> Array:
	_load()
	return parse_hypertext(text, _kw).map(func(m): return String(m.id))

func add_topics_from_text(text: String) -> void:
	update_actor_known_topics()
	for t in topic_ids_in(text):
		if actor_known.has(t):
			_ds().known[t] = true

func add_topic(id: String) -> bool:
	if dialogue(id).is_empty():
		unknown_topics[id.to_lower()] = true
		return false
	_ds().known[id.to_lower()] = true
	return true

# --- podstawianie (%PCName…) ---------------------------------------------------------------------------

const ACTION_BINDINGS := [["actionslideright", "sRight"], ["actionreadymagic", "sReady_Magic"],
	["actionprevweapon", "sPrevWeapon"], ["actionnextweapon", "sNextWeapon"], ["actiontogglerun", "sAuto_Run"],
	["actionslideleft", "sLeft"], ["actionreadyitem", "sReady_Weapon"], ["actionprevspell", "sPrevSpell"],
	["actionnextspell", "sNextSpell"], ["actionrestmenu", "sRestKey"], ["actionmenumode", "sInventory"],
	["actionactivate", "sActivate"], ["actionjournal", "sJournal"], ["actionforward", "sForward"],
	["actioncrouch", "sCrouch_Sneak"], ["actionjump", "sJump"], ["actionback", "sBack"], ["actionuse", "sUse"],
	["actionrun", "sRun"]]
const ACTION_KEYS := {"actionactivate": "activate", "actionjournal": "journal", "actionmenumode": "inventory"}
const CONTEXT := ["nextpcrank", "pcnextrank", "faction", "pcclass", "pcname", "pcrace", "pcrank", "class", "cell",
	"race", "rank", "name"]
const DIALOG_ONLY := ["nextpcrank", "pcnextrank", "faction", "pcrank", "rank"]
var _globals_sorted: Array = []

func _record_name(file: String, id: String) -> String:
	var r: Dictionary = records.record(file, id.to_lower())
	var fb := String(r.get("name", id))
	var t: String = {"race": "RACE", "class": "CLAS", "faction": "FACT"}.get(file, "")
	return main.loc.plain(Loc.key(t, id, "FNAM"), fb) if main.loc != null and t != "" else fb

func _rank_name(fid: String, rank: int) -> String:
	var ranks: Array = records.record("faction", fid).get("ranks", [])
	if rank < 0 or rank >= ranks.size():
		return ""
	return main.loc.plain(Loc.key("FACT", fid, "RNAM[%d]" % rank), String(ranks[rank])) if main.loc != null else String(ranks[rank])

func _context_value(name: String, a: Dictionary, dialog: bool) -> Variant:
	if not dialog and name in DIALOG_ONLY:
		return ""
	var st := _pst()
	var has_actor: bool = not a.is_empty() and dialog
	match name:
		"pcname": return String(st.get("name", ""))
		"pcclass": return _record_name("class", String(st.get("class", "")))
		"pcrace": return _record_name("race", String(st.get("race", "")))
		"class":
			return _record_name("class", String(a.rec.get("class", ""))) if has_actor and a.npc else _record_name("class", String(st.get("class", "")))
		"race":
			return _record_name("race", String(a.rec.get("race", ""))) if has_actor and a.npc else _record_name("race", String(st.get("race", "")))
		"name": return actor_name(a) if has_actor else String(st.get("name", ""))
		"cell": return _cell_name()
		"faction", "rank", "pcrank", "nextpcrank", "pcnextrank":
			if a.is_empty():
				return ""
			var f := faction_of(a)
			if f.is_empty():
				return "%"
			if name == "faction":
				return _record_name("faction", f)
			if name == "rank":
				var r := faction_rank_of(a)
				return "%" if r < 0 or r > 9 else _rank_name(f, r)
			var pr := player_rank(f)
			if name == "pcrank":
				return _rank_name(f, maxi(pr, 0))
			return _rank_name(f, mini(pr + 1, 9))
	return null

## fixDefinesDialog / fixDefinesMsgBox: %Zmienna i ^Zmienna → wartości (wbudowane, potem zmienne globalne).
func fix_defines(text: String, a: Dictionary, dialog := true) -> String:
	if not text.contains("%") and not text.contains("^"):
		return text
	var out := ""
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if ch != "%" and ch != "^":
			out += ch
			i += 1
			continue
		var low := text.substr(i + 1).to_lower()
		var repl = null
		var used := 0
		for b in ACTION_BINDINGS:
			if low.begins_with(b[0]):
				repl = _action_key(b[0], b[1])
				used = String(b[0]).length()
				break
		if repl == null and low.begins_with("pccrimelevel"):
			repl = str(int(_pst().get("bounty", 0)))
			used = 12
		if repl == null:
			for cname in CONTEXT:
				if low.begins_with(cname):
					repl = _context_value(cname, a, dialog)
					used = String(cname).length()
					if repl == null:
						repl = ""
					break
		if repl == null:
			if _globals_sorted.is_empty():
				_globals_sorted = (records._all("global") as Dictionary).keys()
				_globals_sorted.sort_custom(func(x, y): return String(x).length() > String(y).length())
			for g in _globals_sorted:
				if low.begins_with(String(g)):
					var gr: Dictionary = records.record("global", String(g))
					var v: float = main.scripts.get_global(String(g))
					repl = str(int(v)) if String(gr.get("type", "f")) in ["short", "long", "s", "l"] else _fmt_float(v)
					used = String(g).length()
					break
		if repl == null:
			out += ch
			i += 1
		else:
			out += String(repl)
			i += 1 + used
	return out

static func _fmt_float(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)

func _action_key(action: String, gm: String) -> String:
	var act := String(ACTION_KEYS.get(action, ""))
	if act != "" and InputMap.has_action(act):
		for e in InputMap.action_get_events(act):
			if e is InputEventKey:
				return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return gmst_text(gm, gm)

## Tekst odpowiedzi: tłumaczenie (warianty płci), potem podstawienia.
func info_text(dial_id: String, info: Dictionary, a: Dictionary) -> String:
	var t := String(info.get("text", ""))
	if main.loc != null:
		var f := bool(a.rec.get("female", false)) if not a.is_empty() else false
		t = main.loc.info_text(dial_id, String(info.get("id", "")), t, f, bool(_pst().get("female", false)))
	return fix_defines(t, a, true)

# --- rozmowa (DialogueManager) -------------------------------------------------------------------------

## startDialogue: powitanie („Greeting 0”…„Greeting 9”, bez fallbacku). false – brak powitania (okno się nie otwiera).
func start(node: Node) -> bool:
	_load()
	var a := make_actor(node)
	if a.rec.is_empty():
		return false
	update_globals()
	actor = a
	_cand.clear()
	last_topic = ""
	choice = -1
	in_choice = false
	goodbye_flag = false
	choices = []
	history = []
	talked = talked_to_player(a)
	actor_known = {}
	original_disp = base_disposition(a)
	current_disp = original_disp
	for gid in _greeting_ids:
		var r := search(gid, a, false)
		if r.is_empty():
			continue
		_npc_state(a)["talked"] = true
		var info: Dictionary = r[1]
		_respond("", info_text(gid, info, a))
		last_topic = gid
		_run_result(info)
		add_topics_from_text(String(info.get("text", "")))
		return true
	actor = {}
	return false

## DialogueManager::say: kwestia z dialogu głosowego („hello”, „idle”, „attack”, „hit”, „flee”, „thief”,
## „intruder”) – nie, gdy aktor już mówi, NPC pływa albo jest powalony; pierwsza pasująca odpowiedź (filtr jak
## w rozmowie, bez fallbacku): napis, głos (SNAM) i skrypt wyniku. true – znaleziono odpowiedź.
func say_voice(node: Node, topic: String) -> bool:
	if node == null or not is_instance_valid(node) or main.audio == null:
		return false
	_load()
	var a := make_actor(node)
	if a.rec.is_empty() or main.audio.say_active(a.sid):
		return false
	if a.npc and bool(node.get("swimming")):
		return false
	if main.combat != null and bool(main.combat._actor_state({"sid": a.sid}).get("knocked_down", false)):
		return false                    # nieprzytomny nie mówi
	update_globals()
	var r := search(topic, a, false)
	if r.is_empty():
		return false
	var info: Dictionary = r[1]
	var text := info_text(String(r[0]), info, a)
	var secs: float = main.audio.say(a.sid, String(info.get("sound", "")), node as Node3D,
			float(node.get("height")) * 0.9 if node.get("height") != null else 1.6)
	voice_said.emit(a.sid, topic, String(info.get("id", "")))
	if not text.is_empty() and main.has_method("subtitle"):
		main.subtitle(actor_name(a) + ": " + text, secs if secs > 0.0 else 1.0 + 0.06 * text.length())
	if not (info.get("result_body", []) as Array).is_empty():
		main.scripts.run_dialogue(info.get("result_body", []), a)
	return true

func _respond(title: String, text: String) -> void:
	history.append({"kind": "response", "title": title, "text": text})

func message(text: String) -> void:
	history.append({"kind": "message", "text": text})

func _run_result(info: Dictionary) -> void:
	var body: Array = info.get("result_body", [])
	if body.is_empty() or actor.is_empty():
		return
	main.scripts.run_dialogue(body, actor)

## Dostępne tematy (getAvailableTopics): znane graczowi i mające odpowiedź u aktora – posortowane bez wielkości liter.
func available_topics() -> Array:
	update_actor_known_topics()
	var out := []
	var known: Dictionary = _ds().known
	for t in actor_known:
		if known.has(t):
			out.append(t)
	out.sort_custom(func(x, y): return topic_name(x).to_lower() < topic_name(y).to_lower())
	return out

func update_actor_known_topics() -> void:
	update_globals()
	actor_known = {}
	if actor.is_empty():
		return
	var saved := choice
	choice = -1
	for k in _order:
		if String(_data[k].get("type", "")) != "topic":
			continue
		var r := search(k, actor, true)
		if r.is_empty():
			continue
		var info: Dictionary = r[1]
		var flags := 0
		if not _in_journal(k, String(info.get("id", ""))):
			if String(info.get("actor", "")).to_lower() == actor.base:
				flags |= SPECIFIC
		else:
			flags |= EXHAUSTED
		actor_known[k] = {"flags": flags, "info": info}
	choice = saved
	var known: Dictionary = _ds().known
	for k in actor_known:
		var e: Dictionary = actor_known[k]
		if not (int(e.flags) & EXHAUSTED) or not known.has(k):
			continue
		for t in topic_ids_in(String(e.info.get("text", ""))):
			if actor_known.has(t) and not known.has(t):
				e.flags = int(e.flags) & ~EXHAUSTED
				break

func topic_flags(t: String) -> int:
	return int(actor_known.get(t, {}).get("flags", 0))

func _in_journal(topic: String, info_id: String) -> bool:
	for e in _ds().topics.get(topic, []):
		if String(e.get("info", "")) == info_id:
			return true
	return false

## Wybór tematu (keywordSelected → executeTopic).
func select_topic(t: String) -> void:
	if in_choice or goodbye_flag or actor.is_empty():
		return
	var d := dialogue(t)
	if String(d.get("type", "")) != "topic":
		return
	_execute_topic(t.to_lower())

func _execute_topic(t: String) -> void:
	var r := search(t, actor, true)
	if r.is_empty():
		return
	var info: Dictionary = r[1]
	var dtype := String(dialogue(t).get("type", ""))
	var title := topic_name(t)
	if dtype == "persuasion":
		title = gmst_text("s" + String(dialogue(t).get("id", t)).replace(" ", ""), title)
	_respond(title, info_text(String(r[0]), info, actor))
	if dtype == "topic" and String(r[0]) == t:
		add_topic_entry(t, info, actor)
	last_topic = t
	_run_result(info)
	add_topics_from_text(String(info.get("text", "")))

## Odpowiedź na pytanie (questionAnswered).
func answer(n: int) -> void:
	choice = n
	var d := dialogue(last_topic)
	if not d.is_empty() and String(d.get("type", "")) in ["topic", "greeting"]:
		var r := search(last_topic, actor, true)
		choices = []
		in_choice = false
		if not r.is_empty():
			var info: Dictionary = r[1]
			add_topics_from_text(String(info.get("text", "")))
			choice = -1
			_respond("", info_text(String(r[0]), info, actor))
			if String(d.get("type", "")) == "topic" and String(r[0]) == last_topic:
				add_topic_entry(last_topic, info, actor)
			_run_result(info)
		else:
			choice = -1
	choice = -1
	update_actor_known_topics()

func add_choice(text: String, n: int) -> void:
	in_choice = true
	choices.append([text, n])

func goodbye() -> void:
	in_choice = false
	goodbye_flag = true

## Pożegnanie (goodbyeSelected): trwała zmiana postawy z perswazji.
func end() -> void:
	if actor.is_empty():
		return
	if actor.npc and (permanent_change != 0 or original_disp != current_disp):
		_update_original_disposition()
		set_base_disposition(actor, 0)
		var zero := derived_disposition(actor, false)
		set_base_disposition(actor, clampi(original_disp + permanent_change, -zero, 100 - zero))
	permanent_change = 0
	original_disp = 0
	current_disp = 0
	actor = {}
	_cand.clear()

func _update_original_disposition() -> void:
	if actor.npc and base_disposition(actor) != current_disp:
		current_disp = base_disposition(actor)
		original_disp = current_disp

# --- perswazja -----------------------------------------------------------------------------------------

func _ratings(player: bool, a: Dictionary) -> Array:
	var pers: float
	var luck: float
	var speech: float
	var merc: float
	var rep: float
	var level: float
	var fat: float
	if player:
		var st := _pst()
		var d := _pderived()
		pers = float(d.attributes[A_PERSONALITY])
		luck = float(d.attributes[A_LUCK])
		speech = float(d.skills[SK_SPEECHCRAFT])
		merc = float(d.skills[SK_MERCANTILE])
		rep = float(st.get("reputation", 0))
		level = float(st.get("level", 1))
		fat = main.character.fatigue_term(st, d)
	else:
		var s: Dictionary = main.script_host.npc_autocalc(a.rec)
		var at: Array = s.get("attributes", [])
		var sk: Array = s.get("skills", [])
		pers = float(at[A_PERSONALITY]) if at.size() > A_PERSONALITY else 0.0
		luck = float(at[A_LUCK]) if at.size() > A_LUCK else 0.0
		speech = float(sk[SK_SPEECHCRAFT]) if sk.size() > SK_SPEECHCRAFT else 0.0
		merc = float(sk[SK_MERCANTILE]) if sk.size() > SK_MERCANTILE else 0.0
		rep = float(reputation_of(a))
		level = float(a.rec.get("level", 1))
		fat = float(_gmst("fFatigueBase", 1.25))       # NPC z pełną kondycją (walka – etap 7)
	var pt := pers / float(_gmst("fPersonalityMod", 5.0))
	var lt := luck / float(_gmst("fLuckMod", 10.0))
	var rt := rep * float(_gmst("fReputationMod", 1.0))
	var lv := level * float(_gmst("fLevelMod", 5.0))
	var r1 := (rt + lt + pt + speech) * fat
	if player:
		return [r1, r1 + lv, (merc + lt + pt) * fat]
	return [r1, (lv + rt + lt + pt + speech) * fat, (merc + rt + lt + pt) * fat]

## getPersuasionDispositionChange → {success, temp, perm}; roll – rzut 0..99 (test: stały).
func persuasion_change(kind: String, roll: int) -> Dictionary:
	var a := actor
	var npc := _ratings(false, a)
	var pl := _ratings(true, a)
	var cur := derived_disposition(a)
	var d := 1.0 - 0.02 * absf(cur - 50)
	var t1: float = d * (float(pl[0]) - float(npc[0]) + 50.0)
	var t2: float = d * (float(pl[1]) - float(npc[1]) + 50.0)
	var bribe := float(_gmst({"bribe10": "fBribe10Mod", "bribe100": "fBribe100Mod"}.get(kind, "fBribe1000Mod"), 0.0))
	var t3: float = d * (float(pl[2]) - float(npc[2]) + 50.0) + bribe
	var min_chance := float(_gmst("iPerMinChance", 5))
	var min_change := float(_gmst("iPerMinChange", 1))
	var roll_mult := float(_gmst("fPerDieRollMult", 0.15))
	var temp_mult := float(_gmst("fPerTempMult", 1.0))
	var x := 0.0
	var y := 0.0
	var success := false
	match kind:
		"admire":
			t1 = maxf(min_chance, t1)
			success = roll <= t1
			var c := floorf(roll_mult * (t1 - roll))
			x = maxf(min_change, c) if success else c
		"intimidate":
			t2 = maxf(min_chance, t2)
			success = roll <= t2
			var r := floorf(t2 - roll) if float(roll) != t2 else 1.0
			if roll <= t2:
				var s := floorf(r * roll_mult * temp_mult)
				set_ai_setting(a, "flee", ai_setting(a, "flee") + int(maxf(min_change, s)))
				set_ai_setting(a, "fight", ai_setting(a, "fight") + int(minf(-min_change, -s)))
			var c2 := -absf(floorf(r * roll_mult))
			if success:
				if absf(c2) < min_change:
					x = min_change
					y = x
				else:
					x = -floorf(c2 * temp_mult)
					y = c2
			else:
				x = floorf(c2 * temp_mult)
				y = c2
		"taunt":
			t1 = maxf(min_chance, t1)
			success = roll <= t1
			var c3 := absf(floorf(t1 - roll))
			if success:
				var s2 := c3 * roll_mult * temp_mult
				set_ai_setting(a, "flee", ai_setting(a, "flee") + mini(-int(min_change), int(-s2)))
				set_ai_setting(a, "fight", ai_setting(a, "fight") + maxi(int(min_change), int(s2)))
			x = floorf(-c3 * roll_mult)
			if success and absf(x) < min_change:
				x = -min_change
		_:
			t3 = maxf(min_chance, t3)
			success = roll <= t3
			var c4 := floorf((t3 - roll) * roll_mult)
			x = maxf(min_change, c4) if success else c4
	var temp: int
	var perm: int
	if kind == "intimidate":
		temp = int(x)
		if cur + temp > 100:
			temp = 100 - cur
		elif cur + temp < 0:
			temp = -cur
		perm = -int(temp / temp_mult) if success else int(y)
	else:
		temp = int(x * temp_mult)
		if cur + temp > 100:
			temp = 100 - cur
		elif cur + temp < 0:
			temp = -cur
		perm = int(temp / temp_mult)
	return {"success": success, "temp": temp, "perm": perm}

## persuade: zmiana postawy, łapówka, odpowiedź z „Admire Success” itd.
func persuade(kind: String, roll := -1) -> Dictionary:
	if actor.is_empty() or not actor.npc:
		return {}
	var r := persuasion_change(kind, roll if roll >= 0 else randi() % 100)
	_update_original_disposition()
	var temp := int(r.temp)
	var perm := int(r.perm)
	if temp > 0 and perm > 0 and original_disp + perm + permanent_change < 0:
		perm = -(original_disp + permanent_change)
	current_disp += temp
	set_base_disposition(actor, current_disp)
	permanent_change += perm
	main.skill_used(SK_SPEECHCRAFT, "speechcraft_success" if bool(r.success) else "speechcraft_fail")
	if bool(r.success):
		var amount: int = int({"bribe10": 10, "bribe100": 100, "bribe1000": 1000}.get(kind, 0))
		if amount > 0:
			var inv = main.interaction.inventory
			inv.remove("player", {}, "gold_001", amount)
			inv.add(actor.sid, records.record("npc", actor.base), "gold_001", amount)
	var t := "Bribe" if kind.begins_with("bribe") else kind.capitalize()
	_execute_topic(("%s %s" % [t, "Success" if bool(r.success) else "Fail"]).to_lower())
	return r

func gold() -> int:
	return int(main.interaction.inventory.count_of("player", {}, "gold_001"))

# --- dziennik (Journal, Quest) -------------------------------------------------------------------------

## Data wpisu (StampedJournalEntry): DaysPassed, Month, Day; bez rekordu DaysPassed (podstawowy Morrowind) –
## jak domyślne zmienne OpenMW: liczone od 1 (tu: 1 + dni gry środowiska).
func _date() -> Dictionary:
	var sc = main.scripts
	var days := int(sc.get_global("dayspassed")) if not records.record("global", "dayspassed").is_empty() \
		else 1 + int(main.envr.day if main.envr != null else 0)
	return {"day": days, "month": int(sc.get_global("month")), "day_of_month": int(sc.get_global("day"))}

## World::updateDialogueGlobals – zmienne dla dialogów o grzywnach (przestępstwa – etap 7: grzywna 0).
func update_globals() -> void:
	var bounty := int(_pst().get("bounty", 0))
	var g := gold()
	var disc := int(bounty * float(_gmst("fCrimeGoldDiscountMult", 0.75)))
	var turn := int(bounty * float(_gmst("fCrimeGoldTurnInMult", 0.9)))
	if bounty > 0:
		disc = maxi(1, disc)
		turn = maxi(1, turn)
	for kv in [["pchascrimegold", 1 if bounty <= g else 0], ["pchasgolddiscount", 1 if disc <= g else 0],
			["crimegolddiscount", disc], ["crimegoldturnin", turn], ["pchasturnin", 1 if turn <= g else 0]]:
		if not records.record("global", kv[0]).is_empty():
			main.scripts.set_global(kv[0], float(kv[1]))

func _journal_info(quest: String, index: int) -> Dictionary:
	for info in dialogue(quest).get("infos", []):
		if int(info.get("disposition", 0)) == index and String(info.get("quest", "")) != "name":
			return info
	for info in dialogue(quest).get("infos", []):
		if int(info.get("disposition", 0)) == index:
			return info
	return {}

func quest_name(quest: String) -> String:
	for info in dialogue(quest).get("infos", []):
		if String(info.get("quest", "")) == "name":
			var t := String(info.get("text", ""))
			return main.loc.info_text(quest, String(info.get("id", "")), t) if main.loc != null else t
	return ""

func _quest(q: String) -> Dictionary:
	var qs: Dictionary = _ds().quests
	if not qs.has(q):
		qs[q] = {"finished": false, "infos": []}
	return qs[q]

## Journal (addEntry): wpis z datą, indeks zadania, zakończenie/wznowienie; nieznany indeks – tylko indeks
## (jak OpenMW: „Invoking Journal with a non-existing index is allowed”). who – aktor (podstawienia w tekście).
func add_entry(quest: String, index: int, who := {}) -> void:
	var q := quest.to_lower()
	var info := _journal_info(q, index)
	if info.is_empty() or String(dialogue(q).get("type", "")) != "journal":
		if int(state.journal.get(q, 0)) < index:
			state.journal[q] = index
		return
	var iid := String(info.get("id", ""))
	for e in _ds().entries:
		if String(e.get("quest", "")) == q and String(e.get("info", "")) == iid:
			if int(state.journal.get(q, 0)) < index:
				state.journal[q] = index
				_notify_journal()
			return
	var qq := _quest(q)
	var status := String(info.get("quest", ""))
	if status == "finished" or status == "restart":
		qq["finished"] = status == "finished"
	if index > int(state.journal.get(q, 0)):
		state.journal[q] = index
	if not iid in qq["infos"]:
		qq["infos"].append(iid)
	if status == "restart":
		var name := quest_name(q)
		for other in _ds().quests:
			if bool(_ds().quests[other].get("finished", false)) and quest_name(String(other)).to_lower() == name.to_lower():
				_ds().quests[other]["finished"] = false
	var text := String(info.get("text", ""))
	if main.loc != null:
		text = main.loc.info_text(q, iid, text, bool(who.get("rec", {}).get("female", false)) if not who.is_empty() else false,
				bool(_pst().get("female", false)))
	text = fix_defines(text, who, not who.is_empty())
	if not text.is_empty():
		var e2 := {"quest": q, "info": iid, "text": text, "actor": actor_name(who) if not who.is_empty() else ""}
		e2.merge(_date())
		_ds().entries.append(e2)
		_notify_journal()

func set_journal_index(quest: String, index: int) -> void:
	state.journal[quest.to_lower()] = index

func _notify_journal() -> void:
	var t := gmst_text("sJournalEntry", "Your journal has been updated.")
	if actor.is_empty():
		main.show_message_box(t, [])
	else:
		message(t)

## Dziennik tematów (Journal::addTopic) – odpowiedź z tematu „topic” z nazwą rozmówcy.
func add_topic_entry(topic: String, info: Dictionary, who: Dictionary) -> void:
	var t: Dictionary = _ds().topics
	if not t.has(topic):
		t[topic] = []
	var iid := String(info.get("id", ""))
	for e in t[topic]:
		if String(e.get("info", "")) == iid and String(e.get("actor", "")) == actor_name(who):
			return
	t[topic].append({"info": iid, "text": info_text(topic, info, who), "actor": actor_name(who)})

## ClearInfoActor: usuwa ostatnią odpowiedź tego aktora z dziennika tematu (removeLastAddedTopicResponse).
func clear_info_actor(who: Dictionary) -> void:
	if who.is_empty() or actor.is_empty() or who.sid != actor.sid or last_topic.is_empty():
		return
	var t: Dictionary = _ds().topics
	var lst: Array = t.get(last_topic, [])
	var name := actor_name(who)
	for i in range(lst.size() - 1, -1, -1):
		if String(lst[i].get("actor", "")) == name:
			lst.remove_at(i)
			break
	if lst.is_empty():
		t.erase(last_topic)

## Zadania do okna dziennika: [{id, name, finished, index, entries: [...]}] – kolejność pierwszego wpisu.
func quests_view() -> Array:
	var out := []
	var seen := {}
	for e in _ds().entries:
		var q := String(e.get("quest", ""))
		if seen.has(q):
			out[seen[q]].entries.append(e)
			continue
		seen[q] = out.size()
		out.append({"id": q, "name": quest_name(q), "finished": bool(_ds().quests.get(q, {}).get("finished", false)),
			"index": int(state.journal.get(q, 0)), "entries": [e]})
	return out

# --- raport --------------------------------------------------------------------------------------------

func report() -> Dictionary:
	return {"partial": partial, "unknown_topics": unknown_topics.keys(), "dialogues": _data.size()}
