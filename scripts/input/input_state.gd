class_name InputState
extends RefCounted
## Les commandes d'un joueur pour UNE frame de jeu.
## Le combattant ne lit jamais le clavier ou la manette directement : il ne voit que cet objet.
## Pour le jeu en ligne, c'est exactement ce qu'on enverra sur le réseau (voir to_dict / from_dict).

var stick := Vector2.ZERO   ## direction du stick ou de la croix (x : gauche/droite, y : haut/bas)
var down_pressed := false   ## bas appuyé cette frame : descendre d'une plateforme
var jump_pressed := false   ## saut appuyé cette frame
var jump_held := false      ## saut maintenu (saut plus haut si on garde appuyé)
var attack_pressed := false  ## attaque légère (visée automatique vers l'adversaire le plus proche)
var aimed_attack_pressed := false  ## attaque légère visée : pichenette sur le stick droit
var aim := Vector2.ZERO      ## direction de l'attaque visée (longueur 1)
var heavy_pressed := false   ## attaque lourde (début de la charge)
var heavy_held := false      ## attaque lourde maintenue (on charge tant qu'on garde)
var dash_pressed := false
var block_held := false     ## blocage maintenu (B)
var sprint_held := false    ## course maintenue (LT / Shift)
var item_pressed := false   ## objet (RT) appuyé cette frame : tirer au pistolet, lever le bouclier...
var item_held := false      ## objet maintenu : la grenade est dégoupillée tant qu'on garde
var throw_pressed := false  ## lancer son arme (RB) appuyé cette frame
var throw_held := false     ## RB maintenu (en mecha : on charge le coup de poing)
var ultimate_pressed := false  ## X + Y appuyés ensemble cette frame : l'attaque ultime (si sa jauge est pleine)


func to_dict() -> Dictionary:
	return {
		"sx": stick.x, "sy": stick.y, "dp": down_pressed,
		"j": jump_pressed, "jh": jump_held, "a": attack_pressed, "aa": aimed_attack_pressed,
		"ax": aim.x, "ay": aim.y, "h": heavy_pressed, "hh": heavy_held, "d": dash_pressed,
		"b": block_held, "r": sprint_held, "o": item_pressed, "oh": item_held, "t": throw_pressed, "th": throw_held, "u": ultimate_pressed,
	}


static func from_dict(data: Dictionary) -> InputState:
	var s := InputState.new()
	s.stick = Vector2(data.get("sx", 0.0), data.get("sy", 0.0))
	s.down_pressed = data.get("dp", false)
	s.jump_pressed = data.get("j", false)
	s.jump_held = data.get("jh", false)
	s.attack_pressed = data.get("a", false)
	s.aimed_attack_pressed = data.get("aa", false)
	s.aim = Vector2(data.get("ax", 0.0), data.get("ay", 0.0))
	s.heavy_pressed = data.get("h", false)
	s.heavy_held = data.get("hh", false)
	s.dash_pressed = data.get("d", false)
	s.block_held = data.get("b", false)
	s.sprint_held = data.get("r", false)
	s.item_pressed = data.get("o", false)
	s.item_held = data.get("oh", false)
	s.throw_pressed = data.get("t", false)
	s.throw_held = data.get("th", false)
	s.ultimate_pressed = data.get("u", false)
	return s
