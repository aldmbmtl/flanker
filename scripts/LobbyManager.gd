extends Node

const MAX_PLAYERS := 10
const RESPAWN_BASE: float = 10.0
const RESPAWN_INCREMENT: float = 0.0

var players: Dictionary = {}
var host_id: int = 1
var game_started := false
var supporter_claimed: Dictionary = { 0: false, 1: false }
var player_death_counts: Dictionary = {}
var ai_supporter_teams: Array = []  # teams where an AI Supporter was spawned

var _dirty := false
var _roles_pending: int = 0

signal lobby_updated
signal game_start_requested
signal kicked_from_server
signal player_left(id: int)
signal role_slots_updated(claimed: Dictionary)
signal all_roles_confirmed
signal human_supporter_claimed(team: int)
signal item_spawned(item_type: String, team: int)
signal tower_despawned(item_type: String, team: int, tower_name: String)

func _ready() -> void:
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_init_bullet_sync()
	_init_minion_sync()
	GameSync.player_respawned.connect(_on_game_sync_player_respawned)
	TeamLives.game_over.connect(_on_team_lives_game_over)

func _on_game_sync_player_respawned(peer_id: int, spawn_pos: Vector3) -> void:
	if multiplayer.is_server():
		notify_player_respawned.rpc(peer_id, spawn_pos)

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
		"role": -1,
		"ready": false,
		"avatar_char": ""
	}
	players[peer_id] = player_info
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
		human_supporter_claimed.emit(team)
	players[id].role = role
	_dirty = true
	_sync_role_slots.rpc(supporter_claimed)
	_roles_pending -= 1
	if _roles_pending <= 0:
		_roles_pending = 0
		all_roles_confirmed.emit()

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

@rpc("authority", "call_local", "reliable")
func notify_game_seed(new_seed: int, new_time_seed: int) -> void:
	GameSync.game_seed = new_seed
	GameSync.time_seed = new_time_seed
	LaneData.regenerate_for_new_game()

func start_game(path: String, map_seed: int = 0, time_seed: int = -1) -> void:
	var s: int = map_seed if map_seed > 0 else randi()
	if s == 0:
		s = 1  # never send seed=0; TerrainGenerator fallback path means client diverges
	notify_game_seed.rpc(s, time_seed)  # call_local — sets GameSync on server too
	supporter_claimed = { 0: false, 1: false }
	player_death_counts.clear()
	ai_supporter_teams.clear()
	_roles_pending = players.size()
	LevelSystem.clear_all()
	# Re-register all connected peers for the new match
	for pid in players.keys():
		LevelSystem.register_peer(pid)
	game_started = true
	game_start_requested.emit()
	load_game_scene.rpc(path)
	get_tree().change_scene_to_file(path)

const RESPAWN_CAP: float = 60.0

func increment_death_count(peer_id: int) -> int:
	player_death_counts[peer_id] = player_death_counts.get(peer_id, 0) + 1
	var new_count: int = player_death_counts[peer_id]
	# Broadcast updated death count to all clients so their local respawn timer is accurate
	sync_death_count.rpc(peer_id, new_count)
	return new_count

func get_respawn_time(peer_id: int) -> float:
	var deaths: int = player_death_counts.get(peer_id, 0)
	var t: float = RESPAWN_BASE + (deaths * RESPAWN_INCREMENT)
	return min(t, RESPAWN_CAP)

@rpc("authority", "reliable")
func sync_death_count(peer_id: int, count: int) -> void:
	player_death_counts[peer_id] = count

@rpc("any_peer", "reliable")
func register_player_team(peer_id: int, team: int) -> void:
	if not multiplayer.is_server():
		return
	GameSync.set_player_team(peer_id, team)

@rpc("any_peer", "reliable")
func report_ammo(reserve: int, weapon_type: String) -> void:
	if not multiplayer.is_server():
		return
	GameSync.set_player_reserve_ammo(_sender_id(), reserve, weapon_type)

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
	# Register in LevelSystem so XP tracking is ready when game starts
	LevelSystem.register_peer(id)

