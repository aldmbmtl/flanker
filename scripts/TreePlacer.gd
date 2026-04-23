extends Node3D

const TREE_PATHS := [
	"res://assets/kenney_fantasy-town-kit/Models/GLB format/tree.glb",
	"res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-crooked.glb",
	"res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-high.glb",
	"res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-high-crooked.glb",
	"res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-high-round.glb",
]

const GRID_SIZE := 200
const GRID_STEPS := 200
const CELL_SIZE := float(GRID_SIZE) / float(GRID_STEPS)

const LANE_CLEAR_WIDTH := 6.0
const MOUNTAIN_CLEAR_RADIUS := 8.0

const BASE_CLEAR_RADIUS := 12.0
const BLUE_BASE_CENTER := Vector3(0.0, 0.0, 82.0)
const RED_BASE_CENTER := Vector3(0.0, 0.0, -82.0)

const TREE_SCALE_MIN := 0.8
const TREE_SCALE_MAX := 1.2

const TREE_DENSITY := 0.5

const CLEARING_CHANCE := 0.05
const CLEARING_MIN_RADIUS := 8.0
const CLEARING_MAX_RADIUS := 15.0
const CLEARING_COUNT := 20

const SECRET_PATH_CLEAR_WIDTH := 5.0

var _random_clearing_centers: Array[Vector2] = []
var _random_clearing_radii: Array[float] = []

@onready var terrain_body: StaticBody3D = null

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	terrain_body = _find_terrain()
	_generate_random_clearings()
	_place_trees()

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
		if _is_on_lane_area(pos) or _is_on_secret_path(pos) or _is_in_base_area(pos):
			continue
		var radius: float = randf_range(CLEARING_MIN_RADIUS, CLEARING_MAX_RADIUS)
		_random_clearing_centers.append(pos)
		_random_clearing_radii.append(radius)
	print("TreePlacer: generated ", _random_clearing_centers.size(), " random clearings")

func _place_trees() -> void:
	print("TreePlacer: loading tree scenes...")
	var tree_scenes: Array[PackedScene] = []
	for path in TREE_PATHS:
		var scn: PackedScene = load(path)
		if scn:
			tree_scenes.append(scn)
		else:
			print("TreePlacer: failed to load ", path)
	
	print("TreePlacer: loaded ", tree_scenes.size(), " tree scenes")
	
	if tree_scenes.is_empty():
		print("TreePlacer: no tree scenes!")
		return
	
	var placed: int = 0
	for gx in range(GRID_STEPS):
		for gz in range(GRID_STEPS):
			if randf() > TREE_DENSITY:
				continue
			
			var wx: float = (float(gx) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var wz: float = (float(gz) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var pos := Vector3(wx, 0.0, wz)
			
			if _is_in_lane(pos) or _is_on_mountain(pos) or _is_in_base(pos) or _is_in_random_clearing(pos) or _is_on_secret_path(Vector2(pos.x, pos.z)):
				continue
			
			_place_tree(pos, tree_scenes)
			placed += 1
	
	print("TreePlacer: placed ", placed, " trees")

func _place_tree(pos: Vector3, tree_scenes: Array[PackedScene]) -> void:
	var terrain_y: float = _get_terrain_height(pos)
	pos.y = terrain_y
	
	var scn: PackedScene = tree_scenes[randi() % tree_scenes.size()]
	var tree: Node = scn.instantiate()
	add_child(tree)
	tree.position = pos
	
	var angle: float = randf() * TAU
	tree.rotate_y(angle)
	
	var scale: float = randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX)
	tree.scale = Vector3(scale, scale, scale)

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

func _is_in_lane(pos: Vector3) -> bool:
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		for pt in pts:
			var lane_pos := Vector3(pt.x, 0.0, pt.y)
			if pos.distance_to(lane_pos) < LANE_CLEAR_WIDTH:
				return true
	return false

func _is_on_mountain(pos: Vector3) -> bool:
	var peaks: Array = _get_mountain_peaks()
	for peak in peaks:
		if pos.distance_to(peak) < MOUNTAIN_CLEAR_RADIUS:
			return true
	return false

func _is_in_base(pos: Vector3) -> bool:
	if pos.distance_to(BLUE_BASE_CENTER) < BASE_CLEAR_RADIUS:
		return true
	if pos.distance_to(RED_BASE_CENTER) < BASE_CLEAR_RADIUS:
		return true
	return false

func _get_mountain_peaks() -> Array:
	var peaks: Array = []
	var pts: Array = LaneData.get_lane_points(0)
	if pts.size() >= 2:
		var left_mid: Vector2 = pts[pts.size() / 2]
		peaks.append(Vector3(left_mid.x - 50.0, 0.0, left_mid.y))
	var pts2: Array = LaneData.get_lane_points(1)
	if pts2.size() >= 2:
		var mid_mid: Vector2 = pts2[pts2.size() / 2]
		peaks.append(Vector3(mid_mid.x, 0.0, mid_mid.y))
	var pts3: Array = LaneData.get_lane_points(2)
	if pts3.size() >= 2:
		var right_mid: Vector2 = pts3[pts3.size() / 2]
		peaks.append(Vector3(right_mid.x + 50.0, 0.0, right_mid.y))
	return peaks

func _is_on_lane_area(pos: Vector2) -> bool:
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		for pt in pts:
			if pos.distance_to(pt) < LANE_CLEAR_WIDTH + 5.0:
				return true
	return false

func _is_on_secret_path(pos: Vector2) -> bool:
	var terrain: Node = _get_terrain_node()
	if terrain and terrain.has_method("get_secret_paths"):
		var paths: Array = terrain.get_secret_paths()
		for path_pts in paths:
			for pt in path_pts:
				if pos.distance_to(pt) < SECRET_PATH_CLEAR_WIDTH:
					return true
	return false

func _get_terrain_node() -> Node:
	if has_node("/root/Main/World/Terrain"):
		return $/root/Main/World/Terrain
	return null

func _is_in_base_area(pos: Vector2) -> bool:
	if pos.distance_to(Vector2(BLUE_BASE_CENTER.x, BLUE_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + 5.0:
		return true
	if pos.distance_to(Vector2(RED_BASE_CENTER.x, RED_BASE_CENTER.z)) < BASE_CLEAR_RADIUS + 5.0:
		return true
	return false

func _is_in_random_clearing(pos: Vector3) -> bool:
	var pos2 := Vector2(pos.x, pos.z)
	for i in range(_random_clearing_centers.size()):
		if pos2.distance_to(_random_clearing_centers[i]) < _random_clearing_radii[i]:
			return true
	return false