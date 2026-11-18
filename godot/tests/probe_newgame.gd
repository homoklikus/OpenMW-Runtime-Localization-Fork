extends SceneTree
## Sonda całej nowej gry (CharGen) z agentem gracza – na RZECZYWISTYCH danych (Morrowind.esm przekonwertowany
## lokalnie; nie wchodzi do repozytorium). Uruchomienie:
##   godot --headless --path godot -s res://tests/probe_newgame.gd -- --data=WYNIKI --project=KATALOG --newgame=morrowind
## (PROBE_SECONDS – limit, domyślnie 170 s; PROBE_GOAL – cel startowy przy --pos). Wynik: RESULT {checks, failures,
## events}; kod wyjścia 1 przy niezgodności.
## Agent: statek → Jiub → strażnik → wyjście → nabrzeże (rasa) →
## urząd celny (klasa, znak, przegląd) → arkusz → strażnik drzwi → beczka (pierścień) → kapitan (paczka) →
## wyjście do Seyda Neen. Gracz chodzi po navmeshu (Input „move_forward”), aktywuje obiekty dopiero z bliska
## i tylko gdy sterowanie jest dozwolone. Loguje zdarzenia (okna, komórki, przedmioty, blokady, zmienne
## skryptów). Tylko identyfikatory i liczby – bez tekstów gry.
var main
var t := 0.0
var goal := 0
var goal_t := 0.0
var path: Array = []
var path_t := 0.0
var events: Array = []
var _last := {}
const UNITS := 1.0 / 69.99125   # metr na jednostkę MW (jak MWCoords)

func _init():
	_run.call_deferred()

func ev(s: String) -> void:
	var line := "t=%.1f %s" % [t, s]
	events.append(line)
	print("PROBE EV ", line)

func _refs() -> Array:
	var out := []
	for key in main.loaded:
		var refs: Node = main.loaded[key].get_node_or_null("Refs")
		if refs == null:
			continue
		for n in refs.get_children():
			if not n.get_meta("mw_disabled", false):
				out.append(n)
	return out

func find(base: String) -> Node3D:
	for n in _refs():
		if String(n.get_meta("mw_base", "")).to_lower() == base:
			return n
	return null

func loc(base: String, var_name: String) -> Variant:
	var n := find(base)
	if n == null:
		return null
	return main.scripts._sc().locals.get(String(n.get_meta("mw_sid", "")), {}).get(var_name, null)

func pcount(id: String) -> int:
	return int(main.interaction.inventory.count_of("player", {}, id))

func ppos() -> Vector3:
	return main.ai.mw_pos(main.player)

func menus_open() -> bool:
	return main.dialogue_window.visible or (main.chargen != null and main.chargen.visible) \
		or (main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible) \
		or (main.menu_mode != null and main.menu_mode.visible) or (main.book_window != null and main.book_window.visible)

## Ruch gracza do punktu MW (navmesh; bez niego – prosto). true, gdy w promieniu (jednostki MW, 2D).
var path_dbg_n := 0
func walk_to(dest: Vector3, radius: float) -> bool:
	var here := ppos()
	if Vector2(dest.x - here.x, dest.y - here.y).length() <= radius:
		Input.action_release("move_forward")
		return true
	if not main.control_allowed("controls") or menus_open():
		if OS.has_environment("MWDBG_PATH") and int(t * 10) % 50 == 0:
			print("MWDBG blocked ctl=%s dlg=%s cg=%s msg=%s mm=%s book=%s" % [main.control_allowed("controls"), main.dialogue_window.visible,
				main.chargen != null and main.chargen.visible, main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible,
				main.menu_mode != null and main.menu_mode.visible, main.book_window != null and main.book_window.visible])
		Input.action_release("move_forward")
		return false
	if t - path_t > 1.0 or path.is_empty():
		path_t = t
		var key: String = main.ai.cell_key_at(here)
		var r: Dictionary = main.navmesh.find_path(key, here, dest)
		path = (r.path as Array).duplicate() if not (r.path as Array).is_empty() else [dest]
		if OS.has_environment("MWDBG_PATH") and key.begins_with("ext:") and (path_dbg_n < 8 or OS.get_environment("MWDBG_PATH") == "all"):
			path_dbg_n += 1
			print("MWDBG path key=%s status=%s here=%s n=%d %s" % [key, r.status, str(here.round()), path.size(), str(path.map(func(v): return v.round()))])
	while path.size() > 1 and Vector2((path[0] as Vector3).x - here.x, (path[0] as Vector3).y - here.y).length() < 24.0:
		path.pop_front()
	if OS.has_environment("MWDBG_PATH") and int(t * 10) % 30 == 0 and main.player is CharacterBody3D:
		var cols := []
		for i in main.player.get_slide_collision_count():
			var c = main.player.get_slide_collision(i).get_collider()
			var nm := ""
			var n: Node = c as Node
			while n != null and nm.length() < 200:
				nm = String(n.name) + "<" + nm
				n = n.get_parent()
				if n != null and n.name == "Refs":
					break
			cols.append(nm + " meta=" + (str(c.get_meta("mw_base", "")) if c is Node else ""))
		print("MWDBG stuck here=%s cols=%s" % [str(here.round()), str(cols)])
	var wp: Vector3 = path[0]
	var to: Vector3 = MWCoords.mw_to_godot(wp) - main.player.global_position
	to.y = 0
	main.player.rotation.y = atan2(-to.x, -to.z)
	Input.action_press("move_forward")
	return false

