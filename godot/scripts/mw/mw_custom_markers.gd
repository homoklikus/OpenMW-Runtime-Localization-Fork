extends RefCounted
## Notatki na mapie jak OpenMW 0.51 CustomMarkerCollection (apps/openmw/mwgui/mapwindow.cpp, ESM::CustomMarker):
## znacznik = komórka (zewnętrzna „ext:x,y” – komórka klikniętego miejsca, wnętrze „int:nazwa”), położenie w świecie
## (jednostki MW: mWorldX, mWorldY) i notatka. Porównanie znaczników – wszystkie pola (operator==). Zapis w stanie
## gracza („custom_markers”, WindowManager::write → ESM::REC_MARK), czyszczone przy nowej grze/wczytaniu.

var main
var version := 0                 # eventMarkersChanged – okna przebudowują znaczniki przy zmianie

func _init(m = null) -> void:
	main = m

func _list() -> Array:
	var st: Dictionary = main.state.player
	if not (st.get("custom_markers") is Array):
		st["custom_markers"] = []
	return st["custom_markers"]

static func make(cell: String, x: float, y: float, note := "") -> Dictionary:
	return {"cell": cell.to_lower(), "x": x, "y": y, "note": note}

static func same(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("cell", "")) == String(b.get("cell", "")) and is_equal_approx(float(a.get("x", 0)), float(b.get("x", 0))) \
		and is_equal_approx(float(a.get("y", 0)), float(b.get("y", 0))) and String(a.get("note", "")) == String(b.get("note", ""))

func all() -> Array:
	return _list()

func size() -> int:
	return _list().size()

func add(m: Dictionary) -> void:
	_list().append(make(String(m.cell), float(m.x), float(m.y), String(m.get("note", ""))))
	version += 1

## deleteMarker / updateMarker: znacznik musi istnieć (OpenMW: wyjątek „can't find marker”) → false.
func delete(m: Dictionary) -> bool:
	var l := _list()
	for i in l.size():
		if same(l[i], m):
			l.remove_at(i)
			version += 1
			return true
	return false

func update(m: Dictionary, note: String) -> bool:
	for e in _list():
		if same(e, m):
			e["note"] = note
			version += 1
			return true
	return false

## getMarkers(cellId) – kolejność dodania.
func in_cell(cell: String) -> Array:
	var out := []
	var k := cell.to_lower()
	for e in _list():
		if String(e.cell) == k:
			out.append(e)
	return out

func notes(cell: String) -> Array:
	return in_cell(cell).map(func(e): return String(e.note))

func clear() -> void:
	main.state.player["custom_markers"] = []
	version += 1
