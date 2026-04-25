extends Node3D

const GRAVITY      := 18.0
const FLIGHT_TIME  := 2.5
const SPLASH_RADIUS := 3.0
const SPLASH_DAMAGE_MULT := 0.5
const MAX_LIFETIME := FLIGHT_TIME + 1.0

var target_pos: Vector3  = Vector3.ZERO
var damage: float        = 50.0
var source: String       = "cannonball"
var shooter_team: int    = -1

var _velocity: Vector3 = Vector3.ZERO
var _age: float        = 0.0
var _light: OmniLight3D = null
var _flicker_timer: float = 0.0
const FLICKER_INTERVAL := 0.05  # update light ~20fps

func _ready() -> void:
	_light = get_node_or_null("OmniLight3D")
	# Tint tracer particle light by team (reuse shared helper material logic)
	# Note: Cannonball uses OmniLight not a mesh tracer, no material needed here.

	# Compute ballistic velocity so we arrive at target_pos in FLIGHT_TIME seconds.
	# x/z components are constant; y must overcome gravity over the arc.
	var start: Vector3 = global_position
	var dt: float = FLIGHT_TIME
	_velocity.x = (target_pos.x - start.x) / dt
	_velocity.z = (target_pos.z - start.z) / dt
	_velocity.y = (target_pos.y - start.y + 0.5 * GRAVITY * dt * dt) / dt

func _process(delta: float) -> void:
	_age += delta
	if _age >= MAX_LIFETIME:
		queue_free()
		return

	var prev_pos: Vector3 = global_position
	_velocity.y -= GRAVITY * delta
	var new_pos: Vector3 = prev_pos + _velocity * delta

	# Raycast for collision
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos)
	var result: Dictionary = space.intersect_ray(query)

	if not result.is_empty():
		_impact(result.position, result.collider)
		return

	global_position = new_pos

	# Flicker the light at reduced rate
	if _light:
		_flicker_timer += delta
		if _flicker_timer >= FLICKER_INTERVAL:
			_flicker_timer = 0.0
			_light.light_energy = randf_range(1.6, 2.4)

func _impact(pos: Vector3, direct_hit: Object) -> void:
	# Tree destruction — check before combat so we still explode + clear even if not damaging anything else
	if direct_hit != null and direct_hit.has_meta("tree_trunk_height"):
		_spawn_tree_impact(pos)
		_request_destroy_tree(pos)
		queue_free()
		return

	# Direct hit damage
	if CombatUtils.should_damage(direct_hit, shooter_team):
		direct_hit.take_damage(damage, "cannonball", shooter_team)

	# Splash damage — nearby bodies in a sphere
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = SPLASH_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.collision_mask = 0xFFFFFFFF
	var overlaps: Array = space.intersect_shape(params, 16)
	for overlap in overlaps:
		var body: Object = overlap.get("collider")
		if body == null or body == direct_hit:
			continue
		if CombatUtils.should_damage(body, shooter_team):
			body.take_damage(damage * SPLASH_DAMAGE_MULT, "cannonball_splash", shooter_team)

	_spawn_impact(pos)
	queue_free()

func _request_destroy_tree(pos: Vector3) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Server — fan out directly to all peers
		LobbyManager.sync_destroy_tree.rpc(pos)
	elif multiplayer.has_multiplayer_peer():
		# Client — send request to server; server fans out
		LobbyManager.request_destroy_tree.rpc_id(1, pos)
	else:
		# Single-player — destroy locally
		var tp: Node = get_tree().root.get_node_or_null("Main/World/TreePlacer")
		if tp != null:
			tp.clear_trees_at(pos, LobbyManager.TREE_DESTROY_RADIUS)