## Aktywacja z bliska (jak gracz): podchodzi do obiektu i aktywuje, gdy odległość 3D od oczu ≤ iMaxActivateDist.
var _act_done := {}
func approach_activate(base: String, tag: String) -> void:
	var n := find(base)
	if n == null:
		return
	var p: Vector3 = main.ai.mw_pos(n)
	if walk_to(p, 64.0) and not menus_open() and main.control_allowed("controls"):
		if _act_done.get(tag, -10.0) + 2.0 < t:
			_act_done[tag] = t
			var eye := ppos() + Vector3(0, 0, 0.9 * 128.0)
			ev("aktywacja %s (odl. 3D od oczu %.0f)" % [base, eye.distance_to(p)])
			main.activate(n)

func _snapshot() -> void:
	var s := {}
	s["cell"] = main.display_location() if false else (main.interior if not main.interior.is_empty() else "ext")
	s["cg"] = main.scripts.get_global("chargenstate")
	var ctl := []
	for k in ["controls", "fighting", "magic", "jumping", "looking", "viewswitch", "vanitymode"]:
		if not main.control_allowed(k):
			ctl.append(k)
	for k in ["stats", "inventory", "magic", "map", "rest"]:
		if not main.menu_allowed(k):
			ctl.append("menu:" + k)
	s["blok"] = ",".join(ctl)
	for id in ["chargen statssheet", "ring_keley", "bk_a1_1_caiuspackage", "bk_a1_1_directionscaiuscosades", "gold_001"]:
		s["item:" + id] = pcount(id)
	s["chargen"] = main.chargen.step if main.chargen != null and main.chargen.visible else "-"
	s["dlg"] = String(main.dialogue.actor.get("base", "")) if main.dialogue_window.visible else "-"
	s["book"] = main.book_window != null and main.book_window.visible
	s["cont"] = main.menu_mode.cont_sid if main.menu_mode != null and main.menu_mode.visible else "-"
	for b in ["chargen name", "chargen boat guard 2", "chargen dock guard", "chargen class", "chargen door guard", "chargen captain"]:
		var st = loc(b, "state")
		if st == null:
			st = loc(b, "done")
		s["st:" + b] = st
	for k in s:
		if not _last.has(k) or str(_last[k]) != str(s[k]):
			ev("%s: %s → %s" % [k, str(_last.get(k, "∅")), str(s[k])])
	_last = s

func _handle_windows() -> void:
	if main.chargen != null and main.chargen.visible:
		main.chargen._create()
	if main.msgbox != null and is_instance_valid(main.msgbox) and main.msgbox.visible:
		ev("messagebox (%d przyc.)" % main.msgbox.find_children("*", "Button", true, false).size())
		main.press_message_button(0)
	if main.book_window != null and main.book_window.visible:
		if goal_name() == "arkusz":
			var tb = main.book_window._take
			ev("okno książki – przycisk Weź widoczny=%s" % str(tb != null and tb.visible))
			if tb != null and tb.visible:
				main.book_window.take()
			else:
				main.book_window.close()
		else:
			main.book_window.close()
	if main.menu_mode != null and main.menu_mode.visible and main.menu_mode.cont_sid != "":
		if goal_name() == "beczka":
			ev("pojemnik – weź ring_keley")
			main.menu_mode.take_item("ring_keley")
		main.menu_mode.close()
	if main.dialogue_window.visible:
		var d = main.dialogue
		if d.in_choice and not d.goodbye_flag:
			ev("pytanie w rozmowie: %d odpowiedzi – wybór %d" % [d.choices.size(), int(d.choices[0][1])])
			d.answer(int(d.choices[0][1]))
			main.dialogue_window.refresh()
			return
		if goal_name() == "kapitan" and pcount("bk_a1_1_caiuspackage") == 0:
			var topics: Array = d.available_topics()
			ev("rozmowa %s: %d tematów, duties=%s" % [String(d.actor.get("base", "")), topics.size(), str(topics.has("duties"))])
			if topics.has("duties"):
				ev("wybór tematu duties")
				main.dialogue_window.select_topic("duties")
				return
			# gracz pyta o kolejne dostępne tematy (hiperłącza dopisują nowe) – aż pojawi się „duties”
			for tp in topics:
				if not _asked.has(tp):
					_asked[tp] = true
					ev("wybór tematu %s" % tp)
					main.dialogue_window.select_topic(tp)
					return
		ev("koniec rozmowy %s" % String(d.actor.get("base", "")))
		main.dialogue_window.close(true)

