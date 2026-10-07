class_name ClashMark
extends Node2D
## La marque laissée sur le terrain quand deux attaques se contrent.
## Elle apparaît d'un coup, puis grossit doucement et s'efface en quelques secondes.

const LIFETIME := 3.0          ## durée avant de disparaître complètement (en secondes)
const SIZE := 14.0

var color := Color(1, 1, 1)    ## blanc = deux attaques qui s'annulent, orange = attaque lourde contrée
var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFETIME
	var alpha := 1.0 - t * t
	var flash := clampf(1.0 - _age / 0.15, 0.0, 1.0)   # gros éclat au tout début
	var size := SIZE * (1.0 + t * 0.6)
	draw_circle(Vector2.ZERO, size * 0.35 + flash * 14.0, Color(color, alpha))
	draw_arc(Vector2.ZERO, size * 1.3, 0.0, TAU, 24, Color(color, alpha * 0.6), 3.0)
	for i in 4:
		var dir := Vector2.RIGHT.rotated(PI / 4.0 + i * PI / 2.0)
		draw_line(dir * size * 0.6, dir * size * (1.6 + flash), Color(color, alpha), 3.0)
