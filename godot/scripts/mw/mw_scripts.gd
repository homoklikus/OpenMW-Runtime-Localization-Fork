extends RefCounted
## Maszyna skryptów MWScript (etap 5) – wykonuje drzewa składni z konwertera (world/records/script.json),
## jak OpenMW (apps/openmw/mwscript): skrypty globalne (startowe: „main” + SSCR, StartScript) i lokalne (skrypty
## obiektów we wczytanych komórkach – także wyłączonych) co klatkę; zmienne lokalne obiektów i skryptów
## globalnych oraz dziennik w GameState (zapis gry). Funkcje wdrażane grupami; nieobsługiwane są zgłaszane
## (raport: unsupported/errors) i zwracają 0 / nic nie robią.

const MAX_LOOP := 10000

var records          # record(file, id)
var state            # MWGameState
var game             # main.gd – świat, gracz, interakcje, okna
var db
var _scripts := {}   # id → rekord skryptu (cache)
var unsupported := {}            # nazwa funkcji → liczba wywołań
var errors := {}                 # opis → liczba
var calls := {}                  # nazwa funkcji → liczba wywołań (obsługiwanych)
var partial := {}                # funkcje zależne od późniejszych etapów – zwracają stan „spoczynku” (0)
## Zdarzenia walki/AI (etapy 7–8): bez walki i śmierci ich poprawna wartość to 0.
const IDLE_ZERO := []
## Funkcje bez argumentów, które skrypty zapisują jak zmienne (bez nawiasów).
const BARE_FUNCTIONS := ["saydone", "getaipackagedone", "onactivate", "menumode", "getbuttonpressed", "cellchanged",
	"getsecondspassed", "ondeath", "onknockout", "onmurder", "getpcsleep",
	"getpcjumping", "getstandingpc", "getcurrenttime", "getdisabled", "getinterior", "getcurrentaipackage",
	"getweapondrawn", "getspellreadied", "getpccrimelevel", "random100", "getlevel", "gethealth", "getpcrank",
	"getdeadcount", "getlocked", "getscale", "getpcinjail", "getpctraveling", "getwaterlevel"]
var delta := 0.0
var button_pressed := -1
var cell_changed := false
var activated := {}              # sid → true (aktywowany w tej klatce; OnActivate)
var warnings := {}               # ostrzeżenia jak kompilator OpenMW (nieznana nazwa w wyrażeniu = liczba)
var _inv_counts := {}            # przedmiot ze skryptem u gracza → liczba w poprzedniej klatce (OnPCAdd)
var _refindex = null
var frame := 0

class Ctx:
	var sid := ""                # referencja (pusta dla skryptów globalnych)
	var base := ""               # id rekordu obiektu
	var scr := ""                # id skryptu
	var key := ""                # klucz zmiennych lokalnych w GameState
	var node: Node = null
	var stop := false
	var failed := false          # wykonanie przerwane błędem (ScriptManager::run → false)

func _init(records_source, game_state, game_main, world_db) -> void:
	records = records_source
	state = game_state
	game = game_main
	db = world_db

# --- dane --------------------------------------------------------------------------------------------------

func script_rec(id: String) -> Dictionary:
	var k := id.to_lower()
	if not _scripts.has(k):
		_scripts[k] = records.record("script", k)
	return _scripts[k]

func uses(id: String, fname: String) -> bool:
	return fname in (script_rec(id).get("functions", []) as Array)

func refindex() -> Dictionary:
	if _refindex == null:
		var d = db._read_json(db.data_root.path_join("world/refindex.json"))
		_refindex = d if d is Dictionary else {}
	return _refindex

func _sc() -> Dictionary:
	if not state.get("scripts") is Dictionary or state.scripts.is_empty():
		state.scripts = {"running": [], "locals": {}, "started": false}
	return state.scripts

## Nowa gra: skrypty startowe – „main” (jak GlobalScripts::addStartup) i rekordy SSCR.
func start_new_game() -> void:
	inactive.clear()
	var sc := _sc()
	if sc.get("started", false):
		return
	sc["started"] = true
	var ids := []
	if not script_rec("main").is_empty():
		ids.append("main")
	for id in records._all("startscript"):
		ids.append(String(records._all("startscript")[id].get("script", id)).to_lower())
	for id in ids:
		start(id)

func start(id: String) -> void:
	var k := id.to_lower()
	var sc := _sc()
	if script_rec(k).is_empty():
		_err("StartScript: brak skryptu %s" % k)
		return
	if not k in sc.running:
		sc.running.append(k)

func stop(id: String) -> void:
	_sc().running.erase(id.to_lower())

func running(id: String) -> bool:
	return id.to_lower() in _sc().running

func _locals(key: String) -> Dictionary:
	var l: Dictionary = _sc().locals
	if not l.has(key):
		l[key] = {}
	return l[key]

func _err(msg: String) -> void:
	errors[msg] = int(errors.get(msg, 0)) + 1
	if int(errors[msg]) == 1:
		print("MWGODOT_SCRIPT_ERROR ", msg)

func _unsupported(fname: String) -> void:
	unsupported[fname] = int(unsupported.get(fname, 0)) + 1
	if int(unsupported[fname]) == 1:
		print("MWGODOT_SCRIPT_UNSUPPORTED ", fname)

# --- wykonanie ---------------------------------------------------------------------------------------------

## Jedna klatka: skrypty globalne, potem lokalne obiektów we wczytanych komórkach.
var clock := 0.0                 # czas gry skryptów (s) – kwestie Say, liczniki niezależne od zegara systemowego

func tick(dt: float, local_refs: Array) -> void:
	delta = dt
	clock += dt
	frame += 1
	# kolejność jak Engine::frame: najpierw skrypty lokalne (obiekty, ekwipunek gracza), potem globalne
	for n in local_refs:
		if not is_instance_valid(n):
			continue
		var base := String(n.get_meta("mw_base", "")).to_lower()
		var o: Dictionary = db.get_object(base)
		var sid := String(o.get("script", "")).to_lower()
		if sid.is_empty():
			continue
		var c := Ctx.new()
		c.sid = String(n.get_meta("mw_sid", ""))
		c.base = base
		c.scr = sid
		c.key = c.sid
		c.node = n
		if inactive.has(sid + "|" + c.sid):
			continue
		run(c)
		if c.failed:
			inactive[sid + "|" + c.sid] = true
	# skrypty przedmiotów w ekwipunku gracza (OpenMW: LocalScripts dla zawartości gracza); OnPCAdd przy przybyciu
	var now := {}
	var scr_of := {}
	for e in game.player_scripted_items():
		var iid := String(e[0])
		now[iid] = int(e[2])
		scr_of[iid] = String(e[1])
		if int(e[2]) > int(_inv_counts.get(iid, 0)):
			set_event_var("inv:" + iid, String(e[1]), "onpcadd")
	for iid in now:
		var c := Ctx.new()
		c.base = iid
		c.scr = String(scr_of[iid])
		c.key = "inv:" + iid
		c.sid = ""
		if inactive.has(c.scr + "|" + c.key):
			continue
		run(c)
		if c.failed:
			inactive[c.scr + "|" + c.key] = true
	_inv_counts = now
	for id in (_sc().running as Array).duplicate():
		var c := Ctx.new()
		c.scr = id
		c.key = "global:" + id
		run(c)
		if c.failed:
			stop(id)                        # GlobalScripts::run: błąd → mRunning = false
	activated.clear()
	cell_changed = false
	# World::update: „podróż” trwa jedną klatkę skryptów; „więzienie” – do zamknięcia okna więzienia (tu: klatka)
	state.player.erase("traveling")
	state.player.erase("in_jail")

## Przedmiot przeszedł ze świata do gracza: zmienne lokalne skryptu idą z nim (RefData przenoszone z obiektem).
func item_to_player(from_sid: String, item_id: String) -> void:
	var src: Dictionary = _sc().locals.get(from_sid, {})
	if not src.is_empty() and not _sc().locals.has("inv:" + item_id.to_lower()):
		_sc().locals["inv:" + item_id.to_lower()] = src.duplicate()

## Zmienne zdarzeń ustawiane przez silnik (OpenMW: Locals::setVarByInt – tylko gdy skrypt ją deklaruje; skrypt sam
## ją zeruje): OnPCAdd (ContainerStore::add do gracza), OnPCEquip (InventoryWindow), OnPCDrop (World::PCDropped),
## OnPCHitMe (Npc/Creature::onHit od gracza), OnPCRepair (Repair).
func set_event_var(key: String, script_id: String, var_name: String, value := 1.0) -> bool:
	if script_id.is_empty() or _var_type(script_id, var_name).is_empty():
		return false
	_locals(key)[var_name] = value
	return true

func _item_script(item_id: String) -> String:
	for e in game.player_scripted_items():
		if String(e[0]) == item_id.to_lower():
			return String(e[1])
	return String(db.get_object(item_id.to_lower()).get("script", "")).to_lower()

## Gracz założył przedmiot: OnPCEquip = 1.
func item_equipped(item_id: String) -> void:
	set_event_var("inv:" + item_id.to_lower(), _item_script(item_id), "onpcequip")

## Gracz upuścił przedmiot (nowa referencja w świecie): zmienne lokalne idą z przedmiotem, OnPCDrop = 1.
func item_dropped(item_id: String, new_sid: String) -> void:
	var k := "inv:" + item_id.to_lower()
	var src: Dictionary = _sc().locals.get(k, {})
	if not src.is_empty():
		_sc().locals[new_sid] = src.duplicate()
	set_event_var(new_sid, _item_script(item_id), "onpcdrop")

## Gracz trafił aktora (Npc/Creature::onHit): OnPCHitMe = 1 w skrypcie ofiary.
func actor_hit_by_player(sid: String, base: String) -> void:
	set_event_var(sid, String(db.get_object(base.to_lower()).get("script", "")).to_lower(), "onpchitme")

## Skrypt wyniku odpowiedzi (BNAM): w kontekście rozmówcy – jego zmienne lokalne (DialogueManager::executeScript).
func run_dialogue(body: Array, who: Dictionary) -> void:
	var c := Ctx.new()
	c.sid = String(who.get("sid", ""))
	c.base = String(who.get("base", ""))
	c.scr = String(who.get("script", ""))
	c.key = c.sid
	c.node = who.get("node")
	_exec(body, c)

