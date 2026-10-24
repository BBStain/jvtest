class_name Ville
extends RefCounted
## La Ville : la map cachée (easter egg) des combats de mechas. Très large et surtout très haute,
## pour les combats aériens, avec des toits proches pour se battre à pied de toit en toit.
## Étape 1 du plan : la ville "vide", rien n'est encore cassable. Pour l'ouvrir en attendant
## l'accès secret : https://bbstain.github.io/jvtest/?ville (elle s'ajoute alors au choix de la map).
##
## La ville est fabriquée ici, pas dessinée dans une scène : chaque immeuble est une liste d'étages.
## Un immeuble est creux : deux murs, un plancher traversable par étage, un toit traversable.
## Un étage sur deux a une porte de chaque côté (on entre, on traverse, on monte d'étage en étage).

const BLOCK := 80.0                 ## taille d'un bloc (les futurs blocs cassables)
const FLOOR_BLOCKS := 3             ## hauteur d'un étage en blocs (240 px : un saut + double saut y monte)
const FLOOR_HEIGHT := BLOCK * FLOOR_BLOCKS
const SLAB := 24.0                  ## épaisseur d'un plancher, d'un toit, d'une passerelle
const DOOR_BLOCKS := 2              ## hauteur d'une porte en blocs (le 3e bloc reste au-dessus)
const HALF_WIDTH := 6300.0          ## la rue va de -6300 à 6300 : au-delà, c'est le vide
const STREET_DEPTH := 200.0
const SKY := 8000.0                 ## hauteur de la ville (la zone de jeu monte jusque-là)
const GAP := 200.0                  ## écart entre deux immeubles voisins (on saute de toit en toit)

## Les immeubles de gauche à droite : [largeur en blocs, nombre d'étages]. 20 étages = 4 800 px.
const BUILDINGS := [
	[4, 3], [5, 5], [4, 4], [6, 7], [5, 6], [4, 9], [5, 8], [6, 12], [4, 10], [5, 14],
	[6, 20],
	[5, 14], [4, 10], [6, 12], [5, 8], [4, 9], [5, 6], [6, 7], [4, 4], [5, 5], [4, 3],
]
## Passerelles entre deux voisins : [index de l'immeuble de gauche, étage] (un étage avec portes).
const BRIDGES := [[3, 4], [7, 8], [9, 10], [10, 10], [12, 8], [16, 4]]

const STREET_COLOR := "#3a3d45"
const WALL_COLOR := "#9ea3ad"
const FLOOR_COLOR := "#7d828c"
const BRIDGE_COLOR := "#8a6a4a"
const INSIDE_COLOR := "#242833"

static var _next_id := 0


## La ville peut-elle être choisie dans le menu ? (?ville dans l'adresse, en attendant l'accès secret)
static func unlocked() -> bool:
	if not OS.has_feature("web"):
		return false
	return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('ville')")) == "true"


## Le bord gauche de chaque immeuble (ils sont centrés dans la rue).
static func building_lefts() -> Array[float]:
	var total: float = GAP * (BUILDINGS.size() - 1)
	for b in BUILDINGS:
		total += b[0] * BLOCK
	var lefts: Array[float] = []
	var x := -total / 2.0
	for b in BUILDINGS:
		lefts.append(x)
		x += b[0] * BLOCK + GAP
	return lefts


## Le haut du toit de l'immeuble n° index (en y, la rue est à 0 et le haut est négatif).
static func roof_top(index: int) -> float:
	return -BUILDINGS[index][1] * FLOOR_HEIGHT


## Le milieu (en x) de l'immeuble n° index.
static func building_center(index: int) -> float:
	return building_lefts()[index] + BUILDINGS[index][0] * BLOCK / 2.0


