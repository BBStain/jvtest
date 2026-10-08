class_name Game
extends Node2D
## Le chef d'orchestre de la partie : crée les joueurs, leur passe les commandes,
## gère les coups, les chocs d'attaques, les chutes hors de la map, la caméra et la fin de partie.
## Les joueurs, leurs appareils, leurs personnages et la map viennent de GameSetup.
## La map est une scène à part (scenes/maps/), chargée au début de la partie.

const PLAYER_COLORS := [
	Color(0.95, 0.35, 0.35),  # Joueur 1 : rouge
	Color(0.35, 0.65, 1.0),   # Joueur 2 : bleu
	Color(0.45, 0.9, 0.45),   # Joueur 3 : vert
	Color(1.0, 0.85, 0.3),    # Joueur 4 : jaune
]
const RESTART_DELAY := 1.0   ## évite de relancer par erreur en martelant les boutons
const LOBBY_SCENE := "res://scenes/lobby.tscn"

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

var fighters: Array[Fighter] = []
var _match_over := false
var _match_over_time := 0.0
var _time_engine := TimeEngine.new()
var _duel: Array[Fighter] = []             ## les deux joueurs du micro-duel en cours

var map: GameMap
@onready var _end_screen: Control = $UI/EndScreen
@onready var _winner_label: Label = $UI/EndScreen/Winner
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	add_child(_time_engine)
	map = (load(GameSetup.map_path) as PackedScene).instantiate()
	add_child(map)
	move_child(map, 0)  # le décor est dessiné derrière les joueurs
	InputBindings.register_menu_actions()
	var player_devices := GameSetup.devices_or_default()
	for i in player_devices.size():
		InputBindings.register_player(i, player_devices[i])
		var fighter := Fighter.new()
		fighter.name = "Joueur%d" % (i + 1)
		fighter.player_index = i
		fighter.stats = GameSetup.character_for(i)
		fighter.color = PLAYER_COLORS[i]
		fighter.input_source = LocalInputSource.new(i)
		fighter.position = map.spawn_position(i)
		fighter.facing = 1.0 if fighter.position.x < map.respawn_position().x else -1.0
		add_child(fighter)
		fighter.life_lost.connect(_on_life_lost)
		fighter.show_lives()
		fighters.append(fighter)
	_update_camera(1.0, true)


func _process(delta: float) -> void:
	if not _time_engine.is_active():
		_duel.clear()
	_update_camera(delta / Engine.time_scale, false)  # la caméra garde sa vitesse pendant un ralenti


func _physics_process(delta: float) -> void:
	if _match_over:
		_match_over_time += delta
		if _match_over_time > RESTART_DELAY:
			if Input.is_action_just_pressed("restart"):
				get_tree().reload_current_scene()
			elif Input.is_action_just_pressed("back_to_menu"):
				get_tree().change_scene_to_file(LOBBY_SCENE)
		return

	for fighter in fighters:
		fighter.target = _closest_opponent(fighter)
	for fighter in fighters:
		fighter.physics_tick(fighter.input_source.poll(), delta)

	_resolve_clashes()
	_resolve_hits()
	_check_blast_zone()
	_check_end_of_match()


## Cadre tous les joueurs encore en jeu : centre au milieu d'eux, zoom selon leur écart.
## Pendant un micro-duel, la caméra zoome sur les deux duellistes.
func _update_camera(delta: float, instant: bool) -> void:
	var box := Rect2()
	var first := true
	var framed := _duel if not _duel.is_empty() else fighters
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
	var needed := box.size + (DUEL_CAMERA_MARGIN if not _duel.is_empty() else CAMERA_MARGIN)
	var zoom_max := DUEL_ZOOM_MAX if not _duel.is_empty() else CAMERA_ZOOM_MAX
	var target_zoom := clampf(minf(view_size.x / needed.x, view_size.y / needed.y), CAMERA_ZOOM_MIN, zoom_max)
	var target_position := box.get_center()
	if instant:
		_camera.position = target_position
		_camera.zoom = Vector2.ONE * target_zoom
		return
	var weight := 1.0 - exp(-CAMERA_SMOOTHING * delta)
	_camera.position = _camera.position.lerp(target_position, weight)
	_camera.zoom = _camera.zoom.lerp(Vector2.ONE * target_zoom, weight)


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
			if a.attack_center().distance_to(b.attack_center()) > a.attack_radius() + b.attack_radius():
				continue
			_clash(a, b, (a.attack_center() + b.attack_center()) / 2.0)


