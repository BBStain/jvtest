class_name InputState
extends RefCounted
## Les commandes d'un joueur pour UNE frame de jeu.
## Le combattant ne lit jamais le clavier ou la manette directement : il ne voit que cet objet.
## Pour le jeu en ligne, c'est exactement ce qu'on enverra sur le réseau (voir to_dict / from_dict).

var stick := Vector2.ZERO   ## direction du stick ou de la croix (x : gauche/droite, y : haut/bas)
var down_pressed := false   ## bas appuyé cette frame : descendre d'une plateforme
var jump_pressed := false   ## saut appuyé cette frame
var jump_held := false      ## saut maintenu (saut plus haut si on garde appuyé)
var attack_pressed := false
var dash_pressed := false


func to_dict() -> Dictionary:
	return {
		"sx": stick.x, "sy": stick.y, "dp": down_pressed,
		"j": jump_pressed, "jh": jump_held, "a": attack_pressed, "d": dash_pressed,
	}


static func from_dict(data: Dictionary) -> InputState:
	var s := InputState.new()
	s.stick = Vector2(data.get("sx", 0.0), data.get("sy", 0.0))
	s.down_pressed = data.get("dp", false)
	s.jump_pressed = data.get("j", false)
	s.jump_held = data.get("jh", false)
	s.attack_pressed = data.get("a", false)
	s.dash_pressed = data.get("d", false)
	return s
