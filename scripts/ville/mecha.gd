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
##   Y : l'arme lourde, tirée au hasard à son arrivée (heavy_weapon) : lance-roquette (garder pour
##       charger : 1 à 3 roquettes, guidées à charge pleine) ou canon laser (un appui = 1 s de charge puis il tire ; gardé = plus rapide, long et gros)
##   B : bouclier d'énergie (il encaisse à la place du mecha ; vide, il est cassé pour de bon) ;
##       levé juste avant le coup (PARRY_WINDOW) = blocage parfait, un contre
##   RB : coup de poing devant soi
##   RT : missiles (objet ramassé en mecha) : 4 missiles qui suivent l'ennemi le plus proche
##   X + Y : l'ultime du pilote en plus gros (jauge d'ultime pleine) : Barre = grand laser qui
##       traverse tout et gèle 3 s, Jumb = onde de choc de 600 px, Jib = 3 traversées éclair
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
const STOMP_MIN_SPEED := 1300.0         ## retombé plus vite que ça (de haut) sur des blocs de la ville : il les abîme...
const STOMP_DAMAGE := [1, 4]            ## ... de 1 (pas très haut) à 4 (de très haut) : 2 grosses chutes cassent un bloc neuf
const STOMP_KEEP := 0.7                 ## ... et s'il casse, il continue de tomber un peu freiné
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
const ROCKET_FULL_CHARGE := 1.5         ## Y gardé 1,5 s : charge pleine, 3 roquettes guidées (elles partent toutes seules)
const ROCKET_VOLLEY_CHARGE := [0.5, 1.0]  ## petite charge : 1 roquette ; gardé 0,5 s : 2 ; gardé 1 s : 3
const ROCKET_POWER := 0.5               ## force de chaque roquette (voir Game.ROCKET_RADIUS)
const ROCKET_GAP := 0.12                ## les roquettes d'une salve partent une toutes les 0,12 s...
const ROCKET_SPREAD := 0.08             ## ... un peu écartées
const ROCKET_COOLDOWN := 0.8
const LASER_MIN_CHARGE := 1.0           ## canon laser : un appui sur Y = 1 s de charge, puis il tire...
const LASER_FULL_CHARGE := 2.5          ## ... Y gardé plus longtemps : plus de charge (au plus 2,5 s, il tire tout seul)
const LASER_COOLDOWN := 1.0
const HEAVY_WEAPONS := ["roquette", "laser"]
const GUN_MOUNT := Vector2(94.0, -125.0)  ## la mitrailleuse sous le nez (x vers l'avant) : d'où partent les balles...
const GUN_LENGTH := 99.0
const TURRET_PIVOT := Vector2(0.0, -270.0)  ## ... et la tourelle sur le dos, d'où partent les roquettes
const TURRET_LENGTH := 182.0
const AIM_UP_MAX := 1.3                 ## les armes visent jusqu'à presque droit au-dessus...
const AIM_DOWN_MAX := 1.0               ## ... et assez bas devant soi
const SHIELD_MAX := 20                  ## B : le bouclier d'énergie encaisse 20 points d'usure, puis casse pour de bon
const SHIELD_WALK_MULT := 0.4           ## bouclier levé : il avance lentement, ne tire pas, ne dashe pas
const PARRY_WINDOW := Fighter.PARRY_WINDOW  ## B levé depuis au plus ça au moment du coup : blocage parfait
const PARRY_LOCK := 1.0                 ## frappé sur un blocage parfait : plus de poing ni de tir pendant 1 s
const MISSILES := 4                     ## RT avec l'objet missiles : 4 missiles...
const MISSILE_GAP := 0.12               ## ... un toutes les 0,12 s, qui partent vers le haut puis suivent l'ennemi
const ULT_LASER_STARTUP := 0.4          ## Barre : le grand laser vise (fin trait bleu)...
const ULT_LASER_ACTIVE := 0.6           ## ... puis tire : il traverse tout (blocs compris) et gèle
const ULT_LASER_RANGE := 2600.0
const ULT_LASER_RADIUS := 45.0          ## demi-épaisseur du rayon
const ULT_WAVE_STARTUP := 0.3           ## Jumb : il se ramasse...
const ULT_WAVE_ACTIVE := 0.45           ## ... puis l'onde s'ouvre jusqu'à 600 px
const ULT_WAVE_RADIUS := 600.0
const ULT_BOLT_STARTUP := 0.15          ## Jib : un éclair l'entoure, puis 3 traversées à travers l'ennemi
const ULT_BOLT_PASSES := 3
const ULT_BOLT_PASS_TIME := 0.2
const ULT_BOLT_GAP := 0.12
const ULT_BOLT_SPEED := 3000.0
const FREEZE_TIME := 3.0                ## gelé par le grand laser : plus rien ne marche pendant 3 s
const PUNCH_STARTUP := 0.06             ## RB : le poing part...
const PUNCH_ACTIVE := 0.12              ## ... frappe pendant ce temps...
const PUNCH_COOLDOWN := 0.5             ## ... et revient au plus toutes les 0,5 s
const PUNCH_REACH := 150.0              ## jusqu'où il frappe devant le corps
const PUNCH_HEIGHT := 220.0             ## haute zone : il touche aussi un joueur à pied, tout petit devant lui
const PUNCH_Y := -120.0                 ## hauteur du poing (bas du corps, vers ceux qui sont à pied)

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
var _volley_left := 0                   ## roquettes de la salve qui restent à partir
var _volley_timer := 0.0
var volley_guided := false              ## salve chargée à fond : ses roquettes suivent l'adversaire (game.gd)
var _barrel := 0
var shield := SHIELD_MAX                ## ce qu'il reste au bouclier d'énergie
var shield_broken := false
var _shielding := false
var _shield_hold := 0.0                 ## B gardé depuis ce temps (blocage parfait au début)
var _shield_flash := 0.0                ## le bouclier vient d'encaisser (ou de casser) : il brille
var _punch_time := -1.0                 ## RB : temps depuis le début du coup de poing (-1 = pas de poing)
var _punch_cooldown := 0.0
var _missiles_left := 0
var _missile_timer := 0.0
var punch_hit := []
var ultimate := ""                      ## l'ultime en cours : "laser", "onde", "eclair" ("" = aucun)
var ult_time := 0.0
var ult_dir := Vector2.RIGHT            ## grand laser : sa direction
var ult_hit := []                       ## ce que l'ultime a déjà touché (éclair : pendant cette traversée)
var ult_blocks := {}                    ## onde : les blocs déjà abîmés
var ult_target: Node2D                  ## éclair : ce qu'il traverse (le mecha de l'ennemi, ou l'ennemi à pied)
var laser_blocks_done := false
var frozen_timer := 0.0
var _bolt_pass := -1
var _dash_speed := DASH_SPEED                     ## ce que ce coup de poing a déjà touché (une fois chacun)


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
	frozen_timer -= delta
	if pilot == null or frozen_timer > 0.0:
		input = InputState.new()  # vide, ou gelé par un grand laser : il ne fait plus rien
	var on_floor := is_on_floor()
	if ultimate == "" and pilot != null and input.ultimate_pressed and pilot.is_ultimate_ready():
		_start_ultimate()
	if ultimate != "":
		_tick_ultimate(delta)
		input = InputState.new()  # pendant l'ultime, il ne fait rien d'autre
	_dash_timer -= delta
	_dash_cooldown -= delta
	var exiting := input.stick.y > EXIT_STICK and input.jump_held
	_exit_hold = _exit_hold + delta if exiting and pilot != null else 0.0
	if input.stick.x != 0.0 and _dash_timer <= 0.0:
		facing = signf(input.stick.x)
	if _empty_tank and fuel >= FUEL_RESTART:
		_empty_tank = false
	var has_fuel := fuel > 0.0 and not _empty_tank
	_tick_shield(input, delta)
	var turbo := input.sprint_held and has_fuel and absf(input.stick.x) > 0.2 and not _shielding
	_thrusting = false

	if input.dash_pressed and _dash_cooldown <= 0.0 and not _shielding:
		_dash_dir = input.stick.normalized() if input.stick.length() >= 0.3 else Vector2(facing, 0.0)
		_dash_timer = DASH_TIME
		_dash_speed = DASH_SPEED
		_dash_cooldown = DASH_COOLDOWN
	if _dash_timer > 0.0:
		velocity = _dash_dir * _dash_speed
		if _dash_timer <= delta:
			velocity *= DASH_END_KEEP
	else:
		var speed := (WALK_SPEED if on_floor else FLY_SPEED) * (TURBO_MULT if turbo else 1.0) * (SHIELD_WALK_MULT if _shielding else 1.0)
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
	_tick_punch(input, delta)
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
	if pilot == null or _shielding:
		_burst_left = 0
		_charge = -1.0
		_missiles_left = 0
		_volley_left = 0
		visual.turret_charge = -1.0
		return
	if input.item_pressed and pilot.item == "missiles" and _missiles_left <= 0:
		pilot.item = ""
		_missiles_left = MISSILES
		_missile_timer = 0.0
	if _missiles_left > 0:
		_missile_timer -= delta
		if _missile_timer <= 0.0:
			# Ils partent de la tourelle en éventail vers le haut, puis tournent vers leur cible
			var spread := (_missiles_left - (MISSILES + 1) / 2.0) * 0.25
			var dir := Vector2(facing * 0.45, -1.0).normalized().rotated(spread)
			fired.emit(self, "missile", global_position + TURRET_PIVOT + Vector2(0.0, -30.0), dir, 0.0)
			_missiles_left -= 1
			_missile_timer = MISSILE_GAP
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
	if _volley_left > 0:
		_volley_timer -= delta
		if _volley_timer <= 0.0:
			_fire_volley_rocket()
	if input.heavy_pressed and _rocket_cooldown <= 0.0 and _charge < 0.0 and _volley_left <= 0:
		_charge = 0.0
	if _charge >= 0.0:
		_charge += delta
		var laser := heavy_weapon == "laser"
		var full := LASER_FULL_CHARGE if laser else ROCKET_FULL_CHARGE
		if (not input.heavy_held and (not laser or _charge >= LASER_MIN_CHARGE)) or _charge >= full:
			if laser:
				var dir := aim_direction(TURRET_PIVOT)
				_face(dir)
				fired.emit(self, heavy_weapon, turret_muzzle(dir), dir, clampf((_charge - LASER_MIN_CHARGE) / (full - LASER_MIN_CHARGE), 0.0, 1.0))
				_shot_flash()
				_rocket_cooldown = LASER_COOLDOWN
			else:
				# Roquettes : 1 à 3 selon la charge, guidées si la charge est pleine
				_volley_left = 1 + ROCKET_VOLLEY_CHARGE.filter(func(t: float) -> bool: return _charge >= t).size()
				volley_guided = _charge >= full
				_volley_timer = 0.0
				_fire_volley_rocket()
			_charge = -1.0
	var full_charge := LASER_FULL_CHARGE if heavy_weapon == "laser" else ROCKET_FULL_CHARGE
	visual.turret_charge = clampf(_charge / full_charge, 0.0, 1.0) if _charge >= 0.0 else -1.0


