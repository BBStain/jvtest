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
signal weapon_thrown(fighter: Fighter, direction: Vector2, speed: float)  ## lance : game.gd crée la lance qui vole
## Un objet utilisé (balle tirée, grenade lancée ou lâchée) : game.gd crée ce qui vole.
## power : 0 à 1 (distance de la grenade) ; fuse : temps restant avant que la grenade explose.
signal item_used(fighter: Fighter, kind: String, direction: Vector2, power: float, fuse: float)

const PLATFORM_LAYER := 3  ## numéro de la couche "plateformes_traversables"

# --- Déplacement ---
const COYOTE_TIME := 0.1                ## on peut encore sauter un instant après avoir quitté le bord
const JUMP_BUFFER := 0.12               ## un saut appuyé juste avant d'atterrir compte quand même
const DROP_THROUGH_TIME := 0.22         ## temps pendant lequel on traverse les plateformes après "bas"
const DROP_STICK := 0.3                 ## stick poussé vers le bas au-delà de ça (1 = tout en bas) : on descend

# --- Murs ---
const WALL_JUMP_LOCK := 0.1             ## petit temps où l'on contrôle moins bien après un saut mural
const WALL_JUMP_ACCEL := 2200.0

# --- Échelle (voir ladder.gd) ---
const LADDER_GRAB_STICK := 0.5          ## stick poussé vers le haut au-delà de ça : on s'accroche à l'échelle
const LADDER_CLIMB_SPEED := 1500.0      ## on monte très vite, tout seul
const LADDER_REGRAB_TIME := 0.35        ## après avoir lâché l'échelle, on ne se raccroche pas tout de suite
const LADDER_FLING_TIME := 0.25         ## éjecté en haut de l'échelle : on garde son élan sur le côté ce temps

# --- Liane (voir vine.gd) : on s'y balance comme un pendule ---
const VINE_GRAB_MARGIN := 14.0          ## on attrape la liane à cette distance du corps
const VINE_REGRAB_TIME := 0.3           ## après avoir lâché une liane, on ne se raccroche pas tout de suite
const VINE_MIN_LENGTH := 60.0           ## on ne se tient jamais plus près que ça du point d'accroche
const VINE_PUMP := 1500.0               ## élan pris avec gauche / droite
const VINE_DAMPING := 0.2               ## le balancement ralentit un peu tout seul
const VINE_MAX_SPEED := 1200.0          ## vitesse max en se balançant
const VINE_MAX_ANGLE := 1.75            ## on monte au plus un peu au-dessus de l'horizontale (en radians, 1,57 = horizontal)
const VINE_JUMP_BOOST := 0.4            ## en sautant de la liane : petit saut en plus de l'élan (part du double saut)
const VINE_FLING_TIME := 0.3            ## après avoir lâché la liane, on garde son élan ce temps

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

# --- Armes (voir weapon_stats.gd) ---
const KATANA_DASH_END_KEEP := 0.4       ## fin du dash du katana : part de la vitesse gardée
const KATANA_DASH_REACH := 0.8          ## la lame dépasse du perso de 0,8 fois la longueur de l'arme
const SLAM_WAVE_TIME := 0.12            ## marteau : durée de l'onde de choc après l'arc
const SLAM_WAVE_REACH := 150.0          ## ... jusqu'où elle va de chaque côté (x1,6 à pleine charge)
const SLAM_WAVE_RADIUS := 14.0          ## ... sa hauteur (de chaque côté du sol)
const SPEAR_MAX_COUNTERS := 3          ## lance lancée contrée 3 fois : cassée jusqu'à la prochaine vie perdue
const SPEAR_SHORTEN := 0.2              ## chaque contre raccourcit la lance de 20 % (100 %, 80 %, 60 %)
const THROW_CHARGE_SPEED := 1.5         ## lance / dash du katana : à pleine charge, 1,5 fois plus vite

