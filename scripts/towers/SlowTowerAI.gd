extends StaticBody3D
## Slow Tower — pulses every 2s, applies 40% speed debuff for 3s to nearby enemies.

const TOWER_SCENE := preload("res://assets/kenney_pirate-kit/Models/GLB format/tower-complete-small.glb")

const PULSE_INTERVAL := 2.0
const SLOW_DURATION  := 3.0
const SLOW_MULT      := 0.4

var team := 0
var health := 500.0
const MAX_HEALTH := 500.0
var attack_range := 18.0
var _pulse_timer := 0.0
var _dead := false

@onready var area: Area3D = $Area3D

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("towers")
	_load_model()
	var shape := SphereShape3D.new()
	shape.radius = attack_range
	$Area3D/CollisionShape3D.shape = shape

func _load_model() -> void:
	var root: Node3D = TOWER_SCENE.instantiate()
	# Cyan tint to distinguish visually
	root.scale = Vector3(0.9, 0.9, 0.9)
	add_child(root)
	_tint_model(root, Color(0.3, 0.9, 1.0))

func _tint_model(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
		node.material_override = mat
	for child in node.get_children():
		_tint_model(child, color)

func _process(delta: float) -> void:
	if _dead:
		return
	_pulse_timer += delta
	if _pulse_timer >= PULSE_INTERVAL:
		_pulse_timer = 0.0
		_emit_pulse()

func _emit_pulse() -> void:
	_spawn_pulse_vfx()
	for body in area.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		# Get team
		var body_team := -1
		var pt = body.get("player_team")
		if pt != null:
			body_team = pt as int
		else:
			var t = body.get("team")
			if t != null:
				body_team = t as int
		# Only slow enemies with clear LOS
		if body_team == team or body_team == -1:
			continue
		if not _has_line_of_sight(body):
			continue
		if body.has_method("apply_slow"):
			body.apply_slow(SLOW_DURATION, SLOW_MULT)

func _has_line_of_sight(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3(0.0, 1.5, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.8, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var excluded: Array[RID] = [get_rid(), target.get_rid()]
	for _attempt in range(4):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collision_mask = 0b11
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return true
		var body: Object = result.collider
		if body != null and body.has_meta("tree_trunk_height"):
			excluded.append(body.get_rid())
			continue
		return false
	return true

func _spawn_pulse_vfx() -> void:
	var root: Node = get_tree().root
	var origin: Vector3 = global_position + Vector3(0.0, 0.3, 0.0)

	# ── Layer 1: Ground shockwave ring ────────────────────────────────────────
	# Particles emitted outward along the ground plane
	var p1 := GPUParticles3D.new()
	var pm1 := ParticleProcessMaterial.new()
	pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm1.emission_sphere_radius = 0.5
	pm1.direction = Vector3(0.0, 0.05, 0.0)
	pm1.spread = 180.0
	pm1.initial_velocity_min = 6.0
	pm1.initial_velocity_max = 12.0
	pm1.gravity = Vector3(0.0, -28.0, 0.0)  # snap quickly to ground
	pm1.scale_min = 0.15
	pm1.scale_max = 0.35
	var m1 := QuadMesh.new()
	m1.size = Vector2(0.25, 0.25)
	var mat1 := StandardMaterial3D.new()
	mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat1.albedo_color = Color(0.4, 0.95, 1.0, 0.9)
	mat1.emission_enabled = true
	mat1.emission = Color(0.1, 0.85, 1.0)
	mat1.emission_energy_multiplier = 4.0
	mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m1.material = mat1
	p1.process_material = pm1
	p1.draw_pass_1 = m1
	p1.amount = 60
	p1.lifetime = 0.5
	p1.one_shot = true
	p1.explosiveness = 1.0
	root.add_child(p1)
	p1.global_position = origin
	p1.emitting = true
	p1.restart()
	get_tree().create_timer(p1.lifetime + 0.1).timeout.connect(p1.queue_free)

	# ── Layer 2: Rising ice crystal wisps ─────────────────────────────────────
	var p2 := GPUParticles3D.new()
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = attack_range * 0.35
	pm2.direction = Vector3.UP
	pm2.spread = 30.0
	pm2.initial_velocity_min = 3.0
	pm2.initial_velocity_max = 8.0
	pm2.gravity = Vector3(0.0, -1.5, 0.0)
	pm2.scale_min = 0.08
	pm2.scale_max = 0.2
	var m2 := QuadMesh.new()
	m2.size = Vector2(0.15, 0.4)  # tall thin wisp shape
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(0.55, 0.9, 1.0, 0.75)
	mat2.emission_enabled = true
	mat2.emission = Color(0.2, 0.7, 1.0)
	mat2.emission_energy_multiplier = 2.5
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.material = mat2
	p2.process_material = pm2
	p2.draw_pass_1 = m2
	p2.amount = 30
	p2.lifetime = 0.8
	p2.one_shot = true
	p2.explosiveness = 0.85
	root.add_child(p2)
	p2.global_position = origin
	p2.emitting = true
	p2.restart()
	get_tree().create_timer(p2.lifetime + 0.1).timeout.connect(p2.queue_free)

	# ── Layer 3: Central flash burst ──────────────────────────────────────────
	var p3 := GPUParticles3D.new()
	var pm3 := ParticleProcessMaterial.new()
	pm3.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm3.emission_sphere_radius = 0.2
	pm3.direction = Vector3.UP
	pm3.spread = 180.0
	pm3.initial_velocity_min = 3.0
	pm3.initial_velocity_max = 7.0
	pm3.gravity = Vector3.ZERO
	pm3.scale_min = 0.3
	pm3.scale_max = 0.7
	var m3 := QuadMesh.new()
	m3.size = Vector2(0.6, 0.6)
	var mat3 := StandardMaterial3D.new()
	mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat3.albedo_color = Color(0.85, 0.98, 1.0, 0.95)
	mat3.emission_enabled = true
	mat3.emission = Color(0.5, 0.95, 1.0)
	mat3.emission_energy_multiplier = 6.0
	mat3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m3.material = mat3
	p3.process_material = pm3
	p3.draw_pass_1 = m3
	p3.amount = 15
	p3.lifetime = 0.2
	p3.one_shot = true
	p3.explosiveness = 1.0
	root.add_child(p3)
	p3.global_position = origin
	p3.emitting = true
	p3.restart()
	get_tree().create_timer(p3.lifetime + 0.1).timeout.connect(p3.queue_free)

	# ── Flash light ───────────────────────────────────────────────────────────
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.3, 0.9, 1.0)
	flash.light_energy = 5.0
	flash.omni_range = 8.0
	flash.shadow_enabled = false
	root.add_child(flash)
	flash.global_position = origin + Vector3(0.0, 1.0, 0.0)
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if not multiplayer.is_server():
		return
	if _dead:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	_dead = true
	if multiplayer.has_multiplayer_peer():
		LobbyManager.despawn_tower.rpc(name)
	else:
		queue_free()
