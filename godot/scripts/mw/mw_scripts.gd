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
const IDLE_ZERO := ["onknockout", "onmurder", "onpchitme", "gettarget", "getattacked", "getpcsleep",
	"getforcesneak", "getforcerun", "getpcjumping", "getpcsneaking", "getpcinjail", "getpctraveling", "iswerewolf",
	"getwerewolfkills", "getpccrimelevel", "getdetected", "getlineofsight", "getlos"]
## Funkcje bez argumentów, które skrypty zapisują jak zmienne (bez nawiasów).
const BARE_FUNCTIONS := ["saydone", "getaipackagedone", "onactivate", "menumode", "getbuttonpressed", "cellchanged",
	"getsecondspassed", "onpcadd", "onpcequip", "onpcdrop", "ondeath", "onknockout", "onmurder", "getpcsleep",
	"getpcjumping", "getstandingpc", "getcurrenttime", "getdisabled", "getinterior", "getcurrentaipackage",
	"getweapondrawn", "getspellreadied", "getpccrimelevel", "random100", "getlevel", "gethealth", "getpcrank",
	"getdeadcount", "getlocked", "getscale", "getpcinjail", "getpctraveling", "getwaterlevel", "onpchitme"]
var delta := 0.0
var button_pressed := -1
var cell_changed := false
var activated := {}              # sid → true (aktywowany w tej klatce; OnActivate)
var flags := {}                  # "klucz|onpcadd/onpcequip/onpcdrop" → zdarzenie dla skryptu (odczyt je kasuje)
var _inv_counts := {}            # przedmiot ze skryptem u gracza → liczba w poprzedniej klatce (OnPCAdd)
var died := {}                   # sid → true (zginął od ostatniej klatki; OnDeath – etap 7)
var _refindex = null
var frame := 0

class Ctx:
	var sid := ""                # referencja (pusta dla skryptów globalnych)
	var base := ""               # id rekordu obiektu
	var scr := ""                # id skryptu
	var key := ""                # klucz zmiennych lokalnych w GameState
	var node: Node = null
	var stop := false

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
	for id in (_sc().running as Array).duplicate():
		var c := Ctx.new()
		c.scr = id
		c.key = "global:" + id
		run(c)
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
		run(c)
	# skrypty przedmiotów w ekwipunku gracza (OpenMW: LocalScripts dla zawartości gracza); OnPCAdd przy przybyciu
	var now := {}
	var scr_of := {}
	for e in game.player_scripted_items():
		var iid := String(e[0])
		now[iid] = int(e[2])
		scr_of[iid] = String(e[1])
		if int(e[2]) > int(_inv_counts.get(iid, 0)):
			flags["inv:" + iid + "|onpcadd"] = true
	for iid in now:
		var c := Ctx.new()
		c.base = iid
		c.scr = String(scr_of[iid])
		c.key = "inv:" + iid
		c.sid = ""
		run(c)
	_inv_counts = now
	activated.clear()
	died.clear()
	cell_changed = false

## Przedmiot przeszedł ze świata do gracza: zmienne lokalne skryptu idą z nim (RefData przenoszone z obiektem).
func item_to_player(from_sid: String, item_id: String) -> void:
	var src: Dictionary = _sc().locals.get(from_sid, {})
	if not src.is_empty() and not _sc().locals.has("inv:" + item_id.to_lower()):
		_sc().locals["inv:" + item_id.to_lower()] = src.duplicate()

## Gracz założył przedmiot: OnPCEquip (zdarzenie i zmienna lokalna „OnPCEquip”, jak w Morrowindzie).
func item_equipped(item_id: String) -> void:
	var k := "inv:" + item_id.to_lower()
	flags[k + "|onpcequip"] = true
	var scr := ""
	for e in game.player_scripted_items():
		if String(e[0]) == item_id.to_lower():
			scr = String(e[1])
	if not scr.is_empty() and not _var_type(scr, "onpcequip").is_empty():
		_locals(k)["onpcequip"] = 1.0

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

func get_global(name: String) -> float:
	var k := name.to_lower()
	if state.globals.has(k):
		return float(state.globals[k])
	return float(_global_rec(k).get("value", 0.0))

