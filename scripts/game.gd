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
const CHUNK_SHIELD_DAMAGE := 6               ## Ville : un gros morceau qui tombe sur un bouclier
const CHUNK_KNOCKBACK := 900.0               ## Ville : ... et sur quelqu'un qui ne bloque pas
const BEACON_FIRST_TIME := 5.0               ## Ville : la première balise d'appel tombe au bout de 5 s...
const BEACON_SPAWN_TIME := 20.0              ## ... puis une toutes les 20 s, tant qu'il y a moins de mechas que de joueurs
const MECHA_SHOCK_PUSH := 1100.0             ## Ville : un mecha qui se pose repousse tout le monde autour...
const MECHA_SHOCK_LIFT := 380.0              ## ... en les soulevant un peu...
const MECHA_SHOCK_BLOCK_DAMAGE := 2          ## ... et abîme les blocs de la ville dans le rayon (sans casser le toit où il se pose)
# Ville : ce qui use un mecha (il a Mecha.WEAR_MAX points de solidité)
const MECHA_WEAR_LIGHT := 1                  ## coup léger d'un joueur à pied
const MECHA_WEAR_HEAVY := 3                  ## coup lourd
const MECHA_WEAR_BULLET := 1                 ## balle (pistolet ou rafale de mecha)
const MECHA_WEAR_ARROW := 2
const MECHA_WEAR_SPEAR := 3
const MECHA_WEAR_GRENADE := 4                ## explosion de grenade
const MECHA_WEAR_ROCKET := [5, 7]            ## roquette : non chargée, chargée à fond
const MECHA_WEAR_CHUNK := 8                  ## gros morceau d'immeuble
const MECHA_WEAR_PUNCH := 3                  ## coup de poing d'un autre mecha
const MECHA_WEAR_BLAST := 4                  ## un mecha qui explose use ceux d'à côté
const MECHA_BLAST_RADIUS := 230.0            ## l'explosion d'un mecha : rayon (blocs, mechas, joueurs repoussés)
const MECHA_BLAST_PUSH := 1000.0
const PUNCH_KNOCKBACK := 1300.0               ## coup de poing de mecha sur un joueur à pied (comme une grosse lourde)
const PUNCH_BLOCK_DAMAGE := 2                 ## ... et sur les blocs de la ville
const MECHA_WEAR_ULT_LASER := 10             ## ultimes en mecha : le grand laser de Barre (et il gèle 3 s)...
const MECHA_WEAR_ULT_WAVE := 8                ## ... l'onde de Jumb (et elle repousse)...
const MECHA_WEAR_ULT_BOLT := 5                ## ... chaque traversée de Jib
const ULT_WAVE_PUSH := 1400.0                 ## l'onde de Jumb repousse les mechas...
const ULT_WAVE_KNOCKBACK := 1900.0            ## ... et projette très loin ceux qui sont à pied
const ULT_WAVE_BLOCK_DAMAGE := 3
const ULT_BOLT_KNOCKBACK := 900.0
const MECHA_PARRY_PUSH := 900.0               ## mecha dont le coup est bloqué parfaitement : repoussé
const MECHA_BULLET_SPEED := 2100.0           ## les balles de la rafale vont plus vite que celles du pistolet
const ROCKET_SPEED := [950.0, 1500.0]        ## roquette : non chargée, chargée à fond
const ROCKET_RADIUS := [110.0, 160.0]        ## rayon de son explosion
const ROCKET_KNOCKBACK := [1000.0, 1350.0]
const ROCKET_CANCEL_BULLETS := 3             ## balles adverses pour annuler une roquette en vol
const MECHA_LASER_RANGE := [900.0, 1600.0]    ## canon laser de mecha : non chargé, chargé à fond
const MECHA_WEAR_LASER := [6, 8]
const MECHA_LASER_BLOCKS := 2                 ## il traverse et casse jusqu'à 2 blocs de la ville, puis s'arrête
const MECHA_LASER_BULLETS := 3                ## ... il efface les balles sur son chemin et s'arrête à la 3e
const MECHA_LASER_KNOCKBACK := 1100.0
const MECHA_LASER_RADIUS := 14.0
const MISSILE_SPEED := 950.0                  ## missiles de mecha (objet) : ils suivent l'ennemi le plus proche...
const MISSILE_RADIUS := 75.0                  ## ... et font une petite explosion
const MISSILE_KNOCKBACK := 900.0
const MECHA_WEAR_MISSILE := 3
const LAUNCHER_ROCKET_SPEED := 1300.0         ## la roquette du lance-roquette (à pied) : grosse mais esquivable
const ITEM_TOSS_LOCK := 0.6                   ## arme à 2 mains jetée : son lanceur ne la reprend pas avant ce temps
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
const ARROW_CLOSE_COUNTER := 220.0         ## flèche contrée à moins de cette distance du tireur : l'arc s'use (comme une lourde contrée)
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
var _ultimate_test := false                ## ?ultime=plein dans l'adresse : jauges d'ultime toujours pleines
var _online_state: Array = []              ## (copain) le dernier état du jeu reçu de l'hôte

var map: GameMap
var projectiles: Array[Projectile] = []    ## ce qui vole : lances lancées, balles, grenades
var pickups: Array[ItemPickup] = []        ## les objets tombés sur la map, pas encore ramassés
var mechas: Array[Mecha] = []              ## Ville : les mechas appelés (pilotés, vides, ou en train d'arriver)
var _beacon_timer := BEACON_FIRST_TIME
var rng := RandomNumberGenerator.new()     ## où et quel objet tombe (seul l'hôte tire au sort)
var _item_spawn_timer := ITEM_SPAWN_TIME
var _weapon_spawn_timer := WEAPON_SPAWN_TIME
var _bow_count := 0                     ## pour donner un numéro à chaque arc (voir _new_bow_id)
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
	_ultimate_test = _ultimate_full_for_tests()
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
		fighter.arrow_shot.connect(_on_arrow_shot)
		fighter.weapon_tossed.connect(_on_weapon_tossed)
		fighter.item_used.connect(_on_item_used)
		fighter.item_tossed.connect(_on_item_tossed)
		fighter.grapple_parried.connect(_on_grapple_parried)
		fighter.ultimate_used.connect(_on_ultimate_used)
		if _ultimate_test:
			fighter.ultimate_points = Fighter.ULTIMATE_POINTS
		fighter.bow_id = _new_bow_id()
		fighter.show_lives()
		fighters.append(fighter)
	var gauge_bar := CounterGaugeBar.new()
	gauge_bar.gauge = gauge
	$UI.add_child(gauge_bar)
	$UI.move_child(gauge_bar, 0)  # sous l'écran de fin et le menu pause
	_update_camera(1.0, true)


## Pour essayer l'ultime sans faire 20 contres : https://bbstain.github.io/jvtest/?ultime=plein
## (hors ligne, les jauges d'ultime sont toujours pleines).
func _ultimate_full_for_tests() -> bool:
	if online or not OS.has_feature("web"):
		return false
	return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('ultime') || ''")) == "plein"


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
	_tick_mechas(delta)

	_resolve_clashes()
	_resolve_hits()
	_resolve_mecha_hits()
	_resolve_punches()
	_resolve_mecha_ultimates()
	_resolve_chunks()
	_resolve_lasers()
	_resolve_waves()
	_resolve_bolts()
	_projectiles_hit_mechas()
	_resolve_shot_cancels(delta)
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
	var counterers: Array = [a, b]  # les deux attaques se sont percutées : chacun a contré l'autre
	if counterer != null:
		counterers = [counterer]
	elif heavy_countered:
		counterers = [a] if b.is_heavy_attack() else [b]  # la légère a contré la lourde
	_count_counter(heavy_countered or explosion, counterers)  # contrer une lourde compte triple
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


