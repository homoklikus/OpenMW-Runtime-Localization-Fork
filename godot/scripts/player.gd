extends "res://scripts/mw/mw_actor.gd"
## Gracz = MWActor + kontroler gracza (wejście, kamera). Plik zostaje pod tą ścieżką dla zgodności.

const PlayerController := preload("res://scripts/mw/mw_player_controller.gd")
var cam: Camera3D
var mouse_sens := 0.0025:
	set(v):
		mouse_sens = v
		if controller:
			controller.mouse_sens = v
var invert_y := false:
	set(v):
		invert_y = v
		if controller:
			controller.invert_y = v

func _ready() -> void:
	kind = "player"
	record_id = "player"
	super()
	var c := PlayerController.new()
	c.name = "PlayerController"
	c.mouse_sens = mouse_sens
	c.invert_y = invert_y
	add_child(c)
	c.attach(self)
	cam = c.cam
	controller = c
