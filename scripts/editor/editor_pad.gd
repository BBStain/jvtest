class_name EditorPad
extends Node
## La manette dans l'éditeur de map. Tout se fait avec un curseur (la croix jaune) :
##
##   stick gauche      : bouger le curseur (la vue suit)        croix : bouger d'un cran de grille
##   A (maintenu)      : prendre l'élément sous le curseur et le déplacer ; A sur du vide : lâcher le choix
##   X                 : le catalogue (haut / bas, A pose l'élément au curseur)
##   Y                 : les réglages de l'élément choisi (haut / bas, gauche / droite pour changer)
##   stick droit       : taille de l'élément choisi (droite = plus large, haut = plus haut) ;
##                       sans élément choisi, il bouge la vue
##   LB / RB           : tourner (ou changer la direction d'un élément qui bouge sans tourner)
##   LT / RT           : zoom          R3 (cliquer le stick droit) : dupliquer
##   B                 : annuler le déplacement en cours, sinon lâcher le choix, sinon fermer le panneau
##   Start             : le menu (tester, sauver, nom, ouvrir, nouvelle map, annuler, voir bouger, grille,
##                       aimant, quitter)
## Pour attacher un élément à un autre : Y (réglages) > « Attacher à... », puis A sur l'autre élément.
##   Select / View     : tester la map tout de suite
## Dès qu'on touche la souris ou le clavier, le curseur disparaît (et revient à la manette).

enum Focus { MAP, CATALOG, PROPS, MENU, OPEN, KEYBOARD }

const DEADZONE := 0.2
const CURSOR_SPEED := 900.0       ## pixels de l'écran par seconde, stick à fond
const PAN_SPEED := 1000.0         ## stick droit sans rien de choisi : la vue bouge
const ZOOM_SPEED := 2.2           ## gâchette à fond : zoom x2,2 par seconde
const REPEAT_DELAY := 0.3         ## croix / stick maintenus : ça se répète après ce temps...
const REPEAT_RATE := 0.08         ## ...puis à ce rythme
const RESIZE_DELAY := 0.25
const RESIZE_RATE := 0.07
const VIEW_MARGIN := Rect2(270, 110, 330, 140)  ## le curseur reste dans la zone de la map (gauche, haut, droite, bas)
const BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
	JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_RIGHT_STICK]
const KEY_ROWS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ-_!?", "0123456789", "⎵⌫✓"]
const MAX_NAME := 24
const MAX_PADS := 8               ## on écoute les manettes 0 à 7

const HELP := {
	Focus.MAP: "MANETTE   stick G : curseur   ·   croix : un cran   ·   A (maintenu) : prendre et déplacer   ·   X : catalogue   ·   Y : réglages   ·   stick D : taille   ·   LB / RB : tourner   ·   LT / RT : zoom   ·   R3 : dupliquer   ·   B : lâcher   ·   Start : menu   ·   Select : tester",
	Focus.CATALOG: "CATALOGUE   haut / bas : choisir   ·   A : poser au curseur   ·   B : fermer",
	Focus.PROPS: "RÉGLAGES   haut / bas : choisir   ·   gauche / droite : changer   ·   A : appuyer   ·   B : fermer",
	Focus.MENU: "MENU   haut / bas : choisir   ·   gauche / droite : changer   ·   A : valider   ·   B ou Start : fermer",
	Focus.OPEN: "OUVRIR   haut / bas : choisir   ·   A : ouvrir   ·   B : retour",
	Focus.KEYBOARD: "NOM   croix ou stick : choisir une lettre   ·   A : écrire   ·   X : effacer   ·   Start : valider   ·   B : annuler",
}

var editor: MapEditor
var active := false                ## la manette a servi en dernier : le curseur est affiché
var focus := Focus.MAP
var cursor := Vector2(640, 360)    ## dans la map
var index := 0                     ## la ligne allumée du panneau ouvert
var dragging := false

