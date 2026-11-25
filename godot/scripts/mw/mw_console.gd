extends CanvasLayer
## Konsola jak OpenMW 0.51 (apps/openmw/mwgui/console.cpp, openmw_console.layout):
##  - przełączana klawiszem A_Console („`”, SDL_SCANCODE_GRAVE; nie przy oknie modalnym); widoczna konsola =
##    isConsoleMode – liczy się jako tryb GUI (pauza, kursor, MenuMode), przypięte okna ukryte; Esc zamyka konsolę;
##  - okno MW_Window „#{OMWEngine:ConsoleWindow}” ([Windows] console 0,255; 0,215; 0,49 × 0,3125 ekranu), historia
##    (MonoFont, biały, zawijanie, 10000 znaków), wiersz poleceń z fokusem, pasek wyszukiwania (<, >, pole, Aa, .*);
##  - polecenie: „> polecenie” w historii, kompilacja MWScript (mw_mwscript_compiler.gd – to samo drzewo składni
##    co konwerter) ze zmiennymi lokalnymi skryptu wybranego obiektu, wykonanie w kontekście wybranego obiektu;
##    wynik funkcji w wierszu wypisywany; błędy na czerwono (#FF2222), komunikaty na fioletowo (#FF00FF);
##  - polecenia tylko dla konsoli: coc/centeroncell, coe/centeronexterior, tgm/togglegodmode, tcl/togglecollision,
##    tai/toggleai, fillmap, tm/togglemenus, sv/showvars, help, ra/resetactors, fixme;
##  - historia poleceń (strzałki, zapis do console_history.txt, [General] console history buffer size = 4096),
##    Tab – uzupełnianie nazw (listNames: słowa kluczowe, funkcje, identyfikatory rekordów), Ctrl+W / Ctrl+U;
##  - kliknięcie obiektu w świecie przy otwartej konsoli wybiera go (setConsoleSelectedObject), tytuł „(refid)”.

const UI := preload("res://scripts/mw/mw_ui.gd")
const Compiler := preload("res://scripts/mw/mw_mwscript_compiler.gd")
const SIG := preload("res://scripts/mw/mw_mwscript_sig.gd")
const L10n := preload("res://scripts/mw/mw_l10n.gd")

const COLOR_DEFAULT := "#FFFFFF"
const COLOR_ERROR := "#FF2222"
const COLOR_SUCCESS := "#FF00FF"
const COLOR_INFO := "#AAAAAA"
const MAX_TEXT := 10000
const CONSOLE_ONLY := ["coc", "centeroncell", "coe", "centeronexterior", "tgm", "togglegodmode", "tcl",
	"togglecollision", "tai", "toggleai", "fillmap", "tm", "togglemenus", "sv", "showvars", "help", "ra",
	"resetactors", "fixme", "ts", "togglesky", "twa", "togglewater", "twf", "togglewireframe", "tw",
	"toggleworld", "togglescripts", "tfh", "togglefullhelp", "user1", "user2", "user3", "user4", "tfow", "togglefogofwar"]

var main
var win: Control = null
var history: RichTextLabel = null
var command: LineEdit = null
var search: LineEdit = null
var title: Label = null
var case_btn: Button = null
var regex_btn: Button = null
var selected: Node = null          # mPtr
var text_log := ""                 # treść historii (BBCode)
var plain_log := ""                # treść bez znaczników (wyszukiwanie, testy)
var command_history: Array = []
var _cur := 0
var _edit_string := ""
var case_sensitive := false
var regex_search := false
var _search_pos := -1
var compiler := Compiler.new()
var _names: Array = []
var history_limit := 4096
var history_path := ""
var menus_hidden := false

func _ready() -> void:
	layer = 95                      # warstwa Console – nad oknami gry
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if history_path.is_empty():
		history_path = "user://console_history.txt"
	_init_history()

func is_open() -> bool:
	return visible

