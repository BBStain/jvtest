class_name Fighter
extends CharacterBody2D
## Un combattant : une barre verticale qui court, saute, dashe et attaque.
##
## Le combattant ne lit pas la manette lui-même : à chaque frame, le jeu (game.gd)
## lui donne un InputState via physics_tick(). Les coups et les chocs d'attaques
## sont gérés par game.gd, qui voit tous les combattants à la fois.
##
## Les caractéristiques propres à chaque personnage (vitesse, sauts, dash, attaques, poids...)
## sont dans "stats" : un fichier .tres du dossier characters/ (voir character_stats.gd).
## Les constantes ci-dessous sont les règles communes à tous les personnages.

signal life_lost(fighter: Fighter)

const PLATFORM_LAYER := 3  ## numéro de la couche "plateformes_traversables"

# --- Déplacement ---
const COYOTE_TIME := 0.1                ## on peut encore sauter un instant après avoir quitté le bord
const JUMP_BUFFER := 0.12               ## un saut appuyé juste avant d'atterrir compte quand même
const DROP_THROUGH_TIME := 0.22         ## temps pendant lequel on traverse les plateformes après "bas"
const DROP_STICK := 0.3                 ## stick poussé vers le bas au-delà de ça (1 = tout en bas) : on descend

# --- Murs ---
const WALL_JUMP_LOCK := 0.1             ## petit temps où l'on contrôle moins bien après un saut mural
const WALL_JUMP_ACCEL := 2200.0

# --- Dash ---
const DASH_END_KEEP := 0.55             ## part de la vitesse gardée à la fin du dash

# --- Attaque légère (X) : un coup droit vers l'adversaire ---
const ATTACK_BUFFER := 0.12             ## X appuyé un peu trop tôt compte quand même
const CLASH_LOCKOUT := 0.08             ## petit temps mort après un contre (la recharge repart presque de zéro)
const LIGHT_DEPLOY_TIME := 0.06         ## le coup léger se déploie : la barre sort du perso et s'allonge pendant ce temps...
const LIGHT_DEPLOY_START := 0.3         ## ... en partant de 30 % de sa longueur

# --- Attaque lourde (Y) : un arc de cercle du dessus de la tête jusqu'aux pieds, devant soi ---
# On la charge en gardant Y appuyé : plus on charge, plus l'arme grandit et frappe loin.
# On frappe en lâchant Y (ou tout seul quand la charge est au maximum).
# Pendant la frappe, le perso est immobilisé.
const HEAVY_CHARGE_GROWTH := 2.0        ## à pleine charge, l'arme est 2 fois plus longue
const HEAVY_CHARGE_TIP_GROWTH := 1.5    ## à pleine charge, la zone qui touche est 1,5 fois plus grosse
const HEAVY_CHARGE_KNOCKBACK := 1.5     ## à pleine charge, on projette 1,5 fois plus fort
const HEAVY_ARC_START := -100.0         ## angle de départ en degrés (-90 = droit au-dessus de la tête)
const HEAVY_ARC_END := 32.0             ## angle d'arrivée (à hauteur des pieds, devant soi)
const HEAVY_COUNTERED_COOLDOWN := 1.0   ## attaque lourde contrée par une légère : celui qui l'a lancée ne frappe
                                        ## plus pendant 1 s ; celui qui contre peut refrapper tout de suite
const HEAVY_COUNTER_PUSH := 750.0       ## ... et les deux sont repoussés plus loin
const HEAVY_CLASH_PUSH := 1150.0        ## deux attaques lourdes qui se percutent : micro-explosion, éjectés fort
const HEAVY_CLASH_LIFT := 320.0         ## ... et un peu soulevés

# --- Blocage (B) : un bouclier qui craque peu à peu (ses points sont dans les stats du perso) ---
const SHIELD_REGEN_TIME := 2.0          ## 1 point regagné toutes les 2 s quand on ne bloque pas
const SHIELD_BREAK_COOLDOWN := 2.0      ## bouclier cassé : pas d'attaque pendant ce temps (on peut bouger)
const SHIELD_BREAK_PUSH := 1000.0       ## bouclier cassé : les deux joueurs sont éjectés...
const SHIELD_BREAK_LIFT := 300.0        ## ... et un peu soulevés
const HEAVY_SHIELD_DAMAGE := 2          ## l'attaque lourde compte pour 2 coups, la légère pour 1
const BLOCK_SPEED_MULT := 0.3           ## en bloquant, on se déplace beaucoup plus lentement
const BLOCK_JUMP_MULT := 0.7            ## en bloquant, on saute environ 2 fois moins haut
const SHIELD_HIT_PUSH := 380.0          ## l'attaquant qui frappe le bouclier est repoussé
const SHIELD_BLOCKER_PUSH := 120.0      ## celui qui bloque recule un tout petit peu
const PARRY_WINDOW := 0.15              ## blocage parfait : B appuyé au plus tant de secondes avant le coup...
const PARRY_COOLDOWN := 1.0             ## ... c'est un contre : celui qui frappait ne frappe plus pendant 1 s

# --- Effets de la jauge de contre (une seule pour toute la partie, voir counter_gauge.gd) ---
const PHASE_COOLDOWN := [1.0, 0.7, 0.45, 0.35]  ## recharge des attaques selon la phase (0,5 = 2 fois plus courte)
const PHASE_SHIELD_DAMAGE := [1, 2, 3, 3]       ## les coups abîment les boucliers 1, 2 ou 3 fois plus
const BERSERK_MOVE := 1.25              ## berserk : on court et on dashe 1,25 fois plus vite...
const BERSERK_JUMP := 1.12              ## ... on saute plus haut...
const BERSERK_ATTACK_SPEED := 1.4       ## ... les attaques partent et se chargent 1,4 fois plus vite...
const BERSERK_RANGE := 1.3              ## ... et vont 1,3 fois plus loin

