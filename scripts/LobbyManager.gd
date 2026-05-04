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

## Set by BridgeClient when it receives a lobby_state message from Python.
## True iff all players are registered and all are ready.
var _can_start: bool = false

signal lobby_updated
signal kicked_from_server
signal player_left(id: int)
signal role_slots_updated(claimed: Dictionary)
signal all_roles_confirmed
signal human_supporter_claimed(team: int)
signal item_spawned(item_type: String, team: int)
signal tower_despawned(item_type: String, team: int, tower_name: String)

func _ready() -> void:
	_init_bullet_sync()
	_init_minion_sync()
	GameSync.player_respawned.connect(_on_game_sync_player_respawned)
	TeamLives.game_over.connect(_on_team_lives_game_over)
	BridgeClient.disconnected_from_server.connect(_on_bridge_disconnected)

func _on_game_sync_player_respawned(_peer_id: int, _spawn_pos: Vector3) -> void:
	pass  # Respawn broadcast is handled by the Python bridge (player_respawned update).

func _on_bridge_disconnected() -> void:
	players.clear()
	game_started = false
	kicked_from_server.emit()

func set_role_ingame(role: int) -> void:
	BridgeClient.send("set_role_ingame", {"role": role})

func _handle_set_role_ingame(id: int, role: int) -> void:
	# role: 0=FIGHTER, 1=SUPPORTER — called after game scene loads
	if not players.has(id):
		return
	var team: int = players[id].team
	if role == 1:
		if supporter_claimed.get(team, false):
			# Slot taken — reject and re-broadcast current state
			_notify_role_rejected(id, supporter_claimed)
			return
		supporter_claimed[team] = true
		human_supporter_claimed.emit(team)
	players[id].role = role
	# Register the peer in the skill tree so the server can validate unlocks
	# and execute skills on behalf of remote clients.
	var role_str: String = "Supporter" if role == 1 else "Fighter"
	SkillTree.register_peer(id, role_str)
	_sync_role_slots(supporter_claimed)

func _sync_role_slots(claimed: Dictionary) -> void:
	supporter_claimed = claimed.duplicate()
	role_slots_updated.emit(supporter_claimed)

func _notify_role_rejected(_id: int, claimed: Dictionary) -> void:
	supporter_claimed = claimed.duplicate()
	role_slots_updated.emit(supporter_claimed)

func set_ready(ready_state: bool) -> void:
	BridgeClient.send("set_ready", {"ready": ready_state})

func _handle_set_ready(id: int, ready_state: bool) -> void:
	if not players.has(id):
		return
	if game_started:
		return
	players[id].ready = ready_state
	lobby_updated.emit()

func sync_lobby_state(state: Dictionary) -> void:
	players = state.duplicate(true)
	lobby_updated.emit()

const RESPAWN_CAP: float = 60.0

func increment_death_count(peer_id: int) -> int:
	player_death_counts[peer_id] = player_death_counts.get(peer_id, 0) + 1
	var new_count: int = player_death_counts[peer_id]
	BridgeClient.send("sync_death_count", {"peer_id": peer_id, "count": new_count})
	return new_count

func get_respawn_time(peer_id: int) -> float:
	var deaths: int = player_death_counts.get(peer_id, 0)
	var t: float = RESPAWN_BASE + (deaths * RESPAWN_INCREMENT)
	t = min(t, RESPAWN_CAP)
	return maxf(1.0, t)

# Called by Python relay — updates local death count for respawn timer calculation.
func sync_death_count(peer_id: int, count: int) -> void:
	player_death_counts[peer_id] = count

func can_start_game() -> bool:
	return _can_start

func get_players_by_team(team: int) -> Array:
	var result: Array = []
	for id in players:
		if players[id].team == team:
			result.append(id)
	return result

# Returns the peer_id of the human Supporter on the given team, or -1 if none.
# Used to attribute kill XP from towers and minions to the team's Supporter.
func get_supporter_peer(team: int) -> int:
	for id in players:
		var info: Dictionary = players[id]
		if info.get("team", -1) == team and info.get("role", -1) == 1:
			return id
	return -1


var _bullet_scene: PackedScene
var _rocket_scene: PackedScene
var _cannonball_scene: PackedScene
var _mortar_scene: PackedScene

func _init_bullet_sync() -> void:
	_bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")
	_rocket_scene = preload("res://scenes/projectiles/Rocket.tscn")