## Une roquette de la salve, vers l'adversaire visé (un peu écartée des autres).
func _fire_volley_rocket() -> void:
	var dir := aim_direction(TURRET_PIVOT)
	_face(dir)
	dir = dir.rotated((_volley_left % 3 - 1) * ROCKET_SPREAD)
	fired.emit(self, "roquette", turret_muzzle(dir), dir, ROCKET_POWER)
	_shot_flash()
	_volley_left -= 1
	_volley_timer = ROCKET_GAP
	_rocket_cooldown = ROCKET_COOLDOWN


func _shot_flash() -> void:
	visual.turret_barrel = _barrel
	visual.turret_shot_time = 0.0
	_barrel = (_barrel + 1) % MechaVisual.BARRELS


## X + Y, jauge d'ultime du pilote pleine : l'ultime de son perso, en plus gros.
func _start_ultimate() -> void:
	pilot.ultimate_points = 0
	ultimate = pilot.stats.ultimate
	ult_time = 0.0
	ult_hit.clear()
	ult_blocks.clear()
	laser_blocks_done = false
	_bolt_pass = -1
	_burst_left = 0
	_charge = -1.0
	_volley_left = 0
	_punch_time = -1.0
	ult_dir = aim_direction(TURRET_PIVOT)
	var target := pilot.target
	ult_target = null
	if target != null and not target.eliminated:
		ult_target = target.mecha if target.is_piloting() else target


