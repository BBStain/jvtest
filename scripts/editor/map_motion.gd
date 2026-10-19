class_name MapMotion
extends Node
## Fait bouger les éléments d'une map de l'éditeur pendant la partie : chacun fait son aller-retour
## (son "travel") et suit en plus tout ce à quoi il est attaché (voir MapData.offset_at).
## Les blocs qui bougent sont des AnimatableBody2D : les joueurs posés dessus sont transportés.
## L'éditeur s'en sert aussi pour « Voir bouger » (aperçu du mouvement).

var time := 0.0
var _found := {}                    ## id -> élément
var _moving: Array[Dictionary] = [] ## {"node", "base", "element"}


func setup(data: Dictionary, nodes: Dictionary) -> void:
	_found = MapData.by_id(data)
	_moving.clear()
	for element in data.elements:
		var node: Node2D = nodes.get(int(element.id))
		if node != null and MapData.moves(_found, element):
			_moving.append({"node": node, "base": MapData.vec(element, "pos"), "element": element})


func is_empty() -> bool:
	return _moving.is_empty()


func _physics_process(delta: float) -> void:
	set_time(time + delta)


func set_time(value: float) -> void:
	time = value
	for entry in _moving:
		var node: Node2D = entry.node
		if is_instance_valid(node):
			node.position = entry.base + MapData.offset_at(_found, entry.element, time)