var _asked := {}
const GOALS := ["statek", "wyjście ze statku", "rasa", "urząd", "klasa", "arkusz", "strażnik drzwi", "drzwi hall",
	"wyjście z urzędu", "beczka", "drzwi kapitana", "kapitan", "wyjście", "gra"]
func goal_name() -> String:
	return GOALS[goal] if goal < GOALS.size() else "koniec"

func next_goal() -> void:
	goal += 1
	goal_t = t
	path = []
	Input.action_release("move_forward")
	ev("CEL → %s" % goal_name())

func _agent() -> void:
	match goal_name():
		"statek":
			var g := find("chargen boat guard 2")
			var st = loc("chargen boat guard 2", "state")
			if st != null and int(st) == -1:
				next_goal()
			elif g != null and st != null and int(st) >= 40:
				walk_to(main.ai.mw_pos(g), 100.0)
		"wyjście ze statku":
			if main.interior.is_empty():
				next_goal()
			else:
				approach_activate("chargen_shipdoor", "shipdoor")
		"rasa":
			var st = loc("chargen dock guard", "state")
			if st != null and int(st) == -1:
				next_goal()
			elif st != null and int(st) == 10:
				var g := find("chargen dock guard")
				walk_to(main.ai.mw_pos(g), 80.0)
		"urząd":
			if main.interior.to_lower() == "seyda neen, census and excise office":
				next_goal()
			else:
				approach_activate("chargen customs door", "customs")
		"klasa":
			var st = loc("chargen class", "state")
			if st != null and int(st) == -1:
				next_goal()
			elif st == null or int(st) == 0:
				walk_to(main.ai.mw_pos(find("chargen class")), 80.0)
		"arkusz":
			if pcount("chargen statssheet") > 0:
				next_goal()
			else:
				approach_activate("chargen statssheet", "sheet")
		"strażnik drzwi":
			if loc("chargen door guard", "done") != null and int(loc("chargen door guard", "done")) == 1:
				next_goal()
			else:
				walk_to(main.ai.mw_pos(find("chargen door guard")), 140.0)
		"drzwi hall":
			var d := find("chargen door hall")
			if d != null and main.doors.is_open(String(d.get_meta("mw_sid", ""))) and main.doors.state_of(String(d.get_meta("mw_sid", ""))) == 0:
				ev("drzwi hall otwarte (obrót %.2f rad)" % (main.doors.current_rot(String(d.get_meta("mw_sid", ""))).z - main.doors.base_rot(String(d.get_meta("mw_sid", ""))).z))
				next_goal()
			elif t - goal_t > 0.5:
				approach_activate("chargen door hall", "hall")
		"wyjście z urzędu":
			if main.interior.is_empty():
				next_goal()
			else:
				approach_activate("chargen door exit", "doorexit")
		"beczka":
			if pcount("ring_keley") > 0:
				next_goal()
			else:
				approach_activate("chargen barrel fatigue", "barrel")
		"drzwi kapitana":
			if not main.interior.is_empty():
				next_goal()
			else:
				approach_activate("chargen door captain", "captdoor")
		"kapitan":
			if pcount("bk_a1_1_caiuspackage") > 0 and not main.dialogue_window.visible:
				next_goal()
			else:
				approach_activate("chargen captain", "captain")
		"wyjście":
			if main.interior.is_empty() and main.scripts.get_global("chargenstate") == -1.0:
				next_goal()
			else:
				approach_activate("chargen exit door", "exitdoor")
		"gra":
			# normalna rozgrywka: kilka kroków naprzód i sprawdzenie blokad
			Input.action_press("move_forward")
			if t - goal_t > 3.0:
				Input.action_release("move_forward")
				next_goal()

