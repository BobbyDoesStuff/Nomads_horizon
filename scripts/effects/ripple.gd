class_name Ripple
extends Node2D
## A short-lived expanding ring drawn at a player's feet over water.

const LIFETIME := 0.6
const START_RADIUS := 6.0
const END_RADIUS := 36.0

var _life: float = 0.0


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	_life += delta
	if _life >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _life / LIFETIME
	var radius := lerpf(START_RADIUS, END_RADIUS, t)
	var alpha := 1.0 - t
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.7, 0.9, 1.0, alpha * 0.7), 2.5)
	draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, alpha * 0.35), 1.5)
