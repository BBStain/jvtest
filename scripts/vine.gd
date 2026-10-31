class_name Vine
extends Node2D
## Une liane : elle pend depuis sa position (le point d'accroche, en haut) sur "length" pixels.
## En sautant dessus (en l'air), on s'y accroche tout seul et on se balance comme un pendule :
## gauche / droite pour prendre de l'élan, saut pour lâcher en gardant l'élan, bas pour se laisser tomber.
## Un coup reçu fait lâcher. Le combattant gère tout ça lui-même (voir fighter.gd) : il cherche les
## lianes du groupe "lianes".
## La liane ne fait que se dessiner : quand un joueur s'y balance, elle suit sa main ; quand il lâche,
## elle se balance encore un peu toute seule. Accrochée à quelque chose qui bouge (une structure de
## l'éditeur), elle balance aussi quand son point d'accroche démarre, freine ou change de sens.
## Réglages dans l'inspecteur de Godot, sur la liane dans la scène de la map.

@export var length := 260.0
@export var color := Color(0.35, 0.7, 0.3)

const WIDTH := 8.0
const FREE_DAMPING := 1.6   ## une liane lâchée s'arrête de bouger petit à petit
const FREE_GRAVITY := 2300.0
const ANCHOR_SWAY := 2.0      ## combien les à-coups du point d'accroche la font balancer (plus = plus visible)
const MAX_ANCHOR_ACCEL := 8000.0
const TELEPORT_SPEED := 6000.0  ## plus vite que ça, le point d'accroche a été déplacé d'un coup : on ignore

var _angle := 0.0           ## 0 = pend droit vers le bas
var _angle_speed := 0.0
var _holder: Fighter = null
var _last_anchor := Vector2.INF
var _anchor_speed := Vector2.ZERO


func _ready() -> void:
	add_to_group("lianes")


## Le point de la liane (dans la map) à "distance" pixels de son point d'accroche, là où elle est
## en ce moment (elle se balance).
func point_at(distance: float) -> Vector2:
	return global_position + Vector2(sin(_angle), cos(_angle)) * distance


## Le bas de la liane quand elle pend droit (dans la map).
func bottom() -> Vector2:
	return global_position + Vector2(0.0, length)


func _process(delta: float) -> void:
	_holder = null
	for node in get_tree().get_nodes_in_group("combattants"):
		var fighter := node as Fighter
		if fighter != null and fighter.is_swinging_on(self):
			_holder = fighter
			break
	sway(delta)


## Fait avancer le balancement de "delta" secondes (l'éditeur l'appelle lui-même pour « Voir bouger »).
func sway(delta: float) -> void:
	if delta > 0.0:
		var anchor_accel := _anchor_accel(delta)
		if _holder != null:
			var offset := _holder.global_position - global_position
			var angle := atan2(offset.x, offset.y)
			_angle_speed = (angle - _angle) / delta
			_angle = angle
		else:
			# Un pendule dont le point d'accroche bouge : s'il part à droite, la liane traîne à gauche.
			var gravity := FREE_GRAVITY - anchor_accel.y
			_angle_speed += -(gravity * sin(_angle) + anchor_accel.x * cos(_angle)) / length * delta
			_angle_speed *= maxf(1.0 - FREE_DAMPING * delta, 0.0)
			_angle += _angle_speed * delta
	queue_redraw()


## Remet la liane droite, immobile (l'éditeur, quand on éteint « Voir bouger »).
func reset_sway() -> void:
	_angle = 0.0
	_angle_speed = 0.0
	_last_anchor = Vector2.INF
	_anchor_speed = Vector2.ZERO
	queue_redraw()


## L'accélération du point d'accroche (lissée, et ignorée s'il a été déplacé d'un coup).
func _anchor_accel(delta: float) -> Vector2:
	var anchor := global_position
	if _last_anchor == Vector2.INF:
		_last_anchor = anchor
		return Vector2.ZERO
	var speed := (anchor - _last_anchor) / delta
	_last_anchor = anchor
	if speed.length() > TELEPORT_SPEED:
		_anchor_speed = Vector2.ZERO
		return Vector2.ZERO
	# (lissé : la map bouge aux images de physique, la liane se dessine aux images d'écran)
	var smoothed := _anchor_speed.lerp(speed, minf(12.0 * delta, 1.0))
	var accel := (smoothed - _anchor_speed) / delta
	_anchor_speed = smoothed
	return accel.limit_length(MAX_ANCHOR_ACCEL) * ANCHOR_SWAY


func _draw() -> void:
	var dir := Vector2(sin(_angle), cos(_angle))
	draw_line(Vector2.ZERO, dir * length, color, WIDTH)
	draw_circle(Vector2.ZERO, WIDTH, color.darkened(0.3))
