extends Node

const MINION_SCENE := "res://scenes/minions/Minion.tscn"
const WAVE_INTERVAL := 20.0
const MAX_WAVE_SIZE := 6
const MINION_STAGGER := 0.5  # seconds between each minion in a wave
const SYNC_INTERVAL := 6     # physics frames between position broadcasts

var wave_number := 0
var wave_timer := 0.0
var _minion_counter: int = 0
var _minion_node_cache: Dictionary = {}  # minion_id -> Node

# Per-team lane boosts: _lane_boosts[team][lane_i] = extra minions to spawn next wave.
# Set via boost_lane() / boost_all_lanes(). Consumed (reset to 0) after each wave fires.
var _lane_boosts: Array = [[0, 0, 0], [0, 0, 0]]
var _sync_frame: int = 0
var _last_synced_next_in: int = -1

var _minion_scene: PackedScene = null
var _main: Node = null

func _ready() -> void:
	_minion_scene = load(MINION_SCENE)
	_main = get_node_or_null("/root/Main")

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	_sync_frame += 1
	if _sync_frame >= SYNC_INTERVAL:
		_sync_frame = 0
		_broadcast_minion_states()

func _broadcast_minion_states() -> void:
	if _minion_node_cache.is_empty():
		return
	var ids:       PackedInt32Array   = PackedInt32Array()
	var positions: PackedVector3Array = PackedVector3Array()
	var rotations: PackedFloat32Array = PackedFloat32Array()
	var healths:   PackedFloat32Array = PackedFloat32Array()
	for mid in _minion_node_cache.keys():
		var m: Node = _minion_node_cache[mid]
		if not is_instance_valid(m):
			_minion_node_cache.erase(mid)
			continue
		ids.append(mid as int)
		positions.append(m.global_position)
		rotations.append(m.rotation.y)
		healths.append(m.get("health") as float)
	if ids.is_empty():
		return
	LobbyManager.sync_minion_states.rpc(ids, positions, rotations, healths)

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	wave_timer += delta
	# Update countdown label
	if _main and _main.has_method("update_wave_info"):
		var next_in := int(WAVE_INTERVAL - wave_timer) + 1
		_main.update_wave_info(wave_number, next_in)
		if next_in != _last_synced_next_in:
			_last_synced_next_in = next_in
			LobbyManager.sync_wave_info.rpc(wave_number, next_in)

	if wave_timer >= WAVE_INTERVAL:
		wave_timer = 0.0
		wave_number += 1
		_last_synced_next_in = -1
		_launch_wave()

func _launch_wave() -> void:
	if _main and _main.has_method("show_wave_announcement"):
		_main.show_wave_announcement(wave_number)
		LobbyManager.sync_wave_announcement.rpc(wave_number)

	var base_count: int = min(wave_number, 5)
	for lane_i in range(3):
		for team in range(2):
			var extra: int = _lane_boosts[team][lane_i]
			var count: int = base_count + extra
			for i in range(count):
				var delay := i * MINION_STAGGER
				_spawn_minion_delayed(team, lane_i, delay)

	# Reset all boosts after the wave launches and broadcast zeroes to all peers
	_lane_boosts = [[0, 0, 0], [0, 0, 0]]
	LobbyManager.sync_lane_boosts.rpc([0, 0, 0], [0, 0, 0])

# ── Lane boost API ────────────────────────────────────────────────────────────

## Adds `amount` extra minions for `team` on `lane_i` for the next wave.
## Called server-side only.
func boost_lane(team: int, lane_i: int, amount: int) -> void:
	if lane_i < 0 or lane_i > 2:
		return
	if team < 0 or team > 1:
		return
	_lane_boosts[team][lane_i] += amount

## Adds 1 extra minion per lane for `team` on the next wave.
## Called server-side only.
func boost_all_lanes(team: int) -> void:
	if team < 0 or team > 1:
		return
	for lane_i in range(3):
		_lane_boosts[team][lane_i] += 1

func _spawn_minion_delayed(team: int, lane_i: int, delay: float) -> void:
	if delay <= 0.0:
		_spawn_minion(team, lane_i)
	else:
		await get_tree().create_timer(delay).timeout
		_spawn_minion(team, lane_i)

func _spawn_minion(team: int, lane_i: int) -> void:
	var waypts: Array[Vector3] = LaneData.get_lane_waypoints(lane_i, team)
	var spawn_pos := Vector3(waypts[0].x, 0.0, waypts[0].z)
	spawn_pos.y = _get_terrain_height(spawn_pos) + 1.0
	_minion_counter += 1
	var minion_id: int = _minion_counter
	_spawn_at_position(team, spawn_pos, waypts, lane_i, minion_id)

	if multiplayer.is_server():
		LobbyManager.spawn_minion_visuals.rpc(team, spawn_pos, waypts, lane_i, minion_id)

func _spawn_at_position(team: int, pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int) -> void:
	if _minion_scene == null:
		_minion_scene = load(MINION_SCENE)
	var minion: CharacterBody3D = _minion_scene.instantiate()
	minion.set("team", team)
	minion.set("_minion_id", minion_id)
	minion.name = "Minion_%d" % minion_id
	minion.position = pos
	get_tree().root.get_node("Main").add_child(minion)
	minion.setup(team, waypts, lane_i)
	_minion_node_cache[minion_id] = minion

func spawn_for_network(team: int, pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int) -> void:
	_spawn_at_position(team, pos, waypts, lane_i, minion_id)
	# Mark as puppet — server drives position
	var minion: Node = _minion_node_cache.get(minion_id)
	if minion == null:
		minion = get_tree().root.get_node_or_null("Main/Minion_%d" % minion_id)
	if minion != null:
		minion.set("is_puppet", true)
		minion.set("_physics_process_disabled", true)
		minion.set("velocity", Vector3.ZERO)
		minion.set("_puppet_target_pos", pos)
		minion.call("set_physics_process", false)
	else:
		push_warning("MinionSpawner: spawn_for_network id=%d node not found" % minion_id)

func kill_minion_by_id(minion_id: int) -> void:
	var minion: Node = _minion_node_cache.get(minion_id)
	_minion_node_cache.erase(minion_id)
	if minion != null and is_instance_valid(minion) and minion.has_method("force_die"):
		minion.force_die()

func get_terrain_height(pos: Vector3) -> float:
	return _get_terrain_height(pos)

func _get_terrain_height(pos: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var from: Vector3 = Vector3(pos.x, 50.0, pos.z)
	var to: Vector3 = Vector3(pos.x, -10.0, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result.position.y