func run(c: Ctx) -> void:
	var sc := script_rec(c.scr)
	if sc.is_empty():
		return
	_exec(sc.get("body", []), c)

func _exec(body: Array, c: Ctx) -> void:
	for st in body:
		if c.stop:
			return
		match String(st[0]):
			"set":
				_assign(st[1], _eval(st[2], c), c)
			"if":
				var done := false
				for br in st[1]:
					if _truthy(_eval(br[0], c)):
						_exec(br[1], c)
						done = true
						break
				if not done:
					_exec(st[2], c)
			"while":
				var n := 0
				while not c.stop and _truthy(_eval(st[1], c)):
					_exec(st[2], c)
					n += 1
					if n >= MAX_LOOP:
						_err("%s: pętla while przerwana po %d obiegach" % [c.scr, MAX_LOOP])
						break
			"return":
				c.stop = true
			"call":
				_call(st[1], String(st[2]), st[3], c)

static func _truthy(v) -> bool:
	return float(v) != 0.0 if (v is float or v is int) else (v != null and str(v) != "")

# --- zmienne -----------------------------------------------------------------------------------------------

func _var_type(script_id: String, name: String) -> String:
	return String((script_rec(script_id).get("locals", {}) as Dictionary).get(name, ""))

func _global_rec(name: String) -> Dictionary:
	return records.record("global", name)

## Zmienne czasu (DateTimeManager): GameHour – bieżąca godzina świata, DaysPassed – licznik dni (znacznik czasu
## TimeStamp); Day/Month/Year – kalendarz (zmieniany o północy i przez GameHour ≥ 24 – setHour → setDay).
const DAYS_PER_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

func _days_passed_base() -> float:
	return float(_global_rec("dayspassed").get("value", 1.0))

func get_global(name: String) -> float:
	var k := name.to_lower()
	if game != null and game.get("envr") != null:
		if k == "gamehour":
			return float(game.envr.game_hour)
		if k == "dayspassed" and not _global_rec(k).is_empty():
			return float(game.envr.day) + _days_passed_base()
	if state.globals.has(k):
		return float(state.globals[k])
	return float(_global_rec(k).get("value", 0.0))

func set_global(name: String, v: float) -> void:
	var k := name.to_lower()
	if game != null and game.get("envr") != null:
		if k == "gamehour":
			# DateTimeManager::setHour: ujemna → 0; pełne doby przesuwają kalendarz (nie DaysPassed)
			var h := maxf(0.0, v)
			var days := int(floorf(h / 24.0))
			game.envr.game_hour = h - 24.0 * days
			if days > 0:
				calendar_add_days(days)
			game.envr.apply()
			return
		if k == "dayspassed" and not _global_rec(k).is_empty():
			game.envr.day = int(v - _days_passed_base())
			return
	var t := String(_global_rec(k).get("type", "f"))
	state.globals[k] = float(int(v)) if t in ["s", "l", "short", "long"] else v

## DateTimeManager::setDay: dzień kalendarza z przejściem miesięcy i lat.
func calendar_add_days(n: int) -> void:
	var day := int(get_global("day")) + n
	var month := int(get_global("month"))
	var year := int(get_global("year"))
	while day > int(DAYS_PER_MONTH[clampi(month, 0, 11)]):
		day -= int(DAYS_PER_MONTH[clampi(month, 0, 11)])
		month += 1
		if month > 11:
			month = 0
			year += 1
	set_global("day", day)
	set_global("month", month)
	set_global("year", year)

func _read_var(name: String, c: Ctx):
	var k := name.to_lower()
	if not _var_type(c.scr, k).is_empty():
		return float(_locals(c.key).get(k, 0.0))
	if not _global_rec(k).is_empty():
		return get_global(k)
	return null

func _assign(target: Array, v, c: Ctx) -> void:
	var fv := float(v) if (v is float or v is int) else 0.0
	if target[0] == "id":
		var k := String(target[1]).to_lower()
		var t := _var_type(c.scr, k)
		if not t.is_empty():
			_locals(c.key)[k] = float(int(fv)) if t != "float" else fv
		elif not _global_rec(k).is_empty():
			set_global(k, fv)
		else:
			_err("%s: nieznana zmienna %s" % [c.scr, k])
	elif target[0] == "member":
		var tc := _member_ctx(String(target[1]))
		if tc == null:
			_err("%s: brak obiektu %s (zmienna %s)" % [c.scr, target[1], target[2]])
			return
		var k2 := String(target[2]).to_lower()
		var t2 := _var_type(tc.scr, k2)
		_locals(tc.key)[k2] = float(int(fv)) if t2 != "float" else fv

## Kontekst zmiennych innego obiektu ("obiekt".zmienna) albo skryptu globalnego (Skrypt.zmienna).
func _member_ctx(obj: String) -> Ctx:
	var o := obj.to_lower()
	var c := Ctx.new()
	if not script_rec(o).is_empty() and db.get_object(o).is_empty():
		c.scr = o
		c.key = "global:" + o
		return c
	var r := resolve(o)
	if r.is_empty():
		return null
	c.sid = r.sid
	c.base = o
	c.scr = String(db.get_object(o).get("script", "")).to_lower()
	c.key = r.sid
	return c

# --- odniesienia do obiektów -------------------------------------------------------------------------------

## Referencja obiektu o danym id: najpierw wczytane komórki, potem indeks świata (World::searchPtr).
func resolve(id: String) -> Dictionary:
	var k := id.to_lower()
	if k == "player":
		return {"sid": "player", "node": game.player}
	var n: Node = game.find_ref_by_base(k)
	if n != null:
		return {"sid": String(n.get_meta("mw_sid")), "node": n}
	var e: Dictionary = refindex().get(k, {})
	if not e.is_empty():
		return {"sid": String(e.sid), "node": null, "cell": String(e.cell)}
	return {}

## Pakiety AI ze skryptów (OpenMW mwscript/aiextensions.cpp): argumenty jak w Morrowindzie.
func _ai_function(fname: String, t: Dictionary, args: Array, c: Ctx):
	var m = game.main
	var n = t.get("node")
	var is_get := fname.begins_with("get")
	if m.get("ai") == null or n == null or not is_instance_valid(n) or not n.has_meta("mw_actor"):
		return 0.0 if is_get else null
	match fname:
		"getaipackagedone":
			return 1.0 if bool(m.ai.ai_state(n).get("done", false)) else 0.0
		"getcurrentaipackage":
			return float(m.ai.current_type(n))
		"aiwander":
			var idle := []
			for i in 8:
				idle.append(int(_num(args, 3 + i, c, 0)))
			m.ai.stack(n, {"type": "wander", "distance": _num(args, 0, c), "duration": _num(args, 1, c),
				"time_of_day": _num(args, 2, c), "idle": idle, "repeat": _num(args, 11, c, 0) != 0.0})
		"aitravel":
			m.ai.stack(n, {"type": "travel", "pos": [_num(args, 0, c), _num(args, 1, c), _num(args, 2, c)],
				"repeat": _num(args, 3, c, 0) != 0.0})
		"aiescort", "aifollow":
			m.ai.stack(n, {"type": "escort" if fname == "aiescort" else "follow", "target": _str(args, 0).to_lower(),
				"duration": _num(args, 1, c), "pos": [_num(args, 2, c), _num(args, 3, c), _num(args, 4, c)],
				"repeat": _num(args, 5, c, 0) != 0.0})
		"aiescortcell", "aifollowcell":
			m.ai.stack(n, {"type": "escort" if fname == "aiescortcell" else "follow", "target": _str(args, 0).to_lower(),
				"cell": _str(args, 1), "duration": _num(args, 2, c),
				"pos": [_num(args, 3, c), _num(args, 4, c), _num(args, 5, c)], "repeat": _num(args, 6, c, 0) != 0.0})
		"aiactivate":
			m.ai.stack(n, {"type": "activate", "target": _str(args, 0).to_lower(), "repeat": _num(args, 1, c, 0) != 0.0})
	return null

func _fighter(t: Dictionary) -> Dictionary:
	var m = game.main
	if t.is_empty() or m.get("combat") == null:
		return {}
	if String(t.get("sid", "")) == "player":
		return m.combat.player_fighter()
	var n = t.get("node")
	if n != null and is_instance_valid(n):
		return m.combat.fighter_of(n)
	var f: Dictionary = m.fighter_by_sid(String(t.get("sid", ""))) if m.has_method("fighter_by_sid") else {}
	if not f.is_empty():
		return f
	# obiekt w nieaktywnej komórce (World::searchPtr): statystyki w GameState.actors[sid], użyte po wczytaniu
	var base := String(t.get("base", "")).to_lower()
	var ty := String(db.get_object(base).get("type", ""))
	if ty == "NPC_" or ty == "CREA":
		var kind := "npc" if ty == "NPC_" else "creature"
		return {"kind": kind, "sid": String(t.sid), "base": base, "node": null,
			"rec": records.record("npc" if kind == "npc" else "creature", base)}
	return {}

var _stats = null

func stats():
	if _stats == null:
		_stats = preload("res://scripts/mw/mw_actor_stats.gd").new(game.main)
	return _stats

const ATTR_LIST := ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
const SKILL_LIST := ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear",
	"athletics", "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration",
	"alchemy", "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman",
	"mercantile", "speechcraft", "handtohand"]
const DYN_LIST := ["health", "magicka", "fatigue"]

