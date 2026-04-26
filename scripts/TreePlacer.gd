extends Node3D

signal done

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

const TREE_SCALE_MIN := 3
const TREE_SCALE_MAX := 5

const TREE_DENSITY := .07

const CLEARING_CHANCE := 0.1
const CLEARING_MIN_RADIUS := 8.0
const CLEARING_MAX_RADIUS := 15.0
const CLEARING_COUNT := 20

const SECRET_PATH_CLEAR_WIDTH := 5.0

# Distance-band thresholds from map center (XZ magnitude)
# Near  ≤ 55 u from center, Far > 55 u — two bands keeps MMI count low.
const BAND_NEAR_MAX := 55.0
const BAND_FAR_MIN  := 55.0

var _random_clearing_centers: Array[Vector2] = []
var _random_clearing_radii: Array[float] = []

# Set to a value > 0 before add_child to override TREE_DENSITY (e.g. menu background)
var menu_density: float = -1.0

@onready var terrain_body: StaticBody3D = null

# Per-variant, per-band transform accumulation
# _band_transforms[variant_idx][band_idx] = Array[Transform3D]
var _band_transforms: Array = []

func _ready() -> void:
	var gen_seed: int = GameSync.game_seed
	if gen_seed == 0:
		gen_seed = randi()
	seed(gen_seed)
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

func _place_trees() -> void:
	var tree_scenes: Array[PackedScene] = []
	for path in TREE_PATHS:
		var scn: PackedScene = load(path)
		if scn:
			tree_scenes.append(scn)

	if tree_scenes.is_empty():
		done.emit()
		return

	# Initialise per-variant, per-band (2 bands: near / far) accumulator
	_band_transforms.clear()
	for _vi in tree_scenes.size():
		_band_transforms.append([[], []])  # [near_transforms, far_transforms]

	var placed: int = 0
	var density: float = menu_density if menu_density > 0.0 else TREE_DENSITY
	for gx in range(GRID_STEPS):
		for gz in range(GRID_STEPS):
			if randf() > density:
				continue

			var wx: float = (float(gx) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var wz: float = (float(gz) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var pos := Vector3(wx, 0.0, wz)

			if _is_in_lane(pos) or _is_on_mountain(pos) or _is_in_base(pos) or _is_in_random_clearing(pos) or _is_on_secret_path(Vector2(pos.x, pos.z)):
				continue

			_accumulate_tree(pos, tree_scenes)
			placed += 1
			_add_tree_collision(pos, randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX))

	# Build MultiMeshInstance3D nodes for each variant × band
	_commit_multimeshes(tree_scenes)

	if menu_density < 0.0:
		LoadingState.report("Placing trees...", 45.0)
	done.emit()

func _accumulate_tree(pos: Vector3, tree_scenes: Array[PackedScene]) -> void:
	var terrain_y: float = _get_terrain_height(pos)
	pos.y = terrain_y

	var vi: int = randi() % tree_scenes.size()
	var scale: float = randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX)
	var angle: float = randf() * TAU

	var t := Transform3D()
	t = t.rotated(Vector3.UP, angle)
	t = t.scaled(Vector3(scale, scale, scale))
	t.origin = pos

	# Band by distance from map center
	var dist_from_center: float = Vector2(pos.x, pos.z).length()
	var band: int = 0 if dist_from_center <= BAND_NEAR_MAX else 1
	_band_transforms[vi][band].append(t)

func _commit_multimeshes(tree_scenes: Array[PackedScene]) -> void:
	# Visibility range distances for each band (camera-to-MMI-origin proxy)
	# Band 0 (near/center): always visible, clip at 200
	# Band 1 (far/edge): visible up to 260 (camera.far = 250)
	const BAND_VIS_END: Array = [200.0, 260.0]

	for vi in tree_scenes.size():
		# Extract a mesh from the scene to use in MultiMesh
		var mesh: Mesh = _extract_first_mesh(tree_scenes[vi])
		if mesh == null:
			continue

		for band in 2:
			var transforms: Array = _band_transforms[vi][band]
			if transforms.is_empty():
				continue

			var mm := MultiMesh.new()
			mm.mesh = mesh
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.instance_count = transforms.size()
			for i in transforms.size():
				mm.set_instance_transform(i, transforms[i] as Transform3D)

			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = BAND_VIS_END[band]
			mmi.visibility_range_end_margin = 10.0
			add_child(mmi)

func _extract_first_mesh(scene: PackedScene) -> Mesh:
	# Instantiate temporarily to find the first MeshInstance3D
	var inst: Node = scene.instantiate()
	var mesh: Mesh = _find_mesh_recursive(inst)
	inst.queue_free()
	return mesh

func _find_mesh_recursive(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m: Mesh = _find_mesh_recursive(child)
		if m != null:
			return m
	return null

func _add_tree_collision(world_pos: Vector3, scale: float) -> void:
	var trunk_radius: float = 0.4 * scale
	var trunk_height: float = 3.0 * scale

	var col_shape: CylinderShape3D = CylinderShape3D.new()
	col_shape.radius = trunk_radius * 0.4
	col_shape.height = trunk_height

	var col_node: CollisionShape3D = CollisionShape3D.new()
	col_node.shape = col_shape
	col_node.position = Vector3(0.0, trunk_height / 2.0, 0.0)

	var collision: StaticBody3D = StaticBody3D.new()
	collision.add_child(col_node)
	collision.position = world_pos
	collision.collision_layer = 2
	collision.collision_mask = 1
	collision.set_meta("tree_trunk_height", trunk_height)

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

# Remove all tree collision nodes within radius of world_pos (XZ).
# MultiMesh instances cannot be removed individually — they are purely visual.
# Collision StaticBody3D trunks are still individual children and can be freed.
func clear_trees_at(world_pos: Vector3, radius: float) -> void:
	var center := Vector2(world_pos.x, world_pos.z)
	for child in get_children():
		if child is MultiMeshInstance3D:
			continue  # visual — skip
		var child_pos := Vector2(child.position.x, child.position.z)
		if child_pos.distance_to(center) <= radius:
			child.queue_free()
