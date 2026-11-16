extends RefCounted
## Wygląd aktorów (etap 2): składanie NPC z części ciała i animacje NPC/stworzeń – wg OpenMW
## (apps/openmw/mwrender/npcanimation.cpp, components/sceneutil/attach.cpp).
##
## NPC: szkielet base_anim(.nif) / base_anim_female / base_animkna (rasy zwierzęce) albo własny model NPC
##   → jeden Skeleton3D „Skeleton” (kości = węzły szkieletu; kształty szkieletu – „manekin” – pomijane);
##   części ciała rasy (BODY: typ skóra, grywalne, nie „1st”; dla kobiet męskie jako zastępcze) + głowa i włosy NPC;
##   część ze skinningiem: kształty pasujące do filtra (nazwa zaczyna się od kości lub „Tri <kość>”) przepięte na
##   kości szkieletu po nazwach; część sztywna: do kości (BoneAttachment3D), lewa strona odbita (skala X −1).
## Animacje: xbase_anim (+ żeńskie/zwierzęce grupy z pierwszeństwem); bezczynność „idle” w pętli.

const PART_BONES := {  # PRT_* → kość mocowania (sPartList w OpenMW)
	0: "Head", 1: "Head", 2: "Neck", 3: "Chest", 4: "Groin", 5: "Groin", 6: "Right Hand", 7: "Left Hand",
	8: "Right Wrist", 9: "Left Wrist", 10: "Shield Bone", 11: "Right Forearm", 12: "Left Forearm",
	13: "Right Upper Arm", 14: "Left Upper Arm", 15: "Right Foot", 16: "Left Foot", 17: "Right Ankle",
	18: "Left Ankle", 19: "Right Knee", 20: "Left Knee", 21: "Right Upper Leg", 22: "Left Upper Leg",
	23: "Right Clavicle", 24: "Left Clavicle", 25: "Weapon Bone", 26: "Tail"}
const MESH_TO_PARTS := {  # BODY MP_* → PRT_* (sBodyPartMap w OpenMW; głowa i włosy osobno – z rekordu NPC)
	2: [2], 3: [3], 4: [4], 5: [6, 7], 6: [8, 9], 7: [11, 12], 8: [13, 14], 9: [15, 16], 10: [17, 18],
	11: [19, 20], 12: [21, 22], 14: [26]}

var db
var models
var _records := {}          # plik → słownik rekordów
var _index = null
var _libs := {}             # klucz animacji → AnimationLibrary (wspólna dla aktorów o tej samej budowie)
var _race_parts := {}       # (rasa, kobieta) → {PRT: rekord BODY}
var stats := {"npcs": 0, "creatures": 0, "parts": 0, "skinned": 0, "rigid": 0, "missing_parts": 0, "equipped": 0}
var equipment = null        # MWEquipment (etap 2c)

