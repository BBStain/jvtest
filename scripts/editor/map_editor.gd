class_name MapEditor
extends Node2D
## L'éditeur de map, dans le jeu (menu principal > ÉDITEUR). Il se joue à la manette (voir EditorPad,
## editor_pad.gd) ou à la souris et au clavier ; on passe de l'un à l'autre quand on veut.
##
## L'écran :
##   en haut     : Nouvelle, Ouvrir, Sauver, le nom de la map, la grille (oui / non, sa taille),
##                 l'aimant (coller à la grille ou placement libre), TESTER et Quitter ;
##   à gauche    : le catalogue, rangé par familles (Décor, Mouvement, Apparitions) : un clic pose
##                 l'élément au milieu de la vue ;
##   à droite    : les réglages de l'élément choisi (position, taille, rotation, trajet...) ;
##   au milieu   : la map. Clic gauche : choisir / déplacer. Carré jaune : agrandir / rétrécir.
##                 Rond violet (plateforme mobile) : tirer pour régler son trajet.
##                 Clic droit ou molette enfoncée : déplacer la vue. Molette : zoom.
## Raccourcis : R / Maj+R tourner, Suppr effacer, flèches pousser, Ctrl+C / Ctrl+V copier / coller,
## Ctrl+D dupliquer, Ctrl+Z / Ctrl+Y annuler / refaire, Ctrl+S sauver, G grille, Échap lâcher.
##
## La map est gardée sous forme de données (voir MapData) ; MapBuilder en fait l'aperçu et la map jouable.
## TESTER lance une partie à 2 joueurs sur la map ; QUITTER dans le menu pause revient ici.

const EDITOR_SCENE := "res://scenes/editor.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const ROTATE_STEP := 15.0          ## degrés par appui sur R
const MIN_ZOOM := 0.12
const MAX_ZOOM := 2.5
const MIN_SIZE := 8.0
const AUTOSAVE_TIME := 20.0        ## le brouillon est gardé tout seul toutes les 20 s (s'il a changé)
const MAX_UNDO := 100
const HANDLE := 9.0                ## demi-taille du carré pour agrandir (à l'écran)
## Les 12 directions des plateformes mobiles (tous les 30°).
const DIRECTION_NAMES := ["→ droite", "↗ 30°", "↗ 60°", "↑ haut", "↖ 120°", "↖ 150°",
	"← gauche", "↙ 210°", "↙ 240°", "↓ bas", "↘ 300°", "↘ 330°"]
const PLAYER_COLORS := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(0.35, 0.85, 0.4), Color(1.0, 0.8, 0.2)]
## Les couleurs qu'on fait défiler à la manette (gauche / droite sur « Couleur »).
const COLOR_PRESETS := ["#525973", "#808aa8", "#9e8cd9", "#8cc7e6", "#59b34d", "#d9b366", "#d9735e", "#e6e6e6"]
const MOUSE_HELP := "Clic : choisir / déplacer   ·   carré jaune : taille   ·   R : tourner   ·   Suppr : effacer   ·   Ctrl+C / Ctrl+V : copier / coller   ·   Ctrl+Z : annuler   ·   clic droit : bouger la vue   ·   molette : zoom   ·   (ou prends une manette)"

## Gardés entre deux visites (quand on part tester la map et qu'on revient).
static var _last_camera := Vector2(640, 360)
static var _last_zoom := 0.6

var data: Dictionary                  ## la map en cours (voir MapData)
var selected_id := -1
var grid_on := true
var grid_size := 40
var snap_on := true
var change_scene := true              ## false dans les tests : TESTER et Quitter ne changent pas de scène

var _nodes := {}                      ## id -> le nœud d'aperçu de l'élément
var _clipboard: Dictionary = {}
var _undo: Array[String] = []
var _redo: Array[String] = []
var _drag := ""                       ## "", "move", "resize", "travel", "length", "pan"
var _drag_changed := false
var _drag_offset := Vector2.ZERO
var _drag_center := Vector2.ZERO
var _drag_anchor := Vector2.ZERO
var _dirty := false
var _autosave_left := AUTOSAVE_TIME

var _camera: Camera2D
var _grid: Node2D
var _preview: Node2D
var _overlay: Node2D
var _name_edit: LineEdit
var _grid_check: CheckButton
var _grid_spin: SpinBox
var _snap_check: CheckButton
var _open_button: MenuButton
var _props: VBoxContainer
var _message: Label
var _message_left := 0.0
var _help: Label
var _ui: CanvasLayer
var _pad: EditorPad
var _juice: EditorJuice
var _catalog_buttons: Array[Button] = []
var _catalog_types: Array[String] = []
var _prop_rows: Array[Dictionary] = []
var _prop_boxes: Array[PanelContainer] = []
var _prop_highlight := -1


