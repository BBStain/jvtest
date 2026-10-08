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

enum Screen { TITLE, MAIN, CONTROLS, OPTIONS, CHARACTERS, MAPS }

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/main.tscn"
const MAIN_BUTTONS := ["JOUER", "COMMANDES", "OPTIONS"]
const MIN_LIVES := 1
const MAX_LIVES := 5
const STICK_PRESS := 0.6     ## stick poussé au-delà : compte comme un appui
const STICK_RELEASE := 0.3   ## stick revenu en deçà : prêt pour l'appui suivant

const BG_COLOR := Color(0.08, 0.09, 0.13)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const HIGHLIGHT := Color(1.0, 0.85, 0.3)

# Touches du clavier gauche et du clavier droit pour se déplacer dans le menu (touches physiques).
const KEYS_LEFT_SIDE := {
	KEY_W: "up", KEY_S: "down", KEY_A: "left", KEY_D: "right",
	KEY_SPACE: "confirm", KEY_F: "confirm", KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm",
	KEY_ESCAPE: "back", KEY_C: "back",
}
const KEYS_RIGHT_SIDE := {
	KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right",
	KEY_L: "confirm", KEY_K: "confirm", KEY_KP_0: "confirm", KEY_KP_1: "confirm",
	KEY_U: "back", KEY_BACKSPACE: "back", KEY_KP_4: "back",
	KEY_I: "", KEY_J: "", KEY_KP_2: "", KEY_KP_3: "",  # autres touches du joueur de droite
}
const JOY_BUTTON_ACTIONS := {
	JOY_BUTTON_DPAD_UP: "up", JOY_BUTTON_DPAD_DOWN: "down",
	JOY_BUTTON_DPAD_LEFT: "left", JOY_BUTTON_DPAD_RIGHT: "right",
	JOY_BUTTON_A: "confirm", JOY_BUTTON_START: "confirm", JOY_BUTTON_B: "back",
}

var screen := Screen.TITLE
var change_scene_on_start := true        ## false dans les tests : on ne quitte pas la scène
var players: Array[Dictionary] = []      ## l'appareil de chaque joueur, dans l'ordre J1, J2...
var _choice := 0                         ## bouton sélectionné (menu principal, options)
var _character_choice: Array[int] = []   ## perso sélectionné par chaque joueur
var _locked: Array[bool] = []            ## le joueur a validé son perso
var _map_choice := 0
var _stick_held := {}                    ## "manette:axe" -> le stick est déjà poussé
var _blink_label: Label
var _blink_time := 0.0
var _content: VBoxContainer


func _ready() -> void:
	InputBindings.fix_web_triggers()
	var background := ColorRect.new()
	background.color = BG_COLOR
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
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	# En revenant d'une partie, on garde les joueurs et on va directement au menu principal.
	for devices in GameSetup.player_devices:
		var device: Dictionary = devices[0]
		if device.type == "keyboard" or device.id in Input.get_connected_joypads():
			_add_player(device)
	screen = Screen.MAIN if not players.is_empty() else Screen.TITLE
	_show()


func _process(delta: float) -> void:
	if _blink_label != null and is_instance_valid(_blink_label):
		_blink_time += delta
		_blink_label.modulate.a = 0.45 + 0.55 * absf(sin(_blink_time * 2.5))


