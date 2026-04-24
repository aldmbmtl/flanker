extends Node

const ROLES := ["Tank", "DPS", "Support", "Sniper", "Flanker"]
const MAX_PLAYERS := 10

var players: Dictionary = {}
var host_id: int = 1
var game_started := false

signal lobby_updated
signal game_start_requested
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)

func _ready() -> void:
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		sync_lobby_state.rpc(players)

@rpc("any_peer", "reliable")
func register_player(new_player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	
	var assigned_team := _assign_team()
	var player_info := {
		"name": new_player_name,
		"team": assigned_team,
		"role": "",
		"ready": false
	}
	players[id] = player_info
	
	print("Player registered: ", new_player_name, " (ID: ", id, ") team: ", assigned_team)
	player_joined.emit(id, player_info)
	lobby_updated.emit()

@rpc("any_peer", "reliable")
func set_team(team_id: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	if game_started:
		return
	players[id].team = team_id
	lobby_updated.emit()

@rpc("any_peer", "reliable")
func set_role(role_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	if game_started:
		return
	
	if role_name == "" or ROLES.has(role_name):
		players[id].role = role_name
		lobby_updated.emit()

@rpc("any_peer", "reliable")
func set_ready(ready_state: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	if game_started:
		return
	players[id].ready = ready_state
	lobby_updated.emit()

@rpc("authority", "call_local", "reliable")
func sync_lobby_state(state: Dictionary) -> void:
	players = state.duplicate(true)
	lobby_updated.emit()

@rpc("authority", "call_local", "reliable")
func load_game_scene(path: String) -> void:
	game_started = true
	var scene := load(path)
	get_tree().change_scene_to_file(path)

@rpc("any_peer", "reliable")
func request_start_game() -> void:
	var id := multiplayer.get_remote_sender_id()
	if id != host_id:
		return
	game_start_requested.emit()

func _assign_team() -> int:
	var blue_count := 0
	var red_count := 0
	for p in players.values():
		if p.team == 0:
			blue_count += 1
		else:
			red_count += 1
	return 0 if blue_count <= red_count else 1

func can_start_game() -> bool:
	if players.is_empty():
		return false
	var ready_count := 0
	for p in players.values():
		if p.ready and p.role != "":
			ready_count += 1
	return ready_count >= 2

func get_players_by_team(team: int) -> Array:
	var result: Array = []
	for id in players:
		if players[id].team == team:
			result.append(id)
	return result

func _on_peer_connected(id: int) -> void:
	print("Lobby: peer connected ", id)
	if players.is_empty():
		host_id = id
		print("Host assigned to peer ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Lobby: peer disconnected ", id)
	players.erase(id)
	if id == host_id and not players.is_empty():
		host_id = players.keys()[0]
	player_left.emit(id)
	lobby_updated.emit()

func _on_connected_to_server() -> void:
	print("Connected to lobby server")

func _on_server_disconnected() -> void:
	print("Server disconnected")
	players.clear()
	game_started = false
	NetworkManager.close_connection()