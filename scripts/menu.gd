extends Control
## Le menu du jeu, du premier écran jusqu'au lancement de la partie :
##   1. Écran titre : « Appuie sur une touche ». Le premier qui appuie devient le joueur 1.
##   2. Menu principal : JOUER, COMMANDES, OPTIONS. Tant qu'on est dans le menu, chaque
##      nouvelle manette ou côté de clavier qui appuie sur une touche devient le joueur suivant.
##   3. Choix du personnage : chaque joueur fait défiler les persos (gauche / droite) et valide.
##   4. Choix de la map, puis la partie se lance.
##
## Commandes du menu, pour chaque joueur :
##   manette : stick ou croix pour choisir, A (ou Start) pour valider, B pour revenir
##   clavier gauche : Z Q S D, Espace / F / Entrée pour valider, Échap / C pour revenir
##   clavier droit : flèches, L / K pour valider, U / Retour arrière pour revenir
## Dans le choix du perso, chaque joueur peut se retirer de la partie : Y (manette), R (clavier
## gauche) ou I (clavier droit).
## (voir MenuInput pour la lecture des touches et UiKit pour les morceaux d'affichage communs)

enum Screen { TITLE, MAIN, CONTROLS, OPTIONS, CHARACTERS, MAPS }

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/main.tscn"
const MAIN_BUTTONS := ["JOUER", "COMMANDES", "OPTIONS"]
const MIN_LIVES := 1
const MAX_LIVES := 5
const SLOT_SIZE := Vector2(230, 480)    ## taille fixe des cases du choix de perso (rien ne bouge)
const PREVIEW_SIZE := Vector2(120, 130) ## la zone où le perso est dessiné

var screen := Screen.TITLE
var change_scene_on_start := true        ## false dans les tests : on ne quitte pas la scène
var players: Array[Dictionary] = []      ## l'appareil de chaque joueur, dans l'ordre J1, J2...
var _choice := 0                         ## bouton sélectionné (menu principal, options)
var _character_choice: Array[int] = []   ## perso sélectionné par chaque joueur
var _locked: Array[bool] = []            ## le joueur a validé son perso
var _map_choice := 0
var _input_reader := MenuInput.new()
var _blink_label: Label
var _blink_time := 0.0
var _content: VBoxContainer


func _ready() -> void:
	InputBindings.fix_web_triggers()
	var background := ColorRect.new()
	background.color = UiKit.BG_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 22)
	center.add_child(_content)
	add_child(BuildVersion.make_label())
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	# En revenant d'une partie, on garde les joueurs (et leur perso) et on va directement au menu principal.
	for i in GameSetup.player_devices.size():
		var device: Dictionary = GameSetup.player_devices[i][0]
		if device in players or not (device.type == "keyboard" or device.id in Input.get_connected_joypads()):
			continue
		_add_player(device)
		if i < GameSetup.player_characters.size():
			_character_choice[-1] = maxi(GameSetup.CHARACTERS.find(GameSetup.player_characters[i]), 0)
	screen = Screen.MAIN if not players.is_empty() else Screen.TITLE
	_show()


func _process(delta: float) -> void:
	if _blink_label != null and is_instance_valid(_blink_label):
		_blink_time += delta
		_blink_label.modulate.a = 0.45 + 0.55 * absf(sin(_blink_time * 2.5))


# --- Lecture des manettes et du clavier ---

func _input(event: InputEvent) -> void:
	var press := _input_reader.read(event)
	if press.is_empty():
		if event is InputEventMouseButton and event.pressed and screen == Screen.TITLE:
			handle({"type": "keyboard", "layout": 0}, "confirm")
		return
	if press.stick and not (press.device in players):
		return  # un stick ne fait pas rejoindre (il peut bouger tout seul)
	handle(press.device, "confirm" if press.action == "start" else press.action)


## Un appareil vient d'appuyer sur une touche. action = "up", "down", "left", "right",
## "confirm", "back", ou "" pour une autre touche.
func handle(device: Dictionary, action: String) -> void:
	if screen == Screen.TITLE:
		_add_player(device)  # le premier qui appuie devient le joueur 1
		_go(Screen.MAIN)
		return
	var player := players.find(device)
	if player == -1:
		# Un nouvel appareil appuie : il devient le joueur suivant (pas pendant le choix de la map).
		if screen != Screen.MAPS and players.size() < MAX_PLAYERS:
			_add_player(device)
			_show()
		return
	match screen:
		Screen.MAIN:
			_handle_main(action)
		Screen.CONTROLS:
			if action in ["back", "confirm"]:
				_go(Screen.MAIN, 1)
		Screen.OPTIONS:
			_handle_options(action)
		Screen.CHARACTERS:
			_handle_characters(player, action)
		Screen.MAPS:
			_handle_maps(action)


