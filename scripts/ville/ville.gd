class_name Ville
extends RefCounted
## La Ville : la map cachée (easter egg) des combats de mechas. Très large et surtout très haute,
## pour les combats aériens, avec des toits proches pour se battre à pied de toit en toit.
## Pour l'ouvrir en attendant l'accès secret : https://bbstain.github.io/jvtest/?ville
## (elle s'ajoute alors au choix de la map).
##
## La ville est fabriquée ici, pas dessinée dans une scène : chaque immeuble est une liste d'étages.
## Un immeuble est creux : deux murs, un plancher traversable par étage, un toit traversable.
## Le rez-de-chaussée est fermé (ses murs posent l'immeuble sur la rue). Les étages impairs ont une
## porte, d'un seul côté à la fois (gauche, puis droite deux étages plus haut...) : l'autre mur continue
## de tenir l'immeuble. On entre par l'étage 1 en sautant depuis la rue, ou par une passerelle.
## Murs, planchers et passerelles sont des blocs cassables (CityBlock) : seule la rue est indestructible.
## Ce qui ne touche plus le sol s'écroule (CityCollapse). Au centre, la grande tour, reliée à ses
## voisins par de grosses passerelles en bas.
## À gauche de la ville, un parc d'attractions (grande roue, grand huit) ; à droite, un parc arboré.

const BLOCK := 80.0                 ## taille d'un bloc cassable
const FLOOR_BLOCKS := 3             ## hauteur d'un étage en blocs (240 px : un saut + double saut y monte)
const FLOOR_HEIGHT := BLOCK * FLOOR_BLOCKS
const SLAB := 24.0                  ## épaisseur d'un plancher, d'un toit, d'une passerelle
const DOOR_BLOCKS := 2              ## hauteur d'une porte en blocs (le 3e bloc reste au-dessus)
const HALF_WIDTH := 9300.0          ## la rue va de -9300 à 9300 : au-delà, c'est le vide
const PARK_START := 6500.0          ## les deux parcs commencent à cette distance du centre
const STREET_DEPTH := 200.0
const SKY := 8000.0                 ## hauteur de la ville (la zone de jeu monte jusque-là)
const GAP := 200.0                  ## écart entre deux immeubles voisins (on saute de toit en toit)

## Les immeubles de gauche à droite : [largeur en blocs, nombre d'étages, épaisseur des murs en blocs].
## 20 étages = 4 800 px. Au milieu, la grande tour : 30 étages (7 200 px) et des murs de 2 blocs.
const BUILDINGS := [
	[4, 3, 1], [5, 5, 1], [4, 4, 1], [6, 7, 1], [5, 6, 1], [4, 9, 1], [5, 8, 1], [6, 12, 1], [4, 10, 1], [5, 14, 1],
	[12, 30, 2],
	[5, 14, 1], [4, 10, 1], [6, 12, 1], [5, 8, 1], [4, 9, 1], [5, 6, 1], [6, 7, 1], [4, 4, 1], [5, 5, 1], [4, 3, 1],
]
const TOWER := 10                   ## l'index de la grande tour
## Passerelles entre deux voisins : [index de l'immeuble de gauche, étage] (un étage où les deux
## immeubles ont leur porte face à face, voir has_door).
const BRIDGES := [[3, 5], [7, 9], [9, 9], [10, 11], [12, 7], [16, 3]]
## Grosses passerelles pleines (un bloc d'épaisseur) entre la tour et ses voisins, en bas.
const BIG_BRIDGES := [[9, 1], [9, 5], [10, 3], [10, 7]]

const STREET_COLOR := "#3a3d45"
const WALL_COLOR := "#9ea3ad"
const FLOOR_COLOR := "#7d828c"
const BRIDGE_COLOR := "#8a6a4a"
const INSIDE_COLOR := "#242833"
const FAIR_GROUND_COLOR := "#4a3f55"
const GRASS_COLOR := "#3f6b45"
const BLOCK_HP := 6                 ## PV d'un bloc (une attaque légère : 1, une lourde : 3)

static var _next_id := 0
static var _all_blocks: Array[CityBlock] = []


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


## L'étage "floor" de l'immeuble n° index a-t-il une porte du côté "side" (-1 : gauche, 1 : droite) ?
## Étages impairs seulement, un côté à la fois ; un immeuble sur deux commence par l'autre côté,
## pour que deux voisins aient des portes face à face.
static func has_door(index: int, floor: int, side: int) -> bool:
	if floor % 2 == 0:
		return false
	var left_first := (floor % 4 == 1) == (index % 2 == 0)
	return left_first == (side < 0)


## Le milieu (en x) de l'immeuble n° index.
static func building_center(index: int) -> float:
	return building_lefts()[index] + BUILDINGS[index][0] * BLOCK / 2.0


