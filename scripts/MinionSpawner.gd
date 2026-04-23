extends Node

const MINION_SCENE := "res://scenes/Minion.tscn"
const WAVE_INTERVAL := 30.0
const MAX_WAVE_SIZE := 6
const MINION_STAGGER := 0.5  # seconds between each minion in a wave

var wave_number := 0
var wave_timer := 0.0

var _minion_scene: PackedScene = null

func _ready() -> void:
	_minion_scene = load(MINION_SCENE)

func _process(delta: float) -> void:
	wave_timer += delta
	# Update countdown label
	var main := get_node_or_null("/root/Main")
	if main and main.has_method("update_wave_info"):
		var next_in := int(WAVE_INTERVAL - wave_timer) + 1
		main.update_wave_info(wave_number, next_in)

	if wave_timer >= WAVE_INTERVAL:
		wave_timer = 0.0
		wave_number += 1
		_launch_wave()

func _launch_wave() -> void:
	var main := get_node_or_null("/root/Main")
	if main and main.has_method("show_wave_announcement"):
		main.show_wave_announcement(wave_number)

	var count: int = min(wave_number, MAX_WAVE_SIZE)
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
	var minion: CharacterBody3D = _minion_scene.instantiate()
	var waypts: Array[Vector3] = LaneData.get_lane_waypoints(lane_i, team)
	minion.set("team", team)
	minion.position = Vector3(waypts[0].x, 1.0, waypts[0].z)
	get_tree().root.get_node("Main").add_child(minion)
	minion.setup(team, waypts, lane_i)
