class_name EditorJuice
extends Node2D
## Le « jus » de l'éditeur de map : ce qui rend la construction agréable, sans rien changer à la map.
##   - un élément posé apparaît en rebondissant, avec un cadre qui s'élargit et quelques étincelles ;
##   - un élément pris se soulève un peu (plus gros, avec une ombre) et glisse d'une case à l'autre ;
##   - lâché, il s'écrase un peu en se posant et fait un petit nuage de poussière ;
##   - effacé, il part en morceaux ;
##   - agrandi ou tourné, il fait un petit rebond ;
##   - « Sauvée ! » apparaît en grand ;
##   - à la manette, chaque geste fait une petite vibration.
## Tout est dessiné par-dessus la map (comme les marqueurs de l'éditeur) ou appliqué aux nœuds d'aperçu.

const GLIDE_TIME := 0.09          ## un élément qui change de place y glisse en ce temps
const POP_TIME := 0.34
const LAND_TIME := 0.3
const BUMP_TIME := 0.2
const LIFT_SCALE := 1.06          ## un élément pris est un peu plus gros
const BIT_GRAVITY := 1400.0
const TOAST_TIME := 1.4

var editor: MapEditor
var lifted_id := -1               ## l'élément pris (souris ou manette), -1 : aucun
var time := 0.0                   ## pour les petites pulsations (curseur)

var _anims := {}                  ## id -> l'animation en cours de son nœud d'aperçu
var _fx: Array[Dictionary] = []   ## cadres et morceaux qui volent
var _toast: Label
var _toast_t := TOAST_TIME
var _rng := RandomNumberGenerator.new()
var _shadow: Node2D               ## l'ombre de l'élément pris, dessinée sous la map


func _ready() -> void:
	_shadow = Node2D.new()
	_shadow.draw.connect(_draw_shadow)
	editor.add_child(_shadow)
	editor.move_child(_shadow, editor._preview.get_index())
	_toast = UiKit.label("", 44, UiKit.HIGHLIGHT)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 70
	_toast.size = Vector2(600, 60)
	_toast.position.x = -300
	_toast.pivot_offset = Vector2(300, 30)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	editor._ui.add_child(_toast)


func _process(delta: float) -> void:
	time += delta
	for id in _anims.keys():
		var anim: Dictionary = _anims[id]
		var node: Node2D = editor._nodes.get(id)
		if node == null or not is_instance_valid(node):
			_anims.erase(id)
			continue
		anim.t += delta
		var k := clampf(anim.t / anim.dur, 0.0, 1.0)
		var smooth := 1.0 - pow(1.0 - k, 3.0)
		node.position = (anim.pos_from as Vector2).lerp(anim.pos_to, smooth)
		node.rotation = lerp_angle(anim.rot_from, anim.rot_to, smooth)
		node.scale = (anim.scale_from as Vector2).lerp(anim.scale_to, _back(k) if anim.bouncy else smooth)
		if k >= 1.0:
			_anims.erase(id)
	var lifted: Node2D = editor._nodes.get(lifted_id)
	if lifted != null and is_instance_valid(lifted) and not _anims.has(lifted_id):
		lifted.scale = lifted.scale.lerp(Vector2.ONE * LIFT_SCALE, 1.0 - exp(-20.0 * delta))
	for fx in _fx:
		fx.t += delta
		for bit in fx.get("bits", []):
			bit.v.y += BIT_GRAVITY * delta
			bit.p += bit.v * delta
	_fx = _fx.filter(func(fx: Dictionary) -> bool: return fx.t < fx.dur)
	if _toast.visible:
		_toast_t += delta
		_toast.scale = Vector2.ONE * lerpf(0.4, 1.0, _back(clampf(_toast_t / 0.25, 0.0, 1.0)))
		_toast.modulate.a = clampf((TOAST_TIME - _toast_t) / 0.4, 0.0, 1.0)
		_toast.visible = _toast_t < TOAST_TIME
	queue_redraw()
	_shadow.queue_redraw()
	if editor._pad != null and editor._pad.active:
		editor._overlay.queue_redraw()  # le curseur respire


## Rebond qui dépasse un peu puis revient (comme un ressort).
func _back(k: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)


func _anim(id: int, dur: float, scale_from: Vector2, bouncy: bool) -> void:
	var node: Node2D = editor._nodes.get(id)
	if node == null:
		return
	var scale_to := Vector2.ONE * LIFT_SCALE if id == lifted_id else Vector2.ONE
	var pos_to := node.position
	var rot_to := node.rotation
	if _anims.has(id):  # il glissait encore : il finit d'arriver à sa place
		pos_to = _anims[id].pos_to
		rot_to = _anims[id].rot_to
	_anims[id] = {"t": 0.0, "dur": dur, "pos_from": node.position, "pos_to": pos_to,
		"rot_from": node.rotation, "rot_to": rot_to, "scale_from": scale_from, "scale_to": scale_to, "bouncy": bouncy}
	node.scale = scale_from


# --- Ce que l'éditeur appelle ---