func _on_peer_disconnected(id: int) -> void:
	print("Lobby: peer disconnected ", id)
	# If roles haven't all been confirmed yet and this peer hadn't submitted,
	# decrement so the server doesn't wait forever.
	if game_started and _roles_pending > 0:
		var info: Dictionary = players.get(id, {})
		if not info.has("role") or info.get("role", "") == "":
			_roles_pending -= 1
			if _roles_pending <= 0:
				_roles_pending = 0
				all_roles_confirmed.emit()
	players.erase(id)
	_dirty = true
	player_left.emit(id)
	lobby_updated.emit()
	LevelSystem.clear_peer(id)

func _on_connected_to_server() -> void:
	print("Connected to lobby server")

func _on_server_disconnected() -> void:
	print("Server disconnected")
	# Close the peer immediately so no in-flight RPCs hit a dead connection
	NetworkManager.close_connection()
	players.clear()
	game_started = false
	kicked_from_server.emit()

var _bullet_scene: PackedScene
var _rocket_scene: PackedScene

func _init_bullet_sync() -> void:
	_bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")
	_rocket_scene = preload("res://scenes/projectiles/Rocket.tscn")

@rpc("authority", "call_remote", "unreliable_ordered")
func spawn_bullet_visuals(pos: Vector3, dir: Vector3, damage: float, shooter_team: int, shooter_peer_id: int = -1, projectile_type: String = "bullet") -> void:
	if projectile_type == "rocket":
		if _rocket_scene == null:
			_rocket_scene = preload("res://scenes/projectiles/Rocket.tscn")
		var rocket: Node3D = _rocket_scene.instantiate()
		rocket.damage          = damage
		rocket.source          = "rocket"
		rocket.shooter_team    = shooter_team
		rocket.shooter_peer_id = shooter_peer_id
		rocket.velocity        = dir * 0.1   # initial speed, Rocket.gd accelerates from here
		get_tree().root.get_child(0).add_child(rocket)
		rocket.global_position = pos
		return
	if _bullet_scene == null:
		_bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")
	var bullet: Node3D = _bullet_scene.instantiate()
	bullet.damage = damage
	bullet.source = "network_sync"
	bullet.shooter_team = shooter_team
	bullet.set("shooter_peer_id", shooter_peer_id)
	bullet.velocity = dir * 196.0
	get_tree().root.get_child(0).add_child(bullet)
	bullet.global_position = pos
	var main: Node = get_tree().root.get_node("Main")
	if main.has_method("_on_bullet_hit_something") and shooter_peer_id == multiplayer.get_unique_id():
		bullet.hit_something.connect(main._on_bullet_hit_something)

var _minion_scene: PackedScene

func _init_minion_sync() -> void:
	_minion_scene = preload("res://scenes/minions/Minion.tscn")

@rpc("authority", "call_remote", "reliable")
func spawn_minion_visuals(team: int, spawn_pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int) -> void:
	if _minion_scene == null:
		_minion_scene = preload("res://scenes/minions/Minion.tscn")

	var main: Node = get_tree().root.get_node("Main")
	if main == null:
		return
	if not main.has_node("MinionSpawner"):
		return
	var spawner: Node = main.get_node("MinionSpawner")
	spawner.spawn_for_network(team, spawn_pos, waypts, lane_i, minion_id)