const Equipment := preload("res://scripts/mw/mw_equipment.gd")
# NpcAnimation::updateParts: kolejność slotów i priorytet bazowy (szata 11, spódnica 3, reszta 0)
const SLOT_LIST := [[11, 11], [10, 3], [0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [7, 0], [5, 0], [6, 0], [8, 0], [9, 0],
	[17, 0], [16, 0]]
const ROBE_RESERVED := [4, 5, 21, 22, 13, 14, 19, 20, 11, 12, 3]   # krocze, spódnica, nogi, ramiona, kolana, przedramiona, tułów
const SKIRT_RESERVED := [4, 21, 22]

func _init(world_db, model_cache) -> void:
	db = world_db
	models = model_cache

# --- rekordy (world/records z konwertera, etap 1) -------------------------------------------------

func records_index() -> Dictionary:
	if _index == null:
		var d = db._read_json(db.data_root.path_join("world/records/index.json"))
		_index = d if d is Dictionary else {}
	return _index

func available() -> bool:
	return not records_index().is_empty()

func record(file: String, id: String) -> Dictionary:
	if not _records.has(file):
		var d = db._read_json(db.data_root.path_join("world/records/%s.json" % file))
		_records[file] = d if d is Dictionary else {}
	return _records[file].get(id.to_lower(), {})

func _all(file: String) -> Dictionary:
	record(file, "")
	return _records[file]

# --- wybór części ciała (getBodyParts, 3. osoba) ---------------------------------------------------

func race_parts(race: String, female: bool) -> Dictionary:
	var key := race.to_lower() + ("|f" if female else "|m")
	if _race_parts.has(key):
		return _race_parts[key]
	var parts := {}
	var bodies := _all("bodypart")
	var ids := bodies.keys()
	ids.sort()
	for id in ids:
		var bp: Dictionary = bodies[id]
		if not bp.get("playable", true) or int(bp.get("mesh_type", 0)) != 0:
			continue
		if String(bp.get("race", "")).to_lower() != race.to_lower():
			continue
		if String(id).ends_with("1st"):
			continue
		var slots: Array = MESH_TO_PARTS.get(int(bp.get("part", -1)), [])
		var part_female := bool(bp.get("female", false))
		for prt in slots:
			if female and not part_female:
				if not parts.has(prt):           # męska część zastępcza dla kobiety
					parts[prt] = bp
			elif part_female == female:
				parts[prt] = bp
	_race_parts[key] = parts
	return parts

# --- szkielet ---------------------------------------------------------------------------------------

## Drzewo węzłów szkieletu (także z Skeleton3D/BoneAttachment3D z importu glTF) → [nazwa, rodzic, Transform3D lokalny].
static func flatten_skeleton(root: Node) -> Array:
	var start := _find_named(root, "Bip01")
	if start == null:
		start = root
	var out := []
	var acc := Transform3D.IDENTITY
	var p := start.get_parent()
	while p != null and p != root.get_parent() and p is Node3D:
		acc = (p as Node3D).transform * acc
		if p == root:
			break
		p = p.get_parent()
	_flat(start, "", acc, out)
	return out

static func _flat(n: Node, parent: String, acc: Transform3D, out: Array) -> void:
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		for b in sk.get_bone_count():
			var bp := sk.get_bone_parent(b)
			var local := sk.get_bone_rest(b)
			if bp < 0:
				out.append([sk.get_bone_name(b), parent, acc * sk.transform * local])
			else:
				out.append([sk.get_bone_name(b), sk.get_bone_name(bp), local])
		for c in n.get_children():
			if c is BoneAttachment3D:
				for cc in c.get_children():
					_flat(cc, (c as BoneAttachment3D).bone_name, Transform3D.IDENTITY, out)
		return
	if n is MeshInstance3D or n is ImporterMeshInstance3D or n is AnimationPlayer:
		return
	if not n is Node3D:
		return
	out.append([String(n.name), parent, acc * (n as Node3D).transform])
	for c in n.get_children():
		_flat(c, String(n.name), Transform3D.IDENTITY, out)

static func _find_named(n: Node, name: String) -> Node:
	if String(n.name) == name:
		return n
	for c in n.get_children():
		var r := _find_named(c, name)
		if r != null:
			return r
	return null

static func build_skeleton(bones: Array) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for b in bones:
		if sk.find_bone(b[0]) >= 0:
			continue
		var i := sk.get_bone_count()
		sk.add_bone(b[0])
		var pi := sk.find_bone(b[1]) if String(b[1]) != "" else -1
		if pi >= 0:
			sk.set_bone_parent(i, pi)
		sk.set_bone_rest(i, b[2])
		sk.set_bone_pose_position(i, b[2].origin)
		sk.set_bone_pose_rotation(i, b[2].basis.get_rotation_quaternion())
		sk.set_bone_pose_scale(i, b[2].basis.get_scale())
	return sk

# --- części ciała -----------------------------------------------------------------------------------

static func filter_matches(name: String, filter: String) -> bool:
	var n := name.to_lower()
	var f := filter.to_lower()
	return n.begins_with(f) or (n.begins_with("tri ") and n.substr(4).begins_with(f))

static func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)

