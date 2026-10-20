class_name Game
extends Node2D
## Le chef d'orchestre de la partie : crée les joueurs, leur passe les commandes,
## gère les coups, les chocs d'attaques, les chutes hors de la map, la caméra et la fin de partie.
## Les joueurs, leurs appareils, leurs personnages et la map viennent de GameSetup.
## La map est une scène à part (scenes/maps/), chargée au début de la partie.
##
## En ligne (voir Online) : chez l'hôte, la partie tourne comme en local, mais les touches des
## copains arrivent par le réseau, et l'état du jeu leur est renvoyé à chaque frame. Chez un
## copain, rien n'est calculé : on envoie ses touches à l'hôte et on affiche ce qu'il renvoie.

const PLAYER_COLORS := [
	Color(0.95, 0.35, 0.35),  # Joueur 1 : rouge
	Color(0.35, 0.65, 1.0),   # Joueur 2 : bleu
	Color(0.45, 0.9, 0.45),   # Joueur 3 : vert
	Color(1.0, 0.85, 0.3),    # Joueur 4 : jaune
]
const RESTART_DELAY := 1.0   ## évite de relancer par erreur en martelant les boutons
const MENU_SCENE := "res://scenes/menu.tscn"

# --- Caméra : elle suit le milieu des joueurs et dézoome quand ils s'éloignent ---
const CAMERA_MARGIN := Vector2(700, 450)   ## espace gardé autour des joueurs (en pixels)
const CAMERA_ZOOM_MIN := 0.2              ## zoom le plus éloigné (plus petit = voit plus loin)
const CAMERA_ZOOM_MAX := 1.2               ## zoom le plus proche
const CAMERA_SMOOTHING := 6.0              ## plus grand = la caméra réagit plus vite

# --- Micro-duel : une attaque lourde contrée par une légère -> zoom et ralenti ---
const DUEL_TIME_SCALE := 0.5               ## le jeu va 2 fois moins vite
const DUEL_DURATION := 5.0                 ## pendant 5 vraies secondes
const DUEL_CAMERA_MARGIN := Vector2(320, 220)  ## la caméra serre les deux duellistes
const DUEL_ZOOM_MAX := 2.0
const DUEL_GROUP_CAMERA_MARGIN := Vector2(480, 320)  ## à 3 ou 4 : tout le monde reste à l'écran, un peu plus serré
const SHIELD_BREAK_TIME_SCALE := 0.3        ## bouclier cassé : ralenti (3 fois moins vite)...
const SHIELD_BREAK_SLOWMO := 1.2            ## ... pendant 1,2 vraie seconde
const PARRY_COLOR := Color(0.55, 0.85, 1.0)  ## la marque d'un blocage parfait
const WEAPON_BREAK_TIME_SCALE := 0.25       ## arme cassée (3e contre de sa lourde) : court ralenti...
const WEAPON_BREAK_SLOWMO := 0.8            ## ... pendant 0,8 vraie seconde...
const WEAPON_BREAK_CAMERA_MARGIN := Vector2(260, 180)  ## ... et la caméra zoome fort sur l'arme qui casse
const WEAPON_BREAK_ZOOM_MAX := 2.4

# --- 1 contre 1 : tant qu'un joueur est sonné, la caméra serre les deux joueurs et le temps ralentit un peu ---
const STUN_TIME_SCALE := 0.75              ## le jeu va un peu moins vite (2 s sonné = 2,7 vraies secondes)
const STUN_CAMERA_MARGIN := Vector2(380, 260)
const STUN_ZOOM_MAX := 1.8
const STUN_CAMERA_SMOOTHING := 12.0        ## la caméra fonce sur l'impact

# --- Une vie perdue (coup ou chute) : l'écran tremble ---
const SHAKE_TIME := 0.35                   ## en vraies secondes
const SHAKE_STRENGTH := 12.0               ## pixels à l'écran au début, puis le tremblement se calme

# --- Objets qui tombent sur la map (voir item_pickup.gd) ---
const ITEM_SPAWN_TIME := 10.0              ## un objet tombe toutes les 10 s...
const MAX_PICKUPS := 2                     ## ... s'il n'y en a pas déjà 2 par terre
const BULLET_SPEED := 1700.0
const BULLET_KNOCKBACK := 450.0
const DEFLECT_PERFECT := 0.04              ## balle frappée dans les 0,04 s où le coup sort : renvoyée droit sur le tireur
const DEFLECT_MAX_ANGLE := 90.0            ## ... sinon déviée, jusqu'à 90° pour un coup donné tout à la fin
const DEFLECT_SPEED := 1.15                ## une balle renvoyée va un peu plus vite
const GRENADE_MIN_THROW := 650.0           ## RT juste tapé : la grenade part assez près...
const GRENADE_MAX_THROW := 1800.0          ## ... RT gardé 1 s : elle part le plus loin et le plus vite possible
const GRENADE_LOB := 0.25                  ## lancée presque droit (un peu vers le haut), elle colle là où elle touche
const GRENADE_MAX_POWER := 1.4             ## ... et pleine charge, son explosion projette 1,4 fois plus fort
const GRENADE_HIT_SPEED := 900.0           ## frappée par un coup, elle repart dans le sens du coup
const GRENADE_RADIUS := 140.0              ## rayon de l'explosion
const GRENADE_KNOCKBACK := 1150.0
const GRENADE_SHIELD_DAMAGE := 3

# --- Blocage parfait : l'arme de celui qui frappait lui saute des mains ---
const KNOCKED_SPEED_MIN := 550.0           ## jauge de contre vide : elle tombe à quelques pas...
const KNOCKED_SPEED_MAX := 1400.0          ## ... jauge pleine (berserk) : elle part très loin
const KNOCKED_LIFT := 0.9                  ## elle part en cloche, vers l'arrière de celui qui frappait
const KNOCKED_PICKUP_DELAY := 0.4          ## on ne peut pas la rattraper tout de suite en vol

# --- Armes qui apparaissent sur la map (points WeaponSpawns, voir GameMap.weapon_spawn_points) ---
const WEAPON_SPAWN_TIME := 12.0            ## une arme au hasard tombe toutes les 12 s...
const MAX_LOOSE_WEAPONS := 2               ## ... s'il n'y a pas déjà 2 armes qui traînent sur la map

# --- RB : on lance son arme vers l'adversaire le plus proche, sans dégâts ---
const TOSS_SPEED := 1150.0
const TOSS_LIFT := 220.0                   ## un peu vers le haut, pour qu'elle aille loin avant de tomber
const WEAPON_BOUNCE_SPEED := 150.0         ## une arme qui vole plus vite que ça rebondit sur un joueur armé

# --- Objets et armes qui traînent par terre (voir LooseBody) : un coup les fait valdinguer ---
const LOOSE_HIT_SPEED := 1.2               ## vitesse = recul du coup x 1,2 (lourde, marteau : plus loin)
const LOOSE_HIT_LIFT := 300.0              ## ... un peu vers le haut, pour qu'ils décollent du sol
const LOOSE_HIT_LOCK := 0.3                ## le même coup ne le refrappe pas à chaque frame
const LOOSE_BLAST_SPEED := 1100.0          ## soufflé par une grenade

const ONLINE_HEADER := 11                  ## jeu en ligne : nombre de cases avant l'état des joueurs (voir online_state)