func _tick_ultimate(delta: float) -> void:
	ult_time += delta
	match ultimate:
		"laser":
			velocity.x = 0.0
			if ult_time < ULT_LASER_STARTUP:
				ult_dir = aim_direction(TURRET_PIVOT)  # il vise l'ennemi pendant qu'il se prépare
				_face(ult_dir)
			elif ult_time >= ULT_LASER_STARTUP + ULT_LASER_ACTIVE:
				stop_ultimate()
		"onde":
			velocity.x = 0.0
			if ult_time >= ULT_WAVE_STARTUP + ULT_WAVE_ACTIVE:
				stop_ultimate()
		"eclair":
			if ult_time < ULT_BOLT_STARTUP:
				velocity = Vector2.ZERO
				return
			var cycle := ULT_BOLT_PASS_TIME + ULT_BOLT_GAP
			var index := int((ult_time - ULT_BOLT_STARTUP) / cycle)
			if index >= ULT_BOLT_PASSES:
				stop_ultimate()
				return
			if index != _bolt_pass:
				# Nouvelle traversée : il vise à nouveau l'ennemi et fonce à travers lui
				_bolt_pass = index
				ult_hit.clear()
				var aim := Vector2(facing, 0.0)
				if is_instance_valid(ult_target):
					aim = (_center_of(ult_target) - body_rect().get_center()).normalized()
				_dash_dir = aim
				_dash_speed = ULT_BOLT_SPEED
				_dash_timer = ULT_BOLT_PASS_TIME
				_face(aim)
			elif _dash_timer <= 0.0:
				velocity = Vector2.ZERO  # petit arrêt entre deux traversées


