class_name TournamentMenu
extends RefCounted
## Les écrans du bouton TOURNOI du menu (le menu lui passe les touches et lui laisse sa place à l'écran) :
##   CODE : taper le code (voir TournamentSetup.CODE) pour entrer dans la préparation.
##   HOME : la préparation du tournoi, en 3 étapes.
##   MODE : étape 1, comment le tournoi se déroule (joueurs inscrits, puis un réglage par phase).
##   MAPS : étape 2, la map de chaque phase (et plus tard sa musique et sa direction artistique).
##   STEP3 : étape 3, pas encore définie.
## Dans les tableaux : haut / bas = ligne, gauche / droite = colonne, A = changer la valeur.

enum Page { CODE, HOME, MODE, MAPS, STEP3 }

const STEPS := ["1. MODE DE JEU", "2. MAPS", "3. À VENIR"]
const CELL_WIDTHS := [170, 120, 170, 90, 190, 190]  ## MODE : nom de la phase, puis une colonne par réglage
const MAP_CELL_WIDTHS := [170, 200, 170, 220]       ## MAPS : phase, map, musique, direction artistique

var page := Page.CODE
var exited := false          ## B depuis le code ou l'accueil : on revient au menu principal
var _redraw: Callable        ## redessine l'écran (après un clic de souris)
var _choice := 0             ## HOME : étape sélectionnée
var _row := 0                ## MODE / MAPS : ligne sélectionnée (MODE : 0 = joueurs inscrits)
var _col := 0                ## MODE : colonne sélectionnée
var _letters: Array[String] = []
var _cursor := 0
var _wrong_code := false
var _map_names := {}         ## chemin de la map -> son nom (pour ne pas recharger la map à chaque affichage)


func _init(redraw: Callable) -> void:
	_redraw = redraw


## Ouvre le tournoi : le code d'abord, sauf s'il a déjà été tapé.
func open() -> void:
	TournamentSetup.ensure_loaded()
	exited = false
	_letters = []
	_cursor = 0
	_wrong_code = false
	_choice = 0
	page = Page.HOME if TournamentSetup.unlocked else Page.CODE


## Une touche du menu : "up", "down", "left", "right", "confirm", "back".
func handle(action: String) -> void:
	match page:
		Page.CODE:
			_handle_code(action)
		Page.HOME:
			match action:
				"up", "down":
					_choice = posmod(_choice + (1 if action == "down" else -1), STEPS.size())
				"confirm":
					_open_step(_choice)
				"back":
					exited = true
		Page.MODE:
			_handle_mode(action)
		Page.MAPS:
			match action:
				"up", "down":
					_row = posmod(_row + (1 if action == "down" else -1), TournamentSetup.PHASES.size())
				"left", "right", "confirm":
					TournamentSetup.cycle_map(_phase_id(_row), -1 if action == "left" else 1)
				"back":
					_go_home(1)
		Page.STEP3:
			if action in ["back", "confirm"]:
				_go_home(2)


## Une touche du clavier pendant qu'on tape le code : une lettre, ou Retour arrière pour effacer.
## Renvoie true si la touche a servi.
func type_key(event: InputEvent) -> bool:
	if page != Page.CODE or not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var key := event as InputEventKey
	var letter := char(key.unicode).to_upper() if key.unicode > 0 else ""
	if letter.length() == 1 and TournamentSetup.CODE_LETTERS.contains(letter):
		if _cursor < _letters.size():
			_letters[_cursor] = letter
		else:
			_letters.append(letter)
		_cursor = mini(_cursor + 1, 3)
		_wrong_code = false
		return true
	if key.keycode == KEY_BACKSPACE:
		if not _letters.is_empty():
			_letters.pop_back()
		_cursor = mini(_letters.size(), 3)
		return true
	return false


