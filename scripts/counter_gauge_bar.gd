class_name CounterGaugeBar
extends Control
## La jauge de contre (partagée par tous les joueurs) en haut de l'écran : une petite barre avec
## un trait à chaque passage de phase. Sa couleur est celle de la phase : blanc, jaune, orange,
## puis rouge qui pulse en berserk. Elle n'apparaît que quand quelqu'un a contré.

const WIDTH := 300.0
const HEIGHT := 12.0
const TOP := 18.0

var gauge: CounterGauge
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.05)
	queue_redraw()


func _draw() -> void:
	if gauge == null or gauge.points <= 0.0:
		return
	var alpha := clampf(gauge.points * 2.0, 0.0, 1.0)  # apparaît / disparaît en douceur
	var frame := Rect2((get_viewport_rect().size.x - WIDTH) / 2.0, TOP, WIDTH, HEIGHT)
	var full: float = CounterGauge.PHASE_POINTS[-1]
	var fill_color := gauge.color()
	if gauge.is_berserk():
		fill_color = fill_color.lightened(0.35 * (0.5 + 0.5 * sin(_clock * 14.0)))
	if gauge.flash_timer > 0.0:
		var glow := gauge.flash_timer / CounterGauge.FLASH_TIME
		draw_rect(frame.grow(6.0 * glow), Color(gauge.color(), 0.5 * glow))
	draw_rect(frame, Color(0, 0, 0, 0.6 * alpha))
	draw_rect(Rect2(frame.position, Vector2(WIDTH * minf(gauge.points / full, 1.0), HEIGHT)), Color(fill_color, alpha))
	for i in CounterGauge.PHASE_POINTS.size() - 1:
		var x: float = frame.position.x + WIDTH * CounterGauge.PHASE_POINTS[i] / full
		draw_line(Vector2(x, frame.position.y), Vector2(x, frame.end.y), Color(0, 0, 0, 0.85 * alpha), 2.0)
	draw_rect(frame, Color(1, 1, 1, 0.5 * alpha), false, 1.5)