# --- Objets ramassés sur la map (un seul à la fois, utilisé avec RT ; voir item_pickup.gd) ---
const PISTOL_AMMO := 5                  ## balles du pistolet (une par appui)
const PISTOL_COOLDOWN := 0.18           ## temps minimum entre deux balles
const GRENADE_FUSE := 3.0               ## la grenade explose 3 s après avoir été dégoupillée (RT appuyé)
const GRENADE_FULL_HOLD := 1.0          ## RT gardé ce temps : la grenade part le plus loin possible
const ITEM_SHIELD_TIME := 5.0           ## le bouclier ramassé reste levé 5 s
const ITEM_SHIELD_PUSH := 1300.0        ## qui frappe le bouclier ramassé est projeté très loin...
const ITEM_SHIELD_COOLDOWN := 0.5       ## ... et ne peut plus frapper un instant

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
	"_stun_timer", "_block_hold_time", "weapon_away", "spear_counters",
	"item", "item_ammo", "_grenade_fuse", "_grenade_hold", "item_shield_timer",
	"_swinging", "_swing_anchor",
]
const LIVES_SHOW_TIME := 2.0            ## durée d'affichage des vies au-dessus de la tête

var stats: CharacterStats = CharacterStats.new()  ## le personnage joué, avec son arme en main (choisi par game.gd)
var weapon: WeaponStats = WeaponStats.new()       ## l'arme choisie (choisie par game.gd ; mains nues par défaut)
## Lance lancée et pas encore ramassée : on se bat à mains nues en attendant.
var weapon_away := false:
	set(value):
		weapon_away = value
		if _armed_stats != null:
			stats = _bare_stats if value else _armed_stats
## Lance : combien de fois sa lance lancée a été contrée. Chaque contre la raccourcit ;
## au bout de SPEAR_MAX_COUNTERS elle est cassée : mains nues jusqu'à la prochaine vie perdue,
## où une lance neuve revient.
var spear_counters := 0:
	set(value):
		spear_counters = value
		if _armed_stats != null:
			_update_armed_stats()
			stats = _bare_stats if weapon_away else _armed_stats
var _bare_stats: CharacterStats                   ## le perso sans arme
var _armed_stats: CharacterStats                  ## le perso avec son arme
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
var _ladder: Ladder = null              ## l'échelle sur laquelle on grimpe (null = pas d'échelle)
var _ladder_regrab_timer := 0.0
var _ladder_fling_timer := 0.0          ## éjecté (échelle) ou lâché d'une liane : on garde son élan
var _vine: Vine = null                  ## la liane à laquelle on se balance (null = pas de liane)
var _swinging := false                  ## pareil, envoyé aux copains en ligne (pour dessiner la liane)
var _swing_anchor := Vector2.ZERO       ## le point d'accroche de la liane
var _swing_length := 0.0
var _swing_angle := 0.0                 ## 0 = droit sous le point d'accroche
var _swing_speed := 0.0                 ## vitesse de rotation (radians par seconde)
var _vine_regrab_timer := 0.0

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

var item := ""                          ## l'objet ramassé : "", "pistolet", "grenade" ou "bouclier"
var item_ammo := 0                      ## balles qui restent dans le pistolet
var item_shield_timer := 0.0            ## bouclier ramassé levé encore ce temps
var _item_cooldown := 0.0
var _grenade_fuse := -1.0               ## grenade dégoupillée en main : temps avant l'explosion (-1 = non)
var _grenade_hold := 0.0                ## depuis combien de temps RT est gardé (distance du lancer)

var gauge := CounterGauge.new()         ## la jauge de contre de la partie (partagée, donnée par game.gd)

var _stun_timer := 0.0
var _invincible_timer := 0.0
var _knockback_timer := 0.0
var _lives_show_timer := 0.0
var _blink_clock := 0.0


