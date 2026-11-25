extends SceneTree
## Etap 10 cz. 33: pasek zdrowia wroga w HUD (HUD::setEnemy / updateEnemyHealthBar / onFrame, OpenMW 0.51):
## trafienie gracza w zwarciu (Npc::hit – przed rzutem na trafienie, także chybienie), efekt czaru gracza zmieniający
## zdrowie celu (ActiveSpells::update – mShowHealth), int(zdrowie/maks × 100), fNPCHealthBarTime i fNPCHealthBarFade,
## WeaponSpellName 20 px wyżej przy pasku, HUD::clear przy nowej grze.
## godot --headless --path godot -s res://tests/test_enemy_health.gd -- --data=WYNIKI(aktorzy) --scripts=0

var failures: Array[String] = []
var checks := 0

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

func _ref(main, base: String) -> Node3D:
	for key in main.loaded:
		for n in main.loaded[key].get_node("Refs").get_children():
			if String(n.get_meta("mw_base", "")).to_lower() == base:
				return n
	return null

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var hud = main.mw_hud
	var cb = main.combat
	var s: float = hud.scale_ui
	check(hud.enemy_bar != null and not hud.enemy_bar.visible, "pasek wroga ukryty na starcie")
	var y_bar: float = hud.bars.health.position.y
	check(is_equal_approx(hud.enemy_bar.position.y, y_bar - 15.0 * s) and is_equal_approx(hud.enemy_bar.position.x, hud.bars.health.position.x),
		"EnemyHealth 15 px nad paskiem zdrowia (13 131 vs 13 146)")
	var fy: float = hud.flash_label.position.y
	var me: Dictionary = cb.player_fighter()
	var vic: Dictionary = cb.fighter_of(_ref(main, "synth_villager"))
	cb.test_roll = 50
	cb.melee(me, vic, 0, 1.0, 99)                      # chybienie – pasek i tak (setEnemy przed rzutem)
	check(hud.enemy_bar.visible and is_equal_approx(hud.flash_label.position.y, fy - 20.0 * s), "chybienie gracza: pasek widoczny, nazwa broni 20 px wyżej")
	check(int(hud.enemy_bar.value) == 100, "pełne zdrowie – 100 (%s)" % hud.enemy_bar.value)
	cb.melee(me, vic, 0, 1.0, 0)
	var expect := int(cb.health(vic) / cb.max_health(vic) * 100.0)
	check(int(hud.enemy_bar.value) == expect, "po trafieniu int(zdrowie/maks × 100) = %d (%s)" % [expect, hud.enemy_bar.value])
	var t: float = hud._gmst_f("fNPCHealthBarTime", 5.0)
	var fade: float = hud._gmst_f("fNPCHealthBarFade", 1.0)
	hud._enemy_tick(t - fade * 0.5)
	check(hud.enemy_bar.visible and absf(hud.enemy_bar.modulate.a - 0.5) < 0.02, "wygasanie: krycie czas/fNPCHealthBarFade (%s)" % hud.enemy_bar.modulate.a)
	hud._enemy_tick(fade)
	check(not hud.enemy_bar.visible and is_equal_approx(hud.flash_label.position.y, fy), "po fNPCHealthBarTime pasek znika, nazwa broni wraca")
	# atak NPC na gracza – bez paska
	cb.melee(vic, me, 0, 1.0, 0)
	check(not hud.enemy_bar.visible, "NPC trafia gracza – bez paska wroga")
	# czar gracza zmieniający zdrowie celu
	var mg = main.magic
	mg.test_roll = 99
	var r: Dictionary = mg.cast_spell(me, "synth_touch", vic, 0)
	check(bool(r.get("success", false)) and hud.enemy_bar.visible and hud.enemy == vic, "Uszkodzenie zdrowia czarem gracza – pasek celu")
	hud.clear_enemy()
	check(not hud.enemy_bar.visible and hud.enemy.is_empty() and is_equal_approx(hud.flash_label.position.y, fy), "HUD::clear – bez celu")
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if failures.size() > 0 else 0)
