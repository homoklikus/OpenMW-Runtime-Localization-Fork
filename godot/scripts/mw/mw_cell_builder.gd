class_name MWCellBuilder
extends RefCounted
## Buduje węzeł Godota dla komórki: teren + referencje (modele GLB, światła) + metadane.
## Każda referencja to Node3D "MWRef" z meta: mw_sid, mw_base, mw_source – używane przez grę i CS 2.0.

var db: MWWorldDB
var models: MWModelCache
var editor_mode := false        # CS 2.0: bez kolizji terenu, modele jako dzieci bez właściciela
var with_lights := true
var with_water := true
var show_markers := false
var state = null                # mw_game_state.gd – różnice stanu gry (gra; w CS 2.0 brak)
var actors = null               # mw_actor_visual.gd – wygląd NPC i animacje stworzeń (etap 2)
var flora = null                # mw_flora.gd – roślinność komórek zewnętrznych (gra; w CS 2.0 wyłączona)       # znaczniki edytora widoczne także poza CS 2.0 (diagnostyka)
var stats := {"cells": 0, "refs": 0, "missing_model": 0, "no_model": 0, "markers": 0, "build_ms": 0.0}

## Obiekty-znaczniki Morrowinda: punkty docelowe zaklęć i skryptów (Interwencja Almsivi/Boska,
## więzienie, północ mapy) oraz pomocnicze znaczniki drzwi i podróży z Construction Set.
## Gra ich nie rysuje (tak samo OpenMW) – zostają w danych, bez modelu i kolizji. W CS 2.0 widoczne.
const HIDDEN_MARKERS := ["templemarker", "divinemarker", "prisonmarker", "northmarker",
		"doormarker", "travelmarker"]

static func is_hidden_marker(base_id: String) -> bool:
	return base_id.to_lower() in HIDDEN_MARKERS

const InventoryScript := preload("res://scripts/mw/mw_inventory.gd")
const ActorScript := preload("res://scripts/mw/mw_actor.gd")
const ActorVisual := preload("res://scripts/mw/mw_actor_visual.gd")

func _init(world_db: MWWorldDB, model_cache: MWModelCache) -> void:
	actors = ActorVisual.new(world_db, model_cache)
	db = world_db
	models = model_cache

func build_cell(key: String) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var c := db.get_cell(key)
	if c.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Cell_" + key.replace(":", "_").replace(",", "_").replace(" ", "_")
	root.set_meta("mw_cell_key", key)
	root.set_meta("mw_cell_name", c.get("name", ""))
	if not c.get("interior", false) and c.get("terrain") != null:
		var t := db.get_terrain(c["terrain"])
		var tn := MWTerrain.build(t, db.data_root, not editor_mode)
		if tn:
			root.add_child(tn)
	if with_water and c.get("has_water", false):
		if c.get("interior", false):
			root.add_child(MWEnvironment.water_plane(600.0, float(c.get("water_height_m", 0.0))))
		elif c.has("origin_godot"):
			var o: Array = c["origin_godot"]
			var size := MWCoords.CELL_SIZE / MWCoords.UNITS_PER_METER
			var w := MWEnvironment.water_plane(size, float(c.get("water_height_m", 0.0)))
			w.position = Vector3(o[0] + size / 2.0, w.position.y, o[2] - size / 2.0)
			root.add_child(w)
	var refs_node := Node3D.new()
	refs_node.name = "Refs"
	root.add_child(refs_node)
	for r in c.get("refs", []):
		var n := build_ref(state.apply_to_ref(r) if state != null else r)
		if n:
			refs_node.add_child(n)
	if state != null and state.has_method("dynamic_refs"):     # przedmioty położone w grze (dyn#N)
		for r in state.dynamic_refs(key):
			var dn := build_ref(r)
			if dn:
				refs_node.add_child(dn)
	# poziom wody komórki dla aktorów (pływanie NPC i stworzeń jak gracza; bez tego toną i chodzą po dnie)
	var wl := float(c.get("water_height_m", 0.0)) if c.get("has_water", false) else -INF
	for n in refs_node.get_children():
		if n.has_meta("mw_actor") and "water_level" in n:
			n.water_level = wl
	if flora != null and not editor_mode and not c.get("interior", false):
		var fl: Node3D = flora.build_cell(key)
		if fl:
			root.add_child(fl)
	stats.cells += 1
	stats.build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return root

