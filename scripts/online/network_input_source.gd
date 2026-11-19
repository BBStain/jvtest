class_name NetworkInputSource
extends InputSource
## Les commandes d'un joueur qui joue depuis un autre ordinateur (jeu en ligne, côté hôte).
## Ses touches arrivent par le réseau (push) ; le jeu les lit une fois par frame (poll).
## Un appui (saut, coup...) n'est jamais perdu : s'il arrive entre deux frames, ou si deux
## messages arrivent dans la même frame, il est gardé jusqu'à la frame suivante.
##
## Les messages des touches peuvent se perdre en route (c'est voulu : un message en retard ne sert
## plus à rien, on ne l'attend pas). Pour ne perdre aucun appui, le copain envoie à chaque frame,
## pour chaque bouton, le nombre de fois qu'il l'a appuyé depuis le début (« pc », voir
## InputState.PRESSED). Si ce nombre a augmenté depuis le dernier message reçu, le bouton a été appuyé.

var _latest := InputState.new()
var _pending := {}  ## les appuis reçus depuis la dernière frame
var _pending_aim := Vector2.ZERO
var _counts := PackedByteArray()  ## les compteurs d'appuis du dernier message reçu


func push(data: Dictionary) -> void:
	_latest = InputState.from_dict(data)
	var counts = data.get("pc")
	if counts is PackedByteArray and counts.size() == InputState.PRESSED.size():
		for i in counts.size():
			# Le premier message ne compte pas les appuis d'avant ; un compteur repasse de 255 à 0.
			if _counts.size() == counts.size() and counts[i] != _counts[i]:
				_pending[InputState.PRESSED[i]] = true
		_counts = counts
	else:
		for flag in InputState.PRESSED:
			if _latest.get(flag):
				_pending[flag] = true
	if _pending.get("aimed_attack_pressed", false):
		_pending_aim = _latest.aim


func poll() -> InputState:
	var s := InputState.from_dict(_latest.to_dict())
	for flag in InputState.PRESSED:
		s.set(flag, _pending.get(flag, false))
	if s.aimed_attack_pressed:
		s.aim = _pending_aim
	_pending.clear()
	return s


## Le joueur est parti : plus aucune touche.
func clear() -> void:
	_latest = InputState.new()
	_pending.clear()
	_counts = PackedByteArray()