## Le corps est créé à l'entrée dans la partie, une fois le personnage (stats) choisi.
func _ready() -> void:
	add_to_group("combattants")
	_bare_stats = stats
	_update_armed_stats()
	stats = _bare_stats if weapon_away else _armed_stats
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

	# Échelle : "haut" en la touchant pour s'accrocher ; on monte tout seul (rien d'autre à faire).
	if _ladder == null and _ladder_regrab_timer <= 0.0 and input.stick.y < -LADDER_GRAB_STICK \
			and not is_heavy_swinging():
		_ladder = _touched_ladder()
		if _ladder != null:
			_cancel_attack()
			_dash_timer = 0.0
			_air_jumps_left = stats.air_jumps
			_air_dashes_left = stats.air_dashes
	if _ladder != null:
		_blocking = false
		_sprinting = false
		_tick_ladder(input)
		move_and_slide()
		queue_redraw()
		return

	# Liane : on s'y accroche tout seul en la touchant en l'air, et on se balance.
	if _vine == null and not on_floor and _vine_regrab_timer <= 0.0 and _knockback_timer <= 0.0 \
			and not is_heavy_swinging() and not is_katana_dashing():
		var vine := _touched_vine()
		if vine != null:
			_grab_vine(vine)
	if _vine != null:
		_blocking = false
		_sprinting = false
		_tick_vine(input, delta)
		_tick_item(input, delta)
		queue_redraw()
		return

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
	elif is_katana_dashing():
		velocity = _attack_dir * weapon.heavy_speed * lerpf(1.0, THROW_CHARGE_SPEED, _heavy_charge) * _move_mult()
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
	_tick_item(input, delta)

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
	_ladder_regrab_timer -= delta
	_ladder_fling_timer -= delta
	_vine_regrab_timer -= delta
	_item_cooldown -= delta
	item_shield_timer -= delta
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
	elif _ladder_fling_timer > 0.0:
		accel = 0.0  # éjecté de l'échelle : on garde son élan
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


## On ramasse un objet (seulement si on n'en a pas déjà un).
func take_item(kind: String) -> bool:
	if item != "":
		return false
	item = kind
	item_ammo = PISTOL_AMMO if kind == "pistolet" else 0
	return true


## RT : pistolet = une balle par appui ; grenade = dégoupillée à l'appui, lancée en lâchant
## (plus on garde, plus elle va loin) ; bouclier = levé pour quelques secondes.
func _tick_item(input: InputState, delta: float) -> void:
	if _grenade_fuse >= 0.0:
		_grenade_fuse -= delta
		_grenade_hold += delta
		if _grenade_fuse <= 0.0:
			_release_grenade(Vector2.ZERO, 0.0)  # gardée trop longtemps : elle explose en main
		elif not input.item_held:
			_release_grenade(_item_direction(), clampf(_grenade_hold / GRENADE_FULL_HOLD, 0.0, 1.0))
		return
	if not input.item_pressed or _blocking or is_dashing():
		return
	match item:
		"pistolet":
			if _item_cooldown <= 0.0:
				_item_cooldown = PISTOL_COOLDOWN
				item_ammo -= 1
				if item_ammo <= 0:
					item = ""
				item_used.emit(self, "balle", _item_direction(), 1.0, 0.0)
		"grenade":
			_grenade_fuse = GRENADE_FUSE
			_grenade_hold = 0.0
		"bouclier":
			item = ""
			item_shield_timer = ITEM_SHIELD_TIME


func _release_grenade(direction: Vector2, power: float) -> void:
	var fuse := maxf(_grenade_fuse, 0.0)
	item = ""
	_grenade_fuse = -1.0
	item_used.emit(self, "grenade", direction, power, fuse)


## Vers l'adversaire visé (comme les attaques), ou devant soi.
func _item_direction() -> Vector2:
	if target != null and not target.eliminated:
		var to_target := target.global_position - global_position
		if to_target.length() > 1.0:
			return to_target.normalized()
	return Vector2(facing, 0.0)


func is_item_shielded() -> bool:
	return item_shield_timer > 0.0


## L'échelle que le corps touche, ou null.
func _touched_ladder() -> Ladder:
	for node in get_tree().get_nodes_in_group("echelles"):
		var ladder := node as Ladder
		if ladder != null and ladder.rect().intersects(body_rect()):
			return ladder
	return null


