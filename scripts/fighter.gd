class_name Fighter
extends CharacterBody2D
## Un combattant : une barre verticale qui court, saute, dashe et attaque.
##
## Le combattant ne lit pas la manette lui-même : à chaque frame, le jeu (game.gd)
## lui donne un InputState via physics_tick(). Les coups et les chocs d'attaques
## sont gérés par game.gd, qui voit tous les combattants à la fois.
##
## Tous les réglages du "ressenti" sont les constantes ci-dessous : change un chiffre,
## relance le jeu (F5) et teste !

signal life_lost(fighter: Fighter)

const PLATFORM_LAYER := 3  ## numéro de la couche "plateformes_traversables"

# --- Corps ---
const BODY_SIZE := Vector2(20, 60)      ## largeur, hauteur de la barre (en pixels)

# --- Déplacement ---
const RUN_SPEED := 460.0                ## vitesse de course max
const GROUND_ACCEL := 5000.0            ## à quelle vitesse on atteint la vitesse max au sol
const AIR_ACCEL := 3000.0               ## pareil, en l'air
const GRAVITY := 2600.0
const SHORT_HOP_GRAVITY := 5200.0       ## gravité quand on lâche le saut tôt (petit saut)
const MAX_FALL_SPEED := 1000.0
const FAST_FALL_SPEED := 1500.0         ## chute rapide en tenant bas
const JUMP_SPEED := 850.0
const DOUBLE_JUMP_SPEED := 780.0
const AIR_JUMPS := 1                    ## 1 = double saut
const COYOTE_TIME := 0.08               ## on peut encore sauter un instant après avoir quitté le bord
const JUMP_BUFFER := 0.1                ## un saut appuyé juste avant d'atterrir compte quand même
const DROP_THROUGH_TIME := 0.22         ## temps pendant lequel on traverse les plateformes après "bas"

# --- Murs ---
const WALL_SLIDE_SPEED := 160.0         ## vitesse de glissade le long d'un mur (en tenant vers le mur)
const WALL_JUMPS := 2                   ## sauts rendus quand on touche un mur (saut mural + 1 en l'air)
const WALL_JUMP_PUSH := 480.0           ## force qui éjecte du mur quand on saute
const WALL_JUMP_LOCK := 0.12            ## petit temps où l'on contrôle moins bien après un saut mural
const WALL_JUMP_ACCEL := 1200.0

# --- Dash ---
const DASH_SPEED := 1150.0
const DASH_TIME := 0.14
const DASH_COOLDOWN := 0.45             ## temps de recharge
const DASH_END_KEEP := 0.4              ## part de la vitesse gardée à la fin du dash
const AIR_DASHES := 1                   ## dashs possibles en l'air avant de retoucher le sol

# --- Attaque légère (X) : un coup droit vers l'adversaire ---
const ATTACK_STARTUP := 0.04            ## délai avant que le coup touche
const ATTACK_ACTIVE := 0.10             ## durée pendant laquelle le coup peut toucher
const ATTACK_COOLDOWN := 0.30           ## temps de recharge entre deux attaques
const ATTACK_REACH := 48.0              ## distance entre le centre du perso et le centre du coup
const ATTACK_RADIUS := 26.0             ## taille de la zone qui touche
const CLASH_LOCKOUT := 0.08             ## petit temps mort après un choc d'attaques

# --- Attaque lourde (Y) : un arc de cercle du dessus de la tête jusqu'aux pieds, devant soi ---
const HEAVY_STARTUP := 0.18             ## on lève l'arme avant de frapper
const HEAVY_ACTIVE := 0.18              ## durée du balayage
const HEAVY_COOLDOWN := 0.65
const HEAVY_ARC_RADIUS := 56.0          ## distance entre le centre du perso et le bout de l'arme
const HEAVY_TIP_RADIUS := 24.0          ## taille de la zone qui touche au bout de l'arme
const HEAVY_ARC_START := -100.0         ## angle de départ en degrés (-90 = droit au-dessus de la tête)
const HEAVY_ARC_END := 32.0             ## angle d'arrivée (à hauteur des pieds, devant soi)
const HEAVY_KNOCKBACK := 650.0
const COUNTER_COOLDOWN_MULT := 2.0      ## contrer une attaque lourde avec une légère : recharge x2

