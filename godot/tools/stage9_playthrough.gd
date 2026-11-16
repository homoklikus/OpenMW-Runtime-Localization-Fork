extends SceneTree
## Etap 9: przejście fragmentu początku Morrowinda na danych z gry – nowa gra ze skryptami CharGen (statek, Seyda
## Neen, urząd celny), potem cele z --goals. Obsługa okien jak gracz: MessageBox – pierwszy przycisk, menu
## tworzenia postaci – wartości domyślne (imię z --name), rozmowa – pytania (pierwsza odpowiedź) i tematy celu,
## podążanie za eskortującym NPC (AiEscort/AiFollow gracza). Dziennik zdarzeń tylko z id i liczbami.
## godot --headless --path godot -s res://tools/stage9_playthrough.gd -- --data=DANE --newgame=morrowind
##     --scripts=1 --seconds=240 --out=wynik.json [--load=zapis] [--save=zapis]

var log_events := []
## Cele po kolei: [komórka (początek nazwy, "ext" – zewnątrz), działanie, id obiektu]; działanie: activate – podejście
## i aktywacja (drzwi, przedmioty, NPC – rozmowa), talk – rozmowa, take – podniesienie. Cel jest wykonywany,
## gdy nikt nie eskortuje gracza, nie ma okna i minęły 2 s spokoju.
const CHARGEN_GOALS := [
	["imperial prison ship", "activate", "chargen_shipdoor"],
	["ext", "approach", "chargen dock guard"],
	["ext", "activate", "chargen customs door"],
	["seyda neen, census", "approach", "chargen class"],
	["seyda neen, census", "activate", "chargen statssheet"],
	["seyda neen, census", "approach", "chargen door guard"],
	["seyda neen, census", "activate", "chargen door hall"],
	["seyda neen, census", "activate", "chargen dagger"],
	["seyda neen, census", "activate", "chargen door exit"],
	["ext", "activate", "chargen barrel fatigue"],
	["ext", "activate", "chargen door captain"],
	["seyda neen, census", "talk", "chargen captain", ["duties"]],
	["seyda neen, census", "activate", "chargen exit door"],
	["ext", "travel", "darvame hleran", "balmora"],
	["ext", "door", "balmora, caius cosades' house"],
	["balmora, caius", "talk", "caius cosades", ["report to caius cosades", "orders"]],
	["balmora, caius", "door", "ext"],
	["ext", "door", "balmora, guild of fighters"],
	["balmora, guild of fighters", "talk", "eydis fire-eye", ["join the fighters guild", "orders", "cave rat"]],
	["balmora, guild of fighters", "door", "ext"],
	["ext", "door", "balmora, drarayne thelas' house"],
	["balmora, drarayne thelas' house", "talk", "drarayne thelas", ["cave rat"]],
	["balmora, drarayne thelas' house", "activate", "in_hlaalu_door"],
	["balmora, drarayne thelas' house", "kill", "rat_cave_fgrh"],
	["balmora, drarayne thelas' house", "door", "ext"],
	["ext", "door", "balmora, drarayne thelas' storage"],
	["balmora, drarayne thelas' storage", "kill", "rat_cave_fgrh"],
	["balmora, drarayne thelas' storage", "door", "ext"],
	["ext", "door", "balmora, drarayne thelas' house"],
	["balmora, drarayne thelas' house", "talk", "drarayne thelas", ["cave rat"]],
	["balmora, drarayne thelas' house", "door", "ext"],
	["ext", "door", "balmora, guild of fighters"],
	["balmora, guild of fighters", "talk", "eydis fire-eye", ["cave rat"]],
]
var approach: Node3D = null
var topics_todo: Array = []
var approach_t := 0.0
var goals: Array = []
var goal_i := 0
var calm_t := 0.0
var t0 := 0
var main

func _init() -> void:
	_run.call_deferred()

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def

func _ev(kind: String, data := {}) -> void:
	var e := {"t": snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), "kind": kind}
	e.merge(data)
	log_events.append(e)
	print("EV ", JSON.stringify(e))