## Rodziny statystyk (statsextensions.cpp): Get/Set/Mod atrybutów i umiejętności, Get/Set/Mod/ModCurrent zdrowia,
## magii, kondycji, Get…GetRatio, Get/Set/Mod efektów (Resist*, WaterWalking…), Get/SetLevel. null – inna funkcja.
func _stat_family(fname: String, ref, args: Array, c: Ctx):
	var op := ""
	var rest := ""
	for pre in ["modcurrent", "get", "set", "mod"]:
		if fname.begins_with(pre):
			op = pre
			rest = fname.substr(pre.length())
			break
	if op.is_empty():
		return null
	var ratio := false
	if op == "get" and rest.ends_with("getratio"):
		rest = rest.trim_suffix("getratio")
		ratio = true
	var kind := ""
	var idx := -1
	if rest in ATTR_LIST:
		kind = "attributes"
		idx = ATTR_LIST.find(rest)
	elif rest in SKILL_LIST:
		kind = "skills"
		idx = SKILL_LIST.find(rest)
	elif rest in DYN_LIST:
		kind = "dyn"
		idx = DYN_LIST.find(rest)
	elif stats().MAGIC_EFFECTS.has(rest):
		kind = "effect"
	elif rest == "level" and op in ["get", "set"]:
		kind = "level"
	else:
		return null
	if (op == "modcurrent" or ratio) and kind != "dyn":
		return null
	var f := _fighter(_target(ref, c))
	var S = stats()
	match kind:
		"attributes", "skills":
			match op:
				"get": return S.modified_value(f, kind, idx) if S.is_actor(f) else 0.0
				"set": S.set_base(f, kind, idx, _num(args, 0, c))
				"mod": S.mod_stat(f, kind, idx, _num(args, 0, c))
			return NONE
		"dyn":
			if ratio:
				return S.ratio(f, idx)
			match op:
				"get": return S.get_dynamic(f, idx)
				"set": S.set_dynamic(f, idx, _num(args, 0, c))
				"mod": S.mod_dynamic(f, idx, _num(args, 0, c))
				"modcurrent": S.mod_current(f, idx, _num(args, 0, c))
			return NONE
		"effect":
			match op:
				"get": return float(S.effect_value(f, rest))
				"set": S.set_effect(f, rest, int(_num(args, 0, c)))
				"mod": S.mod_effect(f, rest, int(_num(args, 0, c)))
			return NONE
		"level":
			if op == "get":
				return float(S.get_level(f))
			S.set_level(f, int(_num(args, 0, c)))
			return NONE
	return null

const NONE := "__none__"

## Indeks efektu z nazwy skryptu („sEffectFireDamage”, jak GMST) albo liczby.
func _effect_index(name: String) -> int:
	if name.is_valid_int():
		return int(name)
	var k := name.to_lower().trim_prefix("seffect")
	var all: Dictionary = records._all("magiceffect")
	for id in all:
		if String(all[id].get("name", "")).to_lower() == k:
			return int(id)
	return -1

## GetEffect, GetSpellEffects, Cast/ExplodeSpell (natychmiast, bez pocisku), RemoveSpellEffects, RemoveEffects,
## GetWeaponDrawn/GetSpellReadied (gracz), HasSoulGem, GetCommonDisease/GetBlightDisease.
func _magic_function(fname: String, t: Dictionary, args: Array, c: Ctx):
	var m = game.main
	var f := _fighter(t)
	if m.get("magic") == null or (f.is_empty() and fname != "hassoulgem"):
		return 0.0 if fname.begins_with("get") or fname.begins_with("has") else null
	var mg = m.magic
	match fname:
		"geteffect":
			return 1.0 if mg.magnitude_of(f, _effect_index(_str(args, 0))) > 0.0 else 0.0
		"getspelleffects":
			var spid := _str(args, 0).to_lower()
			for sp in mg.active(f):
				if String(sp.get("id", "")) == spid:
					return 1.0
			return 0.0
		"cast", "explodespell":
			var spid2 := _str(args, 0).to_lower()
			var sp2: Dictionary = records.record("spell", spid2)
			if sp2.is_empty():
				return null
			if f.get("kind", "") == "player":
				# OpCast/OpExplodeSpell dla gracza: tylko wybór czaru (Player::setSelectedSpell)
				if game.main.has_method("select_magic"):
					game.main.select_magic("spell", spid2)
				return null
			var tgt := f
			if fname == "cast":
				tgt = _fighter(_target(_str(args, 1), c))
			var src := {"id": spid2, "name": String(sp2.get("name", spid2)), "kind": "spell"}
			for rt in [0, 1, 2]:
				var who: Dictionary = f if rt == 0 else tgt
				if not who.is_empty():
					mg.inflict(who, f, src, mg.by_range(sp2.get("effects", []), rt), sp2)
			return null
		"removespelleffects":
			var spid3 := _str(args, 0).to_lower()
			for sp3 in mg.active(f):
				if String(sp3.get("id", "")) == spid3:
					for e in sp3.effects:
						e.time_left = 0.0
			mg.tick(f, 0.0)
			return null
		"removeeffects":
			mg._purge_effect(f, _effect_index(_str(args, 0)))
			mg.tick(f, 0.0)
			return null
		"getweapondrawn":
			return 1.0 if f.kind == "player" and bool(m.weapon_drawn) else 0.0
		"getspellreadied":
			return 1.0 if f.kind == "player" and bool(m.magic_ready) else 0.0
		"hassoulgem":
			# OpHasSoulGem: liczba kamieni z tą duszą w ekwipunku aktora (nie 0/1)
			var cr := _str(args, 0).to_lower()
			var n := 0
			var who: String = String(f.get("sid", "player")) if not f.is_empty() else "player"
			for e in m.interaction.inventory.contents(who, f.get("rec", {}) if who != "player" else {}):
				if mg.is_soul_gem(String(e.id)) and mg.soul_of(String(e.id)) == cr:
					n += int(e.count)
			return float(n)
		"getcommondisease", "getblightdisease":
			var want := 3 if fname == "getcommondisease" else 2
			var list: Array = m.player_stats().get("spells", []) if f.kind == "player" else m.magic.actor_spells(f)
			for s in list:
				if int(records.record("spell", String(s)).get("spell_type", 0)) == want:
					return 1.0
			return 0.0
	return null

func _target(ref, c: Ctx) -> Dictionary:
	if ref == null:
		if c.sid.is_empty():
			return {}
		return {"sid": c.sid, "node": c.node, "base": c.base}
	var r := resolve(String(ref))
	if not r.is_empty():
		r["base"] = String(ref).to_lower()
	return r

# --- wyrażenia ---------------------------------------------------------------------------------------------

func _eval(e, c: Ctx):
	match String(e[0]):
		"num":
			return float(e[1])
		"str":
			return String(e[1])
		"id":
			var v = _read_var(String(e[1]), c)
			if v == null and String(e[1]).to_lower() in BARE_FUNCTIONS:
				# funkcja bez argumentów zapisana bez nawiasów („if ( SayDone == 1 )”) – kompilator Morrowinda to przyjmuje
				var r = _call(null, String(e[1]).to_lower(), [], c)
				return r if r != null else 0.0
			if v == null:
				# OpenMW ExprParser::parseName: nazwa niebędąca zmienną ani obiektem → liczba (strumień, zwykle 0)
				var w := "%s: nazwa %s jako liczba" % [c.scr, e[1]]
				warnings[w] = int(warnings.get(w, 0)) + 1
				return _name_as_number(String(e[1]))
			return v
		"member":
			var tc := _member_ctx(String(e[1]))
			if tc == null:
				return 0.0
			return float(_locals(tc.key).get(String(e[2]).to_lower(), 0.0))
		"call":
			var r = _call(e[1], String(e[2]), e[3], c)
			return r if r != null else 0.0
		"ref":
			var rc := Ctx.new()
			var t := _target(e[1], c)
			rc.sid = String(t.get("sid", ""))
			rc.node = t.get("node")
			rc.base = String(e[1])
			rc.scr = c.scr
			rc.key = c.key
			return _eval(e[2], rc)
		"neg":
			return -float(_eval(e[1], c))
		"bin":
			var a := float(_eval(e[2], c))
			var b := float(_eval(e[3], c))
			match String(e[1]):
				"+": return a + b
				"-": return a - b
				"*": return a * b
				"/": return a / b if b != 0.0 else 0.0
				"==": return 1.0 if a == b else 0.0
				"!=": return 1.0 if a != b else 0.0
				"<": return 1.0 if a < b else 0.0
				"<=": return 1.0 if a <= b else 0.0
				">": return 1.0 if a > b else 0.0
				">=": return 1.0 if a >= b else 0.0
	return 0.0

## std::stringstream >> float: początkowa liczba z nazwy („1st” → 1), inaczej 0.
static func _name_as_number(t: String) -> float:
	var m := RegEx.create_from_string("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?").search(t)
	return float(m.get_string()) if m != null else 0.0

## Argument liczbowy: liczba, zmienna albo wyrażenie.
func _num(args: Array, i: int, c: Ctx, def := 0.0) -> float:
	if i >= args.size():
		return def
	var a: Array = args[i]
	if a[0] == "id":
		var v = _read_var(String(a[1]), c)
		return float(v) if v != null else def
	var r = _eval(a, c)
	return float(r) if (r is float or r is int) else def

## Argument tekstowy (id obiektu, nazwa): tekst albo identyfikator.
static func _str(args: Array, i: int) -> String:
	if i >= args.size():
		return ""
	var a: Array = args[i]
	if a[0] == "str" or a[0] == "id":
		return String(a[1])
	if a[0] == "num":
		return str(int(a[1]))
	return ""

# --- funkcje -----------------------------------------------------------------------------------------------

const AXES := {"x": 0, "y": 1, "z": 2}

const REFS := preload("res://scripts/mw/mw_script_refs.gd")

## Błąd wykonania (wyjątek w interpreterze OpenMW): skrypt przerwany w tej klatce; skrypt globalny zatrzymany
## (GlobalScripts::run: mRunning = false), lokalny wyłączony dla tego obiektu do wczytania gry (mInactive) –
## poza brakiem obiektu (MissingImplicitRefError), po którym lokalny wykona się znowu w następnej klatce.
func _fail(c: Ctx, msg: String, implicit_ref := false) -> void:
	_err(msg)
	c.stop = true
	c.failed = true
	if implicit_ref and not c.sid.is_empty():
		c.failed = false

var inactive := {}               # "skrypt|sid" → true (lokalny wyłączony po błędzie; czyszczone przy wczytaniu)

