extends Node3D

signal done

# Preload all asset scenes so no synchronous disk I/O occurs during placement.
const WALL_SCENE_PATHS: Array[PackedScene] = [
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/wall.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/wall-wood.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/wall-block.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/wall-corner.glb"),
	preload("res://assets/kenney_blaster-kit/Models/GLB format/crate-medium.glb"),
	preload("res://assets/kenney_blaster-kit/Models/GLB format/crate-small.glb"),
	preload("res://assets/kenney_blaster-kit/Models/GLB format/crate-wide.glb"),
]

const GRID_SIZE := 200
const GRID_STEPS := 200
const CLEARING_COUNT := 20

const BASE_CLEAR_RADIUS := 12.0
const BLUE_BASE_CENTER := Vector3(0.0, 0.0, 82.0)
const RED_BASE_CENTER := Vector3(0.0, 0.0, -82.0)

const WALL_DENSITY := 0.3
const WALL_SCALE_MIN := 1.0
const WALL_SCALE_MAX := 2.0

var _random_clearing_centers: Array[Vector2] = []
var _random_clearing_radii: Array[float] = []
var generation_done: bool = false

@onready var terrain_body: StaticBody3D = null

func _ready() -> void:
	var gen_seed: int = GameSync.game_seed
	if gen_seed == 0:
		gen_seed = randi()
	seed(gen_seed)
	await get_tree().process_frame
	await get_tree().process_frame

	# Ensure terrain collision is ready before raycasting.
	if has_node("/root/Main/World/Terrain"):
		var terrain_node: Node = $/root/Main/World/Terrain
		if terrain_node.get_child_count() == 0:
			await terrain_node.done

	terrain_body = _find_terrain()
	_generate_random_clearings()
	await _place_walls()

func _find_terrain() -> StaticBody3D:
	if has_node("/root/Main/World/Terrain"):
		return $/root/Main/World/Terrain
	return null

func _generate_random_clearings() -> void:
	_random_clearing_centers.clear()
	_random_clearing_radii.clear()
	var half_size: float = GRID_SIZE / 2.0
	var edge_margin: float = 20.0
	var attempts: int = 0
	while _random_clearing_centers.size() < CLEARING_COUNT and attempts < 500:
		attempts += 1
		var wx: float = randf_range(-half_size + edge_margin, half_size - edge_margin)
		var wz: float = randf_range(-half_size + edge_margin, half_size - edge_margin)
		var pos := Vector2(wx, wz)
		# Skip lane areas, secret paths, and base areas
		if _is_on_lane_area(pos) or _is_on_secret_path(pos) or _is_in_base_area(pos):
			continue
		var radius: float = randf_range(8.0, 15.0)
		_random_clearing_centers.append(pos)
		_random_clearing_radii.append(radius)
	print("WallPlacer: generated ", _random_clearing_centers.size(), " random clearings")

