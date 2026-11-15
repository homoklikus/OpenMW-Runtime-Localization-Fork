class_name MWControllers
extends RefCounted
## Odtwarzanie kontrolerów NIF opisanych przez konwerter w `extras`:
##   węzły:     mw_controllers   – vis (widoczność), uv (przesuw tekstury), lookat, roll
##   materiały: mw_mat_controllers – alpha, color (diffuse/emissive/…), flip (animacja tekstur)
##   węzły:     mw_particles     – system cząsteczek → CPUParticles3D (działa też w trybie zgodności)
##   pliki .anim.json (z .kf)    – biblioteka animacji z klipami wg kluczy tekstowych
## Każdy kontroler dostaje własny AnimationPlayer (różne okresy i tryby cyklu).

static var _tex_cache := {}

static func apply(root: Node, base_dir: String) -> Dictionary:
	var st := {"controllers": 0, "particles": 0, "skipped": []}
	var nodes: Array[Node] = []
	_collect(root, nodes)
	var by_name := {}
	for n in nodes:
		var ex := MWModelCache.extras_of(n)
		if ex.has("mw_name"):
			by_name[String(ex["mw_name"])] = n
	for n in nodes:
		var ex := MWModelCache.extras_of(n)
		for c in ex.get("mw_controllers", []):
			if _node_controller(root, n, c, base_dir, by_name):
				st.controllers += 1
			else:
				st.skipped.append(String(c.get("type", "?")))
		if ex.has("mw_particles"):
			if _particles(n, ex["mw_particles"], base_dir, by_name):
				st.particles += 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m == null:
					continue
				var mex := MWModelCache.extras_of(m)
				if mex.has("mw_mat_controllers"):
					m = m.duplicate()
					mi.set_surface_override_material(s, m)
					for c in mex["mw_mat_controllers"]:
						if _mat_controller(root, mi, s, m, c, base_dir):
							st.controllers += 1
	return st

static func _collect(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)

# --- czas -------------------------------------------------------------------------------------
static func _new_anim(c: Dictionary) -> Animation:
	var a := Animation.new()
	var f: float = c.get("frequency", 1.0)
	if f == 0.0:
		f = 1.0
	var length := (float(c.get("stop", 0.0)) - float(c.get("start", 0.0))) / absf(f)
	a.length = maxf(length, 0.001)
	a.loop_mode = Animation.LOOP_NONE if c.get("cycle", "loop") == "clamp" else \
		(Animation.LOOP_PINGPONG if c.get("cycle") == "reverse" else Animation.LOOP_LINEAR)
	return a

## czas klucza → czas animacji Godota (t_klucza = t · f + phase, liczony od start)
static func _t(c: Dictionary, key_t: float) -> float:
	var f: float = c.get("frequency", 1.0)
	if f == 0.0:
		f = 1.0
	return clampf((key_t - float(c.get("phase", 0.0)) - float(c.get("start", 0.0))) / f, 0.0, 1e6)

static func _player(root: Node, holder: Node, a: Animation, name: String) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	ap.name = "MWCtl_%s_%d" % [name, holder.get_child_count()]
	var lib := AnimationLibrary.new()
	lib.add_animation("ctl", a)
	ap.add_animation_library("", lib)
	ap.autoplay = "ctl"
	holder.add_child(ap)
	ap.owner = root
	ap.root_node = ap.get_path_to(root) if ap.is_inside_tree() else NodePath("..")
	return ap

static func _rel(root: Node, holder: Node, target: Node) -> String:
	# ścieżka od korzenia AnimationPlayera (= holder) do celu
	return String(holder.get_path_to(target)) if holder.is_inside_tree() else _path_without_tree(holder, target)

static func _path_without_tree(from: Node, to: Node) -> String:
	var a: Array[Node] = []
	var n := from
	while n:
		a.append(n)
		n = n.get_parent()
	var b: Array[Node] = []
	n = to
	while n and not a.has(n):
		b.push_front(n)
		n = n.get_parent()
	var ups := a.find(n)
	var parts: Array[String] = []
	for i in ups:
		parts.append("..")
	for x in b:
		parts.append(String(x.name))
	return "/".join(parts) if not parts.is_empty() else "."