func _on_joy_connection_changed(id: int, connected: bool) -> void:
	if not connected:
		var player := players.find({"type": "joypad", "id": id})
		if player != -1:
			_remove_player(player)


# --- Ce que fait chaque écran ---

func _handle_main(action: String) -> void:
	match action:
		"up":
			_choice = posmod(_choice - 1, MAIN_BUTTONS.size())
			_show()
		"down":
			_choice = posmod(_choice + 1, MAIN_BUTTONS.size())
			_show()
		"confirm":
			_open_main_button(_choice)


func _open_main_button(index: int) -> void:
	_choice = index
	match index:
		0:
			for i in players.size():
				_locked[i] = false
			_go(Screen.CHARACTERS)
		1:
			_go(Screen.CONTROLS)
		2:
			_go(Screen.OPTIONS)


func _handle_options(action: String) -> void:
	match action:
		"left":
			GameSetup.lives = maxi(GameSetup.lives - 1, MIN_LIVES)
			_show()
		"right":
			GameSetup.lives = mini(GameSetup.lives + 1, MAX_LIVES)
			_show()
		"back", "confirm":
			_go(Screen.MAIN, 2)


func _handle_characters(player: int, action: String) -> void:
	var count := GameSetup.CHARACTERS.size()
	match action:
		"left", "right":
			if not _locked[player]:
				_character_choice[player] = posmod(_character_choice[player] + (1 if action == "right" else -1), count)
				_show()
		"confirm":
			_locked[player] = true
			if _all_locked():
				_go(Screen.MAPS)
			else:
				_show()
		"back":
			if _locked[player]:
				_locked[player] = false
				_show()
			elif player == 0:
				_go(Screen.MAIN, 0)
		"quit":
			_remove_player(player)  # le joueur se retire (les suivants remontent d'une place)


func _all_locked() -> bool:
	return players.size() >= MIN_PLAYERS and not (false in _locked)


func _handle_maps(action: String) -> void:
	var count := GameSetup.MAPS.size()
	match action:
		"left", "right":
			_map_choice = posmod(_map_choice + (1 if action == "right" else -1), count)
			_show()
		"confirm":
			_start_game()
		"back":
			for i in players.size():
				_locked[i] = false
			_go(Screen.CHARACTERS)


func _start_game() -> void:
	GameSetup.player_devices = []
	GameSetup.player_characters = []
	for i in players.size():
		GameSetup.player_devices.append([players[i]])
		GameSetup.player_characters.append(GameSetup.CHARACTERS[_character_choice[i]])
	GameSetup.map_path = GameSetup.MAPS[_map_choice]
	if change_scene_on_start:
		get_tree().change_scene_to_file(GAME_SCENE)


func _add_player(device: Dictionary) -> void:
	if device in players or players.size() >= MAX_PLAYERS:
		return
	players.append(device)
	_character_choice.append(0)
	_locked.append(false)


func _remove_player(index: int) -> void:
	players.remove_at(index)
	_character_choice.remove_at(index)
	_locked.remove_at(index)
	if players.is_empty():
		_go(Screen.TITLE)
	elif screen == Screen.MAPS and players.size() < MIN_PLAYERS:
		_go(Screen.CHARACTERS)
	elif screen == Screen.CHARACTERS and _all_locked():
		_go(Screen.MAPS)
	else:
		_show()


func _go(to: Screen, choice := 0) -> void:
	screen = to
	_choice = choice
	_show()


# --- Affichage ---