func _escort_leader() -> Node3D:
	for n in main.ai.actor_nodes():
		var p: Dictionary = main.ai.current_package(n)
		if String(p.get("type", "")) in ["escort", "follow"] and String(p.get("target", "player")).to_lower() == "player":
			return n
	return null

func _find(base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base.to_lower() and not n.get_meta("mw_disabled", false):
				return n
	return null

## Drzwi prowadzące do komórki (nazwa wnętrza albo „ext” – na zewnątrz) we wczytanych komórkach.
func _door_to(dest: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if n.get_meta("mw_disabled", false):
				continue
			var c: Dictionary = main.interaction.snapshot(n)
			if String(c.get("kind", "")) != "door":
				continue
			var e: Dictionary = c.get("extra", {})
			if not e.has("door_dest"):
				continue
			var dc := String(e.get("door_dest_cell", "")).to_lower()
			if (dest == "ext" and dc.is_empty()) or (dest != "ext" and dc == dest.to_lower()):
				return n
	return null

func _any_hostile() -> bool:
	for n in main.ai.actor_nodes():
		if main.ai.in_combat(n) and not main.combat.is_dead(main.combat.fighter_of(n)):
			return true
	return false

func _alive(base: String) -> Array:
	var out := []
	for n in main.ai.actor_nodes():
		if String(n.get_meta("mw_base", "")).to_lower() == base and not main.combat.is_dead(main.combat.fighter_of(n)):
			out.append(n)
	return out

## Walka gracza: dobyta broń, zwrot do celu, ciosy co 0,7 s z pełną siłą (jak przytrzymanie przycisku).
func _fight(target: Node3D) -> void:
	if main.combat.weapon(main.combat.player_fighter()).is_empty():
		for e in main.interaction.inventory.contents("player", {}):
			if String(main.interaction.inventory.item(String(e.id)).get("kind", "")) == "weapon":
				main.equip_item(String(e.id))
				_ev("equip", {"id": e.id})
				break
	main.weapon_drawn = true
	var d: Vector3 = main.player.global_position - target.global_position
	d.y = 0
	main.player.global_position = target.global_position + (d.normalized() if d.length() > 0.01 else Vector3.BACK) * 0.8 + Vector3(0, 0.2, 0)
	var to: Vector3 = target.global_position - main.player.global_position
	main.player.rotation.y = atan2(-to.x, -to.z)
	var cam := main.player.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.rotation.x = -0.35
	main._attack_hold = 1.0
	var r: Dictionary = main.player_attack()
	var pf: Dictionary = main.combat.player_fighter()
	_ev("attack", {"target": target.get_meta("mw_base", ""), "hit": bool(r.get("hit", r.get("success", false))), "damage": snappedf(float(r.get("damage", 0.0)), 0.1),
		"chance": snappedf(float(r.get("chance", -1)), 0.1), "fatigue": snappedf(main.combat.fatigue(pf), 0.1), "skill": main.combat.weapon_skill(main.combat.weapon(pf)),
		"player_health": snappedf(main.combat.health(pf), 0.1), "target_health": snappedf(main.combat.health(main.combat.fighter_of(target)), 0.1)})
	# kolejny cios po czasie animacji ataku (≈ 1 s / szybkość broni + 0,2 s), w czasie gry
	var w: Dictionary = main.combat.weapon(main.combat.player_fighter())
	var game_s := 1.0 / maxf(0.5, float(w.get("rec", {}).get("speed", 1.0))) + 0.2
	for i in maxi(4, int(game_s * 60.0 / Engine.time_scale)):
		await process_frame

func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	var last := {"cell": "", "cgs": -999.0, "journal": {}, "menus": {}, "controls": {}}
	var secs := float(_arg("seconds", "240"))
	var dl = main.dialogue
	var name := _arg("name", "Testowy")
	goals = CHARGEN_GOALS.duplicate(true)
	goal_i = int(_arg("goal-start", "0"))
	Engine.time_scale = float(_arg("speed", "1"))
	if not _arg("goals").is_empty():
		goals = JSON.parse_string(FileAccess.get_file_as_string(_arg("goals")))
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		if goal_i >= goals.size() and calm_t > 3.0:
			break
		await process_frame
		# okna
		if main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible:
			_ev("messagebox", {"buttons": main.msgbox.find_children("*", "Button", true, false).size()})
			main.press_message_button(0)
		if main.chargen != null and main.chargen.visible:
			var st: String = main.chargen.step
			if st == "name":
				main.chargen.name_edit.text = name
			for kind in ["race", "class", "birthsign"]:
				if not _arg(kind).is_empty() and (st == kind or (st == "birth" and kind == "birthsign")):
					main.chargen.choose(kind, _arg(kind))
			_ev("chargen_menu", {"step": st})
			main.chargen._create()
		if main.item_window != null and main.item_window.visible and main.item_window.mode == "container":
			_ev("container", {"id": main.item_window.cont_sid, "items": main.interaction.inventory.contents(main.item_window.cont_sid, main.item_window.cont_rec).size()})
			main.item_window._take_all()
			main.item_window.close()
		if main.dialogue_window != null and main.dialogue_window.visible:
			if dl.in_choice and not dl.choices.is_empty():
				_ev("dialogue_choice", {"actor": dl.actor.get("base", ""), "n": int(dl.choices[0][1])})
				dl.answer(int(dl.choices[0][1]))
			elif not topics_todo.is_empty():
				var tp := String(topics_todo.pop_front())
				_ev("dialogue_topic", {"actor": dl.actor.get("base", ""), "topic": tp, "known": tp in dl.available_topics()})
				dl.select_topic(tp)
				if main.dialogue_window.has_method("refresh"):
					main.dialogue_window.refresh()
			else:
				_ev("dialogue_end", {"actor": dl.actor.get("base", ""), "topics": dl.available_topics().size()})
				main.dialogue_window.close(true)
		# podążanie za eskortą
		var lead := _escort_leader()
		if lead != null and main.ai.mw_pos(lead).distance_to(main.ai.mw_pos(main.player)) > 260.0:
			var back := Vector3(sin(lead.rotation.y), 0, cos(lead.rotation.y)) * 1.5
			main.player.global_position = lead.global_position + back + Vector3(0, 0.2, 0)
		# podejście do NPC: gracz trzyma się obok, aż skrypt NPC zareaguje (blokada sterowania / menu) albo 25 s
		if approach != null and is_instance_valid(approach):
			approach_t += Engine.time_scale / 60.0
			if main.scripts.game.menu_mode() or not main.control_allowed("controls") or approach_t > 25.0:
				_ev("approach_done", {"id": approach.get_meta("mw_base", ""), "t_wait": snappedf(approach_t, 0.1)})
				approach = null
			elif approach.global_position.distance_to(main.player.global_position) > 1.1:
				var d2: Vector3 = main.player.global_position - approach.global_position
				d2.y = 0
				main.player.global_position = approach.global_position + (d2.normalized() if d2.length() > 0.01 else Vector3.BACK) * 0.9 + Vector3(0, 0.3, 0)
			continue
		# cele
		var busy: bool = lead != null or main.scripts.game.menu_mode() or not main.control_allowed("controls")
		calm_t = 0.0 if busy else calm_t + Engine.time_scale / 60.0
		if goal_i < goals.size() and calm_t > 2.0:
			var g: Array = goals[goal_i]
			var here: String = (main.interior if not main.interior.is_empty() else "ext").to_lower()
			if main.combat.is_dead(main.combat.player_fighter()):
				_ev("player_dead", {"cell": here})
				break
			if here.begins_with(String(g[0]).to_lower()) and String(g[1]) == "kill":
				var pf0: Dictionary = main.combat.player_fighter()
				if main.combat.health(pf0) < 0.7 * main.combat.max_health(pf0) and not _any_hostile():
					var hours := 0
					while hours < 12 and main.combat.health(pf0) < main.combat.max_health(pf0):
						main.character.rest_hour(main.player_stats(), true)     # odpoczynek (T) przed walką
						main.envr.advance(1.0)
						hours += 1
					_ev("rest", {"hours": hours, "health": snappedf(main.combat.health(pf0), 0.1)})
				var victims := _alive(String(g[2]))
				if victims.is_empty():
					_ev("goal", {"goal": goal_i, "action": "kill", "id": g[2], "done": true})
					goal_i += 1
				else:
					await _fight(victims[0])
				continue
			if here.begins_with(String(g[0]).to_lower()):
				var node := _door_to(String(g[2])) if String(g[1]) == "door" else _find(String(g[2]))
				if node == null:
					_ev("goal_missing", {"goal": goal_i, "id": g[2]})
					goal_i += 1
				else:
					var dir: Vector3 = main.player.global_position - node.global_position
					dir.y = 0
					main.player.global_position = node.global_position + (dir.normalized() if dir.length() > 0.01 else Vector3.BACK) * 1.2 + Vector3(0, 0.3, 0)
					await process_frame
					match String(g[1]):
						"talk":
							topics_todo = (g[3] as Array).duplicate() if g.size() > 3 else []
							main.open_dialogue(node)
						"approach":
							approach = node
							approach_t = 0.0
						"travel":
							var a: Dictionary = dl.make_actor(node)
							var offers: Array = main.trade.travel_offers(a)
							var pick := -1
							for o in offers:
								if String(o.name).to_lower().contains(String(g[3]).to_lower()):
									pick = int(o.index)
							var gold: int = main.interaction.inventory.count_of("player", {}, "gold_001")
							var ok_t: bool = pick >= 0 and main.trade.travel(a, pick)
							_ev("travel", {"to": g[3], "offers": offers.size(), "ok": ok_t, "gold_paid": gold - main.interaction.inventory.count_of("player", {}, "gold_001")})
						_: main.activate(node)
					_ev("goal", {"goal": goal_i, "action": g[1], "id": g[2]})
					goal_i += 1
					calm_t = 0.0
		# zmiany stanu
		var cell: String = main.interior if not main.interior.is_empty() else "ext:" + str(MWCoords.cell_of(main.player.global_position))
		if main.combat.is_dead(main.combat.player_fighter()):
			_ev("player_dead", {"cell": cell})
			break
		if cell != last.cell:
			_ev("cell", {"cell": cell, "health": snappedf(main.combat.health(main.combat.player_fighter()), 0.1), "max": snappedf(main.combat.max_health(main.combat.player_fighter()), 0.1)})
			last.cell = cell
		var cgs := float(main.state.globals.get("chargenstate", -1))
		if cgs != last.cgs:
			_ev("chargenstate", {"value": cgs})
			last.cgs = cgs
		if JSON.stringify(main.state.journal) != JSON.stringify(last.journal):
			_ev("journal", {"journal": main.state.journal.duplicate()})
			last.journal = main.state.journal.duplicate()
		var menus: Dictionary = main.state.player.get("menus", {})
		if JSON.stringify(menus) != JSON.stringify(last.menus):
			_ev("menus", {"menus": menus.duplicate()})
			last.menus = menus.duplicate()
		var ctl: Dictionary = main.state.player.get("controls", {})
		if JSON.stringify(ctl) != JSON.stringify(last.controls):
			_ev("controls", {"controls": ctl.duplicate()})
			last.controls = ctl.duplicate()
	Engine.time_scale = 1.0
	if not _arg("save").is_empty():
		var se: String = main.save_game(_arg("save"))
		_ev("save", {"ok": se == "", "goal_next": goal_i})
	var rep: Dictionary = main.scripts.report()
	var out := {"events": log_events, "goal_next": goal_i, "player": {"cell": last.cell, "pos": main.ai.mw_pos(main.player).round(),
		"character": {"name": main.player_stats().get("name", ""), "race": main.player_stats().get("race", ""),
		"class": main.player_stats().get("class", ""), "birthsign": main.player_stats().get("birthsign", "")}},
		"scripts": {"unsupported": rep.get("unsupported"), "errors": rep.get("errors"), "partial": rep.get("partial")}}
	print("END ", JSON.stringify(out.player), " ", JSON.stringify(out.scripts))
	var f := FileAccess.open(_arg("out"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	quit(0)
