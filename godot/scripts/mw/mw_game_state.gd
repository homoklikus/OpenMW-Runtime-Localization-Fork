extends RefCounted
## GameState – jedyne miejsce zmian świata w trakcie gry (plan, rewizja 2.0, §2.1 i §2.4).
##
## Dane bazowe z konwertera (world/…) są tylko do odczytu; tu żyją wyłącznie RÓŻNICE względem nich:
##   refs     sid → {"enabled": bool, "deleted": bool, "mw": {"pos": [x,y,z], "rot": [rx,ry,rz], "scale": s},
##            "lock": poziom zamka (0 = otwarty), "trap": id czaru pułapki ("" = rozbrojona)}
##            (sid = "<plik, który utworzył referencję>#<refnum>" – stabilny, niezależny od kolejności modów)
##   globals  zmienne globalne (GLOB; skrypty – etap 5)
##   time     {"day", "hour"}
##   player   {"interior": nazwa wnętrza albo "", "mw": {"pos", "rot"}}  (jednostki i kąty Morrowinda)
##   dyn_next licznik referencji utworzonych w grze ("dyn#N")
##   inventories  (v2) sid pojemnika/NPC (albo "player") → [{"id", "count"[, "parts"]}, …] – pełna zawartość po pierwszej
##            zmianie; bez wpisu = zawartość z rekordu (z listami poziomowanymi rozlosowanymi wg seed i sid)
##   dynamic  (v2) sid "dyn#N" → {"base", "cell" (klucz komórki), "mw": {"pos","rot","scale"}, "count"} – przedmioty
##            położone w świecie w trakcie gry
##   seed     (v2) ziarno losowania list poziomowanych tej rozgrywki
##   scripts  (v2, etap 5) skrypty globalne działające, zmienne lokalne skryptów i obiektów
##   journal  (v2, etap 5) indeksy zadań (GetJournalIndex/Journal)
##   dialogue (v3, etap 6) znane tematy, wpisy dziennika z datą, zakończone zadania, dziennik tematów, postawa
##            i ustawienia AI NPC zmienione w grze, zmienione reakcje frakcji, liczniki zabitych (mw_dialogue.gd)
##   actors   (v4, etap 7) sid NPC/stworzenia → {"health", "fatigue", "magicka", "dead", "knocked_down",
##            "attacked", "condition": {slot: stan przedmiotu}} – tylko aktorzy zmienieni w grze
##   created  (v5, etap 7d) rekordy utworzone w grze: plik ("potion", "enchantment", "weapon", …) → id →
##            rekord (mikstury z alchemii, zaklęcia i przedmioty zaklęte); created_next – licznik id
##   extra    sekcje zapisu, których ta wersja nie zna – zachowywane przy ponownym zapisie
## Zapis nie zależy od scen ani węzłów Godota. Wpisy dla wtyczek, których brakuje, NIE są usuwane.

signal ref_changed(sid: String)

const FORMAT := "mwgodot-save"
const VERSION := 5
const KNOWN := ["format", "version", "header", "refs", "globals", "time", "player", "dyn_next", "inventories",
	"dynamic", "seed", "scripts", "journal", "dialogue", "actors", "created", "created_next"]

var refs := {}
var globals := {}
var time := {"day": 0, "hour": 9.0}
var player := {}
var dyn_next := 1
var inventories := {}
var dynamic := {}
var seed := 0
var scripts := {}                 # etap 5: {"running": [id skryptów globalnych], "locals": {sid|"global:id": {zmienna: wartość}}, "started"}
var journal := {}                 # etap 5/6: id zadania → indeks
var dialogue := {}                # etap 6: stan rozmów i dziennika (mw_dialogue.gd)
var actors := {}                  # etap 7: stan aktorów (zdrowie, śmierć…) – mw_combat.gd
var created := {}                 # etap 7d: rekordy utworzone w grze (mw_magic.gd)
var created_next := 1
var extra := {}

signal inventory_changed(sid: String)
signal dynamic_changed(sid: String)

# --- referencje -------------------------------------------------------------------------------------

func _entry(sid: String) -> Dictionary:
	if not refs.has(sid):
		refs[sid] = {}
	return refs[sid]

