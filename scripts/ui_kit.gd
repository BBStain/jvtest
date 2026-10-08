class_name UiKit
extends RefCounted
## Les morceaux d'affichage communs aux menus (menu de démarrage et menu pause) :
## textes, boutons, cases de joueur, dessins de manette et de clavier.

const BG_COLOR := Color(0.08, 0.09, 0.13)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const HIGHLIGHT := Color(1.0, 0.85, 0.3)


static func label(text: String, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


static func menu_button(text: String, selected: bool, on_click: Callable) -> Button:
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
	button.pressed.connect(on_click, CONNECT_DEFERRED)  # différé : l'écran peut être redessiné pendant le clic
	return button


static func slot_style(color: Color, active: bool) -> StyleBoxFlat:
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


## Un petit dessin de manette ou de clavier.
static func device_icon(device: Dictionary, color: Color, icon_size: Vector2) -> Control:
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