## Sur l'échelle : on est collé au milieu et on monte. En haut, on est éjecté.
func _tick_ladder(input: InputState) -> void:
	if input.jump_pressed:
		_leave_ladder()
		velocity = Vector2(input.stick.x * stats.run_speed * _move_mult(), -stats.jump_speed)
		_jump_rising = true
		return
	if input.down_pressed:
		_leave_ladder()
		velocity = Vector2.ZERO
		return
	global_position.x = _ladder.global_position.x
	velocity = Vector2(0.0, -LADDER_CLIMB_SPEED * _move_mult())
	if global_position.y + stats.body_size.y / 2.0 <= _ladder.top():
		var push := _ladder.exit_push
		_leave_ladder()
		velocity = push
		_jump_rising = false
		_ladder_fling_timer = LADDER_FLING_TIME


func _leave_ladder() -> void:
	_ladder = null
	_ladder_regrab_timer = LADDER_REGRAB_TIME


func is_climbing() -> bool:
	return _ladder != null


## La liane que le corps touche (en pendant droit), ou null.
func _touched_vine() -> Vine:
	var reach := stats.body_size.x / 2.0 + VINE_GRAB_MARGIN
	for node in get_tree().get_nodes_in_group("lianes"):
		var vine := node as Vine
		if vine == null:
			continue
		var anchor := vine.global_position
		if global_position.y < anchor.y + VINE_MIN_LENGTH:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(global_position, anchor, vine.bottom())
		if global_position.distance_to(closest) <= reach:
			return vine
	return null


## On attrape la liane : la longueur du balancier = là où on l'a attrapée ; on garde son élan.
func _grab_vine(vine: Vine) -> void:
	_vine = vine
	_swinging = true
	_swing_anchor = vine.global_position
	var offset := global_position - _swing_anchor
	_swing_length = clampf(offset.length(), VINE_MIN_LENGTH, vine.length)
	_swing_angle = clampf(atan2(offset.x, offset.y), -VINE_MAX_ANGLE, VINE_MAX_ANGLE)
	var tangent := Vector2(cos(_swing_angle), -sin(_swing_angle))
	_swing_speed = velocity.dot(tangent) / _swing_length
	_cancel_attack()
	_dash_timer = 0.0
	_jump_rising = false
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	_dash_cooldown_timer = 0.0


## Sur la liane : un pendule. Gauche / droite donne de l'élan ; saut = on lâche en gardant l'élan
## (plus un petit saut) ; bas = on se laisse tomber. En touchant le sol, on lâche.
func _tick_vine(input: InputState, delta: float) -> void:
	var tangent := Vector2(cos(_swing_angle), -sin(_swing_angle))
	if input.jump_pressed:
		var push := tangent * _swing_speed * _swing_length
		_leave_vine()
		velocity = Vector2(push.x, minf(push.y, 0.0) - stats.double_jump_speed * VINE_JUMP_BOOST)
		_ladder_fling_timer = VINE_FLING_TIME
		return
	if input.down_pressed:
		velocity = tangent * _swing_speed * _swing_length
		_leave_vine()
		_ladder_fling_timer = VINE_FLING_TIME
		return
	var accel := -stats.gravity * sin(_swing_angle) + input.stick.x * VINE_PUMP * _move_mult()
	_swing_speed += accel / _swing_length * delta
	_swing_speed *= maxf(1.0 - VINE_DAMPING * delta, 0.0)
	var max_speed := VINE_MAX_SPEED * _move_mult() / _swing_length
	_swing_speed = clampf(_swing_speed, -max_speed, max_speed)
	_swing_angle += _swing_speed * delta
	if absf(_swing_angle) > VINE_MAX_ANGLE:
		_swing_angle = clampf(_swing_angle, -VINE_MAX_ANGLE, VINE_MAX_ANGLE)
		_swing_speed = 0.0
	var target := _swing_anchor + Vector2(sin(_swing_angle), cos(_swing_angle)) * _swing_length
	velocity = (target - global_position) / maxf(delta, 0.0001)
	move_and_slide()
	if is_on_floor():
		_leave_vine()  # on s'est posé : on lâche
	elif get_slide_collision_count() > 0:
		# Cogné un mur ou le plafond : on reste à l'endroit atteint, le balancement repart dans l'autre sens.
		var offset := global_position - _swing_anchor
		_swing_angle = atan2(offset.x, offset.y)
		_swing_speed *= -0.3