# --- Course (LT / Shift, à maintenir) et endurance ---
const STAMINA_BLOCK_SPRINT_MULT := 2.33  ## en bloquant tout en courant, l'endurance part 2,33 fois plus vite
const STAMINA_REGEN_DELAY := 0.6        ## temps avant que l'endurance remonte
const STAMINA_RESTART := 25.0           ## jauge vide : il faut remonter jusque-là pour recourir
const STAMINA_SHOW_TIME := 1.0          ## la jauge reste affichée ce temps après être pleine

# --- Coup reçu ---
# Un premier coup sonne (pas de vie perdue). Sonné, le coup suivant retire une vie : pour s'en
# sortir, il faut contrer ou faire un blocage parfait (un blocage normal ne protège plus).
const STUN_TIME := 2.0                  ## durée pendant laquelle on reste sonné
const STUN_GRACE := 0.3                 ## juste après avoir été sonné, on ne peut pas être touché tout de suite
const INVINCIBLE_TIME := 1.2            ## après avoir perdu une vie ; doit rester plus long que la recharge de l'attaque légère
const CLASH_PUSH := 450.0
const KNOCKBACK_TIME := 0.2             ## durée pendant laquelle on contrôle moins bien après un coup / un choc
const KNOCKBACK_ACCEL := 2000.0

const START_LIVES := 3

## Jeu en ligne : ce que l'hôte envoie aux copains à chaque frame pour qu'ils dessinent ce joueur
## (voir net_state). Tout ce que _draw() utilise doit être dans cette liste.
const NET_VARS := [
	"position", "velocity", "facing", "lives", "eliminated", "visible",
	"_attack_time", "_attack_dir", "_attack_heavy", "_heavy_charging", "_charge_time", "_heavy_charge",
	"stamina", "_exhausted", "_sprinting", "_stamina_show_timer",
	"shield", "shield_broken", "_blocking", "_shield_broken_timer", "_shield_flash_timer",
	"_invincible_timer", "_lives_show_timer", "_blink_clock", "_dash_timer", "_dash_dir", "_wall_normal_x",
	"_stun_timer",
]
const LIVES_SHOW_TIME := 2.0            ## durée d'affichage des vies au-dessus de la tête

var stats: CharacterStats = CharacterStats.new()  ## le personnage joué (choisi par game.gd)
var player_index := 0
var color := Color.WHITE
var input_source: InputSource
var target: Fighter                     ## l'adversaire visé par l'attaque (choisi par game.gd)

var lives := START_LIVES
var max_lives := START_LIVES  ## vies au début de la partie (pour le dessin des vies)
var eliminated := false
var facing := 1.0                       ## 1 = regarde à droite, -1 = à gauche

var _air_jumps_left := 0
var _air_dashes_left := 0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _drop_timer := 0.0
var _wall_normal_x := 0.0               ## -1 / 1 quand on glisse contre un mur, 0 sinon
var _wall_jump_timer := 0.0
var _jump_rising := false              ## true = on monte grâce à un saut (pour le petit saut)

var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_dir := Vector2.RIGHT

var _attack_time := -1.0                ## temps écoulé depuis le début de l'attaque (-1 = pas d'attaque)
var _attack_dir := Vector2.RIGHT
var _attack_has_hit := false
var _attack_heavy := false              ## true = attaque lourde en cours
var _attack_cooldown_timer := 0.0
var _attack_buffer_timer := 0.0
var _aimed_dir := Vector2.ZERO   ## direction du coup visé en attente (stick droit), ou ZERO : visée auto
var _heavy_buffer_timer := 0.0          ## pareil pour Y : appuyé un peu trop tôt, il compte quand même
var _heavy_charging := false            ## true = on garde Y pour charger l'attaque lourde
var _charge_time := 0.0
var _heavy_charge := 0.0                ## 0 = pas chargée, 1 = charge pleine

var stamina := 0.0
var _sprinting := false
var _exhausted := false                 ## jauge vidée : on ne peut plus courir tant qu'elle n'est pas remontée
var _stamina_regen_timer := 0.0
var _stamina_show_timer := 0.0

var shield := 0
var shield_broken := false              ## cassé : plus de blocage jusqu'à la fin de la partie
var _cracks: Array[PackedVector2Array] = []  ## les fissures du bouclier, une par point perdu
var _blocking := false
var _block_hold_time := 0.0             ## depuis combien de temps B est appuyé (pour le blocage parfait)
var _shield_regen_timer := 0.0
var _shield_broken_timer := 0.0         ## pour l'effet visuel du bouclier cassé
var _shield_flash_timer := 0.0          ## petit éclat quand le bouclier encaisse un coup

var gauge := CounterGauge.new()         ## la jauge de contre de la partie (partagée, donnée par game.gd)

var _stun_timer := 0.0
var _invincible_timer := 0.0
var _knockback_timer := 0.0
var _lives_show_timer := 0.0
var _blink_clock := 0.0


