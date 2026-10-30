class_name Fighter
extends CharacterBody2D
## Un combattant : une barre verticale qui court, saute, dashe et attaque.
##
## Le combattant ne lit pas la manette lui-même : à chaque frame, le jeu (game.gd)
## lui donne un InputState via physics_tick(). Les coups et les chocs d'attaques
## sont gérés par game.gd, qui voit tous les combattants à la fois.
##
## Les caractéristiques propres à chaque personnage (vitesse, sauts, dash, attaques, poids...)
## sont dans "stats" : un fichier .tres du dossier characters/ (voir character_stats.gd).
## Les constantes ci-dessous sont les règles communes à tous les personnages.

signal life_lost(fighter: Fighter)
signal weapon_thrown(fighter: Fighter, direction: Vector2, speed: float)  ## lance : game.gd crée la lance qui vole
signal arrow_shot(fighter: Fighter, direction: Vector2, speed: float, knockback: float)  ## arc : game.gd crée la flèche
signal weapon_tossed(fighter: Fighter)  ## RB : on lance son arme (sans dégâts), game.gd la fait voler
## Un objet utilisé (balle tirée, grenade lancée ou lâchée) : game.gd crée ce qui vole.
## power : 0 à 1 (distance de la grenade) ; fuse : temps restant avant que la grenade explose.
signal item_used(fighter: Fighter, kind: String, direction: Vector2, power: float, fuse: float)
signal item_tossed(fighter: Fighter, kind: String, ammo: int)  ## RB avec une arme à 2 mains : game.gd la fait voler (objet par terre)
signal grapple_parried(fighter: Fighter, by: Fighter)  ## notre grappin arrive sur un blocage parfait
signal ultimate_used(fighter: Fighter)  ## X + Y avec la jauge d'ultime pleine : game.gd lance l'attaque ultime du perso

const PLATFORM_LAYER := 3  ## numéro de la couche "plateformes_traversables"

# --- Déplacement ---
const COYOTE_TIME := 0.1                ## on peut encore sauter un instant après avoir quitté le bord
const JUMP_BUFFER := 0.12               ## un saut appuyé juste avant d'atterrir compte quand même
const DROP_THROUGH_TIME := 0.22         ## temps pendant lequel on traverse les plateformes après "bas"
const DROP_STICK := 0.3                 ## stick poussé vers le bas au-delà de ça (1 = tout en bas) : on descend

# --- Murs ---
const WALL_JUMP_LOCK := 0.1             ## petit temps où l'on contrôle moins bien après un saut mural
const WALL_JUMP_ACCEL := 2200.0

# --- Échelle (voir ladder.gd) ---
const LADDER_GRAB_STICK := 0.5          ## stick poussé vers le haut au-delà de ça : on s'accroche à l'échelle
const LADDER_CLIMB_SPEED := 1500.0      ## on monte très vite, tout seul
const LADDER_REGRAB_TIME := 0.35        ## après avoir lâché l'échelle, on ne se raccroche pas tout de suite
const LADDER_FLING_TIME := 0.25         ## éjecté en haut de l'échelle : on garde son élan sur le côté ce temps

# --- Liane (voir vine.gd) : on s'y balance comme un pendule ---
const VINE_GRAB_MARGIN := 14.0          ## on attrape la liane à cette distance du corps
const VINE_REGRAB_TIME := 0.3           ## après avoir lâché une liane, on ne se raccroche pas tout de suite
const VINE_MIN_LENGTH := 60.0           ## on ne se tient jamais plus près que ça du point d'accroche
const VINE_PUMP := 1500.0               ## élan pris avec gauche / droite
const VINE_DAMPING := 0.2               ## le balancement ralentit un peu tout seul
const VINE_MAX_SPEED := 1200.0          ## vitesse max en se balançant
const VINE_MAX_ANGLE := 1.75            ## on monte au plus un peu au-dessus de l'horizontale (en radians, 1,57 = horizontal)
const VINE_JUMP_BOOST := 0.4            ## en sautant de la liane : petit saut en plus de l'élan (part du double saut)
const VINE_FLING_TIME := 0.3            ## après avoir lâché la liane, on garde son élan ce temps

# --- Fenêtres (voir breakable_window.gd) ---
const WINDOW_BREAK_SPEED := 900.0       ## percuter une fenêtre au moins aussi vite (dash, projeté) la casse
const WINDOW_BREAK_KEEP := 0.85         ## ... et on passe au travers en gardant cette part de sa vitesse

# --- Dash ---
const DASH_END_KEEP := 0.55             ## part de la vitesse gardée à la fin du dash

# --- Attaque légère (X) : un coup droit vers l'adversaire ---
const ATTACK_BUFFER := 0.12             ## X appuyé un peu trop tôt compte quand même
const CLASH_LOCKOUT := 0.08             ## petit temps mort après un contre (la recharge repart presque de zéro)
const LIGHT_DEPLOY_TIME := 0.06         ## le coup léger se déploie : la barre sort du perso et s'allonge pendant ce temps...
const LIGHT_DEPLOY_START := 0.3         ## ... en partant de 30 % de sa longueur

# --- Attaque lourde (Y) : un arc de cercle du dessus de la tête jusqu'aux pieds, devant soi ---
# On la charge en gardant Y appuyé : plus on charge, plus l'arme grandit et frappe loin.
# On frappe en lâchant Y (ou tout seul quand la charge est au maximum).
# Pendant la frappe, le perso est immobilisé.
const HEAVY_CHARGE_GROWTH := 2.0        ## à pleine charge, l'arme est 2 fois plus longue
const HEAVY_CHARGE_TIP_GROWTH := 1.5    ## à pleine charge, la zone qui touche est 1,5 fois plus grosse
const HEAVY_CHARGE_KNOCKBACK := 1.5     ## à pleine charge, on projette 1,5 fois plus fort
const HEAVY_ARC_START := -100.0         ## angle de départ en degrés (-90 = droit au-dessus de la tête)
const HEAVY_ARC_END := 32.0             ## angle d'arrivée (à hauteur des pieds, devant soi)
const HEAVY_COUNTERED_COOLDOWN := 1.0   ## attaque lourde contrée par une légère : celui qui l'a lancée ne frappe
                                        ## plus pendant 1 s ; celui qui contre peut refrapper tout de suite
const HEAVY_COUNTER_PUSH := 750.0       ## ... et les deux sont repoussés plus loin
const HEAVY_CLASH_PUSH := 1150.0        ## deux attaques lourdes qui se percutent : micro-explosion, éjectés fort
const HEAVY_CLASH_LIFT := 320.0         ## ... et un peu soulevés

# --- Armes (voir weapon_stats.gd) ---
const KATANA_DASH_END_KEEP := 0.4       ## fin du dash du katana : part de la vitesse gardée
const KATANA_DASH_REACH := 0.8          ## la lame dépasse du perso de 0,8 fois la longueur de l'arme
const SLAM_WAVE_TIME := 0.12            ## marteau : durée de l'onde de choc après l'arc
const SLAM_WAVE_REACH := 150.0          ## ... jusqu'où elle va de chaque côté (x1,6 à pleine charge)
const SLAM_WAVE_RADIUS := 14.0          ## ... sa hauteur (de chaque côté du sol)
const WEAPON_MAX_COUNTERS := 3         ## lourde d'une arme contrée 3 fois : arme cassée pour de bon
const WEAPON_SHRINK := 0.2              ## chaque contre rapetisse l'arme de 20 % (100 %, 80 %, 60 %)
const WEAPON_REPAIR_COUNTERS := 2       ## contrer 2 fois avec le coup léger de son arme la répare d'un cran
const WEAPON_REPAIR_FLASH := 0.5        ## arme réparée : un anneau de sa couleur apparaît ce temps
const THROW_CHARGE_SPEED := 1.5         ## lance / dash du katana : à pleine charge, 1,5 fois plus vite
const SWING_TILT := 25.0                ## nunchaku : le coup part 25° plus bas (ou plus haut) que l'adversaire...
const SWING_PUSH_SIDE := 0.5            ## ... et projette surtout vers le bas (ou le haut), un peu vers l'avant
const BURST_HITS := 3                   ## nunchaku : la lourde est une rafale de 3 coups...
const BURST_HIT_TIME := 0.12            ## ... un toutes les 0,12 s (chacun peut toucher)
const BURST_CHARGE_REACH := 1.8         ## ... à pleine charge, ils vont 1,8 fois plus loin
const ARROW_CHARGE_SPEED := 1.8         ## arc : à pleine charge, la flèche part 1,8 fois plus vite (donc plus loin)
const ARROWS_MAX := 5                   ## arc : 5 flèches ; il faut aller les ramasser (seul celui qui tient cet arc le peut)

# --- Objets ramassés sur la map (un seul à la fois, utilisé avec RT ; voir item_pickup.gd) ---
const PISTOL_AMMO := 5                  ## balles du pistolet (une par appui)
const PISTOL_COOLDOWN := 0.18           ## temps minimum entre deux balles
## Ville : fusil d'assaut et lance-roquette sont des objets à 2 MAINS : tant qu'on les tient, plus
## d'attaque X / Y (ni d'ultime) ; RB les jette par terre pour reprendre son arme. Vides, ils disparaissent.
const TWO_HANDED_ITEMS := ["fusil", "lance_roquette"]
const RIFLE_AMMO := 30                  ## fusil d'assaut : 30 balles, par rafales de 3 (RT)
const RIFLE_BURST := 3
const RIFLE_GAP := 0.07                 ## entre deux balles d'une rafale
const RIFLE_COOLDOWN := 0.4             ## entre deux rafales
const RIFLE_BULLET_SPEED := 1.25        ## ses balles vont 1,25 fois plus vite que celles du pistolet
const LAUNCHER_BLAST := 1.8             ## lance-roquette : UNE roquette, plus violente qu'une roquette de mecha chargée à fond (1)
const GRENADE_FUSE := 3.0               ## la grenade explose 3 s après avoir été dégoupillée (RT appuyé)
const GRENADE_FULL_HOLD := 1.0          ## RT gardé ce temps : la grenade part le plus loin possible
const ITEM_SHIELD_TIME := 5.0           ## le bouclier ramassé reste levé 5 s
const ITEM_SHIELD_PUSH := 1300.0        ## qui frappe le bouclier ramassé est projeté très loin...
const ITEM_SHIELD_COOLDOWN := 0.5       ## ... et ne peut plus frapper un instant
const ITEM_FLASH_TIME := 0.4            ## objet ramassé : un anneau de sa couleur apparaît ce temps
const GRAPPLE_USES := 3                 ## le grappin sert 3 fois
const GRAPPLE_SPEED := 2400.0           ## vitesse du crochet, qui part toujours vers l'adversaire le plus proche
const GRAPPLE_RANGE := 900.0            ## au-delà, il revient sans rien accrocher (un mur l'arrête aussi)
const GRAPPLE_PULL := 1300.0            ## vitesse à laquelle la corde tire
const GRAPPLE_MAX_TIME := 1.2           ## on ne reste pas accroché plus longtemps
const GRAPPLE_ARRIVE := 70.0            ## les deux sont arrivés l'un contre l'autre : la corde se décroche...
const GRAPPLE_ARRIVE_KEEP := 0.4        ## ... et celui qui était tiré garde 40 % de son élan
const GRAPPLE_FLING_TIME := 0.35        ## corde lâchée en route : celui qui était tiré garde tout son élan ce temps
enum Grapple { NONE, FLYING, PULL_SELF, PULL_THEM }

# --- Ville : piloter un mecha (voir scripts/ville/mecha.gd) ---
const MECHA_BOARD_STICK := 0.5          ## collé à un mecha vide, stick vers le haut au-delà de ça : on monte dedans
const MECHA_REBOARD_TIME := 0.6         ## juste après être sorti, on ne remonte pas tout de suite
const MECHA_EXIT_LIFT := 750.0          ## en sortant, on saute par le haut du mecha
const MECHA_EJECT_SPEED := 1100.0       ## mecha détruit : le pilote est éjecté vers le haut, sonné

# --- Blocage (B) : un bouclier qui craque peu à peu (ses points sont dans les stats du perso) ---
const SHIELD_REGEN_TIME := 2.0          ## 1 point regagné toutes les 2 s quand on ne bloque pas
const SHIELD_BREAK_COOLDOWN := 2.0      ## bouclier cassé : pas d'attaque pendant ce temps (on peut bouger)
const SHIELD_BREAK_PUSH := 1000.0       ## bouclier cassé : les deux joueurs sont éjectés...
const SHIELD_BREAK_LIFT := 300.0        ## ... et un peu soulevés
const HEAVY_SHIELD_DAMAGE := 2          ## l'attaque lourde compte pour 2 coups, la légère pour 1
const BLOCK_SPEED_MULT := 0.3           ## en bloquant, on se déplace beaucoup plus lentement
const BLOCK_JUMP_MULT := 0.7            ## en bloquant, on saute environ 2 fois moins haut
const SHIELD_HIT_PUSH := 380.0          ## l'attaquant qui frappe le bouclier est repoussé
const SHIELD_BLOCKER_PUSH := 120.0      ## celui qui bloque recule un tout petit peu
const PARRY_WINDOW := 0.15              ## blocage parfait : B appuyé au plus tant de secondes avant le coup...
const PARRY_COOLDOWN := 1.0             ## ... c'est un contre : celui qui frappait ne frappe plus pendant 1 s

