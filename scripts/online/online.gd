extends Node
## Le jeu en ligne (chargé tout le temps, sous le nom « Online »).
##
## 1. Le salon : l'hôte crée un salon avec un code de 4 lettres, les copains le rejoignent avec
##    ce code. Le petit serveur des salons (dossier server/) les met en contact, puis chaque
##    copain est relié directement au navigateur de l'hôte (WebRTC). Si la connexion directe
##    est bloquée (navigateur, antivirus, box), ce copain passe par le serveur (voir HybridPeer).
## 2. La partie : l'hôte fait tourner la vraie partie, exactement comme en local. Chaque copain
##    envoie ses touches à l'hôte à chaque frame, et l'hôte renvoie à tout le monde l'état du
##    jeu (position des joueurs, attaques, vies...) que les copains affichent.
##
## Un seul joueur par ordinateur en ligne. L'hôte est toujours le joueur 1 (id réseau 1).

signal changed                      ## le salon a changé (joueurs, persos, prêts, map, message)
signal closed(reason: String)       ## la session est finie (hôte parti, connexion perdue...)

enum Status { OFF, CONNECTING, LOBBY, PLAYING }

const MAX_PLAYERS := 4
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"  ## pas de I ni de O (on les confond avec 1 et 0)
const CONNECT_TIMEOUT := 15.0       ## secondes pour se relier à l'hôte avant d'abandonner
const RELAY_AFTER := 5.0            ## secondes d'essai en direct avant de passer par le serveur
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var status := Status.OFF
var code := ""                      ## le code du salon
var is_host := false
var my_id := 0                      ## mon numéro réseau (1 = l'hôte)
var message := ""                   ## ce qu'il faut afficher (connexion en cours, erreur...)
var players: Array = []             ## le salon, dans l'ordre J1, J2... : {"id", "character", "ready"}
var map_index := 0
var local_device := {}              ## la manette ou le côté du clavier de ce joueur
var game: Node                      ## la partie en cours (Game), qui reçoit touches et état

var _ws: WebSocketPeer
var _ws_was_open := false
var _peer: HybridPeer
var _connections := {}              ## id réseau -> WebRTCPeerConnection (essai en direct)
var _connect_time := 0.0
var _host_retries := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # le réseau tourne même quand le menu pause est ouvert
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_host)
	multiplayer.server_disconnected.connect(_on_host_lost)


func is_online() -> bool:
	return status != Status.OFF


## Mon numéro de joueur (0 = J1) dans le salon, ou -1.
func my_index() -> int:
	return index_of(my_id)


func index_of(peer_id: int) -> int:
	for i in players.size():
		if players[i].id == peer_id:
			return i
	return -1


# --- Créer, rejoindre, quitter ---

## Crée un salon avec un code tiré au hasard.
func host() -> void:
	_reset()
	is_host = true
	code = _random_code()
	_open_socket("/salon/%s?hote=1" % code, "Création du salon…")


## Rejoint le salon d'un copain.
func join(room_code: String) -> void:
	_reset()
	is_host = false
	code = room_code.to_upper()
	_open_socket("/salon/%s" % code, "Connexion au salon %s…" % code)


## Quitte le salon (ou la partie en ligne).
func leave() -> void:
	_reset()
	changed.emit()


func _reset() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_ws_was_open = false
	for id in _connections:
		_connections[id].close()
	_connections.clear()
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	status = Status.OFF
	players = []
	map_index = 0
	my_id = 0
	message = ""
	game = null


func _end(reason: String) -> void:
	var was_playing := status == Status.PLAYING
	_reset()
	message = reason
	closed.emit(reason)
	changed.emit()
	if was_playing:
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(MENU_SCENE)


func _random_code() -> String:
	var letters := ""
	for i in 4:
		letters += CODE_LETTERS[randi() % CODE_LETTERS.length()]
	return letters


# --- Le serveur des salons (WebSocket) ---

func _open_socket(path: String, waiting_text: String) -> void:
	status = Status.CONNECTING
	message = waiting_text
	_connect_time = 0.0
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(OnlineConfig.server_url() + path)
	if err != OK:
		_end("Impossible de joindre le serveur des salons")
		return
	changed.emit()


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_ws_was_open = true
		while _ws.get_available_packet_count() > 0:
			var packet := _ws.get_packet()
			if not _ws.was_string_packet():
				# Un paquet du jeu passé par le serveur : [qui l'envoie, données...]
				if _peer != null and packet.size() > 1:
					_peer.receive_relay(packet[0], packet.slice(1))
				continue
			var data = JSON.parse_string(packet.get_string_from_utf8())
			if data is Dictionary:
				_on_server_message(data)
				if _ws == null:
					return
	elif state == WebSocketPeer.STATE_CLOSED:
		_ws = null
		# Pendant la partie, ceux qui sont reliés en direct n'ont plus besoin du serveur.
		if status == Status.CONNECTING or status == Status.LOBBY or (not is_host and _peer != null and _peer.is_relay(1)):
			_end("Connexion au serveur des salons perdue" if _ws_was_open else "Impossible de joindre le serveur des salons")
		elif _peer != null:
			_peer.relay_lost()
		return
	if status == Status.CONNECTING:
		_connect_time += delta
		if not is_host and _peer != null and _peer.is_direct(1) and _connect_time > RELAY_AFTER:
			print("En ligne : la connexion directe ne passe pas, on passe par le serveur")
			_ask_relay(1)
		if _connect_time > CONNECT_TIMEOUT:
			_end("Impossible de se relier à l'hôte (sa box ou la tienne bloque peut-être la connexion)")


