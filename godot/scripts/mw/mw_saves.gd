extends RefCounted
## Zapisy pogrupowane według postaci jak OpenMW MWState::CharacterManager / Character / QuickSaveManager:
## <zapisy>/<Postać>/<opis>.mwsave – katalog postaci z imienia (znaki ASCII alfanumeryczne, reszta „_”,
## przy kolizji „ - N”), plik slotu z opisu tak samo; sloty od najnowszego (Character::begin = rbegin),
## postacie od tej z najnowszym zapisem; zapisy innej gry (pierwszy plik .esm) i pliki nieczytelne są pomijane
## (Character::addSlot ignoruje nieprawidłowe). Szybki zapis: opis „Quicksave”, najstarszy z [Saves] max quicksaves
## nadpisywany. Zgodność wsteczna: zapisy z katalogu głównego (sprzed tego etapu, np. quicksave.mwsave) tworzą
## osobną pozycję postaci (z imienia w zapisie); nowe zapisy tej postaci idą już do katalogu postaci.

const GameStateScript := preload("res://scripts/mw/mw_game_state.gd")
const EXT := ".mwsave"

var root := ""
var game := ""                   # pierwszy plik .esm treści (getFirstGameFile)
var characters: Array = []       # [{"path", "dir", "legacy", "slots": [{"path", "mtime", "header"}]}]
var current = null               # postać bieżącej gry (słownik z characters) albo null
var max_quicksaves := 1
var _cache := {}                 # ścieżka → [mtime, nagłówek|null]

func _init(saves_root: String, first_game: String) -> void:
	root = saves_root
	game = first_game.to_lower()

static func first_game_file(content: Array) -> String:
	for c in content:
		var n := String(c.get("name", "") if c is Dictionary else c)
		if n.to_lower().ends_with(".esm") or n.to_lower().ends_with(".omwgame"):
			return n
	return ""