# --- Attaque ultime : chaque perso a sa jauge, remplie par SES contres ---
const ULTIMATE_POINTS := 20             ## 20 contres pour remplir la jauge d'ultime...
const ULTIMATE_HEAVY_POINTS := 2        ## ... contrer une attaque lourde compte double
const ULTIMATE_FLASH_TIME := 0.5        ## ultime lancée : une onde blanche part du perso
const ULTIMATE_PARTICLES := 18          ## l'aura autour du perso : jusqu'à 18 particules (jauge pleine)
const LASER_STARTUP := 0.3              ## Barre : le laser se prépare (fin trait bleu vers l'adversaire)...
const LASER_ACTIVE := 0.25              ## ... puis tire : il gèle tous ceux qu'il traverse pendant ce temps
const LASER_RANGE := 1400.0             ## il va jusque-là, ou jusqu'au premier mur
const LASER_RADIUS := 10.0              ## demi-épaisseur du rayon
const LASER_COLOR := Color(0.35, 0.7, 1.0)
const WAVE_STARTUP := 0.25              ## Jumb : il se ramasse, un cercle se forme autour de lui...
const WAVE_ACTIVE := 0.3                ## ... puis le cercle s'ouvre : il frappe tous ceux qu'il atteint...
const WAVE_START_RADIUS := 40.0
const WAVE_RADIUS := 280.0              ## ... jusqu'à cette distance du centre de Jumb
const WAVE_KNOCKBACK := 1700.0          ## ... et les projette très loin (vers l'extérieur, un peu vers le haut)
const WAVE_LIFT := 0.35
const WAVE_COLOR := Color(1.0, 0.62, 0.25)
const BOLT_STARTUP := 0.15              ## Jib : un éclair jaune l'entoure...
const BOLT_PASSES := 3                  ## ... puis il fonce 3 fois à travers l'adversaire...
const BOLT_PASS_TIME := 0.12            ## ... chaque traversée dure ce temps...
const BOLT_GAP := 0.08                  ## ... avec un petit arrêt entre deux (il vise à nouveau)
const BOLT_OVERSHOOT := 140.0           ## il ressort de l'autre côté de l'adversaire de cette distance
const BOLT_SPEED_MIN := 1500.0
const BOLT_SPEED_MAX := 4200.0          ## (un adversaire très loin n'est pas forcément rattrapé)
const BOLT_REACH := 14.0                ## chaque traversée frappe ceux qu'elle touche (corps de Jib élargi de ça)
const BOLT_KNOCKBACK := 650.0
const BOLT_COLOR := Color(1.0, 0.92, 0.3)
const FREEZE_TIME := 3.0                ## gelé par le laser : ni bouger ni attaquer pendant 3 s ; le coup suivant fait perdre une vie

# --- Effets de la jauge de contre (une seule pour toute la partie, voir counter_gauge.gd) ---
const PHASE_COOLDOWN := [1.0, 0.7, 0.45, 0.35]  ## recharge des attaques selon la phase (0,5 = 2 fois plus courte)
const PHASE_SHIELD_DAMAGE := [1, 2, 3, 3]       ## les coups abîment les boucliers 1, 2 ou 3 fois plus
const BERSERK_MOVE := 1.25              ## berserk : on court et on dashe 1,25 fois plus vite...
const BERSERK_JUMP := 1.12              ## ... on saute plus haut...
const BERSERK_ATTACK_SPEED := 1.4       ## ... les attaques partent et se chargent 1,4 fois plus vite...
const BERSERK_RANGE := 1.3              ## ... et vont 1,3 fois plus loin

# --- Course (LT / Shift, à maintenir) et endurance ---
const STAMINA_BLOCK_SPRINT_MULT := 2.33  ## en bloquant tout en courant, l'endurance part 2,33 fois plus vite
const STAMINA_REGEN_DELAY := 0.6        ## temps avant que l'endurance remonte
const STAMINA_RESTART := 25.0           ## jauge vide : il faut remonter jusque-là pour recourir
const STAMINA_SHOW_TIME := 1.0          ## la jauge reste affichée ce temps après être pleine

# --- Coup reçu ---
# Un premier coup sonne (pas de vie perdue). Sonné, le coup suivant retire une vie : pour s'en
# sortir, il faut contrer ou faire un blocage parfait (un blocage normal ne protège plus).
const STUN_TIME := 2.0                  ## durée pendant laquelle on reste sonné
const STUN_GRACE := 0.3                 ## juste après avoir été sonné, on ne peut pas être touché tout de suite
const INVINCIBLE_TIME := 1.2            ## après avoir perdu une vie ; doit rester plus long que la recharge de l'attaque légère
const CLASH_PUSH := 450.0
const KNOCKBACK_TIME := 0.2             ## durée pendant laquelle on contrôle moins bien après un coup / un choc
const KNOCKBACK_ACCEL := 2000.0

const START_LIVES := 3
const MAX_LIVES := 10                  ## l'objet « vie » ne fait pas monter au-delà

## Jeu en ligne : ce que l'hôte envoie aux copains à chaque frame pour qu'ils dessinent ce joueur
## (voir net_state). Tout ce que _draw() utilise doit être dans cette liste.
const NET_VARS := [
	"position", "velocity", "facing", "lives", "eliminated", "visible",
	"_attack_time", "_attack_dir", "_attack_heavy", "_heavy_charging", "_charge_time", "_heavy_charge",
	"stamina", "_exhausted", "_sprinting", "_stamina_show_timer",
	"shield", "shield_broken", "_blocking", "_shield_broken_timer", "_shield_flash_timer",
	"_invincible_timer", "_lives_show_timer", "_blink_clock", "_dash_timer", "_dash_dir", "_wall_normal_x",
	"_stun_timer", "_block_hold_time", "weapon_id", "weapon_away", "weapon_counters",
	"item", "item_ammo", "_grenade_fuse", "_grenade_hold", "item_shield_timer",
	"_swinging", "_swing_anchor", "_swing_up", "arrows", "grapple_mode", "grapple_point", "_item_flash_timer", "_item_flash_kind", "_repair_flash_timer",
	"ultimate_points", "_ultimate_flash_timer", "_laser_time", "_laser_dir", "_laser_length", "_frozen_timer", "_wave_time", "_bolt_time", "_bolt_dir",
]
const LIVES_SHOW_TIME := 2.0            ## durée d'affichage des vies au-dessus de la tête

var stats: CharacterStats = CharacterStats.new()  ## le personnage joué, avec son arme en main (choisi par game.gd)
var weapon: WeaponStats = WeaponStats.new()       ## l'arme choisie (choisie par game.gd ; mains nues par défaut)
## L'arme en jeu en ligne : son fichier (l'hôte l'envoie, un copain la change s'il en a ramassé une autre).
var weapon_id: String:
	get:
		return weapon.resource_path
	set(value):
		if value == "" or value == weapon.resource_path:
			return
		weapon = load(value) as WeaponStats
		if _armed_stats != null:
			_update_armed_stats()
			stats = _bare_stats if weapon_away else _armed_stats
## Lance lancée et pas encore ramassée : on se bat à mains nues en attendant.
var weapon_away := false:
	set(value):
		if value == weapon_away:
			return  # en ligne, l'hôte la renvoie à chaque frame : rien à refaire si elle ne change pas
		weapon_away = value
		if _armed_stats != null:
			stats = _bare_stats if value else _armed_stats
## Combien de fois l'attaque lourde de son arme a été contrée (lance lancée comprise). Chaque contre
## rapetisse l'arme ; au bout de WEAPON_MAX_COUNTERS elle est cassée : mains nues jusqu'à la prochaine
## vie perdue, où une arme neuve revient.
var weapon_counters := 0:
	set(value):
		if value == weapon_counters:
			return  # pareil : on ne recalcule l'arme que si elle change
		weapon_counters = value
		if _armed_stats != null:
			_update_armed_stats()
			stats = _bare_stats if weapon_away else _armed_stats
var _bare_stats: CharacterStats                   ## le perso sans arme
var _armed_stats: CharacterStats                  ## le perso avec son arme
var player_index := 0
var color := Color.WHITE
var input_source: InputSource
var target: Fighter                     ## l'adversaire visé par l'attaque (choisi par game.gd)

var lives := START_LIVES
var max_lives := START_LIVES  ## vies au début de la partie (pour le dessin des vies)
var eliminated := false
var facing := 1.0                       ## 1 = regarde à droite, -1 = à gauche

var _air_jumps_left := 0
var _air_dashes_left := 0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _drop_timer := 0.0
var _wall_normal_x := 0.0               ## -1 / 1 quand on glisse contre un mur, 0 sinon
var _wall_jump_timer := 0.0
var _jump_rising := false              ## true = on monte grâce à un saut (pour le petit saut)
var _ladder: Ladder = null              ## l'échelle sur laquelle on grimpe (null = pas d'échelle)
var _ladder_regrab_timer := 0.0
var _ladder_fling_timer := 0.0          ## éjecté (échelle) ou lâché d'une liane : on garde son élan
var _vine: Vine = null                  ## la liane à laquelle on se balance (null = pas de liane)
var _swinging := false                  ## pareil, envoyé aux copains en ligne (pour dessiner la liane)
var _swing_anchor := Vector2.ZERO       ## le point d'accroche de la liane
var _swing_length := 0.0
var _swing_angle := 0.0                 ## 0 = droit sous le point d'accroche
var _swing_speed := 0.0                 ## vitesse de rotation (radians par seconde)
var _vine_regrab_timer := 0.0

var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_dir := Vector2.RIGHT

var _attack_time := -1.0                ## temps écoulé depuis le début de l'attaque (-1 = pas d'attaque)
var _attack_dir := Vector2.RIGHT
var _attack_has_hit := false
var _swing_up := true                   ## nunchaku : le dernier coup allait vers le haut (le prochain ira vers le bas)
var arrows := ARROWS_MAX                ## arc : flèches qui restent dans l'arc (elles suivent l'arc s'il change de main)
var bow_id := 0                         ## arc : de quel arc il s'agit (ses flèches ne se ramassent qu'avec lui)
var _burst_index := 0                   ## nunchaku : quel coup de la rafale est en cours
var _attack_heavy := false              ## true = attaque lourde en cours
var _attack_cooldown_timer := 0.0
var _attack_buffer_timer := 0.0
var _aimed_dir := Vector2.ZERO   ## direction du coup visé en attente (stick droit), ou ZERO : visée auto
var _heavy_buffer_timer := 0.0          ## pareil pour Y : appuyé un peu trop tôt, il compte quand même
var _heavy_charging := false            ## true = on garde Y pour charger l'attaque lourde
var _charge_time := 0.0
var _heavy_charge := 0.0                ## 0 = pas chargée, 1 = charge pleine

var stamina := 0.0
var _sprinting := false
var _exhausted := false                 ## jauge vidée : on ne peut plus courir tant qu'elle n'est pas remontée
var _stamina_regen_timer := 0.0
var _stamina_show_timer := 0.0

var shield := 0
var shield_broken := false              ## cassé : plus de blocage jusqu'à la fin de la partie
var _cracks: Array[PackedVector2Array] = []  ## les fissures du bouclier, une par point perdu
var _blocking := false
var _block_hold_time := 0.0             ## depuis combien de temps B est appuyé (pour le blocage parfait)
var _shield_regen_timer := 0.0
var _shield_broken_timer := 0.0         ## pour l'effet visuel du bouclier cassé
var _shield_flash_timer := 0.0          ## petit éclat quand le bouclier encaisse un coup

var item := ""                          ## l'objet ramassé : "", "pistolet", "grenade", "bouclier", "vie", "grappin" ou "balise" (Ville)
var item_ammo := 0                      ## balles qui restent dans le pistolet (ou lancers du grappin)
var item_shield_timer := 0.0            ## bouclier ramassé levé encore ce temps
var _item_cooldown := 0.0
var _rifle_burst_left := 0               ## balles de la rafale en cours qui restent à partir
var _rifle_gap_timer := 0.0              ## avant la balle suivante de la rafale
var _grenade_fuse := -1.0               ## grenade dégoupillée en main : temps avant l'explosion (-1 = non)
var _grenade_hold := 0.0                ## depuis combien de temps RT est gardé (distance du lancer)
var _item_flash_timer := 0.0            ## > 0 juste après avoir ramassé un objet (ou pris une vie)
var _item_flash_kind := ""              ## l'objet de cet anneau (pour sa couleur)
var _repair_flash_timer := 0.0          ## > 0 juste après que son arme a été réparée
var grapple_mode := Grapple.NONE       ## grappin : crochet qui vole, ou corde qui tire (nous ou l'autre)
var grapple_point := Vector2.ZERO       ## où est le crochet (dans la map)
var _grapple_target: Fighter            ## celui que le crochet vise / a accroché
var _grapple_target_lives := 0          ## s'il perd une vie, la corde se décroche
var _grapple_tap := false               ## RT lâché avant que le crochet accroche : c'est nous qui sommes tirés
var _grapple_time := 0.0
var _grapple_dist := 0.0
var _grappled_by: Fighter               ## celui dont la corde nous tire vers lui
var _repair_counters := 0               ## contres au coup léger depuis la dernière réparation (voir weapon_light_counter)

var mecha: Mecha = null                 ## Ville : le mecha qu'on pilote (null = à pied)
var _mecha_reboard_timer := 0.0

var gauge := CounterGauge.new()         ## la jauge de contre de la partie (partagée, donnée par game.gd)
var ultimate_points := 0                ## la jauge d'ultime de ce joueur (pleine à ULTIMATE_POINTS)
var _ultimate_flash_timer := 0.0        ## > 0 juste après avoir lancé son ultime
var _laser_time := -1.0                 ## Barre : temps depuis le début du laser (-1 = pas de laser)
var _laser_dir := Vector2.RIGHT
var _laser_length := LASER_RANGE        ## jusqu'au premier mur
var laser_frozen: Array[Fighter] = []   ## ceux que ce laser a déjà touchés (une fois chacun)
var _frozen_timer := 0.0                ## > 0 : gelé par un laser
var _wave_time := -1.0                  ## Jumb : temps depuis le début de l'onde de choc (-1 = pas d'onde)
var wave_hit: Array[Fighter] = []       ## ceux que cette onde a déjà frappés (une fois chacun)
var _bolt_time := -1.0                  ## Jib : temps depuis le début de l'éclair (-1 = pas d'éclair)
var _bolt_pass := -1                    ## quelle traversée est en cours (pour viser au début de chacune)
var _bolt_dir := Vector2.RIGHT
var _bolt_speed := BOLT_SPEED_MIN
var bolt_hit: Array[Fighter] = []       ## ceux que la traversée en cours a déjà frappés

var _stun_timer := 0.0
var _invincible_timer := 0.0
var _knockback_timer := 0.0
var _lives_show_timer := 0.0
var _blink_clock := 0.0


## Le corps est créé à l'entrée dans la partie, une fois le personnage (stats) choisi.
func _ready() -> void:
	add_to_group("combattants")
	_bare_stats = stats
	_update_armed_stats()
	stats = _bare_stats if weapon_away else _armed_stats
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	stamina = stats.stamina_max
	shield = stats.shield_max
	_make_cracks()
	collision_layer = 0
	set_collision_layer_value(2, true)          # on est un "joueur"
	collision_mask = 0
	set_collision_mask_value(1, true)           # on touche le sol
	set_collision_mask_value(PLATFORM_LAYER, true)
	floor_snap_length = 6.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = stats.body_size
	shape.shape = rect
	add_child(shape)