## Un contre a eu lieu : la jauge de contre (partagée) monte, et la jauge d'ultime de chacun de ceux
## qui ont contré aussi (voir Fighter.add_ultimate_points).
func _count_counter(countered_heavy: bool, counterers: Array) -> void:
	gauge.add_counter(countered_heavy)
	for fighter: Fighter in counterers:
		fighter.add_ultimate_points(countered_heavy)


## X + Y avec la jauge d'ultime pleine. Pour l'instant, seule l'onde blanche autour du perso
## (dessinée par fighter.gd) : l'attaque ultime de chaque perso arrive aux étapes suivantes.
func _on_ultimate_used(fighter: Fighter) -> void:
	if _ultimate_test:
		fighter.ultimate_points = Fighter.ULTIMATE_POINTS  # mode essai : la jauge se remplit tout de suite


## Le laser de la Barre (son ultime) gèle chacun de ceux qu'il traverse, une fois chacun.
## Seul un blocage parfait l'arrête : c'est alors un contre, comme un coup bloqué parfaitement.
## Le bouclier ramassé l'arrête aussi (sans contre). Un blocage normal ne protège pas.
func _resolve_lasers() -> void:
	for shooter in fighters:
		if shooter.eliminated or not shooter.is_laser_active():
			continue
		for victim in fighters:
			if victim == shooter or victim.eliminated or victim in shooter.laser_frozen or not victim.can_be_hit() \
					or not _segment_hits_rect(shooter.global_position, shooter.laser_end(), Fighter.LASER_RADIUS, victim.body_rect()):
				continue
			shooter.laser_frozen.append(victim)
			if victim.is_item_shielded():
				_spawn_clash_mark(victim.global_position, false, ItemPickup.color_of("bouclier"))
			elif victim.is_parrying():
				_parry_ultimate(shooter, victim)
				break
			else:
				victim.freeze()
				_spawn_clash_mark(victim.global_position, true, Fighter.LASER_COLOR)
				if _alive_count() == 2:
					_stun_focus = [shooter, victim]


## L'onde de choc de Jumb (son ultime) : un cercle qui s'ouvre autour de lui et frappe chacun de
## ceux qu'il atteint (sonné, ou une vie en moins si on l'était déjà ou si on était gelé), en les
## projetant très loin. Comme pour le laser : seul un blocage parfait l'arrête (un contre), le
## bouclier ramassé la bloque, un blocage normal ne protège pas.
func _resolve_waves() -> void:
	for jumb in fighters:
		if jumb.eliminated or jumb.wave_radius() <= 0.0:
			continue
		for victim in fighters:
			if victim == jumb or victim.eliminated or victim in jumb.wave_hit or not victim.can_be_hit():
				continue
			var rect := victim.body_rect()
			var closest := Vector2(clampf(jumb.global_position.x, rect.position.x, rect.end.x),
				clampf(jumb.global_position.y, rect.position.y, rect.end.y))
			if closest.distance_to(jumb.global_position) > jumb.wave_radius():
				continue
			jumb.wave_hit.append(victim)
			if victim.is_item_shielded():
				_spawn_clash_mark(victim.global_position, false, ItemPickup.color_of("bouclier"))
			elif victim.is_parrying():
				_parry_ultimate(jumb, victim)
				break
			else:
				var side := signf(victim.global_position.x - jumb.global_position.x)
				if side == 0.0:
					side = jumb.facing
				victim.take_hit(Vector2(side, -Fighter.WAVE_LIFT).normalized(), Fighter.WAVE_KNOCKBACK)
				_spawn_clash_mark(victim.global_position, true, Fighter.WAVE_COLOR)
				if victim.is_stunned() and _alive_count() == 2:
					_stun_focus = [jumb, victim]


## L'éclair de Jib (son ultime) : chaque traversée frappe ceux qu'elle touche (sonné, ou une vie en
## moins si on l'était déjà). Comme pour les autres ultimes : seul un blocage parfait l'arrête.
func _resolve_bolts() -> void:
	for jib in fighters:
		if jib.eliminated or not jib.is_bolt_passing():
			continue
		var reach := jib.body_rect().grow(Fighter.BOLT_REACH)
		for victim in fighters:
			if victim == jib or victim.eliminated or victim in jib.bolt_hit or not victim.can_be_hit() \
					or not reach.intersects(victim.body_rect()):
				continue
			jib.bolt_hit.append(victim)
			if victim.is_item_shielded():
				_bounce_off_item_shield(jib, victim)
				break
			elif victim.is_parrying():
				_parry_ultimate(jib, victim)
				break
			else:
				victim.take_hit(jib._bolt_dir, Fighter.BOLT_KNOCKBACK)
				_spawn_clash_mark(victim.global_position, false, Fighter.BOLT_COLOR)
				if victim.is_stunned() and _alive_count() == 2:
					_stun_focus = [jib, victim]


## Ultime (laser, onde ou éclair) bloqué parfaitement : il s'éteint, son lanceur est repoussé et ne frappe plus pendant 1 s.
func _parry_ultimate(shooter: Fighter, defender: Fighter) -> void:
	var push := _push_dir(shooter, defender)
	_spawn_clash_mark(defender.global_position, true, PARRY_COLOR)
	_count_counter(true, [defender])
	defender.recover()
	defender.reset_cooldown()
	shooter.clash(push * Fighter.CLASH_PUSH * defender.stats.mass(), Fighter.PARRY_COOLDOWN)
	_renew_slowmo(shooter, defender)


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
	_count_counter(heavy, [defender])
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
	loose.bow_id = _new_bow_id()  # un arc neuf, avec toutes ses flèches
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
	loose.ammo = holder.arrows
	loose.bow_id = holder.bow_id
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
				if window is CityBlock:  # un bloc de la Ville : une lourde l'abîme plus
					(window as CityBlock).hit(CityBlock.HEAVY_DAMAGE if attacker.is_heavy_attack() else 1)
				else:
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
		var hit_dir: Vector2 = attacker.hit_push_direction((victim.global_position - attacker.global_position).normalized())
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


## Arc : la flèche part vers l'adversaire. Elle tombe un peu en volant et fait mal comme une
## balle (un coup peut la renvoyer, le bouclier ramassé aussi).
func _on_arrow_shot(fighter: Fighter, direction: Vector2, speed: float, knockback: float) -> void:
	var arrow := Projectile.new()
	arrow.kind = "fleche"
	arrow.owner_index = fighter.player_index
	arrow.position = fighter.global_position + direction * 24.0
	arrow.velocity = direction * speed
	arrow.rotation = direction.angle()
	arrow.knockback = knockback
	arrow.color = fighter.weapon.color
	arrow.length = Projectile.ARROW_LENGTH
	arrow.bow_id = fighter.bow_id
	_add_projectile(arrow)


## Chaque arc a son numéro : ses flèches ne se ramassent qu'avec lui.
func _new_bow_id() -> int:
	_bow_count += 1
	return _bow_count


