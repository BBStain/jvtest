class_name ExplosiveBarrel
extends CityBlock
## Un tonneau explosif posé dans un immeuble de la Ville (placés au hasard à chaque partie).
## Un seul dégât suffit (coup, balle, explosion, dash de mecha...) : il est projeté, sa mèche
## s'allume, et il explose un peu plus tard (voir Game._on_barrel_exploded et Projectile "tonneau").
## Une explosion qui en touche un autre l'allume à son tour : ça fait des chaînes.
## Il fait partie de la ville : si le plancher sous lui s'écroule, il tombe avec (sans exploser).

signal exploded(barrel: ExplosiveBarrel)

const SIZE := Vector2(48, 64)
const COLOR := Color(0.85, 0.2, 0.15)


func setup_barrel() -> void:
	setup(SIZE, COLOR, false, 1)


func set_broken(value: bool) -> void:
	var was_broken := broken
	super.set_broken(value)
	if value and not was_broken:
		exploded.emit(self)


## Toujours dessiné par lui-même (pas par le peintre de la ville) : un tonneau, pas un bloc.
func is_plain() -> bool:
	return false


func _draw() -> void:
	if broken:
		return
	var r := Rect2(-size / 2.0, size)
	draw_rect(r, color.lerp(Color.WHITE, _flash * 3.0))
	var band := Color(0.25, 0.08, 0.06)
	draw_rect(Rect2(r.position.x, r.position.y + size.y * 0.22, size.x, 5.0), band)
	draw_rect(Rect2(r.position.x, r.end.y - size.y * 0.22 - 5.0, size.x, 5.0), band)
	draw_rect(Rect2(-6.0, -6.0, 12.0, 12.0), Color(1.0, 0.85, 0.2))  # le symbole « danger »