## Część ze skinningiem: kształty pasujące do filtra przepięte na kości szkieletu (po nazwach). Zwraca liczbę.
static func attach_skinned(sk: Skeleton3D, inst: Node, filter: String) -> int:
	var meshes := []
	_meshes(inst, meshes)
	var n := 0
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.skin == null:
			continue
		var ok := filter_matches(String(m.name), filter)
		var p := m.get_parent()
		while not ok and p != null and p != inst:          # rodzice o pasującej nazwie (CopyRigVisitor)
			ok = filter_matches(String(p.name), filter)
			p = p.get_parent()
		if not ok:
			continue
		var src_sk := m.get_node_or_null(m.skeleton) as Skeleton3D
		var skin := Skin.new()
		for i in m.skin.get_bind_count():
			var bname := String(m.skin.get_bind_name(i))
			if bname.is_empty() and src_sk:
				bname = src_sk.get_bone_name(m.skin.get_bind_bone(i))
			skin.add_named_bind(bname, m.skin.get_bind_pose(i))
		var copy := MeshInstance3D.new()
		copy.name = String(m.name)
		copy.mesh = m.mesh
		for s in m.get_surface_override_material_count():
			copy.set_surface_override_material(s, m.get_surface_override_material(s))
		copy.skin = skin
		sk.add_child(copy)
		copy.skeleton = NodePath("..")
		n += 1
	return n

## Część sztywna: do kości; lewa strona odbita (jak attach.cpp w OpenMW: skala X −1 dla kości z „Left”).
static func attach_rigid(sk: Skeleton3D, inst: Node3D, bone: String) -> bool:
	if sk.find_bone(bone) < 0:
		return false
	var ba := BoneAttachment3D.new()
	ba.name = "Part_" + bone.replace(" ", "_")
	ba.bone_name = bone
	sk.add_child(ba)
	if bone.contains("Left"):
		inst.scale = Vector3(-1, 1, 1)
	ba.add_child(inst)
	return true

func _part_glb(bp: Dictionary) -> String:
	var g := String(bp.get("glb", ""))
	if g.is_empty() and bp.has("model"):
		g = "meshes/" + String(bp["model"]).replace("\\", "/").to_lower().get_basename() + ".glb"
	return g

func _attach_part(sk: Skeleton3D, prt: int, glb: String) -> void:
	var inst: Node3D = models.instantiate(glb) if not glb.is_empty() else null
	if inst == null:
		stats.missing_parts += 1
		return
	var bone: String = PART_BONES[prt]
	var filter := "Hair" if prt == 1 else bone
	var has_skin := false
	var meshes := []
	_meshes(inst, meshes)
	for m in meshes:
		if (m as MeshInstance3D).skin != null:
			has_skin = true
			break
	if has_skin:
		var n := attach_skinned(sk, inst, filter)
		stats.skinned += n
		inst.free()
		if n > 0:
			stats.parts += 1
	elif attach_rigid(sk, inst, bone):
		stats.rigid += 1
		stats.parts += 1
	else:
		inst.free()

# --- animacje ---------------------------------------------------------------------------------------

