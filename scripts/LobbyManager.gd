extends Node

const MAX_PLAYERS := 10
const RESPAWN_BASE: float = 5.0
const RESPAWN_INCREMENT: float = 5.0

var players: Dictionary = {}
var host_id: int = 1
var game_started := false
var supporter_claimed: Dictionary = { 0: false, 1: false }
var player_death_counts: Dictionary = {}

var _dirty := false

signal lobby_updated
signal game_start_requested
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal role_slots_updated(claimed: Dictionary)

func _ready() -> void:
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_init_bullet_sync()
	_init_minion_sync()

func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server() and _dirty and players.size() > 0:
		sync_lobby_state.rpc(players)
		_dirty = false

func register_player_local(peer_id: int, new_player_name: String) -> void:
	var assigned_team := _assign_team()
	var player_info := {
		"name": new_player_name,
		"team": assigned_team,
		"role": "",
		"ready": false
	}
	players[peer_id] = player_info
	print("Player registered: ", new_player_name, " (ID: ", peer_id, ") team: ", assigned_team)
	player_joined.emit(peer_id, player_info)
	_dirty = true
	lobby_updated.emit()

@rpc("any_peer", "call_remote", "reliable")
func register_player(new_player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	register_player_local(id, new_player_name)

# get_remote_sender_id() returns 0 when the server calls an RPC on itself.
# In that case the caller is the server, whose peer id is always 1.
func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1

@rpc("any_peer", "reliable")
func set_team(team_id: int) -> void:
	var id := _sender_id()
	if not players.has(id):
		return
	if game_started:
		return
	players[id].team = team_id
	_dirty = true
	lobby_updated.emit()

@rpc("any_peer", "reliable")
func set_role_ingame(role: int) -> void:
	# role: 0=FIGHTER, 1=SUPPORTER — called after game scene loads
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if not players.has(id):
		return
	var team: int = players[id].team
	if role == 1:
		if supporter_claimed.get(team, false):
			# Slot taken — reject and re-broadcast current state
			_notify_role_rejected.rpc_id(id, supporter_claimed)
			return
		supporter_claimed[team] = true
	players[id].role = role
	_dirty = true
	_sync_role_slots.rpc(supporter_claimed)

@rpc("authority", "call_local", "reliable")
func _sync_role_slots(claimed: Dictionary) -> void:
	supporter_claimed = claimed.duplicate()
	role_slots_updated.emit(supporter_claimed)

@rpc("authority", "reliable")
func _notify_role_rejected(claimed: Dictionary) -> void:
	supporter_claimed = claimed.duplicate()
	role_slots_updated.emit(supporter_claimed)

@rpc("any_peer", "reliable")
func set_ready(ready_state: bool) -> void:
	var id := _sender_id()
	if not players.has(id):
		return
	if game_started:
		return
	players[id].ready = ready_state
	_dirty = true
	lobby_updated.emit()

@rpc("authority", "call_local", "reliable")
func sync_lobby_state(state: Dictionary) -> void:
	players = state.duplicate(true)
	lobby_updated.emit()

@rpc("authority", "reliable")
func load_game_scene(path: String) -> void:
	game_started = true
	game_start_requested.emit()
	get_tree().change_scene_to_file(path)

@rpc("authority", "reliable")
func notify_game_seed(new_seed: int) -> void:
	GameSync.game_seed = new_seed

func start_game(path: String) -> void:
	GameSync.game_seed = randi()
	notify_game_seed.rpc(GameSync.game_seed)
	supporter_claimed = { 0: false, 1: false }
	player_death_counts.clear()
	game_started = true
	game_start_requested.emit()
	load_game_scene.rpc(path)
	get_tree().change_scene_to_file(path)

func increment_death_count(peer_id: int) -> int:
	player_death_counts[peer_id] = player_death_counts.get(peer_id, 0) + 1
	return player_death_counts[peer_id]

func get_respawn_time(peer_id: int) -> float:
	var deaths: int = player_death_counts.get(peer_id, 0)
	return RESPAWN_BASE + (deaths * RESPAWN_INCREMENT)

@rpc("any_peer", "reliable")
func request_start_game() -> void:
	var id := _sender_id()
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
	for p in players.values():
		if not p.ready:
			return false
	return true

func get_players_by_team(team: int) -> Array:
	var result: Array = []
	for id in players:
		if players[id].team == team:
			result.append(id)
	return result

func _on_peer_connected(id: int) -> void:
	print("Lobby: peer connected ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Lobby: peer disconnected ", id)
	players.erase(id)
	_dirty = true
	player_left.emit(id)
	lobby_updated.emit()

func _on_connected_to_server() -> void:
	print("Connected to lobby server")

func _on_server_disconnected() -> void:
	print("Server disconnected")
	players.clear()
	game_started = false
	NetworkManager.close_connection()

var _bullet_scene: PackedScene

func _init_bullet_sync() -> void:
	_bullet_scene = preload("res://scenes/Bullet.tscn")

@rpc("authority", "reliable")
func spawn_bullet_visuals(pos: Vector3, dir: Vector3, damage: float, shooter_team: int) -> void:
	if _bullet_scene == null:
		_bullet_scene = preload("res://scenes/Bullet.tscn")
	var bullet: Node3D = _bullet_scene.instantiate()
	bullet.damage = damage
	bullet.source = "network_sync"
	bullet.shooter_team = shooter_team
	bullet.velocity = dir * 196.0
	get_tree().root.get_child(0).add_child(bullet)
	bullet.global_position = pos

var _minion_scene: PackedScene

func _init_minion_sync() -> void:
	_minion_scene = preload("res://scenes/Minion.tscn")

@rpc("authority", "reliable")
func spawn_minion_visuals(team: int, spawn_pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int) -> void:
	if _minion_scene == null:
		_minion_scene = preload("res://scenes/Minion.tscn")
	var main: Node = get_tree().root.get_node("Main")
	if main == null:
		return
	if not main.has_node("MinionSpawner"):
		return
	var spawner: Node = main.get_node("MinionSpawner")
	spawner.spawn_for_network(team, spawn_pos, waypts, lane_i, minion_id)

@rpc("authority", "reliable")
func kill_minion_visuals(minion_path: NodePath) -> void:
	var main: Node = get_tree().root.get_node("Main")
	if main == null:
		return
	var minion: Node = main.get_node(minion_path)
	if minion != null and minion.has_method("force_die"):
		minion.force_die()

@rpc("any_peer", "reliable")
func report_player_transform(pos: Vector3, rot: Vector3, team: int) -> void:
	var sender: int = _sender_id()
	GameSync.set_player_team(sender, team)
	if multiplayer.is_server():
		broadcast_player_transform.rpc(sender, pos, rot, team)

@rpc("authority", "reliable")
func broadcast_player_transform(peer_id: int, pos: Vector3, rot: Vector3, team: int) -> void:
	GameSync.remote_player_updated.emit(peer_id, pos, rot, team)

@rpc("any_peer", "reliable")
func validate_shot(origin: Vector3, direction: Vector3, damage: float, shooter_team: int, shooter_peer: int) -> void:
	if not multiplayer.is_server():
		return
	
	var hit_result: Dictionary = _raycast_players(origin, direction)
	
	if hit_result.has("peer_id"):
		var target_peer: int = hit_result.peer_id
		var new_hp: float = GameSync.damage_player(target_peer, damage, shooter_team)
		apply_player_damage.rpc(target_peer, new_hp)
	elif hit_result.has("minion_path"):
		var main: Node = get_tree().root.get_node("Main")
		if main != null:
			var minion: Node = main.get_node(hit_result.minion_path)
			if minion != null and minion.has_method("take_damage"):
				minion.take_damage(damage, "player", shooter_team)
	
	spawn_bullet_visuals.rpc(origin, direction, damage, shooter_team)

@rpc("authority", "reliable")
func apply_player_damage(peer_id: int, new_health: float) -> void:
	GameSync.set_player_health(peer_id, new_health)

func _raycast_players(origin: Vector3, direction: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if space == null:
		return {}
	var to: Vector3 = origin + direction * 500.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return {}
	var collider: Object = result.collider
	# CollisionShape3D is a child — walk up to the real node
	var node: Node = collider if collider is Node else null
	if node == null:
		return {}
	# Check if this is (or belongs to) a player CharacterBody3D
	var check: Node = node
	while check != null:
		if check.has_method("take_damage") and check.has("player_team"):
			var peer_id: int = _find_peer_id_from_node(check)
			if peer_id > 0:
				return {"peer_id": peer_id}
		check = check.get_parent() if check != get_tree().root else null
	# Check for minion
	if node.has_method("take_damage"):
		return {"minion_path": node.get_path()}
	return {}

func _find_peer_id_from_node(node: Node) -> int:
	# Players are named "FPSPlayer_{peer_id}"
	var n: String = node.name
	if n.begins_with("FPSPlayer_"):
		var id_str: String = n.substr(10)
		if id_str.is_valid_int():
			return id_str.to_int()
	return -1