func _on_server_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"bienvenue":
			_on_welcome(int(data.get("id", 0)))
		"arrivee":
			if is_host:
				_on_player_arrived(int(data.get("id", 0)))
		"depart":
			# En direct, la connexion directe le signale elle-même (peer_disconnected).
			var id := int(data.get("id", 0))
			if _peer != null and _peer.is_relay(id):
				_peer.drop(id)
		"signal":
			_on_signal(int(data.get("de", 0)), data.get("data", {}))
		"erreur":
			var reason: String = data.get("raison", "")
			if reason == "code_pris" and is_host and _host_retries < 5:
				_host_retries += 1
				host()
				return
			_end({
				"introuvable": "Aucun salon avec le code %s" % code,
				"plein": "Le salon %s est plein (4 joueurs)" % code,
			}.get(reason, "Le serveur a refusé : %s" % reason))
		"ferme":
			_end("L'hôte a fermé le salon")


func _send_to_server(data: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))


## Un paquet du jeu à faire passer par le serveur (0 = à tous les autres) : [à qui, données...]
func _send_relay(target: int, data: PackedByteArray) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var packet := PackedByteArray([target])
		packet.append_array(data)
		_ws.send(packet)


func _on_welcome(id: int) -> void:
	my_id = id
	_peer = HybridPeer.new()
	_peer.send_relay = _send_relay
	if is_host:
		_host_retries = 0
		_peer.create_server()
		multiplayer.multiplayer_peer = _peer
		status = Status.LOBBY
		message = ""
		players = [{"id": 1, "character": 0, "ready": false}]
		print("En ligne : salon %s créé" % code)
	else:
		_peer.create_client(id)
		multiplayer.multiplayer_peer = _peer
		message = "Connexion à l'hôte…"
		if not _add_connection(1):
			_ask_relay(1)
	changed.emit()


## (hôte) Un copain arrive dans le salon : on prépare la connexion directe et on lui fait une offre.
func _on_player_arrived(id: int) -> void:
	if status == Status.PLAYING:
		_send_to_server({"type": "signal", "a": id, "data": {"refus": "Une partie est déjà en cours dans ce salon"}})
		return
	if _add_connection(id):
		_connections[id].create_offer()
	else:
		_ask_relay(id)


## La connexion directe avec ce joueur ne marche pas : on prévient l'autre et on passe par le serveur.
func _ask_relay(id: int) -> void:
	_send_to_server({"type": "signal", "a": id, "data": {"relais": true}})
	_use_relay(id)


func _use_relay(id: int) -> void:
	if _peer == null:
		return
	_peer.use_relay(id)
	if _connections.has(id):
		_connections[id].close()
		_connections.erase(id)


func _add_connection(id: int) -> bool:
	var connection := WebRTCPeerConnection.new()
	# Si le navigateur refuse les serveurs STUN, on essaie sans (ça suffit souvent sur le même réseau).
	if connection.initialize({"iceServers": OnlineConfig.ICE_SERVERS}) != OK and connection.initialize({}) != OK:
		print("En ligne : pas de connexion directe possible (%s), on passe par le serveur" % _webrtc_problem())
		return false
	connection.session_description_created.connect(func(type: String, sdp: String) -> void:
		connection.set_local_description(type, sdp)
		_send_to_server({"type": "signal", "a": id, "data": {"type": type, "sdp": sdp}}))
	connection.ice_candidate_created.connect(func(media: String, index: int, candidate: String) -> void:
		_send_to_server({"type": "signal", "a": id, "data": {"media": media, "index": index, "candidate": candidate}}))
	_peer.add_direct(id, connection)
	_connections[id] = connection
	return true


## Pourquoi le navigateur refuse la connexion directe (WebRTC), pour la console.
func _webrtc_problem() -> String:
	if not OS.has_feature("web"):
		return "hors navigateur"
	return str(JavaScriptBridge.eval("""(function () {
		if (typeof RTCPeerConnection === 'undefined') return 'WebRTC désactivé';
		try { new RTCPeerConnection().close(); return 'erreur inconnue'; }
		catch (e) { return String((e && e.message) || e); }
	})()"""))


func _on_signal(from: int, data) -> void:
	if not data is Dictionary:
		return
	if data.has("refus"):
		_end(str(data.refus))
		return
	if data.has("relais"):
		if is_host and status != Status.LOBBY:
			return
		print("En ligne : le joueur %d passe par le serveur" % from)
		_use_relay(from)
		return
	var connection: WebRTCPeerConnection = _connections.get(from)
	if connection == null:
		return
	if data.has("sdp"):
		connection.set_remote_description(str(data.get("type", "")), str(data.sdp))
	elif data.has("candidate"):
		connection.add_ice_candidate(str(data.get("media", "")), int(data.get("index", 0)), str(data.candidate))