## WindowManager::toggleConsole.
func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	if win == null or not is_instance_valid(win):
		_build()
	visible = true
	_update_title()
	command.grab_focus()            # onOpen: setKeyFocusWidget(mCommandLine)
	if main != null and main.get("gui") != null:
		main.gui.update_visible()

func close() -> void:
	visible = false
	if command != null:
		command.release_focus()
	if main != null and main.get("gui") != null:
		main.gui.update_visible()

func _build() -> void:
	var s: float = UI.ui_scale()
	var vp := get_viewport().get_visible_rect().size
	win = PanelContainer.new()
	win.name = "Console"
	win.add_theme_stylebox_override("panel", UI.window_box_mw(s))
	win.theme = UI.theme(s)
	win.position = (Vector2(0.255, 0.215) * vp).floor()
	win.size = (Vector2(0.49, 0.3125) * vp).floor()
	win.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(win)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(2 * s))
	win.add_child(box)
	title = Label.new()
	title.name = "Caption"
	UI.add_head(box, title, s)                         # pasek tytułu skórki MW_Window
	var bar := HBoxContainer.new()                        # HBox: <, >, pole wyszukiwania, Aa, .*
	bar.name = "SearchBar"
	bar.add_theme_constant_override("separation", roundi(4 * s))   # HBox Spacing 4
	var bar_m := MarginContainer.new()                  # HBox (1 0 379 28) w obszarze klienta 384
	bar_m.add_theme_constant_override("margin_left", roundi(1 * s))
	bar_m.add_theme_constant_override("margin_right", roundi(4 * s))
	bar_m.add_child(bar)
	box.add_child(bar_m)
	var prev := _button("<", func(): find_occurrence(-1))
	prev.name = "button_Previous"
	bar.add_child(prev)
	var nxt := _button(">", func(): find_occurrence(1))
	nxt.name = "button_Next"
	bar.add_child(nxt)
	search = LineEdit.new()
	search.name = "edit_SearchTerm"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.size_flags_vertical = Control.SIZE_SHRINK_BEGIN    # MW_ConsoleCommand: MW_Box 26 px w polu 28 px
	search.custom_minimum_size.y = 26 * s
	search.text_submitted.connect(func(_t): _search_pos = -1; find_occurrence(1))
	bar.add_child(search)
	case_btn = _button("Aa", toggle_case_sensitive)
	case_btn.name = "button_CaseSensitive"
	bar.add_child(case_btn)
	regex_btn = _button(".*", toggle_regex)
	regex_btn.name = "button_RegExSearch"
	bar.add_child(regex_btn)
	history = RichTextLabel.new()
	history.name = "list_History"
	history.bbcode_enabled = true
	history.scroll_following = true
	history.selection_enabled = true
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.add_theme_color_override("default_color", Color.WHITE)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
	history.add_theme_font_override("normal_font", mono)
	history.add_theme_font_size_override("normal_font_size", roundi(14 * s))
	history.text = text_log
	box.add_child(history)                             # MW_TextBoxEdit: bez ramki, pasek przewijania z prawej
	command = LineEdit.new()
	command.name = "edit_Command"
	command.set_meta("accept_tab", true)               # AcceptTab: Tab uzupełnia nazwy
	command.text_submitted.connect(func(_t): accept_command())
	command.gui_input.connect(_command_key)
	command.custom_minimum_size.y = 26 * s
	box.add_child(command)

func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(28, 28) * UI.ui_scale()
	b.clip_text = true                                 # stały rozmiar 28 × 28 jak w openmw_console.layout
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

## updateConsoleTitle: „#{OMWEngine:ConsoleWindow}” + „ (refid)” wybranego obiektu.
func _update_title() -> void:
	if title == null:
		return
	var t := L10n.ctx_text("OMWEngine", "ConsoleWindow", "Console")
	if selected != null and is_instance_valid(selected):
		t += " (%s)" % String(selected.get_meta("mw_base", selected.name))
	title.text = t

# --- historia tekstu ---------------------------------------------------------------------------------------

