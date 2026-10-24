extends Node
## Test automatique : lance la partie avec des commandes simulées et vérifie les règles.

class Scripted extends InputSource:
	var fn: Callable
	var frame := 0
	func _init(f: Callable) -> void:
		fn = f
	func poll() -> InputState:
		var s := InputState.new()
		fn.call(s, frame)
		frame += 1
		return s

var game: Node
var base := CharacterStats.new()  ## les stats par défaut (la Barre)
## Une attaque légère qui touche tout de suite, de toute sa longueur (préparation finie, barre déployée)
var light_hit_time := base.attack_startup + Fighter.LIGHT_DEPLOY_TIME
## Frames entre l'appui sur X et le moment où le coup léger touche au plus loin
var light_frames := int(ceil(light_hit_time * 60.0)) + 1
var shot_dir := ""
var failures := 0

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1

## Touché : sonné ou une vie en moins.
func touched(f: Fighter) -> bool:
	return f.is_stunned() or f.lives < f.max_lives

func untouched(f: Fighter) -> bool:
	return not touched(f)

## Une attaque légère qui touche tout de suite, de toute sa longueur, dans cette direction.
func light_now(f: Fighter, dir: Vector2) -> void:
	f._attack_heavy = false
	f._attack_has_hit = false
	f._attack_dir = dir
	f._attack_time = f.stats.light_startup() + Fighter.LIGHT_DEPLOY_TIME
	f._attack_cooldown_timer = 0.0

func new_game() -> void:
	if game:
		game.queue_free()
		await get_tree().process_frame
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func step(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func shot(name: String) -> void:
	if shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir + "/" + name + ".png")

