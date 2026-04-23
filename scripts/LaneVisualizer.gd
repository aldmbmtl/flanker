extends Node3D

const LANE_WIDTH := 6.0
const LANE_HEIGHT := 0.06
const LANE_Y := 0.03  # just above flat terrain
const LANE_COLOR := Color(0.38, 0.30, 0.16)  # dirt brown

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LANE_COLOR
	mat.roughness = 1.0

	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			_place_segment(a, b, mat)

func _place_segment(a: Vector2, b: Vector2, mat: StandardMaterial3D) -> void:
	var seg := b - a
	var length := seg.length()
	if length < 0.01:
		return

	# Midpoint in world space
	var mid := Vector3((a.x + b.x) * 0.5, LANE_Y, (a.y + b.y) * 0.5)

	var box := BoxMesh.new()
	# x=width, y=height, z=length along segment
	box.size = Vector3(LANE_WIDTH, LANE_HEIGHT, length + 0.1)  # +0.1 overlap to avoid gaps
	box.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = mid

	# Rotate to align z-axis with segment direction
	var dir := Vector3(seg.x, 0.0, seg.y).normalized()
	var angle := Vector3.FORWARD.signed_angle_to(dir, Vector3.UP)
	mi.rotation.y = angle

	add_child(mi)
