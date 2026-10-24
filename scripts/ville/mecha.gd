class_name Mecha
extends CharacterBody2D
## Un mecha de la Ville : on l'appelle, on le pilote, il tire, il s'use et il explose.
##
## Il arrive avec une balise d'appel (objet ramassé, RT) : un viseur rouge marque le sol, puis il
## tombe du ciel et fait une onde de choc en se posant (game.gd l'applique, voir landed).
## Ensuite n'importe qui peut monter dedans : se coller à lui et pousser le stick vers le haut.
## Le pilote le dirige avec ses touches habituelles (voir tick) :
##   stick gauche : marcher, diriger le vol      A : sauter, garder appuyé en l'air = voler
##   LT : turbo (plus vite, brûle du carburant)    LB : dash (casse les blocs qu'il percute)
##   bas + A gardés 0,5 s : sortir (le mecha reste là, vide)
##   X : fusil d'assaut, une rafale de 3 balles (visée auto, ou stick droit)
##   Y : lance-roquette, garder pour charger (plus loin, plus fort), lâcher pour tirer
## Il s'use : WEAR_MAX points de solidité, les coups et les tirs en enlèvent (voir game.gd), on le voit
## aux fissures. À 0 il explose (signal destroyed) : le pilote est éjecté et sonné, sans perdre de vie.
## Gros et lourd, mais vif : il démarre et s'arrête vite, il ne traverse jamais les planchers.
## La position du nœud est entre les deux pieds, au sol (comme MechaVisual).

signal landed(mecha: Mecha)             ## il vient de se poser (après l'appel) : onde de choc
## Il tire (game.gd crée ce qui vole) : kind "balle" ou "roquette", power = charge de la roquette (0 à 1).
signal fired(mecha: Mecha, kind: String, origin: Vector2, direction: Vector2, power: float)
signal destroyed(mecha: Mecha)          ## plus de solidité : il explose (game.gd éjecte le pilote)

enum State { CALLED, FALLING, READY }

const BODY := Vector2(170, 300)         ## le corps qui touche le décor (le dessin dépasse un peu)
const CALL_TIME := 1.5                  ## balise activée : il se pose 1,5 s plus tard...
const SHOCKWAVE_RADIUS := MechaVisual.SHOCKWAVE_RADIUS  ## ... avec une onde de choc de 300 px
const WALK_SPEED := 620.0
const FLY_SPEED := 760.0                ## vitesse sur le côté en l'air
const TURBO_MULT := 1.6                 ## LT : 1,6 fois plus vite
const GROUND_ACCEL := 5200.0            ## vif : il démarre et s'arrête vite au sol...
const AIR_ACCEL := 2600.0
const GRAVITY := 2600.0                 ## ... mais lourd : il retombe vite
const MAX_FALL := 1700.0
const JUMP_SPEED := 1050.0
const RISE_SPEED := 760.0               ## A gardé en l'air : il monte à cette vitesse...
const RISE_STICK := 0.7                 ## ... plus vite stick en haut, moins vite stick en bas
const THRUST_ACCEL := 3800.0
const FUEL_MAX := 12.0                  ## 12 s de vol
const FUEL_GROUND_REFILL := FUEL_MAX / 3.0  ## plein en 3 s au sol...
const FUEL_AIR_REFILL := 0.6            ## ... un peu en l'air, quand on ne pousse pas
const FUEL_RESTART := 1.0               ## réservoir vidé : il faut en avoir au moins ça pour revoler
const TURBO_BURN := 1.0                 ## le turbo brûle 1 s de carburant par seconde (en vol : 2 fois plus vite)
const DASH_SPEED := 1800.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 0.6
const DASH_END_KEEP := 0.4
const DASH_BLOCK_DAMAGE := 3            ## un dash qui percute un bloc de la ville l'abîme (2 dashs le cassent)
const EXIT_STICK := 0.6                 ## sortir : stick vers le bas au-delà de ça...
const EXIT_TIME := 0.5                  ## ... et A gardés ce temps
const EMPTY_COLOR := Color(0.55, 0.57, 0.62)  ## un mecha vide est gris
const FUEL_SHOW_TIME := 1.0             ## la jauge de carburant reste affichée ce temps après être pleine
const WEAR_MAX := 40                    ## solidité d'un mecha neuf
const HIT_FLASH_TIME := 0.1             ## touché : il blanchit un instant
const BURST_SHOTS := 3                  ## X : une rafale de 3 balles...
const BURST_GAP := 0.07                 ## ... une toutes les 0,07 s...
const BURST_COOLDOWN := 0.45            ## ... et une nouvelle rafale au plus toutes les 0,45 s
const ROCKET_FULL_CHARGE := 1.0         ## Y gardé 1 s : roquette chargée au maximum (elle part toute seule)
const ROCKET_COOLDOWN := 0.8
const GUN_MOUNT := Vector2(94.0, -125.0)  ## la mitrailleuse sous le nez (x vers l'avant) : d'où partent les balles...
const GUN_LENGTH := 99.0
const TURRET_PIVOT := Vector2(0.0, -270.0)  ## ... et la tourelle sur le dos, d'où partent les roquettes
const TURRET_LENGTH := 182.0
const AIM_UP_MAX := 1.3                 ## les armes visent jusqu'à presque droit au-dessus...
const AIM_DOWN_MAX := 1.0               ## ... et assez bas devant soi