# --- Coup reçu ---
const INVINCIBLE_TIME := 0.55           ## doit rester plus long que ATTACK_COOLDOWN
const HIT_KNOCKBACK := 420.0
const CLASH_PUSH := 450.0
const KNOCKBACK_TIME := 0.15            ## durée pendant laquelle on contrôle moins bien après un coup / un choc
const KNOCKBACK_ACCEL := 1500.0

const START_LIVES := 3
const LIVES_SHOW_TIME := 2.0            ## durée d'affichage des vies au-dessus de la tête

var player_index := 0
var color := Color.WHITE
var input_source: InputSource
var target: Fighter                     ## l'adversaire visé par l'attaque (choisi par game.gd)

var lives := START_LIVES
var eliminated := false
var facing := 1.0                       ## 1 = regarde à droite, -1 = à gauche

var _air_jumps_left := AIR_JUMPS
var _air_dashes_left := AIR_DASHES
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _drop_timer := 0.0
var _wall_normal_x := 0.0               ## -1 / 1 quand on glisse contre un mur, 0 sinon
var _wall_jump_timer := 0.0

var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_dir := Vector2.RIGHT

var _attack_time := -1.0                ## temps écoulé depuis le début de l'attaque (-1 = pas d'attaque)
var _attack_dir := Vector2.RIGHT
var _attack_has_hit := false
var _attack_heavy := false              ## true = attaque lourde en cours
var _attack_cooldown_timer := 0.0

var _invincible_timer := 0.0
var _knockback_timer := 0.0
var _lives_show_timer := 0.0
var _blink_clock := 0.0


func _init() -> void:
	collision_layer = 0
	set_collision_layer_value(2, true)          # on est un "joueur"
	collision_mask = 0
	set_collision_mask_value(1, true)           # on touche le sol
	set_collision_mask_value(PLATFORM_LAYER, true)
	floor_snap_length = 6.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY_SIZE
	shape.shape = rect
	add_child(shape)


## Appelé par game.gd une fois par frame physique.
func physics_tick(input: InputState, delta: float) -> void:
	_tick_timers(delta)
	if eliminated:
		return

	var on_floor := is_on_floor()
	if on_floor:
		_air_jumps_left = AIR_JUMPS
		_air_dashes_left = AIR_DASHES
		_coyote_timer = COYOTE_TIME

	if input.stick.x != 0.0 and not is_attacking():
		facing = signf(input.stick.x)

	# Collé à un mur en l'air (en poussant vers lui) : on glisse, et sauts + dash sont rechargés.
	_wall_normal_x = 0.0
	if not on_floor and is_on_wall():
		var normal_x := get_wall_normal().x
		if absf(normal_x) > 0.5 and input.stick.x * normal_x < -0.3:
			_wall_normal_x = signf(normal_x)
			_air_jumps_left = WALL_JUMPS
			_air_dashes_left = AIR_DASHES
			_dash_cooldown_timer = 0.0
			facing = _wall_normal_x

	# Descendre d'une plateforme traversable avec "bas".
	if input.down_pressed and on_floor:
		_drop_timer = DROP_THROUGH_TIME
	set_collision_mask_value(PLATFORM_LAYER, _drop_timer <= 0.0)

	if input.dash_pressed:
		_try_start_dash(input, on_floor)

	if is_dashing():
		_tick_dash(delta)
	else:
		_tick_movement(input, on_floor, delta)

	if input.attack_pressed:
		_try_start_attack(false)
	elif input.heavy_pressed:
		_try_start_attack(true)
	_tick_attack(delta)

	move_and_slide()
	queue_redraw()


