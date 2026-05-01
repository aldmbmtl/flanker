extends ProjectileBase

const MAX_SPEED            := 55.0
const MIN_SPEED  : float   = 20.0  # forward floor — rocket leaves muzzle fast, player can't outrun it
const RAMP_TIME  : float   = 0.6   # seconds to reach full speed
const RAMP_POWER : float   = 4.0   # quartic curve — near-zero for most of ramp, then snaps hard
const SPLASH_RADIUS        := 8.0
const SPLASH_DAMAGE        := 80.0
const TREE_DESTROY_RADIUS  := 8.0

# ── Swirl constants ───────────────────────────────────────────────────────────
const SWIRL_AMP   : float = 2.5  # slight wobble out of barrel — won't throw shots wide
const SWIRL_HZ    : float = 1.0   # full rotations per second (~1 spiral visible)
const SWIRL_DECAY : float = 4.0   # decays quickly so rocket locks on fast
const SWIRL_START_DIST : float = 2.0   # units of straight flight before spiral begins

const SND_LAUNCH    := "res://assets/kenney_sci-fi-sounds/Audio/thrusterFire_000.ogg"
const SND_EXPLOSION := "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_003.ogg"

var _fire_trail: GPUParticles3D  = null
var _smoke_trail: GPUParticles3D = null

# ── Swirl state ───────────────────────────────────────────────────────────────
var _initial_dir    : Vector3 = Vector3.ZERO
var _swirl_axis1    : Vector3 = Vector3.ZERO
var _swirl_axis2    : Vector3 = Vector3.ZERO
var _swirl_phase    : float   = 0.0     # random per-shot offset so no two spirals look identical
var _forward_dist   : float   = 0.0    # cumulative forward distance traveled
var _swirl_start_age: float   = -1.0   # age when swirl activated; -1 = not yet

func _ready() -> void:
	gravity      = 0.0
	max_lifetime = 6.0
	source       = "rocket"
	can_destroy_trees = true
	_spawn_fire_trail()
	_spawn_smoke_trail()
	SoundManager.play_3d(SND_LAUNCH, global_position, -2.0, randf_range(0.92, 1.05))

	# Cache swirl axes perpendicular to the initial aim direction.
	# No random phase — axis1 is always the consistent rightward cross product,
	# so the spiral always begins with the same directional kick from the barrel.
	# axis2 uses the reversed cross (axis1 × dir) so it points UPWARD — the spiral
	# goes right → up → left → (barely) down, preventing ground collision early on.
	if velocity.length() > 0.0:
		_initial_dir = velocity.normalized()
		var up: Vector3 = Vector3.UP if abs(_initial_dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		_swirl_axis1 = _initial_dir.cross(up).normalized()
		_swirl_axis2 = _swirl_axis1.cross(_initial_dir).normalized()
		_swirl_phase = randf() * TAU

# ── Core loop override ────────────────────────────────────────────────────────
# Identical to ProjectileBase._process except collision_mask excludes layer 2
# (fences and torches) so the rocket passes through them without detonating.

func _process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		_on_expire()
		queue_free()
		return

	var prev_pos: Vector3 = global_position
	var new_pos: Vector3  = prev_pos + velocity * delta

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos)
	query.collision_mask = 0xFFFFFFFB   # all layers except layer 3 (fences / walls)
	var result: Dictionary = space.intersect_ray(query)

	if not result.is_empty():
		_on_hit(result.position, result.collider)
		queue_free()
		return

	global_position = new_pos
	_after_move()

# ── Hooks ─────────────────────────────────────────────────────────────────────

func _after_move() -> void:
	# Quartic power curve: stays near-zero for ~0.6 s then snaps hard to MAX_SPEED.
	# MIN_SPEED floor ensures the rocket always clears terrain while swirling.
	var t: float = clamp(_age / RAMP_TIME, 0.0, 1.0)
	var fwd_speed: float = max(MAX_SPEED * pow(t, RAMP_POWER), MIN_SPEED)

	# Accumulate forward distance. Swirl is gated until SWIRL_START_DIST is covered,
	# so the rocket flies straight from the barrel before the spiral begins.
	# _swirl_start_age is latched once so decay and rotation are anchored to swirl-start.
	_forward_dist += fwd_speed * get_process_delta_time()

	var swirl: Vector3 = Vector3.ZERO
	if _forward_dist >= SWIRL_START_DIST:
		if _swirl_start_age < 0.0:
			_swirl_start_age = _age
		var swirl_age: float = _age - _swirl_start_age
		var swirl_amp: float = SWIRL_AMP * exp(-swirl_age * SWIRL_DECAY)
		var angle: float     = swirl_age * SWIRL_HZ * TAU + _swirl_phase
		swirl = (_swirl_axis1 * cos(angle) + _swirl_axis2 * sin(angle)) * swirl_amp

	velocity = _initial_dir * fwd_speed + swirl

	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)

func _on_hit(pos: Vector3, collider: Object) -> void:
	_detach_trails()

	if collider != null and collider.has_meta("tree_trunk_height"):
		_spawn_explosion(pos)
		_request_destroy_tree(pos)
		return

	if CombatUtils.should_damage(collider, shooter_team):
		collider.take_damage(damage, source, shooter_team, shooter_peer_id)

	_apply_splash(pos, SPLASH_RADIUS, SPLASH_DAMAGE, "rocket_splash", collider)
	_request_destroy_tree(pos)
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

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.6, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 10.0, "vel_max": 28.0, "gravity": Vector3(0.0, -5.0, 0.0),
		"scale_min": 0.6, "scale_max": 1.4, "quad_size": Vector2(0.9, 0.9),
		"color": Color(1.0, 0.85, 0.3, 1.0), "billboard": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.5, 0.02), "emission_energy": 7.0,
		"amount": 55, "lifetime": 0.5, "explosiveness": 1.0})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 1.0, "direction": Vector3.UP, "spread": 35.0,
		"vel_min": 3.0, "vel_max": 9.0, "gravity": Vector3(0.0, 0.6, 0.0),
		"scale_min": 1.0, "scale_max": 2.2, "quad_size": Vector2(1.6, 1.6),
		"color": Color(0.1, 0.09, 0.08, 0.9),
		"amount": 30, "lifetime": 2.0, "explosiveness": 0.6,
		"offset": Vector3(0.0, 0.5, 0.0)})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.2, "direction": Vector3.UP, "spread": 110.0,
		"vel_min": 14.0, "vel_max": 32.0, "gravity": Vector3(0.0, -20.0, 0.0),
		"scale_min": 0.05, "scale_max": 0.18, "quad_size": Vector2(0.14, 0.14),
		"color": Color(1.0, 0.8, 0.1, 1.0), "alpha": false, "billboard": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.55, 0.0), "emission_energy": 8.0,
		"amount": 45, "lifetime": 0.8, "explosiveness": 1.0})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.4, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 5.0, "vel_max": 12.0, "gravity": Vector3(0.0, -22.0, 0.0),
		"scale_min": 0.4, "scale_max": 1.0, "quad_size": Vector2(0.7, 0.7),
		"color": Color(0.58, 0.45, 0.3, 0.75),
		"amount": 28, "lifetime": 1.2, "explosiveness": 0.95})

	VfxUtils.spawn_flash_light(root, pos, {
		"color": Color(1.0, 0.55, 0.1), "energy": 12.0, "range": 14.0,
		"duration": 0.6, "offset": Vector3(0.0, 1.0, 0.0)})
	SoundManager.play_3d(SND_EXPLOSION, pos, 2.0, randf_range(0.88, 1.0))
