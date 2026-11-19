extends RefCounted
## PersuasionDialog jak OpenMW 0.51 (apps/openmw/mwgui/dialogue.cpp, openmw_persuasion_dialog.layout):
## okno modalne MW_DialogNoTransp 220 × 192 na środku: sPersuasionMenuTitle (NormalText, 0, 4, 220, 24,
## wyśrodkowany), MW_Box ActionsBox (8, 32, 196, 114; Stretch Top) z przyciskami SandTextButton od x = 4:
## sAdmire, sIntimidate, sTaunt, sBribe 10/100/1000 Gold – adjustAction: wiersze po fontSize + 2 = 18 px
## od y = 3 (okno rośnie, gdy suma + 3 przekroczy wysokość pola); GoldLabel „sGold: N” (8, 158) i Cancel
## (prawa krawędź 204, 154; ExpandDirection Left). onOpen: łapówki wyłączone bez złota, okno szersze o nadmiar
## szerokości napisu złota ponad 196 − Cancel − 8. Wybór – DialogueManager::persuade, odświeżenie tematów.

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")
const CU := preload("res://scripts/mw/mw_chargen_ui.gd")
const Box := preload("res://scripts/mw/mw_box_layout.gd")

const ACTIONS := [["admire", "sAdmire", "AdmireButton"], ["intimidate", "sIntimidate", "IntimidateButton"],
	["taunt", "sTaunt", "TauntButton"], ["bribe10", "sBribe 10 Gold", "Bribe10Button"],
	["bribe100", "sBribe 100 Gold", "Bribe100Button"], ["bribe1000", "sBribe 1000 Gold", "Bribe1000Button"]]

var main
var dialogue
var ui = null
var win: Control = null
var buttons := {}                  # rodzaj → Button
var gold_label: Label = null
var cancel_button: Button = null
var on_persuade: Callable          # po perswazji (odświeżenie okna rozmowy)

func _init(game_main, dlg) -> void:
	main = game_main
	dialogue = dlg

func _t(gm: String, fb: String) -> String:
	return dialogue.gmst_text(gm, fb)

func is_open() -> bool:
	return win != null and is_instance_valid(win)

## PersuasionDialog: konstruktor (adjustAction) + onOpen.
func open(host: Node) -> void:
	close()
	ui = CU.new(main, UI.ui_scale())
	var bl := Box.new(ui.sc)
	var line_h := 16 + 2
	var total := 3 + line_h * ACTIONS.size() + 3
	var h := 192 + maxi(0, total - 114)
	var g: int = dialogue.gold()
	var gold_text := "%s: %d" % [_t("sGold", "Gold"), g]
	var cancel_text := L10n.ctx_text("Interface", "Cancel", "Cancel")
	var cancel_w: float = bl.text_size(cancel_text).x + 24
	var initial_gold_w := 196 - cancel_w - 8
	var diff: float = bl.text_size(gold_text).x - initial_gold_w
	var w := 220.0 + (diff if diff > 0 else 0.0)
	var dw := w - 220.0
	win = ui.modal(host, w, h, true)
	win.name = "PersuasionDialog"
	var c: Control = win.get_meta("client")
	# HCenter Top: wyśrodkowany przy poszerzeniu okna
	var title: Label = ui.label(c, floorf(dw / 2.0), 4, 220, 24, _t("sPersuasionMenuTitle", "Persuasion"), "header", HORIZONTAL_ALIGNMENT_CENTER)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var box: Control = ui.box(c, 8, 32, 196 + dw, 114 + (h - 192))
	box.name = "ActionsBox"
	buttons = {}
	var y := 3
	for a in ACTIONS:
		var text := _t(String(a[1]), String(a[1]))
		var kind := String(a[0])
		var b: Button = ui.text_button(box, 4, y, bl.text_size(text).x + 24, line_h, text, func(): persuade(kind))
		b.name = String(a[2])
		buttons[kind] = b
		y += line_h
	(buttons.bribe10 as Button).disabled = g < 10
	(buttons.bribe100 as Button).disabled = g < 100
	(buttons.bribe1000 as Button).disabled = g < 1000
	for k in buttons:
		(buttons[k] as Button).add_theme_color_override("font_disabled_color", UI.color("disabled"))
	# AutoSizedTextBox (8, 158) – rozmiar tekstu, Left Bottom
	gold_label = ui.label(c, 8, 158 + (h - 192), bl.text_size(gold_text).x, 16, gold_text)
	gold_label.name = "GoldLabel"
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cancel_button = ui.button(cancel_text, close)
	cancel_button.name = "CancelButton"
	c.add_child(cancel_button)
	cancel_button.position = Vector2(204 + dw - cancel_w, 154 + (h - 192)) * ui.sc
	cancel_button.size = Vector2(cancel_w, 24) * ui.sc

func close() -> void:
	if is_open():
		CU.close(win)
	win = null

## onPersuade: DialogueManager::persuade, updateTopics, okno zamknięte.
func persuade(kind: String, roll := -1) -> void:
	if buttons.has(kind) and (buttons[kind] as Button).disabled:
		return
	dialogue.persuade(kind, roll)
	close()
	if on_persuade.is_valid():
		on_persuade.call()