var fighters: Array[Fighter] = []
var player_devices: Array = []             ## les appareils de chaque joueur (voir InputBindings)
var pause_menu: PauseMenu                  ## le menu pause, quand il est ouvert
var _resume_grace := 0                     ## en sortant de la pause, on ignore les touches un instant
var _match_over := false
var _match_over_time := 0.0
var _time_engine := TimeEngine.new()
var _duel: Array[Fighter] = []             ## les deux joueurs du micro-duel en cours
var _duel_slowmo := -1                     ## le ralenti du micro-duel en cours (voir TimeEngine.play())
var _stun_focus: Array[Fighter] = []       ## 1 contre 1 : celui qui a sonné et le joueur sonné
var _stun_slowmo := -1                     ## le ralenti lancé pour le joueur sonné (voir TimeEngine.play())
var _break_focus: Array[Fighter] = []      ## arme qui vient de casser : son porteur et celui qui l'a contré
var _break_slowmo := -1                    ## le court ralenti de l'arme cassée (voir TimeEngine.play())
var _shake_left := 0.0                     ## l'écran tremble encore pendant ce temps (vraies secondes)
var _lives_seen: Array[int] = []           ## les vies de chacun à la frame d'avant (pour voir une vie perdue)
var gauge := CounterGauge.new()            ## la jauge de contre, une seule pour tous les joueurs
var online := false                        ## partie en ligne
var _online_state: Array = []              ## (copain) le dernier état du jeu reçu de l'hôte

var map: GameMap
var projectiles: Array[Projectile] = []    ## ce qui vole : lances lancées, balles, grenades
var pickups: Array[ItemPickup] = []        ## les objets tombés sur la map, pas encore ramassés
var rng := RandomNumberGenerator.new()     ## où et quel objet tombe (seul l'hôte tire au sort)
var _item_spawn_timer := ITEM_SPAWN_TIME
var _weapon_spawn_timer := WEAPON_SPAWN_TIME
@onready var _end_screen: Control = $UI/EndScreen
@onready var _winner_label: Label = $UI/EndScreen/Winner
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	online = Online.status == Online.Status.PLAYING
	if online:
		Online.game = self
		$UI/EndScreen/Restart.text = "Start, A ou Entrée : rejouer      B ou Échap : retour au salon" if Online.is_host \
			else "L'hôte peut relancer une partie"
	add_child(_time_engine)
	map = GameSetup.make_map(GameSetup.map_path)
	add_child(map)
	move_child(map, 0)  # le décor est dessiné derrière les joueurs
	InputBindings.register_menu_actions()
	player_devices = GameSetup.devices_or_default().duplicate(true)
	for i in player_devices.size():
		InputBindings.register_player(i, player_devices[i])
		var fighter := Fighter.new()
		fighter.name = "Joueur%d" % (i + 1)
		fighter.player_index = i
		fighter.stats = GameSetup.character_for(i)
		fighter.weapon = GameSetup.weapon_for(i)
		fighter.max_lives = GameSetup.lives
		fighter.lives = GameSetup.lives
		fighter.color = PLAYER_COLORS[i]
		fighter.gauge = gauge
		fighter.input_source = LocalInputSource.new(i)
		if online and Online.players[i].id != Online.my_id:
			# Un copain qui joue depuis un autre ordinateur : chez l'hôte ses touches arrivent par le
			# réseau ; chez les autres copains, il est seulement affiché.
			fighter.input_source = NetworkInputSource.new() if Online.is_host else InputSource.new()
		fighter.position = _feet_to_center(map.spawn_position(i), fighter.stats)
		fighter.facing = 1.0 if fighter.position.x < map.respawn_position().x else -1.0
		add_child(fighter)
		fighter.life_lost.connect(_on_life_lost)
		fighter.weapon_thrown.connect(_on_weapon_thrown)
		fighter.weapon_tossed.connect(_on_weapon_tossed)
		fighter.item_used.connect(_on_item_used)
		fighter.show_lives()
		fighters.append(fighter)
	var gauge_bar := CounterGaugeBar.new()
	gauge_bar.gauge = gauge
	$UI.add_child(gauge_bar)
	$UI.move_child(gauge_bar, 0)  # sous l'écran de fin et le menu pause
	_update_camera(1.0, true)


func _process(delta: float) -> void:
	var real_delta := delta / Engine.time_scale  # la caméra garde sa vitesse pendant un ralenti
	if not _is_online_guest() and not _time_engine.is_playing(_duel_slowmo):
		_duel.clear()  # le ralenti du duel est fini (ou un autre ralenti a pris sa place) : plus de duel
	if not _is_online_guest() and not _time_engine.is_playing(_break_slowmo):
		_break_focus.clear()
	_update_camera(real_delta, false)
	_update_shake(real_delta)


func _physics_process(delta: float) -> void:
	if _is_online_guest():
		_guest_tick()
		_shake_on_life_loss()
		return
	if _match_over:
		_match_over_time += delta
		if _match_over_time > RESTART_DELAY:
			if Input.is_action_just_pressed("restart"):
				if online:
					Online.restart()
				else:
					get_tree().reload_current_scene()
			elif Input.is_action_just_pressed("back_to_menu"):
				if online:
					Online.back_to_lobby()
				else:
					get_tree().change_scene_to_file(GameSetup.exit_scene())
		# Partie finie : plus personne n'est touché, mais une balle arrivée dans un mur (ou une grenade
		# à la fin de sa mèche) ne doit pas rester figée à l'écran.
		for projectile: Projectile in projectiles.duplicate():
			if projectile.finished:
				_remove_projectile(projectile)
		if online:
			Online.send_state(online_state())
		return

	gauge.tick(delta)
	for fighter in fighters:
		fighter.target = _closest_opponent(fighter)
	for fighter in fighters:
		var input := fighter.input_source.poll()
		if pause_menu != null and fighter.input_source is LocalInputSource:
			input = InputState.new()  # en ligne, le jeu continue pendant le menu : le perso ne bouge pas
		if _resume_grace > 0:
			# La touche qui a fermé la pause ne fait pas sauter / frapper. Les touches gardées
			# (charge de la lourde, blocage, saut) restent, pour ne rien lâcher par erreur.
			input.jump_pressed = false
			input.attack_pressed = false
			input.heavy_pressed = false
			input.dash_pressed = false
			input.down_pressed = false
			input.item_pressed = false
		fighter.physics_tick(input, delta)
	_resume_grace -= 1

	_resolve_clashes()
	_resolve_hits()
	_resolve_projectiles()
	_hit_loose_objects()
	_tick_pickups(delta)
	_tick_weapon_spawns(delta)
	_check_blast_zone()
	_update_stun_slowmo()
	_shake_on_life_loss()
	_check_end_of_match()
	if online:
		Online.send_state(online_state())


# --- Jeu en ligne ---

## Je suis un copain (pas l'hôte) dans une partie en ligne.
func _is_online_guest() -> bool:
	return online and not Online.is_host


## (copain) Une frame : j'envoie mes touches à l'hôte et j'affiche le dernier état reçu.
func _guest_tick() -> void:
	var me := Online.my_index()
	if me != -1:
		var input := fighters[me].input_source.poll()
		if pause_menu != null or _match_over:
			input = InputState.new()  # menu ouvert : le perso ne bouge pas
		Online.send_input(input.to_dict())
	for fighter in fighters:
		fighter.target = _closest_opponent(fighter)
	if _online_state.is_empty():
		return
	var state := _online_state
	_online_state = []
	Engine.time_scale = state[0]
	_duel.clear()
	for index in state[1]:
		_duel.append(fighters[index])
	_stun_focus.clear()
	for index in state[4]:
		_stun_focus.append(fighters[index])
	gauge.flash_timer -= get_physics_process_delta_time()
	gauge.set_points(state[5])
	map.apply_moving_state(state[6])
	_apply_projectiles(state[7])
	_apply_pickups(state[8])
	map.apply_window_state(state[9])
	_break_focus.clear()
	for index in state[10]:
		_break_focus.append(fighters[index])
	if state[2] != "" and not _match_over:
		_show_end(state[2], fighters[state[3]].color if state[3] >= 0 else Color.WHITE)
	for i in mini(fighters.size(), state.size() - ONLINE_HEADER):
		fighters[i].apply_net_state(state[ONLINE_HEADER + i])