## Le corps est créé à l'entrée dans la partie, une fois le personnage (stats) choisi.
func _ready() -> void:
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	stamina = stats.stamina_max
	shield = stats.shield_max
	_make_cracks()
	collision_layer = 0
	set_collision_layer_value(2, true)          # on est un "joueur"
	collision_mask = 0
	set_collision_mask_value(1, true)           # on touche le sol
	set_collision_mask_value(PLATFORM_LAYER, true)
	floor_snap_length = 6.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = stats.body_size
	shape.shape = rect
	add_child(shape)


## Appelé par game.gd une fois par frame physique.
func physics_tick(input: InputState, delta: float) -> void:
	_tick_timers(delta)
	if eliminated:
		return

	var on_floor := is_on_floor()
	if on_floor:
		_air_jumps_left = stats.air_jumps
		_air_dashes_left = stats.air_dashes
		_coyote_timer = COYOTE_TIME

	if input.stick.x != 0.0 and not is_attacking():
		facing = signf(input.stick.x)

	# Collé à un mur en l'air (en poussant vers lui) : on glisse, et sauts + dash sont rechargés.
	_wall_normal_x = 0.0
	if not on_floor and is_on_wall():
		var normal_x := get_wall_normal().x
		if absf(normal_x) > 0.5 and input.stick.x * normal_x < -0.3:
			_wall_normal_x = signf(normal_x)
			_air_jumps_left = stats.wall_jumps
			_air_dashes_left = stats.air_dashes
			_dash_cooldown_timer = 0.0
			facing = _wall_normal_x

	# Descendre d'une plateforme traversable avec "bas" (pas besoin d'aller tout en bas avec le stick).
	if on_floor and (input.down_pressed or input.stick.y > DROP_STICK):
		_drop_timer = DROP_THROUGH_TIME
	set_collision_mask_value(PLATFORM_LAYER, _drop_timer <= 0.0)

	_update_block(input, delta)
	_update_sprint(input, delta)

	if input.dash_pressed and not _blocking:
		_try_start_dash(input, on_floor)

	if is_dashing():
		_tick_dash(delta)
	elif is_heavy_swinging():
		velocity = Vector2.ZERO  # immobilisé pendant la frappe lourde
	else:
		_tick_movement(input, on_floor, delta)

	# X et Y sont gardés en mémoire un court instant : en martelant, le coup suivant part dès que
	# possible, et un Y appuyé juste avant la fin d'une recharge n'est pas perdu.
	if input.attack_pressed:
		_attack_buffer_timer = ATTACK_BUFFER
		_aimed_dir = Vector2.ZERO
	if input.aimed_attack_pressed and input.aim != Vector2.ZERO:
		_attack_buffer_timer = ATTACK_BUFFER
		_aimed_dir = input.aim.normalized()
	if input.heavy_pressed:
		_heavy_buffer_timer = ATTACK_BUFFER
	if not _blocking and can_attack():  # pas d'attaque en bloquant
		if _attack_buffer_timer > 0.0:
			_attack_buffer_timer = 0.0
			_heavy_buffer_timer = 0.0
			_try_start_attack(false)
		elif _heavy_buffer_timer > 0.0:
			_heavy_buffer_timer = 0.0
			_try_start_attack(true)
	_tick_attack(input, delta)

	move_and_slide()
	queue_redraw()


func _tick_timers(delta: float) -> void:
	_coyote_timer -= delta
	_jump_buffer_timer -= delta
	_drop_timer -= delta
	_dash_cooldown_timer -= delta
	_attack_cooldown_timer -= delta
	_attack_buffer_timer -= delta
	_heavy_buffer_timer -= delta
	_invincible_timer -= delta
	_knockback_timer -= delta
	_wall_jump_timer -= delta
	_lives_show_timer -= delta
	_shield_broken_timer -= delta
	_shield_flash_timer -= delta
	_stun_timer -= delta
	_blink_clock += delta


## On court tant que LT / Shift est maintenu et qu'il reste de l'endurance.
## Courir vide la jauge (plus vite si on bloque en même temps) ; elle remonte quand on s'arrête.
func _update_sprint(input: InputState, delta: float) -> void:
	if stamina >= STAMINA_RESTART:
		_exhausted = false
	var moving := absf(input.stick.x) > 0.2
	_sprinting = input.sprint_held and not _exhausted and stamina > 0.0 and (moving or _blocking)
	if _sprinting:
		stamina -= stats.stamina_sprint_drain * (STAMINA_BLOCK_SPRINT_MULT if _blocking else 1.0) * delta
		_stamina_regen_timer = STAMINA_REGEN_DELAY
		if stamina <= 0.0:
			stamina = 0.0
			_exhausted = true
	else:
		_stamina_regen_timer -= delta
		if _stamina_regen_timer <= 0.0:
			stamina = minf(stamina + stats.stamina_regen * delta, stats.stamina_max)
	if stamina < stats.stamina_max:
		_stamina_show_timer = STAMINA_SHOW_TIME
	else:
		_stamina_show_timer -= delta


## On bloque tant que B est maintenu, si le bouclier n'est pas cassé et qu'on n'est pas
## en train de dasher ou de frapper. Le bouclier se répare lentement quand on ne bloque pas.
func _update_block(input: InputState, delta: float) -> void:
	_blocking = input.block_held and not shield_broken and not is_dashing() \
		and not _is_attack_startup_or_active()
	# Compté depuis l'appui sur B, même si on ne pouvait pas encore bloquer (pendant une attaque,
	# un dash...) : garder B appuyé pendant sa propre attaque ne donne pas un blocage parfait gratuit.
	_block_hold_time = _block_hold_time + delta if input.block_held else 0.0
	if _blocking or shield_broken or shield >= stats.shield_max:
		_shield_regen_timer = 0.0
		return
	_shield_regen_timer += delta
	if _shield_regen_timer >= SHIELD_REGEN_TIME:
		_shield_regen_timer = 0.0
		shield += 1