var _held := {}                    ## bouton -> appuyé à la frame d'avant
var _first_frame := true
var _repeat_dir := Vector2i.ZERO
var _repeat_left := 0.0
var _resize_dir := Vector2i.ZERO
var _resize_left := 0.0
var _drag_offset := Vector2.ZERO
var _drag_moved := false
var _catalog_index := 0
var _rows: Array[Dictionary] = []  ## les lignes du menu ou de la liste « ouvrir »
var _panel: PanelContainer         ## le panneau du milieu (menu, ouvrir, clavier)
var _box: VBoxContainer
var _key := Vector2i.ZERO          ## la lettre allumée du clavier
var _typed := ""


func _ready() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.97)
	style.border_color = UiKit.HIGHLIGHT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	editor._ui.add_child(_panel)


# --- Lecture de la manette (toutes les manettes branchées comptent) ---

func _process(delta: float) -> void:
	var pressed := {}
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	var zoom := 0.0
	var dpad := Vector2i.ZERO
	for device in MAX_PADS:
		for button in BUTTONS:
			if Input.is_joy_button_pressed(device, button):
				pressed[button] = true
		dpad.x += int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT)) - int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT))
		dpad.y += int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)) - int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP))
		var l := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		var r := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if l.length() > left.length():
			left = l
		if r.length() > right.length():
			right = r
		zoom += Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	if _first_frame:  # le A qui a ouvert l'éditeur depuis le menu ne compte pas
		_first_frame = false
		_held = pressed
		return
	for button in BUTTONS:
		if pressed.get(button, false) and not _held.get(button, false):
			press(button)
		elif _held.get(button, false) and not pressed.get(button, false):
			release(button)
	_held = pressed
	tick(delta, left, right, clampf(zoom, -1.0, 1.0), dpad.clamp(Vector2i(-1, -1), Vector2i(1, 1)))


## Un bouton vient d'être appuyé.
func press(button: int) -> void:
	set_active(true)
	match focus:
		Focus.MAP:
			_press_map(button)
		Focus.CATALOG:
			match button:
				JOY_BUTTON_A:
					var types := editor.catalog_types()
					_close()
					editor.add_from_catalog(types[_catalog_index], cursor)
				JOY_BUTTON_B, JOY_BUTTON_X:
					_close()
				JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
					_jump_family(-1 if button == JOY_BUTTON_LEFT_SHOULDER else 1)
		Focus.PROPS:
			match button:
				JOY_BUTTON_A:
					var rows := editor.prop_rows()
					if index < rows.size():
						MapEditor.activate_row(rows[index])
					if editor.attach_picking:  # « Attacher à... » : on va montrer l'autre élément sur la map
						var help := MapEditor.ATTACH_HELP
						_close()
						editor.set_help(help)
						return
					_after_props_change()
				JOY_BUTTON_B, JOY_BUTTON_Y:
					_close()
		Focus.MENU, Focus.OPEN:
			match button:
				JOY_BUTTON_A:
					if index < _rows.size():
						MapEditor.activate_row(_rows[index])
						if focus == Focus.MENU and _panel.visible:
							_open_menu(index)
				JOY_BUTTON_B:
					if focus == Focus.OPEN:
						_open_menu(4)
					else:
						_close()
				JOY_BUTTON_START:
					_close()
		Focus.KEYBOARD:
			match button:
				JOY_BUTTON_A:
					_type_key()
				JOY_BUTTON_X:
					_typed = _typed.left(-1)
					_show_keyboard()
				JOY_BUTTON_START:
					_name_done()
				JOY_BUTTON_B:
					_open_menu(3)


func release(button: int) -> void:
	if button == JOY_BUTTON_A and dragging:
		dragging = false
		editor._juice.land(editor.selected(), _drag_moved)
		if _drag_moved:
			editor._show_props()


