extends Node3D

const LAMP_SPACING  := 6
const ROAD_OFFSET   := 3.2    # distance from lane center to pole base
const POLE_HEIGHT   := 4.0
const ARM_LENGTH    := 1.4    # how far arm extends inward over road
const HANGER_DROP   := 0.85   # wire drop from arm tip
const LIGHT_Y_OFF   := 0.1    # bulb below lamp head center
const LIGHT_RANGE   := 22.0
const LIGHT_ENERGY  := 5.0
const LIGHT_COLOR   := Color(1.0, 0.72, 0.35)
const POLE_COLOR    := Color(0.22, 0.22, 0.26)

func _ready() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = POLE_COLOR
	pole_mat.roughness = 0.85
	pole_mat.metallic = 0.3

	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		for i in range(0, pts.size(), LAMP_SPACING):
			# Lane direction via neighbours
			var prev: Vector2 = pts[max(i - 1, 0)]
			var next: Vector2 = pts[min(i + 1, pts.size() - 1)]
			var dir: Vector2 = (next - prev).normalized()
			# Perpendicular: rotate 90° CCW
			var perp := Vector2(-dir.y, dir.x)
			# Alternate sides per lamp index
			var side_index := i / LAMP_SPACING
			var offset: Vector2 = perp * ROAD_OFFSET if (side_index % 2 == 0) else -perp * ROAD_OFFSET
			# Arm points inward (toward road center), opposite of offset
			var arm_dir: Vector2 = -offset.normalized()

			var center: Vector2 = pts[i]
			var base_xz := Vector2(center.x + offset.x, center.y + offset.y)
			_place_lamp(base_xz, arm_dir, pole_mat)

func _place_lamp(base_xz: Vector2, arm_dir: Vector2, pole_mat: StandardMaterial3D) -> void:
	var root := Node3D.new()
	root.position = Vector3(base_xz.x, 0.0, base_xz.y)
	add_child(root)

	# ── Pole ──────────────────────────────────────────────
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.14, POLE_HEIGHT, 0.14)
	var pole_mi := MeshInstance3D.new()
	pole_mi.mesh = pole_mesh
	pole_mi.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	pole_mi.material_override = pole_mat
	root.add_child(pole_mi)

	# ── Horizontal arm ────────────────────────────────────
	# Arm runs from pole top toward road; centre of arm box is at half ARM_LENGTH
	var arm_cx := arm_dir.x * (ARM_LENGTH * 0.5)
	var arm_cz := arm_dir.y * (ARM_LENGTH * 0.5)
	# Rotate arm mesh to face arm_dir
	var arm_angle := atan2(arm_dir.x, arm_dir.y)  # around Y axis
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.1, 0.1, ARM_LENGTH)
	var arm_mi := MeshInstance3D.new()
	arm_mi.mesh = arm_mesh
	arm_mi.position = Vector3(arm_cx, POLE_HEIGHT - 0.05, arm_cz)
	arm_mi.rotation = Vector3(0.0, arm_angle, 0.0)
	arm_mi.material_override = pole_mat
	root.add_child(arm_mi)

	# ── Hanger wire ───────────────────────────────────────
	var tip_x := arm_dir.x * ARM_LENGTH
	var tip_z := arm_dir.y * ARM_LENGTH
	var wire_mesh := BoxMesh.new()
	wire_mesh.size = Vector3(0.05, HANGER_DROP, 0.05)
	var wire_mi := MeshInstance3D.new()
	wire_mi.mesh = wire_mesh
	wire_mi.position = Vector3(tip_x, POLE_HEIGHT - HANGER_DROP * 0.5 - 0.05, tip_z)
	wire_mi.material_override = pole_mat
	root.add_child(wire_mi)

	# ── Lamp head box ─────────────────────────────────────
	var head_y := POLE_HEIGHT - HANGER_DROP - 0.12
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.38, 0.18, 0.38)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head_mesh
	head_mi.position = Vector3(tip_x, head_y, tip_z)
	head_mi.material_override = pole_mat
	root.add_child(head_mi)

	# ── Emissive bulb ─────────────────────────────────────
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.88, 0.55)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.75, 0.3)
	bulb_mat.emission_energy_multiplier = 5.0
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.1
	bulb_mesh.height = 0.2
	var bulb_mi := MeshInstance3D.new()
	bulb_mi.mesh = bulb_mesh
	bulb_mi.position = Vector3(tip_x, head_y - LIGHT_Y_OFF, tip_z)
	bulb_mi.material_override = bulb_mat
	root.add_child(bulb_mi)

	# ── OmniLight ─────────────────────────────────────────
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.position = Vector3(tip_x, head_y - LIGHT_Y_OFF, tip_z)
	root.add_child(light)
