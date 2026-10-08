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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # on ne laisse jamais le jeu ralenti en quittant la partie


## Change la vitesse du jeu pendant "duration" vraies secondes.
func play(time_scale: float, duration: float) -> void:
	_scale = maxf(time_scale, 0.05)
	_time_left = duration
	Engine.time_scale = _scale


## Revient à la vitesse normale : en douceur (sur RAMP_TIME), ou tout de suite.
func stop(instant := false) -> void:
	if instant:
		_time_left = 0.0
		Engine.time_scale = 1.0
	else:
		_time_left = minf(_time_left, RAMP_TIME)


func is_active() -> bool:
	return _time_left > 0.0


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