## Appelé par game.gd une fois par frame physique.
func physics_tick(input: InputState, delta: float) -> void:
	_tick_timers(delta)
	if eliminated:
		return
	if mecha != null:
		_tick_mecha(input, delta)
		return
	if is_frozen():
		# Gelé : on ne fait plus rien, on tombe seulement si on était en l'air.
		velocity.x = move_toward(velocity.x, 0.0, stats.ground_accel * delta)
		velocity.y = minf(velocity.y + stats.gravity * delta, stats.max_fall_speed)
		_blocking = false
		_sprinting = false
		_move()
		queue_redraw()
		return

	if input.throw_pressed:
		_toss_weapon()

	var on_floor := is_on_floor()
	if on_floor:
		_air_jumps_left = stats.air_jumps
		_air_dashes_left = stats.air_dashes
		_coyote_timer = COYOTE_TIME

	if input.stick.x != 0.0 and not is_attacking():
		facing = signf(input.stick.x)

	# Collé à un mur en l'air (en poussant vers lui) : on glisse, et sauts + dash sont rechargés.
	_wall_normal_x = 0.0
	if not on_floor and is_on_wall():
		var normal_x := get_wall_normal().x
		if absf(normal_x) > 0.5 and input.stick.x * normal_x < -0.3:
			_wall_normal_x = signf(normal_x)
			_air_jumps_left = stats.wall_jumps
			_air_dashes_left = stats.air_dashes
			_dash_cooldown_timer = 0.0
			facing = _wall_normal_x

	# Ville : "haut" en touchant un mecha vide pour monter dedans (pas sonné : il faut d'abord s'en sortir).
	if input.stick.y < -MECHA_BOARD_STICK and _mecha_reboard_timer <= 0.0 and not is_stunned() \
			and not is_attacking() and not is_dashing():
		var empty := _touched_mecha()
		if empty != null:
			_board(empty)
			return

	# Échelle : "haut" en la touchant pour s'accrocher ; on monte tout seul (rien d'autre à faire).
	if _ladder == null and _ladder_regrab_timer <= 0.0 and input.stick.y < -LADDER_GRAB_STICK \
			and not is_heavy_swinging():
		_ladder = _touched_ladder()
		if _ladder != null:
			_cancel_attack()
			_dash_timer = 0.0
			_air_jumps_left = stats.air_jumps
			_air_dashes_left = stats.air_dashes
	if _ladder != null:
		_blocking = false
		_sprinting = false
		_tick_ladder(input)
		_tick_item(input, delta)  # une grenade dégoupillée continue de compter sur l'échelle
		move_and_slide()
		queue_redraw()
		return

	# Liane : on s'y accroche tout seul en la touchant en l'air, et on se balance.
	if _vine == null and not on_floor and _vine_regrab_timer <= 0.0 and _knockback_timer <= 0.0 \
			and not is_heavy_swinging() and not is_katana_dashing():
		var vine := _touched_vine()
		if vine != null:
			_grab_vine(vine)
	if _vine != null:
		_blocking = false
		_sprinting = false
		_tick_vine(input, delta)
		_tick_item(input, delta)
		queue_redraw()
		return

	# Descendre d'une plateforme traversable avec "bas" (pas besoin d'aller tout en bas avec le stick).
	if on_floor and (input.down_pressed or input.stick.y > DROP_STICK):
		_drop_timer = DROP_THROUGH_TIME
	set_collision_mask_value(PLATFORM_LAYER, _drop_timer <= 0.0)

	_update_block(input, delta)
	_update_sprint(input, delta)

	if input.dash_pressed and not _blocking:
		_try_start_dash(input, on_floor)

	if is_dashing():
		_tick_dash(delta)
	elif is_katana_dashing():
		velocity = _attack_dir * weapon.heavy_speed * lerpf(1.0, THROW_CHARGE_SPEED, _heavy_charge) * _move_mult()
	elif is_bolt_passing():
		velocity = _bolt_dir * _bolt_speed  # Jib : il fonce à travers l'adversaire
	elif is_heavy_swinging() or is_ultimate_under_way():
		velocity = Vector2.ZERO  # immobilisé pendant la frappe lourde (et pendant les ultimes)
	else:
		_tick_movement(input, on_floor, delta)

	# X et Y sont gardés en mémoire un court instant : en martelant, le coup suivant part dès que
	# possible, et un Y appuyé juste avant la fin d'une recharge n'est pas perdu.
	if input.attack_pressed:
		_attack_buffer_timer = ATTACK_BUFFER
		_aimed_dir = Vector2.ZERO
	if input.aimed_attack_pressed and input.aim != Vector2.ZERO:
		_attack_buffer_timer = ATTACK_BUFFER
		_aimed_dir = input.aim.normalized()
	if input.heavy_pressed:
		_heavy_buffer_timer = ATTACK_BUFFER
	if input.ultimate_pressed and can_use_ultimate():
		_use_ultimate()
	if not _blocking and can_attack():  # pas d'attaque en bloquant
		if _attack_buffer_timer > 0.0:
			_attack_buffer_timer = 0.0
			_heavy_buffer_timer = 0.0
			_try_start_attack(false)
		elif _heavy_buffer_timer > 0.0:
			_heavy_buffer_timer = 0.0
			_try_start_attack(true)
	_tick_attack(input, delta)
	_tick_laser(delta)
	if _wave_time >= 0.0:
		_wave_time += delta
		if _wave_time >= WAVE_STARTUP + WAVE_ACTIVE:
			_wave_time = -1.0
	_tick_bolt(delta)
	_tick_item(input, delta)
	_apply_grapple_pull()

	_move()
	queue_redraw()


func _tick_timers(delta: float) -> void:
	_coyote_timer -= delta
	_jump_buffer_timer -= delta
	_drop_timer -= delta
	_dash_cooldown_timer -= delta
	_attack_cooldown_timer -= delta
	_attack_buffer_timer -= delta
	_heavy_buffer_timer -= delta
	_invincible_timer -= delta
	_knockback_timer -= delta
	_wall_jump_timer -= delta
	_lives_show_timer -= delta
	_shield_broken_timer -= delta
	_shield_flash_timer -= delta
	_stun_timer -= delta
	_ladder_regrab_timer -= delta
	_ladder_fling_timer -= delta
	_vine_regrab_timer -= delta
	_mecha_reboard_timer -= delta
	_item_cooldown -= delta
	_item_flash_timer -= delta
	_repair_flash_timer -= delta
	_ultimate_flash_timer -= delta
	_frozen_timer -= delta
	item_shield_timer -= delta
	_blink_clock += delta


## On court tant que LT / Shift est maintenu et qu'il reste de l'endurance.
## Courir vide la jauge (plus vite si on bloque en même temps) ; elle remonte quand on s'arrête.
func _update_sprint(input: InputState, delta: float) -> void:
	if stamina >= STAMINA_RESTART:
		_exhausted = false
	var moving := absf(input.stick.x) > 0.2
	_sprinting = input.sprint_held and not _exhausted and stamina > 0.0 and (moving or _blocking)
	if _sprinting:
		stamina -= stats.stamina_sprint_drain * (STAMINA_BLOCK_SPRINT_MULT if _blocking else 1.0) * delta
		_stamina_regen_timer = STAMINA_REGEN_DELAY
		if stamina <= 0.0:
			stamina = 0.0
			_exhausted = true
	else:
		_stamina_regen_timer -= delta
		if _stamina_regen_timer <= 0.0:
			stamina = minf(stamina + stats.stamina_regen * delta, stats.stamina_max)
	if stamina < stats.stamina_max:
		_stamina_show_timer = STAMINA_SHOW_TIME
	else:
		_stamina_show_timer -= delta


## On bloque tant que B est maintenu, si le bouclier n'est pas cassé et qu'on n'est pas
## en train de dasher ou de frapper. Le bouclier se répare lentement quand on ne bloque pas.
func _update_block(input: InputState, delta: float) -> void:
	_blocking = input.block_held and not shield_broken and not is_dashing() \
		and not _is_attack_startup_or_active()
	# Compté depuis l'appui sur B, même si on ne pouvait pas encore bloquer (pendant une attaque,
	# un dash...) : garder B appuyé pendant sa propre attaque ne donne pas un blocage parfait gratuit.
	_block_hold_time = _block_hold_time + delta if input.block_held else 0.0
	if _blocking or shield_broken or shield >= stats.shield_max:
		_shield_regen_timer = 0.0
		return
	_shield_regen_timer += delta
	if _shield_regen_timer >= SHIELD_REGEN_TIME:
		_shield_regen_timer = 0.0
		shield += 1


func _tick_movement(input: InputState, on_floor: bool, delta: float) -> void:
	# Gauche / droite
	var accel := (stats.ground_accel if on_floor else stats.air_accel) * _move_mult()
	if _knockback_timer > 0.0:
		accel = KNOCKBACK_ACCEL
	elif _wall_jump_timer > 0.0:
		accel = WALL_JUMP_ACCEL
	elif _ladder_fling_timer > 0.0:
		accel = 0.0  # éjecté de l'échelle : on garde son élan
	var speed := stats.run_speed * _move_mult()
	if _sprinting:
		speed *= stats.sprint_speed_mult
	if _blocking:
		speed *= BLOCK_SPEED_MULT
	elif _heavy_charging and heavy_kind() != WeaponStats.Heavy.BURST:
		speed *= stats.heavy_charge_move_mult  # (le nunchaku avance normalement en chargeant)
	velocity.x = move_toward(velocity.x, input.stick.x * speed, accel * delta)

	# Gravité (plus forte si on a lâché le saut pendant la montée d'un saut = petit saut).
	# Seulement pour un saut : un dash vers le haut ou une projection ne sont pas coupés.
	if velocity.y >= 0.0:
		_jump_rising = false
	var gravity := stats.gravity
	if velocity.y < 0.0 and _jump_rising and not input.jump_held:
		gravity = stats.short_hop_gravity
	velocity.y += gravity * delta
	var max_fall := stats.fast_fall_speed if (input.stick.y > 0.5 and not on_floor) else stats.max_fall_speed
	if is_wall_sliding():
		max_fall = stats.wall_slide_speed
	velocity.y = minf(velocity.y, max_fall)

	# Saut, double saut et saut mural
	if input.jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
	var jump_mult := (BLOCK_JUMP_MULT if _blocking else 1.0) * (BERSERK_JUMP if is_berserk() else 1.0)
	if _jump_buffer_timer > 0.0:
		if on_floor or _coyote_timer > 0.0:
			velocity.y = -stats.jump_speed * jump_mult
			_jump_rising = true
			_jump_buffer_timer = 0.0
			_coyote_timer = 0.0
		elif input.jump_pressed and is_wall_sliding() and _air_jumps_left > 0:
			velocity = Vector2(_wall_normal_x * stats.wall_jump_push, -stats.jump_speed * jump_mult)
			_jump_rising = true
			_air_jumps_left -= 1
			_jump_buffer_timer = 0.0
			_wall_jump_timer = WALL_JUMP_LOCK
		elif input.jump_pressed and _air_jumps_left > 0:
			velocity.y = -stats.double_jump_speed * jump_mult
			_jump_rising = true
			_air_jumps_left -= 1
			_jump_buffer_timer = 0.0


## On ramasse un objet (seulement si on n'en a pas déjà un).
## "ammo" : ce qu'il reste dans une arme à 2 mains jetée par un autre (-1 = neuve).
func take_item(kind: String, ammo := -1) -> bool:
	if item != "" or (mecha != null) != (kind == "missiles"):
		return false  # en mecha, on ne prend que les missiles (et eux, seulement en mecha)
	item = kind
	item_ammo = PISTOL_AMMO if kind == "pistolet" else 0
	if kind == "grappin":
		item_ammo = GRAPPLE_USES
	elif kind == "fusil":
		item_ammo = RIFLE_AMMO
	elif kind == "lance_roquette":
		item_ammo = 1
	if ammo >= 0 and kind in TWO_HANDED_ITEMS:
		item_ammo = ammo
	_item_flash_timer = ITEM_FLASH_TIME
	_item_flash_kind = kind
	return true


## RT : pistolet = une balle par appui ; grenade = dégoupillée à l'appui, lancée en lâchant
## (plus on garde, plus elle va loin) ; bouclier = levé pour quelques secondes ; vie = une vie en plus.
func _tick_item(input: InputState, delta: float) -> void:
	if grapple_mode != Grapple.NONE:
		_tick_grapple(input, delta)
		return
	if _grenade_fuse >= 0.0:
		_grenade_fuse -= delta
		_grenade_hold += delta
		if _grenade_fuse <= 0.0:
			_release_grenade(Vector2.ZERO, 0.0)  # gardée trop longtemps : elle explose en main
		elif not input.item_held:
			_release_grenade(_item_direction(), clampf(_grenade_hold / GRENADE_FULL_HOLD, 0.0, 1.0))
		return
	if _rifle_burst_left > 0:
		# Rafale en cours : les balles partent seules, l'une après l'autre.
		_rifle_gap_timer -= delta
		if _rifle_gap_timer <= 0.0:
			_fire_rifle_bullet()
		return
	if not input.item_pressed or _blocking or is_dashing():
		return
	match item:
		"pistolet":
			if _item_cooldown <= 0.0:
				_item_cooldown = PISTOL_COOLDOWN
				item_ammo -= 1
				if item_ammo <= 0:
					item = ""
				item_used.emit(self, "balle", _item_direction(), 1.0, 0.0)
		"grenade":
			_grenade_fuse = GRENADE_FUSE
			_grenade_hold = 0.0
		"bouclier":
			item = ""
			item_shield_timer = ITEM_SHIELD_TIME
		"grappin":
			if target != null and not target.eliminated:
				item_ammo -= 1
				grapple_mode = Grapple.FLYING
				grapple_point = global_position
				_grapple_target = target
				_grapple_target_lives = target.lives
				_grapple_tap = false
				_grapple_time = 0.0
				_grapple_dist = 0.0
		"fusil":
			if _item_cooldown <= 0.0:
				_item_cooldown = RIFLE_COOLDOWN
				_rifle_burst_left = mini(RIFLE_BURST, item_ammo)
				_fire_rifle_bullet()
		"lance_roquette":
			if _item_cooldown <= 0.0:
				item = ""
				item_ammo = 0
				item_used.emit(self, "roquette", _item_direction(), LAUNCHER_BLAST, 0.0)
		"balise":
			item = ""
			item_used.emit(self, "balise", Vector2.ZERO, 0.0, 0.0)  # game.gd appelle le mecha
		"vie":
			if lives < MAX_LIVES:
				item = ""
				lives += 1
				_item_flash_timer = ITEM_FLASH_TIME
				_item_flash_kind = "vie"
				show_lives()


