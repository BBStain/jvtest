extends Control
## L'écran de connexion avant la partie.
##
## Chaque joueur se connecte avec son appareil :
##   - manette : bouton A (B pour se retirer)
##   - clavier gauche : Espace      - clavier droit : L
##   - Échap retire le dernier joueur clavier
## Il faut au moins 2 joueurs pour lancer la partie (bouton à l'écran, Start ou Entrée).

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/main.tscn"

## Un appareil par joueur (voir InputBindings pour le format).
var _joined: Array[Dictionary] = []
var _slots: Array[Dictionary] = []   ## les cases affichées : {"panel", "title", "detail"}

@onready var _slots_box: HBoxContainer = $Center/Layout/Slots
@onready var _start_button: Button = $Center/Layout/StartButton
@onready var _start_hint: Label = $Center/Layout/StartHint


func _ready() -> void:
	_build_slots()
	_start_button.pressed.connect(_start_game)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# En revenant d'une partie, on garde les joueurs déjà connectés.
	for devices in GameSetup.player_devices:
		var device: Dictionary = devices[0]
		if device.type == "keyboard" or device.id in Input.get_connected_joypads():
			_joined.append(device)
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var device := {"type": "joypad", "id": event.device}
		match event.button_index:
			JOY_BUTTON_A:
				_join(device)
			JOY_BUTTON_B:
				_leave(device)
			JOY_BUTTON_START:
				_start_game()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				_join({"type": "keyboard", "layout": 0})
			KEY_L, KEY_KP_0:
				_join({"type": "keyboard", "layout": 1})
			KEY_ESCAPE:
				for i in range(_joined.size() - 1, -1, -1):
					if _joined[i].type == "keyboard":
						_leave(_joined[i])
						break
			KEY_ENTER, KEY_KP_ENTER:
				_start_game()


func _join(device: Dictionary) -> void:
	if device in _joined or _joined.size() >= MAX_PLAYERS:
		return
	_joined.append(device)
	_refresh()


func _leave(device: Dictionary) -> void:
	_joined.erase(device)
	_refresh()


func _on_joy_connection_changed(id: int, connected: bool) -> void:
	if not connected:
		_leave({"type": "joypad", "id": id})


func _start_game() -> void:
	if _joined.size() < MIN_PLAYERS:
		return
	GameSetup.player_devices = []
	for device in _joined:
		GameSetup.player_devices.append([device])
	get_tree().change_scene_to_file(GAME_SCENE)


# --- Affichage ---

func _build_slots() -> void:
	for i in MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(250, 170)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 12)
		panel.add_child(box)
		var title := Label.new()
		title.text = "Joueur %d" % (i + 1)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 32)
		box.add_child(title)
		var detail := Label.new()
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", 18)
		box.add_child(detail)
		_slots_box.add_child(panel)
		_slots.append({"panel": panel, "title": title, "detail": detail})


func _refresh() -> void:
	for i in MAX_PLAYERS:
		var slot := _slots[i]
		var color: Color = Game.PLAYER_COLORS[i]
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		if i < _joined.size():
			style.bg_color = Color(color, 0.25)
			style.border_color = color
			style.set_border_width_all(3)
			slot.title.add_theme_color_override("font_color", color)
			slot.detail.text = InputBindings.device_name(_joined[i])
			slot.detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		else:
			style.bg_color = Color(1, 1, 1, 0.05)
			slot.title.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
			slot.detail.text = "En attente…" if i > _joined.size() else "Appuie sur A\n(ou Espace / L au clavier)"
			slot.detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		slot.panel.add_theme_stylebox_override("panel", style)

	var can_start := _joined.size() >= MIN_PLAYERS
	_start_button.disabled = not can_start
	if can_start:
		_start_hint.text = "ou appuie sur Start / Entrée"
	else:
		_start_hint.text = "Il faut %d joueurs pour lancer la partie" % MIN_PLAYERS
