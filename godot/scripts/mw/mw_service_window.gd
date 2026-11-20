extends CanvasLayer
## Okna usług w układach OpenMW (skórka MW_Dialog, wyśrodkowane, bez paska tytułu):
##   zaklęcia – openmw_spell_buying_window.layout (450 × 290), SpellBuyingWindow;
##   podróże – openmw_travel_window.layout (500 × 250), TravelWindow;
##   trening – openmw_trainingwindow.layout (320 × 200), TrainingWindow;
##   naprawa – openmw_merchantrepair.layout (420 × 250), MerchantRepair.
## Tytuł (NormalText, środek), podtytuł (SandText), pole MW_Box z listą przycisków SandTextButton po
## fontSize + 2 px („nazwa  - cena” + sgp; za drogie – SandTextButtonDisabled), „sGold: N”, OK / Cancel.
## Logika cen i usług – mw_trade.gd.

const UI := preload("res://scripts/mw/mw_ui.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")

## Teksty z układów: [prostokąt tytułu (NormalText), prostokąt podtytułu (SandText, przesunięcie skórki −1)];
## TextAlign „Center” / „Left” w MyGUI – wyśrodkowanie w pionie.
const TEXT_RECTS := {
	"spells": [Rect2(0, 6, 442, 18), Rect2(6, 25, 450, 18)],
	"travel": [Rect2(0, 3, 490, 24), Rect2(6, 22, 490, 24)],
	"training": [Rect2(6, 3, 300, 24), Rect2(6, 22, 300, 24)],
	"repair": [Rect2(0, 3, 412, 24), Rect2(6, 22, 412, 24)],
}

const LAYOUTS := {
	# [rozmiar okna, tytuł (GMST), podtytuł (GMST), pole MW_Box (x, y, w, h), złoto (x, y), przycisk (x, y), przycisk (l10n)]
	"spells": [Vector2(450, 290), "sServiceSpellsTitle", "sSpellServiceTitle", Rect2(6, 42, 430, 205), Vector2(6, 253), Vector2(376, 253), "OK"],
	"travel": [Vector2(500, 250), "sServiceTravelTitle", "sTravelServiceTitle", Rect2(6, 42, 480, 165), Vector2(6, 211), Vector2(425, 212), "Cancel"],
	"training": [Vector2(320, 200), "sServiceTrainingTitle", "sTrainingServiceTitle", Rect2(6, 42, 300, 115), Vector2(6, 161), Vector2(246, 161), "OK"],
	# openmw_merchantrepair.layout (MerchantRepair)
	"repair": [Vector2(420, 250), "sServiceRepairTitle", "sRepairServiceTitle", Rect2(6, 42, 400, 165), Vector2(6, 212), Vector2(350, 212), "OK"],
}

var main
var trade
var mode := ""
var actor := {}
var panel: Control = null
var rows: Array = []                 # testy: [id, tekst, dostępny]
var gold_label: Label = null
var title_label: Label = null
var _list: VBoxContainer = null
var _s := 1.0

func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _t(gm: String, fb: String) -> String:
	return main.dialogue.gmst_text(gm, fb)

const GUI_MODES := {"spells": "spellbuying", "travel": "travel", "training": "training", "repair": "merchantrepair"}

func open(service: String, a: Dictionary) -> void:
	mode = service
	actor = a
	_s = UI.ui_scale()
	_build()
	visible = true
	refresh()
	main.gui.push(String(GUI_MODES.get(service, service)), [self])     # GM_SpellBuying / GM_Travel / ...

