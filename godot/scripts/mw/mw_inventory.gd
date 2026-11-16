extends RefCounted
## Inwentarze (etap 3): zawartość pojemników, NPC i gracza – jak OpenMW (apps/openmw/mwworld/containerstore.cpp:
## fill/addInitialItem, apps/openmw/mwmechanics/levelledlist.cpp: getLevelledItem).
##
## Zawartość bez zmian w grze = rekord (CONT/NPC_/CREA „inventory”) z rozlosowanymi listami poziomowanymi (LEVI);
## losowanie jest deterministyczne: ziarno rozgrywki (GameState.seed) + sid referencji – ten sam wynik przy każdym
## wczytaniu komórki, bez zapisywania. Po pierwszej zmianie (podniesienie, przełożenie) pełna zawartość trafia do
## GameState.inventories (zapis gry).

const ITEM_FILES := ["weapon", "armor", "clothing", "book", "misc", "apparatus", "lockpick", "probe", "repair", "light",
	"potion", "ingredient"]
# kolejność typów jak w ContainerStore (iteracja: mikstury, aparaty, zbroje, książki, ubrania, składniki, światła,
# wytrychy, różne, sondy, narzędzia, broń)
const TYPE_ORDER := ["potion", "apparatus", "armor", "book", "clothing", "ingredient", "light", "lockpick", "misc",
	"probe", "repair", "weapon"]
const ITEM_EACH := 1          # ESM::ItemLevList::Each
const ITEM_ALL_LEVELS := 2    # ESM::ItemLevList::AllLevels

var records          # obiekt z metodą record(file, id) (MWActorVisual)
var state            # MWGameState
var player_level := 1
var stats := {"resolved": 0, "leveled": 0, "missing": 0}

func _init(records_source, game_state) -> void:
	records = records_source
	state = game_state

## {"kind": plik rekordu, "rec": rekord} albo {} – przedmiot, który może leżeć w inwentarzu.
## Kamień dusz z duszą: „id@stworzenie” (OpenMW: dusza w CellRef; tu – w id, osobny stos jak w OpenMW).
func item(id: String) -> Dictionary:
	var k := id.to_lower()
	var base := k.get_slice("@", 0)
	for f in ITEM_FILES:
		var r: Dictionary = records.record(f, base)
		if not r.is_empty():
			if base != k:
				return {"kind": f, "id": k, "rec": r, "soul": k.get_slice("@", 1)}
			return {"kind": f, "id": k, "rec": r}
	return {}

func is_item(id: String) -> bool:
	return not item(id).is_empty()

## Losowanie OpenMW: rollDice(n) = całkowita z [0, n), roll0to99 = rollDice(100).
static func _dice(rng: RandomNumberGenerator, n: int) -> int:
	return rng.randi_range(0, n - 1) if n > 0 else 0

## getLevelledItem: id przedmiotu albo "" (szansa „brak”, brak kandydatów na tym poziomie, nieistniejący przedmiot).
func leveled_item(list: Dictionary, rng: RandomNumberGenerator, level: int, depth := 0) -> String:
	if depth > 16:
		return ""
	if _dice(rng, 100) < int(list.get("chance_none", 0)):
		return ""
	var items: Array = list.get("items", [])
	var highest := 0
	for it in items:
		var lv := int(it.get("level", 0))
		if lv > highest and lv <= level:
			highest = lv
	var all_levels := (int(list.get("flags", 0)) & ITEM_ALL_LEVELS) != 0
	var cand := []
	for it in items:
		var lv := int(it.get("level", 0))
		if level >= lv and (all_levels or lv == highest):
			cand.append(String(it.get("id", "")).to_lower())
	if cand.is_empty():
		return ""
	var pick: String = cand[_dice(rng, cand.size())]
	var nested: Dictionary = records.record("leveleditem", pick)
	if not nested.is_empty():
		return leveled_item(nested, rng, level, depth + 1)
	if not is_item(pick):
		stats.missing += 1
		return ""
	return pick

