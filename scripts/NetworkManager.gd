extends Node

signal connection_failed
signal server_disconnected
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connected_to_server

const DEFAULT_PORT := 8910
const MAX_CLIENTS := 10

var _peer: ENetMultiplayerPeer
var _is_host := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func is_host() -> bool:
	return _is_host

func start_host(port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("*")
	var err: int = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to start server on port %d: %s" % [port, str(err)])
		return err
	
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_is_host = true
	
	print("Host started on port %d" % port)
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(address, port)
	if err != OK:
		push_error("Failed to connect to %s:%d: %s" % [address, port, str(err)])
		return err
	
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_is_host = false
	
	return OK

func close_connection() -> void:
	if _peer:
		_peer.close()
		_peer = null
		multiplayer.multiplayer_peer = null
	_is_host = false

func _on_peer_connected(id: int) -> void:
	var addr := ""
	if _peer and _peer.get_peer(id):
		addr = " from %s:%d" % [_peer.get_peer(id).get_remote_address(), _peer.get_peer(id).get_remote_port()]
	print("[NET] Connection request accepted — peer_id=%d%s" % [id, addr])
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	peer_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("Connected to server")
	connected_to_server.emit()

func _on_connection_failed() -> void:
	print("Connection failed")
	connection_failed.emit()