# --- kontrolery węzłów --------------------------------------------------------------------------
static func _node_controller(root: Node, n: Node, c: Dictionary, base_dir: String, by_name: Dictionary) -> bool:
	match String(c.get("type", "")):
		"vis":
			var a := _new_anim(c)
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(_rel(root, root, n) + ":visible"))
			a.value_track_set_update_mode(tr, Animation.UPDATE_CONTINUOUS)
			a.track_set_interpolation_type(tr, Animation.INTERPOLATION_NEAREST)
			var times: Array = c["times"]
			for i in times.size():
				a.track_insert_key(tr, _t(c, times[i]), c["values"][i] != 0)
			_player(root, root, a, "vis")
			return true
		"uv":
			if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
				return false
			var mi := n as MeshInstance3D
			var m := mi.mesh.surface_get_material(0)
			if not (m is BaseMaterial3D):
				return false
			m = m.duplicate()
			mi.set_surface_override_material(0, m)
			var a := _new_anim(c)
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(_rel(root, root, mi) + ":surface_material_override/0:uv1_offset"))
			var ku: Dictionary = c.get("u_offset", {})
			var kv: Dictionary = c.get("v_offset", {})
			var ts := {}
			for k in [ku, kv]:
				for t in k.get("times", []):
					ts[float(t)] = true
			var keys := ts.keys()
			keys.sort()
			for t in keys:
				a.track_insert_key(tr, _t(c, t), Vector3(_sample(ku, t, 0.0), _sample(kv, t, 0.0), 0))
			_player(root, root, a, "uv")
			return true
		"roll", "lookat":
			return false  # TODO: rzadkie w Morrowindzie – opisane w extras
	return false

static func _sample(k: Dictionary, t: float, def: float) -> float:
	var times: Array = k.get("times", [])
	var vals: Array = k.get("values", [])
	if times.is_empty():
		return def
	if t <= times[0]:
		return vals[0][0]
	for i in range(1, times.size()):
		if t <= times[i]:
			var x := (t - float(times[i - 1])) / maxf(float(times[i]) - float(times[i - 1]), 1e-9)
			return lerpf(vals[i - 1][0], vals[i][0], x)
	return vals[-1][0]

# --- kontrolery materiałów ----------------------------------------------------------------------
static func _mat_controller(root: Node, mi: MeshInstance3D, surf: int, m: Material, c: Dictionary, base_dir: String) -> bool:
	if not (m is BaseMaterial3D):
		return false
	var bm := m as BaseMaterial3D
	var path := _rel(root, root, mi) + ":surface_material_override/%d:" % surf
	match String(c.get("type", "")):
		"alpha":
			if bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var a := _new_anim(c)
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(path + "albedo_color"))
			var k: Dictionary = c["keys"]
			for i in k["times"].size():
				var col := bm.albedo_color
				col.a = float(k["values"][i][0])
				a.track_insert_key(tr, _t(c, k["times"][i]), col)
			_player(root, root, a, "alpha")
			return true
		"color":
			var prop := "albedo_color"
			if c.get("target") == "emissive":
				bm.emission_enabled = true
				prop = "emission"
			elif c.get("target") != "diffuse":
				return false  # ambient/specular – brak odpowiednika w BaseMaterial3D
			var a := _new_anim(c)
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(path + prop))
			var k: Dictionary = c["keys"]
			for i in k["times"].size():
				var v: Array = k["values"][i]
				a.track_insert_key(tr, _t(c, k["times"][i]), Color(v[0], v[1], v[2], bm.albedo_color.a))
			_player(root, root, a, "color")
			return true
		"flip":
			var texs: Array[Texture2D] = []
			for uri in c.get("textures", []):
				var t := _load_tex(base_dir, uri)
				if t:
					texs.append(t)
			if texs.is_empty() or float(c.get("delta", 0.0)) <= 0.0:
				return false
			var cc := c.duplicate()
			var delta: float = c["delta"]
			cc["stop"] = float(c.get("start", 0.0)) + delta * texs.size()
			var a := _new_anim(cc)
			var tr := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(tr, NodePath(path + "albedo_texture"))
			a.value_track_set_update_mode(tr, Animation.UPDATE_CONTINUOUS)
			a.track_set_interpolation_type(tr, Animation.INTERPOLATION_NEAREST)
			for i in texs.size():
				a.track_insert_key(tr, _t(cc, float(c.get("start", 0.0)) + i * delta), texs[i])
			_player(root, root, a, "flip")
			return true
	return false

