class_name LocalInputSource
extends InputSource
## Commandes lues sur le clavier ou la manette de cette machine.

var _prefix: String


func _init(player_index: int) -> void:
	_prefix = InputBindings.action_prefix(player_index)


func poll() -> InputState:
	var s := InputState.new()
	s.stick = Input.get_vector(_prefix + "left", _prefix + "right", _prefix + "up", _prefix + "down")
	s.down_pressed = Input.is_action_just_pressed(_prefix + "down")
	s.jump_pressed = Input.is_action_just_pressed(_prefix + "jump")
	s.jump_held = Input.is_action_pressed(_prefix + "jump")
	s.attack_pressed = Input.is_action_just_pressed(_prefix + "attack")
	s.dash_pressed = Input.is_action_just_pressed(_prefix + "dash")
	return s
