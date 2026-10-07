class_name InputSource
extends RefCounted
## D'où viennent les commandes d'un joueur. Le jeu appelle poll() une fois par frame.
##
## Aujourd'hui il n'y a que LocalInputSource (clavier / manette de cette machine).
## Pour le jeu en ligne, il suffira d'ajouter une NetworkInputSource qui renvoie
## les InputState reçus du réseau : le code du combattant n'aura pas à changer.


func poll() -> InputState:
	return InputState.new()
