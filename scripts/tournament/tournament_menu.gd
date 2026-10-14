class_name TournamentMenu
extends RefCounted
## Les écrans du bouton TOURNOI du menu (le menu lui passe les touches et lui laisse sa place à l'écran) :
##   CODE : taper le code (voir TournamentData.CODE) pour entrer.
##   HOME : continuer le tournoi enregistré, ou en créer un nouveau.
##   EDIT : le nom, le format, les joueurs (ajouter, retirer, mélanger), puis voir l'arbre.
##   KEYBOARD : taper un nom (celui du tournoi ou d'un joueur), voir TextKeyboard.
##   BRACKET : l'arbre du tournoi (voir BracketView).

enum Page { CODE, HOME, EDIT, KEYBOARD, BRACKET }
enum Row { NAME, FORMAT, PLAYERS, ADD, SHUFFLE, BRACKET }

const CHIP_COLUMNS := 8
const BRACKET_SIZE := Vector2(1220, 520)

var page := Page.CODE
var exited := false          ## B depuis le code ou l'accueil : on revient au menu principal
var tournament: TournamentData
var _redraw: Callable        ## redessine l'écran (après un clic de souris)
var _saved: TournamentData   ## le tournoi enregistré (null s'il n'y en a pas)
var _choice := 0             ## HOME : bouton sélectionné ; EDIT : ligne sélectionnée (Row)
var _chip := 0               ## EDIT : joueur sélectionné dans la liste
var _confirm := false        ## un 2e appui sur A confirme (retirer un joueur, remplacer le tournoi)
var _keyboard: TextKeyboard
var _keyboard_target := ""   ## "name" (le tournoi) ou "player" (ajouter un joueur)
var _letters: Array[String] = []
var _cursor := 0
var _wrong_code := false


func _init(redraw: Callable) -> void:
	_redraw = redraw


## Ouvre le tournoi : le code d'abord, sauf s'il a déjà été tapé.
func open() -> void:
	exited = false
	_letters = []
	_cursor = 0
	_wrong_code = false
	_go_home()
	if not TournamentData.unlocked:
		page = Page.CODE


## Une touche du menu : "up", "down", "left", "right", "confirm", "back" (ou "quit", "").
func handle(action: String) -> void:
	match page:
		Page.CODE:
			_handle_code(action)
		Page.HOME:
			_handle_home(action)
		Page.EDIT:
			_handle_edit(action)
		Page.KEYBOARD:
			_keyboard.handle(action)
			_after_keyboard()
		Page.BRACKET:
			if action == "back":
				page = Page.EDIT


## Une touche du vrai clavier, pour taper du texte. Renvoie true si elle a servi.
func type_key(event: InputEvent) -> bool:
	if page == Page.KEYBOARD:
		var used := _keyboard.type_key(event)
		_after_keyboard()
		return used
	if page == Page.CODE and event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var letter := char(key.unicode).to_upper() if key.unicode > 0 else ""
		if letter.length() == 1 and TournamentData.CODE_LETTERS.contains(letter):
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
	var letters := TournamentData.CODE_LETTERS
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
			if TournamentData.check_code("".join(_letters)):
				_go_home()
			else:
				_wrong_code = true
				_letters = []
				_cursor = 0
		"back":
			exited = true


func _home_buttons() -> Array:
	var buttons := []
	if _saved != null:
		buttons.append("CONTINUER : %s" % _saved.name)
	buttons.append("NOUVEAU TOURNOI")
	return buttons


func _handle_home(action: String) -> void:
	var count := _home_buttons().size()
	match action:
		"up", "down":
			_choice = posmod(_choice + (1 if action == "down" else -1), count)
			_confirm = false
		"confirm":
			_open_home_button(_choice)
		"back":
			exited = true


func _open_home_button(index: int) -> void:
	_choice = index
	if _saved != null and index == 0:
		_edit(_saved)
	elif _saved != null and not _confirm:
		_confirm = true  # on remplacerait le tournoi enregistré : on demande un 2e appui
	else:
		var fresh := TournamentData.new()
		fresh.save()
		_edit(fresh)


func _edit(data: TournamentData) -> void:
	tournament = data
	page = Page.EDIT
	_choice = Row.NAME
	_chip = 0
	_confirm = false