func _call(ref, fname: String, args: Array, c: Ctx):
	calls[fname] = int(calls.get(fname, 0)) + 1
	# InterpreterContext::getReferenceImp: funkcja z odniesieniem bez obiektu (skrypt globalny, brak „obiekt->”)
	if ref == null and c.sid.is_empty() and not c.key.begins_with("inv:") and String(REFS.REF.get(fname, "")) == "r":
		_fail(c, "%s: %s – brak obiektu (no implicit reference)" % [c.scr, fname], true)
		return null
	var sf = _stat_family(fname, ref, args, c)
	if sf != null:
		return null if (sf is String and sf == NONE) else sf
	match fname:
		# --- przepływ, czas, losowość
		"getsecondspassed": return delta
		"random": return float(randi() % maxi(1, int(_num(args, 0, c, 1))))
		"menumode": return 1.0 if game.menu_mode() else 0.0
		"cellchanged": return 1.0 if cell_changed else 0.0
		"getcurrenttime": return float(game.envr.game_hour)
		"getbuttonpressed":
			var b := button_pressed
			button_pressed = -1
			return float(b)
		"startscript": start(_str(args, 0)); return null
		"stopscript": stop(_str(args, 0) if args.size() > 0 else c.scr); return null
		"scriptrunning": return 1.0 if running(_str(args, 0)) else 0.0
		"messagebox":
			var parts := _format(args, c)
			var dl = game.main.dialogue
			if parts[1].is_empty() and dl != null and not dl.actor.is_empty():
				dl.message(dl.fix_defines(parts[0], dl.actor, false))      # w rozmowie – do historii okna
			else:
				game.script_message_box(parts[0], parts[1])
			return null
		# --- dziennik i rozmowy (etap 6)
		"getjournalindex": return float(int(state.journal.get(_str(args, 0).to_lower(), 0)))
		"journal":
			_dlg().add_entry(_str(args, 0), int(_num(args, 1, c)), _who(ref, c))
			return null
		"setjournalindex":
			_dlg().set_journal_index(_str(args, 0), int(_num(args, 1, c)))
			return null
		"addtopic":
			if not _dlg().add_topic(_str(args, 0)):
				_err("AddTopic: brak tematu %s" % _str(args, 0))
			return null
		"choice":
			var i := 0
			while i < args.size():
				var q := _str(args, i)
				var n := int(_num(args, i + 1, c, 1)) if i + 1 < args.size() else 1
				_dlg().add_choice(q, n)
				i += 2
			return null
		"goodbye": _dlg().goodbye(); return null
		"forcegreeting":
			var tf := _target(ref, c)
			if tf.get("node") != null and state.is_enabled(String(tf.sid)):
				game.main.open_dialogue(tf.node)
			return null
		"clearinfoactor": _dlg().clear_info_actor(_who(ref, c)); return null
		"moddisposition", "setdisposition":
			var wd := _who(ref, c)
			if not wd.is_empty() and wd.npc:
				var v := int(_num(args, 0, c))
				_dlg().set_base_disposition(wd, (_dlg().base_disposition(wd) + v) if fname == "moddisposition" else v)
			return null
		"getdisposition":
			var wg := _who(ref, c)
			return float(_dlg().derived_disposition(wg)) if not wg.is_empty() and wg.npc else 0.0
		"modreputation", "setreputation", "getreputation":
			var wr := _who(ref, c)
			if String(_target(ref, c).get("sid", "")) == "player" or (wr.is_empty() and c.sid.is_empty()):
				var pst: Dictionary = game.main.player_stats()
				if fname == "getreputation":
					return float(pst.get("reputation", 0))
				pst["reputation"] = (int(pst.get("reputation", 0)) if fname == "modreputation" else 0) + int(_num(args, 0, c))
				return null
			if wr.is_empty():
				return 0.0
			if fname == "getreputation":
				return float(_dlg().reputation_of(wr))
			_dlg()._npc_state(wr)["reputation"] = (_dlg().reputation_of(wr) if fname == "modreputation" else 0) + int(_num(args, 0, c))
			return null
		"samefaction":
			var ws := _who(ref, c)
			return 1.0 if not ws.is_empty() and _dlg().in_faction(_dlg().faction_of(ws)) else 0.0
		"getfactionreaction":
			return float(_dlg().faction_reaction(_str(args, 0), _str(args, 1)))
		"modfactionreaction", "setfactionreaction":
			var f1 := _str(args, 0).to_lower()
			var f2 := _str(args, 1).to_lower()
			var val := int(_num(args, 2, c))
			if fname == "modfactionreaction":
				val += _dlg().faction_reaction(f1, f2)
			var rx: Dictionary = _dlg()._ds().reactions
			if not rx.has(f1):
				rx[f1] = {}
			rx[f1][f2] = val
			return null
		"pcjoinfaction", "pcraiserank", "pclowerrank", "pcexpell", "pcclearexpelled", "pcexpelled", "getpcrank", \
				"modpcfacrep", "getpcfacrep", "setpcfacrep":
			return _faction_call(fname, ref, args, c)
		"getfight", "gethello", "getflee", "getalarm":
			var wa := _who(ref, c)
			return float(_dlg().ai_setting(wa, fname.substr(3), true, false)) if not wa.is_empty() else 0.0
		"setfight", "sethello", "setflee", "setalarm", "modfight", "modhello", "modflee", "modalarm":
			var wm := _who(ref, c)
			if not wm.is_empty():
				var key := fname.substr(3)
				var nv := int(_num(args, 0, c))
				if fname.begins_with("mod"):
					nv += _dlg().ai_setting(wm, key, false)
				_dlg().set_ai_setting(wm, key, nv)
			return null
		"setpccrimelevel", "modpccrimelevel":
			# OpSetPCCrimeLevel: bez ograniczenia; OpModPCCrimeLevel: max(0, …); grzywna 0 → recordCrimeId
			var pc: Dictionary = game.main.player_stats()
			var nb := int(_num(args, 0, c))
			if fname.begins_with("mod"):
				nb = maxi(0, nb + int(pc.get("bounty", 0)))
			pc["bounty"] = nb
			if nb == 0 and game.main.crime != null:
				game.main.crime.record_crime_id()
			return null
		"getpccrimelevel":
			return float(game.main.player_stats().get("bounty", 0))
		"addspell", "removespell":
			var tsp := _target(ref, c)
			if String(tsp.get("sid", "")) == "player":
				var sp: Array = game.main.player_stats().get("spells", [])
				var spid := _str(args, 0).to_lower()
				if fname == "addspell" and not spid in sp and not records.record("spell", spid).is_empty():
					sp.append(spid)
				elif fname == "removespell":
					sp.erase(spid)
				game.main.player_stats()["spells"] = sp
			else:
				# NPC/stworzenie: lista zaklęć w stanie aktora (Spells::add/remove); zdolności działają od razu
				var fs := _fighter(tsp)
				var spid2 := _str(args, 0).to_lower()
				if fs.is_empty():
					return null
				if records.record("spell", spid2).is_empty():
					_fail(c, "%s: %s – nieznane zaklęcie %s" % [c.scr, fname, spid2])
					return null
				var ast: Dictionary = game.main.combat._actor_state(fs)
				if not ast.get("spells") is Array:
					ast["spells"] = (fs.rec.get("spells", []) as Array).map(func(x): return String(x).to_lower())
				if fname == "addspell" and not spid2 in ast.spells:
					ast.spells.append(spid2)
				elif fname == "removespell":
					ast.spells.erase(spid2)
				if game.main.magic != null:
					game.main.magic.sync_dynamic(fs)
			return null
		"showmap", "filljournal":
			if fname == "filljournal":
				_unsupported(fname)
				return null
			var mk: Dictionary = _dlg()._ds()
			if not mk.get("map_markers") is Array:
				mk["map_markers"] = []
			if not _str(args, 0) in mk["map_markers"]:
				mk["map_markers"].append(_str(args, 0))      # mapa świata – etap 10 (znaczniki zapamiętane)
			return null
		# --- obiekty: włączenie, aktywacja, usuwanie
		"getdisabled":
			var t := _target(ref, c)
			return 0.0 if t.is_empty() else (0.0 if state.is_enabled(String(t.sid)) else 1.0)
		"enable", "disable":
			var t2 := _target(ref, c)
			if t2.is_empty() or String(t2.sid) == "player":
				_err("%s: %s bez obiektu" % [c.scr, fname]); return null
			state.set_enabled(String(t2.sid), fname == "enable")
			return null
		"setdelete":
			var t3 := _target(ref, c)
			if not t3.is_empty() and _num(args, 0, c, 1.0) != 0.0:
				state.delete_ref(String(t3.sid))
			return null
		"onactivate":
			return 1.0 if activated.has(c.sid) and ref == null else 0.0
		"ondeath", "onmurder":
			# OpOnDeath/OpOnMurder: flaga aktora (hasDied/hasBeenMurdered) trwa do odczytu i jest nim kasowana
			var td := _target(ref, c)
			var fd := _fighter(td)
			if fd.is_empty() or fd.kind == "player" and fname == "onmurder":
				return 0.0
			var hd: Dictionary = game.main.player_stats() if fd.kind == "player" else game.main.combat._actor_state(fd)
			var flag := "has_died" if fname == "ondeath" else "murdered"
			if bool(hd.get(flag, false)):
				hd.erase(flag)
				return 1.0
			return 0.0
		"onknockout":
			# OpOnKnockout: knockedDownOneFrame (Actors::update – dokładnie jedna klatka po powaleniu)
			var fk := _fighter(_target(ref, c))
			if fk.is_empty() or fk.kind == "player":
				return 0.0
			return 1.0 if bool(game.main.combat._actor_state(fk).get("knocked_one", false)) else 0.0
		"getattacked":
			# stats.getAttacked: trafiony przez aktora, z którym nie walczył (Npc/Creature::onHit); kasowane po
			# spłacie przestępstwa (calm_witnesses)
			var fa := _fighter(_target(ref, c))
			if fa.is_empty() or fa.kind == "player":
				return 0.0
			return 1.0 if bool(game.main.combat._actor_state(fa).get("attacked", false)) else 0.0
		"gettarget":
			# OpGetTarget: cel walki (id rekordu) == argument; „player” także podczas powitania
			var tt := _target(ref, c)
			var want := _str(args, 0).to_lower()
			var nt = tt.get("node")
			if tt.is_empty() or String(tt.sid) == "player" or nt == null or not is_instance_valid(nt) or game.main.ai == null:
				return 0.0
			var cur: String = game.main.ai.combat_target(nt)
			if not cur.is_empty():
				if cur == "player":
					return 1.0 if want == "player" else 0.0
				var tn: Node = game.main.ai._target_of({"target": cur})
				return 1.0 if tn != null and String(tn.get_meta("mw_base", "")).to_lower() == want else 0.0
			return 1.0 if want == "player" and String(game.main.ai._rt(nt).get("greet", "")) == "progress" else 0.0
		"getdeadcount":
			return float(int(_dlg()._ds().deaths.get(_str(args, 0).to_lower(), 0)))
		"activate":
			var t4 := _target(ref, c)
			if t4.get("node") != null:
				game.activate_default(t4.node)
			return null
		"getlocked":
			var t5 := _target(ref, c)
			return 1.0 if not t5.is_empty() and t5.get("node") != null and game.interaction.lock_level(t5.node) > 0 else 0.0
		"lock":
			var t6 := _target(ref, c)
			if not t6.is_empty():
				state.set_lock(String(t6.sid), int(_num(args, 0, c, 100)) if args.size() > 0 else 100)
			return null
		"unlock":
			var t7 := _target(ref, c)
			if not t7.is_empty():
				state.set_lock(String(t7.sid), 0)
			return null
		# --- przedmioty
		"additem", "removeitem", "getitemcount":
			var t8 := _target(ref, c)
			if t8.is_empty():
				return 0.0
			var who := String(t8.sid)
			var rec := _inv_record(t8)
			var item := _str(args, 0).to_lower()
			var inv = game.interaction.inventory
			if fname == "getitemcount":
				return float(inv.count_of(who, rec, item))
			var n := int(_num(args, 1, c, 1))
			var g: Array = game.interaction.normalize_gold(item, n)
			if fname == "additem":
				inv.add(who, rec, g[0], g[1])
			else:
				inv.remove(who, rec, g[0], g[1])
			return null
		"placeatpc", "placeatme", "placeitem":
			game.script_place(fname, _str(args, 0), int(_num(args, 1, c, 1)), _target(ref, c), args, c, self)
			return null
		# --- pozycja i obrót (jednostki i stopnie Morrowinda)
		"getpos", "getangle", "getstartingpos", "getstartingangle":
			var t9 := _target(ref, c) if ref != null or not c.sid.is_empty() else {}
			if t9.is_empty():
				return 0.0
			return game.script_get_transform(t9, fname, int(AXES.get(_str(args, 0).to_lower(), 0)))
		"setpos", "setangle", "position", "positioncell", "setatstart":
			game.script_set_transform(_target(ref, c), fname, args, c, self)
			return null
		"rotate", "rotateworld":
			game.script_rotate(_target(ref, c), _str(args, 0).to_lower(), _num(args, 1, c) * delta)
			return null
		"getdistance":
			var a := _target(ref, c)
			var b := resolve(_str(args, 0))
			return game.script_distance(a, b)
		"getpccell":
			return 1.0 if game.player_cell_name().to_lower().begins_with(_str(args, 0).to_lower()) else 0.0
		# --- dźwięk
		"playsound", "playsoundvp", "playsound3d", "playsound3dvp", "playloopsound3d", "playloopsound3dvp", "say":
			var snd := _str(args, 0)
			var t10 := _target(ref, c)
			if fname == "say":
				# głos (Sound/Vo…) z napisem jak w OpenMW przy włączonych napisach – bez okna (nie wstrzymuje
				# skryptów); SayDone po czasie trwania nagrania
				game.say(t10 if not t10.is_empty() else {"sid": c.sid, "base": c.base, "node": c.node}, snd, _str(args, 1))
				return null
			var vp := fname.ends_with("vp")
			game.script_sound(snd, t10 if fname.contains("3d") else {}, t10,
					_num(args, 1, c, 1.0) if vp else 1.0, _num(args, 2, c, 1.0) if vp else 1.0, fname.begins_with("playloop"))
			return null
		"streammusic":
			game.stream_music(_str(args, 0))
			return null
		"stopsound":
			game.stop_sound(_target(ref, c), _str(args, 0))
			return null
		"getsoundplaying":
			return 1.0 if game.sound_playing(_target(ref, c), _str(args, 0)) else 0.0
		"dontsaveobject": return null
		"getspell":
			var t11 := _target(ref, c)
			var spell := _str(args, 0).to_lower()
			if String(t11.get("sid", "")) == "player" or t11.is_empty() and c.sid.is_empty():
				return 1.0 if spell in (game.main.player_stats().get("spells", []) as Array) else 0.0
			var f11 := _fighter(t11)
			if f11.is_empty():
				return 0.0
			return 1.0 if spell in (game.main.magic.actor_spells(f11) as Array).map(func(x): return String(x).to_lower()) else 0.0
		# --- przestępstwa (etap 8)
		"payfine", "payfinethief":
			if game.main.get("crime") != null:
				game.main.crime.pay_fine(fname == "payfine")
			return null
		"gotojail":
			if game.main.get("crime") != null:
				if game.main.dialogue_window != null and game.main.dialogue_window.visible:
					game.main.dialogue_window.close()
				game.main.crime.go_to_jail()
			return null
		"startcombat", "stopcombat":
			var tn = _target(ref, c).get("node")
			if game.main.get("ai") == null or tn == null or not is_instance_valid(tn) or not tn.has_meta("mw_actor"):
				return null
			if fname == "stopcombat":
				game.main.ai.stop_combat(tn)
			else:
				var who := _str(args, 0).to_lower()
				var tgt: Node = game.main.player if who == "player" else (game.main.script_host.find_ref_by_base(who) if game.main.script_host != null else null)
				if tgt != null:
					game.main.ai.start_combat(tn, tgt)
			return null
		# --- tworzenie postaci i sterowanie gracza (etap 9: CharGen – OpenMW controlextensions, guiextensions)
		"disableplayercontrols", "enableplayercontrols", "disableplayerfighting", "enableplayerfighting", "disableplayerjumping", "enableplayerjumping", "disableplayermagic", "enableplayermagic", "disableplayerviewswitch", "enableplayerviewswitch", "disablevanitymode", "enablevanitymode", "disableplayerlooking", "enableplayerlooking":
			var on := fname.begins_with("enable")
			game.set_control(fname.substr(6 if on else 7).replace("player", ""), on)
			return null
		"getplayercontrolsdisabled", "getplayerfightingdisabled", "getplayerjumpingdisabled", "getplayermagicdisabled", "getplayerviewswitchdisabled", "getvanitymodedisabled", "getplayerlookingdisabled":
			return 0.0 if game.control_enabled(fname.substr(3).replace("player", "").replace("disabled", "")) else 1.0
		"enablenamemenu", "enableracemenu", "enableclassmenu", "enablebirthmenu", "enablestatreviewmenu":
			game.chargen_menu(fname.substr(6).replace("menu", ""))
			return null
		"enableinventorymenu", "enablemagicmenu", "enablemapmenu", "enablestatsmenu", "enablerest", "enablelevelupmenu":
			game.enable_menu(fname.substr(6).replace("menu", ""))
			return null
		"disablerest":
			game.disable_menu("rest")
			return null
		"showrestmenu":
			game.show_rest_menu()
			return null
		"changeweather":
			game.change_weather(_str(args, 0), int(_num(args, 1, c)))
			return null
		# --- start gry / ekran (OpenMW miscextensions: OpPlayBink, OpFadeIn, OpFadeOut, OpFadeTo) ---
		"playbink":
			game.play_bink(_str(args, 0), _num(args, 1, c) != 0.0)
			return null
		"fadein":
			game.fade("in", _num(args, 0, c))
			return null
		"fadeout":
			game.fade("out", _num(args, 0, c))
			return null
		"fadeto":
			game.fade("to", _num(args, 1, c), _num(args, 0, c))
			return null
		"getrace":
			var tr := _target(ref, c)
			var race := ""
			if String(tr.get("sid", "")) == "player" or (tr.is_empty() and c.sid.is_empty()):
				race = String(game.main.player_stats().get("race", ""))
			else:
				race = String(records.record("npc", String(tr.get("base", ""))).get("race", ""))
			return 1.0 if race.to_lower() == _str(args, 0).to_lower() else 0.0
		"getcurrentweather":
			var wi: int = game.WEATHER_NAMES.find(String(game.envr.weather).to_lower())
			return float(maxi(wi, 0))
		"playgroup", "loopgroup":
			game.play_group(_target(ref, c), _str(args, 0).to_lower(), int(_num(args, 1, c)) if args.size() > 1 else 0, fname == "loopgroup", int(_num(args, 2, c, 1)) if args.size() > 2 else 1)
			return null
		"getstandingpc":
			return 1.0 if game.player_standing_on(_target(ref, c)) else 0.0
		"xbox": return 0.0
		"saydone":
			return 1.0 if game.say_done(_target(ref, c)) else 0.0
		# --- AI (etap 8)
		"aiwander", "aitravel", "aiescort", "aiescortcell", "aifollow", "aifollowcell", "aiactivate", "getaipackagedone", "getcurrentaipackage":
			return _ai_function(fname, _target(ref, c), args, c)
		# --- magia (etap 7d)
		"geteffect", "getspelleffects", "cast", "explodespell", "removespelleffects", "removeeffects", "getweapondrawn", "getspellreadied", "hassoulgem", "getcommondisease", "getblightdisease":
			return _magic_function(fname, _target(ref, c), args, c)
	var st_r = _state_function(fname, ref, args, c)
	if not (st_r is String and st_r == NONE_FN):
		return st_r
	if fname in IDLE_ZERO:
		partial[fname] = int(partial.get(fname, 0)) + 1
		return 0.0
	if fname == "getinterior":
		return 0.0 if game.main.interior.is_empty() else 1.0
	_unsupported(fname)
	return null