func _leave_vine() -> void:
	if _vine == null:
		return
	_vine = null
	_swinging = false
	_vine_regrab_timer = VINE_REGRAB_TIME


func is_swinging() -> bool:
	return _swinging


## Pour la liane : est-ce qu'on se balance à elle ? (marche aussi chez les copains en ligne)
func is_swinging_on(vine: Vine) -> bool:
	return _swinging and _swing_anchor.is_equal_approx(vine.global_position)


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
	return stats.cooldown(heavy) * PHASE_COOLDOWN[counter_phase() - 1]


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
			if heavy_kind() == WeaponStats.Heavy.THROW:
				_throw_weapon()
		return
	_attack_time += delta * _attack_speed()
	if _attack_time >= _attack_startup() + _attack_active():
		if is_katana_dashing():
			velocity *= KATANA_DASH_END_KEEP
		_attack_time = -1.0


## Lance : elle part vers l'adversaire, et on continue à mains nues jusqu'à la ramasser.
func _throw_weapon() -> void:
	var speed := weapon.heavy_speed * lerpf(1.0, THROW_CHARGE_SPEED, _heavy_charge)
	_cancel_attack()
	weapon_away = true
	weapon_thrown.emit(self, _attack_dir, speed)


## On ramasse sa lance (ou elle revient quand on réapparaît). Cassée : elle revient à la vie suivante.
func get_weapon_back() -> void:
	weapon_away = is_weapon_broken()


## Le perso avec son arme en main ; une lance contrée est plus courte (coup léger et lourde).
func _update_armed_stats() -> void:
	_armed_stats = weapon.apply_to(_bare_stats)
	_armed_stats.attack_reach *= weapon_length()
	_armed_stats.heavy_arc_radius *= weapon_length()


## Longueur de l'arme : 1 = neuve ; chaque contre de la lance lancée la raccourcit.
func weapon_length() -> float:
	return 1.0 - SPEAR_SHORTEN * mini(spear_counters, SPEAR_MAX_COUNTERS - 1)


## Lance lancée contrée : plus courte, ou cassée (jusqu'à la prochaine vie perdue) au bout de SPEAR_MAX_COUNTERS.
func spear_countered() -> void:
	spear_counters += 1


func is_weapon_broken() -> bool:
	return spear_counters >= SPEAR_MAX_COUNTERS


## Un contre : la recharge des attaques (légère et lourde) repart de zéro.
func reset_cooldown() -> void:
	_attack_cooldown_timer = 0.0


## Ce que fait l'attaque lourde avec l'arme en main (l'arc habituel à mains nues).
func heavy_kind() -> WeaponStats.Heavy:
	return WeaponStats.Heavy.SWING if weapon_away else weapon.heavy


## Katana : en plein dash tranchant (on traverse l'adversaire, on ne peut pas être touché).
func is_katana_dashing() -> bool:
	return heavy_kind() == WeaponStats.Heavy.DASH and is_heavy_swinging() \
		and _attack_time < stats.heavy_startup + stats.heavy_active


## Marteau : l'onde de choc au sol, juste après l'arc (seulement si on est au sol).
func _is_slam_wave() -> bool:
	return heavy_kind() == WeaponStats.Heavy.SLAM and is_heavy_swinging() \
		and _attack_time >= stats.heavy_startup + stats.heavy_active


func _attack_startup() -> float:
	return stats.heavy_startup if _attack_heavy else stats.light_startup()


func _attack_active() -> float:
	if _attack_heavy and heavy_kind() == WeaponStats.Heavy.SLAM:
		return stats.heavy_active + SLAM_WAVE_TIME
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
		and _attack_time < stats.light_startup() + stats.attack_active


## Temps restant avant de pouvoir attaquer à nouveau.
func attack_cooldown_left() -> float:
	return maxf(_attack_cooldown_timer, 0.0)


func can_attack() -> bool:
	return not eliminated and not is_dashing() and not is_invincible() and not _blocking \
		and not is_attacking() and _attack_cooldown_timer <= 0.0


