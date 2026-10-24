class_name MechaVisual
extends Node2D
## Le dessin du mecha de la Ville (étape 4 du plan : son design, pas encore jouable).
## Le même mecha pour tout le monde, inspiré du Juggernaut de Command & Conquer 3 : une grosse coque
## blindée dans la couleur du joueur, posée sur deux jambes épaisses, avec une tourelle à TROIS
## canons sur le dos (l'arme lourde : roquettes ou laser) et une petite mitrailleuse sous le nez (la
## rafale). On voit le pilote dans la vitre du cockpit. Des réacteurs sous les pieds pour voler.
## Gros et lourd mais vif : des pas rapides, et chaque pied écrase le sol (le corps s'enfonce, poussière).
## Tout est dessiné avec des formes simples (une forme + une couleur par chose).
## La position du nœud est entre les deux pieds, au sol.

enum Pose { IDLE, WALK, FLY, SHOOT, HEAVY, WORN, LAND, EXPLODE }

const SIZE := Vector2(260, 330)       ## largeur de la coque, hauteur totale (pieds au sommet de la tourelle)
const LAND_TIME := 0.7                ## chute du ciel...
const SHOCKWAVE_TIME := 0.5           ## ... puis onde de choc
const SHOCKWAVE_RADIUS := 300.0
const EXPLODE_TIME := 1.2
const HEAVY_CYCLE := 1.6              ## pose « tir lourd » : charge 1 s puis les 3 canons tirent l'un après l'autre
const HEAVY_CHARGE := 1.0
const BARRELS := 3
const STEP_SPEED := 6.5              ## vitesse des pas (marche)

var stats: CharacterStats             ## le pilote (sa taille dans le cockpit)
var color := Color(0.95, 0.35, 0.35)
var pose := Pose.IDLE
var facing := 1.0                     ## 1 = regarde à droite
var aim := 0.0                        ## angle de visée des armes (0 = devant)
var wear := 0.0                       ## 0 = neuf, 1 = sur le point d'exploser
var pose_time := 0.0                  ## depuis quand on est dans cette pose
var heavy_weapon := "roquette"        ## "roquette" ou "laser"
var piloted := true                   ## false : mecha vide, cockpit sans pilote
var hover := true                     ## pose « vol » : dessiné au-dessus du sol (vitrine) ; en jeu, c'est le corps qui vole
var gun_shot_time := -1.0             ## en jeu : depuis quand la rafale a tiré sa dernière balle (-1 = rien)
var turret_charge := -1.0             ## en jeu : charge de la roquette, 0 à 1 (-1 = pas de charge)
var turret_shot_time := -1.0          ## en jeu : depuis quand une roquette est partie (-1 = rien)...
var turret_barrel := 1                ## ... et de quel canon (0, 1 ou 2)
var flames := true                    ## pose « vol » : réacteurs allumés (false : il retombe, jambes repliées)
var _time := 0.0


## Largeur et hauteur du mecha (pieds compris) : la même pour tous les pilotes.
func mecha_size() -> Vector2:
	return SIZE


func set_pose(value: Pose) -> void:
	pose = value
	pose_time = 0.0


func _process(delta: float) -> void:
	_time += delta
	pose_time += delta
	if gun_shot_time >= 0.0:
		gun_shot_time = -1.0 if gun_shot_time > 0.2 else gun_shot_time + delta
	if turret_shot_time >= 0.0:
		turret_shot_time = -1.0 if turret_shot_time > 0.4 else turret_shot_time + delta
	queue_redraw()