func _ready() -> void:
	_camera = Camera2D.new()
	_camera.position = _last_camera
	_camera.zoom = Vector2.ONE * _last_zoom
	add_child(_camera)
	_grid = Node2D.new()
	_grid.draw.connect(_draw_grid)
	add_child(_grid)
	_preview = Node2D.new()
	_preview.process_mode = Node.PROCESS_MODE_DISABLED  # l'aperçu ne bouge pas (pas de navettes qui roulent)
	add_child(_preview)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_ui()
	_juice = EditorJuice.new()
	_juice.editor = self
	add_child(_juice)
	_pad = EditorPad.new()
	_pad.editor = self
	add_child(_pad)
	if not GameSetup.editor_map.is_empty():
		data = MapData.normalized(GameSetup.editor_map)
	else:
		data = MapData.load_saved(MapData.DRAFT_NAME)
		if data.is_empty():
			data = MapData.new_map()
	_rebuild_all()


func _process(delta: float) -> void:
	_last_camera = _camera.position
	_last_zoom = _camera.zoom.x
	_grid.queue_redraw()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message.text = ""
	if _dirty:
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			_save_draft()


# --- Ce qu'on peut faire (aussi utilisé par les tests) ---

## Pose un élément du catalogue (au milieu de la vue si on ne dit pas où) et le choisit.
func add_from_catalog(type: String, where: Variant = null) -> Dictionary:
	_push_undo()
	var pos: Vector2 = where if where != null else _camera.position
	if type == "reapparition":
		for element in data.elements:
			if element.type == "reapparition":  # une seule réapparition : on la déplace
				MapData.set_vec(element, "pos", pos)
				_snap(element)
				_refresh(element)
				select(element.id)
				_juice.pop(element)
				return element
	var element := MapData.add_element(data, type, pos)
	if type == "spawn_joueur":
		element.player = _free_player_number()
	_snap(element)
	_refresh(element)
	select(element.id)
	_juice.pop(element)
	_say("%s ajouté" % MapData.CATALOG[type].label)
	return element


func select(id: int) -> void:
	selected_id = id
	_show_props()
	_overlay.queue_redraw()


func selected() -> Dictionary:
	for element in data.elements:
		if element.id == selected_id:
			return element
	return {}


func delete_selected() -> void:
	var element := selected()
	if element.is_empty():
		return
	_push_undo()
	_juice.puff(element)
	data.elements.erase(element)
	if _nodes.has(element.id):
		_nodes[element.id].queue_free()
		_nodes.erase(element.id)
	select(-1)


func copy_selected() -> void:
	var element := selected()
	if not element.is_empty():
		_clipboard = element.duplicate(true)
		_say("Copié")


## Colle l'élément copié (à cet endroit, ou un cran à côté de l'original).
func paste(where: Variant = null) -> Dictionary:
	if _clipboard.is_empty():
		return {}
	_push_undo()
	var element := _clipboard.duplicate(true)
	element.id = MapData.next_id(data)
	if element.type == "spawn_joueur":
		element.player = _free_player_number()
	var pos: Vector2 = where if where != null else MapData.vec(element, "pos") + Vector2(grid_size, grid_size)
	MapData.set_vec(element, "pos", pos)
	data.elements.append(element)
	_snap(element)
	_refresh(element)
	select(element.id)
	_juice.pop(element)
	return element


func duplicate_selected() -> void:
	copy_selected()
	paste()


func move_selected(pos: Vector2) -> void:
	var element := selected()
	if element.is_empty():
		return
	MapData.set_vec(element, "pos", pos)
	_snap(element)
	_refresh(element)


func rotate_selected(degrees: float) -> void:
	var element := selected()
	if element.is_empty() or not MapData.CATALOG[element.type].rotatable:
		return
	_push_undo()
	element.rot = fposmod(float(element.get("rot", 0.0)) + degrees, 360.0)
	_refresh(element)
	_juice.bump(element)
	_show_props()


## Manette : stick droit. Agrandit (+1) ou rétrécit (-1) d'un cran : à droite plus large, en haut
## plus haut (le coin en bas à gauche ne bouge pas). Une liane : vers le bas, plus longue.
func grow_selected(dx: int, dy: int) -> void:
	var element := selected()
	if element.is_empty() or (dx == 0 and dy == 0):
		return
	var step := float(grid_size) if snap_on else 4.0
	var smallest := step if snap_on else MIN_SIZE
	if element.type == "liane":
		if dy == 0:
			return
		_push_undo()
		element.length = maxf(float(element.length) - dy * step, 40.0)
	elif element.has("size"):
		_push_undo()
		var angle := MapData.rotation(element)
		var size := MapData.vec(element, "size")
		var new_size := Vector2(maxf(size.x + dx * step, smallest), maxf(size.y + dy * step, smallest))
		var corner := Vector2(-size.x / 2.0, size.y / 2.0)
		var middle := corner + Vector2(new_size.x / 2.0, -new_size.y / 2.0)
		MapData.set_vec(element, "pos", MapData.vec(element, "pos") + middle.rotated(angle))
		MapData.set_vec(element, "size", new_size)
	else:
		return
	_refresh(element)
	_juice.bump(element)
	_show_props()