func _fire_rifle_bullet() -> void:
	_rifle_burst_left -= 1
	_rifle_gap_timer = RIFLE_GAP
	item_ammo -= 1
	if item_ammo <= 0:
		item = ""  # chargeur vide : le fusil disparaît, on retrouve son arme
		_rifle_burst_left = 0
	item_used.emit(self, "balle", _item_direction(), RIFLE_BULLET_SPEED, 0.0)


## Une arme à 2 mains (fusil d'assaut, lance-roquette) : plus d'attaque X / Y tant qu'on la tient.
func has_two_handed_item() -> bool:
	return item in TWO_HANDED_ITEMS


## Grappin (RT) : le crochet file vers l'adversaire le plus proche. S'il l'accroche :
##   RT déjà lâché (une petite pression) : la corde NOUS tire vers lui ; un 2e appui la lâche.
##   RT encore gardé : la corde LE tire vers nous ; lâcher RT la décroche.
## Corde lâchée en route, celui qui était tiré garde son élan (il est « jeté »). Les deux peuvent
## frapper et bloquer pendant ce temps ; seul un blocage parfait à l'arrivée du crochet le contre.
func _tick_grapple(input: InputState, delta: float) -> void:
	var other := _grapple_target
	if other == null or other.eliminated or other.lives != _grapple_target_lives:
		_end_grapple(false)
		return
	_grapple_time += delta
	match grapple_mode:
		Grapple.FLYING:
			if not input.item_held:
				_grapple_tap = true
			var next := grapple_point + (other.global_position - grapple_point).limit_length(GRAPPLE_SPEED * delta)
			var wall := get_world_2d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters2D.create(grapple_point, next, 1))
			if not wall.is_empty():
				_end_grapple(false)  # un mur entre les deux : le crochet ne passe pas
				return
			_grapple_dist += grapple_point.distance_to(next)
			grapple_point = next
			if other.body_rect().grow(8.0).has_point(grapple_point):
				if other.is_parrying():
					_end_grapple(false)
					grapple_parried.emit(self, other)
					return
				_grapple_time = 0.0
				if _grapple_tap:
					grapple_mode = Grapple.PULL_SELF
					_leave_ladder()
					_leave_vine()
				else:
					grapple_mode = Grapple.PULL_THEM
					other.grappled_by(self)
			elif _grapple_dist > GRAPPLE_RANGE:
				_end_grapple(false)
		Grapple.PULL_SELF:
			grapple_point = other.global_position
			if input.item_pressed:
				_end_grapple(true)  # 2e appui : on lâche la corde, on garde son élan
				return
			var to := other.global_position - global_position
			if to.length() < GRAPPLE_ARRIVE or _grapple_time > GRAPPLE_MAX_TIME:
				velocity *= GRAPPLE_ARRIVE_KEEP
				_end_grapple(false)
				return
			velocity = to.normalized() * GRAPPLE_PULL
			_jump_rising = false
		Grapple.PULL_THEM:
			grapple_point = other.global_position
			if not input.item_held:
				_end_grapple(true)  # RT lâché : la corde se décroche, il part sur son élan
				return
			if global_position.distance_to(other.global_position) < GRAPPLE_ARRIVE or _grapple_time > GRAPPLE_MAX_TIME:
				other.velocity *= GRAPPLE_ARRIVE_KEEP
				_end_grapple(false)


## La corde se décroche. "fling" : lâchée en route, celui qui était tiré garde tout son élan.
func _end_grapple(fling: bool) -> void:
	if fling:
		var pulled := self if grapple_mode == Grapple.PULL_SELF else _grapple_target
		if pulled != null:
			pulled._ladder_fling_timer = GRAPPLE_FLING_TIME
	grapple_mode = Grapple.NONE
	_grapple_target = null
	if item == "grappin" and item_ammo <= 0:
		item = ""


## La corde d'un autre nous a accroché : il nous tire vers lui (voir _apply_grapple_pull).
func grappled_by(puller: Fighter) -> void:
	_grappled_by = puller
	_leave_ladder()
	_leave_vine()


func is_grappled() -> bool:
	return _grappled_by != null and _grappled_by.grapple_mode == Grapple.PULL_THEM and _grappled_by._grapple_target == self


func _apply_grapple_pull() -> void:
	if not is_grappled():
		_grappled_by = null
		return
	var to := _grappled_by.global_position - global_position
	if to.length() > 1.0:
		velocity = to.normalized() * GRAPPLE_PULL
		_jump_rising = false


func _release_grenade(direction: Vector2, power: float) -> void:
	var fuse := maxf(_grenade_fuse, 0.0)
	item = ""
	_grenade_fuse = -1.0
	item_used.emit(self, "grenade", direction, power, fuse)


## Vers l'adversaire visé (comme les attaques), ou devant soi.
func _item_direction() -> Vector2:
	if target != null and not target.eliminated:
		var to_target := target.global_position - global_position
		if to_target.length() > 1.0:
			return to_target.normalized()
	return Vector2(facing, 0.0)


func is_item_shielded() -> bool:
	return item_shield_timer > 0.0


## Le mecha vide (posé) que le corps touche, ou null.
func _touched_mecha() -> Mecha:
	for node in get_tree().get_nodes_in_group("mechas"):
		var candidate := node as Mecha
		if candidate != null and candidate.pilot == null and candidate.is_ready() and candidate.body_rect().intersects(body_rect()):
			return candidate
	return null


## On monte dans le mecha : on lâche tout (attaque, bouclier, échelle, liane, grappin, grenade dégoupillée).
func _board(new_mecha: Mecha) -> void:
	_cancel_attack()
	_leave_ladder()
	_leave_vine()
	if grapple_mode != Grapple.NONE:
		_end_grapple(false)
	if _grenade_fuse >= 0.0:
		_release_grenade(Vector2.ZERO, 0.0)
	_dash_timer = 0.0
	_blocking = false
	_sprinting = false
	_knockback_timer = 0.0
	mecha = new_mecha
	mecha.board(self)
	set_collision_mask_value(1, false)  # dans le cockpit, on ne touche plus le décor
	set_collision_mask_value(PLATFORM_LAYER, false)
	global_position = mecha.cockpit()
	velocity = Vector2.ZERO


## Aux commandes : le mecha suit nos touches, on reste dans le cockpit. Bas + A gardés : on sort.
func _tick_mecha(input: InputState, delta: float) -> void:
	mecha.tick(input, delta)
	facing = mecha.facing
	global_position = mecha.cockpit()
	velocity = mecha.velocity
	if mecha.wants_exit():
		leave_mecha()
		velocity = Vector2(0.0, -MECHA_EXIT_LIFT)
	queue_redraw()


## On sort du mecha (il reste là, vide) : on réapparaît juste au-dessus de lui.
func leave_mecha() -> void:
	if mecha == null:
		return
	var top := mecha.body_rect().position.y
	mecha.leave()
	mecha = null
	if item == "missiles":
		item = ""  # les missiles ne se tirent qu'en mecha : gardés à pied, ils bloqueraient les autres objets
	_mecha_reboard_timer = MECHA_REBOARD_TIME
	global_position = Vector2(global_position.x, top - stats.body_size.y / 2.0 - 4.0)
	velocity = Vector2.ZERO
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	if not eliminated:
		set_collision_mask_value(1, true)
		set_collision_mask_value(PLATFORM_LAYER, true)
	queue_redraw()


func is_piloting() -> bool:
	return mecha != null


## Notre mecha a explosé (game.gd nous a déjà sortis) : éjectés vers le haut et sonnés, comme un
## premier coup, mais sans perdre de vie (même si on l'était déjà). Invincibles juste après.
func eject_from_mecha() -> void:
	_cancel_attack()
	velocity = Vector2(0.0, -MECHA_EJECT_SPEED)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME
	_stun_timer = STUN_TIME
	_invincible_timer = INVINCIBLE_TIME


## L'échelle que le corps touche, ou null.
func _touched_ladder() -> Ladder:
	for node in get_tree().get_nodes_in_group("echelles"):
		var ladder := node as Ladder
		if ladder != null and ladder.rect().intersects(body_rect()):
			return ladder
	return null


## Sur l'échelle : on est collé au milieu et on monte. En haut, on est éjecté.
func _tick_ladder(input: InputState) -> void:
	if input.jump_pressed:
		_leave_ladder()
		velocity = Vector2(input.stick.x * stats.run_speed * _move_mult(), -stats.jump_speed)
		_jump_rising = true
		return
	if input.down_pressed:
		_leave_ladder()
		velocity = Vector2.ZERO
		return
	global_position.x = _ladder.global_position.x
	velocity = Vector2(0.0, -LADDER_CLIMB_SPEED * _move_mult())
	if global_position.y + stats.body_size.y / 2.0 <= _ladder.top():
		var push := _ladder.exit_push
		_leave_ladder()
		velocity = push
		_jump_rising = false
		_ladder_fling_timer = LADDER_FLING_TIME


func _leave_ladder() -> void:
	_ladder = null
	_ladder_regrab_timer = LADDER_REGRAB_TIME


func is_climbing() -> bool:
	return _ladder != null


## La liane que le corps touche (en pendant droit), ou null.
func _touched_vine() -> Vine:
	var reach := stats.body_size.x / 2.0 + VINE_GRAB_MARGIN
	for node in get_tree().get_nodes_in_group("lianes"):
		var vine := node as Vine
		if vine == null:
			continue
		var anchor := vine.global_position
		if global_position.y < anchor.y + VINE_MIN_LENGTH:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(global_position, anchor, vine.bottom())
		if global_position.distance_to(closest) <= reach:
			return vine
	return null


## On attrape la liane : la longueur du balancier = là où on l'a attrapée ; on garde son élan.
func _grab_vine(vine: Vine) -> void:
	_vine = vine
	_swinging = true
	_swing_anchor = vine.global_position
	var offset := global_position - _swing_anchor
	_swing_length = clampf(offset.length(), VINE_MIN_LENGTH, vine.length)
	_swing_angle = clampf(atan2(offset.x, offset.y), -VINE_MAX_ANGLE, VINE_MAX_ANGLE)
	var tangent := Vector2(cos(_swing_angle), -sin(_swing_angle))
	_swing_speed = velocity.dot(tangent) / _swing_length
	_cancel_attack()
	_dash_timer = 0.0
	_jump_rising = false
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	_dash_cooldown_timer = 0.0


## Sur la liane : un pendule. Gauche / droite donne de l'élan ; saut = on lâche en gardant l'élan
## (plus un petit saut) ; bas = on se laisse tomber. En touchant le sol, on lâche.
func _tick_vine(input: InputState, delta: float) -> void:
	var tangent := Vector2(cos(_swing_angle), -sin(_swing_angle))
	if input.jump_pressed:
		var push := tangent * _swing_speed * _swing_length
		_leave_vine()
		velocity = Vector2(push.x, minf(push.y, 0.0) - stats.double_jump_speed * VINE_JUMP_BOOST)
		_ladder_fling_timer = VINE_FLING_TIME
		return
	if input.down_pressed:
		velocity = tangent * _swing_speed * _swing_length
		_leave_vine()
		_ladder_fling_timer = VINE_FLING_TIME
		return
	var accel := -stats.gravity * sin(_swing_angle) + input.stick.x * VINE_PUMP * _move_mult()
	_swing_speed += accel / _swing_length * delta
	_swing_speed *= maxf(1.0 - VINE_DAMPING * delta, 0.0)
	var max_speed := VINE_MAX_SPEED * _move_mult() / _swing_length
	_swing_speed = clampf(_swing_speed, -max_speed, max_speed)
	_swing_angle += _swing_speed * delta
	if absf(_swing_angle) > VINE_MAX_ANGLE:
		_swing_angle = clampf(_swing_angle, -VINE_MAX_ANGLE, VINE_MAX_ANGLE)
		_swing_speed = 0.0
	var target := _swing_anchor + Vector2(sin(_swing_angle), cos(_swing_angle)) * _swing_length
	velocity = (target - global_position) / maxf(delta, 0.0001)
	_move()
	if is_on_floor():
		_leave_vine()  # on s'est posé : on lâche
	elif get_slide_collision_count() > 0:
		# Cogné un mur ou le plafond : on reste à l'endroit atteint, le balancement repart dans l'autre sens.
		var offset := global_position - _swing_anchor
		_swing_angle = atan2(offset.x, offset.y)
		_swing_speed *= -0.3


## Avance (move_and_slide). Une fenêtre percutée assez vite casse, et on passe au travers.
## Tomber dessus par le haut ne la casse pas.
func _move() -> void:
	var before := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var window := collision.get_collider() as BreakableWindow
		if window == null:
			continue
		var normal := collision.get_normal()
		if normal.y < -0.5:
			continue
		if -before.dot(normal) >= WINDOW_BREAK_SPEED and window.smash():
			velocity = before * WINDOW_BREAK_KEEP


func _leave_vine() -> void:
	if _vine == null:
		return
	_vine = null
	_swinging = false
	_vine_regrab_timer = VINE_REGRAB_TIME


func is_swinging() -> bool:
	return _swinging


## Pour la liane : est-ce qu'on se balance à elle ? (marche aussi chez les copains en ligne)
func is_swinging_on(vine: Vine) -> bool:
	return _swinging and _swing_anchor.is_equal_approx(vine.global_position)


func _try_start_dash(input: InputState, on_floor: bool) -> void:
	if is_dashing() or _dash_cooldown_timer > 0.0:
		return
	if _is_attack_startup_or_active():
		return
	if not on_floor and _air_dashes_left <= 0:
		return
	var dir := input.stick
	if dir.length() < 0.3:
		dir = Vector2(facing, 0.0)
	_dash_dir = dir.normalized()
	if not on_floor:
		_air_dashes_left -= 1
	_dash_timer = stats.dash_time
	_dash_cooldown_timer = stats.dash_cooldown
	_jump_rising = false
	_cancel_attack()


