class_name TournamentMenu
extends RefCounted
## Les écrans du bouton TOURNOI du menu (le menu lui passe les touches et lui laisse sa place à l'écran) :
##   CODE : taper le code (voir TournamentData.CODE) pour entrer.
##   SIGNUP : l'inscription : chaque joueur tape son nom, choisit sa couleur et s'inscrit.
##   KEYBOARD : taper un nom (voir TextKeyboard).
##   BOARD : l'arbre (voir TournamentBoard), le gros bouton ALÉATOIRE qui tire les places au sort,
##           et à droite les réglages en 2 pages : MAPS et RÈGLES.

enum Page { CODE, SIGNUP, KEYBOARD, BOARD }
enum Row { NAME, COLOR, REGISTER, PLAYERS, NEXT, CLEAR }       ## SIGNUP, de haut en bas
enum Focus { RANDOM, PLAY, TABS, SETTING }                           ## BOARD
enum Tab { MAPS, RULES }

const CHIP_COLUMNS := 8
const BOARD_SIZE := Vector2(860, 540)
const PANEL_WIDTH := 330.0
const WARNING := Color(1, 0.5, 0.5)

var page := Page.CODE
var exited := false          ## B depuis le code ou l'inscription : on revient au menu principal
var tournament: TournamentData
var _redraw: Callable        ## redessine l'écran (après un clic de souris)
var _row := Row.NAME         ## SIGNUP : ligne sélectionnée
var _chip := 0               ## SIGNUP : joueur sélectionné dans la liste
var _draft_name := ""        ## SIGNUP : le nom du prochain inscrit
var _draft_color := 0        ## SIGNUP : sa couleur
var _message := ""           ## SIGNUP : un petit message (nom déjà pris...)
var _confirm := false        ## un 2e appui sur A confirme (retirer un joueur, tout effacer)
var _focus := Focus.RANDOM   ## BOARD : ce qui est sélectionné
var _tab := Tab.MAPS         ## BOARD : la page de réglages affichée
var _anim_start := -1        ## BOARD : début de l'animation du tirage (voir TournamentBoard)
var _from_places: Array = [] ## BOARD : la place de chaque joueur avant le tirage (-1 = salle d'attente)
var launch := {}             ## BOARD : le match à lancer (le menu le prend et passe au choix des persos)
var board_message := ""     ## BOARD : un petit message (il manque une manette...)
var _keyboard: TextKeyboard
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
	_open_signup()
	if not TournamentData.unlocked:
		page = Page.CODE


## Une touche du menu : "up", "down", "left", "right", "confirm", "back" (ou "quit", "").
func handle(action: String) -> void:
	match page:
		Page.CODE:
			_handle_code(action)
		Page.SIGNUP:
			_handle_signup(action)
		Page.KEYBOARD:
			_keyboard.handle(action)
			_after_keyboard()
		Page.BOARD:
			_handle_board(action)


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


# --- Le code ---

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
				_open_signup()
			else:
				_wrong_code = true
				_letters = []
				_cursor = 0
		"back":
			exited = true


# --- Page 1 : l'inscription ---

func _open_signup() -> void:
	tournament = TournamentData.load_saved()
	page = Page.SIGNUP
	_row = Row.NAME
	_chip = 0
	_confirm = false
	_message = ""
	_draft_color = tournament.next_free_color()


func _handle_signup(action: String) -> void:
	var count := tournament.players.size()
	if action != "confirm":
		_confirm = false
	if action != "":
		_message = ""
	match action:
		"up", "down":
			var step := 1 if action == "down" else -1
			if _row == Row.PLAYERS and _chip + step * CHIP_COLUMNS >= 0 and _chip + step * CHIP_COLUMNS < count:
				_chip += step * CHIP_COLUMNS  # on monte / descend dans la liste des inscrits
			else:
				_row = posmod(_row + step, Row.size())
				if _row == Row.PLAYERS and count == 0:
					_row = posmod(_row + step, Row.size())  # personne d'inscrit : on saute la liste
		"left", "right":
			var step := 1 if action == "right" else -1
			if _row == Row.COLOR:
				_draft_color = posmod(_draft_color + step, TournamentData.COLORS.size())
			elif _row == Row.PLAYERS:
				_chip = posmod(_chip + step, count)
			elif _row in [Row.NEXT, Row.CLEAR]:
				_row = Row.CLEAR if _row == Row.NEXT else Row.NEXT
		"confirm":
			_activate_row(_row)
		"back":
			exited = true