## Manette : LB / RB. Tourne l'élément de 15°, ou change la direction d'une plateforme mobile de 30°.
func turn_selected(direction: int) -> void:
	var element := selected()
	if element.is_empty():
		return
	if MapData.CATALOG[element.type].rotatable:
		rotate_selected(ROTATE_STEP * direction)
	elif element.type == "mobile":
		_push_undo()
		var travel := MapData.vec(element, "travel").rotated(deg_to_rad(30.0 * direction))
		element.travel = [snappedf(travel.x, 0.01), snappedf(travel.y, 0.01)]
		_refresh(element)
		_juice.bump(element)
		_show_props()


func set_grid(on: bool) -> void:
	_grid_check.button_pressed = on


func set_grid_size(value: int) -> void:
	_grid_spin.value = value


func set_snap(on: bool) -> void:
	_snap_check.button_pressed = on


func map_name() -> String:
	return _name_edit.text.strip_edges()


func set_map_name(value: String) -> void:
	_name_edit.text = value
	data.name = value if value.strip_edges() != "" else "Ma map"


func set_help(text: String) -> void:
	if _help != null:
		_help.text = text


func say(text: String) -> void:
	_say(text)


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(MapData.to_json(data))
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(MapData.to_json(data))
	_restore(_redo.pop_back())


func new_map() -> void:
	_push_undo()
	data = MapData.new_map()
	_rebuild_all()
	_camera.position = Vector2(640, 360)
	_say("Nouvelle map (Ctrl+Z pour revenir à l'ancienne)")


func save_map() -> bool:
	data.name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Ma map"
	var ok := MapData.save(data)
	_save_draft()
	_say("Sauvée : %s (on la retrouve dans JOUER > choix de la map)" % data.name if ok else "Impossible de sauver")
	if ok:
		_juice.toast("Sauvée !")
	return ok


func open_map(map_name: String) -> void:
	var loaded := MapData.load_saved(map_name)
	if loaded.is_empty():
		_say("Map introuvable")
		return
	_push_undo()
	data = loaded
	_rebuild_all()
	var area := MapData.bounds(data)
	_camera.position = area.get_center()
	_say("Ouverte : %s" % data.name)


## Lance une partie à 2 joueurs sur la map (clavier gauche + manette 1, clavier droit + manette 2).
func test_map() -> bool:
	var floors: Array = data.elements.filter(func(e: Dictionary) -> bool: return e.type in ["sol", "plateforme", "mobile"])
	if floors.is_empty():
		_say("Ajoute au moins un sol ou une plateforme avant de tester")
		return false
	data.name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Ma map"
	_save_draft()
	GameSetup.editor_map = data.duplicate(true)
	GameSetup.map_path = GameSetup.EDITOR_MAP
	GameSetup.return_scene = EDITOR_SCENE
	GameSetup.player_devices = []
	GameSetup.player_characters = []
	GameSetup.player_weapons = []
	if change_scene:
		get_tree().change_scene_to_file(GAME_SCENE)
	return true


func quit_editor() -> void:
	_save_draft()
	GameSetup.editor_map = data.duplicate(true)
	if change_scene:
		get_tree().change_scene_to_file(GameSetup.MENU_SCENE)


# --- Souris et clavier sur la map ---

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey) and _pad.active:
		_pad.set_active(false)  # retour à la souris et au clavier
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_mouse_motion(event)
	elif event is InputEventKey and event.pressed:
		_key(event)