static func _load_tex(base_dir: String, uri) -> Texture2D:
	if uri == null:
		return null
	var p := base_dir.path_join(String(uri)).simplify_path()
	if _tex_cache.has(p):
		return _tex_cache[p]
	var img := Image.load_from_file(p)
	var t: Texture2D = ImageTexture.create_from_image(img) if img else null
	_tex_cache[p] = t
	return t

# --- cząsteczki -----------------------------------------------------------------------------------
static func _particles(n: Node, p: Dictionary, base_dir: String, by_name: Dictionary) -> bool:
	var holder: Node = by_name.get(String(p.get("emitter", "")), n)
	var cp := CPUParticles3D.new()
	cp.name = "MWParticles"
	cp.amount = maxi(1, int(p.get("amount", 8)))
	var life: float = maxf(0.05, float(p.get("lifetime", 1.0)))
	cp.lifetime = life
	cp.randomness = clampf(float(p.get("lifetime_random", 0.0)) / life, 0.0, 1.0)
	if p.get("use_rate", false) and float(p.get("emit_rate", 0.0)) > 0.0:
		cp.amount = clampi(int(ceil(float(p["emit_rate"]) * life)), 1, 4096)
	cp.local_coords = false
	var d: Array = p.get("direction", [0, 1, 0])
	cp.direction = Vector3(d[0], d[1], d[2])
	cp.spread = clampf(float(p.get("spread_deg", 0.0)), 0.0, 180.0)
	var sp: float = p.get("speed", 0.0)
	var spr: float = p.get("speed_random", 0.0)
	cp.initial_velocity_min = maxf(0.0, sp - spr)
	cp.initial_velocity_max = sp + spr
	var ext: Array = p.get("emission_box_extents", [0, 0, 0])
	if ext[0] + ext[1] + ext[2] > 0.0:
		cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		cp.emission_box_extents = Vector3(ext[0], ext[1], ext[2])
	cp.gravity = Vector3.ZERO
	var size: float = maxf(0.01, float(p.get("size", 0.1)))
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 1))
	for m in p.get("modifiers", []):
		match String(m.get("type", "")):
			"gravity":
				var g: Array = m["direction"]
				cp.gravity = Vector3(g[0], g[1], g[2]) * float(m["force"])
			"growfade":
				curve = Curve.new()
				var grow := clampf(float(m["grow"]) / life, 0.0, 0.5)
				var fade := clampf(float(m["fade"]) / life, 0.0, 0.5)
				curve.add_point(Vector2(0, 0.0 if grow > 0 else 1.0))
				if grow > 0:
					curve.add_point(Vector2(grow, 1))
				if fade > 0:
					curve.add_point(Vector2(1.0 - fade, 1))
				curve.add_point(Vector2(1, 0.0 if fade > 0 else 1.0))
			"rotation":
				cp.angular_velocity_min = rad_to_deg(float(m["speed"]))
				cp.angular_velocity_max = rad_to_deg(float(m["speed"]))
	cp.scale_amount_curve = curve
	var ck = p.get("color_keys")
	if ck is Dictionary:
		var gr := Gradient.new()
		var times: Array = ck["times"]
		var t0: float = times[0]
		var t1: float = maxf(float(times[-1]), t0 + 1e-6)
		var offsets := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in times.size():
			var v: Array = ck["values"][i]
			offsets.append((float(times[i]) - t0) / (t1 - t0))
			cols.append(Color(v[0], v[1], v[2], v[3]))
		gr.offsets = offsets
		gr.colors = cols
		cp.color_ramp = gr
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if p.get("blend", "alpha") == "add":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var tex := _load_tex(base_dir, p.get("texture"))
	if tex:
		mat.albedo_texture = tex
	quad.material = mat
	cp.mesh = quad
	holder.add_child(cp)
	cp.set_meta("mw_particles", true)
	return true

