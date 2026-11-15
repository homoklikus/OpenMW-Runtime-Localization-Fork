extends Control
## Launcher / instalator MWGodot: wskaż Morrowinda → konwersja lokalna z paskiem postępu → Graj.

var L := MWLauncher.new()
var path_edit: LineEdit
var out_edit: LineEdit
var scope: OptionButton
var bake_check: CheckBox
var progress_bar: ProgressBar
var stage_label: Label
var log_box: TextEdit
var convert_btn: Button
var play_btn: Button
var dialog: FileDialog

func _ready() -> void:
	var s := MWLauncher.load_settings()
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(vb)
	var title := Label.new()
	title.text = "MWGodot – eksperymentalny remaster Morrowinda"
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = "Wskaż swoją legalną instalację Morrowinda (katalog gry, „Data Files” albo openmw.cfg). Konwersja odbywa się lokalnie; żadne pliki gry nie są nigdzie wysyłane."
	vb.add_child(info)
	var h := HBoxContainer.new()
	path_edit = LineEdit.new()
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.placeholder_text = "Ścieżka do Morrowinda"
	h.add_child(path_edit)
	var browse := Button.new()
	browse.text = "Wybierz…"
	browse.pressed.connect(func(): dialog.popup_centered_ratio(0.7))
	h.add_child(browse)
	var detect_btn := Button.new()
	detect_btn.text = "Wykryj"
	detect_btn.pressed.connect(_detect)
	h.add_child(detect_btn)
	vb.add_child(h)
	var h2 := HBoxContainer.new()
	var ol := Label.new()
	ol.text = "Dane gry (wyniki):"
	h2.add_child(ol)
	out_edit = LineEdit.new()
	out_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_edit.text = s.get("data_root", ProjectSettings.globalize_path("user://mwdata"))
	h2.add_child(out_edit)
	vb.add_child(h2)
	scope = OptionButton.new()
	scope.add_item("Balmora i okolice (szybki test)")
	scope.add_item("Cała gra (długo – pierwszy pomiar)")
	vb.add_child(scope)
	bake_check = CheckBox.new()
	bake_check.text = "Wypiecz sceny z teksturami pod GPU (szybsze wczytywanie gry)"
	bake_check.button_pressed = true
	vb.add_child(bake_check)
	var py := L.check_python()
	var pyl := Label.new()
	pyl.text = ("Python: " + py["details"]) if py["ok"] else ("Brak Pythona/zależności. " + py["hint"])
	vb.add_child(pyl)
	var hb := HBoxContainer.new()
	convert_btn = Button.new()
	convert_btn.text = "Konwertuj"
	convert_btn.disabled = not py["ok"]
	convert_btn.pressed.connect(_convert)
	hb.add_child(convert_btn)
	play_btn = Button.new()
	play_btn.text = "Graj"
	play_btn.disabled = not MWLauncher.data_ready(out_edit.text)
	play_btn.pressed.connect(_play)
	hb.add_child(play_btn)
	vb.add_child(hb)
	stage_label = Label.new()
	vb.add_child(stage_label)
	progress_bar = ProgressBar.new()
	vb.add_child(progress_bar)
	log_box = TextEdit.new()
	log_box.editable = false
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(log_box)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	dialog.dir_selected.connect(func(d): path_edit.text = d)
	dialog.file_selected.connect(func(f): path_edit.text = f)
	add_child(dialog)
	L.progress.connect(_on_progress)
	L.line.connect(func(t): log_box.text += t + "\n"; log_box.scroll_vertical = 1e9)
	L.finished.connect(_on_finished)
	path_edit.text = s.get("install_path", "")
	if path_edit.text.is_empty():
		_detect()

func _detect() -> void:
	var found := MWLauncher.detect()
	if found.is_empty():
		stage_label.text = "Nie wykryto instalacji – wskaż ją ręcznie."
	else:
		path_edit.text = found[0]["path"]
		stage_label.text = "Wykryto: %s (%s)" % [found[0]["path"], found[0]["kind"]]

func _convert() -> void:
	var inst := MWLauncher.classify(path_edit.text)
	if not inst["ok"]:
		stage_label.text = "To nie wygląda na instalację Morrowinda: " + path_edit.text
		return
	var opts := {"bake": bake_check.button_pressed}
	if scope.selected == 0:
		opts["cells"] = ["Balmora"]
		opts["grid_range"] = "-4,-4,-1,-1"
	else:
		opts["all_cells"] = true
		opts["all_models"] = true
	MWLauncher.save_settings({"install_path": path_edit.text, "data_root": out_edit.text})
	log_box.text = ""
	convert_btn.disabled = true
	var err := L.start(inst, out_edit.text, opts)
	stage_label.text = "Konwersja…" if err == OK else "Nie udało się uruchomić konwertera (%s)" % error_string(err)

func _process(_d: float) -> void:
	if L.is_running():
		L.poll()

func _on_progress(stage: String, done: int, total: int) -> void:
	var names := {"vfs": "Pliki gry", "world": "Świat (ESM/ESP)", "models": "Modele", "textures": "Tekstury", "bake": "Wypiekanie"}
	stage_label.text = "%s: %d/%d" % [names.get(stage, stage), done, total]
	progress_bar.value = 100.0 * done / total if total > 0 else 0.0

func _on_finished(ok: bool, info: Dictionary) -> void:
	convert_btn.disabled = false
	play_btn.disabled = not MWLauncher.data_ready(out_edit.text)
	stage_label.text = ("Gotowe w %.1f s" % float(info.get("seconds", 0))) if ok else "Konwersja zakończona błędem – zobacz log."
	progress_bar.value = 100.0 if ok else progress_bar.value

func _play() -> void:
	MWLauncher.save_settings({"data_root": out_edit.text})
	get_tree().change_scene_to_file("res://main.tscn")