func _build() -> void:
	if panel != null:
		panel.queue_free()
	var L: Array = LAYOUTS[mode]
	var size: Vector2 = L[0] * _s
	var vp := get_viewport().get_visible_rect().size
	panel = Panel.new()
	panel.name = "ServiceWindow"
	panel.theme = UI.theme(_s)
	panel.add_theme_stylebox_override("panel", UI.window_box())
	panel.size = size
	panel.position = ((vp - size) / 2.0).floor()          # align="Center"
	add_child(panel)
	# współrzędne układu są względem obszaru Client skórki MW_Dialog (4 px od krawędzi)
	var client := Control.new()
	client.position = Vector2(4, 4) * _s
	client.size = size - Vector2(8, 8) * _s
	panel.add_child(client)
	title_label = Label.new()
	title_label.text = _t(String(L[1]), "")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tr: Rect2 = TEXT_RECTS[mode][0]
	title_label.position = tr.position * _s
	title_label.size = tr.size * _s
	client.add_child(title_label)
	var sub := Label.new()
	sub.text = _t(String(L[2]), "")
	sub.add_theme_color_override("font_color", UI.color("normal"))
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sr: Rect2 = TEXT_RECTS[mode][1]
	sub.position = (sr.position + Vector2(0, -1)) * _s
	sub.size = Vector2(minf(sr.size.x, client.size.x / _s - sr.position.x), sr.size.y) * _s
	client.add_child(sub)
	var r: Rect2 = L[3]
	var box := PanelContainer.new()
	var bsb: StyleBox = UI.inner_box().duplicate()
	bsb.content_margin_left = 4 * _s
	bsb.content_margin_top = 3 * _s
	bsb.content_margin_right = 1 * _s
	bsb.content_margin_bottom = 2 * _s
	box.add_theme_stylebox_override("panel", bsb)
	box.position = r.position * _s
	box.size = r.size * _s
	client.add_child(box)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	gold_label = Label.new()
	gold_label.add_theme_color_override("font_color", UI.color("normal"))
	gold_label.position = L[4] * _s + Vector2(2, -1) * _s       # setCoord(8, …); SandText −1, wyśrodkowany w pionie
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.size = Vector2(200, 24) * _s
	client.add_child(gold_label)
	var b := Button.new()
	b.name = "CancelButton"
	b.text = L10n.ctx_text("Interface", String(L[6]), String(L[6]))
	b.pressed.connect(close)
	client.add_child(b)
	await get_tree().process_frame
	if is_instance_valid(b):
		var bw := maxf(60 * _s, b.get_combined_minimum_size().x)     # ExpandDirection Left od prawej krawędzi
		var right := (L[5] as Vector2).x * _s + (56.0 if mode == "repair" else 60.0) * _s    # szerokość przycisku z układu
		b.position = Vector2(right - bw, (L[5] as Vector2).y * _s)
		b.size = Vector2(bw, 24 * _s)

func refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	rows = []
	var gold: int = trade.player_gold()
	var gp := _t("sgp", "gp")
	match mode:
		"spells":
			for sp in trade.spells_for_sale(actor):
				_row(String(sp.id), "%s  - %d%s" % [String(sp.name), int(sp.price), gp], int(sp.price) <= gold)
		"travel":
			for o in trade.travel_offers(actor):
				_row(int(o.index), "%s  - %d%s" % [String(o.name), int(o.price), gp], int(o.price) <= gold)
		"repair":
			for o in main.repair.merchant_offers(actor):
				_row(String(o.id), String(o.text), bool(o.ok))
		"training":
			var names: Array = main.character.skill_names()
			for o in trade.training_offers(actor):
				var sid := String(names[int(o.skill)])
				_row(int(o.skill), "%s  - %d%s" % [_t("sSkill" + sid.capitalize().replace(" ", ""), sid), int(o.price), gp], int(o.price) <= gold)
	gold_label.text = "%s: %d" % [_t("sGold", "Gold"), gold]

## Przycisk SandTextButton (nieaktywny – SandTextButtonDisabled, bez reakcji), wysokość fontSize + 2.
func _row(id, text: String, ok: bool) -> void:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 18 * _s
	b.add_theme_constant_override("h_separation", 0)
	# SandTextButton: TextAlign „Left Bottom” – linia 16 px przy dolnej krawędzi wiersza 18 px
	var eb := StyleBoxEmpty.new()
	eb.content_margin_top = 2 * _s
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, eb)
	b.add_theme_color_override("font_color", UI.color("normal") if ok else UI.color("disabled"))
	b.add_theme_color_override("font_hover_color", UI.color("normal_over") if ok else UI.color("disabled"))
	b.add_theme_color_override("font_pressed_color", UI.color("normal_pressed") if ok else UI.color("disabled"))
	if ok:
		b.pressed.connect(choose.bind(id))
	if mode == "spells":
		b.set_meta("mw_tip", {"type": "spell", "id": String(id), "cost": true})     # SpellBuyingWindow: Spell + SpellCost
	_list.add_child(b)
	rows.append([id, text, ok])

## Wybór pozycji: zakup zaklęcia (lista odświeżona), trening (wyjście z usługi i rozmowy), podróż.
func choose(id) -> void:
	match mode:
		"spells":
			if trade.buy_spell(actor, String(id)):
				refresh()
		"repair":
			if main.repair.merchant_repair(actor, String(id)):
				refresh()
		"training":
			var r: Dictionary = trade.train(actor, int(id))
			if not String(r.message).is_empty():
				main._toast(String(r.message))
			if bool(r.ok):
				close()
				main.dialogue_window.close(true)        # TrainingWindow: exitCurrentGuiMode po treningu
		"travel":
			close()
			main.dialogue_window.close(true)
			trade.travel(actor, int(id))

func close() -> void:
	visible = false
	if panel != null:
		panel.queue_free()
		panel = null
	_list = null
	if main != null and main.get("gui") != null:
		main.gui.remove(String(GUI_MODES.get(mode, mode)))
