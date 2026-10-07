class_name InputBindings
extends RefCounted
## Les touches et boutons de chaque joueur, enregistrés au lancement du jeu.
##
## Manette : la manette n°1 connectée = joueur 1, la n°2 = joueur 2, etc.
##   Stick gauche ou croix : se déplacer / viser le dash
##   A : sauter    X : attaquer    Gâchette gauche (ou LB) : dash
##
## Clavier (pour tester sur ordinateur). Ce sont des touches PHYSIQUES :
## "W A S D" ici correspond à "Z Q S D" sur un clavier français (AZERTY).

const KEYBOARD := [
	# Joueur 1 : Z Q S D pour bouger, Espace saut, F attaque, G dash
	{
		"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"jump": [KEY_SPACE], "attack": [KEY_F], "dash": [KEY_G],
	},
	# Joueur 2 : flèches pour bouger, L saut, K attaque, J dash (ou pavé numérique 0 / 1 / 2)
	{
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"jump": [KEY_L, KEY_KP_0], "attack": [KEY_K, KEY_KP_1], "dash": [KEY_J, KEY_KP_2],
	},
	{},  # Joueur 3 : manette seulement
	{},  # Joueur 4 : manette seulement
]

const GAMEPAD_BUTTONS := {
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
	"jump": [JOY_BUTTON_A], "attack": [JOY_BUTTON_X], "dash": [JOY_BUTTON_LEFT_SHOULDER],
}
const GAMEPAD_AXES := {
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"dash": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}
const ACTIONS := ["left", "right", "up", "down", "jump", "attack", "dash"]
const DEADZONE := 0.35


static func action_prefix(player_index: int) -> String:
	return "p%d_" % (player_index + 1)


static func register(player_count: int) -> void:
	for i in player_count:
		var keys: Dictionary = KEYBOARD[i] if i < KEYBOARD.size() else {}
		for action in ACTIONS:
			var action_name: String = action_prefix(i) + action
			_reset_action(action_name)
			for key in keys.get(action, []):
				var key_event := InputEventKey.new()
				key_event.physical_keycode = key
				InputMap.action_add_event(action_name, key_event)
			for button in GAMEPAD_BUTTONS.get(action, []):
				var button_event := InputEventJoypadButton.new()
				button_event.device = i
				button_event.button_index = button
				InputMap.action_add_event(action_name, button_event)
			if GAMEPAD_AXES.has(action):
				var axis_event := InputEventJoypadMotion.new()
				axis_event.device = i
				axis_event.axis = GAMEPAD_AXES[action][0]
				axis_event.axis_value = GAMEPAD_AXES[action][1]
				InputMap.action_add_event(action_name, axis_event)

	# Rejouer à la fin de la partie : Entrée / R au clavier, Start ou A sur n'importe quelle manette.
	_reset_action("restart")
	for key in [KEY_ENTER, KEY_KP_ENTER, KEY_R]:
		var restart_key := InputEventKey.new()
		restart_key.physical_keycode = key
		InputMap.action_add_event("restart", restart_key)
	for button in [JOY_BUTTON_START, JOY_BUTTON_A]:
		var restart_button := InputEventJoypadButton.new()
		restart_button.device = -1  # n'importe quelle manette
		restart_button.button_index = button
		InputMap.action_add_event("restart", restart_button)


static func _reset_action(action_name: String) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, DEADZONE)