func set_global(name: String, v: float) -> void:
	var k := name.to_lower()
	var t := String(_global_rec(k).get("type", "f"))
	state.globals[k] = float(int(v)) if t in ["s", "l", "short", "long"] else v

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
	return m.fighter_by_sid(String(t.get("sid", ""))) if m.has_method("fighter_by_sid") else {}

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
			var cr := _str(args, 0).to_lower()
			var n := 0
			for e in m.interaction.inventory.contents("player", {}):
				if mg.is_soul_gem(String(e.id)) and mg.soul_of(String(e.id)) == cr:
					n += int(e.count)
			return 1.0 if n > 0 else 0.0
		"getcommondisease", "getblightdisease":
			var want := 3 if fname == "getcommondisease" else 2
			var list: Array = m.player_stats().get("spells", []) if f.kind == "player" else f.rec.get("spells", [])
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
			if v == null and String(e[1]).to_lower() == "xbox":
				return 0.0                    # zmienna wersji Xbox (w PC Morrowindzie nieokreślona = 0)
			if v == null:
				_err("%s: nieznany identyfikator %s" % [c.scr, e[1]])
				return 0.0
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

func _call(ref, fname: String, args: Array, c: Ctx):
	calls[fname] = int(calls.get(fname, 0)) + 1
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
			return float(_dlg().ai_setting(wa, fname.substr(3))) if not wa.is_empty() else 0.0
		"setfight", "sethello", "setflee", "setalarm", "modfight", "modhello", "modflee", "modalarm":
			var wm := _who(ref, c)
			if not wm.is_empty():
				var key := fname.substr(3)
				var nv := int(_num(args, 0, c))
				if fname.begins_with("mod"):
					nv += _dlg().ai_setting(wm, key)
				_dlg().set_ai_setting(wm, key, nv)
			return null
		"setpccrimelevel", "modpccrimelevel":
			var pc: Dictionary = game.main.player_stats()
			pc["bounty"] = maxi(0, (int(pc.get("bounty", 0)) if fname.begins_with("mod") else 0) + int(_num(args, 0, c)))
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
				partial[fname + " (NPC – etap 7)"] = int(partial.get(fname + " (NPC – etap 7)", 0)) + 1
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
		"ondeath":
			var td := _target(ref, c)
			return 1.0 if not td.is_empty() and died.has(String(td.sid)) else 0.0
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
		"playsound", "playsound3d", "playsound3dvp", "playloopsound3d", "playloopsound3dvp", "say":
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
		"stopsound":
			game.stop_sound(_target(ref, c), _str(args, 0))
			return null
		"getsoundplaying":
			return 1.0 if game.sound_playing(_target(ref, c), _str(args, 0)) else 0.0
		# --- postać gracza
		"getlevel", "gethealth", "getmagicka", "getfatigue":
			return game.script_stat(_target(ref, c), fname)
		"dontsaveobject": return null
		"getspell":
			var t11 := _target(ref, c)
			var spell := _str(args, 0).to_lower()
			if String(t11.get("sid", "")) == "player" or t11.is_empty() and c.sid.is_empty():
				return 1.0 if spell in (game.main.player_stats().get("spells", []) as Array) else 0.0
			var nrec: Dictionary = records.record("npc", String(t11.get("base", "")))
			if nrec.is_empty():
				nrec = records.record("creature", String(t11.get("base", "")))
			return 1.0 if spell in (nrec.get("spells", []) as Array).map(func(x): return String(x).to_lower()) else 0.0
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
		"onpcadd", "onpcequip", "onpcdrop":
			var fk := c.key + "|" + fname
			if flags.has(fk):
				flags.erase(fk)
				return 1.0
			return float(_locals(c.key).get(fname, 0.0)) if not _var_type(c.scr, fname).is_empty() else 0.0
		"saydone":
			return 1.0 if game.say_done(_target(ref, c)) else 0.0
		# --- AI (etap 8)
		"aiwander", "aitravel", "aiescort", "aiescortcell", "aifollow", "aifollowcell", "aiactivate", "getaipackagedone", "getcurrentaipackage":
			return _ai_function(fname, _target(ref, c), args, c)
		# --- magia (etap 7d)
		"geteffect", "getspelleffects", "cast", "explodespell", "removespelleffects", "removeeffects", "getweapondrawn", "getspellreadied", "hassoulgem", "getcommondisease", "getblightdisease":
			return _magic_function(fname, _target(ref, c), args, c)
	if fname in IDLE_ZERO:
		partial[fname] = int(partial.get(fname, 0)) + 1
		return 0.0
	if fname == "getinterior":
		return 0.0 if game.main.interior.is_empty() else 1.0
	if fname.begins_with("get") and fname.substr(3) in game.character_stat_names():
		return game.script_stat(_target(ref, c), fname)
	_unsupported(fname)
	return null

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
	return {"unsupported": unsupported, "partial": partial, "errors": errors, "calls": calls,
		"running": _sc().running, "frames": frame}