func spawn_bullet_visuals(pos: Vector3, dir: Vector3, damage: float, shooter_team: int, shooter_peer_id: int = -1, projectile_type: String = "bullet") -> void:
	print("[LobbyManager] spawn_bullet_visuals: type=%s pos=%s dir=%s team=%d peer=%d" % [projectile_type, pos, dir, shooter_team, shooter_peer_id])
	if projectile_type == "rocket":
		if _rocket_scene == null:
			_rocket_scene = preload("res://scenes/projectiles/Rocket.tscn")
		var rocket: Node3D = _rocket_scene.instantiate()
		rocket.damage          = damage
		rocket.source          = "rocket"
		rocket.shooter_team    = shooter_team
		rocket.shooter_peer_id = shooter_peer_id
		rocket.velocity        = dir * 0.1   # initial speed, Rocket.gd accelerates from here
		VfxUtils.get_scene_root(self).add_child(rocket)
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
	VfxUtils.get_scene_root(self).add_child(bullet)
	bullet.global_position = pos
	var main: Node = VfxUtils.get_scene_root(self)
	if main != null and main.has_method("_on_bullet_hit_something") and shooter_peer_id == BridgeClient.get_peer_id():
		bullet.hit_something.connect(main._on_bullet_hit_something)

func spawn_cannonball_visuals(pos: Vector3, target: Vector3, damage: float, team: int) -> void:
	if _cannonball_scene == null:
		_cannonball_scene = preload("res://scenes/projectiles/Cannonball.tscn")
	var ball: Node3D = _cannonball_scene.instantiate()
	ball.damage       = damage
	ball.source       = "cannonball"
	ball.shooter_team = team
	ball.target_pos   = target
	ball.position     = pos
	VfxUtils.get_scene_root(self).add_child(ball)
	SoundManager.play_3d("res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_001.ogg", pos, 0.0, randf_range(0.9, 1.05))

func spawn_mortar_visuals(pos: Vector3, target: Vector3, damage: float, team: int) -> void:
	if _mortar_scene == null:
		_mortar_scene = preload("res://scenes/projectiles/MortarShell.tscn")
	var shell: Node3D = _mortar_scene.instantiate()
	shell.damage       = damage
	shell.source       = "mortar_shell"
	shell.shooter_team = team
	shell.target_pos   = target
	shell.position     = pos
	VfxUtils.get_scene_root(self).add_child(shell)
	SoundManager.play_3d("res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_004.ogg", pos, 1.0, randf_range(0.88, 1.0))

var _minion_scene: PackedScene

func _init_minion_sync() -> void:
	_minion_scene = preload("res://scenes/minions/Minion.tscn")

func spawn_minion_visuals(team: int, spawn_pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int, mtype: String = "basic") -> void:
	if _minion_scene == null:
		_minion_scene = preload("res://scenes/minions/Minion.tscn")

	var main: Node = get_tree().root.get_node("Main")
	if main == null:
		return
	if not main.has_node("MinionSpawner"):
		return
	var spawner: Node = main.get_node("MinionSpawner")
	spawner.spawn_for_network(team, spawn_pos, waypts, lane_i, minion_id, mtype)

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

func report_avatar_char(char: String) -> void:
	BridgeClient.send("report_avatar", {"char": char})

func _handle_report_avatar_char(sender: int, char: String) -> void:
	if not players.has(sender):
		return
	players[sender]["avatar_char"] = char
	# Broadcast updated state so all clients get the new avatar_char
	sync_lobby_state(players)

func report_player_transform(pos: Vector3, rot: Vector3, team: int) -> void:
	BridgeClient.send("report_transform", {
		"pos": [pos.x, pos.y, pos.z],
		"rot": [rot.x, rot.y, rot.z],
		"team": team,
	})

func report_initial_transform(pos: Vector3, rot: Vector3, team: int) -> void:
	BridgeClient.send("report_initial_transform", {
		"pos": [pos.x, pos.y, pos.z],
		"rot": [rot.x, rot.y, rot.z],
		"team": team,
	})

func broadcast_player_transform(peer_id: int, pos: Vector3, rot: Vector3, team: int) -> void:
	print("[BCAST] peer_id=", peer_id, " pos=", pos)
	GameSync.remote_player_updated.emit(peer_id, pos, rot, team)

func seed_player_transform(peer_id: int, pos: Vector3, rot: Vector3, team: int) -> void:
	print("[SEED] peer_id=", peer_id, " pos=", pos)
	GameSync.remote_player_updated.emit(peer_id, pos, rot, team)

## Returns the peer ID from an FPSPlayer node name.
func _find_peer_id_from_node(node: Node) -> int:
	var n: String = node.name
	if n.begins_with("FPSPlayer_"):
		var id_str: String = n.substr(10)
		if id_str.is_valid_int():
			return id_str.to_int()
	return -1


# ── Minion sync ───────────────────────────────────────────────────────────────

