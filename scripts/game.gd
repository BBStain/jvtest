class_name Game
extends Node2D
## Le chef d'orchestre de la partie : crée les joueurs, leur passe les commandes,
## gère les coups, les chocs d'attaques, les chutes hors de la map, la caméra et la fin de partie.
## Les joueurs et leurs appareils viennent de l'écran de connexion (lobby.gd, via GameSetup).

const PLAYER_COLORS := [
	Color(0.95, 0.35, 0.35),  # Joueur 1 : rouge
	Color(0.35, 0.65, 1.0),   # Joueur 2 : bleu
	Color(0.45, 0.9, 0.45),   # Joueur 3 : vert
	Color(1.0, 0.85, 0.3),    # Joueur 4 : jaune
]
## Au-delà de ces limites, le joueur est sorti de la map et perd une vie.
const BLAST_ZONE := Rect2(-2150, -700, 5400, 1650)
const RESTART_DELAY := 1.0   ## évite de relancer par erreur en martelant les boutons
const LOBBY_SCENE := "res://scenes/lobby.tscn"

# --- Caméra : elle suit le milieu des joueurs et dézoome quand ils s'éloignent ---
const CAMERA_MARGIN := Vector2(700, 450)   ## espace gardé autour des joueurs (en pixels)
const CAMERA_ZOOM_MIN := 0.3               ## zoom le plus éloigné (plus petit = voit plus loin)
const CAMERA_ZOOM_MAX := 1.2               ## zoom le plus proche
const CAMERA_SMOOTHING := 4.0              ## plus grand = la caméra réagit plus vite

var fighters: Array[Fighter] = []
var _match_over := false
var _match_over_time := 0.0

@onready var _spawn_points: Array[Node] = $SpawnPoints.get_children()
@onready var _respawn_point: Marker2D = $RespawnPoint
@onready var _end_screen: Control = $UI/EndScreen
@onready var _winner_label: Label = $UI/EndScreen/Winner
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	InputBindings.register_menu_actions()
	var player_devices := GameSetup.devices_or_default()
	for i in player_devices.size():
		InputBindings.register_player(i, player_devices[i])
		var fighter := Fighter.new()
		fighter.name = "Joueur%d" % (i + 1)
		fighter.player_index = i
		fighter.color = PLAYER_COLORS[i]
		fighter.input_source = LocalInputSource.new(i)
		fighter.position = (_spawn_points[i] as Node2D).position
		fighter.facing = 1.0 if fighter.position.x < _respawn_point.position.x else -1.0
		add_child(fighter)
		fighter.show_lives()
		fighters.append(fighter)
	_update_camera(1.0, true)


func _process(delta: float) -> void:
	_update_camera(delta, false)


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
func _update_camera(delta: float, instant: bool) -> void:
	var box := Rect2()
	var first := true
	for fighter in fighters:
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
	var needed := box.size + CAMERA_MARGIN
	var target_zoom := clampf(minf(view_size.x / needed.x, view_size.y / needed.y), CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
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
## Si une attaque légère contre une attaque lourde, celui qui a contré a une recharge doublée.
func _resolve_clashes() -> void:
	for i in fighters.size():
		for j in range(i + 1, fighters.size()):
			var a := fighters[i]
			var b := fighters[j]
			if not (a.is_attack_active() and b.is_attack_active()):
				continue
			if a.attack_center().distance_to(b.attack_center()) > a.attack_radius() + b.attack_radius():
				continue
			var push := a.global_position - b.global_position
			if push.length() < 1.0:
				push = Vector2(-1.0, 0.0)
			push.y = 0.0
			push = push.normalized()
			var heavy_countered := a.is_heavy_attack() != b.is_heavy_attack()
			_spawn_clash_mark((a.attack_center() + b.attack_center()) / 2.0, heavy_countered)
			a.clash(push, b.is_heavy_attack() and not a.is_heavy_attack())
			b.clash(-push, a.is_heavy_attack() and not b.is_heavy_attack())


## Laisse une marque sur le terrain à l'endroit du contre (orange si une attaque lourde a été contrée).
func _spawn_clash_mark(where: Vector2, heavy_countered: bool) -> void:
	var mark := ClashMark.new()
	mark.position = where
	mark.color = Color(1.0, 0.6, 0.2) if heavy_countered else Color(1, 1, 1)
	add_child(mark)


func _resolve_hits() -> void:
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
				victim.take_hit(hit_dir, attacker.attack_knockback())
				attacker.mark_attack_hit()
				break


func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := center.clamp(rect.position, rect.end)
	return center.distance_to(closest) <= radius


func _check_blast_zone() -> void:
	for fighter in fighters:
		if not fighter.eliminated and not BLAST_ZONE.has_point(fighter.global_position):
			fighter.fall_out(_respawn_point.position)


func _check_end_of_match() -> void:
	var alive: Array[Fighter] = []
	for fighter in fighters:
		if not fighter.eliminated:
			alive.append(fighter)
	if alive.size() > 1:
		return
	_match_over = true
	_match_over_time = 0.0
	if alive.size() == 1:
		var winner := alive[0]
		_winner_label.text = "Joueur %d gagne !" % (winner.player_index + 1)
		_winner_label.add_theme_color_override("font_color", winner.color)
	else:
		_winner_label.text = "Égalité !"
	_end_screen.visible = true