## Une flèche : sortie de la map, elle est détruite ; un coup ou un blocage parfait la contre
## (elle casse) ; elle tombe après avoir touché quelqu'un ; posée ou plantée, celui qui tient
## son arc la ramasse en passant dessus (s'il lui manque des flèches). Contrée de très près
## (tireur à moins de ARROW_CLOSE_COUNTER), l'arc s'use comme n'importe quelle arme contrée.
func _resolve_arrow(arrow: Projectile) -> void:
	if not map.blast_zone.has_point(arrow.position):
		_remove_projectile(arrow)
		return
	if arrow.state != Projectile.State.FLYING:
		for fighter in fighters:
			if not fighter.eliminated and fighter.has_weapon_in_hand() and fighter.bow_id == arrow.bow_id \
					and fighter.arrows < Fighter.ARROWS_MAX and fighter.body_rect().grow(12.0).has_point(arrow.position):
				fighter.arrows += 1
				_remove_projectile(arrow)
				return
		return
	for fighter in fighters:
		if fighter.player_index != arrow.owner_index and fighter.is_attack_active() and _projectile_in_attack(arrow, fighter):
			fighter.mark_attack_hit()
			fighter.reset_cooldown()
			_count_counter(false, [fighter])
			_spawn_clash_mark(arrow.position, false)
			_wear_bow_close(arrow, fighter)
			_remove_projectile(arrow)
			return
	var victim := _projectile_victim(arrow)
	if victim == null:
		return
	if victim.is_parrying():
		_projectile_hits(arrow, victim, 1)  # blocage parfait : un contre, la flèche casse
		_wear_bow_close(arrow, victim)
		_remove_projectile(arrow)
		return
	if not victim.is_item_shielded() and victim.can_be_hit():
		_projectile_hits(arrow, victim, 1)
	arrow.drop()


func _wear_bow_close(arrow: Projectile, counterer: Fighter) -> void:
	var shooter: Fighter = fighters[arrow.owner_index]
	if shooter.bow_id == arrow.bow_id and shooter.global_position.distance_to(counterer.global_position) <= ARROW_CLOSE_COUNTER:
		_wear_weapon(shooter, counterer)


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
			"fleche":
				_resolve_arrow(projectile)
			"grenade":
				_resolve_grenade(projectile)
			"roquette", "missile":
				_resolve_rocket(projectile)
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
		fighter.equip(loose.weapon, loose.counters, loose.ammo, loose.bow_id)
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
	_count_counter(true, [counterer])
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
## Un renvoi parfait compte comme un contre (de lourde pour une roquette). Sert aussi aux roquettes.
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
	if bullet.kind == "missile":
		bullet.homing = _homing_node(shooter)  # renvoyé : il suit maintenant son tireur
	var perfect := error <= 0.0
	_spawn_clash_mark(bullet.position, false, PARRY_COLOR if perfect else Color.WHITE)
	if perfect:
		_count_counter(bullet.kind == "roquette", [deflector])
		deflector.recover()
		deflector.reset_cooldown()


## Ville : les gros morceaux d'immeuble qui tombent. Ils font mal comme une attaque lourde venue du
## ciel (une seule fois par joueur), et se contrent pareil : un coup lourd (ou 3 légers) le casse en
## l'air, un blocage parfait le fait éclater sur le bouclier (contre), un dash passe à travers.
## Un blocage normal l'arrête mais le bouclier craque fort.
func _resolve_chunks() -> void:
	var collapse := map.get_node_or_null("Ecroulement") as CityCollapse
	if collapse == null:
		return
	for chunk in collapse.chunks:
		if not is_instance_valid(chunk) or not chunk.is_dangerous():
			continue
		var parts := chunk.current_rects()
		for fighter in fighters:
			if fighter.eliminated or not fighter.is_attack_active():
				continue
			for r in parts:
				if _segment_hits_rect(fighter.attack_start(), fighter.attack_center(), fighter.attack_radius(), r):
					fighter.mark_attack_hit()
					if chunk.take_attack(fighter.is_heavy_attack()):
						_spawn_clash_mark(r.get_center(), true)
						_count_counter(true, [fighter])
						fighter.recover()
					break
		if not chunk.is_dangerous():
			continue
		for fighter in fighters:
			if fighter.eliminated or chunk.hit_fighters.has(fighter) or fighter.is_dodging() or not fighter.can_be_hit():
				continue
			var body := fighter.body_rect()
			if not parts.any(func(r: Rect2) -> bool: return r.intersects(body)):
				continue
			chunk.hit_fighters[fighter] = true
			var side := Vector2(signf(body.get_center().x - chunk.bounds().get_center().x), 0.0)
			if side.x == 0.0:
				side.x = 1.0
			if _crush(fighter, side):
				chunk.burst()  # il s'en est protégé : le morceau éclate dessus
			if not chunk.is_dangerous():
				break
		if not chunk.is_dangerous():
			continue
		for mecha in mechas.duplicate():  # un mecha (piloté ou vide) s'use, et le morceau éclate dessus
			if not is_instance_valid(mecha) or not mecha.is_ready() or chunk.hit_fighters.has(mecha):
				continue
			var hull: Rect2 = mecha.body_rect()
			if parts.any(func(r: Rect2) -> bool: return r.intersects(hull)):
				chunk.hit_fighters[mecha] = true
				chunk.burst()
				_wear_mecha(mecha, MECHA_WEAR_CHUNK, true)
				break


## Ville : quelque chose de lourd tombe sur "fighter" (gros morceau, mecha qui se pose). Ça se traite
## comme une lourde : bouclier ramassé, blocage parfait (un contre) ou blocage normal (le bouclier
## craque fort) le protègent ; sinon il est touché (sonné, ou une vie en moins s'il l'était déjà).
## side : de quel côté il est repoussé. Renvoie true s'il s'en est protégé.
func _crush(fighter: Fighter, side: Vector2) -> bool:
	if fighter.is_item_shielded():
		return true
	if fighter.is_parrying():
		_spawn_clash_mark(fighter.body_rect().get_center(), true, PARRY_COLOR)
		_count_counter(true, [fighter])
		fighter.recover()
		return true
	if fighter.is_blocking() and not fighter.is_stunned():
		if fighter.absorb_hit(side, CHUNK_SHIELD_DAMAGE):
			fighter.shield_burst(side, true)
		return true
	fighter.take_hit((side + Vector2.DOWN).normalized(), CHUNK_KNOCKBACK)
	if fighter.is_stunned() and _alive_count() == 2:
		_stun_focus = [fighter, _closest_opponent(fighter)]
	return false


# --- Ville : les mechas (voir scripts/ville/mecha.gd) ---

## Les mechas vides (ou en train d'arriver) avancent tout seuls ; un mecha piloté avance avec son
## pilote (voir Fighter._tick_mecha). Un mecha vide tombé hors de la ville est perdu.
func _tick_mechas(delta: float) -> void:
	for i in range(mechas.size() - 1, -1, -1):  # à l'envers : on peut en retirer en route
		if not is_instance_valid(mechas[i]) or mechas[i].is_queued_for_deletion():
			mechas.remove_at(i)  # tombé avec son pilote (voir Fighter.fall_out)
			continue
		var mecha := mechas[i]
		if mecha.pilot != null and mecha.pilot.eliminated:
			mecha.pilot.leave_mecha()
		if mecha.pilot != null:
			continue
		if not map.blast_zone.has_point(mecha.global_position):
			mechas.remove_at(i)
			mecha.queue_free()
			continue
		mecha.tick(InputState.new(), delta)


## La balise d'appel est activée (RT) : un viseur rouge marque l'endroit où le mecha va se poser,
## à la verticale du joueur, sur ce qu'il y a de plus haut (un toit plutôt que l'intérieur d'un immeuble).
## weapon : son arme lourde ("roquette" ou "laser") ; par défaut tirée au hasard.
func call_mecha(fighter: Fighter, weapon := "") -> Mecha:
	var mecha := Mecha.new()
	mecha.heavy_weapon = weapon if weapon != "" else Mecha.HEAVY_WEAPONS[rng.randi() % Mecha.HEAVY_WEAPONS.size()]
	mecha.caller = fighter
	mecha.position = _mecha_landing(fighter.global_position.x, fighter.global_position.y + fighter.stats.body_size.y / 2.0)
	mecha.facing = fighter.facing
	mecha.landed.connect(_on_mecha_landed)
	mecha.fired.connect(_on_mecha_fired)
	mecha.destroyed.connect(_on_mecha_destroyed)
	mechas.append(mecha)
	add_child(mecha)
	move_child(mecha, 1)  # derrière les joueurs, devant le décor
	return mecha