func _tick_timers(delta: float) -> void:
	_coyote_timer -= delta
	_jump_buffer_timer -= delta
	_drop_timer -= delta
	_dash_cooldown_timer -= delta
	_attack_cooldown_timer -= delta
	_invincible_timer -= delta
	_knockback_timer -= delta
	_wall_jump_timer -= delta
	_lives_show_timer -= delta
	_blink_clock += delta


func _tick_movement(input: InputState, on_floor: bool, delta: float) -> void:
	# Gauche / droite
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	if _knockback_timer > 0.0:
		accel = KNOCKBACK_ACCEL
	elif _wall_jump_timer > 0.0:
		accel = WALL_JUMP_ACCEL
	velocity.x = move_toward(velocity.x, input.stick.x * RUN_SPEED, accel * delta)

	# Gravité (plus forte si on a lâché le saut pendant la montée = petit saut)
	var gravity := GRAVITY
	if velocity.y < 0.0 and not input.jump_held:
		gravity = SHORT_HOP_GRAVITY
	velocity.y += gravity * delta
	var max_fall := FAST_FALL_SPEED if (input.stick.y > 0.5 and not on_floor) else MAX_FALL_SPEED
	if is_wall_sliding():
		max_fall = WALL_SLIDE_SPEED
	velocity.y = minf(velocity.y, max_fall)

	# Saut, double saut et saut mural
	if input.jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
	if _jump_buffer_timer > 0.0:
		if on_floor or _coyote_timer > 0.0:
			velocity.y = -JUMP_SPEED
			_jump_buffer_timer = 0.0
			_coyote_timer = 0.0
		elif input.jump_pressed and is_wall_sliding() and _air_jumps_left > 0:
			velocity = Vector2(_wall_normal_x * WALL_JUMP_PUSH, -JUMP_SPEED)
			_air_jumps_left -= 1
			_jump_buffer_timer = 0.0
			_wall_jump_timer = WALL_JUMP_LOCK
		elif input.jump_pressed and _air_jumps_left > 0:
			velocity.y = -DOUBLE_JUMP_SPEED
			_air_jumps_left -= 1
			_jump_buffer_timer = 0.0


func _try_start_dash(input: InputState, on_floor: bool) -> void:
	if is_dashing() or _dash_cooldown_timer > 0.0:
		return
	if _is_attack_startup_or_active():
		return
	if not on_floor and _air_dashes_left <= 0:
		return
	var dir := input.stick
	if dir.length() < 0.3:
		dir = Vector2(facing, 0.0)
	_dash_dir = dir.normalized()
	if not on_floor:
		_air_dashes_left -= 1
	_dash_timer = DASH_TIME
	_dash_cooldown_timer = DASH_COOLDOWN
	_cancel_attack()


func _tick_dash(delta: float) -> void:
	velocity = _dash_dir * DASH_SPEED
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		velocity *= DASH_END_KEEP


func _try_start_attack(heavy: bool) -> void:
	if not can_attack():
		return
	if target != null and not target.eliminated:
		var to_target := target.global_position - global_position
		_attack_dir = to_target.normalized() if to_target.length() > 1.0 else Vector2(facing, 0.0)
	else:
		_attack_dir = Vector2(facing, 0.0)
	if absf(_attack_dir.x) > 0.1:
		facing = signf(_attack_dir.x)
	_attack_heavy = heavy
	_attack_time = 0.0
	_attack_has_hit = false
	_attack_cooldown_timer = HEAVY_COOLDOWN if heavy else ATTACK_COOLDOWN


func _tick_attack(delta: float) -> void:
	if _attack_time < 0.0:
		return
	_attack_time += delta
	if _attack_time >= _attack_startup() + _attack_active():
		_attack_time = -1.0


