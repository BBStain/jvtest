class_name BreakableWindow
extends StaticBody2D
## Une fenêtre : un bloc plein qu'on peut casser. Empilées, elles forment les deux grandes colonnes
## au milieu des hauteurs de l'Arène.
## Elle casse quand :
##   - un joueur la percute assez vite (dash, projeté par un coup, lâché d'une liane...),
##     voir Fighter.WINDOW_BREAK_SPEED ; il passe alors au travers ;
##   - un coup la frappe (attaque légère ou lourde, avec ou sans arme) ;
##   - une balle, une lance lancée ou une explosion la touche.
## Une fenêtre cassée revient toute seule au bout de RESPAWN_TIME (si personne n'est à sa place).
## En ligne, seul l'hôte décide ; les copains reçoivent quelles fenêtres sont cassées (voir game_map.gd).
## La position de la fenêtre est son centre.

const RESPAWN_TIME := 15.0
const SHATTER_TIME := 0.45   ## les éclats volent ce temps

@export var size := Vector2(90, 110)
@export var color := Color(0.55, 0.78, 0.9)

var broken := false
var _broken_timer := 0.0
var _shatter := 0.0          ## effet d'éclats en cours (temps restant)
var _shape: CollisionShape2D


func _ready() -> void:
	add_to_group("fenetres")
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	add_child(_shape)


func rect() -> Rect2:
	return Rect2(global_position - size / 2.0, size)


## Casse la fenêtre (rien si elle l'est déjà). Renvoie true si elle vient de casser.
func smash() -> bool:
	if broken:
		return false
	set_broken(true)
	return true


func set_broken(value: bool) -> void:
	if value == broken:
		return
	broken = value
	_broken_timer = 0.0
	_shape.set_deferred("disabled", value)
	if value:
		_shatter = SHATTER_TIME
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _shatter > 0.0:
		_shatter -= delta
		queue_redraw()
	if not broken:
		return
	_broken_timer += delta
	if _broken_timer >= RESPAWN_TIME and not _someone_inside():
		set_broken(false)


func _someone_inside() -> bool:
	for node in get_tree().get_nodes_in_group("combattants"):
		var fighter := node as Fighter
		if fighter != null and not fighter.eliminated and fighter.body_rect().intersects(rect()):
			return true
	return false


func _draw() -> void:
	var half := size / 2.0
	if not broken:
		draw_rect(Rect2(-half, size), Color(color, 0.55))
		draw_rect(Rect2(-half, size), color, false, 4.0)
		return
	# Cassée : juste le cadre, très pâle, et des éclats qui volent un instant.
	draw_rect(Rect2(-half, size), Color(color, 0.12), false, 2.0)
	if _shatter > 0.0:
		var k := 1.0 - _shatter / SHATTER_TIME
		for i in 8:
			var dir := Vector2.RIGHT.rotated(TAU * i / 8.0 + 0.4)
			var p := dir * (12.0 + 70.0 * k)
			draw_line(p, p + dir * 14.0, Color(color, 1.0 - k), 3.0)