func _center_of(node: Node2D) -> Vector2:
	return node.body_rect().get_center() if node.has_method("body_rect") else node.global_position


func stop_ultimate() -> void:
	ultimate = ""
	if _dash_speed != DASH_SPEED:
		_dash_timer = 0.0
		_dash_speed = DASH_SPEED


func is_laser_firing() -> bool:
	return ultimate == "laser" and ult_time >= ULT_LASER_STARTUP


func laser_start() -> Vector2:
	return turret_muzzle(ult_dir)


func laser_end() -> Vector2:
	return laser_start() + ult_dir * ULT_LASER_RANGE


## Onde de Jumb : son rayon en ce moment (0 = pas d'onde).
func wave_radius() -> float:
	if ultimate != "onde" or ult_time < ULT_WAVE_STARTUP:
		return 0.0
	return lerpf(80.0, ULT_WAVE_RADIUS, clampf((ult_time - ULT_WAVE_STARTUP) / ULT_WAVE_ACTIVE, 0.0, 1.0))


func is_bolt_passing() -> bool:
	return ultimate == "eclair" and _dash_timer > 0.0


## Touché par un grand laser : gelé (plus rien ne marche) pendant FREEZE_TIME.
func freeze() -> void:
	frozen_timer = FREEZE_TIME
	stop_ultimate()
	_punch_time = -1.0
	_burst_left = 0
	_charge = -1.0
	_missiles_left = 0
	_dash_timer = 0.0


func is_frozen() -> bool:
	return frozen_timer > 0.0