func _attack_startup() -> float:
	return HEAVY_STARTUP if _attack_heavy else ATTACK_STARTUP


func _attack_active() -> float:
	return HEAVY_ACTIVE if _attack_heavy else ATTACK_ACTIVE


## Angle actuel de l'arme pendant l'attaque lourde (en radians, côté "facing").
func _heavy_angle() -> float:
	var progress := clampf((_attack_time - HEAVY_STARTUP) / HEAVY_ACTIVE, 0.0, 1.0)
	return deg_to_rad(lerpf(HEAVY_ARC_START, HEAVY_ARC_END, progress))


## Position du bout de l'arme (par rapport au centre du perso) pour un angle donné.
func _heavy_tip(angle: float) -> Vector2:
	return Vector2(facing * cos(angle), sin(angle)) * HEAVY_ARC_RADIUS


func _cancel_attack() -> void:
	_attack_time = -1.0


# --- Questions que game.gd pose au combattant ---

func is_dashing() -> bool:
	return _dash_timer > 0.0


func is_wall_sliding() -> bool:
	return _wall_normal_x != 0.0


func is_invincible() -> bool:
	return _invincible_timer > 0.0


func is_attacking() -> bool:
	return _attack_time >= 0.0


func _is_attack_startup_or_active() -> bool:
	return _attack_time >= 0.0 and _attack_time < _attack_startup() + _attack_active()


func can_attack() -> bool:
	return not eliminated and not is_dashing() and not is_invincible() \
		and not is_attacking() and _attack_cooldown_timer <= 0.0


## Le coup peut-il toucher en ce moment ?
func is_attack_active() -> bool:
	return _attack_time >= _attack_startup() and _attack_time < _attack_startup() + _attack_active() \
		and not _attack_has_hit


func is_heavy_attack() -> bool:
	return _attack_heavy


## Centre de la zone qui touche : devant soi pour l'attaque légère, au bout de l'arme pour la lourde.
func attack_center() -> Vector2:
	if _attack_heavy:
		return global_position + _heavy_tip(_heavy_angle())
	return global_position + _attack_dir * ATTACK_REACH


func attack_radius() -> float:
	return HEAVY_TIP_RADIUS if _attack_heavy else ATTACK_RADIUS


func attack_knockback() -> float:
	return HEAVY_KNOCKBACK if _attack_heavy else HIT_KNOCKBACK


func attack_direction() -> Vector2:
	return _attack_dir


## Peut-on se faire toucher ? Non pendant un dash ou une invincibilité.
func can_be_hit() -> bool:
	return not eliminated and not is_dashing() and not is_invincible()


func body_rect() -> Rect2:
	return Rect2(global_position - BODY_SIZE / 2.0, BODY_SIZE)


# --- Événements déclenchés par game.gd ---

func mark_attack_hit() -> void:
	_attack_has_hit = true


## Deux attaques se sont touchées : elles s'annulent et on est repoussé.
## countered_heavy = on a contré une attaque lourde avec une légère : recharge doublée.
func clash(push_dir: Vector2, countered_heavy := false) -> void:
	_cancel_attack()
	_attack_cooldown_timer = ATTACK_COOLDOWN * COUNTER_COOLDOWN_MULT if countered_heavy else CLASH_LOCKOUT
	velocity = push_dir * CLASH_PUSH + Vector2(0.0, -150.0)
	_knockback_timer = KNOCKBACK_TIME


func take_hit(hit_dir: Vector2, knockback := HIT_KNOCKBACK) -> void:
	_cancel_attack()
	_dash_timer = 0.0
	velocity = hit_dir * knockback + Vector2(0.0, -200.0)
	_knockback_timer = KNOCKBACK_TIME
	_lose_life()


## Sorti de la map : on perd une vie et on réapparaît au milieu.
func fall_out(respawn_position: Vector2) -> void:
	_cancel_attack()
	_dash_timer = 0.0
	global_position = respawn_position
	velocity = Vector2.ZERO
	_air_jumps_left = AIR_JUMPS
	_air_dashes_left = AIR_DASHES
	_lose_life()


