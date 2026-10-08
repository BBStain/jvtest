class_name CounterGauge
extends RefCounted
## La jauge de contre, une seule pour toute la partie : chaque contre, de n'importe quel joueur, la
## remplit, et sa phase s'applique à tout le monde. Plus on se contre, plus le combat s'emballe.
## Elle redescend quand plus personne ne contre.
##
## Phase 1 : normale. Phase 2 : recharge des attaques plus courte, boucliers plus abîmés.
## Phase 3 : recharge très courte, boucliers très abîmés. Phase 4 : berserk, tout est boosté.
## (Les effets de chaque phase sont en haut de scripts/fighter.gd.)

const PHASE_POINTS := [4, 10, 18]       ## points pour passer en phase 2, 3, puis 4 (berserk)
const MAX_POINTS := 21.0                ## la jauge ne monte pas plus haut (un peu de réserve en berserk)
const HEAVY_COUNTER_POINTS := 3         ## contrer une attaque lourde compte pour 3 contres
const IDLE_TIME := 4.0                  ## après 4 s sans contre, la jauge redescend...
const DECAY := 1.0                      ## ... d'un point par seconde
const FLASH_TIME := 0.45                ## éclat quand la jauge passe une phase
const PHASE_COLORS := [
	Color(0.9, 0.92, 1.0),   # phase 1 : blanc
	Color(1.0, 0.85, 0.3),   # phase 2 : jaune
	Color(1.0, 0.55, 0.2),   # phase 3 : orange
	Color(1.0, 0.22, 0.15),  # phase 4 : rouge (berserk)
]

var points := 0.0
var flash_timer := 0.0                  ## > 0 juste après un passage de phase
var _idle_timer := 0.0


## Un contre vient d'avoir lieu (contrer une attaque lourde compte triple).
func add_counter(countered_heavy: bool) -> void:
	set_points(minf(points + (HEAVY_COUNTER_POINTS if countered_heavy else 1), MAX_POINTS))
	_idle_timer = IDLE_TIME


## Change les points (jeu en ligne : un copain reçoit ceux de l'hôte). Passer une phase fait un éclat.
func set_points(value: float) -> void:
	var before := phase()
	points = value
	if phase() > before:
		flash_timer = FLASH_TIME


func tick(delta: float) -> void:
	flash_timer -= delta
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		points = maxf(points - DECAY * delta, 0.0)


## De 1 (normale) à 4 (berserk).
func phase() -> int:
	var result := 1
	for threshold in PHASE_POINTS:
		if points >= threshold:
			result += 1
	return result


func is_berserk() -> bool:
	return phase() == 4


func color() -> Color:
	return PHASE_COLORS[phase() - 1]