## Redessine l'écran en cours.
func _show() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_blink_label = null
	match screen:
		Screen.TITLE:
			_add_title(72)
			_content.add_child(UiKit.spacer(40))
			_blink_label = UiKit.label("Appuie sur une touche", 34)
			_content.add_child(_blink_label)
			_content.add_child(UiKit.label("manette ou clavier", 18, UiKit.TEXT_DIM))
		Screen.MAIN:
			_add_title(56)
			for i in MAIN_BUTTONS.size():
				_content.add_child(UiKit.menu_button(MAIN_BUTTONS[i], i == _choice, _open_main_button.bind(i)))
			_content.add_child(UiKit.spacer(10))
			_content.add_child(_player_chips())
			_content.add_child(_join_hint())
		Screen.CONTROLS:
			_content.add_child(UiKit.label("COMMANDES", 44))
			_content.add_child(_controls_table())
			_content.add_child(UiKit.label("B / Échap : retour", 18, UiKit.TEXT_DIM))
		Screen.OPTIONS:
			_content.add_child(UiKit.label("OPTIONS", 44))
			_content.add_child(UiKit.label("Vies par joueur :   <   %d   >" % GameSetup.lives, 30, UiKit.HIGHLIGHT))
			_content.add_child(UiKit.label("gauche / droite pour changer, B / Échap : retour", 18, UiKit.TEXT_DIM))
		Screen.CHARACTERS:
			_content.add_child(UiKit.label("CHOISIS TON PERSONNAGE", 40))
			var slots := HBoxContainer.new()
			slots.alignment = BoxContainer.ALIGNMENT_CENTER
			slots.add_theme_constant_override("separation", 18)
			for i in MAX_PLAYERS:
				slots.add_child(_character_slot(i))
			_content.add_child(slots)
			var hint := "gauche / droite pour choisir, A pour valider, B pour revenir"
			if players.size() < MIN_PLAYERS:
				hint = "Il faut au moins 2 joueurs : appuie sur une touche d'une autre manette ou de l'autre côté du clavier"
			_content.add_child(UiKit.label(hint, 18, UiKit.TEXT_DIM))
		Screen.MAPS:
			_content.add_child(UiKit.label("CHOISIS LA MAP", 40))
			_content.add_child(_map_card())
			_content.add_child(UiKit.label("gauche / droite pour choisir, A pour lancer la partie, B pour revenir", 18, UiKit.TEXT_DIM))


func _add_title(size: int) -> void:
	_content.add_child(UiKit.label("BRAWLER DU SWAG", size))


## Les joueurs déjà connectés, en petites pastilles de leur couleur.
func _player_chips() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for i in players.size():
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiKit.slot_style(Game.PLAYER_COLORS[i], true))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.add_child(UiKit.device_icon(players[i], Game.PLAYER_COLORS[i], Vector2(44, 28)))
		box.add_child(UiKit.label("J%d" % (i + 1), 20, Game.PLAYER_COLORS[i]))
		chip.add_child(box)
		row.add_child(chip)
	return row


func _join_hint() -> Label:
	if players.size() >= MAX_PLAYERS:
		return UiKit.label("4 joueurs connectés", 18, UiKit.TEXT_DIM)
	return UiKit.label("Autres joueurs : appuie sur une touche de ta manette ou de l'autre côté du clavier pour rejoindre", 18, UiKit.TEXT_DIM)


