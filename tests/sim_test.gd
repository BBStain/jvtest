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
var shot_dir := ""
var failures := 0

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1

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
	check(p2.lives == 2, "J2 touché, vies = %d" % p2.lives)
	check(p2.is_invincible(), "J2 invincible après le coup")
	check(not p2.can_attack(), "J2 ne peut pas attaquer pendant l'invincibilité")

	# 3) Attaque de loin = dans le vide
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 60)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(80)
	check(p2.lives == 3, "Attaque de loin rate, J2 vies = %d" % p2.lives)

	# 3b) Toute la barre de l'attaque légère touche : même collé à l'adversaire, le coup porte
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p2.input_source = Scripted.new(func(s, f): pass)
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	await step(25)
	p1.position.x = 640; p2.position.x = 652
	await step(10)
	check(p2.lives == 2, "Attaque légère collé à l'adversaire : touché (vies = %d)" % p2.lives)

	# 3c) Portée : le bout de la barre touche, juste au-delà ça rate
	for gap in [base.attack_reach + base.body_size.x / 2.0 - 4.0, base.attack_reach + base.body_size.x / 2.0 + 6.0]:
		await new_game()
		p1 = game.fighters[0]; p2 = game.fighters[1]
		p2.input_source = Scripted.new(func(s, f): pass)
		p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
		await step(25)
		p1.position.x = 600; p2.position.x = 600 + gap
		p1.velocity = Vector2.ZERO; p2.velocity = Vector2.ZERO
		await step(10)
		var reached: bool = gap < base.attack_reach + base.body_size.x / 2.0
		check((p2.lives == 2) == reached, "Portée de l'attaque légère : à %.0f px %s (vies = %d)" % [gap, "touche" if reached else "rate", p2.lives])

	# 4) Choc d'attaques : personne ne perd de vie
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 590; p2.position.x = 690
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	await step(42)
	check(p1.lives == 3 and p2.lives == 3, "Choc : vies %d / %d" % [p1.lives, p2.lives])
	check(p1.position.x < 570 and p2.position.x > 710, "Choc : les deux repoussés (x = %.0f / %.0f)" % [p1.position.x, p2.position.x])
	check(p1.can_attack(), "Choc : J1 peut ré-attaquer vite")
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
	check(p2.lives == 2, "Attaque lourde : J2 touché (vies = %d)" % p2.lives)

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
		if not p1.is_attacking() and p1._attack_cooldown_timer > base.heavy_cooldown + 0.2:
			clash_seen = true
			break
	check(clash_seen and absf(p1._attack_cooldown_timer - Fighter.HEAVY_COUNTERED_COOLDOWN) < 0.05,
		"Contre : J1 qui a lancé la lourde ne frappe plus pendant 1 s (%.2f s)" % p1._attack_cooldown_timer)
	check(p2.can_attack(), "Contre : J2 qui a contré peut refrapper tout de suite (%.2f s)" % p2._attack_cooldown_timer)
	check(p1.lives == 3 and p2.lives == 3, "Contre : personne ne perd de vie (%d / %d)" % [p1.lives, p2.lives])
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
	check(p1.lives == 3 and p2.lives == 3, "Lourde contre lourde : personne ne perd de vie")
	check(is_equal_approx(Engine.time_scale, 1.0), "Lourde contre lourde : pas de ralenti")

	# 4d) Blocage : le coup tombe sur le bouclier, personne ne perd de vie, l'attaquant peut refrapper
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.block_held = true)
	await step(29)
	check(p2.is_blocking(), "Blocage : J2 bloque en tenant B")
	await shot("09_blocage")
	await step(5)
	check(p2.lives == 3, "Blocage : J2 ne perd pas de vie (vies = %d)" % p2.lives)
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
	p2.input_source = Scripted.new(func(s, f): s.block_held = f >= 29 and f < 40)
	await step(34)
	check(p2.lives == 3 and p2.shield == base.shield_max,
		"Blocage parfait : pas de vie perdue, bouclier intact (vies %d, bouclier %d)" % [p2.lives, p2.shield])
	check(not p1.can_attack() and p1._attack_cooldown_timer > Fighter.PARRY_COOLDOWN - 0.1,
		"Blocage parfait : J1 ne peut plus frapper pendant 1 s (%.2f s)" % p1._attack_cooldown_timer)
	check(p2._attack_cooldown_timer <= 0.0, "Blocage parfait : J2 peut riposter tout de suite")
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
	await step(34)
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
		await step(8)
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
	check(p2.shield == base.shield_max - 2 and p2.lives == 3, "Lourde sur bouclier : compte pour 2 coups (reste %d, vies %d)" % [p2.shield, p2.lives])
	p2.shield = 1
	p1.position.x = p2.position.x - 50; p1.velocity = Vector2.ZERO
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 2)
	var shield_gap := p2.position.x - p1.position.x
	await step(6)
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
	await step(36)
	check(p2.lives == 2, "Attaque rapide : touche à 90 px (vies = %d)" % p2.lives)

	# 4h) Attaque lourde non chargée : trop courte à 130 px
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 730
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(60)
	check(p2.lives == 3, "Lourde sans charge : rate à 130 px (vies = %d)" % p2.lives)

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
	check(p2.lives == 2, "Lourde chargée : touche à 130 px (vies = %d)" % p2.lives)

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
	check(p2.lives == 3, "Pendant le dash J2 n'est pas touché (vies = %d)" % p2.lives)

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
		fi._attack_time = base.attack_startup
		fi._attack_cooldown_timer = base.attack_cooldown
	await step(1)
	check(p1.lives == 3 and p2.lives == 3, "Coups simultanés : annulés, personne ne perd de vie (J1 %d, J2 %d)" % [p1.lives, p2.lives])
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
	p1._attack_time = base.attack_startup
	await step(60)
	check(p2.lives == 2 and absf(p2.position.x - 680 - 100) < 8, "Coup léger : J2 repoussé de %.0f px (visé : 100)" % (p2.position.x - 680))

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
		fi._attack_time = base.attack_startup
	await step(1)
	check(f3[0].lives == 3 and f3[1].lives == 2 and f3[2].lives == 2,
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
	p1._attack_time = base.attack_startup
	await step(60)
	check(p2.lives == 2 and p2.position.x - 680 < 70, "Persos : J2, 2 fois plus lourd, recule moins (%.0f px)" % (p2.position.x - 680))
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
	check(p1.is_on_floor() and absf(p1.position.y - (570 - 70)) < 3 and p1.lives == 3,
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

	# 9f) Attaque rapide spammable : en martelant X (1 appui toutes les 4 frames), au moins 7 coups par seconde
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
	check(swings >= 7, "Spam de l'attaque rapide : %d coups en 1 s" % swings)

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
	menu.handle(kb_right, "confirm")
	if await layout.call() != layout_before:
		stable = false
	menu.handle(kb_right, "back")
	check(stable, "Perso : changer de perso ou valider ne fait rien bouger à l'écran")
	menu.handle(kb_left, "quit")
	check(menu.players == [pad, kb_right], "Perso : J3 se retire avec sa touche « se retirer »")
	menu.handle(pad, "right")
	menu.handle(pad, "confirm")
	check(menu.screen == menu.Screen.CHARACTERS and menu._locked == [true, false], "Perso : J1 prêt, on attend J2")
	await shot("08_persos")
	menu.handle(kb_right, "confirm")
	check(menu.screen == menu.Screen.MAPS, "Perso : tout le monde prêt, on passe au choix de la map")
	await shot("09_map")
	menu.handle(pad, "confirm")
	check(GameSetup.player_devices == [[pad], [kb_right]] and GameSetup.player_characters.size() == 2 \
		and GameSetup.map_path == GameSetup.MAPS[0], "Map : la partie est lancée avec les bons joueurs, persos et map")
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
			and c.shield_max >= 1 and c.mass() > 0.0 and c.attack_reach > c.attack_radius \
			and c.heavy_startup < c.heavy_charge_time and c.dash_time > 0.0,
			"Contenu : le perso %s est complet" % path)
	for path in GameSetup.MAPS:
		var m := (load(path) as PackedScene).instantiate() as GameMap
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
	p1._attack_time = base.attack_startup
	await step(1)
	check(p2.lives == 3 and p2.shield == base.shield_max - 1, "Blocage parfait : là, c'est un blocage normal (bouclier %d)" % p2.shield)

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
	p1.input_source = Scripted.new(func(s, f):
		s.attack_pressed = f == 1
		s.heavy_pressed = f == 4
		s.heavy_held = f >= 4)
	await step(20)
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
		fi._attack_time = base.attack_startup
	game._resolve_hits()
	check(f3[0].lives == 3 and f3[1].lives == 3 and f3[2].lives == 3 and not f3[1].is_attacking() and not f3[2].is_attacking(),
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
		fi._attack_time = base.attack_startup
		fi._attack_cooldown_timer = 0.0
	for fi in f4:
		fi.input_source = Scripted.new(func(s, f): pass)
	await step(40)
	# J2 frappe J3 devant lui, J1 est juste derrière J2 : J3 perd une vie, pas J1.
	f4[0].position = Vector2(600, 540); f4[1].position = Vector2(622, 540); f4[2].position = Vector2(640, 540)
	f4[3].position = Vector2(1100, 540)
	set_light.call(f4[1], Vector2.RIGHT)
	game._resolve_hits()
	check(f4[0].lives == 3 and f4[2].lives == 2,
		"4 joueurs : le coup léger touche devant, pas le joueur dans le dos (J1 %d, J3 %d)" % [f4[0].lives, f4[2].lives])
	# Dos à dos : J1 frappe J3 à gauche, J2 frappe J4 à droite -> pas de choc, J3 et J4 sont touchés.
	await step(90)
	for fi in f4:
		fi.lives = 3
		fi._invincible_timer = 0.0
		fi._attack_time = -1.0
		fi.velocity = Vector2.ZERO
	f4[2].position = Vector2(575, 540); f4[0].position = Vector2(600, 540)
	f4[1].position = Vector2(630, 540); f4[3].position = Vector2(655, 540)
	set_light.call(f4[0], Vector2.LEFT)
	set_light.call(f4[1], Vector2.RIGHT)
	game._resolve_clashes()
	game._resolve_hits()
	check(f4[2].lives == 2 and f4[3].lives == 2 and f4[0].lives == 3 and f4[1].lives == 3,
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
			if b.lives == 3:
				set_light.call(b, Vector2.RIGHT))
		var outcome := ""
		for k in 40:
			await step(1)
			if Engine.time_scale < 0.99:
				outcome = "duel"
				break
			if b.lives < 3:
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
	game._clash(game.fighters[0], game.fighters[2], game.fighters[0].position)
	check(is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION), "Duel à 4 joueurs : un duelliste qui contre un autre joueur relance le ralenti")
	game._time_engine._time_left = 2.0
	game._clash(game.fighters[0], game.fighters[1], game.fighters[0].position)
	check(is_equal_approx(game._time_engine._time_left, Game.DUEL_DURATION), "Duel à 4 joueurs : un contre entre duellistes relance le ralenti")
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
	check(p2.lives == 3, "Attaque visée : J2, derrière, n'est pas touché")
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
	check(f3[1].lives == 3 and f3[2].lives == 2,
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
	check(g1.net_state() == host_state[4] and g2.net_state() == host_state[5],
		"En ligne (copain) : les joueurs sont affichés exactement comme chez l'hôte")
	check(g1.is_charging_heavy() and g2.shield == 7 and g2.lives == 2, "En ligne (copain) : charge de la lourde, bouclier et vies reçus")
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