func _draw() -> void:
	var w := SIZE.x
	var h := SIZE.y
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
			stride = sin(_time * STEP_SPEED)
			# Juste après chaque pas, le corps s'enfonce d'un coup puis remonte : ça pèse lourd
			var since_step := fmod(_time * STEP_SPEED, PI) / PI
			bob = h * 0.04 * maxf(0.0, 1.0 - since_step * 4.0) - h * 0.015
			_draw_stomp(since_step, -signf(stride) * facing * w * 0.22)
		Pose.FLY:
			lift = (h * 0.35 if hover else 0.0) + sin(_time * 3.0) * h * 0.03
			tuck = 0.6
		Pose.LAND:
			var k := clampf(pose_time / LAND_TIME, 0.0, 1.0)
			lift = h * 4.0 * (1.0 - k * k)
			tuck = 0.4 * (1.0 - k)
			if pose_time >= LAND_TIME:
				_draw_shockwave(pose_time - LAND_TIME)
				bob = -h * 0.05 * maxf(0.0, 1.0 - (pose_time - LAND_TIME) * 5.0)  # s'écrase un peu
	var hip_y := -h * 0.4 - lift + bob
	var body := color.darkened(wear * 0.35)
	# Les jambes, épaisses (celle de derrière plus sombre), avec la flamme des réacteurs en vol
	for side: float in [-1.0, 1.0]:
		var phase := stride * side
		var hip := Vector2(side * w * 0.2, hip_y)
		var foot := Vector2(side * w * 0.22 + phase * w * 0.25 * facing, -lift + bob * 0.2)
		foot.y -= maxf(0.0, phase * facing * side) * h * 0.06 if pose == Pose.WALK else 0.0
		foot = foot.lerp(hip + Vector2(side * w * 0.08, h * 0.2), tuck)
		var knee := _knee(hip, foot, h * 0.22)
		var leg := body.darkened(0.3 if side * facing < 0.0 else 0.12)
		draw_line(hip, knee, leg, w * 0.2)
		draw_line(knee, foot, leg, w * 0.17)
		draw_circle(hip, w * 0.13, leg.darkened(0.15))
		draw_circle(knee, w * 0.11, leg.darkened(0.25))
		# Le pied : large et plat, un orteil devant
		draw_rect(Rect2(foot + Vector2(-w * 0.13, -h * 0.04), Vector2(w * 0.26, h * 0.04)), leg.darkened(0.35))
		draw_colored_polygon(PackedVector2Array([foot + Vector2(facing * w * 0.13, -h * 0.04),
			foot + Vector2(facing * w * 0.2, 0.0), foot + Vector2(facing * w * 0.13, 0.0)]), leg.darkened(0.35))
		if (pose == Pose.FLY and flames) or (pose == Pose.LAND and pose_time < LAND_TIME):
			var flame := h * 0.16 * (0.85 + 0.15 * sin(_time * 40.0 + side))
			var base := foot + Vector2(0.0, h * 0.01)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.1, 0.0), base + Vector2(w * 0.1, 0.0),
				base + Vector2(0.0, flame)]), Color(1.0, 0.6, 0.15))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.05, 0.0), base + Vector2(w * 0.05, 0.0),
				base + Vector2(0.0, flame * 0.6)]), Color(1.0, 0.92, 0.45))
	# La coque : un gros bloc blindé, l'avant en pente (comme le Juggernaut)
	var hull := Rect2(Vector2(-w * 0.5, hip_y - h * 0.34), Vector2(w, h * 0.38))
	var f := facing
	var top := hull.position.y
	var bottom := hull.end.y
	draw_colored_polygon(PackedVector2Array([
		Vector2(-f * w * 0.5, top), Vector2(f * w * 0.28, top), Vector2(f * w * 0.5, top + h * 0.14),
		Vector2(f * w * 0.42, bottom), Vector2(-f * w * 0.46, bottom)]), body)
	draw_rect(Rect2(Vector2(-w * 0.5 if f > 0.0 else -w * 0.28, top), Vector2(w * 0.78, h * 0.03)), body.lightened(0.25))
	draw_rect(Rect2(Vector2(-w * 0.46, bottom - h * 0.05), Vector2(w * 0.88, h * 0.05)), body.darkened(0.25))
	# Le cockpit : une vitre à l'avant de la pente, on y voit le pilote (à sa taille)
	var glass := Rect2(Vector2(f * w * 0.24 - w * 0.13, top + h * 0.07), Vector2(w * 0.26, h * 0.13))
	draw_rect(glass, Color(0.1, 0.12, 0.17))
	var pilot := (stats.body_size if stats != null else Vector2(20, 60)) * 0.42
	if piloted:
		draw_rect(Rect2(Vector2(glass.get_center().x - pilot.x / 2.0, glass.end.y - pilot.y), pilot), color.lightened(0.35))
	draw_rect(Rect2(glass.position, Vector2(glass.size.x, h * 0.02)), Color(0.55, 0.75, 0.95, 0.5))
	_draw_wear(hull)
	# La mitrailleuse sous le nez, puis la tourelle à trois canons sur le dos
	_draw_chin_gun(Vector2(f * w * 0.36, bottom - h * 0.02), body)
	_draw_turret(Vector2(-f * w * 0.12, top), body)


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


## La direction des armes (devant le mecha, tournée de "aim").
func _aim_dir() -> Vector2:
	return Vector2(facing, 0.0).rotated(aim * facing)


