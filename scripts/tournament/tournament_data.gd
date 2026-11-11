class_name TournamentData
extends RefCounted
## Un tournoi en duels : les joueurs inscrits (un nom et une couleur chacun), leur place dans
## le 1er tour (tirée au sort avec ALÉATOIRE), et les réglages (map, nombre de vies).
## Le tournoi est gardé dans le navigateur (user://tournoi.json) : on le retrouve en revenant sur le jeu.
##
## L'arbre est fait de tours ; chaque tour est une liste de matchs. Les matchs sont des duels
## (le gagnant passe) ou des matchs à 4 (les 2 derniers en vie passent), selon le réglage.
## Les tours suivants reçoivent les qualifiés des matchs d'avant, jusqu'à la finale (toujours un
## duel). Quand il manque des joueurs, des cases « exempt » complètent les matchs.

const CODE := "SWAG"  ## le code pour entrer (juste une porte dans le jeu, pas une vraie sécurité)
const CODE_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SAVE_PATH := "user://tournoi.json"
const MAX_PLAYERS := 32
const MAX_NAME := 12
const MATCH_SIZES := [2, 4]  ## joueurs par match : duels, ou matchs à 4 (les 2 derniers passent)
## Les couleurs qu'on peut choisir à l'inscription.
const COLORS := [
	Color(0.95, 0.3, 0.3), Color(0.3, 0.55, 1.0), Color(0.35, 0.85, 0.4), Color(1.0, 0.8, 0.25),
	Color(0.75, 0.4, 0.95), Color(1.0, 0.55, 0.2), Color(0.25, 0.85, 0.85), Color(1.0, 0.45, 0.75),
	Color(0.6, 0.85, 0.2), Color(0.55, 0.4, 0.25), Color(0.85, 0.85, 0.9), Color(0.4, 0.4, 0.5),
]
const MIN_LIVES := 1
const MAX_LIVES := 5

static var unlocked := false     ## le code a été tapé (on ne le redemande pas avant de recharger la page)

var players: Array[Dictionary] = []  ## {"name": String, "color": index dans COLORS}
var seeding: Array[int] = []         ## les joueurs (leur index) dans l'ordre des places du 1er tour ; vide = pas encore tirés
var lives := 3
var match_size := 2                 ## joueurs par match au 1er tour (voir MATCH_SIZES)
var map: String = GameSetup.MAPS[0]
var results := {}                   ## numéro du match (en texte) -> les joueurs qualifiés (Array)


## Le tournoi enregistré (un tournoi vide s'il n'y en a pas).
static func load_saved() -> TournamentData:
	var tournament := TournamentData.new()
	if not FileAccess.file_exists(SAVE_PATH):
		return tournament
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return tournament
	for player in data.get("players", []):
		if player is Dictionary and tournament.players.size() < MAX_PLAYERS:
			tournament.players.append({"name": str(player.get("name", "?")).left(MAX_NAME),
				"color": clampi(int(player.get("color", 0)), 0, COLORS.size() - 1)})
	for index in data.get("seeding", []):
		tournament.seeding.append(int(index))
	if not tournament.is_seeded():
		tournament.seeding = []
	tournament.lives = clampi(int(data.get("lives", 3)), MIN_LIVES, MAX_LIVES)
	if int(data.get("match_size", 2)) in MATCH_SIZES:
		tournament.match_size = int(data.match_size)
	var saved_results = data.get("results", {})
	if tournament.is_seeded() and saved_results is Dictionary:
		for number in saved_results:
			var qualified = saved_results[number]
			tournament.results[str(number)] = (qualified as Array).map(func(p) -> int: return int(p)) if qualified is Array else [int(qualified)]
	if str(data.get("map", "")) in GameSetup.MAPS:
		tournament.map = data.map
	return tournament


static func check_code(typed: String) -> bool:
	unlocked = unlocked or typed.to_upper() == CODE
	return unlocked


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"players": players, "seeding": seeding, "lives": lives, "map": map,
			"match_size": match_size, "results": results}))


## Inscrit un joueur (pas de doublon, pas de nom vide). Renvoie false s'il n'a pas été inscrit.
## Le tirage au sort est à refaire.
func add_player(player_name: String, color: int) -> bool:
	player_name = player_name.strip_edges().left(MAX_NAME)
	if player_name == "" or players.size() >= MAX_PLAYERS:
		return false
	for player in players:
		if player.name.to_lower() == player_name.to_lower():
			return false
	players.append({"name": player_name, "color": color})
	seeding = []
	results = {}
	return true


func remove_player(index: int) -> void:
	players.remove_at(index)
	seeding = []
	results = {}


## La couleur proposée au prochain inscrit : la première pas encore prise (après "after").
func next_free_color(after := -1) -> int:
	for step in range(1, COLORS.size() + 1):
		var color := posmod(after + step, COLORS.size())
		if not players.any(func(p: Dictionary) -> bool: return p.color == color):
			return color
	return posmod(after + 1, COLORS.size())


## Tire au sort la place de chaque joueur dans le 1er tour.
func shuffle() -> void:
	results = {}
	seeding = []
	for i in players.size():
		seeding.append(i)
	seeding.shuffle()


func is_seeded() -> bool:
	if seeding.size() != players.size():
		return false
	var sorted := seeding.duplicate()
	sorted.sort()
	for i in sorted.size():
		if sorted[i] != i:
			return false
	return true


const BYE := -2      ## une case "passe d'office" (pas d'adversaire)
const UNKNOWN := -1  ## une case pas encore connue (pas tiré, ou vainqueur pas encore joué)


## La taille de l'arbre : la puissance de 2 juste au-dessus du nombre d'inscrits (5 -> 8),
## au moins un match plein.
func bracket_size() -> int:
	var size := match_size
	while size < players.size():
		size *= 2
	return size