func _handle_edit(action: String) -> void:
	var count := tournament.players.size()
	if action != "confirm":
		_confirm = false
	match action:
		"up", "down":
			var step := 1 if action == "down" else -1
			if _choice == Row.PLAYERS and _chip + step * CHIP_COLUMNS >= 0 and _chip + step * CHIP_COLUMNS < count:
				_chip += step * CHIP_COLUMNS  # on monte / descend dans la liste des joueurs
			else:
				_choice = posmod(_choice + step, Row.size())
				if _choice == Row.PLAYERS and count == 0:
					_choice = posmod(_choice + step, Row.size())  # liste vide : on la saute
		"left", "right":
			var step := 1 if action == "right" else -1
			if _choice == Row.FORMAT:
				_change_format(step)
			elif _choice == Row.PLAYERS:
				_chip = posmod(_chip + step, count)
		"confirm":
			_activate_row(_choice)
		"back":
			_go_home()


func _activate_row(row: int) -> void:
	_choice = row
	match row:
		Row.NAME:
			_open_keyboard("name", "NOM DU TOURNOI", tournament.name, TournamentData.MAX_NAME * 2)
		Row.FORMAT:
			_change_format(1)
		Row.PLAYERS:
			if tournament.players.is_empty():
				return
			if _confirm:
				tournament.players.remove_at(_chip)
				tournament.save()
				_chip = clampi(_chip, 0, maxi(tournament.players.size() - 1, 0))
				_confirm = false
				if tournament.players.is_empty():
					_choice = Row.ADD
			else:
				_confirm = true
		Row.ADD:
			if tournament.players.size() < TournamentData.MAX_PLAYERS:
				_open_keyboard("player", "NOM DU JOUEUR %d" % (tournament.players.size() + 1), "", TournamentData.MAX_NAME)
		Row.SHUFFLE:
			tournament.shuffle()
			tournament.save()
		Row.BRACKET:
			if tournament.players.size() >= 2:
				page = Page.BRACKET


func _change_format(step: int) -> void:
	tournament.format = posmod(tournament.format + step, TournamentData.FORMATS.size())
	tournament.save()


func _open_keyboard(target: String, title: String, text: String, length: int) -> void:
	_keyboard = TextKeyboard.new(title, text, length)
	_keyboard_target = target
	page = Page.KEYBOARD


func _after_keyboard() -> void:
	if _keyboard.cancelled:
		page = Page.EDIT
	elif _keyboard.done:
		page = Page.EDIT
		if _keyboard_target == "name":
			if _keyboard.text.strip_edges() != "":
				tournament.name = _keyboard.text.strip_edges()
		elif tournament.add_player(_keyboard.text) and tournament.players.size() < TournamentData.MAX_PLAYERS:
			# Joueur ajouté : on enchaîne directement sur le suivant.
			tournament.save()
			_open_keyboard("player", "NOM DU JOUEUR %d" % (tournament.players.size() + 1), "", TournamentData.MAX_NAME)
		tournament.save()


func _go_home() -> void:
	_saved = TournamentData.load_saved()
	page = Page.HOME
	_choice = 0
	_confirm = false


# --- Affichage ---

