class_name LocalInputSource
extends InputSource
## Commandes lues sur le clavier ou la manette de cette machine.

const AIM_PRESS := 0.6     ## stick droit poussé au-delà : le coup visé part
const AIM_RELEASE := 0.3   ## stick droit revenu en deçà : prêt pour le coup suivant

var _prefix: String
var _aim_latched := false  ## le stick droit est déjà poussé (un coup par pichenette)


func _init(player_index: int) -> void:
	_prefix = InputBindings.action_prefix(player_index)


func poll() -> InputState:
	var s := InputState.new()
	s.stick = Input.get_vector(_prefix + "left", _prefix + "right", _prefix + "up", _prefix + "down")
	s.down_pressed = Input.is_action_just_pressed(_prefix + "down")
	s.jump_pressed = Input.is_action_just_pressed(_prefix + "jump")
	s.jump_held = Input.is_action_pressed(_prefix + "jump")
	s.attack_pressed = Input.is_action_just_pressed(_prefix + "attack")
	# Pichenette sur le stick droit : un coup léger dans cette direction.
	var aim := Input.get_vector(_prefix + "aim_left", _prefix + "aim_right", _prefix + "aim_up", _prefix + "aim_down", 0.0)
	if aim.length() < AIM_RELEASE:
		_aim_latched = false
	elif aim.length() > AIM_PRESS and not _aim_latched:
		_aim_latched = true
		s.aimed_attack_pressed = true
		s.aim = aim.normalized()
	s.heavy_pressed = Input.is_action_just_pressed(_prefix + "heavy")
	s.heavy_held = Input.is_action_pressed(_prefix + "heavy")
	s.dash_pressed = Input.is_action_just_pressed(_prefix + "dash")
	s.block_held = Input.is_action_pressed(_prefix + "block")
	s.sprint_held = Input.is_action_pressed(_prefix + "sprint")
	return s