# --- biblioteka animacji z .kf -------------------------------------------------------------------
static func load_anim_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## Dodaje do modelu AnimationPlayer "MWAnimations" z animacjami klipów (lub całości, gdy brak klipów).
static func attach_anim_library(root: Node, doc: Dictionary) -> AnimationPlayer:
	if doc.is_empty():
		return null
	var targets := _anim_targets(root)
	var full := Animation.new()
	full.length = maxf(float(doc.get("duration", 0.0)), 0.001)
	var missing := 0
	for tr in doc.get("tracks", []):
		var nm := String(tr["node"])
		if not targets.has(nm):
			missing += 1
			continue
		var tgt: Array = targets[nm]  # [ścieżka, czy kość]
		for kind in ["translation", "rotation", "scale"]:
			if not tr.has(kind):
				continue
			var ttype := Animation.TYPE_POSITION_3D if kind == "translation" else \
				(Animation.TYPE_ROTATION_3D if kind == "rotation" else Animation.TYPE_SCALE_3D)
			var ti := full.add_track(ttype)
			full.track_set_path(ti, NodePath(tgt[0]))
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
	var lib := AnimationLibrary.new()
	var clips: Dictionary = doc.get("clips", {})
	if clips.is_empty():
		lib.add_animation("all", full)
	else:
		for name in clips:
			var c: Dictionary = clips[name]
			var a := slice(full, float(c["start"]), float(c["stop"]))
			if c.get("loop_start") != null:
				a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(String(name), a)
	var ap := AnimationPlayer.new()
	ap.name = "MWAnimations"
	ap.add_animation_library("", lib)
	root.add_child(ap)
	ap.owner = root
	ap.set_meta("mw_missing_tracks", missing)
	return ap

## Mapa nazwa węzła NIF → [ścieżka względem korzenia, czy kość Skeleton3D].
static func _anim_targets(root: Node) -> Dictionary:
	var out := {}
	var nodes: Array[Node] = []
	_collect(root, nodes)
	for n in nodes:
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			for b in sk.get_bone_count():
				out[sk.get_bone_name(b)] = [_path_without_tree(root, sk) + ":" + sk.get_bone_name(b), true]
	for n in nodes:
		var nm := String(MWModelCache.extras_of(n).get("mw_name", ""))
		if nm != "" and not out.has(nm) and n is Node3D:
			out[nm] = [_path_without_tree(root, n), false]
	return out

## Wycina fragment [t0, t1] animacji (z kluczami na brzegach) i przesuwa do zera.
static func slice(src: Animation, t0: float, t1: float) -> Animation:
	var a := Animation.new()
	a.length = maxf(t1 - t0, 0.001)
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		var ti := a.add_track(ty)
		a.track_set_path(ti, src.track_get_path(i))
		a.track_set_interpolation_type(ti, src.track_get_interpolation_type(i))
		var edge := [t0, t1]
		for t in edge:
			var v = _sample_track(src, i, t)
			if v != null:
				_insert(a, ti, ty, t - t0, v)
		for k in src.track_get_key_count(i):
			var kt := src.track_get_key_time(i, k)
			if kt > t0 + 1e-5 and kt < t1 - 1e-5:
				_insert(a, ti, ty, kt - t0, src.track_get_key_value(i, k))
	return a

static func _sample_track(a: Animation, i: int, t: float):
	match a.track_get_type(i):
		Animation.TYPE_POSITION_3D:
			return a.position_track_interpolate(i, t)
		Animation.TYPE_ROTATION_3D:
			return a.rotation_track_interpolate(i, t)
		Animation.TYPE_SCALE_3D:
			return a.scale_track_interpolate(i, t)
		Animation.TYPE_VALUE:
			return a.value_track_interpolate(i, t)
	return null

static func _insert(a: Animation, ti: int, ty: int, t: float, v) -> void:
	match ty:
		Animation.TYPE_POSITION_3D:
			a.position_track_insert_key(ti, t, v)
		Animation.TYPE_ROTATION_3D:
			a.rotation_track_insert_key(ti, t, v)
		Animation.TYPE_SCALE_3D:
			a.scale_track_insert_key(ti, t, v)
		_:
			a.track_insert_key(ti, t, v)