const NONE_FN := "__nofn__"
const MOVE_FLAGS := {"sneak": "force_sneak", "run": "force_run", "jump": "force_jump", "movejump": "force_move_jump"}

## Słownik stanu aktora (gracz – postać, NPC/stworzenie – GameState.actors) albo {} dla nie-aktora.
func _actor_holder(t: Dictionary) -> Dictionary:
	var f := _fighter(t)
	if f.is_empty():
		return {}
	return game.main.player_stats() if f.kind == "player" else game.main.combat._actor_state(f)

func _node_of(t: Dictionary) -> Node3D:
	if String(t.get("sid", "")) == "player":
		return game.main.player
	var n = t.get("node")
	return n if n != null and is_instance_valid(n) else null

## Stan gracza i aktorów: sen, skok, skradanie, wymuszony ruch (controlextensions.cpp), więzienie i podróż
## (World::isPlayerInJail/isPlayerTraveling), wykrycie i linia wzroku (aiextensions.cpp), wilkołak.
## NONE_FN – inna funkcja.
func _state_function(fname: String, ref, args: Array, c: Ctx):
	var m = game.main
	match fname:
		"getpcsleep":
			return 1.0 if m.rest_window != null and m.rest_window.player_sleeping() else 0.0
		"wakeuppc":
			if m.rest_window != null:
				m.rest_window.wake_up()
			return null
		"getpcjumping":
			return 1.0 if m.player != null and bool(m.player.get("jumping")) else 0.0
		"getpcsneaking":
			# MechanicsManager::isSneaking: postawa skradania (klawisz albo ForceSneak) poza wodą i lewitacją
			var p = m.player
			if p == null:
				return 0.0
			var force := bool((m.player_stats().get("move_flags", {}) as Dictionary).get("force_sneak", false))
			return 1.0 if (bool(p.want_sneak) or force) and not bool(p.swimming) and not bool(p.fly) else 0.0
		"getpcinjail":
			return 1.0 if bool(m.state.player.get("in_jail", false)) else 0.0
		"getpctraveling":
			return 1.0 if bool(m.state.player.get("traveling", false)) else 0.0
		"getforcesneak", "getforcerun", "getforcejump", "getforcemovejump":
			var h := _actor_holder(_target(ref, c))
			return 1.0 if bool((h.get("move_flags", {}) as Dictionary).get(MOVE_FLAGS[fname.substr(8)], false)) else 0.0
		"forcesneak", "forcerun", "forcejump", "forcemovejump", "clearforcesneak", "clearforcerun", "clearforcejump", \
				"clearforcemovejump":
			var h2 := _actor_holder(_target(ref, c))
			if h2.is_empty():
				return null
			if not h2.get("move_flags") is Dictionary:
				h2["move_flags"] = {}
			var on := not fname.begins_with("clear")
			var key: String = MOVE_FLAGS[fname.trim_prefix("clear").substr(5)]
			if on:
				h2.move_flags[key] = true
			else:
				h2.move_flags.erase(key)
			return null
		"getdetected":
			# isActorDetected(aktor z argumentu, obserwator): obserwator-NPC – LOS i awarenessCheck; bez obserwatora
			# (lub nie-NPC) – którykolwiek aktor w zasięgu przetwarzania
			var who := resolve(_str(args, 0))
			var an: Node3D = _node_of(who) if not who.is_empty() else null
			if an == null or m.ai == null:
				return 0.0
			var ob := _target(ref, c) if ref != null or not c.sid.is_empty() else {}
			var on2: Node3D = _node_of(ob) if not ob.is_empty() else null
			if on2 != null and String(on2.get_meta("mw_actor", "")) == "npc":
				return 1.0 if m.ai._los(on2, an) and m.ai.awareness(an, on2) else 0.0
			for nb in m.ai.actor_nodes():
				if nb == an or m.combat.is_dead(m.combat.fighter_of(nb)):
					continue
				if (nb as Node3D).global_position.distance_to(an.global_position) > PROCESSING_RANGE_M:
					continue
				if m.ai._los(nb, an) and m.ai.awareness(an, nb):
					return 1.0
			return 0.0
		"getlineofsight", "getlos":
			var src: Node3D = _node_of(_target(ref, c))
			var dst := resolve(_str(args, 0))
			var dn: Node3D = _node_of(dst) if not dst.is_empty() else null
			if src == null or dn == null or m.ai == null or not (src == m.player or src.has_meta("mw_actor")) \
					or not (dn == m.player or dn.has_meta("mw_actor")):
				return 0.0
			return 1.0 if m.ai._los(src, dn) else 0.0
		"becomewerewolf", "undowerewolf":
			var fwo := _fighter(_target(ref, c))
			if not fwo.is_empty() and fwo.kind != "creature":
				set_werewolf(fwo, fname == "becomewerewolf")
			return null
		"setwerewolfacrobatics":
			var fwa := _fighter(_target(ref, c))
			if not fwa.is_empty() and fwa.kind != "creature":
				# applyWerewolfAcrobatics: akrobatyka – setBase(baza, true), modyfikator = wartość wilkołaka − baza
				var S = stats()
				S.reset_to_base(fwa, "skills", 20)
				S.set_modifier(fwa, "skills", 20, _werewolf_value("skills", 20) - S.base_value(fwa, "skills", 20))
			return null
		"iswerewolf":
			var fw := _fighter(_target(ref, c))
			if fw.is_empty() or fw.kind == "creature":
				return 0.0
			return 1.0 if bool(_actor_holder(_target(ref, c)).get("werewolf", false)) else 0.0
		"getwerewolfkills":
			return float(int(m.player_stats().get("werewolf_kills", 0)))
	return _world_function(fname, ref, args, c)

