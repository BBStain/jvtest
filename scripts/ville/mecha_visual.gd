class_name MechaVisual
extends Node2D
## Le dessin du mecha de la Ville (étape 4 du plan : son design, pas encore jouable).
## Un mecha bipède 4 fois plus grand que son pilote : un corps dans la couleur du joueur, un cockpit
## où l'on voit le pilote, deux jambes articulées, une arme de chaque côté qui vise (la rafale sur
## l'épaule de devant, l'arme lourde posée sur celle de derrière) et des réacteurs sous les pieds.
## Tout est dessiné avec des formes simples (une forme + une couleur par chose).
## La position du nœud est entre les deux pieds, au sol.

enum Pose { IDLE, WALK, FLY, SHOOT, HEAVY, WORN, LAND, EXPLODE }

const SCALE := 4.0                    ## le mecha fait 4 fois la taille de son pilote
const LAND_TIME := 0.7                ## chute du ciel...
const SHOCKWAVE_TIME := 0.5           ## ... puis onde de choc
const SHOCKWAVE_RADIUS := 300.0
const EXPLODE_TIME := 1.2

var stats: CharacterStats
var color := Color(0.95, 0.35, 0.35)
var pose := Pose.IDLE
var facing := 1.0                     ## 1 = regarde à droite
var aim := 0.0                        ## angle de visée des armes (0 = devant)
var wear := 0.0                       ## 0 = neuf, 1 = sur le point d'exploser
var pose_time := 0.0                  ## depuis quand on est dans cette pose
var heavy_weapon := "roquette"        ## "roquette" ou "laser"
var _time := 0.0


## Largeur et hauteur du mecha (pieds compris), d'après la taille de son pilote.
func mecha_size() -> Vector2:
	var body := stats.body_size if stats != null else Vector2(20, 60)
	return body * SCALE


func set_pose(value: Pose) -> void:
	pose = value
	pose_time = 0.0


func _process(delta: float) -> void:
	_time += delta
	pose_time += delta
	queue_redraw()


