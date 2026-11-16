extends RefCounted
## Interakcje gracza ze światem (etap 3): aktywacja drzwi, przedmiotów i pojemników, zamki z kluczami, pułapki,
## podnoszenie i odkładanie przedmiotów. Logika bez interfejsu (okna: mw_item_window.gd) – testowalna.
##
## Wzorce z OpenMW: apps/openmw/mwclass/{door,container,misc,…}.cpp (activate), mwworld/actiontake.cpp,
## mwworld/containerstore.cpp (złoto: gold_005 → 5 × gold_001), mwgui/inventorywindow.cpp (upuszczanie).
## Kradzież (przedmioty i pojemniki z właścicielem) – etap 8; efekty czarów pułapek – etap 7.

const ITEM_TYPES := ["WEAP", "ARMO", "CLOT", "BOOK", "MISC", "APPA", "LOCK", "PROB", "REPA", "ALCH", "INGR"]
const GOLD := {"gold_001": 1, "gold_005": 5, "gold_010": 10, "gold_025": 25, "gold_100": 100}
const PLAYER := "player"

var db
var state
var records          # MWActorVisual (record(file, id))
var inventory        # MWInventory
var loc = null       # tłumaczenia nazw (opcjonalnie)
var _equipment = null

const WEAPON_SOUND := {0: "Item Weapon Shortblade", 1: "Item Weapon Longblade", 2: "Item Weapon Longblade",
	3: "Item Weapon Blunt", 4: "Item Weapon Blunt", 5: "Item Weapon Blunt", 6: "Item Weapon Spear", 7: "Item Weapon Blunt",
	8: "Item Weapon Blunt", 9: "Item Weapon Bow", 10: "Item Weapon Crossbow", 11: "Item Weapon Blunt", 12: "Item Ammo",
	13: "Item Ammo"}
const KIND_SOUND := {"apparatus": "Item Apparatus", "book": "Item Book", "ingredient": "Item Ingredient",
	"light": "Item Misc", "lockpick": "Item Lockpick", "probe": "Item Probe", "repair": "Item Repair",
	"potion": "Item Potion"}

## Dźwięk podniesienia/odłożenia przedmiotu (Class::getUpSoundId/getDownSoundId w OpenMW).
func item_sound(id: String, up: bool) -> String:
	var it: Dictionary = inventory.item(id)
	if it.is_empty():
		return ""
	var base := ""
	match String(it.kind):
		"misc":
			base = "Item Gold" if GOLD.has(String(it.id)) else "Item Misc"
		"clothing":
			base = "Item Ring" if int(it.rec.get("clothing_type", -1)) == 8 else "Item Clothes"
		"armor":
			if _equipment == null:
				_equipment = load("res://scripts/mw/mw_equipment.gd").new(records)
			var sk: int = _equipment.armor_skill(it.rec)
			base = {21: "Item Armor Light", 2: "Item Armor Medium", 3: "Item Armor Heavy"}.get(sk, "Item Armor Light")
		"weapon":
			base = String(WEAPON_SOUND.get(int(it.rec.get("weapon_type", 0)), "Item Weapon Blunt"))
		_:
			base = String(KIND_SOUND.get(String(it.kind), "Item Misc"))
	return base + (" Up" if up else " Down")

func _init(world_db, game_state, records_source, inv) -> void:
	db = world_db
	state = game_state
	records = records_source
	inventory = inv

static func extra_of(node: Node) -> Dictionary:
	return node.get_meta("mw_extra", {}) if node != null and node.has_meta("mw_extra") else {}

func base_of(node: Node) -> Dictionary:
	return db.get_object(String(node.get_meta("mw_base", ""))) if node != null else {}

func sid_of(node: Node) -> String:
	return String(node.get_meta("mw_sid", "")) if node != null else ""