static func sanitize(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text.unicode_at(i)
		var ok := ch <= 0x7F and ((ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122))
		out += char(ch) if ok else "_"
	return out

## Nagłówek slotu (z pliku, z pamięcią podręczną według czasu modyfikacji); null – plik nieczytelny/obcej gry.
## Po zapisie do pliku: nagłówek z pamięci podręcznej nieaktualny (czas pliku ma rozdzielczość sekundy – nadpisanie
## w tej samej sekundzie nie zmienia klucza).
func forget(path: String) -> void:
	_cache.erase(path)

func read_header(path: String):
	var mt := FileAccess.get_modified_time(path)
	if _cache.has(path) and int(_cache[path][0]) == mt:
		return _cache[path][1]
	var h = null
	var raw := GameStateScript.read_file(path)
	if not raw.has("error") and String(raw.get("format", "")) == GameStateScript.FORMAT:
		h = (raw.get("header", {}) as Dictionary).duplicate()
		var content: Array = h.get("content", [])
		var fg := first_game_file(content).to_lower()
		if not game.is_empty() and not fg.is_empty() and fg != game:
			h = null
		elif h != null:
			# zapisy sprzed etapu: opis z nazwy pliku, imię z danych postaci
			if String(h.get("description", "")).is_empty():
				h["description"] = path.get_file().get_basename()
			if String(h.get("player_name", "")).is_empty():
				var ch: Dictionary = (raw.get("player", {}) as Dictionary).get("character", {})
				h["player_name"] = String(ch.get("name", ""))
				h["player_level"] = int(ch.get("level", (raw.get("player", {}) as Dictionary).get("level", 1)))
			h["legacy"] = not h.has("time_played")
	_cache[path] = [mt, h]
	return h

func _slots_in(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(EXT):
			continue
		var p := dir.path_join(f)
		var h = read_header(p)
		if h == null:
			continue
		out.append({"path": p, "mtime": FileAccess.get_modified_time(p), "header": h})
	# najnowszy pierwszy (OpenMW: last_write_time z dokładnością do nanosekund); czas pliku w Godocie ma sekundy –
	# remis rozstrzyga czas zapisu z nagłówka z ułamkami sekund (created_unix), potem napis „created”
	out.sort_custom(func(a, b):
		if int(a.mtime) != int(b.mtime):
			return int(a.mtime) > int(b.mtime)
		var ua := float(a.header.get("created_unix", 0.0))
		var ub := float(b.header.get("created_unix", 0.0))
		if ua != ub:
			return ua > ub
		return String(a.header.get("created", "")) > String(b.header.get("created", "")))
	return out

## CharacterManager: katalogi postaci (i zapisy z katalogu głównego jako postacie „legacy”).
func refresh() -> void:
	var cur_path: String = current.path if current != null else ""
	characters.clear()
	var d := DirAccess.open(root)
	if d != null:
		for sub in d.get_directories():
			var p := root.path_join(sub)
			var slots := _slots_in(p)
			if not slots.is_empty():
				characters.append({"path": p, "dir": sub, "legacy": false, "slots": slots})
		var by_name := {}
		for s in _slots_in(root):
			var nm := String(s.header.get("player_name", ""))
			if not by_name.has(nm):
				by_name[nm] = {"path": root, "dir": "", "legacy": true, "name": nm, "slots": []}
				characters.append(by_name[nm])
			by_name[nm].slots.append(s)
	characters.sort_custom(func(a, b): return int(a.slots[0].mtime) > int(b.slots[0].mtime))
	current = null
	for c in characters:
		if not cur_path.is_empty() and c.path == cur_path and not c.legacy:
			current = c

func has_any() -> bool:
	return not characters.is_empty()

## Character::getSignature – zapis z najwyższym poziomem, przy remisie najnowszy.
func signature(c: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for s in c.slots:
		if best.is_empty() or int(s.header.get("player_level", 0)) > int(best.header.get("player_level", 0)) \
				or (int(s.header.get("player_level", 0)) == int(best.header.get("player_level", 0)) and int(s.mtime) > int(best.mtime)):
			best = s
	return best.header if not best.is_empty() else {}

## CharacterManager::createCharacter.
func create_character(name: String) -> Dictionary:
	var base := sanitize(name)
	var p := root.path_join(base)
	var i := 0
	while DirAccess.dir_exists_absolute(p) or FileAccess.file_exists(p):
		i += 1
		p = root.path_join("%s - %d" % [base, i])
	DirAccess.make_dir_recursive_absolute(p)
	var c := {"path": p, "dir": p.get_file(), "legacy": false, "slots": []}
	characters.push_front(c)
	return c

## Character::addSlot: ścieżka nowego slotu z opisu (unikalna).
func new_slot_path(c: Dictionary, description: String) -> String:
	var base := sanitize(description)
	var p := String(c.path).path_join(base + EXT)
	var i := 0
	while FileAccess.file_exists(p):
		i += 1
		p = String(c.path).path_join("%s - %d%s" % [base, i, EXT])
	return p

## QuickSaveManager::getNextQuickSaveSlot: null – nowy slot; inaczej najstarszy szybki zapis do nadpisania.
func quick_slot(c, name: String):
	if c == null:
		return null
	var same := (c.slots as Array).filter(func(s): return String(s.header.get("description", "")) == name)
	if same.size() < max_quicksaves:
		return null
	var oldest = null
	for s in same:
		if oldest == null or int(s.mtime) <= int(oldest.mtime):
			oldest = s
	return oldest

func find_slot(path: String) -> Array:
	for c in characters:
		for s in c.slots:
			if String(s.path) == path:
				return [c, s]
	return []

## CharacterManager::deleteSlot (po potwierdzeniu w oknie): plik slotu (i jego kopia .bak); pusty katalog postaci
## usuwany (Character::cleanup – tylko gdy naprawdę pusty).
func delete_slot(c: Dictionary, s: Dictionary) -> bool:
	var p := String(s.path)
	if DirAccess.remove_absolute(p) != OK:
		return false
	if FileAccess.file_exists(p + ".bak"):
		DirAccess.remove_absolute(p + ".bak")
	_cache.erase(p)
	(c.slots as Array).erase(s)
	if (c.slots as Array).is_empty():
		if not c.legacy:
			var d := DirAccess.open(String(c.path))
			if d != null and d.get_files().is_empty() and d.get_directories().is_empty():
				DirAccess.remove_absolute(String(c.path))
		characters.erase(c)
		if current == c:
			current = null
	return true

## Najnowszy zapis bieżącej postaci (quickLoad: currentCharacter->begin()).
func latest(c) -> String:
	if c == null or (c.slots as Array).is_empty():
		return ""
	return String(c.slots[0].path)
