class_name MenuInput
extends RefCounted
## Lit les manettes et le clavier dans les menus et dit QUI a appuyé et SUR QUOI.
## read(event) renvoie {} si l'appui ne compte pas, sinon :
##   {"device": l'appareil (comme dans InputBindings), "action": ..., "stick": true si ça vient du stick}
## action = "up", "down", "left", "right", "confirm", "back", "start", ou "" pour une autre touche.
##
##   manette : stick ou croix pour choisir, A pour valider, B pour revenir, Start
##   clavier gauche : Z Q S D, Espace / F / Entrée pour valider, Échap / C pour revenir
##   clavier droit : flèches, L / K pour valider, U / Retour arrière pour revenir

const STICK_PRESS := 0.6     ## stick poussé au-delà : compte comme un appui
const STICK_RELEASE := 0.3   ## stick revenu en deçà : prêt pour l'appui suivant

# Touches du clavier gauche et du clavier droit (touches physiques).
const KEYS_LEFT_SIDE := {
	KEY_W: "up", KEY_S: "down", KEY_A: "left", KEY_D: "right",
	KEY_SPACE: "confirm", KEY_F: "confirm", KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm",
	KEY_ESCAPE: "back", KEY_C: "back",
}
const KEYS_RIGHT_SIDE := {
	KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right",
	KEY_L: "confirm", KEY_K: "confirm", KEY_KP_0: "confirm", KEY_KP_1: "confirm",
	KEY_U: "back", KEY_BACKSPACE: "back", KEY_KP_4: "back",
	KEY_I: "", KEY_J: "", KEY_KP_2: "", KEY_KP_3: "",  # autres touches du joueur de droite
}
const JOY_BUTTON_ACTIONS := {
	JOY_BUTTON_DPAD_UP: "up", JOY_BUTTON_DPAD_DOWN: "down",
	JOY_BUTTON_DPAD_LEFT: "left", JOY_BUTTON_DPAD_RIGHT: "right",
	JOY_BUTTON_A: "confirm", JOY_BUTTON_B: "back", JOY_BUTTON_START: "start",
}

var _stick_held := {}  ## "manette:axe" -> le stick est déjà poussé


func read(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key == KEY_SHIFT and event.location == KEY_LOCATION_RIGHT:
			return _press({"type": "keyboard", "layout": 1}, "")  # Shift droit = course du joueur de droite
		if KEYS_RIGHT_SIDE.has(key):
			return _press({"type": "keyboard", "layout": 1}, KEYS_RIGHT_SIDE[key])
		return _press({"type": "keyboard", "layout": 0}, KEYS_LEFT_SIDE.get(key, ""))
	if event is InputEventJoypadButton and event.pressed:
		return _press({"type": "joypad", "id": event.device}, JOY_BUTTON_ACTIONS.get(event.button_index, ""))
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var latch := "%d:%d" % [event.device, event.axis]
		if absf(event.axis_value) < STICK_RELEASE:
			_stick_held[latch] = false
		elif absf(event.axis_value) > STICK_PRESS and not _stick_held.get(latch, false):
			_stick_held[latch] = true
			var action := ""
			if event.axis == JOY_AXIS_LEFT_X:
				action = "right" if event.axis_value > 0.0 else "left"
			else:
				action = "down" if event.axis_value > 0.0 else "up"
			var press := _press({"type": "joypad", "id": event.device}, action)
			press.stick = true
			return press
	return {}


func _press(device: Dictionary, action: String) -> Dictionary:
	return {"device": device, "action": action, "stick": false}
