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

## Stan przedmiotu (CellRef::charge OpenMW – wytrzymałość broni i pancerza, użycia wytrychów, sond i narzędzi
## naprawczych): egzemplarz niepełny to osobny stos „id#c:N” (OpenMW nie łączy w stos przedmiotów o różnym stanie);
## stos bez przyrostka – stan pełny. Jak kamień dusz z duszą („id@stworzenie”) – stan w identyfikatorze stosu.
static func base_id(id: String) -> String:
	return id.to_lower().get_slice("#", 0).get_slice("@", 0)

## Stan zapisany w identyfikatorze stosu albo −1 (pełny).
static func charge_of(id: String) -> float:
	var i := id.find("#c:")
	return float(id.substr(i + 3)) if i >= 0 else -1.0

## Identyfikator stosu dla stanu: pełny (charge < 0 albo ≥ max) – bez przyrostka.
static func charged_id(id: String, charge: float, max_charge: float) -> String:
	var b := id.to_lower().get_slice("#", 0)
	if charge < 0.0 or (max_charge > 0.0 and charge >= max_charge):
		return b
	return "%s#c:%d" % [b, int(charge)]

## Największy stan przedmiotu (getItemMaxHealth): wytrzymałość broni i pancerza, użycia wytrychów, sond, narzędzi.
static func max_charge(rec: Dictionary) -> float:
	return float(rec.get("health", rec.get("uses", 0)))

## Class::hasItemHealth: broń z wytrzymałością (bez amunicji i broni miotanej – WeaponType bez HasHealth), pancerz,
## wytrychy, sondy, narzędzia naprawcze (liczba użyć).
static func has_item_health(kind: String, rec: Dictionary) -> bool:
	return kind in ["armor", "lockpick", "probe", "repair"] or (kind == "weapon" and int(rec.get("weapon_type", 0)) < 11)

## Identyfikator stosu przedmiotu z referencji w świecie: dusza kamienia (XSOL) i stan (INTV – CellRef::getCharge)
## przechodzą do stosu jak w OpenMW (ContainerStore::stacks – różny stan albo dusza: osobne stosy).
func ref_stack_id(base: String, extra: Dictionary) -> String:
	var k := base.to_lower()
	var soul := String(extra.get("soul", "")).to_lower()
	if not soul.is_empty() and k.begins_with("misc_soulgem"):
		k = k + "@" + soul
	var it := item(k)
	if not it.is_empty() and extra.has("health") and has_item_health(String(it.kind), it.rec):
		k = charged_id(k, float(extra.health), max_charge(it.rec))
	return k

## {"kind": plik rekordu, "rec": rekord} albo {} – przedmiot, który może leżeć w inwentarzu.
## Kamień dusz z duszą: „id@stworzenie” (OpenMW: dusza w CellRef; tu – w id, osobny stos jak w OpenMW).
func item(id: String) -> Dictionary:
	var k := id.to_lower()
	var base := base_id(k)
	for f in ITEM_FILES:
		var r: Dictionary = records.record(f, base)
		if not r.is_empty():
			var out := {"kind": f, "id": k, "rec": r}
			if k.get_slice("#", 0).contains("@"):
				out["soul"] = k.get_slice("#", 0).get_slice("@", 1)
			if k.contains("#c:"):
				out["charge"] = charge_of(k)
			return out
	return {}

## Bieżący stan egzemplarza (stos „id#c:N” albo pełny wg rekordu).
func item_charge(id: String) -> float:
	var c := charge_of(id)
	if c >= 0.0:
		return c
	var it := item(id)
	return max_charge(it.rec) if not it.is_empty() else 0.0

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
			if e.has("parts"):
				e["parts"] = stacks_of(e) + [count] if count > 0 else stacks_of(e)
			return
	out.append({"id": id, "count": count})

## ContainerStore::stacks: przedmioty ze skryptem nigdy nie łączą się w stos – każda dodana porcja (wpis NPCO
## rekordu, podniesiona referencja, przełożona część) to osobny stos. Wpis inwentarza trzyma wtedy „parts”: liczby
## sztuk kolejnych stosów (suma = count).
func is_scripted(id: String) -> bool:
	var it := item(id)
	return not it.is_empty() and not String(it.rec.get("script", "")).is_empty()

func _put(out: Array, id: String, count: int) -> void:
	if count <= 0 or not is_scripted(id):
		_add(out, id, count)
		return
	for e in out:
		if e.id == id:
			var parts := stacks_of(e)
			e.count += count
			parts.append(count)
			e["parts"] = parts
			return
	out.append({"id": id, "count": count, "parts": [count]})

## Odjęcie n sztuk z wpisu; stosy (parts) ubywają od ostatniego (najnowszego).
static func _take(e: Dictionary, n: int) -> void:
	var parts := stacks_of(e) if e.has("parts") else []
	e.count -= n
	if e.has("parts"):
		var left := n
		while left > 0 and not parts.is_empty():
			var last := int(parts[-1])
			if last <= left:
				left -= last
				parts.pop_back()
			else:
				parts[-1] = last - left
				left = 0
		e["parts"] = parts

## Liczby sztuk stosów wpisu (parts uzgodnione z count; bez parts – jeden stos).
static func stacks_of(e: Dictionary) -> Array:
	var c := int(e.get("count", 0))
	if not e.has("parts"):
		return [c] if c > 0 else []
	var out := []
	var sum := 0
	for p in e.parts:
		var n := mini(int(p), c - sum)
		if n > 0:
			out.append(n)
			sum += n
	if sum < c:
		out.append(c - sum)
	return out

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
	_put(out, k, absi(count))

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
			_take(e, moved)
			break
	if moved <= 0:
		return 0
	_put(dst, k, moved)
	state.set_inventory(from_sid, src)
	state.set_inventory(to_sid, dst)
	return moved

func add(sid: String, rec: Dictionary, id: String, count: int) -> void:
	var items := contents(sid, rec)
	_put(items, id.to_lower(), count)
	state.set_inventory(sid, items)

## Usuwa do count sztuk; zwraca usuniętą liczbę.
func remove(sid: String, rec: Dictionary, id: String, count: int) -> int:
	var items := contents(sid, rec)
	var k := id.to_lower()
	for e in items:
		if e.id == k:
			var n := mini(count, int(e.count))
			_take(e, n)
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
