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
const IDLE_ZERO := ["ondeath", "onknockout", "onmurder", "onpchitme", "gettarget", "getattacked", "getweapondrawn",
	"getspellreadied", "getcommondisease", "getblightdisease", "getpcsleep", "getcurrentaipackage", "getaipackagedone",
	"getforcesneak", "getforcerun", "getpcjumping", "getpcsneaking", "getpcinjail", "getpctraveling", "iswerewolf",
	"getwerewolfkills", "getpccrimelevel", "getdetected", "getlineofsight", "getlos"]
var delta := 0.0
var button_pressed := -1
var cell_changed := false
var activated := {}              # sid → true (aktywowany w tej klatce; OnActivate)
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
func tick(dt: float, local_refs: Array) -> void:
	delta = dt
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
	activated.clear()
	cell_changed = false

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
			game.script_message_box(parts[0], parts[1])
			return null
		# --- dziennik (teksty – etap 6)
		"getjournalindex": return float(int(state.journal.get(_str(args, 0).to_lower(), 0)))
		"journal", "setjournalindex":
			state.journal[_str(args, 0).to_lower()] = int(_num(args, 1, c))     # Journal::addEntry ustawia indeks
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
				_unsupported("say (głosy – etap 6)")
				return null
			game.script_sound(snd, t10 if fname.contains("3d") else {})
			return null
		"stopsound": return null
		"getsoundplaying": return 0.0
		# --- postać gracza
		"getlevel", "gethealth", "getmagicka", "getfatigue":
			return game.script_stat(_target(ref, c), fname)
		"dontsaveobject": return null
	if fname in IDLE_ZERO:
		partial[fname] = int(partial.get(fname, 0)) + 1
		return 0.0
	if fname == "getinterior":
		return 0.0 if game.main.interior.is_empty() else 1.0
	if fname.begins_with("get") and fname.substr(3) in game.character_stat_names():
		return game.script_stat(_target(ref, c), fname)
	_unsupported(fname)
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
