extends RefCounted
## Siatka ścieżek komórki (PGRD, etap 8) – jak OpenMW apps/openmw/mwmechanics/pathgrid.cpp (PathgridGraph):
## krawędzie skierowane z kosztem 300 × odległość Manhattan, składowe silnie spójne (Tarjan) – szybkie
## sprawdzenie osiągalności, A* z tą samą heurystyką; components/misc/pathgridutils (getClosestPoint).
## Punkty w jednostkach świata Morrowinda (konwerter: world/cells/*.json → "pathgrid").

var points: Array = []            # [Vector3] (MW, świat)
var edges: Array = []             # edges[v] = [[w, koszt], …]
var component: PackedInt32Array = PackedInt32Array()

static func from_cell(cell: Dictionary):
	var pg: Dictionary = cell.get("pathgrid", {})
	var g = load("res://scripts/mw/mw_pathgrid.gd").new()
	for p in pg.get("points", []):
		g.points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	g.edges.resize(g.points.size())
	for i in g.points.size():
		g.edges[i] = []
	for e in pg.get("edges", []):
		var a := int(e[0])
		var b := int(e[1])
		if a >= 0 and b >= 0 and a < g.points.size() and b < g.points.size():
			g.edges[a].append([b, manhattan(g.points[a], g.points[b])])
	g._components()
	return g

static func manhattan(a: Vector3, b: Vector3) -> float:
	return 300.0 * (absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z))

func size() -> int:
	return points.size()

## Tarjan (iteracyjnie – siatki mają do kilkuset punktów, rekurencja GDScript jest ograniczona).
func _components() -> void:
	var n := points.size()
	component.resize(n)
	component.fill(-1)
	var index := PackedInt32Array()
	index.resize(n)
	index.fill(-1)
	var low := PackedInt32Array()
	low.resize(n)
	var on_stack := PackedByteArray()
	on_stack.resize(n)
	var stack: Array = []
	var counter := 0
	var comp := 0
	for s in n:
		if index[s] != -1:
			continue
		var work: Array = [[s, 0]]
		while not work.is_empty():
			var top: Array = work.back()
			var v: int = top[0]
			var ei: int = top[1]
			if ei == 0 and index[v] == -1:
				index[v] = counter
				low[v] = counter
				counter += 1
				stack.append(v)
				on_stack[v] = 1
			var pushed := false
			var lst: Array = edges[v]
			while ei < lst.size():
				var w: int = lst[ei][0]
				ei += 1
				if index[w] == -1:
					top[1] = ei
					work.append([w, 0])
					pushed = true
					break
				elif on_stack[w] == 1:
					low[v] = mini(low[v], index[w])
			if pushed:
				continue
			top[1] = ei
			if low[v] == index[v]:
				while true:
					var w2: int = stack.pop_back()
					on_stack[w2] = 0
					component[w2] = comp
					if w2 == v:
						break
				comp += 1
			work.pop_back()
			if not work.is_empty():
				var parent: int = work.back()[0]
				low[parent] = mini(low[parent], low[v])

func connected(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a < component.size() and b < component.size() and component[a] == component[b]

## getClosestPoint: najbliższy punkt (odległość euklidesowa).
func closest(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in points.size():
		var d: float = (points[i] as Vector3).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best

## Najbliższy punkt osiągalny z punktu start (getClosestReachablePoint).
func closest_reachable(pos: Vector3, start: int) -> int:
	var best := -1
	var bd := INF
	for i in points.size():
		if not connected(start, i):
			continue
		var d: float = (points[i] as Vector3).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best

## aStarSearch → indeksy punktów od start do goal (puste, gdy niespójne).
func astar(start: int, goal: int) -> Array:
	if not connected(start, goal):
		return []
	var n := points.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(-1.0)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	g[start] = 0.0
	var open: Array = [[manhattan(points[start], points[goal]), start]]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(open[i][0]) < float(open[bi][0]):
				bi = i
		var cur: int = open[bi][1]
		open.remove_at(bi)
		if cur == goal:
			break
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		for e in edges[cur]:
			var w: int = e[0]
			if closed[w] == 1:
				continue
			var cost: float = g[cur] + float(e[1])
			if g[w] < 0.0 or cost < g[w]:
				g[w] = cost
				parent[w] = cur
				open.append([cost + manhattan(points[w], points[goal]), w])
	if start != goal and parent[goal] == -1:
		return []
	var path: Array = [goal]
	var c := goal
	while c != start:
		c = parent[c]
		path.push_front(c)
	return path

## PathFinder::buildPath (wariant siatki): najbliższy punkt startu → A* → najbliższy osiągalny punkt celu →
## cel. Bez siatki – prosto do celu. → [Vector3] (MW)
func build_path(from: Vector3, to: Vector3) -> Array:
	if points.size() < 2:
		return [to]
	var s := closest(from)
	var e := closest_reachable(to, s)
	var out: Array = []
	for i in astar(s, e):
		out.append(points[i])
	# pierwszy punkt pomijany, gdy cel jest bliżej niż on (jak w OpenMW – droga nie wraca)
	if out.size() >= 1 and from.distance_to(to) <= (out[0] as Vector3).distance_to(to):
		return [to]
	out.append(to)
	return out

## Sąsiedzi punktu (getNeighbouringPoints).
func neighbours(i: int) -> Array:
	var out := []
	for e in edges[i]:
		if int(e[0]) != i:
			out.append(points[int(e[0])])
	return out