## Où se pose un mecha appelé à la verticale de x : le plus haut de ce qui est sous le ciel à cet endroit
## (sur toute la largeur de son corps). Au-dessus du vide : là où est le joueur (il tombera).
func _mecha_landing(x: float, feet_y: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	var best := INF
	var mask := 1 | (1 << (Fighter.PLATFORM_LAYER - 1))  # le sol et les planchers
	for dx in [-Mecha.BODY.x / 2.0 + 1.0, -Mecha.BODY.x / 4.0, 0.0, Mecha.BODY.x / 4.0, Mecha.BODY.x / 2.0 - 1.0]:
		var from := Vector2(x + dx, map.blast_zone.position.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, Vector2(x + dx, map.blast_zone.end.y), mask))
		if not hit.is_empty():
			best = minf(best, hit.position.y)
	return Vector2(x, best if best != INF else feet_y)


## Les coups des joueurs à pied usent les mechas qu'ils touchent (une fois par attaque) : 1 pour un
## léger, 3 pour un lourd. Le pilote, lui, n'est pas touché tant que son mecha tient.
func _resolve_mecha_hits() -> void:
	for mecha in mechas.duplicate():  # (un mecha détruit sort de la liste)
		if not is_instance_valid(mecha) or not mecha.is_ready():
			continue
		for attacker in mecha.hit_by.keys():
			if not is_instance_valid(attacker) or not (attacker as Fighter).is_attack_active():
				mecha.hit_by.erase(attacker)  # cette attaque est finie : la suivante pourra toucher
		for attacker in fighters:
			if attacker.eliminated or attacker == mecha.pilot or not attacker.is_attack_active() or mecha.hit_by.has(attacker):
				continue
			if _segment_hits_rect(attacker.attack_start(), attacker.attack_center(), attacker.attack_radius(), mecha.body_rect()):
				mecha.hit_by[attacker] = true
				attacker.mark_attack_hit()
				var heavy := attacker.is_heavy_attack()
				if _wear_mecha(mecha, MECHA_WEAR_HEAVY if heavy else MECHA_WEAR_LIGHT, heavy) == "parry":
					# Blocage parfait du mecha : comme sur un joueur, l'attaquant est repoussé et ne frappe plus 1 s
					attacker.clash(_push_dir_from(mecha.body_rect().get_center(), attacker) * Fighter.CLASH_PUSH, Fighter.PARRY_COOLDOWN)
				if mecha.is_destroyed():
					break


## Ce qui vole et touche un mecha (pas les tirs de son propre pilote) : la balle s'arrête dessus,
## la flèche et la lance retombent, la roquette explose. Chacun l'use un peu.
func _projectiles_hit_mechas() -> void:
	for projectile: Projectile in projectiles.duplicate():
		if projectile.state != Projectile.State.FLYING or projectile.finished \
				or not projectile.kind in ["balle", "fleche", "lance", "roquette", "missile"]:
			continue
		for mecha in mechas.duplicate():
			if not is_instance_valid(mecha) or not mecha.is_ready() \
					or (mecha.pilot != null and mecha.pilot.player_index == projectile.owner_index):
				continue
			if not _segment_hits_rect(projectile.tail(), projectile.tip(), Projectile.RADIUS, mecha.body_rect()):
				continue
			if projectile.kind in ["balle", "roquette", "missile"] and mecha.is_parrying():
				# Blocage parfait du mecha : la balle (ou la roquette) repart droit sur son tireur
				_wear_mecha(mecha, 0, projectile.kind == "roquette")
				_send_back(projectile, mecha.pilot)
				break
			match projectile.kind:
				"balle":
					_remove_projectile(projectile)
					_wear_mecha(mecha, MECHA_WEAR_BULLET, false)
				"fleche":
					projectile.drop()
					_wear_mecha(mecha, MECHA_WEAR_ARROW, false)
				"lance":
					projectile.drop()
					_wear_mecha(mecha, MECHA_WEAR_SPEAR, true)
				"roquette", "missile":
					projectile.finished = true  # elle explose tout de suite (voir _resolve_rocket)
			break


## Un mecha s'use de "amount" (voir Mecha.absorb) : son bouclier levé encaisse à sa place, et un
## blocage parfait n'use rien du tout et compte comme un contre pour son pilote ("heavy" : de lourde).
## Renvoie ce qui s'est passé : "parry", "shield" ou "hit".
func _wear_mecha(mecha: Mecha, amount: int, heavy: bool) -> String:
	var result := mecha.absorb(amount)
	if result == "parry":
		_spawn_clash_mark(mecha.body_rect().get_center(), heavy, PARRY_COLOR)
		if mecha.pilot != null:
			_count_counter(heavy, [mecha.pilot])
	return result


## Une balle ou une roquette renvoyée droit sur celui qui l'a tirée ; elle appartient maintenant à "by".
func _send_back(projectile: Projectile, by: Fighter) -> void:
	var shooter: Fighter = fighters[projectile.owner_index]
	var dir := -projectile.velocity.normalized()
	var aim_at := shooter.mecha.body_rect().get_center() if shooter.is_piloting() else shooter.global_position
	if not shooter.eliminated:
		dir = (aim_at - projectile.position).normalized()
	projectile.velocity = dir * projectile.velocity.length() * DEFLECT_SPEED
	projectile.rotation = dir.angle()
	projectile.position += dir * 30.0  # qu'il ne retouche pas tout de suite le bouclier
	if by != null:
		projectile.owner_index = by.player_index
	if projectile.kind == "missile":
		projectile.homing = _homing_node(shooter)


## Du point "from" vers le joueur, à plat (pour repousser).
func _push_dir_from(from: Vector2, fighter: Fighter) -> Vector2:
	var side := signf(fighter.global_position.x - from.x)
	return Vector2(side if side != 0.0 else 1.0, 0.0)