@rpc("authority", "call_remote", "reliable")
func kill_minion_visuals(minion_id: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var spawner: Node = main.get_node_or_null("MinionSpawner")
	if spawner != null and spawner.has_method("kill_minion_by_id"):
		spawner.kill_minion_by_id(minion_id)
	else:
		# Fallback: node-path lookup
		var minion: Node = main.get_node_or_null("Minion_%d" % minion_id)
		if minion != null and minion.has_method("force_die"):
			minion.force_die()

@rpc("any_peer", "reliable")
func report_avatar_char(char: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _sender_id()
	if not players.has(sender):
		return
	players[sender]["avatar_char"] = char
	# Broadcast updated state so all clients get the new avatar_char
	sync_lobby_state.rpc(players)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func report_player_transform(pos: Vector3, rot: Vector3, team: int) -> void:
	var sender: int = _sender_id()
	# Do NOT set_player_team here — team is authoritative from spawn (FPSController._ready)
	# and must not be overwritten by per-frame transform broadcasts which can carry stale values.
	if multiplayer.is_server():
		broadcast_player_transform.rpc(sender, pos, rot, team)

@rpc("authority", "call_local", "unreliable_ordered")
func broadcast_player_transform(peer_id: int, pos: Vector3, rot: Vector3, team: int) -> void:
	GameSync.remote_player_updated.emit(peer_id, pos, rot, team)

@rpc("any_peer", "reliable")
func validate_shot(origin: Vector3, direction: Vector3, damage: float, shooter_team: int, shooter_peer: int, hit_info: Dictionary = {}, projectile_type: String = "bullet") -> void:
	if not multiplayer.is_server():
		return

	# --- Client-reported hit path (avoids server raycast hitting FPSPlayer_1) ---
	if not hit_info.is_empty():
		if hit_info.has("minion_id"):
			var mid: int = hit_info["minion_id"] as int
			var main: Node = get_tree().root.get_node("Main")
			if main != null:
				var minion: Node = main.get_node_or_null("Minion_%d" % mid)
				if minion != null and minion.has_method("take_damage"):
					var mpos: Vector3 = minion.global_position
					if mpos.distance_to(origin) <= 550.0:
						minion.take_damage(damage, "player", shooter_team, shooter_peer)
		elif hit_info.has("tower_pos"):
			var tpos: Vector3 = hit_info["tower_pos"] as Vector3
			var towers: Array = get_tree().get_nodes_in_group("towers")
			var best: Node = null
			var best_dist: float = 5.0
			for t in towers:
				var d: float = (t as Node3D).global_position.distance_to(tpos)
				if d < best_dist:
					best_dist = d
					best = t
			if best != null and best.has_method("take_damage"):
				best.take_damage(damage, "player", shooter_team, shooter_peer)
		elif hit_info.has("peer_id"):
			var target_peer: int = hit_info["peer_id"] as int
			if target_peer != shooter_peer and not GameSync.player_dead.get(target_peer, false):
				var target_team: int = GameSync.get_player_team(target_peer)
				if target_team == -1 or target_team != shooter_team:
					var new_hp: float = GameSync.damage_player(target_peer, damage, shooter_team, shooter_peer)
					apply_player_damage.rpc(target_peer, new_hp)
					if new_hp <= 0.0:
						notify_player_died.rpc(target_peer)
		spawn_bullet_visuals.rpc(origin, direction, damage, shooter_team, shooter_peer, projectile_type)
		return

	# --- Server-side fallback (used when host fires, hit_info is empty) ---
	var hit_result: Dictionary = _raycast_players(origin, direction)

	if hit_result.has("peer_id"):
		var target_peer: int = hit_result.peer_id
		var new_hp: float = GameSync.damage_player(target_peer, damage, shooter_team, shooter_peer)
		apply_player_damage.rpc(target_peer, new_hp)
		if new_hp <= 0.0:
			notify_player_died.rpc(target_peer)
	elif hit_result.has("minion_path"):
		var main: Node = get_tree().root.get_node("Main")
		if main != null:
			var minion: Node = main.get_node(hit_result.minion_path)
			if minion != null and minion.has_method("take_damage"):
				minion.take_damage(damage, "player", shooter_team, shooter_peer)

	spawn_bullet_visuals.rpc(origin, direction, damage, shooter_team, shooter_peer, projectile_type)

@rpc("authority", "call_local", "reliable")
func apply_player_damage(peer_id: int, new_health: float) -> void:
	GameSync.set_player_health(peer_id, new_health)

@rpc("authority", "call_remote", "reliable")
func notify_player_died(peer_id: int) -> void:
	GameSync.player_dead[peer_id] = true
	GameSync.player_died.emit(peer_id)

@rpc("authority", "call_remote", "reliable")
func notify_player_respawned(peer_id: int, spawn_pos: Vector3) -> void:
	GameSync.player_healths[peer_id] = GameSync.PLAYER_MAX_HP
	GameSync.player_dead[peer_id] = false
	GameSync.player_respawned.emit(peer_id, spawn_pos)

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
	# Check if this is a remote player ghost hitbox (StaticBody3D with peer_id meta)
	var check_ghost: Node = node
	while check_ghost != null and check_ghost != get_tree().root:
		if check_ghost.has_meta("ghost_peer_id"):
			var ghost_peer: int = check_ghost.get_meta("ghost_peer_id") as int
			if ghost_peer > 0:
				return {"peer_id": ghost_peer}
		check_ghost = check_ghost.get_parent()
	# Check if this is (or belongs to) a player CharacterBody3D
	var check: Node = node
	while check != null:
		if check.has_method("take_damage") and check.get("player_team") != null:
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

# ── Minion sync ───────────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_minion_states(ids: PackedInt32Array, positions: PackedVector3Array,
		rotations: PackedFloat32Array, healths: PackedFloat32Array) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var spawner: Node = main.get_node_or_null("MinionSpawner")
	for i in ids.size():
		var minion: Node = null
		if spawner != null:
			minion = spawner.get_minion_by_id(ids[i])
		if minion == null:
			minion = main.get_node_or_null("Minion_%d" % ids[i])
		if minion != null and minion.has_method("apply_puppet_state"):
			minion.apply_puppet_state(positions[i], rotations[i], healths[i])

# ── Tower / item sync ────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_place_item(world_pos: Vector3, team: int, item_type: String, subtype: String) -> void:
	if not multiplayer.is_server():
		return
	var id: int = _sender_id()
	var info: Dictionary = players.get(id, {})
	if info.get("team", -1) != team:
		return
	# Only Supporters (role == 1) may place items
	if info.get("role", -1) != 1:
		return
	var build_sys: Node = get_tree().root.get_node_or_null("Main/BuildSystem")
	if build_sys == null:
		return
	var assigned_name: String = build_sys.place_item(world_pos, team, item_type, subtype)
	if assigned_name != "":
		spawn_item_visuals.rpc(world_pos, team, item_type, subtype, assigned_name)
		# Server already has the node from place_item but never runs spawn_item_visuals
		# (call_remote). Emit item_spawned locally so the server-host player's
		# LauncherHUD registers client-placed launchers.
		item_spawned.emit(item_type, team)
		sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))