static func build() -> GameMap:
	_next_id = 0
	var map := GameMap.new()
	map.name = "Ville"
	map.map_name = "Ville"
	var decor := Node2D.new()
	decor.name = "Decor"
	map.add_child(decor)
	# La rue (le seul sol qui ne cassera jamais)
	_add(decor, "sol", Rect2(-HALF_WIDTH, 0.0, HALF_WIDTH * 2.0, STREET_DEPTH), STREET_COLOR)
	var lefts := building_lefts()
	for i in BUILDINGS.size():
		_building(decor, lefts[i], BUILDINGS[i][0], BUILDINGS[i][1])
	for bridge in BRIDGES:
		var i: int = bridge[0]
		var from: float = lefts[i] + BUILDINGS[i][0] * BLOCK
		var y: float = -float(bridge[1]) * FLOOR_HEIGHT
		_add(decor, "plateforme", Rect2(from - BLOCK, y, GAP + BLOCK * 2.0, SLAB), BRIDGE_COLOR)
	# Les départs : sur les toits autour du centre ; on réapparaît en tombant du ciel au milieu
	var spawns := Node2D.new()
	spawns.name = "SpawnPoints"
	map.add_child(spawns)
	for i in [7, 13, 9, 11]:
		var marker := Marker2D.new()
		marker.position = Vector2(building_center(i), roof_top(i))
		spawns.add_child(marker)
	var respawn := Marker2D.new()
	respawn.name = "RespawnPoint"
	respawn.position = Vector2(building_center(10), roof_top(10) - 400.0)
	map.add_child(respawn)
	var items := Node2D.new()
	items.name = "ItemSpawns"
	map.add_child(items)
	var weapons := Node2D.new()
	weapons.name = "WeaponSpawns"
	map.add_child(weapons)
	for i in [3, 6, 8, 12, 14, 17]:
		var marker := Marker2D.new()
		marker.position = Vector2(building_center(i), roof_top(i) - 200.0)
		(weapons if i in [6, 8, 12, 14] else items).add_child(marker)
	map.blast_zone = Rect2(-HALF_WIDTH - 700.0, -SKY - 600.0, HALF_WIDTH * 2.0 + 1400.0, SKY + 600.0 + 900.0)
	return map


## Un immeuble creux de "width" blocs et "floors" étages, posé sur la rue à partir de x = left.
static func _building(decor: Node2D, left: float, width: int, floors: int) -> void:
	var w: float = width * BLOCK
	# L'intérieur, un peu plus clair que le ciel (juste du décor, on passe au travers)
	var inside := ColorRect.new()
	inside.position = Vector2(left, -floors * FLOOR_HEIGHT)
	inside.size = Vector2(w, floors * FLOOR_HEIGHT)
	inside.color = Color(INSIDE_COLOR)
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.z_index = -1
	decor.add_child(inside)
	for f in floors:
		var bottom: float = -f * FLOOR_HEIGHT     # le bas de l'étage
		var top := bottom - FLOOR_HEIGHT
		# Un étage sur deux (le rez-de-chaussée compris) a une porte de chaque côté
		var wall_top := top
		var wall_height := FLOOR_HEIGHT
		if f % 2 == 0:
			wall_height = FLOOR_HEIGHT - DOOR_BLOCKS * BLOCK
		for x in [left, left + w - BLOCK]:
			_add(decor, "sol", Rect2(x, wall_top, BLOCK, wall_height), WALL_COLOR)
		# Le plafond de l'étage : un plancher traversable, en haut de l'étage (le dernier est le toit)
		_add(decor, "plateforme", Rect2(left, top, w, SLAB), FLOOR_COLOR if f < floors - 1 else WALL_COLOR)


static func _add(decor: Node2D, type: String, rect: Rect2, color: String) -> void:
	_next_id += 1
	var element := {"id": _next_id, "type": type, "color": color}
	MapData.set_vec(element, "pos", rect.get_center())
	MapData.set_vec(element, "size", rect.size)
	decor.add_child(MapBuilder.build_element(element))