func _activate_row(row: int) -> void:
	_row = row
	match row:
		Row.NAME:
			_open_keyboard()
		Row.COLOR, Row.REGISTER:
			_register()
		Row.PLAYERS:
			if tournament.players.is_empty():
				return
			if _confirm:
				tournament.remove_player(_chip)
				tournament.save()
				_chip = clampi(_chip, 0, maxi(tournament.players.size() - 1, 0))
				_confirm = false
				if tournament.players.is_empty():
					_row = Row.NAME
			else:
				_confirm = true
		Row.NEXT:
			if tournament.players.size() >= 2:
				_open_board()
			else:
				_message = "Il faut au moins 2 inscrits pour faire l'arbre"
		Row.CLEAR:
			if tournament.players.is_empty():
				return
			if _confirm:
				tournament = TournamentData.new()
				tournament.save()
				_confirm = false
				_row = Row.NAME
				_draft_color = 0
			else:
				_confirm = true


func _register() -> void:
	if _draft_name.strip_edges() == "":
		_open_keyboard()
		return
	if tournament.players.size() >= TournamentData.MAX_PLAYERS:
		_message = "C'est complet : %d joueurs au maximum" % TournamentData.MAX_PLAYERS
	elif tournament.add_player(_draft_name, _draft_color):
		tournament.save()
		_message = "%s est inscrit !" % _draft_name.strip_edges()
		_draft_name = ""
		_draft_color = tournament.next_free_color(_draft_color)
		_row = Row.NAME
	else:
		_message = "Ce nom est déjà pris"


func _open_keyboard() -> void:
	_keyboard = TextKeyboard.new("TON NOM", _draft_name, TournamentData.MAX_NAME)
	page = Page.KEYBOARD


func _after_keyboard() -> void:
	if _keyboard.cancelled:
		page = Page.SIGNUP
	elif _keyboard.done:
		page = Page.SIGNUP
		_draft_name = _keyboard.text.strip_edges()
		_row = Row.COLOR if _draft_name != "" else Row.NAME  # le nom est tapé : on choisit la couleur


# --- Page 2 : l'arbre, ALÉATOIRE et les réglages ---

func _open_board() -> void:
	page = Page.BOARD
	_focus = Focus.PLAY if not tournament.next_match().is_empty() else Focus.RANDOM
	_anim_start = -1
	_confirm = false
	board_message = ""


## Revient sur l'arbre (après un match du tournoi, ou en quittant le choix des persos).
func open_board() -> void:
	exited = false
	tournament = TournamentData.load_saved()
	_open_board()


func _handle_board(action: String) -> void:
	if action != "confirm":
		_confirm = false
	if action != "":
		board_message = ""
	match action:
		"up", "down":
			var bottom := _focus if _focus in [Focus.RANDOM, Focus.PLAY] else Focus.RANDOM
			var order := [Focus.TABS, Focus.SETTING, bottom]
			_focus = order[posmod(order.find(_focus if _focus != Focus.PLAY else bottom) + (1 if action == "down" else -1), order.size())]
		"left", "right":
			var step := 1 if action == "right" else -1
			match _focus:
				Focus.TABS:
					_tab = posmod(_tab + step, Tab.size())
				Focus.SETTING:
					_change_setting(step)
				Focus.RANDOM, Focus.PLAY:
					_focus = Focus.PLAY if _focus == Focus.RANDOM else Focus.RANDOM
		"confirm":
			match _focus:
				Focus.RANDOM:
					_shuffle_or_confirm()
				Focus.PLAY:
					_play()
				Focus.TABS:
					_tab = posmod(_tab + 1, Tab.size())
				Focus.SETTING:
					_change_setting(1)
		"back":
			_open_signup()


## ALÉATOIRE : une fois des matchs joués, un 2e appui est demandé (le tirage efface les résultats).
func _shuffle_or_confirm() -> void:
	if not tournament.results.is_empty() and not _confirm:
		_confirm = true
		return
	_confirm = false
	_shuffle()


## START : tire au hasard un match du tour en cours et le lance (le menu passe à la page d'appel).
func _play() -> void:
	var game := tournament.random_match()
	if not game.is_empty():
		launch = game


## Ce qu'on dit sous les boutons quand START ne peut rien lancer : le champion, ou ce qu'il manque.
func _play_text() -> String:
	var champion := tournament.champion()
	if champion >= 0:
		return "CHAMPION : %s !" % tournament.players[champion].name
	return "Tire au sort d'abord avec ALÉATOIRE"


