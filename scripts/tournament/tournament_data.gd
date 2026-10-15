class_name TournamentData
extends RefCounted
## Un tournoi en duels : les joueurs inscrits (un nom et une couleur chacun), leur place dans
## le 1er tour (tirée au sort avec ALÉATOIRE), et les réglages (map, nombre de vies).
## Le tournoi est gardé dans le navigateur (user://tournoi.json) : on le retrouve en revenant sur le jeu.
##
## L'arbre est fait de tours ; chaque tour est une liste de matchs (des duels). Les tours suivants
## reçoivent les vainqueurs des matchs d'avant, jusqu'à la finale. Avec un nombre impair de
## joueurs, un match n'a qu'un joueur : il passe d'office.

const CODE := "SWAG"  ## le code pour entrer (juste une porte dans le jeu, pas une vraie sécurité)
const CODE_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SAVE_PATH := "user://tournoi.json"
const MAX_PLAYERS := 32
const MAX_NAME := 12
const PER_MATCH := 2
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
var map: String = GameSetup.MAPS[0]


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
	if str(data.get("map", "")) in GameSetup.MAPS:
		tournament.map = data.map
	return tournament


static func check_code(typed: String) -> bool:
	unlocked = unlocked or typed.to_upper() == CODE
	return unlocked


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"players": players, "seeding": seeding, "lives": lives, "map": map}))


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
	return true


func remove_player(index: int) -> void:
	players.remove_at(index)
	seeding = []


## La couleur proposée au prochain inscrit : la première pas encore prise (après "after").
func next_free_color(after := -1) -> int:
	for step in range(1, COLORS.size() + 1):
		var color := posmod(after + step, COLORS.size())
		if not players.any(func(p: Dictionary) -> bool: return p.color == color):
			return color
	return posmod(after + 1, COLORS.size())


## Tire au sort la place de chaque joueur dans le 1er tour.
func shuffle() -> void:
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


## La taille de chaque match du 1er tour (au plus juste : des duels, et au plus un joueur seul).
func first_round_sizes() -> Array[int]:
	var sizes: Array[int] = []
	var count := ceili(players.size() / float(PER_MATCH))
	for m in count:
		sizes.append(players.size() / count + (1 if m < players.size() % count else 0))
	return sizes


## L'arbre : une liste de tours, chaque tour une liste de matchs.
## Un match = {"number": numéro (M1, M2... sur tout le tournoi),
##             "slots": une case par joueur : au 1er tour l'index du joueur (-1 = pas encore tiré),
##                      ensuite -1 (on ne sait pas encore qui gagne),
##             "sources": les numéros des matchs dont les vainqueurs viennent ici}.
func bracket() -> Array:
	var rounds := []
	if players.size() < 2:
		return rounds
	var number := 1
	var first := []
	var place := 0
	for size in first_round_sizes():
		var slots := []
		for s in size:
			slots.append(seeding[place] if is_seeded() else -1)
			place += 1
		first.append({"number": number, "slots": slots, "sources": []})
		number += 1
	rounds.append(first)
	while rounds[-1].size() > 1:
		var previous: Array = rounds[-1]
		var next := []
		for m in range(0, previous.size(), PER_MATCH):
			var sources := []
			for game in previous.slice(m, m + PER_MATCH):
				sources.append(game.number)
			var slots := []
			slots.resize(sources.size())
			slots.fill(-1)
			next.append({"number": number, "slots": slots, "sources": sources})
			number += 1
		rounds.append(next)
	return rounds


## Le nom d'un tour, d'après son nombre de matchs : Finale, Demies, Quarts, Huitièmes...
static func round_name(match_count: int) -> String:
	if match_count <= 1:
		return "Finale"
	if match_count == 2:
		return "Demies"
	if match_count <= 4:
		return "Quarts"
	if match_count <= 8:
		return "Huitièmes"
	return "Seizièmes"