## Ajoute l'écran en cours dans content (la colonne centrale du menu).
func build(content: VBoxContainer) -> void:
	match page:
		Page.CODE:
			content.add_child(UiKit.label("TOURNOI", 44))
			content.add_child(UiKit.label("Tape le code pour entrer", 22, UiKit.TEXT_DIM))
			content.add_child(UiKit.code_boxes(_letters, _cursor))
			content.add_child(UiKit.label("Code faux, réessaie" if _wrong_code else " ", 22, Color(1, 0.4, 0.4)))
			content.add_child(UiKit.label("Clavier : tape les lettres (Retour arrière pour effacer)", 18, UiKit.TEXT_DIM))
			content.add_child(UiKit.label("Manette : haut / bas change la lettre, gauche / droite change de case", 18, UiKit.TEXT_DIM))
			content.add_child(UiKit.label("A / Entrée : valider      B / Échap : retour", 18, UiKit.TEXT_DIM))
		Page.HOME:
			content.add_child(UiKit.label("TOURNOI", 44))
			var buttons := _home_buttons()
			for i in buttons.size():
				content.add_child(UiKit.menu_button(buttons[i], i == _choice, _click_home.bind(i)))
			if _confirm:
				content.add_child(UiKit.label("Ça remplace « %s ». Appuie encore sur A pour confirmer." % _saved.name, 20, Color(1, 0.5, 0.5)))
			content.add_child(UiKit.label("A : ouvrir      B : retour au menu", 18, UiKit.TEXT_DIM))
		Page.EDIT:
			_build_edit(content)
		Page.KEYBOARD:
			content.add_child(_keyboard.build())
		Page.BRACKET:
			var format: Dictionary = TournamentData.FORMATS[tournament.format]
			content.add_child(UiKit.label(tournament.name, 34))
			content.add_child(UiKit.label("%d joueurs · %s" % [tournament.players.size(), format.name], 18, UiKit.TEXT_DIM))
			content.add_child(BracketView.new(tournament.bracket(), BRACKET_SIZE))
			content.add_child(UiKit.label("B : retour", 18, UiKit.TEXT_DIM))


func _build_edit(parent: VBoxContainer) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	parent.add_child(content)
	content.add_child(UiKit.label("CRÉER LE TOURNOI", 40))
	content.add_child(_setting_row("Nom :", tournament.name, Row.NAME, 420))
	var format: Dictionary = TournamentData.FORMATS[tournament.format]
	content.add_child(_setting_row("Format :", "<  %s  >" % format.name, Row.FORMAT, 300))
	content.add_child(UiKit.label(format.detail, 16, UiKit.TEXT_DIM))

	content.add_child(UiKit.label("Joueurs : %d / %d" % [tournament.players.size(), TournamentData.MAX_PLAYERS], 22))
	if tournament.players.is_empty():
		content.add_child(UiKit.label("Aucun joueur pour l'instant", 18, UiKit.TEXT_DIM))
	else:
		var grid := GridContainer.new()
		grid.columns = CHIP_COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for i in tournament.players.size():
			var selected := _choice == Row.PLAYERS and i == _chip
			grid.add_child(UiKit.cell_button("%d. %s" % [i + 1, tournament.players[i]], selected, _click_chip.bind(i), 142))
		content.add_child(grid)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	actions.add_child(UiKit.cell_button("AJOUTER UN JOUEUR", _choice == Row.ADD, _click_row.bind(Row.ADD), 240))
	actions.add_child(UiKit.cell_button("MÉLANGER", _choice == Row.SHUFFLE, _click_row.bind(Row.SHUFFLE), 160))
	var can_draw := tournament.players.size() >= 2
	actions.add_child(UiKit.cell_button("VOIR L'ARBRE", _choice == Row.BRACKET, _click_row.bind(Row.BRACKET), 200,
		Color.WHITE if can_draw else UiKit.TEXT_DIM))
	content.add_child(actions)

	var hint := "haut / bas : choisir      A : valider      B : retour"
	if _confirm:
		hint = "Retirer %s ? Appuie encore sur A pour confirmer." % tournament.players[_chip]
	elif _choice == Row.PLAYERS:
		hint = "flèches : choisir un joueur      A : le retirer      B : retour"
	elif _choice == Row.BRACKET and not can_draw:
		hint = "Il faut au moins 2 joueurs pour faire l'arbre"
	content.add_child(UiKit.label(hint, 18, Color(1, 0.5, 0.5) if _confirm else UiKit.TEXT_DIM))


## Une ligne « titre : valeur », la valeur dans une case qu'on peut sélectionner.
func _setting_row(title: String, value: String, row: int, width: float) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 12)
	line.add_child(UiKit.label(title, 22))
	line.add_child(UiKit.cell_button(value, _choice == row, _click_row.bind(row), width))
	return line


# --- Souris ---

func _click_home(index: int) -> void:
	_open_home_button(index)
	_redraw.call()


func _click_row(row: int) -> void:
	_confirm = false
	_activate_row(row)
	_redraw.call()


func _click_chip(index: int) -> void:
	if _choice != Row.PLAYERS or _chip != index:
		_confirm = false
	_choice = Row.PLAYERS
	_chip = index
	_activate_row(Row.PLAYERS)
	_redraw.call()
