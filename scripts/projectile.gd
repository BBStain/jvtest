class_name Projectile
extends Node2D
## Un objet qui vole dans la map. game.gd décide de ce qui arrive quand il touche un joueur.
##   lance   : la lance lancée (attaque lourde de la lance). Elle vole en cloche, se plante dans
##             le premier sol ou mur, et son lanceur la ramasse en passant dessus.
##   balle   : une balle de pistolet, rapide et en ligne droite ; elle disparaît contre un mur.
##             Un coup donné au bon moment la renvoie (voir game.gd, _deflect_bullet).
##   fleche  : la flèche de l'arc (attaque lourde). Elle vole comme la lance et se plante dans le
##             décor ; seul celui qui tient l'arc d'où elle vient peut la ramasser. Contrée, elle casse.
##   grenade : collante. Elle se colle au premier élément de la map qu'elle touche (sol, mur,
##             plateforme qui bouge, liane, fenêtre) et explose quand sa mèche est finie. Une fenêtre
##             touchée trop vite casse et la grenade continue. Un coup la décolle et la repousse.
##   arme    : l'arme qui a sauté des mains (blocage parfait) ou qu'on a lancée avec RB. Elle vole
##             en tournant, sans danger, rebondit sur les murs, se pose au sol. Un joueur à mains
##             nues l'attrape en vol ou la ramasse en passant dessus (voir game.gd, _resolve_spear).
## Seul l'hôte le fait bouger en ligne : les copains reçoivent sa position (voir net_state).
## Dessin très simple : à remplacer par un graphiste.

enum State { FLYING, DROPPED, STUCK }  ## en vol (dangereux), qui retombe (sans danger), posé

const FLY_GRAVITY := 500.0
const THROW_LIFT := 120.0               ## lance lancée un peu vers le haut, pour ne pas piquer tout de suite dans le sol
const DROP_GRAVITY := 2300.0
const GRENADE_GRAVITY := 900.0          ## la grenade vole plus droit qu'avant (elle tombe moins vite)
const GRENADE_WINDOW_BREAK := 900.0     ## plus vite que ça, elle casse la fenêtre au lieu de s'y coller
const BULLET_LIFETIME := 2.5            ## une balle qui ne touche rien disparaît au bout de ce temps
const ARROW_GRAVITY := 400.0            ## la flèche de l'arc tombe un peu en volant
const ARROW_LENGTH := 34.0
const RADIUS := 6.0                     ## épaisseur de la zone qui touche
const SPEAR_LENGTH := 70.0              ## lance neuve (plus courte à chaque fois qu'elle est contrée)
const KNOCKED_SPIN := 14.0              ## arme qui a sauté des mains : elle tourne sur elle-même en volant
const KNOCKED_RADIUS := 4.0             ## ... (elle tombe et rebondit comme un objet, voir LooseBody)
const KNOCKED_SCALE := 1.3              ## ... dessinée un peu plus grande qu'en main, pour la repérer

var kind := "lance"
var owner_index := 0                    ## le joueur qui l'a lancé (ou qui a renvoyé la balle)
var velocity := Vector2.ZERO
var state := State.FLYING
var knockback := 940.0
var length := SPEAR_LENGTH
var head := 0.0                         ## arme qui a sauté : taille de son bout (tête du marteau...)
var color := Color(1, 1, 1)
var fuse := -1.0                        ## grenade : temps avant l'explosion
var blast := 1.0                        ## grenade : force de l'explosion (plus elle a été chargée, plus fort)
var age := 0.0
var finished := false                   ## à retirer (balle arrivée dans un mur, grenade qui explose)
var weapon: WeaponStats                 ## lance ou arme : l'arme qu'on récupère en la ramassant...
var counters := 0                       ## ... et son usure (voir Fighter.weapon_counters)
var ammo := Fighter.ARROWS_MAX          ## arc par terre : ses flèches ; flèche : l'arc auquel elle revient (bow_id)
var bow_id := 0
var body := LooseBody.new()             ## arme posée ou plantée : elle suit ce qui la porte (plateforme qui bouge)
var stuck_vine: Vine                    ## grenade collée à une liane...
var stuck_on_vine := 0.0                ## ... à cette distance de son point d'accroche
var _stuck_normal := Vector2.UP         ## grenade collée : le côté d'où elle est arrivée
var tumbling := false                   ## lance frappée ou contrée : elle vole pointe devant et se replante
var hit_lock := 0.0                     ## vient d'être frappée : le même coup ne la refrappe pas
var simulate := true                    ## false chez un copain en ligne : il ne fait qu'afficher