func _tick_dash(delta: float) -> void:
	velocity = _dash_dir * stats.dash_speed * _move_mult()
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		velocity *= DASH_END_KEEP


func _try_start_attack(heavy: bool) -> void:
	if not can_attack():
		return
	if heavy and heavy_kind() == WeaponStats.Heavy.SHOOT and arrows <= 0:
		return  # arc vide : il faut ramasser ses flèches
	_aim_at_target()
	if not heavy and _aimed_dir != Vector2.ZERO:
		_aim_towards(_aimed_dir)  # coup visé au stick droit
	_aimed_dir = Vector2.ZERO
	if not heavy:
		_swing_up = not _swing_up  # nunchaku : vers le bas, puis vers le haut, et ainsi de suite
	_attack_heavy = heavy
	_attack_time = 0.0
	_attack_has_hit = false
	_heavy_charging = heavy
	_charge_time = 0.0
	_heavy_charge = 0.0
	_attack_cooldown_timer = _cooldown(heavy)


## X + Y : la jauge d'ultime est pleine et on n'est pas occupé. On peut la lancer pendant qu'un coup
## léger se prépare ou qu'une lourde se charge (X puis Y, ou Y puis X, un peu décalés) : ce coup est annulé.
func can_use_ultimate() -> bool:
	return is_ultimate_ready() and not eliminated and not has_two_handed_item() and not is_dashing() and not is_invincible() \
		and not _blocking and not is_stunned() and not is_ultimate_under_way() \
		and (_heavy_charging or (not _attack_heavy and is_attacking() and _attack_time < stats.light_startup()) \
			or (not is_attacking() and _attack_cooldown_timer <= 0.0))  # privé d'attaque (contré...) : pas d'ultime non plus


func is_ultimate_ready() -> bool:
	return ultimate_points >= ULTIMATE_POINTS


## On vient de contrer : la jauge d'ultime monte (contrer une lourde compte double).
func add_ultimate_points(countered_heavy: bool) -> void:
	ultimate_points = mini(ultimate_points + (ULTIMATE_HEAVY_POINTS if countered_heavy else 1), ULTIMATE_POINTS)


func _use_ultimate() -> void:
	_cancel_attack()
	_attack_buffer_timer = 0.0
	_heavy_buffer_timer = 0.0
	ultimate_points = 0
	_ultimate_flash_timer = ULTIMATE_FLASH_TIME
	if stats.ultimate == "laser":
		_laser_time = 0.0
		laser_frozen.clear()
		_aim_laser()
	elif stats.ultimate == "onde":
		_wave_time = 0.0
		wave_hit.clear()
	elif stats.ultimate == "eclair":
		_bolt_time = 0.0
		_bolt_pass = -1
	ultimate_used.emit(self)


## Barre : le laser vise l'adversaire pendant qu'il se prépare, puis part tout droit.
func _tick_laser(delta: float) -> void:
	if _laser_time < 0.0:
		return
	var was_startup := _laser_time < LASER_STARTUP
	_laser_time += delta
	if was_startup:
		_aim_laser()
	if _laser_time >= LASER_STARTUP + LASER_ACTIVE:
		_laser_time = -1.0


func _aim_laser() -> void:
	if target != null and not target.eliminated and target.global_position.distance_to(global_position) > 1.0:
		_laser_dir = (target.global_position - global_position).normalized()
	else:
		_laser_dir = Vector2(facing, 0.0)
	if absf(_laser_dir.x) > 0.1:
		facing = signf(_laser_dir.x)
	# Le rayon s'arrête au premier mur (ou sol) qu'il rencontre.
	_laser_length = LASER_RANGE
	if is_inside_tree():
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + _laser_dir * LASER_RANGE, 1)
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_laser_length = global_position.distance_to(hit.position)


func is_lasering() -> bool:
	return _laser_time >= 0.0


## Le laser peut-il geler en ce moment ? Il touche tout ce qu'il y a entre ces deux points.
func is_laser_active() -> bool:
	return _laser_time >= LASER_STARTUP


## Jib : au début de chaque traversée, il vise l'adversaire et prend la vitesse qu'il faut pour
## ressortir de l'autre côté (BOLT_OVERSHOOT).
func _tick_bolt(delta: float) -> void:
	if _bolt_time < 0.0:
		return
	_bolt_time += delta
	var t := _bolt_time - BOLT_STARTUP
	if t >= BOLT_PASSES * (BOLT_PASS_TIME + BOLT_GAP):
		_bolt_time = -1.0
		velocity *= 0.2
		return
	if t < 0.0:
		return
	var index := int(t / (BOLT_PASS_TIME + BOLT_GAP))
	if index != _bolt_pass:
		_bolt_pass = index
		bolt_hit.clear()
		var distance := 0.0
		if target != null and not target.eliminated and target.global_position.distance_to(global_position) > 1.0:
			_bolt_dir = (target.global_position - global_position).normalized()
			distance = target.global_position.distance_to(global_position)
		else:
			_bolt_dir = Vector2(facing, 0.0)
		_bolt_speed = clampf((distance + BOLT_OVERSHOOT) / BOLT_PASS_TIME, BOLT_SPEED_MIN, BOLT_SPEED_MAX)
		if absf(_bolt_dir.x) > 0.1:
			facing = signf(_bolt_dir.x)


func is_bolting() -> bool:
	return _bolt_time >= 0.0


## Jib est en train de foncer (pas pendant la préparation ni les petits arrêts).
func is_bolt_passing() -> bool:
	var t := _bolt_time - BOLT_STARTUP
	return _bolt_time >= 0.0 and t >= 0.0 and fmod(t, BOLT_PASS_TIME + BOLT_GAP) < BOLT_PASS_TIME


func is_ultimate_under_way() -> bool:
	return is_lasering() or is_waving() or is_bolting()


func is_waving() -> bool:
	return _wave_time >= 0.0


## Jumb : rayon actuel du cercle de l'onde de choc (0 = elle ne frappe pas encore).
func wave_radius() -> float:
	if _wave_time < WAVE_STARTUP:
		return 0.0
	return lerpf(WAVE_START_RADIUS, WAVE_RADIUS, clampf((_wave_time - WAVE_STARTUP) / WAVE_ACTIVE, 0.0, 1.0))


func laser_end() -> Vector2:
	return global_position + _laser_dir * _laser_length


## Touché par le laser de la Barre : gelé (ni bouger, ni attaquer, ni bloquer) pendant FREEZE_TIME.
## Comme quand on est sonné, le coup suivant fait perdre une vie.
func freeze() -> void:
	_cancel_attack()
	if _grenade_fuse >= 0.0:
		_release_grenade(Vector2.ZERO, 0.0)
	_leave_ladder()
	_leave_vine()
	if grapple_mode != Grapple.NONE:
		_end_grapple(false)
	_dash_timer = 0.0
	velocity = Vector2(0.0, maxf(velocity.y, 0.0))
	_frozen_timer = FREEZE_TIME
	_stun_timer = maxf(_stun_timer, FREEZE_TIME)
	_invincible_timer = STUN_GRACE


func is_frozen() -> bool:
	return _frozen_timer > 0.0


## Recharge d'une attaque (comptée depuis son départ) : plus courte quand la jauge de contre est haute.
func _cooldown(heavy: bool) -> float:
	return stats.cooldown(heavy) * PHASE_COOLDOWN[counter_phase() - 1]


## Se tourne vers l'adversaire visé.
func _aim_at_target() -> void:
	if target != null and not target.eliminated:
		var to_target := target.global_position - global_position
		_aim_towards(to_target.normalized() if to_target.length() > 1.0 else Vector2(facing, 0.0))
	else:
		_aim_towards(Vector2(facing, 0.0))


## Oriente l'attaque dans une direction (et le perso du même côté).
func _aim_towards(dir: Vector2) -> void:
	_attack_dir = dir
	if absf(_attack_dir.x) > 0.1:
		facing = signf(_attack_dir.x)


func _tick_attack(input: InputState, delta: float) -> void:
	if _attack_time < 0.0:
		return
	if _heavy_charging:
		# On charge tant que Y est gardé ; on frappe en le lâchant, ou quand la charge est pleine.
		_charge_time += delta * _attack_speed()
		_heavy_charge = clampf((_charge_time - stats.heavy_startup) / maxf(stats.heavy_charge_time - stats.heavy_startup, 0.001), 0.0, 1.0)
		if (_charge_time >= stats.heavy_startup and not input.heavy_held) or _charge_time >= stats.heavy_charge_time:
			_heavy_charging = false
			_aim_at_target()  # l'adversaire a pu bouger pendant la charge
			_attack_time = stats.heavy_startup
			_attack_cooldown_timer = _cooldown(true)
			velocity = Vector2.ZERO  # la frappe commence : on s'arrête net
			_burst_index = 0
			_swing_up = not _swing_up  # nunchaku : 1er coup de la rafale (vers le bas, puis haut, puis bas)
			if heavy_kind() == WeaponStats.Heavy.THROW:
				_throw_weapon()
			elif heavy_kind() == WeaponStats.Heavy.SHOOT:
				_shoot_arrow()
		return
	_attack_time += delta * _attack_speed()
	if _attack_heavy and heavy_kind() == WeaponStats.Heavy.BURST and _attack_time >= stats.heavy_startup:
		# Rafale du nunchaku : chaque coup peut toucher, vise à nouveau et change de sens.
		var index := mini(int((_attack_time - stats.heavy_startup) / BURST_HIT_TIME), BURST_HITS - 1)
		if index != _burst_index:
			_burst_index = index
			_attack_has_hit = false
			_swing_up = not _swing_up
			_aim_at_target()
	if _attack_time >= _attack_startup() + _attack_active():
		if is_katana_dashing():
			velocity *= KATANA_DASH_END_KEEP
		_attack_time = -1.0


## Lance : elle part vers l'adversaire, et on continue à mains nues jusqu'à la ramasser.
func _throw_weapon() -> void:
	var speed := weapon.heavy_speed * lerpf(1.0, THROW_CHARGE_SPEED, _heavy_charge)
	_cancel_attack()
	weapon_away = true
	weapon_thrown.emit(self, _attack_dir, speed)


## Arc : la flèche part vers l'adversaire ; on garde l'arc.
func _shoot_arrow() -> void:
	var speed := weapon.heavy_speed * lerpf(1.0, ARROW_CHARGE_SPEED, _heavy_charge)
	var knockback := attack_knockback()
	_cancel_attack()
	arrows -= 1
	arrow_shot.emit(self, _attack_dir, speed, knockback)


## On ramasse sa lance. Arme cassée : on reste à mains nues.
func get_weapon_back() -> void:
	weapon_away = is_weapon_broken()


## RB : on lance l'arme qu'on a en main (pas pendant une attaque). Elle ne fait mal à personne ;
## game.gd la fait voler vers l'adversaire le plus proche.
func _toss_weapon() -> void:
	if has_two_handed_item():
		# RB jette d'abord l'arme à 2 mains (avec ce qu'il reste dedans) : on retrouve son arme.
		var kind := item
		var ammo := item_ammo
		item = ""
		item_ammo = 0
		_rifle_burst_left = 0
		item_tossed.emit(self, kind, ammo)
		return
	if is_attacking() or not knock_weapon_away():
		return
	weapon_tossed.emit(self)


## Une arme en main ? (pas à mains nues, pas lancée, pas cassée)
func has_weapon_in_hand() -> bool:
	return not weapon.is_bare_hands() and not weapon_away


## On ramasse une arme (la sienne ou celle d'un autre), usée de "counters" contres.
## Arc : il garde ses flèches ("ammo") et son numéro ("id") en changeant de main.
func equip(new_weapon: WeaponStats, counters: int, ammo := ARROWS_MAX, id := 0) -> void:
	weapon = new_weapon
	weapon_counters = counters
	arrows = ammo
	bow_id = id
	_repair_counters = 0
	_update_armed_stats()
	weapon_away = false
	stats = _armed_stats
	_repair_flash_timer = WEAPON_REPAIR_FLASH  # un anneau de sa couleur : on voit qu'on l'a prise


## Le perso avec son arme en main ; une arme contrée est plus petite (coup léger et lourde).
func _update_armed_stats() -> void:
	_armed_stats = weapon.apply_to(_bare_stats)
	_armed_stats.attack_reach *= weapon_length()
	_armed_stats.heavy_arc_radius *= weapon_length()
	_armed_stats.heavy_tip_radius *= weapon_length()


## Taille de l'arme : 1 = neuve ; chaque contre de sa lourde la rapetisse.
func weapon_length() -> float:
	return 1.0 - WEAPON_SHRINK * mini(weapon_counters, WEAPON_MAX_COUNTERS - 1)


## La lourde de notre arme a été contrée : l'arme rapetisse, ou casse au WEAPON_MAX_COUNTERS-ième
## contre (mains nues : il faut trouver une autre arme). Renvoie true si elle vient de casser.
## À mains nues (ou lance lancée et pas en main) : rien ne s'use.
func weapon_countered() -> bool:
	if not has_weapon_in_hand():
		return false
	weapon_counters += 1
	if not is_weapon_broken():
		return false
	weapon_away = true
	return true


## On a contré avec le coup léger de son arme : tous les WEAPON_REPAIR_COUNTERS contres, une arme
## usée regagne un cran (80 % -> 100 %, 60 % -> 80 %). Une arme neuve ne garde pas de contres
## d'avance ; une arme cassée ne se répare pas. Renvoie true si l'arme vient d'être réparée.
func weapon_light_counter() -> bool:
	if weapon.is_bare_hands() or weapon_away or weapon_counters <= 0:
		return false
	_repair_counters += 1
	if _repair_counters < WEAPON_REPAIR_COUNTERS:
		return false
	_repair_counters = 0
	weapon_counters -= 1
	_repair_flash_timer = WEAPON_REPAIR_FLASH
	return true


## Blocage parfait : l'arme en main nous saute des mains (game.gd la fait voler). On se bat à
## mains nues jusqu'à la ramasser en passant dessus. Renvoie false s'il n'y avait rien en main.
func knock_weapon_away() -> bool:
	if weapon.is_bare_hands() or weapon_away:
		return false
	weapon_away = true
	return true