## (hôte) L'état du jeu envoyé aux copains : vitesse du temps, duel, fin de partie, zoom sur un joueur
## sonné, jauge de contre, plateformes qui bougent, ce qui vole, objets par terre, fenêtres cassées,
## puis chaque joueur.
func online_state() -> Array:
	var duel := []
	for fighter in _duel:
		duel.append(fighters.find(fighter))
	var stun_focus := []
	for fighter in _stun_focus:
		stun_focus.append(fighters.find(fighter))
	var break_focus := []
	for fighter in _break_focus:
		break_focus.append(fighters.find(fighter))
	var winner := -1
	for i in fighters.size():
		if _match_over and not fighters[i].eliminated:
			winner = i
	var state := [Engine.time_scale, duel, _winner_label.text if _match_over else "", winner, stun_focus, gauge.points,
		map.moving_state(), projectiles.map(func(p: Projectile) -> Array: return p.net_state()),
		pickups.map(func(p: ItemPickup) -> Array: return p.net_state()), map.window_state(), break_focus]
	for fighter in fighters:
		state.append(fighter.net_state())
	return state


## (copain) L'hôte a envoyé l'état du jeu : on l'affichera à la prochaine frame.
func receive_online_state(state: Array) -> void:
	if state.size() >= ONLINE_HEADER:
		_online_state = state


## (hôte) Les touches d'un copain sont arrivées.
func receive_online_input(index: int, data: Dictionary) -> void:
	if index >= 0 and index < fighters.size() and fighters[index].input_source is NetworkInputSource:
		(fighters[index].input_source as NetworkInputSource).push(data)


## (hôte) Un copain a quitté la partie : il est éliminé.
func on_online_player_left(index: int) -> void:
	if index < 0 or index >= fighters.size() or fighters[index].eliminated:
		return
	if fighters[index].input_source is NetworkInputSource:
		(fighters[index].input_source as NetworkInputSource).clear()
	fighters[index].forfeit()


## (copain) Un effet visuel envoyé par l'hôte.
func spawn_online_effect(data: Dictionary) -> void:
	match data.get("k", ""):
		"marque":
			_spawn_clash_mark(data.p, false, data.c)
		"explosion":
			_spawn_explosion(data.p, data.c)


## Start (manette), Échap ou P (clavier) : ouvre le menu pause.
func _input(event: InputEvent) -> void:
	if _match_over or pause_menu != null:
		return
	var pause_pressed := false
	if event is InputEventJoypadButton:
		pause_pressed = event.pressed and event.button_index == JOY_BUTTON_START
	elif event is InputEventKey:
		pause_pressed = event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_P]
	if pause_pressed:
		get_viewport().set_input_as_handled()
		open_pause()


func _exit_tree() -> void:
	get_tree().paused = false  # on ne quitte jamais la partie en laissant le jeu en pause


func open_pause() -> void:
	pause_menu = PauseMenu.new()
	pause_menu.game = self
	$UI.add_child(pause_menu)
	if not online:
		get_tree().paused = true  # en ligne, on ne peut pas arrêter le jeu des copains


func close_pause() -> void:
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false
	_resume_grace = 2


## Le joueur contrôlé par cet appareil (-1 si aucun).
func player_of_device(device: Dictionary) -> int:
	for i in player_devices.size():
		if device in player_devices[i]:
			return i
	return -1


## Échange les manettes (ou claviers) de deux joueurs. Gardé pour les prochaines parties.
func swap_devices(a: int, b: int) -> void:
	if a == b:
		return
	var devices_a = player_devices[a]
	player_devices[a] = player_devices[b]
	player_devices[b] = devices_a
	InputBindings.register_player(a, player_devices[a])
	InputBindings.register_player(b, player_devices[b])
	GameSetup.player_devices = player_devices.duplicate(true)


## Cadre tous les joueurs encore en jeu : centre au milieu d'eux, zoom selon leur écart.
## Pendant un micro-duel, la caméra zoome sur les deux duellistes. À 3 ou 4 joueurs, elle garde
## tout le monde à l'écran (personne ne doit sortir du cadre) et se resserre juste un peu.
## En 1 contre 1, tant qu'un joueur est sonné, la caméra serre vite les deux joueurs.
func _update_camera(delta: float, instant: bool) -> void:
	var box := Rect2()
	var first := true
	var one_on_one := _alive_count() <= 2
	var break_zoom := not _break_focus.is_empty() and one_on_one
	var stun_zoom := not break_zoom and not _stun_focus.is_empty() and one_on_one
	var duel_zoom := not break_zoom and not stun_zoom and not _duel.is_empty() and one_on_one
	var framed := _break_focus if break_zoom else _stun_focus if stun_zoom else _duel if duel_zoom else fighters
	for fighter in framed:
		if fighter.eliminated:
			continue
		if first:
			box = Rect2(fighter.global_position, Vector2.ZERO)
			first = false
		else:
			box = box.expand(fighter.global_position)
	if first:
		return
	var view_size := get_viewport_rect().size
	var margin := CAMERA_MARGIN
	var zoom_max := CAMERA_ZOOM_MAX
	var smoothing := CAMERA_SMOOTHING
	if break_zoom:
		margin = WEAPON_BREAK_CAMERA_MARGIN
		zoom_max = WEAPON_BREAK_ZOOM_MAX
		smoothing = STUN_CAMERA_SMOOTHING
	elif stun_zoom:
		margin = STUN_CAMERA_MARGIN
		zoom_max = STUN_ZOOM_MAX
		smoothing = STUN_CAMERA_SMOOTHING
	elif duel_zoom:
		margin = DUEL_CAMERA_MARGIN
		zoom_max = DUEL_ZOOM_MAX
	elif not _duel.is_empty():
		margin = DUEL_GROUP_CAMERA_MARGIN
	var needed := box.size + margin
	var target_zoom := clampf(minf(view_size.x / needed.x, view_size.y / needed.y), CAMERA_ZOOM_MIN, zoom_max)
	var target_position := box.get_center()
	if instant:
		_camera.position = target_position
		_camera.zoom = Vector2.ONE * target_zoom
		return
	var weight := 1.0 - exp(-smoothing * delta)
	_camera.position = _camera.position.lerp(target_position, weight)
	_camera.zoom = _camera.zoom.lerp(Vector2.ONE * target_zoom, weight)


## Une vie perdue (coup ou chute) fait trembler l'écran. On compare les vies de chacun d'une frame
## à l'autre : ça marche aussi chez un copain en ligne, qui reçoit les vies de l'hôte.
func _shake_on_life_loss() -> void:
	for i in mini(fighters.size(), _lives_seen.size()):
		if fighters[i].lives < _lives_seen[i]:
			_shake_left = SHAKE_TIME
	_lives_seen.clear()
	for fighter in fighters:
		_lives_seen.append(fighter.lives)


## L'écran tremble un court instant, de moins en moins fort.
func _update_shake(delta: float) -> void:
	_shake_left = maxf(_shake_left - delta, 0.0)
	var strength := SHAKE_STRENGTH * _shake_left / SHAKE_TIME
	_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength / _camera.zoom.x


## Nombre de joueurs encore en jeu (pas éliminés).
func _alive_count() -> int:
	var count := 0
	for fighter in fighters:
		if not fighter.eliminated:
			count += 1
	return count


