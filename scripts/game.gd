extends Node2D
## Le chef d'orchestre de la partie : crée les joueurs, leur passe les commandes,
## gère les coups, les chocs d'attaques, les chutes hors de la map et la fin de partie.

const PLAYER_COUNT := 2      ## nombre de joueurs (le code est prêt pour 4)
const MAX_PLAYERS := 4
const PLAYER_COLORS := [
	Color(0.95, 0.35, 0.35),  # Joueur 1 : rouge
	Color(0.35, 0.65, 1.0),   # Joueur 2 : bleu
	Color(0.45, 0.9, 0.45),   # Joueur 3 : vert
	Color(1.0, 0.85, 0.3),    # Joueur 4 : jaune
]
## Au-delà de ces limites, le joueur est sorti de la map et perd une vie.
const BLAST_ZONE := Rect2(-400, -700, 2080, 1650)
const RESTART_DELAY := 1.0   ## évite de relancer par erreur en martelant les boutons

var fighters: Array[Fighter] = []
var _match_over := false
var _match_over_time := 0.0

@onready var _spawn_points: Array[Node] = $SpawnPoints.get_children()
@onready var _respawn_point: Marker2D = $RespawnPoint
@onready var _end_screen: Control = $UI/EndScreen
@onready var _winner_label: Label = $UI/EndScreen/Winner
@onready var _gamepad_hint: Label = $UI/GamepadHint


func _ready() -> void:
	InputBindings.register(MAX_PLAYERS)
	for i in PLAYER_COUNT:
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


func _physics_process(delta: float) -> void:
	_gamepad_hint.visible = Input.get_connected_joypads().is_empty()

	if _match_over:
		_match_over_time += delta
		if _match_over_time > RESTART_DELAY and Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return

	for fighter in fighters:
		fighter.target = _closest_opponent(fighter)
	for fighter in fighters:
		fighter.physics_tick(fighter.input_source.poll(), delta)

	_resolve_clashes()
	_resolve_hits()
	_check_blast_zone()
	_check_end_of_match()


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
func _resolve_clashes() -> void:
	for i in fighters.size():
		for j in range(i + 1, fighters.size()):
			var a := fighters[i]
			var b := fighters[j]
			if not (a.is_attack_active() and b.is_attack_active()):
				continue
			if a.attack_center().distance_to(b.attack_center()) > Fighter.ATTACK_RADIUS * 2.0:
				continue
			var push := a.global_position - b.global_position
			if push.length() < 1.0:
				push = Vector2(-1.0, 0.0)
			push.y = 0.0
			push = push.normalized()
			a.clash(push)
			b.clash(-push)


func _resolve_hits() -> void:
	for attacker in fighters:
		if not attacker.is_attack_active():
			continue
		for victim in fighters:
			if victim == attacker or not victim.can_be_hit():
				continue
			if _circle_hits_rect(attacker.attack_center(), Fighter.ATTACK_RADIUS, victim.body_rect()):
				victim.take_hit(attacker.attack_direction())
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