func is_enabled(sid: String) -> bool:
	var e: Dictionary = refs.get(sid, {})
	return bool(e.get("enabled", true)) and not bool(e.get("deleted", false))

func set_enabled(sid: String, on: bool) -> void:
	if is_enabled(sid) == on:
		return
	_entry(sid)["enabled"] = on
	_compact(sid)
	ref_changed.emit(sid)

func delete_ref(sid: String) -> void:
	_entry(sid)["deleted"] = true
	ref_changed.emit(sid)

## Liczba sztuk referencji przedmiotu (CellRef::setCount – np. część stosu z półki kupiona u kupca).
func set_ref_count(sid: String, count: int) -> void:
	_entry(sid)["count"] = count
	ref_changed.emit(sid)

func ref_count_of(sid: String, base_count: int) -> int:
	return int(refs.get(sid, {}).get("count", base_count))

## Nowa pozycja/obrót referencji w jednostkach MW (np. przesunięty przedmiot).
func set_ref_mw(sid: String, pos: Vector3, rot: Vector3, scale := 1.0) -> void:
	_entry(sid)["mw"] = {"pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z], "scale": scale}
	ref_changed.emit(sid)

## Pozycja aktora przesuniętego przez AI (etap 8) – bez sygnału (węzeł już stoi w tym miejscu).
func store_ref_mw(sid: String, pos: Vector3, rot: Vector3) -> void:
	var e := _entry(sid)
	var sc := float((e.get("mw", {}) as Dictionary).get("scale", 1.0))
	e["mw"] = {"pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z], "scale": sc}

## Zamek i pułapka referencji (etap 3): stan gry nadpisuje wartości z danych (FLTV, TNAM).
func lock_of(sid: String, base_level: int) -> int:
	return int(refs.get(sid, {}).get("lock", base_level))

func set_lock(sid: String, level: int) -> void:
	_entry(sid)["lock"] = level
	ref_changed.emit(sid)

func trap_of(sid: String, base_trap: String) -> String:
	return String(refs.get(sid, {}).get("trap", base_trap))

func set_trap(sid: String, trap: String) -> void:
	_entry(sid)["trap"] = trap
	ref_changed.emit(sid)

func has_override(sid: String) -> bool:
	return refs.has(sid)

## Referencja z danych bazowych z nałożonym stanem (kopia; dane bazowe nietknięte).
func apply_to_ref(r: Dictionary) -> Dictionary:
	var e: Dictionary = refs.get(String(r.get("sid", "")), {})
	if e.is_empty():
		return r
	var out := r.duplicate()
	if e.has("mw"):
		var m: Dictionary = e["mw"]
		var p: Array = m["pos"]
		var ro: Array = m["rot"]
		var s := float(m.get("scale", 1.0))
		var t := Transform3D(MWCoords.mw_rot_to_basis(Vector3(ro[0], ro[1], ro[2])).scaled(Vector3(s, s, s)),
				MWCoords.mw_to_godot(Vector3(p[0], p[1], p[2])))
		var f := MWCoords.transform_to_ref_fields(t)
		out["mw"] = m.duplicate()
		out["godot"] = f["godot"]
	if e.has("count"):
		var ex: Dictionary = (r.get("extra", {}) as Dictionary).duplicate()
		ex["count"] = int(e["count"])
		out["extra"] = ex
	if not is_enabled(String(r.get("sid", ""))):
		out["disabled"] = true
	return out

func new_dynamic_sid() -> String:
	var s := "dyn#%d" % dyn_next
	dyn_next += 1
	return s

# --- inwentarze i przedmioty w świecie (etap 3) -------------------------------------------------------

func has_inventory(sid: String) -> bool:
	return inventories.has(sid)

func inventory(sid: String) -> Array:
	return inventories.get(sid, [])

func set_inventory(sid: String, items: Array) -> void:
	var clean := []
	for it in items:
		if int(it.get("count", 0)) != 0:
			clean.append(_inv_entry(it))
	inventories[sid] = clean
	inventory_changed.emit(sid)

## Wpis inwentarza: {"id", "count"} oraz – dla przedmiotów ze skryptem (osobne stosy) – „parts”: liczby sztuk stosów.
static func _inv_entry(it: Dictionary) -> Dictionary:
	var e := {"id": String(it["id"]).to_lower(), "count": int(it["count"])}
	if it.get("parts") is Array and (it.parts as Array).size() > 1:
		e["parts"] = (it.parts as Array).map(func(p): return int(p))
	return e

## Przedmiot położony w świecie (gracz wyrzucił/odłożył): nowy sid dyn#N.
func add_dynamic(base: String, cell_key: String, pos: Vector3, rot: Vector3, count := 1) -> String:
	var sid := new_dynamic_sid()
	dynamic[sid] = {"base": base.to_lower(), "cell": cell_key, "count": count,
			"mw": {"pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z], "scale": 1.0}}
	dynamic_changed.emit(sid)
	return sid

func remove_dynamic(sid: String) -> void:
	if dynamic.erase(sid):
		dynamic_changed.emit(sid)

## Referencje dynamiczne komórki – w formacie referencji z konwertera (dla MWCellBuilder).
func dynamic_refs(cell_key: String) -> Array:
	var out := []
	for sid in dynamic:
		var d: Dictionary = dynamic[sid]
		if String(d.get("cell", "")) != cell_key:
			continue
		var m: Dictionary = d["mw"]
		var p: Array = m["pos"]
		var ro: Array = m["rot"]
		var t := Transform3D(MWCoords.mw_rot_to_basis(Vector3(ro[0], ro[1], ro[2])), MWCoords.mw_to_godot(Vector3(p[0], p[1], p[2])))
		var r := {"sid": sid, "base": d["base"], "mw": m.duplicate(true), "source": "dynamic"}
		r.merge(MWCoords.transform_to_ref_fields(t), true)
		if int(d.get("count", 1)) > 1:
			r["extra"] = {"count": int(d["count"])}
		out.append(r)
	return out

func _compact(sid: String) -> void:
	var e: Dictionary = refs.get(sid, {})
	if bool(e.get("enabled", true)) and not e.has("mw") and not bool(e.get("deleted", false)) \
			and not e.has("lock") and not e.has("trap") and not e.has("count"):
		refs.erase(sid)

# --- zapis/odczyt -----------------------------------------------------------------------------------

## header: profil, postać, lista treści (wtyczki z SHA-256 w kolejności ładowania), odcisk danych bazowych.
func to_dict(header: Dictionary) -> Dictionary:
	var d := extra.duplicate(true)
	d.merge({"format": FORMAT, "version": VERSION, "header": header, "refs": refs, "globals": globals,
			"time": time, "player": player, "dyn_next": dyn_next, "inventories": inventories, "dynamic": dynamic,
			"seed": seed, "scripts": scripts, "journal": journal, "dialogue": dialogue, "actors": actors,
			"created": created, "created_next": created_next}, true)
	return d

## Wczytuje słownik zapisu (po migracji). Zwraca listę ostrzeżeń (pusta = zgodny).
func from_dict(d: Dictionary) -> Array:
	var warnings := []
	refs = (d.get("refs", {}) as Dictionary).duplicate(true)
	globals = (d.get("globals", {}) as Dictionary).duplicate(true)
	time = (d.get("time", {"day": 0, "hour": 9.0}) as Dictionary).duplicate(true)
	player = (d.get("player", {}) as Dictionary).duplicate(true)
	dyn_next = int(d.get("dyn_next", 1))
	inventories = (d.get("inventories", {}) as Dictionary).duplicate(true)
	for k in inventories:        # JSON: liczby jako float
		inventories[k] = (inventories[k] as Array).map(func(it): return _inv_entry(it))
	dynamic = (d.get("dynamic", {}) as Dictionary).duplicate(true)
	seed = int(d.get("seed", 0))
	scripts = (d.get("scripts", {}) as Dictionary).duplicate(true)
	journal = {}
	for q in (d.get("journal", {}) as Dictionary):
		journal[q] = int(d["journal"][q])
	dialogue = (d.get("dialogue", {}) as Dictionary).duplicate(true)
	actors = (d.get("actors", {}) as Dictionary).duplicate(true)
	created = (d.get("created", {}) as Dictionary).duplicate(true)
	created_next = int(d.get("created_next", 1))
	extra = {}
	for k in d:
		if not k in KNOWN:
			extra[k] = d[k]
	if not extra.is_empty():
		warnings.append("zapis zawiera sekcje nieznane tej wersji gry (zachowane): %s" % ", ".join(extra.keys()))
	return warnings

## Migracje do bieżącej wersji: v0 → v1 itd. Zwraca {"data": …} albo {"error": …}.
static func migrate(d: Dictionary) -> Dictionary:
	if String(d.get("format", "")) != FORMAT:
		return {"error": "not an OpenMWGodot saved game"}
	var v := int(d.get("version", 0))
	var v0 := v
	if v > VERSION:
		return {"error": "save from a newer game version (format %d, this game supports %d) – the original is left unchanged" % [v, VERSION]}
	if v <= 1:
		d = _v1_to_v2(d)
		v = 2
	if v == 2:
		d["dialogue"] = d.get("dialogue", {})      # v2 → v3: rozmowy i dziennik (etap 6) – pusty stan
		v = 3
	if v == 3:
		d["actors"] = d.get("actors", {})          # v3 → v4: stan aktorów (etap 7) – pusty
		v = 4
	if v == 4:
		d["created"] = d.get("created", {})        # v4 → v5: rekordy utworzone w grze (etap 7d) – brak
		d["created_next"] = d.get("created_next", 1)
		v = 5
	# (kolejne kroki: if v == 5: d = _v5_to_v6(d); v = 6 …)
	d["version"] = VERSION
	return {"data": d, "migrated": v0 != VERSION}

## v1 → v2: inwentarze, przedmioty w świecie, ziarno losowania (puste – stan jak w danych bazowych), poziom gracza.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	d["inventories"] = d.get("inventories", {})
	d["dynamic"] = d.get("dynamic", {})
	d["seed"] = d.get("seed", 0)
	var p: Dictionary = d.get("player", {})
	if not p.has("level"):
		p["level"] = 1
	d["player"] = p
	return d

## Zgodność zapisu z bieżącymi danymi: brakujące/zmienione wtyczki, inna kolejność ładowania.
static func compatibility(save_header: Dictionary, current_header: Dictionary) -> Array:
	var out := []
	var cur := {}
	for c in current_header.get("content", []):
		cur[String(c.get("name", "")).to_lower()] = c
	var names_save := []
	for c in save_header.get("content", []):
		var n := String(c.get("name", "")).to_lower()
		names_save.append(n)
		if not cur.has(n):
			out.append("missing content file %s – its objects are kept in the save but will not be visible" % c.get("name", ""))
		elif String(cur[n].get("sha256", "")) != String(c.get("sha256", "")):
			out.append("content file %s has changed since the save" % c.get("name", ""))
	for n in cur:
		if not n in names_save:
			out.append("new content file %s (not present when saved)" % cur[n].get("name", n))
	var order_cur := []
	for c in current_header.get("content", []):
		var n := String(c.get("name", "")).to_lower()
		if n in names_save:
			order_cur.append(n)
	var order_save := names_save.filter(func(x): return cur.has(x))
	if order_cur != order_save:
		out.append("the content file load order has changed")
	return out

## Zapis atomowy: plik tymczasowy → zmiana nazwy; poprzednia wersja jako .bak.
static func write_file(path: String, d: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path + ".bak")
		var e1 := DirAccess.rename_absolute(path, path + ".bak")
		if e1 != OK:
			return e1
	return DirAccess.rename_absolute(tmp, path)

static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "saved game file %s not found" % path}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {"error": "cannot open the saved game (%d)" % FileAccess.get_open_error()}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary:
		return {"error": "damaged saved game file"}
	return d

## Kopia bezpieczeństwa przed migracją (oryginał zostaje nietknięty pod nazwą .v<wersja>.bak).
static func backup_before_migration(path: String, version: int) -> void:
	var dst := "%s.v%d.bak" % [path, version]
	if not FileAccess.file_exists(dst):
		DirAccess.copy_absolute(path, dst)