## B : le bouclier d'énergie se lève (pas pendant un dash ni un coup de poing ; plus jamais une fois cassé).
func _tick_shield(input: InputState, delta: float) -> void:
	_shield_flash -= delta
	_shielding = pilot != null and input.block_held and not shield_broken and _dash_timer <= 0.0 and _punch_time < 0.0 and ultimate == ""
	_shield_hold = _shield_hold + delta if _shielding else 0.0


func is_shielding() -> bool:
	return _shielding


## Bouclier levé juste avant le coup : blocage parfait.
func is_parrying() -> bool:
	return _shielding and _shield_hold <= PARRY_WINDOW


## Quelque chose l'use de "amount" : blocage parfait ("parry", rien n'est usé), bouclier levé
## ("shield", c'est lui qui s'use, et il casse à 0), sinon le mecha s'use ("hit", voir damage).
func absorb(amount: int) -> String:
	if is_parrying():
		_shield_flash = HIT_FLASH_TIME
		return "parry"
	if _shielding:
		shield = maxi(shield - amount, 0)
		_shield_flash = HIT_FLASH_TIME * 2.0
		if shield <= 0:
			shield_broken = true
			_shielding = false
		return "shield"
	damage(amount)
	return "hit"


## Ce qu'il a frappé était en blocage parfait : repoussé, et plus de poing ni de tir un instant.
func parried(push: Vector2) -> void:
	velocity = push
	stop_ultimate()
	_punch_time = -1.0
	_burst_left = 0
	_charge = -1.0
	_volley_left = 0
	_punch_cooldown = PARRY_LOCK
	_gun_cooldown = PARRY_LOCK
	_rocket_cooldown = PARRY_LOCK


## RB : coup de poing devant soi (game.gd applique ce qu'il touche, voir punch_rect).
func _tick_punch(input: InputState, delta: float) -> void:
	_punch_cooldown -= delta
	if _punch_time >= 0.0:
		_punch_time += delta
		if _punch_time >= PUNCH_STARTUP + PUNCH_ACTIVE:
			_punch_time = -1.0
	elif pilot != null and input.throw_pressed and _punch_cooldown <= 0.0 and not _shielding:
		_punch_time = 0.0
		_punch_cooldown = PUNCH_COOLDOWN
		punch_hit.clear()
		var target_dir := aim_direction(Vector2(0.0, PUNCH_Y))
		_face(target_dir)


func is_punch_active() -> bool:
	return _punch_time >= PUNCH_STARTUP


## La zone que le poing frappe, devant le corps.
func punch_rect() -> Rect2:
	var front := global_position.x + facing * BODY.x / 2.0
	var left := front if facing > 0.0 else front - PUNCH_REACH
	return Rect2(left, global_position.y + PUNCH_Y - PUNCH_HEIGHT / 2.0, PUNCH_REACH, PUNCH_HEIGHT)


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


## Retombé de haut sur des blocs de la ville : il les abîme (plus il tombait vite, plus fort).
## Un bloc cassé : il continue de tomber (un peu freiné) et peut casser le plancher d'en dessous.
func _stomp(before: Vector2) -> void:
	if before.y < STOMP_MIN_SPEED:
		return
	var damage := roundi(lerpf(STOMP_DAMAGE[0], STOMP_DAMAGE[1], inverse_lerp(STOMP_MIN_SPEED, MAX_FALL, before.y)))
	var broke := false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var block := collision.get_collider() as CityBlock
		if block != null and collision.get_normal().y < -0.5 and block.hit(damage):
			broke = true
	if broke:
		velocity.y = before.y * STOMP_KEEP


func is_destroyed() -> bool:
	return hp <= 0


func _move() -> void:
	var dashing := _dash_timer > 0.0
	var before := velocity
	move_and_slide()
	if not dashing:
		_stomp(before)
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
	visual.modulate = Color(2.0, 2.0, 2.0) if _hit_flash > 0.0 else (Color(0.6, 0.85, 1.4) if is_frozen() else Color.WHITE)


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
	_draw_shield()
	_draw_punch()
	_draw_ultimate()
	if pilot != null and pilot.item == "missiles":
		# Les missiles prêts : 4 petits traits roses sur la tourelle
		for i in MISSILES:
			draw_rect(Rect2(Vector2(-30.0 + i * 16.0, TURRET_PIVOT.y - 60.0), Vector2(8.0, 22.0)), ItemPickup.color_of("missiles"))
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


