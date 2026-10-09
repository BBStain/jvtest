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
const CAMERA_ZOOM_MIN := 0.3               ## zoom le plus éloigné (plus petit = voit plus loin)
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

# --- 1 contre 1 : tant qu'un joueur est sonné, la caméra serre les deux joueurs et le temps ralentit un peu ---
const STUN_TIME_SCALE := 0.75              ## le jeu va un peu moins vite (2 s sonné = 2,7 vraies secondes)
const STUN_CAMERA_MARGIN := Vector2(380, 260)
const STUN_ZOOM_MAX := 1.8
const STUN_CAMERA_SMOOTHING := 12.0        ## la caméra fonce sur l'impact

# --- Une vie perdue (coup ou chute) : l'écran tremble ---
const SHAKE_TIME := 0.35                   ## en vraies secondes
const SHAKE_STRENGTH := 12.0               ## pixels à l'écran au début, puis le tremblement se calme

const ONLINE_HEADER := 6                   ## jeu en ligne : nombre de cases avant l'état des joueurs (voir online_state)

var fighters: Array[Fighter] = []
var player_devices: Array = []             ## les appareils de chaque joueur (voir InputBindings)
var pause_menu: PauseMenu                  ## le menu pause, quand il est ouvert
var _resume_grace := 0                     ## en sortant de la pause, on ignore les touches un instant
var _match_over := false
var _match_over_time := 0.0
var _time_engine := TimeEngine.new()
var _duel: Array[Fighter] = []             ## les deux joueurs du micro-duel en cours
var _stun_focus: Array[Fighter] = []       ## 1 contre 1 : celui qui a sonné et le joueur sonné
var _stun_slowmo := -1                     ## le ralenti lancé pour le joueur sonné (voir TimeEngine.play())
var _shake_left := 0.0                     ## l'écran tremble encore pendant ce temps (vraies secondes)
var _lives_seen: Array[int] = []           ## les vies de chacun à la frame d'avant (pour voir une vie perdue)
var gauge := CounterGauge.new()            ## la jauge de contre, une seule pour tous les joueurs
var online := false                        ## partie en ligne
var _online_state: Array = []              ## (copain) le dernier état du jeu reçu de l'hôte

var map: GameMap
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
	map = (load(GameSetup.map_path) as PackedScene).instantiate()
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
		fighter.show_lives()
		fighters.append(fighter)
	var gauge_bar := CounterGaugeBar.new()
	gauge_bar.gauge = gauge
	$UI.add_child(gauge_bar)
	$UI.move_child(gauge_bar, 0)  # sous l'écran de fin et le menu pause
	_update_camera(1.0, true)


func _process(delta: float) -> void:
	var real_delta := delta / Engine.time_scale  # la caméra garde sa vitesse pendant un ralenti
	if not _is_online_guest() and not _time_engine.is_active():
		_duel.clear()
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
					get_tree().change_scene_to_file(MENU_SCENE)
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
		fighter.physics_tick(input, delta)
	_resume_grace -= 1

	_resolve_clashes()
	_resolve_hits()
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
	if state[2] != "" and not _match_over:
		_show_end(state[2], fighters[state[3]].color if state[3] >= 0 else Color.WHITE)
	for i in mini(fighters.size(), state.size() - ONLINE_HEADER):
		fighters[i].apply_net_state(state[ONLINE_HEADER + i])


## (hôte) L'état du jeu envoyé aux copains : vitesse du temps, duel, fin de partie, zoom sur un joueur
## sonné, jauge de contre, puis chaque joueur.
func online_state() -> Array:
	var duel := []
	for fighter in _duel:
		duel.append(fighters.find(fighter))
	var stun_focus := []
	for fighter in _stun_focus:
		stun_focus.append(fighters.find(fighter))
	var winner := -1
	for i in fighters.size():
		if _match_over and not fighters[i].eliminated:
			winner = i
	var state := [Engine.time_scale, duel, _winner_label.text if _match_over else "", winner, stun_focus, gauge.points]
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
	var stun_zoom := not _stun_focus.is_empty() and one_on_one
	var duel_zoom := not stun_zoom and not _duel.is_empty() and one_on_one
	var framed := _stun_focus if stun_zoom else _duel if duel_zoom else fighters
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
	if stun_zoom:
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
		for fighter in [a, b]:
			var other: Fighter = b if fighter == a else a
			var direction := push if fighter == a else -push
			var cooldown := Fighter.CLASH_LOCKOUT
			if counterer != null and fighter != counterer:
				cooldown = maxf(fighter.attack_cooldown_left(), Fighter.CLASH_LOCKOUT)  # contré : sa recharge continue
			fighter.clash(direction * Fighter.CLASH_PUSH * other.stats.mass(), cooldown)
		_renew_slowmo(a, b)


## Blocage parfait : le défenseur a appuyé sur B pile au moment du coup. C'est un contre :
## les deux sont repoussés, le bouclier ne craque pas, celui qui frappait ne frappe plus
## pendant 1 s et le défenseur peut riposter tout de suite (et n'est plus sonné).
func _parry(attacker: Fighter, defender: Fighter) -> void:
	var push := _push_dir(attacker, defender)
	_spawn_clash_mark((attacker.global_position + defender.global_position) / 2.0, false, PARRY_COLOR)
	gauge.add_counter(attacker.is_heavy_attack())
	defender.recover()
	attacker.clash(push * Fighter.CLASH_PUSH * defender.stats.mass(), Fighter.PARRY_COOLDOWN)
	defender.clash(-push * Fighter.CLASH_PUSH * attacker.stats.mass(), 0.0)
	_renew_slowmo(attacker, defender)


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
	_time_engine.play(DUEL_TIME_SCALE, DUEL_DURATION)


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
	if not _time_engine.is_active():
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
			fighter.fall_out(_feet_to_center(map.respawn_position(), fighter.stats))


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
