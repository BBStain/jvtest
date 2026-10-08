class_name GameMap
extends Node2D
## Une map : le décor (sols, murs, plateformes), les points d'apparition et la zone de jeu.
##
## Pour créer une nouvelle map : duplique scenes/maps/arene.tscn (clic droit > Dupliquer),
## change le décor, puis ajoute-la dans MAPS de scripts/game_setup.gd.
## Une map doit garder ces deux nœuds :
##   SpawnPoints   -> 4 Marker2D : où apparaissent les joueurs 1 à 4 au début
##   RespawnPoint  -> un Marker2D : où l'on réapparaît après une chute

@export var map_name := "Map"
## Au-delà de ce rectangle, le joueur est sorti de la map et perd une vie.
@export var blast_zone := Rect2(-2150, -1500, 5400, 2450)


func spawn_position(player_index: int) -> Vector2:
	var points := $SpawnPoints.get_children()
	return (points[player_index % points.size()] as Node2D).position


func respawn_position() -> Vector2:
	return ($RespawnPoint as Node2D).position