## Obiekty i świat: Move/MoveWorld, skala, woda, stojący/zderzający się aktorzy, Hurt*, przedmioty (PlaceItemCell,
## Drop, RemoveSoulGem, HasItemEquipped, GetWeaponType), teleportacja/lewitacja, ModRegion, RaiseRank/LowerRank,
## Resurrect, GetSquareRoot, GetStat, Fall, Face. NONE_FN – inna funkcja.
func _world_function(fname: String, ref, args: Array, c: Ctx):
	var m = game.main
	match fname:
		"move", "moveworld":
			# OpMove/OpMoveWorld: prędkość × czas klatki; Move w osiach obiektu, MoveWorld – świata
			game.script_move(_target(ref, c), _str(args, 0).to_lower(), _num(args, 1, c) * delta, fname == "move")
			return null
		"getscale":
			var ts := _target(ref, c)
			return game.ref_scale(ts) if not ts.is_empty() else 0.0
		"setscale", "modscale":
			var tsc := _target(ref, c)
			if not tsc.is_empty():
				var v := _num(args, 0, c)
				game.script_set_scale(tsc, v if fname == "setscale" else game.ref_scale(tsc) + v)
			return null
		"fall":
			return null                     # OpFall: w OpenMW pusta instrukcja
		"face":
			# OpFace: pakiet AiFace (obrót do punktu x, y); gracz i nie-aktorzy – bez działania
			var tf := _target(ref, c)
			var fn = tf.get("node")
			if fn != null and is_instance_valid(fn) and fn.has_meta("mw_actor") and m.ai != null:
				m.ai.stack(fn, {"type": "face", "x": _num(args, 0, c), "y": _num(args, 1, c)}, false)
			return null
		"getwaterlevel":
			# OpGetWaterLevel: komórka gracza; zewnętrze – 0 (jak oryginał), wnętrze bez wody – −FLT_MAX
			if m.interior.is_empty():
				return 0.0
			var wl: float = m.cell_water_m("int:" + String(m.interior).to_lower())
			return -3.4028234663852886e38 if is_inf(wl) else wl * MWCoords.UNITS_PER_METER
		"setwaterlevel", "modwaterlevel":
			if m.interior.is_empty():
				_fail(c, "%s: %s w komórce zewnętrznej („Can't set water level in exterior cell”)" % [c.scr, fname])
				return null
			var key := "int:" + String(m.interior).to_lower()
			var cur: float = m.cell_water_m(key)
			var base := 0.0 if is_inf(cur) else cur * MWCoords.UNITS_PER_METER
			m.set_cell_water(key, _num(args, 0, c) + (base if fname == "modwaterlevel" else 0.0))
			return null
		"getstandingactor":
			var tn: Node = _node_of(_target(ref, c))
			return 1.0 if tn != null and not game.actors_standing_on(tn).filter(func(a): return a != m.player).is_empty() else 0.0
		"getcollidingpc", "getcollidingactor":
			return 1.0 if game.colliding(_target(ref, c), fname == "getcollidingpc") else 0.0
		"hurtstandingactor", "hurtcollidingactor":
			game.hurt_actors(_target(ref, c), _num(args, 0, c), fname == "hurtstandingactor", delta)
			return null
		"placeitemcell":
			# OpPlaceItemCell: przedmiot, komórka, x, y, z, obrót Z (stopnie); nieznana komórka – błąd
			var cell := _str(args, 1)
			var key2 := "int:" + cell.to_lower()
			var pos := Vector3(_num(args, 2, c), _num(args, 3, c), _num(args, 4, c))
			if m.db.get_cell(key2).is_empty():
				var ext := false
				for ci in m.db.cell_index():
					if not bool(ci.get("interior", false)) and String(ci.get("name", "")).to_lower() == cell.to_lower():
						ext = true
						break
				if not ext:
					_err("%s: PlaceItemCell – nieznana komórka (%s)" % [c.scr, cell])
					return null
				key2 = m.db.exterior_key(MWCoords.cell_of(MWCoords.mw_to_godot(pos)))
			state.add_dynamic(_str(args, 0).to_lower(), key2, pos, Vector3(0, 0, deg_to_rad(_num(args, 5, c))), 1)
			game.dirty = true
			return null
		"drop":
			return _drop(_target(ref, c), _str(args, 0).to_lower(), int(_num(args, 1, c)), c)
		"addsoulgem":
			# OpAddSoulGem: kamień z duszą stworzenia (nieznane stworzenie – błąd skryptu), osobna sztuka
			var fa := _fighter(_target(ref, c))
			if fa.is_empty():
				return null
			var cre := _str(args, 0).to_lower()
			if records.record("creature", cre).is_empty():
				_fail(c, "%s: AddSoulGem – nieznane stworzenie %s" % [c.scr, cre])
				return null
			m.interaction.inventory.add(String(fa.sid), fa.get("rec", {}) if fa.kind != "player" else {},
					"%s@%s" % [_str(args, 1).to_lower(), cre], 1)
			return null
		"equip":
			return _equip(_target(ref, c), _str(args, 0).to_lower())
		"removesoulgem":
			var tr := _target(ref, c)
			var fr := _fighter(tr)
			if fr.is_empty():
				return null
			var soul := _str(args, 0).to_lower()
			var inv = m.interaction.inventory
			for e in inv.contents(String(fr.sid), fr.get("rec", {})):
				if String(e.id).to_lower().get_slice("@", 1) == soul and String(e.id).contains("@"):
					inv.remove(String(fr.sid), fr.get("rec", {}), String(e.id), 1)
					break
			return null
		"hasitemequipped":
			var fe := _fighter(_target(ref, c))
			if fe.is_empty():
				return 0.0
			var want := _str(args, 0).to_lower()
			for sl in m.combat.equipment(fe).values():
				if String(sl.id).to_lower() == want:
					return 1.0
			return 0.0
		"getweapontype":
			# OpGetWeaponType: prawa ręka – typ broni; wytrych −2, sonda −3, nic/inne −1
			var fw := _fighter(_target(ref, c))
			if fw.is_empty():
				return -1.0
			var e2: Dictionary = m.combat.equipment(fw).get(16, {})
			if e2.is_empty():
				return -1.0
			match String(e2.kind):
				"weapon": return float(int(e2.rec.get("weapon_type", 0)))
				"lockpick": return -2.0
				"probe": return -3.0
			return -1.0
		"enableteleporting", "disableteleporting":
			m.state.player["teleport_enabled"] = fname.begins_with("enable")    # World::enableTeleporting (TELE)
			return null
		"enablelevitation", "disablelevitation":
			m.state.player["levitation_enabled"] = fname.begins_with("enable")  # World::enableLevitation (LEVT)
			return null
		"modregion":
			# OpModRegion: szanse pogód regionu (0..100, kolejność clear…blizzard), trwałe
			var chances := {}
			var names: Array = ["clear", "cloudy", "foggy", "overcast", "rain", "thunder", "ash", "blight", "snow", "blizzard"]
			for i in range(1, args.size()):
				if i - 1 < names.size():
					chances[names[i - 1]] = clampi(int(_num(args, i, c)), 0, 100)
			m.envr.mod_region(_str(args, 0).to_lower(), chances)
			return null
		"raiserank", "lowerrank":
			return _npc_rank(fname, _target(ref, c))
		"getsquareroot":
			var q := _num(args, 0, c)
			if q < 0.0:
				_fail(c, "%s: GetSquareRoot z liczby ujemnej" % c.scr)
				return 0.0
			return sqrt(q)
		"getstat":
			return 0.0                      # OpGetStat: w OpenMW atrapa zwracająca 0 (ta sama semantyka)
		"hitonme", "hitattemptonme":
			# OpHitOnMe/OpHitAttemptOnMe: ostatni (udany / każdy) cios tym obiektem; trafienie kasuje zapamiętany
			var hh := _actor_holder(_target(ref, c))
			var hk := "last_hit" if fname == "hitonme" else "last_hit_attempt"
			if not hh.is_empty() and String(hh.get(hk, "")) == _str(args, 0).to_lower():
				hh.erase(hk)
				return 1.0
			return 0.0
		"resurrect":
			return _resurrect(_target(ref, c))
		"turnmoonred", "turnmoonwhite":
			_missing(fname, "brak księżyców na niebie (Masser/Secunda nie są renderowane)")
			return null
	return NONE_FN

