class_name LaserTrace
extends Node2D
## Le trait du canon laser d'un mecha : il apparaît d'un coup (le tir est instantané) et s'efface vite.

const LIFETIME := 0.25

var from := Vector2.ZERO                ## dans la map
var to := Vector2.ZERO
var width := 14.0
var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var alpha := 1.0 - _age / LIFETIME
	draw_line(to_local(from), to_local(to), Color(Fighter.LASER_COLOR, 0.6 * alpha), width * 2.0)
	draw_line(to_local(from), to_local(to), Color(1, 1, 1, alpha), width * 0.6)
