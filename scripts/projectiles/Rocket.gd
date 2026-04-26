extends ProjectileBase

const INITIAL_SPEED        := 0.1
const ACCELERATION         := 120.0
const MAX_SPEED            := 49.0
const SPLASH_RADIUS        := 8.0
const SPLASH_DAMAGE        := 80.0
const TREE_DESTROY_RADIUS  := 8.0

var _fire_trail: GPUParticles3D  = null
var _smoke_trail: GPUParticles3D = null

func _ready() -> void:
	gravity      = 0.0
	max_lifetime = 6.0
	source       = "rocket"
	_spawn_fire_trail()
	_spawn_smoke_trail()

# ── Hooks ─────────────────────────────────────────────────────────────────────

func _after_move() -> void:
	# Accelerate along current direction
	var speed: float = velocity.length()
	if speed > 0.0:
		var dir: Vector3 = velocity / speed
		speed = min(speed + ACCELERATION * get_process_delta_time(), MAX_SPEED)
		velocity = dir * speed
	if speed > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)

func _on_hit(pos: Vector3, collider: Object) -> void:
	_detach_trails()

	if collider != null and collider.has_meta("tree_trunk_height"):
		_spawn_explosion(pos)
		_request_destroy_trees(pos)
		return

	if CombatUtils.should_damage(collider, shooter_team):
		collider.take_damage(damage, source, shooter_team)

	_apply_splash(pos, SPLASH_RADIUS, SPLASH_DAMAGE, "rocket_splash", collider)
	_request_destroy_trees(pos)
	_spawn_explosion(pos)

func _on_expire() -> void:
	_detach_trails()
	_spawn_explosion(global_position)

# ── Trail helpers ─────────────────────────────────────────────────────────────

func _detach_trails() -> void:
	if _fire_trail != null and is_instance_valid(_fire_trail):
		_fire_trail.reparent(get_tree().root)
		_fire_trail.emitting = false
		get_tree().create_timer(_fire_trail.lifetime + 0.1).timeout.connect(_fire_trail.queue_free)
	if _smoke_trail != null and is_instance_valid(_smoke_trail):
		_smoke_trail.reparent(get_tree().root)
		_smoke_trail.emitting = false
		get_tree().create_timer(_smoke_trail.lifetime + 0.3).timeout.connect(_smoke_trail.queue_free)

# ── Tree clearing ─────────────────────────────────────────────────────────────

func _request_destroy_trees(pos: Vector3) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		LobbyManager.sync_destroy_tree.rpc(pos)
	elif multiplayer.has_multiplayer_peer():
		LobbyManager.request_destroy_tree.rpc_id(1, pos)
	else:
		var tp: Node = get_tree().root.get_node_or_null("Main/World/TreePlacer")
		if tp != null:
			tp.clear_trees_at(pos, TREE_DESTROY_RADIUS)

# ── Particle trails ───────────────────────────────────────────────────────────

func _spawn_fire_trail() -> void:
	_fire_trail = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = 10.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.12
	pm.scale_max = 0.28
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.1, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	_fire_trail.process_material = pm
	_fire_trail.draw_pass_1 = mesh
	_fire_trail.amount = 30
	_fire_trail.lifetime = 0.25
	_fire_trail.one_shot = false
	_fire_trail.explosiveness = 0.0
	add_child(_fire_trail)
	_fire_trail.position = Vector3(0.0, 0.0, 0.35)
	_fire_trail.emitting = true

func _spawn_smoke_trail() -> void:
	_smoke_trail = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.0, 0.4, 0.0)
	pm.scale_min = 0.3
	pm.scale_max = 0.7
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.68, 0.65, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	_smoke_trail.process_material = pm
	_smoke_trail.draw_pass_1 = mesh
	_smoke_trail.amount = 20
	_smoke_trail.lifetime = 2.5
	_smoke_trail.one_shot = false
	_smoke_trail.explosiveness = 0.0
	add_child(_smoke_trail)
	_smoke_trail.position = Vector3(0.0, 0.0, 0.35)
	_smoke_trail.emitting = true

# ── Explosion VFX ─────────────────────────────────────────────────────────────

