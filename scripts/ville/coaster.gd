class_name Coaster
extends Node2D
## Le petit grand huit du parc d'attractions de la Ville : des rails (on peut marcher dessus,
## traversables par en dessous) et un wagon qui les parcourt en aller-retour en emmenant
## ceux qui sont posés dessus. Les points du rail sont relatifs à la position du nœud.

@export var points: PackedVector2Array = PackedVector2Array()
@export var speed := 520.0                  ## vitesse du wagon, en px/s
@export var color := Color(0.98, 0.78, 0.3)
@export var cart_size := Vector2(130, 18)

const RAIL := 14.0

var _time := 0.0
var _length := 0.0
var _cart: AnimatableBody2D


func setup(track: PackedVector2Array) -> void:
	points = track
	_length = 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		_length += a.distance_to(b)
		# Un morceau de rail : un bloc fin, tourné dans le sens de la pente
		var piece := StaticBody2D.new()
		piece.collision_layer = 0
		piece.set_collision_layer_value(Fighter.PLATFORM_LAYER, true)
		piece.collision_mask = 0
		piece.position = (a + b) / 2.0
		piece.rotation = (b - a).angle()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(a.distance_to(b) + 4.0, RAIL)
		shape.shape = rect
		shape.one_way_collision = true
		piece.add_child(shape)
		add_child(piece)
	_cart = AnimatableBody2D.new()
	_cart.collision_layer = 0
	_cart.set_collision_layer_value(Fighter.PLATFORM_LAYER, true)
	_cart.collision_mask = 0
	var cart_shape := CollisionShape2D.new()
	var cart_rect := RectangleShape2D.new()
	cart_rect.size = cart_size
	cart_shape.shape = cart_rect
	cart_shape.one_way_collision = true
	_cart.add_child(cart_shape)
	add_child(_cart)
	_place()


func _physics_process(delta: float) -> void:
	_time += delta
	_place()
	queue_redraw()


## Le wagon : à plat, posé au-dessus du rail, il va jusqu'au bout puis revient.
func _place() -> void:
	if _cart == null or _length <= 0.0:
		return
	var d := pingpong(_time * speed, _length)
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if d <= seg or i == points.size() - 2:
			var p := points[i].lerp(points[i + 1], clampf(d / seg, 0.0, 1.0))
			_cart.position = p - Vector2(0.0, RAIL / 2.0 + cart_size.y / 2.0 + 6.0)
			return
		d -= seg


func _draw() -> void:
	var post := Color(0.6, 0.6, 0.68)
	for p in points:
		draw_line(p, Vector2(p.x, 0.0), post, 6.0)  # les piliers jusqu'au sol (y = 0 : la rue)
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], color, RAIL)
	if _cart != null:
		draw_rect(Rect2(_cart.position - cart_size / 2.0, cart_size), Color(0.9, 0.25, 0.3))