func _ready() -> void:
	shot_dir = OS.get_environment("SHOT_DIR")
	var p1: Fighter
	var p2: Fighter

	# 1) Les joueurs atterrissent sur le sol
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(60)
	check(p1.is_on_floor() and absf(p1.position.y - (570 - 30)) < 3, "J1 au sol (y=%.1f)" % p1.position.y)
	await shot("01_debut")

	# 2) J1 marche vers J2 et attaque : J2 perd une vie
	p1.position.x = 700; p2.position.x = 880
	p1.input_source = Scripted.new(func(s, f):
		s.stick.x = 1.0 if f < 15 else 0.0
		s.attack_pressed = f == 60)
	await step(63)
	await shot("02_attaque")
	await step(10)
	check(touched(p2), "J2 touché, vies = %d" % p2.lives)
	check(p2.is_invincible(), "J2 invincible après le coup")
	check(not p2.can_attack(), "J2 ne peut pas attaquer pendant l'invincibilité")

	# 3) Attaque de loin = dans le vide
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 60)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(80)
	check(untouched(p2), "Attaque de loin rate, J2 vies = %d" % p2.lives)

	# 3b) Toute la barre de l'attaque légère touche : même collé à l'adversaire, le coup porte
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	await step(25)
	p1.position.x = 640; p2.position.x = 652
	await step(5 + light_frames)
	check(touched(p2), "Attaque légère collé à l'adversaire : touché (vies = %d)" % p2.lives)

	# 3c) Portée : le bout de la barre touche, juste au-delà ça rate
	for gap in [base.attack_reach + base.body_size.x / 2.0 - 4.0, base.attack_reach + base.body_size.x / 2.0 + 6.0]:
		await new_game()
		p1 = game.fighters[0]; p2 = game.fighters[1]
		p2.input_source = Scripted.new(func(s, f): pass)
		p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
		await step(25)
		p1.position.x = 600; p2.position.x = 600 + gap
		p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
		await step(5 + light_frames)
		var reached: bool = gap < base.attack_reach + base.body_size.x / 2.0
		check((touched(p2)) == reached, "Portée de l'attaque légère : à %.0f px %s (vies = %d)" % [gap, "touche" if reached else "rate", p2.lives])

	# 4) Choc d'attaques : personne ne perd de vie
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 590; p2.position.x = 690
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	await step(30 + light_frames + 8)
	check(untouched(p1) and untouched(p2), "Choc : vies %d / %d" % [p1.lives, p2.lives])
	check(p1.position.x < 570 and p2.position.x > 710, "Choc : les deux repoussés (x = %.0f / %.0f)" % [p1.position.x, p2.position.x])
	check(p1.can_attack(), "Choc : J1 peut ré-attaquer vite")
	check(game.gauge.points == 1, "Choc : la jauge de contre monte d'un cran (%.0f)" % game.gauge.points)
	var marks := game.get_children().filter(func(n): return n is ClashMark)
	check(marks.size() == 1, "Choc : une marque apparaît sur le terrain (%d)" % marks.size())
	await shot("09_marque_contre")
	await step(200)
	marks = game.get_children().filter(func(n): return n is ClashMark)
	check(marks.is_empty(), "Choc : la marque s'est effacée après quelques secondes")

	# 4b) Attaque lourde : l'arc touche un adversaire proche, devant soi
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(42)
	await shot("08_lourde")
	await step(10)
	check(touched(p2), "Attaque lourde : J2 touché (vies = %d)" % p2.lives)

	# 4c) Attaque lourde contrée par une légère : personne touché, 1 s sans frapper pour celui qui a lancé
	# la lourde, celui qui contre peut refrapper tout de suite, et les deux sont repoussés loin
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 690
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 42)
	var clash_seen := false
	for i in 60:
		await step(1)
		if not game.get_children().filter(func(n): return n is ClashMark).is_empty():
			clash_seen = true
			break
	check(clash_seen and absf(p1._attack_cooldown_timer - Fighter.HEAVY_COUNTERED_COOLDOWN) < 0.05,
		"Contre : J1 qui a lancé la lourde ne frappe plus pendant 1 s (%.2f s)" % p1._attack_cooldown_timer)
	check(p2.can_attack(), "Contre : J2 qui a contré peut refrapper tout de suite (%.2f s)" % p2._attack_cooldown_timer)
	check(untouched(p1) and untouched(p2), "Contre : personne ne perd de vie (%d / %d)" % [p1.lives, p2.lives])
	check(game.gauge.points == CounterGauge.HEAVY_COUNTER_POINTS,
		"Contre d'une lourde : compte pour 3 contres dans la jauge (%.0f)" % game.gauge.points)
	check(Engine.time_scale < 0.6, "Micro-duel : le temps ralentit (vitesse %.2f)" % Engine.time_scale)
	var gap_before := p2.position.x - p1.position.x
	for i in 90:
		await get_tree().process_frame
	var duel_zoom: float = game.get_node("Camera").zoom.x
	check(duel_zoom > Game.CAMERA_ZOOM_MAX, "Micro-duel : la caméra zoome (zoom %.2f)" % duel_zoom)
	await shot("12_micro_duel")
	var gap_after := p2.position.x - p1.position.x
	check(gap_after - gap_before > 150, "Contre : les deux sont repoussés loin (écart %.0f -> %.0f)" % [gap_before, gap_after])
	check(Engine.time_scale < 0.6, "Micro-duel : toujours au ralenti après 1,5 s")
	await step(int(Game.DUEL_DURATION * 60) - 60)
	check(is_equal_approx(Engine.time_scale, 1.0), "Micro-duel : le temps revient à la normale après 5 s (vitesse %.2f)" % Engine.time_scale)

	# 4c bis) Lourde contre lourde : micro-explosion, les deux éjectés fort, personne ne perd de vie
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 690
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	var boom_seen := false
	for i in 50:
		await step(1)
		if not game.get_children().filter(func(n): return n is MicroExplosion).is_empty():
			boom_seen = true
			break
	check(boom_seen, "Lourde contre lourde : micro-explosion")
	await shot("13_micro_explosion")
	var boom_gap := p2.position.x - p1.position.x
	await step(20)
	check(p2.position.x - p1.position.x - boom_gap > 250, "Lourde contre lourde : éjectés fort (écart %.0f -> %.0f)" % [boom_gap, p2.position.x - p1.position.x])
	check(untouched(p1) and untouched(p2), "Lourde contre lourde : personne ne perd de vie")
	check(is_equal_approx(Engine.time_scale, 1.0), "Lourde contre lourde : pas de ralenti")

	# 4d) Blocage : le coup tombe sur le bouclier, personne ne perd de vie, l'attaquant peut refrapper
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(29)
	check(p2.is_blocking(), "Blocage : J2 bloque en tenant B")
	await step(1 + light_frames)
	await shot("09_blocage")
	check(untouched(p2), "Blocage : J2 ne perd pas de vie (vies = %d)" % p2.lives)
	check(p2.shield == base.shield_max - 1, "Blocage : le bouclier craque d'un cran (reste %d / %d)" % [p2.shield, base.shield_max])
	check(p1.can_attack(), "Blocage : J1 peut refrapper tout de suite")
	await step(10)
	check(p1.position.x < 590, "Blocage : J1 est repoussé (x = %.0f)" % p1.position.x)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(int(Fighter.SHIELD_REGEN_TIME * 60) + 5)
	check(p2.shield == base.shield_max, "Bouclier : il se répare quand on ne bloque pas (%d)" % p2.shield)

	# 4d bis) Blocage parfait : B appuyé juste avant le coup = contre. Pas de vie perdue, le bouclier
	# ne craque pas, l'attaquant ne frappe plus pendant 1 s et le défenseur peut riposter
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= 29 and f < 45)
	await step(31 + light_frames)
	check(untouched(p2) and p2.shield == base.shield_max,
		"Blocage parfait : pas de vie perdue, bouclier intact (vies %d, bouclier %d)" % [p2.lives, p2.shield])
	check(not p1.can_attack() and p1._attack_cooldown_timer > Fighter.PARRY_COOLDOWN - 0.1,
		"Blocage parfait : J1 ne peut plus frapper pendant 1 s (%.2f s)" % p1._attack_cooldown_timer)
	check(p2._attack_cooldown_timer <= 0.0, "Blocage parfait : J2 peut riposter tout de suite")
	check(game.gauge.points == 1, "Blocage parfait : la jauge de contre monte")
	marks = game.get_children().filter(func(n): return n is ClashMark and n.color == Game.PARRY_COLOR)
	check(marks.size() == 1, "Blocage parfait : une marque bleue apparaît")
	await step(10)
	check(p1.position.x < 590 and p2.position.x > 660, "Blocage parfait : les deux sont repoussés (x = %.0f / %.0f)" % [p1.position.x, p2.position.x])
	# Bloquer trop tôt : ce n'est plus un blocage parfait, le bouclier encaisse normalement
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= 10)
	await step(31 + light_frames)
	check(p2.shield == base.shield_max - 1 and p1.can_attack(),
		"Blocage trop tôt : simple blocage (bouclier %d, J1 peut refrapper)" % p2.shield)

	# 4d ter) Pendant un ralenti, chaque contre le fait repartir pour toute sa durée
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	game._clash(p1, p2, p1.position)
	check(not game._time_engine.is_active(), "Ralenti : un contre sans ralenti en cours n'en lance pas")
	game._time_engine.play(Game.DUEL_TIME_SCALE, Game.DUEL_DURATION)
	game._time_engine._time_left = 0.3  # le ralenti allait se terminer...
	game._clash(p1, p2, p1.position)     # ... un contre (légère contre légère) le relance
	check(is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION) and is_equal_approx(Engine.time_scale, Game.DUEL_TIME_SCALE),
		"Ralenti : un contre le relance pour toute sa durée (%.1f s, vitesse %.2f)" % [game._time_engine._time_left, Engine.time_scale])
	game._time_engine._time_left = 0.3
	game._parry(p1, p2)
	check(is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION), "Ralenti : un blocage parfait le relance aussi")
	game._time_engine.stop(true)

	# 4d2) Il faut 20 attaques légères pour casser le bouclier
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(20)  # J2 bloque depuis un moment : ce ne sont pas des blocages parfaits
	var shield_hits := 0
	while not p2.shield_broken and shield_hits < 40:
		p1.position = Vector2(p2.position.x - 50, p2.position.y); p1.velocity = Vector2.ZERO
		p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
		await step(2 + light_frames)
		p1._attack_cooldown_timer = 0.0  # on ne teste pas la recharge ici
		shield_hits += 1
		if shield_hits == 12:
			await shot("09_blocage_fissure")
	check(shield_hits == 20, "Bouclier : cassé au bout de %d attaques légères" % shield_hits)

	# 4e) Attaque lourde sur le bouclier : compte pour 2 coups, et casser le bouclier : ralenti, éjection, 2 s sans frapper
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f):
		s.block_held = f < 80
		s.stick.x = 1.0 if f >= 80 else 0.0
		s.attack_pressed = f == 85)
	await step(55)
	check(p2.shield == base.shield_max - 2 and untouched(p2), "Lourde sur bouclier : compte pour 2 coups (reste %d, vies %d)" % [p2.shield, p2.lives])
	p2.shield = 1
	p1.position.x = p2.position.x - 50; p1.velocity = Vector2.ZERO
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 2)
	var shield_gap := p2.position.x - p1.position.x
	await step(2 + light_frames)
	check(p2.shield_broken and not p2.is_blocking(), "Bouclier cassé : J2 ne bloque plus")
	await shot("09_bouclier_casse")
	check(Engine.time_scale < 0.5, "Bouclier cassé : ralenti (vitesse x%.2f)" % Engine.time_scale)
	check(p2._attack_cooldown_timer > 1.5, "Bouclier cassé : J2 ne peut pas attaquer (%.2f s)" % p2._attack_cooldown_timer)
	check(p1.can_attack(), "Bouclier cassé : J1 peut attaquer")
	await step(20)
	check(p2.position.x - p1.position.x > shield_gap + 150, "Bouclier cassé : les deux sont éjectés (écart %.0f -> %.0f)" % [shield_gap, p2.position.x - p1.position.x])
	var x_before := p2.position.x
	await step(6)
	check(not p2.is_attacking(), "Bouclier cassé : J2 appuie sur X mais n'attaque pas")
	await step(40)
	check(p2.position.x > x_before + 50, "Bouclier cassé : J2 peut toujours bouger")
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(int(Fighter.SHIELD_REGEN_TIME * 60) * 3)
	check(p2.shield_broken and p2.shield == 0 and not p2.is_blocking(), "Bouclier cassé : il ne revient pas (plus de blocage)")
	check(is_equal_approx(Engine.time_scale, 1.0), "Bouclier cassé : le temps revient à la normale")

	# 4f) En bloquant : déplacement lent, petit saut, pas de dash, pas d'attaque
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f):
		s.block_held = true
		s.stick.x = 1.0 if f >= 40 and f < 70 else 0.0
		s.dash_pressed = f == 72
		s.attack_pressed = f == 70
		s.jump_pressed = f == 80
		s.jump_held = f >= 80)
	await step(65)
	check(absf(p1.velocity.x) <= base.run_speed * Fighter.BLOCK_SPEED_MULT + 1, "Blocage : marche lente (vx = %.0f)" % p1.velocity.x)
	await step(9)
	check(not p1.is_dashing(), "Blocage : pas de dash")
	check(not p1.is_attacking(), "Blocage : pas d'attaque")
	var start_y := p1.position.y
	var top_y := start_y
	for i in 40:
		await step(1)
		top_y = minf(top_y, p1.position.y)
	var jump_height := start_y - top_y
	check(jump_height > 30 and jump_height < 100, "Blocage : saut moins haut (%.0f px)" % jump_height)

	# 4g) Attaque rapide : touche à 90 px
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 690
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(31 + light_frames)
	check(touched(p2), "Attaque rapide : touche à 90 px (vies = %d)" % p2.lives)

	# 4h) Attaque lourde non chargée : trop courte à 130 px
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 730
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(60)
	check(untouched(p2), "Lourde sans charge : rate à 130 px (vies = %d)" % p2.lives)

	# 4i) Attaque lourde chargée : l'arme grandit, touche à 130 px, et le perso est immobile pendant la frappe
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 730
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 30
		s.heavy_held = f >= 30 and f < 200
		s.stick.x = -1.0 if f >= 88 else 0.0)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(80)
	check(p1.is_charging_heavy() and p1.heavy_scale() > 1.5, "Lourde chargée : l'arme grandit (taille x%.2f)" % p1.heavy_scale())
	await shot("10_charge")
	var swing_frames := 0
	var swing_moved := 0.0
	for i in 40:
		var x_before_frame := p1.position.x
		await step(1)
		if p1.is_heavy_swinging():
			swing_frames += 1
			swing_moved += absf(p1.position.x - x_before_frame)
	check(swing_frames > 5, "Lourde chargée : la frappe part toute seule à pleine charge (%d frames)" % swing_frames)
	check(swing_moved < 1.0, "Lourde chargée : immobile pendant la frappe (bougé de %.1f px)" % swing_moved)
	check(touched(p2), "Lourde chargée : touche à 130 px (vies = %d)" % p2.lives)

	# 4j) Plateforme mobile : le joueur posé dessus est transporté
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	var shuttle: Node2D = game.map.get_node("ZoneDuel/NavetteHaute")
	p1.position = shuttle.position + Vector2(0, -45)
	await step(20)
	var rider_x := p1.position.x
	var shuttle_x := shuttle.position.x
	await step(60)
	var shuttle_moved := shuttle.position.x - shuttle_x
	check(p1.is_on_floor() and shuttle_moved > 50 and absf((p1.position.x - rider_x) - shuttle_moved) < 6,
		"Plateforme mobile : J1 est transporté (plateforme %.0f px, J1 %.0f px)" % [shuttle_moved, p1.position.x - rider_x])

	# 4k) Course : plus rapide, vide l'endurance (plus vite en bloquant), puis la jauge remonte
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 100
	p1.input_source = Scripted.new(func(s, f):
		s.stick.x = 1.0 if f >= 20 and f < 80 else 0.0
		s.sprint_held = f >= 20 and f < 80)
	await step(50)
	check(p1.is_sprinting() and p1.velocity.x > base.run_speed * 1.3, "Course : J1 va plus vite (vx = %.0f)" % p1.velocity.x)
	await shot("11_course")
	var stamina_sprint := base.stamina_max - p1.stamina
	await step(30)
	check(p1.stamina < base.stamina_max - 20, "Course : l'endurance baisse (%.0f)" % p1.stamina)
	var low := p1.stamina
	await step(90)
	check(p1.stamina > low + 10, "Course : l'endurance remonte quand on s'arrête (%.0f)" % p1.stamina)

	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.block_held = f >= 20 and f < 50
		s.sprint_held = f >= 20 and f < 50)
	await step(50)
	var stamina_block := base.stamina_max - p1.stamina
	check(stamina_block > stamina_sprint * 1.5, "Course + blocage : l'endurance baisse plus vite (%.0f contre %.0f)" % [stamina_block, stamina_sprint])

	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 100
	p1.input_source = Scripted.new(func(s, f):
		s.stick.x = 1.0 if f < 400 else 0.0
		s.sprint_held = true)
	p1.stamina = 5.0
	await step(30)
	check(not p1.is_sprinting() and absf(p1.velocity.x) <= base.run_speed + 1, "Endurance vide : J1 ne court plus (vx = %.0f)" % p1.velocity.x)

	# 5) Dash = intouchable
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 680
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f):
		s.stick = Vector2(0, -1)
		s.dash_pressed = f == 29)
	await step(36)
	check(untouched(p2), "Pendant le dash J2 n'est pas touché (vies = %d)" % p2.lives)

	# 6) Saut + double saut + dash vers le haut jusqu'à la plateforme du haut
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 640
	p1.input_source = Scripted.new(func(s, f):
		s.jump_pressed = f == 30 or f == 48
		s.jump_held = f >= 30 and f < 70
		if f >= 62 and f < 64:
			s.stick = Vector2(0, -1)
		s.dash_pressed = f == 62)
	p2.input_source = Scripted.new(func(s, f): pass)
	var min_y := 1000.0
	for i in 140:
		await step(1)
		min_y = minf(min_y, p1.position.y)
		if i == 70:
			await shot("03_triple_saut")
	check(p1.is_on_floor() and absf(p1.position.y - (282 - 30)) < 3, "Arrivé sur la plateforme du haut (y=%.1f, plus haut=%.1f)" % [p1.position.y, min_y])

	# 7) Descendre avec bas
	p1.input_source = Scripted.new(func(s, f):
		s.stick.y = 1.0 if f < 3 else 0.0
		s.down_pressed = f == 0)
	await step(40)
	check(p1.is_on_floor() and absf(p1.position.y - (432 - 30)) < 3, "Descendu sur la plateforme du milieu (y=%.1f)" % p1.position.y)

	# 7a) Descendre avec le stick en diagonale (pas tout en bas)
	p1.input_source = Scripted.new(func(s, f):
		s.stick = Vector2(0.9, 0.4) if f < 3 else Vector2.ZERO)
	await step(40)
	check(p1.position.y > 432 + 20, "Descendu de la plateforme avec le stick en diagonale (y=%.1f)" % p1.position.y)

	# 7b) Mur : on glisse lentement, sauts et dash rechargés, le saut mural éjecte du mur
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position = Vector2(-40, 330)
	p1.input_source = Scripted.new(func(s, f): s.stick.x = -1.0)
	await step(2)
	p1._air_jumps_left = 0
	p1._air_dashes_left = 0
	await step(40)
	check(p1.is_wall_sliding(), "Mur : J1 glisse contre le mur gauche")
	check(p1.velocity.y <= base.wall_slide_speed + 1, "Mur : glissade lente (vy=%.0f)" % p1.velocity.y)
	check(p1._air_jumps_left == 2 and p1._air_dashes_left == 1, "Mur : 2 sauts et le dash rechargés")
	await shot("07_mur")
	p1.input_source = Scripted.new(func(s, f):
		s.stick.x = -1.0
		s.jump_pressed = f == 0
		s.jump_held = f < 15)
	await step(6)
	check(p1.velocity.x > 0 and p1.velocity.y < 0, "Mur : saut mural vers la droite (v=%s)" % p1.velocity)
	check(p1._air_jumps_left == 1, "Mur : il reste 1 saut après le saut mural")

	# 8) Tomber de la map coûte une vie, puis réapparition au milieu ; 3 chutes = fin
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): s.stick.x = -1.0 if not p1.is_invincible() else 0.0)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(150)
	check(p1.lives < 3, "Chute : J1 a perdu une vie (vies = %d)" % p1.lives)
	await step(600)
	check(p1.eliminated and game._match_over, "J1 éliminé après 3 chutes, partie finie")
	await shot("04_fin")

	# 9) La caméra dézoome quand les joueurs s'éloignent, zoome quand ils se rapprochent
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 300; p2.position.x = 980
	for i in 120:
		await get_tree().process_frame
	var far_zoom: float = game.get_node("Camera").zoom.x
	p1.position.x = 600; p2.position.x = 680
	for i in 120:
		await get_tree().process_frame
	var near_zoom: float = game.get_node("Camera").zoom.x
	check(near_zoom > far_zoom, "Caméra : zoom loin %.2f < zoom proche %.2f" % [far_zoom, near_zoom])
	var cam_x: float = game.get_node("Camera").position.x
	check(absf(cam_x - 640) < 10, "Caméra centrée entre les joueurs (x=%.0f)" % cam_x)
	await shot("05_camera_proche")

	# 9b) Manette : la course est sur LT, le dash sur LB
	InputBindings.register_player(3, [{"type": "joypad", "id": 7}])
	var sprint_on_lt := false
	for event in InputMap.action_get_events("p4_sprint"):
		if event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_LEFT:
			sprint_on_lt = true
	var dash_on_lb := false
	for event in InputMap.action_get_events("p4_dash"):
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			dash_on_lb = true
	check(sprint_on_lt and dash_on_lb, "Manette : course sur LT, dash sur LB")
	InputBindings.fix_web_triggers(true)
	check(InputBindings._web_triggers_fixed, "Navigateur : correctif des gâchettes LT / RT chargé")

	# 9c) Deux coups qui touchent en même temps (sans se croiser) : choc, personne ne perd de vie
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	p1.position.x = 600; p2.position.x = 660
	for pair in [[p1, Vector2.RIGHT], [p2, Vector2.LEFT]]:
		var fi: Fighter = pair[0]
		fi._attack_heavy = false
		fi._attack_has_hit = false
		fi._attack_dir = pair[1]
		fi._attack_time = light_hit_time
		fi._attack_cooldown_timer = base.attack_cooldown
	await step(1)
	check(untouched(p1) and untouched(p2), "Coups simultanés : annulés, personne ne perd de vie (J1 %d, J2 %d)" % [p1.lives, p2.lives])
	await step(5)
	check(not p1.is_attacking() and not p2.is_attacking() and p1.position.x < 600 and p2.position.x > 660,
		"Coups simultanés : les deux attaques s'arrêtent et les joueurs sont repoussés")

	# 9c bis) Un coup léger repousse nettement la victime
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	p1.position.x = 600; p2.position.x = 680
	p1._attack_heavy = false
	p1._attack_has_hit = false
	p1._attack_dir = Vector2.RIGHT
	p1._attack_time = light_hit_time
	await step(60)
	check(touched(p2) and absf(p2.position.x - 680 - 100) < 8, "Coup léger : J2 repoussé de %.0f px (visé : 100)" % (p2.position.x - 680))

	# 9c ter) À 3 joueurs : J1 touche J2 pendant que J2 touche J3 -> J2 et J3 perdent une vie (l'ordre ne compte pas)
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
	await new_game()
	GameSetup.player_devices = []
	var f3: Array = game.fighters
	for fi in f3:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	f3[0].position = Vector2(500, 540); f3[1].position = Vector2(560, 540); f3[2].position = Vector2(620, 540)
	for k in 2:
		var fi: Fighter = f3[k]
		fi._attack_heavy = false
		fi._attack_has_hit = false
		fi._attack_dir = Vector2.RIGHT
		fi._attack_time = light_hit_time
	await step(1)
	check(untouched(f3[0]) and touched(f3[1]) and touched(f3[2]),
		"3 joueurs : coups en chaîne tous comptés (J1 %d, J2 %d, J3 %d)" % [f3[0].lives, f3[1].lives, f3[2].lives])

	# 9g) Personnages : chacun peut avoir ses propres stats (vitesse, poids...)
	var slow := CharacterStats.new()
	slow.display_name = "Test lent"
	slow.run_speed = 300.0
	slow.weight = 2.0
	ResourceSaver.save(slow, "user://perso_test.tres")
	GameSetup.player_characters = ["", "user://perso_test.tres"]
	await new_game()
	GameSetup.player_characters = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	check(p1.stats.display_name == "Barre" and p2.stats.display_name == "Test lent",
		"Persos : J1 = %s, J2 = %s" % [p1.stats.display_name, p2.stats.display_name])
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): s.stick.x = -1.0 if f >= 40 else 0.0)
	await step(60)
	check(absf(absf(p2.velocity.x) - 300.0) < 5.0, "Persos : J2 court à sa propre vitesse (vx = %.0f)" % p2.velocity.x)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(600, 540); p2.position = Vector2(680, 540)
	p2._invincible_timer = 0.0
	p1._attack_heavy = false
	p1._attack_has_hit = false
	p1._attack_dir = Vector2.RIGHT
	p1._attack_time = light_hit_time
	await step(60)
	check(touched(p2) and p2.position.x - 680 < 70, "Persos : J2, 2 fois plus lourd, recule moins (%.0f px)" % (p2.position.x - 680))
	check(game.map is GameMap and game.map.map_name == "Arène", "Map : chargée depuis scenes/maps/ (%s)" % game.map.map_name)
	p1.clash(Vector2.LEFT * Fighter.CLASH_PUSH)
	p2.clash(Vector2.RIGHT * Fighter.CLASH_PUSH)
	check(absf(p1.velocity.x + Fighter.CLASH_PUSH) < 1.0 and absf(p2.velocity.x - Fighter.CLASH_PUSH / 2.0) < 1.0,
		"Persos : le poids compte aussi dans les chocs (J1 %.0f, J2 2 fois plus lourd %.0f)" % [p1.velocity.x, p2.velocity.x])

	# 9g bis) Un grand perso apparaît posé sur le sol (les points d'apparition marquent les pieds)
	var tall := CharacterStats.new()
	tall.display_name = "Test grand"
	tall.body_size = Vector2(40, 140)
	ResourceSaver.save(tall, "user://perso_grand.tres")
	GameSetup.player_characters = ["user://perso_grand.tres", ""]
	await new_game()
	GameSetup.player_characters = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(60)
	check(p1.is_on_floor() and absf(p1.position.y - (570 - 70)) < 3 and untouched(p1),
		"Persos : un perso de 140 px de haut apparaît posé sur le sol (y=%.1f)" % p1.position.y)

	# 9d) Dash vers le haut sans tenir le saut : il n'est plus coupé net (vrai 3e saut)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.stick = Vector2(0, -1) if f >= 40 and f < 45 else Vector2.ZERO
		s.dash_pressed = f == 40)
	await step(40)
	var dash_ground_y := p1.position.y
	var dash_top_y := dash_ground_y
	for i in 50:
		await step(1)
		dash_top_y = minf(dash_top_y, p1.position.y)
	check(dash_ground_y - dash_top_y > 230, "Dash vers le haut : monte de %.0f px" % (dash_ground_y - dash_top_y))

	# 9e) Après une chute, on repart à neuf (plus de recul en cours)
	p1._knockback_timer = 0.5
	p1.fall_out(Vector2(640, 120))
	check(p1._knockback_timer <= 0.0 and p1.lives == 2, "Réapparition : plus de recul, vies = %d" % p1.lives)

	# 9f) Recharge de l'attaque légère : en martelant X (1 appui toutes les 4 frames), un coup toutes les 0,4 s
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f >= 40 and f % 4 == 0)
	await step(40)
	var swings := 0
	var was_attacking := false
	for i in 60:
		await step(1)
		if p1.is_attacking() and not was_attacking:
			swings += 1
		was_attacking = p1.is_attacking()
	var expected_swings := ceili(1.0 / base.attack_cooldown)
	check(swings >= expected_swings - 1 and swings <= expected_swings,
		"Recharge : en martelant X, %d coups en 1 s (attendu : %d)" % [swings, expected_swings])

	# 10) Menu : écran titre, joueurs qui rejoignent, choix du perso et de la map
	game.queue_free(); game = null
	GameSetup.player_devices = []
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	menu.change_scene_on_start = false
	add_child(menu)
	await get_tree().process_frame
	check(menu.screen == menu.Screen.TITLE, "Menu : on arrive sur « Appuie sur une touche »")
	await shot("06_titre")
	var pad := {"type": "joypad", "id": 0}
	var kb_left := {"type": "keyboard", "layout": 0}
	var kb_right := {"type": "keyboard", "layout": 1}
	menu.handle(pad, "")
	check(menu.screen == menu.Screen.MAIN and menu.players == [pad], "Menu : le premier qui appuie devient J1 et ouvre le menu")
	menu.handle(kb_right, "down")
	menu.handle(kb_left, "confirm")
	check(menu.players == [pad, kb_right, kb_left] and menu._choice == 0, "Menu : les appareils suivants deviennent J2, J3 (sans agir)")
	await shot("07_menu")
	menu.handle(pad, "down")
	menu.handle(pad, "down")
	menu.handle(pad, "down")
	menu.handle(pad, "confirm")
	check(menu.screen == menu.Screen.OPTIONS, "Menu : OPTIONS s'ouvre")
	menu.handle(kb_left, "right")
	menu.handle(kb_left, "right")
	menu.handle(kb_left, "right")
	check(GameSetup.lives == 5, "Options : vies réglées à %d (max 5)" % GameSetup.lives)
	menu.handle(pad, "back")
	menu.handle(pad, "up")
	check(menu.screen == menu.Screen.MAIN and menu._choice == 2, "Menu : retour, COMMANDES sélectionné")
	menu.handle(pad, "confirm")
	check(menu.screen == menu.Screen.CONTROLS, "Menu : COMMANDES s'ouvre")
	menu.handle(pad, "confirm")
	check(menu.screen == menu.Screen.CONTROLS and menu._pad_test_cells.size() == 11,
		"COMMANDES : A ne fait pas revenir (on y teste ses boutons, une case manette par commande)")
	menu.handle(pad, "back")
	menu.handle(pad, "up")
	menu.handle(pad, "up")
	menu.handle(pad, "confirm")
	check(menu.screen == menu.Screen.CHARACTERS, "Menu : JOUER ouvre le choix du perso")
	menu.handle(kb_left, "back")
	check(menu.players == [pad, kb_right, kb_left] and menu.screen == menu.Screen.CHARACTERS,
		"Perso : B de J3 (pas encore prêt) ne le fait pas quitter")
	# Rien ne bouge à l'écran quand on change de perso ou qu'on valide
	var layout := func() -> Array:
		await get_tree().process_frame
		await get_tree().process_frame
		var title: Control = menu._content.get_child(0)
		var sizes := [title.global_position]
		for slot in menu._content.get_child(1).get_children():
			sizes.append(slot.global_position)
			sizes.append(slot.size)
		return sizes
	var layout_before: Array = await layout.call()
	var stable := true
	for k in GameSetup.CHARACTERS.size() * 2:
		menu.handle(kb_right, "right")
		var now: Array = await layout.call()
		if now != layout_before:
			stable = false
	for k in GameSetup.WEAPONS.size():
		menu.handle(kb_right, "down")
		if await layout.call() != layout_before:
			stable = false
	menu.handle(kb_right, "confirm")
	if await layout.call() != layout_before:
		stable = false
	menu.handle(kb_right, "back")
	check(stable, "Perso : changer de perso, d'arme ou valider ne fait rien bouger à l'écran")
	menu.handle(kb_left, "quit")
	check(menu.players == [pad, kb_right], "Perso : J3 se retire avec sa touche « se retirer »")
	menu.handle(pad, "right")
	menu.handle(pad, "down")
	menu.handle(pad, "confirm")
	menu.handle(pad, "down")
	check(menu.screen == menu.Screen.CHARACTERS and menu._locked == [true, false], "Perso : J1 prêt, on attend J2")
	await shot("08_persos")
	menu.handle(kb_right, "confirm")
	check(menu.screen == menu.Screen.MAPS, "Perso : tout le monde prêt, on passe au choix de la map")
	await shot("09_map")
	menu.handle(pad, "confirm")
	check(GameSetup.player_devices == [[pad], [kb_right]] and GameSetup.player_characters.size() == 2 \
		and GameSetup.map_path == GameSetup.MAPS[0], "Map : la partie est lancée avec les bons joueurs, persos et map")
	check(GameSetup.player_weapons == [GameSetup.WEAPONS[1], GameSetup.WEAPONS[0]],
		"Perso : J1 a choisi le katana (haut / bas), J2 garde les mains nues ; une fois prêt, on ne change plus")
	GameSetup.player_weapons = []
	menu.queue_free()

	# 10b) Seul, on ne peut pas passer au choix de la map
	GameSetup.player_devices = []
	menu = load("res://scenes/menu.tscn").instantiate()
	menu.change_scene_on_start = false
	add_child(menu)
	await get_tree().process_frame
	menu.handle(kb_left, "confirm")
	menu.handle(kb_left, "confirm")
	menu.handle(kb_left, "confirm")
	check(menu.screen == menu.Screen.CHARACTERS and menu.players.size() == 1, "Menu : seul, on reste au choix du perso")
	menu.handle(pad, "confirm")
	check(menu.screen == menu.Screen.CHARACTERS and menu.players.size() == 2, "Menu : un 2e joueur rejoint pendant le choix du perso")
	menu._on_joy_connection_changed(0, false)
	check(menu.players.size() == 1, "Menu : une manette débranchée quitte la partie")
	menu.handle(pad, "confirm")
	menu.handle(kb_left, "quit")
	check(menu.players == [pad] and menu.screen == menu.Screen.CHARACTERS, "Perso : J1 se retire, la manette devient J1")
	menu.handle(pad, "quit")
	check(menu.players.is_empty() and menu.screen == menu.Screen.TITLE, "Perso : le dernier joueur se retire, retour à l'écran titre")
	menu.queue_free()

	# 10c) Une partie avec 5 vies les affiche bien
	GameSetup.player_devices = []
	await new_game()
	check(game.fighters[0].lives == 5 and game.fighters[0].max_lives == 5, "Partie : les vies réglées dans OPTIONS sont utilisées")
	GameSetup.lives = 3

	# 11) Menu pause : Reprendre, Restart, Remap, Quitter
	var pad0 := {"type": "joypad", "id": 0}
	var pad1 := {"type": "joypad", "id": 1}
	GameSetup.player_devices = [[pad0], [pad1]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	await step(10)
	var start_event := InputEventJoypadButton.new()
	start_event.device = 1
	start_event.button_index = JOY_BUTTON_START
	start_event.pressed = true
	game._input(start_event)
	check(get_tree().paused and game.pause_menu != null, "Pause : Start ouvre le menu pause, le jeu est figé")
	var x_paused := p1.position.x
	p1.velocity.x = 500.0
	await step(10)
	check(p1.position.x == x_paused, "Pause : plus rien ne bouge")
	await shot("14_pause")
	var pause: PauseMenu = game.pause_menu
	pause.change_scene = false
	pause.handle(pad1, "down")
	pause.handle(pad1, "down")
	pause.handle(pad1, "confirm")
	check(pause.screen == PauseMenu.Screen.REMAP, "Pause : REMAP s'ouvre")
	pause.handle(pad0, "right")
	check(game.player_devices == [[pad1], [pad0]] and GameSetup.player_devices == [[pad1], [pad0]],
		"Remap : la manette 1 passe au joueur 2 (et la 2 au joueur 1)")
	var p1_jump_device := -1
	for ev in InputMap.action_get_events("p1_jump"):
		p1_jump_device = ev.device
	check(p1_jump_device == 1, "Remap : J1 saute maintenant avec la manette 2")
	await shot("15_remap")
	# Bug : la manette dont on pousse le stick pour remapper ne doit pas laisser une direction « coincée »
	var stick_push := InputEventJoypadMotion.new()
	stick_push.device = 1; stick_push.axis = JOY_AXIS_LEFT_X; stick_push.axis_value = 1.0
	Input.parse_input_event(stick_push)
	Input.flush_buffered_events()
	pause.handle(pad1, "right")  # la manette 2 (au J1) repasse au J2
	check(not Input.is_action_pressed("p1_right"),
		"Remap : le J1 ne garde pas la direction poussée par l'ancienne manette")
	var stick_back := InputEventJoypadMotion.new()
	stick_back.device = 1; stick_back.axis = JOY_AXIS_LEFT_X; stick_back.axis_value = 0.0
	Input.parse_input_event(stick_back)
	Input.flush_buffered_events()
	check(not Input.is_action_pressed("p1_right") and not Input.is_action_pressed("p2_right"),
		"Remap : aucune direction ne reste coincée après avoir poussé le stick")
	pause.handle(pad0, "right")  # remet la manette 2 au J1 pour la suite
	pause.handle(pad0, "back")
	check(pause.screen == PauseMenu.Screen.LIST, "Remap : B revient à la liste")
	pause.handle(pad0, "up")
	pause.handle(pad0, "up")
	pause.handle(pad0, "confirm")
	await get_tree().process_frame
	check(not get_tree().paused and game.pause_menu == null, "Pause : REPRENDRE relance le jeu")
	await step(10)
	check(p1.position.x != x_paused, "Pause : après Reprendre, ça rebouge")
	await step(40)
	check(absf(p1.velocity.x) < 1.0 and absf(p2.velocity.x) < 1.0,
		"Remap : après Reprendre, personne ne court tout seul (vx J1 %.0f, J2 %.0f)" % [p1.velocity.x, p2.velocity.x])
	game.open_pause()
	game.pause_menu.change_scene = false
	game.pause_menu.choose(1)
	check(not get_tree().paused, "Pause : RESTART relance (sans rester en pause)")
	GameSetup.player_devices = []
	GameSetup.lives = 3

	# 11b) Jumb (grand, lourd) et Jib (petit, rapide)
	var barre := load("res://characters/barre.tres") as CharacterStats
	var jumb := load("res://characters/jumb.tres") as CharacterStats
	var jib := load("res://characters/jib.tres") as CharacterStats
	check(is_equal_approx(barre.mass(), 1.0) and jumb.mass() > 1.2 and jib.mass() < 0.85,
		"Poids selon la taille : Barre %.2f, Jumb %.2f, Jib %.2f" % [barre.mass(), jumb.mass(), jib.mass()])
	var jump_ratio := pow(jumb.jump_speed / barre.jump_speed, 2.0)
	check(jump_ratio > 0.88 and jump_ratio < 0.97, "Jumb saute juste un peu moins haut (%d %%)" % roundi(jump_ratio * 100.0))
	check(jumb.run_speed < barre.run_speed and jib.run_speed > barre.run_speed, "Jumb plus lent, Jib plus rapide")
	check(absf(jumb.dash_speed * jumb.dash_time - barre.dash_speed * barre.dash_time) < 5.0 and jumb.dash_speed < barre.dash_speed,
		"Jumb : dash de même longueur mais plus lent")
	check(jib.dash_speed > barre.dash_speed and jib.heavy_charge_time < barre.heavy_charge_time
		and jib.stamina_sprint_drain < barre.stamina_sprint_drain and jumb.stamina_sprint_drain > barre.stamina_sprint_drain,
		"Jib : dash plus rapide, charge plus courte ; endurance : Jib la vide moins vite, Jumb plus vite")
	check(is_equal_approx(barre.tempo(), 1.0) and absf(jumb.tempo() - 1.2) < 0.01 and absf(jib.tempo() - 0.89) < 0.01,
		"Vitesse d'attaque selon le poids : Barre x%.2f, Jumb x%.2f, Jib x%.2f" % [barre.tempo(), jumb.tempo(), jib.tempo()])
	check(jib.light_startup() < barre.light_startup() and barre.light_startup() < jumb.light_startup()
		and jib.cooldown(false) < barre.cooldown(false) and barre.cooldown(false) < jumb.cooldown(false)
		and jib.cooldown(true) < barre.cooldown(true) and barre.cooldown(true) < jumb.cooldown(true),
		"Jib arme et recharge plus vite, Jumb plus lentement (recharge %.2f / %.2f / %.2f s)" % [jib.cooldown(false), barre.cooldown(false), jumb.cooldown(false)])
	check(jib.attack_reach < barre.attack_reach and barre.attack_reach < jumb.attack_reach
		and jib.heavy_arc_radius < barre.heavy_arc_radius and barre.heavy_arc_radius < jumb.heavy_arc_radius,
		"Portée : Jib la plus courte, Jumb la plus longue")
	GameSetup.player_characters = ["res://characters/jumb.tres", "res://characters/jib.tres"]
	await new_game()
	GameSetup.player_characters = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	p1.position = Vector2(600, p1.position.y); p2.position = Vector2(680, p2.position.y)
	game._clash(p1, p2, Vector2(640, 520))
	check(absf(p2.velocity.x) > absf(p1.velocity.x) * 2.5,
		"Contre Jumb / Jib : Jib (léger) repoussé bien plus loin (%.0f contre %.0f)" % [p2.velocity.x, p1.velocity.x])
	await step(30)
	p2.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = true)
	var full_frames := 0
	for i in 70:
		await step(1)
		if p2.is_heavy_swinging():
			full_frames = i
			break
	await shot("16_jumb_jib")
	check(full_frames > 0 and full_frames < 50, "Jib : sa lourde arrive au max plus vite (%.2f s)" % (full_frames / 60.0))
	# Le coup léger de Jumb part plus tard et sa recharge dure plus longtemps (en phase 1 de la jauge)
	await step(90)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	var jumb_active := -1
	for i in 30:
		await step(1)
		if p1.is_attack_active():
			jumb_active = i
			break
	check(jumb_active >= int(jumb.light_startup() * 60.0) - 1 and jumb_active > int(barre.light_startup() * 60.0),
		"Jumb : son coup léger s'arme plus longtemps (%.2f s)" % (jumb_active / 60.0))
	check(absf(p1._cooldown(false) - jumb.cooldown(false)) < 0.001 and absf(p2._cooldown(true) - jib.cooldown(true)) < 0.001,
		"La recharge en jeu suit le poids (Jumb %.2f s, lourde de Jib %.2f s)" % [p1._cooldown(false), p2._cooldown(true)])

	# 11c) Chaque perso monte sur la plateforme du milieu en un seul saut (Jumb saute un peu moins haut,
	# mais ça ne doit pas l'empêcher d'aller là où va la Barre)
	for c_path in GameSetup.CHARACTERS:
		GameSetup.player_characters = [c_path, c_path]
		await new_game()
		GameSetup.player_characters = []
		p1 = game.fighters[0]; p2 = game.fighters[1]
		p2.input_source = Scripted.new(func(s, f): pass)
		p1.input_source = Scripted.new(func(s, f): pass)
		await step(40)
		p1.position.x = 640  # sous la plateforme du milieu
		p1.input_source = Scripted.new(func(s, f):
			s.jump_pressed = f == 1
			s.jump_held = f >= 1 and f < 40)
		await step(70)
		var feet := p1.position.y + p1.stats.body_size.y / 2.0
		check(p1.is_on_floor() and absf(feet - 432.0) < 3.0,
			"Saut : %s monte sur la plateforme du milieu en un saut (pieds à y=%.0f)" % [p1.stats.display_name, feet])

	# 12) Contenu : chaque perso et chaque map de GameSetup est complet et jouable
	# (si on ajoute un perso ou une map incomplet, la mise en ligne s'arrête ici)
	for path in GameSetup.CHARACTERS:
		var c := load(path) as CharacterStats
		check(c != null and c.display_name != "" and c.body_size.x > 0.0 and c.body_size.y > 0.0 \
			and c.shield_max >= 1 and c.mass() > 0.0 and c.tempo() > 0.0 and c.attack_reach > c.attack_radius \
			and c.heavy_startup < c.heavy_charge_time and c.dash_time > 0.0,
			"Contenu : le perso %s est complet" % path)
		# Sa description tient dans les 3 lignes prévues dans le choix du perso (même texte et largeur que menu.gd)
		var description := UiKit.label(c.description, 14, UiKit.TEXT_DIM)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size = Vector2(200, 60)
		add_child(description)
		await step(1)
		check(description.get_line_count() <= 3, "Contenu : la description de %s tient en 3 lignes (%d)" % [c.display_name, description.get_line_count()])
		description.queue_free()
	for path in GameSetup.MAPS + [GameSetup.VILLE_MAP]:
		var m := GameSetup.make_map(path)
		var problems: Array[String] = []
		if m == null:
			problems.append("ce n'est pas une GameMap")
		else:
			if m.map_name == "":
				problems.append("pas de nom")
			if not m.has_node("SpawnPoints") or m.get_node("SpawnPoints").get_child_count() < 4:
				problems.append("il faut 4 points dans SpawnPoints")
			if not m.has_node("RespawnPoint"):
				problems.append("pas de RespawnPoint")
			else:
				var points: Array = [m.get_node("RespawnPoint")]
				if m.has_node("SpawnPoints"):
					points.append_array(m.get_node("SpawnPoints").get_children())
				for point in points:
					if not m.blast_zone.has_point(point.position):
						problems.append("%s est hors de la zone de jeu" % point.name)
				for where in m.weapon_spawn_points():
					if not m.blast_zone.has_point(where):
						problems.append("une apparition d'arme est hors de la zone de jeu")
			_check_visuals(m, problems)
			m.free()
		check(problems.is_empty(), "Contenu : la map %s est complète %s" % [path, problems])
		# Sur chaque map, chaque perso apparaît posé (4 joueurs) et ne perd pas de vie en arrivant
		GameSetup.map_path = path
		for c_path in GameSetup.CHARACTERS:
			GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}],
				[{"type": "joypad", "id": 5}], [{"type": "joypad", "id": 6}]]
			GameSetup.player_characters = [c_path, c_path, c_path, c_path]
			await new_game()
			for fi in game.fighters:
				fi.input_source = Scripted.new(func(s, f): pass)
			await step(90)
			var landed := 0
			for fi in game.fighters:
				if fi.is_on_floor() and fi.lives == GameSetup.lives:
					landed += 1
			check(landed == 4, "Contenu : sur %s, les 4 %s atterrissent (%d/4)" % [path.get_file(), c_path.get_file(), landed])
		# ... et une arme qui apparaît à chaque point d'apparition d'arme se pose sur le décor
		for fi in game.fighters:
			fi.equip(load(GameSetup.WEAPONS[1]), 0)  # armés : personne ne ramasse les armes
		var spawned: Array[Projectile] = []
		for where in game.map.weapon_spawn_points():
			spawned.append(game.spawn_weapon(load(GameSetup.WEAPONS[1]), where))
		await step(180)
		var weapons_landed := spawned.filter(func(w): return is_instance_valid(w) and w in game.projectiles and w.state == Projectile.State.STUCK).size()
		check(weapons_landed == spawned.size(), "Contenu : sur %s, les armes apparues se posent (%d/%d)" % [path.get_file(), weapons_landed, spawned.size()])
	check(not GameSetup.VILLE_MAP in GameSetup.all_maps(), "Contenu : la Ville reste cachée (pas dans le choix de la map sans ?ville)")
	# Ville : dans un immeuble, chaque perso monte d'un étage avec saut + double saut
	GameSetup.map_path = GameSetup.VILLE_MAP
	for c_path in GameSetup.CHARACTERS:
		GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}]]
		GameSetup.player_characters = [c_path, c_path]
		await new_game()
		var climber: Fighter = game.fighters[0]
		climber.input_source = Scripted.new(func(s, f):
			s.jump_held = f >= 30 and f < 90
			s.jump_pressed = f == 30 or f == 48)
		game.fighters[1].input_source = Scripted.new(func(s, f): pass)
		climber.global_position = Vector2(Ville.building_center(10), -climber.stats.body_size.y / 2.0)
		climber.velocity = Vector2.ZERO
		await step(140)
		if c_path == GameSetup.CHARACTERS[0]:
			await shot("ville_etage")
		var feet := climber.global_position.y + climber.stats.body_size.y / 2.0
		check(climber.is_on_floor() and absf(feet + Ville.FLOOR_HEIGHT) < 4.0,
			"Ville : %s monte d'un étage avec saut + double saut (pieds à %d)" % [c_path.get_file(), feet])
	# Ville : les murs se cassent à coups d'attaque lourde (3 PV sur 6 par coup), et ne reviennent pas
	var wall_x := Ville.building_lefts()[9] + Ville.BUILDINGS[9][0] * Ville.BLOCK - Ville.BLOCK / 2.0
	var wall_block: CityBlock = null
	for window in game.map.windows():
		if window is CityBlock and window.rect().has_point(Vector2(wall_x, -2.0 * Ville.FLOOR_HEIGHT - Ville.BLOCK / 2.0)):
			wall_block = window
	var breaker: Fighter = game.fighters[0]
	breaker.global_position = Vector2(wall_x - Ville.BLOCK / 2.0 - 40.0, -2.0 * Ville.FLOOR_HEIGHT - breaker.stats.body_size.y / 2.0)
	breaker.velocity = Vector2.ZERO
	breaker.input_source = Scripted.new(func(s, f):
		s.stick = Vector2(1, 0) if f < 3 else Vector2.ZERO
		s.heavy_pressed = f == 20 or f == 90 or f == 160
		s.heavy_held = s.heavy_pressed)
	await step(60)
	var after_one := wall_block.hp if wall_block != null else -1
	await step(160)
	check(wall_block != null and after_one == Ville.BLOCK_HP - CityBlock.HEAVY_DAMAGE and wall_block.broken,
		"Ville : un mur s'abîme puis se casse à coups d'attaque lourde (PV après 1 coup : %d, cassé : %s)" % [after_one, wall_block.broken if wall_block else false])
	await shot("ville_mur_casse")
	await step(60 * 20)
	check(wall_block != null and wall_block.broken, "Ville : un bloc cassé ne revient pas (la ville ne se répare pas)")
	# ... et une grenade qui explose contre un immeuble abîme les blocs autour
	var near: Array = game.map.windows().filter(func(w): return w is CityBlock and not w.broken \
		and w.rect().get_center().distance_to(Vector2(Ville.building_center(9), -Ville.FLOOR_HEIGHT * 3.0)) < 150.0)
	game.map.smash_windows_in(Vector2(Ville.building_center(9), -Ville.FLOOR_HEIGHT * 3.0), 150.0)
	check(not near.is_empty() and near.all(func(w): return w.hp == Ville.BLOCK_HP - CityBlock.EXPLOSION_DAMAGE),
		"Ville : une explosion abîme les blocs dans son rayon (%d blocs)" % near.size())
	# Ville : écroulement. Casser un seul mur du rez-de-chaussée ne fait rien tomber...
	await new_game()
	var collapse := game.map.get_node("Ecroulement") as CityCollapse
	for fi in game.fighters:
		fi.input_source = Scripted.new(func(s, f): pass)
	var ground_walls := func(index: int, side: int) -> Array:
		var left: float = Ville.building_lefts()[index]
		var right: float = left + Ville.BUILDINGS[index][0] * Ville.BLOCK
		var x: float = left + Ville.BLOCK / 2.0 if side < 0 else right - Ville.BLOCK / 2.0
		return collapse.blocks.filter(func(b: CityBlock) -> bool:
			return not b.one_way and b.rect().has_point(Vector2(x, b.rect().get_center().y)) and b.rect().position.y >= -Ville.FLOOR_HEIGHT - 1.0)
	var in_building := func(index: int) -> Array:
		var left: float = Ville.building_lefts()[index]
		var right: float = left + Ville.BUILDINGS[index][0] * Ville.BLOCK
		return collapse.blocks.filter(func(b: CityBlock) -> bool:
			return not b.broken and b.rect().get_center().x > left and b.rect().get_center().x < right)
	var before_count: int = in_building.call(1).size()
	for b in ground_walls.call(1, -1):
		b.hit(Ville.BLOCK_HP)
	await step(30)
	check(collapse.chunks.is_empty() and in_building.call(1).size() == before_count - 3,
		"Ville : un seul mur coupé, l'immeuble tient (morceaux qui tombent : %d)" % collapse.chunks.size())
	# ... couper les deux murs fait tomber tout le haut d'un bloc : il tremble, tombe, fait mal et éclate
	var victim: Fighter = game.fighters[1]
	victim.global_position = Vector2(Ville.building_center(0), -victim.stats.body_size.y / 2.0)
	victim.velocity = Vector2.ZERO
	for b in ground_walls.call(0, -1) + ground_walls.call(0, 1):
		b.hit(Ville.BLOCK_HP)
	await step(3)
	var falling := collapse.chunks.size()
	var chunk_size: int = collapse.chunks[0].rects.size() if falling > 0 else 0
	var warned: bool = falling > 0 and collapse.chunks[0].state == FallingChunk.State.WARN
	await step(20)
	await shot("ville_ecroulement")
	await step(130)
	check(falling == 1 and chunk_size >= 20 and warned,
		"Ville : les deux murs coupés, le haut tombe d'un seul morceau qui tremble d'abord (%d morceau(x), %d blocs)" % [falling, chunk_size])
	check(in_building.call(0).is_empty() and collapse.chunks.is_empty(), "Ville : le morceau s'écrase et éclate (blocs restants : %d)" % in_building.call(0).size())
	check(victim.is_stunned() or victim.lives < GameSetup.lives, "Ville : celui qui est dessous est touché (sonné : %s)" % victim.is_stunned())
	# ... et un blocage l'arrête : il éclate sur le bouclier, qui craque fort
	await step(200)
	var blocker: Fighter = game.fighters[1]
	blocker.global_position = Vector2(Ville.building_center(2), -blocker.stats.body_size.y / 2.0)
	blocker.velocity = Vector2.ZERO
	blocker.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(30)
	var shield_before := blocker.shield
	var stunned_before := blocker.is_stunned()
	for b in ground_walls.call(2, -1) + ground_walls.call(2, 1):
		b.hit(Ville.BLOCK_HP)
	await step(120)
	check(not stunned_before and not blocker.is_stunned() and blocker.shield == shield_before - Game.CHUNK_SHIELD_DAMAGE,
		"Ville : un gros morceau sur un bouclier éclate et le bouclier craque (%d -> %d)" % [shield_before, blocker.shield])
	# Ville : la balise d'appel. RT : un viseur rouge, puis le mecha tombe du ciel 1,5 s plus tard et se
	# pose sur le toit (pas dedans). Celui qui est dessous est écrasé (sonné), celui qui l'a appelé non.
	await new_game()
	game._beacon_timer = 1e9
	game._item_spawn_timer = 1e9
	var caller: Fighter = game.fighters[0]
	var other: Fighter = game.fighters[1]
	var cmd := {"stick": Vector2.ZERO, "jump": false, "jp": false, "dash": false, "item": false}
	caller.input_source = Scripted.new(func(s, f):
		s.stick = cmd.stick
		s.jump_held = cmd.jump
		s.jump_pressed = cmd.jp
		s.dash_pressed = cmd.dash
		s.item_pressed = cmd.item
		cmd.jp = false
		cmd.dash = false
		cmd.item = false)
	other.input_source = Scripted.new(func(s, f): pass)
	var roof_x := Ville.building_center(13) - 120.0
	var roof_y := Ville.roof_top(13)
	caller.global_position = Vector2(roof_x, roof_y - caller.stats.body_size.y / 2.0 - 2.0)
	other.global_position = Vector2(roof_x + 30.0, roof_y - other.stats.body_size.y / 2.0 - 2.0)
	await step(10)
	check(caller.take_item("balise") and caller.item == "balise", "Ville : on ramasse une balise d'appel")
	cmd.item = true
	await step(2)
	var mecha: Mecha = game.mechas[0] if game.mechas.size() == 1 else null
	check(mecha != null and caller.item == "" and mecha.state == Mecha.State.CALLED and absf(mecha.global_position.y - roof_y) < 2.0,
		"Ville : RT avec la balise marque le toit d'un viseur rouge (mecha en route : %s)" % (mecha != null))
	var frames := 0
	while mecha != null and not mecha.is_ready() and frames < 200:
		await step(1)
		frames += 1
		if frames == 82:
			await shot("ville_mecha_appel")
	check(mecha != null and mecha.is_ready() and absf(frames / 60.0 - Mecha.CALL_TIME) < 0.1,
		"Ville : le mecha se pose %.2f s après l'appel" % (frames / 60.0))
	await step(2)
	check(touched(other) and untouched(caller), "Ville : il écrase celui qui est dessous (sonné : %s), pas celui qui l'a appelé" % other.is_stunned())
	await step(40)
	check(mecha.is_on_floor() and absf(mecha.global_position.y - roof_y) < 2.0, "Ville : le mecha tient sur le toit (y = %d)" % mecha.global_position.y)
	# Monter : collé au mecha, stick vers le haut
	caller.global_position = Vector2(mecha.global_position.x, roof_y - caller.stats.body_size.y / 2.0 - 2.0)
	await step(2)
	cmd.stick = Vector2(0.0, -1.0)
	await step(3)
	cmd.stick = Vector2.ZERO
	check(caller.is_piloting() and mecha.pilot == caller and not caller.can_be_hit() and mecha.visual.color == caller.color,
		"Ville : stick vers le haut contre le mecha, on monte dedans")
	# Marcher, voler, carburant, dash
	var x0 := mecha.global_position.x
	cmd.stick = Vector2(1.0, 0.0)
	await step(20)
	cmd.stick = Vector2.ZERO
	await step(10)
	check(mecha.global_position.x - x0 > 120.0 and caller.global_position.distance_to(mecha.cockpit()) < 1.0,
		"Ville : le mecha marche (%d px), le pilote reste dans le cockpit" % (mecha.global_position.x - x0))
	cmd.jp = true
	cmd.jump = true
	await step(90)
	await shot("ville_mecha_vol")
	check(mecha.global_position.y < roof_y - 600.0 and mecha.fuel < Mecha.FUEL_MAX - 1.0,
		"Ville : A gardé, il vole (%d px au-dessus du toit, carburant %.1f s)" % [roof_y - mecha.global_position.y, mecha.fuel])
	cmd.jump = false
	var fuel_air := mecha.fuel
	frames = 0
	while not mecha.is_on_floor() and frames < 300:
		await step(1)
		frames += 1
	await step(30)
	check(mecha.is_on_floor() and absf(mecha.global_position.y - roof_y) < 2.0 and mecha.fuel > fuel_air + 1.0,
		"Ville : A lâché, il retombe sur le toit et le carburant revient (%.1f -> %.1f)" % [fuel_air, mecha.fuel])
	mecha.fuel = 0.3
	cmd.jp = true
	cmd.jump = true
	await step(60)
	cmd.jump = false
	check(mecha._empty_tank and mecha.global_position.y > roof_y - 400.0, "Ville : réservoir vide, il ne vole plus (%d px)" % (roof_y - mecha.global_position.y))
	await step(120)
	x0 = mecha.global_position.x
	cmd.stick = Vector2(-1.0, 0.0)
	cmd.dash = true
	await step(12)
	cmd.stick = Vector2.ZERO
	check(x0 - mecha.global_position.x > 200.0, "Ville : LB, le mecha fait un dash (%d px)" % (x0 - mecha.global_position.x))
	await step(30)
	# Sortir : bas + A gardés 0,5 s (pas moins)
	cmd.stick = Vector2(0.0, 1.0)
	cmd.jump = true
	await step(15)
	var still_in := caller.is_piloting()
	await step(25)
	cmd.stick = Vector2.ZERO
	cmd.jump = false
	check(still_in and not caller.is_piloting() and mecha.pilot == null and caller.global_position.y < mecha.body_rect().position.y,
		"Ville : bas + A gardés 0,5 s, on sort par le haut (pas avant)")
	await step(60)
	check(caller.can_be_hit() and mecha.pilot == null and mecha.visual.color == Mecha.EMPTY_COLOR, "Ville : le mecha reste là, vide (gris)")
	# N'importe qui peut le prendre ; tombé hors de la ville avec, on perd une vie et le mecha
	other.global_position = Vector2(mecha.global_position.x, roof_y - other.stats.body_size.y / 2.0 - 2.0)
	other.input_source = Scripted.new(func(s, f): s.stick = Vector2(0.0, -1.0) if f < 3 else Vector2.ZERO)
	await step(6)
	check(other.is_piloting() and mecha.pilot == other and mecha.visual.color == other.color, "Ville : un autre joueur monte dans le mecha vide")
	var lives_before_fall := other.lives
	mecha.global_position = Vector2(Ville.HALF_WIDTH + 2000.0, -500.0)
	await step(3)
	check(other.lives == lives_before_fall - 1 and not other.is_piloting() and not is_instance_valid(mecha) and game.mechas.is_empty(),
		"Ville : tombé hors de la ville dans le mecha, on perd une vie et le mecha")
	# L'onde de choc repousse ceux qui sont autour (sans les sonner)
	await step(90)
	caller.global_position = Vector2(roof_x, roof_y - caller.stats.body_size.y / 2.0 - 2.0)
	other.global_position = Vector2(roof_x + 200.0, roof_y - other.stats.body_size.y / 2.0 - 2.0)
	await step(5)
	var stunned_other := other.is_stunned()
	var x_other := other.global_position.x
	var second_mecha: Mecha = game.call_mecha(caller)
	frames = 0
	while not second_mecha.is_ready() and frames < 200:
		await step(1)
		frames += 1
	await step(4)
	check(other.global_position.x - x_other > 40.0 and other.is_stunned() == stunned_other,
		"Ville : l'onde de choc repousse ceux qui sont autour (%d px), sans les sonner" % (other.global_position.x - x_other))
	# Les balises tombent tant qu'il y a moins de mechas que de joueurs
	game._beacon_timer = 0.0
	await step(1)
	var beacons: int = game.pickups.filter(func(p): return p.kind == "balise").size()
	game._beacon_timer = 0.0
	await step(1)
	var beacons_after: int = game.pickups.filter(func(p): return p.kind == "balise").size()
	check(beacons == 1 and beacons_after == 1, "Ville : une balise tombe tant qu'il y a moins de mechas que de joueurs (%d puis %d)" % [beacons, beacons_after])
	# Ville, tests préventifs : chaque perso monte et sort ; un mecha appelé contre un immeuble ne reste
	# pas coincé dans le mur ; appelé au-dessus du vide, il tombe et disparaît sans bug.
	for c_path in GameSetup.CHARACTERS:
		GameSetup.player_characters = [c_path, c_path]
		await new_game()
		game._beacon_timer = 1e9
		game._item_spawn_timer = 1e9
		var mech_rider: Fighter = game.fighters[0]
		mech_rider.input_source = Scripted.new(func(s, f):
			s.stick = Vector2(0.0, -1.0) if f >= 100 and f < 104 else Vector2(0.0, 1.0) if f >= 140 and f < 180 else Vector2.ZERO
			s.jump_held = f >= 140 and f < 180)
		game.fighters[1].input_source = Scripted.new(func(s, f): pass)
		mech_rider.global_position = Vector2(Ville.building_center(13), Ville.roof_top(13) - mech_rider.stats.body_size.y / 2.0 - 2.0)
		game.fighters[1].global_position = Vector2(Ville.building_center(7), Ville.roof_top(7) - 60.0)
		await step(2)
		var mech_ride: Mecha = game.call_mecha(mech_rider)
		await step(120)
		var boarded := mech_rider.is_piloting()
		await step(150)
		check(boarded and not mech_rider.is_piloting() and mech_rider.is_on_floor() and not mech_ride.pilot,
			"Ville : %s monte dans le mecha puis en sort" % c_path.get_file())
	var wall_left := Ville.building_lefts()[13]
	caller = game.fighters[0]
	caller.input_source = Scripted.new(func(s, f): pass)
	caller.global_position = Vector2(wall_left - 30.0, -caller.stats.body_size.y / 2.0 - 2.0)
	await step(5)
	var walled: Mecha = game.call_mecha(caller)
	await step(100)
	var landed_y := walled.global_position.y
	caller._board(walled)
	caller.input_source = Scripted.new(func(s, f): s.stick = Vector2(1.0, 0.0) if f < 15 else Vector2.ZERO)
	var x_start := walled.global_position.x
	await step(20)
	check(absf(landed_y - Ville.roof_top(13)) < 2.0 and walled.global_position.x > x_start + 60.0 and absf(walled.global_position.y - landed_y) < 2.0,
		"Ville : appelé au pied d'un immeuble, il se pose sur son toit et n'est pas coincé (y %d, x %d -> %d)" % [landed_y, x_start, walled.global_position.x])
	caller.leave_mecha()
	var faller: Fighter = game.fighters[1]
	faller.global_position = Vector2(Ville.HALF_WIDTH + 300.0, -600.0)
	var lost_mecha: Mecha = game.call_mecha(faller)
	await step(200)
	check(not is_instance_valid(lost_mecha) and not lost_mecha in game.mechas and faller.lives < GameSetup.lives,
		"Ville : un mecha appelé au-dessus du vide tombe et disparaît")
	check(not caller.take_item("balise") or not caller.is_piloting(), "Ville : on ne ramasse pas d'objet en mecha")

	# Ville : les coups des joueurs à pied usent un mecha (1 pour un léger, 3 pour un lourd, une fois
	# par coup) ; le pilote, lui, n'est pas touché.
	GameSetup.player_characters = [GameSetup.CHARACTERS[0], GameSetup.CHARACTERS[0]]
	await new_game()
	game._beacon_timer = 1e9
	game._item_spawn_timer = 1e9
	var pilot: Fighter = game.fighters[0]
	var hitter: Fighter = game.fighters[1]
	var pcmd := {"stick": Vector2.ZERO, "x": false, "y": false, "yh": false}
	pilot.input_source = Scripted.new(func(s, f):
		s.stick = pcmd.stick
		s.attack_pressed = pcmd.x
		s.heavy_pressed = pcmd.y
		s.heavy_held = pcmd.yh
		pcmd.x = false
		pcmd.y = false)
	hitter.input_source = Scripted.new(func(s, f): pass)
	var mx := Ville.building_center(Ville.TOWER) - 300.0  # sur le toit de la grande tour (960 px de large)
	var my := Ville.roof_top(Ville.TOWER)
	pilot.global_position = Vector2(mx, my - 40.0)
	hitter.global_position = Vector2(mx + 400.0, my - 40.0)
	await step(2)
	var tank: Mecha = game.call_mecha(pilot)
	await step(100)
	pilot._board(tank)
	await step(2)
	hitter.global_position = Vector2(tank.body_rect().end.x + hitter.stats.body_size.x / 2.0 + 4.0, my - hitter.stats.body_size.y / 2.0 - 1.0)
	await step(5)
	var hp0 := tank.hp
	hitter.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 0)
	await step(40)
	var after_light := tank.hp
	hitter.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 0
		s.heavy_held = f < 4)
	await step(70)
	check(hp0 == Mecha.WEAR_MAX and after_light == hp0 - Game.MECHA_WEAR_LIGHT and tank.hp == after_light - Game.MECHA_WEAR_HEAVY,
		"Ville : un coup léger use le mecha de 1, un lourd de 3 (%d -> %d -> %d)" % [hp0, after_light, tank.hp])
	check(untouched(pilot) and pilot.is_piloting() and tank.visual.wear > 0.0, "Ville : le pilote n'est pas touché, le mecha se fissure")
	# Le fusil d'assaut : X = une rafale de 3 balles vers l'adversaire, qui le sonne
	hitter.input_source = Scripted.new(func(s, f): pass)
	hitter.global_position = Vector2(mx + 350.0, my - hitter.stats.body_size.y / 2.0 - 1.0)
	await step(90)
	var bullets_before: int = game.projectiles.filter(func(p): return p.kind == "balle").size()
	pcmd.x = true
	await step(1)
	var seen_bullets := {}  # toutes les balles vues (la première peut toucher avant que la 3e parte)
	for i in 12:
		await step(1)
		for p in game.projectiles:
			if p.kind == "balle":
				seen_bullets[p.get_instance_id()] = true
	var max_bullets := seen_bullets.size()
	check(bullets_before == 0 and max_bullets == Mecha.BURST_SHOTS and tank.facing > 0.0, "Ville : X tire une rafale de %d balles vers l'adversaire" % max_bullets)
	await step(30)
	check(touched(hitter) and tank.hp == after_light - Game.MECHA_WEAR_HEAVY, "Ville : la rafale touche l'adversaire, pas son propre mecha")
	await shot("ville_mecha_rafale")
	# Le lance-roquette : Y gardé = chargée, lâché = elle part ; elle explose sur l'adversaire
	await step(200)
	hitter.recover()
	hitter._invincible_timer = 0.0
	var lives_h := hitter.lives
	pcmd.y = true
	pcmd.yh = true
	await step(30)
	check(tank.visual.turret_charge > 0.3, "Ville : Y gardé, la roquette se charge (%.2f)" % tank.visual.turret_charge)
	pcmd.yh = false
	await step(2)
	var rocket_list: Array = game.projectiles.filter(func(p): return p.kind == "roquette")
	check(rocket_list.size() == 1 and rocket_list[0].blast > 0.3, "Ville : Y lâché, une roquette part (charge %.2f)" % (rocket_list[0].blast if rocket_list.size() > 0 else -1.0))
	await step(4)
	await shot("ville_mecha_roquette")
	await step(40)
	check(game.projectiles.filter(func(p): return p.kind == "roquette").is_empty() and touched(hitter),
		"Ville : la roquette explose sur l'adversaire (vies %d -> %d, sonné : %s)" % [lives_h, hitter.lives, hitter.is_stunned()])
	# Une roquette use un autre mecha (de 5 à 7) ; le mecha détruit explose, son pilote est éjecté sonné
	# sans perdre de vie
	await step(150)
	hitter.recover()
	hitter.global_position = Vector2(mx + 550.0, my - 40.0)
	await step(2)
	var enemy: Mecha = game.call_mecha(hitter)
	await step(100)
	hitter._board(enemy)
	await step(5)
	pcmd.y = true
	pcmd.yh = false
	frames = 0
	while enemy.hp == Mecha.WEAR_MAX and frames < 120:
		await step(1)
		frames += 1
	check(enemy.hp <= Mecha.WEAR_MAX - Game.MECHA_WEAR_ROCKET[0] and enemy.hp >= Mecha.WEAR_MAX - Game.MECHA_WEAR_ROCKET[1] and hitter.is_piloting() and untouched(hitter),
		"Ville : une roquette use l'autre mecha de %d, son pilote n'est pas touché" % (Mecha.WEAR_MAX - enemy.hp))
	var hitter_lives := hitter.lives
	enemy.hp = 2
	await step(60)
	pcmd.y = true
	frames = 0
	while is_instance_valid(enemy) and frames < 120:
		await step(1)
		frames += 1
	await step(2)
	await shot("ville_mecha_explosion")
	check(not is_instance_valid(enemy) and not hitter.is_piloting() and hitter.is_stunned() and hitter.is_invincible() and hitter.lives == hitter_lives and game.mechas.size() == 1,
		"Ville : plus de solidité, le mecha explose ; le pilote est éjecté, sonné, sans perdre de vie")
	await step(20)
	check(hitter.global_position.y < my - 100.0 or hitter.velocity.y < 0.0 or hitter.is_on_floor(), "Ville : le pilote éjecté part vers le haut")
	# Une grenade use un mecha (pas le pilote)
	var hp_before_grenade := tank.hp
	game._explode(tank.body_rect().get_center())
	check(tank.hp == hp_before_grenade - Game.MECHA_WEAR_GRENADE and pilot.is_piloting() and untouched(pilot), "Ville : une grenade use le mecha de 4, pas son pilote")
	# Ville : fusil d'assaut et lance-roquette à pied, des objets à 2 mains
	await new_game()
	game._beacon_timer = 1e9
	game._item_spawn_timer = 1e9
	var gunner: Fighter = game.fighters[0]
	var foe: Fighter = game.fighters[1]
	game._weapon_spawn_timer = 1e9
	var gcmd := {"x": false, "rt": false, "rb": false}
	gunner.input_source = Scripted.new(func(s, f):
		s.attack_pressed = gcmd.x
		s.item_pressed = gcmd.rt
		s.item_held = gcmd.rt
		s.throw_pressed = gcmd.rb
		gcmd.x = false
		gcmd.rt = false
		gcmd.rb = false)
	foe.input_source = Scripted.new(func(s, f): pass)
	gunner.global_position = Vector2(mx, my - 40.0)
	foe.global_position = Vector2(mx + 350.0, my - 40.0)
	await step(20)
	check(gunner.take_item("fusil") and gunner.item_ammo == Fighter.RIFLE_AMMO and gunner.has_two_handed_item(), "Ville : le fusil d'assaut a 30 balles")
	gcmd.x = true
	await step(3)
	check(not gunner.is_attacking(), "Ville : avec le fusil (2 mains), X n'attaque plus")
	var rifle_seen := {}
	gcmd.rt = true
	for i in 14:
		await step(1)
		for p in game.projectiles:
			if p.kind == "balle":
				rifle_seen[p.get_instance_id()] = true
	check(rifle_seen.size() == Fighter.RIFLE_BURST and gunner.item_ammo == Fighter.RIFLE_AMMO - Fighter.RIFLE_BURST,
		"Ville : RT tire une rafale de 3 balles (%d vues, %d restent)" % [rifle_seen.size(), gunner.item_ammo])
	await step(30)
	check(touched(foe), "Ville : la rafale du fusil touche l'adversaire")
	await shot("ville_fusil")
	gcmd.rb = true
	await step(2)
	var tossed_rifle: Array = game.pickups.filter(func(p): return p.kind == "fusil")
	check(gunner.item == "" and tossed_rifle.size() == 1 and tossed_rifle[0].ammo == Fighter.RIFLE_AMMO - Fighter.RIFLE_BURST,
		"Ville : RB jette le fusil par terre avec ses balles, on retrouve son arme")
	gcmd.x = true
	await step(3)
	check(gunner.is_attacking(), "Ville : fusil jeté, X attaque de nouveau")
	await step(40)
	# Il vole vers l'adversaire, qui peut le ramasser (ici il passe dessus) ; on le lui reprend.
	check(foe.item == "fusil" and foe.item_ammo == Fighter.RIFLE_AMMO - Fighter.RIFLE_BURST, "Ville : l'adversaire ramasse le fusil jeté, avec ses balles")
	foe.item = ""
	gunner.take_item("fusil", Fighter.RIFLE_AMMO - Fighter.RIFLE_BURST)
	gunner.item_ammo = 2
	await step(30)
	gcmd.rt = true
	await step(12)
	check(gunner.item == "", "Ville : fusil vide, il disparaît")
	# Le lance-roquette : une seule roquette, très violente
	await step(200)
	foe.recover()
	foe._invincible_timer = 0.0
	foe.global_position = Vector2(mx + 350.0, my - foe.stats.body_size.y / 2.0 - 1.0)
	gunner.global_position = Vector2(mx, my - gunner.stats.body_size.y / 2.0 - 1.0)
	await step(5)
	check(gunner.take_item("lance_roquette") and gunner.item_ammo == 1, "Ville : le lance-roquette a 1 roquette")
	var foe_x := foe.global_position.x
	gcmd.rt = true
	await step(2)
	var foot_rockets: Array = game.projectiles.filter(func(p): return p.kind == "roquette")
	check(foot_rockets.size() == 1 and gunner.item == "", "Ville : RT tire la roquette, le lance-roquette disparaît")
	await step(8)
	await shot("ville_lance_roquette")
	await step(20)
	check(touched(foe) and foe.global_position.x > foe_x + 60.0, "Ville : la roquette touche et projette loin (%d px)" % (foe.global_position.x - foe_x))
	# Les tirs s'annulent : balle contre balle, 3 balles contre une roquette ; une roquette se contre
	# (coup ou blocage parfait), un blocage parfait dans une explosion est un contre.
	var reset_pair := func() -> void:
		for fi: Fighter in [gunner, foe]:
			fi.recover()
			fi._invincible_timer = 0.0
			fi.velocity = Vector2.ZERO
		gunner.global_position = Vector2(mx, my - gunner.stats.body_size.y / 2.0 - 1.0)
		foe.global_position = Vector2(mx + 400.0, my - foe.stats.body_size.y / 2.0 - 1.0)
	await step(200)
	reset_pair.call()
	await step(5)
	var lives_pair := [gunner.lives, foe.lives]
	game._on_item_used(gunner, "balle", Vector2.RIGHT, 1.0, 0.0)
	game._on_item_used(foe, "balle", Vector2.LEFT, 1.0, 0.0)
	await step(20)
	check(game.projectiles.filter(func(p): return p.kind == "balle").is_empty() and not gunner.is_stunned() and not foe.is_stunned()
		and [gunner.lives, foe.lives] == lives_pair, "Ville : deux balles qui se croisent s'annulent")
	game.gauge.points = 0.0  # la jauge a un maximum : on repart de 0 pour voir le +3
	var gauge_cancel: float = game.gauge.points
	game._fire_launcher(foe, Vector2.LEFT, Fighter.LAUNCHER_BLAST)
	for i in Game.ROCKET_CANCEL_BULLETS:
		game._on_item_used(gunner, "balle", Vector2.RIGHT, 1.0, 0.0)
		await step(3)
	await step(30)
	check(game.projectiles.is_empty() and not gunner.is_stunned() and not foe.is_stunned() and game.gauge.points >= gauge_cancel + 3.0,
		"Ville : 3 balles annulent la roquette, contre compté triple (jauge %.0f -> %.0f)" % [gauge_cancel, game.gauge.points])
	await step(60)
	reset_pair.call()
	gunner.input_source = Scripted.new(func(s, f): s.block_held = f > 16)
	await step(5)
	game._fire_launcher(foe, Vector2.LEFT, Fighter.LAUNCHER_BLAST)
	var parry_frames := 0
	while not game.projectiles.is_empty() and parry_frames < 60:
		await step(1)
		parry_frames += 1
	check(game.projectiles.is_empty() and not gunner.is_stunned() and gunner.shield == gunner.stats.shield_max,
		"Ville : une roquette prise en blocage parfait est annulée, sans explosion")
	await step(60)
	reset_pair.call()
	gunner.input_source = Scripted.new(func(s, f): pass)
	await step(5)
	game.gauge.points = 0.0  # la jauge a un maximum : on repart de 0 pour voir le +3
	var gauge_hit: float = game.gauge.points
	game._fire_launcher(foe, Vector2.LEFT, Fighter.LAUNCHER_BLAST)
	await step(8)
	var rocket_now: Array = game.projectiles.filter(func(p): return p.kind == "roquette")
	if not rocket_now.is_empty():
		gunner.global_position.x = rocket_now[0].tip().x - 50.0
		light_now(gunner, Vector2.RIGHT)
		gunner._attack_time = gunner._attack_startup()  # pile quand le coup sort : renvoi parfait
	await step(2)
	var sent_back: Array = game.projectiles.filter(func(p): return p.kind == "roquette")
	check(sent_back.size() == 1 and sent_back[0].owner_index == gunner.player_index and sent_back[0].velocity.x > 0.0
		and game.gauge.points >= gauge_hit + 3.0, "Ville : une roquette frappée pile au bon moment repart vers le tireur (contre de lourde)")
	var foe_lives := foe.lives
	await step(40)
	check(not gunner.is_stunned() and (foe.is_stunned() or foe.lives < foe_lives), "Ville : la roquette renvoyée explose sur son tireur")
	await step(60)
	reset_pair.call()
	gunner.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(4)
	var shield_parry := gunner.shield
	game._explode(gunner.global_position + Vector2(60.0, 0.0))
	check(not gunner.is_stunned() and gunner.shield == shield_parry, "Ville : un blocage parfait dans une explosion ne prend rien (contre)")
	# Un gros morceau qui tombe se casse en l'air sous 3 balles, ou sous une roquette (contre de lourde)
	var city := game.map.get_node("Ecroulement") as CityCollapse
	var cut_building := func(index: int) -> void:
		var left: float = Ville.building_lefts()[index]
		var right: float = left + Ville.BUILDINGS[index][0] * Ville.BLOCK
		for b: CityBlock in city.blocks:
			var c := b.rect().get_center()
			if not b.one_way and b.rect().position.y >= -Ville.FLOOR_HEIGHT - 1.0 \
					and (absf(c.x - (left + Ville.BLOCK / 2.0)) < 1.0 or absf(c.x - (right - Ville.BLOCK / 2.0)) < 1.0):
				b.hit(Ville.BLOCK_HP)
	var shoot_at := func(kind: String, where: Vector2) -> void:
		var p := Projectile.new()
		p.kind = kind
		p.owner_index = 0
		p.position = where
		p.velocity = Vector2.UP * 10.0
		p.rotation = -PI / 2.0
		p.length = 16.0
		game._add_projectile(p)
	for test in [["roquette", 0], ["balle", 2]]:
		cut_building.call(test[1])
		await step(36)  # il tremble 0,5 s, puis tombe
		var falling_now: Array = city.chunks.filter(func(c): return is_instance_valid(c) and c.is_dangerous())
		var piece: FallingChunk = falling_now[0] if falling_now.size() > 0 else null
		game.gauge.points = 0.0  # la jauge a un maximum : on repart de 0 pour voir le +3
		var gauge_chunk: float = game.gauge.points
		for i in (1 if test[0] == "roquette" else FallingChunk.LIGHT_HITS):
			if piece != null and piece.is_dangerous():
				shoot_at.call(test[0], piece.current_rects()[0].get_center())
			await step(2)
		check(piece != null and piece.state == FallingChunk.State.BURST and game.gauge.points >= gauge_chunk + 3.0,
			"Ville : un gros morceau se casse en l'air sous %s (contre de lourde)" % ("une roquette" if test[0] == "roquette" else "3 balles"))
		await step(200)
	# Ville : le bouclier d'énergie du mecha (B) et son coup de poing (RB)
	await new_game()
	game._beacon_timer = 1e9
	game._item_spawn_timer = 1e9
	game._weapon_spawn_timer = 1e9
	var knight: Fighter = game.fighters[0]
	var walker: Fighter = game.fighters[1]
	var kcmd := {"b": false, "rb": false}
	knight.input_source = Scripted.new(func(s, f):
		s.block_held = kcmd.b
		s.throw_pressed = kcmd.rb
		kcmd.rb = false)
	walker.input_source = Scripted.new(func(s, f): pass)
	knight.global_position = Vector2(mx, my - 40.0)
	walker.global_position = Vector2(mx + 500.0, my - 40.0)
	await step(2)
	var guard: Mecha = game.call_mecha(knight)
	await step(100)
	knight._board(guard)
	await step(5)
	var walker_at_mecha := func() -> void:
		walker.recover()
		walker._invincible_timer = 0.0
		walker.velocity = Vector2.ZERO
		walker.global_position = Vector2(guard.body_rect().end.x + walker.stats.body_size.x / 2.0 + 4.0, my - walker.stats.body_size.y / 2.0 - 1.0)
	walker_at_mecha.call()
	kcmd.b = true
	await step(20)  # bouclier levé depuis longtemps : plus de blocage parfait
	var hp_guard := guard.hp
	light_now(walker, Vector2.LEFT)
	await step(3)
	check(guard.is_shielding() and guard.hp == hp_guard and guard.shield == Mecha.SHIELD_MAX - Game.MECHA_WEAR_LIGHT,
		"Ville : B lève le bouclier du mecha, il encaisse à sa place (bouclier %d)" % guard.shield)
	await shot("ville_mecha_bouclier")
	kcmd.b = false
	await step(30)
	walker_at_mecha.call()
	await step(2)
	game.gauge.points = 0.0
	var shield_now := guard.shield
	kcmd.b = true
	await step(2)
	light_now(walker, Vector2.LEFT)
	await step(3)
	check(guard.hp == hp_guard and guard.shield == shield_now and game.gauge.points >= 1.0 and walker.attack_cooldown_left() > 0.5,
		"Ville : B juste avant le coup = blocage parfait du mecha (rien d'usé, contre, l'attaquant ne frappe plus)")
	kcmd.b = false
	await step(70)
	# Une balle sur un blocage parfait repart vers son tireur
	walker.recover()
	walker.global_position = Vector2(mx + 500.0, my - walker.stats.body_size.y / 2.0 - 1.0)
	await step(5)
	game._on_item_used(walker, "balle", (guard.body_rect().get_center() - walker.global_position).normalized(), 1.0, 0.0)
	var bullet_back: Projectile = null
	for i in 30:
		if game.projectiles.size() > 0 and bullet_back == null:
			var b_now: Projectile = game.projectiles[0]
			if b_now.position.distance_to(guard.body_rect().get_center()) < 260.0:
				kcmd.b = true
		await step(1)
		for p in game.projectiles:
			if p.kind == "balle" and p.owner_index == knight.player_index:
				bullet_back = p
		if bullet_back != null:
			break
	check(bullet_back != null and bullet_back.velocity.x > 0.0 and guard.hp == hp_guard, "Ville : une balle sur le blocage parfait du mecha repart vers son tireur")
	kcmd.b = false
	await step(40)
	# Le bouclier vide casse pour de bon
	guard.shield = 1
	walker_at_mecha.call()
	kcmd.b = true
	await step(20)
	light_now(walker, Vector2.LEFT)
	await step(3)
	kcmd.b = false
	await step(2)
	kcmd.b = true
	await step(3)
	check(guard.shield_broken and not guard.is_shielding(), "Ville : le bouclier du mecha vide casse, B ne le relève plus")
	kcmd.b = false
	# RB : le coup de poing sonne le joueur à pied devant lui et le projette
	await step(60)
	walker_at_mecha.call()
	await step(3)
	var walker_x := walker.global_position.x
	kcmd.rb = true
	await step(4)
	await shot("ville_mecha_poing")
	await step(10)
	check(walker.is_stunned() and walker.global_position.x > walker_x + 40.0, "Ville : RB, le coup de poing du mecha sonne et projette (%d px)" % (walker.global_position.x - walker_x))
	# ... un blocage parfait l'arrête : contre, le mecha est repoussé et ne frappe plus
	await step(150)
	walker_at_mecha.call()
	walker.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(3)
	game.gauge.points = 0.0
	kcmd.rb = true
	await step(8)
	check(not walker.is_stunned() and game.gauge.points >= 3.0 and guard._punch_cooldown > 0.6,
		"Ville : un blocage parfait arrête le poing du mecha (contre, le mecha ne frappe plus)")
	walker.input_source = Scripted.new(func(s, f): pass)
	# ... et il use un autre mecha de 3
	await step(70)
	walker.recover()
	walker.global_position = Vector2(guard.body_rect().end.x + 200.0, my - 40.0)
	await step(2)
	var rival: Mecha = game.call_mecha(walker)
	await step(100)
	walker._board(rival)
	await step(5)
	rival.global_position.x = guard.body_rect().end.x + Mecha.BODY.x / 2.0 + 40.0
	await step(3)
	var rival_hp := rival.hp
	kcmd.rb = true
	await step(15)
	check(rival.hp == rival_hp - Game.MECHA_WEAR_PUNCH, "Ville : le coup de poing use l'autre mecha de 3 (%d -> %d)" % [rival_hp, rival.hp])
	# Ville : le parc d'attractions et le parc arboré (captures)
	if shot_dir != "":
		for place in [["ville_fete_foraine", -8000.0, -6900.0], ["ville_parc", 6900.0, 8600.0]]:
			game.fighters[0].global_position = Vector2(place[1], -300.0)
			game.fighters[1].global_position = Vector2(place[2], -300.0)
			await step(120)
			await shot(place[0])
	# Ville : la vitrine des mechas (design) montre le même mecha avec chaque pilote, dans chaque pose
	game.queue_free()
	game = null
	var showroom := (load(MechaShowroom.SCENE) as PackedScene).instantiate() as MechaShowroom
	add_child(showroom)
	await step(2)
	var sizes_ok := showroom.mechas.size() == GameSetup.CHARACTERS.size() and showroom.mechas.all(
		func(m: MechaVisual) -> bool: return m.mecha_size() == MechaVisual.SIZE)
	check(sizes_ok, "Ville : vitrine, un mecha par perso, le même pour tous")
	for i in MechaShowroom.POSE_NAMES.size():
		showroom.show_pose(i)
		await step(50 if i != MechaVisual.Pose.LAND else 60)
		if i == MechaVisual.Pose.WORN:
			for m in showroom.mechas:
				m.wear = 0.9
			await step(2)
		await shot("mecha_%d" % i)
	check(showroom.pose_index == MechaShowroom.POSE_NAMES.size() - 1, "Ville : vitrine, toutes les poses s'affichent")
	showroom.queue_free()
	GameSetup.map_path = GameSetup.MAPS[0]
	GameSetup.player_devices = []
	GameSetup.player_characters = []

	# 13) Check-up : les petits défauts corrigés restent corrigés
	# 13a) Garder B pendant sa propre attaque lourde ne donne pas un blocage parfait juste après
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 250; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = f < 30
		s.block_held = f >= 3)
	await step(5)
	check(p2.is_charging_heavy() and not p2.is_blocking(), "Blocage parfait : J2 charge sa lourde en gardant B")
	for i in 80:  # jusqu'à la première frame où J2 peut enfin bloquer, après sa lourde
		await step(1)
		if p2.is_blocking():
			break
	check(p2.is_blocking() and not p2.is_parrying(), "Blocage parfait : B gardé depuis la lourde ne compte pas comme un appui pile")
	p1.position = Vector2(p2.position.x - 50, p2.position.y); p1.velocity = Vector2.ZERO
	p1._attack_heavy = false
	p1._attack_has_hit = false
	p1._attack_dir = Vector2.RIGHT
	p1._attack_time = light_hit_time
	await step(1)
	check(untouched(p2) and p2.shield == base.shield_max - 1, "Blocage parfait : là, c'est un blocage normal (bouclier %d)" % p2.shield)

	# 13b) Pause pendant la charge d'une lourde : à la reprise, la charge continue (Y toujours tenu)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 250; p2.position.x = 900
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = true)
	await step(15)
	game.open_pause()
	await get_tree().process_frame
	game.close_pause()
	await step(3)
	check(p1.is_charging_heavy(), "Pause : la lourde en charge n'est pas lâchée à la reprise")

	# 13c) Y appuyé juste avant la fin de la recharge de l'attaque légère : la lourde part quand même
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 250; p2.position.x = 900
	p2.input_source = Scripted.new(func(s, f): pass)
	var y_frame := 1 + int(base.attack_cooldown * 60.0) - 4  # Y appuyé 4 frames avant la fin de la recharge
	p1.input_source = Scripted.new(func(s, f):
		s.attack_pressed = f == 1
		s.heavy_pressed = f == y_frame
		s.heavy_held = f >= y_frame)
	await step(y_frame + 12)
	check(p1.is_charging_heavy(), "Attaque lourde : Y appuyé pendant la recharge n'est pas perdu")

	# 13d) À 3 joueurs : J2 et J3 se frappent l'un l'autre avec J1 entre eux -> choc entre J2 et J3,
	# J1 n'est pas touché (avant, ça dépendait de l'ordre des joueurs)
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
	await new_game()
	GameSetup.player_devices = []
	f3 = game.fighters
	for fi in f3:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	f3[0].position = Vector2(600, 540); f3[1].position = Vector2(560, 540); f3[2].position = Vector2(640, 540)
	for k in [1, 2]:
		var fi: Fighter = f3[k]
		fi._attack_heavy = false
		fi._attack_has_hit = false
		fi._attack_dir = Vector2.RIGHT if k == 1 else Vector2.LEFT
		fi._attack_time = light_hit_time
	game._resolve_hits()
	check(untouched(f3[0]) and untouched(f3[1]) and untouched(f3[2]) and not f3[1].is_attacking() and not f3[2].is_attacking(),
		"3 joueurs : J2 et J3 se frappent = choc, J1 entre eux n'est pas touché (vies %d %d %d)" % [f3[0].lives, f3[1].lives, f3[2].lives])

	# 13e) Un duel déjà tranché ne repart pas sur un contre, et un bouclier cassé pendant un duel ne l'écourte pas
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	game._start_duel(p1, p2)
	game._time_engine.stop()
	game._clash(p1, p2, p1.position)
	check(game._time_engine._time_left <= TimeEngine.RAMP_TIME, "Ralenti : un duel tranché ne repart pas sur un contre")
	game._start_duel(p1, p2)
	game._time_engine._time_left = 2.0
	p2.shield = 1
	game._hit_shield(p1, p2, false)
	check(p2.shield_broken and is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION) and is_equal_approx(Engine.time_scale, Game.DUEL_TIME_SCALE),
		"Ralenti : bouclier cassé pendant un duel, le duel continue (%.1f s, vitesse %.2f)" % [game._time_engine._time_left, Engine.time_scale])
	game._time_engine.stop(true)

	# 13f) Menu : Shift droit appartient au joueur du clavier de droite
	var reader := MenuInput.new()
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.location = KEY_LOCATION_RIGHT
	shift.pressed = true
	var read: Dictionary = reader.read(shift)
	check(read.get("device", {}) == {"type": "keyboard", "layout": 1}, "Menu : Shift droit = clavier de droite (%s)" % [read.get("device")])

	# 13g) À 3 ou 4 joueurs, l'attaque légère ne touche pas dans le dos de celui qui frappe
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}],
		[{"type": "joypad", "id": 5}], [{"type": "joypad", "id": 6}]]
	await new_game()
	GameSetup.player_devices = []
	var f4: Array = game.fighters
	var set_light := func(fi: Fighter, dir: Vector2) -> void:
		fi._attack_heavy = false
		fi._attack_has_hit = false
		fi._attack_dir = dir
		fi._attack_time = light_hit_time
		fi._attack_cooldown_timer = 0.0
	for fi in f4:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	# J2 frappe J3 devant lui, J1 est juste derrière J2 : J3 perd une vie, pas J1.
	f4[0].position = Vector2(600, 540); f4[1].position = Vector2(622, 540); f4[2].position = Vector2(640, 540)
	f4[3].position = Vector2(1100, 540)
	set_light.call(f4[1], Vector2.RIGHT)
	game._resolve_hits()
	check(untouched(f4[0]) and touched(f4[2]),
		"4 joueurs : le coup léger touche devant, pas le joueur dans le dos (J1 %d, J3 %d)" % [f4[0].lives, f4[2].lives])
	# Dos à dos : J1 frappe J3 à gauche, J2 frappe J4 à droite -> pas de choc, J3 et J4 sont touchés.
	await step(90)
	for fi in f4:
		fi.lives = 3
		fi._stun_timer = 0.0
		fi._invincible_timer = 0.0
		fi._attack_time = -1.0
		fi.velocity = Vector2.ZERO
	f4[2].position = Vector2(575, 540); f4[0].position = Vector2(600, 540)
	f4[1].position = Vector2(630, 540); f4[3].position = Vector2(655, 540)
	set_light.call(f4[0], Vector2.LEFT)
	set_light.call(f4[1], Vector2.RIGHT)
	game._resolve_clashes()
	game._resolve_hits()
	check(touched(f4[2]) and touched(f4[3]) and untouched(f4[0]) and untouched(f4[1]),
		"4 joueurs : deux coups légers dos à dos ne font pas de choc (vies %d %d %d %d)" % [f4[0].lives, f4[1].lives, f4[2].lives, f4[3].lives])
	# J1 met une lourde dans le dos de J2 pendant que J2 frappe devant lui (vers la droite) :
	# J2 est touché, ce n'est pas un contre (pas de duel au ralenti).
	var duels: Array[String] = []
	for offset in [Vector2(50, -30), Vector2(65, -30), Vector2(80, 0), Vector2(65, 0), Vector2(35, 0)]:
		GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
		await new_game()
		GameSetup.player_devices = []
		f4 = game.fighters
		for fi in f4:
			fi.input_source = Scripted.new(func(s, f): pass)
		await step(30)
		f4[2].position = Vector2(1100, 540)
		f4[0].position = Vector2(600, 540); f4[0].velocity = Vector2.ZERO
		f4[0].input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 1)
		var b: Fighter = f4[1]
		b.input_source = Scripted.new(func(s, f):
			b.position = Vector2(600, 540) + offset; b.velocity = Vector2.ZERO
			if untouched(b):
				set_light.call(b, Vector2.RIGHT))
		var outcome := ""
		for k in 40:
			await step(1)
			if Engine.time_scale < 0.99:
				outcome = "duel"
				break
			if touched(b):
				outcome = "touché"
				break
		if outcome != "touché":
			duels.append("%s : %s" % [offset, outcome if outcome != "" else "rien"])
		game._time_engine.stop(true)
	check(duels.is_empty(), "3 joueurs : une lourde dans le dos d'un joueur qui frappe devant lui le touche, pas de duel %s" % [duels])

	# 13h) Micro-duel à 4 joueurs : la caméra garde tout le monde à l'écran ; à 2, elle zoome sur le duel
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}],
		[{"type": "joypad", "id": 5}], [{"type": "joypad", "id": 6}]]
	await new_game()
	GameSetup.player_devices = []
	for fighter in game.fighters:
		fighter.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	game.fighters[0].position = Vector2(500, 540); game.fighters[1].position = Vector2(560, 540)
	game.fighters[2].position = Vector2(1700, 300); game.fighters[3].position = Vector2(1750, 300)
	game._start_duel(game.fighters[0], game.fighters[1])
	game._update_camera(1.0, true)
	var cam: Camera2D = game._camera
	var view := Rect2(cam.position - game.get_viewport_rect().size / cam.zoom / 2.0, game.get_viewport_rect().size / cam.zoom)
	check(view.has_point(game.fighters[3].position) and view.has_point(game.fighters[0].position),
		"Duel à 4 joueurs : les autres joueurs restent à l'écran (zoom %.2f)" % cam.zoom.x)
	game._time_engine._time_left = 2.0
	game._clash(game.fighters[2], game.fighters[3], game.fighters[2].position)
	check(is_equal_approx(game._time_engine._time_left, 2.0), "Duel à 4 joueurs : un contre entre les 2 autres joueurs ne relance pas le ralenti")
	game._time_engine._time_left = 2.0
	game._clash(game.fighters[0], game.fighters[1], game.fighters[0].position)
	check(is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION), "Duel à 4 joueurs : un contre entre duellistes relance le ralenti")
	game._time_engine._time_left = 2.0
	game._clash(game.fighters[0], game.fighters[2], game.fighters[0].position)
	check(is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION), "Duel à 4 joueurs : un duelliste qui contre un autre joueur relance le ralenti")
	check(game._duel.size() == 2 and game.fighters[0] in game._duel and game.fighters[2] in game._duel,
		"Duel à 4 joueurs : le joueur contré par un duelliste devient duelliste, l'ancien redevient normal")
	game._time_engine._time_left = 2.0
	game._clash(game.fighters[1], game.fighters[3], game.fighters[1].position)
	check(is_equal_approx(game._time_engine._time_left, 2.0), "Duel à 4 joueurs : l'ancien duelliste ne relance plus le ralenti")
	game._on_life_lost(game.fighters[1])
	check(is_equal_approx(game._time_engine._time_left, 2.0), "Duel à 4 joueurs : l'ancien duelliste perd une vie, le ralenti continue")
	game._on_life_lost(game.fighters[2])
	check(game._time_engine._time_left <= TimeEngine.RAMP_TIME, "Duel à 4 joueurs : le nouveau duelliste perd une vie, le ralenti s'arrête")
	var group_zoom := cam.zoom.x
	game._duel.clear()
	game._update_camera(1.0, true)
	check(group_zoom > cam.zoom.x, "Duel à 4 joueurs : la caméra se resserre un peu (%.2f > %.2f)" % [group_zoom, cam.zoom.x])
	game.fighters[2].eliminated = true; game.fighters[3].eliminated = true
	game._start_duel(game.fighters[0], game.fighters[1])
	game._update_camera(1.0, true)
	check(cam.zoom.x > 1.2, "Duel quand il ne reste que 2 joueurs : zoom sur les duellistes (%.2f)" % cam.zoom.x)
	game._time_engine.stop(true)

	# 14) Attaque visée : une pichenette sur le stick droit lance un coup léger dans cette direction
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position = Vector2(500, 540); p2.position = Vector2(560, 540)
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.aimed_attack_pressed = f == 1
		s.aim = Vector2(-1, -1).normalized())
	await step(3)
	check(p1.is_attacking() and p1.attack_direction().is_equal_approx(Vector2(-1, -1).normalized()) and p1.facing < 0,
		"Attaque visée : le coup part vers le stick droit (haut gauche), pas vers J2 (%s)" % p1.attack_direction())
	await step(30)
	check(untouched(p2), "Attaque visée : J2, derrière, n'est pas touché")
	# X juste après : de nouveau la visée automatique vers J2
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	await step(3)
	check(p1.is_attacking() and p1.attack_direction().x > 0.9, "Attaque visée : X vise de nouveau automatiquement J2")
	# À 3 : on touche celui qu'on vise, même s'il n'est pas le plus proche
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
	await new_game()
	GameSetup.player_devices = []
	f3 = game.fighters
	for fi in f3:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	f3[0].position = Vector2(600, 540); f3[1].position = Vector2(650, 540); f3[2].position = Vector2(540, 540)
	f3[0].input_source = Scripted.new(func(s, f):
		s.aimed_attack_pressed = f == 1
		s.aim = Vector2.LEFT)
	await step(10)
	check(untouched(f3[1]) and touched(f3[2]),
		"Attaque visée : à 3, on touche celui qu'on vise, pas le plus proche (J2 %d, J3 %d)" % [f3[1].lives, f3[2].lives])
	# Manette : le stick droit poussé une fois = un seul coup, il faut le relâcher pour le suivant
	InputBindings.register_player(0, [{"type": "joypad", "id": 7}])
	var pad_source := LocalInputSource.new(0)
	var stick_right := func(x: float, y: float) -> void:
		for axis in [[JOY_AXIS_RIGHT_X, x], [JOY_AXIS_RIGHT_Y, y]]:
			var motion := InputEventJoypadMotion.new()
			motion.device = 7
			motion.axis = axis[0]
			motion.axis_value = axis[1]
			Input.parse_input_event(motion)
		Input.flush_buffered_events()
	stick_right.call(0.0, -1.0)
	var first := pad_source.poll()
	var held := pad_source.poll()
	stick_right.call(0.0, 0.0)
	pad_source.poll()
	stick_right.call(0.9, 0.0)
	var second := pad_source.poll()
	stick_right.call(0.0, 0.0)
	check(first.aimed_attack_pressed and first.aim.is_equal_approx(Vector2.UP) and not held.aimed_attack_pressed
		and second.aimed_attack_pressed and second.aim.is_equal_approx(Vector2.RIGHT),
		"Manette : une pichenette du stick droit = un coup visé (haut %s, tenu %s, droite %s)" % [first.aim, held.aimed_attack_pressed, second.aim])

	# 16) Combat plus posé : le coup léger s'arme avant de partir, on a le temps de le contrer,
	# la recharge est plus longue, un premier coup sonne, et les contres remplissent une jauge
	# partagée par tous (phases 1 à 3, puis berserk)
	# 16a) Le coup léger s'arme : il ne touche pas tout de suite, puis la barre se déploie
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30 + int(base.attack_startup * 60.0) - 1)
	check(p1.is_attacking() and not p1.is_attack_active() and untouched(p2), "Coup léger : il s'arme d'abord, pas de coup tout de suite")
	await shot("16_coup_arme")
	await step(3)
	await shot("16_coup_deploye")
	await step(light_frames)
	check(touched(p2), "Coup léger : il part ensuite et touche")

	# 16b) Le coup qui sonne : un premier coup sonne sans retirer de vie ; sonné, le coup suivant retire
	# une vie (puis invincibilité de 1,2 s). Pour s'en sortir : contrer ou blocage parfait.
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	for fi in [p1, p2]:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.is_stunned() and p2.lives == 3, "Coup qui sonne : J2 est sonné, sans perdre de vie")
	check(p2.is_invincible(), "Coup qui sonne : J2 ne peut pas être retouché dans l'instant")
	await shot("16_sonne")
	await step(int(Fighter.STUN_GRACE * 60.0 / Game.STUN_TIME_SCALE) + 2)  # en 1 contre 1, le jeu ralentit tant qu'on est sonné
	check(p2.is_stunned() and not p2.is_invincible(), "Coup qui sonne : J2 est toujours sonné, et plus protégé")
	p1.position = Vector2(p2.position.x - 60, p2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.lives == 2 and not p2.is_stunned() and p2.is_invincible(), "Sonné : le coup suivant retire une vie (vies %d)" % p2.lives)
	await step(int((Fighter.INVINCIBLE_TIME - 0.25) * 60.0))
	check(p2.is_invincible(), "Invincibilité : encore invincible un peu avant %.1f s" % Fighter.INVINCIBLE_TIME)
	await step(30)
	check(not p2.is_invincible() and p2.can_attack(), "Invincibilité : terminée après %.1f s" % Fighter.INVINCIBLE_TIME)
	# Sonné trop longtemps sans être retouché : on redevient normal, le coup suivant sonne à nouveau
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	for fi in [p1, p2]:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	light_now(p1, Vector2.RIGHT)
	await step(int(Fighter.STUN_TIME * 60.0 / Game.STUN_TIME_SCALE) + 5)
	check(not p2.is_stunned(), "Sonné : ça passe au bout de %.0f s" % Fighter.STUN_TIME)
	p1.position = Vector2(p2.position.x - 60, p2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.is_stunned() and p2.lives == 3, "Sonné : passé ce temps, le coup suivant sonne de nouveau (vies %d)" % p2.lives)
	# Sonné, un blocage normal ne protège pas
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(20)
	p2._stun_timer = Fighter.STUN_TIME
	await step(10 + light_frames)
	check(p2.lives == 2 and p2.shield == base.shield_max, "Sonné : un blocage normal ne protège pas (vies %d, bouclier %d)" % [p2.lives, p2.shield])
	# Sonné, un blocage parfait protège et on n'est plus sonné
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= 33)
	await step(20)
	p2._stun_timer = Fighter.STUN_TIME
	await step(10 + light_frames)
	check(p2.lives == 3 and not p2.is_stunned(), "Sonné : un blocage parfait protège et fait sortir de l'état sonné")
	# Sonné, contrer en armant son coup protège aussi
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 680
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 35)
	await step(20)
	p2._stun_timer = Fighter.STUN_TIME
	await step(10 + light_frames)
	check(p2.lives == 3 and not p2.is_stunned() and p1.lives == 3, "Sonné : contrer protège et fait sortir de l'état sonné")

	# 16c) Contrer en armant son coup : J1 frappe, J2 appuie sur X juste après (son coup s'arme quand
	# celui de J1 arrive) -> contre de J2. Personne n'est touché, J2 peut riposter tout de suite,
	# J1 attend la fin de sa recharge, et la jauge de contre monte.
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 680
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 35)
	var counter_seen := false
	for i in 30 + light_frames:
		await step(1)
		if not game.get_children().filter(func(n): return n is ClashMark).is_empty():
			counter_seen = true
			break
	check(counter_seen and untouched(p1) and untouched(p2), "Contre en armant son coup : personne ne perd de vie (%d / %d)" % [p1.lives, p2.lives])
	check(game.gauge.points == 1, "Contre en armant son coup : la jauge de contre monte")
	check(p2.attack_cooldown_left() <= Fighter.CLASH_LOCKOUT and p1.attack_cooldown_left() > 0.15,
		"Contre : J2 peut riposter tout de suite, J1 attend sa recharge (%.2f / %.2f s)" % [p2.attack_cooldown_left(), p1.attack_cooldown_left()])
	# Mais un coup qui arrive dans le dos pendant qu'on arme le sien n'est pas contré
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	for fi in [p1, p2]:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	p1._attack_heavy = false; p1._attack_has_hit = false; p1._attack_dir = Vector2.RIGHT; p1._attack_time = light_hit_time
	p2._attack_heavy = false; p2._attack_has_hit = false; p2._attack_dir = Vector2.RIGHT; p2._attack_time = 0.02
	game._resolve_hits()
	check(touched(p2), "Contre : un coup dans le dos pendant qu'on arme le sien touche quand même")

	# 16d) Jauge de contre : 4 contres pour la phase 2 (une lourde contrée compte pour 3), puis 3 et berserk
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	for fi in [p1, p2]:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	var g: CounterGauge = game.gauge
	check(p1.gauge == g and p2.gauge == g, "Jauge : une seule jauge pour tous les joueurs")
	for k in 3:
		g.add_counter(false)
	check(p1.counter_phase() == 1 and p2.counter_phase() == 1, "Jauge : 3 contres, toujours en phase 1")
	g.add_counter(false)
	check(p1.counter_phase() == 2 and p2.counter_phase() == 2, "Jauge : 4 contres, phase 2 pour les deux joueurs")
	g.points = 0.0
	g.add_counter(true)
	g.add_counter(false)
	check(g.phase() == 2, "Jauge : une lourde contrée + un contre, phase 2")
	g.points = CounterGauge.PHASE_POINTS[1]
	check(p1.counter_phase() == 3, "Jauge : phase 3 à %d points" % CounterGauge.PHASE_POINTS[1])
	g.points = CounterGauge.PHASE_POINTS[2] - 1
	g.add_counter(false)
	check(p1.is_berserk() and p2.is_berserk() and g.flash_timer > 0.0, "Jauge : berserk à %d points, pour tout le monde" % CounterGauge.PHASE_POINTS[2])
	for k in 10:
		g.add_counter(true)
	check(g.points == CounterGauge.MAX_POINTS, "Jauge : elle ne dépasse pas %.0f points" % CounterGauge.MAX_POINTS)
	# Recharge plus courte selon la phase
	var cooldowns := []
	for points in [0.0, CounterGauge.PHASE_POINTS[0], CounterGauge.PHASE_POINTS[1], CounterGauge.PHASE_POINTS[2]]:
		g.points = points
		cooldowns.append(p1._cooldown(false))
	check(cooldowns[0] == base.attack_cooldown and cooldowns[0] > cooldowns[1] and cooldowns[1] > cooldowns[2] and cooldowns[2] > cooldowns[3],
		"Jauge : la recharge raccourcit à chaque phase (%s)" % [cooldowns])
	# Plus de dégâts au bouclier en phase 2 et 3
	var damages := []
	for points in [0.0, CounterGauge.PHASE_POINTS[0], CounterGauge.PHASE_POINTS[1]]:
		g.points = points
		damages.append(p1.shield_damage(false))
	g.points = CounterGauge.PHASE_POINTS[1]
	check(damages == [1, 2, 3] and p1.shield_damage(true) == 6, "Jauge : coups au bouclier x1, x2, x3 (lourde en phase 3 : %d)" % p1.shield_damage(true))
	g.points = CounterGauge.PHASE_POINTS[0]
	g._idle_timer = 10.0
	p1.position = Vector2(600, 540); p2.position = Vector2(650, 540)
	p1.velocity = Vector2.ZERO
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(20)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	await step(2 + light_frames)
	check(p2.shield == base.shield_max - 2, "Jauge en phase 2 : un coup léger fait craquer 2 points de bouclier (%d)" % p2.shield)
	await shot("16_jauge")

	# 16e) Berserk : on court plus vite, on saute plus haut, les coups partent plus vite et vont plus loin
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.position.x = 1300
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): s.stick.x = 1.0 if f >= 20 and f < 50 else 0.0)
	await step(20)
	game.gauge.points = CounterGauge.MAX_POINTS
	game.gauge._idle_timer = 100.0
	await step(25)
	check(absf(p1.velocity.x - base.run_speed * Fighter.BERSERK_MOVE) < 5.0, "Berserk : court plus vite (%.0f)" % p1.velocity.x)
	await shot("16_berserk")
	await step(30)
	p1.position = Vector2(600, 540)
	p1._attack_heavy = false; p1._attack_has_hit = false; p1._attack_dir = Vector2.RIGHT; p1._attack_time = light_hit_time
	var berserk_reach := p1.attack_center().x - p1.position.x + base.attack_radius
	check(absf(berserk_reach - base.attack_reach * Fighter.BERSERK_RANGE) < 1.0, "Berserk : le coup léger va plus loin (%.0f px)" % berserk_reach)
	p1._attack_time = -1.0
	p1._attack_cooldown_timer = 0.0
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	var frames_to_active := 0
	for i in 20:
		await step(1)
		if p1.is_attack_active():
			frames_to_active = i
			break
	check(frames_to_active > 0 and frames_to_active < int(base.attack_startup * 60.0),
		"Berserk : le coup part plus vite (%d frames)" % frames_to_active)

	# 16f) La jauge redescend quand on ne contre plus
	await new_game()
	p1 = game.fighters[0]
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(10)
	for k in 5:
		game.gauge.add_counter(false)
	await step(int((CounterGauge.IDLE_TIME - 0.5) * 60.0))
	check(game.gauge.points == 5, "Jauge : elle ne bouge pas juste après un contre (%.1f)" % game.gauge.points)
	await step(int(2.5 * 60.0))
	check(p1.counter_phase() == 1 and game.gauge.points > 0.0, "Jauge : sans contre, elle redescend (%.1f, phase %d)" % [game.gauge.points, p1.counter_phase()])

	# 16g) 1 contre 1 : tant qu'un joueur est sonné -> zoom et léger ralenti ; une vie perdue -> l'écran tremble
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	for fi in [p1, p2]:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	var normal_zoom: float = game._camera.zoom.x
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.is_stunned() and game._stun_focus.size() == 2 and is_equal_approx(Engine.time_scale, Game.STUN_TIME_SCALE) and game._shake_left == 0.0,
		"Coup qui sonne en 1 contre 1 : zoom et léger ralenti (vitesse %.2f), l'écran ne tremble pas" % Engine.time_scale)
	for i in 20:
		await get_tree().process_frame
	check(game._camera.zoom.x > normal_zoom + 0.2, "Joueur sonné : la caméra zoome (%.2f -> %.2f)" % [normal_zoom, game._camera.zoom.x])
	await shot("16_coup_zoom")
	await step(60)
	check(p2.is_stunned() and is_equal_approx(Engine.time_scale, Game.STUN_TIME_SCALE), "Joueur sonné : le ralenti dure tant qu'il est sonné")
	game._time_engine._time_left = 1.0
	game._renew_slowmo(p1, p2)
	check(game._time_engine._time_left <= 1.0, "Joueur sonné : un contre ne relance pas ce ralenti")
	game._time_engine._time_left = 5.0
	var stun_frames := 0
	while p2.is_stunned() and stun_frames < 400:
		await step(1)
		stun_frames += 1
	check(game._stun_focus.is_empty() and game._time_engine._time_left <= TimeEngine.RAMP_TIME,
		"Plus sonné (au bout du temps) : le ralenti s'arrête et la caméra se détend")
	await step(40)
	check(is_equal_approx(Engine.time_scale, 1.0) and p2.lives == 3, "Plus sonné : tout revient à la normale, sans vie perdue")
	# Sauvé par un contre ou un blocage parfait : le ralenti s'arrête tout de suite
	p1.position = Vector2(p2.position.x - 60, p2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.is_stunned() and Engine.time_scale < 1.0, "Sonné une 2e fois : le ralenti repart")
	p2.recover()
	await step(1)
	check(game._stun_focus.is_empty() and game._time_engine._time_left <= TimeEngine.RAMP_TIME, "Sauvé (contre ou blocage parfait) : le ralenti s'arrête")
	p2._invincible_timer = 0.0
	p1.position = Vector2(p2.position.x - 60, p2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.is_stunned() and is_equal_approx(Engine.time_scale, Game.STUN_TIME_SCALE) and game._time_engine._time_left > TimeEngine.RAMP_TIME,
		"Resonné pendant le retour à la normale : le ralenti repart tout de suite (vitesse %.2f)" % Engine.time_scale)
	p2.recover()
	await step(40)
	# Un micro-duel pendant qu'un joueur est sonné : le duel garde son ralenti, celui du sonné ne l'écrase pas
	p1.position = Vector2(p2.position.x - 60, p2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	game._start_duel(p1, p2)
	await step(1)
	check(p2.is_stunned() and is_equal_approx(Engine.time_scale, Game.DUEL_TIME_SCALE), "Sonné pendant un micro-duel : le ralenti du duel reste")
	game._time_engine._time_left = 0.05  # le duel se termine alors que J2 est encore sonné
	await step(6)
	check(p2.is_stunned() and game._duel.is_empty() and is_equal_approx(Engine.time_scale, Game.STUN_TIME_SCALE),
		"Duel fini, J2 encore sonné : le ralenti du sonné reprend et le duel est bien terminé (vitesse %.2f)" % Engine.time_scale)
	game._on_life_lost(p1)
	check(is_equal_approx(Engine.time_scale, Game.STUN_TIME_SCALE), "Duel fini : il n'arrête plus le ralenti du sonné")
	game._start_duel(p1, p2)
	await step(1)
	p2.recover()
	await step(1)
	check(game._time_engine._time_left > 4.0, "Sonné pendant un micro-duel : la fin du coup qui sonne n'arrête pas le duel")
	game._time_engine.stop(true)
	game._duel.clear()
	await step(1)
	# Une vie perdue : l'écran tremble, puis se calme
	p2._stun_timer = Fighter.STUN_TIME
	p2._invincible_timer = 0.0
	p1.position = Vector2(p2.position.x - 60, p2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	await get_tree().process_frame
	check(p2.lives == 2 and game._shake_left > 0.0 and game._camera.offset.length() > 0.0 and game._stun_focus.is_empty(),
		"Vie perdue : l'écran tremble (%.1f px), pas de zoom" % game._camera.offset.length())
	await shot("16_vie_perdue")
	await step(40)
	check(game._shake_left == 0.0 and game._camera.offset == Vector2.ZERO, "Vie perdue : l'écran arrête de trembler")
	p1.position = Vector2(640, game.map.blast_zone.end.y + 200)
	await step(1)
	check(p1.lives == 2 and game._shake_left > 0.0, "Chute : l'écran tremble aussi")
	await step(40)
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
	await new_game()
	GameSetup.player_devices = []
	f3 = game.fighters
	for fi in f3:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	f3[0].position = Vector2(600, 540); f3[1].position = Vector2(660, 540); f3[2].position = Vector2(1200, 540)
	light_now(f3[0], Vector2.RIGHT)
	await step(1)
	check(f3[1].is_stunned() and game._stun_focus.is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		"Joueur sonné à 3 joueurs : pas de zoom ni de ralenti")
	f3[1]._invincible_timer = 0.0
	f3[0].position = Vector2(f3[1].position.x - 60, f3[1].position.y); f3[0].velocity = Vector2.ZERO
	light_now(f3[0], Vector2.RIGHT)
	await step(1)
	check(f3[1].lives == 2 and game._shake_left > 0.0, "Vie perdue à 3 joueurs : l'écran tremble")

	# 18) Les armes (choisies avec le perso) : katana, marteau, lance
	var katana := load(GameSetup.WEAPONS[1]) as WeaponStats
	var hammer := load(GameSetup.WEAPONS[2]) as WeaponStats
	var spear_weapon := load(GameSetup.WEAPONS[3]) as WeaponStats
	# 18a) Katana : coup léger qui se martèle et pousse à peine
	GameSetup.player_weapons = [GameSetup.WEAPONS[1], GameSetup.WEAPONS[0]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	check(is_equal_approx(p1.stats.attack_cooldown, base.attack_cooldown * katana.light_cooldown_mult)
		and is_equal_approx(p2.stats.attack_cooldown, base.attack_cooldown), "Katana : recharge du coup léger bien plus courte (J2 à mains nues)")
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.is_stunned() and absf(p2.velocity.x) < base.hit_knockback * 0.4, "Katana : le coup léger pousse à peine (vx %.0f)" % p2.velocity.x)
	# 18b) Katana : la lourde est un dash tranchant qui traverse l'adversaire
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 30
		s.heavy_held = f >= 30 and f < 34)
	await step(29)
	p1.position.x = 500; p2.position.x = 700
	var dashed_through := false
	var safe_while_dashing := true
	for i in 30:
		await step(1)
		if p1.is_katana_dashing() and p1.can_be_hit():
			safe_while_dashing = false
		if p1.position.x > p2.position.x:
			dashed_through = true
		if i == 12:
			await shot("18_katana_dash")
	check(dashed_through and touched(p2), "Katana : la lourde traverse l'adversaire et le touche (J1 x %.0f, J2 x %.0f)" % [p1.position.x, p2.position.x])
	check(safe_while_dashing, "Katana : on ne peut pas être touché pendant le dash tranchant")
	# 18c) ... mais un coup léger qui s'arme vers lui le contre : micro-duel
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 30
		s.heavy_held = f >= 30 and f < 34)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 39)
	await step(29)
	p1.position.x = 500; p2.position.x = 700
	await step(30)
	check(untouched(p2) and untouched(p1) and not game._duel.is_empty(), "Katana : le dash tranchant contré par un coup léger -> micro-duel")
	# 18c bis) Toute lourde d'une arme contrée l'use : plus petite, cassée au 3e contre (court ralenti zoomé)
	check(p1.weapon_counters == 1 and p1.weapon_length() < 1.0 and p1._armed_stats.attack_reach < p1._bare_stats.attack_reach * p1.weapon.light_reach_mult,
		"Arme usée : le katana contré rapetisse")
	check(not game._wear_weapon(p2, p1) and p2.weapon_counters == 0, "Arme usée : à mains nues, rien ne s'use")
	check(not game._wear_weapon(p1, p2) and p1.weapon_counters == 2, "Arme usée : 2e contre, pas encore cassée")
	check(game._wear_weapon(p1, p2) and p1.is_weapon_broken() and p1.weapon_away and p1.heavy_kind() == WeaponStats.Heavy.SWING,
		"Arme usée : au 3e contre l'arme casse (mains nues)")
	await step(2)
	check(Engine.time_scale < 0.5 and game._break_focus == [p1, p2], "Arme cassée : court ralenti et zoom sur les deux joueurs")
	await step(120)
	check(game._break_focus.is_empty() and Engine.time_scale > 0.99, "Arme cassée : le ralenti est court")
	p1.position = Vector2(640, 2000)
	await step(2)
	check(p1.weapon_away and p1.is_weapon_broken() and p1.heavy_kind() == WeaponStats.Heavy.SWING,
		"Arme cassée : perdre une vie ne la rend pas")
	# 18d) Marteau : le coup léger projette bien plus loin ; la lourde fait une onde de choc au sol
	GameSetup.player_weapons = [GameSetup.WEAPONS[2], GameSetup.WEAPONS[0]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(p2.velocity.x > base.hit_knockback * 1.5, "Marteau : le coup léger projette loin (vx %.0f)" % p2.velocity.x)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 30
		s.heavy_held = f >= 30 and f < 34)
	await step(29)
	p1.position.x = 600; p2.position.x = 735  # trop loin pour l'arc, mais dans l'onde de choc
	var wave_seen := false
	for i in 30:
		await step(1)
		if p1._is_slam_wave() and p1.is_attack_active():
			if not wave_seen:
				await shot("18_marteau_onde")
			wave_seen = true
	check(wave_seen and touched(p2), "Marteau : l'onde de choc au sol touche plus loin que l'arc")
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 30
		s.heavy_held = f >= 30 and f < 34)
	await step(29)
	p1.position.x = 600; p2.position.x = 650
	await step(30)
	check(p2.shield == base.shield_max - Fighter.HEAVY_SHIELD_DAMAGE * hammer.heavy_shield_damage and untouched(p2),
		"Marteau : la lourde abîme 2 fois plus les boucliers (reste %d)" % p2.shield)
	# 18e) Lance : coup léger très long ; la lourde la lance, on la ramasse en passant dessus
	GameSetup.player_weapons = [GameSetup.WEAPONS[3], GameSetup.WEAPONS[0]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 30
		s.heavy_held = f >= 30 and f < 34)
	await step(29)
	check(is_equal_approx(p1.stats.attack_reach, base.attack_reach * spear_weapon.light_reach_mult), "Lance : le coup léger va bien plus loin")
	p1.position.x = 400; p2.position.x = 800
	await step(12)
	await step(4)
	await shot("18_lance_vol")
	check(p1.weapon_away and game.projectiles.size() == 1 and is_equal_approx(p1.stats.attack_reach, base.attack_reach),
		"Lance : la lourde lance la lance ; en attendant, on se bat à mains nues")
	for i in 40:
		await step(1)
	check(touched(p2) and game.projectiles.size() == 1 and game.projectiles[0].state != Projectile.State.FLYING,
		"Lance : la lance touche l'adversaire, puis retombe")
	await step(60)
	check(game.projectiles[0].state == Projectile.State.STUCK, "Lance : elle se plante au sol")
	var spear_x: float = game.projectiles[0].position.x
	p1.input_source = Scripted.new(func(s, f): s.stick.x = 1.0 if p1.position.x < spear_x else -1.0)
	for i in 120:
		await step(1)
		if not p1.weapon_away:
			break
	check(not p1.weapon_away and game.projectiles.is_empty() and is_equal_approx(p1.stats.attack_reach, base.attack_reach * spear_weapon.light_reach_mult),
		"Lance : on la ramasse en passant dessus")
	# 18f) Lance lancée puis perdue : on reste à mains nues, même en perdant une vie
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 2
		s.heavy_held = f >= 2 and f < 6)
	p1._attack_cooldown_timer = 0.0
	await step(14)
	check(p1.weapon_away, "Lance : relancée")
	game.projectiles[0].position = Vector2(640, 5000)
	await step(1)
	check(p1.weapon_away and game.projectiles.is_empty(), "Lance : sortie de la map, elle est perdue (on reste à mains nues)")
	p1.position = Vector2(640, 2000)
	await step(2)
	check(p1.weapon_away and game.projectiles.is_empty(), "Lance : perdre une vie ne la rend pas")
	p1.weapon_away = false
	# 18g) Lance lancée contrée : un coup dessus la fait retomber (plus courte), 3 contres la cassent
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 3)
	p1.position = Vector2(300, 560); p2.position = Vector2(700, 560)
	p2._attack_cooldown_timer = 0.0
	p2.recover()
	await step(1)
	for i in 30:
		await step(1)
		if p2.is_attack_active():
			break
	check(p2.is_attack_active(), "Lance contrée : le coup léger de l'adversaire est sorti")
	var points_before: float = game.gauge.points
	p1.weapon_away = true
	game._on_weapon_thrown(p1, Vector2.RIGHT, 300.0)
	var spear: Projectile = game.projectiles[0]
	spear.position = p2.attack_center()
	spear.velocity = Vector2(300, 0)
	await step(1)
	check(p1.weapon_counters == 1 and spear.state == Projectile.State.DROPPED and untouched(p2),
		"Lance contrée : frappée en vol, elle retombe sans toucher")
	check(game.gauge.points > points_before and p2.attack_cooldown_left() == 0.0,
		"Lance contrée : ça compte comme un contre (jauge, recharge à zéro)")
	check(spear.length < Projectile.SPEAR_LENGTH and p1._armed_stats.attack_reach < base.attack_reach * spear_weapon.light_reach_mult,
		"Lance contrée : elle est plus courte (lancée et en main)")
	game._counter_spear(spear, p2)
	check(p1.weapon_counters == 2 and not p1.is_weapon_broken() and game.projectiles.size() == 1, "Lance contrée 2 fois : pas encore cassée")
	game._counter_spear(spear, p2)
	check(p1.is_weapon_broken() and game.projectiles.is_empty() and p1.weapon_away, "Lance contrée 3 fois : cassée")
	# Contrée pointe en l'air (lancée vers le haut), elle retombe et se plante : elle ne traverse
	# pas le sol (avant, seul le bout de devant cherchait le sol).
	var through_floor := []
	for angle in [-150.0, -90.0, -30.0]:
		var dropped := Projectile.new()
		dropped.kind = "lance" if through_floor.size() % 2 == 0 else "fleche"
		dropped.position = Vector2(500, 520)  # entre les deux joueurs (sinon J2 la ramasse)
		dropped.rotation = deg_to_rad(angle)
		dropped.velocity = Vector2(900, 0).rotated(dropped.rotation)
		game._add_projectile(dropped)
		dropped.drop()
		for i in 120:
			await step(1)
			if not is_instance_valid(dropped) or dropped.state == Projectile.State.STUCK:
				break
		var ok := is_instance_valid(dropped) and dropped.state == Projectile.State.STUCK and dropped.tip().y < 575.0
		through_floor.append(ok)
		if is_instance_valid(dropped):
			game._remove_projectile(dropped)
	check(not false in through_floor, "Lance contrée : pointe en l'air, elle retombe sans traverser le sol (%s)" % [through_floor])
	p1._attack_cooldown_timer = 0.0
	p1.get_weapon_back()
	check(p1.weapon_away and p1.heavy_kind() == WeaponStats.Heavy.SWING and is_equal_approx(p1.stats.attack_reach, base.attack_reach),
		"Lance cassée : on reste à mains nues")
	p1.position = Vector2(640, 2000)
	await step(2)
	check(p1.weapon_away and p1.is_weapon_broken() and is_equal_approx(p1.stats.attack_reach, base.attack_reach),
		"Lance cassée : perdre une vie ne la rend pas")
	# 18h) Contrer 2 fois avec le coup léger de son arme la répare d'un cran (pas au-delà de 100 %)
	GameSetup.player_weapons = [GameSetup.WEAPONS[1], GameSetup.WEAPONS[0]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.weapon_counters = 2
	game._clash(p2, p1, p1.position, p1)
	check(p1.weapon_counters == 2, "Arme réparée : 1 contre au coup léger ne suffit pas")
	game._clash(p2, p1, p1.position, p1)
	check(p1.weapon_counters == 1 and p1._repair_flash_timer > 0.0 and p1._armed_stats.attack_reach > p1._bare_stats.attack_reach * katana.light_reach_mult * 0.7,
		"Arme réparée : 2 contres au coup léger = 1 cran regagné (60 % -> 80 %)")
	game._clash(p1, p2, p1.position)  # deux légères qui se percutent : chacun a contré
	game._clash(p1, p2, p1.position)
	check(p1.weapon_counters == 0 and is_equal_approx(p1.weapon_length(), 1.0), "Arme réparée : de nouveau neuve")
	game._clash(p2, p1, p1.position, p1)
	game._clash(p2, p1, p1.position, p1)
	p1.weapon_counters = 1
	game._clash(p2, p1, p1.position, p1)
	check(p1.weapon_counters == 1, "Arme réparée : une arme neuve ne garde pas de contres d'avance")
	game._clash(p1, p2, p1.position, p2)
	check(p1.weapon_counters == 1, "Arme réparée : il faut que ce soit nous qui contrions")
	p1.weapon_counters = Fighter.WEAPON_MAX_COUNTERS
	p1.weapon_away = true
	game._clash(p2, p1, p1.position, p1)
	game._clash(p2, p1, p1.position, p1)
	check(p1.is_weapon_broken() and p1.weapon_away, "Arme réparée : une arme cassée ne se répare pas")
	# 18i) Blocage parfait : l'arme de celui qui frappait lui saute des mains, vers l'arrière, en cloche
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= 29 and f < 45)
	await step(31 + light_frames)
	check(untouched(p2) and p1.weapon_away and game.projectiles.size() == 1 and game.projectiles[0].kind == "arme",
		"Arme projetée : un blocage parfait fait sauter l'arme des mains")
	var knocked: Projectile = game.projectiles[0]
	check(knocked.velocity.x < 0.0 and knocked.velocity.y < 0.0 and is_equal_approx(p1.stats.attack_reach, base.attack_reach),
		"Arme projetée : elle part en cloche loin de celui qui bloque ; mains nues en attendant")
	await step(8)
	await shot("18_arme_projetee")
	for i in 120:
		await step(1)
		if knocked.state == Projectile.State.STUCK:
			break
	check(knocked.state == Projectile.State.STUCK and untouched(p1) and untouched(p2), "Arme projetée : elle retombe au sol sans toucher personne")
	await shot("18_arme_au_sol")
	var knocked_x := knocked.position.x
	p1.input_source = Scripted.new(func(s, f): s.stick.x = 1.0 if p1.position.x < knocked_x else -1.0)
	for i in 180:
		await step(1)
		if not p1.weapon_away:
			break
	check(not p1.weapon_away and game.projectiles.is_empty() and is_equal_approx(p1.stats.attack_reach, base.attack_reach * katana.light_reach_mult),
		"Arme projetée : on la ramasse en passant dessus")
	# ... on ne la rattrape pas tout de suite, et plus la jauge est haute, plus elle part loin
	p1.input_source = Scripted.new(func(s, f): pass)
	game.gauge.points = 0.0
	game._knock_weapon(p1, Vector2.LEFT)
	var slow_speed: float = game.projectiles[0].velocity.length()
	await step(2)
	check(p1.weapon_away and game.projectiles.size() == 1, "Arme projetée : on ne la rattrape pas dans la seconde")
	game._pick_up_weapon(p1, game.projectiles[0])
	check(not p1.weapon_away and game.projectiles.is_empty(), "Arme projetée : ramassée, on l'a de nouveau en main")
	game.gauge.points = CounterGauge.MAX_POINTS
	game._knock_weapon(p1, Vector2.LEFT)
	check(game.projectiles[0].velocity.length() > slow_speed * 2.0,
		"Arme projetée : jauge berserk, elle part bien plus loin (%.0f contre %.0f)" % [game.projectiles[0].velocity.length(), slow_speed])
	game._pick_up_weapon(p1, game.projectiles[0])
	game.gauge.points = 0.0
	# ... à mains nues rien ne s'envole, et une lourde qui casse l'arme ne la fait pas voler
	game._knock_weapon(p2, Vector2.RIGHT)
	check(game.projectiles.is_empty(), "Arme projetée : à mains nues, rien ne s'envole")
	p1.weapon_counters = Fighter.WEAPON_MAX_COUNTERS - 1
	p1._attack_heavy = true
	p1._attack_time = 0.0
	game._parry(p1, p2)
	check(p1.is_weapon_broken() and game.projectiles.is_empty(), "Arme projetée : une arme qui casse sur le blocage ne s'envole pas")
	# 18j) RB : on lance son arme vers l'adversaire, sans dégâts. Un joueur armé la fait rebondir ;
	# un joueur à mains nues l'attrape (usée comme avant)
	GameSetup.player_weapons = [GameSetup.WEAPONS[1], GameSetup.WEAPONS[2]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 400; p2.position.x = 800
	p1.input_source = Scripted.new(func(s, f): s.throw_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	for i in 60:
		await step(1)
		if p1.weapon_away:
			break
	check(p1.weapon_away and not p1.has_weapon_in_hand() and game.projectiles.size() == 1 and game.projectiles[0].kind == "arme"
		and game.projectiles[0].velocity.x > 0.0, "RB : on lance son arme vers l'adversaire")
	var tossed: Projectile = game.projectiles[0]
	var bounced := false
	for i in 60:
		await step(1)
		if tossed.velocity.x < 0.0:
			bounced = true
			break
	check(bounced and untouched(p2) and p2.weapon == hammer and p2.has_weapon_in_hand(), "RB : elle rebondit sur un joueur armé, sans lui faire mal")
	game._remove_projectile(tossed)
	p1.equip(katana, 1)
	p2.weapon_away = true  # p2 à mains nues
	p1.input_source = Scripted.new(func(s, f): s.throw_pressed = f == 1)
	await step(2)
	check(p1.weapon_away and game.projectiles.size() == 1, "RB : relancée")
	for i in 60:
		await step(1)
		if p2.has_weapon_in_hand():
			break
	check(p2.has_weapon_in_hand() and p2.weapon == katana and p2.weapon_counters == 1 and game.projectiles.is_empty() and untouched(p2)
		and is_equal_approx(p2.stats.attack_reach, p2._bare_stats.attack_reach * katana.light_reach_mult * 0.8),
		"RB : à mains nues, l'adversaire l'attrape en vol, usée comme avant")
	p1.input_source = Scripted.new(func(s, f): s.throw_pressed = f == 1)
	await step(3)
	check(game.projectiles.is_empty(), "RB : à mains nues, rien à lancer")
	GameSetup.player_weapons = []

	# 19) Les objets qui tombent sur la map : pistolet, grenade, bouclier (RT pour les utiliser)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	# 19a) Un objet tombe du ciel, on le ramasse en passant dessus (un seul à la fois)
	p1.position.x = 150  # rien au-dessus (pas de plateforme)
	game.spawn_pickup("pistolet", Vector2(p1.position.x, 200))
	game.spawn_pickup("grenade", Vector2(p1.position.x, 100))
	await step(60)
	check(p1.item == "pistolet" and p1.item_ammo == Fighter.PISTOL_AMMO and game.pickups.size() == 1 and game.pickups[0].landed,
		"Objets : on ramasse le pistolet en passant dessus ; la grenade reste par terre (un seul objet à la fois)")
	await shot("19_objet_par_terre")
	# 19b) Pistolet : une balle par appui sur RT, elle touche l'adversaire
	game._remove_pickup(game.pickups[0])
	p1.position = Vector2(400, 540); p2.position = Vector2(900, 540)
	p1.input_source = Scripted.new(func(s, f): s.item_pressed = f == 1)
	await step(3)
	check(game.projectiles.size() == 1 and game.projectiles[0].kind == "balle" and p1.item_ammo == Fighter.PISTOL_AMMO - 1,
		"Pistolet : RT tire une balle (reste %d)" % p1.item_ammo)
	await shot("19_balle")
	for i in 30:
		await step(1)
	check(touched(p2) and game.projectiles.is_empty(), "Pistolet : la balle touche l'adversaire")
	p1.input_source = Scripted.new(func(s, f): s.item_pressed = f % 15 == 1)
	await step(70)
	check(p1.item == "", "Pistolet : vide après 5 balles, le slot se libère")
	# 19b2) Une balle sur un joueur invincible (il clignote) s'arrête sur lui sans effet (avant, elle le
	# traversait lentement pendant les ralentis et semblait coincée dans le perso) ; un dash la laisse passer.
	await step(60)
	for p in game.projectiles.duplicate():
		game._remove_projectile(p)
	p2.position = Vector2(900, 540); p2.velocity = Vector2.ZERO
	p2._stun_timer = 0.0; p2._invincible_timer = 5.0
	var lives_bullet := p2.lives
	game._on_item_used(p1, "balle", Vector2.RIGHT, 1.0, 0.0)
	var stopped := false
	for i in 30:
		await step(1)
		if game.projectiles.is_empty():
			stopped = true
			break
	check(stopped and not p2.is_stunned() and p2.lives == lives_bullet and game.projectiles.is_empty(),
		"Pistolet : la balle s'arrête sur un joueur invincible, sans effet (pas coincée dedans)")
	p2._invincible_timer = 0.0
	p2.position = Vector2(560, 540)
	game._on_item_used(p1, "balle", Vector2.RIGHT, 1.0, 0.0)
	var lives_dash := p2.lives
	for i in 10:  # J2 dashe sur place pendant que la balle arrive
		p2.position = Vector2(560, 540)
		p2._dash_timer = 1.0; p2._dash_dir = Vector2.UP
		await step(1)
	var passed: bool = not game.projectiles.is_empty() and game.projectiles[0].position.x > p2.position.x + 20.0
	p2._dash_timer = 0.0
	check(passed and not p2.is_stunned() and p2.lives == lives_dash, "Pistolet : un dash esquive la balle (elle passe au travers)")
	for p in game.projectiles.duplicate():
		game._remove_projectile(p)
	# 19b3) Canon collé à un mur : la balle s'arrête dans le mur au lieu de partir de l'intérieur et de le traverser
	p1.position = Vector2(-59, 330)
	game._on_item_used(p1, "balle", Vector2.LEFT, 1.0, 0.0)
	check(game.projectiles.is_empty(), "Pistolet : tiré collé à un mur, la balle ne traverse pas le mur")
	# 19b4) Partie finie : une balle arrivée dans un mur ne reste pas figée à l'écran
	var frozen := Projectile.new()
	frozen.kind = "balle"; frozen.finished = true; frozen.simulate = false
	game._add_projectile(frozen)
	game._match_over = true
	await step(2)
	check(game.projectiles.is_empty(), "Partie finie : les balles arrêtées sont retirées")
	# 19c) Renvoi de balle au bon moment (timing parfait) : droit sur le tireur, et c'est un contre
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(300, 540); p2.position = Vector2(900, 540)
	var gauge_before: float = game.gauge.points
	var bullet := Projectile.new()
	bullet.kind = "balle"; bullet.owner_index = 0; bullet.length = 16.0
	bullet.position = Vector2(860, 540); bullet.velocity = Vector2(game.BULLET_SPEED, 0.0)
	game._add_projectile(bullet)
	p2._attack_heavy = false; p2._attack_has_hit = false; p2._attack_dir = Vector2.LEFT; p2._attack_cooldown_timer = 0.0
	p2._attack_time = p2.stats.light_startup()
	await step(1)
	var to_shooter := (p1.global_position - bullet.position).normalized()
	check(bullet.owner_index == 1 and bullet.velocity.normalized().dot(to_shooter) > 0.99 and game.gauge.points > gauge_before,
		"Renvoi parfait : la balle repart droit sur le tireur, ça compte comme un contre")
	for i in 40:
		await step(1)
	check(touched(p1), "Renvoi parfait : le tireur est touché par sa propre balle")
	# 19d) Renvoi en retard : la balle est déviée (vers le haut), jusqu'à 90°
	bullet = Projectile.new()
	bullet.kind = "balle"; bullet.owner_index = 0; bullet.length = 16.0
	p2.position = Vector2(900, 540)
	bullet.position = Vector2(860, 540); bullet.velocity = Vector2(game.BULLET_SPEED, 0.0)
	game._add_projectile(bullet)
	p2._attack_heavy = false; p2._attack_has_hit = false; p2._attack_dir = Vector2.LEFT
	p2._attack_time = p2.stats.light_startup() + p2.stats.attack_active * 0.85
	await step(1)
	var deviation := rad_to_deg(bullet.velocity.angle_to((p1.global_position - p2.global_position)))
	check(bullet.owner_index == 1 and absf(deviation) > 50.0 and bullet.velocity.y < 0.0,
		"Renvoi en retard : la balle est déviée vers le haut (%.0f°)" % deviation)
	# 19e) Grenade : RT gardé = dégoupillée ; plus on garde, plus elle part loin
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 31
		s.item_held = f >= 31 and f < 34)
	await step(30)
	p1.take_item("grenade")
	await step(6)
	var short_throw: float = game.projectiles[0].velocity.length() if game.projectiles.size() == 1 else 0.0
	game._remove_projectile(game.projectiles[0])
	p1.take_item("grenade")
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f >= 1 and f < 70)
	await step(40)
	await shot("19_grenade_degoupillee")
	await step(35)
	var long_throw: float = game.projectiles[0].velocity.length() if game.projectiles.size() == 1 else 0.0
	check(short_throw > 0.0 and long_throw > short_throw * 1.8 and p1.item == "",
		"Grenade : plus on garde RT, plus elle part loin (%.0f -> %.0f)" % [short_throw, long_throw])
	check(game.projectiles[0].blast > 1.3, "Grenade : chargée à fond, son explosion projette plus fort")
	check(game.projectiles[0].fuse < Fighter.GRENADE_FUSE - 1.0, "Grenade : la mèche a commencé dès l'appui (reste %.1f s)" % game.projectiles[0].fuse)
	# 19f) Elle explose au bout de sa mèche : ceux qui sont autour sont touchés et éjectés
	game.projectiles[0].position = p2.position + Vector2(-40, 0); game.projectiles[0].velocity = Vector2.ZERO
	game.projectiles[0].fuse = 0.05
	await step(5)
	check(game.projectiles.is_empty() and touched(p2) and p2.velocity.x > 300, "Grenade : l'explosion touche et éjecte (vx %.0f)" % p2.velocity.x)
	# 19g) Frappée par un coup, elle repart dans le sens du coup
	var grenade := Projectile.new()
	grenade.kind = "grenade"; grenade.fuse = 3.0; grenade.length = 18.0; grenade.owner_index = 1
	p1.position = Vector2(500, 540); p1._invincible_timer = 0.0
	grenade.position = Vector2(560, 545)
	game._add_projectile(grenade)
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(grenade.velocity.x > 500, "Grenade : un coup la repousse (vx %.0f)" % grenade.velocity.x)
	game._remove_projectile(grenade)
	# 19g bis) Grenade collante : elle se colle au sol, à une plateforme qui bouge (et la suit), à une
	# liane ; sur une fenêtre, elle colle si elle va doucement, la casse si elle va trop vite
	var sticky := func(where: Vector2, vel: Vector2) -> Projectile:
		var sg := Projectile.new()
		sg.kind = "grenade"; sg.fuse = 30.0; sg.length = 18.0; sg.owner_index = 1
		sg.position = where; sg.velocity = vel
		game._add_projectile(sg)
		return sg
	var sg1: Projectile = sticky.call(Vector2(150, 400), Vector2(300, 400))
	for i in 60:
		await step(1)
		if sg1.state == Projectile.State.STUCK:
			break
	var sg1_pos := sg1.position
	await step(10)
	check(sg1.state == Projectile.State.STUCK and sg1.position == sg1_pos and sg1.velocity == Vector2.ZERO, "Grenade collante : elle se colle au sol")
	game._remove_projectile(sg1)
	var sg_ride := MovingPlatform.new()
	sg_ride.size = Vector2(200, 16); sg_ride.travel = Vector2(300, 0); sg_ride.period = 2.0
	sg_ride.position = Vector2(50, 200)
	game.map.add_child(sg_ride)
	await step(1)
	var sg2: Projectile = sticky.call(Vector2(sg_ride.position.x, 120), Vector2(0, 300))
	for i in 60:
		await step(1)
		if sg2.state == Projectile.State.STUCK:
			break
	var sg2_gap := sg2.position.x - sg_ride.position.x
	await step(20)
	check(sg2.state == Projectile.State.STUCK and absf(sg2.position.x - sg_ride.position.x - sg2_gap) < 4.0 and sg_ride.position.x > 80.0,
		"Grenade collante : collée à une plateforme qui bouge, elle la suit")
	game._remove_projectile(sg2)
	sg_ride.queue_free()
	var sg_vine := Vine.new()
	sg_vine.position = Vector2(150, 0); sg_vine.length = 260.0
	game.map.add_child(sg_vine)
	await step(1)
	var sg3: Projectile = sticky.call(Vector2(60, 150), Vector2(900, -50))
	for i in 30:
		await step(1)
		if sg3.state == Projectile.State.STUCK:
			break
	check(sg3.state == Projectile.State.STUCK and sg3.stuck_vine == sg_vine and absf(sg3.position.x - 150.0) < 3.0, "Grenade collante : elle se colle à une liane")
	game._remove_projectile(sg3)
	sg_vine.queue_free()
	var sg_pane := BreakableWindow.new()
	sg_pane.size = Vector2(20, 200)
	sg_pane.position = Vector2(300, 150)
	game.map.add_child(sg_pane)
	await step(1)
	var sg4: Projectile = sticky.call(Vector2(200, 150), Vector2(400, 0))
	for i in 30:
		await step(1)
		if sg4.state == Projectile.State.STUCK:
			break
	check(sg4.state == Projectile.State.STUCK and not sg_pane.broken and sg4.position.x < 300.0, "Grenade collante : lancée doucement, elle se colle à la fenêtre")
	sg_pane.smash()
	await step(3)
	check(sg4.state != Projectile.State.STUCK, "Grenade collante : la fenêtre casse, elle se décolle")
	game._remove_projectile(sg4)
	sg_pane.set_broken(false)
	await step(2)
	var sg5: Projectile = sticky.call(Vector2(200, 150), Vector2(1600, 0))
	await step(10)
	check(sg_pane.broken and sg5.position.x > 320.0, "Grenade collante : lancée trop vite, elle casse la fenêtre et continue")
	game._remove_projectile(sg5)
	sg_pane.queue_free()
	# 19h) Gardée trop longtemps : elle explose en main
	p2.recover()  # J2 sonné par la grenade d'avant : on arrête le ralenti, pour compter la mèche en vraies frames
	await step(1)
	game._time_engine.stop(true)
	p1.position = Vector2(500, 540); p1._invincible_timer = 0.0; p1._stun_timer = 0.0
	var lives_before := p1.lives
	p1.take_item("grenade")
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f >= 1)
	await step(int(Fighter.GRENADE_FUSE * 60) + 5)
	check(p1.item == "" and (p1.is_stunned() or p1.lives < lives_before), "Grenade : gardée trop longtemps, elle explose en main")
	# 19i) Bouclier : RT le lève ; qui frappe dedans est projeté très loin, sans toucher
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p2.take_item("bouclier")
	p2.input_source = Scripted.new(func(s, f): s.item_pressed = f == 1)
	await step(3)
	check(p2.is_item_shielded() and p2.item == "", "Bouclier : RT le lève (le slot se libère)")
	p1.position = Vector2(600, 540); p2.position = Vector2(660, 540)
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(untouched(p2) and p1.velocity.x < -900 and not p1.can_attack(), "Bouclier : l'attaquant est projeté très loin (vx %.0f)" % p1.velocity.x)
	await shot("19_bouclier")
	await step(int(Fighter.ITEM_SHIELD_TIME * 60))
	check(not p2.is_item_shielded(), "Bouclier : il disparaît au bout de %d s" % Fighter.ITEM_SHIELD_TIME)
	# 19i bis) Vie en plus : RT donne une vie, sans dépasser Fighter.MAX_LIVES
	var vie_before := p2.lives
	p2.take_item("vie")
	p2.input_source = Scripted.new(func(s, f): s.item_pressed = f == 1)
	await step(3)
	check(p2.lives == vie_before + 1 and p2.item == "", "Vie en plus : RT donne une vie (%d -> %d)" % [vie_before, p2.lives])
	p2.lives = Fighter.MAX_LIVES
	p2.take_item("vie")
	p2.input_source = Scripted.new(func(s, f): s.item_pressed = f == 1)
	await step(3)
	check(p2.lives == Fighter.MAX_LIVES and p2.item == "vie", "Vie en plus : à %d vies on la garde" % Fighter.MAX_LIVES)
	p2.item = ""
	# 19i ter) Grappin : RT gardé = il tire l'autre vers soi ; petite pression = on est tiré vers lui
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.position = Vector2(500, 540); p2.position = Vector2(800, 540)
	await step(2)
	p1.take_item("grappin")
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f >= 1)
	var gr_p1x := p1.position.x
	var gr_pulled := false
	for i in 40:
		await step(1)
		if p2.is_grappled():
			gr_pulled = true
	check(gr_pulled and p2.position.x < 800 - 150 and absf(p1.position.x - gr_p1x) < 40 and p1.item_ammo == Fighter.GRAPPLE_USES - 1,
		"Grappin gardé : il tire l'autre vers soi (J2 x %.0f)" % p2.position.x)
	check(p1.grapple_mode == Fighter.Grapple.NONE, "Grappin gardé : arrivé, la corde se décroche")
	await shot("19_grappin")
	# Petite pression : c'est nous qui sommes tirés
	p1.position = Vector2(500, 540); p2.position = Vector2(800, 540)
	p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
	await step(2)
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f == 1)
	var gr_p2x := p2.position.x
	await step(25)
	check(p1.position.x > 500 + 150 and absf(p2.position.x - gr_p2x) < 40 and p1.item_ammo == Fighter.GRAPPLE_USES - 2,
		"Grappin, petite pression : on est tiré vers l'autre (J1 x %.0f)" % p1.position.x)
	await step(30)
	# Gardé puis lâché en route : l'autre est « jeté » (il garde son élan)
	p1.position = Vector2(400, 540); p2.position = Vector2(1000, 540)
	p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
	await step(2)
	var gr_frame := [0]
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f >= 1 and (gr_frame[0] == 0 or f < gr_frame[0] + 4))
	for i in 40:
		await step(1)
		if p2.is_grappled() and gr_frame[0] == 0:
			gr_frame[0] = p1.input_source.frame
		if gr_frame[0] != 0 and p1.grapple_mode == Fighter.Grapple.NONE:
			break
	await step(1)
	check(gr_frame[0] != 0 and p2.velocity.x < -900, "Grappin lâché en route : l'autre part sur son élan (vx %.0f)" % p2.velocity.x)
	check(p1.item == "", "Grappin : vide après %d lancers" % Fighter.GRAPPLE_USES)
	# Blocage parfait à l'arrivée du crochet : contré
	await step(60)
	p1.position = Vector2(500, 540); p2.position = Vector2(800, 540)
	p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
	await step(2)
	p1.take_item("grappin")
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f >= 1)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= 1)
	await step(20)
	check(p1.grapple_mode == Fighter.Grapple.NONE and not p2.is_grappled() and p2.position.x > 780 and not p1.can_attack(),
		"Grappin : un blocage parfait le contre (J1 ne frappe plus)")
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(70)
	p1.input_source = Scripted.new(func(s, f):
		s.item_pressed = f == 1
		s.item_held = f >= 1)
	gr_pulled = false
	for i in 30:
		await step(1)
		if p2.is_grappled():
			gr_pulled = true
	check(gr_pulled, "Grappin : un blocage normal ne l'arrête pas")
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.item = ""
	await step(30)
	# 19k) Nunchaku : coups vers le bas puis vers le haut, lourde = rafale de 3 coups
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.equip(load("res://weapons/nunchaku.tres"), 0)
	p1.position = Vector2(600, 540); p2.position = Vector2(670, 540)
	await step(2)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	var nun_vy := [0.0, 0.0]
	for i in 30:
		await step(1)
		if touched(p2):
			nun_vy[0] = p2.velocity.y
			break
	p2._stun_timer = 0.0; p2._invincible_timer = 0.0
	await step(40)
	p2._stun_timer = 0.0; p2._invincible_timer = 0.0
	p1.position = Vector2(600, 540); p2.position = Vector2(670, 540)
	p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
	await step(2)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	for i in 30:
		await step(1)
		if touched(p2):
			nun_vy[1] = p2.velocity.y
			break
	check(nun_vy[0] > 100.0 and nun_vy[1] < -500.0, "Nunchaku : 1er coup projette vers le bas, 2e vers le haut (vy %.0f puis %.0f)" % [nun_vy[0], nun_vy[1]])
	# Lourde : on avance normalement en chargeant, puis 3 coups (bas / haut / bas)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.equip(load("res://weapons/nunchaku.tres"), 0)
	p1.position = Vector2(500, 540); p2.position = Vector2(1100, 540)
	await step(2)
	var nun_x := p1.position.x
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = f >= 1 and f < 70
		s.stick.x = 1.0 if f < 40 else 0.0)
	await step(40)
	var nun_moved := p1.position.x - nun_x
	check(p1.is_charging_heavy() and nun_moved > 0.6 * p1.stats.run_speed * 39.0 / 60.0, "Nunchaku : on avance normalement en chargeant la lourde (%.0f px)" % nun_moved)
	var nun_index := {}
	var nun_ups := {}
	var nun_reach := 0.0
	for i in 60:
		await step(1)
		if p1.is_attack_active():
			nun_index[p1._burst_index] = true
			nun_ups[p1._hit_dir().y < 0.0] = true
			nun_reach = maxf(nun_reach, p1.attack_center().distance_to(p1.global_position))
	check(nun_index.size() == Fighter.BURST_HITS and nun_ups.size() == 2, "Nunchaku : la lourde est une rafale de %d coups, vers le bas et vers le haut" % Fighter.BURST_HITS)
	check(nun_reach > p1.stats.attack_reach * 1.3, "Nunchaku : chargée, la rafale va plus loin (%.0f px)" % nun_reach)
	await shot("19_nunchaku")
	# 19l) Arc : petit couteau rapide au coup léger, flèche à la lourde (on garde l'arc)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	p1.equip(load("res://weapons/arc.tres"), 0)
	check(p1.stats.attack_reach < base.attack_reach * 0.6 and p1.stats.attack_cooldown < base.attack_cooldown * 0.5,
		"Arc : coup léger très court et très rapide (portée %.0f, recharge %.2f s)" % [p1.stats.attack_reach, p1.stats.attack_cooldown])
	p1.position = Vector2(500, 540); p2.position = Vector2(900, 540)
	await step(2)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = f >= 1 and f < 50)
	var arrow_seen := false
	for i in 120:
		await step(1)
		for pr in game.projectiles:
			if pr.kind == "fleche":
				arrow_seen = true
		if touched(p2):
			break
	check(arrow_seen and touched(p2) and p1.has_weapon_in_hand() and p1.arrows == Fighter.ARROWS_MAX - 1,
		"Arc : la lourde tire une flèche qui touche, on garde l'arc (%d flèches)" % p1.arrows)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(60)
	var arrows_lying: Array = game.projectiles.filter(func(pr): return pr.kind == "fleche")
	check(arrows_lying.size() == 1 and arrows_lying[0].state != Projectile.State.FLYING, "Arc : la flèche retombe après avoir touché")
	# Un autre joueur (même avec un arc) ne ramasse pas cette flèche ; celui qui tient l'arc oui
	p2.equip(load("res://weapons/arc.tres"), 0, 2, 99)
	p2.position = arrows_lying[0].position + Vector2(0, -10); p2.velocity = Vector2.ZERO
	await step(3)
	check(arrows_lying[0] in game.projectiles and p2.arrows == 2, "Arc : la flèche d'un autre arc ne se ramasse pas")
	p2.position = Vector2(1200, 540)
	p1.position = arrows_lying[0].position + Vector2(0, -10); p1.velocity = Vector2.ZERO
	await step(3)
	check(not arrows_lying[0] in game.projectiles and p1.arrows == Fighter.ARROWS_MAX, "Arc : celui qui tient l'arc ramasse sa flèche")
	# Arc vide : Y ne tire rien
	p1.arrows = 0
	p1.position = Vector2(500, 540); p2.position = Vector2(900, 540)
	await step(2)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = f >= 1 and f < 20)
	await step(40)
	check(game.projectiles.filter(func(pr): return pr.kind == "fleche").is_empty(), "Arc : sans flèche, la lourde ne tire rien")
	# Une flèche frappée par un coup est contrée : elle casse
	p1.arrows = 3
	p2._stun_timer = 0.0; p2._invincible_timer = 0.0
	p2.equip(load(GameSetup.WEAPONS[0]), 0)
	p1.position = Vector2(400, 540); p2.position = Vector2(800, 540)
	await step(2)
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = f >= 1 and f < 30)
	var arrow_cut := false
	for i in 90:
		await step(1)
		var flying: Array = game.projectiles.filter(func(pr): return pr.kind == "fleche")
		if not flying.is_empty() and flying[0].position.distance_to(p2.global_position) < 140.0 and not p2.is_attacking():
			light_now(p2, Vector2.LEFT)
		if p1.arrows == 2 and flying.is_empty():
			arrow_cut = true
			break
	check(arrow_cut and untouched(p2), "Arc : une flèche frappée par un coup casse")
	check(p1.weapon_counters == 0, "Arc : contrée de loin, l'arc ne s'use pas")
	# Contrée de très près : l'arc s'use comme une arme contrée
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(60)
	p2._stun_timer = 0.0; p2._invincible_timer = 0.0
	p1.position = Vector2(500, 540); p2.position = Vector2(620, 540)
	p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
	await step(2)
	var bow_arrows := p1.arrows
	p1.input_source = Scripted.new(func(s, f):
		s.heavy_pressed = f == 1
		s.heavy_held = f >= 1 and f < 20)
	for i in 60:
		await step(1)
		if not p2.is_attacking() and not game.projectiles.filter(func(pr): return pr.kind == "fleche").is_empty():
			light_now(p2, Vector2.LEFT)
		if p1.arrows < bow_arrows and game.projectiles.filter(func(pr): return pr.kind == "fleche").is_empty():
			break
	check(p1.weapon_counters == 1 and untouched(p2), "Arc : une flèche contrée de très près abîme l'arc")
	p1.weapon_counters = 0
	# L'arc lancé (RB) et rattrapé : le nouveau porteur a les flèches qui restaient
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(30)
	var bow_before := p1.bow_id
	var arrows_before := p1.arrows
	p1.position = Vector2(500, 540); p2.position = Vector2(700, 540)
	p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
	await step(2)
	p1.input_source = Scripted.new(func(s, f): s.throw_pressed = f == 1)
	for i in 60:
		await step(1)
		if p2.has_weapon_in_hand():
			break
	check(p2.has_weapon_in_hand() and p2.weapon.heavy == WeaponStats.Heavy.SHOOT and p2.arrows == arrows_before and p2.bow_id == bow_before,
		"Arc : rattrapé par un autre, il garde ses flèches (%d) et ses flèches par terre sont à lui" % p2.arrows)
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.equip(load(GameSetup.WEAPONS[0]), 0)  # la suite des tests est à mains nues
	p2.equip(load(GameSetup.WEAPONS[0]), 0)
	await step(30)
	# 19j) Un objet tombe toutes les 10 s, au plus 2 par terre
	for pickup in game.pickups.duplicate():
		game._remove_pickup(pickup)
	for i in 3:
		game._item_spawn_timer = 0.0
		await step(1)
	check(game.pickups.size() == game.MAX_PICKUPS, "Objets : un objet tombe à chaque fois, au plus %d par terre" % game.MAX_PICKUPS)
	await step(180)
	var all_landed := true
	for pickup in game.pickups:
		all_landed = all_landed and pickup.landed
	check(all_landed, "Objets : ils se posent sur le décor")
	# 19l) Armes qui apparaissent : une toutes les 12 s (pas plus de 2 par terre), sans propriétaire ;
	# un joueur à mains nues la prend en passant dessus
	var weapons_before: int = game.projectiles.size()
	game._weapon_spawn_timer = 0.0
	await step(1)
	var appeared: Array = game.projectiles.filter(func(w): return w.kind == "arme" and w.owner_index == -1)
	check(game.projectiles.size() == weapons_before + 1 and appeared.size() == 1 and appeared[0].weapon != null
		and not appeared[0].weapon.is_bare_hands(), "Armes qui apparaissent : une arme au hasard tombe")
	for i in 120:
		await step(1)
		if appeared[0].state == Projectile.State.STUCK:
			break
	check(appeared[0].state == Projectile.State.STUCK, "Armes qui apparaissent : elle se pose")
	for i in 3:
		game._weapon_spawn_timer = 0.0
		await step(1)
	check(game.projectiles.filter(func(w): return w.kind == "arme").size() == game.MAX_LOOSE_WEAPONS,
		"Armes qui apparaissent : au plus %d qui traînent" % game.MAX_LOOSE_WEAPONS)
	var free_weapon: Projectile = appeared[0]
	var free_kind: WeaponStats = free_weapon.weapon
	p2.weapon_away = true
	p2.position = free_weapon.position + Vector2(0, -20)
	await step(2)
	check(p2.has_weapon_in_hand() and p2.weapon == free_kind and not free_weapon in game.projectiles,
		"Armes qui apparaissent : à mains nues, on la prend en passant dessus")
	# 19k) Physique : posé sur une plateforme qui bouge, l'objet est transporté ; elle part, il retombe ;
	# un coup le fait valdinguer dans le sens du coup ; une grenade le souffle ; une fenêtre qui casse le lâche
	for pickup in game.pickups.duplicate():
		game._remove_pickup(pickup)
	game._item_spawn_timer = 999.0
	p1.take_item("pistolet"); p2.take_item("pistolet")  # mains pleines : ils ne ramassent rien
	p1.position = Vector2(900, 540); p2.position = Vector2(1100, 540)
	var ride := MovingPlatform.new()
	ride.size = Vector2(200, 16); ride.travel = Vector2(300, 0); ride.period = 2.0
	ride.position = Vector2(50, 200)
	game.map.add_child(ride)
	await step(1)
	var rider: ItemPickup = game.spawn_pickup("bouclier", Vector2(ride.position.x, 120))
	for i in 60:
		await step(1)
		if rider.landed:
			break
	var gap := rider.position.x - ride.position.x
	await step(20)
	check(rider.landed and ride.position.x > 120.0 and absf(rider.position.x - ride.position.x - gap) < 4.0 and absf(rider.position.y - 179.0) < 3.0,
		"Objets : posé sur une plateforme qui bouge, il est transporté (écart %.1f)" % (rider.position.x - ride.position.x - gap))
	ride.queue_free()
	await step(10)
	check(not rider.landed and rider.position.y > 185.0, "Objets : la plateforme partie, il retombe")
	for i in 90:
		await step(1)
		if rider.landed:
			break
	check(rider.landed, "Objets : il se repose plus bas")
	p1.position = rider.position + Vector2(-50, 0)
	p1._invincible_timer = 0.0
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(not rider.landed and rider.velocity.x > 500.0 and rider.velocity.y < 0.0, "Objets : un coup le fait valdinguer dans le sens du coup (vx %.0f)" % rider.velocity.x)
	var light_speed := rider.velocity.length()
	await step(1)
	check(rider.velocity.length() < light_speed * 1.2, "Objets : le même coup ne le refrappe pas à chaque frame")
	await step(120)
	game._explode(rider.position + Vector2(60, 10))
	check(rider.velocity.x < -300.0 and rider.velocity.y < 0.0, "Objets : une grenade le souffle")
	await step(120)
	var pane := BreakableWindow.new()
	pane.size = Vector2(120, 20)
	pane.position = Vector2(150, 200)
	game.map.add_child(pane)
	await step(1)
	for pickup in game.pickups.duplicate():
		game._remove_pickup(pickup)
	rider = game.spawn_pickup("bouclier", Vector2(150, 150))
	await step(40)
	check(rider.landed and absf(rider.position.y - 177.0) < 3.0, "Objets : il se pose sur une fenêtre")
	pane.smash()
	await step(10)
	check(not rider.landed and rider.position.y > 185.0, "Objets : la fenêtre casse, il tombe")
	# ... pareil pour une arme qui traîne par terre
	var lying := Projectile.new()
	lying.kind = "arme"; lying.state = Projectile.State.DROPPED; lying.length = 40.0; lying.color = Color.RED
	lying.position = Vector2(700, 400)
	game._add_projectile(lying)
	for i in 90:
		await step(1)
		if lying.state == Projectile.State.STUCK:
			break
	check(lying.state == Projectile.State.STUCK, "Arme par terre : elle se pose")
	p1.position = lying.position + Vector2(50, -20)
	p1._attack_cooldown_timer = 0.0
	light_now(p1, Vector2.LEFT)
	await step(1)
	check(lying.state == Projectile.State.DROPPED and lying.velocity.x < -500.0, "Arme par terre : un coup la fait valdinguer (vx %.0f)" % lying.velocity.x)
	lying.position = Vector2(700, 3000)
	await step(1)
	check(not lying in game.projectiles, "Arme par terre : sortie de la map, elle est perdue")
	p1.item = ""; p2.item = ""

	# 17) Le toit de l'Arène (le labo) : on ne le traverse pas par en dessous ; on y monte par l'échelle
	# (à gauche, très rapide, on est éjecté en haut) ou par l'ascenseur (à droite)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	var roof := game.map.get_node("Toit/Plafond") as Node2D
	var roof_top := roof.position.y - 20.0
	var ladder := game.map.get_node("Toit/Echelle") as Ladder
	var lift := game.map.get_node("Toit/AscenseurToit") as MovingPlatform
	# 17a) Sous le toit : sauts + dash vers le haut, on cogne le plafond
	p1.position = Vector2(640, -320 - 30)
	p1.input_source = Scripted.new(func(s, f):
		s.jump_pressed = f == 2 or f == 14
		s.jump_held = true
		s.stick.y = -1.0 if f >= 22 else 0.0
		s.dash_pressed = f == 22)
	var highest := p1.position.y
	for i in 60:
		await step(1)
		highest = minf(highest, p1.position.y)
	check(highest - 30 >= roof_top + 40 - 1, "Toit : on ne le traverse pas par en dessous (tête au plus haut %.0f)" % (highest - 30))
	# 17b) L'échelle : "haut" en la touchant, on monte tout seul très vite, éjecté sur le toit en haut
	p1.position = Vector2(ladder.position.x + 10, 300); p1.velocity = Vector2.ZERO
	p1.input_source = Scripted.new(func(s, f): s.stick.y = -1.0 if f < 3 else 0.0)
	await step(2)
	check(p1.is_climbing() and is_equal_approx(p1.position.x, ladder.position.x), "Échelle : on s'y accroche avec haut")
	var climb_frames := 0
	while p1.is_climbing() and climb_frames < 120:
		await step(1)
		climb_frames += 1
	check(climb_frames < 60, "Échelle : on monte très vite (%d frames pour %d px)" % [climb_frames, 300 + 30 - roof_top])
	check(p1.velocity.y < -300 and p1.velocity.x > 200, "Échelle : en sortant en haut, on est éjecté (v = %s)" % p1.velocity)
	await step(60)
	check(p1.is_on_floor() and absf(p1.position.y + 30 - roof_top) < 3 and p1.position.x > roof.position.x - 2250,
		"Échelle : on atterrit sur le toit (%s)" % p1.position)
	await shot("17_toit")
	# 17c) Un coup reçu en grimpant fait lâcher l'échelle
	p1.position = Vector2(ladder.position.x, 200); p1.velocity = Vector2.ZERO
	p1.input_source = Scripted.new(func(s, f): s.stick.y = -1.0)
	await step(2)
	check(p1.is_climbing(), "Échelle : accroché de nouveau")
	p1.take_hit(Vector2.RIGHT)
	await step(1)
	check(not p1.is_climbing() and p1.is_stunned(), "Échelle : un coup reçu fait lâcher l'échelle")
	# 17d) Sauter depuis l'échelle la lâche
	p1._stun_timer = 0.0; p1._invincible_timer = 0.0
	p1.position = Vector2(ladder.position.x, 200); p1.velocity = Vector2.ZERO; p1._ladder_regrab_timer = 0.0
	p1.input_source = Scripted.new(func(s, f):
		s.stick.y = -1.0 if f < 5 else 0.0
		s.jump_pressed = f == 5)
	await step(7)
	check(not p1.is_climbing() and p1.velocity.y < -500, "Échelle : on la lâche en sautant")
	# 17e) L'ascenseur monte du sol de droite jusqu'au toit
	lift.set_time(0.0)
	p2.position = Vector2(lift.position.x, 570 - 30); p2.velocity = Vector2.ZERO
	await step(5)
	check(p2.is_on_floor(), "Ascenseur : J2 monte dessus en bas")
	await step(int(lift.period * 30) + 20)
	check(p2.is_on_floor() and absf(p2.position.y + 30 - roof_top) < 4, "Ascenseur : J2 arrive au niveau du toit (pieds à %.0f)" % (p2.position.y + 30))
	p2.input_source = Scripted.new(func(s, f): s.stick.x = -1.0 if f < 30 else 0.0)
	await step(50)
	check(p2.is_on_floor() and absf(p2.position.y + 30 - roof_top) < 3 and p2.position.x < roof.position.x + 2250,
		"Ascenseur : J2 descend sur le toit (%s)" % p2.position)

	# 18) La jungle sur le toit : on s'accroche tout seul à une liane en la touchant en l'air,
	# gauche / droite donne de l'élan, sauter lâche en gardant l'élan, un coup fait lâcher
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	var vine := game.map.get_node("Toit/Jungle/Arche3/Liane") as Vine
	var anchor := vine.global_position
	p1.position = anchor + Vector2(-20, 160); p1.velocity = Vector2(500, -100)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(3)
	check(p1.is_swinging(), "Liane : on s'y accroche en la touchant en l'air")
	await step(1)
	check(vine._holder == p1, "Liane : elle suit le joueur qui s'y balance")
	# Pousser dans le sens du balancement : il grandit
	p1.input_source = Scripted.new(func(s, f): s.stick.x = signf(p1._swing_speed) if p1._swing_speed != 0.0 else 1.0)
	var widest := 0.0
	for i in 150:
		await step(1)
		widest = maxf(widest, absf(p1._swing_angle))
	check(p1.is_swinging() and widest > 1.0, "Liane : gauche / droite donne de l'élan (angle max %.2f rad)" % widest)
	check(p1.position.distance_to(anchor) <= vine.length + 1.0, "Liane : on reste au bout de la liane")
	# Lâcher en sautant quand on part vers la droite : on garde l'élan
	var waited := 0
	while not (p1._swing_speed > 0.0 and absf(p1._swing_angle) < 0.3) and waited < 240:
		await step(1)
		waited += 1
	p1.input_source = Scripted.new(func(s, f): s.jump_pressed = f == 0; s.jump_held = true)
	await step(1)
	var release_speed := p1.velocity.x
	check(not p1.is_swinging() and release_speed > 500 and p1.velocity.y < 0, "Liane : on la lâche en sautant, avec l'élan (v = %s)" % p1.velocity)
	await step(10)
	check(p1.velocity.x > release_speed * 0.8, "Liane : l'élan est gardé après avoir lâché (vx = %.0f)" % p1.velocity.x)
	await step(30)
	check(not p1.is_swinging() or p1._vine != vine, "Liane : on ne se raccroche pas tout de suite à la même")
	# Un coup reçu fait lâcher
	p1.position = anchor + Vector2(0, 150); p1.velocity = Vector2.ZERO
	p1._vine_regrab_timer = 0.0; p1._knockback_timer = 0.0; p1._ladder_fling_timer = 0.0
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(3)
	check(p1.is_swinging(), "Liane : accroché de nouveau")
	p1.take_hit(Vector2.RIGHT)
	await step(1)
	check(not p1.is_swinging(), "Liane : un coup reçu fait lâcher")
	# Bas : on se laisse tomber
	p1._stun_timer = 0.0; p1._invincible_timer = 0.0
	p1.position = anchor + Vector2(0, 150); p1.velocity = Vector2.ZERO
	p1._vine_regrab_timer = 0.0; p1._knockback_timer = 0.0
	p1.input_source = Scripted.new(func(s, f): s.down_pressed = f == 2)
	await step(4)
	check(not p1.is_swinging(), "Liane : bas pour la lâcher")
	# Arbre : on se pose sur une grosse branche
	var tree := game.map.get_node("Toit/Jungle/Arbre") as JungleTree
	var branch: Rect2 = tree.branches[0]
	p1.position = tree.global_position + Vector2(branch.get_center().x, branch.position.y - 100); p1.velocity = Vector2.ZERO
	p1._vine_regrab_timer = 0.0
	await step(40)
	check(p1.is_on_floor() and absf(p1.position.y + 30 - (tree.global_position.y + branch.position.y)) < 3,
		"Arbre : on se pose sur une branche (%s)" % p1.position)
	# En ligne : la liane suit aussi le joueur chez les copains
	p1.position = anchor + Vector2(0, 150); p1.velocity = Vector2.ZERO; p1._vine_regrab_timer = 0.0
	await step(3)
	var copy := p2.net_state()
	p2.apply_net_state(p1.net_state())
	check(p2.is_swinging_on(vine), "Liane en ligne : le copain sait qui s'y balance")
	p2.apply_net_state(copy)
	await shot("18_jungle")
	# 18b) Les hauteurs au-dessus du toit : chaque échelle mène à un étage où l'on atterrit
	for node in get_tree().get_nodes_in_group("echelles"):
		var lad := node as Ladder
		p1._stun_timer = 0.0; p1._invincible_timer = 0.0; p1._knockback_timer = 0.0
		p1._ladder_regrab_timer = 0.0; p1._vine_regrab_timer = 0.0; p1._leave_vine()
		p1.position = Vector2(lad.position.x, lad.position.y + lad.size.y / 2.0 - 40.0); p1.velocity = Vector2.ZERO
		p1.input_source = Scripted.new(func(s, f): s.stick.y = -1.0 if f < 3 else 0.0)
		await step(3)
		var grabbed := p1.is_climbing()
		var t := 0
		while not (t > 20 and p1.is_on_floor() and not p1.is_climbing()) and t < 240:
			await step(1)
			t += 1
		check(grabbed and p1.is_on_floor() and p1.position.y + 30 < lad.top() + 120,
			"%s : on monte et on atterrit en haut (pieds à %.0f, haut %.0f)" % [lad.name, p1.position.y + 30, lad.top()])
	# L'ascenseur des cimes monte du toit jusqu'aux cimes de droite
	var lift2 := game.map.get_node("Toit/Hauteurs/AscenseurCimes") as MovingPlatform
	var top_right := game.map.get_node("Toit/Hauteurs/CimesDroite") as Node2D
	lift2.set_time(0.0)
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.position = Vector2(lift2.position.x, roof_top - 100); p1.velocity = Vector2.ZERO
	await step(int(lift2.period * 30) + 40)
	check(p1.is_on_floor() and absf(p1.position.y + 30 - (top_right.position.y - 8)) < 4,
		"Ascenseur des cimes : on arrive en haut (pieds à %.0f)" % (p1.position.y + 30))
	p1.input_source = Scripted.new(func(s, f): s.stick.x = 1.0 if f < 30 else 0.0)
	await step(60)
	check(p1.is_on_floor() and absf(p1.position.y + 30 - (top_right.position.y - 8)) < 3, "Ascenseur des cimes : on passe sur les cimes de droite")
	await shot("18_hauteurs")
	# 18c) Les colonnes de fenêtres : on les casse en les percutant vite (dash), en les frappant,
	# au pistolet ou avec une explosion ; marcher dedans ne les casse pas ; elles reviennent
	var cols: Node = game.map.get_node("Toit/Hauteurs/ColonneGauche")
	var win1 := cols.get_node("Fenetre1") as BreakableWindow
	var win_feet := roof_top
	p2.position = Vector2(win1.position.x + 300, win_feet - 30); p2.velocity = Vector2.ZERO
	p1._leave_vine(); p1._stun_timer = 0.0; p1._invincible_timer = 0.0; p1._knockback_timer = 0.0
	p1.position = Vector2(win1.position.x - 150, win_feet - 30); p1.velocity = Vector2.ZERO
	p1.input_source = Scripted.new(func(s, f): s.stick.x = 1.0)
	await step(60)
	check(not win1.broken and p1.position.x < win1.position.x, "Fenêtre : marcher dedans ne la casse pas")
	p1.position = Vector2(win1.position.x - 150, win_feet - 30); p1.velocity = Vector2.ZERO
	p1._dash_cooldown_timer = 0.0
	p1.input_source = Scripted.new(func(s, f): s.stick.x = 1.0; s.dash_pressed = f == 1)
	await step(20)
	check(win1.broken and p1.position.x > win1.position.x + win1.size.x / 2.0,
		"Fenêtre : un dash la casse et on passe au travers (x = %.0f)" % p1.position.x)
	var win2 := cols.get_node("Fenetre2") as BreakableWindow
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.position = Vector2(win2.position.x - 70, win2.position.y); p1.velocity = Vector2.ZERO
	light_now(p1, Vector2.RIGHT)
	await step(1)
	check(win2.broken, "Fenêtre : un coup la casse")
	var win3 := cols.get_node("Fenetre3") as BreakableWindow
	p1._cancel_attack()
	p1.position = Vector2(win3.position.x - 200, win3.position.y); p1.velocity = Vector2.ZERO
	p2.position = Vector2(win3.position.x + 200, win3.position.y); p2.velocity = Vector2.ZERO
	await step(1)
	p1.take_item("pistolet")
	p1._item_cooldown = 0.0
	p1.input_source = Scripted.new(func(s, f): s.item_pressed = f == 0)
	await step(20)
	check(win3.broken and untouched(p2), "Fenêtre : une balle la casse (et s'arrête)")
	var win5 := cols.get_node("Fenetre5") as BreakableWindow
	game._explode(win5.position + Vector2(-90, 0))
	check(win5.broken, "Fenêtre : une explosion la casse")
	var online_copy: Array = game.map.window_state()
	check(online_copy.count(true) >= 4, "Fenêtres en ligne : l'hôte envoie lesquelles sont cassées (%d)" % online_copy.count(true))
	game.map.apply_window_state([false, false, false, false])
	check(not win1.broken and not win2.broken and not win3.broken, "Fenêtres en ligne : le copain les répare comme l'hôte")
	game.map.apply_window_state(online_copy)
	await shot("18_fenetres")
	p1.position = Vector2(win2.position.x - 300, win2.position.y); p2.position = Vector2(win2.position.x + 300, win2.position.y)
	await step(int(BreakableWindow.RESPAWN_TIME * 60) + 5)
	check(not win1.broken and not win2.broken and not win5.broken, "Fenêtres : elles reviennent au bout de %d s" % BreakableWindow.RESPAWN_TIME)
	# 18d) Le 2e toit ferme le haut : on ne le traverse pas en sautant
	var roof2 := game.map.get_node("Toit/Toit2") as Node2D
	var top_mid := game.map.get_node("Toit/Hauteurs/SommetMilieu2") as Node2D
	p1.position = Vector2(top_mid.position.x, top_mid.position.y - 8 - 30); p1.velocity = Vector2.ZERO
	p1._air_dashes_left = 1; p1._dash_cooldown_timer = 0.0
	p1.input_source = Scripted.new(func(s, f):
		s.jump_pressed = f == 2 or f == 14
		s.jump_held = true
		s.stick.y = -1.0 if f >= 22 else 0.0
		s.dash_pressed = f == 22)
	var top_head := p1.position.y
	for i in 60:
		await step(1)
		top_head = minf(top_head, p1.position.y - 30)
	check(top_head >= roof2.position.y + 20 - 1, "Toit du haut : on ne le traverse pas (tête au plus haut %.0f)" % top_head)

	# 15) Jeu en ligne (sans réseau ici : on joue l'hôte puis un copain, et on passe les messages à la main)
	# 15a) Les touches d'un copain arrivent par le réseau : un appui n'est jamais perdu
	var net := NetworkInputSource.new()
	net.push({"j": true, "jh": true, "sx": 1.0})
	net.push({"jh": true, "sx": 1.0})  # 2e message dans la même frame : le saut appuyé reste
	var polled := net.poll()
	var polled_again := net.poll()
	check(polled.jump_pressed and polled.jump_held and polled.stick.x == 1.0 and not polled_again.jump_pressed and polled_again.jump_held,
		"En ligne : un saut envoyé par un copain compte une fois, même si deux messages arrivent ensemble")
	# 15b) Chez l'hôte : le copain (J2) est piloté par ses touches reçues
	Online.status = Online.Status.PLAYING
	Online.is_host = true
	Online.my_id = 1
	Online.players = [{"id": 1, "character": 0, "ready": true}, {"id": 2, "character": 1, "ready": true}]
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], []]
	GameSetup.player_characters = [GameSetup.CHARACTERS[0], GameSetup.CHARACTERS[1]]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	check(game.online and p1.input_source is LocalInputSource and p2.input_source is NetworkInputSource,
		"En ligne (hôte) : J1 joue sur cet ordinateur, J2 par le réseau")
	await step(40)
	var y_before := p2.position.y
	game.receive_online_input(1, {"j": true, "jh": true})
	for k in 8:
		game.receive_online_input(1, {"jh": true})
		await step(1)
	check(p2.position.y < y_before - 30, "En ligne (hôte) : J2 saute avec la touche reçue du réseau (monté de %.0f px)" % (y_before - p2.position.y))
	p1._attack_heavy = true; p1._heavy_charging = true; p1._attack_time = 0.0; p1._charge_time = 0.3; p1._heavy_charge = 0.4
	p2.shield = 7; p2.lives = 2; p2._lives_show_timer = 1.0
	game.gauge.points = 6.0
	p2._stun_timer = 1.0
	var host_state: Array = game.online_state()
	game.on_online_player_left(1)
	await step(1)
	check(p2.eliminated and game._match_over, "En ligne (hôte) : un copain qui quitte est éliminé (fin de partie à 2)")
	# 15c) Chez un copain : rien n'est calculé, on affiche l'état reçu de l'hôte
	Online.is_host = false
	Online.my_id = 2
	GameSetup.player_devices = [[], [{"type": "keyboard", "layout": 1}]]
	await new_game()
	var g1: Fighter = game.fighters[0]
	var g2: Fighter = game.fighters[1]
	check(g1.input_source is InputSource and not g1.input_source is LocalInputSource and g2.input_source is LocalInputSource,
		"En ligne (copain) : J2 joue sur cet ordinateur, J1 est seulement affiché")
	var spawn_y := g1.position.y
	await step(20)
	check(is_equal_approx(g1.position.y, spawn_y), "En ligne (copain) : sans message de l'hôte, rien ne bouge (pas de gravité calculée)")
	game.receive_online_state(host_state)
	await step(1)
	check(g1.net_state() == host_state[Game.ONLINE_HEADER] and g2.net_state() == host_state[Game.ONLINE_HEADER + 1],
		"En ligne (copain) : les joueurs sont affichés exactement comme chez l'hôte")
	var guest_times: Array = game.map.moving_state()
	var times_ok: bool = guest_times.size() == host_state[6].size() and guest_times.size() > 0
	for i in guest_times.size():
		times_ok = times_ok and absf(guest_times[i] - host_state[6][i]) < 0.05
	check(times_ok, "En ligne (copain) : navettes et ascenseurs au même endroit que chez l'hôte")
	var spear_state := host_state.duplicate()
	spear_state[7] = [["lance", 0, Vector2(500, 300), 0.5, Projectile.State.FLYING, Color.YELLOW]]
	game.receive_online_state(spear_state)
	await step(1)
	check(game.projectiles.size() == 1 and game.projectiles[0].position == Vector2(500, 300) and not game.projectiles[0].simulate,
		"En ligne (copain) : une lance lancée chez l'hôte s'affiche ici")
	game.receive_online_state(host_state)
	await step(1)
	check(game.projectiles.is_empty(), "En ligne (copain) : ramassée chez l'hôte, elle disparaît ici")
	var item_state := host_state.duplicate()
	item_state[8] = [["grenade", Vector2(700, 400)]]
	game.receive_online_state(item_state)
	await step(1)
	check(game.pickups.size() == 1 and game.pickups[0].kind == "grenade" and game.pickups[0].position == Vector2(700, 400) \
		and not game.pickups[0].simulate, "En ligne (copain) : les objets par terre s'affichent comme chez l'hôte")
	game.receive_online_state(host_state)
	await step(1)
	check(g1.is_charging_heavy() and g2.shield == 7 and g2.lives == 2 and g2.is_stunned() and game.gauge.points == 6.0,
		"En ligne (copain) : charge de la lourde, bouclier, vies, état sonné et jauge de contre reçus")
	check(game._shake_left > 0.0, "En ligne (copain) : une vie perdue chez l'hôte fait trembler l'écran ici aussi")
	var hit_state := host_state.duplicate()
	hit_state[4] = [0, 1]
	game.receive_online_state(hit_state)
	await step(1)
	check(game._stun_focus.size() == 2, "En ligne (copain) : le zoom sur un joueur sonné est reçu de l'hôte")
	game.spawn_online_effect({"k": "marque", "p": Vector2(600, 500), "c": Color.WHITE})
	game.spawn_online_effect({"k": "explosion", "p": Vector2(600, 500), "c": Color.ORANGE})
	var effects := 0
	for child in game.get_children():
		if child is ClashMark or child is MicroExplosion:
			effects += 1
	check(effects == 2, "En ligne (copain) : les effets envoyés par l'hôte s'affichent (%d)" % effects)
	var end_state := host_state.duplicate()
	end_state[2] = "Joueur 1 gagne !"
	end_state[3] = 0
	game.receive_online_state(end_state)
	await step(1)
	check(game._match_over and game._end_screen.visible and game._winner_label.text == "Joueur 1 gagne !",
		"En ligne (copain) : l'écran de fin s'affiche quand l'hôte le dit")
	Online.leave()
	GameSetup.player_devices = []
	GameSetup.player_characters = []
	check(Online.status == Online.Status.OFF and Online.players.is_empty(), "En ligne : quitter remet tout à zéro")

	# 15b) Relais : quand la connexion directe est bloquée, les paquets passent par le serveur
	var host_peer := HybridPeer.new()
	var guest_peer := HybridPeer.new()
	host_peer.create_server()
	guest_peer.create_client(2)
	var relayed := []
	host_peer.send_relay = func(target: int, data: PackedByteArray) -> void:
		relayed.append(target)
		guest_peer.receive_relay(1, data)
	guest_peer.send_relay = func(target: int, data: PackedByteArray) -> void:
		host_peer.receive_relay(2, data)
	var seen := []
	host_peer.peer_connected.connect(func(id: int) -> void: seen.append("+%d" % id))
	host_peer.peer_disconnected.connect(func(id: int) -> void: seen.append("-%d" % id))
	check(guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING, "Relais : le copain attend d'être relié")
	host_peer.use_relay(2)
	guest_peer.use_relay(1)
	check(guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and seen == ["+2"],
		"Relais : l'hôte et le copain sont reliés par le serveur (%s)" % [seen])
	guest_peer.set_target_peer(1)
	guest_peer.put_packet(PackedByteArray([4, 5, 6]))
	check(host_peer.get_available_packet_count() == 1 and host_peer.get_packet_peer() == 2 and host_peer.get_packet() == PackedByteArray([4, 5, 6]),
		"Relais : le paquet du copain arrive chez l'hôte")
	host_peer.set_target_peer(0)
	host_peer.put_packet(PackedByteArray([7]))
	check(relayed == [2] and guest_peer.get_available_packet_count() == 1 and guest_peer.get_packet() == PackedByteArray([7]),
		"Relais : le paquet de l'hôte arrive chez le copain (%s)" % [relayed])
	host_peer.receive_relay(3, PackedByteArray([9]))
	check(host_peer.get_available_packet_count() == 0, "Relais : un paquet d'un joueur inconnu est ignoré")
	host_peer.drop(2)
	guest_peer.drop(1)
	check(seen == ["+2", "-2"] and guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED,
		"Relais : le copain parti est signalé, le copain sans hôte est déconnecté")

	# 14) Éditeur de map : format JSON, construction de la map, outils de l'éditeur, partie sur la map
	var fresh := MapData.new_map("Test")
	var built := MapBuilder.build(fresh)
	var built_problems: Array[String] = []
	_check_visuals(built, built_problems)
	check(built.get_node("SpawnPoints").get_child_count() == 2 and built.has_node("RespawnPoint")
		and built.blast_zone.has_point(built.respawn_position()) and built_problems.is_empty(),
		"Éditeur : une map neuve donne une vraie map (2 départs, une réapparition) %s" % [built_problems])
	built.free()
	check(MapData.from_json(MapData.to_json(fresh)) == MapData.normalized(fresh), "Éditeur : sauver puis relire le JSON redonne la même map")
	var odd := MapData.normalized({"name": "X", "elements": [{"type": "inconnu", "pos": [0, 0]}, {"type": "mobile", "pos": [5, 6]}]})
	check(odd.elements.size() == 1 and odd.elements[0].has("travel") and odd.elements[0].has("period"),
		"Éditeur : un fichier incomplet est complété (réglages par défaut), un type inconnu est ignoré")

	var editor: MapEditor = (load("res://scenes/editor.tscn") as PackedScene).instantiate()
	editor.change_scene = false
	GameSetup.editor_map = {}
	add_child(editor)
	editor.new_map()
	await step(1)
	var count: int = editor.data.elements.size()
	var mobile := editor.add_from_catalog("mobile", Vector2(1013, 207))
	check(editor.selected_id == mobile.id and editor.data.elements.size() == count + 1
		and MapData.vec(mobile, "pos") == Vector2(1000, 208), "Éditeur : poser une plateforme mobile la colle à la grille (%s)" % [mobile.pos])
	editor.snap_on = false
	editor.move_selected(Vector2(1013, 207))
	check(MapData.vec(mobile, "pos") == Vector2(1013, 207), "Éditeur : sans l'aimant, placement libre au pixel près")
	editor.snap_on = true
	editor.undo()
	check(editor.data.elements.size() == count, "Éditeur : Ctrl+Z annule la pose")
	editor.redo()
	check(editor.data.elements.size() == count + 1, "Éditeur : Ctrl+Y la refait")
	var block := editor.add_from_catalog("sol", Vector2(0, 800))
	var block_corner := MapData.vec(block, "pos") - MapData.vec(block, "size") / 2.0
	editor._start_handle_drag(block, "resize")
	editor._resize(block, Vector2(200, 840))
	var block_rect := Rect2(MapData.vec(block, "pos") - MapData.vec(block, "size") / 2.0, MapData.vec(block, "size"))
	check(block_rect.end == Vector2(200, 840) and block_rect.position == block_corner,
		"Éditeur : tirer le coin agrandit le bloc, le coin opposé ne bouge pas (%s)" % [block_rect])
	editor.rotate_selected(15.0)
	check(is_equal_approx(float(block.rot), 15.0), "Éditeur : R tourne le bloc de 15°")
	editor.copy_selected()
	var pasted := editor.paste(Vector2(400, 1000))
	check(pasted.id != block.id and pasted.size == block.size and editor.data.elements.size() == count + 3,
		"Éditeur : copier / coller fait un deuxième bloc pareil")
	editor.delete_selected()
	check(editor.data.elements.size() == count + 2 and editor.selected_id == -1, "Éditeur : Suppr efface l'élément choisi")
	var p3 := editor.add_from_catalog("spawn_joueur", Vector2(700, 580))
	check(int(p3.player) == 3, "Éditeur : un nouveau départ prend le numéro libre suivant (J3)")
	editor.add_from_catalog("echelle", Vector2(160, 400))
	editor.add_from_catalog("liane", Vector2(1100, 100))
	editor.add_from_catalog("fenetre", Vector2(900, 300))
	editor.add_from_catalog("spawn_objet", Vector2(640, 200))
	editor.add_from_catalog("spawn_arme", Vector2(500, 200))
	var resp_count: int = editor.data.elements.filter(func(e): return e.type == "reapparition").size()
	editor.add_from_catalog("reapparition", Vector2(600, 100))
	check(editor.data.elements.filter(func(e): return e.type == "reapparition").size() == resp_count,
		"Éditeur : une seule réapparition (la poser à nouveau la déplace)")
	check(editor._nodes.size() == editor.data.elements.filter(func(e): return not e.type in MapData.POINT_TYPES).size(),
		"Éditeur : chaque élément a son aperçu")
	# 14b) L'éditeur à la manette
	var epad: EditorPad = editor._pad
	editor.select(-1)
	editor._camera.zoom = Vector2.ONE
	epad.press(JOY_BUTTON_A)
	check(epad.active and epad.cursor == editor._camera.position, "Éditeur manette : la manette fait apparaître le curseur au milieu de la vue")
	var target := editor.add_from_catalog("sol", Vector2(-600, 1400))
	var target_pos := MapData.vec(target, "pos")
	editor.select(-1)
	epad.cursor = target_pos
	epad.press(JOY_BUTTON_A)
	check(editor.selected_id == target.id and epad.dragging, "Éditeur manette : A sur un élément le prend")
	epad.tick(0.1, Vector2(1, 0), Vector2.ZERO, 0.0, Vector2i.ZERO)
	check(MapData.vec(target, "pos").x > target_pos.x, "Éditeur manette : le stick gauche déplace l'élément pris")
	epad.release(JOY_BUTTON_A)
	epad.press(JOY_BUTTON_A)
	epad.tick(0.1, Vector2(0, 1), Vector2.ZERO, 0.0, Vector2i.ZERO)
	var moved_pos := MapData.vec(editor.selected(), "pos")
	epad.press(JOY_BUTTON_B)
	target = editor.selected()
	check(not epad.dragging and MapData.vec(target, "pos").y < moved_pos.y, "Éditeur manette : B annule le déplacement en cours")
	var before_cursor := epad.cursor
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i(1, 0))
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i.ZERO)
	check(is_equal_approx(epad.cursor.x, before_cursor.snapped(Vector2(40, 40)).x + 40.0), "Éditeur manette : la croix avance le curseur d'un cran de grille")
	var size_before := MapData.vec(target, "size")
	var bottom_left := MapData.vec(target, "pos") + Vector2(-size_before.x, size_before.y) / 2.0
	epad.tick(0.016, Vector2.ZERO, Vector2(1, 0), 0.0, Vector2i.ZERO)
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i.ZERO)
	epad.tick(0.016, Vector2.ZERO, Vector2(0, -1), 0.0, Vector2i.ZERO)
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i.ZERO)
	var size_after := MapData.vec(target, "size")
	var bottom_left_after := MapData.vec(target, "pos") + Vector2(-size_after.x, size_after.y) / 2.0
	check(size_after == size_before + Vector2(40, 40) and bottom_left_after == bottom_left,
		"Éditeur manette : le stick droit agrandit (plus large, plus haut), le coin en bas à gauche reste (%s)" % [size_after])
	epad.press(JOY_BUTTON_RIGHT_SHOULDER)
	check(is_equal_approx(float(target.rot), 15.0), "Éditeur manette : RB tourne de 15°")
	epad.press(JOY_BUTTON_Y)
	var prop_x_before: float = MapData.vec(target, "pos").x
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i(1, 0))
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i.ZERO)
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i(1, 0))
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i.ZERO)
	check(epad.focus == EditorPad.Focus.PROPS and is_equal_approx(MapData.vec(target, "pos").x, prop_x_before + 80.0),
		"Éditeur manette : Y ouvre les réglages, droite change la valeur (X + un cran, deux fois)")
	epad.press(JOY_BUTTON_B)
	var count_pad: int = editor.data.elements.size()
	epad.press(JOY_BUTTON_X)
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i(0, 1))
	epad.tick(0.016, Vector2.ZERO, Vector2.ZERO, 0.0, Vector2i.ZERO)
	epad.press(JOY_BUTTON_A)
	check(epad.focus == EditorPad.Focus.MAP and editor.data.elements.size() == count_pad + 1 and editor.selected().type == editor.catalog_types()[1],
		"Éditeur manette : X ouvre le catalogue, bas puis A pose le 2e élément au curseur")
	epad.press(JOY_BUTTON_RIGHT_STICK)
	check(editor.data.elements.size() == count_pad + 2, "Éditeur manette : R3 duplique")
	editor.delete_selected()
	editor.delete_selected()
	epad.press(JOY_BUTTON_START)
	for i in 10:
		epad.nav(Vector2i(0, 1))
	epad.nav(Vector2i(1, 0))
	check(epad.focus == EditorPad.Focus.MENU and not editor.grid_on, "Éditeur manette : Start ouvre le menu, la grille s'y éteint")
	epad.nav(Vector2i(-1, 0))
	editor.set_map_name("")
	epad.index = 3
	epad.press(JOY_BUTTON_A)
	epad.press(JOY_BUTTON_A)
	epad.nav(Vector2i(1, 0))
	epad.press(JOY_BUTTON_A)
	epad.press(JOY_BUTTON_START)
	check(editor.grid_on and editor.map_name() == "AB" and epad.focus == EditorPad.Focus.MENU,
		"Éditeur manette : le clavier à l'écran écrit le nom de la map (%s)" % editor.map_name())
	epad.press(JOY_BUTTON_B)
	check(epad.focus == EditorPad.Focus.MAP and not epad._panel.visible, "Éditeur manette : B ferme le menu")
	editor.delete_selected()
	epad.set_active(false)
	editor.select(target.id)
	editor.delete_selected()
	# 14c) Tout peut bouger, et s'attacher à un autre élément (structures animées)
	var base_block := editor.add_from_catalog("sol", Vector2(2000, 400))
	check(base_block.has("travel") and MapData.vec(base_block, "travel") == Vector2.ZERO and int(base_block.attach) == 0,
		"Éditeur mouvement : un bloc posé ne bouge pas (trajet nul, attaché à rien)")
	var arm := editor.add_from_catalog("plateforme", Vector2(2000, 200))
	check(editor.attach_selected(base_block.id) and int(arm.attach) == base_block.id, "Éditeur mouvement : la plateforme s'attache au bloc")
	editor.select(base_block.id)
	check(not editor.attach_selected(arm.id), "Éditeur mouvement : pas de boucle (le bloc ne peut pas s'attacher à sa plateforme)")
	var arm_before := MapData.vec(arm, "pos")
	editor.move_selected(MapData.vec(base_block, "pos") + Vector2(80, 0))
	check(MapData.vec(arm, "pos") == arm_before + Vector2(80, 0), "Éditeur mouvement : déplacer le bloc emmène ce qui y est attaché")
	var rows_motion := editor.prop_rows()
	var distance_row: Dictionary = rows_motion.filter(func(row): return row.label == "Distance")[0]
	var direction_row: Dictionary = rows_motion.filter(func(row): return row.label == "Direction")[0]
	direction_row.set.call(3)  # vers le haut
	check(MapData.vec(base_block, "travel").is_equal_approx(Vector2(0, -200)), "Éditeur mouvement : choisir une direction fait bouger un bloc immobile (5 cases) (%s)" % [base_block.travel])
	editor.select(arm.id)
	editor.start_attach_pick()
	editor.finish_attach_pick(null)
	check(int(arm.attach) == base_block.id and not editor.attach_picking, "Éditeur mouvement : annuler « Attacher à... » ne change rien")
	editor.set_playing(true)
	editor._process(1.0)  # la moitié de l'aller-retour (4 s) : en haut
	editor._process(1.0)
	var arm_node: Node2D = editor._nodes[arm.id]
	check(arm_node.position.is_equal_approx(MapData.vec(arm, "pos") + Vector2(0, -200)), "Éditeur mouvement : « Voir bouger » fait monter le bloc et sa plateforme (%s)" % [arm_node.position])
	editor.set_playing(false)
	check(arm_node.position == MapData.vec(arm, "pos"), "Éditeur mouvement : éteint, tout revient à sa place")
	editor.select(base_block.id)
	editor.delete_selected()
	check(int(arm.attach) == 0, "Éditeur mouvement : effacer le bloc détache sa plateforme")
	editor.select(arm.id)
	editor.delete_selected()
	var loose := MapData.normalized({"elements": [{"id": 1, "type": "sol", "pos": [0, 0], "attach": 7},
		{"id": 2, "type": "sol", "pos": [0, 0], "attach": 3}, {"id": 3, "type": "sol", "pos": [0, 0], "attach": 2}]})
	check(int(loose.elements[0].attach) == 0 and (int(loose.elements[1].attach) == 0 or int(loose.elements[2].attach) == 0),
		"Éditeur mouvement : un fichier avec un lien vers rien ou une boucle est réparé")
	# Check-up de l'éditeur (2026-10-19)
	var cu_parent := editor.add_from_catalog("sol", Vector2(400, 300))
	var cu_child := editor.add_from_catalog("plateforme", Vector2(400, 200))
	editor.attach_selected(cu_parent.id)
	cu_child.travel = [100, 0]
	editor.copy_selected()
	editor.select(cu_parent.id)
	editor.delete_selected()
	var cu_pasted := editor.paste()
	check(int(cu_pasted.attach) == 0 and MapData.offset_at(MapData.by_id(editor.data), cu_pasted, 2.0).x <= 100.5,
		"Check-up éditeur : coller une copie d'un élément dont le parent est effacé ne l'attache pas (ni à lui-même)")
	var cu_base := editor.add_from_catalog("sol", Vector2(1000, 300))
	var cu_top := editor.add_from_catalog("plateforme", Vector2(1000, 200))
	editor.attach_selected(cu_base.id)
	editor.select(cu_base.id)
	var cu_before := MapData.vec(cu_top, "pos")
	editor._nudge(KEY_RIGHT, true)
	editor._set_vec_part(cu_base, "pos", 1, 260.0)
	check(MapData.vec(cu_top, "pos") == cu_before + Vector2(1, -40),
		"Check-up éditeur : les flèches et les cases X / Y emmènent aussi ce qui est attaché")
	for e in [cu_pasted, cu_base, cu_top]:
		editor.select(e.id)
		editor.delete_selected()
	var cu_name: String = editor._name_edit.text
	editor._name_edit.text = "_test_nom_quitter"
	editor._save_draft()
	check(MapData.load_saved(MapData.DRAFT_NAME).name == "_test_nom_quitter", "Check-up éditeur : le nom tapé est gardé en quittant")
	editor._name_edit.text = cu_name
	editor.data.name = cu_name
	# 14d) Exporter / importer : la map passe dans un fichier, et revient (dans un autre navigateur)
	editor._name_edit.text = "_test_export"
	var exported := editor.export_map()
	var exported_text := FileAccess.get_file_as_string(MapEditor.EXPORT_DIR + "/" + exported)
	check(exported == "_test_export.json" and MapData.from_json(exported_text) == MapData.normalized(editor.data),
		"Éditeur : Exporter écrit la map dans un fichier .json")
	var count_before_import: int = editor.data.elements.size()
	editor.new_map()
	check(not editor.import_text("pas une map") and editor.data.elements.size() != count_before_import,
		"Éditeur : Importer refuse un fichier qui n'est pas une map")
	check(editor.import_text(exported_text) and editor.data.elements.size() == count_before_import
		and "_test_export" in MapData.list_saved(), "Éditeur : Importer ouvre la map du fichier et la sauve dans le navigateur")
	check(editor.import_text(exported_text) and editor.data.name == "_test_export (2)" and "_test_export_(2)" in MapData.list_saved(),
		"Check-up éditeur : importer une map du même nom ne remplace pas celle déjà sauvée")
	MapData.delete_saved("_test_export")
	MapData.delete_saved("_test_export (2)")
	DirAccess.remove_absolute(MapEditor.EXPORT_DIR + "/" + exported)
	editor._name_edit.text = "_test_editeur"
	check(editor.save_map() and "_test_editeur" in MapData.list_saved(), "Éditeur : la map est sauvée et listée")
	check(MapData.load_saved("_test_editeur") == MapData.normalized(editor.data), "Éditeur : la map sauvée se relit pareil")
	check("carte:_test_editeur" in GameSetup.all_maps(), "Éditeur : la map sauvée est dans le choix des maps")
	check(editor.test_map() and GameSetup.map_path == GameSetup.EDITOR_MAP and GameSetup.exit_scene() == MapEditor.EDITOR_SCENE,
		"Éditeur : TESTER prépare une partie sur la map, et QUITTER y ramènera")
	editor.queue_free()
	# La partie sur la map de l'éditeur : 3 joueurs posés, la navette, l'échelle, la liane et la fenêtre marchent
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
	await new_game()
	for fi in game.fighters:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(90)
	var landed_custom: int = game.fighters.filter(func(fi): return fi.is_on_floor() and fi.lives == GameSetup.lives).size()
	check(landed_custom == 3, "Éditeur : sur la map de l'éditeur, les 3 joueurs atterrissent (%d/3)" % landed_custom)
	var moving: Array = game.map.get_node("Decor").get_children().filter(func(n): return n.name.begins_with("mobile_"))
	var start_x: float = moving[0].position.x if moving.size() == 1 else 0.0
	await step(30)
	check(moving.size() == 1 and moving[0].position.x != start_x and game.map.windows().size() == 1
		and get_tree().get_nodes_in_group("echelles").size() == 1 and get_tree().get_nodes_in_group("lianes").size() == 1,
		"Éditeur : la navette roule, l'échelle, la liane et la fenêtre sont là")
	check(game.map.item_spawn_points().size() == 1, "Éditeur : les objets tombent depuis le point posé")
	check(game.map.has_node("WeaponSpawns") and game.map.weapon_spawn_points().size() == 1,
		"Éditeur : les armes tombent depuis le « Spawn d'arme » posé")
	var saved_map := GameSetup.make_map("carte:_test_editeur")
	check(saved_map.map_name == "_test_editeur", "Éditeur : une map sauvée se charge par son nom")
	saved_map.free()
	MapData.delete_saved("_test_editeur")
	# La Tour : une grande map verticale faite avec l'éditeur, livrée avec le jeu
	var tower_path := "res://maps_editeur/La_Tour.json"
	check(tower_path in GameSetup.MAPS and GameSetup.all_maps().count(tower_path) == 1 and not "carte:La_Tour" in GameSetup.all_maps(),
		"La Tour : une map officielle du jeu, une seule fois dans le choix des maps (aussi en ligne)")
	var tower_data := MapData.load_saved("La_Tour")
	var tower_area := MapData.bounds(tower_data)
	check(tower_data.elements.size() > 100 and tower_area.size.y > 5000 and tower_area.size.x > 2500,
		"La Tour : une très grande map verticale (%d éléments, %.0f x %.0f px)" % [tower_data.elements.size(), tower_area.size.x, tower_area.size.y])
	var tower_map := GameSetup.make_map(tower_path)
	var host_times := tower_map.moving_state()
	var guest_map := GameSetup.make_map(tower_path)
	host_times[-1] = 3.7
	guest_map.apply_moving_state(host_times)
	check(host_times.size() == 1 and is_equal_approx(guest_map.get_node("Mouvements").time, 3.7),
		"La Tour : en ligne, les éléments qui bougent sont calés sur ceux de l'hôte")
	tower_map.free()
	guest_map.free()
	GameSetup.map_path = tower_path
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}], [{"type": "joypad", "id": 6}]]
	await new_game()
	for fi in game.fighters:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(90)
	var tower_landed: int = game.fighters.filter(func(fi): return fi.is_on_floor() and fi.lives == GameSetup.lives).size()
	check(tower_landed == 4 and game.map.has_node("Mouvements"), "La Tour : les 4 joueurs atterrissent, les ascenseurs et la tour bougent (%d/4)" % tower_landed)
	GameSetup.player_devices = []
	# Une structure animée en partie : un bloc qui va à droite, une plateforme attachée ; J1 posé dessus est emmené
	var anim_map := MapData.new_map("Anim")
	var carrier := MapData.add_element(anim_map, "sol", Vector2(640, 300))
	carrier.size = [200, 40]
	carrier.travel = [400, 0]
	carrier.period = 4.0
	var rider_pf := MapData.add_element(anim_map, "plateforme", Vector2(640, 200))
	rider_pf.attach = carrier.id
	GameSetup.editor_map = anim_map
	GameSetup.map_path = GameSetup.EDITOR_MAP
	GameSetup.player_devices = []
	await new_game()
	for fi in game.fighters:
		fi.input_source = Scripted.new(func(s, f): pass)
	var pf_node: Node2D = game.map.get_node("Decor/plateforme_%d" % rider_pf.id)
	game.fighters[0].position = pf_node.position + Vector2(0, -40)
	await step(10)
	var ride_from: float = game.fighters[0].position.x
	var pf_from: float = pf_node.position.x
	await step(40)
	var pf_moved: float = pf_node.position.x - pf_from
	check(game.map.has_node("Mouvements") and game.map.get_node("Decor/sol_%d" % carrier.id) is AnimatableBody2D
		and pf_moved > 40 and game.fighters[0].is_on_floor() and absf((game.fighters[0].position.x - ride_from) - pf_moved) < 8,
		"Éditeur mouvement : en partie, la plateforme attachée suit le bloc et emmène J1 (plateforme %.0f px, J1 %.0f px)" % [pf_moved, game.fighters[0].position.x - ride_from])
	GameSetup.map_path = GameSetup.MAPS[0]
	GameSetup.editor_map = {}
	GameSetup.return_scene = ""
	GameSetup.player_devices = []

	# Attaque ultime, étape 1 : jauge perso remplie par SES contres, X + Y quand elle est pleine
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position = Vector2(600, 500); p2.position = Vector2(650, 500)
	await step(30)
	game._clash(p1, p2, p1.position, p1)
	check(p1.ultimate_points == 1 and p2.ultimate_points == 0, "Ultime : un contre remplit la jauge de celui qui contre seulement (%d / %d)" % [p1.ultimate_points, p2.ultimate_points])
	p1.ultimate_points = 0
	light_now(p1, Vector2.RIGHT)
	p2._attack_heavy = true; p2._attack_time = p2.stats.heavy_startup; p2._heavy_charging = false
	game._clash(p1, p2, p1.position)
	check(p1.ultimate_points == Fighter.ULTIMATE_HEAVY_POINTS and p2.ultimate_points == 0, "Ultime : contrer une lourde compte double (%d / %d)" % [p1.ultimate_points, p2.ultimate_points])
	p1._cancel_attack(); p2._cancel_attack()
	game._parry(p1, p2)
	check(p2.ultimate_points == 1, "Ultime : un blocage parfait remplit la jauge de celui qui bloque")
	var round_trip := InputState.from_dict(InputState.new().to_dict())
	var ult_in := InputState.new(); ult_in.ultimate_pressed = true
	check(not round_trip.ultimate_pressed and InputState.from_dict(ult_in.to_dict()).ultimate_pressed, "Ultime : X + Y passe par le réseau")
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position = Vector2(500, 500); p2.position = Vector2(900, 500)
	var ult_used := [0]
	p1.ultimate_used.connect(func(_f): ult_used[0] += 1)
	p1.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS - 1
	p1.input_source = Scripted.new(func(s, f):
		s.attack_pressed = f == 1; s.heavy_pressed = f == 3; s.heavy_held = f >= 3 and f < 6)
	await step(6)
	check(ult_used[0] == 0 and p1.ultimate_points == Fighter.ULTIMATE_POINTS - 1, "Ultime : jauge pas pleine, X + Y ne lance rien")
	await step(60)
	p1._attack_cooldown_timer = 0.0
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1.input_source = Scripted.new(func(s, f):
		s.attack_pressed = f == 1; s.heavy_pressed = f == 3; s.heavy_held = f >= 3 and f < 6
		s.ultimate_pressed = f == 3)
	await step(5)
	check(ult_used[0] == 1 and p1.ultimate_points == 0 and not p1.is_attacking() and p1._ultimate_flash_timer > 0.0,
		"Ultime : X puis Y avec la jauge pleine lance l'ultime, vide la jauge et annule le coup léger")
	await step(60)
	p1._attack_cooldown_timer = 0.0
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1._stun_timer = 1.0
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(3)
	check(ult_used[0] == 1 and p1.is_ultimate_ready(), "Ultime : pas d'ultime en étant sonné")

	# Attaque ultime, étape 2 : le laser gelant de la Barre
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 500; p2.position.x = 900
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(3)
	check(p1.is_lasering() and not p1.is_laser_active() and not p2.is_frozen(), "Laser : il se prépare d'abord (personne n'est gelé)")
	await step(int(Fighter.LASER_STARTUP * 60.0) + 3)
	check(p2.is_frozen() and p2.is_stunned() and p2.lives == p2.max_lives, "Laser : J2, à 400 px, est gelé (et sonné), sans perdre de vie")
	var frozen_x := p2.position.x
	p2.input_source = Scripted.new(func(s, f): s.stick.x = -1.0; s.attack_pressed = f % 5 == 0; s.jump_pressed = f == 2)
	await step(60)
	check(p2.is_frozen() and absf(p2.position.x - frozen_x) < 2.0 and not p2.is_attacking(), "Laser : gelé, J2 ne bouge pas, ne saute pas et n'attaque pas")
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = p2.position.x - 50
	p1._attack_cooldown_timer = 0.0
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 1)
	await step(2 + light_frames)
	check(p2.lives == p2.max_lives - 1 and not p2.is_frozen(), "Laser : gelé puis frappé, J2 perd une vie et n'est plus gelé")
	await step(Fighter.FREEZE_TIME * 60.0 as int)
	# Blocage parfait : le laser s'arrête, c'est un contre (et la Barre ne frappe plus pendant 1 s)
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 500; p2.position.x = 900
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	var laser_frames := int(Fighter.LASER_STARTUP * 60.0)
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= laser_frames - 2)
	await step(laser_frames + 4)
	check(not p2.is_frozen() and not p1.is_lasering() and p1.attack_cooldown_left() > 0.5 and p2.ultimate_points == Fighter.ULTIMATE_HEAVY_POINTS,
		"Laser : un blocage parfait l'arrête, c'est un contre (Barre privée d'attaque, J2 +%d)" % p2.ultimate_points)
	# Bloquer normalement ne protège pas
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	p1.position.x = 500; p2.position.x = 900
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(laser_frames + 4)
	check(p2.is_frozen(), "Laser : un blocage normal ne protège pas")
	# Les autres persos n'ont pas de laser
	GameSetup.player_characters = ["res://characters/jib.tres", ""]
	await new_game()
	GameSetup.player_characters = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 500; p2.position.x = 900
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(laser_frames + 4)
	check(p1.ultimate_points == 0 and not p1.is_lasering() and not p2.is_frozen(), "Laser : seule la Barre tire le laser")

	# Attaque ultime, étape 3 : l'onde de choc de Jumb
	GameSetup.player_characters = ["res://characters/jumb.tres", "", ""]
	GameSetup.player_devices = [[{"type": "keyboard", "layout": 0}], [{"type": "keyboard", "layout": 1}], [{"type": "joypad", "id": 5}]]
	await new_game()
	GameSetup.player_characters = []
	GameSetup.player_devices = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	var wave_p3: Fighter = game.fighters[2]
	for fi in game.fighters:
		fi.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 640; p2.position.x = 840; wave_p3.position.x = 1040
	await step(40)
	var wave_from := p2.position.x
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(3)
	check(p1.is_waving() and p1.wave_radius() == 0.0 and untouched(p2), "Onde : Jumb se ramasse d'abord (personne n'est touché)")
	await step(int((Fighter.WAVE_STARTUP + Fighter.WAVE_ACTIVE) * 60.0) + 2)
	check(p2.is_stunned() and p2.lives == p2.max_lives and untouched(wave_p3), "Onde : J2, à 200 px, est frappé (sonné) ; J3, à 400 px, est trop loin")
	await step(20)
	check(p2.position.x - wave_from > 250.0, "Onde : J2 est projeté très loin (%.0f px)" % (p2.position.x - wave_from))
	# Sonné (ou gelé) puis pris dans l'onde : une vie en moins
	await step(20)
	p2.position.x = 840; p2.velocity = Vector2.ZERO
	p2._invincible_timer = 0.0
	p2.freeze()
	p2._invincible_timer = 0.0
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1._attack_cooldown_timer = 0.0
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(int((Fighter.WAVE_STARTUP + Fighter.WAVE_ACTIVE) * 60.0) + 4)
	check(p2.lives == p2.max_lives - 1, "Onde : gelé par un laser puis pris dans l'onde, J2 perd une vie")
	# Blocage parfait : c'est un contre
	GameSetup.player_characters = ["res://characters/jumb.tres", ""]
	await new_game()
	GameSetup.player_characters = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 640; p2.position.x = 760
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	var wave_frames := int(Fighter.WAVE_STARTUP * 60.0)
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= wave_frames + 3)
	await step(wave_frames + 12)
	check(untouched(p2) and not p1.is_waving() and p1.attack_cooldown_left() > 0.5 and p2.ultimate_points == Fighter.ULTIMATE_HEAVY_POINTS,
		"Onde : un blocage parfait l'arrête, c'est un contre (touché %s, onde %s, recharge %.2f, J2 +%d)" % [touched(p2), p1.is_waving(), p1.attack_cooldown_left(), p2.ultimate_points])

	# Attaque ultime, étape 4 : l'éclair de Jib
	GameSetup.player_characters = ["res://characters/jib.tres", ""]
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 500; p2.position.x = 760
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	await step(int((Fighter.BOLT_STARTUP + Fighter.BOLT_PASS_TIME) * 60.0) + 3)
	check(p2.is_stunned() and p2.lives == p2.max_lives and p1.position.x > p2.position.x - 40,
		"Éclair : 1re traversée, Jib passe à travers J2 et le sonne (Jib x=%.0f, J2 x=%.0f)" % [p1.position.x, p2.position.x])
	await step(60)  # (le jeu ralentit pendant que J2 est sonné)
	check(p2.lives == p2.max_lives - 1 and not p1.is_bolting(), "Éclair : les traversées suivantes lui font perdre une vie")
	# Blocage parfait dès la 1re traversée : c'est un contre
	await new_game()
	GameSetup.player_characters = []
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): pass)
	p1.position.x = 500; p2.position.x = 760
	await step(40)
	p1.ultimate_points = Fighter.ULTIMATE_POINTS
	var bolt_frames := int(Fighter.BOLT_STARTUP * 60.0)
	p1.input_source = Scripted.new(func(s, f): s.ultimate_pressed = f == 1)
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= bolt_frames)
	await step(bolt_frames + 12)
	check(untouched(p2) and not p1.is_bolting() and p1.attack_cooldown_left() > 0.5 and p2.ultimate_points == Fighter.ULTIMATE_HEAVY_POINTS,
		"Éclair : un blocage parfait l'arrête, c'est un contre")

	print("ECHECS: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Chaque plateforme a une forme qui bloque (Collision) et un rectangle de couleur (Visuel) :
## les deux doivent avoir la même taille, sinon on marche dans le vide ou on traverse un mur visible.
func _check_visuals(node: Node, problems: Array[String]) -> void:
	for child in node.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D \
				and node.has_node("Visuel") and node.get_node("Visuel") is ColorRect:
			var size: Vector2 = ((child as CollisionShape2D).shape as RectangleShape2D).size
			var shape_rect := Rect2((child as Node2D).position - size / 2.0, size)
			var v := node.get_node("Visuel") as ColorRect
			var visual_rect := Rect2(v.offset_left, v.offset_top, v.offset_right - v.offset_left, v.offset_bottom - v.offset_top)
			if not shape_rect.is_equal_approx(visual_rect):
				problems.append("%s : Collision et Visuel n'ont pas la même taille" % node.name)
		_check_visuals(child, problems)