func _tick_movement(input: InputState, on_floor: bool, delta: float) -> void:
	# Gauche / droite
	var accel := (stats.ground_accel if on_floor else stats.air_accel) * _move_mult()
	if _knockback_timer > 0.0:
		accel = KNOCKBACK_ACCEL
	elif _wall_jump_timer > 0.0:
		accel = WALL_JUMP_ACCEL
	var speed := stats.run_speed * _move_mult()
	if _sprinting:
		speed *= stats.sprint_speed_mult
	if _blocking:
		speed *= BLOCK_SPEED_MULT
	elif _heavy_charging:
		speed *= stats.heavy_charge_move_mult
	velocity.x = move_toward(velocity.x, input.stick.x * speed, accel * delta)

	# Gravité (plus forte si on a lâché le saut pendant la montée d'un saut = petit saut).
	# Seulement pour un saut : un dash vers le haut ou une projection ne sont pas coupés.
	if velocity.y >= 0.0:
		_jump_rising = false
	var gravity := stats.gravity
	if velocity.y < 0.0 and _jump_rising and not input.jump_held:
		gravity = stats.short_hop_gravity
	velocity.y += gravity * delta
	var max_fall := stats.fast_fall_speed if (input.stick.y > 0.5 and not on_floor) else stats.max_fall_speed
	if is_wall_sliding():
		max_fall = stats.wall_slide_speed
	velocity.y = minf(velocity.y, max_fall)

	# Saut, double saut et saut mural
	if input.jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
	var jump_mult := (BLOCK_JUMP_MULT if _blocking else 1.0) * (BERSERK_JUMP if is_berserk() else 1.0)
	if _jump_buffer_timer > 0.0:
		if on_floor or _coyote_timer > 0.0:
			velocity.y = -stats.jump_speed * jump_mult
			_jump_rising = true
			_jump_buffer_timer = 0.0
			_coyote_timer = 0.0
		elif input.jump_pressed and is_wall_sliding() and _air_jumps_left > 0:
			velocity = Vector2(_wall_normal_x * stats.wall_jump_push, -stats.jump_speed * jump_mult)
			_jump_rising = true
			_air_jumps_left -= 1
			_jump_buffer_timer = 0.0
			_wall_jump_timer = WALL_JUMP_LOCK
		elif input.jump_pressed and _air_jumps_left > 0:
			velocity.y = -stats.double_jump_speed * jump_mult
			_jump_rising = true
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
	_dash_timer = stats.dash_time
	_dash_cooldown_timer = stats.dash_cooldown
	_jump_rising = false
	_cancel_attack()


func _tick_dash(delta: float) -> void:
	velocity = _dash_dir * stats.dash_speed * _move_mult()
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		velocity *= DASH_END_KEEP


func _try_start_attack(heavy: bool) -> void:
	if not can_attack():
		return
	_aim_at_target()
	if not heavy and _aimed_dir != Vector2.ZERO:
		_aim_towards(_aimed_dir)  # coup visé au stick droit
	_aimed_dir = Vector2.ZERO
	_attack_heavy = heavy
	_attack_time = 0.0
	_attack_has_hit = false
	_heavy_charging = heavy
	_charge_time = 0.0
	_heavy_charge = 0.0
	_attack_cooldown_timer = _cooldown(heavy)


## Recharge d'une attaque (comptée depuis son départ) : plus courte quand la jauge de contre est haute.
func _cooldown(heavy: bool) -> float:
	return (stats.heavy_cooldown if heavy else stats.attack_cooldown) * PHASE_COOLDOWN[counter_phase() - 1]


## Se tourne vers l'adversaire visé.
func _aim_at_target() -> void:
	if target != null and not target.eliminated:
		var to_target := target.global_position - global_position
		_aim_towards(to_target.normalized() if to_target.length() > 1.0 else Vector2(facing, 0.0))
	else:
		_aim_towards(Vector2(facing, 0.0))


## Oriente l'attaque dans une direction (et le perso du même côté).
func _aim_towards(dir: Vector2) -> void:
	_attack_dir = dir
	if absf(_attack_dir.x) > 0.1:
		facing = signf(_attack_dir.x)


func _tick_attack(input: InputState, delta: float) -> void:
	if _attack_time < 0.0:
		return
	if _heavy_charging:
		# On charge tant que Y est gardé ; on frappe en le lâchant, ou quand la charge est pleine.
		_charge_time += delta * _attack_speed()
		_heavy_charge = clampf((_charge_time - stats.heavy_startup) / maxf(stats.heavy_charge_time - stats.heavy_startup, 0.001), 0.0, 1.0)
		if (_charge_time >= stats.heavy_startup and not input.heavy_held) or _charge_time >= stats.heavy_charge_time:
			_heavy_charging = false
			_aim_at_target()  # l'adversaire a pu bouger pendant la charge
			_attack_time = stats.heavy_startup
			_attack_cooldown_timer = _cooldown(true)
			velocity = Vector2.ZERO  # la frappe commence : on s'arrête net
		return
	_attack_time += delta * _attack_speed()
	if _attack_time >= _attack_startup() + _attack_active():
		_attack_time = -1.0