## Le coup peut-il toucher en ce moment ?
func is_attack_active() -> bool:
	return not _heavy_charging and _attack_time >= _attack_startup() and _attack_time < _attack_startup() + _attack_active() \
		and not _attack_has_hit and not (_is_slam_wave() and not is_on_floor())


## Depuis combien de temps le coup peut toucher (pour le renvoi de balle au bon moment).
func attack_time_since_active() -> float:
	return _attack_time - _attack_startup()


func attack_active_duration() -> float:
	return _attack_active()


func is_heavy_attack() -> bool:
	return _attack_heavy


## La zone qui touche est un segment épais (de attack_start() à attack_center(), d'épaisseur attack_radius()).
## Attaque légère : toute la barre, du centre du perso jusqu'au bout, comme un coup de poing ou
## d'épée, donc on touche aussi un adversaire tout proche. Le segment commence une épaisseur devant
## le centre : la zone s'arrête pile au centre du perso et ne déborde pas dans son dos.
## Attaque lourde : seulement le bout de l'arme.
func attack_start() -> Vector2:
	if _is_slam_wave():
		return _feet() - Vector2(_slam_wave_reach(), 0.0)
	if is_katana_dashing():
		return global_position
	if _attack_heavy:
		return attack_center()
	return global_position + _attack_dir * clampf(_light_reach() - stats.attack_radius, 0.0, stats.attack_radius)


## Le bout de la zone qui touche.
func attack_center() -> Vector2:
	if _is_slam_wave():
		return _feet() + Vector2(_slam_wave_reach(), 0.0)
	if is_katana_dashing():
		return global_position + _attack_dir * stats.heavy_arc_radius * KATANA_DASH_REACH * _range_mult()
	if _attack_heavy:
		return global_position + _heavy_tip(_heavy_angle())
	return global_position + _attack_dir * maxf(_light_reach() - stats.attack_radius, 0.0)


## Longueur actuelle du coup léger : la barre sort du perso et s'allonge pendant LIGHT_DEPLOY_TIME.
func _light_reach() -> float:
	var deploy := clampf((_attack_time - stats.light_startup()) / LIGHT_DEPLOY_TIME, 0.0, 1.0)
	return stats.attack_reach * _range_mult() * lerpf(LIGHT_DEPLOY_START, 1.0, deploy)


func _feet() -> Vector2:
	return global_position + Vector2(0.0, stats.body_size.y / 2.0 - SLAM_WAVE_RADIUS)


## Marteau : la moitié de la longueur de l'onde de choc (elle grandit pendant qu'elle part).
func _slam_wave_reach() -> float:
	var progress := clampf((_attack_time - stats.heavy_startup - stats.heavy_active) / SLAM_WAVE_TIME, 0.0, 1.0)
	return SLAM_WAVE_REACH * lerpf(1.0, 1.6, _heavy_charge) * _range_mult() * lerpf(0.4, 1.0, progress)


func attack_radius() -> float:
	if _is_slam_wave():
		return SLAM_WAVE_RADIUS
	return stats.heavy_tip_radius * lerpf(1.0, HEAVY_CHARGE_TIP_GROWTH, _heavy_charge) if _attack_heavy else stats.attack_radius


func attack_knockback() -> float:
	return stats.heavy_knockback * lerpf(1.0, HEAVY_CHARGE_KNOCKBACK, _heavy_charge) if _attack_heavy else stats.hit_knockback


func attack_direction() -> Vector2:
	return _attack_dir


## Peut-on se faire toucher ? Non pendant un dash (aussi celui du katana) ou une invincibilité.
## Le dash du katana peut quand même être contré (voir game.gd).
func can_be_hit() -> bool:
	return not eliminated and not is_dashing() and not is_katana_dashing() and not is_invincible()


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
	_leave_ladder()
	_leave_vine()
	_attack_cooldown_timer = cooldown
	velocity = _pushed(push) + Vector2(0.0, -lift)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME


