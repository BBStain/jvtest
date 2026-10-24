class_name FerrisWheel
extends Node2D
## La grande roue du parc d'attractions de la Ville : des nacelles (plateformes traversables)
## qui tournent lentement autour du centre en restant à plat. On monte dessus et on se fait porter.
## La position du nœud est le centre de la roue.

@export var radius := 520.0
@export var cabins := 8
@export var period := 26.0                  ## durée d'un tour complet, en secondes
@export var cabin_size := Vector2(150, 16)
@export var color := Color(0.95, 0.45, 0.6)

var _time := 0.0
var _cabins: Array[AnimatableBody2D] = []


func _init() -> void:
	for i in cabins:
		var cabin := AnimatableBody2D.new()
		cabin.collision_layer = 0
		cabin.set_collision_layer_value(Fighter.PLATFORM_LAYER, true)
		cabin.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = cabin_size
		shape.shape = rect
		shape.one_way_collision = true
		cabin.add_child(shape)
		add_child(cabin)
		_cabins.append(cabin)
	_place()


func _physics_process(delta: float) -> void:
	_time += delta
	_place()
	queue_redraw()


func _angle(i: int) -> float:
	return TAU * (float(i) / cabins + _time / period)


func _place() -> void:
	for i in _cabins.size():
		_cabins[i].position = Vector2.RIGHT.rotated(_angle(i)) * radius


func _draw() -> void:
	# Le pied (deux poutres jusqu'au sol) puis la roue, ses rayons et les nacelles
	var foot := radius + 120.0
	var beam := Color(0.75, 0.75, 0.82)
	draw_line(Vector2.ZERO, Vector2(-radius * 0.45, foot), beam, 10.0)
	draw_line(Vector2.ZERO, Vector2(radius * 0.45, foot), beam, 10.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(color, 0.8), 6.0)
	for i in cabins:
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(_angle(i)) * radius, Color(color, 0.5), 3.0)
	draw_circle(Vector2.ZERO, 24.0, color)
	for cabin in _cabins:
		var p := cabin.position
		draw_line(p, p + Vector2(0, -36), beam, 3.0)
		draw_rect(Rect2(p - Vector2(cabin_size.x / 2.0, 0.0) + Vector2(0, -cabin_size.y / 2.0), Vector2(cabin_size.x, 22.0)), color)