func _handle_code(action: String) -> void:
	var letters := TournamentSetup.CODE_LETTERS
	match action:
		"up", "down":
			_wrong_code = false
			if _letters.size() <= _cursor:
				while _letters.size() <= _cursor:
					_letters.append("A" if action == "down" else letters[-1])
			else:
				var i := letters.find(_letters[_cursor])
				_letters[_cursor] = letters[posmod(i + (1 if action == "down" else -1), letters.length())]
		"left":
			_cursor = maxi(_cursor - 1, 0)
		"right":
			_cursor = mini(_cursor + 1, mini(_letters.size(), 3))
		"confirm":
			if TournamentSetup.check_code("".join(_letters)):
				_go_home(0)
			else:
				_wrong_code = true
				_letters = []
				_cursor = 0
		"back":
			exited = true


func _handle_mode(action: String) -> void:
	var rows := TournamentSetup.PHASES.size() + 1  # + la ligne des joueurs inscrits
	match action:
		"up", "down":
			_row = posmod(_row + (1 if action == "down" else -1), rows)
		"left", "right":
			if _row > 0:
				_col = posmod(_col + (1 if action == "right" else -1), TournamentSetup.FIELDS.size())
		"confirm":
			_change_cell(_row, _col)
		"back":
			_go_home(0)


func _change_cell(row: int, col: int) -> void:
	if row == 0:
		TournamentSetup.cycle_registered()
	else:
		TournamentSetup.cycle(_phase_id(row - 1), TournamentSetup.FIELDS[col])


func _open_step(index: int) -> void:
	_choice = index
	_row = 0
	_col = 0
	page = [Page.MODE, Page.MAPS, Page.STEP3][index]


func _go_home(choice: int) -> void:
	page = Page.HOME
	_choice = choice


func _phase_id(index: int) -> String:
	return TournamentSetup.PHASES[index].id


# --- Affichage ---

## Ajoute l'écran en cours dans content (la colonne centrale du menu).
func build(content: VBoxContainer) -> void:
	match page:
		Page.CODE:
			content.add_child(UiKit.label("TOURNOI", 44))
			content.add_child(UiKit.label("Tape le code pour préparer le tournoi", 22, UiKit.TEXT_DIM))
			content.add_child(UiKit.code_boxes(_letters, _cursor))
			content.add_child(UiKit.label("Code faux, réessaie" if _wrong_code else " ", 22, Color(1, 0.4, 0.4)))
			content.add_child(UiKit.label("Clavier : tape les lettres (Retour arrière pour effacer)", 18, UiKit.TEXT_DIM))
			content.add_child(UiKit.label("Manette : haut / bas change la lettre, gauche / droite change de case", 18, UiKit.TEXT_DIM))
			content.add_child(UiKit.label("A / Entrée : valider      B / Échap : retour", 18, UiKit.TEXT_DIM))
		Page.HOME:
			content.add_child(UiKit.label("PRÉPARATION DU TOURNOI", 44))
			content.add_child(UiKit.label("24 octobre 2026", 22, UiKit.TEXT_DIM))
			for i in STEPS.size():
				content.add_child(UiKit.menu_button(STEPS[i], i == _choice, _click_step.bind(i)))
			content.add_child(UiKit.label(TournamentSetup.summary()[0], 18, UiKit.TEXT_DIM))
			content.add_child(UiKit.label("A : ouvrir      B : retour au menu", 18, UiKit.TEXT_DIM))
		Page.MODE:
			_build_mode(content)
		Page.MAPS:
			_build_maps(content)
		Page.STEP3:
			content.add_child(UiKit.label("3. À VENIR", 44))
			content.add_child(UiKit.label("Cette étape sera remplie quand on saura ce qu'elle contient.", 22, UiKit.TEXT_DIM))
			content.add_child(UiKit.label("B : retour", 18, UiKit.TEXT_DIM))