func _physics_process(delta: float) -> void:
	if not simulate:
		return
	age += delta
	hit_lock -= delta
	match kind:
		"balle":
			_tick_bullet(delta)
		"grenade":
			_tick_grenade(delta)
		"arme":
			_tick_knocked(delta)
		_:
			_tick_spear(delta)
	queue_redraw()


func _tick_spear(delta: float) -> void:
	if state == State.STUCK:
		_follow_support()
		return
	var gravity := ARROW_GRAVITY if kind == "fleche" else FLY_GRAVITY
	velocity.y += (gravity if state == State.FLYING else DROP_GRAVITY) * delta
	var step := velocity * delta
	var hit := _ray(position, tip() + step, velocity.y > 0.0)
	if state == State.FLYING and not hit.is_empty() and hit.collider is BreakableWindow:
		(hit.collider as BreakableWindow).smash()  # la lance casse la fenêtre et passe au travers
		hit = {}
	if not hit.is_empty():
		position += (hit.position as Vector2) - tip()
		velocity = Vector2.ZERO
		state = State.STUCK
		tumbling = false
		body.rest_on(self, hit.collider)
	else:
		position += step
	if state == State.FLYING or tumbling:
		rotation = velocity.angle()  # frappée par un coup : elle part pointe devant


## Lance plantée : elle suit ce dans quoi elle est plantée (bloc qui bouge). S'il disparaît
## (fenêtre cassée...), elle retombe.
func _follow_support() -> void:
	body.follow(self)
	var dir := Vector2.RIGHT.rotated(rotation)
	if _ray(tip() - dir * 6.0, tip() + dir * 6.0, true).is_empty():
		state = State.DROPPED
		velocity = Vector2.ZERO
		body.launch()


func _tick_bullet(delta: float) -> void:
	var step := velocity * delta
	var hit := _ray(position, tip() + step, false)
	if not hit.is_empty() and hit.collider is BreakableWindow:
		(hit.collider as BreakableWindow).smash()  # la balle casse la fenêtre et s'arrête
	if age > BULLET_LIFETIME or not hit.is_empty():
		finished = true
		return
	position += step
	rotation = velocity.angle()


