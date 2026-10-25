class_name CityPainter
extends Node2D
## Dessine d'un coup tous les blocs intacts d'un morceau de la Ville (des milliers de petits dessins
## séparés, c'est trop lent sur téléphone). Un bloc abîmé, qui casse ou qui tombe se dessine seul.

const TILE := 1600.0              ## taille d'un morceau (les morceaux hors de l'écran ne sont pas dessinés)

var blocks: Array[CityBlock] = []


## Range les blocs par morceau de TILE px et ajoute un peintre par morceau dans "decor".
static func paint(decor: Node2D, all_blocks: Array[CityBlock]) -> void:
	var tiles := {}
	for block in all_blocks:
		var cell := Vector2i((block.position / TILE).floor())
		if not tiles.has(cell):
			var painter := CityPainter.new()
			painter.name = "Peintre_%d_%d" % [cell.x, cell.y]
			tiles[cell] = painter
			decor.add_child(painter)
		var painter: CityPainter = tiles[cell]
		painter.blocks.append(block)
		block.painter = painter
		block.refresh_look()


func _draw() -> void:
	for block in blocks:
		if block.is_plain():
			draw_rect(Rect2(block.position - block.size / 2.0, block.size), block.color)
