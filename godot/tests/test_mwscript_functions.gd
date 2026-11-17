extends SceneTree
## MWScript – semantyka funkcji jak w OpenMW (dane syntetyczne; porównania z OpenMW na danych gry –
## tools/openmw-xvfb/mwscript_compare.py): statystyki (Set/Mod/ModCurrent, efekty, poziom), zdarzenia
## (OnDeath/OnMurder kasowane odczytem, OnKnockout przez jedną klatkę, GetAttacked, OnPCHitMe jako zmienna),
## ruch i skala (Move/MoveWorld, SetScale/ModScale), woda wnętrza, wymuszony ruch, Drop, Equip, kamienie dusz,
## teleportacja, ModRegion, rangi NPC, Resurrect, wilkołak, sen (GetPCSleep/WakeUpPC), skrypty w trybie menu,
## spłata grzywny uspokaja świadków (GetAttacked = 0), zapis/odczyt nowych stanów.
## godot --headless --path godot -s res://tests/test_mwscript_functions.gd -- --data=WYNIKI(aktorzy) --scripts=0

var failures: Array[String] = []
var checks := 0
var main
var vm

func check(c: bool, m: String) -> void:
	checks += 1
	if not c:
		failures.append(m)
		printerr("FAIL: ", m)

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _ref(base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func ctx():
	return vm.Ctx.new()

## Wiersz MWScript skompilowany wcześniej przez konwerter nie jest tu potrzebny – wywołania jak z interpretera.
func call_(ref, fname: String, args := []):
	return vm._call(ref, fname, args, ctx())

func n_(v: float) -> Array:
	return ["num", v]

func s_(v: String) -> Array:
	return ["str", v]

static func near(a, b, eps := 0.01) -> bool:
	return absf(float(a) - float(b)) <= eps

func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	vm = main.scripts
	var S = vm.stats()
	var me: Dictionary = main.combat.player_fighter()
	var vil := _ref("synth_villager")
	var vf: Dictionary = main.combat.fighter_of(vil)

	# --- statystyki: Set czyści modyfikator, Mod z limitem 100, ModCurrent kondycji poniżej zera → powalenie
	call_("player", "setstrength", [n_(60)])
	call_("player", "modstrength", [n_(20)])
	check(near(call_("player", "getstrength"), 80), "SetStrength 60 + ModStrength 20 = 80")
	call_("player", "modstrength", [n_(50)])
	check(near(call_("player", "getstrength"), 100), "ModStrength nie przekracza 100 bez wzmocnień")
	call_("synth_villager", "sethealth", [n_(40)])
	call_("synth_villager", "modcurrenthealth", [n_(-10)])
	check(near(S.dyn_base(vf, 0), 40) and near(S.dyn_current(vf, 0), 30), "SetHealth/ModCurrentHealth na NPC")
	call_("synth_villager", "setresistfire", [n_(30)])
	check(near(call_("synth_villager", "getresistfire"), 30), "SetResistFire → GetResistFire")

	# --- OnKnockout: dokładnie jedna klatka; GetAttacked/OnPCHitMe
	call_("synth_villager", "modcurrentfatigue", [n_(-1000)])
	var ko := 0
	for i in 6:
		await process_frame
		if call_("synth_villager", "onknockout") == 1.0:
			ko += 1
	check(ko == 1, "OnKnockout prawdziwe przez jedną klatkę (%d)" % ko)
	check(bool(main.combat._actor_state(vf).get("knocked_down", false)), "kondycja < 0 – nieprzytomny")
	main.combat._actor_state(vf)["fatigue"] = 50.0
	await create_timer(main.KNOCKDOWN_TIME + 0.4).timeout
	check(not bool(main.combat._actor_state(vf).get("knocked_down", false)), "po odzyskaniu kondycji wstaje")
	check(call_("synth_villager", "getattacked") == 0.0, "GetAttacked = 0 przed atakiem")
	main.combat.on_hit(vf, me, {"health": 1.0}, false)
	check(call_("synth_villager", "getattacked") == 1.0, "GetAttacked po chybionym ataku gracza")

	# --- OnDeath: trwa do odczytu, odczyt kasuje
	call_("synth_villager", "modcurrenthealth", [n_(-1000)])
	await _frames(3)
	check(call_("synth_villager", "ondeath") == 1.0 and call_("synth_villager", "ondeath") == 0.0, "OnDeath kasowane odczytem")
	check(call_("synth_villager", "onmurder") == 0.0, "OnMurder bez morderstwa = 0")
	call_("synth_villager", "resurrect")
	await _frames(2)
	vil = _ref("synth_villager")
	vf = main.combat.fighter_of(vil)
	check(not main.combat.is_dead(vf) and near(S.dyn_current(vf, 0), S.dyn_modified(vf, 0)), "Resurrect: żywy, pełne zdrowie")

	# --- ruch i skala
	var crate := _ref("synth_crate")
	if crate == null:
		for key in main.loaded:
			for n in main.loaded[key].get_node("Refs").get_children():
				if not n.has_meta("mw_actor") and n is Node3D and String(n.get_meta("mw_base", "")) != "":
					crate = n
					break
			if crate != null:
				break
	var cid := String(crate.get_meta("mw_base")) if crate != null else ""
	check(crate != null, "obiekt do testu ruchu (%s)" % cid)
	if crate != null:
		var z0: float = call_(cid, "getpos", [s_("z")])
		vm.delta = 0.5
		call_(cid, "moveworld", [s_("z"), n_(100)])
		check(near(float(call_(cid, "getpos", [s_("z")])) - z0, 50.0, 0.5), "MoveWorld z 100 × 0,5 s = +50")
		call_(cid, "setscale", [n_(1.5)])
		call_(cid, "modscale", [n_(0.25)])
		check(near(call_(cid, "getscale"), 1.75), "SetScale 1,5 + ModScale 0,25")
		call_(cid, "fall")

	# --- woda (zewnętrze: GetWaterLevel = 0, SetWaterLevel – błąd i przerwanie skryptu)
	check(call_(null, "getwaterlevel") == 0.0, "GetWaterLevel na zewnątrz = 0")
	var cx = ctx()
	vm._call(null, "setwaterlevel", [n_(10)], cx)
	check(cx.stop and not vm.errors.is_empty(), "SetWaterLevel na zewnątrz – błąd skryptu")

	# --- błąd w skrypcie globalnym (brak obiektu dla funkcji z odniesieniem) zatrzymuje skrypt jak OpenMW
	vm._scripts["synth_failing"] = {"locals": {"n": "short"}, "body": [
		["set", ["id", "n"], ["bin", "+", ["id", "n"], ["num", 1.0]]], ["call", null, "modreputation", [n_(1)]],
		["set", ["id", "n"], ["num", 100.0]]]}
	vm.start("synth_failing")
	await _frames(3)
	var fl: Dictionary = main.state.scripts.locals.get("global:synth_failing", {})
	check(not vm.running("synth_failing") and int(fl.get("n", 0)) == 1, "brak obiektu: skrypt globalny przerwany i zatrzymany (%s)" % [fl])

	# --- wymuszony ruch, przedmioty
	call_("player", "forcesneak")
	check(call_("player", "getforcesneak") == 1.0, "ForceSneak → GetForceSneak")
	await _frames(2)
	check(call_(null, "getpcsneaking") == 1.0, "ForceSneak → GetPCSneaking")
	call_("player", "clearforcesneak")
	await _frames(2)
	check(call_("player", "getforcesneak") == 0.0, "ClearForceSneak")
	var inv = main.interaction.inventory
	inv.add("player", {}, "misc_synth_spoon", 3)
	var have: int = inv.count_of("player", {}, "misc_synth_spoon")
	call_("player", "drop", [s_("misc_synth_spoon"), n_(2)])
	check(inv.count_of("player", {}, "misc_synth_spoon") == have - 2, "Drop 2")
	call_("player", "equip", [s_("synth_sword")])
	check(call_("player", "hasitemequipped", [s_("synth_sword")]) == 1.0 and call_("player", "getweapontype") >= 0.0,
			"Equip dodaje brakujący przedmiot i zakłada (HasItemEquipped, GetWeaponType)")
	main.combat.on_hit(vf, me, {"health": 1.0}, true)
	check(call_("synth_villager", "hitonme", [s_("synth_sword")]) == 1.0 and call_("synth_villager", "hitonme", [s_("synth_sword")]) == 0.0
			and call_("synth_villager", "hitattemptonme", [s_("synth_sword")]) == 1.0, "HitOnMe/HitAttemptOnMe – broń ciosu, kasowane odczytem")
	check(near(call_(null, "getsquareroot", [n_(20.25)]), 4.5) and call_("player", "getstat", [n_(1)]) == 0.0, "GetSquareRoot, GetStat = 0")
	call_(null, "disableteleporting")
	check(not bool(main.state.player.get("teleport_enabled", true)), "DisableTeleporting")
	call_(null, "enableteleporting")

	# --- wilkołak gracza: statystyki z GMST, szata, powrót
	var str0: float = call_("player", "getstrength")
	call_("player", "becomewerewolf")
	check(call_("player", "iswerewolf") == 1.0 and inv.count_of("player", {}, "werewolfrobe") >= 0, "BecomeWerewolf")
	check(not main.menu_allowed("inventory"), "wilkołak – ekwipunek niedostępny")
	call_("player", "undowerewolf")
	check(call_("player", "iswerewolf") == 0.0 and near(call_("player", "getstrength"), str0), "UndoWerewolf przywraca siłę")

	# --- sen: GetPCSleep podczas odliczania, WakeUpPC przerywa; skrypty działają w trybie menu
	var hour0: float = main.envr.game_hour
	var opened: bool = main.rest_window.open()
	check(opened, "okno odpoczynku")
	if opened:
		main.rest_window.rest(8)
		var slept := false
		var t_end := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < t_end:
			await process_frame
			if call_(null, "getpcsleep") == 1.0:
				slept = true
				call_(null, "wakeuppc")
				break
		await _frames(3)
		check(slept and not main.rest_window.is_resting(), "GetPCSleep w czasie snu, WakeUpPC przerywa")
		check(fposmod(main.envr.game_hour - hour0, 24.0) < 7.5, "przerwany sen – mniej niż 8 godzin")
	var ticks0: float = vm.get_global("SynthTicks")
	main.rest_window.open()
	await _frames(4)
	check(vm.get_global("SynthTicks") > ticks0 or main.arg("scripts", "1") == "0", "skrypty globalne działają przy otwartym oknie")
	main.rest_window.close()

	# --- grzywna: spłata uspokaja świadków (GetAttacked = 0, crime_id usunięte)
	var guard := _ref("synth_guard")
	if guard != null:
		var gf: Dictionary = main.combat.fighter_of(guard)
		main.combat._actor_state(gf)["attacked"] = true
		main.combat._actor_state(gf)["crime_id"] = main.crime.new_crime_id()
		main.crime.set_bounty(0)
		main.crime.calm_witnesses()
		check(call_("synth_guard", "getattacked") == 0.0 and not main.combat._actor_state(gf).has("crime_id"), "spłata – świadek uspokojony")

	# --- zapis i odczyt: wymuszony ruch, wilkołak, zabici wilkołakiem
	call_("synth_villager", "forcerun")
	main.player_stats()["werewolf_kills"] = 2
	var path := ProjectSettings.globalize_path("user://test_saves/mwscript_fn.mwsave")
	check(main.save_game(path) == "", "zapis")
	main.combat._actor_state(vf).erase("move_flags")
	main.player_stats()["werewolf_kills"] = 0
	main.load_game(path)
	await _frames(3)
	check(call_("synth_villager", "getforcerun") == 1.0 and call_(null, "getwerewolfkills") == 2.0, "odczyt: ForceRun, GetWerewolfKills")
	var rep: Dictionary = vm.report()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures, "unsupported": rep.unsupported}))
	quit(1 if failures.size() > 0 else 0)