func _run():
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.launched_by_launcher = true
	root.add_child(main)
	await process_frame
	var limit := float(OS.get_environment("PROBE_SECONDS")) if OS.get_environment("PROBE_SECONDS") != "" else 170.0
	var start_goal := OS.get_environment("PROBE_GOAL")
	ev("start")
	if start_goal != "":
		goal = GOALS.find(start_goal)
		ev("CEL (start) → %s" % goal_name())
	var last_goal_t := 0.0
	for i in int(limit * 60):
		await physics_frame
		t += 1.0 / 60.0
		_snapshot()
		_handle_windows()
		_agent()
		if i % 300 == 0:
			var gd := find("chargen dock guard") if main.interior.is_empty() else null
			var gtxt := ""
			if gd != null:
				gtxt = " straznik=%s ai=%s" % [str(main.ai.mw_pos(gd).snapped(Vector3(1, 1, 1))), str(main.ai.current_package(gd).get("type", "-"))]
			print("PROBE t=%.0f cel=%s pl=%s cell=%s%s" % [t, goal_name(), str(ppos().snapped(Vector3(1, 1, 1))), main.interior, gtxt])
		if goal_name() == "koniec":
			break
		if t - goal_t > 60.0:
			ev("CEL %s nie osiągnięty w 60 s – przerwanie" % goal_name())
			break
	var rep: Dictionary = main.scripts.report()
	_verdict(rep)
	print("PROBE wynik cel=%s t=%.0f chargenstate=%s journal A1_1_FindSpymaster=%s odpoczynek=%s tematy=%d" % [goal_name(), t, main.scripts.get_global("chargenstate"),
		str(main.state.journal.get("a1_1_findspymaster", "-")), str(main.menu_allowed("rest")), (main.dialogue._ds().known as Dictionary).size()])
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "events": events.size()}))
	quit(1 if failures.size() > 0 else 0)

var failures: Array[String] = []
var checks := 0
func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _first(prefix: String) -> float:
	for e in events:
		var s2 := String(e)
		var sp := s2.find(" ")
		if s2.substr(sp + 1).begins_with(prefix):
			return float(s2.substr(2, sp - 2))
	return -1.0

## Werdykt wg skryptów CharGen (OpenMW wykonuje te same skrypty – kolejność zdarzeń wynika z nich).
func _verdict(rep: Dictionary) -> void:
	if OS.get_environment("PROBE_GOAL") != "":
		return
	check(goal_name() == "koniec", "wszystkie etapy osiągnięte (stoi na: %s)" % goal_name())
	var order := ["chargen: - → name", "chargen: - → race", "chargen: - → class", "chargen: - → birth", "chargen: - → statreview"]
	var last := -1.0
	for o in order:
		var tt := _first(o)
		check(tt > last, "kolejność menu kreatora: %s (t=%.1f)" % [o, tt])
		last = tt
	var cells := events.filter(func(e): return String(e).contains(" cell: ")).map(func(e): return String(e).substr(String(e).find("cell: ")))
	check(cells.size() == 6, "przejścia: statek → nabrzeże → urząd → podwórze → urząd → Seyda Neen (%d)" % cells.size())
	check(_first("st:chargen boat guard 2: 10.0 → 30.0") > 0.0 and _first("st:chargen boat guard 2: 57.0 → -1.0") > _first("st:chargen boat guard 2: 10.0 → 30.0"),
		"strażnik: dojście do gracza i eskorta na pokład (stany 30 → −1)")
	check(_first("st:chargen dock guard: 50.0 → -1.0") > 0.0, "strażnik na nabrzeżu: menu rasy i koniec (−1)")
	check(_first("item:chargen statssheet: 0 → 1") > 0.0 and _first("item:chargen statssheet: 1 → 0") > _first("item:chargen statssheet: 0 → 1"),
		"arkusz: wzięty, oddany kapitanowi")
	check(pcount("ring_keley") == 1 and pcount("bk_a1_1_caiuspackage") == 1 and pcount("bk_a1_1_directionscaiuscosades") == 1 and pcount("gold_001") == 87,
		"przedmioty: pierścień, paczka, wskazówki, 87 sztuk złota")
	check(int(main.state.journal.get("a1_1_findspymaster", 0)) == 1, "dziennik A1_1_FindSpymaster = 1")
	check(main.scripts.get_global("chargenstate") == -1.0 and main.interior.is_empty(), "CharGenState −1, gracz w Seyda Neen")
	check(String(_last.get("blok", "?")) == "", "po wyjściu: brak blokad sterowania i okien (%s)" % str(_last.get("blok", "?")))
	check((rep.get("errors", {}) as Dictionary).is_empty(), "skrypty bez błędów (%s)" % str(rep.get("errors", {})))