func is_weapon_broken() -> bool:
	return weapon_counters >= WEAPON_MAX_COUNTERS


## Un contre : la recharge des attaques (légère et lourde) repart de zéro.
func reset_cooldown() -> void:
	_attack_cooldown_timer = 0.0


## Ce que fait l'attaque lourde avec l'arme en main (l'arc habituel à mains nues).
func heavy_kind() -> WeaponStats.Heavy:
	return WeaponStats.Heavy.SWING if weapon_away else weapon.heavy


## Katana : en plein dash tranchant (on traverse l'adversaire, on ne peut pas être touché).
func is_katana_dashing() -> bool:
	return heavy_kind() == WeaponStats.Heavy.DASH and is_heavy_swinging() \
		and _attack_time < stats.heavy_startup + stats.heavy_active


## Marteau : l'onde de choc au sol, juste après l'arc (seulement si on est au sol).
func _is_slam_wave() -> bool:
	return heavy_kind() == WeaponStats.Heavy.SLAM and is_heavy_swinging() \
		and _attack_time >= stats.heavy_startup + stats.heavy_active


func _attack_startup() -> float:
	return stats.heavy_startup if _attack_heavy else stats.light_startup()


func _attack_active() -> float:
	if _attack_heavy and heavy_kind() == WeaponStats.Heavy.SLAM:
		return stats.heavy_active + SLAM_WAVE_TIME
	if _attack_heavy and heavy_kind() == WeaponStats.Heavy.BURST:
		return BURST_HITS * BURST_HIT_TIME
	return stats.heavy_active if _attack_heavy else stats.attack_active


## Angle actuel de l'arme pendant l'attaque lourde (en radians, côté "facing").
func _heavy_angle() -> float:
	var progress := clampf((_attack_time - stats.heavy_startup) / maxf(stats.heavy_active, 0.001), 0.0, 1.0)
	return deg_to_rad(lerpf(HEAVY_ARC_START, HEAVY_ARC_END, progress))


## Position du bout de l'arme (par rapport au centre du perso) pour un angle donné.
func _heavy_tip(angle: float) -> Vector2:
	return Vector2(facing * cos(angle), sin(angle)) * stats.heavy_arc_radius * heavy_scale() * _range_mult()


## Taille de l'arme lourde : 1 sans charge, HEAVY_CHARGE_GROWTH à pleine charge.
func heavy_scale() -> float:
	return lerpf(1.0, HEAVY_CHARGE_GROWTH, _heavy_charge)


func _cancel_attack() -> void:
	_attack_time = -1.0
	_heavy_charging = false
	_laser_time = -1.0
	_wave_time = -1.0
	_bolt_time = -1.0


# --- Questions que game.gd pose au combattant ---

func is_dashing() -> bool:
	return _dash_timer > 0.0


func is_wall_sliding() -> bool:
	return _wall_normal_x != 0.0


func is_invincible() -> bool:
	return _invincible_timer > 0.0


func is_attacking() -> bool:
	return _attack_time >= 0.0


func is_charging_heavy() -> bool:
	return _heavy_charging


## En train de donner le coup lourd (après la charge) : le perso est immobilisé.
func is_heavy_swinging() -> bool:
	return _attack_heavy and _attack_time >= 0.0 and not _heavy_charging


func _is_attack_startup_or_active() -> bool:
	return _attack_time >= 0.0 and (_heavy_charging or _attack_time < _attack_startup() + _attack_active())


func is_sprinting() -> bool:
	return _sprinting


func is_blocking() -> bool:
	return _blocking


## Blocage parfait : on vient tout juste de commencer à bloquer.
func is_parrying() -> bool:
	return _blocking and _block_hold_time <= PARRY_WINDOW


## Une attaque légère lancée qui n'a encore touché personne (en préparation ou en train de frapper).
## Se faire toucher à ce moment-là par celui qu'elle vise, c'est le contrer (voir game.gd).
func is_light_attack_under_way() -> bool:
	return not _attack_heavy and _attack_time >= 0.0 and not _attack_has_hit \
		and _attack_time < stats.light_startup() + stats.attack_active


## Temps restant avant de pouvoir attaquer à nouveau.
func attack_cooldown_left() -> float:
	return maxf(_attack_cooldown_timer, 0.0)


func can_attack() -> bool:
	return not eliminated and not has_two_handed_item() and not is_dashing() and not is_invincible() and not _blocking \
		and not is_attacking() and not is_ultimate_under_way() and _attack_cooldown_timer <= 0.0


## Le coup peut-il toucher en ce moment ?
func is_attack_active() -> bool:
	return not _heavy_charging and _attack_time >= _attack_startup() and _attack_time < _attack_startup() + _attack_active() \
		and not _attack_has_hit and not (_is_slam_wave() and not is_on_floor())


## Depuis combien de temps le coup peut toucher (pour le renvoi de balle au bon moment).
func attack_time_since_active() -> float:
	return _attack_time - _attack_startup()


func attack_active_duration() -> float:
	return _attack_active()


func is_heavy_attack() -> bool:
	return _attack_heavy


## La zone qui touche est un segment épais (de attack_start() à attack_center(), d'épaisseur attack_radius()).
## Attaque légère : toute la barre, du centre du perso jusqu'au bout, comme un coup de poing ou
## d'épée, donc on touche aussi un adversaire tout proche. Le segment commence une épaisseur devant
## le centre : la zone s'arrête pile au centre du perso et ne déborde pas dans son dos.
## Attaque lourde : seulement le bout de l'arme.
func attack_start() -> Vector2:
	if _is_slam_wave():
		return _feet() - Vector2(_slam_wave_reach(), 0.0)
	if is_katana_dashing():
		return global_position
	if _is_burst():
		return global_position + _hit_dir() * stats.attack_radius
	if _attack_heavy:
		return attack_center()
	return global_position + _hit_dir() * clampf(_light_reach() - stats.attack_radius, 0.0, stats.attack_radius)


## Le bout de la zone qui touche.
func attack_center() -> Vector2:
	if _is_slam_wave():
		return _feet() + Vector2(_slam_wave_reach(), 0.0)
	if is_katana_dashing():
		return global_position + _attack_dir * stats.heavy_arc_radius * KATANA_DASH_REACH * _range_mult()
	if _is_burst():
		return global_position + _hit_dir() * maxf(_burst_reach() - stats.attack_radius, 0.0)
	if _attack_heavy:
		return global_position + _heavy_tip(_heavy_angle())
	return global_position + _hit_dir() * maxf(_light_reach() - stats.attack_radius, 0.0)


## Nunchaku : en pleine rafale (après la charge).
func _is_burst() -> bool:
	return heavy_kind() == WeaponStats.Heavy.BURST and is_heavy_swinging()


## Longueur des coups de la rafale : plus on a chargé, plus ils vont loin.
func _burst_reach() -> float:
	return stats.attack_reach * _range_mult() * lerpf(1.0, BURST_CHARGE_REACH, _heavy_charge)


## Le nunchaku en main : ses coups alternent vers le bas et vers le haut.
func _swings() -> bool:
	return not weapon_away and weapon.light_swing


## Direction du coup : vers l'adversaire, penchée vers le bas ou le haut pour le nunchaku.
func _hit_dir() -> Vector2:
	if not _swings():
		return _attack_dir
	var side := signf(_attack_dir.x) if absf(_attack_dir.x) > 0.01 else facing
	return _attack_dir.rotated(deg_to_rad(SWING_TILT) * side * (-1.0 if _swing_up else 1.0))


## Le sens dans lequel notre coup projette celui qu'il touche ("toward" : de nous vers lui).
## Nunchaku : vers le bas ou vers le haut, selon le sens du coup.
func hit_push_direction(toward: Vector2) -> Vector2:
	if _swings():
		var side := signf(toward.x) if absf(toward.x) > 0.01 else facing
		return Vector2(side * SWING_PUSH_SIDE, -1.0 if _swing_up else 1.0).normalized()
	return toward if _attack_heavy else _attack_dir


## Longueur actuelle du coup léger : la barre sort du perso et s'allonge pendant LIGHT_DEPLOY_TIME.
func _light_reach() -> float:
	var deploy := clampf((_attack_time - stats.light_startup()) / LIGHT_DEPLOY_TIME, 0.0, 1.0)
	return stats.attack_reach * _range_mult() * lerpf(LIGHT_DEPLOY_START, 1.0, deploy)


func _feet() -> Vector2:
	return global_position + Vector2(0.0, stats.body_size.y / 2.0 - SLAM_WAVE_RADIUS)


## Marteau : la moitié de la longueur de l'onde de choc (elle grandit pendant qu'elle part).
func _slam_wave_reach() -> float:
	var progress := clampf((_attack_time - stats.heavy_startup - stats.heavy_active) / SLAM_WAVE_TIME, 0.0, 1.0)
	return SLAM_WAVE_REACH * lerpf(1.0, 1.6, _heavy_charge) * _range_mult() * lerpf(0.4, 1.0, progress)


func attack_radius() -> float:
	if _is_slam_wave():
		return SLAM_WAVE_RADIUS
	if _is_burst():
		return stats.attack_radius
	return stats.heavy_tip_radius * lerpf(1.0, HEAVY_CHARGE_TIP_GROWTH, _heavy_charge) if _attack_heavy else stats.attack_radius


func attack_knockback() -> float:
	return stats.heavy_knockback * lerpf(1.0, HEAVY_CHARGE_KNOCKBACK, _heavy_charge) if _attack_heavy else stats.hit_knockback


func attack_direction() -> Vector2:
	return _attack_dir


## Peut-on se faire toucher ? Non pendant un dash (aussi celui du katana) ou une invincibilité.
## Le dash du katana peut quand même être contré (voir game.gd).
func can_be_hit() -> bool:
	return not eliminated and mecha == null and not is_dashing() and not is_katana_dashing() and not is_invincible()


## En train d'esquiver (dash, dash du katana) : ce qui vole (balle, lance) passe au travers.
func is_dodging() -> bool:
	return is_dashing() or is_katana_dashing() or mecha != null


func body_rect() -> Rect2:
	return Rect2(global_position - stats.body_size / 2.0, stats.body_size)


# --- Événements déclenchés par game.gd ---

func mark_attack_hit() -> void:
	_attack_has_hit = true


## Un contre : notre attaque est annulée (s'il y en avait une), on est repoussé par "push"
## (game.gd la calcule : plus l'autre est lourd, plus elle est forte) et on ne peut plus
## attaquer pendant "cooldown".
func clash(push: Vector2, cooldown := CLASH_LOCKOUT, lift := 150.0) -> void:
	_cancel_attack()
	_leave_ladder()
	_leave_vine()
	_attack_cooldown_timer = cooldown
	velocity = _pushed(push) + Vector2(0.0, -lift)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME


## Notre coup a frappé un bouclier : il s'arrête, on est repoussé, mais on peut refrapper tout de suite.
func hit_shield(push_dir: Vector2) -> void:
	_cancel_attack()
	_leave_ladder()
	_leave_vine()
	_attack_cooldown_timer = 0.0
	velocity = _pushed(push_dir * SHIELD_HIT_PUSH) + Vector2(0.0, -120.0)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME


## Points de bouclier que nos coups font perdre : plus quand notre jauge de contre est haute.
func shield_damage(heavy: bool) -> int:
	var damage := HEAVY_SHIELD_DAMAGE * (1 if weapon_away else weapon.heavy_shield_damage) if heavy else 1
	return damage * PHASE_SHIELD_DAMAGE[counter_phase() - 1]


## Notre bouclier encaisse un coup (il craque de "damage" points). Renvoie true s'il vient de casser.
func absorb_hit(push_dir: Vector2, damage: int) -> bool:
	shield = maxi(shield - damage, 0)
	_shield_regen_timer = 0.0
	_shield_flash_timer = 0.12
	velocity.x = _pushed(push_dir * SHIELD_BLOCKER_PUSH).x
	if shield > 0:
		return false
	# Bouclier cassé pour le reste de la partie.
	shield_broken = true
	_blocking = false
	return true


## Un bouclier vient de casser : on est éjecté. Celui dont le bouclier a cassé ne peut plus
## attaquer pendant SHIELD_BREAK_COOLDOWN (mais peut bouger).
func shield_burst(push_dir: Vector2, own_shield_broke: bool) -> void:
	_cancel_attack()
	_leave_ladder()
	_leave_vine()
	velocity = _pushed(push_dir * SHIELD_BREAK_PUSH) + Vector2(0.0, -SHIELD_BREAK_LIFT)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME
	if own_shield_broke:
		_attack_cooldown_timer = SHIELD_BREAK_COOLDOWN
		_shield_broken_timer = SHIELD_BREAK_COOLDOWN
	else:
		_attack_cooldown_timer = 0.0


## Un coup reçu. Pas encore sonné : on est sonné, sans perdre de vie. Déjà sonné : on perd une vie.
## Renvoie true si une vie est perdue.
## knockback = force du coup reçu (-1 = celle d'une attaque légère). Plus on est lourd, moins on recule.
func take_hit(hit_dir: Vector2, knockback := -1.0) -> bool:
	if knockback < 0.0:
		knockback = stats.hit_knockback
	_cancel_attack()
	_frozen_timer = 0.0  # gelé puis frappé : on perd une vie (voir plus bas) et on n'est plus gelé
	if _grenade_fuse >= 0.0:
		_release_grenade(Vector2.ZERO, 0.0)  # touché : la grenade dégoupillée tombe des mains
	_leave_ladder()
	_leave_vine()
	_dash_timer = 0.0
	velocity = _pushed(hit_dir * knockback) + Vector2(0.0, -200.0)
	_jump_rising = false
	_knockback_timer = KNOCKBACK_TIME
	if is_stunned():
		_lose_life()
		return true
	_stun_timer = STUN_TIME
	_invincible_timer = STUN_GRACE
	return false


func is_stunned() -> bool:
	return _stun_timer > 0.0


## On a contré (ou fait un blocage parfait) : on n'est plus sonné.
func recover() -> void:
	_stun_timer = 0.0
	_frozen_timer = 0.0


## Phase de la jauge de contre de la partie : de 1 (normale) à 4 (berserk).
func counter_phase() -> int:
	return gauge.phase()


func is_berserk() -> bool:
	return gauge.is_berserk()


func _move_mult() -> float:
	return BERSERK_MOVE if is_berserk() else 1.0