func print_line(msg: String, color := COLOR_DEFAULT) -> void:
	text_log += "[color=%s]%s[/color]" % [color, msg.replace("[", "[lb]")]
	plain_log += msg
	if plain_log.length() > MAX_TEXT:                    # MaxTextLength 10000
		plain_log = plain_log.right(MAX_TEXT)
	if history != null:
		history.text = text_log

func print_ok(msg: String) -> void:
	print_line(msg + "\n", COLOR_SUCCESS)

func print_error(msg: String) -> void:
	print_line(msg + "\n", COLOR_ERROR)

# --- polecenia ---------------------------------------------------------------------------------------------

## acceptCommand: historia (bez powtórzeń z rzędu), zapis do pliku, wyczyszczenie wiersza, wykonanie.
func accept_command() -> void:
	var cm := command.text if command != null else ""
	if cm.is_empty():
		return
	if command_history.is_empty() or command_history.back() != cm:
		command_history.append(cm)
		_append_history_file(cm)
	_cur = command_history.size()
	_edit_string = ""
	command.text = ""
	execute(cm)

## Console::execute.
func execute(cmd: String) -> void:
	print_line("> " + cmd + "\n")
	if cmd.length() >= 3 and cmd.substr(0, 3) == "lua":
		print_error("Error: Lua console is not available")        # brak Lua w porcie
		return
	var locals := {}
	var ctx_who := {}
	if selected != null and is_instance_valid(selected):
		ctx_who = main.dialogue.make_actor(selected) if main.get("dialogue") != null else {}
		var scr := String(ctx_who.get("script", ""))
		if not scr.is_empty():
			locals = (main.scripts.script_rec(scr).get("locals", {}) as Dictionary).duplicate()
	var out: Dictionary = compiler.compile(cmd + "\n", "console", locals)
	for e in out.errors:
		print_error(_short_error(String(e)))
	for w in out.warnings:
		print_line(_short_error(String(w)) + "\n", COLOR_INFO)
	if not out.errors.is_empty():
		return
	for st in out.body:
		_run_statement(st, ctx_who)

static func _short_error(e: String) -> String:
	var k := e.find(": ")
	var s := e.substr(k + 2) if k >= 0 else e
	var bar := s.find(" | ")
	return s.left(bar) if bar >= 0 else s

func _run_statement(st: Array, who: Dictionary) -> void:
	if String(st[0]) == "call" and String(st[2]) in CONSOLE_ONLY:
		_console_only(String(st[2]), st[3], st[1], who)
		return
	var sc = main.scripts
	var c = sc.Ctx.new()
	c.sid = String(who.get("sid", ""))
	c.base = String(who.get("base", ""))
	c.scr = String(who.get("script", ""))
	c.key = c.sid if not c.sid.is_empty() else "console"
	c.node = who.get("node")
	var fn0 := String(st[2]) if String(st[0]) == "call" else ""
	var unsup_before := int((sc.unsupported as Dictionary).get(fn0, 0))
	var errs_before := 0
	for k in sc.errors:
		errs_before += int(sc.errors[k])
	if String(st[0]) == "call":
		var fname := String(st[2])
		var r = sc._call(st[1], fname, st[3], c)
		if int((sc.unsupported as Dictionary).get(fname, 0)) > unsup_before:
			print_error("Error: %s is not supported" % fname)
		elif r != null and (r is float or r is int):
			print_ok(_num_str(float(r)))                  # wynik funkcji w konsoli
	else:
		sc._exec([st], c)
	var errs_after := 0
	for k in sc.errors:
		errs_after += int(sc.errors[k])
	if c.failed or errs_after > errs_before:
		print_error("Error: script execution failed")

static func _num_str(v: float) -> String:
	if v == floorf(v) and absf(v) < 1e9:
		return str(int(v))
	return "%s" % v

# --- polecenia tylko konsoli ---------------------------------------------------------------------------------

