class_name TimeEngine
extends Node
## Le moteur de temps : ralentit ou accélère tout le jeu pendant un moment, puis revient doucement
## à la vitesse normale. N'importe quel événement du jeu peut le déclencher, par exemple :
##   time_engine.play(0.5, 5.0)   -> tout va 2 fois moins vite pendant 5 secondes
##   time_engine.play(1.5, 2.0)   -> tout va 1,5 fois plus vite pendant 2 secondes
## Les durées sont en vraies secondes (celles de ta montre), même pendant un ralenti.

const RAMP_TIME := 0.4   ## temps pour revenir en douceur à la vitesse normale à la fin

var _scale := 1.0        ## vitesse visée (1 = normale, 0.5 = 2 fois moins vite, 2 = 2 fois plus vite)
var _time_left := 0.0    ## vraies secondes restantes avant le retour à la normale
var _duration := 0.0     ## durée demandée au dernier play() (pour renew())
var _stopping := false   ## stop() demandé : le ralenti se termine, renew() ne le relance plus
var _renewable := true   ## false = un effet que renew() ne relance pas (ex. le ralenti d'un joueur sonné)
var _effect := 0         ## numéro de l'effet en cours : chaque play() en lance un nouveau


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # on ne laisse jamais le jeu ralenti en quittant la partie


## Change la vitesse du jeu pendant "duration" vraies secondes. Renvoie le numéro de cet effet
## (voir is_playing()). renewable = false : renew() ne le relancera pas.
func play(time_scale: float, duration: float, renewable := true) -> int:
	_scale = maxf(time_scale, 0.05)
	_duration = duration
	_time_left = duration
	_stopping = false
	_renewable = renewable
	Engine.time_scale = _scale
	_effect += 1
	return _effect


## Si un ralenti (ou une accélération) est en cours, il repart de zéro pour toute sa durée.
## Ne fait rien sinon, ni s'il est en train de s'arrêter (par exemple un duel déjà tranché),
## ni pour un effet bref (voir play()).
func renew() -> void:
	if is_active() and not _stopping and _renewable:
		_time_left = _duration
		Engine.time_scale = _scale


## Revient à la vitesse normale : en douceur (sur RAMP_TIME), ou tout de suite.
func stop(instant := false) -> void:
	_stopping = true
	if instant:
		_time_left = 0.0
		Engine.time_scale = 1.0
	else:
		_time_left = minf(_time_left, RAMP_TIME)


func is_active() -> bool:
	return _time_left > 0.0


## L'effet lancé par ce play() est-il encore en cours (pas fini, ni remplacé par un autre play()) ?
func is_playing(effect: int) -> bool:
	return is_active() and effect == _effect


## stop() a été demandé : l'effet en cours revient à la vitesse normale.
func is_stopping() -> bool:
	return _stopping


func _process(delta: float) -> void:
	if _time_left <= 0.0 or get_tree().paused:
		return  # pendant la pause, le ralenti attend
	_time_left -= delta / Engine.time_scale  # delta est déjà ralenti : on retrouve le vrai temps
	if _time_left <= 0.0:
		Engine.time_scale = 1.0
	elif _time_left < RAMP_TIME:
		Engine.time_scale = lerpf(1.0, _scale, _time_left / RAMP_TIME)
	else:
		Engine.time_scale = _scale