func sync_minion_states(ids: PackedInt32Array, positions: PackedVector3Array,
		rotations: PackedFloat32Array, healths: PackedFloat32Array) -> void:
	var id_arr: Array = []
	var pos_arr: Array = []
	var rot_arr: Array = []
	var hp_arr: Array = []
	for i in ids.size():
		id_arr.append(ids[i])
		pos_arr.append([positions[i].x, positions[i].y, positions[i].z])
		rot_arr.append(rotations[i])
		hp_arr.append(healths[i])
	BridgeClient.send("sync_minion_states", {
		"ids": id_arr, "positions": pos_arr, "rotations": rot_arr, "healths": hp_arr,
	})

# ── Tower / item sync ────────────────────────────────────────────────────────

func notify_tower_hit(tower_name: String) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var tower: Node = main.get_node_or_null(tower_name)
	if tower != null and tower.has_method("_flash_hit"):
		tower._flash_hit()

func notify_minion_hit(minion_id: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var spawner: Node = main.get_node_or_null("MinionSpawner")
	var minion: Node = null
	if spawner != null:
		minion = spawner.get_minion_by_id(minion_id)
	if minion == null:
		minion = main.get_node_or_null("Minion_%d" % minion_id)
	if minion != null and is_instance_valid(minion) and not minion.is_queued_for_deletion() and minion.has_method("_flash_hit"):
		minion._flash_hit()

func spawn_mg_visuals(tower_name: String, muzzle_pos: Vector3, hit_pos: Vector3, hit_normal: Vector3, hit_unit: bool) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var tower: Node = main.get_node_or_null(tower_name)
	if tower == null:
		return
	if tower.has_method("_spawn_muzzle_flash"):
		tower._spawn_muzzle_flash(muzzle_pos)
	if tower.has_method("_spawn_hit_impact"):
		tower._spawn_hit_impact(hit_pos, hit_normal, hit_unit)
	if tower.has_method("_spawn_tracer"):
		tower._spawn_tracer(muzzle_pos, hit_pos)
	SoundManager.play_3d("res://assets/kenney_sci-fi-sounds/Audio/laserSmall_002.ogg", muzzle_pos, -3.0, randf_range(0.92, 1.08))

func spawn_slow_pulse_visuals(tower_name: String, origin: Vector3) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var tower: Node = main.get_node_or_null(tower_name)
	if tower != null and tower.has_method("_spawn_pulse_vfx"):
		tower._spawn_pulse_vfx()
	else:
		# Fallback: tower node not found on this client (e.g. not yet spawned).
		# Nothing to do — pulse VFX is cosmetic only.
		pass

func sync_mg_turret_rot(tower_name: String, yaw_rad: float) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var tower: Node = main.get_node_or_null(tower_name)
	if tower == null:
		return
	var pivot: Node3D = tower.get_node_or_null("TurretPivot")
	if pivot != null:
		pivot.rotation.y = yaw_rad

# ── Supporter drop despawn sync ───────────────────────────────────────────────

# Any client calls this when a supporter-placed drop is picked up.
# Sends to Python for server-authoritative validation before broadcasting despawn.
func notify_drop_picked_up(node_name: String) -> void:
	BridgeClient.send("pickup_drop", {"name": node_name})

# Executed on every peer (call_local) — removes the named drop node from Main.
func despawn_drop(node_name: String) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var node: Node = main.get_node_or_null(node_name)
	if node != null:
		node.queue_free()

# Called by server when a tower or heal station dies — removes it on all peers.
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
func request_fire_missile(launcher_name: String, target_pos: Vector3, team: int, launcher_type: String) -> void:
	BridgeClient.send("request_fire_missile", {
		"launcher_name": launcher_name,
		"target_pos": [target_pos.x, target_pos.y, target_pos.z],
		"team": team,
		"launcher_type": launcher_type,
	})

func spawn_missile_server(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	_spawn_missile_server(fire_pos, target_pos, team, launcher_type)

func _spawn_missile_server(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	_do_spawn_missile_body(fire_pos, target_pos, team, launcher_type)

# Executed on each client — spawns the missile projectile.
func spawn_missile_visuals(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	_do_spawn_missile_body(fire_pos, target_pos, team, launcher_type)

func _do_spawn_missile_body(fire_pos: Vector3, target_pos: Vector3, team: int, launcher_type: String) -> void:
	var def: Dictionary = LauncherDefs.DEFS.get(launcher_type, {})
	if def.is_empty():
		return
	var missile_path: String = LauncherDefs.get_missile_scene(launcher_type)
	var missile_scene: PackedScene = load(missile_path) as PackedScene
	if missile_scene == null:
		return
	var missile: Node3D = missile_scene.instantiate() as Node3D
	missile.configure(def, team, fire_pos, target_pos, launcher_type)
	VfxUtils.get_scene_root(self).add_child(missile)
	missile.global_position = fire_pos

# ── Wave info sync ────────────────────────────────────────────────────────────

func sync_wave_info(wave_num: int, next_in: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("update_wave_info"):
		main.update_wave_info(wave_num, next_in)

func sync_wave_announcement(wave_num: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("show_wave_announcement"):
		main.show_wave_announcement(wave_num)

# ── Tree destruction sync ──────────────────────────────────────────────────────

const TREE_DESTROY_RADIUS := 3.0

# Called by any peer when a cannonball hits a tree — relays to Python.
func request_destroy_tree(pos: Vector3) -> void:
	BridgeClient.send("destroy_tree", {"pos": [pos.x, pos.y, pos.z]})

# Called by BridgeClient relay — removes tree nodes near pos.
func sync_destroy_tree(pos: Vector3) -> void:
	var tp: Node = get_tree().root.get_node_or_null("Main/World/TreePlacer")
	if tp != null:
		tp.clear_trees_at(pos, TREE_DESTROY_RADIUS)

# ── Lane boost sync ──────────────────────────────────────────────────────────

const LANE_BOOST_COST: int = 15
const LANE_BOOST_AMOUNT: int = 3

signal lane_boosts_synced(boosts_team0: Array, boosts_team1: Array)

# Called by BridgeClient relay — emits signal so local HUD and MinionSpawner update.
func sync_lane_boosts(boosts_team0: Array, boosts_team1: Array) -> void:
	lane_boosts_synced.emit(boosts_team0, boosts_team1)

# Client (Supporter) requests a lane boost for the next wave.
# lane_i: 0=Left, 1=Mid, 2=Right, -1=all lanes (+1 each)
func request_lane_boost(lane_i: int, team: int) -> void:
	BridgeClient.send("request_lane_boost", {"lane_i": lane_i, "team": team})

# Client (Supporter) requests a ram minion on a specific lane (or all lanes).
# tier:   0=beaver ($15), 1=cow ($30), 2=elephant ($50). All-lanes cost is ×3.
# lane_i: 0=Left, 1=Mid, 2=Right, -1=all lanes.
func request_ram_minion(tier: int, team: int, lane_i: int) -> void:
	BridgeClient.send("request_ram_minion", {"tier": tier, "team": team, "lane_i": lane_i})

# ── Recon strike (fog reveal) sync ───────────────────────────────────────────

# Client requests server to broadcast a recon reveal for their team.
func request_recon_reveal(target_pos: Vector3, reveal_radius: float, reveal_duration: float, team: int) -> void:
	BridgeClient.send("request_recon_reveal", {
		"target_pos": [target_pos.x, target_pos.y, target_pos.z],
		"reveal_radius": reveal_radius,
		"reveal_duration": reveal_duration,
		"team": team,
	})

# Executed on every peer — triggers fog reveal + VFX on all clients.
func broadcast_recon_reveal(target_pos: Vector3, reveal_radius: float, reveal_duration: float, _team: int) -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("apply_recon_reveal"):
		main.apply_recon_reveal(target_pos, reveal_radius, reveal_duration)

# ── Game over broadcast ───────────────────────────────────────────────────────

func _on_team_lives_game_over(winner_team: int) -> void:
	# Python is authoritative for game_over — this is a no-op relay only.
	# BridgeClient handles the actual broadcast via the "game_over" message.
	pass

# ── Ping system ───────────────────────────────────────────────────────────────

signal ping_received(world_pos: Vector3, team: int, color: Color)

const _PING_COL_DEFAULT := Color(0.62, 0.0, 1.0, 1.0)  # vivid purple

# Any peer calls this with their world position and team.
# Python validates team membership then broadcasts to all peers.
# color defaults to purple so existing callers need no changes.
func request_ping(world_pos: Vector3, team: int, color: Color = Color(0.62, 0.0, 1.0, 1.0)) -> void:
	BridgeClient.send("request_ping", {
		"world_pos": [world_pos.x, world_pos.y, world_pos.z],
		"team": team,
		"color": [color.r, color.g, color.b, color.a],
	})

func _handle_request_ping(id: int, world_pos: Vector3, team: int, color: Color) -> void:
	var info: Dictionary = players.get(id, {})
	if info.get("team", -1) != team:
		return
	broadcast_ping(world_pos, team, color)

func broadcast_ping(world_pos: Vector3, team: int, color: Color = Color(0.62, 0.0, 1.0, 1.0)) -> void:
	ping_received.emit(world_pos, team, color)

# Called from Main.leave_game() to wipe all session state before returning
# to the start menu. Autoload persists across scene changes so we must clear
# manually — the incoming session must start completely fresh.
func reset() -> void:
	players.clear()
	game_started = false
	supporter_claimed = { 0: false, 1: false }
	player_death_counts.clear()
	ai_supporter_teams.clear()
	_can_start = false
