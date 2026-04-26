extends Node3D

const FENCE_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/fence.glb"

const LANE_WIDTH := 6.0
const FENCE_OFFSET := 3.3        # half-lane + small gap from dirt ribbon edge
const FENCE_SPACING := 4.0       # world units between fence piece centers (2x scale)
const FENCE_SCALE := 3.0

# Collision box: x=rail thickness, y=height, z=length along lane direction
const FENCE_COL_SIZE := Vector3(0.15, 1.2, 2.0)
const INTERSECTION_CLEAR := LANE_WIDTH / 2.0 + 1.0  # skip fence near other lanes
const FENCE_GAP_CHANCE := 0.2  # probability a fence piece is skipped

const TORCH_CHANCE := 0.15
const TORCH_HEIGHT := 1.5       # local Y offset on fence body (tune as needed)
const TORCH_LIGHT_RANGE := 4.0
const TORCH_LIGHT_ENERGY := 1.5
const TORCH_LIGHT_COLOR := Color(1.0, 0.38, 0.04)
const TORCH_MIN_DIST := FENCE_SPACING * 3.0  # min distance between torches

@onready var _terrain_body: StaticBody3D = null
var _last_torch_pos := Vector3(INF, INF, INF)

# Accumulated fence visual transforms for MultiMesh batching
# _fence_transforms[i] = Transform3D
var _fence_transforms: Array[Transform3D] = []
var _fence_mesh: Mesh = null

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	seed(GameSync.game_seed)
	_terrain_body = _find_terrain()

	var fence_scene: PackedScene = load(FENCE_PATH)
	if fence_scene == null:
		push_error("FencePlacer: failed to load " + FENCE_PATH)
		return

	# Extract mesh from the GLB for MultiMesh use
	_fence_mesh = _extract_first_mesh(fence_scene)

	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		_place_lane_fences(pts, lane_i)

	_commit_fence_multimesh()

func _extract_first_mesh(scene: PackedScene) -> Mesh:
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

func _commit_fence_multimesh() -> void:
	if _fence_mesh == null or _fence_transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.mesh = _fence_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = _fence_transforms.size()
	for i in _fence_transforms.size():
		mm.set_instance_transform(i, _fence_transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _place_lane_fences(pts: Array, lane_i: int) -> void:
	for side in [-1, 1]:
		var carry: float = 0.0

		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg: Vector2 = b - a
			var seg_len: float = seg.length()
			if seg_len < 0.001:
				continue

			var seg_dir: Vector2 = seg / seg_len
			var perp: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
			var edge_a: Vector2 = a + perp * (FENCE_OFFSET * float(side))

			var t: float = FENCE_SPACING - carry
			while t <= seg_len:
				var world_xz: Vector2 = edge_a + seg_dir * t
				var center_xz: Vector2 = a + seg_dir * t
				if not _is_near_other_lane(center_xz, lane_i) and randf() >= FENCE_GAP_CHANCE:
					var world_pos := Vector3(world_xz.x, 0.0, world_xz.y)
					_spawn_fence(world_pos, seg_dir)
				t += FENCE_SPACING

			carry = fmod(carry + seg_len, FENCE_SPACING)

func _spawn_fence(pos: Vector3, seg_dir: Vector2) -> void:
	# Collision-only StaticBody3D (no visual mesh child)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = pos

	var dir3 := Vector3(seg_dir.x, 0.0, seg_dir.y).normalized()
	var angle: float = Vector3.FORWARD.signed_angle_to(dir3, Vector3.UP)
	body.rotation.y = angle

	var col_shape := BoxShape3D.new()
	col_shape.size = FENCE_COL_SIZE
	var col_node := CollisionShape3D.new()
	col_node.shape = col_shape
	col_node.position = Vector3(0.0, FENCE_COL_SIZE.y * 0.5, 0.0)
	body.add_child(col_node)

	add_child(body)

	# Accumulate visual transform for MultiMesh
	# Build rotation-only basis first so the -1.25 local offset is applied at
	# model scale (pre-scale), then scale the basis afterwards.
	var rot_basis := Basis(Vector3.UP, angle)
	var world_offset: Vector3 = rot_basis * Vector3(-1.25, 0.0, 0.0)
	var t := Transform3D()
	t.basis = rot_basis.scaled(Vector3(FENCE_SCALE, FENCE_SCALE, FENCE_SCALE))
	t.origin = pos + world_offset
	_fence_transforms.append(t)

	if randf() < TORCH_CHANCE and pos.distance_to(_last_torch_pos) >= TORCH_MIN_DIST:
		_add_torch(body)
		_last_torch_pos = pos

func _add_torch(body: StaticBody3D) -> void:
	var torch_root := Node3D.new()
	torch_root.position = Vector3(0.15, TORCH_HEIGHT, 1.4)
	body.add_child(torch_root)

	# Stick — thin cylinder
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.04
	stick_mesh.bottom_radius = 0.06
	stick_mesh.height = 0.6
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.35, 0.2, 0.08)
	stick_mesh.surface_set_material(0, stick_mat)
	var stick_mi := MeshInstance3D.new()
	stick_mi.mesh = stick_mesh
	stick_mi.position = Vector3(0.0, 0.0, 0.0)
	torch_root.add_child(stick_mi)

	# Flame light
	var light := OmniLight3D.new()
	light.light_color = TORCH_LIGHT_COLOR
	light.light_energy = TORCH_LIGHT_ENERGY
	light.omni_range = TORCH_LIGHT_RANGE
	light.position = Vector3(0.0, 0.4, 0.0)
	torch_root.add_child(light)

	# Fire particles — with custom visibility AABB for culling
	var particles := GPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 0.5
	particles.explosiveness = 0.0
	particles.position = Vector3(0.0, 0.4, 0.0)
	# Small AABB so the GPU culls this when off-screen
	particles.visibility_aabb = AABB(Vector3(-0.5, -0.1, -0.5), Vector3(1.0, 1.2, 1.0))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 18.0
	pmat.initial_velocity_min = 0.8
	pmat.initial_velocity_max = 1.6
	pmat.gravity = Vector3(0.0, -0.3, 0.0)
	pmat.scale_min = 0.3
	pmat.scale_max = 0.5

	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.05, 1.0))
	grad.add_point(0.5, Color(1.0, 0.9, 0.1, 0.6))
	grad.add_point(1.0, Color(0.15, 0.15, 0.15, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pmat.color_ramp = grad_tex

	particles.process_material = pmat

	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.06
	flame_mesh.height = 0.12
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.5, 0.05)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.4, 0.0)
	flame_mat.emission_energy_multiplier = 2.0
	flame_mesh.surface_set_material(0, flame_mat)
	particles.draw_pass_1 = flame_mesh

	torch_root.add_child(particles)

func _is_near_other_lane(pos: Vector2, skip_lane: int) -> bool:
	for lane_i in range(3):
		if lane_i == skip_lane:
			continue
		var pts: Array = LaneData.get_lane_points(lane_i)
		if LaneData.dist_to_polyline(pos, pts) < INTERSECTION_CLEAR:
			return true
	return false

func _get_terrain_height(pos: Vector3) -> float:
	if _terrain_body == null:
		return 0.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var from := Vector3(pos.x, 50.0, pos.z)
	var to   := Vector3(pos.x, -10.0, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result.position.y

func _find_terrain() -> StaticBody3D:
	if has_node("/root/Main/World/Terrain"):
		return $/root/Main/World/Terrain
	return null
