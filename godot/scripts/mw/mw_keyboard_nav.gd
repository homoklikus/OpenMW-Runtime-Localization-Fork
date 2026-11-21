extends Node
## Nawigacja klawiaturą w oknach jak OpenMW 0.51 KeyboardNavigation (apps/openmw/mwgui/keyboardnavigation.cpp),
## wywoływana przed przekazaniem klawisza do GUI (WindowManager::injectKeyPress):
##  - tylko w trybie GUI; poza nim fokus klawiatury zdejmowany (onFrame → setKeyFocusWidget(nullptr));
##  - Tab / Shift+Tab – następna / poprzednia kontrolka przyjmująca fokus w oknie (z zawinięciem); bez fokusu –
##    pierwsza kontrolka (okna modalnego, jeśli jest); pole z „AcceptTab” (filtry, wiersz konsoli) – Tab dla pola;
##  - strzałki – tylko gdy fokus ma przycisk: sąsiad z listy w tej kolejności, bez zawinięcia, i tylko gdy leży
##    w danym kierunku (przewaga pionowa/pozioma różnicy położenia);
##  - Enter / Enter numeryczny / Spacja – kliknięcie przycisku z fokusem (bez powtórzeń klawisza).
## Kontrolki przyjmujące fokus (getKeyFocusWidgets): widoczne, włączone przyciski (Button, CheckBox, …), pola
## tekstowe, listy i pola wyboru, w kolejności drzewa (MyGUI: kolejność dzieci). Okno = najwyższy przodek pod
## warstwą (korzeń MyGUI).

var main

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## isGuiMode – stos trybów, konsola, menu główne, kreator i okna poza stosem (jak MenuMode skryptów).
func _gui_mode() -> bool:
	if main == null:
		return false
	if main.get("gui") != null and main.gui != null and main.gui.is_gui_mode():
		return true
	return main.get("script_host") != null and main.script_host != null and main.script_host.menu_mode()