func _arg_str(args: Array, i: int) -> String:
	return String(args[i][1]) if i < args.size() and args[i] is Array and (args[i] as Array).size() > 1 else ""

func _arg_num(args: Array, i: int) -> float:
	if i >= args.size():
		return 0.0
	var a = args[i]
	if a is Array and String(a[0]) == "num":
		return float(a[1])
	var c = main.scripts.Ctx.new()
	c.key = "console"
	return float(main.scripts._eval(a, c))

func _console_only(name: String, args: Array, ref, who: Dictionary) -> void:
	match name:
		"coc", "centeroncell":
			var cell := _arg_str(args, 0)
			if not main.center_on_cell(cell):
				print_error("Error: Can't find cell %s" % cell)
		"coe", "centeronexterior":
			main.center_on_exterior(int(_arg_num(args, 0)), int(_arg_num(args, 1)))
		"tgm", "togglegodmode":
			main.god_mode = not main.god_mode
			print_ok("God Mode -> %s" % ("On" if main.god_mode else "Off"))
		"tcl", "togglecollision":
			var on: bool = main.toggle_collision()
			print_ok("Collision -> %s" % ("On" if on else "Off"))
		"tai", "toggleai":
			main.ai.enabled = not main.ai.enabled
			print_ok("AI -> %s" % ("On" if main.ai.enabled else "Off"))
		"fillmap":
			main.fill_map()
		"tm", "togglemenus":
			menus_hidden = not menus_hidden                 # WindowManager::setHudVisibility (toggleGui)
			if main.get("mw_hud") != null and main.mw_hud != null:
				main.mw_hud.set_hud_visible(not menus_hidden)
			print_ok("GUI -> %s" % ("Off" if menus_hidden else "On"))
		"sv", "showvars":
			_show_vars(who if ref == null else main.script_host.find_ref(String(ref)))
		"help":
			var names := SIG.SIG.keys()
			names.sort()
			print_ok(" ".join(names))
		"ts", "togglesky":
			print_ok("Sky -> %s" % ("On" if main.envr.toggle_sky() else "Off"))
		"twa", "togglewater":
			print_ok("Water -> %s" % ("On" if main.envr.toggle_water() else "Off"))
		"twf", "togglewireframe":
			# RenderingManager::toggleRenderMode(Render_Wireframe): cała scena w siatce
			var vp: Viewport = main.get_viewport()
			var on: bool = vp.debug_draw != Viewport.DEBUG_DRAW_WIREFRAME
			vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if on else Viewport.DEBUG_DRAW_DISABLED
			print_ok("Wireframe Rendering -> %s" % ("On" if on else "Off"))
		"tw", "toggleworld":
			# Render_Scene: świat (bez nieba i interfejsu) niewidoczny
			var cam: Camera3D = main.get_viewport().get_camera_3d()
			if cam != null:
				var on2: bool = cam.cull_mask == 0
				if on2:
					cam.cull_mask = int(main.get_meta("world_cull_mask", 0xFFFFF))
				else:
					main.set_meta("world_cull_mask", cam.cull_mask)
					cam.cull_mask = 0
				print_ok("World -> %s" % ("On" if on2 else "Off"))
		"togglescripts":
			# World::toggleScripts: skrypty lokalne i globalne wstrzymane
			main.scripts_enabled = not main.scripts_enabled
			print_ok("Scripts -> %s" % ("On" if main.scripts_enabled else "Off"))
		"tfh", "togglefullhelp":
			main.full_help = not main.full_help
			print_ok("Full help -> %s" % ("On" if main.full_help else "Off"))
		"tfow", "togglefogofwar":
			main.fog_of_war = not main.fog_of_war              # WindowManager::toggleFogOfWar (mapa i minimapa)
			if main.get("map_window") != null and main.map_window.visible:
				main.map_window._build_local()                 # applyFogOfWar: tekstury mgły od razu
			print_ok("Fog of war -> %s" % ("On" if main.fog_of_war else "Off"))
		"user1", "user2", "user3", "user4":
			print_ok("%s: not in use" % name)                # OpUser1–4
		"ra", "resetactors", "fixme":
			print_error("Error: %s is not supported" % name)

