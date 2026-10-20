class_name ItemPickup
extends Node2D
## Un objet qui tombe du ciel sur la map (voir game.gd) : on le ramasse en passant dessus,
## s'il n'a pas déjà un objet. On l'utilise ensuite avec RT (voir Fighter._tick_item).
##   pistolet : 5 balles, une par appui
##   grenade  : RT gardé = dégoupillée, plus on garde plus elle part loin, explose au bout de 3 s
##   bouclier : levé pendant 5 s, qui frappe dedans est projeté très loin
##   vie      : RT donne une vie en plus (jusqu'à Fighter.MAX_LIVES)
## Dessin très simple (une caisse de couleur avec une lettre) : à remplacer par un graphiste.

const KINDS := ["pistolet", "grenade", "bouclier", "vie"]
const SIZE := 26.0
const MAX_FALL := 600.0                 ## il tombe du ciel doucement (plus vite s'il est frappé)

var kind := "pistolet"
var velocity := Vector2.ZERO
var body := LooseBody.new()             ## tombe, se pose, suit les plateformes, valdingue quand on le frappe
var hit_lock := 0.0                     ## vient d'être frappé : le même coup ne le refrappe pas
var _launched := false                  ## frappé, pas encore reposé
var simulate := true                    ## false chez un copain en ligne : il ne fait qu'afficher
var landed: bool:                       ## posé quelque part
	get:
		return body.resting


static func color_of(item_kind: String) -> Color:
	match item_kind:
		"pistolet":
			return Color(0.6, 0.62, 0.7)
		"grenade":
			return Color(0.45, 0.75, 0.35)
		"bouclier":
			return Color(0.45, 0.7, 1.0)
		"vie":
			return Color(1.0, 0.45, 0.6)
	return Color.WHITE


func _physics_process(delta: float) -> void:
	if not simulate:
		return
	hit_lock -= delta
	if not _launched:
		velocity.y = minf(velocity.y, MAX_FALL)  # chute tranquille quand personne ne l'a frappé
	velocity = body.step(self, velocity, SIZE / 2.0, delta)
	if body.resting:
		_launched = false


## Un coup (ou une explosion) l'envoie valdinguer.
func launch(new_velocity: Vector2) -> void:
	velocity = new_velocity
	body.launch()
	_launched = true
	hit_lock = Game.LOOSE_HIT_LOCK


func rect() -> Rect2:
	return Rect2(position - Vector2.ONE * SIZE / 2.0, Vector2.ONE * SIZE)


func net_state() -> Array:
	return [kind, position]


func apply_net_state(data: Array) -> void:
	if kind != data[0]:
		kind = data[0]
		queue_redraw()
	position = data[1]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var box := Rect2(-Vector2.ONE * SIZE / 2.0, Vector2.ONE * SIZE)
	draw_rect(box, Color(color_of(kind), 0.9))
	draw_rect(box, Color(1, 1, 1, 0.8), false, 2.0)
	var font := ThemeDB.fallback_font
	var letter := kind.left(1).to_upper()
	draw_string(font, Vector2(-SIZE / 2.0, 6.0), letter, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 16, Color(0.08, 0.09, 0.13))
