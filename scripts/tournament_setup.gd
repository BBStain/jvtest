class_name TournamentSetup
extends RefCounted
## Le tournoi (24 octobre 2026) : ses réglages, préparés dans le menu TOURNOI (derrière un code).
## Ils sont gardés dans le navigateur (user://tournoi.cfg) : on les retrouve en revenant sur le jeu.
##
## Le tournoi se joue en phases, dans l'ordre de PHASES. L'entraînement est à part (pas
## d'élimination). Pour les autres phases, chaque match envoie ses meilleurs joueurs
## ("qualifiés") à la phase suivante, et la finale désigne le champion.

## Le code pour entrer dans la préparation du tournoi (juste une porte dans le jeu, pas une vraie sécurité).
const CODE := "SWAG"
const CODE_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SAVE_PATH := "user://tournoi.cfg"
const REGISTERED_CHOICES := [4, 8, 12, 16, 24, 32]

const PHASES := [
	{"id": "entrainement", "name": "Entraînement"},
	{"id": "elimination", "name": "Élimination"},
	{"id": "stage1", "name": "Stage 1"},
	{"id": "stage2", "name": "Stage 2"},
	{"id": "finale", "name": "Finale"},
]
## Les réglages de chaque phase :
##   on = la phase a lieu, players = joueurs par match, lives = vies par joueur,
##   wins = manches à gagner pour gagner le match, qualified = joueurs qualifiés par match,
##   map = la map de la phase (chemin d'une scène de GameSetup.MAPS).
const DEFAULTS := {
	"entrainement": {"on": true, "players": 4, "lives": 3, "wins": 1, "qualified": 1},
	"elimination": {"on": true, "players": 4, "lives": 3, "wins": 1, "qualified": 2},
	"stage1": {"on": true, "players": 2, "lives": 3, "wins": 1, "qualified": 1},
	"stage2": {"on": true, "players": 2, "lives": 3, "wins": 2, "qualified": 1},
	"finale": {"on": true, "players": 2, "lives": 3, "wins": 2, "qualified": 1},
}
## Les colonnes du tableau MODE DE JEU, dans l'ordre.
const FIELDS := ["on", "players", "lives", "wins", "qualified"]
const FIELD_TITLES := ["Phase", "Joueurs / match", "Vies", "Manches à gagner", "Qualifiés / match"]

static var registered := 16      ## joueurs inscrits au tournoi
static var phases := {}          ## id de la phase -> ses réglages (comme DEFAULTS, + "map")
static var unlocked := false     ## le code a été tapé (on ne le redemande pas avant de recharger la page)
static var _loaded := false


## Remet les réglages par défaut (sans les enregistrer).
static func reset() -> void:
	registered = 16
	phases = {}
	for phase in PHASES:
		var settings: Dictionary = DEFAULTS[phase.id].duplicate()
		settings.map = GameSetup.MAPS[0]
		phases[phase.id] = settings
	_loaded = true


## Charge les réglages enregistrés (une seule fois).
static func ensure_loaded() -> void:
	if _loaded:
		return
	reset()
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	registered = int(file.get_value("tournoi", "registered", registered))
	if not registered in REGISTERED_CHOICES:
		registered = 16
	for phase in PHASES:
		var settings: Dictionary = phases[phase.id]
		for key in settings.keys():
			settings[key] = file.get_value(phase.id, key, settings[key])
		if not settings.map in GameSetup.MAPS:
			settings.map = GameSetup.MAPS[0]
		_fix(phase.id)


static func save() -> void:
	var file := ConfigFile.new()
	file.set_value("tournoi", "registered", registered)
	for phase in PHASES:
		for key in phases[phase.id].keys():
			file.set_value(phase.id, key, phases[phase.id][key])
	file.save(SAVE_PATH)


static func check_code(typed: String) -> bool:
	unlocked = unlocked or typed.to_upper() == CODE
	return typed.to_upper() == CODE


## Les valeurs possibles d'un réglage d'une phase. Vide = pas réglable (affiché "–" ou fixé).
static func choices(phase_id: String, field: String) -> Array:
	match field:
		"on":
			return [] if phase_id == "finale" else [true, false]  # la finale a toujours lieu
		"players":
			return [2, 3, 4]
		"lives":
			return [1, 2, 3, 4, 5]
		"wins":
			return [] if phase_id == "entrainement" else [1, 2, 3]
		"qualified":
			if phase_id in ["entrainement", "finale"]:
				return []
			return range(1, int(phases[phase_id].players))
	return []


## Passe un réglage à sa valeur suivante (et revient au début après la dernière).
static func cycle(phase_id: String, field: String) -> void:
	var values := choices(phase_id, field)
	if values.is_empty():
		return
	var settings: Dictionary = phases[phase_id]
	settings[field] = values[(values.find(settings[field]) + 1) % values.size()]
	_fix(phase_id)
	save()


static func cycle_registered() -> void:
	registered = REGISTERED_CHOICES[(REGISTERED_CHOICES.find(registered) + 1) % REGISTERED_CHOICES.size()]
	save()


## Change la map d'une phase (direction = +1 ou -1).
static func cycle_map(phase_id: String, direction: int) -> void:
	var settings: Dictionary = phases[phase_id]
	settings.map = GameSetup.MAPS[posmod(GameSetup.MAPS.find(settings.map) + direction, GameSetup.MAPS.size())]
	save()


## Le texte d'un réglage dans le tableau.
static func value_text(phase_id: String, field: String) -> String:
	var value = phases[phase_id][field]
	if field == "on":
		return "oui" if value else "non"
	if choices(phase_id, field).is_empty():
		return "–"
	return str(value)


## Garde des réglages cohérents (il faut moins de qualifiés que de joueurs dans un match).
static func _fix(phase_id: String) -> void:
	var settings: Dictionary = phases[phase_id]
	settings.qualified = clampi(int(settings.qualified), 1, maxi(int(settings.players) - 1, 1))
	if phase_id == "finale":
		settings.on = true


## Le déroulé du tournoi avec ces réglages, une ligne par phase : combien de matchs, combien
## de qualifiés. Signale quand ça ne tombe pas juste (pas assez de joueurs, plusieurs finales...).
static func summary() -> Array[String]:
	var lines: Array[String] = []
	var count := registered
	lines.append("%d joueurs inscrits" % count)
	for phase in PHASES:
		var settings: Dictionary = phases[phase.id]
		if not settings.on or phase.id == "entrainement":
			continue
		var per_match := int(settings.players)
		if count < 2:
			lines.append("%s : pas assez de joueurs !" % phase.name)
			continue
		var matches := ceili(count / float(per_match))
		var match_word := "duel" if per_match == 2 else "match"
		var text := "%s : %d %s%s" % [phase.name, matches, match_word, "s" if matches > 1 else ""]
		if per_match > 2:
			text += " de %d" % per_match
		if count % per_match != 0:
			text += " (un match à %d)" % (count % per_match)
		if phase.id == "finale":
			if matches > 1:
				text += "  →  trop de joueurs pour une seule finale !"
			else:
				text += "  →  1 champion"
		else:
			var full := count / per_match
			var rest := count % per_match
			count = full * int(settings.qualified) + (mini(int(settings.qualified), rest - 1) if rest > 1 else rest)
			text += "  →  %d qualifié%s" % [count, "s" if count > 1 else ""]
		lines.append(text)
	return lines
