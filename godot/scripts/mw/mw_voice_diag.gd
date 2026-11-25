extends Node
## Diagnostyka głosów NPC i paska zdrowia wroga na sprzęcie użytkownika (--voice-diag): co sekundę wiersz
## `MWGODOT_VOICEDIAG` (tylko identyfikatory i liczby – bez tekstów gry) o najbliższych NPC: odległość, Hello, stan
## powitania (updateGreetingState), linia wzroku, zauważenie, czy mówi; stan dźwięku (włączony, głośność głosu,
## liczniki odtworzonych/brakujących plików). Każda kwestia (voice_said) – wiersz „said”. --diag-attack: co 3 s atak
## gracza (player_attack; bez celu – chybienie w najbliższego aktora, rzut 99) i stan paska wroga (HUD::setEnemy). --diag-seconds=N – zakończenie po N s.

var main
var attack := false
var seconds := 0.0
var _t := 0.0
var _tick := 0.0
var _atk := 0.0

var _hooked := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log({"ev": "start", "attack": attack, "seconds": seconds})

func _hook() -> void:
	if _hooked or main.get("dialogue") == null or main.dialogue == null or not main.dialogue.has_signal("voice_said"):
		return
	_hooked = true
	main.dialogue.voice_said.connect(func(sid, topic, info_id): _log({"ev": "said", "sid": sid, "topic": topic, "info": info_id,
		"file": String(main.audio.last_played) if main.audio != null else ""}))

func _log(row: Dictionary) -> void:
	row["t"] = snappedf(_t, 0.01)
	print("MWGODOT_VOICEDIAG ", JSON.stringify(row))

func _process(dt: float) -> void:
	_t += dt
	_hook()
	if seconds > 0.0 and _t >= seconds:
		_log({"ev": "quit"})
		get_tree().quit()
		return
	if String(main.get("game_state")) != "running" or main.player == null or main.ai == null:
		return
	_tick += dt
	if _tick >= 1.0:
		_tick = 0.0
		_report()
	if attack:
		_atk += dt
		if _atk >= 3.0:
			_atk = 0.0
			var r: Dictionary = main.player_attack() if main.has_method("player_attack") else {}
			if String(r.get("target", "")).is_empty():     # nikt pod celownikiem – chybienie w najbliższego aktora (bez obrażeń)
				var best: Node = null
				var bd := 400.0
				for n in main.ai.actor_nodes():
					if is_instance_valid(n) and main.ai.mw_pos(n).distance_to(main.ai.mw_pos(main.player)) < bd \
							and not main.combat.is_dead(main.combat.fighter_of(n)):
						bd = main.ai.mw_pos(n).distance_to(main.ai.mw_pos(main.player))
						best = n
				if best != null:
					main.combat.melee(main.combat.player_fighter(), main.combat.fighter_of(best), 0, 1.0, 99)
					r = {"target": String(best.get_meta("mw_sid", "")), "forced": true}
			var hud = main.mw_hud
			_log({"ev": "attack", "target": String(r.get("target", "")), "success": bool(r.get("success", false)), "forced": bool(r.get("forced", false)),
				"bar": hud.enemy_bar != null and hud.enemy_bar.visible, "bar_value": hud.enemy_bar.value if hud.enemy_bar != null else -1,
				"bar_alpha": snappedf(hud.enemy_bar.modulate.a, 0.01) if hud.enemy_bar != null else -1,
				"enemy": String(hud.enemy.get("sid", "")), "timer": snappedf(hud._enemy_t, 0.01),
				"root": hud.root != null and hud.root.visible})

func _report() -> void:
	var ai = main.ai
	var pp: Vector3 = ai.mw_pos(main.player)
	var rows := []
	for n in ai.actor_nodes():
		if not is_instance_valid(n) or String(n.get_meta("mw_actor", "")) != "npc":
			continue
		var d: float = ai.mw_pos(n).distance_to(pp)
		if d > 1500.0:
			continue
		var rec: Dictionary = ai._record(n)
		var r: Dictionary = ai._rt(n)
		var pk: Array = ai.ai_state(n).packages
		rows.append({"base": String(n.get_meta("mw_base", "")), "d": roundi(d),
			"hello": int((rec.get("ai", {}) as Dictionary).get("hello", 0)), "greet": String(r.get("greet", "")),
			"gt": int(r.get("greet_timer", 0)), "pkg": String(pk[0].get("type", "")) if not pk.is_empty() else "none",
			"los": ai._los(n, main.player), "aware": ai.awareness(main.player, n),
			"talking": main.audio != null and main.audio.say_active(String(n.get_meta("mw_sid", "")))})
	rows.sort_custom(func(a, b): return int(a.d) < int(b.d))
	var au = main.audio
	_log({"ev": "npcs", "n": rows.size(), "near": rows.slice(0, 5),
		"audio": {"enabled": au != null and bool(au.enabled), "voice": snappedf(float(au.voice_volume), 0.01) if au != null else -1,
			"played": int(au.stats.played) if au != null else -1, "missing": int(au.stats.missing) if au != null else -1},
		"sneak": main.player_sneaking(), "idle_odds": float(ai._gmst("fVoiceIdleOdds", 0.0)),
		"greet_mult": float(ai._gmst("iGreetDistanceMultiplier", 6))})
