extends Node3D

signal done

const WIND_SHADER := preload("res://assets/tree_wind.gdshader")

# Preload tree GLBs so disk I/O does not block the main thread during placement.
const TREE_SCENES: Array[PackedScene] = [
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/tree.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-crooked.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-high.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-high-crooked.glb"),
	preload("res://assets/kenney_fantasy-town-kit/Models/GLB format/tree-high-round.glb"),
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

# How many grid rows to process before yielding a frame.
# Lower = smoother loading screen, higher = fewer frame drops but longer perceived stall.
const ROWS_PER_FRAME := 20

var _random_clearing_centers: Array[Vector2] = []
var _random_clearing_radii: Array[float] = []

# Set to a value > 0 before add_child to override TREE_DENSITY (e.g. menu background)
var menu_density: float = -1.0

var generation_done: bool = false

# ── Wind configuration ────────────────────────────────────────────────────────
# Base sway amplitude and the extra amplitude added at peak gust.
@export var wind_strength_base: float   = 0.03
@export var wind_strength_gust: float   = 0.04
# How fast the gust cycle oscillates (full period ≈ 2π / gust_cycle_speed seconds)
@export var wind_gust_cycle_speed: float = 0.25
@export var wind_speed: float           = 0.9
@export var wind_direction: Vector2     = Vector2(1.0, 0.3)
# Spatial frequency of the travelling wave: smaller = longer wavelength (more natural).
@export var wave_scale: float           = 0.05

# ── Wind spike (random large gusts layered on top of the base rhythm) ─────────
# Maximum shader strength reached at the peak of a spike.
@export var wind_strength_peak: float           = 0.16
# Seconds between random spike events (randomised in this range each time).
@export var wind_gust_spike_min_interval: float = 8.0
@export var wind_gust_spike_max_interval: float = 22.0
# Rate at which the spike magnitude decays back to zero (units per second).
@export var wind_gust_spike_decay: float        = 2.5

# Rate at which _gust_spike ramps UP to the target (units per second).
# Lower = slower attack = smoother onset. ~1.2 gives a ~0.8s build-up.
@export var wind_gust_spike_attack: float       = 1.2

# Current spike magnitude [0..1]; ramps up toward _gust_target, decays back to 0.
var _gust_spike: float       = 0.0
var _gust_target: float      = 0.0
# Absolute time (seconds) at which the next spike fires.
var _next_spike_time: float  = 0.0

# All live MMIs that have a wind ShaderMaterial applied — updated each _process.
var _wind_mmis: Array[MultiMeshInstance3D] = []

@onready var terrain_body: StaticBody3D = null

# Per-variant, per-band transform accumulation
# _band_transforms[variant_idx][band_idx] = Array[Transform3D]
var _band_transforms: Array = []

# Precomputed O(1) exclusion mask: flat array indexed by [gz * GRID_STEPS + gx]
var _exclusion_mask: Array = []

# Flat list of per-tree records used for visual clearing.
# Each entry is a Dictionary: { "xz": Vector2, "vi": int, "band": int }
# Parallel to _band_transforms — one entry per tree placed.
var _tree_records: Array = []

# MMI lookup table: _mmis[vi * 2 + band] = MultiMeshInstance3D (or null before commit)
var _mmis: Array = []

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

	# Ensure terrain mesh and collision are fully built before raycasting.
	var terrain_node: Node = _get_terrain_node()
	if terrain_node and not terrain_node.get_child_count():
		# Terrain thread still running — wait for its done signal.
		await terrain_node.done

	terrain_body = _find_terrain()
	_generate_random_clearings()
	await _place_trees()

func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0

	# ── Random spike trigger ──────────────────────────────────────────────────
	# Set target to 1.0; spike ramps up smoothly then decays — no snap.
	if t >= _next_spike_time:
		_gust_target = 1.0
		_next_spike_time = t + randf_range(wind_gust_spike_min_interval, wind_gust_spike_max_interval)
	# Ramp up toward target at attack rate, then decay back to zero.
	if _gust_spike < _gust_target:
		_gust_spike = minf(_gust_target, _gust_spike + wind_gust_spike_attack * delta)
	else:
		_gust_spike = maxf(0.0, _gust_spike - wind_gust_spike_decay * delta)
		if _gust_spike <= 0.0:
			_gust_target = 0.0

	if _wind_mmis.is_empty():
		return

	# ── Base sine rhythm + spike combined ────────────────────────────────────
	var gust_factor: float = sin(t * wind_gust_cycle_speed) * 0.5 + 0.5
	var current_strength: float = wind_strength_base \
		+ wind_strength_gust * gust_factor \
		+ (wind_strength_peak - wind_strength_base) * _gust_spike
	for mmi in _wind_mmis:
		if is_instance_valid(mmi):
			var mat: ShaderMaterial = mmi.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("wind_strength", current_strength)

# Returns a normalised [0..1] wind intensity for external consumers (e.g. WindParticles).
# Blends 40 % base sine rhythm with 60 % spike so particles react strongly to gusts.
func get_wind_intensity() -> float:
	var t: float = Time.get_ticks_msec() / 1000.0
	var base: float = sin(t * wind_gust_cycle_speed) * 0.5 + 0.5
	return clampf(base * 0.4 + _gust_spike * 0.6, 0.0, 1.0)

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

# Build a flat boolean mask once so each grid cell lookup is O(1).
func _build_exclusion_mask() -> void:
	_exclusion_mask.resize(GRID_STEPS * GRID_STEPS)
	var mountain_peaks: Array = _get_mountain_peaks()
	for gz in range(GRID_STEPS):
		for gx in range(GRID_STEPS):
			var wx: float = (float(gx) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var wz: float = (float(gz) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var pos3 := Vector3(wx, 0.0, wz)
			var pos2 := Vector2(wx, wz)

			var excluded := false

			# Lane check
			if not excluded:
				for lane_i in range(3):
					var pts: Array = LaneData.get_lane_points(lane_i)
					for pt in pts:
						if pos2.distance_to(pt) < LANE_CLEAR_WIDTH:
							excluded = true
							break
					if excluded:
						break

			# Mountain/peak check
			if not excluded:
				for peak in mountain_peaks:
					if pos3.distance_to(peak) < MOUNTAIN_CLEAR_RADIUS:
						excluded = true
						break

			# Base check
			if not excluded:
				if pos3.distance_to(BLUE_BASE_CENTER) < BASE_CLEAR_RADIUS:
					excluded = true
				elif pos3.distance_to(RED_BASE_CENTER) < BASE_CLEAR_RADIUS:
					excluded = true

			# Random clearing check
			if not excluded:
				for i in range(_random_clearing_centers.size()):
					if pos2.distance_to(_random_clearing_centers[i]) < _random_clearing_radii[i]:
						excluded = true
						break

			# Secret path check
			if not excluded:
				excluded = _is_on_secret_path(pos2)

			_exclusion_mask[gz * GRID_STEPS + gx] = excluded

func _place_trees() -> void:
	if TREE_SCENES.is_empty():
		generation_done = true
		done.emit()
		return

	# Build the exclusion mask before iterating (still fast — no raycasts)
	_build_exclusion_mask()

	# Initialise per-variant, per-band (2 bands: near / far) accumulator
	_band_transforms.clear()
	_tree_records.clear()
	_mmis.clear()
	_mmis.resize(TREE_SCENES.size() * 2)  # vi * 2 + band
	for _vi in TREE_SCENES.size():
		_band_transforms.append([[], []])  # [near_transforms, far_transforms]

	var density: float = menu_density if menu_density > 0.0 else TREE_DENSITY

	# Collect candidate positions first (fast — uses precomputed mask, no raycasts)
	var candidates: Array[Vector3] = []
	for gz in range(GRID_STEPS):
		for gx in range(GRID_STEPS):
			if randf() > density:
				continue
			if _exclusion_mask[gz * GRID_STEPS + gx]:
				continue
			var wx: float = (float(gx) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			var wz: float = (float(gz) / float(GRID_STEPS) - 0.5) * GRID_SIZE
			candidates.append(Vector3(wx, 0.0, wz))

	# Process candidates in batches, yielding between batches so the loading
	# screen can update and the OS does not kill the process as frozen.
	var batch: int = 0
	for pos in candidates:
		_accumulate_tree(pos, TREE_SCENES)
		_add_tree_collision(pos, randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX))
		batch += 1
		if batch >= 50:
			batch = 0
			await get_tree().process_frame
			if not is_inside_tree():
				return

	# Build MultiMeshInstance3D nodes for each variant × band
	_commit_multimeshes(TREE_SCENES)

	if menu_density < 0.0:
		LoadingState.report("Placing trees...", 45.0)
	generation_done = true
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

	# Record this tree for visual clearing support
	_tree_records.append({"xz": Vector2(pos.x, pos.z), "vi": vi, "band": band})

func _commit_multimeshes(tree_scenes: Array[PackedScene]) -> void:
	# Visibility range distances for each band (camera-to-MMI-origin proxy)
	# Band 0 (near/center): always visible, clip at 200
	# Band 1 (far/edge): visible up to 260 (camera.far = 250)
	const BAND_VIS_END: Array = [200.0, 260.0]

	for vi in tree_scenes.size():
		# Extract a mesh and its albedo texture from the scene to use in MultiMesh
		var mesh: Mesh = _extract_first_mesh(tree_scenes[vi])
		if mesh == null:
			continue
		var albedo_tex: Texture2D = _extract_albedo_texture(tree_scenes[vi])

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
			# tree_shadow_distance: 0=Off, 1=Close (near band only), 2=Far (both bands)
			var tsd: int = GraphicsSettings.tree_shadow_distance
			var cast: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if tsd == 1 and band == 0:
				cast = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			elif tsd == 2:
				cast = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.cast_shadow = cast
			mmi.visibility_range_end = BAND_VIS_END[band]
			mmi.visibility_range_end_margin = 10.0
			add_child(mmi)
			# Store in lookup table so clear_trees_at can find and rebuild this MMI
			_mmis[vi * 2 + band] = mmi

			# Apply wind shader material so trees sway with the wind.
			var mat := ShaderMaterial.new()
			mat.shader = WIND_SHADER
			mat.set_shader_parameter("wind_strength", wind_strength_base)
			mat.set_shader_parameter("wind_speed", wind_speed)
			mat.set_shader_parameter("wind_direction", wind_direction)
			mat.set_shader_parameter("wave_scale", wave_scale)
			if albedo_tex != null:
				mat.set_shader_parameter("albedo_texture", albedo_tex)
			mmi.material_override = mat
			_wind_mmis.append(mmi)

func _extract_first_mesh(scene: PackedScene) -> Mesh:
	# Instantiate temporarily to find the first MeshInstance3D
	var inst: Node = scene.instantiate()
	var mesh: Mesh = _find_mesh_recursive(inst)
	inst.queue_free()
	return mesh

func _extract_albedo_texture(scene: PackedScene) -> Texture2D:
	# Instantiate temporarily to read the albedo texture from the first surface.
	# Returns null if the material has no albedo texture (solid colour is fine).
	var inst: Node = scene.instantiate()
	var tex: Texture2D = _find_albedo_recursive(inst)
	inst.queue_free()
	return tex

func _find_albedo_recursive(node: Node) -> Texture2D:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			if mat is BaseMaterial3D:
				var bm: BaseMaterial3D = mat as BaseMaterial3D
				if bm.albedo_texture != null:
					return bm.albedo_texture
	for child in node.get_children():
		var t: Texture2D = _find_albedo_recursive(child)
		if t != null:
			return t
	return null

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
# Also removes the corresponding visual transforms from _band_transforms and
# rebuilds the affected MultiMeshInstance3D nodes so trees visually disappear.
func clear_trees_at(world_pos: Vector3, radius: float) -> void:
	var center := Vector2(world_pos.x, world_pos.z)

	# --- Collision: free StaticBody3D trunks ---
	for child in get_children():
		if child is MultiMeshInstance3D:
			continue  # visual — handled below
		var child_pos := Vector2(child.position.x, child.position.z)
		if child_pos.distance_to(center) <= radius:
			child.queue_free()

	# --- Visuals: remove transforms from _band_transforms and rebuild MMIs ---
	if _tree_records.is_empty():
		return

	# Collect indices of records to remove, and track which (vi, band) pairs need rebuild
	var to_remove: Array[int] = []
	var dirty_keys: Dictionary = {}  # "vi_band" -> true
	for i in _tree_records.size():
		var rec: Dictionary = _tree_records[i]
		var xz: Vector2 = rec["xz"]
		if xz.distance_to(center) <= radius:
			to_remove.append(i)
			dirty_keys[str(rec["vi"]) + "_" + str(rec["band"])] = true

	if to_remove.is_empty():
		return

	# Build a set of removed XZ positions for fast transform matching
	var removed_xz: Array[Vector2] = []
	for i in to_remove:
		removed_xz.append(_tree_records[i]["xz"])

	# Remove transforms from _band_transforms for affected (vi, band) pairs
	for key in dirty_keys.keys():
		var parts: Array = key.split("_")
		var vi: int = int(parts[0])
		var band: int = int(parts[1])
		var old_transforms: Array = _band_transforms[vi][band]
		var new_transforms: Array = []
		for t in old_transforms:
			var t_xz := Vector2((t as Transform3D).origin.x, (t as Transform3D).origin.z)
			var keep := true
			for rxz in removed_xz:
				if t_xz.distance_to(rxz) < 0.01:
					keep = false
					break
			if keep:
				new_transforms.append(t)
		_band_transforms[vi][band] = new_transforms
		_rebuild_mmi(vi, band)

	# Remove records (iterate in reverse to preserve indices)
	for i in range(to_remove.size() - 1, -1, -1):
		_tree_records.remove_at(to_remove[i])

# Rebuild the MultiMeshInstance3D for (vi, band) from the current _band_transforms.
# Preserves the existing wind ShaderMaterial.
func _rebuild_mmi(vi: int, band: int) -> void:
	var idx: int = vi * 2 + band
	if idx >= _mmis.size():
		return
	var mmi: MultiMeshInstance3D = _mmis[idx] as MultiMeshInstance3D
	if mmi == null or not is_instance_valid(mmi):
		return

	var transforms: Array = _band_transforms[vi][band]
	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		return

	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i] as Transform3D)