## X + Y en mecha : l'ultime du pilote en plus gros (voir Mecha._start_ultimate). Comme à pied,
## seul un blocage parfait l'arrête (contre de lourde, le mecha est repoussé) ; le bouclier ramassé
## protège ; un blocage normal non. Un mecha touché s'use (son bouclier encaisse à sa place).
##   grand laser (Barre) : traverse tout, casse les blocs sur son chemin, gèle 3 s (joueur ou mecha) ;
##   onde (Jumb) : 600 px autour, projette ceux à pied, repousse les mechas, abîme les blocs ;
##   éclair (Jib) : chaque traversée frappe ce qu'elle touche.
func _resolve_mecha_ultimates() -> void:
	for mecha in mechas.duplicate():
		if not is_instance_valid(mecha) or not mecha.is_ready() or mecha.ultimate == "" or mecha.pilot == null:
			continue
		var shooter: Fighter = mecha.pilot
		var center: Vector2 = mecha.body_rect().get_center()
		var targets: Array = []  # [ce qui est touché, sa zone]
		match mecha.ultimate:
			"laser":
				if not mecha.is_laser_firing():
					continue
				var a: Vector2 = mecha.laser_start()
				var b: Vector2 = mecha.laser_end()
				if not mecha.laser_blocks_done:
					mecha.laser_blocks_done = true
					for block in map.windows():
						if not block.broken and _segment_hits_rect(a, b, Mecha.ULT_LASER_RADIUS, block.rect()):
							if block is CityBlock:
								(block as CityBlock).hit(Ville.BLOCK_HP)
							else:
								block.smash()
				for fighter in fighters:
					if not fighter.is_piloting() and _segment_hits_rect(a, b, Mecha.ULT_LASER_RADIUS, fighter.body_rect()):
						targets.append(fighter)
				for other in mechas:
					if other != mecha and is_instance_valid(other) and other.is_ready() \
							and _segment_hits_rect(a, b, Mecha.ULT_LASER_RADIUS, other.body_rect()):
						targets.append(other)
			"onde":
				var r: float = mecha.wave_radius()
				if r <= 0.0:
					continue
				for block in map.windows():
					if not block.broken and not mecha.ult_blocks.has(block) and _rect_distance(block.rect(), center) <= r:
						mecha.ult_blocks[block] = true
						if block is CityBlock:
							(block as CityBlock).hit(ULT_WAVE_BLOCK_DAMAGE)
						else:
							block.smash()
				for fighter in fighters:
					if not fighter.is_piloting() and _rect_distance(fighter.body_rect(), center) <= r:
						targets.append(fighter)
				for other in mechas:
					if other != mecha and is_instance_valid(other) and other.is_ready() and _rect_distance(other.body_rect(), center) <= r:
						targets.append(other)
			"eclair":
				if not mecha.is_bolt_passing():
					continue
				var reach: Rect2 = mecha.body_rect().grow(20.0)
				for fighter in fighters:
					if not fighter.is_piloting() and reach.intersects(fighter.body_rect()):
						targets.append(fighter)
				for other in mechas:
					if other != mecha and is_instance_valid(other) and other.is_ready() and reach.intersects(other.body_rect()):
						targets.append(other)
		for target in targets:
			if target in mecha.ult_hit or mecha.ultimate == "":
				continue
			if target is Fighter:
				var victim: Fighter = target
				if victim == shooter or victim.eliminated or not victim.can_be_hit():
					continue
				mecha.ult_hit.append(victim)
				if victim.is_item_shielded():
					_spawn_clash_mark(victim.global_position, false, ItemPickup.color_of("bouclier"))
				elif victim.is_parrying():
					_spawn_clash_mark(victim.global_position, true, PARRY_COLOR)
					_count_counter(true, [victim])
					victim.recover()
					victim.reset_cooldown()
					mecha.parried(_push_dir_from(victim.global_position, shooter) * MECHA_PARRY_PUSH)
				else:
					var away := (victim.global_position - center).normalized()
					match mecha.ultimate:
						"laser":
							victim.freeze()
							_spawn_clash_mark(victim.global_position, true, Fighter.LASER_COLOR)
						"onde":
							victim.take_hit((away + Vector2(0.0, -Fighter.WAVE_LIFT)).normalized(), ULT_WAVE_KNOCKBACK)
							_spawn_clash_mark(victim.global_position, true, Fighter.WAVE_COLOR)
						"eclair":
							victim.take_hit(mecha.velocity.normalized(), ULT_BOLT_KNOCKBACK)
							_spawn_clash_mark(victim.global_position, false, Fighter.BOLT_COLOR)
					if victim.is_stunned() and _alive_count() == 2:
						_stun_focus = [shooter, victim]
			else:
				var hit_mecha: Mecha = target
				mecha.ult_hit.append(hit_mecha)
				var wear := MECHA_WEAR_ULT_LASER if mecha.ultimate == "laser" else MECHA_WEAR_ULT_WAVE if mecha.ultimate == "onde" else MECHA_WEAR_ULT_BOLT
				var kind: String = mecha.ultimate
				if _wear_mecha(hit_mecha, wear, true) == "parry":
					mecha.parried((center - hit_mecha.body_rect().get_center()).normalized() * MECHA_PARRY_PUSH)
				elif is_instance_valid(hit_mecha) and not hit_mecha.is_destroyed():
					if kind == "laser":
						hit_mecha.freeze()
					elif kind == "onde":
						var push_dir := (hit_mecha.body_rect().get_center() - center).normalized()
						hit_mecha.velocity = (push_dir + Vector2(0.0, -0.3)).normalized() * ULT_WAVE_PUSH


## RB en mecha : le coup de poing. Il frappe une fois chacun de ce qu'il touche devant lui :
##   un joueur à pied : comme une lourde (blocage parfait = contre et le mecha est repoussé ;
##   blocage normal : le bouclier craque fort ; sinon sonné, ou une vie en moins) ;
##   un autre mecha : MECHA_WEAR_PUNCH d'usure (son bouclier et son blocage parfait marchent) ;
##   les blocs de la ville : PUNCH_BLOCK_DAMAGE, les fenêtres cassent ; les objets par terre valdinguent.
func _resolve_punches() -> void:
	for mecha in mechas.duplicate():
		if not is_instance_valid(mecha) or not mecha.is_ready() or not mecha.is_punch_active():
			continue
		var zone: Rect2 = mecha.punch_rect()
		var push := Vector2(mecha.facing, -0.25).normalized()
		for victim in fighters:
			if victim.eliminated or victim.is_piloting() or victim == mecha.pilot or victim in mecha.punch_hit \
					or victim.is_dodging() or not zone.intersects(victim.body_rect()):
				continue
			mecha.punch_hit.append(victim)
			if victim.is_item_shielded():
				_spawn_clash_mark(victim.global_position, false, ItemPickup.color_of("bouclier"))
			elif victim.is_parrying():
				_spawn_clash_mark(victim.global_position, true, PARRY_COLOR)
				_count_counter(true, [victim])
				victim.recover()
				victim.reset_cooldown()
				mecha.parried(-push * MECHA_PARRY_PUSH)
				break
			elif victim.is_blocking() and not victim.is_stunned():
				var side := Vector2(mecha.facing, 0.0)
				if victim.absorb_hit(side, CHUNK_SHIELD_DAMAGE):
					victim.shield_burst(side, true)
			elif victim.can_be_hit():
				victim.take_hit(push, PUNCH_KNOCKBACK)
				_spawn_clash_mark(victim.global_position, false)
				if victim.is_stunned() and _alive_count() == 2 and mecha.pilot != null:
					_stun_focus = [mecha.pilot, victim]
		if not mecha.is_punch_active():
			continue  # blocage parfait : le poing s'est arrêté
		for other in mechas.duplicate():
			if other == mecha or not is_instance_valid(other) or not other.is_ready() or other in mecha.punch_hit \
					or not zone.intersects(other.body_rect()):
				continue
			mecha.punch_hit.append(other)
			if _wear_mecha(other, MECHA_WEAR_PUNCH, true) == "parry":
				mecha.parried(-push * MECHA_PARRY_PUSH)
				break
			_spawn_clash_mark(zone.get_center(), false)
		if mecha.is_punch_active() and not mecha.punch_hit.has(map):
			mecha.punch_hit.append(map)  # les blocs : une seule fois par coup de poing
			for block in map.windows():
				if block.broken or not zone.intersects(block.rect()):
					continue
				if block is CityBlock:
					(block as CityBlock).hit(PUNCH_BLOCK_DAMAGE)
				else:
					block.smash()
			for loose: Node2D in _loose_objects():
				if zone.has_point(loose.position):
					loose.launch(push * LOOSE_BLAST_SPEED)