static func build() -> GameMap:
	_next_id = 0
	_all_blocks = []
	var map := GameMap.new()
	map.name = "Ville"
	map.map_name = "Ville"
	var decor := Node2D.new()
	decor.name = "Decor"
	map.add_child(decor)
	# Le sol (jamais cassable) : la fête foraine, la rue, le parc
	_add(decor, "sol", Rect2(-HALF_WIDTH, 0.0, HALF_WIDTH - PARK_START, STREET_DEPTH), FAIR_GROUND_COLOR)
	_add(decor, "sol", Rect2(-PARK_START, 0.0, PARK_START * 2.0, STREET_DEPTH), STREET_COLOR)
	_add(decor, "sol", Rect2(PARK_START, 0.0, HALF_WIDTH - PARK_START, STREET_DEPTH), GRASS_COLOR)
	var lefts := building_lefts()
	for i in BUILDINGS.size():
		_building(decor, i, lefts[i])
	for bridge in BRIDGES:
		var i: int = bridge[0]
		var from: float = lefts[i] + BUILDINGS[i][0] * BLOCK
		var y: float = -float(bridge[1]) * FLOOR_HEIGHT
		_blocks(decor, Rect2(from - BLOCK, y, GAP + BLOCK * 2.0, SLAB), BRIDGE_COLOR, true)
	for bridge in BIG_BRIDGES:
		var i: int = bridge[0]
		var from: float = lefts[i] + BUILDINGS[i][0] * BLOCK
		var y: float = -float(bridge[1]) * FLOOR_HEIGHT
		_blocks(decor, Rect2(from, y, GAP, BLOCK), BRIDGE_COLOR, false)
	var collapse := CityCollapse.new()
	collapse.name = "Ecroulement"
	collapse.setup(_all_blocks)
	map.add_child(collapse)
	_fair(decor)
	_park(decor)
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
	respawn.position = Vector2(building_center(TOWER), roof_top(TOWER) - 400.0)
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
	for x in [-7320.0, 7920.0]:  # un objet dans chaque parc
		var marker := Marker2D.new()
		marker.position = Vector2(x, -200.0)
		items.add_child(marker)
	map.blast_zone = Rect2(-HALF_WIDTH - 700.0, -SKY - 600.0, HALF_WIDTH * 2.0 + 1400.0, SKY + 600.0 + 900.0)
	return map


## L'immeuble creux n° index de BUILDINGS, posé sur la rue à partir de x = left.
static func _building(decor: Node2D, index: int, left: float) -> void:
	var width: int = BUILDINGS[index][0]
	var floors: int = BUILDINGS[index][1]
	var wall: int = BUILDINGS[index][2]
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
		for side in [-1, 1]:
			var x: float = left if side < 0 else left + w - wall * BLOCK
			var wall_height := FLOOR_HEIGHT - (DOOR_BLOCKS * BLOCK if has_door(index, f, side) else 0.0)
			_blocks(decor, Rect2(x, top, wall * BLOCK, wall_height), WALL_COLOR, false)
		# Le plafond de l'étage : un plancher traversable, en haut de l'étage (le dernier est le toit)
		_blocks(decor, Rect2(left, top, w, SLAB), FLOOR_COLOR if f < floors - 1 else WALL_COLOR, true)


## Remplit un rectangle de blocs cassables d'environ BLOCK de côté (des planchers si "floor_blocks").
static func _blocks(decor: Node2D, rect: Rect2, color: String, floor_blocks: bool) -> void:
	var columns := maxi(1, roundi(rect.size.x / BLOCK))
	var rows := maxi(1, roundi(rect.size.y / BLOCK))
	var piece := rect.size / Vector2(columns, rows)
	for c in columns:
		for r in rows:
			var block := CityBlock.new()
			block.setup(piece, Color(color), floor_blocks, BLOCK_HP)
			block.position = rect.position + piece * Vector2(c + 0.5, r + 0.5)
			_next_id += 1
			block.name = "bloc_%d" % _next_id
			decor.add_child(block)
			_all_blocks.append(block)


## Le parc d'attractions, à gauche de la ville : une grande roue et un petit grand huit.
static func _fair(decor: Node2D) -> void:
	var wheel := FerrisWheel.new()
	wheel.name = "GrandeRoue"
	wheel.position = Vector2(-8570.0, -wheel.radius - 120.0)
	decor.add_child(wheel)
	var coaster := Coaster.new()
	coaster.name = "GrandHuit"
	var track := PackedVector2Array()
	for p in [[-7550, -40], [-7420, -160], [-7280, -330], [-7120, -430], [-6960, -360], [-6820, -220],
			[-6700, -200], [-6570, -320], [-6430, -400], [-6300, -260], [-6230, -60]]:
		track.append(Vector2(p[0] - 320.0, p[1]))
	coaster.setup(track)
	decor.add_child(coaster)


## Le parc arboré, à droite de la ville : des arbres où se percher et des bancs.
static func _park(decor: Node2D) -> void:
	var trees := [[6450, 380, 120], [6800, 560, 150], [7150, 300, 110], [7500, 640, 170], [7900, 420, 130],
		[8250, 520, 150], [8650, 340, 120]]
	for t in trees:
		var tree := ParkTree.new()
		tree.setup(t[1], t[2])
		tree.position = Vector2(t[0] + 320.0, 0.0)
		decor.add_child(tree)
	for x in [6940.0, 7650.0, 8400.0, 8780.0]:  # les bancs
		_add(decor, "plateforme", Rect2(x - 60.0, -44.0, 120.0, 12.0), "#8a6a4a")


static func _add(decor: Node2D, type: String, rect: Rect2, color: String) -> void:
	_next_id += 1
	var element := {"id": _next_id, "type": type, "color": color}
	MapData.set_vec(element, "pos", rect.get_center())
	MapData.set_vec(element, "size", rect.size)
	decor.add_child(MapBuilder.build_element(element))