## Punkt pojawiania się stworzenia (CreatureLevList w komórce, OpenMW: CreatureLevList::insertObjectRendering →
## getLevelledItem po poziomie gracza): wylosowane stworzenie zastępuje bazę referencji (ten sam sid – stan gry,
## AI i zapis odnoszą się do niego). Losowanie deterministyczne wg ziarna zapisu i sid (jak inwentarze).
func _spawn_leveled(r: Dictionary) -> Dictionary:
	var list: Dictionary = actors.record("leveledcreature", String(r.get("base", "")).to_lower())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|levc" % [int(state.seed) if state != null else 0, String(r.get("sid", ""))])
	var level := int((state.player as Dictionary).get("level", 1)) if state != null else 1
	var pick := _leveled_creature(list, rng, level, 0)
	if pick.is_empty():
		return {}
	var out := r.duplicate()
	out["base"] = pick
	out["leveled_from"] = String(r.get("base", ""))
	return out

func _leveled_creature(list: Dictionary, rng: RandomNumberGenerator, level: int, depth: int) -> String:
	if list.is_empty() or depth > 16 or rng.randi_range(0, 99) < int(list.get("chance_none", 0)):
		return ""
	var items: Array = list.get("items", [])
	var highest := 0
	for it in items:
		var lv := int(it.get("level", 0))
		if lv > highest and lv <= level:
			highest = lv
	var all_levels := (int(list.get("flags", 0)) & 1) != 0        # CreatureLevList::AllLevels
	var cand := []
	for it in items:
		var lv := int(it.get("level", 0))
		if level >= lv and (all_levels or lv == highest):
			cand.append(String(it.get("id", "")).to_lower())
	if cand.is_empty():
		return ""
	var pick: String = cand[rng.randi_range(0, cand.size() - 1)]
	var nested: Dictionary = actors.record("leveledcreature", pick)
	if not nested.is_empty():
		return _leveled_creature(nested, rng, level, depth + 1)
	return pick if String(db.get_object(pick).get("type", "")) == "CREA" else ""

func build_ref(r: Dictionary) -> Node3D:
	var base := db.get_object(r.get("base", ""))
	var atype := String(base.get("type", ""))
	if atype == "LEVC" and not editor_mode and actors != null and not r.get("disabled", false):
		var sp := _spawn_leveled(r)
		if not sp.is_empty():
			r = sp
			base = db.get_object(String(r.base))
			atype = String(base.get("type", ""))
	# NPC i stworzenia jako MWActor (etap 2: bez AI – stoją w miejscu; ruch i kontrolery AI w etapie 8)
	var is_actor := (atype == "NPC_" or atype == "CREA") and not editor_mode
	var n: Node3D = ActorScript.new() if is_actor else Node3D.new()
	if is_actor:
		n.kind = "npc" if atype == "NPC_" else "creature"
		n.record_id = String(r.get("base", "")).to_lower()
		n.sid = String(r.get("sid", ""))
		n.collide = true
	n.name = _safe_name(r.get("base", "ref") + "_" + String(r.get("sid", "")).get_slice("#", 1))
	n.transform = MWCoords.ref_transform(r)
	n.set_meta("mw_sid", r.get("sid", ""))
	n.set_meta("mw_base", r.get("base", ""))
	n.set_meta("mw_source", r.get("source", ""))
	if r.has("extra"):
		n.set_meta("mw_extra", r["extra"])
	stats.refs += 1
	if r.get("disabled", false):     # wyłączona w GameState (Disable, usunięta, podniesiona…) – węzeł bez modelu
		n.set_meta("mw_disabled", true)
		n.visible = false
		return n
	if is_hidden_marker(String(r.get("base", ""))):
		n.set_meta("mw_marker", true)
		stats.markers += 1
		if not (editor_mode or show_markers):
			return n
	if base.is_empty():
		n.set_meta("mw_missing_base", true)
		return n
	var btype := String(base.get("type", ""))
	if btype == "NPC_" and actors != null and actors.available():
		if actors.inventory == null and state != null:
			actors.inventory = InventoryScript.new(actors, state)
		var am: Node3D = actors.build_npc(String(r.get("base", "")), String(r.get("sid", "")).hash(), String(r.get("sid", "")))
		if am:
			_strip_collision(am)            # części ciała i ekwipunek nie kolidują z kapsułą aktora (dryf – etap 8)
			n.add_child(am)
			n.set_meta("mw_actor", "npc")
			return n
	var glb: String = base.get("glb", "")
	if not glb.is_empty():
		var m := models.instantiate(glb)
		if m:
			m.name = "Model"
			n.add_child(m)
			if btype == "CREA" and actors != null:
				actors.animate_creature(m, String(r.get("sid", "")).hash())
				n.set_meta("mw_actor", "creature")
			if is_actor:
				_strip_collision(m)
				_fit_capsule(n, m, actors.record("creature", String(r.get("base", ""))) if actors != null else {})
		else:
			stats.missing_model += 1
			n.add_child(_placeholder())
	else:
		stats.no_model += 1
	# światła ujemne (np. „dark_128”) pomijane jak w OpenMW przy oświetleniu shaderami (lightmanager.cpp:
	# „Ignore negative lights”) – w Godocie dawały czarne plamy, których OpenMW nie rysuje
	if with_lights and base.has("light") and not bool((base["light"] as Dictionary).get("negative", false)):
		var L: Dictionary = base["light"]
		var ol := OmniLight3D.new()
		ol.name = "Light"
		var col: Array = L.get("color", [255, 255, 255])
		configure_light(ol, float(L.get("radius", 256)), Color8(int(col[0]), int(col[1]), int(col[2])))
		n.add_child(ol)
	return n

