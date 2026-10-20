class_name WeaponStats
extends Resource
## Une arme, choisie avec son perso. Elle change les attaques du perso : vitesse, portée,
## projection... (des multiplicateurs : 1 = comme à mains nues), et ce que fait l'attaque lourde.
##
## Chaque arme est un fichier .tres dans le dossier weapons/ (ex. weapons/katana.tres).
## Pour créer une arme : duplique weapons/mains_nues.tres, change ses chiffres dans l'inspecteur,
## puis ajoute-la dans WEAPONS de scripts/game_setup.gd.
## Le dessin est volontairement très simple (une couleur par arme) : un graphiste le remplacera.

enum Heavy {
	SWING,   ## l'arc de cercle habituel du dessus de la tête jusqu'aux pieds
	DASH,    ## katana : un dash tranchant qui traverse l'adversaire (on esquive pendant, mais un contre l'arrête)
	SLAM,    ## marteau : l'arc, puis une onde de choc au sol des deux côtés
	THROW,   ## lance : on la lance ; tant qu'on ne l'a pas ramassée, on se bat à mains nues
	BURST,   ## nunchaku : une rafale de 3 coups (on avance normalement en chargeant ; la charge les allonge)
	SHOOT,   ## arc : une flèche qui fait mal (plus on charge, plus elle va loin et vite) ; on garde l'arc
}

@export var display_name := "Mains nues"
@export var description := ""
@export var color := Color(1, 1, 1)  ## couleur de l'arme (la barre du coup léger, la lame de la lourde)
@export var held_length := 0.0       ## longueur de l'arme dessinée dans la main (0 = rien dans la main)
@export var held_head := 0.0         ## taille du bout de l'arme dans la main (tête du marteau, pointe de la lance)

@export_group("Attaque légère")
@export var light_startup_mult := 1.0    ## temps pour armer le coup (plus petit = part plus vite)
@export var light_cooldown_mult := 1.0   ## recharge (plus petit = on peut marteler)
@export var light_reach_mult := 1.0      ## longueur du coup
@export var light_radius_mult := 1.0     ## épaisseur du coup
@export var light_knockback_mult := 1.0  ## projection
@export var light_swing := false         ## nunchaku : les coups alternent vers le bas puis vers le haut, et projettent dans ce sens

@export_group("Attaque lourde")
@export var heavy: Heavy = Heavy.SWING
@export var heavy_cooldown_mult := 1.0
@export var heavy_reach_mult := 1.0      ## longueur de l'arme (arc) ou du coup
@export var heavy_radius_mult := 1.0     ## taille de la zone qui touche
@export var heavy_knockback_mult := 1.0
@export var heavy_shield_damage := 1     ## la lourde abîme les boucliers tant de fois plus
@export var heavy_speed := 0.0           ## katana : vitesse du dash ; lance : vitesse du lancer (pleine charge = x1,5) ; arc : vitesse de la flèche


## Mains nues : pas d'arme qui s'use ni qui casse.
func is_bare_hands() -> bool:
	return heavy == Heavy.SWING and held_length <= 0.0


## Les stats du perso avec cette arme en main (une copie : le perso de base ne change pas).
func apply_to(base: CharacterStats) -> CharacterStats:
	var s := base.duplicate() as CharacterStats
	s.weight = base.mass()  # la copie garde le poids du perso, même si on change une taille plus tard
	s.attack_tempo = base.tempo()
	s.attack_startup *= light_startup_mult
	s.attack_cooldown *= light_cooldown_mult
	s.attack_reach *= light_reach_mult
	s.attack_radius *= light_radius_mult
	s.hit_knockback *= light_knockback_mult
	s.heavy_cooldown *= heavy_cooldown_mult
	s.heavy_arc_radius *= heavy_reach_mult
	s.heavy_tip_radius *= heavy_radius_mult
	s.heavy_knockback *= heavy_knockback_mult
	return s
