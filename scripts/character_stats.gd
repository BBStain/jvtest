class_name CharacterStats
extends Resource
## Les caractéristiques d'un personnage : vitesse, sauts, dash, attaques, poids...
##
## Chaque personnage est un fichier .tres dans le dossier characters/ (ex. characters/barre.tres).
## Pour créer un perso : duplique characters/barre.tres, ouvre-le dans Godot, change ses chiffres
## dans l'inspecteur, puis ajoute-le dans CHARACTERS de scripts/game_setup.gd.
## Les valeurs ci-dessous sont celles par défaut (celles de la Barre).

@export var display_name := "Barre"
@export var description := ""


@export_group("Corps")
@export var body_size: Vector2 = Vector2(20, 60)  ## largeur, hauteur de la barre (en pixels)

@export_group("Déplacement")
@export var run_speed: float = 560.0  ## vitesse de course max
@export var ground_accel: float = 8500.0  ## à quelle vitesse on atteint la vitesse max au sol
@export var air_accel: float = 5500.0  ## pareil, en l'air
@export var gravity: float = 2300.0
@export var short_hop_gravity: float = 4800.0  ## gravité quand on lâche le saut tôt (petit saut)
@export var max_fall_speed: float = 1050.0
@export var fast_fall_speed: float = 1700.0  ## chute rapide en tenant bas
@export var jump_speed: float = 820.0
@export var double_jump_speed: float = 760.0
@export var air_jumps: int = 1  ## 1 = double saut

@export_group("Murs")
@export var wall_slide_speed: float = 160.0  ## vitesse de glissade le long d'un mur (en tenant vers le mur)
@export var wall_jumps: int = 2  ## sauts rendus quand on touche un mur (saut mural + 1 en l'air)
@export var wall_jump_push: float = 480.0  ## force qui éjecte du mur quand on saute

@export_group("Dash")
@export var dash_speed: float = 1300.0
@export var dash_time: float = 0.14
@export var dash_cooldown: float = 0.32  ## temps de recharge
@export var air_dashes: int = 1  ## dashs possibles en l'air avant de retoucher le sol

@export_group("Attaque légère")
@export var attack_startup: float = 0.02  ## délai avant que le coup touche
@export var attack_active: float = 0.08  ## durée pendant laquelle le coup peut toucher
@export var attack_cooldown: float = 0.13  ## temps de recharge entre deux attaques (à peine plus que le coup)
@export var attack_reach: float = 72.0  ## distance entre le centre du perso et le centre du coup
@export var attack_radius: float = 28.0  ## taille de la zone qui touche
@export var hit_knockback: float = 700.0  ## un coup léger repousse d'environ 100 px

@export_group("Attaque lourde")
@export var heavy_startup: float = 0.14  ## charge minimale : on lève l'arme avant de frapper
@export var heavy_active: float = 0.15  ## durée du balayage
@export var heavy_cooldown: float = 0.5
@export var heavy_arc_radius: float = 56.0  ## distance entre le centre du perso et le bout de l'arme
@export var heavy_tip_radius: float = 24.0  ## taille de la zone qui touche au bout de l'arme
@export var heavy_knockback: float = 940.0
@export var heavy_charge_move_mult: float = 0.6  ## en chargeant, on avance lentement

@export_group("Blocage")
@export var shield_max: int = 3  ## points de bouclier

@export_group("Course")
@export var sprint_speed_mult: float = 1.5  ## en courant on va 1,5 fois plus vite (et on saute plus loin)
@export var stamina_max: float = 100.0
@export var stamina_sprint_drain: float = 30.0  ## endurance perdue par seconde en courant
@export var stamina_regen: float = 25.0  ## endurance regagnée par seconde sans courir

@export_group("Poids")
@export var weight: float = 1.0  ## plus lourd = repoussé moins loin par les coups (2 = 2 fois moins loin)
