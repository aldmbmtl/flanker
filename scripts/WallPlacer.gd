extends Node3D

signal done

# Rock assets from kenney_pirate-kit — placed in jungle clearings with collision.
const ROCK_SCENE_PATHS: Array[PackedScene] = [
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-a.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-b.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-c.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-sand-a.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-sand-b.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-sand-c.glb"),
]

# Grass/bush assets from kenney_pirate-kit — scattered on the green biome side only,
# purely decorative (no collision).
const GRASS_SCENE_PATHS: Array[PackedScene] = [
	preload("res://assets/kenney_pirate-kit/Models/GLB format/grass.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/grass-patch.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/grass-plant.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/patch-grass.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/patch-grass-foliage.glb"),
]

# Sand patch assets from kenney_pirate-kit — scattered on the desert biome side only,
# purely decorative (no collision). Uses the sandy rock variants as desert ground scatter.
const SAND_SCENE_PATHS: Array[PackedScene] = [
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-sand-a.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-sand-b.glb"),
	preload("res://assets/kenney_pirate-kit/Models/GLB format/rocks-sand-c.glb"),
]

const SAND_COUNT := 113

const GRID_SIZE := 200
const GRID_STEPS := 200
const CLEARING_COUNT := 20
const GRASS_COUNT := 750  # target number of grass scatter placements across the jungle

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
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return

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
	if ROCK_SCENE_PATHS.is_empty():
		print("WallPlacer: no rock scenes found!")
		generation_done = true
		done.emit()
		return

	var placed_rocks: int = 0

	# Place rocks in random clearings — yield every clearing so the loading
	# screen remains responsive.
	for i in range(_random_clearing_centers.size()):
		var center := _random_clearing_centers[i]
		var radius := _random_clearing_radii[i]

		# Skip if too close to important positions
		if center.distance_to(Vector2(BLUE_BASE_CENTER.x, BLUE_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + radius:
			continue
		if center.distance_to(Vector2(RED_BASE_CENTER.x, RED_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + radius:
			continue

		# Place 1 or 2 rocks in this clearing with some chance
		var rock_count: int = 1 if randf() < WALL_DENSITY else 0
		if randf() < 0.4:
			rock_count += 1  # 40% chance for an extra rock

		for _r in range(rock_count):
			var angle: float = randf() * TAU
			var distance: float = randf_range(0.3, 0.7) * radius
			var rock_pos := Vector3(center.x + cos(angle) * distance, 0.0, center.y + sin(angle) * distance)

			var terrain_y: float = _get_terrain_height(rock_pos)
			rock_pos.y = terrain_y + 0.5

			_place_rock(rock_pos)
			placed_rocks += 1

		# Yield every clearing to keep the loading screen responsive
		await get_tree().process_frame
		if not is_inside_tree():
			return

	await _scatter_grass()
	await _scatter_sand()

	print("WallPlacer: placed ", placed_rocks, " rocks, ", GRASS_COUNT, " grass patches, and ", SAND_COUNT, " sand patches")
	LoadingState.report("Placing cover objects...", 55.0)
	generation_done = true
	done.emit()

func _place_rock(pos: Vector3) -> void:
	var rock_scene: PackedScene = ROCK_SCENE_PATHS[randi() % ROCK_SCENE_PATHS.size()]
	var rock: Node3D = rock_scene.instantiate()
	rock.position = pos
	add_child(rock)

	var angle: float = randf() * TAU
	rock.rotate_y(angle)

	var scale: float = randf_range(1.0, 2.5)
	rock.scale = Vector3(scale, scale, scale)

	# Collision box sized to rock geometry (~3.6-5.1 wide/deep, ~2.3-3.7 tall at scale 1).
	# 3.2 x/z gives a snug fit without the large invisible margin of 4.0.
	# Layer 2 so CharacterBody3D players (collision_mask=7 = layers 1+2+4) are blocked.
	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = Vector3(3.2 * scale, 2.0 * scale, 3.2 * scale)

	var col_node: CollisionShape3D = CollisionShape3D.new()
	col_node.shape = col_shape
	col_node.position = Vector3(0.0, 1.0 * scale, 0.0)

	var collision: StaticBody3D = StaticBody3D.new()
	collision.add_child(col_node)
	collision.position = pos
	collision.collision_layer = 2
	collision.collision_mask = 1

	add_child(collision)

func _scatter_grass() -> void:
	if GRASS_SCENE_PATHS.is_empty():
		return

	# Grass only appears on the green biome side, past the blend zone (±10 units).
	var grass_left: bool = (GameSync.game_seed % 2 == 0)
	var grass_sign: float = -1.0 if grass_left else 1.0  # green side is x<0 or x>0

	var half_size: float = GRID_SIZE / 2.0
	var edge_margin: float = 20.0
	var placed: int = 0
	var attempts: int = 0
	var max_attempts: int = GRASS_COUNT * 3

	while placed < GRASS_COUNT and attempts < max_attempts:
		attempts += 1
		var wx: float = randf_range(-half_size + edge_margin, half_size - edge_margin)
		var wz: float = randf_range(-half_size + edge_margin, half_size - edge_margin)

		# Skip if not past the biome blend zone on the green side
		if wx * grass_sign <= 10.0:
			continue

		var pos2d := Vector2(wx, wz)

		if _is_on_lane_area(pos2d) or _is_on_secret_path(pos2d) or _is_in_base_area(pos2d):
			continue

		var terrain_result: Dictionary = _query_terrain(Vector3(wx, 0.0, wz))

		# Skip hills and plateau areas — anything above 3.5 units is on or
		# approaching a plateau (base terrain max is 4.0, plateaus top at 6.0).
		if terrain_result.get("y", 0.0) >= 3.5:
			continue

		var grass_pos := Vector3(wx, terrain_result.get("y", 0.0), wz)

		var grass_scene: PackedScene = GRASS_SCENE_PATHS[randi() % GRASS_SCENE_PATHS.size()]
		var grass: Node3D = grass_scene.instantiate()
		grass.position = grass_pos
		grass.rotate_y(randf() * TAU)
		var scale: float = randf_range(0.8, 1.8)
		grass.scale = Vector3(scale, scale, scale)
		add_child(grass)

		placed += 1

		# Yield every 20 placements to keep the loading screen responsive
		if placed % 20 == 0:
			await get_tree().process_frame
			if not is_inside_tree():
				return

func _scatter_sand() -> void:
	if SAND_SCENE_PATHS.is_empty():
		return

	# Sand only appears on the desert biome side, past the blend zone (±10 units).
	var grass_left: bool = (GameSync.game_seed % 2 == 0)
	var desert_sign: float = 1.0 if grass_left else -1.0  # desert side is x>0 or x<0

	var half_size: float = GRID_SIZE / 2.0
	var edge_margin: float = 20.0
	var placed: int = 0
	var attempts: int = 0
	var max_attempts: int = SAND_COUNT * 3

	while placed < SAND_COUNT and attempts < max_attempts:
		attempts += 1
		var wx: float = randf_range(-half_size + edge_margin, half_size - edge_margin)
		var wz: float = randf_range(-half_size + edge_margin, half_size - edge_margin)

		# Skip if not past the biome blend zone on the desert side
		if wx * desert_sign <= 10.0:
			continue

		var pos2d := Vector2(wx, wz)

		if _is_on_lane_area(pos2d) or _is_on_secret_path(pos2d) or _is_in_base_area(pos2d):
			continue

		var terrain_result: Dictionary = _query_terrain(Vector3(wx, 0.0, wz))

		# Skip hills and plateau areas
		if terrain_result.get("y", 0.0) >= 3.5:
			continue

		var sand_pos := Vector3(wx, terrain_result.get("y", 0.0), wz)

		var sand_scene: PackedScene = SAND_SCENE_PATHS[randi() % SAND_SCENE_PATHS.size()]
		var sand: Node3D = sand_scene.instantiate()
		sand.position = sand_pos
		sand.rotate_y(randf() * TAU)
		var scale: float = randf_range(0.8, 1.8)
		sand.scale = Vector3(scale, scale, scale)
		add_child(sand)

		# Collision — same layer/size heuristic as jungle rocks.
		var col_shape: BoxShape3D = BoxShape3D.new()
		col_shape.size = Vector3(3.2 * scale, 2.0 * scale, 3.2 * scale)
		var col_node: CollisionShape3D = CollisionShape3D.new()
		col_node.shape = col_shape
		col_node.position = Vector3(0.0, 1.0 * scale, 0.0)
		var collision: StaticBody3D = StaticBody3D.new()
		collision.add_child(col_node)
		collision.position = sand_pos
		collision.collision_layer = 2
		collision.collision_mask = 1
		add_child(collision)

		placed += 1

		# Yield every 20 placements to keep the loading screen responsive
		if placed % 20 == 0:
			await get_tree().process_frame
			if not is_inside_tree():
				return

func _query_terrain(pos: Vector3) -> Dictionary:
	if terrain_body == null:
		return {"y": 0.0, "normal": Vector3.UP}

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {"y": 0.0, "normal": Vector3.UP}

	var from: Vector3 = Vector3(pos.x, 50.0, pos.z)
	var to: Vector3 = Vector3(pos.x, -10.0, pos.z)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 1

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return {"y": 0.0, "normal": Vector3.UP}

	return {"y": result.position.y, "normal": result.normal}

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
	# Find the Terrain node relative to our parent (works in both Main/World and
	# StartMenu/World3D) rather than relying on an absolute scene-tree path.
	var terrain: Node = get_parent().get_node_or_null("Terrain")
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
