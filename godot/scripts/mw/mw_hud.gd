extends CanvasLayer
## HUD jak w Morrowindzie/OpenMW (files/data/mygui/openmw_hud.layout, apps/openmw/mwgui/hud.cpp), etap 10:
## lewy dół – paski zdrowia, magii i kondycji (65 × 12), pole broni (ikona i stan) i czaru (ikona efektu „b_”
## albo przedmiotu, szansa/ładunek), ikona skradania; prawy dół – minimapa (mapa lokalna wokół gracza z mgłą
## i kompasem textures/compass), obok – ikony działających efektów; nazwa broni/czaru po zmianie, nazwa miejsca
## po wejściu (napisy jak SandText, gasną); celownik (textures/target) i podpowiedź nad celem (nazwa obiektu,
## dla przedmiotów waga i wartość – ToolTips::getFocusObject).

const UI := preload("res://scripts/mw/mw_ui.gd")

var main
var scale_ui := 1.0
var root: Control
var bars := {}                    # kind → ProgressBar
var weap_icon: TextureRect
var weap_frame: TextureRect
var weap_bar: ProgressBar
var spell_icon: TextureRect
var spell_frame: TextureRect
var spell_bar: ProgressBar
var sneak_box: Control
var weap_box: Control
var spell_box: Control
var effects_box: HBoxContainer
var minimap: Control
var minimap_tiles: Control
var compass: TextureRect
var flash_label: Label            # nazwa broni/czaru
var cell_label: Label             # nazwa miejsca
var effects_frame: Panel
var _effects_right := 0.0
var _effects_y := 0.0
var blind_fader: ColorRect        # WindowManager::setBlindness – warstwa FadeToBlack pod HUD-em
var _blind_layer: CanvasLayer
var crosshair: Control
var crosshair_enabled := true      # [HUD] crosshair (WindowManager::showCrosshair)
var focus_panel: PanelContainer
var focus_label: Label
var _flash_t := 0.0
var _cell_t := 0.0
var _last_cell := ""
var _last_weap := ""
var _last_spell := ""
var _map_t := 0.0
var _map_key := ""
var hud_visible := true

const MINIMAP := 65.0
const MAP_TILE := 256.0           # „local map hud widget size” (OpenMW) – wielkość segmentu na minimapie

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(func(): if root != null: build())