func _spawn_tree_impact(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# ── Layer 1: Wood splinters ───────────────────────────────────────────────
	var p1 := GPUParticles3D.new()
	var pm1 := ParticleProcessMaterial.new()
	pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm1.emission_sphere_radius = 0.2
	pm1.direction = Vector3.UP
	pm1.spread = 150.0
	pm1.initial_velocity_min = 6.0
	pm1.initial_velocity_max = 16.0
	pm1.gravity = Vector3(0.0, -14.0, 0.0)
	pm1.scale_min = 0.15
	pm1.scale_max = 0.4
	var m1 := QuadMesh.new()
	m1.size = Vector2(0.18, 0.06)
	var mat1 := StandardMaterial3D.new()
	mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat1.albedo_color = Color(0.52, 0.32, 0.14, 1.0)
	m1.material = mat1
	p1.process_material = pm1
	p1.draw_pass_1 = m1
	p1.amount = 28
	p1.lifetime = 0.8
	p1.one_shot = true
	p1.explosiveness = 1.0
	root.add_child(p1)
	p1.global_position = pos + Vector3(0.0, 1.0, 0.0)
	p1.emitting = true
	p1.restart()
	get_tree().create_timer(p1.lifetime + 0.1).timeout.connect(p1.queue_free)

	# ── Layer 2: Leaf scatter ─────────────────────────────────────────────────
	var p2 := GPUParticles3D.new()
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = 0.5
	pm2.direction = Vector3.UP
	pm2.spread = 180.0
	pm2.initial_velocity_min = 2.0
	pm2.initial_velocity_max = 7.0
	pm2.gravity = Vector3(0.0, -1.5, 0.0)
	pm2.scale_min = 0.4
	pm2.scale_max = 0.9
	var m2 := QuadMesh.new()
	m2.size = Vector2(0.22, 0.22)
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(0.18, 0.55, 0.12, 0.9)
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.material = mat2
	p2.process_material = pm2
	p2.draw_pass_1 = m2
	p2.amount = 22
	p2.lifetime = 1.8
	p2.one_shot = true
	p2.explosiveness = 0.8
	root.add_child(p2)
	p2.global_position = pos + Vector3(0.0, 1.5, 0.0)
	p2.emitting = true
	p2.restart()
	get_tree().create_timer(p2.lifetime + 0.1).timeout.connect(p2.queue_free)

	# ── Layer 3: Bark dust puff ───────────────────────────────────────────────
	var p3 := GPUParticles3D.new()
	var pm3 := ParticleProcessMaterial.new()
	pm3.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm3.emission_sphere_radius = 0.3
	pm3.direction = Vector3.UP
	pm3.spread = 180.0
	pm3.initial_velocity_min = 1.5
	pm3.initial_velocity_max = 4.0
	pm3.gravity = Vector3(0.0, -3.0, 0.0)
	pm3.scale_min = 0.5
	pm3.scale_max = 1.0
	var m3 := QuadMesh.new()
	m3.size = Vector2(0.5, 0.5)
	var mat3 := StandardMaterial3D.new()
	mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat3.albedo_color = Color(0.42, 0.33, 0.22, 0.7)
	mat3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat3.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m3.material = mat3
	p3.process_material = pm3
	p3.draw_pass_1 = m3
	p3.amount = 14
	p3.lifetime = 1.2
	p3.one_shot = true
	p3.explosiveness = 0.9
	root.add_child(p3)
	p3.global_position = pos + Vector3(0.0, 0.5, 0.0)
	p3.emitting = true
	p3.restart()
	get_tree().create_timer(p3.lifetime + 0.1).timeout.connect(p3.queue_free)

func _should_damage(hit: Object) -> bool:
	if hit == null or not hit.has_method("take_damage"):
		return false
	var hit_team: int = hit.get("team") if hit.get("team") != null else -999
	if shooter_team != -1 and hit_team == shooter_team:
		return false
	if shooter_team == -1 and hit_team == -1:
		return false
	return true

func _spawn_impact(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# ── Layer 1: Fireball core ────────────────────────────────────────────────
	var p1 := GPUParticles3D.new()
	var pm1 := ParticleProcessMaterial.new()
	pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm1.emission_sphere_radius = 0.3
	pm1.direction = Vector3.UP
	pm1.spread = 180.0
	pm1.initial_velocity_min = 8.0
	pm1.initial_velocity_max = 18.0
	pm1.gravity = Vector3(0.0, -6.0, 0.0)
	pm1.scale_min = 0.35
	pm1.scale_max = 0.7
	var m1 := QuadMesh.new()
	m1.size = Vector2(0.5, 0.5)
	var mat1 := StandardMaterial3D.new()
	mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat1.albedo_color = Color(1.0, 0.92, 0.5, 1.0)
	mat1.emission_enabled = true
	mat1.emission = Color(1.0, 0.55, 0.05)
	mat1.emission_energy_multiplier = 5.0
	mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m1.material = mat1
	p1.process_material = pm1
	p1.draw_pass_1 = m1
	p1.amount = 30
	p1.lifetime = 0.35
	p1.one_shot = true
	p1.explosiveness = 1.0
	root.add_child(p1)
	p1.global_position = pos
	p1.emitting = true
	p1.restart()
	get_tree().create_timer(p1.lifetime + 0.1).timeout.connect(p1.queue_free)

	# ── Layer 2: Black smoke column ───────────────────────────────────────────
	var p2 := GPUParticles3D.new()
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = 0.5
	pm2.direction = Vector3.UP
	pm2.spread = 25.0
	pm2.initial_velocity_min = 2.0
	pm2.initial_velocity_max = 5.0
	pm2.gravity = Vector3(0.0, 0.4, 0.0)
	pm2.scale_min = 0.6
	pm2.scale_max = 1.1
	var m2 := QuadMesh.new()
	m2.size = Vector2(0.8, 0.8)
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(0.1, 0.09, 0.08, 0.88)
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.material = mat2
	p2.process_material = pm2
	p2.draw_pass_1 = m2
	p2.amount = 20
	p2.lifetime = 1.5
	p2.one_shot = true
	p2.explosiveness = 0.7
	root.add_child(p2)
	p2.global_position = pos + Vector3(0.0, 0.3, 0.0)
	p2.emitting = true
	p2.restart()
	get_tree().create_timer(p2.lifetime + 0.1).timeout.connect(p2.queue_free)

	# ── Layer 3: Shrapnel sparks ──────────────────────────────────────────────
	var p3 := GPUParticles3D.new()
	var pm3 := ParticleProcessMaterial.new()
	pm3.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm3.emission_sphere_radius = 0.1
	pm3.direction = Vector3.UP
	pm3.spread = 90.0
	pm3.initial_velocity_min = 10.0
	pm3.initial_velocity_max = 22.0
	pm3.gravity = Vector3(0.0, -18.0, 0.0)
	pm3.scale_min = 0.05
	pm3.scale_max = 0.15
	var m3 := QuadMesh.new()
	m3.size = Vector2(0.12, 0.12)
	var mat3 := StandardMaterial3D.new()
	mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat3.albedo_color = Color(1.0, 0.8, 0.1, 1.0)
	mat3.emission_enabled = true
	mat3.emission = Color(1.0, 0.6, 0.0)
	mat3.emission_energy_multiplier = 6.0
	m3.material = mat3
	p3.process_material = pm3
	p3.draw_pass_1 = m3
	p3.amount = 25
	p3.lifetime = 0.6
	p3.one_shot = true
	p3.explosiveness = 1.0
	root.add_child(p3)
	p3.global_position = pos
	p3.emitting = true
	p3.restart()
	get_tree().create_timer(p3.lifetime + 0.1).timeout.connect(p3.queue_free)

	# ── Layer 4: Ground dust ring ─────────────────────────────────────────────
	var p4 := GPUParticles3D.new()
	var pm4 := ParticleProcessMaterial.new()
	pm4.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm4.emission_sphere_radius = 0.2
	pm4.direction = Vector3.UP
	pm4.spread = 180.0
	pm4.initial_velocity_min = 3.0
	pm4.initial_velocity_max = 7.0
	pm4.gravity = Vector3(0.0, -20.0, 0.0)
	pm4.scale_min = 0.25
	pm4.scale_max = 0.55
	var m4 := QuadMesh.new()
	m4.size = Vector2(0.4, 0.4)
	var mat4 := StandardMaterial3D.new()
	mat4.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat4.albedo_color = Color(0.58, 0.45, 0.3, 0.75)
	mat4.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat4.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m4.material = mat4
	p4.process_material = pm4
	p4.draw_pass_1 = m4
	p4.amount = 18
	p4.lifetime = 0.9
	p4.one_shot = true
	p4.explosiveness = 0.95
	root.add_child(p4)
	p4.global_position = pos
	p4.emitting = true
	p4.restart()
	get_tree().create_timer(p4.lifetime + 0.1).timeout.connect(p4.queue_free)

	# ── Flash light ───────────────────────────────────────────────────────────
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.15)
	flash.light_energy = 8.0
	flash.omni_range = 6.0
	flash.shadow_enabled = false
	root.add_child(flash)
	flash.global_position = pos + Vector3(0.0, 0.5, 0.0)
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.tween_callback(flash.queue_free)