func _draw() -> void:
	var s := mecha_size()
	var w := s.x
	var h := s.y
	if pose == Pose.EXPLODE:
		_draw_explosion(w, h)
		return
	var lift := 0.0                   # de combien le corps est au-dessus du sol (vol, chute)
	var bob := 0.0
	var stride := 0.0                 # -1..1 : où en sont les jambes dans le pas
	var tuck := 0.0                   # 0 = jambes tendues, 1 = repliées (vol)
	match pose:
		Pose.IDLE, Pose.SHOOT, Pose.HEAVY, Pose.WORN:
			bob = sin(_time * 2.0) * h * 0.008
		Pose.WALK:
			stride = sin(_time * 5.0)
			bob = absf(cos(_time * 5.0)) * h * 0.025
		Pose.FLY:
			lift = h * 0.35 + sin(_time * 3.0) * h * 0.03
			tuck = 0.6
		Pose.LAND:
			var k := clampf(pose_time / LAND_TIME, 0.0, 1.0)
			lift = h * 4.0 * (1.0 - k * k)
			tuck = 0.4 * (1.0 - k)
			if pose_time >= LAND_TIME:
				_draw_shockwave(pose_time - LAND_TIME)
				bob = -h * 0.04 * maxf(0.0, 1.0 - (pose_time - LAND_TIME) * 5.0)  # s'écrase un peu
	var hip_y := -h * 0.42 - lift + bob
	var body := color.darkened(wear * 0.35)
	# Les jambes (celle de derrière plus sombre), avec la flamme des réacteurs en vol
	for side: float in [-1.0, 1.0]:
		var phase := stride * side
		var hip := Vector2(side * w * 0.22, hip_y)
		var foot := Vector2(side * w * 0.26 + phase * w * 0.35 * facing, -lift + bob * 0.2)
		foot.y -= maxf(0.0, phase * facing * side) * h * 0.06 if pose == Pose.WALK else 0.0
		foot = foot.lerp(hip + Vector2(side * w * 0.1, h * 0.22), tuck)
		var knee := _knee(hip, foot, h * 0.22)
		var leg := body.darkened(0.25 if side * facing < 0.0 else 0.1)
		draw_line(hip, knee, leg, w * 0.2)
		draw_line(knee, foot, leg, w * 0.17)
		draw_circle(knee, w * 0.11, leg.darkened(0.2))
		draw_rect(Rect2(foot + Vector2(-w * 0.22, -h * 0.03), Vector2(w * 0.44, h * 0.045)), leg.darkened(0.3))
		if pose == Pose.FLY or (pose == Pose.LAND and pose_time < LAND_TIME):
			var flame := h * 0.16 * (0.85 + 0.15 * sin(_time * 40.0 + side))
			var base := foot + Vector2(0.0, h * 0.015)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.15, 0.0), base + Vector2(w * 0.15, 0.0),
				base + Vector2(0.0, flame)]), Color(1.0, 0.6, 0.15))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.07, 0.0), base + Vector2(w * 0.07, 0.0),
				base + Vector2(0.0, flame * 0.6)]), Color(1.0, 0.92, 0.45))
	var shoulder_y := hip_y - h * 0.4
	# Le corps : un bloc, le cockpit (on voit le pilote), une petite tête avec une antenne
	var torso := Rect2(Vector2(-w * 0.5, hip_y - h * 0.5), Vector2(w, h * 0.52))
	draw_rect(torso, body)
	draw_rect(Rect2(torso.position.x, torso.position.y, w, h * 0.04), body.lightened(0.25))
	var cockpit := Rect2(Vector2(facing * w * 0.06 - w * 0.22, torso.position.y + h * 0.09), Vector2(w * 0.44, h * 0.15))
	draw_rect(cockpit, Color(0.1, 0.12, 0.17))
	var pilot := Vector2(w * 0.09, h * 0.11)
	draw_rect(Rect2(cockpit.get_center() - pilot / 2.0 + Vector2(0.0, h * 0.02), pilot), color.lightened(0.35))
	draw_rect(Rect2(Vector2(-w * 0.16, torso.position.y - h * 0.06), Vector2(w * 0.32, h * 0.06)), body.darkened(0.15))
	var antenna := Vector2(-facing * w * 0.1, torso.position.y - h * 0.06)
	draw_line(antenna, antenna + Vector2(0.0, -h * 0.08), body.darkened(0.3), 3.0)
	draw_circle(antenna + Vector2(0.0, -h * 0.08), 4.0, Color(1.0, 0.3, 0.3) if fmod(_time, 1.0) < 0.5 else body)
	_draw_wear(torso)
	# L'arme lourde, posée sur l'épaule de derrière (au-dessus du corps), puis la rafale sur celle de devant
	_draw_weapon(Vector2(-facing * w * 0.3, torso.position.y - h * 0.02), true, body)
	_draw_weapon(Vector2(facing * w * 0.5, shoulder_y), false, body)


## Le genou : entre la hanche et le pied, plié vers l'avant (deux os de longueur "bone").
func _knee(hip: Vector2, foot: Vector2, bone: float) -> Vector2:
	var mid := (hip + foot) / 2.0
	var half := hip.distance_to(foot) / 2.0
	var bend := sqrt(maxf(bone * bone - half * half, 0.0))
	var along := (foot - hip).normalized()
	var out := Vector2(-along.y, along.x)
	if out.x * facing < 0.0:
		out = -out
	return mid + out * bend


## Une arme d'épaule : la rafale (fine, deux canons) ou l'arme lourde (roquette : gros tube ;
## laser : tube fin et lumineux). Recul et éclair quand elle tire, lueur quand elle charge.
func _draw_weapon(shoulder: Vector2, heavy: bool, body: Color) -> void:
	var s := mecha_size()
	var dir := Vector2(facing, 0.0).rotated(aim * facing)
	var length := s.x * (0.75 if heavy else 0.65)
	var thick := s.y * (0.085 if heavy else 0.05)
	var firing := (pose == Pose.SHOOT and not heavy) or (pose == Pose.HEAVY and heavy and fmod(pose_time, 1.4) > 1.0)
	var cycle := fmod(pose_time, 0.25 if not heavy else 1.4) - (0.0 if not heavy else 1.0)
	var recoil := -dir * 10.0 * maxf(0.0, 1.0 - cycle * 10.0) if firing else Vector2.ZERO
	var base := shoulder + recoil
	var tip := base + dir * length
	var metal := body.darkened(0.45)
	draw_circle(shoulder, thick * 1.1, body.darkened(0.2))
	draw_line(base, tip, metal, thick)
	if heavy and heavy_weapon == "laser":
		draw_line(base + dir * length * 0.3, tip, Color(0.55, 0.85, 1.0), thick * 0.35)
	elif not heavy:
		var side := Vector2(-dir.y, dir.x) * thick * 0.9
		draw_line(base + side, tip + side - dir * length * 0.15, metal, thick * 0.6)
	if heavy and pose == Pose.HEAVY and fmod(pose_time, 1.4) <= 1.0:
		var charge := fmod(pose_time, 1.4)
		var glow := Color(0.55, 0.85, 1.0) if heavy_weapon == "laser" else Color(1.0, 0.6, 0.2)
		draw_circle(tip, thick * (0.4 + charge), Color(glow, 0.35 + 0.4 * charge))
	if firing and cycle < 0.07:
		draw_circle(tip + dir * thick, thick * 1.2, Color(1.0, 0.9, 0.5))