var state := State.CALLED
var caller: Fighter                     ## celui qui l'a appelé (l'onde de choc l'épargne)
var pilot: Fighter                      ## qui est dedans (null = vide)
var facing := 1.0
var fuel := FUEL_MAX
var heavy_weapon := "roquette"
var visual := MechaVisual.new()
var _state_time := 0.0
var _dash_timer := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector2.RIGHT
var _exit_hold := 0.0
var _empty_tank := false
var _fuel_show_timer := 0.0
var _thrusting := false
var hp := WEAR_MAX                      ## solidité qui reste
var hit_by := {}                        ## les attaques qui l'ont déjà touché (une fois par attaque, voir game.gd)
var _hit_flash := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _burst_dir := Vector2.RIGHT
var _gun_cooldown := 0.0
var _rocket_cooldown := 0.0
var _charge := -1.0                     ## Y gardé depuis ce temps (-1 = pas de charge)
var _barrel := 0


func _ready() -> void:
	add_to_group("mechas")
	collision_layer = 0
	collision_mask = 0
	set_collision_mask_value(1, true)                     # le sol, les murs, les blocs
	set_collision_mask_value(Fighter.PLATFORM_LAYER, true)  # les planchers (il ne les traverse jamais)
	floor_snap_length = 8.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY
	shape.shape = rect
	shape.position = Vector2(0.0, -BODY.y / 2.0)
	shape.disabled = true  # pas de corps tant qu'il n'est pas posé
	shape.name = "Corps"
	add_child(shape)
	visual.hover = false
	visual.piloted = false
	visual.color = EMPTY_COLOR
	visual.heavy_weapon = heavy_weapon
	visual.visible = false  # au début, seul le viseur rouge est là
	add_child(visual)


## Appelé par game.gd à chaque frame. input : les touches du pilote (rien s'il est vide).
func tick(input: InputState, delta: float) -> void:
	_state_time += delta
	match state:
		State.CALLED:
			if _state_time >= CALL_TIME - MechaVisual.LAND_TIME:
				state = State.FALLING
				visual.visible = true
				visual.set_pose(MechaVisual.Pose.LAND)
			queue_redraw()
			return
		State.FALLING:
			if _state_time >= CALL_TIME:
				state = State.READY
				($Corps as CollisionShape2D).set_deferred("disabled", false)
				landed.emit(self)
			queue_redraw()
			return
	if pilot == null:
		input = InputState.new()
	var on_floor := is_on_floor()
	_dash_timer -= delta
	_dash_cooldown -= delta
	var exiting := input.stick.y > EXIT_STICK and input.jump_held
	_exit_hold = _exit_hold + delta if exiting and pilot != null else 0.0
	if input.stick.x != 0.0 and _dash_timer <= 0.0:
		facing = signf(input.stick.x)
	if _empty_tank and fuel >= FUEL_RESTART:
		_empty_tank = false
	var has_fuel := fuel > 0.0 and not _empty_tank
	var turbo := input.sprint_held and has_fuel and absf(input.stick.x) > 0.2
	_thrusting = false

	if input.dash_pressed and _dash_cooldown <= 0.0:
		_dash_dir = input.stick.normalized() if input.stick.length() >= 0.3 else Vector2(facing, 0.0)
		_dash_timer = DASH_TIME
		_dash_cooldown = DASH_COOLDOWN
	if _dash_timer > 0.0:
		velocity = _dash_dir * DASH_SPEED
		if _dash_timer <= delta:
			velocity *= DASH_END_KEEP
	else:
		var speed := (WALK_SPEED if on_floor else FLY_SPEED) * (TURBO_MULT if turbo else 1.0)
		velocity.x = move_toward(velocity.x, input.stick.x * speed, (GROUND_ACCEL if on_floor else AIR_ACCEL) * delta)
		if on_floor and input.jump_pressed and not exiting:
			velocity.y = -JUMP_SPEED
		elif not on_floor and input.jump_held and not exiting and has_fuel:
			_thrusting = true
			var rise := RISE_SPEED * (1.0 - input.stick.y * RISE_STICK)
			velocity.y = move_toward(velocity.y, -rise, THRUST_ACCEL * delta)
		else:
			velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	# Carburant : le vol et le turbo en brûlent ; il revient vite au sol, un peu en l'air
	var burn := (1.0 if _thrusting else 0.0) + (TURBO_BURN if turbo else 0.0) * (2.0 if _thrusting else 1.0)
	if burn > 0.0:
		fuel = maxf(fuel - burn * delta, 0.0)
		if fuel <= 0.0:
			_empty_tank = true
	elif on_floor:
		fuel = minf(fuel + FUEL_GROUND_REFILL * delta, FUEL_MAX)
	else:
		fuel = minf(fuel + FUEL_AIR_REFILL * delta, FUEL_MAX)
	_fuel_show_timer = FUEL_SHOW_TIME if fuel < FUEL_MAX else _fuel_show_timer - delta

	_tick_weapons(input, delta)
	_move()
	_update_visual(on_floor)
	queue_redraw()