# --- Lecture des manettes et du clavier ---

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if KEYS_RIGHT_SIDE.has(key):
			handle({"type": "keyboard", "layout": 1}, KEYS_RIGHT_SIDE[key])
		else:
			handle({"type": "keyboard", "layout": 0}, KEYS_LEFT_SIDE.get(key, ""))
	elif event is InputEventJoypadButton and event.pressed:
		handle({"type": "joypad", "id": event.device}, JOY_BUTTON_ACTIONS.get(event.button_index, ""))
	elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var latch := "%d:%d" % [event.device, event.axis]
		if absf(event.axis_value) < STICK_RELEASE:
			_stick_held[latch] = false
		elif absf(event.axis_value) > STICK_PRESS and not _stick_held.get(latch, false):
			_stick_held[latch] = true
			var action := ""
			if event.axis == JOY_AXIS_LEFT_X:
				action = "right" if event.axis_value > 0.0 else "left"
			else:
				action = "down" if event.axis_value > 0.0 else "up"
			var device := {"type": "joypad", "id": event.device}
			if device in players:  # un stick ne fait pas rejoindre (il peut bouger tout seul)
				handle(device, action)
	elif event is InputEventMouseButton and event.pressed and screen == Screen.TITLE:
		handle({"type": "keyboard", "layout": 0}, "confirm")


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
			else:
				_remove_player(player)  # le joueur quitte la partie


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
			_content.add_child(_spacer(40))
			_blink_label = _label("Appuie sur une touche", 34)
			_content.add_child(_blink_label)
			_content.add_child(_label("manette ou clavier", 18, TEXT_DIM))
		Screen.MAIN:
			_add_title(56)
			for i in MAIN_BUTTONS.size():
				_content.add_child(_menu_button(MAIN_BUTTONS[i], i == _choice, _open_main_button.bind(i)))
			_content.add_child(_spacer(10))
			_content.add_child(_player_chips())
			_content.add_child(_join_hint())
		Screen.CONTROLS:
			_content.add_child(_label("COMMANDES", 44))
			_content.add_child(_controls_table())
			_content.add_child(_label("B / Échap : retour", 18, TEXT_DIM))
		Screen.OPTIONS:
			_content.add_child(_label("OPTIONS", 44))
			_content.add_child(_label("Vies par joueur :   <   %d   >" % GameSetup.lives, 30, HIGHLIGHT))
			_content.add_child(_label("gauche / droite pour changer, B / Échap : retour", 18, TEXT_DIM))
		Screen.CHARACTERS:
			_content.add_child(_label("CHOISIS TON PERSONNAGE", 40))
			var slots := HBoxContainer.new()
			slots.alignment = BoxContainer.ALIGNMENT_CENTER
			slots.add_theme_constant_override("separation", 18)
			for i in MAX_PLAYERS:
				slots.add_child(_character_slot(i))
			_content.add_child(slots)
			var hint := "gauche / droite pour choisir, A pour valider, B pour revenir"
			if players.size() < MIN_PLAYERS:
				hint = "Il faut au moins 2 joueurs : appuie sur une touche d'une autre manette ou de l'autre côté du clavier"
			_content.add_child(_label(hint, 18, TEXT_DIM))
		Screen.MAPS:
			_content.add_child(_label("CHOISIS LA MAP", 40))
			_content.add_child(_map_card())
			_content.add_child(_label("gauche / droite pour choisir, A pour lancer la partie, B pour revenir", 18, TEXT_DIM))


func _add_title(size: int) -> void:
	_content.add_child(_label("BRAWLER DU SWAG", size))


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _menu_button(text: String, selected: bool, on_click: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(380, 70)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 30)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.bg_color = Color(HIGHLIGHT, 0.22) if selected else Color(1, 1, 1, 0.06)
	style.border_color = HIGHLIGHT if selected else Color(1, 1, 1, 0.15)
	style.set_border_width_all(3 if selected else 1)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", HIGHLIGHT if selected else Color.WHITE)
	button.pressed.connect(on_click, CONNECT_DEFERRED)  # différé : le bouton est recréé par _show()
	return button


## Les joueurs déjà connectés, en petites pastilles de leur couleur.
func _player_chips() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for i in players.size():
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _slot_style(Game.PLAYER_COLORS[i], true))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.add_child(_device_icon(players[i], Game.PLAYER_COLORS[i], Vector2(44, 28)))
		box.add_child(_label("J%d" % (i + 1), 20, Game.PLAYER_COLORS[i]))
		chip.add_child(box)
		row.add_child(chip)
	return row


func _join_hint() -> Label:
	if players.size() >= MAX_PLAYERS:
		return _label("4 joueurs connectés", 18, TEXT_DIM)
	return _label("Autres joueurs : appuie sur une touche de ta manette ou de l'autre côté du clavier pour rejoindre", 18, TEXT_DIM)