# Legacy alias — still works for any old callers
@rpc("any_peer", "reliable")
func request_place_tower(world_pos: Vector3, team: int) -> void:
	request_place_item(world_pos, team, "cannon", "")

@rpc("authority", "call_remote", "reliable")
func spawn_item_visuals(world_pos: Vector3, team: int, item_type: String, subtype: String, node_name: String = "") -> void:
	var build_sys: Node = get_tree().root.get_node_or_null("Main/BuildSystem")
	if build_sys != null and build_sys.has_method("spawn_item_local"):
		build_sys.spawn_item_local(world_pos, team, item_type, subtype, node_name)
	item_spawned.emit(item_type, team)

# Legacy alias
@rpc("authority", "call_remote", "reliable")
func spawn_tower_visuals(world_pos: Vector3, team: int) -> void:
	spawn_item_visuals(world_pos, team, "cannon", "")

# ── Supporter drop despawn sync ───────────────────────────────────────────────

# Any client calls this when a supporter-placed drop is picked up.
# Server validates and broadcasts despawn to all peers (including itself).
@rpc("any_peer", "reliable")
func notify_drop_picked_up(node_name: String) -> void:
	if not multiplayer.is_server():
		return
	despawn_drop.rpc(node_name)

# Executed on every peer (call_local) — removes the named drop node from Main.
@rpc("authority", "call_local", "reliable")
func despawn_drop(node_name: String) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var node: Node = main.get_node_or_null(node_name)
	if node != null:
		node.queue_free()

