class_name MicroExplosion
extends Node2D
## La petite explosion quand deux attaques lourdes se percutent :
## un éclair, une onde qui s'agrandit et des éclats qui partent dans tous les sens.

const LIFETIME := 0.6
const RADIUS := 90.0     ## taille de l'onde à la fin
const SPARKS := 10

const DEFAULT_COLOR := Color(1.0, 0.45, 0.2)

var color := DEFAULT_COLOR
var _age := 0.0
var _spark_dirs: Array[Vector2] = []


func _ready() -> void:
	for i in SPARKS:
		_spark_dirs.append(Vector2.RIGHT.rotated(TAU * i / SPARKS + randf_range(-0.2, 0.2)) * randf_range(0.7, 1.2))


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFETIME
	var ease_out := 1.0 - (1.0 - t) * (1.0 - t)
	var alpha := 1.0 - t
	# Éclair blanc au tout début
	var flash := clampf(1.0 - _age / 0.1, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, 40.0 + 30.0 * (1.0 - flash), Color(1, 1, 1, flash))
	# Boule de feu qui gonfle puis s'efface
	draw_circle(Vector2.ZERO, RADIUS * 0.45 * ease_out, Color(color, 0.5 * alpha))
	# Onde de choc
	draw_arc(Vector2.ZERO, RADIUS * ease_out, 0.0, TAU, 32, Color(1, 0.9, 0.6, alpha), 5.0 * alpha + 1.0)
	# Éclats
	for dir in _spark_dirs:
		var start := dir * RADIUS * ease_out * 0.6
		draw_line(start, start + dir * 22.0 * alpha, Color(1, 0.85, 0.4, alpha), 3.0)