func _rng_for(sid: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [int(state.seed) if state != null else 0, sid])
	return rng

static func _add(out: Array, id: String, count: int) -> void:
	for e in out:
		if e.id == id:
			e.count += count
			return
	out.append({"id": id, "count": count})

## addInitialItem: listy z flagą „każdy” i liczbą > 1 losowane osobno dla każdej sztuki; zagnieżdżone listy
## rozwiązywane do przedmiotu; liczby ujemne (uzupełnianie u kupców) – liczone jako wartość bezwzględna.
func _add_initial(out: Array, id: String, count: int, rng: RandomNumberGenerator, top := true) -> void:
	if count == 0:
		return
	var k := id.to_lower()
	var lev: Dictionary = records.record("leveleditem", k)
	if not lev.is_empty():
		stats.leveled += 1
		if top and absi(count) > 1 and (int(lev.get("flags", 0)) & ITEM_EACH) != 0:
			for i in absi(count):
				_add_initial(out, k, 1, rng, true)
			return
		var pick := leveled_item(lev, rng, player_level)
		if not pick.is_empty():
			_add_initial(out, pick, count, rng, false)
		return
	if not is_item(k):
		stats.missing += 1
		return
	_add(out, k, absi(count))

## Zawartość z rekordu (bez zmian z gry) – deterministyczna dla danego sid i ziarna.
func base_contents(rec: Dictionary, sid: String) -> Array:
	var out := []
	var rng := _rng_for(sid)
	for e in rec.get("inventory", []):
		_add_initial(out, String(e.get("item", "")), int(e.get("count", 1)), rng)
	stats.resolved += 1
	return out

## Bieżąca zawartość: stan gry albo rekord.
func contents(sid: String, rec: Dictionary) -> Array:
	if state != null and state.has_inventory(sid):
		return (state.inventory(sid) as Array).duplicate(true)
	return base_contents(rec, sid)

## Przedmioty posortowane jak w ContainerStore (wg typu, w obrębie typu – kolejność w inwentarzu).
func ordered(items: Array) -> Array:
	var out := []
	for t in TYPE_ORDER:
		for e in items:
			var it := item(String(e.id))
			if not it.is_empty() and it.kind == t:
				out.append({"kind": t, "id": it.id, "rec": it.rec, "count": int(e.count)})
	return out

## Przenosi count sztuk id z jednego inwentarza do drugiego (oba trafiają do GameState). Zwraca przeniesioną liczbę.
func transfer(from_sid: String, from_rec: Dictionary, to_sid: String, to_rec: Dictionary, id: String, count: int) -> int:
	var src := contents(from_sid, from_rec)
	var dst := contents(to_sid, to_rec)
	var k := id.to_lower()
	var moved := 0
	for e in src:
		if e.id == k:
			moved = mini(count, int(e.count))
			e.count -= moved
			break
	if moved <= 0:
		return 0
	_add(dst, k, moved)
	state.set_inventory(from_sid, src)
	state.set_inventory(to_sid, dst)
	return moved

func add(sid: String, rec: Dictionary, id: String, count: int) -> void:
	var items := contents(sid, rec)
	_add(items, id.to_lower(), count)
	state.set_inventory(sid, items)

## Usuwa do count sztuk; zwraca usuniętą liczbę.
func remove(sid: String, rec: Dictionary, id: String, count: int) -> int:
	var items := contents(sid, rec)
	var k := id.to_lower()
	for e in items:
		if e.id == k:
			var n := mini(count, int(e.count))
			e.count -= n
			state.set_inventory(sid, items)
			return n
	return 0

func count_of(sid: String, rec: Dictionary, id: String) -> int:
	for e in contents(sid, rec):
		if e.id == id.to_lower():
			return int(e.count)
	return 0

func total_weight(items: Array) -> float:
	var w := 0.0
	for e in items:
		var it := item(String(e.id))
		if not it.is_empty():
			w += float(it.rec.get("weight", 0.0)) * int(e.count)
	return w
