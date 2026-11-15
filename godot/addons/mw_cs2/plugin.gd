@tool
extends EditorPlugin
## Construction Set 2.0 – panel w edytorze Godota.

const CELL_ROOT_SCRIPT := preload("res://addons/mw_cs2/mw_cell_root.gd")
const WORK_DIR := "res://cs2_cells"

var dock: VBoxContainer
var data_edit: LineEdit
var project_edit: LineEdit
var filter_edit: LineEdit
var cell_list: ItemList
var info: Label
var base_edit: LineEdit
var objects_list: ItemList
var status: Label
var db: MWWorldDB
var models: MWModelCache

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "MW CS 2.0"
	data_edit = _row("Dane (wyniki konwertera):", ProjectSettings.globalize_path(
		ProjectSettings.get_setting("mwgodot/data_root", "user://mwdata")))
	project_edit = _row("Projekt (nadpisania):", ProjectSettings.globalize_path(
		ProjectSettings.get_setting("mwgodot/project_root", "user://mw_project")))
	var load_btn := Button.new()
	load_btn.text = "Wczytaj świat"
	load_btn.pressed.connect(_load_world)
	dock.add_child(load_btn)
	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filtr komórek (np. Balmora)"
	filter_edit.text_changed.connect(func(_t): _fill_cells())
	dock.add_child(filter_edit)
	cell_list = ItemList.new()
	cell_list.custom_minimum_size = Vector2(0, 220)
	cell_list.item_activated.connect(func(_i): _open_selected())
	dock.add_child(cell_list)
	var open_btn := Button.new()
	open_btn.text = "Otwórz komórkę"
	open_btn.pressed.connect(_open_selected)
	dock.add_child(open_btn)
	dock.add_child(HSeparator.new())
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = "Zaznacz referencję w widoku 3D."
	dock.add_child(info)
	base_edit = LineEdit.new()
	base_edit.placeholder_text = "ID obiektu bazowego (np. synth_crate)"
	dock.add_child(base_edit)
	objects_list = ItemList.new()
	objects_list.custom_minimum_size = Vector2(0, 120)
	objects_list.item_selected.connect(func(i): base_edit.text = objects_list.get_item_text(i))
	dock.add_child(objects_list)
	var add_btn := Button.new()
	add_btn.text = "Dodaj obiekt przy zaznaczeniu"
	add_btn.pressed.connect(_add_object)
	dock.add_child(add_btn)
	var save_btn := Button.new()
	save_btn.text = "Zapisz nadpisania projektu"
	save_btn.pressed.connect(_save)
	dock.add_child(save_btn)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	dock.add_child(status)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	EditorInterface.get_selection().selection_changed.connect(_on_selection)

func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()

func _row(label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	dock.add_child(l)
	var e := LineEdit.new()
	e.text = value
	dock.add_child(e)
	return e

func _load_world() -> void:
	db = MWWorldDB.new(data_edit.text, project_edit.text)
	models = MWModelCache.new(data_edit.text)
	_fill_cells()
	objects_list.clear()
	var ids := db.objects().keys()
	ids.sort()
	for id in ids:
		objects_list.add_item(id)
	status.text = "Komórek: %d, obiektów: %d" % [db.cell_index().size(), ids.size()]

func _fill_cells() -> void:
	if db == null:
		return
	cell_list.clear()
	var f := filter_edit.text.to_lower()
	for c in db.cell_index():
		var label := "%s  [%s]  (%d)" % [c.get("name", ""), c["key"], c.get("refs", 0)]
		if f.is_empty() or label.to_lower().contains(f):
			cell_list.add_item(label)
			cell_list.set_item_metadata(cell_list.item_count - 1, c["key"])

func _open_selected() -> void:
	var sel := cell_list.get_selected_items()
	if sel.is_empty() or db == null:
		return
	var key: String = cell_list.get_item_metadata(sel[0])
	var ed := MWCellEditing.new(db, models)
	var root := ed.open_cell(key)
	if root == null:
		status.text = "Nie udało się otworzyć %s" % key
		return
	root.set_script(CELL_ROOT_SCRIPT)
	root.set("data_root", data_edit.text)
	root.set("project_root", project_edit.text)
	root.set("cell_key", key)
	DirAccess.make_dir_recursive_absolute(WORK_DIR)
	var info_c := db.find_cell(key)
	var path := WORK_DIR.path_join(String(info_c["file"]).get_file().get_basename() + ".tscn")
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	ResourceSaver.save(ps, path)
	EditorInterface.open_scene_from_path(path)
	status.text = "Otwarto %s (plik roboczy %s – bez zasobów gry)" % [key, path]

func _current_root() -> Node3D:
	var r := EditorInterface.get_edited_scene_root()
	if r and r.has_meta("mw_cell_key"):
		return r as Node3D
	if r and r.get("cell_key") != null and String(r.get("cell_key")) != "":
		r.set_meta("mw_cell_key", r.get("cell_key"))
		return r as Node3D
	return null

func _on_selection() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if nodes.is_empty():
		return
	var n: Node = nodes[0]
	if n.has_meta("mw_sid"):
		var mw: Dictionary = MWCoords.transform_to_ref_fields((n as Node3D).transform)["mw"]
		info.text = "sid: %s\nbaza: %s\nźródło: %s\nMW pos: %s\nMW rot: %s\nskala: %.3f" % [
			n.get_meta("mw_sid"), n.get_meta("mw_base"), n.get_meta("mw_source", ""),
			str(mw["pos"]), str(mw["rot"]), mw["scale"]]

func _add_object() -> void:
	var root := _current_root()
	if root == null or db == null or base_edit.text.is_empty():
		status.text = "Otwórz komórkę, wczytaj świat i podaj ID obiektu."
		return
	var at := Transform3D.IDENTITY
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if not nodes.is_empty() and nodes[0] is Node3D:
		at = (nodes[0] as Node3D).transform.translated(Vector3(1.5, 0, 0))
	var ed := MWCellEditing.new(db, models)
	var n := ed.add_ref(root, base_edit.text, at)
	var ur := get_undo_redo()
	ur.create_action("Dodaj referencję MW")
	ur.add_undo_method(root.get_node("Refs"), "remove_child", n)
	ur.add_do_reference(n)
	ur.commit_action(false)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)

func _save() -> void:
	var root := _current_root()
	if root == null:
		status.text = "Aktywna scena nie jest komórką MW."
		return
	if db == null:
		_load_world()
	var ed := MWCellEditing.new(db, models)
	var ov := ed.compute_overrides(root)
	var err := db.save_overrides(root.get_meta("mw_cell_key"), ov)
	status.text = "Zapisano nadpisania (%s): zmienione %d, dodane %d, usunięte %d → %s" % [
		error_string(err), ov["modified"].size(), ov["added"].size(), ov["deleted"].size(),
		db.override_path(root.get_meta("mw_cell_key"))]
