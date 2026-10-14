class_name BracketView
extends Control
## Dessine l'arbre d'un tournoi (voir TournamentData.bracket) : un tour par colonne, un
## rectangle par match avec ses joueurs, et des traits qui relient chaque match à ceux qui
## l'alimentent. Tout est mis à l'échelle pour tenir dans la place donnée, même à 32 joueurs.

const BOX_COLOR := Color(1, 1, 1, 0.07)
const LINE_COLOR := Color(1, 1, 1, 0.3)
const NAME_COLOR := Color.WHITE
const PLACEHOLDER_COLOR := Color(1, 1, 1, 0.45)
const GAP := 0.15  ## la place entre deux matchs d'une même colonne (en part de la hauteur d'un match)

var rounds: Array = []


func _init(bracket: Array, view_size: Vector2) -> void:
	rounds = bracket
	custom_minimum_size = view_size
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	if rounds.is_empty():
		return
	var font := ThemeDB.fallback_font
	var title_height := 26.0
	var column_width := size.x / rounds.size()
	var box_width := minf(column_width * 0.8, 240.0)
	var area_height := size.y - title_height
	var biggest := 1
	for matches in rounds:
		for m in matches:
			biggest = maxi(biggest, m.slots.size())
	# La hauteur d'un match de la colonne la plus chargée décide de la taille du texte.
	var row_height := area_height
	for matches in rounds:
		row_height = minf(row_height, area_height / (matches.size() * (1.0 + GAP)))
	var font_size := clampi(int(row_height / biggest * 0.8), 9, 20)
	var centers := {}  ## numéro du match -> milieu de son bord droit
	for r in rounds.size():
		var matches: Array = rounds[r]
		var x := r * column_width + (column_width - box_width) / 2.0
		draw_string(font, Vector2(r * column_width, 18), TournamentData.round_name(r, rounds.size()),
			HORIZONTAL_ALIGNMENT_CENTER, column_width, 18, UiKit.HIGHLIGHT)
		for i in matches.size():
			var m: Dictionary = matches[i]
			var height := minf(row_height, (font_size + 6) * m.slots.size() + 8)
			# Au 1er tour, les matchs sont empilés ; ensuite, chacun se met au niveau de ceux qui l'alimentent.
			var middle := title_height + (i + 0.5) * area_height / matches.size()
			if not m.sources.is_empty():
				middle = 0.0
				for source in m.sources:
					middle += centers[source].y
				middle /= m.sources.size()
			var box := Rect2(x, middle - height / 2.0, box_width, height)
			for source in m.sources:
				var from: Vector2 = centers[source]
				var elbow := (from.x + box.position.x) / 2.0
				draw_polyline(PackedVector2Array([from, Vector2(elbow, from.y), Vector2(elbow, middle), Vector2(box.position.x, middle)]), LINE_COLOR, 2.0)
			draw_rect(box, BOX_COLOR)
			draw_rect(box, UiKit.HIGHLIGHT if m.qualified == 0 else LINE_COLOR, false, 2.0)
			draw_string(font, box.position + Vector2(4, minf(font_size, box.size.y)), "M%d" % m.number,
				HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(font_size - 4, 8), PLACEHOLDER_COLOR)
			var line: float = (box.size.y - 8) / m.slots.size()
			for s in m.slots.size():
				var text: String = m.slots[s]
				var placeholder: bool = m.sources.size() > 0
				draw_string(font, Vector2(box.position.x + 24, box.position.y + 4 + line * (s + 0.5) + font_size * 0.35),
					text, HORIZONTAL_ALIGNMENT_LEFT, box_width - 28, font_size, PLACEHOLDER_COLOR if placeholder else NAME_COLOR)
			centers[m.number] = Vector2(box.end.x, middle)