## Rodzaj aktywacji: door | item | container | npc | creature | activator | "" (nic – brak podpowiedzi).
func kind_of(node: Node) -> String:
	if node == null or node.has_meta("mw_marker") or node.get_meta("mw_disabled", false):
		return ""
	var b := base_of(node)
	var t := String(b.get("type", ""))
	if t == "DOOR":
		return "door"
	if t in ITEM_TYPES:
		return "item"
	if t == "LIGH":
		var lr: Dictionary = records.record("light", String(b.get("id", node.get_meta("mw_base", ""))))
		return "item" if bool(lr.get("carry", false)) else ""
	if t == "CONT":
		return "container"
	return ""                     # NPC (dialog – etap 6), stworzenia, aktywatory (skrypty – etap 5)

func display_name(node: Node) -> String:
	var b := base_of(node)
	var fb := String(b.get("name", node.get_meta("mw_base", "")))
	return loc.object_name(b, fb) if loc != null and loc.has_method("object_name") else fb

const KIND_TYPES := {"weapon": "WEAP", "armor": "ARMO", "clothing": "CLOT", "book": "BOOK", "misc": "MISC",
	"apparatus": "APPA", "lockpick": "LOCK", "probe": "PROB", "repair": "REPA", "light": "LIGH", "potion": "ALCH",
	"ingredient": "INGR"}

## Nazwa przedmiotu z inwentarza (z tłumaczeniem, jeśli jest).
func item_name(kind: String, id: String, rec: Dictionary) -> String:
	var fb := String(rec.get("name", id))
	if loc != null and loc.has_method("plain") and loc.is_active():
		return loc.plain(loc.key(String(KIND_TYPES.get(kind, "")), id, "FNAM"), fb)
	return fb

func lock_level(node: Node) -> int:
	return state.lock_of(sid_of(node), int(extra_of(node).get("lock_level", 0)))

func trap(node: Node) -> String:
	return state.trap_of(sid_of(node), String(extra_of(node).get("trap", "")))

func count_of_ref(node: Node) -> int:
	return maxi(1, int(extra_of(node).get("count", 1)))

## Podpowiedź pod celownikiem (nazwa, liczba, zamek) – tylko dla tego, co aktywacja faktycznie obsługuje.
func hint(node: Node) -> String:
	var k := kind_of(node)
	if k == "":
		return ""
	if k == "door" and MWTravel.door_destination(node).is_empty() and lock_level(node) <= 0:
		return ""                 # drzwi bez celu i bez zamka – nic do zrobienia (animacja otwierania – etap 10)
	var name := display_name(node)
	var n := count_of_ref(node)
	var s := name + (" (%d)" % n if n > 1 else "")
	if lock_level(node) > 0:
		s += "  [zamknięte, poziom %d]" % lock_level(node)
	if trap(node) != "":
		s += "  [pułapka]"
	return s

func _player_items() -> Array:
	return inventory.contents(PLAYER, {})

## Złoto jak w OpenMW: gold_005 itd. trafia do inwentarza jako gold_001 × wartość.
static func normalize_gold(id: String, count: int) -> Array:
	var k := id.to_lower()
	if GOLD.has(k):
		return ["gold_001", count * int(GOLD[k])]
	return [k, count]

## Migawka referencji przed zmianą stanu (zmiana w GameState przebudowuje węzeł – stary zostaje zwolniony).
func snapshot(node: Node) -> Dictionary:
	return {"sid": sid_of(node), "base": String(node.get_meta("mw_base", "")), "extra": extra_of(node),
			"name": display_name(node), "kind": kind_of(node), "count": count_of_ref(node),
			"lock": lock_level(node), "trap": trap(node), "dest": MWTravel.door_destination(node)}

