class_name Projectile
extends Node2D
## Un objet qui vole dans la map : pour l'instant la lance lancée (attaque lourde de la lance).
## Il vole en cloche ; s'il touche un joueur, game.gd applique le coup et il retombe.
## Il se plante dans le premier sol ou mur qu'il rencontre. Son lanceur le ramasse en passant dessus.
## Seul l'hôte le fait bouger en ligne : les copains reçoivent sa position (voir net_state).

enum State { FLYING, DROPPED, STUCK }  ## en vol (dangereux), qui retombe (sans danger), planté

const FLY_GRAVITY := 500.0
const THROW_LIFT := 120.0               ## lancée un peu vers le haut, pour ne pas piquer tout de suite dans le sol
const DROP_GRAVITY := 2300.0
const RADIUS := 6.0                     ## épaisseur de la zone qui touche

var kind := "lance"
var owner_index := 0                    ## le joueur qui l'a lancé
var velocity := Vector2.ZERO
var state := State.FLYING
var knockback := 940.0
var length := 70.0
var color := Color(1, 1, 1)
var simulate := true                    ## false chez un copain en ligne : il ne fait qu'afficher


func _physics_process(delta: float) -> void:
	if not simulate or state == State.STUCK:
		return
	velocity.y += (FLY_GRAVITY if state == State.FLYING else DROP_GRAVITY) * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(position, tip() + step, 1)
	if velocity.y > 0.0:
		query.collision_mask |= 1 << (Fighter.PLATFORM_LAYER - 1)  # on se pose sur une plateforme en tombant
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		position += (hit.position as Vector2) - tip()
		velocity = Vector2.ZERO
		state = State.STUCK
	else:
		position += step
	if state == State.FLYING:
		rotation = velocity.angle()
	queue_redraw()


## Le bout qui touche (devant, dans le sens du vol) et l'autre bout.
func tip() -> Vector2:
	return position + Vector2.RIGHT.rotated(rotation) * length / 2.0


func tail() -> Vector2:
	return position - Vector2.RIGHT.rotated(rotation) * length / 2.0


## Il a touché quelqu'un (ou un bouclier) : il rebondit un peu et retombe, sans danger.
func drop() -> void:
	state = State.DROPPED
	velocity = Vector2(-velocity.x * 0.15, -320.0)


func net_state() -> Array:
	return [kind, owner_index, position, rotation, state, color]


func apply_net_state(data: Array) -> void:
	kind = data[0]
	owner_index = data[1]
	position = data[2]
	rotation = data[3]
	state = data[4]
	color = data[5]
	queue_redraw()


func _draw() -> void:
	var half := length / 2.0
	var alpha := 1.0 if state == State.FLYING else 0.85
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Color(color, alpha), 4.0)
	draw_colored_polygon(PackedVector2Array([Vector2(half + 8.0, 0.0), Vector2(half - 4.0, -6.0), Vector2(half - 4.0, 6.0)]),
		Color(color.lightened(0.4), alpha))
	if state == State.FLYING:
		draw_line(Vector2(-half - 30.0, 0.0), Vector2(-half, 0.0), Color(color, 0.25), 2.0)
