class_name LooseBody
extends RefCounted
## La physique d'un objet qui traîne sur la map sans faire mal : objet tombé du ciel, arme qui a
## sauté des mains. Il tombe, rebondit sur les murs et les plafonds, se pose sur les sols et les
## plateformes, et se laisse transporter par ce qui bouge (plateforme, bloc de l'éditeur).
## Si ce qui le porte disparaît (fenêtre cassée, plateforme partie), il retombe.
## Un coup le fait valdinguer (voir Game._hit_loose_objects).

const GRAVITY := 1400.0
const MAX_FALL := 1400.0
const BOUNCE := 0.5                  ## contre un mur ou un plafond, il garde 50 % de sa vitesse

var resting := false                 ## posé (il suit ce qui le porte)
var support: CollisionObject2D       ## ce sur quoi il est posé
var _local := Vector2.ZERO           ## sa place sur "support" (pour le suivre quand il bouge)


## Une frame : "radius" est la distance entre le centre de l'objet et le sol quand il est posé.
## Renvoie sa nouvelle vitesse (zéro une fois posé).
func step(node: Node2D, velocity: Vector2, radius: float, delta: float) -> Vector2:
	if resting:
		follow(node)
		if _ground_below(node, radius):
			return Vector2.ZERO
		resting = false
		support = null
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	var motion := velocity * delta
	if motion == Vector2.ZERO:
		return velocity
	var hit := _ray(node, node.global_position, node.global_position + motion + motion.normalized() * radius, velocity.y > 0.0)
	if hit.is_empty():
		node.global_position += motion
		return velocity
	var normal: Vector2 = hit.normal
	node.global_position = (hit.position as Vector2) + normal * radius
	if normal.y < -0.5 and velocity.y >= 0.0:
		rest_on(node, hit.collider)
		return Vector2.ZERO
	return velocity.bounce(normal) * BOUNCE


## Un coup (ou une explosion) le lance : il décolle.
func launch() -> void:
	resting = false
	support = null


## Toujours quelque chose sous lui ? Il s'y recolle (une plateforme qui descend l'emmène).
func _ground_below(node: Node2D, radius: float) -> bool:
	var from := node.global_position - Vector2(0.0, 4.0)
	var hit := _ray(node, from, node.global_position + Vector2(0.0, radius + 6.0), true)
	if hit.is_empty() or (hit.normal as Vector2).y > -0.5:
		return false
	node.global_position.y = (hit.position as Vector2).y - radius
	rest_on(node, hit.collider)
	return true


## Suit ce qui le porte, s'il bouge.
func follow(node: Node2D) -> void:
	if is_instance_valid(support) and support.is_inside_tree():
		node.global_position = support.global_transform * _local


func rest_on(node: Node2D, collider: Object) -> void:
	resting = true
	support = collider as CollisionObject2D
	if support != null:
		_local = support.global_transform.affine_inverse() * node.global_position


## Un rayon contre les sols et les murs (et les plateformes traversables quand il tombe dessus).
func _ray(node: Node2D, from: Vector2, to: Vector2, with_platforms: bool) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	if with_platforms:
		query.collision_mask |= 1 << (Fighter.PLATFORM_LAYER - 1)
	return node.get_world_2d().direct_space_state.intersect_ray(query)
