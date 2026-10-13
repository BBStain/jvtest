class_name JungleTree
extends Node2D
## Un arbre de la jungle (sur le toit) : un tronc qu'on traverse et de grosses branches sur
## lesquelles on peut se poser (traversables par en dessous, comme les autres plateformes).
## Une liane peut pendre d'une branche (mettre une liane en enfant).
## La position de l'arbre est le pied du tronc. Les branches sont des rectangles, à partir du pied.

@export var trunk_size := Vector2(46, 520)  ## largeur, hauteur du tronc
@export var branches: Array[Rect2] = []
@export var color := Color(0.5, 0.38, 0.25)
@export var leaves_color := Color(0.25, 0.55, 0.28)
@export var leaves_radius := 120.0


func _ready() -> void:
	for branch in branches:
		var body := StaticBody2D.new()
		body.collision_layer = 0
		body.set_collision_layer_value(Fighter.PLATFORM_LAYER, true)
		body.collision_mask = 0
		body.position = branch.get_center()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = branch.size
		shape.shape = rect
		shape.one_way_collision = true
		body.add_child(shape)
		add_child(body)


func _draw() -> void:
	draw_circle(Vector2(0.0, -trunk_size.y), leaves_radius, leaves_color)
	draw_rect(Rect2(-trunk_size.x / 2.0, -trunk_size.y, trunk_size.x, trunk_size.y), color)
	for branch in branches:
		draw_rect(branch, color)
