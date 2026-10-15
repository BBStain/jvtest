class_name TournamentBoard
extends Control
## La page de l'arbre du tournoi, dessinée d'un bloc :
##   en haut, la salle d'attente : la case de chaque joueur inscrit (son nom, sur sa couleur) ;
##   en dessous, l'arbre : un tour par colonne, les cases du 1er tour, puis des cases vides "?"
##   jusqu'à la finale, reliées par des traits.
## Quand on tire au sort (ALÉATOIRE), chaque nom vole de là où il était (salle d'attente ou
## ancienne place) jusqu'à sa nouvelle place, l'un après l'autre.
## L'état de l'animation est gardé par TournamentMenu (l'écran est reconstruit à chaque touche).

const POOL_COLUMNS := 8
const POOL_ROW := 30.0         ## hauteur d'une ligne de la salle d'attente
const TITLE_HEIGHT := 24.0     ## les noms des tours
const FLY_TIME := 0.7          ## durée du vol d'un nom (secondes)
const FLY_DELAY := 0.06        ## écart entre deux noms qui partent
const LINE_COLOR := Color(1, 1, 1, 0.25)
const EMPTY_COLOR := Color(1, 1, 1, 0.06)

var tournament: TournamentData
var from_places: Array = []    ## d'où part chaque joueur pendant l'animation : sa place d'avant, ou -1 (salle d'attente)
var anim_start := -1           ## quand l'animation a commencé (Time.get_ticks_msec), -1 = pas d'animation


func _init(data: TournamentData, view_size: Vector2, start: int, from: Array) -> void:
	tournament = data
	anim_start = start
	from_places = from
	custom_minimum_size = view_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## La durée de l'animation du tirage (tous les noms ont atterri).
static func animation_length(player_count: int) -> float:
	return FLY_TIME + FLY_DELAY * maxi(player_count - 1, 0)


func _process(_delta: float) -> void:
	if anim_start >= 0:
		queue_redraw()
		if _elapsed() > animation_length(tournament.players.size()) + 0.1:
			anim_start = -1


func _elapsed() -> float:
	return (Time.get_ticks_msec() - anim_start) / 1000.0


func _draw() -> void:
	var count := tournament.players.size()
	var layout := _layout()
	var pool: Array = layout.pool
	var places: Array = layout.places
	# La salle d'attente : une case vide là où un joueur est parti dans l'arbre.
	draw_string(ThemeDB.fallback_font, Vector2(0, 16), "Joueurs inscrits", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.TEXT_DIM)
	for p in count:
		draw_rect(pool[p], EMPTY_COLOR)
	# L'arbre.
	var font := ThemeDB.fallback_font
	var landed := anim_start < 0 or _elapsed() > animation_length(count)
	for column in layout.columns:
		draw_string(font, Vector2(column.x, layout.bracket_top + 16), column.title,
			HORIZONTAL_ALIGNMENT_CENTER, column.width, 16, UiKit.HIGHLIGHT)
	for game in layout.matches:
		for link in game.links:
			draw_polyline(PackedVector2Array(link), LINE_COLOR, 2.0)
		for s in game.slots.size():
			var slot: Rect2 = game.slots[s]
			draw_rect(slot, EMPTY_COLOR)
			draw_rect(slot, LINE_COLOR, false, 1.0)
			var value: int = game.values[s]
			if value == TournamentData.BYE:
				_text(slot, "exempt", Color(1, 1, 1, 0.3))
			elif game.later and (value < 0 or not landed):
				_text(slot, "?", Color(1, 1, 1, 0.3))
			elif game.later:
				_name_box(slot, value)  # il est passé d'office : il attend déjà ici
	# Les noms : dans la salle d'attente tant qu'ils ne sont pas tirés, sinon à leur place
	# (en vol pendant l'animation).
	var place_of := {}
	if tournament.is_seeded():
		for place in tournament.seeding.size():
			place_of[tournament.seeding[place]] = place
	for p in count:
		var target: Rect2 = places[place_of[p]] if place_of.has(p) else pool[p]
		if anim_start < 0 or not place_of.has(p):
			_name_box(target, p)
			continue
		var from_place: int = from_places[p] if p < from_places.size() else -1
		var from: Rect2 = places[from_place] if from_place >= 0 and from_place < places.size() else pool[p]
		var t := clampf((_elapsed() - FLY_DELAY * place_of[p]) / FLY_TIME, 0.0, 1.0)
		var k := _ease_out_back(t)
		var rect := Rect2(from.position.lerp(target.position, k), from.size.lerp(target.size, clampf(k, 0.0, 1.0)))
		rect.position.y -= sin(t * PI) * 40.0  # un petit saut en l'air
		var grow := 1.0 + sin(t * PI) * 0.15
		rect = rect.grow_individual(rect.size.x * (grow - 1) / 2, rect.size.y * (grow - 1) / 2,
			rect.size.x * (grow - 1) / 2, rect.size.y * (grow - 1) / 2)
		_name_box(rect, p)