## X : rafale de 3 balles ; Y : roquette chargée. Elles partent vers l'adversaire visé par le pilote
## (ou là où pointe le stick droit), et le mecha se tourne de ce côté.
func _tick_weapons(input: InputState, delta: float) -> void:
	_gun_cooldown -= delta
	_rocket_cooldown -= delta
	_burst_timer -= delta
	_hit_flash -= delta
	if pilot == null:
		_burst_left = 0
		_charge = -1.0
		visual.turret_charge = -1.0
		return
	var flick := input.aimed_attack_pressed and input.aim != Vector2.ZERO
	if (input.attack_pressed or flick) and _gun_cooldown <= 0.0:
		_burst_left = BURST_SHOTS
		_burst_timer = 0.0
		_burst_dir = input.aim.normalized() if flick else aim_direction(GUN_MOUNT)
		_gun_cooldown = BURST_COOLDOWN
	if _burst_left > 0 and _burst_timer <= 0.0:
		_burst_left -= 1
		_burst_timer = BURST_GAP
		_face(_burst_dir)
		fired.emit(self, "balle", gun_muzzle(_burst_dir), _burst_dir, 0.0)
		visual.gun_shot_time = 0.0
	if input.heavy_pressed and _rocket_cooldown <= 0.0 and _charge < 0.0:
		_charge = 0.0
	if _charge >= 0.0:
		_charge += delta
		if not input.heavy_held or _charge >= ROCKET_FULL_CHARGE:
			var dir := aim_direction(TURRET_PIVOT)
			_face(dir)
			fired.emit(self, "roquette", turret_muzzle(dir), dir, clampf(_charge / ROCKET_FULL_CHARGE, 0.0, 1.0))
			_charge = -1.0
			_rocket_cooldown = ROCKET_COOLDOWN
			visual.turret_barrel = _barrel
			visual.turret_shot_time = 0.0
			_barrel = (_barrel + 1) % MechaVisual.BARRELS
	visual.turret_charge = clampf(_charge / ROCKET_FULL_CHARGE, 0.0, 1.0) if _charge >= 0.0 else -1.0


## Vers l'adversaire visé par le pilote (depuis cette arme), sinon droit devant.
func aim_direction(mount: Vector2) -> Vector2:
	var from := global_position + Vector2(mount.x * facing, mount.y)
	if pilot != null and pilot.target != null and not pilot.target.eliminated:
		var to_target := pilot.target.global_position - from
		if to_target.length() > 1.0:
			return to_target.normalized()
	return Vector2(facing, 0.0)


func _face(dir: Vector2) -> void:
	if absf(dir.x) > 0.05:
		facing = signf(dir.x)


## Le bout du canon de la mitrailleuse (et de la tourelle) quand l'arme vise dans cette direction.
func gun_muzzle(dir: Vector2) -> Vector2:
	return global_position + Vector2(GUN_MOUNT.x * facing, GUN_MOUNT.y) + dir * GUN_LENGTH


func turret_muzzle(dir: Vector2) -> Vector2:
	return global_position + TURRET_PIVOT + dir * TURRET_LENGTH


## Un coup ou un tir l'abîme. Plus de solidité : il explose (game.gd fait le reste).
func damage(amount: int) -> void:
	if state != State.READY or hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	visual.wear = 1.0 - float(hp) / WEAR_MAX
	_hit_flash = HIT_FLASH_TIME
	if hp <= 0:
		destroyed.emit(self)


func is_destroyed() -> bool:
	return hp <= 0


