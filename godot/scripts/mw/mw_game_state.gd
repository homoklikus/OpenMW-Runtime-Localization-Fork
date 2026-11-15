extends RefCounted
## GameState – jedyne miejsce zmian świata w trakcie gry (plan, rewizja 2.0, §2.1 i §2.4).
##
## Dane bazowe z konwertera (world/…) są tylko do odczytu; tu żyją wyłącznie RÓŻNICE względem nich:
##   refs     sid → {"enabled": bool, "deleted": bool, "mw": {"pos": [x,y,z], "rot": [rx,ry,rz], "scale": s}}
##            (sid = "<plik, który utworzył referencję>#<refnum>" – stabilny, niezależny od kolejności modów)
##   globals  zmienne globalne (GLOB; skrypty – etap 5)
##   time     {"day", "hour"}
##   player   {"interior": nazwa wnętrza albo "", "mw": {"pos", "rot"}}  (jednostki i kąty Morrowinda)
##   dyn_next licznik referencji utworzonych w grze ("dyn#N")
##   extra    sekcje zapisu, których ta wersja nie zna – zachowywane przy ponownym zapisie
## Zapis nie zależy od scen ani węzłów Godota. Wpisy dla wtyczek, których brakuje, NIE są usuwane.

signal ref_changed(sid: String)

const FORMAT := "mwgodot-save"
const VERSION := 1
const KNOWN := ["format", "version", "header", "refs", "globals", "time", "player", "dyn_next"]

var refs := {}
var globals := {}
var time := {"day": 0, "hour": 9.0}
var player := {}
var dyn_next := 1
var extra := {}

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

## Nowa pozycja/obrót referencji w jednostkach MW (np. przesunięty przedmiot).
func set_ref_mw(sid: String, pos: Vector3, rot: Vector3, scale := 1.0) -> void:
	_entry(sid)["mw"] = {"pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z], "scale": scale}
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
	if not is_enabled(String(r.get("sid", ""))):
		out["disabled"] = true
	return out

func new_dynamic_sid() -> String:
	var s := "dyn#%d" % dyn_next
	dyn_next += 1
	return s

func _compact(sid: String) -> void:
	var e: Dictionary = refs.get(sid, {})
	if bool(e.get("enabled", true)) and not e.has("mw") and not bool(e.get("deleted", false)):
		refs.erase(sid)

# --- zapis/odczyt -----------------------------------------------------------------------------------

## header: profil, postać, lista treści (wtyczki z SHA-256 w kolejności ładowania), odcisk danych bazowych.
func to_dict(header: Dictionary) -> Dictionary:
	var d := extra.duplicate(true)
	d.merge({"format": FORMAT, "version": VERSION, "header": header, "refs": refs, "globals": globals,
			"time": time, "player": player, "dyn_next": dyn_next}, true)
	return d

## Wczytuje słownik zapisu (po migracji). Zwraca listę ostrzeżeń (pusta = zgodny).
func from_dict(d: Dictionary) -> Array:
	var warnings := []
	refs = (d.get("refs", {}) as Dictionary).duplicate(true)
	globals = (d.get("globals", {}) as Dictionary).duplicate(true)
	time = (d.get("time", {"day": 0, "hour": 9.0}) as Dictionary).duplicate(true)
	player = (d.get("player", {}) as Dictionary).duplicate(true)
	dyn_next = int(d.get("dyn_next", 1))
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
		return {"error": "to nie jest zapis OpenMWGodot"}
	var v := int(d.get("version", 0))
	if v > VERSION:
		return {"error": "zapis z nowszej wersji gry (format %d, ta gra obsługuje %d) – oryginał pozostaje bez zmian" % [v, VERSION]}
	# (miejsce na kolejne kroki: if v == 1: d = _v1_to_v2(d); v = 2 …)
	d["version"] = VERSION
	return {"data": d, "migrated": v != VERSION}

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
			out.append("brak wtyczki %s – jej obiekty w zapisie zostają zachowane, ale nie będą widoczne" % c.get("name", ""))
		elif String(cur[n].get("sha256", "")) != String(c.get("sha256", "")):
			out.append("wtyczka %s zmieniła się od zapisu" % c.get("name", ""))
	for n in cur:
		if not n in names_save:
			out.append("nowa wtyczka %s (nie było jej przy zapisie)" % cur[n].get("name", n))
	var order_cur := []
	for c in current_header.get("content", []):
		var n := String(c.get("name", "")).to_lower()
		if n in names_save:
			order_cur.append(n)
	var order_save := names_save.filter(func(x): return cur.has(x))
	if order_cur != order_save:
		out.append("zmieniła się kolejność ładowania wtyczek")
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
		return {"error": "brak pliku zapisu %s" % path}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {"error": "nie można otworzyć zapisu (%d)" % FileAccess.get_open_error()}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary:
		return {"error": "uszkodzony plik zapisu"}
	return d

## Kopia bezpieczeństwa przed migracją (oryginał zostaje nietknięty pod nazwą .v<wersja>.bak).
static func backup_before_migration(path: String, version: int) -> void:
	var dst := "%s.v%d.bak" % [path, version]
	if not FileAccess.file_exists(dst):
		DirAccess.copy_absolute(path, dst)