## Tire les places au sort, et lance l'animation des noms qui volent jusqu'à leur place.
func _shuffle() -> void:
	_from_places = []
	_from_places.resize(tournament.players.size())
	_from_places.fill(-1)
	if tournament.is_seeded():
		for place in tournament.seeding.size():
			_from_places[tournament.seeding[place]] = place
	tournament.shuffle()
	tournament.save()
	_anim_start = Time.get_ticks_msec()


func _change_setting(step: int) -> void:
	if _tab == Tab.MAPS:
		var maps := GameSetup.MAPS
		tournament.map = maps[posmod(maps.find(tournament.map) + step, maps.size())]
	else:
		var span := TournamentData.MAX_LIVES - TournamentData.MIN_LIVES + 1
		tournament.lives = TournamentData.MIN_LIVES + posmod(tournament.lives - TournamentData.MIN_LIVES + step, span)
	tournament.save()


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
		Page.SIGNUP:
			_build_signup(content)
		Page.KEYBOARD:
			content.add_child(_keyboard.build())
		Page.BOARD:
			_build_board(content)


func _build_signup(parent: VBoxContainer) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	parent.add_child(content)
	content.add_child(UiKit.label("INSCRIPTION AU TOURNOI", 40))

	var name_row := _line("Nom :")
	name_row.add_child(UiKit.cell_button(_draft_name if _draft_name != "" else "appuie sur A pour l'écrire",
		_row == Row.NAME, _click_row.bind(Row.NAME), 320, Color.WHITE if _draft_name != "" else UiKit.TEXT_DIM))
	content.add_child(name_row)
	var color_row := _line("Couleur :")
	for c in TournamentData.COLORS.size():
		color_row.add_child(_swatch(c))
	content.add_child(color_row)
	var register := UiKit.cell_button("S'INSCRIRE", _row == Row.REGISTER, _click_row.bind(Row.REGISTER), 260)
	register.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(register)
	content.add_child(UiKit.label(_message if _message != "" else " ", 18, UiKit.HIGHLIGHT))

	content.add_child(UiKit.label("Inscrits : %d / %d" % [tournament.players.size(), TournamentData.MAX_PLAYERS], 22))
	if tournament.players.is_empty():
		content.add_child(UiKit.label("Personne pour l'instant", 18, UiKit.TEXT_DIM))
	else:
		var grid := GridContainer.new()
		grid.columns = CHIP_COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for i in tournament.players.size():
			grid.add_child(_name_chip(i, _row == Row.PLAYERS and i == _chip))
		content.add_child(grid)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	actions.add_child(UiKit.cell_button("VOIR L'ARBRE  →", _row == Row.NEXT, _click_row.bind(Row.NEXT), 240))
	actions.add_child(UiKit.cell_button("TOUT EFFACER", _row == Row.CLEAR, _click_row.bind(Row.CLEAR), 200, UiKit.TEXT_DIM))
	content.add_child(actions)

	var hint := "haut / bas : choisir      A : valider      B : retour au menu"
	match _row:
		Row.COLOR:
			hint = "gauche / droite : couleur      A : s'inscrire"
		Row.PLAYERS:
			hint = "flèches : choisir un inscrit      A : le retirer"
	if _confirm and _row == Row.PLAYERS:
		hint = "Retirer %s ? Appuie encore sur A pour confirmer." % tournament.players[_chip].name
	elif _confirm and _row == Row.CLEAR:
		hint = "Effacer tous les inscrits ? Appuie encore sur A pour confirmer."
	content.add_child(UiKit.label(hint, 18, WARNING if _confirm else UiKit.TEXT_DIM))


