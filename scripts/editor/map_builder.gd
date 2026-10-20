class_name MapBuilder
extends RefCounted
## Transforme une map de l'éditeur (les données de MapData) en vraie map jouable (un GameMap),
## avec les mêmes morceaux que l'Arène : blocs pleins, plateformes traversables, plateformes
## mobiles, échelles, lianes, fenêtres cassables, points d'apparition.
## Tout élément peut faire des allers-retours et être attaché à un autre : MapMotion les fait bouger.
## L'éditeur s'en sert aussi pour son aperçu : ce qu'on voit dans l'éditeur = ce qu'on joue.

## Marge autour de la map : au-delà, on est sorti et on perd une vie (gauche, haut, droite, bas).
const BLAST_MARGIN := [700.0, 1000.0, 700.0, 500.0]


static func build(data: Dictionary) -> GameMap:
	var map := GameMap.new()
	map.name = "CarteEditeur"
	map.map_name = str(data.get("name", "Ma map"))
	var decor := Node2D.new()
	decor.name = "Decor"
	map.add_child(decor)
	var spawns := Node2D.new()
	spawns.name = "SpawnPoints"
	map.add_child(spawns)
	var items := Node2D.new()
	items.name = "ItemSpawns"
	var weapons := Node2D.new()
	weapons.name = "WeaponSpawns"
	var respawn := Marker2D.new()
	respawn.name = "RespawnPoint"
	var has_respawn := false
	var player_spawns: Array[Dictionary] = []
	var found := MapData.by_id(data)
	var nodes := {}
	for element in data.elements:
		match element.type:
			"spawn_joueur":
				player_spawns.append(element)
			"reapparition":
				respawn.position = MapData.vec(element, "pos")
				has_respawn = true
			"spawn_objet", "spawn_arme":
				var marker := Marker2D.new()
				marker.position = MapData.vec(element, "pos")
				(items if element.type == "spawn_objet" else weapons).add_child(marker)
			_:
				var node := build_element(element, MapData.moves(found, element))
				decor.add_child(node)
				nodes[int(element.id)] = node
	# Les départs dans l'ordre des joueurs (J1, J2...). S'il en manque, on réutilise ceux qui existent
	# (voir GameMap.spawn_position) ; s'il n'y en a aucun, on part de la réapparition.
	player_spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.player) < int(b.player))
	for element in player_spawns:
		var marker := Marker2D.new()
		marker.position = MapData.vec(element, "pos")
		spawns.add_child(marker)
	if not has_respawn:
		respawn.position = _default_respawn(data, player_spawns)
	if spawns.get_child_count() == 0:
		var marker := Marker2D.new()
		marker.position = respawn.position
		spawns.add_child(marker)
	map.add_child(respawn)
	if items.get_child_count() > 0:
		map.add_child(items)
	else:
		items.free()
	if weapons.get_child_count() > 0:
		map.add_child(weapons)
	else:
		weapons.free()
	var motion := MapMotion.new()
	motion.name = "Mouvements"
	motion.setup(data, nodes)
	if motion.is_empty():
		motion.free()
	else:
		map.add_child(motion)
	var area := MapData.bounds(data)
	map.blast_zone = area.grow_individual(BLAST_MARGIN[0], BLAST_MARGIN[1], BLAST_MARGIN[2], BLAST_MARGIN[3])
	return map


## Sans point de réapparition : au-dessus du milieu des départs, sinon au-dessus du milieu de la map.
static func _default_respawn(data: Dictionary, player_spawns: Array[Dictionary]) -> Vector2:
	if not player_spawns.is_empty():
		var sum := Vector2.ZERO
		for element in player_spawns:
			sum += MapData.vec(element, "pos")
		return sum / player_spawns.size() - Vector2(0.0, 150.0)
	var area := MapData.bounds(data)
	return Vector2(area.get_center().x, area.position.y - 100.0)


## Un élément du décor (pas les points d'apparition), prêt à être ajouté à la map.
## "moving" : il bougera (un bloc devient alors un corps qui transporte les joueurs posés dessus).
static func build_element(element: Dictionary, moving := false) -> Node2D:
	var pos := MapData.vec(element, "pos")
	var node: Node2D
	match element.type:
		"sol", "plateforme":
			node = _block(element, element.type == "plateforme", moving)
		"mobile":  # une plateforme traversable qui bouge (MapMotion), avec un liseré clair dessus
			node = _block(element, true, true)
			var size := MapData.vec(element, "size").max(Vector2(4, 4))
			var edge := ColorRect.new()
			edge.position = -size / 2.0
			edge.size = Vector2(size.x, minf(4.0, size.y))
			edge.color = MapData.color(element).lightened(0.35)
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(edge)
		"echelle":
			var ladder := Ladder.new()
			ladder.size = MapData.vec(element, "size")
			ladder.color = MapData.color(element)
			node = ladder
		"liane":
			var vine := Vine.new()
			vine.length = maxf(float(element.length), 40.0)
			vine.color = MapData.color(element)
			node = vine
		"fenetre":
			var window := BreakableWindow.new()
			window.size = MapData.vec(element, "size")
			window.color = MapData.color(element)
			node = window
		_:
			node = Node2D.new()
	node.name = "%s_%d" % [element.type, int(element.id)]
	node.position = pos
	if MapData.CATALOG[element.type].rotatable:
		node.rotation = MapData.rotation(element)
	return node


## Un bloc plein (on ne le traverse pas) ou une plateforme traversable par en dessous,
## comme dans l'Arène : un corps, sa forme et un rectangle de couleur.
## S'il bouge, c'est un AnimatableBody2D : il transporte ce qui est posé dessus.
static func _block(element: Dictionary, one_way: bool, moving := false) -> PhysicsBody2D:
	var size := MapData.vec(element, "size").max(Vector2(4, 4))
	var body: PhysicsBody2D = AnimatableBody2D.new() if moving else StaticBody2D.new()
	body.collision_layer = 0
	body.set_collision_layer_value(Fighter.PLATFORM_LAYER if one_way else 1, true)
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "Collision"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.one_way_collision = one_way
	body.add_child(shape)
	var visual := ColorRect.new()
	visual.name = "Visuel"
	visual.position = -size / 2.0
	visual.size = size
	visual.color = MapData.color(element)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(visual)
	return body
