class_name CharacterStats
extends Resource
## Les caractéristiques d'un personnage : vitesse, sauts, dash, attaques, poids...
##
## Chaque personnage est un fichier .tres dans le dossier characters/ (ex. characters/barre.tres).
## Pour créer un perso : duplique characters/barre.tres, ouvre-le dans Godot, change ses chiffres
## dans l'inspecteur, puis ajoute-le dans CHARACTERS de scripts/game_setup.gd.
## Les valeurs ci-dessous sont celles par défaut (celles de la Barre).
##
## Le poids est calculé tout seul à partir de la taille (sauf si on le règle à la main) :
## un perso qui prend plus de place est plus lourd. Plus on est lourd, moins on recule, plus
## on repousse loin un adversaire plus léger quand on se contre, et plus on attaque lentement
## (le coup léger s'arme plus longtemps, les recharges sont plus longues). Le reste (vitesse,
## sauts...) se règle à la main, pour garder chaque perso bien à lui.

const BASE_SIZE := Vector2(20, 60)  ## la taille de la Barre : poids 1
const WEIGHT_TEMPO := 0.5  ## 1,4 fois plus lourd que la Barre = attaques 1,2 fois plus lentes (0,8 fois = 0,9 fois)

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
@export var attack_startup: float = 0.1  ## on arme le coup avant qu'il parte : le temps de le voir venir et de le contrer
@export var attack_active: float = 0.12  ## durée pendant laquelle le coup peut toucher (la barre se déploie au début)
@export var attack_cooldown: float = 0.4  ## temps de recharge entre deux attaques, compté depuis le départ du coup
@export var attack_reach: float = 84.0  ## longueur du coup : du centre du perso jusqu'au bout de la barre
@export var attack_radius: float = 16.0  ## demi-épaisseur de la zone qui touche (toute la barre touche)
@export var hit_knockback: float = 700.0  ## un coup léger repousse d'environ 100 px

@export_group("Attaque lourde")
@export var heavy_startup: float = 0.14  ## charge minimale : on lève l'arme avant de frapper
@export var heavy_active: float = 0.15  ## durée du balayage
@export var heavy_cooldown: float = 0.8  ## temps de recharge après la frappe
@export var heavy_arc_radius: float = 56.0  ## distance entre le centre du perso et le bout de l'arme
@export var heavy_tip_radius: float = 24.0  ## taille de la zone qui touche au bout de l'arme
@export var heavy_knockback: float = 940.0
@export var heavy_charge_move_mult: float = 0.6  ## en chargeant, on avance lentement
@export var heavy_charge_time: float = 1.0  ## temps pour arriver à la charge pleine (on frappe alors tout seul)

@export_group("Blocage")
@export var shield_max: int = 20  ## nombre de coups que le bouclier encaisse avant de casser

@export_group("Course")
@export var sprint_speed_mult: float = 1.5  ## en courant on va 1,5 fois plus vite (et on saute plus loin)
@export var stamina_max: float = 100.0
@export var stamina_sprint_drain: float = 30.0  ## endurance perdue par seconde en courant
@export var stamina_regen: float = 25.0  ## endurance regagnée par seconde sans courir

@export_group("Poids")
@export var weight: float = 0.0  ## 0 = calculé selon la taille ; sinon le poids voulu (2 = 2 fois moins repoussé)
@export var attack_tempo: float = 0.0  ## 0 = calculé selon le poids ; sinon la lenteur voulue des attaques (1,2 = 20 % plus lent)


## Le poids du perso : celui réglé à la main, ou sinon calculé selon sa taille
## (2 fois plus de surface que la Barre = environ 1,4 fois plus lourd).
func mass() -> float:
	if weight > 0.0:
		return weight
	return sqrt((body_size.x * body_size.y) / (BASE_SIZE.x * BASE_SIZE.y))


## La lenteur des attaques : 1 pour la Barre, plus pour un perso lourd, moins pour un léger.
## Elle multiplie l'armement du coup léger et la recharge des deux attaques.
func tempo() -> float:
	if attack_tempo > 0.0:
		return attack_tempo
	return 1.0 + WEIGHT_TEMPO * (mass() - 1.0)


## Temps pour armer le coup léger, selon le poids.
func light_startup() -> float:
	return attack_startup * tempo()


## Recharge d'une attaque (légère ou lourde), selon le poids.
func cooldown(heavy: bool) -> float:
	return (heavy_cooldown if heavy else attack_cooldown) * tempo()