func _attack_startup() -> float:
	return stats.heavy_startup if _attack_heavy else stats.attack_startup


func _attack_active() -> float:
	return stats.heavy_active if _attack_heavy else stats.attack_active


## Angle actuel de l'arme pendant l'attaque lourde (en radians, côté "facing").
func _heavy_angle() -> float:
	var progress := clampf((_attack_time - stats.heavy_startup) / maxf(stats.heavy_active, 0.001), 0.0, 1.0)
	return deg_to_rad(lerpf(HEAVY_ARC_START, HEAVY_ARC_END, progress))


## Position du bout de l'arme (par rapport au centre du perso) pour un angle donné.
func _heavy_tip(angle: float) -> Vector2:
	return Vector2(facing * cos(angle), sin(angle)) * stats.heavy_arc_radius * heavy_scale() * _range_mult()


## Taille de l'arme lourde : 1 sans charge, HEAVY_CHARGE_GROWTH à pleine charge.
func heavy_scale() -> float:
	return lerpf(1.0, HEAVY_CHARGE_GROWTH, _heavy_charge)


func _cancel_attack() -> void:
	_attack_time = -1.0
	_heavy_charging = false


# --- Questions que game.gd pose au combattant ---

func is_dashing() -> bool:
	return _dash_timer > 0.0


func is_wall_sliding() -> bool:
	return _wall_normal_x != 0.0


func is_invincible() -> bool:
	return _invincible_timer > 0.0


func is_attacking() -> bool:
	return _attack_time >= 0.0


func is_charging_heavy() -> bool:
	return _heavy_charging


## En train de donner le coup lourd (après la charge) : le perso est immobilisé.
func is_heavy_swinging() -> bool:
	return _attack_heavy and _attack_time >= 0.0 and not _heavy_charging


func _is_attack_startup_or_active() -> bool:
	return _attack_time >= 0.0 and (_heavy_charging or _attack_time < _attack_startup() + _attack_active())


func is_sprinting() -> bool:
	return _sprinting


func is_blocking() -> bool:
	return _blocking


## Blocage parfait : on vient tout juste de commencer à bloquer.
func is_parrying() -> bool:
	return _blocking and _block_hold_time <= PARRY_WINDOW


## Une attaque légère lancée qui n'a encore touché personne (en préparation ou en train de frapper).
## Se faire toucher à ce moment-là par celui qu'elle vise, c'est le contrer (voir game.gd).
func is_light_attack_under_way() -> bool:
	return not _attack_heavy and _attack_time >= 0.0 and not _attack_has_hit \
		and _attack_time < stats.attack_startup + stats.attack_active


## Temps restant avant de pouvoir attaquer à nouveau.
func attack_cooldown_left() -> float:
	return maxf(_attack_cooldown_timer, 0.0)


func can_attack() -> bool:
	return not eliminated and not is_dashing() and not is_invincible() and not _blocking \
		and not is_attacking() and _attack_cooldown_timer <= 0.0


## Le coup peut-il toucher en ce moment ?
func is_attack_active() -> bool:
	return not _heavy_charging and _attack_time >= _attack_startup() and _attack_time < _attack_startup() + _attack_active() \
		and not _attack_has_hit


func is_heavy_attack() -> bool:
	return _attack_heavy


## La zone qui touche est un segment épais (de attack_start() à attack_center(), d'épaisseur attack_radius()).
## Attaque légère : toute la barre, du centre du perso jusqu'au bout, comme un coup de poing ou
## d'épée, donc on touche aussi un adversaire tout proche. Le segment commence une épaisseur devant
## le centre : la zone s'arrête pile au centre du perso et ne déborde pas dans son dos.
## Attaque lourde : seulement le bout de l'arme.
func attack_start() -> Vector2:
	if _attack_heavy:
		return attack_center()
	return global_position + _attack_dir * clampf(_light_reach() - stats.attack_radius, 0.0, stats.attack_radius)


## Le bout de la zone qui touche.
func attack_center() -> Vector2:
	if _attack_heavy:
		return global_position + _heavy_tip(_heavy_angle())
	return global_position + _attack_dir * maxf(_light_reach() - stats.attack_radius, 0.0)


## Longueur actuelle du coup léger : la barre sort du perso et s'allonge pendant LIGHT_DEPLOY_TIME.
func _light_reach() -> float:
	var deploy := clampf((_attack_time - stats.attack_startup) / LIGHT_DEPLOY_TIME, 0.0, 1.0)
	return stats.attack_reach * _range_mult() * lerpf(LIGHT_DEPLOY_START, 1.0, deploy)


func attack_radius() -> float:
	return stats.heavy_tip_radius * lerpf(1.0, HEAVY_CHARGE_TIP_GROWTH, _heavy_charge) if _attack_heavy else stats.attack_radius


func attack_knockback() -> float:
	return stats.heavy_knockback * lerpf(1.0, HEAVY_CHARGE_KNOCKBACK, _heavy_charge) if _attack_heavy else stats.hit_knockback


func attack_direction() -> Vector2:
	return _attack_dir


## Peut-on se faire toucher ? Non pendant un dash ou une invincibilité.
func can_be_hit() -> bool:
	return not eliminated and not is_dashing() and not is_invincible()


func body_rect() -> Rect2:
	return Rect2(global_position - stats.body_size / 2.0, stats.body_size)


# --- Événements déclenchés par game.gd ---

func mark_attack_hit() -> void:
	_attack_has_hit = true