## Une case du choix de perso : le joueur, son appareil, et le perso qu'il fait défiler.
## La case et chacune de ses lignes ont une taille fixe : changer de perso (plus grand, plus
## petit, description plus longue...) ne fait rien bouger à l'écran.
func _character_slot(index: int) -> PanelContainer:
	var color: Color = Game.PLAYER_COLORS[index]
	var joined := index < players.size()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.add_theme_stylebox_override("panel", UiKit.slot_style(color, joined))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiKit.label("Joueur %d" % (index + 1), 26, color if joined else Color(1, 1, 1, 0.3)))
	if not joined:
		box.add_child(UiKit.label("Appuie sur\nune touche\npour rejoindre", 18, Color(1, 1, 1, 0.35)))
		return panel
	var icon := UiKit.device_icon(players[index], color, Vector2(64, 40))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var stats := load(GameSetup.CHARACTERS[_character_choice[index]]) as CharacterStats
	box.add_child(_character_preview(stats, color))
	var arrows := "%s" if _locked[index] else "<   %s   >"
	box.add_child(_fixed_row(UiKit.label(arrows % stats.display_name, 22), 32))
	# La description a toujours 3 lignes de place : une description plus longue ou plus courte
	# ne change pas la hauteur de la case.
	var description_box := Control.new()
	description_box.custom_minimum_size = Vector2(200, 60)
	description_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var description := UiKit.label(stats.description, 14, UiKit.TEXT_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	description_box.add_child(description)
	box.add_child(description_box)
	if _locked[index]:
		box.add_child(_fixed_row(UiKit.label("PRÊT !", 24, UiKit.HIGHLIGHT), 34))
	else:
		box.add_child(_fixed_row(UiKit.label("%s pour valider" % _confirm_key(players[index]), 16, UiKit.TEXT_DIM), 34))
	box.add_child(_fixed_row(UiKit.label("%s : se retirer" % _quit_key(players[index]), 14, UiKit.TEXT_DIM), 22))
	return panel


## Donne une hauteur fixe à une ligne de texte (centrée dedans), pour que rien ne bouge :
## le texte est posé dans une boîte de taille fixe, la taille de la police n'y change rien.
func _fixed_row(label: Label, height: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(200, height)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(label)
	return row


## La touche pour se retirer de la partie, selon l'appareil du joueur.
func _quit_key(device: Dictionary) -> String:
	if device.type == "joypad":
		return "Y"
	return "R" if device.layout == 0 else "I"


## La touche pour valider, selon l'appareil du joueur.
func _confirm_key(device: Dictionary) -> String:
	if device.type == "joypad":
		return "A"
	return "Espace" if device.layout == 0 else "L"


## Le perso dessiné en grand (une barre de sa taille, à sa couleur), posé en bas d'une zone
## de taille fixe. Tous les persos sont dessinés à la même échelle : on voit qui est plus grand.
func _character_preview(stats: CharacterStats, color: Color) -> Control:
	var preview := Control.new()
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var zoom := _preview_zoom()
	preview.draw.connect(func() -> void:
		var body := stats.body_size * zoom
		var origin := Vector2(preview.size.x / 2.0 - body.x / 2.0, preview.size.y - body.y)
		preview.draw_rect(Rect2(origin, body), color)
		preview.draw_rect(Rect2(origin + Vector2(body.x / 2.0 + 2.0, 12.0), Vector2(7, 7)), UiKit.BG_COLOR)
	)
	return preview


## L'échelle commune des aperçus : le plus grand perso remplit la zone (sans dépasser 1,7 fois).
func _preview_zoom() -> float:
	var biggest := Vector2.ONE
	for path in GameSetup.CHARACTERS:
		var size := (load(path) as CharacterStats).body_size
		biggest = Vector2(maxf(biggest.x, size.x), maxf(biggest.y, size.y))
	return minf(1.7, minf(PREVIEW_SIZE.x / biggest.x, PREVIEW_SIZE.y / biggest.y))


## La carte de la map choisie : son nom et un petit plan de son décor.
func _map_card() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var map := (load(GameSetup.MAPS[_map_choice]) as PackedScene).instantiate() as GameMap
	var rects: Array[Rect2] = []
	_collect_map_rects(map, Vector2.ZERO, rects)
	var map_name := map.map_name
	var area := map.blast_zone
	map.free()
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(640, 300)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.draw.connect(func() -> void:
		preview.draw_rect(Rect2(Vector2.ZERO, preview.size), Color(1, 1, 1, 0.04))
		var bounds := rects[0] if not rects.is_empty() else Rect2(area)
		for r in rects:
			bounds = bounds.merge(r)
		bounds = bounds.grow(60)
		var k := minf(preview.size.x / bounds.size.x, preview.size.y / bounds.size.y)
		var offset := (preview.size - bounds.size * k) / 2.0
		for r in rects:
			preview.draw_rect(Rect2(offset + (r.position - bounds.position) * k, r.size * k), Color(0.62, 0.66, 0.8))
		preview.draw_rect(Rect2(Vector2.ZERO, preview.size), UiKit.HIGHLIGHT, false, 3.0)
	)
	box.add_child(preview)
	var arrows := "<   %s   >" if GameSetup.MAPS.size() > 1 else "%s"
	box.add_child(UiKit.label(arrows % map_name, 30, UiKit.HIGHLIGHT))
	return box


## Trouve toutes les plateformes et murs d'une map (pour le petit plan).
func _collect_map_rects(node: Node, offset: Vector2, rects: Array[Rect2]) -> void:
	for child in node.get_children():
		var pos := offset
		if child is Node2D:
			pos += (child as Node2D).position
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var shape_size: Vector2 = ((child as CollisionShape2D).shape as RectangleShape2D).size
			rects.append(Rect2(pos - shape_size / 2.0, shape_size))
		elif child is MovingPlatform:
			var platform := child as MovingPlatform
			rects.append(Rect2(pos - platform.size / 2.0, platform.size))
		_collect_map_rects(child, pos, rects)


## Le tableau des commandes (le même que dans le README).
func _controls_table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	var rows := [
		["", "Manette", "Clavier J1", "Clavier J2"],
		["Se déplacer", "Stick / croix", "Z Q S D", "Flèches"],
		["Sauter", "A", "Espace", "L"],
		["Attaque légère", "X", "F", "K"],
		["Attaque visée", "Stick droit", "-", "-"],
		["Attaque lourde (garder)", "Y", "R", "I"],
		["Dash", "LB", "G", "J"],
		["Courir (garder)", "LT", "Shift gauche", "Shift droit"],
		["Bloquer (garder)", "B", "C", "U"],
		["Pause", "Start", "Échap ou P", "Échap ou P"],
	]
	for r in rows.size():
		for cell in rows[r]:
			var label := UiKit.label(cell, 20, UiKit.HIGHLIGHT if r == 0 else Color.WHITE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			grid.add_child(label)
	return grid
