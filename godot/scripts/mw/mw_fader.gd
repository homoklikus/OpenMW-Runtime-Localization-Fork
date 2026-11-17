extends CanvasLayer
## Zaciemnienie ekranu jak OpenMW ScreenFader/FadeOp (mwgui/screenfader.cpp) i WindowManager::fadeScreenIn/Out/To:
## czarna nakładka o nieprzezroczystości alpha; kolejka operacji (każda: czas, alpha docelowe, opóźnienie),
## liniowa zmiana alpha w czasie operacji, pierwsza operacja z kolejki startuje od bieżącego alpha.
## fadeScreenOut(t) – do czerni (alpha 1), fadeScreenIn(t) – do obrazu (alpha 0), fadeScreenTo(p, t) – alpha p/100.
## time < 0 – pomijane; time == 0 i delay == 0 – natychmiast. Działa także w pauzie (eventFrameStart MyGUI).
## Skrypty (FadeIn/FadeOut/FadeTo) wołają z clear_queue = false; nowa gra – fadeScreenOut(0) i fadeScreenIn(1).

var alpha := 0.0
var factor := 1.0
var _queue: Array = []              # [{time, target, delay, remaining, start, running}]
var _rect: ColorRect = null

func _ready() -> void:
	layer = 110                      # nad grą i interfejsem, pod filmami
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_apply()

func _apply() -> void:
	if _rect == null:
		return
	var a := 1.0 - ((1.0 - alpha) * factor)
	_rect.color.a = a
	_rect.visible = a > 0.0

func fade_screen_in(time: float, clear_queue := true, delay := 0.0) -> void:
	if clear_queue:
		clear_queue_ops()
	_queue_op(time, 0.0, delay)

func fade_screen_out(time: float, clear_queue := true, delay := 0.0) -> void:
	if clear_queue:
		clear_queue_ops()
	_queue_op(time, 1.0, delay)

func fade_screen_to(percent: int, time: float, clear_queue := true, delay := 0.0) -> void:
	if clear_queue:
		clear_queue_ops()
	_queue_op(time, percent / 100.0, delay)

func clear_queue_ops() -> void:
	_queue.clear()

## ScreenFader::clear (np. czyszczenie stanu przy nowej grze / wczytaniu).
func clear() -> void:
	clear_queue_ops()
	alpha = 0.0
	_apply()

func is_empty() -> bool:
	return _queue.is_empty()

func _queue_op(time: float, target: float, delay: float) -> void:
	if time < 0.0:
		return
	if time == 0.0 and delay == 0.0:
		alpha = target
		_apply()
		return
	_queue.append({"time": time, "target": target, "delay": delay, "remaining": time + delay, "start": 0.0,
		"running": false})

func _process(dt: float) -> void:
	step(dt)

## Jedna klatka (onFrameStart) – osobno dla testów.
func step(dt: float) -> void:
	if _queue.is_empty():
		return
	var op: Dictionary = _queue[0]
	if not op.running:
		op.remaining = float(op.time) + float(op.delay)
		op.start = alpha
		op.running = true
	if is_equal_approx(float(op.start), float(op.target)):
		_queue.pop_front()
		return
	if float(op.remaining) <= 0.0:
		alpha = float(op.target)
		_apply()
		_queue.pop_front()
		return
	if float(op.remaining) > float(op.time):
		op.remaining = float(op.remaining) - dt
		return
	if float(op.start) > float(op.target):
		alpha = maxf(alpha - dt / float(op.time) * (float(op.start) - float(op.target)), float(op.target))
	else:
		alpha = minf(alpha + dt / float(op.time) * (float(op.target) - float(op.start)), float(op.target))
	_apply()
	op.remaining = float(op.remaining) - dt
