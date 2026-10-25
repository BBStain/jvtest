class_name CityBlock
extends BreakableWindow
## Un bloc d'immeuble de la Ville : un morceau de mur, de plancher ou de passerelle qui s'use
## à chaque coup et disparaît quand il n'a plus de PV. Il ne revient jamais (la ville ne se répare pas).
## C'est une sorte de fenêtre : tout ce qui casse les fenêtres (coups, balles, lances, explosions,
## dash dans le mur) abîme donc aussi les blocs, sans rien changer ailleurs.
## Un plancher est traversable par en dessous, comme les plateformes.

const HIT_LOCK := 0.2         ## après un dégât, le bloc ignore les coups ce temps (un coup = un dégât)
const DUST_TIME := 0.5        ## la poussière quand il disparaît
const HEAVY_DAMAGE := 3       ## une attaque lourde enlève 3 PV (une légère, une balle, un dash : 1)
const EXPLOSION_DAMAGE := 4   ## une explosion (grenade) enlève 4 PV à tous les blocs dans son rayon

@export var max_hp := 6
@export var one_way := false

var hp := 6
var _lock := 0.0
var _flash := 0.0             ## petit éclair clair quand il prend un coup
var collapse: CityCollapse    ## prévenu quand le bloc casse (ce qui ne tient plus va tomber)


## À appeler avant de l'ajouter à la map : sa forme existe tout de suite (l'aperçu du menu la voit).
func setup(rect_size: Vector2, block_color: Color, floor_block: bool, block_hp: int) -> void:
	size = rect_size
	color = block_color
	one_way = floor_block
	max_hp = block_hp
	hp = block_hp
	collision_layer = 0
	set_collision_layer_value(Fighter.PLATFORM_LAYER if one_way else 1, true)
	collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.name = "Collision"
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	_shape.one_way_collision = one_way
	add_child(_shape)


func _ready() -> void:
	add_to_group("fenetres")
	set_physics_process(false)


## Un dégât (coup, balle, dash...). Renvoie true si le bloc vient de disparaître.
func smash() -> bool:
	return hit(1)


## "damage" dégâts d'un coup. Renvoie true si le bloc vient de disparaître.
func hit(damage: int) -> bool:
	if broken or _lock > 0.0:
		return false
	hp = maxi(hp - damage, 0)
	_lock = HIT_LOCK
	_flash = 0.12
	set_physics_process(true)
	if hp == 0:
		set_broken(true)
		return true
	queue_redraw()
	return false


func set_broken(value: bool) -> void:
	if value == broken:
		return
	if not value:
		hp = max_hp
	elif hp > 0:
		hp = 0
	super.set_broken(value)
	_shatter = DUST_TIME if value else 0.0
	set_physics_process(true)
	if value and collapse != null:
		collapse.block_broken(self)


## Le bloc part avec un morceau qui tombe (FallingChunk le dessine) : il disparaît d'ici, sans poussière.
func vanish() -> void:
	if broken:
		return
	broken = true
	_shatter = 0.0
	_shape.set_deferred("disabled", true)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_lock = maxf(_lock - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_shatter = maxf(_shatter - delta, 0.0)
	queue_redraw()
	if _lock == 0.0 and _flash == 0.0 and _shatter == 0.0:
		set_physics_process(false)


func _draw() -> void:
	var r := Rect2(-size / 2.0, size)
	if not broken:
		# Plus il est abîmé, plus il est sombre, avec des fissures
		var wear := 1.0 - float(hp) / float(max_hp)
		draw_rect(r, color.darkened(wear * 0.45).lerp(Color.WHITE, _flash * 3.0))
		var crack := Color(0.1, 0.1, 0.13, 0.8)
		var w := minf(size.x, size.y)
		if wear > 0.0:
			draw_line(Vector2(-size.x * 0.3, -size.y * 0.5), Vector2(size.x * 0.05, size.y * 0.1), crack, 2.0)
		if wear >= 0.5:
			draw_line(Vector2(size.x * 0.05, size.y * 0.1), Vector2(size.x * 0.35, size.y * 0.5), crack, 2.0)
			draw_line(Vector2(size.x * 0.05, size.y * 0.1), Vector2(-size.x * 0.4, w * 0.2), crack, 2.0)
		if wear >= 0.8:
			draw_line(Vector2(size.x * 0.5, -size.y * 0.3), Vector2(-size.x * 0.1, -size.y * 0.05), crack, 2.0)
		return
	# Disparu : un petit nuage de poussière qui grossit et s'efface
	if _shatter > 0.0:
		var k := 1.0 - _shatter / DUST_TIME
		for i in 6:
			var dir := Vector2.RIGHT.rotated(TAU * i / 6.0 + 0.3)
			draw_circle(dir * (10.0 + 40.0 * k), 10.0 + 14.0 * k, Color(color, 0.6 * (1.0 - k)))