## Change le nombre de joueurs par match (2 -> 4 -> 2). Les matchs déjà joués sont effacés.
func next_match_size(step := 1) -> void:
	match_size = MATCH_SIZES[posmod(MATCH_SIZES.find(match_size) + step, MATCH_SIZES.size())]
	results = {}


## L'ordre classique des têtes de série dans un arbre de cette taille (8 -> 1 8 4 5 2 7 3 6) :
## les places au-delà du nombre d'inscrits deviennent des « exempt », et elles tombent
## chacune dans un match différent, bien réparties dans l'arbre.
static func seed_order(size: int) -> Array[int]:
	var order: Array[int] = [1, 2]
	while order.size() < size:
		var next: Array[int] = []
		for s in order:
			next.append(s)
			next.append(order.size() * 2 + 1 - s)
		order = next
	return order


## Combien de joueurs d'un match passent au tour suivant : 1 en duel, 2 dans un match à 4.
static func qualified_count(game: Dictionary) -> int:
	return game.slots.size() / 2


## L'arbre : une liste de tours, chaque tour une liste de matchs.
## Un match = {"number": numéro (M1, M2... sur tout le tournoi),
##             "slots": les cases (2 ou 4) : l'index du joueur, UNKNOWN (pas encore tiré / pas
##                      encore joué) ou BYE (exempt),
##             "places": au 1er tour, la place de chaque case (voir seeding), -1 pour un BYE,
##             "sources": les numéros des matchs dont les qualifiés viennent ici}.
## Après le dernier match à 4, les 2 qualifiés jouent la finale en duel.
func bracket() -> Array:
	var rounds := []
	if players.size() < 2:
		return rounds
	var order := seed_order(bracket_size())
	var seeded := is_seeded()
	var number := 1
	var first := []
	for m in order.size() / match_size:
		var slots := []
		var places := []
		for seed in order.slice(m * match_size, (m + 1) * match_size):
			if seed > players.size():
				slots.append(BYE)
				places.append(-1)
			else:
				slots.append(seeding[seed - 1] if seeded else UNKNOWN)
				places.append(seed - 1)
		first.append({"number": number, "slots": slots, "places": places, "sources": []})
		number += 1
	rounds.append(first)
	while rounds[-1].size() > 1 or rounds[-1][0].slots.size() > 2:
		var previous: Array = rounds[-1]
		var next := []
		var step := 2 if previous.size() > 1 else 1  # le dernier match à 4 donne la finale à lui seul
		for m in range(0, previous.size(), step):
			var slots := []
			var sources := []
			for game in previous.slice(m, m + step):
				slots.append_array(qualified_of(game))
				sources.append(game.number)
			next.append({"number": number, "slots": slots, "places": [], "sources": sources})
			number += 1
		rounds.append(next)
	return rounds


## Les qualifiés d'un match s'ils sont connus (match joué, ou pas assez d'adversaires pour jouer :
## ceux qui sont là passent d'office), sinon des UNKNOWN. Complété par des BYE.
func qualified_of(game: Dictionary) -> Array:
	var count := qualified_count(game)
	var qualified := []
	if results.has(str(game.number)):
		qualified = results[str(game.number)].duplicate()
	elif not game.slots.has(UNKNOWN) and _real_players(game).size() <= count:
		qualified = _real_players(game)
	else:
		qualified.resize(count)
		qualified.fill(UNKNOWN)
	while qualified.size() < count:
		qualified.append(BYE)
	return qualified


func _real_players(game: Dictionary) -> Array:
	return game.slots.filter(func(p: int) -> bool: return p >= 0)


## Note les qualifiés d'un match (ils passent au tour suivant).
func set_result(number: int, qualified: Array) -> void:
	results[str(number)] = qualified.duplicate()


## Un match qu'on peut jouer : tous ses joueurs sont connus, il y en a plus que de qualifiés,
## et il n'a pas encore de résultat.
func is_playable(game: Dictionary) -> bool:
	return not game.slots.has(UNKNOWN) and _real_players(game).size() > qualified_count(game) \
		and not results.has(str(game.number))


## Le prochain match à jouer, tour après tour. {} s'il n'y en a pas (pas tiré, ou tournoi fini).
## "round_players" : combien de joueurs dans ce tour (pour son nom : Finale, Demies...).
func next_match() -> Dictionary:
	var playable := _playable_round()
	return {} if playable.is_empty() else playable[0]


## START : un match tiré au hasard parmi ceux qu'on peut jouer dans le tour en cours. {} s'il n'y en a pas.
func random_match() -> Dictionary:
	var playable := _playable_round()
	return {} if playable.is_empty() else playable.pick_random()


func _playable_round() -> Array:
	if not is_seeded():
		return []
	for matches in bracket():
		var playable := []
		for game in matches:
			if is_playable(game):
				game.round_players = matches.size() * game.slots.size()
				playable.append(game)
		if not playable.is_empty():
			return playable
	return []


## Le champion (le vainqueur de la finale), ou UNKNOWN si la finale n'est pas jouée.
func champion() -> int:
	var rounds := bracket()
	if rounds.is_empty() or not is_seeded():
		return UNKNOWN
	return qualified_of(rounds[-1][0])[0]


## Le nom d'un tour, d'après son nombre de joueurs : Finale, Demies, Quarts, Huitièmes...
static func round_name(player_count: int) -> String:
	if player_count <= 2:
		return "Finale"
	if player_count <= 4:
		return "Demies"
	if player_count <= 8:
		return "Quarts"
	if player_count <= 16:
		return "Huitièmes"
	return "Seizièmes"