func _mouse_button(event: InputEventMouseButton) -> void:
	var world := screen_to_world(event.position)
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		_zoom_at(event.position, 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
		return
	if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_drag = "pan" if event.pressed else ""
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if _drag != "" and _drag_changed:
			_show_props()
		if _drag == "move":
			_juice.land(selected(), _drag_changed)
		_drag = ""
		return
	get_viewport().gui_release_focus()
	_drag_changed = false
	var element := selected()
	if not element.is_empty():
		var handle := _handle_at(element, world)
		if handle != "":
			_start_handle_drag(element, handle)
			return
	var picked := _pick(world)
	if picked.is_empty():
		select(-1)
		return
	select(picked.id)
	_drag = "move"
	_drag_offset = world - MapData.vec(picked, "pos")
	_juice.lift(picked.id)


func _mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag == "":
		return
	if _drag == "pan":
		_camera.position -= event.relative / _camera.zoom.x
		return
	var element := selected()
	if element.is_empty():
		return
	if not _drag_changed:
		_push_undo()
		_drag_changed = true
	var world := screen_to_world(event.position)
	match _drag:
		"move":
			move_selected(world - _drag_offset)
		"resize":
			_resize(element, world)
		"travel":
			var travel := world - MapData.vec(element, "pos")
			if snap_on:
				travel = travel.snapped(Vector2(grid_size, grid_size))
			MapData.set_vec(element, "travel", travel)
			_refresh(element)
		"length":
			var length := world.y - MapData.vec(element, "pos").y
			if snap_on:
				length = snappedf(length, grid_size)
			element.length = maxf(length, 40.0)
			_refresh(element)


func _key(event: InputEventKey) -> void:
	var ctrl := event.ctrl_pressed or event.meta_pressed
	match event.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			delete_selected()
		KEY_ESCAPE:
			select(-1)
		KEY_R:
			rotate_selected(-ROTATE_STEP if event.shift_pressed else ROTATE_STEP)
		KEY_G:
			_grid_check.button_pressed = not grid_on
		KEY_C:
			if ctrl:
				copy_selected()
		KEY_V:
			if ctrl:
				paste(screen_to_world(get_viewport().get_mouse_position()))
		KEY_D:
			if ctrl:
				duplicate_selected()
		KEY_Z:
			if ctrl:
				if event.shift_pressed:
					redo()
				else:
					undo()
		KEY_Y:
			if ctrl:
				redo()
		KEY_S:
			if ctrl:
				save_map()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			_nudge(event.keycode, event.shift_pressed)
		_:
			return
	get_viewport().set_input_as_handled()


func _nudge(key: Key, fine: bool) -> void:
	var element := selected()
	if element.is_empty():
		return
	var step := 1.0 if fine or not snap_on else float(grid_size)
	var dir := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[key] as Vector2
	_push_undo()
	MapData.set_vec(element, "pos", MapData.vec(element, "pos") + dir * step)
	if not fine:
		_snap(element)
	_refresh(element)
	_show_props()


## Où tombe ce point de l'écran dans la map.
func screen_to_world(screen: Vector2) -> Vector2:
	return _camera.position + (screen - get_viewport_rect().size / 2.0) / _camera.zoom.x


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := screen_to_world(screen)
	var zoom := clampf(_camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position += before - screen_to_world(screen)


## L'élément sous la souris (les points d'apparition d'abord, puis le plus haut dessiné).
func _pick(world: Vector2) -> Dictionary:
	for pass_points in [true, false]:
		for i in range(data.elements.size() - 1, -1, -1):
			var element: Dictionary = data.elements[i]
			if (element.type in MapData.POINT_TYPES) == pass_points and MapData.contains(element, world, 4.0 / _camera.zoom.x):
				return element
	return {}


## Les poignées de l'élément choisi : "resize" (coin), "length" (bas de la liane), "travel" (trajet).
func _handle_at(element: Dictionary, world: Vector2) -> String:
	var reach := (HANDLE + 4.0) / _camera.zoom.x
	for handle in _handles(element):
		if world.distance_to(handle[1]) <= reach:
			return handle[0]
	return ""


func _handles(element: Dictionary) -> Array:
	var list := []
	var pos := MapData.vec(element, "pos")
	if element.type == "liane":
		list.append(["length", pos + Vector2(0.0, float(element.length))])
	elif element.has("size"):
		var half := MapData.vec(element, "size") / 2.0
		list.append(["resize", pos + half.rotated(MapData.rotation(element))])
	if element.type == "mobile":
		list.append(["travel", pos + MapData.vec(element, "travel")])
	return list


func _start_handle_drag(element: Dictionary, handle: String) -> void:
	_drag = handle
	if handle == "resize":
		_drag_center = MapData.vec(element, "pos")
		_drag_anchor = -MapData.vec(element, "size") / 2.0  # le coin opposé ne bouge pas


func _resize(element: Dictionary, world: Vector2) -> void:
	var angle := MapData.rotation(element)
	var corner := world
	if snap_on and is_zero_approx(angle):
		corner = world.snapped(Vector2(grid_size, grid_size))
	var local := (corner - _drag_center).rotated(-angle)
	var size := (local - _drag_anchor).abs().max(Vector2(MIN_SIZE, MIN_SIZE))
	var middle := _drag_anchor + (local - _drag_anchor).sign() * size / 2.0
	MapData.set_vec(element, "size", size)
	MapData.set_vec(element, "pos", _drag_center + middle.rotated(angle))
	_refresh(element)


## Colle l'élément à la grille (son coin en haut à gauche s'il a une taille, sinon son point).
func _snap(element: Dictionary) -> void:
	if not snap_on:
		return
	var step := Vector2(grid_size, grid_size)
	var pos := MapData.vec(element, "pos")
	if element.has("size") and is_zero_approx(MapData.rotation(element)):
		var half := MapData.vec(element, "size") / 2.0
		pos = (pos - half).snapped(step) + half
	else:
		pos = pos.snapped(step)
	MapData.set_vec(element, "pos", pos)


func _free_player_number() -> int:
	var used := []
	for element in data.elements:
		if element.type == "spawn_joueur":
			used.append(int(element.player))
	for n in range(1, 5):
		if not n in used:
			return n
	return 1


# --- Aperçu de la map ---

func _rebuild_all() -> void:
	if _juice != null:
		_juice.reset()
	for node in _nodes.values():
		_preview.remove_child(node)
		node.queue_free()
	_nodes.clear()
	for element in data.elements:
		_refresh(element, false)
	if _name_edit != null:
		_name_edit.text = str(data.name)
	select(-1)


## Refait l'aperçu d'un élément après un changement.
func _refresh(element: Dictionary, changed := true) -> void:
	var old: Node2D = null
	if _nodes.has(element.id):
		old = _nodes[element.id]
		_preview.remove_child(old)
		old.queue_free()
		_nodes.erase(element.id)
	if not element.type in MapData.POINT_TYPES:
		var node := MapBuilder.build_element(element)
		_preview.add_child(node)
		# Garder l'ordre de dessin : les éléments posés après sont dessinés par-dessus.
		var index := 0
		for other in data.elements:
			if other == element:
				break
			if _nodes.has(other.id):
				index += 1
		_preview.move_child(node, index)
		_nodes[element.id] = node
		if old != null and _juice != null:
			_juice.glide(element.id, old)  # il glisse de l'ancienne place à la nouvelle
	if changed:
		_dirty = true
	_overlay.queue_redraw()


func _restore(json: String) -> void:
	var keep := selected_id
	data = MapData.from_json(json)
	_rebuild_all()
	for element in data.elements:
		if element.id == keep:
			select(keep)
	_dirty = true


func _push_undo() -> void:
	_undo.append(MapData.to_json(data))
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func _save_draft() -> void:
	MapData.save(data, MapData.DRAFT_NAME)
	_dirty = false
	_autosave_left = AUTOSAVE_TIME


func _say(text: String) -> void:
	if _message != null:
		_message.text = text
		_message_left = 4.0


# --- Dessins par-dessus la map : grille, points d'apparition, choix ---

func _draw_grid() -> void:
	if not grid_on:
		return
	var view := Rect2(screen_to_world(Vector2.ZERO), get_viewport_rect().size / _camera.zoom.x)
	var step := float(grid_size)
	while step * _camera.zoom.x < 8.0:  # trop serré à l'écran : une ligne sur deux
		step *= 2.0
	var line := Color(1, 1, 1, 0.07)
	var width := 1.0 / _camera.zoom.x
	var x := floorf(view.position.x / step) * step
	while x <= view.end.x:
		_grid.draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), line, width)
		x += step
	var y := floorf(view.position.y / step) * step
	while y <= view.end.y:
		_grid.draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), line, width)
		y += step