func _closest_opponent(fighter: Fighter) -> Fighter:
	var best: Fighter = null
	var best_distance := INF
	for other in fighters:
		if other == fighter or other.eliminated:
			continue
		var d := fighter.global_position.distance_squared_to(other.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	return best


## Deux attaques qui se touchent s'annulent et repoussent les deux joueurs.
## Si une attaque légère contre une attaque lourde, les deux ont une longue recharge et sont repoussés plus loin.
func _resolve_clashes() -> void:
	for i in fighters.size():
		for j in range(i + 1, fighters.size()):
			var a := fighters[i]
			var b := fighters[j]
			if not (a.is_attack_active() and b.is_attack_active()):
				continue
			# Une attaque légère qui part à l'opposé de l'autre joueur ne peut pas faire de choc avec
			# lui (ex. à 3 ou 4 : on frappe devant soi pendant qu'un autre nous frappe dans le dos).
			# Ça couvre aussi deux attaques légères dans le même sens (l'un frappe le dos de l'autre).
			if _points_away(a, b) or _points_away(b, a):
				continue
			var closest := Geometry2D.get_closest_points_between_segments(
				a.attack_start(), a.attack_center(), b.attack_start(), b.attack_center())
			if closest[0].distance_to(closest[1]) > a.attack_radius() + b.attack_radius():
				continue
			_clash(a, b, (closest[0] + closest[1]) / 2.0)


## L'attaque légère de a part-elle à l'opposé de b ?
func _points_away(a: Fighter, b: Fighter) -> bool:
	return not a.is_heavy_attack() and a.attack_direction().dot(b.global_position - a.global_position) <= 0.0


## Les attaques de a et b s'annulent : les deux sont repoussés et une marque apparaît à "where".
## Chacun est repoussé d'autant plus fort que l'autre est lourd (voir CharacterStats.mass()).
## "counterer" : celui qui a contré, quand un seul l'a fait (il a été touché pendant qu'il armait son
## coup vers l'attaquant). Sinon, les deux attaques se sont percutées et chacun a contré l'autre.
## Un contre remplit la jauge de contre (partagée), remet la recharge des attaques à zéro et sort
## de l'état sonné celui qui a contré.
## Légère contre légère : petit temps mort pour celui qui contre ; celui qui est contré attend la
## fin de sa recharge (de quoi riposter).
## Lourde contre lourde : micro-explosion qui éjecte fort les deux joueurs.
## Lourde contrée par une légère : micro-duel, la caméra zoome et le temps ralentit ; celui qui
## a lancé la lourde ne frappe plus pendant 1 s, celui qui a contré peut refrapper tout de suite.
## Pendant un ralenti, chaque contre le fait repartir pour toute sa durée (voir _renew_slowmo).
func _clash(a: Fighter, b: Fighter, where: Vector2, counterer: Fighter = null) -> void:
	var push := _push_dir(a, b)
	var heavy_countered := a.is_heavy_attack() != b.is_heavy_attack()
	var explosion := a.is_heavy_attack() and b.is_heavy_attack()
	var worn: Array[Fighter] = []  # les lourdes contrées : leur arme s'use (voir _wear_weapon)
	var repaired: Array[Fighter] = []  # ceux qui ont contré au coup léger : leur arme se répare
	for fighter in [a, b]:
		if fighter.is_heavy_attack() and not fighter.weapon_away:
			worn.append(fighter)
		elif not fighter.is_heavy_attack() and (counterer == null or fighter == counterer):
			repaired.append(fighter)
	_spawn_clash_mark(where, heavy_countered or explosion)
	gauge.add_counter(heavy_countered or explosion)  # contrer une lourde compte triple
	for fighter in [a, b]:
		if (counterer == null or fighter == counterer) and not (heavy_countered and fighter.is_heavy_attack()):
			fighter.recover()
	if explosion:
		a.clash(push * Fighter.HEAVY_CLASH_PUSH * b.stats.mass(), Fighter.CLASH_LOCKOUT, Fighter.HEAVY_CLASH_LIFT)
		b.clash(-push * Fighter.HEAVY_CLASH_PUSH * a.stats.mass(), Fighter.CLASH_LOCKOUT, Fighter.HEAVY_CLASH_LIFT)
		_spawn_explosion(where, MicroExplosion.DEFAULT_COLOR)
		_renew_slowmo(a, b)
	elif heavy_countered:
		for fighter in [a, b]:
			var other: Fighter = b if fighter == a else a
			var cooldown := Fighter.HEAVY_COUNTERED_COOLDOWN if fighter.is_heavy_attack() else 0.0
			var direction := push if fighter == a else -push
			fighter.clash(direction * Fighter.HEAVY_COUNTER_PUSH * other.stats.mass(), cooldown)
		if _duel.is_empty() or _in_duel(a, b):
			_start_duel(a, b)
		else:
			_renew_slowmo(a, b)  # pendant un duel, pas de 2e duel : il change d'adversaire (ou pas)
	else:
		worn.clear()  # deux légères : pas de lourde contrée
		for fighter in [a, b]:
			var other: Fighter = b if fighter == a else a
			var direction := push if fighter == a else -push
			var cooldown := Fighter.CLASH_LOCKOUT
			if counterer != null and fighter != counterer:
				cooldown = maxf(fighter.attack_cooldown_left(), Fighter.CLASH_LOCKOUT)  # contré : sa recharge continue
			fighter.clash(direction * Fighter.CLASH_PUSH * other.stats.mass(), cooldown)
		_renew_slowmo(a, b)
	for fighter in worn:
		_wear_weapon(fighter, b if fighter == a else a)
	for fighter in repaired:
		fighter.weapon_light_counter()


## Blocage parfait : le défenseur a appuyé sur B pile au moment du coup. C'est un contre :
## les deux sont repoussés, le bouclier ne craque pas, celui qui frappait ne frappe plus
## pendant 1 s et le défenseur peut riposter tout de suite (et n'est plus sonné).
## L'arme de celui qui frappait lui saute des mains (voir _knock_weapon), après s'être usée
## si c'était sa lourde (une arme qui casse ne s'envole pas).
func _parry(attacker: Fighter, defender: Fighter) -> void:
	var push := _push_dir(attacker, defender)
	_spawn_clash_mark((attacker.global_position + defender.global_position) / 2.0, false, PARRY_COLOR)
	var heavy := attacker.is_heavy_attack()
	var armed := not attacker.weapon_away
	gauge.add_counter(heavy)
	defender.recover()
	attacker.clash(push * Fighter.CLASH_PUSH * defender.stats.mass(), Fighter.PARRY_COOLDOWN)
	defender.clash(-push * Fighter.CLASH_PUSH * attacker.stats.mass(), 0.0)
	_renew_slowmo(attacker, defender)
	if heavy and armed and _wear_weapon(attacker, defender):
		return
	_knock_weapon(attacker, push)


## L'arme de "holder" lui saute des mains et part en cloche dans la direction "push" (vers
## l'arrière, loin de celui qui a bloqué). Plus la jauge de contre est haute, plus elle va loin.
## Elle ne fait mal à personne ; son joueur la ramasse en passant dessus (voir _resolve_spear),
## ou la retrouve s'il tombe de la map.
func _knock_weapon(holder: Fighter, push: Vector2) -> void:
	if not holder.knock_weapon_away():
		return
	var speed := lerpf(KNOCKED_SPEED_MIN, KNOCKED_SPEED_MAX, gauge.points / CounterGauge.MAX_POINTS)
	_add_loose_weapon(holder, (push + Vector2(0.0, -KNOCKED_LIFT)).normalized() * speed, -PI / 2.0)


## RB : l'arme part de la main vers l'adversaire le plus proche (devant soi s'il n'y en a pas).
## Elle ne fait mal à personne : un joueur à mains nues l'attrape, un joueur armé la fait rebondir.
func _on_weapon_tossed(fighter: Fighter) -> void:
	var dir := Vector2(fighter.facing, 0.0)
	var target := _closest_opponent(fighter)
	if target != null:
		dir = (target.global_position - fighter.global_position).normalized()
	_add_loose_weapon(fighter, dir * TOSS_SPEED + Vector2(0.0, -TOSS_LIFT), dir.angle())


## Toutes les WEAPON_SPAWN_TIME secondes, une arme au hasard (pas les mains nues) tombe d'un des
## points d'apparition d'armes, s'il n'y en a pas déjà MAX_LOOSE_WEAPONS qui traînent.
## Personne ne la possède : le premier joueur à mains nues qui passe dessus la prend.
func _tick_weapon_spawns(delta: float) -> void:
	_weapon_spawn_timer -= delta
	if _weapon_spawn_timer > 0.0:
		return
	_weapon_spawn_timer = WEAPON_SPAWN_TIME
	var lying := projectiles.filter(func(p: Projectile) -> bool: return p.kind in ["lance", "arme"] and p.state != Projectile.State.FLYING)
	if lying.size() >= MAX_LOOSE_WEAPONS:
		return
	var points := map.weapon_spawn_points()
	spawn_weapon(load(GameSetup.WEAPONS[1 + rng.randi() % (GameSetup.WEAPONS.size() - 1)]), points[rng.randi() % points.size()])


## Une arme neuve, sans propriétaire, qui apparaît à "where" et tombe.
func spawn_weapon(new_weapon: WeaponStats, where: Vector2) -> Projectile:
	var loose := Projectile.new()
	loose.kind = "arme"
	loose.state = Projectile.State.DROPPED
	loose.owner_index = -1
	loose.weapon = new_weapon
	loose.position = where
	loose.color = new_weapon.color
	loose.length = new_weapon.held_length * Projectile.KNOCKED_SCALE
	loose.head = new_weapon.held_head * Projectile.KNOCKED_SCALE
	_add_projectile(loose)
	return loose


## L'arme de "holder" se met à voler, sans danger (elle a sauté des mains, ou il l'a lancée).
func _add_loose_weapon(holder: Fighter, velocity: Vector2, angle: float) -> void:
	var loose := Projectile.new()
	loose.kind = "arme"
	loose.state = Projectile.State.DROPPED
	loose.owner_index = holder.player_index
	loose.weapon = holder.weapon
	loose.counters = holder.weapon_counters
	loose.position = holder.global_position
	loose.velocity = velocity
	loose.rotation = angle
	loose.color = holder.weapon.color
	loose.length = holder.weapon.held_length * holder.weapon_length() * Projectile.KNOCKED_SCALE
	loose.head = holder.weapon.held_head * holder.weapon_length() * Projectile.KNOCKED_SCALE
	_add_projectile(loose)


## La lourde d'une arme a été contrée : l'arme rapetisse, et au 3e contre elle casse (voir
## Fighter.weapon_countered). Casse : éclat de la couleur de l'arme, court ralenti et zoom sur
## les deux joueurs (il prend la place d'un micro-duel en cours). Renvoie true si elle a cassé.
## À mains nues (lance lancée et pas encore ramassée comprise), rien ne s'use.
func _wear_weapon(holder: Fighter, by: Fighter) -> bool:
	if not holder.weapon_countered():
		return false
	_weapon_break_effect(holder.global_position, holder.weapon.color, holder, by)
	return true


func _weapon_break_effect(where: Vector2, color: Color, holder: Fighter, by: Fighter) -> void:
	_spawn_explosion(where, color)
	_break_focus = [holder, by]
	_break_slowmo = _time_engine.play(WEAPON_BREAK_TIME_SCALE, WEAPON_BREAK_SLOWMO, false)


## Un contre relance le ralenti en cours pour toute sa durée. Pendant un micro-duel, il faut
## qu'un des deux duellistes soit dans le contre : un contre entre deux autres joueurs ne
## prolonge pas le duel. Si un duelliste contre un autre joueur, ce joueur prend la place de
## l'ancien adversaire, qui redevient un joueur normal.
func _renew_slowmo(a: Fighter, b: Fighter) -> void:
	if not _duel.is_empty():
		if not a in _duel and not b in _duel:
			return
		if not _in_duel(a, b):
			_duel = [a, b]
	_time_engine.renew()


func _in_duel(a: Fighter, b: Fighter) -> bool:
	return a in _duel and b in _duel


## Direction (horizontale) qui éloigne a de b.
func _push_dir(a: Fighter, b: Fighter) -> Vector2:
	var push := a.global_position - b.global_position
	push.y = 0.0
	if push.length() < 1.0:
		return Vector2(-1.0, 0.0)
	return push.normalized()


## Micro-duel : la caméra serre les deux joueurs et le jeu ralentit pendant quelques secondes.
func _start_duel(a: Fighter, b: Fighter) -> void:
	_duel = [a, b]
	_duel_slowmo = _time_engine.play(DUEL_TIME_SCALE, DUEL_DURATION)


## Un duelliste touché ou tombé : le duel est tranché, le temps revient à la normale.
func _on_life_lost(fighter: Fighter) -> void:
	if fighter in _duel:
		_time_engine.stop()


## Laisse une marque sur le terrain à l'endroit du contre (orange si une attaque lourde a été contrée,
## bleu clair pour un blocage parfait).
func _spawn_clash_mark(where: Vector2, heavy_countered: bool, color := Color.TRANSPARENT) -> void:
	var mark := ClashMark.new()
	mark.position = where
	if color == Color.TRANSPARENT:
		color = Color(1.0, 0.6, 0.2) if heavy_countered else Color(1, 1, 1)
	mark.color = color
	add_child(mark)
	if online and Online.is_host:
		Online.send_effect({"k": "marque", "p": where, "c": color})


func _spawn_explosion(where: Vector2, color: Color) -> void:
	var boom := MicroExplosion.new()
	boom.color = color
	boom.position = where
	add_child(boom)
	if online and Online.is_host:
		Online.send_effect({"k": "explosion", "p": where, "c": color})


## On repère d'abord tous les coups de la frame, puis on les applique : si deux joueurs se
## touchent exactement en même temps, c'est un choc, les deux attaques s'annulent et personne ne perd de vie.
## Un coup qui touche sonne d'abord ; c'est le coup suivant, pendant qu'on est sonné, qui retire une vie.
func _resolve_hits() -> void:
	# Qui chaque attaque touche-t-elle ?
	var reached := {}
	for attacker in fighters:
		if not attacker.is_attack_active():
			continue
		for window in map.windows():  # un coup casse les fenêtres qu'il frappe
			if not window.broken and _segment_hits_rect(
					attacker.attack_start(), attacker.attack_center(), attacker.attack_radius(), window.rect()):
				window.smash()
		reached[attacker] = []
		for victim in fighters:
			if victim != attacker and victim.can_be_hit() and _segment_hits_rect(
					attacker.attack_start(), attacker.attack_center(), attacker.attack_radius(), victim.body_rect()):
				reached[attacker].append(victim)
	# Une attaque touche un seul joueur : de préférence celui qui la frappe en retour (c'est alors
	# un choc), sinon le premier. Ainsi, à 3 ou 4, l'ordre des joueurs ne change rien.
	var landed: Array[Dictionary] = []
	for attacker in reached:
		var victims: Array = reached[attacker]
		if victims.is_empty():
			continue
		var victim: Fighter = victims[0]
		for other in victims:
			if reached.has(other) and attacker in reached[other]:
				victim = other
				break
		var hit_dir: Vector2 = (victim.global_position - attacker.global_position).normalized()
		if not attacker.is_heavy_attack():
			hit_dir = attacker.attack_direction()
		landed.append({"attacker": attacker, "victim": victim, "dir": hit_dir,
			"knockback": attacker.attack_knockback(), "heavy": attacker.is_heavy_attack()})
	# Deux joueurs qui se touchent l'un l'autre : choc, leurs deux coups sont annulés.
	var clashed: Array[Fighter] = []
	for hit in landed:
		for other in landed:
			if other.attacker == hit.victim and other.victim == hit.attacker and not hit.attacker in clashed:
				clashed.append(hit.attacker)
				clashed.append(hit.victim)
				_clash(hit.attacker, hit.victim, (hit.attacker.global_position + hit.victim.global_position) / 2.0)
	# Les autres coups touchent tous, même si leur auteur est lui-même touché à la même frame
	# (à 3 ou 4 joueurs, l'ordre des joueurs ne doit pas décider qui touche).
	for hit in landed:
		var attacker: Fighter = hit.attacker
		var victim: Fighter = hit.victim
		if attacker in clashed:
			continue
		if not victim.can_be_hit():
			continue  # déjà touché cette frame par quelqu'un d'autre
		if victim.is_item_shielded():
			_bounce_off_item_shield(attacker, victim)
			continue
		if victim.is_parrying():
			_parry(attacker, victim)
			continue
		if victim.is_blocking() and not victim.is_stunned():  # sonné, le bouclier ne protège plus
			_hit_shield(attacker, victim, hit.heavy)
			continue
		if _counters(victim, attacker):
			_clash(attacker, victim, (attacker.global_position + victim.global_position) / 2.0, victim)
			continue
		attacker.mark_attack_hit()
		victim.take_hit(hit.dir, hit.knockback)
		if victim.is_stunned() and _alive_count() == 2:
			_stun_focus = [attacker, victim]


## Le coup de l'attaquant arrive pendant que la victime arme (ou donne) une attaque légère vers lui :
## c'est un contre. On a donc le temps de voir le coup partir et d'y répondre.
func _counters(victim: Fighter, attacker: Fighter) -> bool:
	return victim.is_light_attack_under_way() and not _points_away(victim, attacker)


## En 1 contre 1, tant qu'un joueur est sonné : la caméra serre les deux joueurs et le temps ralentit
## un peu, le temps de voir s'il va contrer ou se faire sortir. Ça s'arrête quand il n'est plus
## sonné (fin du temps, contre, blocage parfait, ou vie perdue). Un ralenti plus fort (micro-duel,
## bouclier cassé) passe avant, et celui-ci reprend après si le joueur est encore sonné.
func _update_stun_slowmo() -> void:
	if _stun_focus.is_empty() or not (_stun_focus[0].is_stunned() or _stun_focus[1].is_stunned()) or _alive_count() != 2:
		_stun_focus.clear()
		if _time_engine.is_playing(_stun_slowmo):
			_time_engine.stop()
		return
	# Pas de ralenti en cours, ou le nôtre était en train de s'arrêter (resonné juste après) : il (re)part.
	if not _time_engine.is_active() or (_time_engine.is_playing(_stun_slowmo) and _time_engine.is_stopping()):
		# Assez long pour toute la durée sonné ; un contre ne le relance pas, il s'arrête juste avant.
		_stun_slowmo = _time_engine.play(STUN_TIME_SCALE, Fighter.STUN_TIME / STUN_TIME_SCALE + 0.5, false)


## Le coup tombe sur un bouclier : personne ne perd de vie, l'attaquant est repoussé mais peut
## refrapper tout de suite, et le bouclier craque un peu plus (2 fois plus pour une attaque lourde).
## S'il casse : ralenti, les deux joueurs sont éjectés, et celui qui l'a perdu ne frappe plus 2 s.
func _hit_shield(attacker: Fighter, victim: Fighter, heavy: bool) -> void:
	var push := victim.global_position - attacker.global_position
	push.y = 0.0
	push = push.normalized() if push.length() > 1.0 else Vector2(attacker.facing, 0.0)
	attacker.hit_shield(-push)
	if not victim.absorb_hit(push, attacker.shield_damage(heavy)):
		return
	_spawn_clash_mark(victim.global_position, true)
	victim.shield_burst(push, true)
	attacker.shield_burst(-push, false)
	_spawn_explosion(victim.global_position, Color(0.75, 0.9, 1.0))
	if _duel.is_empty():
		_time_engine.play(SHIELD_BREAK_TIME_SCALE, SHIELD_BREAK_SLOWMO)
	else:
		_renew_slowmo(attacker, victim)  # avec un duelliste, le duel continue (et repart pour toute sa durée)


## Un segment épais (de a à b, d'épaisseur radius de chaque côté) touche-t-il le rectangle ?
func _segment_hits_rect(a: Vector2, b: Vector2, radius: float, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	for corner in corners:
		if Geometry2D.get_closest_point_to_segment(corner, a, b).distance_to(corner) <= radius:
			return true
	for end in [a, b]:
		if end.distance_to(end.clamp(rect.position, rect.end)) <= radius:
			return true
	return false


## Les points d'apparition d'une map marquent les PIEDS du perso : un grand perso
## apparaît donc posé au même endroit qu'un petit, jamais enfoncé dans le sol.
func _feet_to_center(feet: Vector2, stats: CharacterStats) -> Vector2:
	return feet - Vector2(0.0, stats.body_size.y / 2.0)


func _check_blast_zone() -> void:
	for fighter in fighters:
		if not fighter.eliminated and not map.blast_zone.has_point(fighter.global_position):
			fighter.fall_out(_feet_to_center(map.respawn_position(), fighter.stats))  # sans rendre l'arme perdue


func _check_end_of_match() -> void:
	var alive: Array[Fighter] = []
	for fighter in fighters:
		if not fighter.eliminated:
			alive.append(fighter)
	if alive.size() > 1:
		return
	_match_over = true
	_match_over_time = 0.0
	_duel.clear()
	_time_engine.stop(true)
	if alive.size() == 1:
		_show_end("Joueur %d gagne !" % (alive[0].player_index + 1), alive[0].color)
	else:
		_show_end("Égalité !", Color.WHITE)


func _show_end(text: String, color: Color) -> void:
	_match_over = true
	_winner_label.text = text
	_winner_label.add_theme_color_override("font_color", color)
	_end_screen.visible = true


# --- Lances lancées ---

## Un joueur lance sa lance (attaque lourde de la lance) : elle part de sa main vers l'adversaire.
func _on_weapon_thrown(fighter: Fighter, direction: Vector2, speed: float) -> void:
	var spear := Projectile.new()
	spear.owner_index = fighter.player_index
	spear.position = fighter.global_position + direction * 20.0
	spear.velocity = direction * speed + Vector2(0.0, -Projectile.THROW_LIFT)
	spear.rotation = direction.angle()
	spear.knockback = fighter.attack_knockback()
	spear.color = fighter.weapon.color
	spear.length = Projectile.SPEAR_LENGTH * fighter.weapon_length()
	spear.weapon = fighter.weapon
	spear.counters = fighter.weapon_counters
	_add_projectile(spear)


func _add_projectile(projectile: Projectile) -> void:
	projectiles.append(projectile)
	add_child(projectile)


func _remove_projectile(projectile: Projectile) -> void:
	projectiles.erase(projectile)
	projectile.queue_free()


## Ce qui vole : les lances et les balles touchent le premier joueur sur leur chemin, les
## grenades explosent au bout de leur mèche. Un coup peut renvoyer une balle ou repousser une grenade.
## Une lance posée est ramassée par le premier joueur à mains nues qui passe dessus ; sortie de
## la map, elle est perdue.
func _resolve_projectiles() -> void:
	for projectile: Projectile in projectiles.duplicate():
		if not projectile in projectiles:
			continue  # déjà retirée (lance revenue à son lanceur)
		match projectile.kind:
			"balle":
				_resolve_bullet(projectile)
			"grenade":
				_resolve_grenade(projectile)
			_:
				_resolve_spear(projectile)


func _resolve_spear(projectile: Projectile) -> void:
	if not map.blast_zone.has_point(projectile.position):
		_remove_projectile(projectile)  # sortie de la map : perdue (il faudra trouver une autre arme)
		return
	if projectile.state != Projectile.State.FLYING:
		_resolve_loose_weapon(projectile)
		return
	var thrower: Fighter = fighters[projectile.owner_index]
	for fighter in fighters:
		if fighter != thrower and fighter.is_attack_active() and _projectile_in_attack(projectile, fighter):
			_counter_spear(projectile, fighter)
			return
	var victim := _projectile_victim(projectile)
	if victim == null:
		return
	if victim.is_parrying():
		_counter_spear(projectile, victim)
		return
	if victim.is_item_shielded() or not victim.can_be_hit():
		projectile.drop()  # bouclier ramassé, ou joueur invincible : la lance retombe sans rien faire
		return
	_projectile_hits(projectile, victim, Fighter.HEAVY_SHIELD_DAMAGE)
	projectile.drop()


## Une arme qui traîne ou vole sans danger : le premier joueur à mains nues qui la touche la prend
## (en vol aussi). Celui qui vient de la lâcher ou de la lancer ne la rattrape pas tout de suite.
## Un joueur armé fait rebondir une arme qui vole vers lui.
func _resolve_loose_weapon(loose: Projectile) -> void:
	for fighter in fighters:
		if fighter.eliminated or not fighter.body_rect().grow(12.0).has_point(loose.position):
			continue
		if fighter.player_index == loose.owner_index and loose.age < KNOCKED_PICKUP_DELAY:
			continue
		if not fighter.has_weapon_in_hand():
			_pick_up_weapon(fighter, loose)
			return
		if not loose.body.resting and loose.hit_lock <= 0.0 and loose.velocity.length() > WEAPON_BOUNCE_SPEED:
			var away := signf(loose.position.x - fighter.global_position.x)
			loose.launch(Vector2((away if away != 0.0 else 1.0) * absf(loose.velocity.x) * 0.5, -250.0))


## Un joueur à mains nues prend l'arme (la sienne ou celle d'un autre, avec son usure).
func _pick_up_weapon(fighter: Fighter, loose: Projectile) -> void:
	if loose.weapon != null:
		fighter.equip(loose.weapon, loose.counters)
	_remove_projectile(loose)


## Lance lancée contrée (frappée en vol, ou blocage parfait) : c'est un contre de lourde (compte
## triple), celui qui contre peut refrapper tout de suite. La lance retombe, plus courte ;
## contrée pour la 3e fois, elle se casse (voir _wear_weapon).
func _counter_spear(spear: Projectile, counterer: Fighter) -> void:
	var thrower: Fighter = fighters[spear.owner_index]
	if counterer.is_attack_active():
		counterer.mark_attack_hit()
		if not counterer.is_heavy_attack():
			counterer.weapon_light_counter()  # contre au coup léger : l'arme se répare
	counterer.recover()
	counterer.reset_cooldown()
	gauge.add_counter(true)
	_spawn_clash_mark(spear.tip(), true, PARRY_COLOR if counterer.is_parrying() else Color.WHITE)
	_renew_slowmo(counterer, thrower)
	spear.counters += 1
	if thrower.weapon_away and thrower.weapon == spear.weapon:
		thrower.weapon_counters = spear.counters  # c'est encore son arme : elle s'use pour lui aussi
	if spear.counters >= Fighter.WEAPON_MAX_COUNTERS:
		_weapon_break_effect(spear.position, spear.color, thrower, counterer)
		_remove_projectile(spear)
		return
	spear.length = Projectile.SPEAR_LENGTH * (1.0 - Fighter.WEAPON_SHRINK * spear.counters)
	spear.drop()


## Une balle : renvoyée par un coup bien placé, sinon elle touche le premier joueur sur son chemin.
func _resolve_bullet(bullet: Projectile) -> void:
	if bullet.finished or not map.blast_zone.has_point(bullet.position):
		_remove_projectile(bullet)
		return
	for fighter in fighters:
		if fighter.player_index != bullet.owner_index and fighter.is_attack_active() and _projectile_in_attack(bullet, fighter):
			_deflect_bullet(bullet, fighter)
			return
	var victim := _projectile_victim(bullet)
	if victim == null:
		return
	if victim.is_item_shielded():
		bullet.velocity = -bullet.velocity  # le bouclier ramassé renvoie la balle
		bullet.rotation = bullet.velocity.angle()
		bullet.owner_index = victim.player_index
		return
	if not victim.can_be_hit():
		_remove_projectile(bullet)  # joueur invincible (il clignote) : la balle s'arrête sur lui, sans effet
		return
	_projectile_hits(bullet, victim, 1)
	_remove_projectile(bullet)


## Renvoi de balle, selon le TIMING : frappée pile quand le coup sort (dans les DEFLECT_PERFECT
## premières secondes), elle repart droit sur le tireur. Plus le coup était déjà avancé, plus elle
## est déviée (jusqu'à DEFLECT_MAX_ANGLE à la toute fin du coup), toujours vers le haut.
## Un renvoi parfait compte comme un contre.
func _deflect_bullet(bullet: Projectile, deflector: Fighter) -> void:
	deflector.mark_attack_hit()  # le coup est « utilisé » par la balle
	var shooter: Fighter = fighters[bullet.owner_index]
	var back := -bullet.velocity.normalized()
	if not shooter.eliminated:
		back = (shooter.global_position - bullet.position).normalized()
	var error := deflector.attack_time_since_active() - DEFLECT_PERFECT
	var window := maxf(deflector.attack_active_duration() - DEFLECT_PERFECT, 0.001)
	var angle := deg_to_rad(DEFLECT_MAX_ANGLE) * clampf(error / window, 0.0, 1.0)
	var up := back.rotated(angle)
	var down := back.rotated(-angle)
	var dir := up if up.y <= down.y else down
	bullet.velocity = dir * bullet.velocity.length() * DEFLECT_SPEED
	bullet.rotation = dir.angle()
	bullet.owner_index = deflector.player_index
	var perfect := error <= 0.0
	_spawn_clash_mark(bullet.position, false, PARRY_COLOR if perfect else Color.WHITE)
	if perfect:
		gauge.add_counter(false)
		deflector.recover()
		deflector.reset_cooldown()


## Une grenade : un coup la décolle et la repousse ; au bout de sa mèche, elle explose.
func _resolve_grenade(grenade: Projectile) -> void:
	if not map.blast_zone.has_point(grenade.position):
		_remove_projectile(grenade)
		return
	if grenade.finished:
		_explode(grenade.position, GRENADE_KNOCKBACK * grenade.blast)
		_remove_projectile(grenade)
		return
	for fighter in fighters:
		if fighter.is_attack_active() and _projectile_in_attack(grenade, fighter):
			fighter.mark_attack_hit()
			grenade.unstick()
			grenade.velocity = fighter.attack_direction() * GRENADE_HIT_SPEED + Vector2(0.0, -300.0)
			return


## L'explosion d'une grenade : tous ceux qui sont dans le rayon (le lanceur aussi) sont touchés
## et éjectés loin du centre. Un bouclier la bloque (et craque beaucoup).
## Les objets et armes par terre dans le rayon sont soufflés.
func _explode(where: Vector2, knockback := GRENADE_KNOCKBACK) -> void:
	_spawn_explosion(where, Color(1.0, 0.55, 0.2))
	map.smash_windows_in(where, GRENADE_RADIUS)
	for loose: Node2D in _loose_objects():
		var away := loose.position - where
		if away.length() <= GRENADE_RADIUS:
			var dir := (away.normalized() if away.length() > 1.0 else Vector2.UP) + Vector2(0.0, -0.5)
			loose.launch(dir.normalized() * LOOSE_BLAST_SPEED)
	for fighter in fighters:
		if fighter.eliminated or fighter.is_invincible() or fighter.is_item_shielded():
			continue
		var body := fighter.body_rect()
		if where.clamp(body.position, body.end).distance_to(where) > GRENADE_RADIUS:
			continue
		var away := fighter.global_position - where
		var dir := (away.normalized() if away.length() > 1.0 else Vector2.UP) + Vector2(0.0, -0.4)
		if fighter.is_blocking() and not fighter.is_stunned():
			var push := Vector2(signf(away.x) if away.x != 0.0 else 1.0, 0.0)
			if fighter.absorb_hit(push, GRENADE_SHIELD_DAMAGE):
				fighter.shield_burst(push, true)
			continue
		fighter.take_hit(dir.normalized(), knockback)
		if fighter.is_stunned() and _alive_count() == 2:
			_stun_focus = [fighter, _closest_opponent(fighter)]  # sonné par la grenade : zoom et ralenti aussi


## Le joueur qu'un objet en vol touche (pas son lanceur), ou null. Celui qui esquive (dash) le
## laisse passer ; un joueur invincible l'arrête, mais sans effet (voir _resolve_bullet) : avant,
## la balle le traversait lentement pendant les ralentis et semblait coincée dans le perso.
func _projectile_victim(projectile: Projectile) -> Fighter:
	for victim in fighters:
		if victim.player_index != projectile.owner_index and not victim.eliminated and not victim.is_dodging() and _segment_hits_rect(
				projectile.tail(), projectile.tip(), Projectile.RADIUS, victim.body_rect()):
			return victim
	return null


## La zone qui touche du coup de "fighter" passe-t-elle sur l'objet en vol ?
func _projectile_in_attack(projectile: Projectile, fighter: Fighter) -> bool:
	var closest := Geometry2D.get_closest_points_between_segments(
		fighter.attack_start(), fighter.attack_center(), projectile.tail(), projectile.tip())
	return closest[0].distance_to(closest[1]) <= fighter.attack_radius() + Projectile.RADIUS


## Un objet en vol touche un joueur : blocage parfait (un contre), bouclier (qui craque),
## ou coup reçu (sonné, ou une vie en moins si on l'était déjà).
func _projectile_hits(projectile: Projectile, victim: Fighter, shield_damage: int) -> void:
	var thrower: Fighter = fighters[projectile.owner_index]
	var dir := projectile.velocity.normalized()
	if victim.is_parrying():
		victim.recover()
		victim.reset_cooldown()
		gauge.add_counter(false)
		_spawn_clash_mark(projectile.tip(), false, PARRY_COLOR)
	elif victim.is_blocking() and not victim.is_stunned():
		var push := Vector2(signf(dir.x) if dir.x != 0.0 else 1.0, 0.0)
		if victim.absorb_hit(push, shield_damage * thrower.shield_damage(false)):
			_spawn_clash_mark(victim.global_position, true)
			victim.shield_burst(push, true)
	else:
		victim.take_hit(dir, projectile.knockback)
		if victim.is_stunned() and _alive_count() == 2:
			_stun_focus = [thrower, victim]


## Le coup tombe sur le bouclier ramassé : personne n'est touché, l'attaquant est projeté très loin
## et ne peut plus frapper un instant.
func _bounce_off_item_shield(attacker: Fighter, victim: Fighter) -> void:
	var push := _push_dir(attacker, victim)
	_spawn_clash_mark((attacker.global_position + victim.global_position) / 2.0, false, ItemPickup.color_of("bouclier"))
	attacker.clash(push * Fighter.ITEM_SHIELD_PUSH * victim.stats.mass(), Fighter.ITEM_SHIELD_COOLDOWN, 250.0)


# --- Objets ---

## Un objet utilisé : une balle tirée, ou une grenade lancée (ou lâchée, ou qui explose en main).
func _on_item_used(fighter: Fighter, kind: String, direction: Vector2, power: float, fuse: float) -> void:
	var projectile := Projectile.new()
	projectile.kind = kind
	projectile.owner_index = fighter.player_index
	projectile.position = fighter.global_position
	match kind:
		"balle":
			# Canon collé à un mur : la balle s'y arrête tout de suite (sinon elle partirait de
			# l'intérieur du mur et le traverserait).
			var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(
				fighter.global_position, fighter.global_position + direction * (24.0 + 8.0), 1))
			if not wall.is_empty():
				if wall.collider is BreakableWindow:
					(wall.collider as BreakableWindow).smash()
				projectile.free()
				return
			projectile.position += direction * 24.0
			projectile.velocity = direction * BULLET_SPEED
			projectile.rotation = direction.angle()
			projectile.length = 16.0
			projectile.knockback = BULLET_KNOCKBACK
			projectile.color = Color(1.0, 0.9, 0.5)
		"grenade":
			if fuse <= 0.0:
				_explode(fighter.global_position)  # gardée trop longtemps : elle explose en main
				return
			projectile.fuse = fuse
			projectile.length = 18.0
			projectile.color = ItemPickup.color_of("grenade")
			projectile.blast = lerpf(1.0, GRENADE_MAX_POWER, power)
			if direction != Vector2.ZERO:
				# Lancée vers l'adversaire : plus RT a été gardé, plus elle part loin, vite et fort.
				var lob := (direction + Vector2(0.0, -GRENADE_LOB)).normalized()
				projectile.velocity = lob * lerpf(GRENADE_MIN_THROW, GRENADE_MAX_THROW, power)
	_add_projectile(projectile)


## Toutes les ITEM_SPAWN_TIME secondes, un objet tiré au sort apparaît à un des points prévus
## par la map et tombe jusqu'à ce qu'il y a dessous. On le ramasse en passant dessus (si on n'a pas déjà un objet).
## Ce qui traîne sans danger sur la map : objets pas encore ramassés, lances retombées ou
## plantées, armes qui ont sauté des mains.
func _loose_objects() -> Array[Node2D]:
	var list: Array[Node2D] = []
	list.append_array(pickups)
	for projectile in projectiles:
		if projectile.kind in ["lance", "arme"] and projectile.state != Projectile.State.FLYING:
			list.append(projectile)
	return list


## Un coup qui passe sur un objet ou une arme par terre le fait valdinguer dans le sens du coup,
## d'autant plus loin que le coup pousse fort. Le coup continue (il peut aussi toucher un joueur).
func _hit_loose_objects() -> void:
	for fighter in fighters:
		if fighter.eliminated or not fighter.is_attack_active():
			continue
		for loose: Node2D in _loose_objects():
			if loose.hit_lock > 0.0 or not _loose_in_attack(loose, fighter):
				continue
			var speed := fighter.attack_knockback() * LOOSE_HIT_SPEED
			loose.launch(fighter.attack_direction() * speed + Vector2(0.0, -LOOSE_HIT_LIFT))


func _loose_in_attack(loose: Node2D, fighter: Fighter) -> bool:
	if loose is Projectile:
		return _projectile_in_attack(loose, fighter)
	var closest := Geometry2D.get_closest_point_to_segment(loose.position, fighter.attack_start(), fighter.attack_center())
	return closest.distance_to(loose.position) <= fighter.attack_radius() + ItemPickup.SIZE / 2.0


func _tick_pickups(delta: float) -> void:
	_item_spawn_timer -= delta
	if _item_spawn_timer <= 0.0:
		_item_spawn_timer = ITEM_SPAWN_TIME
		if pickups.size() < MAX_PICKUPS:
			var points := map.item_spawn_points()
			spawn_pickup(ItemPickup.KINDS[rng.randi() % ItemPickup.KINDS.size()], points[rng.randi() % points.size()])
	for pickup: ItemPickup in pickups.duplicate():
		if not map.blast_zone.has_point(pickup.position):
			_remove_pickup(pickup)
			continue
		for fighter in fighters:
			if not fighter.eliminated and fighter.body_rect().intersects(pickup.rect()) and fighter.take_item(pickup.kind):
				_remove_pickup(pickup)
				break


func spawn_pickup(kind: String, where: Vector2) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.kind = kind
	pickup.position = where
	pickups.append(pickup)
	add_child(pickup)
	return pickup


func _remove_pickup(pickup: ItemPickup) -> void:
	pickups.erase(pickup)
	pickup.queue_free()


## (copain) Les objets par terre reçus de l'hôte.
func _apply_pickups(list: Array) -> void:
	while pickups.size() > list.size():
		_remove_pickup(pickups[-1])
	while pickups.size() < list.size():
		var pickup := spawn_pickup("pistolet", Vector2.ZERO)
		pickup.simulate = false
	for i in list.size():
		pickups[i].apply_net_state(list[i])


## (copain) Les lances reçues de l'hôte : on en crée ou on en retire pour avoir les mêmes.
func _apply_projectiles(list: Array) -> void:
	while projectiles.size() > list.size():
		_remove_projectile(projectiles[-1])
	while projectiles.size() < list.size():
		var projectile := Projectile.new()
		projectile.simulate = false
		_add_projectile(projectile)
	for i in list.size():
		projectiles[i].apply_net_state(list[i])
