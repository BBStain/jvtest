class_name MovingPlatform
extends AnimatableBody2D
## Une plateforme traversable (on passe à travers par en dessous) qui fait des allers-retours.
## Les joueurs posés dessus sont transportés avec elle.
## Réglages dans l'inspecteur de Godot (size, travel, period), sur la plateforme dans la scène de la map.

@export var size := Vector2(160, 16)        ## largeur, hauteur
@export var travel := Vector2(400, 0)       ## trajet depuis la position de départ (x : droite, y : bas)
@export var period := 6.0                   ## durée d'un aller-retour complet, en secondes (sans les arrêts)
@export var pause := 0.0                    ## arrêt à chaque bout du trajet, en secondes (ascenseur)
@export var color := Color(0.62, 0.55, 0.85)

var _start := Vector2.ZERO
var _time := 0.0


func _ready() -> void:
	_start = position
	collision_layer = 0
	set_collision_layer_value(Fighter.PLATFORM_LAYER, true)
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.one_way_collision = true
	add_child(shape)


func _physics_process(delta: float) -> void:
	set_time(_time + delta)


## Où en est la plateforme dans ses allers-retours (en secondes). En ligne, l'hôte l'envoie aux
## copains pour qu'ils voient les plateformes au même endroit que lui.
func get_time() -> float:
	return _time


func set_time(time: float) -> void:
	_time = time
	# Va-et-vient en douceur : ralentit à chaque bout du trajet (et s'y arrête "pause" secondes).
	var half := period / 2.0
	var t := fposmod(_time, period + 2.0 * pause)
	var k := 0.0
	if t < half:
		k = (1.0 - cos(t / half * PI)) / 2.0
	elif t < half + pause:
		k = 1.0
	elif t < period + pause:
		k = (1.0 + cos((t - half - pause) / half * PI)) / 2.0
	position = _start + travel * k


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), color)
	draw_rect(Rect2(-size.x / 2.0, -size.y / 2.0, size.x, 4.0), color.lightened(0.35))