func _draw_overlay() -> void:
	var px := 1.0 / _camera.zoom.x  # un pixel de l'écran, dans la map
	var font := ThemeDB.fallback_font
	for element in data.elements:
		var pos := MapData.vec(element, "pos")
		match element.type:
			"spawn_joueur":
				var color: Color = PLAYER_COLORS[(int(element.player) - 1) % 4]
				_overlay.draw_rect(Rect2(pos - Vector2(12, 52), Vector2(24, 52)), Color(color, 0.7))
				_overlay.draw_string(font, pos + Vector2(-14, -60), "J%d" % int(element.player),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
			"reapparition":
				_overlay.draw_arc(pos - Vector2(0, MapData.POINT_RADIUS), MapData.POINT_RADIUS, 0.0, TAU, 32, Color.WHITE, 3.0)
				_overlay.draw_string(font, pos + Vector2(-8, -18), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
			"spawn_objet":
				_overlay.draw_rect(Rect2(pos - Vector2(16, 16), Vector2(32, 32)), Color(0.85, 0.65, 0.3), false, 3.0)
				_overlay.draw_string(font, pos + Vector2(-6, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.65, 0.3))
			"mobile":
				var travel := MapData.vec(element, "travel")
				var size := MapData.vec(element, "size")
				_overlay.draw_dashed_line(pos, pos + travel, Color(0.62, 0.55, 0.85, 0.8), 2.0 * px, 12.0 * px)
				_overlay.draw_rect(Rect2(pos + travel - size / 2.0, size), Color(0.62, 0.55, 0.85, 0.5), false, 2.0 * px)
	if _pad != null and _pad.active:
		var hover := _pick(_pad.cursor)
		if not hover.is_empty() and hover.id != selected_id:
			_overlay.draw_set_transform(MapData.center_of(hover), MapData.rotation(hover))
			var hover_half := MapData.size_of(hover) / 2.0
			_overlay.draw_rect(Rect2(-hover_half, hover_half * 2.0).grow(3.0 * px), Color(1, 1, 1, 0.6), false, 2.0 * px)
			_overlay.draw_set_transform(Vector2.ZERO)
		var c := _pad.cursor
		var arm := (14.0 + (4.0 if not hover.is_empty() else 0.0) + 1.5 * sin(_juice.time * 6.0)) * px
		for offset in [Vector2(arm, 0), Vector2(0, arm)]:
			_overlay.draw_line(c - offset, c + offset, Color.BLACK, 6.0 * px)
			_overlay.draw_line(c - offset, c + offset, UiKit.HIGHLIGHT, 3.0 * px)
		_overlay.draw_arc(c, 5.0 * px, 0.0, TAU, 16, UiKit.HIGHLIGHT, 2.0 * px)
	var chosen := selected()
	if chosen.is_empty():
		return
	_overlay.draw_set_transform(MapData.center_of(chosen), MapData.rotation(chosen))
	var half := MapData.size_of(chosen) / 2.0
	_overlay.draw_rect(Rect2(-half, half * 2.0).grow(3.0 * px), UiKit.HIGHLIGHT, false, 2.0 * px)
	_overlay.draw_set_transform(Vector2.ZERO)
	for handle in _handles(chosen):
		var at: Vector2 = handle[1]
		if handle[0] == "travel":
			_overlay.draw_circle(at, HANDLE * px, Color(0.62, 0.55, 0.85))
		else:
			_overlay.draw_rect(Rect2(at - Vector2.ONE * HANDLE * px, Vector2.ONE * HANDLE * 2.0 * px), UiKit.HIGHLIGHT)


# --- Les panneaux ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui = layer
	add_child(layer)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.add_child(_top_bar())
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(middle)
	middle.add_child(_catalog_panel())
	var gap := Control.new()  # la map se voit (et se clique) ici
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(gap)
	var right := _panel(Vector2(260, 0))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_props = VBoxContainer.new()
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_props)
	middle.add_child(right)
	var bottom := _panel(Vector2.ZERO)
	var lines := VBoxContainer.new()
	bottom.add_child(lines)
	_message = Label.new()
	_message.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
	lines.add_child(_message)
	_help = Label.new()
	_help.text = MOUSE_HELP
	_help.add_theme_font_size_override("font_size", 13)
	_help.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_help)
	root.add_child(bottom)


