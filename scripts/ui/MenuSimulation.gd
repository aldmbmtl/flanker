## MenuSimulation.gd
## Lightweight battle simulation for the start-menu background.
## Spawns ~6 minions per lane per team (36 total) and 2 towers per team into
## the World3D node already built by StartMenu._spawn_menu_world().
##
## Minions use MinionAI (the standard rifle minion) directly — no MinionSpawner
## so no wave logic, no net guards, no respawn.  They just fight until they die.
## Trickle re-spawning keeps the scene populated.

extends Node

const MinionScene := preload("res://scenes/minions/Minion.tscn")
const TowerScene  := preload("res://scenes/towers/Tower.tscn")

const MINIONS_PER_LANE_PER_TEAM := 6
const TRICKLE_INTERVAL          := 8.0   # seconds between re-spawn checks
const MAX_MINIONS_TOTAL         := 36    # hard cap — 3 lanes × 2 teams × 6

var _world: Node3D
var _minion_counter: int = 0
var _trickle_timer: float = 0.0

func start(world: Node3D) -> void:
	_world = world
	_spawn_towers()
	_spawn_all_minions()

# ── Helpers ────────────────────────────────────────────────────────────────────

## Cast a ray straight down from high up and return the ground Y at (x, z).
## Falls back to 1.0 if nothing is hit (e.g. edge of map or void).
func _ground_y(x: float, z: float) -> float:
	var space := get_tree().root.get_world_3d().direct_space_state
	var from   := Vector3(x, 60.0, z)
	var to     := Vector3(x, -5.0, z)
	var query  := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1   # terrain is on layer 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 1.0
	return result["position"].y

# ── Tower placement ────────────────────────────────────────────────────────────

func _spawn_towers() -> void:
	# Two cannon towers per team, placed mid-lane on left and right outer lanes.
	# X positions match outer lane X (~±65), Z offset toward each team's half.
	var placements: Array = [
		# [team, x, z]
		[0, -65.0,  25.0],
		[0,  65.0,  25.0],
		[1, -65.0, -25.0],
		[1,  65.0, -25.0],
	]
	for entry in placements:
		var team: int = entry[0]
		var x: float  = entry[1]
		var z: float  = entry[2]
		var y: float  = _ground_y(x, z)
		var tower: StaticBody3D = TowerScene.instantiate()
		_world.add_child(tower)
		tower.global_position = Vector3(x, y, z)
		tower.setup(team)

# ── Minion spawning ────────────────────────────────────────────────────────────

func _spawn_all_minions() -> void:
	for lane_i in 3:
		for team in 2:
			for _n in MINIONS_PER_LANE_PER_TEAM:
				_spawn_minion(lane_i, team)

func _spawn_minion(lane_i: int, team: int) -> void:
	var waypoints: Array = LaneData.get_lane_waypoints(lane_i, team)
	if waypoints.is_empty():
		return
	var wp: Vector3 = waypoints[0]
	# Scatter spawn positions slightly so they don't all stack on the same point
	var spawn_x: float = wp.x + randf_range(-1.5, 1.5)
	var spawn_z: float = wp.z + randf_range(-1.5, 1.5)
	var spawn_y: float = _ground_y(spawn_x, spawn_z) + 0.5   # slight lift so they settle

	_minion_counter += 1
	var minion: CharacterBody3D = MinionScene.instantiate()
	minion.set("team", team)
	minion.set("_minion_id", _minion_counter)
	minion.name = "MenuMinion_%d" % _minion_counter
	# add_child BEFORE setting global_position (AGENTS.md gotcha)
	_world.add_child(minion)
	minion.global_position = Vector3(spawn_x, spawn_y, spawn_z)
	minion.setup(team, waypoints, lane_i)

# ── Trickle re-spawn — keeps scene populated as minions die ───────────────────

func _process(delta: float) -> void:
	_trickle_timer += delta
	if _trickle_timer < TRICKLE_INTERVAL:
		return
	_trickle_timer = 0.0

	# Count living menu minions
	var alive: int = 0
	for child in _world.get_children():
		if child.name.begins_with("MenuMinion_") and is_instance_valid(child):
			alive += 1

	if alive >= MAX_MINIONS_TOTAL:
		return

	# Spawn replacements until cap is reached — one per lane per team
	for lane_i in 3:
		for team in 2:
			if alive < MAX_MINIONS_TOTAL:
				_spawn_minion(lane_i, team)
				alive += 1