var missing := {}                # funkcja → zależność niezrealizowana (raport)

## Funkcja rozpoznana, ale zależna od systemu, którego silnik jeszcze nie ma – jawnie w raporcie, bez skutku.
func _missing(fname: String, dependency: String) -> void:
	missing[fname] = dependency
	unsupported[fname] = int(unsupported.get(fname, 0)) + 1

## OpDrop: najpierw nieużywane, potem zdjęte z ekwipunku sztuki; brak wystarczającej liczby – OpenMW i tak
## kładzie brakujące (nowe) sztuki na ziemię. Ujemna liczba – błąd skryptu, 0 – nic.
func _drop(t: Dictionary, item: String, amount: int, c: Ctx):
	var m = game.main
	if amount < 0:
		_fail(c, "%s: Drop – liczba ujemna" % c.scr)
		return null
	var f := _fighter(t)
	if amount == 0 or f.is_empty():
		return null
	var n: Node3D = _node_of(t)
	if f.kind == "player":
		var have: int = m.interaction.inventory.count_of("player", {}, item)
		var take := mini(have, amount)
		if take > 0:
			var eq: Dictionary = m.player_stats().get("equipment", {})
			var not_eq := have
			for s in eq:
				if String(eq[s].id).to_lower() == item:
					not_eq -= 1
			if take > not_eq:
				for s in eq.keys():
					if String(eq[s].id).to_lower() == item:
						m.unequip_slot(int(s))
			m.drop_item(item, take)
		for i in amount - take:
			m.state.add_dynamic(item, _ground_key(n), _ground_pos(n), Vector3.ZERO, 1)
		game.dirty = true
		return null
	var inv = m.interaction.inventory
	inv.remove(String(f.sid), f.get("rec", {}), item, amount)
	m.state.add_dynamic(item, _ground_key(n), _ground_pos(n), Vector3.ZERO, amount)
	game.dirty = true
	return null

func _ground_pos(n: Node3D) -> Vector3:
	return MWCoords.godot_to_mw(n.global_position) if n != null else Vector3.ZERO

func _ground_key(n: Node3D) -> String:
	var m = game.main
	if not String(m.interior).is_empty():
		return "int:" + String(m.interior).to_lower()
	return m.db.exterior_key(MWCoords.cell_of(n.global_position if n != null else m.player.global_position))

## OpEquip: przedmiot z ekwipunku aktora (kamienie dusz – najpierw pełne); brak – dodana jedna sztuka.
## Gracz: jak użycie z ekwipunku (useItem: zakładanie z OnPCEquip, mikstura – wypita, składnik – zjedzony);
## NPC/stworzenie: założenie w slocie (trwałe nadpisanie automatycznego doboru, zapis w stanie aktora).
func _equip(t: Dictionary, item: String):
	var m = game.main
	var f := _fighter(t)
	if f.is_empty():
		return null
	var inv = m.interaction.inventory
	var who := "player" if f.kind == "player" else String(f.sid)
	var rec: Dictionary = {} if f.kind == "player" else f.get("rec", {})
	var pick := ""
	for e in inv.contents(who, rec):
		var eid := String(e.id).to_lower()
		if eid.get_slice("@", 0) == item:
			pick = eid
			if eid.contains("@") or not m.magic.is_soul_gem(eid):
				break
	if pick.is_empty():
		inv.add(who, rec, item, 1)
		pick = item
	var it: Dictionary = inv.item(pick)
	if f.kind == "player":
		match String(it.get("kind", "")):
			"potion": m.magic.drink(f, pick)
			"ingredient": m.magic.eat(f, pick)
			_: m.equip_item(pick)
		return null
	# NPC: Class::use(item)->execute – mikstura wypita, składnik zjedzony (ActionApply)
	match String(it.get("kind", "")):
		"potion":
			m.magic.drink(f, pick)
			return null
		"ingredient":
			m.magic.eat(f, pick)
			return null
	var slots: Array = m.item_slots(pick) if m.has_method("item_slots") else []
	if slots.is_empty():
		return null
	var st: Dictionary = m.combat._actor_state(f)
	if not st.get("equip_override") is Dictionary:
		st["equip_override"] = {}
	st.equip_override[str(slots[0])] = pick
	return null

## OpRaiseRank/OpLowerRank: ranga NPC w jego głównej frakcji (stan rozmów, zapis); gracz – bez działania.
func _npc_rank(fname: String, t: Dictionary):
	var f := _fighter(t)
	if f.is_empty() or f.kind != "npc":
		return null
	var d = _dlg()
	var a: Dictionary = d.make_actor(t.node) if t.get("node") != null else {"sid": String(t.sid), "rec": f.rec, "npc": true}
	if d.faction_of(a).is_empty():
		return null
	var cur: int = d.faction_rank_of(a)
	if fname == "raiserank":
		d._npc_state(a)["rank"] = cur + 1
	elif cur > 0:
		d._npc_state(a)["rank"] = cur - 1
	return null

## OpResurrect: gracz – ożywienie (stats.resurrect: zdrowie pełne, koniec gry cofnięty); martwy NPC/stworzenie –
## przywrócenie (undelete, stan aktora wyzerowany: zdrowie, ekwipunek, AI; pozycja bez zmian), wyłączony/włączony.
func _resurrect(t: Dictionary):
	var m = game.main
	var f := _fighter(t)
	if f.is_empty():
		return null
	if f.kind == "player":
		var st: Dictionary = m.player_stats()
		if float(st.get("health", 1.0)) <= 0.0:
			st["health"] = float(m.combat.max_health(f))           # CreatureStats::resurrect: zdrowie = maksimum
			st.erase("has_died")
			if m.has_method("resume_after_death"):
				m.resume_after_death()
		return null
	if not m.combat.is_dead(f):
		return null
	var sid := String(f.sid)
	var was_enabled: bool = state.is_enabled(sid)
	if state.refs.has(sid):
		state.refs[sid].erase("deleted")
	m.state.actors.erase(sid)                 # setCustomData(nullptr): statystyki, ekwipunek i AI od nowa
	m.state.inventories.erase(sid)
	if m.dialogue != null:
		(m.dialogue._ds().npcs as Dictionary).erase(sid)
	state.set_enabled(sid, false)
	if was_enabled:
		state.set_enabled(sid, true)
	return null

const WEREWOLF_ATTR_GMST := ["fWerewolfStrength", "fWerewolfIntellegence", "fWerewolfWillpower", "fWerewolfAgility",
	"fWerewolfSpeed", "fWerewolfEndurance", "fWerewolfPersonality", "fWerewolfLuck"]
const WEREWOLF_SKILL_GMST := ["fWerewolfBlock", "fWerewolfArmorer", "fWerewolfMediumarmor", "fWerewolfHeavyarmor",
	"fWerewolfBluntweapon", "fWerewolfLongblade", "fWerewolfAxe", "fWerewolfSpear", "fWerewolfAthletics",
	"fWerewolfEnchant", "fWerewolfDestruction", "fWerewolfAlteration", "fWerewolfIllusion", "fWerewolfConjuration",
	"fWerewolfMysticism", "fWerewolfRestoration", "fWerewolfAlchemy", "fWerewolfUnarmored", "fWerewolfSecurity",
	"fWerewolfSneak", "fWerewolfAcrobatics", "fWerewolfLightarmor", "fWerewolfShortblade", "fWerewolfMarksman",
	"fWerewolfMerchantile", "fWerewolfSpeechcraft", "fWerewolfHandtohand"]