## Światło jak OpenMW (lightutil.cpp configureLight + lighting_util.glsl) z domyślnymi wartościami Morrowind.ini
## (LightAttenuation: tylko liniowe, LinearValue 3, LinearMethod 1, LinearRadiusMult 1): natężenie
## 1 / (3·d / r) = r / (3·d), wygaszanie od promienia r do 2r; promień co najmniej 16 jedn. W Godocie: zanik
## 1/d (omni_attenuation 1) z energią r/3 [m] i zasięgiem 2r.
static func configure_light(ol: OmniLight3D, radius_units: float, color: Color) -> void:
	var r := maxf(radius_units, 16.0) / MWCoords.UNITS_PER_METER
	ol.light_color = color
	ol.omni_range = 2.0 * r
	ol.omni_attenuation = 1.0
	ol.light_energy = r / 3.0
	ol.light_specular = 0.0
	ol.shadow_enabled = false

## Kolizje modelu aktora (siatki bez szkieletu dostają StaticBody3D w MWModelCache) – usuwane: kapsuła aktora
## stała w nich i była wypychana (NPC „dryfowały”).
static func _strip_collision(m: Node) -> void:
	for b in m.find_children("*", "CollisionObject3D", true, false):
		b.get_parent().remove_child(b)
		b.free()

## Kapsuła stworzenia z wymiarów modelu (OpenMW: kształt kolizji z granic modelu) i brak grawitacji dla
## stworzeń tylko latających/pływających.
static func _fit_capsule(n: Node3D, m: Node3D, rec: Dictionary) -> void:
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		var p := (mi as Node3D).get_parent()
		while p != null and p != m:
			if p is Node3D:
				b = (p as Node3D).transform * b
			p = p.get_parent()
		aabb = b if first else aabb.merge(b)
		first = false
	if not first:
		n.capsule_radius = clampf(maxf(aabb.size.x, aabb.size.z) * 0.5, 0.15, 2.0)
		n.capsule_height = clampf(aabb.size.y, 0.3, 6.0)
	var walks := bool(rec.get("walks", true)) or bool(rec.get("bipedal", false))
	n.no_gravity = not walks and (bool(rec.get("flies", false)) or bool(rec.get("swims", false)))

func _placeholder() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	mi.mesh = bm
	return mi

static func _safe_name(s: String) -> String:
	for ch in [".", ":", "@", "/", "\"", "%", "#", " "]:
		s = s.replace(ch, "_")
	return s