func _attack_speed() -> float:
	return BERSERK_ATTACK_SPEED if is_berserk() else 1.0


func _range_mult() -> float:
	return BERSERK_RANGE if is_berserk() else 1.0


## Toutes les poussées reçues (coups, chocs, bouclier) passent par ici : plus le perso est lourd,
## moins il est repoussé (poids 2 = 2 fois moins loin).
func _pushed(force: Vector2) -> Vector2:
	return force / maxf(stats.mass(), 0.1)  # jamais de division par zéro, même avec un réglage bizarre


## Sorti de la map : on perd une vie et on réapparaît au milieu.
func fall_out(respawn_position: Vector2) -> void:
	if mecha != null:
		var lost := mecha
		leave_mecha()
		lost.queue_free()  # tombé avec son mecha : le mecha est perdu
	_cancel_attack()
	_leave_ladder()
	_leave_vine()
	_dash_timer = 0.0
	global_position = respawn_position
	velocity = Vector2.ZERO
	_air_jumps_left = stats.air_jumps
	_air_dashes_left = stats.air_dashes
	# On repart à neuf : plus de recul ni de saut en cours venant d'avant la chute.
	_knockback_timer = 0.0
	_wall_jump_timer = 0.0
	_ladder_fling_timer = 0.0
	if grapple_mode != Grapple.NONE:
		_end_grapple(false)
	if _grenade_fuse >= 0.0:
		item = ""  # tombé avec une grenade dégoupillée : elle est perdue
		_grenade_fuse = -1.0
	_drop_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_rising = false
	_lose_life()


func _lose_life() -> void:
	lives -= 1
	_stun_timer = 0.0
	_frozen_timer = 0.0
	_invincible_timer = INVINCIBLE_TIME
	show_lives()
	if lives <= 0:
		_leave_vine()
		eliminated = true
		visible = false
		set_collision_mask_value(1, false)
		set_collision_mask_value(PLATFORM_LAYER, false)
		velocity = Vector2.ZERO
	life_lost.emit(self)


func show_lives() -> void:
	_lives_show_timer = LIVES_SHOW_TIME
	queue_redraw()


## Jeu en ligne : le joueur a quitté la partie, il est éliminé.
func forfeit() -> void:
	if eliminated:
		return
	lives = 1
	_lose_life()


## Jeu en ligne (hôte) : l'état de ce joueur à envoyer aux copains.
func net_state() -> Array:
	var state := []
	for v in NET_VARS:
		state.append(get(v))
	return state


## Jeu en ligne (copain) : on affiche le joueur tel que l'hôte l'a envoyé.
func apply_net_state(state: Array) -> void:
	for i in mini(state.size(), NET_VARS.size()):
		set(NET_VARS[i], state[i])
	queue_redraw()


# --- Dessin (pas d'images : tout est dessiné avec des rectangles) ---

