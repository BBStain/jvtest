class_name FallingChunk
extends Node2D
## Un morceau d'immeuble détaché qui tombe (voir CityCollapse).
## Petit (moins de BIG_BLOCKS blocs) : de la poussière qui tombe tout de suite, sans danger.
## Gros : il tremble WARN_TIME avec une ombre rouge là où il va tomber, puis il tombe. Il fait mal
## comme une attaque lourde venue du ciel, et se contre pareil (voir game.gd, _resolve_chunks) :
## le casser en l'air, blocage parfait, ou l'esquiver. À l'arrivée, il abîme ce qu'il percute et éclate.

const BIG_BLOCKS := 4
const WARN_TIME := 0.5
const GRAVITY := 2300.0
const MAX_FALL := 1800.0
const IMPACT_DAMAGE := 4       ## un gros morceau qui s'écrase enlève 4 PV aux blocs qu'il percute
const BURST_TIME := 0.45
const LIGHT_HITS := 3          ## coups légers (ou balles) pour le casser en l'air ; une lourde suffit

enum State { WARN, FALL, BURST }

var rects: Array[Rect2] = []    ## les blocs du morceau (position de départ)
var colors: Array[Color] = []
var state := State.FALL
var offset := Vector2.ZERO      ## de combien il est descendu
var big := false
var hits_left := LIGHT_HITS
var hit_fighters := {}          ## ceux qu'il a déjà touchés (une seule fois par joueur)
var _speed := 0.0
var _timer := 0.0
var _shadow := Rect2()
var _collapse: CityCollapse


func setup(group: Array[CityBlock], collapse: CityCollapse) -> void:
	_collapse = collapse
	for block in group:
		rects.append(block.rect())
		colors.append(block.color.darkened(0.45 * (1.0 - float(block.hp) / block.max_hp)))
	big = group.size() >= BIG_BLOCKS
	if big:
		state = State.WARN
		_timer = WARN_TIME
		var box := bounds()
		var land := collapse.ground_below(box.position.x, box.end.x, box.end.y)
		if land < INF:
			_shadow = Rect2(box.position.x, land - 14.0, box.size.x, 14.0)


## Le rectangle qui englobe le morceau, là où il est maintenant.
func bounds() -> Rect2:
	var box := rects[0]
	for r in rects:
		box = box.merge(r)
	return Rect2(box.position + offset, box.size)


## Les blocs du morceau, là où ils sont maintenant.
func current_rects() -> Array[Rect2]:
	var moved: Array[Rect2] = []
	for r in rects:
		moved.append(Rect2(r.position + offset, r.size))
	return moved


## Peut-il encore toucher quelqu'un ?
func is_dangerous() -> bool:
	return big and state == State.FALL


## Un coup sur le morceau en l'air (heavy = attaque lourde). Renvoie true s'il vient d'éclater.
func take_attack(heavy: bool) -> bool:
	if state == State.BURST:
		return false
	hits_left -= LIGHT_HITS if heavy else 1
	if hits_left <= 0:
		burst()
		return true
	return false


## Il éclate en poussière (et disparaît un peu après).
func burst() -> void:
	if state == State.BURST:
		return
	state = State.BURST
	_timer = BURST_TIME
	queue_redraw()


func _physics_process(delta: float) -> void:
	queue_redraw()
	match state:
		State.WARN:
			_timer -= delta
			if _timer <= 0.0:
				state = State.FALL
		State.BURST:
			_timer -= delta
			if _timer <= 0.0:
				queue_free()
		State.FALL:
			_speed = minf(_speed + GRAVITY * delta, MAX_FALL)
			var step := _speed * delta
			var landed := _land_distance(step)
			if landed >= 0.0:
				offset.y += landed
				_impact()
			else:
				offset.y += step
				if bounds().position.y > 2000.0:
					queue_free()  # tombé dans le vide


## De combien il peut descendre avant de toucher quelque chose (-1 : rien dans ce pas).
## (Ses propres blocs sont déjà "cassés" : on ne regarde que les blocs restés en place sous lui.)
func _land_distance(step: float) -> float:
	var best := -1.0
	var box := bounds()
	var below: Array[Rect2] = []
	for block in _collapse.blocks:
		if not block.broken:
			var b := block.rect()
			if b.end.x > box.position.x and b.position.x < box.end.x and b.end.y > box.position.y \
					and b.position.y <= box.end.y + step:
				below.append(b)
	for r in current_rects():
		var swept := Rect2(r.position.x + 1.0, r.position.y, r.size.x - 2.0, r.size.y + step)
		if swept.end.y >= 0.0 and r.end.x > -Ville.HALF_WIDTH and r.position.x < Ville.HALF_WIDTH:
			var d := maxf(0.0 - r.end.y, 0.0)
			if best < 0.0 or d < best:
				best = d
		for b in below:
			if swept.intersects(b) and b.position.y >= r.end.y - 1.0:
				var d := maxf(b.position.y - r.end.y, 0.0)
				if best < 0.0 or d < best:
					best = d
	return best


## Il s'écrase : les blocs juste dessous (et autour) s'abîment, puis il éclate.
func _impact() -> void:
	if big:
		var zone := bounds().grow_individual(4.0, 0.0, 4.0, 6.0)
		for block in _collapse.blocks:
			if not block.broken and zone.intersects(block.rect()):
				block.hit(IMPACT_DAMAGE)
	burst()


func _draw() -> void:
	var shake := Vector2.ZERO
	if state == State.WARN:
		shake = Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0))
	if big and state != State.BURST and _shadow.size.x > 0.0:
		draw_rect(_shadow, Color(0.95, 0.2, 0.2, 0.45))
	if state == State.BURST:
		var k := 1.0 - _timer / BURST_TIME
		for i in rects.size():
			var c := rects[i].get_center() + offset
			draw_circle(c + Vector2(0.0, -20.0 * k), 20.0 + 30.0 * k, Color(colors[i], 0.5 * (1.0 - k)))
		return
	for i in rects.size():
		draw_rect(Rect2(rects[i].position + offset + shake, rects[i].size), colors[i])
