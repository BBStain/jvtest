class_name MapData
extends RefCounted
## Une map faite dans l'éditeur, sous forme de données simples (un Dictionary), faciles à
## sauvegarder en JSON (dans le navigateur, voir save() / load_saved()) et à envoyer en ligne plus tard.
##
## Format (version FORMAT) :
##   {
##     "format": 1,
##     "name": "Ma map",
##     "elements": [
##       {"id": 1, "type": "sol", "pos": [640, 600], "size": [1100, 60], "rot": 0, "color": "#525973"},
##       {"id": 2, "type": "spawn_joueur", "pos": [440, 570], "player": 1},
##       ...
##     ]
##   }
## Les positions sont en pixels du jeu (x : droite, y : bas) ; "pos" est le centre de l'élément,
## sauf pour les points d'apparition (les pieds) et la liane (son point d'accroche, en haut).
## Un champ absent prend la valeur par défaut du CATALOGUE : un vieux fichier se charge toujours.
## MapBuilder transforme ces données en vraie map jouable (GameMap).

const FORMAT := 1
const SAVE_DIR := "user://cartes"
const DRAFT_NAME := "_brouillon"    ## la map en cours, gardée quand on quitte l'éditeur

## Tout ce qu'on peut poser dans l'éditeur. Pour chaque type :
##   label : le nom affiché ; tab : sa famille dans le catalogue ; rotatable : peut tourner ;
##   defaults : les réglages de départ (et ceux d'un champ absent dans un fichier).
const CATALOG := {
	"sol": {
		"label": "Bloc plein", "tab": "Décor", "rotatable": true,
		"defaults": {"size": [300, 40], "rot": 0.0, "color": "#525973"},
	},
	"plateforme": {
		"label": "Plateforme traversable", "tab": "Décor", "rotatable": true,
		"defaults": {"size": [200, 16], "rot": 0.0, "color": "#808aa8"},
	},
	"fenetre": {
		"label": "Fenêtre cassable", "tab": "Décor", "rotatable": false,
		"defaults": {"size": [90, 110], "color": "#8cc7e6"},
	},
	"mobile": {
		"label": "Plateforme mobile", "tab": "Mouvement", "rotatable": false,
		"defaults": {"size": [160, 16], "travel": [400, 0], "period": 6.0, "pause": 0.0, "color": "#9e8cd9"},
	},
	"echelle": {
		"label": "Échelle", "tab": "Mouvement", "rotatable": false,
		"defaults": {"size": [40, 400], "color": "#d9b366"},
	},
	"liane": {
		"label": "Liane", "tab": "Mouvement", "rotatable": false,
		"defaults": {"length": 260.0, "color": "#59b34d"},
	},
	"spawn_joueur": {
		"label": "Départ d'un joueur", "tab": "Apparitions", "rotatable": false,
		"defaults": {"player": 1},
	},
	"reapparition": {
		"label": "Réapparition", "tab": "Apparitions", "rotatable": false,
		"defaults": {},
	},
	"spawn_objet": {
		"label": "Apparition d'objet", "tab": "Apparitions", "rotatable": false,
		"defaults": {},
	},
}
## Les familles du catalogue, dans l'ordre.
const TABS := ["Décor", "Mouvement", "Apparitions"]
## Ces types sont des points (pas de taille) : on les attrape par un rond autour de "pos".
const POINT_TYPES := ["spawn_joueur", "reapparition", "spawn_objet"]
const POINT_RADIUS := 26.0


## Une map toute neuve, déjà jouable : un sol, deux départs, une réapparition.
static func new_map(map_name := "Ma map") -> Dictionary:
	var data := {"format": FORMAT, "name": map_name, "elements": []}
	add_element(data, "sol", Vector2(640, 600)).size = [1100, 60]
	add_element(data, "plateforme", Vector2(640, 440)).size = [440, 16]
	add_element(data, "spawn_joueur", Vector2(400, 570)).player = 1
	add_element(data, "spawn_joueur", Vector2(880, 570)).player = 2
	add_element(data, "reapparition", Vector2(640, 300))
	return data


## Ajoute un élément du CATALOGUE à la map (avec ses réglages par défaut) et le renvoie.
static func add_element(data: Dictionary, type: String, pos: Vector2) -> Dictionary:
	var element := {"id": next_id(data), "type": type, "pos": [pos.x, pos.y]}
	element.merge((CATALOG[type].defaults as Dictionary).duplicate(true))
	data.elements.append(element)
	return element


static func next_id(data: Dictionary) -> int:
	var top := 0
	for element in data.elements:
		top = maxi(top, int(element.get("id", 0)))
	return top + 1