## Les tirs s'annulent, comme les coups qui se croisent : deux balles de joueurs différents qui se
## rencontrent disparaissent toutes les deux ; une roquette disparaît après ROCKET_CANCEL_BULLETS balles
## adverses (c'est un contre de lourde, compté triple pour celui qui tire la 3e), et deux roquettes
## qui se croisent aussi. Un gros morceau qui tombe se casse en l'air comme sous les coups : une balle
## compte comme un coup léger, une roquette comme une lourde (elle explose dessus) ; cassé, c'est
## un contre de lourde pour le tireur. On compare le chemin fait pendant la frame, pour que deux
## tirs rapides qui se croisent ne passent pas l'un à travers l'autre.
func _resolve_shot_cancels(delta: float) -> void:
	var shots: Array[Projectile] = []
	for projectile in projectiles:
		if projectile.kind in ["balle", "roquette", "missile"] and not projectile.finished:
			shots.append(projectile)
	var gone := {}
	for i in shots.size():
		var a := shots[i]
		for j in range(i + 1, shots.size()):
			var b := shots[j]
			if gone.has(a) or gone.has(b) or a.owner_index == b.owner_index:
				continue
			if not _shots_meet(a, b, delta):
				continue
			var where := (a.tip() + b.tip()) / 2.0
			if a.kind == b.kind:
				gone[a] = true
				gone[b] = true
				_spawn_clash_mark(where, a.kind == "roquette")
				continue
			if a.kind == "missile" or b.kind == "missile":
				# Un missile s'annule avec ce qu'il croise (une balle suffit : petit contre pour son tireur)
				gone[a] = true
				gone[b] = true
				_spawn_clash_mark(where, false)
				for shot in [a, b]:
					if shot.kind == "balle":
						_count_counter(false, [fighters[shot.owner_index]])
				continue
			var rocket := a if a.kind == "roquette" else b
			var bullet := b if rocket == a else a
			gone[bullet] = true
			rocket.shot_hits += 1
			if rocket.shot_hits >= ROCKET_CANCEL_BULLETS:
				gone[rocket] = true
				_spawn_clash_mark(where, true)
				_count_counter(true, [fighters[bullet.owner_index]])
			else:
				_spawn_clash_mark(where, false)
	for projectile: Projectile in gone:
		_remove_projectile(projectile)
	_shots_hit_chunks(delta)


func _shots_meet(a: Projectile, b: Projectile, delta: float) -> bool:
	var closest := Geometry2D.get_closest_points_between_segments(
		a.tail() - a.velocity * delta, a.tip(), b.tail() - b.velocity * delta, b.tip())
	return closest[0].distance_to(closest[1]) <= Projectile.RADIUS * 2.0


func _shots_hit_chunks(delta: float) -> void:
	var collapse := map.get_node_or_null("Ecroulement") as CityCollapse
	if collapse == null:
		return
	for chunk in collapse.chunks:
		if not is_instance_valid(chunk) or not chunk.is_dangerous():
			continue
		var parts := chunk.current_rects()
		for projectile: Projectile in projectiles.duplicate():
			if not projectile.kind in ["balle", "roquette", "missile"] or projectile.finished:
				continue
			var from := projectile.tail() - projectile.velocity * delta
			var part_hit := Rect2()
			for r in parts:
				if _segment_hits_rect(from, projectile.tip(), Projectile.RADIUS, r):
					part_hit = r
					break
			if part_hit.size == Vector2.ZERO:
				continue
			var rocket := projectile.kind != "balle"  # roquette et missile explosent dessus
			if chunk.take_attack(projectile.kind == "roquette"):
				_spawn_clash_mark(part_hit.get_center(), true)
				_count_counter(true, [fighters[projectile.owner_index]])
			if rocket:
				projectile.position = part_hit.get_center()
				projectile.finished = true  # elle explose dessus (voir _resolve_rocket)
			else:
				_remove_projectile(projectile)
			if not chunk.is_dangerous():
				break


## Un mecha tire : les balles de la rafale (comme celles du pistolet, en plus rapide) ou une roquette.
## Canon collé au décor : le tir s'arrête contre lui (sinon il partirait de l'intérieur du mur).
func _on_mecha_fired(mecha: Mecha, kind: String, origin: Vector2, direction: Vector2, power: float) -> void:
	if mecha.pilot == null:
		return
	if kind == "laser":
		_fire_mecha_laser(mecha, origin, direction, power)
		return
	var projectile := Projectile.new()
	projectile.kind = kind
	projectile.owner_index = mecha.pilot.player_index
	projectile.rotation = direction.angle()
	projectile.position = origin
	var center := mecha.body_rect().get_center()
	var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(center, origin, 1))
	if kind == "missile":
		projectile.velocity = direction * MISSILE_SPEED
		projectile.length = 26.0
		projectile.color = mecha.pilot.color
		var target := _closest_opponent(mecha.pilot)
		if target != null:
			projectile.homing = _homing_node(target)
	elif kind == "balle":
		if not wall.is_empty():
			if wall.collider is BreakableWindow:
				(wall.collider as BreakableWindow).smash()
			projectile.free()
			return
		projectile.velocity = direction * MECHA_BULLET_SPEED
		projectile.length = 18.0
		projectile.knockback = BULLET_KNOCKBACK
		projectile.color = Color(1.0, 0.9, 0.5)
	else:
		projectile.blast = power
		projectile.velocity = direction * lerpf(ROCKET_SPEED[0], ROCKET_SPEED[1], power)
		projectile.length = lerpf(30.0, 42.0, power)
		projectile.color = mecha.pilot.color
		if not wall.is_empty():
			projectile.position = wall.position
			projectile.finished = true  # elle explose contre le mur collé au canon
	_add_projectile(projectile)


