class_name CityCollapse
extends Node2D
## L'écroulement des immeubles de la Ville.
## Un bloc tient s'il touche, de proche en proche, un bloc posé sur la rue. Quand un bloc casse,
## on cherche tout ce qui ne tient plus : chaque morceau détaché devient un FallingChunk qui tombe.
## Casser un seul mur ne suffit donc pas (l'autre mur et les planchers tiennent l'étage) :
## il faut couper les deux murs au même étage pour faire tomber tout le haut.

var blocks: Array[CityBlock] = []
var chunks: Array[FallingChunk] = []     ## les morceaux en train de tomber (ou de trembler)
var _neighbors := {}                     ## bloc -> les blocs qu'il touche (le plus bas en dernier)
var _cells_map := {}                     ## case de BLOCK px -> les blocs qui la touchent
var _just_broken: Array[CityBlock] = []  ## les blocs cassés cette frame (on vérifie autour d'eux)


## À appeler une fois tous les blocs créés (ils ne bougent jamais) : qui touche qui.
func setup(all_blocks: Array[CityBlock]) -> void:
	blocks = all_blocks
	var cells := _cells_map
	for block in blocks:
		block.collapse = self
		for cell in _cells(block.rect().grow(1.0)):
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(block)
	for block in blocks:
		var around := {}
		var r := block.rect().grow(1.0)
		for cell in _cells(r):
			for other: CityBlock in cells[cell]:
				if other != block and r.intersects(other.rect()):
					around[other] = true
		var list: Array = around.keys()
		list.sort_custom(func(a: CityBlock, b: CityBlock) -> bool: return a.rect().end.y < b.rect().end.y)
		_neighbors[block] = list  # le plus bas en dernier : la recherche du sol descend d'abord


func _cells(r: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for x in range(floori(r.position.x / Ville.BLOCK), floori(r.end.x / Ville.BLOCK) + 1):
		for y in range(floori(r.position.y / Ville.BLOCK), floori(r.end.y / Ville.BLOCK) + 1):
			found.append(Vector2i(x, y))
	return found


## Un bloc vient de casser : on vérifiera ce qui tient encore autour de lui à la fin de la frame.
func block_broken(block: CityBlock) -> void:
	_just_broken.append(block)


func _physics_process(_delta: float) -> void:
	for i in range(chunks.size() - 1, -1, -1):
		if not is_instance_valid(chunks[i]) or chunks[i].is_queued_for_deletion():
			chunks.remove_at(i)
	if not _just_broken.is_empty():
		var broken_now := _just_broken
		_just_broken = []
		_drop_loose_blocks(broken_now)


## Ce qui ne touche plus le sol, de proche en proche, tombe (un morceau par groupe de blocs collés).
## Seuls les voisins des blocs qui viennent de casser ont pu perdre leur appui : depuis chacun, on
## cherche le sol en descendant d'abord. Trouvé : tout ce qu'on a parcouru tient. Pas trouvé : on a
## parcouru tout le morceau détaché, qui tombe.
func _drop_loose_blocks(broken_now: Array[CityBlock]) -> void:
	var held := {}
	var falling := {}
	for gone in broken_now:
		for start: CityBlock in _neighbors[gone]:
			if start.broken or held.has(start) or falling.has(start):
				continue
			var seen := {start: true}
			var group: Array[CityBlock] = [start]
			var todo: Array[CityBlock] = [start]
			var grounded := false
			while not todo.is_empty():
				var block: CityBlock = todo.pop_back()
				if held.has(block) or block.rect().end.y >= -1.0:  # posé sur la rue (ou relié à ce qui tient)
					grounded = true
					break
				for other: CityBlock in _neighbors[block]:
					if not other.broken and not seen.has(other):
						seen[other] = true
						group.append(other)
						todo.append(other)
			if grounded:
				for block in group:
					held[block] = true
				continue
			for block in group:
				falling[block] = true
				block.vanish()
			var chunk := FallingChunk.new()
			chunk.setup(group, self)
			add_child(chunk)
			chunks.append(chunk)


## Les blocs (pas cassés) qui touchent le rectangle r.
func blocks_in(r: Rect2) -> Array[CityBlock]:
	var found: Array[CityBlock] = []
	var seen := {}
	for cell in _cells(r):
		for block: CityBlock in _cells_map.get(cell, []):
			if not block.broken and not seen.has(block) and r.intersects(block.rect()):
				seen[block] = true
				found.append(block)
	return found


## Le haut de ce qu'il y a sous x0..x1 à partir de la hauteur y (les blocs encore là, sinon la rue).
func ground_below(x0: float, x1: float, y: float) -> float:
	var top := 0.0 if x1 > -Ville.HALF_WIDTH and x0 < Ville.HALF_WIDTH else INF
	for block in blocks_in(Rect2(x0, y - 1.0, x1 - x0, maxf(-y, 0.0) + 2.0)):
		var r := block.rect()
		if r.end.x > x0 and r.position.x < x1 and r.position.y >= y - 0.5 and r.position.y < top:
			top = r.position.y
	return top