## ShowVars: zmienne lokalne skryptu wybranego obiektu albo globalne.
func _show_vars(who) -> void:
	var w: Dictionary = who if who is Dictionary else {}
	var scr := String(w.get("script", ""))
	if w.is_empty() or scr.is_empty():
		var globs: Dictionary = main.state.get("globals") if main.state.get("globals") is Dictionary else {}
		var keys := globs.keys()
		keys.sort()
		for k in keys:
			print_ok("%s = %s" % [k, _num_str(float(globs[k]))])
		return
	var loc: Dictionary = main.scripts.script_rec(scr).get("locals", {})
	print_ok("Local variables for %s" % scr)
	for v in loc:
		print_ok("  %s %s = %s" % [loc[v], v, _num_str(main.scripts.local_value(String(w.sid), String(v)))])

# --- klawisze wiersza poleceń ------------------------------------------------------------------------------

func _command_key(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed:
		return
	if e.is_action_pressed("console"):
		close()                                          # A_Console zamyka konsolę także z fokusem w wierszu
		command.accept_event()
		return
	var k := (e as InputEventKey).keycode
	if (e as InputEventKey).ctrl_pressed:
		if k == KEY_W:
			_delete_word()
			command.accept_event()
		elif k == KEY_U:
			command.text = command.text.substr(command.caret_column)
			command.caret_column = 0
			command.accept_event()
		return
	if k == KEY_TAB:
		tab_complete()
		command.accept_event()
		return
	if command_history.is_empty():
		return
	if k == KEY_UP:
		if _cur == command_history.size():
			_edit_string = command.text
		if _cur > 0:
			_cur -= 1
			command.text = command_history[_cur]
			command.caret_column = command.text.length()
		command.accept_event()
	elif k == KEY_DOWN:
		if _cur < command_history.size():
			_cur += 1
			command.text = command_history[_cur] if _cur < command_history.size() else _edit_string
			command.caret_column = command.text.length()
		command.accept_event()

## Ctrl+W: usunięcie słowa przed kursorem (białe znaki i „>” jako separatory).
func _delete_word() -> void:
	var t := command.text
	if t.is_empty():
		return
	var mx := command.caret_column
	var end := mx
	while mx > 0 and (t[mx - 1] in [" ", "\t", ">"]):
		mx -= 1
	while mx > 0 and not (t[mx - 1] in [" ", "\t", ">"]):
		mx -= 1
	command.text = t.left(mx) + t.substr(end)
	command.caret_column = mx

## listNames: słowa kluczowe, instrukcje i funkcje, identyfikatory rekordów (posortowane).
func list_names() -> Array:
	if not _names.is_empty():
		return _names
	var seen := {}
	for k in SIG.KEYWORDS:
		seen[String(k)] = true
	for k in SIG.SIG:
		seen[String(k)] = true
	if main != null and main.get("db") != null and main.db != null:
		for id in main.db.object_ids():
			seen[String(id).to_lower()] = true
	_names = seen.keys()
	_names.sort()
	return _names

## Console::complete: uzupełnienie ostatniego słowa do najdłuższego wspólnego przedrostka; przy braku zmiany –
## lista kandydatów (do 50).
func tab_complete() -> void:
	var old := command.text
	var k := old.length()
	while k > 0 and not (old[k - 1] in [" ", "\t", ">", "\""]):
		k -= 1
	var word := old.substr(k).to_lower()
	if word.is_empty():
		return
	var matches := []
	for n in list_names():
		if String(n).begins_with(word):
			matches.append(String(n))
	if matches.is_empty():
		return
	var common := String(matches[0])
	for m in matches:
		var i := 0
		while i < common.length() and i < m.length() and common[i] == m[i]:
			i += 1
		common = common.left(i)
	var newt := old.left(k) + common
	if matches.size() == 1 and not " " in common:
		newt += " "
	command.text = newt
	command.caret_column = newt.length()
	if newt == old:
		print_ok("")
		for i in mini(50, matches.size()):
			print_ok(matches[i])

# --- wyszukiwanie w historii ---------------------------------------------------------------------------------

func toggle_case_sensitive() -> void:
	case_sensitive = not case_sensitive
	if case_btn != null:
		case_btn.modulate = Color(1, 1, 1, 1) if case_sensitive else Color(0.6, 0.6, 0.6, 1)

func toggle_regex() -> void:
	regex_search = not regex_search
	if regex_btn != null:
		regex_btn.modulate = Color(1, 1, 1, 1) if regex_search else Color(0.6, 0.6, 0.6, 1)

## findOccurrence: następne (1) albo poprzednie (−1) wystąpienie od ostatniego; zwraca pozycję w tekście.
func find_occurrence(direction: int) -> int:
	var term := search.text if search != null else ""
	if term.is_empty():
		return -1
	var hay := plain_log if case_sensitive else plain_log.to_lower()
	var positions := []
	var lengths := []
	if regex_search:
		var re := RegEx.new()
		if re.compile(("" if case_sensitive else "(?i)") + term) != OK:
			return -1
		for m in re.search_all(plain_log):
			positions.append(m.get_start())
			lengths.append(m.get_end() - m.get_start())
	else:
		var needle := term if case_sensitive else term.to_lower()
		var i := hay.find(needle)
		while i >= 0:
			positions.append(i)
			lengths.append(needle.length())
			i = hay.find(needle, i + 1)
	if positions.is_empty():
		return -1
	var pick := -1
	if direction > 0:
		for j in positions.size():
			if int(positions[j]) > _search_pos:
				pick = j
				break
		if pick < 0:
			pick = 0
	else:
		for j in range(positions.size() - 1, -1, -1):
			if int(positions[j]) < _search_pos or _search_pos < 0:
				pick = j
				break
		if pick < 0:
			pick = positions.size() - 1
	_search_pos = int(positions[pick])
	return _search_pos

# --- wybór obiektu ------------------------------------------------------------------------------------------

## setSelectedObject: ten sam obiekt – odznaczenie, inny – wybór; fokus wraca do wiersza poleceń.
func set_selected(n: Node) -> void:
	if n != null and n == selected:
		selected = null
	else:
		selected = n
	_update_title()
	if command != null and visible:
		command.grab_focus()

## Kliknięcie w świat przy otwartej konsoli (HUD::onWorldClicked → getFocusObject pod kursorem).
func pick_at(screen: Vector2) -> Node:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if main.player != null:
		q.exclude = [main.player.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var n: Node = hit.collider
	while n != null and not n.has_meta("mw_sid"):
		n = n.get_parent()
	return n

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("console"):
		var modal: bool = main != null and main.get("msgbox") != null and main.msgbox != null and is_instance_valid(main.msgbox)
		if not modal:                                     # toggleConsole: nie przy oknie modalnym
			toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		set_selected(pick_at((e as InputEventMouseButton).position))
		get_viewport().set_input_as_handled()

# --- historia poleceń w pliku -------------------------------------------------------------------------------

## initConsoleHistory: odczyt ostatnich N poleceń, przepisanie pliku i dopisywanie kolejnych.
func _init_history() -> void:
	command_history = []
	if history_limit > 0 and FileAccess.file_exists(history_path):
		for line in FileAccess.get_file_as_string(history_path).split("\n"):
			if line.is_empty():
				continue
			if command_history.size() >= history_limit:
				command_history.pop_front()
			command_history.append(line)
	_cur = command_history.size()
	var f := FileAccess.open(history_path, FileAccess.WRITE)
	if f != null:
		for l in command_history:
			f.store_line(l)
		f.close()

func _append_history_file(cm: String) -> void:
	var f := FileAccess.open(history_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(history_path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(cm)
	f.close()
