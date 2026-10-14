class_name TournamentData
extends RefCounted
## Un tournoi : son nom, son format, ses joueurs (des pseudos), et l'arbre qu'on en tire.
## Le tournoi en cours est gardé dans le navigateur (user://tournoi.json) : on le retrouve
## en revenant sur le jeu.
##
## L'arbre est fait de tours ; chaque tour est une liste de matchs. Au 1er tour, les joueurs
## sont répartis dans l'ordre de la liste (MÉLANGER change l'ordre). Les tours suivants
## reçoivent les qualifiés des matchs d'avant, dans l'ordre, jusqu'à la finale (1 seul match,
## 1 champion). Un match d'un seul joueur = il passe d'office.

const CODE := "SWAG"  ## le code pour entrer (juste une porte dans le jeu, pas une vraie sécurité)
const CODE_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SAVE_PATH := "user://tournoi.json"
const MAX_PLAYERS := 32
const MAX_NAME := 14
## Les formats : joueurs par match, qualifiés par match (sauf en finale : 1 champion).
const FORMATS := [
	{"name": "Duels", "detail": "1 contre 1, le gagnant passe", "players": 2, "qualified": 1},
	{"name": "Mêlées à 4", "detail": "4 par match, les 2 premiers passent", "players": 4, "qualified": 2},
]

static var unlocked := false     ## le code a été tapé (on ne le redemande pas avant de recharger la page)

var name := "Tournoi du swag"
var format := 0                  ## index dans FORMATS
var players: Array[String] = []


## Le tournoi enregistré, ou null s'il n'y en a pas.
static func load_saved() -> TournamentData:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return null
	var tournament := TournamentData.new()
	tournament.name = str(data.get("name", tournament.name)).left(MAX_NAME * 2)
	tournament.format = clampi(int(data.get("format", 0)), 0, FORMATS.size() - 1)
	for player in data.get("players", []):
		if tournament.players.size() < MAX_PLAYERS:
			tournament.players.append(str(player).left(MAX_NAME))
	return tournament


static func check_code(typed: String) -> bool:
	unlocked = unlocked or typed.to_upper() == CODE
	return unlocked


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"name": name, "format": format, "players": players}))


## Ajoute un joueur (pas de doublon, pas de nom vide). Renvoie false s'il n'a pas été ajouté.
func add_player(player_name: String) -> bool:
	player_name = player_name.strip_edges().left(MAX_NAME)
	if player_name == "" or player_name in players or players.size() >= MAX_PLAYERS:
		return false
	players.append(player_name)
	return true


func shuffle() -> void:
	players.shuffle()


## L'arbre du tournoi : une liste de tours, chaque tour une liste de matchs.
## Un match = {"number": numéro (M1, M2... sur tout le tournoi),
##             "slots": une case par joueur : son nom au 1er tour, sinon d'où il vient ("Vainqueur M1"),
##             "sources": les numéros des matchs qui envoient leurs qualifiés ici,
##             "qualified": combien passent au tour suivant (0 en finale)}.
func bracket() -> Array:
	var rounds := []
	if players.size() < 2:
		return rounds
	var per_match: int = FORMATS[format].players
	var per_qualified: int = FORMATS[format].qualified
	var number := 1
	# Ce qui entre dans le tour : [texte de la case, numéro du match d'où il vient (0 = 1er tour)]
	var entrants := []
	for player in players:
		entrants.append([player, 0])
	while true:
		var count := ceili(entrants.size() / float(per_match))
		var final := count == 1
		var matches := []
		var next := []
		var start := 0
		for m in count:
			# Répartit au plus juste : des matchs de tailles proches (pas de match à 4 puis un à 1).
			var size := entrants.size() / count + (1 if m < entrants.size() % count else 0)
			var game := {"number": number, "slots": [], "sources": [], "qualified": 0}
			for e in entrants.slice(start, start + size):
				game.slots.append(e[0])
				if e[1] != 0 and not e[1] in game.sources:
					game.sources.append(e[1])
			start += size
			if not final:
				game.qualified = size if size == 1 else mini(per_qualified, size - 1)
				for q in game.qualified:
					next.append([_qualified_text(number, q, game.qualified), number])
			matches.append(game)
			number += 1
		rounds.append(matches)
		if final:
			break
		entrants = next
	return rounds


## Le nom d'un tour, en partant de la fin : Finale, Demi-finales, Quarts...
static func round_name(index: int, round_count: int) -> String:
	match round_count - 1 - index:
		0:
			return "Finale"
		1:
			return "Demi-finales"
		2:
			return "Quarts"
	return "Tour %d" % (index + 1)


func _qualified_text(number: int, rank: int, total: int) -> String:
	if total == 1:
		return "Vainqueur M%d" % number
	return "%s M%d" % ["1er" if rank == 0 else "%de" % (rank + 1), number]
