extends Node3D

const BULLET_GRAVITY := 18.0
const MAX_LIFETIME   := 3.0

var velocity: Vector3    = Vector3.ZERO
var damage: float        = 10.0
var source: String       = "unknown"
var shooter_team: int    = -1   # -1 = player, 0/1 = minion team

var _age: float = 0.0
var _mesh_inst: MeshInstance3D = null

func _ready() -> void:
	_mesh_inst = $MeshInstance3D
	# Tint tracer by source
	var mat := StandardMaterial3D.new()
	mat.flags_unshaded = true
	mat.emission_enabled = true
	if shooter_team == -1:
		mat.albedo_color    = Color(1.0, 0.95, 0.6, 1.0)
		mat.emission        = Color(1.0, 0.95, 0.6)
	elif shooter_team == 0:
		mat.albedo_color    = Color(0.4, 0.6, 1.0, 1.0)
		mat.emission        = Color(0.4, 0.6, 1.0)
	else:
		mat.albedo_color    = Color(1.0, 0.4, 0.4, 1.0)
		mat.emission        = Color(1.0, 0.4, 0.4)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	_mesh_inst.material_override = mat

func _process(delta: float) -> void:
	_age += delta
	if _age >= MAX_LIFETIME:
		queue_free()
		return

	var prev_pos: Vector3 = global_position
	velocity.y -= BULLET_GRAVITY * delta
	var new_pos: Vector3 = prev_pos + velocity * delta

	# Raycast between prev and new position to catch collisions
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos)
	var result: Dictionary = space.intersect_ray(query)

	if result.size() > 0:
		var hit: Object = result.collider
		if _should_damage(hit):
			hit.take_damage(damage, source)
		queue_free()
		return

	global_position = new_pos

	# Orient capsule along velocity direction
	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)

func _should_damage(hit: Object) -> bool:
	if not hit.has_method("take_damage"):
		return false
	# Friendly fire: same team = no damage
	var hit_team = hit.get("team") if hit.get("team") != null else -999
	if shooter_team != -1 and hit_team == shooter_team:
		return false
	# Player bullet hitting player = no damage (team == -1 on both sides)
	if shooter_team == -1 and hit_team == -1:
		return false
	return true
