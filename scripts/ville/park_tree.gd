class_name ParkTree
extends StaticBody2D
## Un arbre du parc de la Ville : un tronc (du décor, on passe devant) et un feuillage rond
## dont le dessus est une plateforme traversable : on peut se percher dans les arbres.
## La position du nœud est le pied du tronc.

@export var height := 420.0                 ## du pied au centre du feuillage
@export var crown := 130.0                  ## rayon du feuillage
@export var color := Color(0.32, 0.68, 0.38)


func setup(tree_height: float, crown_radius: float) -> void:
	height = tree_height
	crown = crown_radius
	collision_layer = 0
	set_collision_layer_value(Fighter.PLATFORM_LAYER, true)
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(crown * 1.5, 16.0)
	shape.shape = rect
	shape.one_way_collision = true
	shape.position = Vector2(0.0, -height - crown * 0.62)
	add_child(shape)


func _draw() -> void:
	draw_rect(Rect2(-14.0, -height, 28.0, height), Color(0.5, 0.36, 0.24))
	draw_circle(Vector2(0.0, -height), crown, color)