## Complète une map lue dans un fichier : champs manquants, types inconnus enlevés.
static func normalized(raw: Dictionary) -> Dictionary:
	# Un passage par le JSON : les nombres sont toujours rangés pareil (comme après une relecture).
	raw = JSON.parse_string(JSON.stringify(raw))
	var data := {"format": FORMAT, "name": str(raw.get("name", "Ma map")), "elements": []}
	var used_ids := {}
	for item in raw.get("elements", []):
		if not (item is Dictionary) or not CATALOG.has(item.get("type", "")):
			continue
		var element: Dictionary = (CATALOG[item.type].defaults as Dictionary).duplicate(true)
		element.merge(item, true)
		if not (element.get("pos") is Array) or element.pos.size() < 2:
			element.pos = [0, 0]
		var id := int(element.get("id", 0))
		if id <= 0 or used_ids.has(id):
			id = used_ids.size() + 1000
			while used_ids.has(id):
				id += 1
		element.id = id
		used_ids[id] = true
		data.elements.append(element)
	return data


# --- Lire les champs d'un élément ---

static func vec(element: Dictionary, key: String) -> Vector2:
	var value: Array = element.get(key, [0, 0])
	return Vector2(float(value[0]), float(value[1]))


static func set_vec(element: Dictionary, key: String, value: Vector2) -> void:
	element[key] = [snappedf(value.x, 0.01), snappedf(value.y, 0.01)]


static func color(element: Dictionary) -> Color:
	return Color.from_string(str(element.get("color", "#ffffff")), Color.WHITE)


## L'angle de l'élément, en radians (rangé en degrés dans le fichier).
static func rotation(element: Dictionary) -> float:
	return deg_to_rad(float(element.get("rot", 0.0)))


## La taille de l'élément (une liane : sa largeur et sa longueur ; un point : un petit carré).
static func size_of(element: Dictionary) -> Vector2:
	if element.type == "liane":
		return Vector2(Vine.WIDTH * 3.0, float(element.length))
	if element.type in POINT_TYPES:
		return Vector2(POINT_RADIUS, POINT_RADIUS) * 2.0
	return vec(element, "size")


## Le centre de l'élément (la liane pend sous son point d'accroche).
static func center_of(element: Dictionary) -> Vector2:
	var pos := vec(element, "pos")
	if element.type == "liane":
		return pos + Vector2(0.0, float(element.length) / 2.0)
	if element.type in POINT_TYPES and element.type != "spawn_objet":
		return pos + Vector2(0.0, -POINT_RADIUS)  # les départs sont posés par les pieds
	return pos


## Le point de la map est-il sur l'élément ? (tient compte de la rotation)
static func contains(element: Dictionary, point: Vector2, margin := 0.0) -> bool:
	var local := (point - center_of(element)).rotated(-rotation(element))
	var half := size_of(element) / 2.0 + Vector2(margin, margin)
	half = half.max(Vector2(10.0, 10.0))  # les éléments très fins restent faciles à attraper
	return absf(local.x) <= half.x and absf(local.y) <= half.y


## Le rectangle (sans rotation) que l'élément occupe à peu près, pour cadrer la vue et la zone de jeu.
static func bounds_of(element: Dictionary) -> Rect2:
	var half := size_of(element) / 2.0
	var corners := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	var rect := Rect2(center_of(element), Vector2.ZERO)
	for corner in corners:
		rect = rect.expand(center_of(element) + (corner as Vector2).rotated(rotation(element)))
	if element.type == "mobile":
		rect = rect.merge(Rect2(rect.position + vec(element, "travel"), rect.size))
	return rect


## Tout ce qu'occupe la map.
static func bounds(data: Dictionary) -> Rect2:
	var rect := Rect2()
	var first := true
	for element in data.elements:
		rect = bounds_of(element) if first else rect.merge(bounds_of(element))
		first = false
	return rect


# --- Sauvegarde (dans le navigateur, ou le dossier du jeu sur PC) ---

static func to_json(data: Dictionary) -> String:
	return JSON.stringify(data, "  ")


## Lit une map depuis du texte JSON. Renvoie {} si le texte n'est pas une map.
static func from_json(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("elements"):
		return {}
	return normalized(parsed)


static func file_path(map_name: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, file_name(map_name)]


## Un nom de fichier sans caractères gênants.
static func file_name(map_name: String) -> String:
	var clean := map_name.strip_edges().validate_filename().replace(" ", "_")
	return clean if clean != "" else "sans_nom"


static func save(data: Dictionary, as_name := "") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(file_path(as_name if as_name != "" else str(data.name)), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_json(data))
	file.close()
	return true


static func load_saved(map_name: String) -> Dictionary:
	var path := file_path(map_name)
	if not FileAccess.file_exists(path):
		return {}
	return from_json(FileAccess.get_file_as_string(path))


static func delete_saved(map_name: String) -> void:
	DirAccess.remove_absolute(file_path(map_name))


## Les maps sauvegardées (leurs noms de fichier, sans le brouillon), dans l'ordre alphabétique.
static func list_saved() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return names
	for file in dir.get_files():
		if file.ends_with(".json") and file.get_basename() != DRAFT_NAME:
			names.append(file.get_basename())
	names.sort()
	return names
