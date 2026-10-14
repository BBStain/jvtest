extends Node
## La musique du jeu (chargée tout le temps, sous le nom « Music »).
##
## Chaque playlist est un dossier de musique/ : on y dépose des fichiers .ogg, .mp3 ou .wav et le jeu
## les trouve tout seul (rien d'autre à changer). Les morceaux passent l'un après l'autre, dans
## l'ordre de leur nom (01-..., 02-...), puis la playlist recommence. Un dossier vide = silence.
##   musique/menu/  : tous les écrans du menu (et l'éditeur de map)
##   musique/arene/ : pendant une partie sur l'Arène (une map = un dossier au nom de sa scène)
## Les maps faites dans l'éditeur jouent la playlist de l'Arène.
## La musique ne ralentit pas avec les ralentis (Engine.time_scale ne touche pas au son)
## et continue pendant la pause. Chaque joueur l'entend chez lui (rien à envoyer en ligne).

const FOLDER := "res://musique/"
const MENU := "menu"
const CUSTOM_MAP_PLAYLIST := "arene"  ## la playlist des maps faites dans l'éditeur
const EXTENSIONS := ["ogg", "mp3", "wav"]

var playlist := ""                    ## la playlist en cours ("" = aucune)
var tracks: Array[String] = []        ## ses morceaux
var track_index := -1                 ## le morceau qui joue (-1 = aucun)
var _player := AudioStreamPlayer.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # la musique continue pendant la pause
	add_child(_player)
	_player.finished.connect(_next_track)


## Lance une playlist (le nom de son dossier). Si elle joue déjà, on ne la recommence pas
## (passer d'un écran du menu à l'autre ne coupe pas le morceau).
func play_playlist(playlist_name: String) -> void:
	if playlist_name == playlist:
		return
	playlist = playlist_name
	tracks = tracks_in(FOLDER + playlist_name)
	track_index = -1
	_player.stop()
	_player.stream = null
	_next_track()


## La playlist d'une map (un chemin de GameSetup.all_maps(), ou GameSetup.EDITOR_MAP).
static func playlist_for_map(map_path: String) -> String:
	if map_path.begins_with("res://"):
		return map_path.get_file().get_basename()
	return CUSTOM_MAP_PLAYLIST


## Les morceaux d'un dossier, triés par nom. Dans le jeu exporté (web), le dossier ne contient
## plus que les fichiers « .import » : on retrouve le nom du morceau en enlevant ce bout.
static func tracks_in(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		file = file.trim_suffix(".import")
		if file.get_extension().to_lower() in EXTENSIONS and not found.has(folder.path_join(file)):
			found.append(folder.path_join(file))
	found.sort()
	return found


func _next_track() -> void:
	if tracks.is_empty():
		return
	track_index = (track_index + 1) % tracks.size()
	var stream := load(tracks[track_index]) as AudioStream
	if stream == null:
		return
	_player.stream = stream
	_player.play()