## Canon laser de mecha : un trait instantané, plus long s'il est chargé. Il traverse les joueurs et
## les mechas sur son chemin, casse jusqu'à MECHA_LASER_BLOCKS blocs puis s'arrête (un mur, le sol
## l'arrêtent tout de suite). Les tirs adverses sur son chemin : il efface les balles et s'arrête à
## la 3e (contre de lourde pour son tireur) ; une roquette ou un missile l'annule (les deux disparaissent).
## Ce qu'il touche : un joueur à pied comme une lourde (blocage parfait = contre, blocage normal =
## le bouclier craque fort) ; un mecha s'use (son bouclier et son blocage parfait marchent).
func _fire_mecha_laser(mecha: Mecha, origin: Vector2, direction: Vector2, power: float) -> void:
	var shooter := mecha.pilot
	var length := lerpf(MECHA_LASER_RANGE[0], MECHA_LASER_RANGE[1], power)
	# 1) Le décor : les blocs qu'il casse, et où il s'arrête
	var space := get_world_2d().direct_space_state
	var stop := length
	var to_break: Array = []  # [distance, bloc]
	var exclude: Array[RID] = []
	var from := origin
	var head := origin + direction * length
	if not space.intersect_ray(PhysicsRayQueryParameters2D.create(mecha.body_rect().get_center(), origin, 1)).is_empty():
		from = mecha.body_rect().get_center()  # canon collé au mur : le rayon part du corps (il ne passe pas à travers)
	while true:
		var query := PhysicsRayQueryParameters2D.create(from, head, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var distance: float = origin.distance_to(hit.position) * signf((hit.position - origin).dot(direction))
		var block := hit.collider as BreakableWindow
		if block != null and (not block is CityBlock or to_break.filter(func(b): return b[1] is CityBlock).size() < MECHA_LASER_BLOCKS):
			to_break.append([distance, block])
			exclude.append(hit.rid)
			continue
		stop = maxf(distance, 0.0)
		break
	# 2) Les tirs adverses sur son chemin
	var shots: Array = []
	for projectile in projectiles:
		if projectile.owner_index == shooter.player_index or projectile.finished or not projectile.kind in ["balle", "roquette", "missile"]:
			continue
		var along := (projectile.position - origin).dot(direction)
		if along < 0.0 or along > stop:
			continue
		if Geometry2D.get_closest_point_to_segment(projectile.position, origin, origin + direction * stop).distance_to(projectile.position) <= MECHA_LASER_RADIUS + Projectile.RADIUS:
			shots.append([along, projectile])
	shots.sort_custom(func(a, b): return a[0] < b[0])
	var bullets := 0
	for entry in shots:
		var projectile: Projectile = entry[1]
		_remove_projectile(projectile)
		if projectile.kind == "balle":
			bullets += 1
			if bullets < MECHA_LASER_BULLETS:
				continue
			_count_counter(true, [fighters[projectile.owner_index]])
		stop = entry[0]
		_spawn_clash_mark(origin + direction * stop, true)
		break
	var end := origin + direction * stop
	for entry in to_break:
		if entry[0] <= stop:
			var block: BreakableWindow = entry[1]
			if block is CityBlock:
				(block as CityBlock).hit(Ville.BLOCK_HP)
			else:
				block.smash()
	var trace := LaserTrace.new()
	trace.from = origin
	trace.to = end
	trace.width = MECHA_LASER_RADIUS
	add_child(trace)
	# 3) Ce qu'il traverse
	var wear := roundi(lerpf(MECHA_WEAR_LASER[0], MECHA_WEAR_LASER[1], power))
	for victim in fighters:
		if victim == shooter or victim.eliminated or victim.is_piloting() or victim.is_dodging() \
				or not _segment_hits_rect(origin, end, MECHA_LASER_RADIUS, victim.body_rect()):
			continue
		if victim.is_item_shielded() or not victim.can_be_hit():
			continue
		if victim.is_parrying():
			_spawn_clash_mark(victim.global_position, true, PARRY_COLOR)
			_count_counter(true, [victim])
			victim.recover()
			victim.reset_cooldown()
		elif victim.is_blocking() and not victim.is_stunned():
			var side := Vector2(signf(direction.x) if direction.x != 0.0 else 1.0, 0.0)
			if victim.absorb_hit(side, CHUNK_SHIELD_DAMAGE):
				victim.shield_burst(side, true)
		else:
			victim.take_hit(direction, MECHA_LASER_KNOCKBACK)
			_spawn_clash_mark(victim.global_position, true, Fighter.LASER_COLOR)
			if victim.is_stunned() and _alive_count() == 2:
				_stun_focus = [shooter, victim]
	for other in mechas.duplicate():
		if other != mecha and is_instance_valid(other) and other.is_ready() \
				and _segment_hits_rect(origin, end, MECHA_LASER_RADIUS, other.body_rect()):
			_wear_mecha(other, wear, true)
	var collapse := map.get_node_or_null("Ecroulement") as CityCollapse
	if collapse != null:
		for chunk in collapse.chunks:
			if is_instance_valid(chunk) and chunk.is_dangerous() and chunk.current_rects().any(
					func(r: Rect2) -> bool: return _segment_hits_rect(origin, end, MECHA_LASER_RADIUS, r)):
				if chunk.take_attack(true):
					_count_counter(true, [shooter])


## Ce qu'un missile suit pour toucher ce joueur : son mecha s'il pilote, sinon lui.
func _homing_node(fighter: Fighter) -> Node2D:
	return fighter.mecha if fighter.is_piloting() else fighter


## Une roquette : elle explose contre le décor, un mecha (voir _projectiles_hit_mechas), le premier
## joueur sur son chemin, ou au bout de sa course. Plus elle était chargée, plus l'explosion est grosse.
## Comme tout ce qui vole, elle se contre : frappée par un coup, elle est renvoyée comme une balle
## (voir _deflect_bullet) ; prise en blocage parfait, elle est annulée sans exploser (contre de
## lourde, compté triple).
func _resolve_rocket(rocket: Projectile) -> void:
	if not map.blast_zone.has_point(rocket.position):
		_remove_projectile(rocket)
		return
	if not rocket.finished:
		for fighter in fighters:
			if fighter.player_index != rocket.owner_index and not fighter.eliminated and fighter.is_attack_active() \
					and _projectile_in_attack(rocket, fighter):
				_deflect_bullet(rocket, fighter)
				return
		var victim := _projectile_victim(rocket)
		if victim == null:
			return
		if victim.is_parrying():
			_counter_rocket(rocket, victim)
			return
	if rocket.kind == "missile":
		_explode(rocket.tip() if not rocket.finished else rocket.position, MISSILE_KNOCKBACK, MISSILE_RADIUS, MECHA_WEAR_MISSILE, rocket.owner_index)
		_remove_projectile(rocket)
		return
	var p := rocket.blast
	_explode(rocket.tip() if not rocket.finished else rocket.position, lerpf(ROCKET_KNOCKBACK[0], ROCKET_KNOCKBACK[1], p),
		lerpf(ROCKET_RADIUS[0], ROCKET_RADIUS[1], p), roundi(lerpf(MECHA_WEAR_ROCKET[0], MECHA_WEAR_ROCKET[1], p)), rocket.owner_index)
	_remove_projectile(rocket)


func _counter_rocket(rocket: Projectile, counterer: Fighter) -> void:
	_spawn_clash_mark(rocket.tip(), true, PARRY_COLOR)
	_count_counter(true, [counterer])
	counterer.recover()
	counterer.reset_cooldown()
	_remove_projectile(rocket)


## Un mecha n'a plus de solidité : il explose. Son pilote est éjecté vers le haut, sonné (sans perdre
## de vie). L'explosion casse les blocs autour, use les mechas voisins et repousse ceux qui sont à pied.
func _on_mecha_destroyed(mecha: Mecha) -> void:
	var center := mecha.body_rect().get_center()
	mechas.erase(mecha)
	var pilot := mecha.pilot
	if pilot != null:
		pilot.leave_mecha()
		pilot.eject_from_mecha()
		if _alive_count() == 2:
			_stun_focus = [pilot, _closest_opponent(pilot)]
	var wreck := MechaVisual.new()  # le dessin de l'explosion reste un instant à sa place
	wreck.color = mecha.visual.color
	wreck.hover = false
	wreck.position = mecha.global_position
	wreck.set_pose(MechaVisual.Pose.EXPLODE)
	add_child(wreck)
	get_tree().create_timer(MechaVisual.EXPLODE_TIME).timeout.connect(wreck.queue_free)
	mecha.queue_free()
	_spawn_explosion(center, Color(1.0, 0.55, 0.2))
	_shake_left = SHAKE_TIME
	map.smash_windows_in(center, MECHA_BLAST_RADIUS)
	for loose: Node2D in _loose_objects():
		var away := loose.position - center
		if away.length() <= MECHA_BLAST_RADIUS:
			loose.launch(((away.normalized() if away.length() > 1.0 else Vector2.UP) + Vector2(0.0, -0.6)).normalized() * LOOSE_BLAST_SPEED)
	for other in mechas.duplicate():
		if is_instance_valid(other) and other.is_ready() and _rect_distance(other.body_rect(), center) <= MECHA_BLAST_RADIUS:
			_wear_mecha(other, MECHA_WEAR_BLAST, true)
	for fighter in fighters:
		if fighter == pilot or fighter.eliminated or fighter.is_piloting():
			continue
		if _rect_distance(fighter.body_rect(), center) <= MECHA_BLAST_RADIUS:
			var side := signf(fighter.global_position.x - center.x)
			fighter.clash(Vector2(side if side != 0.0 else 1.0, -0.3).normalized() * MECHA_BLAST_PUSH, Fighter.CLASH_LOCKOUT, 300.0)


## Distance entre un point et le bord d'un rectangle (0 s'il est dedans).
func _rect_distance(rect: Rect2, point: Vector2) -> float:
	return point.clamp(rect.position, rect.end).distance_to(point)


## Le mecha appelé se pose : onde de choc. Celui qui est dessous est écrasé (comme sous un gros
## morceau), les autres autour sont repoussés, les blocs dans le rayon s'abîment, les objets volent.
## Celui qui l'a appelé n'est pas touché.
func _on_mecha_landed(mecha: Mecha) -> void:
	var center := mecha.global_position
	_shake_left = SHAKE_TIME
	for window in map.windows():
		var r := window.rect()
		if window.broken or center.clamp(r.position, r.end).distance_to(center) > Mecha.SHOCKWAVE_RADIUS:
			continue
		if window is CityBlock:
			(window as CityBlock).hit(MECHA_SHOCK_BLOCK_DAMAGE)
		else:
			window.smash()
	for loose: Node2D in _loose_objects():
		var away := loose.position - center
		if away.length() <= Mecha.SHOCKWAVE_RADIUS:
			var dir := (away.normalized() if away.length() > 1.0 else Vector2.UP) + Vector2(0.0, -0.6)
			loose.launch(dir.normalized() * LOOSE_BLAST_SPEED)
	var crush := mecha.body_rect()
	for fighter in fighters:
		if fighter == mecha.caller or fighter.eliminated or fighter.is_piloting():
			continue
		var body := fighter.body_rect()
		var side := Vector2(signf(body.get_center().x - center.x), 0.0)
		if side.x == 0.0:
			side.x = 1.0
		if body.intersects(crush):
			if fighter.can_be_hit():
				_crush(fighter, side)
		elif center.clamp(body.position, body.end).distance_to(center) <= Mecha.SHOCKWAVE_RADIUS:
			fighter.clash(side * MECHA_SHOCK_PUSH, Fighter.CLASH_LOCKOUT, MECHA_SHOCK_LIFT)


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
## radius, mecha_wear : la taille de l'explosion et ce qu'elle use aux mechas (Ville) ; owner : le joueur
## qui l'a provoquée (by_player, -1 = inconnu) : son propre mecha n'est pas usé.
func _explode(where: Vector2, knockback := GRENADE_KNOCKBACK, radius := GRENADE_RADIUS, mecha_wear := MECHA_WEAR_GRENADE, by_player := -1) -> void:
	_spawn_explosion(where, Color(1.0, 0.55, 0.2))
	map.smash_windows_in(where, radius)
	for mecha in mechas.duplicate():
		if is_instance_valid(mecha) and mecha.is_ready() and _rect_distance(mecha.body_rect(), where) <= radius \
				and not (mecha.pilot != null and mecha.pilot.player_index == by_player):
			_wear_mecha(mecha, mecha_wear, true)
	for loose: Node2D in _loose_objects():
		var away := loose.position - where
		if away.length() <= radius:
			var dir := (away.normalized() if away.length() > 1.0 else Vector2.UP) + Vector2(0.0, -0.5)
			loose.launch(dir.normalized() * LOOSE_BLAST_SPEED)
	for fighter in fighters:
		if fighter.eliminated or fighter.is_invincible() or fighter.is_item_shielded() or fighter.is_piloting():
			continue
		var body := fighter.body_rect()
		if where.clamp(body.position, body.end).distance_to(where) > radius:
			continue
		var away := fighter.global_position - where
		var dir := (away.normalized() if away.length() > 1.0 else Vector2.UP) + Vector2(0.0, -0.4)
		if fighter.is_parrying():
			# Blocage parfait au bon moment : il ne prend rien, c'est un contre (de lourde).
			_spawn_clash_mark(fighter.body_rect().get_center(), true, PARRY_COLOR)
			_count_counter(true, [fighter])
			fighter.recover()
			continue
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
		_count_counter(false, [victim])
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


## Le crochet du grappin arrive sur un blocage parfait : c'est un contre, comme pour un coup
## (celui qui l'a lancé est repoussé et ne frappe plus pendant 1 s, l'autre n'est plus sonné).
func _on_grapple_parried(thrower: Fighter, defender: Fighter) -> void:
	var push := _push_dir(thrower, defender)
	_spawn_clash_mark(defender.global_position, false, PARRY_COLOR)
	_count_counter(false, [defender])
	defender.recover()
	defender.reset_cooldown()
	thrower.clash(push * Fighter.CLASH_PUSH * defender.stats.mass(), Fighter.PARRY_COOLDOWN)
	_renew_slowmo(thrower, defender)


## Le coup tombe sur le bouclier ramassé : personne n'est touché, l'attaquant est projeté très loin
## et ne peut plus frapper un instant.
func _bounce_off_item_shield(attacker: Fighter, victim: Fighter) -> void:
	var push := _push_dir(attacker, victim)
	_spawn_clash_mark((attacker.global_position + victim.global_position) / 2.0, false, ItemPickup.color_of("bouclier"))
	attacker.clash(push * Fighter.ITEM_SHIELD_PUSH * victim.stats.mass(), Fighter.ITEM_SHIELD_COOLDOWN, 250.0)


# --- Objets ---

## Un objet utilisé : une balle tirée (pistolet, fusil : "power" = vitesse), une roquette
## (lance-roquette : "power" = sa force), ou une grenade lancée (ou lâchée, ou qui explose en main).
func _on_item_used(fighter: Fighter, kind: String, direction: Vector2, power: float, fuse: float) -> void:
	if kind == "balise":
		call_mecha(fighter)
		return
	if kind == "roquette":
		_fire_launcher(fighter, direction, power)
		return
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
			projectile.velocity = direction * BULLET_SPEED * power
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


## Lance-roquette : sa seule roquette part de l'épaule. Tube collé à un mur : elle y explose tout de suite.
func _fire_launcher(fighter: Fighter, direction: Vector2, blast: float) -> void:
	var rocket := Projectile.new()
	rocket.kind = "roquette"
	rocket.owner_index = fighter.player_index
	rocket.blast = blast
	rocket.rotation = direction.angle()
	rocket.velocity = direction * LAUNCHER_ROCKET_SPEED
	rocket.length = 46.0
	rocket.color = fighter.color
	rocket.position = fighter.global_position + direction * 30.0
	var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(
		fighter.global_position, rocket.position + direction * 20.0, 1))
	if not wall.is_empty():
		rocket.position = wall.position
		rocket.finished = true
	_add_projectile(rocket)