## Les attaques de a et b s'annulent : les deux sont repoussés et une marque apparaît à "where".
## Lourde contre lourde : micro-explosion qui éjecte fort les deux joueurs.
## Lourde contrée par une légère : micro-duel, la caméra zoome et le temps ralentit.
func _clash(a: Fighter, b: Fighter, where: Vector2) -> void:
	var push := a.global_position - b.global_position
	if push.length() < 1.0:
		push = Vector2(-1.0, 0.0)
	push.y = 0.0
	push = push.normalized()
	var heavy_countered := a.is_heavy_attack() != b.is_heavy_attack()
	var explosion := a.is_heavy_attack() and b.is_heavy_attack()
	_spawn_clash_mark(where, heavy_countered or explosion)
	a.clash(push, heavy_countered, explosion)
	b.clash(-push, heavy_countered, explosion)
	if explosion:
		var boom := MicroExplosion.new()
		boom.position = where
		add_child(boom)
	elif heavy_countered:
		_start_duel(a, b)


## Micro-duel : la caméra serre les deux joueurs et le jeu ralentit pendant quelques secondes.
func _start_duel(a: Fighter, b: Fighter) -> void:
	_duel = [a, b]
	_time_engine.play(DUEL_TIME_SCALE, DUEL_DURATION)


## Un duelliste touché ou tombé : le duel est tranché, le temps revient à la normale.
func _on_life_lost(fighter: Fighter) -> void:
	if fighter in _duel:
		_time_engine.stop()


## Laisse une marque sur le terrain à l'endroit du contre (orange si une attaque lourde a été contrée).
func _spawn_clash_mark(where: Vector2, heavy_countered: bool) -> void:
	var mark := ClashMark.new()
	mark.position = where
	mark.color = Color(1.0, 0.6, 0.2) if heavy_countered else Color(1, 1, 1)
	add_child(mark)


## On repère d'abord tous les coups de la frame, puis on les applique : si deux joueurs se
## touchent exactement en même temps, c'est un choc, les deux attaques s'annulent et personne ne perd de vie.
func _resolve_hits() -> void:
	var landed: Array[Dictionary] = []
	for attacker in fighters:
		if not attacker.is_attack_active():
			continue
		for victim in fighters:
			if victim == attacker or not victim.can_be_hit():
				continue
			if _circle_hits_rect(attacker.attack_center(), attacker.attack_radius(), victim.body_rect()):
				var hit_dir := (victim.global_position - attacker.global_position).normalized()
				if not attacker.is_heavy_attack():
					hit_dir = attacker.attack_direction()
				landed.append({"attacker": attacker, "victim": victim, "dir": hit_dir,
					"knockback": attacker.attack_knockback(), "heavy": attacker.is_heavy_attack()})
				break
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
		if victim.is_blocking():
			_hit_shield(attacker, victim, hit.heavy)
			continue
		victim.take_hit(hit.dir, hit.knockback)
		attacker.mark_attack_hit()


## Le coup tombe sur un bouclier : personne ne perd de vie, l'attaquant est repoussé mais peut
## refrapper tout de suite, et le bouclier perd 1 point (2 pour une attaque lourde).
func _hit_shield(attacker: Fighter, victim: Fighter, heavy: bool) -> void:
	var push := victim.global_position - attacker.global_position
	push.y = 0.0
	push = push.normalized() if push.length() > 1.0 else Vector2(attacker.facing, 0.0)
	attacker.hit_shield(-push)
	if victim.absorb_hit(push, heavy):
		_spawn_clash_mark(victim.global_position, true)


func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := center.clamp(rect.position, rect.end)
	return center.distance_to(closest) <= radius


func _check_blast_zone() -> void:
	for fighter in fighters:
		if not fighter.eliminated and not map.blast_zone.has_point(fighter.global_position):
			fighter.fall_out(map.respawn_position())


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
		var winner := alive[0]
		_winner_label.text = "Joueur %d gagne !" % (winner.player_index + 1)
		_winner_label.add_theme_color_override("font_color", winner.color)
	else:
		_winner_label.text = "Égalité !"
	_end_screen.visible = true
