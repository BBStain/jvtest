class_name Projectile
extends Node2D
## Un objet qui vole dans la map. game.gd décide de ce qui arrive quand il touche un joueur.
##   lance   : la lance lancée (attaque lourde de la lance). Elle vole en cloche, se plante dans
##             le premier sol ou mur, et son lanceur la ramasse en passant dessus.
##   balle   : une balle de pistolet, rapide et en ligne droite ; elle disparaît contre un mur.
##             Un coup donné au bon moment la renvoie (voir game.gd, _deflect_bullet).
##   grenade : elle rebondit sur le sol et explose quand sa mèche est finie. Un coup la repousse.
## Seul l'hôte le fait bouger en ligne : les copains reçoivent sa position (voir net_state).
## Dessin très simple : à remplacer par un graphiste.

enum State { FLYING, DROPPED, STUCK }  ## en vol (dangereux), qui retombe (sans danger), posé

const FLY_GRAVITY := 500.0
const THROW_LIFT := 120.0               ## lance lancée un peu vers le haut, pour ne pas piquer tout de suite dans le sol
const DROP_GRAVITY := 2300.0
const GRENADE_GRAVITY := 1600.0
const GRENADE_BOUNCE := 0.4             ## la grenade rebondit (garde 40 % de sa vitesse)
const BULLET_LIFETIME := 2.5            ## une balle qui ne touche rien disparaît au bout de ce temps
const RADIUS := 6.0                     ## épaisseur de la zone qui touche

var kind := "lance"
var owner_index := 0                    ## le joueur qui l'a lancé (ou qui a renvoyé la balle)
var velocity := Vector2.ZERO
var state := State.FLYING
var knockback := 940.0
var length := 70.0
var color := Color(1, 1, 1)
var fuse := -1.0                        ## grenade : temps avant l'explosion
var age := 0.0
var finished := false                   ## à retirer (balle arrivée dans un mur, grenade qui explose)
var simulate := true                    ## false chez un copain en ligne : il ne fait qu'afficher


func _physics_process(delta: float) -> void:
	if not simulate:
		return
	age += delta
	match kind:
		"balle":
			_tick_bullet(delta)
		"grenade":
			_tick_grenade(delta)
		_:
			_tick_spear(delta)
	queue_redraw()


func _tick_spear(delta: float) -> void:
	if state == State.STUCK:
		return
	velocity.y += (FLY_GRAVITY if state == State.FLYING else DROP_GRAVITY) * delta
	var step := velocity * delta
	var hit := _ray(position, tip() + step, velocity.y > 0.0)
	if not hit.is_empty():
		position += (hit.position as Vector2) - tip()
		velocity = Vector2.ZERO
		state = State.STUCK
	else:
		position += step
	if state == State.FLYING:
		rotation = velocity.angle()


func _tick_bullet(delta: float) -> void:
	var step := velocity * delta
	if age > BULLET_LIFETIME or not _ray(position, tip() + step, false).is_empty():
		finished = true
		return
	position += step
	rotation = velocity.angle()


func _tick_grenade(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		finished = true  # game.gd fait l'explosion
		return
	velocity.y += GRENADE_GRAVITY * delta
	var step := velocity * delta
	var hit := _ray(position, position + step + step.normalized() * RADIUS, velocity.y > 0.0)
	if hit.is_empty():
		position += step
		return
	# Rebond : la vitesse est renvoyée par la surface touchée (et s'amortit).
	var normal: Vector2 = hit.normal
	velocity = velocity.bounce(normal) * GRENADE_BOUNCE
	if normal.y < -0.5:
		velocity.x *= 0.8  # elle roule de moins en moins sur le sol
	if velocity.length() < 60.0:
		velocity = Vector2.ZERO
	position = (hit.position as Vector2) + normal * RADIUS


## Un rayon contre les sols et les murs (et les plateformes traversables quand on tombe dessus).
func _ray(from: Vector2, to: Vector2, with_platforms: bool) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	if with_platforms:
		query.collision_mask |= 1 << (Fighter.PLATFORM_LAYER - 1)
	return get_world_2d().direct_space_state.intersect_ray(query)


## Le bout qui touche (devant, dans le sens du vol) et l'autre bout.
func tip() -> Vector2:
	return position + Vector2.RIGHT.rotated(rotation) * length / 2.0


func tail() -> Vector2:
	return position - Vector2.RIGHT.rotated(rotation) * length / 2.0


## La lance a touché quelqu'un (ou un bouclier) : elle rebondit un peu et retombe, sans danger.
func drop() -> void:
	state = State.DROPPED
	velocity = Vector2(-velocity.x * 0.15, -320.0)


func net_state() -> Array:
	return [kind, owner_index, position, rotation, state, color, fuse]


func apply_net_state(data: Array) -> void:
	kind = data[0]
	owner_index = data[1]
	position = data[2]
	rotation = data[3]
	state = data[4]
	color = data[5]
	fuse = data[6] if data.size() > 6 else -1.0
	length = 16.0 if kind == "balle" else 18.0 if kind == "grenade" else 70.0
	queue_redraw()


func _draw() -> void:
	match kind:
		"balle":
			draw_line(Vector2(-length / 2.0 - 24.0, 0.0), Vector2(-length / 2.0, 0.0), Color(color, 0.3), 2.0)
			draw_line(Vector2(-length / 2.0, 0.0), Vector2(length / 2.0, 0.0), color, 4.0)
		"grenade":
			var blink := int(age / lerpf(0.05, 0.25, clampf(fuse / 3.0, 0.0, 1.0))) % 2 == 0
			draw_circle(Vector2.ZERO, 8.0, Color(1, 0.3, 0.2) if blink and fuse < 1.5 else color)
			draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, Color(1, 1, 1, 0.6), 1.5)
		_:
			var half := length / 2.0
			var alpha := 1.0 if state == State.FLYING else 0.85
			draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Color(color, alpha), 4.0)
			draw_colored_polygon(PackedVector2Array([Vector2(half + 8.0, 0.0), Vector2(half - 4.0, -6.0), Vector2(half - 4.0, 6.0)]),
				Color(color.lightened(0.4), alpha))
			if state == State.FLYING:
				draw_line(Vector2(-half - 30.0, 0.0), Vector2(-half, 0.0), Color(color, 0.25), 2.0)