## Zamek: klucz w inwentarzu gracza otwiera (OpenMW: „sKeyUsed”); bez klucza – „zamknięte” (wytrychy – etap 7).
## Zwraca {"ok": bool, "message": String}.
func try_unlock(c: Dictionary) -> Dictionary:
	if int(c.lock) <= 0:
		return {"ok": true, "message": ""}
	var key := String(c.extra.get("key", "")).to_lower()
	if not key.is_empty() and inventory.count_of(PLAYER, {}, key) > 0:
		state.set_lock(c.sid, 0)
		var kr: Dictionary = inventory.item(key).get("rec", {})
		return {"ok": true, "message": "Użyto klucza: %s" % String(kr.get("name", key))}
	return {"ok": false, "message": "Zamknięte"}

## Pułapka uruchamia się przy aktywacji obiektu i znika (efekt czaru – etap 7).
func trigger_trap(c: Dictionary) -> String:
	if String(c.trap).is_empty():
		return ""
	state.set_trap(c.sid, "")
	return "Uruchomiono pułapkę (%s)" % c.trap

## Aktywacja: {"action": "travel"|"take"|"open_container"|"locked"|"none", "message", …}.
func activate(node: Node) -> Dictionary:
	var c := snapshot(node)
	match String(c.kind):
		"door":
			var tr := trigger_trap(c)
			var u := try_unlock(c)
			if not u.ok:
				return {"action": "locked", "sound": "LockedDoor", "message": _join([tr, u.message])}
			if (c.dest as Dictionary).is_empty():
				return {"action": "none", "message": _join([tr, u.message])}
			var dr: Dictionary = records.record("door", String(c.base))
			return {"action": "travel", "dest": c.dest, "sound": String(dr.get("open_sound", "")),
					"message": _join([tr, u.message])}
		"item":
			return take_ref(c)
		"container":
			var tr2 := trigger_trap(c)
			var u2 := try_unlock(c)
			if not u2.ok:
				return {"action": "locked", "sound": "LockedChest", "message": _join([tr2, u2.message])}
			return {"action": "open_container", "sid": c.sid, "base": c.base, "name": c.name,
					"message": _join([tr2, u2.message])}
	return {"action": "none", "message": ""}

static func _join(parts: Array) -> String:
	return "\n".join(parts.filter(func(p): return not String(p).is_empty()))

## Podniesienie przedmiotu ze świata do inwentarza gracza (ActionTake).
func take_ref(c: Dictionary) -> Dictionary:
	var n := int(c.count)
	var g := normalize_gold(String(c.base), n)
	inventory.add(PLAYER, {}, g[0], g[1])
	if String(c.sid).begins_with("dyn#"):
		state.remove_dynamic(c.sid)
	else:
		state.delete_ref(c.sid)
	return {"action": "take", "item": g[0], "count": g[1], "sound": item_sound(g[0], true), "message": "Podniesiono: %s%s" % [c.name, (" × %d" % n if n > 1 else "")]}

## Rekord pojemnika (CONT) referencji.
func container_record(base: String) -> Dictionary:
	return records.record("container", base)

## Przeniesienie między pojemnikiem a graczem (w obie strony). Złoto zawsze jako gold_001.
func move(from_sid: String, from_rec: Dictionary, to_sid: String, to_rec: Dictionary, id: String, count: int) -> int:
	return inventory.transfer(from_sid, from_rec, to_sid, to_rec, id, count)

func take_all(sid: String, rec: Dictionary) -> int:
	var total := 0
	for e in inventory.contents(sid, rec):
		total += inventory.transfer(sid, rec, PLAYER, {}, String(e.id), int(e.count))
	return total

## Odłożenie przedmiotu z inwentarza gracza na ziemię przed graczem (komórka wg pozycji): nowa referencja dyn#N.
func drop(id: String, count: int, cell_key: String, mw_pos: Vector3, mw_rot_z := 0.0) -> String:
	var n: int = inventory.remove(PLAYER, {}, id, count)
	if n <= 0:
		return ""
	return state.add_dynamic(id, cell_key, mw_pos, Vector3(0, 0, mw_rot_z), n)