## Un contre : notre attaque est annulée (s'il y en avait une), on est repoussé par "push"
## (game.gd la calcule : plus l'autre est lourd, plus elle est forte) et on ne peut plus
## attaquer pendant "cooldown".
func clash(push: Vector2, cooldown := CLASH_LOCKOUT, lift := 150.0) -> void:
	_cancel_attack()
	_attack_cooldown_timer = cooldown
	velocity = _pushed(push) + Vector2(0.0, -lift)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME


## Notre coup a frappé un bouclier : il s'arrête, on est repoussé, mais on peut refrapper tout de suite.
func hit_shield(push_dir: Vector2) -> void:
	_cancel_attack()
	_attack_cooldown_timer = 0.0
	velocity = _pushed(push_dir * SHIELD_HIT_PUSH) + Vector2(0.0, -120.0)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME


## Points de bouclier que nos coups font perdre : plus quand notre jauge de contre est haute.
func shield_damage(heavy: bool) -> int:
	return (HEAVY_SHIELD_DAMAGE if heavy else 1) * PHASE_SHIELD_DAMAGE[counter_phase() - 1]


## Notre bouclier encaisse un coup (il craque de "damage" points). Renvoie true s'il vient de casser.
func absorb_hit(push_dir: Vector2, damage: int) -> bool:
	shield = maxi(shield - damage, 0)
	_shield_regen_timer = 0.0
	_shield_flash_timer = 0.12
	velocity.x = _pushed(push_dir * SHIELD_BLOCKER_PUSH).x
	if shield > 0:
		return false
	# Bouclier cassé pour le reste de la partie.
	shield_broken = true
	_blocking = false
	return true


## Un bouclier vient de casser : on est éjecté. Celui dont le bouclier a cassé ne peut plus
## attaquer pendant SHIELD_BREAK_COOLDOWN (mais peut bouger).
func shield_burst(push_dir: Vector2, own_shield_broke: bool) -> void:
	_cancel_attack()
	velocity = _pushed(push_dir * SHIELD_BREAK_PUSH) + Vector2(0.0, -SHIELD_BREAK_LIFT)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME
	if own_shield_broke:
		_attack_cooldown_timer = SHIELD_BREAK_COOLDOWN
		_shield_broken_timer = SHIELD_BREAK_COOLDOWN
	else:
		_attack_cooldown_timer = 0.0


## Un coup reçu. Pas encore sonné : on est sonné, sans perdre de vie. Déjà sonné : on perd une vie.
## Renvoie true si une vie est perdue.
## knockback = force du coup reçu (-1 = celle d'une attaque légère). Plus on est lourd, moins on recule.
func take_hit(hit_dir: Vector2, knockback := -1.0) -> bool:
	if knockback < 0.0:
		knockback = stats.hit_knockback
	_cancel_attack()
	_dash_timer = 0.0
	velocity = _pushed(hit_dir * knockback) + Vector2(0.0, -200.0)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME
	if is_stunned():
		_lose_life()
		return true
	_stun_timer = STUN_TIME
	_invincible_timer = STUN_GRACE
	return false


func is_stunned() -> bool:
	return _stun_timer > 0.0


## On a contré (ou fait un blocage parfait) : on n'est plus sonné.
func recover() -> void:
	_stun_timer = 0.0


## Phase de la jauge de contre de la partie : de 1 (normale) à 4 (berserk).
func counter_phase() -> int:
	return gauge.phase()


func is_berserk() -> bool:
	return gauge.is_berserk()


func _move_mult() -> float:
	return BERSERK_MOVE if is_berserk() else 1.0


func _attack_speed() -> float:
	return BERSERK_ATTACK_SPEED if is_berserk() else 1.0


func _range_mult() -> float:
	return BERSERK_RANGE if is_berserk() else 1.0


## Toutes les poussées reçues (coups, chocs, bouclier) passent par ici : plus le perso est lourd,
## moins il est repoussé (poids 2 = 2 fois moins loin).
func _pushed(force: Vector2) -> Vector2:
	return force / maxf(stats.mass(), 0.1)  # jamais de division par zéro, même avec un réglage bizarre


## Sorti de la map : on perd une vie et on réapparaît au milieu.
func fall_out(respawn_position: Vector2) -> void:
	_cancel_attack()
	_dash_timer = 0.0
	global_position = respawn_position
	velocity = Vector2.ZERO
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	# On repart à neuf : plus de recul ni de saut en cours venant d'avant la chute.
	_knockback_timer = 0.0
	_wall_jump_timer = 0.0
	_drop_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_rising = false
	_lose_life()


func _lose_life() -> void:
	lives -= 1
	_stun_timer = 0.0
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


## Jeu en ligne : le joueur a quitté la partie, il est éliminé.
func forfeit() -> void:
	if eliminated:
		return
	lives = 1
	_lose_life()


## Jeu en ligne (hôte) : l'état de ce joueur à envoyer aux copains.
func net_state() -> Array:
	var state := []
	for v in NET_VARS:
		state.append(get(v))
	return state


## Jeu en ligne (copain) : on affiche le joueur tel que l'hôte l'a envoyé.
func apply_net_state(state: Array) -> void:
	for i in mini(state.size(), NET_VARS.size()):
		set(NET_VARS[i], state[i])
	queue_redraw()


# --- Dessin (pas d'images : tout est dessiné avec des rectangles) ---