## Le bouclier d'énergie : une bulle bleu clair autour du corps, plus pâle quand il est usé,
## blanche au moment du blocage parfait.
func _draw_shield() -> void:
	if not _shielding and _shield_flash <= 0.0:
		return
	var center := Vector2(0.0, -BODY.y / 2.0)
	var left := float(shield) / SHIELD_MAX
	var color := Color(1, 1, 1) if is_parrying() or (_shield_flash > 0.0 and not _shielding) else Fighter.LASER_COLOR
	var points := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		points.append(center + Vector2(cos(a) * (BODY.x / 2.0 + 45.0), sin(a) * (BODY.y / 2.0 + 40.0)))
	draw_colored_polygon(points, Color(color, 0.12 + 0.18 * left))
	draw_polyline(points, Color(color, 0.5 + 0.5 * left), 5.0 if _shield_flash > 0.0 else 3.0)


## Jauge d'ultime pleine : un anneau qui pulse autour du mecha. Pendant l'ultime : le laser (fin
## trait qui vise, puis gros rayon bleu), l'onde orange, ou l'éclair jaune autour du corps.
func _draw_ultimate() -> void:
	var center := Vector2(0.0, -BODY.y / 2.0)
	if pilot != null and pilot.is_ultimate_ready() and ultimate == "":
		var pulse := 0.5 + 0.5 * sin(_state_time * 8.0)
		draw_arc(center, BODY.y / 2.0 + 40.0 + 8.0 * pulse, 0.0, TAU, 48, Color(1, 1, 1, 0.35 + 0.4 * pulse), 4.0)
	match ultimate:
		"laser":
			var from := to_local(laser_start())
			var to := to_local(laser_end())
			if not is_laser_firing():
				draw_line(from, to, Color(Fighter.LASER_COLOR, 0.5), 3.0)
			else:
				draw_line(from, to, Color(Fighter.LASER_COLOR, 0.45), ULT_LASER_RADIUS * 2.0)
				draw_line(from, to, Color(1, 1, 1, 0.9), ULT_LASER_RADIUS * 0.6)
		"onde":
			var r := wave_radius()
			if r <= 0.0:
				draw_arc(center, 120.0 * (1.0 - ult_time / ULT_WAVE_STARTUP) + 60.0, 0.0, TAU, 48, Fighter.WAVE_COLOR, 6.0)
			else:
				draw_arc(center, r, 0.0, TAU, 64, Fighter.WAVE_COLOR, 14.0)
		"eclair":
			var flicker := Color(Fighter.BOLT_COLOR, 0.5 + 0.5 * sin(ult_time * 60.0))
			draw_rect(Rect2(-BODY.x / 2.0 - 20.0, -BODY.y - 20.0, BODY.x + 40.0, BODY.y + 40.0), flicker, false, 8.0)


## Le poing : un gros bloc de sa couleur qui jaillit devant le corps.
func _draw_punch() -> void:
	if _punch_time < 0.0:
		return
	var out := clampf(_punch_time / PUNCH_STARTUP, 0.0, 1.0)
	var front := BODY.x / 2.0 - 30.0
	var length := lerpf(30.0, PUNCH_REACH + 30.0, out)
	var arm := Rect2(Vector2(front if facing > 0.0 else -front - length, PUNCH_Y - 18.0), Vector2(length, 36.0))
	var fist := Rect2(Vector2(arm.end.x - 50.0 if facing > 0.0 else arm.position.x, PUNCH_Y - 40.0), Vector2(50.0, 80.0))
	draw_rect(arm, visual.color.darkened(0.2))
	draw_rect(fist, visual.color)
	draw_rect(fist, Color(1, 1, 1, 0.9), false, 3.0)


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