# Called by server when a tower or heal station dies — removes it on all peers.
@rpc("authority", "call_local", "reliable")
func despawn_tower(node_name: String) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var node: Node = main.get_node_or_null(node_name)
	if node != null:
		# Read team and type before freeing so we can emit the event
		var node_team: int = node.get("team") if node.get("team") != null else -1
		var node_type: String = node.get("tower_type") if node.get("tower_type") != null else _type_from_node_name(node_name)
		node.queue_free()
		tower_despawned.emit(node_type, node_team, node_name)

func _type_from_node_name(node_name: String) -> String:
	# Tower_%s_%d_%d — extract the type segment
	var parts: PackedStringArray = node_name.split("_")
	if parts.size() >= 2:
		return parts[1].to_lower()
	return "tower"

# ── Launcher / Missile sync ───────────────────────────────────────────────────

# Client requests the server to fire a missile from a specific launcher.
@rpc("any_peer", "reliable")
func request_fire_missile(launcher_name: String, target_pos: Vector3, team: int, launcher_type: String) -> void:
	if not multiplayer.is_server():
		return
	var id: int = _sender_id()
	var info: Dictionary = players.get(id, {})
	# Validate: sender must be Supporter on the correct team
	if info.get("role", -1) != 1:
		return
	if info.get("team", -1) != team:
		return
	# Validate: launcher exists and belongs to this team
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var launcher: Node = main.get_node_or_null(launcher_name)
	if launcher == null:
		return
	var launcher_team: int = launcher.get("team") if launcher.get("team") != null else -1
	if launcher_team != team:
		return
	# Spend fire cost server-side
	var fire_cost: int = LauncherDefs.get_fire_cost(launcher_type)
	if not TeamData.spend_points(team, fire_cost):
		return
	# Get fire position
	var fire_pos: Vector3 = launcher.get_fire_position() if launcher.has_method("get_fire_position") else launcher.global_position + Vector3(0.0, 6.0, 0.0)
	# Spawn on server + broadcast to clients
	_spawn_missile_server(fire_pos, target_pos, team, launcher_type)
	spawn_missile_visuals.rpc(fire_pos, target_pos, team, launcher_type)
	sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))

