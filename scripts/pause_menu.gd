class_name PauseMenu
extends Control
## Le menu pause (Start sur la manette, Échap ou P au clavier) :
##   REPRENDRE : on continue la partie.
##   RESTART   : on recommence la partie avec les mêmes joueurs.
##   REMAP     : on échange les manettes (ou claviers) entre joueurs : chacun pousse gauche / droite
##               pour envoyer sa manette au joueur d'à côté (ex. la manette du J1 passe au J2).
##   QUITTER   : retour au menu principal.
## Pendant la pause, tout le jeu est figé (get_tree().paused) ; seul ce menu tourne.

enum Screen { LIST, REMAP }

const BUTTONS := ["REPRENDRE", "RESTART", "REMAP", "QUITTER"]

var game: Game
var screen := Screen.LIST
var change_scene := true   ## false dans les tests : RESTART et QUITTER ne changent pas de scène
var _choice := 0
var _input_reader := MenuInput.new()
var _content: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.06, 0.8)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 20)
	center.add_child(_content)
	_show()


func _input(event: InputEvent) -> void:
	var press := _input_reader.read(event)
	if press.is_empty():
		return
	get_viewport().set_input_as_handled()
	handle(press.device, press.action)


## Un appareil a appuyé sur une touche (même actions que MenuInput).
func handle(device: Dictionary, action: String) -> void:
	if screen == Screen.LIST:
		match action:
			"up":
				_choice = posmod(_choice - 1, BUTTONS.size())
				_show()
			"down":
				_choice = posmod(_choice + 1, BUTTONS.size())
				_show()
			"confirm":
				choose(_choice)
			"back", "start":
				resume()
		return
	# REMAP : gauche / droite envoie sa manette au joueur d'à côté.
	match action:
		"left", "right":
			var player := game.player_of_device(device)
			if player != -1:
				var other := posmod(player + (1 if action == "right" else -1), game.fighters.size())
				game.swap_devices(player, other)
				if device.type == "joypad":
					Input.start_joy_vibration(device.id, 0.4, 0.6, 0.15)  # petite vibration : « c'est bien moi »
				_show()
		"confirm", "back", "start":
			screen = Screen.LIST
			_show()


func choose(index: int) -> void:
	_choice = index
	match index:
		0:
			resume()
		1:
			get_tree().paused = false
			if change_scene:
				get_tree().reload_current_scene()
		2:
			screen = Screen.REMAP
			_show()
		3:
			get_tree().paused = false
			if change_scene:
				get_tree().change_scene_to_file(Game.MENU_SCENE)


func resume() -> void:
	game.close_pause()


func _show() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if screen == Screen.LIST:
		_content.add_child(UiKit.label("PAUSE", 56))
		for i in BUTTONS.size():
			_content.add_child(UiKit.menu_button(BUTTONS[i], i == _choice, choose.bind(i)))
		_content.add_child(UiKit.label("Start / Échap : reprendre", 18, UiKit.TEXT_DIM))
		return
	_content.add_child(UiKit.label("REMAP", 48))
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 18)
	for i in game.fighters.size():
		slots.add_child(_player_slot(i))
	_content.add_child(slots)
	_content.add_child(UiKit.label("Chacun : gauche / droite pour envoyer sa manette (ou son clavier) au joueur d'à côté", 18, UiKit.TEXT_DIM))
	_content.add_child(UiKit.label("A / B : terminé", 18, UiKit.TEXT_DIM))


## La case d'un joueur : sa couleur et le ou les appareils qui le contrôlent.
func _player_slot(index: int) -> PanelContainer:
	var color: Color = Game.PLAYER_COLORS[index]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 200)
	panel.add_theme_stylebox_override("panel", UiKit.slot_style(color, true))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiKit.label("Joueur %d" % (index + 1), 26, color))
	for device in game.player_devices[index]:
		var icon := UiKit.device_icon(device, color, Vector2(64, 40))
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var device_label := "Manette %d" % (device.id + 1) if device.type == "joypad" else InputBindings.device_name(device)
		box.add_child(UiKit.label(device_label, 16))
	box.add_child(UiKit.label("<       >", 22, UiKit.TEXT_DIM))
	return panel
