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

	# 4c) Attaque lourde contrée par une légère : personne touché, longue recharge pour les deux, repoussés loin
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 690
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 42)
	var clash_seen := false
	for i in 60:
		await step(1)
		if p2._attack_cooldown_timer > Fighter.ATTACK_COOLDOWN * 2.5:
			clash_seen = true
			break
	check(clash_seen, "Contre : longue recharge pour J2 qui a contré (%.2f s)" % p2._attack_cooldown_timer)
	check(p1._attack_cooldown_timer > Fighter.HEAVY_COOLDOWN, "Contre : même longue recharge pour J1 qui a lancé la lourde (%.2f s)" % p1._attack_cooldown_timer)
	check(p1.lives == 3 and p2.lives == 3, "Contre : personne ne perd de vie (%d / %d)" % [p1.lives, p2.lives])
	var gap_before := p2.position.x - p1.position.x
	await step(20)
	var gap_after := p2.position.x - p1.position.x
	check(gap_after - gap_before > 150, "Contre : les deux sont repoussés loin (écart %.0f -> %.0f)" % [gap_before, gap_after])

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
	check(p2.shield == 2, "Blocage : le bouclier perd 1 point (reste %d)" % p2.shield)
	check(p1.can_attack(), "Blocage : J1 peut refrapper tout de suite")
	await step(10)
	check(p1.position.x < 590, "Blocage : J1 est repoussé (x = %.0f)" % p1.position.x)

	# 4e) Attaque lourde sur le bouclier : -2 points, et casser le bouclier empêche d'attaquer
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 650
	p1.input_source = Scripted.new(func(s, f): s.heavy_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f):
		s.block_held = f < 80
		s.stick.x = 1.0 if f >= 80 else 0.0
		s.attack_pressed = f == 85)
	await step(55)
	check(p2.shield == 1 and p2.lives == 3, "Lourde sur bouclier : -2 points (reste %d, vies %d)" % [p2.shield, p2.lives])
	p2.shield = 1
	p1.position.x = p2.position.x - 50; p1.velocity = Vector2.ZERO
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 2)
	await step(6)
	check(p2.shield == 0 and not p2.is_blocking(), "Bouclier cassé : J2 ne bloque plus (bouclier %d)" % p2.shield)
	check(p2._attack_cooldown_timer > 1.0, "Bouclier cassé : J2 ne peut pas attaquer (%.2f s)" % p2._attack_cooldown_timer)
	var x_before := p2.position.x
	await step(26)
	check(not p2.is_attacking(), "Bouclier cassé : J2 appuie sur X mais n'attaque pas")
	await step(20)
	check(p2.position.x > x_before + 50, "Bouclier cassé : J2 peut toujours bouger")
	await step(int(Fighter.SHIELD_REGEN_TIME * 60) + 5)
	check(p2.shield == 1, "Bouclier : un point revient après 2 s sans bloquer (%d)" % p2.shield)

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
	check(absf(p1.velocity.x) <= Fighter.RUN_SPEED * Fighter.BLOCK_SPEED_MULT + 1, "Blocage : marche lente (vx = %.0f)" % p1.velocity.x)
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

	# 4g) Attaque rapide plus longue : touche à 100 px
	await new_game()
	p1 = game.fighters[0]; p2 = game.fighters[1]
	p1.position.x = 600; p2.position.x = 700
	p1.input_source = Scripted.new(func(s, f): s.attack_pressed = f == 30)
	p2.input_source = Scripted.new(func(s, f): pass)
	await step(36)
	check(p2.lives == 2, "Attaque rapide longue : touche à 100 px (vies = %d)" % p2.lives)

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
	var shuttle: Node2D = game.get_node("Map/ZoneDuel/NavetteHaute")
	p1.position = shuttle.position + Vector2(0, -45)
	await step(20)
	var rider_x := p1.position.x
	var shuttle_x := shuttle.position.x
	await step(60)
	var shuttle_moved := shuttle.position.x - shuttle_x
	check(p1.is_on_floor() and shuttle_moved > 50 and absf((p1.position.x - rider_x) - shuttle_moved) < 6,
		"Plateforme mobile : J1 est transporté (plateforme %.0f px, J1 %.0f px)" % [shuttle_moved, p1.position.x - rider_x])

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
	check(p1.velocity.y <= Fighter.WALL_SLIDE_SPEED + 1, "Mur : glissade lente (vy=%.0f)" % p1.velocity.y)
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

	# 10) Écran de connexion : il faut 2 joueurs pour lancer
	game.queue_free(); game = null
	var lobby: Node = load("res://scenes/lobby.tscn").instantiate()
	add_child(lobby)
	await get_tree().process_frame
	var button: Button = lobby.get_node("Center/Layout/StartButton")
	check(button.disabled, "Lobby : bouton désactivé sans joueur")
	lobby._join({"type": "keyboard", "layout": 0})
	lobby._join({"type": "keyboard", "layout": 0})
	check(button.disabled and lobby._joined.size() == 1, "Lobby : 1 joueur (pas de doublon), toujours désactivé")
	lobby._join({"type": "joypad", "id": 0})
	check(not button.disabled, "Lobby : 2 joueurs, bouton activé")
	await shot("06_lobby")
	lobby._leave({"type": "joypad", "id": 0})
	check(button.disabled, "Lobby : un joueur part, bouton désactivé")

	print("ECHECS: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