func _press_map(button: int) -> void:
	if editor.attach_picking:  # on montre l'élément auquel attacher le choix
		if button == JOY_BUTTON_A:
			editor.finish_attach_pick(cursor)
		elif button == JOY_BUTTON_B:
			editor.finish_attach_pick(null)
		return
	match button:
		JOY_BUTTON_A:
			var picked := editor._pick(cursor)
			if picked.is_empty():
				editor.select(-1)
				return
			editor.select(picked.id)
			dragging = true
			_drag_moved = false
			_drag_offset = cursor - MapData.vec(picked, "pos")
			editor._juice.lift(picked.id)
		JOY_BUTTON_B:
			if dragging:
				dragging = false
				editor._juice.land({}, false)
				if _drag_moved:
					editor.undo()  # l'élément revient où il était
			else:
				editor.select(-1)
		JOY_BUTTON_X:
			_set_focus(Focus.CATALOG)
			editor.highlight_catalog(_catalog_index)
		JOY_BUTTON_Y:
			if editor.selected().is_empty():
				editor.say("Choisis d'abord un élément : mets le curseur dessus et appuie sur A")
				return
			index = 0
			_set_focus(Focus.PROPS)
			editor.highlight_prop(index)
		JOY_BUTTON_LEFT_SHOULDER:
			editor.turn_selected(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			editor.turn_selected(1)
		JOY_BUTTON_RIGHT_STICK:
			editor.duplicate_selected()
		JOY_BUTTON_START:
			_open_menu(0)
		JOY_BUTTON_BACK:
			editor.test_map()


## Ce qui bouge tout le temps : sticks, gâchettes, croix maintenue.
func tick(delta: float, left: Vector2, right: Vector2, zoom: float, dpad: Vector2i) -> void:
	if left.length() < DEADZONE:
		left = Vector2.ZERO
	if right.length() < DEADZONE:
		right = Vector2.ZERO
	if absf(zoom) < DEADZONE:
		zoom = 0.0
	if left != Vector2.ZERO or right != Vector2.ZERO or zoom != 0.0 or dpad != Vector2i.ZERO:
		set_active(true)
	if not active:
		return
	# Croix (et stick gauche dans les panneaux) : un cran, qui se répète si on garde appuyé.
	var dir := dpad
	if focus != Focus.MAP and dir == Vector2i.ZERO:
		dir = _stick_dir(left, 0.6)
	if dir != _repeat_dir:
		_repeat_dir = dir
		_repeat_left = REPEAT_DELAY
		if dir != Vector2i.ZERO:
			nav(dir)
	elif dir != Vector2i.ZERO:
		_repeat_left -= delta
		if _repeat_left <= 0.0:
			_repeat_left = REPEAT_RATE
			nav(dir)
	if focus != Focus.MAP:
		return
	var zoom_level := editor._camera.zoom.x
	if left != Vector2.ZERO:
		# Doux au milieu du stick (précis), rapide à fond.
		cursor += left * left.length() * CURSOR_SPEED * delta / zoom_level
		_follow_drag()
	if not editor.selected().is_empty():
		var grow := _stick_dir(right, 0.5)
		grow.y = -grow.y  # stick vers le haut = plus haut
		if grow != _resize_dir:
			_resize_dir = grow
			_resize_left = RESIZE_DELAY
			editor.grow_selected(grow.x, grow.y)
		elif grow != Vector2i.ZERO:
			_resize_left -= delta
			if _resize_left <= 0.0:
				_resize_left = RESIZE_RATE
				editor.grow_selected(grow.x, grow.y)
	elif right != Vector2.ZERO:
		var pan := right * PAN_SPEED * delta / zoom_level
		editor._camera.position += pan
		cursor += pan
	if zoom != 0.0:
		editor._zoom_at(_cursor_on_screen(), pow(ZOOM_SPEED, zoom * delta))
	_keep_cursor_in_view()
	editor._overlay.queue_redraw()


## Un cran de croix (ou de stick dans un panneau).
func nav(dir: Vector2i) -> void:
	match focus:
		Focus.MAP:
			var step := float(editor.grid_size) if editor.snap_on else 4.0
			if editor.snap_on:
				cursor = cursor.snapped(Vector2(step, step))
			cursor += Vector2(dir) * step
			_follow_drag()
			_keep_cursor_in_view()
			editor._overlay.queue_redraw()
		Focus.CATALOG:
			if dir.y != 0:
				_catalog_index = posmod(_catalog_index + dir.y, editor.catalog_types().size())
				editor.highlight_catalog(_catalog_index)
		Focus.PROPS:
			var rows := editor.prop_rows()
			if dir.y != 0 and not rows.is_empty():
				index = posmod(index + dir.y, rows.size())
				editor.highlight_prop(index)
			elif dir.x != 0 and index < rows.size():
				MapEditor.change_row(rows[index], dir.x)
				_after_props_change()
		Focus.MENU, Focus.OPEN:
			if dir.y != 0 and not _rows.is_empty():
				index = posmod(index + dir.y, _rows.size())
				_show_rows()
			elif dir.x != 0 and index < _rows.size() and _rows[index].kind != "button":
				MapEditor.change_row(_rows[index], dir.x)
				_open_menu(index)
		Focus.KEYBOARD:
			_key.y = posmod(_key.y + dir.y, KEY_ROWS.size())
			_key.x = posmod(_key.x + dir.x, KEY_ROWS[_key.y].length()) if dir.x != 0 else mini(_key.x, KEY_ROWS[_key.y].length() - 1)
			_show_keyboard()


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		cursor = editor._camera.position
	else:
		dragging = false
		_close()
	editor.set_help(HELP[focus] if on else MapEditor.MOUSE_HELP)
	editor._overlay.queue_redraw()


func _set_focus(value: Focus) -> void:
	focus = value
	editor.set_help(HELP[focus])


func _close() -> void:
	focus = Focus.MAP
	_panel.visible = false
	editor.highlight_catalog(-1)
	editor.highlight_prop(-1)
	if active:
		editor.set_help(HELP[focus])


func _stick_dir(stick: Vector2, threshold: float) -> Vector2i:
	var dir := Vector2i.ZERO
	if absf(stick.x) > threshold and absf(stick.x) >= absf(stick.y):
		dir.x = 1 if stick.x > 0.0 else -1
	elif absf(stick.y) > threshold:
		dir.y = 1 if stick.y > 0.0 else -1
	return dir


func _follow_drag() -> void:
	if not dragging:
		return
	if not _drag_moved:
		editor._push_undo()
		_drag_moved = true
	editor.move_selected(cursor - _drag_offset)


func _cursor_on_screen() -> Vector2:
	return (cursor - editor._camera.position) * editor._camera.zoom.x + editor.get_viewport_rect().size / 2.0


## La vue suit le curseur quand il arrive au bord de la zone de la map.
func _keep_cursor_in_view() -> void:
	var view := editor.get_viewport_rect().size
	var area := Rect2(VIEW_MARGIN.position, view - VIEW_MARGIN.position - VIEW_MARGIN.size)
	var screen := _cursor_on_screen()
	var inside := screen.clamp(area.position, area.end)
	if inside != screen:
		editor._camera.position += (screen - inside) / editor._camera.zoom.x


func _jump_family(direction: int) -> void:
	var types := editor.catalog_types()
	var family: String = MapData.CATALOG[types[_catalog_index]].tab
	var i := _catalog_index
	for n in types.size():
		i = posmod(i + direction, types.size())
		if MapData.CATALOG[types[i]].tab != family:
			break
	if direction < 0:  # au début de la famille
		var start_family: String = MapData.CATALOG[types[i]].tab
		while i > 0 and MapData.CATALOG[types[i - 1]].tab == start_family:
			i -= 1
	_catalog_index = i
	editor.highlight_catalog(_catalog_index)


func _after_props_change() -> void:
	if editor.selected().is_empty():  # « Supprimer »
		_close()
		return
	editor._show_props()  # les lignes reprennent les nouvelles valeurs (pour le cran suivant)
	index = mini(index, editor.prop_rows().size() - 1)
	editor.highlight_prop(index)


# --- Le menu (Start), la liste des maps à ouvrir, le clavier pour le nom ---

func _open_menu(at := 0) -> void:
	_set_focus(Focus.MENU)
	var name_text := editor.map_name() if editor.map_name() != "" else "Ma map"
	_rows = [
		{"label": "Reprendre", "kind": "button", "press": _close},
		{"label": "Tester la map", "kind": "button", "press": func() -> void:
			_close()
			editor.test_map()},
		{"label": "Sauver", "kind": "button", "press": func() -> void:
			_close()
			editor.save_map()},
		{"label": "Nom : " + name_text, "kind": "button", "press": _open_keyboard},
		{"label": "Ouvrir une map", "kind": "button", "press": _open_list},
		{"label": "Nouvelle map", "kind": "button", "press": func() -> void:
			_close()
			editor.new_map()},
		{"label": "Annuler", "kind": "button", "press": editor.undo},
		{"label": "Refaire", "kind": "button", "press": editor.redo},
		{"label": "Voir bouger", "kind": "choice", "options": ["non", "oui"], "index": int(editor.playing),
			"set": func(i: int) -> void: editor.set_playing(i == 1)},
		{"label": "Grille", "kind": "choice", "options": ["non", "oui"], "index": int(editor.grid_on),
			"set": func(i: int) -> void: editor.set_grid(i == 1)},
		{"label": "Taille de la grille", "kind": "number", "value": float(editor.grid_size), "min": 8.0, "max": 400.0,
			"pad_step": 8.0, "wrap": false, "set": func(v: float) -> void: editor.set_grid_size(int(v))},
		{"label": "Aimant (coller à la grille)", "kind": "choice", "options": ["non", "oui"], "index": int(editor.snap_on),
			"set": func(i: int) -> void: editor.set_snap(i == 1)},
		{"label": "Quitter l'éditeur", "kind": "button", "press": func() -> void:
			_close()
			editor.quit_editor()},
	]
	index = clampi(at, 0, _rows.size() - 1)
	_show_rows("MENU")


func _open_list() -> void:
	_set_focus(Focus.OPEN)
	_rows = []
	for saved in MapData.list_saved():
		_rows.append({"label": saved, "kind": "button", "press": func() -> void:
			_close()
			editor.open_map(saved)})
	_rows.append({"label": "← Retour", "kind": "button", "press": _open_menu.bind(4)})
	index = 0
	_show_rows("OUVRIR UNE MAP")


func _show_rows(title := "") -> void:
	_clear_panel()
	if title == "":
		title = "MENU" if focus == Focus.MENU else "OUVRIR UNE MAP"
	_box.add_child(UiKit.label(title, 26, UiKit.HIGHLIGHT))
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var text: String = row.label
		match row.kind:
			"choice":
				text += "   <  %s  >" % row.options[row.index]
			"number":
				text += "   <  %d  >" % int(row.value)
		var on := i == index
		var label := UiKit.label(("▶  " if on else "    ") + text, 20, UiKit.HIGHLIGHT if on else Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_box.add_child(label)
	_panel.visible = true
	_panel.reset_size()


func _open_keyboard() -> void:
	_set_focus(Focus.KEYBOARD)
	_typed = editor.map_name()
	_key = Vector2i.ZERO
	_show_keyboard()


func _show_keyboard() -> void:
	_clear_panel()
	_box.add_child(UiKit.label("NOM DE LA MAP", 26, UiKit.HIGHLIGHT))
	_box.add_child(UiKit.label(_typed + "_", 30))
	for y in KEY_ROWS.size():
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 4)
		var keys: String = KEY_ROWS[y]
		for x in keys.length():
			var on := Vector2i(x, y) == _key
			var key := UiKit.label(_key_name(keys[x]), 22, UiKit.HIGHLIGHT if on else Color.WHITE)
			key.custom_minimum_size = Vector2(110 if keys.length() <= 3 else 38, 38)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(UiKit.HIGHLIGHT, 0.25) if on else Color(1, 1, 1, 0.06)
			style.set_corner_radius_all(4)
			key.add_theme_stylebox_override("normal", style)
			line.add_child(key)
		_box.add_child(line)
	_panel.visible = true
	_panel.reset_size()


func _key_name(key: String) -> String:
	match key:
		"⎵":
			return "espace"
		"⌫":
			return "effacer"
		"✓":
			return "OK"
	return key


func _type_key() -> void:
	var key: String = KEY_ROWS[_key.y][_key.x]
	match key:
		"⌫":
			_typed = _typed.left(-1)
		"✓":
			_name_done()
			return
		"⎵":
			if _typed.length() < MAX_NAME:
				_typed += " "
		_:
			if _typed.length() < MAX_NAME:
				_typed += key
	_show_keyboard()


func _name_done() -> void:
	editor.set_map_name(_typed.strip_edges())
	_open_menu(3)


func _clear_panel() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