func _slot_style(color: Color, active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if active:
		style.bg_color = Color(color, 0.18)
		style.border_color = color
		style.set_border_width_all(3)
	else:
		style.bg_color = Color(1, 1, 1, 0.04)
	return style


## Une case du choix de perso : le joueur, son appareil, et le perso qu'il fait défiler.
func _character_slot(index: int) -> PanelContainer:
	var color: Color = Game.PLAYER_COLORS[index]
	var joined := index < players.size()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 300)
	panel.add_theme_stylebox_override("panel", _slot_style(color, joined))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("Joueur %d" % (index + 1), 26, color if joined else Color(1, 1, 1, 0.3)))
	if not joined:
		box.add_child(_label("Appuie sur\nune touche\npour rejoindre", 18, Color(1, 1, 1, 0.35)))
		return panel
	var icon := _device_icon(players[index], color, Vector2(64, 40))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var stats := load(GameSetup.CHARACTERS[_character_choice[index]]) as CharacterStats
	box.add_child(_character_preview(stats, color))
	var arrows := "%s" if _locked[index] else "<   %s   >"
	box.add_child(_label(arrows % stats.display_name, 22))
	if _locked[index]:
		box.add_child(_label("PRÊT !", 24, HIGHLIGHT))
	else:
		box.add_child(_label("%s pour valider" % _confirm_key(players[index]), 16, TEXT_DIM))
	return panel


## La touche pour valider, selon l'appareil du joueur.
func _confirm_key(device: Dictionary) -> String:
	if device.type == "joypad":
		return "A"
	return "Espace" if device.layout == 0 else "L"


## Le perso dessiné en grand (une barre de sa taille, à sa couleur).
func _character_preview(stats: CharacterStats, color: Color) -> Control:
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(120, 110)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.draw.connect(func() -> void:
		var body := stats.body_size * 1.5
		var origin := Vector2(preview.size.x / 2.0 - body.x / 2.0, preview.size.y - body.y)
		preview.draw_rect(Rect2(origin, body), color)
		preview.draw_rect(Rect2(origin + Vector2(body.x / 2.0 + 2.0, 12.0), Vector2(7, 7)), BG_COLOR)
	)
	return preview


## Un petit dessin de manette ou de clavier.
func _device_icon(device: Dictionary, color: Color, icon_size: Vector2) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = icon_size
	icon.draw.connect(func() -> void:
		var s := icon.size
		if device.type == "joypad":
			var body := Rect2(s.x * 0.18, s.y * 0.15, s.x * 0.64, s.y * 0.55)
			icon.draw_rect(body, color)
			icon.draw_circle(Vector2(s.x * 0.22, s.y * 0.55), s.y * 0.3, color)
			icon.draw_circle(Vector2(s.x * 0.78, s.y * 0.55), s.y * 0.3, color)
			var dark := BG_COLOR
			var c := Vector2(s.x * 0.3, s.y * 0.45)
			icon.draw_rect(Rect2(c - Vector2(s.y * 0.15, s.y * 0.05), Vector2(s.y * 0.3, s.y * 0.1)), dark)
			icon.draw_rect(Rect2(c - Vector2(s.y * 0.05, s.y * 0.15), Vector2(s.y * 0.1, s.y * 0.3)), dark)
			for offset in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
				icon.draw_circle(Vector2(s.x * 0.7, s.y * 0.45) + offset * s.y * 0.11, s.y * 0.05, dark)
		else:
			var frame := Rect2(1, s.y * 0.1, s.x - 2, s.y * 0.8)
			icon.draw_rect(frame, color, false, 2.0)
			var key := Vector2((s.x - 10.0) / 8.0, s.y * 0.14)
			for row in 3:
				for col in 7:
					icon.draw_rect(Rect2(5.0 + col * key.x * 1.12, s.y * 0.2 + row * key.y * 1.4, key.x * 0.85, key.y), color)
			icon.draw_rect(Rect2(s.x * 0.3, s.y * 0.68, s.x * 0.4, key.y * 0.8), color)
	)
	return icon


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
		preview.draw_rect(Rect2(Vector2.ZERO, preview.size), HIGHLIGHT, false, 3.0)
	)
	box.add_child(preview)
	var arrows := "<   %s   >" if GameSetup.MAPS.size() > 1 else "%s"
	box.add_child(_label(arrows % map_name, 30, HIGHLIGHT))
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
		["Attaque lourde (garder)", "Y", "R", "I"],
		["Dash", "LB", "G", "J"],
		["Courir (garder)", "LT", "Shift gauche", "Shift droit"],
		["Bloquer (garder)", "B", "C", "U"],
	]
	for r in rows.size():
		for cell in rows[r]:
			var label := _label(cell, 20, HIGHLIGHT if r == 0 else Color.WHITE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			grid.add_child(label)
	return grid