## Le nœud d'un élément vient d'être refait (déplacé, tourné, agrandi) : il glisse depuis l'ancien.
func glide(id: int, old: Node2D) -> void:
	var node: Node2D = editor._nodes.get(id)
	if node == null or old == null:
		return
	if _anims.has(id):  # une animation tourne déjà (rebond) : elle continue, vers la nouvelle place
		var anim: Dictionary = _anims[id]
		anim.pos_from = old.position
		anim.rot_from = old.rotation
		anim.pos_to = node.position
		anim.rot_to = node.rotation
		anim.t = 0.0
		anim.dur = maxf(anim.dur, GLIDE_TIME)
		node.position = old.position
		node.rotation = old.rotation
		node.scale = old.scale
		return
	if old.position == node.position and is_equal_approx(old.rotation, node.rotation) and old.scale == Vector2.ONE:
		return
	var scale_keep := old.scale
	_anims[id] = {"t": 0.0, "dur": GLIDE_TIME, "pos_from": old.position, "pos_to": node.position,
		"rot_from": old.rotation, "rot_to": node.rotation, "scale_from": scale_keep,
		"scale_to": Vector2.ONE * LIFT_SCALE if id == lifted_id else Vector2.ONE, "bouncy": false}
	node.position = old.position
	node.rotation = old.rotation
	node.scale = scale_keep


## Un élément vient d'être posé : il apparaît en rebondissant.
func pop(element: Dictionary) -> void:
	_anim(element.id, POP_TIME, Vector2(0.3, 0.3), true)
	var rect := MapData.bounds_of(element)
	_fx.append({"kind": "ring", "rect": rect, "color": UiKit.HIGHLIGHT, "t": 0.0, "dur": 0.4})
	_fx.append({"kind": "bits", "color": UiKit.HIGHLIGHT, "t": 0.0, "dur": 0.5,
		"bits": _bits(rect.get_center(), 8, 380.0, -250.0)})
	rumble(0.25, 0.0, 0.08)


## Un élément est pris : il se soulève.
func lift(id: int) -> void:
	lifted_id = id
	rumble(0.15, 0.0, 0.05)


## Un élément pris est lâché : s'il a bougé, il s'écrase un peu en se posant.
func land(element: Dictionary, moved: bool) -> void:
	lifted_id = -1
	if element.is_empty():
		return
	if not moved:
		_anim(element.id, 0.12, Vector2.ONE * LIFT_SCALE, false)
		return
	_anim(element.id, LAND_TIME, Vector2(1.14, 0.84), true)
	var rect := MapData.bounds_of(element)
	var bottom := Vector2(rect.get_center().x, rect.end.y)
	var dust := _bits(bottom, 6, 220.0, -120.0)
	for bit in dust:
		bit.v.y = minf(bit.v.y, -40.0)
	_fx.append({"kind": "bits", "color": Color(1, 1, 1, 0.7), "t": 0.0, "dur": 0.35, "bits": dust})
	rumble(0.4, 0.2, 0.1)


## Agrandi, rétréci, tourné : un petit rebond.
func bump(element: Dictionary) -> void:
	_anim(element.id, BUMP_TIME, Vector2.ONE * 1.08, true)
	rumble(0.12, 0.0, 0.04)


## Effacé : il part en morceaux.
func puff(element: Dictionary) -> void:
	_anims.erase(element.id)
	var rect := MapData.bounds_of(element)
	var color := MapData.color(element) if element.has("color") else Color.WHITE
	_fx.append({"kind": "bits", "color": color, "t": 0.0, "dur": 0.6, "bits": _bits(rect.get_center(), 12, 520.0, -350.0)})
	rumble(0.3, 0.35, 0.12)


## Toute la map vient d'être remplacée (annuler, ouvrir...) : on oublie les animations.
func reset() -> void:
	_anims.clear()
	lifted_id = -1


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 0.0
	_toast.visible = true
	rumble(0.3, 0.3, 0.15)


## Une petite vibration de la manette (seulement si on joue à la manette).
func rumble(weak: float, strong: float, duration: float) -> void:
	if editor._pad == null or not editor._pad.active:
		return
	for device in EditorPad.MAX_PADS:
		Input.start_joy_vibration(device, weak, strong, duration)


func _bits(center: Vector2, count: int, speed: float, lift_speed: float) -> Array:
	var bits := []
	for i in count:
		var angle := TAU * i / count + _rng.randf_range(-0.3, 0.3)
		var v := Vector2.RIGHT.rotated(angle) * speed * _rng.randf_range(0.5, 1.0)
		v.y += lift_speed
		bits.append({"p": center, "v": v})
	return bits


func _draw_shadow() -> void:
	var lifted: Node2D = editor._nodes.get(lifted_id)
	if lifted == null or not is_instance_valid(lifted):
		return
	var px := 1.0 / editor._camera.zoom.x
	for element in editor.data.elements:
		if element.id == lifted_id:
			_shadow.draw_set_transform(lifted.position + Vector2(10, 14) * px, lifted.rotation)
			var half := MapData.size_of(element) / 2.0
			var offset := MapData.center_of(element) - MapData.vec(element, "pos")
			_shadow.draw_rect(Rect2(offset - half, half * 2.0), Color(0, 0, 0, 0.4))
			_shadow.draw_set_transform(Vector2.ZERO)
			return


func _draw() -> void:
	var px := 1.0 / editor._camera.zoom.x
	for fx in _fx:
		var k: float = fx.t / fx.dur
		var color: Color = fx.color
		match fx.kind:
			"ring":
				var rect: Rect2 = fx.rect
				draw_rect(rect.grow((6.0 + 40.0 * k) * px), Color(color, 1.0 - k), false, 3.0 * px)
			"bits":
				for bit in fx.bits:
					var size := 9.0 * (1.0 - k * 0.6) * px
					draw_rect(Rect2(bit.p - Vector2(size, size) / 2.0, Vector2(size, size)), Color(color, 1.0 - k))
