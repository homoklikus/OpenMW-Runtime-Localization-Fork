extends RefCounted
## Stos trybów GUI jak WindowManager OpenMW 0.51 (apps/openmw/mwgui/windowmanagerimp.cpp):
##  - push(mode, okna): tryb obecny już na stosie przenoszony na wierzch; okna poprzedniego trybu ukrywane
##    (GuiModeState::update(false)), okna nowego pokazywane;
##  - pop(): zdjęcie wierzchniego trybu, okna poprzedniego wracają (GuiModeState::update(true) → onOpen –
##    tu gui_resumed(), czyli odświeżenie);
##  - remove(mode): wierzchni – jak pop, inaczej usunięcie ze środka stosu bez zmiany widoku;
##  - contains(mode), get_mode(), is_gui_mode();
##  - exit_current(): Esc (exitCurrentGuiMode) – wywołuje wyjście okna wierzchniego trybu, które zamyka się
##    przez remove(); okno może odmówić (np. rozmowa w trakcie pytania);
##  - update_visible(): tryb rozgrywki (pusty stos) – gra wznowiona, kursor przechwycony; tryb GUI – pauza
##    i widoczny kursor (WindowManager::updateVisible + omw/ui.lua: pauza w trybach GUI).
## Okno ukryte przez wyższy tryb ma meta „gui_suspended” – ignoruje wtedy klawisze.

var main
var stack: Array = []            # [{"mode": String, "windows": Array[Node], "exit": Callable}]
var history: Array = []            # testy: historia operacji
var cursor := ""                   # testy (headless): ostatni tryb kursora z updateVisible – "visible" / "captured"

func _init(game_main) -> void:
	main = game_main

func get_mode() -> String:
	return String(stack.back().mode) if not stack.is_empty() else ""

func modes() -> Array:
	return stack.map(func(e): return String(e.mode))

func _nav():
	return main.get("keyboard_nav") if main != null else null

func contains(mode: String) -> bool:
	for e in stack:
		if String(e.mode) == mode:
			return true
	return false

## isGuiMode: tryb na stosie albo otwarta konsola (isConsoleMode).
func is_gui_mode() -> bool:
	return not stack.is_empty() or is_console_mode()

func is_console_mode() -> bool:
	return main != null and main.get("console") != null and main.console != null and main.console.is_open()

static func is_suspended(n: Node) -> bool:
	return n != null and bool(n.get_meta("gui_suspended", false))

func _windows_of(mode: String) -> Array:
	for e in stack:
		if String(e.mode) == mode:
			return e.windows
	return []

## pushGuiMode.
func push(mode: String, windows: Array, exit := Callable()) -> void:
	var top := get_mode()
	if top != mode and not top.is_empty() and _nav() != null:
		_nav().save_focus(top)                       # KeyboardNavigation::saveFocus(mGuiModes.back())
	if top != mode:
		for i in stack.size():
			if String(stack[i].mode) == mode:
				stack.remove_at(i)
				break
		if not stack.is_empty():
			_set_visible(stack.back().windows, false, windows)
		stack.append({"mode": mode, "windows": windows, "exit": exit})
	else:
		stack.back().windows = windows
		if exit.is_valid():
			stack.back().exit = exit
	_set_visible(windows, true, [])
	history.append("push:" + mode)
	update_visible()

## popGuiMode.
func pop() -> void:
	if stack.is_empty():
		update_visible()
		return
	var e: Dictionary = stack.pop_back()
	history.append("pop:" + String(e.mode))
	if not stack.is_empty():
		_set_visible(stack.back().windows, true, [], true)
		if _nav() != null:
			_nav().restore_focus.call_deferred(String(stack.back().mode))   # restoreFocus(mode)
	update_visible()

## removeGuiMode.
func remove(mode: String) -> void:
	if get_mode() == mode:
		pop()
		return
	var keep := []
	for e in stack:
		if String(e.mode) != mode:
			keep.append(e)
	if keep.size() != stack.size():
		history.append("remove:" + mode)
	stack = keep
	update_visible()

## exitCurrentGuiMode (Esc). → czy tryb obsłużył klawisz
func exit_current() -> bool:
	if stack.is_empty():
		return false
	var e: Dictionary = stack.back()
	var mode := String(e.mode)
	if (e.exit as Callable).is_valid():
		(e.exit as Callable).call()
	else:
		for w in e.windows:
			if w != null and is_instance_valid(w) and w.has_method("close"):
				w.close()
	if get_mode() == mode and stack.size() > 0 and stack.back() == e:
		pass                             # okno odmówiło wyjścia (WindowBase::exit() == false)
	return true

func clear() -> void:
	for e in stack:
		_set_visible(e.windows, true, [])
	stack = []
	update_visible()

## GuiModeState::update: okno wspólne z trybem docelowym (np. ekwipunek w handlu) nie jest ukrywane.
func _set_visible(windows: Array, on: bool, keep: Array, resumed := false) -> void:
	for w in windows:
		if w == null or not is_instance_valid(w) or w in keep:
			continue
		if on:
			if bool(w.get_meta("gui_suspended", false)):
				for c in w.get_meta("gui_hidden_children", []):
					if is_instance_valid(c):
						(c as CanvasItem).visible = true
				w.set_meta("gui_hidden_children", [])
				w.set_meta("gui_suspended", false)
				if resumed and w.has_method("gui_resumed"):
					w.gui_resumed()
		else:
			if bool(w.get_meta("gui_suspended", false)):
				continue
			var hidden := []
			for c in w.get_children():
				if c is CanvasItem and (c as CanvasItem).visible:
					(c as CanvasItem).visible = false
					hidden.append(c)
			w.set_meta("gui_hidden_children", hidden)
			w.set_meta("gui_suspended", true)
			if w.has_method("gui_suspended"):
				w.gui_suspended()

## updateVisible: pauza i kursor wg trybu; menu główne, okno z pytaniem i kreator postaci zarządzają nimi same.
func update_visible() -> void:
	if main == null or not main.is_inside_tree():
		return
	var other_ui: bool = (main.get("main_menu") != null and main.main_menu != null and main.main_menu.is_open()) \
		or (main.get("msgbox") != null and main.msgbox != null and is_instance_valid(main.msgbox)) \
		or (main.get("chargen") != null and main.chargen != null and main.chargen.visible)
	if not stack.is_empty() or is_console_mode():
		main.get_tree().paused = true
		cursor = "visible"
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not other_ui:
		main.get_tree().paused = false
		if String(main.get("game_state")) == "running":
			cursor = "captured"
			if DisplayServer.get_name() != "headless":
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