func _move() -> void:
	var dashing := _dash_timer > 0.0
	var before := velocity
	move_and_slide()
	if not dashing:
		return
	# Un dash percute le décor : il abîme les blocs de la ville (et casse les fenêtres) et continue sur sa lancée
	for i in get_slide_collision_count():
		var block := get_slide_collision(i).get_collider() as BreakableWindow
		if block == null:
			continue
		if block is CityBlock:
			(block as CityBlock).hit(DASH_BLOCK_DAMAGE)
		else:
			block.smash()
		if block.broken:
			velocity = before


func _update_visual(on_floor: bool) -> void:
	visual.facing = facing
	if visual.pose == MechaVisual.Pose.LAND and visual.pose_time < MechaVisual.LAND_TIME + MechaVisual.SHOCKWAVE_TIME:
		return  # on laisse finir l'onde de choc de l'arrivée
	var pose := MechaVisual.Pose.IDLE
	if not on_floor:
		pose = MechaVisual.Pose.FLY
	elif absf(velocity.x) > 60.0:
		pose = MechaVisual.Pose.WALK
	if visual.pose != pose:
		visual.set_pose(pose)
	visual.flames = _thrusting or _dash_timer > 0.0
	# Les armes suivent l'adversaire visé (comme la visée auto)
	var dir := _burst_dir if _burst_left > 0 else aim_direction(TURRET_PIVOT)
	if dir.x * facing < 0.0:
		dir.x = 0.0  # il est derrière : les armes pointent vers le haut ou le bas, sans se retourner
	visual.aim = clampf(atan2(dir.y, absf(dir.x)), -AIM_UP_MAX, AIM_DOWN_MAX)
	visual.modulate = Color(2.0, 2.0, 2.0) if _hit_flash > 0.0 else Color.WHITE


## Le pilote monte (game.gd vérifie qu'il le touche et qu'il pousse vers le haut).
func board(fighter: Fighter) -> void:
	pilot = fighter
	_exit_hold = 0.0
	visual.color = fighter.color
	visual.stats = fighter.stats
	visual.piloted = true


## Le pilote sort (ou est sorti) : le mecha reste là, vide, gris.
func leave() -> void:
	pilot = null
	_exit_hold = 0.0
	visual.color = EMPTY_COLOR
	visual.piloted = false


func is_ready() -> bool:
	return state == State.READY


## Le pilote a gardé bas + A assez longtemps : il veut sortir.
func wants_exit() -> bool:
	return _exit_hold >= EXIT_TIME


func is_dashing() -> bool:
	return _dash_timer > 0.0


func is_flying() -> bool:
	return _thrusting


## Le corps du mecha dans la map.
func body_rect() -> Rect2:
	return Rect2(global_position - Vector2(BODY.x / 2.0, BODY.y), BODY)


## Où est le pilote (dans le cockpit).
func cockpit() -> Vector2:
	return global_position + Vector2(0.0, -BODY.y * 0.62)


func _draw() -> void:
	if state != State.READY:
		_draw_target()
		return
	# Sortie en cours : un anneau qui se remplit au-dessus du mecha
	if _exit_hold > 0.0:
		var center := Vector2(0.0, -BODY.y - 70.0)
		draw_arc(center, 26.0, -PI / 2.0, -PI / 2.0 + TAU * minf(_exit_hold / EXIT_TIME, 1.0), 32, Color(1, 1, 1, 0.9), 6.0)
	# La jauge de carburant, sous les pieds, quand elle n'est pas pleine
	if pilot != null and _fuel_show_timer > 0.0:
		var bar := Rect2(Vector2(-60.0, 14.0), Vector2(120.0, 10.0))
		draw_rect(bar, Color(0, 0, 0, 0.5))
		var fill := Color(1.0, 0.35, 0.25) if _empty_tank else Color(1.0, 0.7, 0.2)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fuel / FUEL_MAX, bar.size.y)), fill)


## Le viseur rouge qui marque le sol avant l'arrivée : il clignote de plus en plus vite.
func _draw_target() -> void:
	var k := clampf(_state_time / CALL_TIME, 0.0, 1.0)
	var blink := 0.55 + 0.45 * sin(_state_time * lerpf(8.0, 30.0, k))
	var red := Color(1.0, 0.2, 0.2, blink)
	var r := lerpf(150.0, 90.0, k)
	draw_arc(Vector2.ZERO, r, PI, TAU, 32, red, 6.0)
	draw_line(Vector2(-r - 30.0, -3.0), Vector2(r + 30.0, -3.0), red, 6.0)
	draw_line(Vector2(0.0, -r - 30.0), Vector2(0.0, 0.0), red, 6.0)
	draw_rect(Rect2(Vector2(-BODY.x / 2.0, -10.0), Vector2(BODY.x, 10.0)), Color(1.0, 0.2, 0.2, 0.3 * blink))