## L'usure : des fissures de plus en plus nombreuses, puis des étincelles et de la fumée.
func _draw_wear(torso: Rect2) -> void:
	var cracks := [
		[Vector2(0.15, 0.1), Vector2(0.3, 0.35), Vector2(0.22, 0.55)],
		[Vector2(0.85, 0.2), Vector2(0.7, 0.45), Vector2(0.8, 0.7)],
		[Vector2(0.3, 0.35), Vector2(0.5, 0.5), Vector2(0.45, 0.85)],
		[Vector2(0.7, 0.45), Vector2(0.55, 0.62), Vector2(0.62, 0.95)],
		[Vector2(0.1, 0.7), Vector2(0.3, 0.8), Vector2(0.25, 0.98)],
	]
	var shown := int(wear * cracks.size() + 0.001)
	for i in mini(shown, cracks.size()):
		var points := PackedVector2Array()
		for p: Vector2 in cracks[i]:
			points.append(torso.position + p * torso.size)
		draw_polyline(points, Color(0.95, 0.95, 1.0, 0.85), 2.5)
	if wear >= 0.75:
		for i in 3:
			var t := fmod(_time * 0.8 + i * 0.33, 1.0)
			var p := torso.position + Vector2(torso.size.x * (0.3 + 0.2 * i), -t * torso.size.y * 0.8)
			draw_circle(p, 8.0 + 14.0 * t, Color(0.45, 0.45, 0.5, 0.5 * (1.0 - t)))
		if fmod(_time, 0.4) < 0.1:
			var spark := torso.position + torso.size * Vector2(0.6, 0.5)
			for j in 4:
				var d := Vector2.RIGHT.rotated(j * 1.7 + _time)
				draw_line(spark, spark + d * 14.0, Color(1.0, 0.9, 0.4), 2.0)


## L'arrivée du ciel : une onde de choc au sol qui s'étend jusqu'à SHOCKWAVE_RADIUS.
func _draw_shockwave(t: float) -> void:
	if t > SHOCKWAVE_TIME:
		return
	var k := t / SHOCKWAVE_TIME
	draw_arc(Vector2.ZERO, SHOCKWAVE_RADIUS * k, PI, TAU, 48, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - k)), 8.0)
	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(Vector2(side * SHOCKWAVE_RADIUS * k - 30.0, -12.0), Vector2(60.0, 12.0)), Color(0.75, 0.75, 0.8, 0.6 * (1.0 - k)))


## L'explosion : une boule de feu, des morceaux du mecha qui volent, puis plus rien.
func _draw_explosion(w: float, h: float) -> void:
	var k := clampf(pose_time / EXPLODE_TIME, 0.0, 1.0)
	var center := Vector2(0.0, -h * 0.55)
	if k < 1.0:
		draw_circle(center, h * (0.2 + 0.6 * k), Color(1.0, 0.55, 0.15, 0.85 * (1.0 - k)))
		draw_circle(center, h * (0.1 + 0.35 * k), Color(1.0, 0.9, 0.5, 0.9 * (1.0 - k)))
		for i in 7:
			var d := Vector2.RIGHT.rotated(i * TAU / 7.0 + 0.4)
			var p := center + d * h * 0.9 * k + Vector2(0.0, h * 0.8 * k * k)
			draw_rect(Rect2(p - Vector2(w, h) * 0.08, Vector2(w, h) * 0.16), Color(color.darkened(0.4), 1.0 - k))
