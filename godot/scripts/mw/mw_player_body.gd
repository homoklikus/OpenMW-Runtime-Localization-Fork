extends Node
## Postać gracza w świecie (NpcAnimation gracza, VM_Normal): model z rekordu „player” z wyglądem z kreatora
## i założonymi rzeczami (main.player_doll – ten sam co podgląd w ekwipunku), widoczny w trzeciej osobie, podglądzie
## i vanity; w pierwszej osobie siatki są ukryte (OpenMW rysuje wtedy osobne ręce 1st – nieprzeniesione), światło
## trzymanej pochodni zostaje. Przebudowa po zmianie wyglądu albo ekwipunku (sprawdzana co 0,25 s).
## Animacje jak CharacterController dla ruchu: idle / idlesneak / idleswim, {walk|run|sneak|swimwalk|swimrun}
## {forward|back|left|right} z tempem wg prędkości (mw_speed grupy), skok (jump) w powietrzu; śmierć – losowa
## grupa deathN (chooseRandomGroup), swimdeath w wodzie, deathknockdown / deathknockout przy powaleniu, ostatnia
## klatka zostaje.

const CellBuilder := preload("res://scripts/mw/mw_cell_builder.gd")

var actor: CharacterBody3D
var main = null
var model: Node3D = null
var shown := false                        # siatki widoczne (tryb inny niż pierwsza osoba)
var dead := false
var death_group := ""
var current := ""
var _sig := ""
var _air_t := 0.0                         # czas w powietrzu (is_on_floor Godota migocze na stokach i stopniach)
var rebuilds := 0                         # diagnostyka: przebudowy modelu
var changes := 0                          # diagnostyka: zmiany grupy animacji
var last_changes: Array = []
var _check_t := 0.0

func _process(delta: float) -> void:
	if actor == null or main == null:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.25
		var s := signature()
		if s != _sig:
			rebuild()
	_air_t = 0.0 if actor.is_on_floor() or actor.swimming or actor.fly else _air_t + delta
	if model != null and shown:
		_animate()

## Wygląd i ekwipunek gracza (rasa, płeć, głowa, włosy, wampiryzm, założone przedmioty).
func signature() -> String:
	if not main.has_method("player_stats") or main.get("builder") == null or main.builder == null:
		return ""
	var st: Dictionary = main.player_stats()
	var eq: Dictionary = main._equipment() if main.has_method("_equipment") else {}
	var parts := []
	for sl in eq:
		parts.append("%s=%s" % [sl, String((eq[sl] as Dictionary).get("id", ""))])
	parts.sort()
	return "%s|%s|%s|%s|%s|%s" % [st.get("race", ""), st.get("head", ""), st.get("hair", ""), st.get("female", false),
		(st.get("spells", []) as Array).size(), ",".join(parts)]

func rebuild() -> void:
	_sig = signature()
	rebuilds += 1
	if model != null:
		model.queue_free()
		model = null
	current = ""
	var m: Node3D = main.player_doll() if main.has_method("player_doll") else null
	if m == null:
		return
	CellBuilder._strip_collision(m)
	m.name = "Body"
	actor.add_child(m)
	model = m
	_apply_shown()
	if dead and not death_group.is_empty():
		var ap := player()
		if ap != null and ap.has_animation(death_group):
			ap.play(death_group)
			ap.seek(ap.get_animation(death_group).length, true)
			current = death_group

func player() -> AnimationPlayer:
	if model == null:
		return null
	return model.get_node_or_null("MWAnimations") as AnimationPlayer

func set_shown(on: bool) -> void:
	shown = on
	_apply_shown()

func _apply_shown() -> void:
	if model == null:
		return
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visible = shown

## CharacterController::playRandomDeath → długość animacji śmierci (s); 0 – brak grupy.
func play_death(swimming: bool, knockdown: bool, knockout: bool) -> float:
	dead = true
	var ap := player()
	var group := ""
	if ap != null:
		if knockout and ap.has_animation("deathknockout"):
			group = "deathknockout"
		elif knockdown and ap.has_animation("deathknockdown"):
			group = "deathknockdown"
		elif swimming and ap.has_animation("swimdeath"):
			group = "swimdeath"
		else:
			var n := 0
			while ap.has_animation("death%d" % (n + 1)):
				n += 1
			if n > 0:
				group = "death%d" % (randi() % n + 1)
	death_group = group
	if group.is_empty():
		return 0.0
	var a := ap.get_animation(group)
	a.loop_mode = Animation.LOOP_NONE
	ap.play(group, 0.1)
	ap.speed_scale = 1.0
	current = group
	return a.length

## Resurrect: koniec animacji śmierci.
func revive() -> void:
	dead = false
	death_group = ""
	current = ""

## Animation::upperBodyReady – animacja śmierci (Priority_Death) albo powalenia blokuje zmianę widoku.
func upper_body_ready() -> bool:
	if dead:
		return false
	return not (main.has_method("player_stats") and bool(main.player_stats().get("knocked_down", false)))

func _animate() -> void:
	var ap := player()
	if ap == null or dead:
		return
	var want := "idle"
	var speed := 1.0
	var mi: Vector2 = actor.move_input
	var hv := Vector2(actor.velocity.x, actor.velocity.z).length()
	var swim: bool = actor.swimming
	var sneak: bool = actor.want_sneak and not swim
	var run: bool = actor.want_run
	# skok (JumpState_InAir): od skoku do lądowania albo dłuższy spadek – nie pojedyncze klatki bez podłoża
	var in_air: bool = actor.jumping or _air_t > 0.25
	if not swim and in_air and not actor.fly and not actor.levitate and ap.has_animation("jump"):
		want = "jump"
	elif mi != Vector2.ZERO and hv > 0.05:
		var dir := ""
		if absf(mi.y) >= absf(mi.x):
			dir = "back" if mi.y > 0.0 else "forward"
		else:
			dir = "right" if mi.x > 0.0 else "left"
		var prefix := "sneak" if sneak else ("run" if run else "walk")
		if swim:
			prefix = "swimrun" if run else "swimwalk"
		want = prefix + dir
		for alt in [prefix + "forward", ("swimwalkforward" if swim else "walkforward"), "walkforward"]:
			if ap.has_animation(want):
				break
			want = alt
		var a := ap.get_animation(want) if ap.has_animation(want) else null
		var anim_speed := float(a.get_meta("mw_speed", 0.0)) if a != null else 0.0
		if anim_speed > 0.01:
			speed = clampf(hv / anim_speed, 0.3, 3.0)
	elif swim and ap.has_animation("idleswim"):
		want = "idleswim"
	elif sneak and ap.has_animation("idlesneak"):
		want = "idlesneak"
	if not ap.has_animation(want):
		want = "idle" if ap.has_animation("idle") else ""
	if want.is_empty():
		return
	if ap.current_animation != want:
		ap.play(want, 0.2)
		changes += 1
		last_changes.append(want)
		if last_changes.size() > 12:
			last_changes.pop_front()
	ap.speed_scale = speed
	current = want