## RB avec une arme à 2 mains : elle part vers l'adversaire le plus proche (sans faire mal) et
## retombe par terre comme un objet, avec ce qu'il reste dedans. N'importe qui peut la ramasser.
func _on_item_tossed(fighter: Fighter, kind: String, ammo: int) -> void:
	var dir := Vector2(fighter.facing, 0.0)
	var target := _closest_opponent(fighter)
	if target != null:
		dir = (target.global_position - fighter.global_position).normalized()
	var pickup := spawn_pickup(kind, fighter.global_position)
	pickup.ammo = ammo
	pickup.thrown_by = fighter.player_index
	pickup.thrown_lock = ITEM_TOSS_LOCK
	pickup.launch(dir * TOSS_SPEED + Vector2(0.0, -TOSS_LIFT))


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
			var kinds: Array = ItemPickup.KINDS + ItemPickup.VILLE_KINDS if map.has_mechas else ItemPickup.KINDS
			spawn_pickup(kinds[rng.randi() % kinds.size()], points[rng.randi() % points.size()])
	if map.has_mechas:
		_tick_beacons(delta)
	for pickup: ItemPickup in pickups.duplicate():
		if not map.blast_zone.has_point(pickup.position):
			_remove_pickup(pickup)
			continue
		for fighter in fighters:
			if pickup.thrown_lock > 0.0 and fighter.player_index == pickup.thrown_by:
				continue
			var reach := fighter.mecha.body_rect() if fighter.is_piloting() else fighter.body_rect()  # en mecha : tout le mecha
			if not fighter.eliminated and reach.intersects(pickup.rect()) and fighter.take_item(pickup.kind, pickup.ammo):
				_remove_pickup(pickup)
				break


## Ville : une balise d'appel tombe de temps en temps, tant qu'il y a moins de mechas (déjà là, en
## route, ou dont la balise est par terre ou en main) que de joueurs encore en jeu.
func _tick_beacons(delta: float) -> void:
	_beacon_timer -= delta
	if _beacon_timer > 0.0:
		return
	_beacon_timer = BEACON_SPAWN_TIME
	var count := mechas.size()
	count += pickups.filter(func(p: ItemPickup) -> bool: return p.kind == "balise").size()
	count += fighters.filter(func(f: Fighter) -> bool: return f.item == "balise").size()
	if count < _alive_count():
		var points := map.item_spawn_points()
		spawn_pickup("balise", points[rng.randi() % points.size()])


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
