class_name GameMap
extends Node2D
## Une map : le décor (sols, murs, plateformes), les points d'apparition et la zone de jeu.
##
## L'Arène (scenes/maps/arene.tscn) est le labo : chaque nouveauté de décor (échelle, ascenseur, lianes...)
## y est essayée en premier.
##
## Pour créer une nouvelle map : duplique scenes/maps/arene.tscn (clic droit > Dupliquer),
## change le décor, puis ajoute-la dans MAPS de scripts/game_setup.gd.
## Une map doit garder ces deux nœuds :
##   SpawnPoints   -> 4 Marker2D : où apparaissent les joueurs 1 à 4 au début (le marqueur = les pieds)
##   RespawnPoint  -> un Marker2D : où l'on réapparaît après une chute (le marqueur = les pieds)
## Et si on veut, ItemSpawns -> des Marker2D : où apparaissent (puis tombent) les objets à ramasser,
## et WeaponSpawns -> des Marker2D : où apparaissent (puis tombent) les armes à ramasser.
## Les tests automatiques vérifient chaque map de MAPS (points présents, dans la zone de jeu,
## joueurs qui atterrissent bien) : s'il manque quelque chose, la mise en ligne s'arrête.

@export var map_name := "Map"
## Au-delà de ce rectangle, le joueur est sorti de la map et perd une vie.
@export var blast_zone := Rect2(-2150, -1500, 5400, 2450)
## Ville : des balises d'appel de mecha tombent sur cette map (voir Game._tick_beacons).
var has_mechas := false

var _windows: Array[BreakableWindow] = []


func spawn_position(player_index: int) -> Vector2:
	var points := $SpawnPoints.get_children()
	return (points[player_index % points.size()] as Node2D).position


func respawn_position() -> Vector2:
	return ($RespawnPoint as Node2D).position


## Où les objets apparaissent (les Marker2D du nœud ItemSpawns : l'objet apparaît là et tombe
## jusqu'à ce qu'il y a dessous). Sans ce nœud, ils apparaissent au-dessus du point de réapparition.
func item_spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if has_node("ItemSpawns"):
		for marker in $ItemSpawns.get_children():
			points.append((marker as Node2D).position)
	if points.is_empty():
		points.append(respawn_position() - Vector2(0.0, 200.0))
	return points


## Où les armes apparaissent (les Marker2D du nœud WeaponSpawns). Sans ce nœud, aux mêmes
## endroits que les objets.
func weapon_spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if has_node("WeaponSpawns"):
		for marker in $WeaponSpawns.get_children():
			points.append((marker as Node2D).position)
	if points.is_empty():
		points = item_spawn_points()
	return points


## Les plateformes qui bougent (navettes, ascenseurs) de la map.
func moving_platforms() -> Array[MovingPlatform]:
	var found: Array[MovingPlatform] = []
	_find_moving(self, found)
	return found


func _find_moving(node: Node, found: Array[MovingPlatform]) -> void:
	for child in node.get_children():
		if child is MovingPlatform:
			found.append(child)
		_find_moving(child, found)


## Jeu en ligne (hôte) : où en sont les plateformes qui bougent.
## (Pour une map de l'éditeur, on ajoute à la fin le temps de ses Mouvements.)
func moving_state() -> Array:
	var times := []
	for platform in moving_platforms():
		times.append(platform.get_time())
	if has_node("Mouvements"):
		times.append(($Mouvements as MapMotion).time)
	return times


## Jeu en ligne (copain) : on cale les plateformes sur celles de l'hôte.
func apply_moving_state(times: Array) -> void:
	var platforms := moving_platforms()
	for i in mini(times.size(), platforms.size()):
		platforms[i].set_time(times[i])
	if has_node("Mouvements") and times.size() > platforms.size():
		($Mouvements as MapMotion).set_time(times[platforms.size()])


## Les fenêtres cassables de la map (cherchées une seule fois).
func windows() -> Array[BreakableWindow]:
	if _windows.is_empty():
		_find_windows(self, _windows)
	return _windows


func _find_windows(node: Node, found: Array[BreakableWindow]) -> void:
	for child in node.get_children():
		if child is BreakableWindow:
			found.append(child)
		_find_windows(child, found)


## Casse les fenêtres touchées par une zone ronde (explosion).
func smash_windows_in(center: Vector2, radius: float) -> void:
	for window in windows():
		var r := window.rect()
		if center.clamp(r.position, r.end).distance_to(center) <= radius:
			if window is CityBlock:
				(window as CityBlock).hit(CityBlock.EXPLOSION_DAMAGE)
			else:
				window.smash()


## Jeu en ligne (hôte) : quelles fenêtres sont cassées.
func window_state() -> Array:
	return windows().map(func(w: BreakableWindow) -> bool: return w.broken)


## Jeu en ligne (copain) : on casse / répare les fenêtres comme chez l'hôte.
func apply_window_state(states: Array) -> void:
	var list := windows()
	for i in mini(states.size(), list.size()):
		list[i].set_broken(states[i])