func _build_mode(content: VBoxContainer) -> void:
	content.add_child(UiKit.label("1. MODE DE JEU", 40))
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 12)
	top.add_child(UiKit.label("Joueurs inscrits :", 22))
	top.add_child(UiKit.cell_button(str(TournamentSetup.registered), _row == 0, _click_cell.bind(0, 0), 90))
	content.add_child(top)

	var grid := GridContainer.new()
	grid.columns = CELL_WIDTHS.size()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_child(_header("", CELL_WIDTHS[0]))
	for c in TournamentSetup.FIELD_TITLES.size():
		grid.add_child(_header(TournamentSetup.FIELD_TITLES[c], CELL_WIDTHS[c + 1]))
	for p in TournamentSetup.PHASES.size():
		var phase: Dictionary = TournamentSetup.PHASES[p]
		var active: bool = TournamentSetup.phases[phase.id].on
		grid.add_child(_header(phase.name, CELL_WIDTHS[0], Color.WHITE if active else UiKit.TEXT_DIM))
		for c in TournamentSetup.FIELDS.size():
			var field: String = TournamentSetup.FIELDS[c]
			var dim := not active and field != "on"
			grid.add_child(UiKit.cell_button(TournamentSetup.value_text(phase.id, field), _row == p + 1 and _col == c,
				_click_cell.bind(p + 1, c), CELL_WIDTHS[c + 1], UiKit.TEXT_DIM if dim else Color.WHITE))
	content.add_child(grid)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	for line in TournamentSetup.summary():
		lines.add_child(UiKit.label(line, 17, Color(1, 0.5, 0.5) if line.ends_with("!") else UiKit.TEXT_DIM))
	content.add_child(lines)
	content.add_child(UiKit.label("haut / bas / gauche / droite : choisir une case      A : changer      B : retour", 18, UiKit.TEXT_DIM))


func _build_maps(content: VBoxContainer) -> void:
	content.add_child(UiKit.label("2. MAPS", 40))
	var grid := GridContainer.new()
	grid.columns = MAP_CELL_WIDTHS.size()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var titles := ["", "Map", "Musique", "Direction artistique"]
	for c in titles.size():
		grid.add_child(_header(titles[c], MAP_CELL_WIDTHS[c]))
	for p in TournamentSetup.PHASES.size():
		var phase: Dictionary = TournamentSetup.PHASES[p]
		var settings: Dictionary = TournamentSetup.phases[phase.id]
		var color := Color.WHITE if settings.on else UiKit.TEXT_DIM
		grid.add_child(_header(phase.name, MAP_CELL_WIDTHS[0], color))
		var map_name := _map_name(settings.map)
		var text := "<  %s  >" % map_name if _row == p and GameSetup.MAPS.size() > 1 else map_name
		grid.add_child(UiKit.cell_button(text, _row == p, _click_map.bind(p), MAP_CELL_WIDTHS[1], color))
		grid.add_child(_header("à venir", MAP_CELL_WIDTHS[2], UiKit.TEXT_DIM))
		grid.add_child(_header("à venir", MAP_CELL_WIDTHS[3], UiKit.TEXT_DIM))
	content.add_child(grid)
	content.add_child(UiKit.label("Chaque phase aura sa map, sa musique et sa direction artistique.\nPour l'instant il n'y a que l'Arène.", 18, UiKit.TEXT_DIM))
	content.add_child(UiKit.label("haut / bas : phase      gauche / droite ou A : changer la map      B : retour", 18, UiKit.TEXT_DIM))


func _header(text: String, width: float, color := UiKit.HIGHLIGHT) -> Label:
	var label := UiKit.label(text, 18, color)
	label.custom_minimum_size = Vector2(width, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _map_name(path: String) -> String:
	if _map_names.has(path):
		return _map_names[path]
	var map := (load(path) as PackedScene).instantiate() as GameMap
	var map_name := map.map_name
	map.free()
	_map_names[path] = map_name
	return map_name


# --- Souris ---

func _click_step(index: int) -> void:
	_open_step(index)
	_redraw.call()


func _click_cell(row: int, col: int) -> void:
	_row = row
	_col = col
	_change_cell(row, col)
	_redraw.call()


func _click_map(row: int) -> void:
	_row = row
	TournamentSetup.cycle_map(_phase_id(row), 1)
	_redraw.call()
