class_name GameSetup
extends RefCounted
## Ce que l'écran de connexion transmet à la partie : quels appareils pour quel joueur.
## (Les "static var" gardent leur valeur quand on change de scène.)

## Un élément par joueur ; chaque élément est la liste de ses appareils (voir InputBindings).
static var player_devices: Array = []


## Si on lance directement la scène de combat (F6 dans l'éditeur), sans passer par l'écran
## de connexion : 2 joueurs, J1 = clavier gauche + manette 1, J2 = clavier droit + manette 2.
static func devices_or_default() -> Array:
	if not player_devices.is_empty():
		return player_devices
	var defaults := []
	for i in 2:
		defaults.append([{"type": "keyboard", "layout": i}, {"type": "joypad", "id": i}])
	return defaults
