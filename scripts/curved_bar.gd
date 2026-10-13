class_name CurvedBar
extends Node2D
## Une barre courbée (une arche) posée sur le toit de la jungle. On ne marche pas dessus :
## elle sert à accrocher une liane (mettre une liane en enfant, en haut de l'arche).
## La position de la barre est le milieu de sa base.

@export var size := Vector2(360, 380)   ## largeur, hauteur
@export var thickness := 18.0
@export var color := Color(0.5, 0.38, 0.25)


func _draw() -> void:
	var points := PackedVector2Array()
	for i in 25:
		var a := PI * i / 24.0
		points.append(Vector2(-cos(a) * size.x / 2.0, -sin(a) * size.y))
	draw_polyline(points, color, thickness)