## Une case de nom : le fond et le bord à la couleur du joueur, le nom en blanc.
func _name_box(rect: Rect2, player: int) -> void:
	var color: Color = TournamentData.COLORS[tournament.players[player].color]
	draw_rect(rect, Color(color, 0.45))
	draw_rect(rect, color, false, 2.0)
	_text(rect, tournament.players[player].name, Color.WHITE)


func _text(rect: Rect2, text: String, color: Color) -> void:
	var size := clampi(int(rect.size.y * 0.55), 9, 30)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 6, rect.get_center().y + size * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, size, color)


func _ease_out_back(t: float) -> float:
	var c := 1.4
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3) + c * pow(t - 1.0, 2)


## Où se trouve chaque case :
##   pool : la case de chaque joueur dans la salle d'attente ;
##   places : les cases du 1er tour, dans l'ordre des places ;
##   columns : le titre de chaque colonne de l'arbre ; matches : les cases et les traits de chaque match.
## L'arbre est en miroir : une moitié à gauche, l'autre à droite, la finale au milieu
## (deux fois plus de place pour les noms du 1er tour).
func _layout() -> Dictionary:
	var count := tournament.players.size()
	var pool := []
	var pool_rows := ceili(count / float(POOL_COLUMNS))
	var chip := Vector2((size.x - (POOL_COLUMNS - 1) * 6) / POOL_COLUMNS, POOL_ROW - 6)
	for p in count:
		pool.append(Rect2(Vector2((p % POOL_COLUMNS) * (chip.x + 6), 22 + (p / POOL_COLUMNS) * POOL_ROW), chip))
	var bracket_top: float = 22 + maxi(pool_rows, 1) * POOL_ROW + 10
	var result := {"pool": pool, "places": [], "columns": [], "matches": [], "bracket_top": bracket_top}
	var bracket := tournament.bracket()
	if bracket.is_empty():
		return result
	var round_count := bracket.size()
	var area_top := bracket_top + TITLE_HEIGHT
	var area_height := size.y - area_top
	var column_count := 2 * round_count - 1
	var column_width := size.x / column_count
	var box_width := minf(column_width * 0.88, 280.0)
	for c in column_count:
		var r := mini(c, column_count - 1 - c)
		result.columns.append({"x": c * column_width, "width": column_width,
			"title": TournamentData.round_name(bracket[r].size())})
	# Le côté de chaque match (-1 gauche, 1 droite, 0 la finale), en partant de la finale.
	var side := {bracket[-1][0].number: 0}
	var by_number := {}
	for r in range(round_count - 1, -1, -1):
		for game in bracket[r]:
			by_number[game.number] = game
			for i in game.sources.size():
				side[game.sources[i]] = side[game.number] if side[game.number] != 0 else (-1 if i == 0 else 1)
	var first: Array = bracket[0]
	var per_side := {-1: 0, 0: 0, 1: 0}
	for game in first:
		per_side[side[game.number]] += 1
	var stacked := {-1: 0, 0: 0, 1: 0}
	# La taille des cases suit le nombre d'inscrits : peu de joueurs = grandes cases, beaucoup = petites.
	var busiest: int = maxi(per_side[-1], maxi(per_side[1], per_side[0]))
	var slot_height := clampf((area_height / busiest - 8) / TournamentData.PER_MATCH, 14.0, 64.0)
	var edges := {}  ## numéro du match -> [bord gauche, bord droit] au milieu de sa hauteur
	result.places.resize(count)
	for r in round_count:
		for game in bracket[r]:
			var game_side: int = side[game.number]
			var column := r if game_side <= 0 else column_count - 1 - r
			if game_side == 0:
				column = round_count - 1
			var x := column * column_width + (column_width - box_width) / 2.0
			var middle := 0.0
			if game.sources.is_empty():
				var match_height := area_height / maxi(per_side[game_side], 1)
				middle = area_top + (stacked[game_side] + 0.5) * match_height
				stacked[game_side] += 1
			else:
				for source in game.sources:
					middle += edges[source][0].y
				middle /= game.sources.size()
			var slots := []
			var top: float = middle - game.slots.size() * slot_height / 2.0
			for s in game.slots.size():
				var slot := Rect2(x, top + s * slot_height + 1, box_width, slot_height - 2)
				slots.append(slot)
				if r == 0 and game.places[s] >= 0:
					result.places[game.places[s]] = slot
			var links := []
			for source in game.sources:
				var source_side: int = side[source]
				var from: Vector2 = edges[source][1] if source_side < 0 else edges[source][0]
				var to := Vector2(x, middle) if source_side < 0 else Vector2(x + box_width, middle)
				var elbow := (from.x + to.x) / 2.0
				links.append([from, Vector2(elbow, from.y), Vector2(elbow, middle), to])
			edges[game.number] = [Vector2(x, middle), Vector2(x + box_width, middle)]
			result.matches.append({"number": game.number, "slots": slots, "values": game.slots, "links": links, "later": r > 0})
	return result