## La rafale : une petite mitrailleuse à deux canons sous le nez, qui recule et crache à chaque tir.
func _draw_chin_gun(mount: Vector2, body: Color) -> void:
	var dir := _aim_dir()
	var length := SIZE.x * 0.38
	var thick := SIZE.y * 0.045
	var firing := pose == Pose.SHOOT or gun_shot_time >= 0.0
	var cycle := fmod(pose_time, 0.2) if pose == Pose.SHOOT else gun_shot_time
	var base := mount - (dir * 8.0 * maxf(0.0, 1.0 - cycle * 10.0) if firing else Vector2.ZERO)
	var side := Vector2(-dir.y, dir.x) * thick * 0.8
	var metal := body.darkened(0.5)
	draw_circle(mount, thick * 1.5, body.darkened(0.3))
	draw_line(base - side, base - side + dir * length, metal, thick * 0.7)
	draw_line(base + side, base + side + dir * length * 0.9, metal, thick * 0.7)
	if firing and cycle < 0.06:
		draw_circle(base + dir * (length + thick), thick * 1.4, Color(1.0, 0.9, 0.5))


## L'arme lourde : une tourelle sur le dos, avec TROIS gros canons l'un au-dessus de l'autre.
## Roquettes : bouches larges ; laser : un cœur bleu lumineux dans chaque canon. En pose « tir lourd »,
## les canons chargent (lueur) puis tirent l'un après l'autre, chacun avec son recul.
func _draw_turret(base: Vector2, body: Color) -> void:
	var w := SIZE.x
	var h := SIZE.y
	var dir := _aim_dir()
	var up := Vector2(dir.y, -dir.x) * facing   # perpendiculaire, vers le haut
	var turret := Rect2(base + Vector2(-w * 0.26, -h * 0.16), Vector2(w * 0.52, h * 0.16))
	draw_rect(turret, body.darkened(0.12))
	draw_rect(Rect2(turret.position, Vector2(turret.size.x, h * 0.025)), body.lightened(0.2))
	var pivot := turret.get_center() + Vector2(facing * w * 0.12, 0.0)
	var laser := heavy_weapon == "laser"
	var glow := Color(0.55, 0.85, 1.0) if laser else Color(1.0, 0.6, 0.2)
	var length := w * 0.7
	var thick := h * 0.05
	var t := fmod(pose_time, HEAVY_CYCLE)
	var charge := t / HEAVY_CHARGE if pose == Pose.HEAVY else turret_charge
	var charging := (pose == Pose.HEAVY and t < HEAVY_CHARGE) or turret_charge >= 0.0
	for i in BARRELS:
		var offset := up * thick * 1.15 * (i - 1)
		var shot_t := t - HEAVY_CHARGE - i * 0.12   # vitrine : chaque canon tire 0.12 s après le précédent
		if pose != Pose.HEAVY:
			shot_t = turret_shot_time if i == turret_barrel else -1.0  # en jeu : le canon qui vient de tirer
		var recoil := 12.0 * maxf(0.0, 1.0 - shot_t * 6.0) if shot_t >= 0.0 else 0.0
		var start := pivot + offset - dir * recoil
		var tip := start + dir * length
		draw_line(start, tip, body.darkened(0.5), thick)
		if laser:
			draw_line(start + dir * length * 0.35, tip, glow, thick * 0.35)
		else:
			draw_line(tip - dir * thick * 1.2, tip, body.darkened(0.6), thick * 1.35)   # la bouche
		if charging:
			draw_circle(tip, thick * (0.3 + 0.7 * charge), Color(glow, 0.35 + 0.4 * charge))
		if shot_t >= 0.0 and shot_t < 0.08:
			draw_circle(tip + dir * thick, thick * 1.8, Color(1.0, 0.9, 0.5) if not laser else glow.lightened(0.4))
	draw_circle(pivot, h * 0.08, body.darkened(0.3))
	# L'antenne à l'arrière de la tourelle
	var antenna := Vector2(turret.get_center().x - facing * w * 0.16, turret.position.y)
	draw_line(antenna, antenna + Vector2(0.0, -h * 0.08), body.darkened(0.3), 3.0)
	draw_circle(antenna + Vector2(0.0, -h * 0.08), 4.0, Color(1.0, 0.3, 0.3) if fmod(_time, 1.0) < 0.5 else body)


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


## La poussière d'un pas qui écrase le sol, sous le pied qui vient de se poser (x).
func _draw_stomp(k: float, x: float) -> void:
	if k > 0.35:
		return
	var t := k / 0.35
	for side: float in [-1.0, 1.0]:
		draw_circle(Vector2(x + side * SIZE.x * (0.1 + 0.15 * t), -6.0), 6.0 + 14.0 * t, Color(0.75, 0.75, 0.8, 0.55 * (1.0 - t)))


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