func _panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _top_bar() -> PanelContainer:
	var panel := _panel(Vector2.ZERO)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	panel.add_child(bar)
	bar.add_child(_button("Nouvelle", new_map))
	_open_button = MenuButton.new()
	_open_button.text = "Ouvrir ▾"
	_open_button.flat = false
	_open_button.about_to_popup.connect(_fill_open_menu)
	_open_button.get_popup().index_pressed.connect(func(i: int) -> void:
		open_map(_open_button.get_popup().get_item_metadata(i)))
	bar.add_child(_open_button)
	bar.add_child(_button("Sauver", save_map))
	bar.add_child(VSeparator.new())
	bar.add_child(_text("Nom"))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(170, 0)
	_name_edit.text_submitted.connect(func(_t: String) -> void: get_viewport().gui_release_focus())
	bar.add_child(_name_edit)
	bar.add_child(VSeparator.new())
	_grid_check = CheckButton.new()
	_grid_check.text = "Grille"
	_grid_check.button_pressed = grid_on
	_grid_check.focus_mode = Control.FOCUS_NONE
	_grid_check.toggled.connect(func(on: bool) -> void:
		grid_on = on
		_grid.queue_redraw())
	bar.add_child(_grid_check)
	_grid_spin = _spin(8, 400, 8, grid_size, func(v: float) -> void:
		grid_size = int(v)
		_grid.queue_redraw())
	bar.add_child(_grid_spin)
	_snap_check = CheckButton.new()
	_snap_check.text = "Aimant"
	_snap_check.tooltip_text = "Allumé : tout se colle à la grille. Éteint : placement libre."
	_snap_check.button_pressed = snap_on
	_snap_check.focus_mode = Control.FOCUS_NONE
	_snap_check.toggled.connect(func(on: bool) -> void: snap_on = on)
	bar.add_child(_snap_check)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(push)
	var test := _button("▶ TESTER", test_map)
	test.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
	bar.add_child(test)
	bar.add_child(_button("Quitter", quit_editor))
	return panel


func _fill_open_menu() -> void:
	var popup := _open_button.get_popup()
	popup.clear()
	var names := MapData.list_saved()
	if names.is_empty():
		popup.add_item("(aucune map sauvée)")
		popup.set_item_disabled(0, true)
		return
	for i in names.size():
		popup.add_item(names[i])
		popup.set_item_metadata(i, names[i])