func _lose_life() -> void:
	lives -= 1
	_invincible_timer = INVINCIBLE_TIME
	show_lives()
	if lives <= 0:
		eliminated = true
		visible = false
		set_collision_mask_value(1, false)
		set_collision_mask_value(PLATFORM_LAYER, false)
		velocity = Vector2.ZERO
	life_lost.emit(self)


func show_lives() -> void:
	_lives_show_timer = LIVES_SHOW_TIME
	queue_redraw()


# --- Dessin (pas d'images : tout est dessiné avec des rectangles) ---

func _draw() -> void:
	if eliminated:
		return
	var body := Rect2(-BODY_SIZE / 2.0, BODY_SIZE)

	# Traînée pendant le dash
	if is_dashing():
		for i in 3:
			var ghost := body
			ghost.position -= _dash_dir * 18.0 * (i + 1)
			draw_rect(ghost, Color(color, 0.25 - i * 0.07))

	# Clignote quand on est invincible
	var body_color := color
	if is_invincible() and int(_blink_clock / 0.06) % 2 == 0:
		body_color = Color(color, 0.25)
	if is_dashing():
		body_color = body_color.lightened(0.4)
	draw_rect(body, body_color)

	# Petit œil pour voir de quel côté on regarde
	draw_rect(Rect2(Vector2(facing * 3.0 - 2.5, -BODY_SIZE.y / 2.0 + 9.0), Vector2(5, 5)), Color(0.08, 0.09, 0.13))

	# L'attaque lourde : l'arme levée au-dessus de la tête, puis un arc jusqu'aux pieds
	if is_attacking() and _attack_heavy:
		var angle := _heavy_angle()
		if _attack_time >= HEAVY_STARTUP:
			var trail := PackedVector2Array()
			var start := deg_to_rad(HEAVY_ARC_START)
			for i in 9:
				trail.append(_heavy_tip(lerpf(start, angle, i / 8.0)))
			draw_polyline(trail, Color(color.lightened(0.5), 0.5), 10.0)
		var tip := _heavy_tip(angle)
		var blade_color := Color(1, 1, 1, 0.95) if _attack_time >= HEAVY_STARTUP else Color(1, 1, 1, 0.6)
		draw_line(tip * 0.2, tip, blade_color, 9.0)
		draw_circle(tip, 9.0, color.lightened(0.6))

	# L'attaque légère : une barre blanche orientée vers l'adversaire
	elif is_attacking():
		draw_set_transform(Vector2.ZERO, _attack_dir.angle())
		var length := ATTACK_REACH + ATTACK_RADIUS
		if _attack_time < ATTACK_STARTUP:
			draw_rect(Rect2(10.0, -2.0, length * 0.5, 4.0), Color(1, 1, 1, 0.5))
		else:
			draw_rect(Rect2(10.0, -9.0, length - 10.0, 18.0), Color(1, 1, 1, 0.95))
			draw_rect(Rect2(length - 14.0, -14.0, 14.0, 28.0), color.lightened(0.6))
		draw_set_transform(Vector2.ZERO, 0.0)

	# Les vies au-dessus de la tête
	if _lives_show_timer > 0.0:
		var alpha := clampf(_lives_show_timer / 0.4, 0.0, 1.0)
		var size := 10.0
		var gap := 5.0
		var total := START_LIVES * size + (START_LIVES - 1) * gap
		var y := -BODY_SIZE.y / 2.0 - 22.0
		for i in START_LIVES:
			var pip := Rect2(-total / 2.0 + i * (size + gap), y, size, size)
			if i < lives:
				draw_rect(pip, Color(color, alpha))
			else:
				draw_rect(pip, Color(1, 1, 1, 0.5 * alpha), false, 2.0)
