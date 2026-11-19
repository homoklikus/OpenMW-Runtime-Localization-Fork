extends SceneTree
## Etap 9: alchemia jak OpenMW 0.51 – Alchemy::getReadyStatus (kolejność), create(name, count) (wiele mikstur,
## składniki po sztuce za każdym razem, miejsce pustoszeje), knownEffect (fWortChanceValue), okno AlchemyWindow
## (prostokąt [Windows] alchemy, miejsca składników i aparatów, lista efektów, nazwa z pierwszego efektu, filtry,
## liczba mikstur, wybór i zdjęcie aparatu).
## godot --headless --path godot -s res://tests/test_alchemy.gd -- --data=WYNIKI(aktorzy) --scripts=0

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

func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	var _pc0: Dictionary = main.player_stats(); var _pc: Dictionary = main.character.build(main.default_choice()); _pc["equipment"] = _pc0.get("equipment", {}); main.state.player["character"] = _pc
	var mg = main.magic
	var inv = main.interaction.inventory
	var me: Dictionary = main.combat.player_fighter()
	mg.test_roll = 0
	# --- kolejność getReadyStatus
	inv.add("player", {}, "synth_ing_a", 3)
	inv.add("player", {}, "synth_ing_b", 2)
	inv.add("player", {}, "synth_ing_c", 1)
	var none := {-1: {}}
	check(mg.brew(me, ["synth_ing_a"], "", 0, 1, none).result == "no_mortar", "bez moździerza – najpierw sNotifyMessage45")
	inv.add("player", {}, "synth_mortar", 1)
	check(mg.brew(me, ["synth_ing_a"], "", 0).result == "few_ingredients", "potem mniej niż dwa składniki")
	check(mg.brew(me, ["synth_ing_a", "synth_ing_b"], "", 0).result == "no_name", "potem brak nazwy")
	check(inv.count_of("player", {}, "synth_ing_a") == 3, "błędy gotowości nie zużywają składników")
	# --- wiele mikstur: countPotionsToBrew = min(3, 2) = 2
	var tools: Dictionary = mg.alchemy_tools(me)
	check(mg.potions_to_brew(me, ["synth_ing_a", "synth_ing_b", "", ""], "P", tools) == 2, "liczba do uwarzenia = najmniejszy stos")
	var br: Dictionary = mg.brew(me, ["synth_ing_a", "synth_ing_b", "", ""], "Pary", 0, 2)
	check(br.result == "success" and int(br.count) == 2 and inv.count_of("player", {}, String(br.potion)) == 2
			and inv.count_of("player", {}, "synth_ing_a") == 1 and inv.count_of("player", {}, "synth_ing_b") == 0
			and String(br.message).ends_with("Pary (2)"),
		"dwie mikstury naraz, komunikat z liczbą (%s)" % [br])
	# --- knownEffect: umiejętność alchemii a fWortChanceValue
	var w: float = mg._gmst("fWortChanceValue", 15.0)
	var sk: float = float(main.combat.skill(me, 16))
	check(mg.known_effect(me, 0) == (sk >= w) and mg.known_effect(me, 2) == (sk >= 2.0 * w), "znane efekty wg fWortChanceValue (%s, %s)" % [sk, w])
	# --- okno
	inv.add("player", {}, "synth_ing_a", 2)
	inv.add("player", {}, "synth_ing_b", 2)
	var aw = main.alchemy_window
	aw.open()
	await _frames(2)
	var vp: Vector2 = aw.get_viewport().get_visible_rect().size
	check(aw.win.position == (Vector2(0.25, 0.25) * vp).floor() and aw.win.size == (Vector2(0.5, 0.5) * vp).floor(),
		"prostokąt okna z [Windows] alchemy (%s %s)" % [aw.win.position, aw.win.size])
	check(aw.tools.has(0) and aw.slots == ["", "", "", ""] and aw.name_edit.text == "" and aw.brew_count() == 1, "stan po otwarciu")
	check(aw.add_ingredient("synth_ing_a") == 0 and aw.add_ingredient("synth_ing_a") == -1 and aw.add_ingredient("synth_ing_b") == 1,
		"składniki do wolnych miejsc, bez powtórzeń")
	check(aw.effects_shown.size() == 1 and String(aw.effects_shown[0].key).begins_with("75:")
			and (bool(aw.effects_shown[0].known) == mg.known_effect(me, 0)), "lista efektów: wspólne leczenie (%s)" % [aw.effects_shown])
	check(aw.name_edit.text == String(aw.effects_shown[0].text) or not bool(aw.effects_shown[0].known), "nazwa podpowiedziana z pierwszego efektu (%s)" % aw.name_edit.text)
	var grid_ids: Array = aw._grid.get_children().filter(func(cl): return not cl.is_queued_for_deletion()).map(func(cl): return cl.item_id)
	check(not "synth_ing_a" in grid_ids and not "synth_ing_b" in grid_ids, "składniki w miejscach znikają z siatki")
	aw.name_edit.text = "Z okna"
	aw.set_count(5)
	var r: Dictionary = aw.create()
	# a: 3 sztuki, b: 2 – po dwóch miksturach miejsce b pustoszeje, a zostaje (1 sztuka)
	check(r.result == "success" and int(r.count) == 2 and aw.slots == ["synth_ing_a", "", "", ""], "warzenie z okna: min(2, 5) = 2, puste miejsce b (%s %s)" % [r, aw.slots])
	aw.remove_ingredient(0)
	aw.apparatus_clicked(0)
	check(not aw.tools.has(0), "klik w aparat zdejmuje go z miejsca")
	inv.add("player", {}, "synth_ing_a", 1)
	inv.add("player", {}, "synth_ing_b", 1)
	aw.add_ingredient("synth_ing_a")
	aw.add_ingredient("synth_ing_b")
	aw.name_edit.text = "X"
	check(aw.create().result == "no_mortar", "bez moździerza w miejscu – sNotifyMessage45")
	aw.apparatus_clicked(0)
	await _frames(2)
	check(aw._select != null, "puste miejsce aparatu – wybór aparatu (ItemSelectionDialog)")
	aw.select_apparatus(0, "synth_mortar")
	check(aw.tools.has(0) and aw._select == null, "wybrany moździerz w miejscu")
	aw.switch_filter_type()
	check(aw.filter_type == "effect" and aw._filter_btn.text == main.dialogue.gmst_text("sMagicEffects", "Magic Effects"), "przełącznik filtra: efekty")
	aw.close()
	print("RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
