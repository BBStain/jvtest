class_name GameSetup
extends RefCounted
## Ce que le menu transmet à la partie :
## quels appareils, quel personnage et quelle arme pour quel joueur, et sur quelle map.
## (Les "static var" gardent leur valeur quand on change de scène.)

## Toutes les maps du jeu. Pour en ajouter une : crée sa scène dans scenes/maps/ et ajoute-la ici.
## Une map du jeu est une scène (.tscn) ou une map faite avec l'éditeur et livrée avec le jeu (.json
## de maps_editeur/) : les deux se jouent pareil, aussi en ligne.
const MAPS := [
	"res://scenes/maps/arene.tscn",
	"res://maps_editeur/La_Tour.json",
]
const SAVED_MAP_PREFIX := "carte:"
const EDITOR_MAP := "editeur"
const MENU_SCENE := "res://scenes/menu.tscn"

## Tous les personnages du jeu. Pour en ajouter un : crée son fichier dans characters/ et ajoute-le ici.
const CHARACTERS := [
	"res://characters/barre.tres",
	"res://characters/jumb.tres",
	"res://characters/jib.tres",
]
## Toutes les armes (choisies avec le perso). Pour en ajouter une : crée son fichier dans weapons/
## et ajoute-le ici. La première est celle par défaut.
const WEAPONS := [
	"res://weapons/mains_nues.tres",
	"res://weapons/katana.tres",
	"res://weapons/marteau.tres",
	"res://weapons/lance.tres",
	"res://weapons/nunchaku.tres",
	"res://weapons/arc.tres",
]

## Un élément par joueur ; chaque élément est la liste de ses appareils (voir InputBindings).
static var player_devices: Array = []
## Le personnage de chaque joueur (chemin d'un fichier de CHARACTERS). Vide = le premier de la liste.
static var player_characters: Array = []
## L'arme de chaque joueur (chemin d'un fichier de WEAPONS). Vide = mains nues.
static var player_weapons: Array = []
## La map de la partie : le chemin d'une scène de MAPS, ou une map faite dans l'éditeur
## ("carte:" + son nom de sauvegarde, ou EDITOR_MAP pour celle qu'on teste depuis l'éditeur).
static var map_path: String = MAPS[0]
## La map qu'on teste depuis l'éditeur (les données de MapData), quand map_path == EDITOR_MAP.
static var editor_map: Dictionary = {}
## Où revient-on en quittant la partie (vide = le menu). L'éditeur y met sa scène quand on teste.
static var return_scene := ""
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


## L'arme du joueur n°player_index (mains nues si rien n'a été choisi).
static func weapon_for(player_index: int) -> WeaponStats:
	var path: String = WEAPONS[0]
	if player_index < player_weapons.size() and player_weapons[player_index] != "":
		path = player_weapons[player_index]
	return load(path) as WeaponStats


## Toutes les maps qu'on peut choisir : celles du jeu (MAPS), puis celles faites dans l'éditeur.
static func all_maps() -> Array[String]:
	var maps: Array[String] = []
	maps.assign(MAPS)
	for saved in MapData.list_saved():
		# Une map de l'éditeur devenue map du jeu n'apparaît qu'une fois (sauf si on en a sauvé sa version).
		var official := "%s/%s.json" % [MapData.BUNDLED_DIR, saved] in MAPS
		if not official or FileAccess.file_exists(MapData.file_path(saved)):
			maps.append(SAVED_MAP_PREFIX + saved)
	return maps


## Crée la map d'un chemin de all_maps() (ou EDITOR_MAP). Une map de l'éditeur introuvable
## donne la première map du jeu.
static func make_map(path: String) -> GameMap:
	if path == EDITOR_MAP and not editor_map.is_empty():
		return MapBuilder.build(editor_map)
	if path.begins_with(SAVED_MAP_PREFIX):
		var data := MapData.load_saved(path.trim_prefix(SAVED_MAP_PREFIX))
		if not data.is_empty():
			return MapBuilder.build(data)
		path = MAPS[0]
	if not path.begins_with("res://"):
		path = MAPS[0]
	if path.ends_with(".json"):
		var data := MapData.from_json(FileAccess.get_file_as_string(path))
		if not data.is_empty():
			return MapBuilder.build(data)
		path = MAPS[0]
	return (load(path) as PackedScene).instantiate() as GameMap


## La scène où l'on revient en quittant une partie : le menu, ou l'éditeur si on y testait sa map.
static func exit_scene() -> String:
	return return_scene if return_scene != "" else MENU_SCENE
