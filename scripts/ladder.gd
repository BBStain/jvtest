class_name Ladder
extends Node2D
## Une échelle : en la touchant, on appuie sur "haut" pour s'y accrocher, et on monte tout seul,
## très vite. Arrivé en haut, on est éjecté un peu vers le haut (et sur le côté, voir exit_push).
## Saut : on lâche l'échelle en sautant. Bas : on la lâche. Un coup reçu fait lâcher aussi.
## Le combattant gère tout ça lui-même (voir fighter.gd) : il cherche les échelles du groupe "echelles".
## Réglages dans l'inspecteur de Godot, sur l'échelle dans la scène de la map.
## La position de l'échelle est son centre.

@export var size := Vector2(40, 1000)          ## largeur, hauteur
@export var exit_push := Vector2(520, -760)    ## éjection en sortant par le haut (x : droite, y : bas)
@export var color := Color(0.85, 0.7, 0.4)


func _ready() -> void:
	add_to_group("echelles")


## Le rectangle de l'échelle, dans la map.
func rect() -> Rect2:
	return Rect2(global_position - size / 2.0, size)


## Le haut de l'échelle (on en sort quand les pieds arrivent là).
func top() -> float:
	return global_position.y - size.y / 2.0


func _draw() -> void:
	var half := size / 2.0
	var rail := Color(color, 0.95)
	draw_rect(Rect2(-half.x, -half.y, 5.0, size.y), rail)
	draw_rect(Rect2(half.x - 5.0, -half.y, 5.0, size.y), rail)
	var y := -half.y + 12.0
	while y < half.y:
		draw_rect(Rect2(-half.x, y, size.x, 4.0), Color(color, 0.8))
		y += 28.0
