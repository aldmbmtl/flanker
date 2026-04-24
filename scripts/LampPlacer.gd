extends Node3D

const LAMP_SPACING   := 6
const ROAD_OFFSET    := 3.2
const POLE_HEIGHT    := 4.0
const ARM_LENGTH     := 1.4
const HANGER_DROP    := 0.85
const LIGHT_Y_OFF    := 0.1
const LIGHT_RANGE    := 22.0
const LIGHT_ENERGY   := 5.0
const LIGHT_COLOR    := Color(1.0, 0.72, 0.35)
const POLE_COLOR     := Color(0.22, 0.22, 0.26)
const BASE_CLEARANCE := 10.0

const ShootableLampScript := preload("res://scripts/ShootableLamp.gd")

# All lamp scripts — queried by MinionAI for darkness checks
var lamp_scripts: Array = []

func _ready() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = POLE_COLOR
	pole_mat.roughness = 0.85
	pole_mat.metallic = 0.3

	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		for i in range(0, pts.size(), LAMP_SPACING):
			var center: Vector2 = pts[i]
			if absf(center.y - 84.0) < BASE_CLEARANCE or absf(center.y + 84.0) < BASE_CLEARANCE:
				continue

			var prev: Vector2 = pts[max(i - 1, 0)]
			var next: Vector2 = pts[min(i + 1, pts.size() - 1)]
			var dir: Vector2 = (next - prev).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var side_index := i / LAMP_SPACING
			var offset: Vector2 = perp * ROAD_OFFSET if (side_index % 2 == 0) else -perp * ROAD_OFFSET
			var arm_dir: Vector2 = -offset.normalized()

			var base_xz := Vector2(center.x + offset.x, center.y + offset.y)
			_place_lamp(base_xz, arm_dir, pole_mat)

	# Noon (time_seed == 1): lamps off, all other times (dusk/sunrise/night): on
	var main: Node = get_node_or_null("/root/Main")
	var is_noon: bool = false
	if main and main.get("time_seed") != null:
		is_noon = (main.time_seed == 1)

	if is_noon:
		for lamp in lamp_scripts:
			lamp._light.visible = false
			lamp._bulb_mat.emission_energy_multiplier = 0.0
			lamp._bulb_mat.albedo_color = Color(0.15, 0.12, 0.08)
			lamp.is_dark = true  # treat as permanently dark (no respawn at noon)

func _place_lamp(base_xz: Vector2, arm_dir: Vector2, pole_mat: StandardMaterial3D) -> void:
	# Root is a StaticBody3D so bullets can raycast-hit it
	var root := StaticBody3D.new()
	root.position = Vector3(base_xz.x, 0.0, base_xz.y)
	root.set_meta("is_lamp", true)
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
	var arm_cx := arm_dir.x * (ARM_LENGTH * 0.5)
	var arm_cz := arm_dir.y * (ARM_LENGTH * 0.5)
	var arm_angle := atan2(arm_dir.x, arm_dir.y)
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
	light.shadow_enabled = true
	light.position = Vector3(tip_x, head_y - LIGHT_Y_OFF, tip_z)
	root.add_child(light)

	# ── Lamp head + bulb collision only (pole is not shootable) ──
	var head_col := CollisionShape3D.new()
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = 0.45
	head_col.shape = head_sphere
	head_col.position = Vector3(tip_x, head_y - LIGHT_Y_OFF, tip_z)
	root.add_child(head_col)

	# ── ShootableLamp script node ──────────────────────────
	var lamp := Node.new()
	lamp.set_script(ShootableLampScript)
	root.add_child(lamp)
	lamp.setup(light, bulb_mi, bulb_mat)
	root.set_meta("lamp_script", lamp)

	lamp_scripts.append(lamp)