func build() -> void:
	var vp := get_viewport().get_visible_rect().size
	scale_ui = UI.ui_scale()
	UI.setup(String(main.data_dir))
	if root != null:
		root.queue_free()
	root = Control.new()
	root.name = "HUD"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme(scale_ui)
	add_child(root)
	var s := scale_ui
	var m := 12.0 * s                          # openmw_hud.layout: paski x = 12
	# paski (od dołu: kondycja, magia, zdrowie)
	var kinds := [["health", "icons/k/health"], ["magic", "icons/k/magicka"], ["fatigue", "icons/k/fatigue"]]
	for i in 3:
		var pb := UI.progress_bar(kinds[i][0], s)
		pb.name = "Bar_" + kinds[i][0]
		pb.custom_minimum_size = Vector2(65, 12) * s
		pb.size = pb.custom_minimum_size
		pb.position = Vector2(m, vp.y - (53.0 - 15.0 * i) * s)   # y 147/162/177 w układzie 300 × 200 (od dołu)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pb)
		bars[kinds[i][0]] = pb
	flash_label = _sand_label(Vector2(m, vp.y - 82 * s), 270 * s)
	cell_label = _sand_label(Vector2(0, vp.y - 111 * s), vp.x)
	cell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# pola broni i czaru
	var wb := _box(Vector2(81 * s, vp.y - 53 * s))
	weap_box = wb
	weap_frame = _icon_rect(wb, true)
	weap_icon = _icon_rect(wb, false)
	weap_bar = UI.progress_bar("weapon_fill", s)
	weap_bar.custom_minimum_size = Vector2(36, 6) * s
	weap_bar.position = Vector2(81 * s, vp.y - 17 * s)
	weap_bar.size = weap_bar.custom_minimum_size
	weap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(weap_bar)
	var sb := _box(Vector2(121 * s, vp.y - 53 * s))
	spell_box = sb
	spell_frame = _icon_rect(sb, true)
	spell_icon = _icon_rect(sb, false)
	spell_bar = UI.progress_bar("magic_fill", s)
	spell_bar.custom_minimum_size = Vector2(36, 6) * s
	spell_bar.position = Vector2(121 * s, vp.y - 17 * s)
	spell_bar.size = spell_bar.custom_minimum_size
	spell_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spell_bar)
	sneak_box = _box(Vector2(161 * s, vp.y - 53 * s))
	var si := _icon_rect(sneak_box, false)
	si.texture = UI.texture("icons/k/stealth_sneak")
	sneak_box.visible = false
	# minimapa z kompasem
	minimap = Panel.new()
	minimap.name = "MiniMap"
	minimap.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 1)))
	minimap.size = Vector2(MINIMAP, MINIMAP) * s
	minimap.position = Vector2(vp.x - (12 + MINIMAP) * s, vp.y - (11 + MINIMAP) * s)   # 223 124 65 65
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(2, 2) * s
	clip.size = Vector2(MINIMAP - 4, MINIMAP - 4) * s
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.add_child(clip)
	minimap_tiles = Control.new()
	minimap_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(minimap_tiles)
	compass = TextureRect.new()
	compass.texture = UI.texture("textures/compass")
	compass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	compass.size = Vector2(32, 32) * s
	compass.pivot_offset = compass.size / 2.0
	compass.position = clip.size / 2.0 - compass.size / 2.0
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(compass)
	if compass.texture == null:
		var arrow := Polygon2D.new()
		var a := 7.0 * s
		arrow.polygon = PackedVector2Array([Vector2(0, -a), Vector2(a * 0.6, a * 0.7), Vector2(-a * 0.6, a * 0.7)])
		arrow.color = Color(1.0, 0.85, 0.3)
		arrow.position = compass.size / 2.0
		compass.add_child(arrow)
	# EffectBox (HUD_Box_Transparent 20 × 20, prawy dolny róg 81 × 11 od krawędzi): ikony 16 px od (2, 2), szerokość
	# rośnie w lewo – SpellIcons::updateWidgets(adjustSize)
	effects_frame = Panel.new()
	effects_frame.name = "EffectBox"
	effects_frame.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 0)))
	effects_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(effects_frame)
	effects_box = HBoxContainer.new()
	effects_box.add_theme_constant_override("separation", 0)
	effects_box.position = Vector2(2, 2) * s
	effects_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effects_frame.add_child(effects_box)
	_effects_right = vp.x - 81.0 * s
	_effects_y = vp.y - 31.0 * s
	# celownik i podpowiedź nad celem
	crosshair = TextureRect.new()
	(crosshair as TextureRect).texture = UI.texture("textures/target")
	(crosshair as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crosshair.size = Vector2(32, 32) * s if (crosshair as TextureRect).texture != null else Vector2(4, 4) * s
	crosshair.position = (vp - crosshair.size) / 2.0
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if (crosshair as TextureRect).texture == null:
		var dot := ColorRect.new()
		dot.color = Color(1, 1, 1, 0.7)
		dot.size = crosshair.size
		crosshair.add_child(dot)
	root.add_child(crosshair)
	focus_panel = PanelContainer.new()
	focus_panel.add_theme_stylebox_override("panel", UI.inner_box(UI.WINDOW_BG))
	focus_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_panel.visible = false
	root.add_child(focus_panel)
	focus_label = Label.new()
	focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_panel.add_child(focus_label)
	root.visible = hud_visible

func _sand_label(pos: Vector2, w: float) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(w, 24 * scale_ui)
	l.add_theme_color_override("font_color", UI.color("normal"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", roundi(3 * scale_ui))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	root.add_child(l)
	return l

func _box(pos: Vector2) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", UI.inner_box(Color(0, 0, 0, 1)))   # HUD_Box: BlackBG + MW_Box
	p.position = pos
	p.size = Vector2(36, 36) * scale_ui
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p

func _icon_rect(parent: Control, frame: bool) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = Vector2(2, 2) * scale_ui if not frame else Vector2(-3, -3) * scale_ui
	t.size = Vector2(32, 32) * scale_ui if not frame else Vector2(42, 42) * scale_ui
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

func set_hud_visible(on: bool) -> void:
	hud_visible = on
	if root != null:
		root.visible = on

## Wielka ikona efektu do pola czaru (SpellWidget): „b_” przed nazwą pliku (icons\s\b_tx_s_fire.dds).
static func big_icon(path: String) -> String:
	var p := path.replace("\\", "/")
	var i := p.rfind("/")
	return p.substr(0, i + 1) + "b_" + p.substr(i + 1)

func flash(text: String) -> void:
	flash_label.text = text
	_flash_t = 2.5

# --- aktualizacja ---------------------------------------------------------------------------------------

## Player::update → WindowManager::setBlindness: czarna nakładka (warstwa FadeToBlack, pod HUD-em), krycie =
## clamp(Oślepienie, 0, 100) / 100 (modyfikator z efektów; tryb boga – 0).
func update_blindness() -> void:
	if _blind_layer == null:
		_blind_layer = CanvasLayer.new()
		_blind_layer.layer = layer - 1
		blind_fader = ColorRect.new()
		blind_fader.color = Color(0, 0, 0, 0)
		blind_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
		blind_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blind_layer.add_child(blind_fader)
		add_child(_blind_layer)
	var blind := 0
	if main.magic != null and main.combat != null and main.get("god_mode") != true:
		blind = clampi(int(main.magic.magnitude_of(main.combat.player_fighter(), 47)), 0, 100)
	blind_fader.color.a = blind / 100.0
	blind_fader.visible = blind > 0

func _process(delta: float) -> void:
	if root == null or main == null or main.player == null:
		return
	update_blindness()
	# WindowManager::updateVisible: HUD widoczny zawsze (także pod menu głównym, ekwipunkiem, rozmową),
	# poza ekranem ładowania, filmem (enableScene(false)) i stanem bez gry; F11 – mHudEnabled
	var loading_on: bool = main.get("loading") != null and main.loading != null and main.loading.visible
	var video_on: bool = main.get("video") != null and main.video != null and main.video.playing
	root.visible = hud_visible and String(main.get("game_state")) != "nogame" and not loading_on and not video_on
	if not root.visible:
		return
	_apply_allowed()
	if crosshair != null:
		crosshair.visible = crosshair_enabled
	update_stats()
	update_weapon_spell()
	sneak_box.visible = bool(main.player.want_sneak)
	_fade(flash_label, delta, "_flash_t")
	var loc: String = main.display_location()
	if loc != _last_cell:
		if not _last_cell.is_empty():
			cell_label.text = loc
			_cell_t = 3.0
		_last_cell = loc
	_fade(cell_label, delta, "_cell_t")
	_map_t += delta
	if _map_t > 0.1:
		_map_t = 0.0
		update_minimap()
		update_effects()
	update_focus()

## WindowManager::updateVisible: części HUD zależne od dozwolonych okien (nowa gra – disallowAll, potem skrypty
## CharGen): paski – statystyki, broń – ekwipunek, czar i efekty – magia, minimapa – mapa.
func _apply_allowed() -> void:
	if not main.has_method("menu_allowed"):
		return
	# przypięte okno zastępuje swoją część HUD (setHMS/Weapon/Spell/MinimapVisibility: allowed && !pinned)
	var mm = main.get("menu_mode")
	var pinned := func(n: String) -> bool: return mm != null and mm.has_method("is_pinned") and mm.is_pinned(n)
	var hms: bool = main.menu_allowed("stats") and not pinned.call("stats")
	for k in bars:
		bars[k].visible = hms
	var inv: bool = main.menu_allowed("inventory") and not pinned.call("inventory")
	weap_box.visible = inv
	weap_bar.visible = inv
	var mag: bool = main.menu_allowed("magic") and not pinned.call("spells")
	spell_box.visible = mag
	spell_bar.visible = mag
	effects_box.visible = mag
	minimap.visible = main.menu_allowed("map") and not pinned.call("map")

func _fade(l: Label, delta: float, var_name: String) -> void:
	var t: float = get(var_name)
	if t > 0.0:
		t -= delta
		set(var_name, t)
	l.modulate.a = clampf(t, 0.0, 1.0)

func update_stats() -> void:
	var st: Dictionary = main.player_stats()
	if st.is_empty() or main.character == null:
		return
	var d: Dictionary = main.character.derived(st)
	var vals := {"health": [st.get("health", 0), d.health.modified], "magic": [st.get("magicka", 0), d.magicka.modified],
		"fatigue": [st.get("fatigue", 0), d.fatigue.modified]}
	for k in vals:
		var pb: ProgressBar = bars[k]
		pb.max_value = maxf(float(vals[k][1]), 1.0)
		pb.value = clampf(float(vals[k][0]), 0.0, pb.max_value)
		pb.tooltip_text = ""
		if main.get("tooltips") != null and main.tooltips != null:       # HUD: HealthToolTip jak w statystykach
			pb.set_meta("mw_tip", main.tooltips.health_tip(k, roundi(float(vals[k][0])), roundi(float(vals[k][1]))))

func update_weapon_spell() -> void:
	var inv = main.interaction.inventory
	# broń w prawej ręce (albo walka wręcz)
	var eq: Dictionary = main.player_stats().get("equipment", {})
	var we: Dictionary = eq.get(str(main.EQ.SLOT_CARRIED_RIGHT), {})
	var wname := ""
	if not we.is_empty():
		var it: Dictionary = inv.item(String(we.id))
		weap_icon.texture = UI.icon(String(it.get("rec", {}).get("icon", "")))
		weap_frame.texture = UI.icon_frame(not String(it.get("rec", {}).get("enchant", "")).is_empty(), "")
		var mh := float(it.get("rec", {}).get("health", 0))
		var h := float(we.get("health", -1.0))
		weap_bar.visible = mh > 0.0
		weap_bar.max_value = maxf(mh, 1.0)
		weap_bar.value = mh if h < 0.0 else h
		wname = main.interaction.item_name(String(it.get("kind", "")), String(we.id), it.get("rec", {}))
	else:
		weap_icon.texture = UI.texture("icons/k/stealth_handtohand")
		if weap_icon.texture == null:
			weap_icon.texture = UI.texture("icons/handtohand")
		weap_frame.texture = null
		weap_bar.visible = true                  # HUD::unsetSelectedWeapon: pasek 0 z ramką
		weap_bar.max_value = 100.0
		weap_bar.value = 0.0
		wname = _t("sSkillHandtohand", "Hand-to-hand")
	if wname != _last_weap:
		if not _last_weap.is_empty():
			flash(wname)
		_last_weap = wname
	# magia
	var sel: Dictionary = main.selected_magic()
	var sname := ""
	if sel.is_empty() or main.get("magic") == null:
		# HUD::unsetSelectedSpell: puste pole, pasek szansy 0 (ramka paska widoczna)
		spell_icon.texture = null
		spell_frame.texture = null
		spell_bar.visible = true
		spell_bar.max_value = 100.0
		spell_bar.value = 0.0
		sname = _t("sNone", "None")
	elif String(sel.get("kind")) == "spell":
		var sp: Dictionary = main.magic.records.record("spell", String(sel.id))
		var effs: Array = sp.get("effects", [])
		var icon := ""
		if not effs.is_empty():
			icon = String(main.magic.effect(int(effs[0].get("effect", -1))).get("icon", ""))
		var t := UI.icon(big_icon(icon)) if not icon.is_empty() else null
		spell_icon.texture = t if t != null else UI.icon(icon)
		spell_frame.texture = null
		spell_bar.visible = true
		spell_bar.max_value = 100.0
		spell_bar.value = main.magic.spell_chance(sp, main.combat.player_fighter()) if int(sp.get("spell_type", 0)) == main.magic.SPELL_SPELL else 100.0
		sname = String(sp.get("name", sel.id))
	else:
		var it2: Dictionary = inv.item(String(sel.id))
		spell_icon.texture = UI.icon(String(it2.get("rec", {}).get("icon", "")))
		spell_frame.texture = UI.icon_frame(true, "")
		var en: Dictionary = main.magic.item_enchantment(it2) if not it2.is_empty() else {}
		spell_bar.visible = not en.is_empty() and int(en.get("type", -1)) == main.magic.ENCH_WHEN_USED
		if spell_bar.visible:
			spell_bar.max_value = maxf(float(main.magic.enchantment_charge(en)), 1.0)
			spell_bar.value = main.magic.item_charge(main.combat.player_fighter(), String(sel.id), en)
		sname = main.interaction.item_name(String(it2.get("kind", "")), String(sel.id), it2.get("rec", {})) if not it2.is_empty() else ""
	if sname != _last_spell:
		if not sname.is_empty():
			flash(sname)
		_last_spell = sname

func _t(gm: String, def: String) -> String:
	return main.dialogue.gmst_text(gm, def) if main.dialogue != null else def

## Minimapa: segmenty mapy lokalnej wokół gracza (MAP_TILE na segment), gracz w środku, kompas obrócony wg
## kierunku patrzenia (jak w OpenMW strzałka na mapie zwróconej na północ).
func update_minimap() -> void:
	var lmap = main.get("local_map")
	if lmap == null or minimap_tiles == null:
		return
	var pp: Vector3 = main.player.global_position
	var L: Dictionary = lmap.locate(pp)
	var T := MAP_TILE * scale_ui
	var center := Vector2(MINIMAP - 4, MINIMAP - 4) * scale_ui / 2.0
	var key := "%s|%s" % [lmap.area, L.seg]
	if key != _map_key or minimap_tiles.get_child_count() == 0:
		_map_key = key
		_marker_sig = ""
		for c in minimap_tiles.get_children():
			c.queue_free()
		for sgm in lmap.visible_segments(pp):
			if (sgm - L.seg).length() > 1.5:
				continue
			if not lmap.has_render(sgm):
				lmap.request(sgm, pp.y + 60.0)
			var holder := Control.new()
			holder.set_meta("seg", sgm)
			holder.position = Vector2(sgm) * T
			holder.size = Vector2(T, T)
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			minimap_tiles.add_child(holder)
			for layer_i in 2:
				var r := TextureRect.new()
				r.name = "Map" if layer_i == 0 else "Fog"
				r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				r.stretch_mode = TextureRect.STRETCH_SCALE
				r.size = Vector2(T, T)
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				holder.add_child(r)
	for holder in minimap_tiles.get_children():
		if not holder.has_meta("seg"):
			continue
		var sgm2: Vector2i = holder.get_meta("seg")
		(holder.get_node("Map") as TextureRect).texture = lmap.texture(sgm2)
		# HudWindow: LocalMapBase(…, [Map] local map hud fog of war = false) – minimapa bez mgły
		(holder.get_node("Fog") as TextureRect).texture = lmap.fog_texture(sgm2) if hud_fog_of_war else null
	minimap_tiles.position = center - (L.f as Vector2) * T
	_update_minimap_markers(lmap, L, T)
	var cam := main.player.get_node_or_null("Camera3D") as Node3D
	var fwd: Vector3 = -(cam.global_transform.basis.z if cam != null else main.player.global_transform.basis.z)
	var q: Vector2 = lmap.to_q(Vector3(fwd.x, 0, fwd.z))
	compass.rotation = Vector2(0, -1).angle_to(q.normalized()) if q.length() > 0.001 else 0.0

var _marker_sig := ""
var minimap_markers: Array = []    # testy: węzły notatek na minimapie
var minimap_door_markers: Array = []  # testy: znaczniki drzwi na minimapie
var hud_fog_of_war := false          # [Map] local map hud fog of war (OpenMW: domyślnie false)

## LocalMapBase::updateDoorMarkers na minimapie HUD (HudWindow to LocalMapBase): drzwi z celem z wczytanych komórek
## (wnętrze – komórka, zewnątrz – komórki wokół gracza), textures\door_icon.dds 8 × 8 w kolorze normal, nad mgłą.
func _update_minimap_doors(lmap, T: float) -> void:
	var tex: Texture2D = UI.texture("textures/door_icon")
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not (n is Node3D) or not (n as Node3D).visible or MWTravel.door_destination(n).is_empty():
				continue
			var pos: Vector2 = Vector2(lmap.locate((n as Node3D).global_position).f) * T
			var w: Control
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_SCALE
				w = tr
			else:
				var cr := ColorRect.new()
				cr.color = Color(0.85, 0.15, 0.1)
				w = cr
			w.name = "DoorMarker"
			w.size = Vector2(8, 8) * scale_ui
			w.position = (pos - w.size / 2.0).floor()
			w.modulate = UI.color("normal")
			w.mouse_filter = Control.MOUSE_FILTER_IGNORE
			minimap_tiles.add_child(w)
			minimap_door_markers.append(w)

## LocalMapBase::updateCustomMarkers na minimapie HUD: znaczniki notatek komórek siatki (wnętrze – komórki).
func _update_minimap_markers(lmap, L: Dictionary, T: float) -> void:
	var cm = main.get("custom_markers")
	if cm == null:
		return
	var interior := String(main.interior)
	var g := MWCoords.cell_of(main.player.global_position)
	var sig := "%s|%s|%d|%d|%s" % [lmap.area, g, cm.version, (main.state.player.get("custom_markers", []) as Array).hash(), main.loaded.keys()]
	if sig == _marker_sig:
		return
	_marker_sig = sig
	for n in minimap_markers + minimap_door_markers:
		if is_instance_valid(n):
			n.queue_free()
	minimap_markers = []
	minimap_door_markers = []
	_update_minimap_doors(lmap, T)
	var cells := []
	if not interior.is_empty():
		cells.append("int:" + interior.to_lower())
	else:
		for x in range(g.x - 1, g.x + 2):
			for y in range(g.y - 1, g.y + 2):
				cells.append("ext:%d,%d" % [x, y])
	for ck in cells:
		for mk in cm.in_cell(ck):
			var pos: Vector2 = Vector2(lmap.locate(MWCoords.mw_to_godot(Vector3(float(mk.x), float(mk.y), 0))).f) * T
			var tex: Texture2D = UI.texture("icons/map_marker_red")
			var w: Control
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_SCALE
				w = tr
			else:
				var cr := ColorRect.new()
				cr.color = Color(0.9, 0.1, 0.1)
				w = cr
			w.name = "CustomMarker"
			w.size = Vector2(16, 16) * scale_ui
			w.position = (pos - w.size / 2.0).floor()
			w.modulate = Color(0.6, 0.6, 0.6)
			w.mouse_filter = Control.MOUSE_FILTER_IGNORE
			w.set_meta("marker", mk.duplicate())
			minimap_tiles.add_child(w)
			minimap_markers.append(w)

## Ikony działających efektów (HUD EffectBox): po jednej na rodzaj efektu, podpowiedź – nazwa i czas.
## SpellIcons::updateWidgets: ikona każdego efektu z działających czarów gracza – także zdolności, chorób, klątw i stałych
## zaklęć przedmiotów (w OpenMW wszystkie są w ActiveSpells); kolejność pierwszego wystąpienia; zanikanie ikony
## w ostatnich fMagicStartIconBlink sekundach; podpowiedź: nazwa źródła, wielkość, czas.
func update_effects() -> void:
	if main.get("magic") == null or effects_frame == null:
		return
	var me: Dictionary = main.combat.player_fighter()
	var order := []
	var info := {}
	for e in main.magic.effect_icon_list(me):
		order.append(int(e.id))
		info[int(e.id)] = e
	var blink := float(main.magic._gmst("fMagicStartIconBlink", 3.0))
	var have := {}
	for c in effects_box.get_children():
		have[int(c.get_meta("fx", -1))] = c
	for id in have:
		if not info.has(id):
			have[id].queue_free()
	var n := 0
	for id in order:
		var mg: Dictionary = main.magic.effect(id)
		var ic: TextureRect = have.get(id)
		if ic == null:
			ic = TextureRect.new()
			ic.set_meta("fx", id)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.custom_minimum_size = Vector2(16, 16) * scale_ui
			ic.texture = UI.icon(String(mg.get("icon", "")))
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			effects_box.add_child(ic)
		effects_box.move_child(ic, n)
		n += 1
		var left2 := float(info[id].left)
		ic.modulate.a = minf(left2 / blink, 1.0) if left2 >= 0.0 and blink > 0.0 else 1.0
		ic.tooltip_text = ""
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		ic.set_meta("mw_tip", {"type": "effect_icon", "id": int(id)})    # SpellIcons: ToolTipInfo (nazwa, źródła)
	var w := (n * 16.0 + 4.0) * scale_ui if n > 0 else 0.0
	effects_frame.visible = n > 0
	effects_frame.size = Vector2(w, 20.0 * scale_ui)
	effects_frame.position = Vector2(_effects_right - w, _effects_y)

## Podpowiedź nad celem (ToolTips::getFocusObject): nazwa obiektu albo osoby; przedmiot – waga i wartość;
## klawisz aktywacji w drugiej linii (zamiast paska tekstowego).
func update_focus() -> void:
	var text: String = main.focus_text() if main.has_method("focus_text") else ""
	# ToolTips::onFrame: obiekt w świecie tylko poza trybem GUI (okna, tryb menu, rozmowa – podpowiedzi okien)
	if main.has_method("_no_window_open") and not main._no_window_open():
		text = ""
	focus_panel.visible = not text.is_empty()
	if focus_panel.visible:
		focus_label.text = text
		focus_panel.reset_size()
		var vp := get_viewport().get_visible_rect().size
		focus_panel.position = Vector2((vp.x - focus_panel.size.x) / 2.0, vp.y / 2.0 + 24 * scale_ui)
