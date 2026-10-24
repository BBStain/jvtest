class_name CityCollapse
extends Node2D
## L'écroulement des immeubles de la Ville.
## Un bloc tient s'il touche, de proche en proche, un bloc posé sur la rue. Quand un bloc casse,
## on cherche tout ce qui ne tient plus : chaque morceau détaché devient un FallingChunk qui tombe.
## Casser un seul mur ne suffit donc pas (l'autre mur et les planchers tiennent l'étage) :
## il faut couper les deux murs au même étage pour faire tomber tout le haut.

var blocks: Array[CityBlock] = []
var chunks: Array[FallingChunk] = []     ## les morceaux en train de tomber (ou de trembler)
var _neighbors := {}                     ## bloc -> les blocs qu'il touche
var _dirty := false


## À appeler une fois tous les blocs créés (ils ne bougent jamais) : qui touche qui.
func setup(all_blocks: Array[CityBlock]) -> void:
	blocks = all_blocks
	var cells := {}
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
		_neighbors[block] = around.keys()


func _cells(r: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for x in range(floori(r.position.x / Ville.BLOCK), floori(r.end.x / Ville.BLOCK) + 1):
		for y in range(floori(r.position.y / Ville.BLOCK), floori(r.end.y / Ville.BLOCK) + 1):
			found.append(Vector2i(x, y))
	return found


## Un bloc vient de casser : on vérifiera ce qui tient encore à la fin de la frame.
func block_broken() -> void:
	_dirty = true


func _physics_process(_delta: float) -> void:
	for i in range(chunks.size() - 1, -1, -1):
		if not is_instance_valid(chunks[i]) or chunks[i].is_queued_for_deletion():
			chunks.remove_at(i)
	if _dirty:
		_dirty = false
		_drop_loose_blocks()


## Ce qui ne touche plus le sol, de proche en proche, tombe (un morceau par groupe de blocs collés).
func _drop_loose_blocks() -> void:
	var held := {}
	var todo: Array[CityBlock] = []
	for block in blocks:
		if not block.broken and block.rect().end.y >= -1.0:  # posé sur la rue
			held[block] = true
			todo.append(block)
	while not todo.is_empty():
		var block: CityBlock = todo.pop_back()
		for other: CityBlock in _neighbors[block]:
			if not other.broken and not held.has(other):
				held[other] = true
				todo.append(other)
	var seen := {}
	for block in blocks:
		if block.broken or held.has(block) or seen.has(block):
			continue
		var group: Array[CityBlock] = [block]
		seen[block] = true
		var i := 0
		while i < group.size():
			for other: CityBlock in _neighbors[group[i]]:
				if not other.broken and not seen.has(other):
					seen[other] = true
					group.append(other)
			i += 1
		for member in group:
			member.vanish()
		var chunk := FallingChunk.new()
		chunk.setup(group, self)
		add_child(chunk)
		chunks.append(chunk)


## Le haut de ce qu'il y a sous x0..x1 à partir de la hauteur y (les blocs encore là, sinon la rue).
func ground_below(x0: float, x1: float, y: float) -> float:
	var top := 0.0 if x1 > -Ville.HALF_WIDTH and x0 < Ville.HALF_WIDTH else INF
	for block in blocks:
		if block.broken:
			continue
		var r := block.rect()
		if r.end.x > x0 and r.position.x < x1 and r.position.y >= y - 0.5 and r.position.y < top:
			top = r.position.y
	return top
