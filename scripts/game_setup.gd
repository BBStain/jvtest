class_name GameSetup
extends RefCounted
## Ce que le menu transmet à la partie :
## quels appareils, quel personnage pour quel joueur, et sur quelle map.
## (Les "static var" gardent leur valeur quand on change de scène.)

## Toutes les maps du jeu. Pour en ajouter une : crée sa scène dans scenes/maps/ et ajoute-la ici.
const MAPS := [
	"res://scenes/maps/arene.tscn",
]
## Tous les personnages du jeu. Pour en ajouter un : crée son fichier dans characters/ et ajoute-le ici.
const CHARACTERS := [
	"res://characters/barre.tres",
]

## Un élément par joueur ; chaque élément est la liste de ses appareils (voir InputBindings).
static var player_devices: Array = []
## Le personnage de chaque joueur (chemin d'un fichier de CHARACTERS). Vide = le premier de la liste.
static var player_characters: Array = []
## La map de la partie (chemin d'une scène de MAPS).
static var map_path: String = MAPS[0]
## Le nombre de vies de chaque joueur (réglable dans OPTIONS).
static var lives := 3


## Si on lance directement la scène de combat (F6 dans l'éditeur), sans passer par le
## menu : 2 joueurs, J1 = clavier gauche + manette 1, J2 = clavier droit + manette 2.
static func devices_or_default() -> Array:
	if not player_devices.is_empty():
		return player_devices
	var defaults := []
	for i in 2:
		defaults.append([{"type": "keyboard", "layout": i}, {"type": "joypad", "id": i}])
	return defaults


## Le personnage du joueur n°player_index (le premier personnage si rien n'a été choisi).
static func character_for(player_index: int) -> CharacterStats:
	var path: String = CHARACTERS[0]
	if player_index < player_characters.size() and player_characters[player_index] != "":
		path = player_characters[player_index]
	return load(path) as CharacterStats