func _place_walls() -> void:
	if WALL_SCENE_PATHS.is_empty():
		print("WallPlacer: no wall scenes found!")
		generation_done = true
		done.emit()
		return

	var placed_walls: int = 0
	var placed_crates: int = 0

	# Place walls in random clearings — yield every clearing so the loading
	# screen remains responsive.
	for i in range(_random_clearing_centers.size()):
		var center := _random_clearing_centers[i]
		var radius := _random_clearing_radii[i]

		# Skip if too close to important positions
		if center.distance_to(Vector2(BLUE_BASE_CENTER.x, BLUE_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + radius:
			continue
		if center.distance_to(Vector2(RED_BASE_CENTER.x, RED_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + radius:
			continue

		# Place walls in this clearing with some chance
		if randf() < WALL_DENSITY:
			var angle: float = randf() * TAU
			var distance: float = randf_range(0.3, 0.7) * radius
			var wall_pos := Vector3(center.x + cos(angle) * distance, 0.0, center.y + sin(angle) * distance)

			# Raycast to find terrain height
			var terrain_y: float = _get_terrain_height(wall_pos)
			wall_pos.y = terrain_y + 0.5  # Slightly above ground

			_place_wall(wall_pos)
			placed_walls += 1
		# Sometimes place crates instead
		else:
			if randf() < 0.4:  # 40% chance to place a crate
				var angle: float = randf() * TAU
				var distance: float = randf_range(0.3, 0.7) * radius
				var crate_pos := Vector3(center.x + cos(angle) * distance, 0.0, center.y + sin(angle) * distance)

				# Raycast to find terrain height
				var terrain_y: float = _get_terrain_height(crate_pos)
				crate_pos.y = terrain_y + 0.5

				_place_crate(crate_pos)
				placed_crates += 1

		# Yield every clearing to keep the loading screen responsive
		await get_tree().process_frame

	print("WallPlacer: placed ", placed_walls, " walls and ", placed_crates, " crates")
	LoadingState.report("Placing cover objects...", 55.0)
	generation_done = true
	done.emit()

func _place_wall(pos: Vector3) -> void:
	var wall_scene: PackedScene = WALL_SCENE_PATHS[randi() % WALL_SCENE_PATHS.size()]
	var wall: Node3D = wall_scene.instantiate()
	wall.position = pos
	add_child(wall)

	# Rotate wall randomly
	var angle: float = randf() * TAU
	wall.rotate_y(angle)

	# Scale the wall
	var scale: float = randf_range(WALL_SCALE_MIN, WALL_SCALE_MAX)
	wall.scale = Vector3(scale, scale, scale)

	# Add simple collision to this wall
	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = Vector3(2.0 * scale, 3.0 * scale, 0.5)

	var col_node: CollisionShape3D = CollisionShape3D.new()
	col_node.shape = col_shape
	col_node.position = Vector3(0.0, 1.5 * scale, 0.0)

	var collision: StaticBody3D = StaticBody3D.new()
	collision.add_child(col_node)
	collision.position = pos
	collision.collision_layer = 4  # layer 3 — passable by rockets/missiles
	collision.collision_mask = 1

	add_child(collision)

func _place_crate(pos: Vector3) -> void:
	var crate_scene: PackedScene = WALL_SCENE_PATHS[randi() % WALL_SCENE_PATHS.size()]
	var crate: Node3D = crate_scene.instantiate()
	crate.position = pos
	add_child(crate)

	# Rotate crate randomly
	var angle: float = randf() * TAU
	crate.rotate_y(angle)

	# Scale the crate
	var scale: float = randf_range(1.5, 2.0)
	crate.scale = Vector3(scale, scale, scale)

	# Add simple collision to this crate
	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = Vector3(1.5 * scale, 1.5 * scale, 1.5 * scale)

	var col_node: CollisionShape3D = CollisionShape3D.new()
	col_node.shape = col_shape
	col_node.position = Vector3(0.0, 0.75 * scale, 0.0)

	var collision: StaticBody3D = StaticBody3D.new()
	collision.add_child(col_node)
	collision.position = pos
	collision.collision_layer = 4  # layer 3 — passable by rockets/missiles
	collision.collision_mask = 1

	add_child(collision)

func _get_terrain_height(pos: Vector3) -> float:
	if terrain_body == null:
		return 0.0

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
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

func _is_on_lane_area(pos: Vector2) -> bool:
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		for pt in pts:
			if pos.distance_to(pt) < 6.0 + 5.0:
				return true
	return false

func _is_on_secret_path(pos: Vector2) -> bool:
	var terrain: Node = $/root/Main/World/Terrain
	if terrain and terrain.has_method("get_secret_paths"):
		var paths: Array = terrain.get_secret_paths()
		for path_pts in paths:
			for pt in path_pts:
				if pos.distance_to(pt) < 5.0:
					return true
	return false

func _is_in_base_area(pos: Vector2) -> bool:
	if pos.distance_to(Vector2(BLUE_BASE_CENTER.x, BLUE_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + 5.0:
		return true
	if pos.distance_to(Vector2(RED_BASE_CENTER.x, RED_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + 5.0:
		return true
	return false