func _anim_doc(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	return MWControllers.load_anim_json(db.data_root.path_join(path)) if not path.begins_with("/") else MWControllers.load_anim_json(path)

## Biblioteka animacji dla szkieletu „Skeleton” pod korzeniem wyglądu (ścieżki „Skeleton:<kość>”).
func anim_library(key: String, docs: Array, sk: Skeleton3D) -> AnimationLibrary:
	if _libs.has(key):
		return _libs[key]
	var lib := AnimationLibrary.new()
	for doc in docs:                       # późniejszy dokument nadpisuje grupy (np. żeńskie nad bazowymi)
		if doc.is_empty():
			continue
		var full := _doc_animation(doc, sk)
		var clips: Dictionary = doc.get("clips", {})
		for name in clips:
			var c: Dictionary = clips[name]
			var a := MWControllers.slice(full, float(c["start"]), float(c["stop"]))
			var nm := String(name).to_lower()
			if c.get("loop_start") != null or nm.begins_with("idle"):
				a.loop_mode = Animation.LOOP_LINEAR
			if lib.has_animation(nm):
				lib.remove_animation(nm)
			lib.add_animation(nm, a)
	_libs[key] = lib
	return lib

static func _doc_animation(doc: Dictionary, sk: Skeleton3D) -> Animation:
	var full := Animation.new()
	full.length = maxf(float(doc.get("duration", 0.0)), 0.001)
	for tr in doc.get("tracks", []):
		var bone := String(tr["node"])
		if sk.find_bone(bone) < 0:
			continue
		for kind in ["translation", "rotation", "scale"]:
			if not tr.has(kind):
				continue
			var ttype := Animation.TYPE_POSITION_3D if kind == "translation" else \
				(Animation.TYPE_ROTATION_3D if kind == "rotation" else Animation.TYPE_SCALE_3D)
			var ti := full.add_track(ttype)
			full.track_set_path(ti, NodePath("Skeleton:" + bone))
			if tr[kind].get("interp", "linear") == "step":
				full.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
			var times: Array = tr[kind]["times"]
			var vals: Array = tr[kind]["values"]
			for i in times.size():
				var v: Array = vals[i]
				if kind == "translation":
					full.position_track_insert_key(ti, times[i], Vector3(v[0], v[1], v[2]))
				elif kind == "rotation":
					full.rotation_track_insert_key(ti, times[i], Quaternion(v[0], v[1], v[2], v[3]).normalized())
				else:
					full.scale_track_insert_key(ti, times[i], Vector3(v[0], v[1], v[2]))
	return full

static func play_idle(ap: AnimationPlayer, seed: int = 0) -> bool:
	for nm in ["idle", "Idle"]:
		if ap.has_animation(nm):
			var a := ap.get_animation(nm)
			a.loop_mode = Animation.LOOP_LINEAR
			ap.play(nm)
			if a.length > 0.0:
				ap.seek(fmod(float(abs(seed) % 1000) * 0.137, a.length), true)   # różne fazy u sąsiadów
			return true
	return false

# --- składanie --------------------------------------------------------------------------------------

## Wygląd NPC jako węzeł „Model” (albo null, gdy brak danych). npc_id – rekord NPC_.
func build_npc(npc_id: String, seed: int = 0) -> Node3D:
	var npc := record("npc", npc_id)
	if npc.is_empty():
		return null
	var race := record("race", String(npc.get("race", "")))
	var female := bool(npc.get("female", false))
	var beast := bool(race.get("beast", false))
	var actor: Dictionary = records_index().get("actor", {})
	var skels: Dictionary = actor.get("skeletons", {})
	var anims: Dictionary = actor.get("anims", {})
	var kind := "beast" if beast else ("female" if female else "male")
	var skel_glb := String(skels.get(kind, skels.get("male", "")))
	var obj: Dictionary = db.get_object(npc_id)
	if String(obj.get("glb", "")) != "" and not String(obj.get("model", "")).to_lower().contains("base_anim"):
		skel_glb = String(obj["glb"])                                   # własny model NPC jako szkielet
	var src: Node3D = models.instantiate(skel_glb) if not skel_glb.is_empty() else null
	if src == null:
		return null
	var root := Node3D.new()
	root.name = "Model"
	var sk := build_skeleton(flatten_skeleton(src))
	src.free()
	root.add_child(sk)
	# części: ekwipunek (priorytety), głowa i włosy z NPC, rasa (szyja…ogon) tam, gdzie nic nie zajęło miejsca
	var parts := npc_parts(npc, female)
	var keys := parts.keys()
	keys.sort()
	for prt in keys:
		_attach_part(sk, int(prt), String(parts[prt]))
	# animacje: baza + (żeńskie | zwierzęce) z pierwszeństwem
	var docs := [_anim_doc(String(anims.get("base", "")))]
	if kind != "male" and anims.has(kind):
		docs.append(_anim_doc(String(anims[kind])))
	var lib := anim_library(kind + "|" + skel_glb, docs, sk)
	var ap := AnimationPlayer.new()
	ap.name = "MWAnimations"
	root.add_child(ap)
	ap.add_animation_library("", lib)
	play_idle(ap, seed)
	root.set_meta("mw_actor", "npc")
	stats.npcs += 1
	return root

## Część ciała przedmiotu (PartReference): dla kobiety część żeńska, gdy podana i istnieje; inaczej męska.
func _item_part(ref: Dictionary, female: bool) -> Dictionary:
	if female and not String(ref.get("female", "")).is_empty():
		var bp := record("bodypart", String(ref["female"]))
		if not bp.is_empty():
			return bp
	if not String(ref.get("male", "")).is_empty():
		return record("bodypart", String(ref["male"]))
	return {}

static func _model_glb(model: String) -> String:
	return "" if model.is_empty() else "meshes/" + model.replace("\\", "/").to_lower().get_basename() + ".glb"

## PRT → GLB do założenia (NpcAnimation::updateParts, 3. osoba, broń schowana).
func npc_parts(npc: Dictionary, female: bool) -> Dictionary:
	if equipment == null:
		equipment = Equipment.new(self)
	var slots: Dictionary = equipment.auto_equip(npc)
	var prio := {}
	var chosen := {}
	var add := func(prt: int, p: int, glb: String) -> bool:
		if p <= int(prio.get(prt, 0)):
			return false
		prio[prt] = p
		chosen[prt] = glb
		return true
	var reserve := func(prt: int, p: int) -> void:
		if p > int(prio.get(prt, 0)):
			prio[prt] = p
			chosen.erase(prt)
	for sl in SLOT_LIST:
		var slot: int = sl[0]
		if not slots.has(slot):
			continue
		var it: Dictionary = slots[slot]
		if slot == 0:                                   # hełm zdejmuje włosy
			prio.erase(1)
			chosen.erase(1)
		var p := 0
		if it.kind == "clothing" or it.kind == "armor":
			p = ((int(sl[1]) + 1) << 1) + (1 if it.kind == "armor" else 0)
			stats.equipped += 1
			for ref in it.rec.get("parts", []):
				var bp := _item_part(ref, female)
				var prt := int(ref.get("part", -1))
				if not bp.is_empty() and not _part_glb(bp).is_empty():
					add.call(prt, p, _part_glb(bp))
				else:
					reserve.call(prt, p)
		if slot == 11:
			for prt in ROBE_RESERVED:
				reserve.call(prt, p)
		elif slot == 10:
			for prt in SKIRT_RESERVED:
				reserve.call(prt, p)
	if int(prio.get(0, 0)) < 1:
		var head := record("bodypart", String(npc.get("head", "")))
		if not head.is_empty():
			add.call(0, 1, _part_glb(head))
	if int(prio.get(1, 0)) < 1 and int(prio.get(0, 0)) <= 1:
		var hair := record("bodypart", String(npc.get("hair", "")))
		if not hair.is_empty():
			add.call(1, 1, _part_glb(hair))
	# tarcza w lewej ręce (showCarriedLeft): bez części ciała – model przedmiotu
	if slots.has(17) and slots[17].kind == "armor" and int(prio.get(10, 0)) < 1:
		var shield_glb := ""
		for ref in slots[17].rec.get("parts", []):
			if int(ref.get("part", -1)) == 10:
				shield_glb = _part_glb(_item_part(ref, female))
		if shield_glb.is_empty():
			shield_glb = _model_glb(String(slots[17].rec.get("model", "")))
		if not shield_glb.is_empty():
			add.call(10, 1, shield_glb)
	var body := race_parts(String(npc.get("race", "")), female)
	for prt in range(2, 27):
		if int(prio.get(prt, 0)) < 1 and body.has(prt):
			add.call(prt, 1, _part_glb(body[prt]))
	return chosen

## Stworzenie: model z biblioteką animacji z xname.kf (dołączoną przez MWModelCache) – bezczynność w pętli.
func animate_creature(model: Node, seed: int = 0) -> bool:
	var ap := model.get_node_or_null("MWAnimations") as AnimationPlayer
	if ap == null:
		for c in model.get_children():
			if c is AnimationPlayer:
				ap = c
				break
	if ap == null:
		return false
	stats.creatures += 1
	return play_idle(ap, seed)