## Notre coup a frappé un bouclier : il s'arrête, on est repoussé, mais on peut refrapper tout de suite.
func hit_shield(push_dir: Vector2) -> void:
	_cancel_attack()
	_leave_ladder()
	_leave_vine()
	_attack_cooldown_timer = 0.0
	velocity = _pushed(push_dir * SHIELD_HIT_PUSH) + Vector2(0.0, -120.0)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME


## Points de bouclier que nos coups font perdre : plus quand notre jauge de contre est haute.
func shield_damage(heavy: bool) -> int:
	var damage := HEAVY_SHIELD_DAMAGE * (1 if weapon_away else weapon.heavy_shield_damage) if heavy else 1
	return damage * PHASE_SHIELD_DAMAGE[counter_phase() - 1]


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
	_leave_ladder()
	_leave_vine()
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
	if _grenade_fuse >= 0.0:
		_release_grenade(Vector2.ZERO, 0.0)  # touché : la grenade dégoupillée tombe des mains
	_leave_ladder()
	_leave_vine()
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
	_leave_ladder()
	_leave_vine()
	_dash_timer = 0.0
	global_position = respawn_position
	velocity = Vector2.ZERO
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	# On repart à neuf : plus de recul ni de saut en cours venant d'avant la chute.
	_knockback_timer = 0.0
	_wall_jump_timer = 0.0
	_ladder_fling_timer = 0.0
	if _grenade_fuse >= 0.0:
		item = ""  # tombé avec une grenade dégoupillée : elle est perdue
		_grenade_fuse = -1.0
	_drop_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_rising = false
	_lose_life()