func _draw() -> void:
	if eliminated or mecha != null:  # aux commandes d'un mecha : on se voit dans son cockpit
		return
	var body := Rect2(-stats.body_size / 2.0, stats.body_size)

	# Traînée pendant le dash
	if is_dashing():
		for i in 3:
			var ghost := body
			ghost.position -= _dash_dir * 18.0 * (i + 1)
			draw_rect(ghost, Color(color, 0.25 - i * 0.07))

	# Berserk : des images rouges traînent derrière le perso quand il bouge
	var phase := counter_phase()
	if phase == 4 and not is_dashing() and velocity.length() > 150.0:
		for i in 3:
			var ghost := body
			ghost.position -= velocity * 0.022 * (i + 1)
			draw_rect(ghost, Color(gauge.color(), 0.22 - i * 0.06))

	# Clignote quand on est invincible
	var body_color := color
	if is_invincible() and int(_blink_clock / 0.06) % 2 == 0:
		body_color = Color(color, 0.25)
	if is_dashing():
		body_color = body_color.lightened(0.4)
	draw_rect(body, body_color)

	# Jauge de contre en phase 2 et plus : un contour de la couleur de la phase (rouge qui pulse en berserk)
	if phase >= 2:
		var phase_color := gauge.color()
		var pulse := 0.5 + 0.5 * sin(_blink_clock * 14.0) if phase == 4 else 0.0
		draw_rect(body.grow(3.0 + 2.0 * pulse), Color(phase_color, 0.55 + 0.35 * pulse), false, 1.5 + phase * 0.5)
	if gauge.flash_timer > 0.0:
		var t := 1.0 - gauge.flash_timer / CounterGauge.FLASH_TIME
		var ring := lerpf(stats.body_size.y * 0.5, stats.body_size.y * 1.3, t)
		draw_arc(Vector2.ZERO, ring, 0.0, TAU, 32, Color(gauge.color(), 1.0 - t), 4.0)

	# Au-dessus de la tête, empilés sans se chevaucher (du bas vers le haut) : les étoiles quand on
	# est sonné, la croix du bouclier cassé, puis les vies.
	var head_y := -stats.body_size.y / 2.0 - 4.0

	# Sonné : des étoiles tournent au-dessus de la tête
	if is_stunned():
		var fade := clampf(_stun_timer / 0.3, 0.0, 1.0)
		var ring_y := head_y - 12.0
		head_y -= 24.0
		for i in 3:
			var angle := _blink_clock * 6.0 + i * TAU / 3.0
			var star := Vector2(cos(angle) * 18.0, ring_y + sin(angle) * 4.0)
			var star_color := Color(1.0, 0.9, 0.3, fade * (0.6 + 0.4 * (sin(angle) * 0.5 + 0.5)))
			draw_line(star + Vector2(-6, 0), star + Vector2(6, 0), star_color, 3.0)
			draw_line(star + Vector2(0, -6), star + Vector2(0, 6), star_color, 3.0)

	# En surbrillance quand on bloque : plus le bouclier a pris de coups, plus il est fissuré et terne.
	# Sonné, le bouclier ne protège plus : il ne s'allume que le temps d'un blocage parfait.
	if _blocking and (not is_stunned() or is_parrying()):
		var damage := 1.0 - float(shield) / stats.shield_max
		var glow := (1.0 if _shield_flash_timer > 0.0 else 0.8) * lerpf(1.0, 0.6, damage)
		draw_rect(body.grow(12.0), Color(color.lightened(0.5), 0.12 * glow))
		draw_rect(body.grow(7.0), Color(color.lightened(0.6), 0.25 * glow))
		draw_rect(body, Color(1, 1, 1, 0.35 * glow))
		draw_rect(body.grow(7.0), Color(1, 1, 1, glow), false, 3.0)
		for i in mini(stats.shield_max - shield, _cracks.size()):
			draw_polyline(_cracks[i], Color(0.1, 0.1, 0.15, 0.9), 2.0)
	elif _shield_flash_timer > 0.0:
		draw_rect(body.grow(5.0), Color(1, 1, 1, 0.8), false, 3.0)

	# Bouclier cassé : une croix grise tant qu'on ne peut pas attaquer
	if _shield_broken_timer > 0.0:
		var a := clampf(_shield_broken_timer / 0.3, 0.0, 1.0) * 0.8
		var c := Vector2(0, head_y - 9.0)
		head_y -= 18.0
		draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), Color(0.75, 0.75, 0.8, a), 3.0)
		draw_line(c + Vector2(-7, 7), c + Vector2(7, -7), Color(0.75, 0.75, 0.8, a), 3.0)

	# Petit œil pour voir de quel côté on regarde
	draw_rect(Rect2(Vector2(facing * 3.0 - 2.5, -stats.body_size.y / 2.0 + 9.0), Vector2(5, 5)), Color(0.08, 0.09, 0.13))

	var weapon_color := Color(1, 1, 1) if weapon_away else weapon.color

	# Katana : le dash tranchant, la lame pointée devant soi
	if is_katana_dashing():
		var blade_tip := attack_center() - global_position
		for i in 3:
			var ghost := body
			ghost.position -= _attack_dir * 18.0 * (i + 1)
			draw_rect(ghost, Color(color, 0.25 - i * 0.07))
		draw_line(Vector2.ZERO, blade_tip, Color(weapon_color, 0.95), 5.0)
		draw_line(-blade_tip * 0.6, blade_tip, Color(weapon_color, 0.3), 12.0)

	# Marteau : l'onde de choc au sol, des deux côtés
	elif _is_slam_wave():
		if is_on_floor():
			var reach := _slam_wave_reach()
			var feet := _feet() - global_position
			var fade := 1.0 - clampf((_attack_time - stats.heavy_startup - stats.heavy_active) / SLAM_WAVE_TIME, 0.0, 1.0)
			draw_rect(Rect2(feet + Vector2(-reach, -SLAM_WAVE_RADIUS), Vector2(reach * 2.0, SLAM_WAVE_RADIUS * 2.0)),
				Color(weapon_color, 0.25 + 0.5 * fade))
			draw_rect(Rect2(feet + Vector2(-reach, SLAM_WAVE_RADIUS - 3.0), Vector2(reach * 2.0, 3.0)), Color(1, 1, 1, 0.8 * fade))

	# Nunchaku et arc : pendant la charge, un trait vers l'adversaire qui s'allonge avec la charge ;
	# puis la rafale du nunchaku (une barre de sa couleur, vers le bas puis vers le haut).
	elif is_attacking() and _attack_heavy and heavy_kind() in [WeaponStats.Heavy.BURST, WeaponStats.Heavy.SHOOT]:
		if _heavy_charging:
			var aim := _attack_dir if target == null else (target.global_position - global_position).normalized()
			var reach := (_burst_reach() if heavy_kind() == WeaponStats.Heavy.BURST else 60.0 + 80.0 * _heavy_charge)
			draw_line(aim * 12.0, aim * reach, Color(weapon_color, lerpf(0.3, 0.8, _heavy_charge)), 3.0)
			if _heavy_charge >= 1.0 and int(_blink_clock / 0.05) % 2 == 0:
				draw_circle(aim * reach, 6.0, Color(1, 1, 1, 0.9))
		else:
			var dir := _hit_dir()
			var reach := _burst_reach()
			draw_line(dir * 10.0, dir * reach, Color(weapon_color, 0.95), stats.attack_radius * 0.6)
			draw_circle(dir * reach, stats.attack_radius * 0.6, color.lightened(0.6))

	# L'attaque lourde : l'arme levée au-dessus de la tête, puis un arc jusqu'aux pieds
	elif is_attacking() and _attack_heavy:
		var angle := _heavy_angle()
		if _attack_time >= stats.heavy_startup:
			var trail := PackedVector2Array()
			var start := deg_to_rad(HEAVY_ARC_START)
			for i in 9:
				trail.append(_heavy_tip(lerpf(start, angle, i / 8.0)))
			draw_polyline(trail, Color(color.lightened(0.5), 0.5), 10.0)
		var tip := _heavy_tip(angle)
		var weapon_scale := heavy_scale()
		var blade_color := Color(weapon_color, 0.95)
		if _heavy_charging:
			blade_color = Color(weapon_color, lerpf(0.55, 0.9, _heavy_charge))
			# La charge : un halo qui grossit au bout de l'arme, qui clignote quand c'est plein
			var halo := attack_radius()
			var full_blink := _heavy_charge >= 1.0 or (_heavy_charge > 0.95 and int(_blink_clock / 0.05) % 2 == 0)
			draw_circle(tip, halo, Color(color.lightened(0.5), 0.15 + 0.25 * _heavy_charge))
			if full_blink:
				draw_arc(tip, halo, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
		var blade := stats.heavy_tip_radius * 0.375 * sqrt(weapon_scale)  # 9 px pour la Barre
		draw_line(tip * 0.2, tip, blade_color, blade)
		draw_circle(tip, blade, color.lightened(0.6))

	# L'attaque légère : une barre blanche orientée vers l'adversaire
	# (sa longueur et son épaisseur suivent la zone qui touche, pour chaque perso)
	elif is_attacking():
		draw_set_transform(Vector2.ZERO, _hit_dir().angle())
		var length := stats.attack_reach * _range_mult()
		var bar := stats.attack_radius * 0.5625   # 9 px pour la Barre
		var tip := stats.attack_radius * 0.875    # 14 px pour la Barre
		if _attack_time < stats.light_startup():
			# On arme le coup : le poing recule derrière le perso, et une fine ligne montre où il va partir
			var windup := clampf(_attack_time / stats.light_startup(), 0.0, 1.0)
			draw_rect(Rect2(10.0, -1.5, length - 10.0, 3.0), Color(1, 1, 1, 0.12 + 0.2 * windup))
			var back := lerpf(2.0, 14.0, windup)
			draw_rect(Rect2(-back - tip, -tip * 0.8, tip, tip * 1.6), Color(color.lightened(0.6), 0.6 + 0.4 * windup))
		else:
			# Le coup part : la barre jaillit du perso et s'allonge jusqu'au bout
			var reach := _light_reach()
			draw_rect(Rect2(10.0, -bar, maxf(reach - 10.0, 0.0), bar * 2.0), Color(weapon_color, 0.95))
			draw_rect(Rect2(reach - tip, -tip, tip, tip * 2.0), color.lightened(0.6))
			if reach < length:
				draw_rect(Rect2(reach, -1.5, length - reach, 3.0), Color(1, 1, 1, 0.25))
		draw_set_transform(Vector2.ZERO, 0.0)

	# L'arme dans la main quand on n'attaque pas (dessin très simple, à remplacer par un graphiste)
	elif not weapon_away and weapon.held_length > 0.0:
		var hand := Vector2(facing * stats.body_size.x / 2.0, 4.0)
		var end := hand + Vector2(facing * 0.4, -1.0).normalized() * weapon.held_length * weapon_length()
		draw_line(hand, end, weapon_color, 3.0)
		if weapon.held_head > 0.0:
			var head := weapon.held_head * weapon_length()
			draw_rect(Rect2(end - Vector2.ONE * head / 2.0, Vector2.ONE * head), weapon_color)
		if weapon.heavy == WeaponStats.Heavy.SHOOT:
			# Les flèches qui restent : des petits traits à côté de l'arc
			for i in arrows:
				var x := hand.x - facing * (6.0 + i * 4.0)
				draw_line(Vector2(x, -6.0), Vector2(x, -18.0), Color(weapon_color, 0.9), 2.0)

	_draw_item(body)
	_draw_ultimate(body)

	# La jauge d'endurance, sur le côté opposé à l'adversaire
	if _stamina_show_timer > 0.0:
		_draw_stamina_gauge()

	# Les vies au-dessus de la tête (au-dessus des étoiles et de la croix s'il y en a)
	if _lives_show_timer > 0.0:
		var alpha := clampf(_lives_show_timer / 0.4, 0.0, 1.0)
		var size := 10.0
		var gap := 5.0
		var pips := maxi(max_lives, lives)  # les vies en plus (objet « vie ») s'ajoutent à droite
		var total := pips * size + (pips - 1) * gap
		var y := head_y - 18.0
		for i in pips:
			var pip := Rect2(-total / 2.0 + i * (size + gap), y, size, size)
			if i < lives:
				draw_rect(pip, Color(color, alpha))
			else:
				draw_rect(pip, Color(1, 1, 1, 0.5 * alpha), false, 2.0)


## L'objet ramassé (dessin très simple, à remplacer par un graphiste) : pistolet et ses balles,
## grenade (qui clignote de plus en plus vite une fois dégoupillée), bouclier levé devant soi,
## vie en plus (un petit carré rose dans la main), grappin (et sa corde quand il est lancé).
func _draw_item(body: Rect2) -> void:
	if is_item_shielded():
		var fade := clampf(item_shield_timer / 0.5, 0.0, 1.0)
		var plate := Rect2(Vector2(facing * (body.size.x / 2.0 + 6.0) - 5.0, -body.size.y / 2.0 - 6.0), Vector2(10.0, body.size.y + 12.0))
		draw_rect(plate, Color(ItemPickup.color_of("bouclier"), 0.85 * fade))
		draw_rect(plate.grow(2.0), Color(1, 1, 1, 0.6 * fade), false, 2.0)
	if _item_flash_timer > 0.0:
		# Un objet vient d'être ramassé : un anneau de sa couleur, pour qu'on le remarque.
		var t := 1.0 - _item_flash_timer / ITEM_FLASH_TIME
		draw_arc(Vector2.ZERO, lerpf(body.size.y * 0.4, body.size.y * 1.1, t), 0.0, TAU, 32,
			Color(ItemPickup.color_of(_item_flash_kind), 1.0 - t), 3.0)
	if _repair_flash_timer > 0.0:
		# L'arme vient d'être réparée : un anneau de sa couleur.
		var t := 1.0 - _repair_flash_timer / WEAPON_REPAIR_FLASH
		draw_arc(Vector2.ZERO, lerpf(body.size.y * 0.4, body.size.y * 1.1, t), 0.0, TAU, 32,
			Color(weapon.color, 1.0 - t), 3.0)
	var hand := Vector2(facing * (body.size.x / 2.0 + 6.0), 6.0)
	if grapple_mode != Grapple.NONE:
		# La corde, de la main jusqu'au crochet.
		var hook := to_local(grapple_point)
		draw_line(hand, hook, Color(ItemPickup.color_of("grappin"), 0.9), 2.0)
		draw_rect(Rect2(hook - Vector2.ONE * 4.0, Vector2.ONE * 8.0), ItemPickup.color_of("grappin"))
	match item:
		"grappin":
			if grapple_mode == Grapple.NONE:
				draw_rect(Rect2(hand - Vector2.ONE * 4.0, Vector2.ONE * 8.0), ItemPickup.color_of("grappin"))
			for i in item_ammo:
				draw_circle(hand + Vector2(-6.0 + i * 6.0, -10.0), 1.8, ItemPickup.color_of("grappin"))
		"vie":
			draw_rect(Rect2(hand - Vector2.ONE * 6.0, Vector2.ONE * 12.0), ItemPickup.color_of("vie"))
		"balise":
			var beacon := ItemPickup.color_of("balise") if int(_blink_clock / 0.25) % 2 == 0 else Color(1, 1, 1)
			draw_colored_polygon(PackedVector2Array([hand + Vector2(0, -8), hand + Vector2(6, 0), hand + Vector2(0, 8), hand + Vector2(-6, 0)]), beacon)
		"pistolet":
			# Le pistolet pointe là où la balle partira ; les balles qui restent sont des points sur le canon.
			var aim := _item_direction()
			var side := signf(aim.x) if absf(aim.x) > 0.01 else facing
			draw_set_transform(Vector2(side * body.size.x / 2.0, 2.0), aim.angle(), Vector2(1.0, side))
			var gun_color := ItemPickup.color_of("pistolet")
			draw_rect(Rect2(2.0, -3.0, 18.0, 6.0), gun_color)   # le canon
			draw_rect(Rect2(2.0, 3.0, 6.0, 7.0), gun_color)     # la poignée
			for i in item_ammo:
				draw_circle(Vector2(5.0 + i * 3.5, -5.5), 1.5, Color(1.0, 0.9, 0.5))
			draw_set_transform(Vector2.ZERO, 0.0)
		"fusil", "lance_roquette":
			# Tenu à 2 mains, pointé là où le tir partira. Fusil : les balles qui restent = une barre
			# sous le canon. Lance-roquette : un gros tube, la roquette dépasse devant.
			var aim2 := _item_direction()
			var side2 := signf(aim2.x) if absf(aim2.x) > 0.01 else facing
			draw_set_transform(Vector2(side2 * body.size.x * 0.2, 0.0), aim2.angle(), Vector2(1.0, side2))
			var two_color := ItemPickup.color_of(item)
			if item == "fusil":
				draw_rect(Rect2(-14.0, -4.0, 46.0, 8.0), two_color)    # le corps et le canon
				draw_rect(Rect2(-22.0, -3.0, 9.0, 9.0), two_color)     # la crosse
				draw_rect(Rect2(6.0, 4.0, 6.0, 9.0), two_color)        # le chargeur
				var left := float(item_ammo) / RIFLE_AMMO
				draw_rect(Rect2(-14.0, -8.0, 46.0 * left, 2.5), Color(1.0, 0.9, 0.5))
			else:
				draw_rect(Rect2(-24.0, -7.0, 52.0, 14.0), two_color)   # le tube sur l'épaule
				draw_rect(Rect2(2.0, 7.0, 6.0, 8.0), two_color)        # la poignée
				if item_ammo > 0:
					draw_colored_polygon(PackedVector2Array([Vector2(28, -5), Vector2(38, 0), Vector2(28, 5)]), color)
			draw_set_transform(Vector2.ZERO, 0.0)
		"grenade":
			var grenade_color := ItemPickup.color_of("grenade")
			if _grenade_fuse >= 0.0 and int(_blink_clock / lerpf(0.05, 0.25, _grenade_fuse / GRENADE_FUSE)) % 2 == 0:
				grenade_color = Color(1, 0.3, 0.2)
			draw_circle(hand, 7.0, grenade_color)
			if _grenade_fuse >= 0.0:
				# Plus RT est gardé, plus elle partira loin
				var power := clampf(_grenade_hold / GRENADE_FULL_HOLD, 0.0, 1.0)
				draw_arc(hand, 12.0, -PI / 2.0, -PI / 2.0 + TAU * power, 20, Color(1, 1, 1, 0.8), 2.0)


## Prépare les fissures du bouclier : chacune part du bord de la surbrillance vers le perso
## en zigzag. Elles sont tirées au hasard une fois pour toutes (toujours les mêmes pour un joueur).
func _make_cracks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + player_index
	var outline := Rect2(-stats.body_size / 2.0, stats.body_size).grow(7.0)
	var perimeter := 2.0 * (outline.size.x + outline.size.y)
	for i in stats.shield_max:
		# Un point sur le bord, réparti tout autour
		var d := fposmod((i * 0.618034 + rng.randf_range(-0.05, 0.05)) * perimeter, perimeter)
		var start: Vector2
		if d < outline.size.x:
			start = outline.position + Vector2(d, 0.0)
		elif d < outline.size.x + outline.size.y:
			start = outline.position + Vector2(outline.size.x, d - outline.size.x)
		elif d < 2.0 * outline.size.x + outline.size.y:
			start = outline.end - Vector2(d - outline.size.x - outline.size.y, 0.0)
		else:
			start = outline.position + Vector2(0.0, outline.size.y - (d - 2.0 * outline.size.x - outline.size.y))
		var crack := PackedVector2Array([start])
		var dir := (-start).normalized()
		var point := start
		for step in 3:
			dir = dir.rotated(rng.randf_range(-0.9, 0.9))
			point += dir * rng.randf_range(5.0, 10.0)
			crack.append(point)
		_cracks.append(crack)


## La jauge d'ultime : une aura de particules autour du perso, de sa couleur. Plus la jauge est
## remplie, plus il y en a. Pleine, elles sont plus grosses, blanches et tournent plus vite :
## X + Y pour lancer l'ultime. Lancée, une onde blanche part du perso.
## (Tout est calculé à partir de _blink_clock : les copains en ligne voient la même aura.)
func _draw_ultimate(body: Rect2) -> void:
	if ultimate_points > 0:
		var ratio := float(ultimate_points) / ULTIMATE_POINTS
		var ready := is_ultimate_ready()
		var count := ULTIMATE_PARTICLES if ready else maxi(2, int(ceil(ULTIMATE_PARTICLES * ratio * 0.7)))
		var speed := 1.8 if ready else 0.7
		for i in count:
			# Chaque particule monte le long du corps en tournant autour, puis recommence en bas.
			var phase := fposmod(_blink_clock * speed * 0.45 + i * 0.618034, 1.0)
			var angle := i * TAU / count + _blink_clock * speed
			var spread := body.size.x / 2.0 + (14.0 if ready else 10.0) + 6.0 * sin(i * 1.7)
			var pos := Vector2(cos(angle) * spread, body.end.y + 4.0 - phase * (body.size.y + 24.0))
			var size := (6.0 if ready else 4.0) * (1.0 - 0.45 * phase)
			var alpha := (1.0 if ready else 0.45 + 0.45 * ratio) * sin(phase * PI)
			var tint := Color(1, 1, 1).lerp(color.lightened(0.4), phase) if ready else color.lightened(0.45)
			draw_rect(Rect2(pos - Vector2.ONE * size / 2.0, Vector2.ONE * size), Color(tint, alpha))
	if _ultimate_flash_timer > 0.0:
		var t := 1.0 - _ultimate_flash_timer / ULTIMATE_FLASH_TIME
		draw_arc(Vector2.ZERO, lerpf(body.size.y * 0.5, body.size.y * 2.2, t), 0.0, TAU, 40, Color(1, 1, 1, 1.0 - t), 4.0)
	if is_lasering():
		# Barre : un fin trait bleu vers l'adversaire, puis le rayon bleu (épais, qui s'amincit).
		var end := _laser_dir * _laser_length
		if _laser_time < LASER_STARTUP:
			var t := _laser_time / LASER_STARTUP
			draw_line(Vector2.ZERO, end, Color(LASER_COLOR, 0.25 + 0.4 * t), 2.0)
			draw_circle(Vector2.ZERO, 6.0 + 8.0 * t, Color(LASER_COLOR, 0.8))
		else:
			var fade := 1.0 - (_laser_time - LASER_STARTUP) / LASER_ACTIVE
			draw_line(Vector2.ZERO, end, Color(LASER_COLOR, 0.5 * fade), LASER_RADIUS * 2.0 * (0.5 + 0.5 * fade) + 8.0)
			draw_line(Vector2.ZERO, end, Color(0.85, 0.95, 1.0, fade), LASER_RADIUS)
	if is_waving():
		# Jumb : un cercle qui se resserre autour de lui, puis s'ouvre d'un coup (l'onde de choc).
		if _wave_time < WAVE_STARTUP:
			var t := _wave_time / WAVE_STARTUP
			draw_arc(Vector2.ZERO, lerpf(WAVE_START_RADIUS * 2.0, WAVE_START_RADIUS, t), 0.0, TAU, 40, Color(WAVE_COLOR, 0.3 + 0.6 * t), 3.0)
		else:
			var fade := 1.0 - (_wave_time - WAVE_STARTUP) / WAVE_ACTIVE
			var radius := wave_radius()
			draw_circle(Vector2.ZERO, radius, Color(WAVE_COLOR, 0.18 * fade))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(WAVE_COLOR, 0.9 * fade), 10.0 * fade + 2.0)
	if is_bolting():
		# Jib : un éclair jaune autour de lui, puis des traînées jaunes à chaque traversée.
		if _bolt_time < BOLT_STARTUP:
			draw_rect(body.grow(4.0 + 6.0 * _bolt_time / BOLT_STARTUP), Color(BOLT_COLOR, 0.9), false, 3.0)
		elif is_bolt_passing():
			for i in 4:
				var ghost := body
				ghost.position -= _bolt_dir * 22.0 * (i + 1)
				draw_rect(ghost, Color(BOLT_COLOR, 0.5 - i * 0.11))
			draw_rect(body.grow(3.0), Color(BOLT_COLOR, 0.95), false, 2.0)
	if is_frozen():
		# Gelé : un bloc de glace bleu par-dessus le perso.
		var ice := body.grow(5.0)
		draw_rect(ice, Color(LASER_COLOR, 0.45))
		draw_rect(ice, Color(0.85, 0.95, 1.0, 0.9), false, 2.0)


## Barre verticale à côté du perso, du côté où n'est pas l'adversaire (pour ne pas gêner le combat).
func _draw_stamina_gauge() -> void:
	var side := -facing
	if target != null and not target.eliminated and absf(target.global_position.x - global_position.x) > 1.0:
		side = -signf(target.global_position.x - global_position.x)
	var alpha := clampf(_stamina_show_timer / 0.3, 0.0, 1.0)
	var height := stats.body_size.y
	var x := side * (stats.body_size.x / 2.0 + 9.0) - 3.0
	var frame := Rect2(x, -height / 2.0, 6.0, height)
	draw_rect(frame, Color(0, 0, 0, 0.5 * alpha))
	var ratio := stamina / stats.stamina_max
	var fill_color := Color(0.4, 0.95, 0.5).lerp(Color(1.0, 0.85, 0.3), 1.0 - ratio)
	if _exhausted:
		fill_color = Color(0.6, 0.6, 0.65)
	var fill_h := height * ratio
	draw_rect(Rect2(x, height / 2.0 - fill_h, 6.0, fill_h), Color(fill_color, alpha))
	draw_rect(frame, Color(1, 1, 1, 0.4 * alpha), false, 1.0)