func _spawn_explosion(pos: Vector3) -> void:
	var root: Node = get_tree().root

	var p1 := GPUParticles3D.new()
	var pm1 := ParticleProcessMaterial.new()
	pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm1.emission_sphere_radius = 0.6
	pm1.direction = Vector3.UP
	pm1.spread = 180.0
	pm1.initial_velocity_min = 10.0
	pm1.initial_velocity_max = 28.0
	pm1.gravity = Vector3(0.0, -5.0, 0.0)
	pm1.scale_min = 0.6
	pm1.scale_max = 1.4
	var m1 := QuadMesh.new()
	m1.size = Vector2(0.9, 0.9)
	var mat1 := StandardMaterial3D.new()
	mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat1.albedo_color = Color(1.0, 0.85, 0.3, 1.0)
	mat1.emission_enabled = true
	mat1.emission = Color(1.0, 0.5, 0.02)
	mat1.emission_energy_multiplier = 7.0
	mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m1.material = mat1
	p1.process_material = pm1
	p1.draw_pass_1 = m1
	p1.amount = 55
	p1.lifetime = 0.5
	p1.one_shot = true
	p1.explosiveness = 1.0
	root.add_child(p1)
	p1.global_position = pos
	p1.emitting = true
	p1.restart()
	get_tree().create_timer(p1.lifetime + 0.1).timeout.connect(p1.queue_free)

	var p2 := GPUParticles3D.new()
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = 1.0
	pm2.direction = Vector3.UP
	pm2.spread = 35.0
	pm2.initial_velocity_min = 3.0
	pm2.initial_velocity_max = 9.0
	pm2.gravity = Vector3(0.0, 0.6, 0.0)
	pm2.scale_min = 1.0
	pm2.scale_max = 2.2
	var m2 := QuadMesh.new()
	m2.size = Vector2(1.6, 1.6)
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(0.1, 0.09, 0.08, 0.9)
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.material = mat2
	p2.process_material = pm2
	p2.draw_pass_1 = m2
	p2.amount = 30
	p2.lifetime = 2.0
	p2.one_shot = true
	p2.explosiveness = 0.6
	root.add_child(p2)
	p2.global_position = pos + Vector3(0.0, 0.5, 0.0)
	p2.emitting = true
	p2.restart()
	get_tree().create_timer(p2.lifetime + 0.1).timeout.connect(p2.queue_free)

	var p3 := GPUParticles3D.new()
	var pm3 := ParticleProcessMaterial.new()
	pm3.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm3.emission_sphere_radius = 0.2
	pm3.direction = Vector3.UP
	pm3.spread = 110.0
	pm3.initial_velocity_min = 14.0
	pm3.initial_velocity_max = 32.0
	pm3.gravity = Vector3(0.0, -20.0, 0.0)
	pm3.scale_min = 0.05
	pm3.scale_max = 0.18
	var m3 := QuadMesh.new()
	m3.size = Vector2(0.14, 0.14)
	var mat3 := StandardMaterial3D.new()
	mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat3.albedo_color = Color(1.0, 0.8, 0.1, 1.0)
	mat3.emission_enabled = true
	mat3.emission = Color(1.0, 0.55, 0.0)
	mat3.emission_energy_multiplier = 8.0
	m3.material = mat3
	p3.process_material = pm3
	p3.draw_pass_1 = m3
	p3.amount = 45
	p3.lifetime = 0.8
	p3.one_shot = true
	p3.explosiveness = 1.0
	root.add_child(p3)
	p3.global_position = pos
	p3.emitting = true
	p3.restart()
	get_tree().create_timer(p3.lifetime + 0.1).timeout.connect(p3.queue_free)

	var p4 := GPUParticles3D.new()
	var pm4 := ParticleProcessMaterial.new()
	pm4.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm4.emission_sphere_radius = 0.4
	pm4.direction = Vector3.UP
	pm4.spread = 180.0
	pm4.initial_velocity_min = 5.0
	pm4.initial_velocity_max = 12.0
	pm4.gravity = Vector3(0.0, -22.0, 0.0)
	pm4.scale_min = 0.4
	pm4.scale_max = 1.0
	var m4 := QuadMesh.new()
	m4.size = Vector2(0.7, 0.7)
	var mat4 := StandardMaterial3D.new()
	mat4.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat4.albedo_color = Color(0.58, 0.45, 0.3, 0.75)
	mat4.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat4.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m4.material = mat4
	p4.process_material = pm4
	p4.draw_pass_1 = m4
	p4.amount = 28
	p4.lifetime = 1.2
	p4.one_shot = true
	p4.explosiveness = 0.95
	root.add_child(p4)
	p4.global_position = pos
	p4.emitting = true
	p4.restart()
	get_tree().create_timer(p4.lifetime + 0.1).timeout.connect(p4.queue_free)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.1)
	flash.light_energy = 12.0
	flash.omni_range = 14.0
	flash.shadow_enabled = false
	root.add_child(flash)
	flash.global_position = pos + Vector3(0.0, 1.0, 0.0)
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.6)
	tw.tween_callback(flash.queue_free)