func _tick_grenade(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		finished = true  # game.gd fait l'explosion
		return
	if state == State.STUCK:
		_follow_sticky()
		return
	velocity.y += GRENADE_GRAVITY * delta
	var step := velocity * delta
	var vine := _vine_crossed(position, position + step)
	var hit := _ray(position, position + step + step.normalized() * RADIUS, velocity.y > 0.0)
	if not hit.is_empty() and hit.collider is BreakableWindow and velocity.length() > GRENADE_WINDOW_BREAK:
		(hit.collider as BreakableWindow).smash()  # trop vite : la fenêtre casse, la grenade continue
		hit = {}
	if not vine.is_empty() and (hit.is_empty() or position.distance_to(vine.point) < position.distance_to(hit.position)):
		position = vine.point
		stuck_vine = vine.vine
		stuck_on_vine = vine.distance
		_stick()
		return
	if hit.is_empty():
		position += step
		return
	_stuck_normal = hit.normal
	position = (hit.position as Vector2) + _stuck_normal * RADIUS
	body.rest_on(self, hit.collider)
	_stick()


func _stick() -> void:
	state = State.STUCK
	velocity = Vector2.ZERO


## Un coup la décolle (game.gd lui donne sa nouvelle vitesse).
func unstick() -> void:
	state = State.FLYING
	stuck_vine = null
	body.launch()


## Grenade collée : elle suit ce sur quoi elle est collée (plateforme qui bouge, liane qui se
## balance). S'il disparaît (fenêtre cassée), elle retombe.
func _follow_sticky() -> void:
	if stuck_vine != null:
		if is_instance_valid(stuck_vine):
			position = stuck_vine.point_at(stuck_on_vine)
		else:
			unstick()
		return
	body.follow(self)
	if _ray(position, position - _stuck_normal * (RADIUS + 6.0), true).is_empty():
		unstick()


## La liane que la grenade traverse entre "from" et "to" (la plus proche) : {vine, point, distance},
## ou vide.
func _vine_crossed(from: Vector2, to: Vector2) -> Dictionary:
	var best := {}
	if from == to:
		return best
	for node in get_tree().get_nodes_in_group("lianes"):
		var vine := node as Vine
		var cross: Variant = Geometry2D.segment_intersects_segment(from, to, vine.global_position, vine.point_at(vine.length))
		if cross != null and (best.is_empty() or from.distance_to(cross) < from.distance_to(best.point)):
			best = {"vine": vine, "point": cross, "distance": vine.global_position.distance_to(cross)}
	return best


func _tick_knocked(delta: float) -> void:
	velocity = body.step(self, velocity, KNOCKED_RADIUS, delta)
	if body.resting:
		if state != State.STUCK:
			rotation = 0.0 if cos(rotation) >= 0.0 else PI  # au sol : elle se pose à plat
		state = State.STUCK
	else:
		state = State.DROPPED
		rotation += KNOCKED_SPIN * delta * (1.0 if velocity.x >= 0.0 else -1.0)


## Un coup (ou une explosion) l'envoie valdinguer, sans danger.
func launch(new_velocity: Vector2) -> void:
	velocity = new_velocity
	state = State.DROPPED
	tumbling = kind in ["lance", "fleche"]
	body.launch()
	hit_lock = Game.LOOSE_HIT_LOCK


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
## Elle retombe pointe devant (comme frappée par terre) : le rayon qui cherche le sol part de son
## milieu vers sa pointe, donc une lance qui retombait pointe en l'air passait à travers le sol.
func drop() -> void:
	state = State.DROPPED
	velocity = Vector2(-velocity.x * 0.15, -320.0)
	tumbling = true
	rotation = velocity.angle()


func net_state() -> Array:
	return [kind, owner_index, position, rotation, state, color, fuse, length, head]


func apply_net_state(data: Array) -> void:
	kind = data[0]
	owner_index = data[1]
	position = data[2]
	rotation = data[3]
	state = data[4]
	color = data[5]
	fuse = data[6] if data.size() > 6 else -1.0
	length = data[7] if data.size() > 7 else 16.0 if kind == "balle" else 18.0 if kind == "grenade" else SPEAR_LENGTH
	head = data[8] if data.size() > 8 else 0.0
	queue_redraw()


func _draw() -> void:
	match kind:
		"balle":
			draw_line(Vector2(-length / 2.0 - 24.0, 0.0), Vector2(-length / 2.0, 0.0), Color(color, 0.3), 2.0)
			draw_line(Vector2(-length / 2.0, 0.0), Vector2(length / 2.0, 0.0), color, 4.0)
		"grenade":
			# Clignote d'après la mèche (envoyée aux copains en ligne), pas d'après l'âge (qui n'est
			# compté que chez l'hôte : chez un copain, la grenade restait rouge sans clignoter).
			var blink := int(fuse / lerpf(0.05, 0.25, clampf(fuse / 3.0, 0.0, 1.0))) % 2 == 0
			draw_circle(Vector2.ZERO, 8.0, Color(1, 0.3, 0.2) if blink and fuse < 1.5 else color)
			draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, Color(1, 1, 1, 0.6), 1.5)
		"arme":
			# Comme dans la main : un manche, et un bout carré (tête du marteau, pointe...).
			var half := length / 2.0
			draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), color, 4.0)
			if head > 0.0:
				draw_rect(Rect2(Vector2(half, 0.0) - Vector2.ONE * head / 2.0, Vector2.ONE * head), color)
		_:
			var half := length / 2.0
			var alpha := 1.0 if state == State.FLYING else 0.85
			draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Color(color, alpha), 4.0)
			draw_colored_polygon(PackedVector2Array([Vector2(half + 8.0, 0.0), Vector2(half - 4.0, -6.0), Vector2(half - 4.0, 6.0)]),
				Color(color.lightened(0.4), alpha))
			if state == State.FLYING:
				draw_line(Vector2(-half - 30.0, 0.0), Vector2(-half, 0.0), Color(color, 0.25), 2.0)
