class_name Ville
extends RefCounted
## La Ville : la map des combats de mechas (une map comme les autres, avec en plus la balise
## d'appel du mecha). Très large et surtout très haute, pour les combats aériens, avec des toits
## proches pour se battre à pied de toit en toit. Pas encore en ligne.
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
## Beaucoup d'objets et d'armes : dans les immeubles (un étage sur deux), sur les toits et dans les parcs.
const ITEM_SPAWN_TIME := 1.5        ## un objet toutes les 1,5 s...
const MAX_PICKUPS := 20             ## ... jusqu'à 20 par terre
const WEAPON_SPAWN_TIME := 2.5      ## une arme toutes les 2,5 s...
const MAX_LOOSE_WEAPONS := 12       ## ... jusqu'à 12 qui traînent
## Un peu de variété, tirée au hasard à chaque partie (voir build) :
const THIN_WALL_CHANCE := 0.3       ## un pan de mur (un étage, un côté) sur 3 est fin : moitié moins épais...
const THIN_WALL_HP := 5             ## ... et un PV de moins
const WINDOW_CHANCE := 0.15         ## un pan de mur plein sur 7 a une fenêtre (le bloc du milieu, en verre)
const WINDOW_HP := 1                ## une fenêtre casse au premier coup
const WINDOW_COLOR := "#9fd3ea"
const BARRELS := 18                 ## tonneaux explosifs posés au hasard dans les immeubles
const BLOCK_HP := 6                 ## PV d'un bloc (une attaque légère : 1, une lourde : 3)

static var _next_id := 0
## false : la ville toujours pareille (sans murs fins, fenêtres ni tonneaux), pour les tests.
static var variety := true
static var _rng := RandomNumberGenerator.new()
static var _all_blocks: Array[CityBlock] = []


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
	_rng.randomize()
	var map := GameMap.new()
	map.name = "Ville"
	map.map_name = "Ville"
	map.has_mechas = true
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
	if variety:
		_barrels(decor)
	var collapse := CityCollapse.new()
	collapse.name = "Ecroulement"
	collapse.setup(_all_blocks)
	map.add_child(collapse)
	CityPainter.paint(decor, _all_blocks)
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
	map.item_spawn_time = ITEM_SPAWN_TIME
	map.max_pickups = MAX_PICKUPS
	map.weapon_spawn_time = WEAPON_SPAWN_TIME
	map.max_loose_weapons = MAX_LOOSE_WEAPONS
	var items := Node2D.new()
	items.name = "ItemSpawns"
	map.add_child(items)
	var weapons := Node2D.new()
	weapons.name = "WeaponSpawns"
	map.add_child(weapons)
	# Dans chaque immeuble, un étage sur deux (objets et armes en alternance), et sur chaque toit
	var spot := 0
	for i in BUILDINGS.size():
		for f in range(0, BUILDINGS[i][1], 2):
			var marker := Marker2D.new()
			marker.position = Vector2(building_center(i), -f * FLOOR_HEIGHT - 100.0)
			(items if spot % 2 == 0 else weapons).add_child(marker)
			spot += 1
		var roof := Marker2D.new()
		roof.position = Vector2(building_center(i), roof_top(i) - 200.0)
		(weapons if i % 2 == 0 else items).add_child(roof)
	for x in [-7920.0, -7320.0, -6800.0, 6800.0, 7400.0, 7920.0]:  # dans les deux parcs
		for target in [items, weapons]:
			var marker := Marker2D.new()
			marker.position = Vector2(x + (60.0 if target == weapons else 0.0), -200.0)
			target.add_child(marker)
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
			var thin := variety and _rng.randf() < THIN_WALL_CHANCE
			var thickness: float = wall * BLOCK / (2.0 if thin else 1.0)
			var hp := THIN_WALL_HP if thin else BLOCK_HP
			var x: float = left if side < 0 else left + w - thickness
			var door := has_door(index, f, side)
			var wall_height := FLOOR_HEIGHT - (DOOR_BLOCKS * BLOCK if door else 0.0)
			if variety and not door and _rng.randf() < WINDOW_CHANCE:
				# Une fenêtre au milieu du mur : un bloc en verre entre deux blocs de mur
				_blocks(decor, Rect2(x, top, thickness, BLOCK), WALL_COLOR, false, hp)
				_blocks(decor, Rect2(x, top + BLOCK, thickness, BLOCK), WINDOW_COLOR, false, WINDOW_HP)
				_blocks(decor, Rect2(x, top + BLOCK * 2.0, thickness, BLOCK), WALL_COLOR, false, hp)
			else:
				_blocks(decor, Rect2(x, top, thickness, wall_height), WALL_COLOR, false, hp)
		# Le plafond de l'étage : un plancher traversable, en haut de l'étage (le dernier est le toit)
		_blocks(decor, Rect2(left, top, w, SLAB), FLOOR_COLOR if f < floors - 1 else WALL_COLOR, true)


## Remplit un rectangle de blocs cassables d'environ BLOCK de côté (des planchers si "floor_blocks").
static func _blocks(decor: Node2D, rect: Rect2, color: String, floor_blocks: bool, hp := BLOCK_HP) -> void:
	var columns := maxi(1, roundi(rect.size.x / BLOCK))
	var rows := maxi(1, roundi(rect.size.y / BLOCK))
	var piece := rect.size / Vector2(columns, rows)
	for c in columns:
		for r in rows:
			var block := CityBlock.new()
			block.setup(piece, Color(color), floor_blocks, hp)
			block.position = rect.position + piece * Vector2(c + 0.5, r + 0.5)
			_next_id += 1
			block.name = "bloc_%d" % _next_id
			decor.add_child(block)
			_all_blocks.append(block)


## Les tonneaux explosifs : BARRELS posés au hasard sur les planchers, à l'intérieur des immeubles
## (pas deux au même endroit).
static func _barrels(decor: Node2D) -> void:
	var lefts := building_lefts()
	var placed: Array[Rect2] = []
	var tries := 0
	while placed.size() < BARRELS and tries < BARRELS * 20:
		tries += 1
		var i := _rng.randi() % BUILDINGS.size()
		var wall: float = BUILDINGS[i][2] * BLOCK
		var inner_left: float = lefts[i] + wall + ExplosiveBarrel.SIZE.x
		var inner_right: float = lefts[i] + BUILDINGS[i][0] * BLOCK - wall - ExplosiveBarrel.SIZE.x
		if inner_right <= inner_left:
			continue
		var f := _rng.randi() % int(BUILDINGS[i][1])
		var spot := Vector2(_rng.randf_range(inner_left, inner_right), -f * FLOOR_HEIGHT - ExplosiveBarrel.SIZE.y / 2.0)
		var box := Rect2(spot - ExplosiveBarrel.SIZE / 2.0, ExplosiveBarrel.SIZE).grow(40.0)
		if placed.any(func(r: Rect2) -> bool: return r.intersects(box)):
			continue
		placed.append(box)
		var barrel := ExplosiveBarrel.new()
		barrel.setup_barrel()
		barrel.position = spot
		_next_id += 1
		barrel.name = "tonneau_%d" % _next_id
		decor.add_child(barrel)
		_all_blocks.append(barrel)


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