func spawn_missile_server(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	_spawn_missile_server(fire_pos, target_pos, team, launcher_type)

func _spawn_missile_server(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	var def: Dictionary = LauncherDefs.DEFS.get(launcher_type, {})
	if def.is_empty():
		return
	var missile_path: String = LauncherDefs.get_missile_scene(launcher_type)
	var missile_scene: PackedScene = load(missile_path) as PackedScene
	if missile_scene == null:
		return
	var missile: Node3D = missile_scene.instantiate() as Node3D
	missile.configure(def, team, fire_pos, target_pos, launcher_type)
	get_tree().root.get_child(0).add_child(missile)
	missile.global_position = fire_pos

# Executed on all remote clients — spawns the missile projectile.
@rpc("authority", "call_remote", "reliable")
func spawn_missile_visuals(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	var def: Dictionary = LauncherDefs.DEFS.get(launcher_type, {})
	if def.is_empty():
		return
	var missile_path: String = LauncherDefs.get_missile_scene(launcher_type)
	var missile_scene: PackedScene = load(missile_path) as PackedScene
	if missile_scene == null:
		return
	var missile: Node3D = missile_scene.instantiate() as Node3D
	missile.configure(def, team, fire_pos, target_pos, launcher_type)
	get_tree().root.get_child(0).add_child(missile)
	missile.global_position = fire_pos

# ── TeamData sync ─────────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func sync_team_points(blue: int, red: int) -> void:
	TeamData.sync_from_server(blue, red)

# ── Wave info sync ────────────────────────────────────────────────────────────

@rpc("authority", "call_remote", "reliable")
func sync_wave_info(wave_num: int, next_in: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("update_wave_info"):
		main.update_wave_info(wave_num, next_in)

@rpc("authority", "call_remote", "reliable")
func sync_wave_announcement(wave_num: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("show_wave_announcement"):
		main.show_wave_announcement(wave_num)

# ── Tree destruction sync ──────────────────────────────────────────────────────

const TREE_DESTROY_RADIUS := 2.5

# Called by any peer when a cannonball hits a tree — server validates + fans out.
@rpc("any_peer", "call_remote", "reliable")
func request_destroy_tree(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	sync_destroy_tree.rpc(pos)

# Executed on every peer (call_local) — removes tree nodes near pos.
@rpc("authority", "call_local", "reliable")
func sync_destroy_tree(pos: Vector3) -> void:
	var tp: Node = get_tree().root.get_node_or_null("Main/World/TreePlacer")
	if tp != null:
		tp.clear_trees_at(pos, TREE_DESTROY_RADIUS)

# ── Lane boost sync ──────────────────────────────────────────────────────────

const LANE_BOOST_COST: int = 15
const LANE_BOOST_AMOUNT: int = 3

signal lane_boosts_synced(boosts_team0: Array, boosts_team1: Array)

# Broadcasts current lane boost state to all peers (call_local so server HUD also updates).
@rpc("authority", "call_local", "reliable")
func sync_lane_boosts(boosts_team0: Array, boosts_team1: Array) -> void:
	lane_boosts_synced.emit(boosts_team0, boosts_team1)

# Client (Supporter) requests a lane boost for the next wave.
# lane_i: 0=Left, 1=Mid, 2=Right, -1=all lanes (+1 each)
@rpc("any_peer", "reliable")
func request_lane_boost(lane_i: int, team: int) -> void:
	if not multiplayer.is_server():
		return
	var id: int = _sender_id()
	var info: Dictionary = players.get(id, {})
	# Validate: sender must be Supporter on the correct team
	if info.get("role", -1) != 1:
		return
	if info.get("team", -1) != team:
		return
	if not TeamData.spend_points(team, LANE_BOOST_COST):
		return
	var spawner: Node = get_tree().root.get_node_or_null("Main/MinionSpawner")
	if spawner == null:
		return
	if lane_i == -1:
		spawner.boost_all_lanes(team)
	else:
		spawner.boost_lane(team, lane_i, LANE_BOOST_AMOUNT)
	# Broadcast updated boost state and points to all peers
	var b: Array = spawner.get("_lane_boosts") as Array
	sync_lane_boosts.rpc(b[0], b[1])
	sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))

# ── Recon strike (fog reveal) sync ───────────────────────────────────────────

# Client requests server to broadcast a recon reveal for their team.
@rpc("any_peer", "reliable")
func request_recon_reveal(target_pos: Vector3, reveal_radius: float, reveal_duration: float, team: int) -> void:
	if not multiplayer.is_server():
		return
	var id: int = _sender_id()
	var info: Dictionary = players.get(id, {})
	# Validate: sender must be Supporter on the correct team
	if info.get("role", -1) != 1:
		return
	if info.get("team", -1) != team:
		return
	# Spend fire cost server-side
	if not TeamData.spend_points(team, LauncherDefs.get_fire_cost("recon_strike")):
		return
	broadcast_recon_reveal.rpc(target_pos, reveal_radius, reveal_duration, team)
	sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))

# Executed on every peer — triggers fog reveal + VFX on all clients.
@rpc("authority", "call_local", "reliable")
func broadcast_recon_reveal(target_pos: Vector3, reveal_radius: float, reveal_duration: float, team: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("apply_recon_reveal"):
		main.apply_recon_reveal(target_pos, reveal_radius, reveal_duration)

# ── Game over broadcast ───────────────────────────────────────────────────────

func _on_team_lives_game_over(winner_team: int) -> void:
	# Only the server (or singleplayer) triggers this; broadcast to all clients.
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	_rpc_game_over.rpc(winner_team)

@rpc("authority", "call_remote", "reliable")
func _rpc_game_over(winner_team: int) -> void:
	TeamLives.game_over.emit(winner_team)
