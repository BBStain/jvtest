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
const SHIELD_BREAK_TIME_SCALE := 0.3        ## bouclier cassé : ralenti (3 fois moins vite)...
const SHIELD_BREAK_SLOWMO := 1.2            ## ... pendant 1,2 vraie seconde
const PARRY_COLOR := Color(0.55, 0.85, 1.0)  ## la marque d'un blocage parfait

var fighters: Array[Fighter] = []
var player_devices: Array = []             ## les appareils de chaque joueur (voir InputBindings)
var pause_menu: PauseMenu                  ## le menu pause, quand il est ouvert
var _resume_grace := 0                     ## en sortant de la pause, on ignore les touches un instant
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
		fighter.input_source = LocalInputSource.new(i)
		fighter.position = _feet_to_center(map.spawn_position(i), fighter.stats)
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
				get_tree().change_scene_to_file(MENU_SCENE)
		return

	for fighter in fighters:
		fighter.target = _closest_opponent(fighter)
	for fighter in fighters:
		var input := fighter.input_source.poll()
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
	_check_end_of_match()


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
	get_tree().paused = true


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
			# Deux attaques légères dans le même sens (l'un frappe le dos de l'autre) : pas de choc.
			if not a.is_heavy_attack() and not b.is_heavy_attack() \
					and a.attack_direction().dot(b.attack_direction()) > 0.0:
				continue
			var closest := Geometry2D.get_closest_points_between_segments(
				a.attack_start(), a.attack_center(), b.attack_start(), b.attack_center())
			if closest[0].distance_to(closest[1]) > a.attack_radius() + b.attack_radius():
				continue
			_clash(a, b, (closest[0] + closest[1]) / 2.0)


## Les attaques de a et b s'annulent : les deux sont repoussés et une marque apparaît à "where".
## Chacun est repoussé d'autant plus fort que l'autre est lourd (voir CharacterStats.mass()).
## Légère contre légère : petit temps mort pour les deux.
## Lourde contre lourde : micro-explosion qui éjecte fort les deux joueurs.
## Lourde contrée par une légère : micro-duel, la caméra zoome et le temps ralentit ; celui qui
## a lancé la lourde ne frappe plus pendant 1 s, celui qui a contré peut refrapper tout de suite.
## Pendant un ralenti, chaque contre le fait repartir pour toute sa durée.
func _clash(a: Fighter, b: Fighter, where: Vector2) -> void:
	var push := _push_dir(a, b)
	var heavy_countered := a.is_heavy_attack() != b.is_heavy_attack()
	var explosion := a.is_heavy_attack() and b.is_heavy_attack()
	_spawn_clash_mark(where, heavy_countered or explosion)
	if explosion:
		a.clash(push * Fighter.HEAVY_CLASH_PUSH * b.stats.mass(), Fighter.CLASH_LOCKOUT, Fighter.HEAVY_CLASH_LIFT)
		b.clash(-push * Fighter.HEAVY_CLASH_PUSH * a.stats.mass(), Fighter.CLASH_LOCKOUT, Fighter.HEAVY_CLASH_LIFT)
		var boom := MicroExplosion.new()
		boom.position = where
		add_child(boom)
		_time_engine.renew()
	elif heavy_countered:
		for fighter in [a, b]:
			var other: Fighter = b if fighter == a else a
			var cooldown := Fighter.HEAVY_COUNTERED_COOLDOWN if fighter.is_heavy_attack() else 0.0
			var direction := push if fighter == a else -push
			fighter.clash(direction * Fighter.HEAVY_COUNTER_PUSH * other.stats.mass(), cooldown)
		_start_duel(a, b)
	else:
		a.clash(push * Fighter.CLASH_PUSH * b.stats.mass())
		b.clash(-push * Fighter.CLASH_PUSH * a.stats.mass())
		_time_engine.renew()


## Blocage parfait : le défenseur a appuyé sur B pile au moment du coup. C'est un contre :
## les deux sont repoussés, le bouclier ne craque pas, celui qui frappait ne frappe plus
## pendant 1 s et le défenseur peut riposter tout de suite.
func _parry(attacker: Fighter, defender: Fighter) -> void:
	var push := _push_dir(attacker, defender)
	_spawn_clash_mark((attacker.global_position + defender.global_position) / 2.0, false, PARRY_COLOR)
	attacker.clash(push * Fighter.CLASH_PUSH * defender.stats.mass(), Fighter.PARRY_COOLDOWN)
	defender.clash(-push * Fighter.CLASH_PUSH * attacker.stats.mass(), 0.0)
	_time_engine.renew()


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


## On repère d'abord tous les coups de la frame, puis on les applique : si deux joueurs se
## touchent exactement en même temps, c'est un choc, les deux attaques s'annulent et personne ne perd de vie.
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
		if victim.is_blocking():
			_hit_shield(attacker, victim, hit.heavy)
			continue
		victim.take_hit(hit.dir, hit.knockback)
		attacker.mark_attack_hit()


## Le coup tombe sur un bouclier : personne ne perd de vie, l'attaquant est repoussé mais peut
## refrapper tout de suite, et le bouclier craque un peu plus (2 fois plus pour une attaque lourde).
## S'il casse : ralenti, les deux joueurs sont éjectés, et celui qui l'a perdu ne frappe plus 2 s.
func _hit_shield(attacker: Fighter, victim: Fighter, heavy: bool) -> void:
	var push := victim.global_position - attacker.global_position
	push.y = 0.0
	push = push.normalized() if push.length() > 1.0 else Vector2(attacker.facing, 0.0)
	attacker.hit_shield(-push)
	if not victim.absorb_hit(push, heavy):
		return
	_spawn_clash_mark(victim.global_position, true)
	victim.shield_burst(push, true)
	attacker.shield_burst(-push, false)
	var burst := MicroExplosion.new()
	burst.color = Color(0.75, 0.9, 1.0)
	burst.position = victim.global_position
	add_child(burst)
	if _duel.is_empty():
		_time_engine.play(SHIELD_BREAK_TIME_SCALE, SHIELD_BREAK_SLOWMO)
	else:
		_time_engine.renew()  # pendant un micro-duel, le duel continue (et repart pour toute sa durée)


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
		var winner := alive[0]
		_winner_label.text = "Joueur %d gagne !" % (winner.player_index + 1)
		_winner_label.add_theme_color_override("font_color", winner.color)
	else:
		_winner_label.text = "Égalité !"
	_end_screen.visible = true