func _lose_life() -> void:
	lives -= 1
	_stun_timer = 0.0
	_invincible_timer = INVINCIBLE_TIME
	show_lives()
	if is_weapon_broken():
		spear_counters = 0  # lance cassée : une neuve revient à la vie suivante
		weapon_away = false
	if lives <= 0:
		_leave_vine()
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

	# En surbrillance quand on bloque : plus le bouclier a pris de coups, plus il est fissuré et terne.
	# Sonné, le bouclier ne protège plus : il ne s'allume que le temps d'un blocage parfait.
	if _blocking and (not is_stunned() or is_parrying()):
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

	var weapon_color := Color(1, 1, 1) if weapon_away else weapon.color

	# Katana : le dash tranchant, la lame pointée devant soi
	if is_katana_dashing():
		var blade_tip := attack_center() - global_position
		for i in 3:
			var ghost := body
			ghost.position -= _attack_dir * 18.0 * (i + 1)
			draw_rect(ghost, Color(color, 0.25 - i * 0.07))
		draw_line(Vector2.ZERO, blade_tip, Color(weapon_color, 0.95), 5.0)
		draw_line(-blade_tip * 0.6, blade_tip, Color(weapon_color, 0.3), 12.0)

	# Marteau : l'onde de choc au sol, des deux côtés
	elif _is_slam_wave():
		if is_on_floor():
			var reach := _slam_wave_reach()
			var feet := _feet() - global_position
			var fade := 1.0 - clampf((_attack_time - stats.heavy_startup - stats.heavy_active) / SLAM_WAVE_TIME, 0.0, 1.0)
			draw_rect(Rect2(feet + Vector2(-reach, -SLAM_WAVE_RADIUS), Vector2(reach * 2.0, SLAM_WAVE_RADIUS * 2.0)),
				Color(weapon_color, 0.25 + 0.5 * fade))
			draw_rect(Rect2(feet + Vector2(-reach, SLAM_WAVE_RADIUS - 3.0), Vector2(reach * 2.0, 3.0)), Color(1, 1, 1, 0.8 * fade))

	# L'attaque lourde : l'arme levée au-dessus de la tête, puis un arc jusqu'aux pieds
	elif is_attacking() and _attack_heavy:
		var angle := _heavy_angle()
		if _attack_time >= stats.heavy_startup:
			var trail := PackedVector2Array()
			var start := deg_to_rad(HEAVY_ARC_START)
			for i in 9:
				trail.append(_heavy_tip(lerpf(start, angle, i / 8.0)))
			draw_polyline(trail, Color(color.lightened(0.5), 0.5), 10.0)
		var tip := _heavy_tip(angle)
		var weapon_scale := heavy_scale()
		var blade_color := Color(weapon_color, 0.95)
		if _heavy_charging:
			blade_color = Color(weapon_color, lerpf(0.55, 0.9, _heavy_charge))
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
		if _attack_time < stats.light_startup():
			# On arme le coup : le poing recule derrière le perso, et une fine ligne montre où il va partir
			var windup := clampf(_attack_time / stats.light_startup(), 0.0, 1.0)
			draw_rect(Rect2(10.0, -1.5, length - 10.0, 3.0), Color(1, 1, 1, 0.12 + 0.2 * windup))
			var back := lerpf(2.0, 14.0, windup)
			draw_rect(Rect2(-back - tip, -tip * 0.8, tip, tip * 1.6), Color(color.lightened(0.6), 0.6 + 0.4 * windup))
		else:
			# Le coup part : la barre jaillit du perso et s'allonge jusqu'au bout
			var reach := _light_reach()
			draw_rect(Rect2(10.0, -bar, maxf(reach - 10.0, 0.0), bar * 2.0), Color(weapon_color, 0.95))
			draw_rect(Rect2(reach - tip, -tip, tip, tip * 2.0), color.lightened(0.6))
			if reach < length:
				draw_rect(Rect2(reach, -1.5, length - reach, 3.0), Color(1, 1, 1, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0)

	# L'arme dans la main quand on n'attaque pas (dessin très simple, à remplacer par un graphiste)
	elif not weapon_away and weapon.held_length > 0.0:
		var hand := Vector2(facing * stats.body_size.x / 2.0, 4.0)
		var end := hand + Vector2(facing * 0.4, -1.0).normalized() * weapon.held_length * weapon_length()
		draw_line(hand, end, weapon_color, 3.0)
		if weapon.held_head > 0.0:
			draw_rect(Rect2(end - Vector2.ONE * weapon.held_head / 2.0, Vector2.ONE * weapon.held_head), weapon_color)

	_draw_item(body)

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


## L'objet ramassé (dessin très simple, à remplacer par un graphiste) : pistolet et ses balles,
## grenade (qui clignote de plus en plus vite une fois dégoupillée), bouclier levé devant soi.
func _draw_item(body: Rect2) -> void:
	if is_item_shielded():
		var fade := clampf(item_shield_timer / 0.5, 0.0, 1.0)
		var plate := Rect2(Vector2(facing * (body.size.x / 2.0 + 6.0) - 5.0, -body.size.y / 2.0 - 6.0), Vector2(10.0, body.size.y + 12.0))
		draw_rect(plate, Color(ItemPickup.color_of("bouclier"), 0.85 * fade))
		draw_rect(plate.grow(2.0), Color(1, 1, 1, 0.6 * fade), false, 2.0)
	var hand := Vector2(facing * (body.size.x / 2.0 + 6.0), 6.0)
	match item:
		"pistolet":
			draw_rect(Rect2(hand + Vector2(-5.0 if facing < 0.0 else 0.0, -3.0), Vector2(14.0 * facing, 6.0)).abs(), ItemPickup.color_of("pistolet"))
			for i in item_ammo:
				draw_rect(Rect2(Vector2(-body.size.x / 2.0 + i * 5.0, body.size.y / 2.0 + 4.0), Vector2(3.0, 5.0)), Color(1, 0.9, 0.5, 0.8))
		"grenade":
			var grenade_color := ItemPickup.color_of("grenade")
			if _grenade_fuse >= 0.0 and int(_blink_clock / lerpf(0.05, 0.25, _grenade_fuse / GRENADE_FUSE)) % 2 == 0:
				grenade_color = Color(1, 0.3, 0.2)
			draw_circle(hand, 7.0, grenade_color)
			if _grenade_fuse >= 0.0:
				# Plus RT est gardé, plus elle partira loin
				var power := clampf(_grenade_hold / GRENADE_FULL_HOLD, 0.0, 1.0)
				draw_arc(hand, 12.0, -PI / 2.0, -PI / 2.0 + TAU * power, 20, Color(1, 1, 1, 0.8), 2.0)


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