func _werewolf_value(kind: String, i: int) -> float:
	var g: String = WEREWOLF_ATTR_GMST[i] if kind == "attributes" else WEREWOLF_SKILL_GMST[i]
	return float(game.main.character._gmst(g.to_lower(), 0.0))

## MechanicsManager::setWerewolf (NPC i gracz): bez zmiany stanu – nic; przygotowana magia schowana; ekwipunek
## zdjęty i założona szata „werewolfrobe” (odwrotnie: szata zdjęta i usunięta). Gracz: czasowe czary usunięte,
## statystyki zapamiętane i zastąpione wartościami wilkołaka (GMST fWerewolf*, zdrowie × fWereWolfHealth),
## ekwipunek i magia niedostępne, świadkowie (LOS i wykrycie w fAlarmRadius) → PCKnownWerewolf = 1 i grzywna
## iWereWolfBounty, gdy któryś ma Alarm > 0. Wygląd wilkołaka (model, nakładka ekranu) – brak.
func set_werewolf(f: Dictionary, on: bool) -> void:
	var m = game.main
	var h: Dictionary = m.combat._actor_state(f) if f.kind != "player" else m.player_stats()
	if bool(h.get("werewolf", false)) == on:
		return
	if f.kind == "player":
		m.magic_ready = false
	h["werewolf"] = on
	var inv = m.interaction.inventory
	var sid := String(f.sid)
	if f.kind == "player":
		if not m.player_stats().get("equipment") is Dictionary:
			m.player_stats()["equipment"] = {}
		var eq: Dictionary = m.player_stats().equipment
		if on:
			eq.clear()
			inv.add("player", {}, "werewolfrobe", 1)
			eq[str(11)] = {"id": "werewolfrobe", "health": -1.0}
		else:
			eq.erase(str(11))
			inv.remove("player", {}, "werewolfrobe", 1)
	else:
		if on:
			inv.add(sid, f.get("rec", {}), "werewolfrobe", 1)
		else:
			inv.remove(sid, f.get("rec", {}), "werewolfrobe", 1)
	if f.kind != "player":
		return
	var st: Dictionary = m.player_stats()
	st["active_spells"] = []                    # czasowe efekty usunięte (Flag_Temporary)
	var S = stats()
	var mult := float(m.character._gmst("fwerewolfhealth", 1.5))
	if on:
		var saved := {"attributes": [], "skills": []}
		for i in 8:
			saved.attributes.append(S.modified_value(f, "attributes", i))
		for i in 27:
			saved.skills.append(S.modified_value(f, "skills", i))
		st["werewolf_saved"] = saved
		S.set_health_plain(f, S.dyn_base(f, 0) * mult)
		for i in 8:
			S.reset_to_base(f, "attributes", i)
			S.set_modifier(f, "attributes", i, _werewolf_value("attributes", i) - S.base_value(f, "attributes", i))
		for i in 27:
			if i == 20:
				continue                        # akrobatyka – SetWerewolfAcrobatics
			S.reset_to_base(f, "skills", i)
			S.set_modifier(f, "skills", i, _werewolf_value("skills", i) - S.base_value(f, "skills", i))
	else:
		var sv: Dictionary = st.get("werewolf_saved", {})
		S.set_health_plain(f, S.dyn_base(f, 0) / mult)
		for i in 27:
			S.clear_damage(f, "skills", i)
			if i < (sv.get("skills", []) as Array).size():
				S.set_modifier(f, "skills", i, float(sv.skills[i]) - S.base_value(f, "skills", i))
		for i in 8:
			S.clear_damage(f, "attributes", i)
			if i < (sv.get("attributes", []) as Array).size():
				S.set_modifier(f, "attributes", i, float(sv.attributes[i]) - S.base_value(f, "attributes", i))
		st.erase("werewolf_saved")
	_werewolf_witnesses()

func _werewolf_witnesses() -> void:
	var m = game.main
	if m.ai == null or m.player == null:
		return
	var radius: float = float(m.character._gmst("falarmradius", 2000.0)) / MWCoords.UNITS_PER_METER
	var detected := false
	var reported := false
	for n in m.ai.actor_nodes():
		if String(n.get_meta("mw_actor", "")) != "npc" or (n as Node3D).global_position.distance_to(m.player.global_position) > radius:
			continue
		if m.combat.is_dead(m.combat.fighter_of(n)):
			continue
		if m.ai._los(n, m.player) and m.ai.awareness(m.player, n):
			detected = true
			if m.dialogue != null and int(m.dialogue.ai_setting(m.dialogue.make_actor(n), "alarm")) > 0:
				reported = true
				break
	if detected:
		if m.dialogue != null:
			m._toast(m.dialogue.gmst_text("sWerewolfAlarmMessage", ""))
		set_global("pcknownwerewolf", 1.0)
		if reported:
			var pc: Dictionary = m.player_stats()
			pc["bounty"] = maxi(0, int(pc.get("bounty", 0)) + int(m.character._gmst("iwerewolfbounty", 1000)))

## Settings::game().mActorsProcessingRange (domyślnie 7168 jednostek) w metrach.
const PROCESSING_RANGE_M := 7168.0 / 69.99125

func _dlg():
	return game.main.dialogue

## Aktor wywołania (jawne odniesienie albo obiekt skryptu) jako kontekst rozmowy; pusty dla gracza/braku.
func _who(ref, c: Ctx) -> Dictionary:
	var d = _dlg()
	if ref == null and not d.actor.is_empty() and c.sid == String(d.actor.sid):
		return d.actor
	var t := _target(ref, c)
	if t.is_empty() or String(t.sid) == "player":
		return {}
	if t.get("node") != null and d.is_actor_node(t.node):
		return d.make_actor(t.node)
	var base := String(t.get("base", "")).to_lower()
	var rec: Dictionary = records.record("npc", base)
	var npc := not rec.is_empty()
	if not npc:
		rec = records.record("creature", base)
	if rec.is_empty():
		return {}
	return {"sid": String(t.sid), "base": base, "node": null, "npc": npc, "rec": rec,
		"script": String(rec.get("script", "")).to_lower()}

## Frakcje gracza (statsextensions.cpp): bez argumentu frakcji – frakcja rozmówcy/obiektu skryptu.
## ModPCFacRep/SetPCFacRep: najpierw wartość, potem opcjonalnie frakcja; reputacja we frakcji niezależna od członkostwa.
func _faction_call(fname: String, ref, args: Array, c: Ctx):
	var d = _dlg()
	var rep_fn := fname in ["modpcfacrep", "setpcfacrep"]
	var fi := 1 if rep_fn else 0
	var fid := _str(args, fi).to_lower() if args.size() > fi else ""
	if fid.is_empty():
		var w := _who(ref, c)
		fid = d.faction_of(w) if not w.is_empty() else ""
	var get := fname in ["pcexpelled", "getpcrank", "getpcfacrep"]
	if fid.is_empty() or records.record("faction", fid).is_empty():
		if fname == "getpcrank":
			return -1.0
		if not get:
			_err("%s: brak frakcji %s" % [fname, fid])
		return 0.0 if get else null
	var pf: Dictionary = d.player_factions()
	var e: Dictionary = pf.get(fid, {})
	match fname:
		"pcjoinfaction":
			if e.is_empty():
				pf[fid] = {"rank": 0, "expelled": false}
		"pcraiserank":
			if e.is_empty():
				pf[fid] = {"rank": 0, "expelled": false}
			else:
				e["rank"] = mini(int(e.get("rank", 0)) + 1, 9)
		"pclowerrank":
			if not e.is_empty():
				e["rank"] = maxi(int(e.get("rank", 0)) - 1, 0)
		"pcexpell":
			if not e.is_empty():
				e["expelled"] = true
		"pcclearexpelled":
			if not e.is_empty():
				e["expelled"] = false
		"pcexpelled":
			return 1.0 if bool(e.get("expelled", false)) else 0.0
		"getpcrank":
			return float(int(e.get("rank", -1))) if not e.is_empty() else -1.0
		"getpcfacrep":
			return float(d.faction_reputation(fid))
		"modpcfacrep", "setpcfacrep":
			var v := int(_num(args, 0, c))
			d.set_faction_reputation(fid, (d.faction_reputation(fid) if fname == "modpcfacrep" else 0) + v)
	return null

func _inv_record(t: Dictionary) -> Dictionary:
	if String(t.sid) == "player":
		return {}
	var base := String(t.get("base", ""))
	if base.is_empty() and t.get("node") != null:
		base = String(t.node.get_meta("mw_base", ""))
	var o: Dictionary = db.get_object(base)
	var f: String = {"CONT": "container", "NPC_": "npc", "CREA": "creature"}.get(String(o.get("type", "")), "")
	return records.record(f, base) if f != "" else {}

## MessageBox: tekst z formatowaniem printf (%g %f %.Nf %d %s %G) z kolejnych zmiennych, potem przyciski.
func _format(args: Array, c: Ctx) -> Array:
	var text := _str(args, 0)
	var i := 1
	var out := ""
	var p := 0
	var re := RegEx.create_from_string("%(\\.\\d+)?([gGfds%])")
	for m in re.search_all(text):
		out += text.substr(p, m.get_start() - p)
		p = m.get_end()
		var spec := m.get_string(2)
		if spec == "%":
			out += "%"
			continue
		var v := _num(args, i, c)
		i += 1
		match spec:
			"f":
				var prec := int(m.get_string(1).substr(1)) if m.get_string(1) != "" else 6
				out += String.num(v, prec) if prec > 0 else str(int(roundf(v)))
			"d":
				out += str(int(v))
			_:
				out += str(v) if v != floorf(v) else str(int(v))
	out += text.substr(p)
	var buttons := []
	for j in range(i, args.size()):
		buttons.append(_str(args, j))
	return [out, buttons]

## Raport (MCP / diagnostyka): nieobsługiwane funkcje, błędy, liczba wywołań.
func report() -> Dictionary:
	return {"unsupported": unsupported, "missing": missing, "partial": partial, "errors": errors, "warnings": warnings, "calls": calls,
		"running": _sc().running, "frames": frame}
