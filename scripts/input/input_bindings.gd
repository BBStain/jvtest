class_name InputBindings
extends RefCounted
## Les touches et boutons de chaque joueur.
##
## Chaque joueur reçoit un ou plusieurs "appareils" (choisis sur l'écran de connexion) :
##   {"type": "keyboard", "layout": 0}  -> clavier, côté gauche (Z Q S D)
##   {"type": "keyboard", "layout": 1}  -> clavier, côté droit (flèches)
##   {"type": "joypad", "id": 2}        -> la manette n°2 connectée
##
## Manette : stick gauche ou croix pour bouger, A sauter, X attaque légère, Y attaque lourde,
## B bloquer, gâchette gauche (LT) courir, LB dash, stick droit attaque légère visée.
## Les touches clavier sont des touches PHYSIQUES : "W A S D" ici = "Z Q S D" sur un clavier AZERTY.

const KEYBOARD_LAYOUTS := [
	# Clavier gauche : Z Q S D pour bouger, Espace saut, F attaque légère, R attaque lourde, G dash, C blocage,
	# Shift gauche pour courir
	{
		"name": "Clavier (Z Q S D)",
		"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
		"jump": [KEY_SPACE], "attack": [KEY_F], "heavy": [KEY_R], "dash": [KEY_G],
		"block": [KEY_C], "sprint": [KEY_SHIFT], "sprint_location": KEY_LOCATION_LEFT,
	},
	# Clavier droit : flèches pour bouger, L saut, K attaque légère, I attaque lourde, J dash, U blocage,
	# Shift droit pour courir
	# (ou pavé numérique 0 / 1 / 3 / 2 / 4)
	{
		"name": "Clavier (flèches)",
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
		"jump": [KEY_L, KEY_KP_0], "attack": [KEY_K, KEY_KP_1], "heavy": [KEY_I, KEY_KP_3],
		"dash": [KEY_J, KEY_KP_2], "block": [KEY_U, KEY_KP_4],
		"sprint": [KEY_SHIFT], "sprint_location": KEY_LOCATION_RIGHT,
	},
]

const GAMEPAD_BUTTONS := {
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	"up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN],
	"jump": [JOY_BUTTON_A], "attack": [JOY_BUTTON_X], "heavy": [JOY_BUTTON_Y],
	"block": [JOY_BUTTON_B], "dash": [JOY_BUTTON_LEFT_SHOULDER],
}
const GAMEPAD_AXES := {
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"sprint": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"aim_left": [JOY_AXIS_RIGHT_X, -1.0], "aim_right": [JOY_AXIS_RIGHT_X, 1.0],
	"aim_up": [JOY_AXIS_RIGHT_Y, -1.0], "aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
}
const ACTIONS := ["left", "right", "up", "down", "jump", "attack", "heavy", "dash", "block", "sprint",
	"aim_left", "aim_right", "aim_up", "aim_down"]
const DEADZONE := 0.35

## Correctif pour la version navigateur (Godot 4.3) : le navigateur envoie les gâchettes LT / RT
## comme des axes n°6 et 7, mais la correspondance "standard" fournie par Godot les attend comme
## des boutons. Résultat : LT et RT ne faisaient rien dans le navigateur. On remplace cette
## correspondance par une version où les gâchettes sont lues sur les axes 6 et 7.
const WEB_STANDARD_MAPPING := "standard,Standard Gamepad Mapping,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:+a6,righttrigger:+a7,a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,back:b8,start:b9,leftstick:b10,rightstick:b11,dpup:b12,dpdown:b13,dpleft:b14,dpright:b15,guide:b16"

static var _web_triggers_fixed := false


## À appeler au démarrage (écran de connexion et combat). Ne fait rien hors du navigateur.
static func fix_web_triggers(force := false) -> void:
	if _web_triggers_fixed or not (force or OS.has_feature("web")):
		return
	Input.add_joy_mapping(WEB_STANDARD_MAPPING, true)
	_web_triggers_fixed = true


static func action_prefix(player_index: int) -> String:
	return "p%d_" % (player_index + 1)


## Nom lisible d'un appareil, pour l'écran de connexion.
static func device_name(device: Dictionary) -> String:
	if device.type == "keyboard":
		return KEYBOARD_LAYOUTS[device.layout].name
	var joy_name := Input.get_joy_name(device.id).get_slice("(", 0).strip_edges()
	if joy_name.length() > 28:
		joy_name = joy_name.left(28) + "…"
	return "Manette" if joy_name.is_empty() else "Manette\n" + joy_name


## Crée les actions "pN_left", "pN_jump"... du joueur N pour ses appareils.
static func register_player(player_index: int, devices: Array) -> void:
	for action in ACTIONS:
		var action_name: String = action_prefix(player_index) + action
		_reset_action(action_name)
		for device in devices:
			if device.type == "keyboard":
				for key in KEYBOARD_LAYOUTS[device.layout].get(action, []):
					var key_event := InputEventKey.new()
					key_event.physical_keycode = key
					# Shift gauche et Shift droit ont le même code : on précise de quel côté.
					key_event.location = KEYBOARD_LAYOUTS[device.layout].get(action + "_location", KEY_LOCATION_UNSPECIFIED)
					InputMap.action_add_event(action_name, key_event)
			else:
				for button in GAMEPAD_BUTTONS.get(action, []):
					var button_event := InputEventJoypadButton.new()
					button_event.device = device.id
					button_event.button_index = button
					InputMap.action_add_event(action_name, button_event)
				if GAMEPAD_AXES.has(action):
					var axis_event := InputEventJoypadMotion.new()
					axis_event.device = device.id
					axis_event.axis = GAMEPAD_AXES[action][0]
					axis_event.axis_value = GAMEPAD_AXES[action][1]
					InputMap.action_add_event(action_name, axis_event)


## Actions communes à tout le monde : rejouer / revenir au menu à la fin de la partie.
static func register_menu_actions() -> void:
	fix_web_triggers()
	_reset_action("restart")
	for key in [KEY_ENTER, KEY_KP_ENTER]:
		var restart_key := InputEventKey.new()
		restart_key.physical_keycode = key
		InputMap.action_add_event("restart", restart_key)
	for button in [JOY_BUTTON_START, JOY_BUTTON_A]:
		var restart_button := InputEventJoypadButton.new()
		restart_button.device = -1  # n'importe quelle manette
		restart_button.button_index = button
		InputMap.action_add_event("restart", restart_button)

	_reset_action("back_to_menu")
	var escape_key := InputEventKey.new()
	escape_key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("back_to_menu", escape_key)
	for button in [JOY_BUTTON_B, JOY_BUTTON_BACK]:
		var back_button := InputEventJoypadButton.new()
		back_button.device = -1
		back_button.button_index = button
		InputMap.action_add_event("back_to_menu", back_button)


## Recrée une action vide. L'action est aussi relâchée : sinon, une touche ou un stick tenu au
## moment du changement (par exemple pendant un Remap) resterait « appuyé » pour toujours,
## et le perso courrait tout seul.
static func _reset_action(action_name: String) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, DEADZONE)
	Input.action_release(action_name)
