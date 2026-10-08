class_name BuildVersion
extends RefCounted
## Le numéro de la version du jeu, affiché en bas à droite du menu et du menu pause.
## Il est rempli automatiquement à chaque mise en ligne (voir .github/workflows/web.yml) :
## ça permet de vérifier qu'on joue bien à la dernière version, et pas à une ancienne
## gardée en mémoire par le navigateur. Sur ton ordinateur, il reste "dev".

const TEXT := "dev"


## Petit texte discret en bas à droite de l'écran.
static func make_label() -> Label:
	var label := Label.new()
	label.text = "version " + TEXT
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
