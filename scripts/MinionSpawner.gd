extends Node

const MINION_SCENE := "res://scenes/Minion.tscn"
const WAVE_INTERVAL := 20.0
const MAX_WAVE_SIZE := 6
const MINION_STAGGER := 0.5  # seconds between each minion in a wave

var wave_number := 0
var wave_timer := 0.0
var _minion_counter: int = 0

var _minion_scene: PackedScene = null
var _main: Node = null

func _ready() -> void:
	_minion_scene = load(MINION_SCENE)
	_main = get_node_or_null("/root/Main")

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	wave_timer += delta
	# Update countdown label
	if _main and _main.has_method("update_wave_info"):
		var next_in := int(WAVE_INTERVAL - wave_timer) + 1
		_main.update_wave_info(wave_number, next_in)

	if wave_timer >= WAVE_INTERVAL:
		wave_timer = 0.0
		wave_number += 1
		_launch_wave()

func _launch_wave() -> void:
	if _main and _main.has_method("show_wave_announcement"):
		_main.show_wave_announcement(wave_number)

	var count: int = min(wave_number, 5)
	for lane_i in range(3):
		for i in range(count):
			var delay := i * MINION_STAGGER
			_spawn_minion_delayed(0, lane_i, delay)
			_spawn_minion_delayed(1, lane_i, delay)

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
	minion.name = "Minion_%d" % minion_id
	minion.position = pos
	get_tree().root.get_node("Main").add_child(minion)
	minion.setup(team, waypts, lane_i)

func spawn_for_network(team: int, pos: Vector3, waypts: Array[Vector3], lane_i: int, minion_id: int) -> void:
	_spawn_at_position(team, pos, waypts, lane_i, minion_id)

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