func _catalog_panel() -> PanelContainer:
	var panel := _panel(Vector2(210, 0))
	var list := VBoxContainer.new()
	panel.add_child(list)
	list.add_child(_text("CATALOGUE"))
	for tab in MapData.TABS:
		var title := _text(str(tab).to_upper())
		title.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
		title.add_theme_font_size_override("font_size", 13)
		list.add_child(UiKit.spacer(4))
		list.add_child(title)
		for type in MapData.CATALOG:
			if MapData.CATALOG[type].tab == tab:
				var button := _button(MapData.CATALOG[type].label, add_from_catalog.bind(type))
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				list.add_child(button)
				_catalog_buttons.append(button)
				_catalog_types.append(type)
	return panel


## Les types du catalogue, dans l'ordre affiché (pour la manette).
func catalog_types() -> Array[String]:
	return _catalog_types


## Manette : allume un bouton du catalogue (-1 : aucun).
func highlight_catalog(index: int) -> void:
	for i in _catalog_buttons.size():
		if i == index:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(UiKit.HIGHLIGHT, 0.25)
			style.border_color = UiKit.HIGHLIGHT
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			style.set_content_margin_all(6)
			_catalog_buttons[i].add_theme_stylebox_override("normal", style)
			_catalog_buttons[i].add_theme_color_override("font_color", UiKit.HIGHLIGHT)
		else:
			_catalog_buttons[i].remove_theme_stylebox_override("normal")
			_catalog_buttons[i].remove_theme_color_override("font_color")


## Les réglages de l'élément choisi, en lignes : la souris les voit en cases à chiffres, la manette
## les parcourt (haut / bas) et les change (gauche / droite). Une ligne :
##   kind "number" : value, min, max, step (souris), pad_step (manette), wrap (tourne en rond), set(valeur)
##   kind "choice" : options, index, set(numéro)
##   kind "color"  : value (Color), set(Color)
##   kind "button" : press()
func prop_rows() -> Array[Dictionary]:
	return _prop_rows


