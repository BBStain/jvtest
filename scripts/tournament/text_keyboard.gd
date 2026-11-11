class_name TextKeyboard
extends RefCounted
## Taper un nom : au clavier on tape directement (Entrée pour valider, Échap pour annuler) ;
## à la manette, un clavier à l'écran : stick / croix pour choisir une touche, A pour l'appuyer,
## B pour annuler.

const ROWS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ-_.!", "0123456789", "⎵⌫✓"]

var title := ""
var text := ""
var max_length := 14
var done := false        ## validé (✓ ou Entrée)
var cancelled := false   ## annulé (B ou Échap)
var _key := Vector2i.ZERO


func _init(keyboard_title: String, start_text: String, length: int) -> void:
	title = keyboard_title
	text = start_text
	max_length = length


## Une touche du menu (manette ou clavier) : déplace le curseur du clavier à l'écran.
func handle(action: String) -> void:
	match action:
		"up", "down":
			_key.y = posmod(_key.y + (1 if action == "down" else -1), ROWS.size())
			_key.x = mini(_key.x, ROWS[_key.y].length() - 1)
		"left", "right":
			_key.x = posmod(_key.x + (1 if action == "right" else -1), ROWS[_key.y].length())
		"confirm":
			_press(ROWS[_key.y][_key.x])
		"back":
			cancelled = true


## Une touche du vrai clavier. Renvoie true si elle a servi (les flèches restent pour le curseur).
func type_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed):
		return false
	var key := event as InputEventKey
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			done = true
			return true
		KEY_ESCAPE:
			cancelled = true
			return true
		KEY_BACKSPACE:
			_press("⌫")
			return true
	if key.unicode >= 32 and not key.echo:
		_add(char(key.unicode))
		return true
	return false


func build() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiKit.label(title, 30, UiKit.HIGHLIGHT))
	box.add_child(UiKit.label(text + "_", 36))
	box.add_child(UiKit.spacer(6))
	for y in ROWS.size():
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 6)
		var keys: String = ROWS[y]
		for x in keys.length():
			var on := Vector2i(x, y) == _key
			var cell := UiKit.label(_key_name(keys[x]), 22, UiKit.HIGHLIGHT if on else Color.WHITE)
			cell.custom_minimum_size = Vector2(130 if keys.length() <= 3 else 44, 44)
			cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var style := StyleBoxFlat.new()
			style.bg_color = Color(UiKit.HIGHLIGHT, 0.25) if on else Color(1, 1, 1, 0.06)
			style.set_corner_radius_all(6)
			cell.add_theme_stylebox_override("normal", style)
			line.add_child(cell)
		box.add_child(line)
	box.add_child(UiKit.label("Clavier : tape le nom, Entrée pour valider, Échap pour annuler", 18, UiKit.TEXT_DIM))
	box.add_child(UiKit.label("Manette : choisis une touche, A pour l'appuyer, OK pour valider, B pour annuler", 18, UiKit.TEXT_DIM))
	return box


func _press(key: String) -> void:
	match key:
		"⌫":
			text = text.left(-1)
		"✓":
			done = true
		"⎵":
			_add(" ")
		_:
			_add(key)


func _add(letter: String) -> void:
	if text.length() < max_length:
		text += letter


func _key_name(key: String) -> String:
	match key:
		"⎵":
			return "espace"
		"⌫":
			return "effacer"
		"✓":
			return "OK"
	return key