func _draw() -> void:
	if eliminated:
		return
	var body := Rect2(-stats.body_size / 2.0, stats.body_size)

	# Traînée pendant le dash
	if is_dashing():
		for i in 3:
			var ghost := body
			ghost.position -= _dash_dir * 18.0 * (i + 1)
			draw_rect(ghost, Color(color, 0.25 - i * 0.07))

	# Berserk : des images rouges traînent derrière le perso quand il bouge
	var phase := counter_phase()
	if phase == 4 and not is_dashing() and velocity.length() > 150.0:
		for i in 3:
			var ghost := body
			ghost.position -= velocity * 0.022 * (i + 1)
			draw_rect(ghost, Color(gauge.color(), 0.22 - i * 0.06))

	# Clignote quand on est invincible
	var body_color := color
	if is_invincible() and int(_blink_clock / 0.06) % 2 == 0:
		body_color = Color(color, 0.25)
	if is_dashing():
		body_color = body_color.lightened(0.4)
	draw_rect(body, body_color)

	# Jauge de contre en phase 2 et plus : un contour de la couleur de la phase (rouge qui pulse en berserk)
	if phase >= 2:
		var phase_color := gauge.color()
		var pulse := 0.5 + 0.5 * sin(_blink_clock * 14.0) if phase == 4 else 0.0
		draw_rect(body.grow(3.0 + 2.0 * pulse), Color(phase_color, 0.55 + 0.35 * pulse), false, 1.5 + phase * 0.5)
	if gauge.flash_timer > 0.0:
		var t := 1.0 - gauge.flash_timer / CounterGauge.FLASH_TIME
		var ring := lerpf(stats.body_size.y * 0.5, stats.body_size.y * 1.3, t)
		draw_arc(Vector2.ZERO, ring, 0.0, TAU, 32, Color(gauge.color(), 1.0 - t), 4.0)

	# Sonné : des étoiles tournent au-dessus de la tête
	if is_stunned():
		var fade := clampf(_stun_timer / 0.3, 0.0, 1.0)
		for i in 3:
			var angle := _blink_clock * 6.0 + i * TAU / 3.0
			var star := Vector2(cos(angle) * 18.0, -stats.body_size.y / 2.0 - 10.0 + sin(angle) * 5.0)
			var star_color := Color(1.0, 0.9, 0.3, fade * (0.6 + 0.4 * (sin(angle) * 0.5 + 0.5)))
			draw_line(star + Vector2(-6, 0), star + Vector2(6, 0), star_color, 3.0)
			draw_line(star + Vector2(0, -6), star + Vector2(0, 6), star_color, 3.0)

	# En surbrillance quand on bloque : plus le bouclier a pris de coups, plus il est fissuré et terne
	if _blocking:
		var damage := 1.0 - float(shield) / stats.shield_max
		var glow := (1.0 if _shield_flash_timer > 0.0 else 0.8) * lerpf(1.0, 0.6, damage)
		draw_rect(body.grow(12.0), Color(color.lightened(0.5), 0.12 * glow))
		draw_rect(body.grow(7.0), Color(color.lightened(0.6), 0.25 * glow))
		draw_rect(body, Color(1, 1, 1, 0.35 * glow))
		draw_rect(body.grow(7.0), Color(1, 1, 1, glow), false, 3.0)
		for i in mini(stats.shield_max - shield, _cracks.size()):
			draw_polyline(_cracks[i], Color(0.1, 0.1, 0.15, 0.9), 2.0)
	elif _shield_flash_timer > 0.0:
		draw_rect(body.grow(5.0), Color(1, 1, 1, 0.8), false, 3.0)

	# Bouclier cassé : une croix grise tant qu'on ne peut pas attaquer
	if _shield_broken_timer > 0.0:
		var a := clampf(_shield_broken_timer / 0.3, 0.0, 1.0) * 0.8
		var c := Vector2(0, -stats.body_size.y / 2.0 - 16.0)
		draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), Color(0.75, 0.75, 0.8, a), 3.0)
		draw_line(c + Vector2(-7, 7), c + Vector2(7, -7), Color(0.75, 0.75, 0.8, a), 3.0)

	# Petit œil pour voir de quel côté on regarde
	draw_rect(Rect2(Vector2(facing * 3.0 - 2.5, -stats.body_size.y / 2.0 + 9.0), Vector2(5, 5)), Color(0.08, 0.09, 0.13))

	# L'attaque lourde : l'arme levée au-dessus de la tête, puis un arc jusqu'aux pieds
	if is_attacking() and _attack_heavy:
		var angle := _heavy_angle()
		if _attack_time >= stats.heavy_startup:
			var trail := PackedVector2Array()
			var start := deg_to_rad(HEAVY_ARC_START)
			for i in 9:
				trail.append(_heavy_tip(lerpf(start, angle, i / 8.0)))
			draw_polyline(trail, Color(color.lightened(0.5), 0.5), 10.0)
		var tip := _heavy_tip(angle)
		var weapon_scale := heavy_scale()
		var blade_color := Color(1, 1, 1, 0.95)
		if _heavy_charging:
			blade_color = Color(1, 1, 1, lerpf(0.55, 0.9, _heavy_charge))
			# La charge : un halo qui grossit au bout de l'arme, qui clignote quand c'est plein
			var halo := attack_radius()
			var full_blink := _heavy_charge >= 1.0 or (_heavy_charge > 0.95 and int(_blink_clock / 0.05) % 2 == 0)
			draw_circle(tip, halo, Color(color.lightened(0.5), 0.15 + 0.25 * _heavy_charge))
			if full_blink:
				draw_arc(tip, halo, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
		var blade := stats.heavy_tip_radius * 0.375 * sqrt(weapon_scale)  # 9 px pour la Barre
		draw_line(tip * 0.2, tip, blade_color, blade)
		draw_circle(tip, blade, color.lightened(0.6))

	# L'attaque légère : une barre blanche orientée vers l'adversaire
	# (sa longueur et son épaisseur suivent la zone qui touche, pour chaque perso)
	elif is_attacking():
		draw_set_transform(Vector2.ZERO, _attack_dir.angle())
		var length := stats.attack_reach * _range_mult()
		var bar := stats.attack_radius * 0.5625   # 9 px pour la Barre
		var tip := stats.attack_radius * 0.875    # 14 px pour la Barre
		if _attack_time < stats.attack_startup:
			# On arme le coup : le poing recule derrière le perso, et une fine ligne montre où il va partir
			var windup := clampf(_attack_time / stats.attack_startup, 0.0, 1.0)
			draw_rect(Rect2(10.0, -1.5, length - 10.0, 3.0), Color(1, 1, 1, 0.12 + 0.2 * windup))
			var back := lerpf(2.0, 14.0, windup)
			draw_rect(Rect2(-back - tip, -tip * 0.8, tip, tip * 1.6), Color(color.lightened(0.6), 0.6 + 0.4 * windup))
		else:
			# Le coup part : la barre jaillit du perso et s'allonge jusqu'au bout
			var reach := _light_reach()
			draw_rect(Rect2(10.0, -bar, maxf(reach - 10.0, 0.0), bar * 2.0), Color(1, 1, 1, 0.95))
			draw_rect(Rect2(reach - tip, -tip, tip, tip * 2.0), color.lightened(0.6))
			if reach < length:
				draw_rect(Rect2(reach, -1.5, length - reach, 3.0), Color(1, 1, 1, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0)

	# La jauge d'endurance, sur le côté opposé à l'adversaire
	if _stamina_show_timer > 0.0:
		_draw_stamina_gauge()

	# Les vies au-dessus de la tête (plus haut si la croix du bouclier cassé est affichée)
	if _lives_show_timer > 0.0:
		var alpha := clampf(_lives_show_timer / 0.4, 0.0, 1.0)
		var size := 10.0
		var gap := 5.0
		var total := max_lives * size + (max_lives - 1) * gap
		var y := -stats.body_size.y / 2.0 - (32.0 if _shield_broken_timer > 0.0 else 22.0)
		for i in max_lives:
			var pip := Rect2(-total / 2.0 + i * (size + gap), y, size, size)
			if i < lives:
				draw_rect(pip, Color(color, alpha))
			else:
				draw_rect(pip, Color(1, 1, 1, 0.5 * alpha), false, 2.0)


## Prépare les fissures du bouclier : chacune part du bord de la surbrillance vers le perso
## en zigzag. Elles sont tirées au hasard une fois pour toutes (toujours les mêmes pour un joueur).
func _make_cracks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + player_index
	var outline := Rect2(-stats.body_size / 2.0, stats.body_size).grow(7.0)
	var perimeter := 2.0 * (outline.size.x + outline.size.y)
	for i in stats.shield_max:
		# Un point sur le bord, réparti tout autour
		var d := fposmod((i * 0.618034 + rng.randf_range(-0.05, 0.05)) * perimeter, perimeter)
		var start: Vector2
		if d < outline.size.x:
			start = outline.position + Vector2(d, 0.0)
		elif d < outline.size.x + outline.size.y:
			start = outline.position + Vector2(outline.size.x, d - outline.size.x)
		elif d < 2.0 * outline.size.x + outline.size.y:
			start = outline.end - Vector2(d - outline.size.x - outline.size.y, 0.0)
		else:
			start = outline.position + Vector2(0.0, outline.size.y - (d - 2.0 * outline.size.x - outline.size.y))
		var crack := PackedVector2Array([start])
		var dir := (-start).normalized()
		var point := start
		for step in 3:
			dir = dir.rotated(rng.randf_range(-0.9, 0.9))
			point += dir * rng.randf_range(5.0, 10.0)
			crack.append(point)
		_cracks.append(crack)


## Barre verticale à côté du perso, du côté où n'est pas l'adversaire (pour ne pas gêner le combat).
func _draw_stamina_gauge() -> void:
	var side := -facing
	if target != null and not target.eliminated and absf(target.global_position.x - global_position.x) > 1.0:
		side = -signf(target.global_position.x - global_position.x)
	var alpha := clampf(_stamina_show_timer / 0.3, 0.0, 1.0)
	var height := stats.body_size.y
	var x := side * (stats.body_size.x / 2.0 + 9.0) - 3.0
	var frame := Rect2(x, -height / 2.0, 6.0, height)
	draw_rect(frame, Color(0, 0, 0, 0.5 * alpha))
	var ratio := stamina / stats.stamina_max
	var fill_color := Color(0.4, 0.95, 0.5).lerp(Color(1.0, 0.85, 0.3), 1.0 - ratio)
	if _exhausted:
		fill_color = Color(0.6, 0.6, 0.65)
	var fill_h := height * ratio
	draw_rect(Rect2(x, height / 2.0 - fill_h, 6.0, fill_h), Color(fill_color, alpha))
	draw_rect(frame, Color(1, 1, 1, 0.4 * alpha), false, 1.0)