func _make_prop_rows(element: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var g := float(grid_size) if snap_on else 4.0
	var pos := MapData.vec(element, "pos")
	rows.append(_num("X", pos.x, -20000, 20000, 1, g, func(v: float) -> void: _set_vec_part(element, "pos", 0, v)))
	rows.append(_num("Y", pos.y, -20000, 20000, 1, g, func(v: float) -> void: _set_vec_part(element, "pos", 1, v)))
	if element.has("size"):
		var size := MapData.vec(element, "size")
		rows.append(_num("Largeur", size.x, MIN_SIZE, 20000, 1, g, func(v: float) -> void: _set_vec_part(element, "size", 0, v)))
		rows.append(_num("Hauteur", size.y, MIN_SIZE, 20000, 1, g, func(v: float) -> void: _set_vec_part(element, "size", 1, v)))
	if MapData.CATALOG[element.type].rotatable:
		var rot := _num("Rotation (°)", float(element.get("rot", 0.0)), 0, 359, 1, ROTATE_STEP,
			func(v: float) -> void: _set_field(element, "rot", v))
		rot.wrap = true
		rows.append(rot)
	match element.type:
		"mobile":
			var travel := MapData.vec(element, "travel")
			var angle := fposmod(rad_to_deg(atan2(-travel.y, travel.x)), 360.0)
			rows.append({"label": "Direction", "kind": "choice", "options": DIRECTION_NAMES, "index": roundi(angle / 30.0) % 12,
				"set": func(i: int) -> void:
					var length := MapData.vec(element, "travel").length()
					var dir := Vector2(cos(deg_to_rad(i * 30.0)), -sin(deg_to_rad(i * 30.0)))
					_set_field(element, "travel", [snappedf(dir.x * length, 0.01), snappedf(dir.y * length, 0.01)])})
			rows.append(_num("Distance", travel.length(), 0, 20000, 1, g, func(v: float) -> void:
				var dir := MapData.vec(element, "travel").normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.RIGHT
				_set_field(element, "travel", [snappedf(dir.x * v, 0.01), snappedf(dir.y * v, 0.01)])))
			rows.append(_num("Aller-retour (s)", float(element.period), 0.2, 120, 0.1, 0.5,
				func(v: float) -> void: _set_field(element, "period", v)))
			rows.append(_num("Arrêt aux bouts (s)", float(element.pause), 0, 30, 0.1, 0.5,
				func(v: float) -> void: _set_field(element, "pause", v)))
		"liane":
			rows.append(_num("Longueur", float(element.length), 40, 3000, 1, g, func(v: float) -> void: _set_field(element, "length", v)))
		"spawn_joueur":
			rows.append(_num("Joueur", int(element.player), 1, 4, 1, 1, func(v: float) -> void: _set_field(element, "player", int(v))))
	if element.has("color"):
		rows.append({"label": "Couleur", "kind": "color", "value": MapData.color(element),
			"set": func(c: Color) -> void: _set_field(element, "color", "#" + c.to_html(false))})
	rows.append({"label": "Dupliquer", "kind": "button", "press": duplicate_selected})
	rows.append({"label": "Supprimer", "kind": "button", "press": delete_selected})
	return rows


func _num(label: String, value: float, min_value: float, max_value: float, step: float, pad_step: float, on_set: Callable) -> Dictionary:
	return {"label": label, "kind": "number", "value": value, "min": min_value, "max": max_value,
		"step": step, "pad_step": pad_step, "wrap": false, "set": on_set}


## Manette : gauche (-1) / droite (+1) sur une ligne de réglage.
static func change_row(row: Dictionary, direction: int) -> void:
	match row.kind:
		"number":
			var value: float = row.value + direction * row.pad_step
			if row.wrap:
				value = fposmod(value, row.max + 1.0)
			row.set.call(clampf(value, row.min, row.max))
		"choice":
			row.set.call(posmod(int(row.index) + direction, row.options.size()))
		"color":
			var i := COLOR_PRESETS.find("#" + (row.value as Color).to_html(false))
			row.set.call(Color.from_string(COLOR_PRESETS[posmod(i + direction, COLOR_PRESETS.size())], Color.WHITE))


## Manette : A sur une ligne de réglage (un bouton : on appuie ; un choix, une couleur : la suivante).
static func activate_row(row: Dictionary) -> void:
	match row.kind:
		"button":
			row.press.call()
		"choice", "color":
			change_row(row, 1)


## Les réglages de l'élément choisi.
func _show_props() -> void:
	if _props == null:
		return
	for child in _props.get_children():
		_props.remove_child(child)
		child.queue_free()
	_prop_boxes.clear()
	var element := selected()
	if element.is_empty():
		_prop_rows = []
		_props.add_child(_text("RÉGLAGES"))
		var hint := _text("Choisis un élément de la map pour le régler, ou pose-en un depuis le catalogue (à gauche).")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", UiKit.TEXT_DIM)
		_props.add_child(hint)
		_props.add_child(_text("%d éléments" % data.elements.size()))
		return
	_props.add_child(_text(str(MapData.CATALOG[element.type].label).to_upper()))
	_prop_rows = _make_prop_rows(element)
	for row in _prop_rows:
		var box := PanelContainer.new()
		var line := HBoxContainer.new()
		box.add_child(line)
		if row.kind != "button":
			var label := _text(row.label)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(label)
		match row.kind:
			"number":
				line.add_child(_spin(row.min, row.max, row.step, row.value, row.set))
			"choice":
				var options := OptionButton.new()
				options.focus_mode = Control.FOCUS_NONE
				for option in row.options:
					options.add_item(option)
				options.select(row.index)
				options.item_selected.connect(row.set)
				line.add_child(options)
			"color":
				var picker := ColorPickerButton.new()
				picker.color = row.value
				picker.edit_alpha = false
				picker.focus_mode = Control.FOCUS_NONE
				picker.custom_minimum_size = Vector2(80, 28)
				picker.color_changed.connect(row.set)
				line.add_child(picker)
			"button":
				var button := _button(row.label, row.press)
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				line.add_child(button)
		_props.add_child(box)
		_prop_boxes.append(box)
	if element.type == "mobile":
		var hint := _text("Ou tire le rond violet sur la map.")
		hint.add_theme_color_override("font_color", UiKit.TEXT_DIM)
		_props.add_child(hint)
	highlight_prop(_prop_highlight)


## Manette : allume une ligne des réglages (-1 : aucune).
func highlight_prop(index: int) -> void:
	_prop_highlight = index
	for i in _prop_boxes.size():
		var style := StyleBoxFlat.new()
		style.set_content_margin_all(2)
		style.bg_color = Color(UiKit.HIGHLIGHT, 0.22) if i == index else Color(0, 0, 0, 0)
		style.border_color = UiKit.HIGHLIGHT
		style.set_border_width_all(2 if i == index else 0)
		_prop_boxes[i].add_theme_stylebox_override("panel", style)


func _set_field(element: Dictionary, key: String, value: Variant) -> void:
	_push_undo()
	element[key] = value
	_refresh(element)


func _set_vec_part(element: Dictionary, key: String, axis: int, value: float) -> void:
	var v := MapData.vec(element, key)
	v[axis] = value
	_push_undo()
	MapData.set_vec(element, key, v)
	_refresh(element)


func _spin(min_value: float, max_value: float, step: float, value: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(96, 0)
	spin.value_changed.connect(on_change)
	return spin


func _button(text: String, on_click: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_click)
	return button


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