# --- Connexions directes ---

func _on_peer_connected(id: int) -> void:
	if is_host and status == Status.LOBBY and index_of(id) == -1 and players.size() < MAX_PLAYERS:
		players.append({"id": id, "character": 0, "ready": false})
		_share_lobby()


func _on_connected_to_host() -> void:
	if not is_host:
		status = Status.LOBBY
		message = ""
		print("En ligne : relié à l'hôte du salon %s" % code)
		changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	_connections.erase(id)
	var index := index_of(id)
	if index == -1:
		return
	if status == Status.PLAYING:
		if game != null:
			game.on_online_player_left(index)
		return
	players.remove_at(index)
	_share_lobby()


func _on_host_lost() -> void:
	_end("L'hôte a quitté la partie")


# --- Le salon : persos, prêts, map ---

## Mon choix de perso et si je suis prêt (envoyé à l'hôte, qui le transmet à tous).
func choose(character: int, ready: bool) -> void:
	if is_host:
		_apply_choice(1, character, ready)
	else:
		# On l'affiche tout de suite, sans attendre que l'hôte renvoie le salon : sinon un appui
		# rapide (droite puis A) repartirait de l'ancien perso.
		var me := my_index()
		if me != -1:
			players[me].character = character
			players[me].ready = ready
			changed.emit()
		_choice_to_host.rpc_id(1, character, ready)


@rpc("any_peer", "call_remote", "reliable")
func _choice_to_host(character: int, ready: bool) -> void:
	if is_host:
		_apply_choice(multiplayer.get_remote_sender_id(), character, ready)


func _apply_choice(id: int, character: int, ready: bool) -> void:
	var index := index_of(id)
	if index == -1:
		return
	players[index].character = clampi(character, 0, GameSetup.CHARACTERS.size() - 1)
	players[index].ready = ready
	_share_lobby()


## (hôte) La map choisie.
func choose_map(index: int) -> void:
	if is_host:
		map_index = posmod(index, GameSetup.MAPS.size())
		_share_lobby()


func all_ready() -> bool:
	if players.size() < 2:
		return false
	for p in players:
		if not p.ready:
			return false
	return true


func _share_lobby() -> void:
	_lobby_from_host.rpc(players, map_index)


@rpc("authority", "call_local", "reliable")
func _lobby_from_host(new_players: Array, new_map: int) -> void:
	players = new_players
	map_index = new_map
	changed.emit()


## (hôte) Tout le monde est prêt : on lance la partie chez tout le monde.
func start_game() -> void:
	if is_host and all_ready():
		_start_from_host.rpc(players, map_index, GameSetup.lives)


@rpc("authority", "call_local", "reliable")
func _start_from_host(final_players: Array, map: int, lives: int) -> void:
	players = final_players
	map_index = map
	status = Status.PLAYING
	GameSetup.player_devices = []
	GameSetup.player_characters = []
	for i in players.size():
		GameSetup.player_devices.append([local_device] if players[i].id == my_id else [])
		GameSetup.player_characters.append(GameSetup.CHARACTERS[players[i].character])
	GameSetup.map_path = GameSetup.MAPS[map_index]
	GameSetup.lives = lives
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## (hôte) Rejouer avec les mêmes joueurs.
func restart() -> void:
	if is_host:
		_restart_from_host.rpc()


@rpc("authority", "call_local", "reliable")
func _restart_from_host() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## (hôte) Revenir au salon (pour changer de perso ou de map).
func back_to_lobby() -> void:
	if is_host:
		for p in players:
			p.ready = false
		_lobby_from_host.rpc(players, map_index)
		_back_from_host.rpc()


@rpc("authority", "call_local", "reliable")
func _back_from_host() -> void:
	status = Status.LOBBY
	game = null
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Pendant la partie ---

## (copain) Mes touches de cette frame, envoyées à l'hôte.
func send_input(data: Dictionary) -> void:
	if _connected():
		_input_to_host.rpc_id(1, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _input_to_host(data: Dictionary) -> void:
	if is_host and game != null:
		game.receive_online_input(index_of(multiplayer.get_remote_sender_id()), data)


## (hôte) L'état du jeu de cette frame, envoyé à tous les copains.
func send_state(data: Array) -> void:
	if _connected():
		_state_from_host.rpc(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _state_from_host(data: Array) -> void:
	if game != null:
		game.receive_online_state(data)


## (hôte) Un effet visuel (marque de choc, explosion) à afficher chez tous les copains.
func send_effect(data: Dictionary) -> void:
	if _connected():
		_effect_from_host.rpc(data)


## Relié aux autres joueurs (sinon, rien à envoyer).
func _connected() -> bool:
	return _peer != null and multiplayer.multiplayer_peer == _peer


@rpc("authority", "call_remote", "reliable")
func _effect_from_host(data: Dictionary) -> void:
	if game != null:
		game.spawn_online_effect(data)