static func accepts_focus(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	if c is BaseButton:
		return not (c as BaseButton).disabled
	if c is LineEdit:
		return (c as LineEdit).editable
	return c is TextEdit or c is ItemList

static func is_button(c: Control) -> bool:
	return c is BaseButton and not (c is OptionButton) and not (c is MenuButton)

## getKeyFocusWidgets: rekurencyjnie – kontrolka przyjmująca fokus nie jest przeszukiwana dalej.
static func focus_list(root: Node, out: Array) -> void:
	for ch in root.get_children():
		if ch is CanvasItem and not (ch as CanvasItem).visible:
			continue
		if ch is Control and accepts_focus(ch):
			out.append(ch)
		else:
			focus_list(ch, out)

## Korzeń okna: przodek, którego rodzic nie jest kontrolką (warstwa / scena).
static func window_of(c: Node) -> Node:
	var w := c
	while w.get_parent() != null and w.get_parent() is Control:
		w = w.get_parent()
	return w

## Okno modalne (mModalWindow): okno z pytaniem, ilości, notatki – najwyżej położone widoczne.
func modal_window() -> Node:
	if main == null:
		return null
	var cands := []
	for n in ["confirm", "msgbox", "count_dialog", "edit_note"]:
		var o = main.get(n)
		if o != null and is_instance_valid(o) and o is Node:
			cands.append(o)
	if main.get("message_boxes") != null and main.message_boxes != null and main.message_boxes.interactive != null \
			and is_instance_valid(main.message_boxes.interactive):
		cands.append(main.message_boxes.interactive)
	var best: Node = null
	var best_layer := -INF
	for o in cands:
		var vis: bool = (o.visible if o is CanvasLayer or o is CanvasItem else true)
		if not vis:
			continue
		var lay: float = float(o.layer) if o is CanvasLayer else float(_layer_of(o))
		if lay > best_layer:
			best = o
			best_layer = lay
	return best

static func _layer_of(n: Node) -> int:
	var p := n
	while p != null:
		if p is CanvasLayer:
			return (p as CanvasLayer).layer
		p = p.get_parent()
	return 0

var _saved := {}                    # tryb → kontrolka (mKeyFocus)

## saveFocus(mode): fokus klawiatury trybu przykrywanego nowym trybem.
func save_focus(mode: String) -> void:
	var f := _focused()
	if f != null and accepts_focus(f):
		_saved[mode] = weakref(f)

## restoreFocus(mode): po powrocie do trybu – jego zapamiętany fokus (jeśli kontrolka nadal widoczna i włączona).
func restore_focus(mode: String) -> void:
	if not _saved.has(mode):
		return
	var w = (_saved[mode] as WeakRef).get_ref()
	if w != null and w is Control and accepts_focus(w):
		_set_focus(w)

func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()

func _set_focus(c: Control) -> void:
	if c.focus_mode == Control.FOCUS_NONE:
		c.focus_mode = Control.FOCUS_CLICK            # kontrolka przyjmuje fokus klawiatury (NeedKeyFocus)
	c.grab_focus()

## selectFirstWidget: pierwsza kontrolka okna modalnego, inaczej wierzchnich okien trybu GUI.
func select_first() -> bool:
	var roots := []
	var modal := modal_window()
	if modal != null:
		roots = [modal]
	else:
		var layers := []
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if (n as CanvasLayer).visible and n != self:
				layers.append(n)
		layers.sort_custom(func(a, b): return a.layer > b.layer)
		roots = layers
	for r in roots:
		var lst := []
		focus_list(r, lst)
		if not lst.is_empty():
			_set_focus(lst[0])
			return true
	return false

## switchFocus(direction, wrap): kierunki 0 lewo, 1 góra, 2 prawo, 3 dół, 4 następna, 5 poprzednia.
func switch_focus(direction: int, wrap: bool) -> bool:
	if not _gui_mode():
		return false
	var focus := _focused()
	var cycle := direction >= 4
	if focus != null and not is_button(focus) and not cycle:
		return false
	if focus != null and cycle and bool(focus.get_meta("accept_tab", false)):
		return false
	if (focus == null or not accepts_focus(focus)) and cycle:
		return select_first()
	if focus == null:
		return false
	var lst := []
	focus_list(window_of(focus), lst)
	if lst.is_empty():
		return false
	var i := lst.find(focus)
	if i < 0:
		return select_first() if cycle else false
	var forward := direction in [2, 3, 4]
	i = i + 1 if forward else i - 1
	if wrap:
		i = posmod(i, lst.size())
	else:
		i = clampi(i, 0, lst.size() - 1)
	var nxt: Control = lst[i]
	var vd: float = nxt.global_position.y - focus.global_position.y
	var hd: float = nxt.global_position.x - focus.global_position.x
	var vertical := absf(vd) > absf(hd)
	match direction:
		2:
			if hd <= 0 or vertical:
				return false
		0:
			if hd >= 0 or vertical:
				return false
		3:
			if vd <= 0 or not vertical:
				return false
		1:
			if vd >= 0 or not vertical:
				return false
	_set_focus(nxt)
	return true

## accept: przycisk z fokusem – kliknięcie (eventMouseButtonClick).
func accept() -> bool:
	var focus := _focused()
	if focus == null or not is_button(focus) or (focus as BaseButton).disabled:
		return false
	var b := focus as BaseButton
	if b.toggle_mode:
		b.button_pressed = not b.button_pressed
	b.pressed.emit()
	return true

## injectKeyPress (przed GUI). → czy klawisz obsłużony.
func inject_key(e: InputEventKey) -> bool:
	match e.keycode:
		KEY_LEFT:
			return switch_focus(0, false)
		KEY_RIGHT:
			return switch_focus(2, false)
		KEY_UP:
			return switch_focus(1, false)
		KEY_DOWN:
			return switch_focus(3, false)
		KEY_TAB:
			return switch_focus(5 if e.shift_pressed else 4, true)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if e.echo:
				return is_button(_focused())         # powtórzenia klawiszy aktywacji wyłączone
			return accept()
	return false

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed:
		return
	if not _gui_mode():
		return
	var k := e as InputEventKey
	var focus := _focused()
	var handled := inject_key(k)
	# Godot ma własną nawigację fokusu (ui_focus_next, strzałki między przyciskami) – OpenMW jej nie ma:
	# Tab poza polem z AcceptTab i strzałki na przycisku nie trafiają dalej, nawet gdy nic nie zmieniły
	if not handled:
		if k.keycode == KEY_TAB and not (focus != null and bool(focus.get_meta("accept_tab", false))):
			handled = true
		elif k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and focus != null and is_button(focus):
			handled = true
	if handled:
		get_viewport().set_input_as_handled()

## KeyboardNavigation::onFrame: poza trybem GUI bez fokusu klawiatury.
func _process(_dt: float) -> void:
	if main == null or _gui_mode():
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
