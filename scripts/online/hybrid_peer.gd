class_name HybridPeer
extends MultiplayerPeerExtension
## Le lien réseau du jeu en ligne, utilisé par Online à la place d'un WebRTCMultiplayerPeer.
## Avec chaque joueur, les paquets passent :
##   - en direct entre les navigateurs (WebRTC), quand ça marche : le plus rapide ;
##   - sinon par le serveur des salons (le « relais ») : certains navigateurs, antivirus ou box
##     bloquent la connexion directe, mais laissent toujours passer le serveur.
## Le reste du jeu (les RPC) ne voit pas la différence.

const DIRECT := "direct"
const RELAY := "relais"
const MAX_PACKET := 16000           ## le serveur refuse les messages de plus de 16 Ko

var send_relay: Callable            ## envoie un paquet par le serveur : func(target: int, data: PackedByteArray)

var _rtc := WebRTCMultiplayerPeer.new()
var _id := 0
var _server := false
var _routes := {}                   ## id -> DIRECT ou RELAY : par où passent les paquets de ce joueur
var _linked := {}                   ## id -> true : joueurs reliés (annoncés au jeu)
var _incoming: Array = []           ## paquets reçus, dans l'ordre : [données, de qui, canal, mode]
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _status := CONNECTION_DISCONNECTED
var _refuse := false


func create_server() -> void:
	_id = 1
	_server = true
	_status = CONNECTION_CONNECTED
	_rtc.create_server()
	_hook_rtc()


func create_client(id: int) -> void:
	_id = id
	_server = false
	_status = CONNECTION_CONNECTING
	_rtc.create_client(id)
	_hook_rtc()


func _hook_rtc() -> void:
	_rtc.peer_connected.connect(func(id: int) -> void:
		if _routes.get(id) == DIRECT:
			_link(id))
	_rtc.peer_disconnected.connect(func(id: int) -> void:
		if _routes.get(id) == DIRECT:
			drop(id))


## Essaie de relier ce joueur en direct avec cette connexion WebRTC (déjà initialisée).
func add_direct(id: int, connection: WebRTCPeerConnection) -> void:
	_routes[id] = DIRECT
	_rtc.add_peer(connection, id)


func is_direct(id: int) -> bool:
	return _routes.get(id) == DIRECT


func is_relay(id: int) -> bool:
	return _routes.get(id) == RELAY


## Ce joueur passe par le serveur (la connexion directe a échoué ou n'est pas possible).
func use_relay(id: int) -> void:
	_routes[id] = RELAY
	if _rtc.has_peer(id):
		_rtc.remove_peer(id)
	_link(id)


## Un paquet arrivé par le serveur, envoyé par ce joueur.
func receive_relay(from: int, data: PackedByteArray) -> void:
	if _routes.get(from) == RELAY and _linked.has(from):
		_incoming.append([data, from, 0, TRANSFER_MODE_RELIABLE])


## Le serveur ne répond plus : les joueurs qui passaient par lui sont perdus.
func relay_lost() -> void:
	for id in _routes.keys():
		if _routes[id] == RELAY:
			drop(id)


## Ce joueur n'est plus relié (parti, ou lien perdu).
func drop(id: int) -> void:
	_routes.erase(id)
	if _rtc.has_peer(id):
		_rtc.remove_peer(id)
	if _linked.erase(id):
		peer_disconnected.emit(id)
	if not _server and id == 1:
		_status = CONNECTION_DISCONNECTED


func _link(id: int) -> void:
	if _linked.has(id):
		return
	_linked[id] = true
	if not _server and id == 1:
		_status = CONNECTION_CONNECTED
	peer_connected.emit(id)


# --- MultiplayerPeer ---

func _poll() -> void:
	_rtc.poll()
	while _rtc.get_available_packet_count() > 0:
		var from := _rtc.get_packet_peer()
		var channel := _rtc.get_packet_channel()
		var mode := _rtc.get_packet_mode()
		var data := _rtc.get_packet()
		if _routes.get(from) == DIRECT:
			_incoming.append([data, from, channel, mode])


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var direct: Array[int] = []
	var relay: Array[int] = []
	for id in _linked:
		if _target == 0 or _target == id or (_target < 0 and -_target != id):
			if _routes[id] == DIRECT:
				direct.append(id)
			else:
				relay.append(id)
	for id in direct:
		_rtc.transfer_channel = _channel
		_rtc.transfer_mode = _mode
		_rtc.set_target_peer(id)
		_rtc.put_packet(buffer)
	if send_relay.is_valid():
		if _target == 0 and relay.size() > 1 and relay.size() == _linked.size():
			send_relay.call(0, buffer)  # tout le monde passe par le serveur : un seul envoi pour tous
		else:
			for id in relay:
				send_relay.call(id, buffer)
	return OK


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()[0]


func _get_packet_peer() -> int:
	return _incoming[0][1] if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return _incoming[0][2] if not _incoming.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _incoming[0][3] if not _incoming.is_empty() else TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return MAX_PACKET


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _server


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> ConnectionStatus:
	return _status


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(peer: int, _force: bool) -> void:
	drop(peer)


func _close() -> void:
	_routes.clear()
	_linked.clear()
	_rtc.close()
	_incoming.clear()
	_status = CONNECTION_DISCONNECTED