func _build_board(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(TournamentBoard.new(tournament, BOARD_SIZE, _anim_start, _from_places))
	var next := tournament.next_match()
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var random := UiKit.menu_button("ALÉATOIRE", _focus == Focus.RANDOM, _click_random, 70)
	random.custom_minimum_size.x = 300
	random.add_theme_font_size_override("font_size", 34)
	buttons.add_child(random)
	var play := UiKit.menu_button("START", _focus == Focus.PLAY, _click_play, 70)
	play.custom_minimum_size.x = 300
	play.add_theme_font_size_override("font_size", 34)
	if next.is_empty():
		play.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	buttons.add_child(play)
	left.add_child(buttons)
	var hint := "A : valider      gauche / droite : ALÉATOIRE ou START      haut / bas : réglages      B : inscription"
	if _confirm:
		hint = "Refaire le tirage efface les matchs déjà joués. Appuie encore sur A pour confirmer."
	elif board_message != "":
		hint = board_message
	elif next.is_empty():
		hint = _play_text()
	left.add_child(UiKit.label(hint, 16, WARNING if _confirm or board_message != "" else UiKit.TEXT_DIM))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UiKit.slot_style(Color.WHITE, false))
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiKit.label("RÉGLAGES", 26))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	for t in Tab.size():
		var tab_selected := _focus == Focus.TABS and _tab == t
		tabs.add_child(UiKit.cell_button(["MAPS", "RÈGLES"][t], tab_selected, _click_tab.bind(t), 140,
			UiKit.HIGHLIGHT if _tab == t else UiKit.TEXT_DIM))
	box.add_child(tabs)
	var on := _focus == Focus.SETTING
	if _tab == Tab.MAPS:
		for path in GameSetup.MAPS:
			var map_name := _map_name(path)
			var chosen: bool = path == tournament.map
			box.add_child(UiKit.cell_button(("✔  " if chosen else "") + map_name, on and chosen, _click_setting, 280))
		box.add_child(UiKit.label("Il n'y a que l'Arène pour l'instant.", 16, UiKit.TEXT_DIM))
	else:
		var lives_row := HBoxContainer.new()
		lives_row.alignment = BoxContainer.ALIGNMENT_CENTER
		lives_row.add_theme_constant_override("separation", 10)
		lives_row.add_child(UiKit.label("Vies :", 22))
		lives_row.add_child(UiKit.cell_button("<   %d   >" % tournament.lives, on, _click_setting, 140))
		box.add_child(lives_row)
		box.add_child(UiKit.label("par joueur et par match", 16, UiKit.TEXT_DIM))


## Une ligne « titre : ... », centrée.
func _line(title: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 8)
	line.add_child(UiKit.label(title, 22))
	return line


## Une pastille de couleur à choisir (entourée quand c'est la couleur choisie).
func _swatch(color_index: int) -> Button:
	var color: Color = TournamentData.COLORS[color_index]
	var chosen := color_index == _draft_color
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(34, 34)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(17)
	style.border_color = UiKit.HIGHLIGHT if _row == Row.COLOR else Color.WHITE
	style.set_border_width_all(4 if chosen else 0)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(_click_color.bind(color_index), CONNECT_DEFERRED)
	return button


## La case d'un inscrit : son nom sur sa couleur.
func _name_chip(index: int, selected: bool) -> Button:
	var player: Dictionary = tournament.players[index]
	var color: Color = TournamentData.COLORS[player.color]
	var button := Button.new()
	button.text = player.name
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(130, 34)
	button.add_theme_font_size_override("font_size", 17)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.bg_color = Color(color, 0.45)
	style.border_color = UiKit.HIGHLIGHT if selected else color
	style.set_border_width_all(3 if selected else 2)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(_click_chip.bind(index), CONNECT_DEFERRED)
	return button


var _map_names := {}  ## chemin de la map -> son nom (pour ne pas recharger la map à chaque affichage)

func _map_name(path: String) -> String:
	if not _map_names.has(path):
		var map := (load(path) as PackedScene).instantiate() as GameMap
		_map_names[path] = map.map_name
		map.free()
	return _map_names[path]


# --- Souris ---

func _click_row(row: int) -> void:
	if row != _row:
		_confirm = false
	_message = ""
	_activate_row(row)
	_redraw.call()


func _click_color(color_index: int) -> void:
	_draft_color = color_index
	_row = Row.COLOR
	_redraw.call()


func _click_chip(index: int) -> void:
	if _row != Row.PLAYERS or _chip != index:
		_confirm = false
	_row = Row.PLAYERS
	_chip = index
	_activate_row(Row.PLAYERS)
	_redraw.call()


func _click_random() -> void:
	if _focus != Focus.RANDOM:
		_confirm = false
	_focus = Focus.RANDOM
	_shuffle_or_confirm()
	_redraw.call()


func _click_play() -> void:
	_focus = Focus.PLAY
	_play()
	_redraw.call()


func _click_tab(tab: int) -> void:
	_focus = Focus.TABS
	_tab = tab
	_redraw.call()


func _click_setting() -> void:
	_focus = Focus.SETTING
	_change_setting(1)
	_redraw.call()
