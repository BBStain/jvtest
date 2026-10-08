class_name NetworkInputSource
extends InputSource
## Les commandes d'un joueur qui joue depuis un autre ordinateur (jeu en ligne, côté hôte).
## Ses touches arrivent par le réseau (push) ; le jeu les lit une fois par frame (poll).
## Un appui (saut, coup...) n'est jamais perdu : s'il arrive entre deux frames, ou si deux
## messages arrivent dans la même frame, il est gardé jusqu'à la frame suivante.

const PRESSED := ["down_pressed", "jump_pressed", "attack_pressed", "aimed_attack_pressed", "heavy_pressed", "dash_pressed"]

var _latest := InputState.new()
var _pending := {}  ## les appuis reçus depuis la dernière frame
var _pending_aim := Vector2.ZERO


func push(data: Dictionary) -> void:
	_latest = InputState.from_dict(data)
	for flag in PRESSED:
		if _latest.get(flag):
			_pending[flag] = true
	if _latest.aimed_attack_pressed:
		_pending_aim = _latest.aim


func poll() -> InputState:
	var s := InputState.from_dict(_latest.to_dict())
	for flag in PRESSED:
		s.set(flag, _pending.get(flag, false))
	if s.aimed_attack_pressed:
		s.aim = _pending_aim
	_pending.clear()
	return s


## Le joueur est parti : plus aucune touche.
func clear() -> void:
	_latest = InputState.new()
	_pending.clear()
