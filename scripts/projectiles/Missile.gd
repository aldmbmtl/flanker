extends ProjectileBase
## Missile — ballistic projectile fired by LauncherTower.
## Stats come from LauncherDefs at configure() time — no hardcoded values.
## Visuals: exhaust trail while flying + massive multi-layer explosion on impact.
## Damage applied server-side only (multiplayer) or locally (singleplayer).

const GRAVITY: float = 18.0

const SND_EXPLOSION := "res://assets/kenney_sci-fi-sounds/Audio/lowFrequency_explosion_000.ogg"

# Configured before add_child via configure()
var target_pos: Vector3  = Vector3.ZERO
var fire_pos: Vector3    = Vector3.ZERO
var blast_radius: float  = 12.0
var blast_damage: float  = 400.0
var flight_time: float   = 4.0
var launcher_type: String = "launcher_missile"

var _max_lifetime: float = 0.0

# Visual nodes
var _exhaust: GPUParticles3D = null
var _trail_light: OmniLight3D = null

# ── Configure (call BEFORE add_child so _ready() sees values) ─────────────────

func configure(def: Dictionary, p_team: int, p_fire: Vector3, p_target: Vector3, p_type: String, p_shooter_peer_id: int = -1) -> void:
	shooter_team     = p_team
	shooter_peer_id  = p_shooter_peer_id
	fire_pos         = p_fire
	target_pos       = p_target
	launcher_type    = p_type
	blast_radius     = float(def.get("blast_radius", 12.0))
	blast_damage     = float(def.get("blast_damage", 400.0))
	flight_time      = float(def.get("flight_time", 4.0))

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	gravity      = 0.0   # Missile owns its own _process; base gravity not used
	_max_lifetime = flight_time + 1.5
	can_destroy_trees = true

	# Ballistic arc: x/z constant, y overcomes gravity over flight_time.
	# Use fire_pos set via configure() — global_position is not yet valid in _ready().
	velocity.x = (target_pos.x - fire_pos.x) / flight_time
	velocity.z = (target_pos.z - fire_pos.z) / flight_time
	velocity.y = (target_pos.y - fire_pos.y + 0.5 * GRAVITY * flight_time * flight_time) / flight_time

	_build_visuals()

func _build_visuals() -> void:
	# ── Rocket body (elongated capsule) ───────────────────────────────────────
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 1.4
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.85, 0.85)
	body_mat.roughness = 0.35
	body_mat.metallic  = 0.8
	body_mesh.material = body_mat
	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body_mesh
	body_inst.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(body_inst)

	# ── Nose cone ─────────────────────────────────────────────────────────────
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius    = 0.0
	nose_mesh.bottom_radius = 0.22
	nose_mesh.height        = 0.45
	nose_mesh.radial_segments = 10
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.9, 0.2, 0.1)
	nose_mat.roughness = 0.4
	nose_mesh.material = nose_mat
	var nose_inst := MeshInstance3D.new()
	nose_inst.mesh = nose_mesh
	nose_inst.position = Vector3(0.0, 0.85, 0.0)
	add_child(nose_inst)

	# ── Exhaust trail particles ────────────────────────────────────────────────
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 15.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.1

	var em := QuadMesh.new()
	em.size = Vector2(0.35, 0.35)
	var em_mat := StandardMaterial3D.new()
	em_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	em_mat.emission_enabled = true
	em_mat.emission = Color(1.0, 0.3, 0.0)
	em_mat.emission_energy_multiplier = 4.0
	em_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	em.material = em_mat

	_exhaust = GPUParticles3D.new()
	_exhaust.process_material = pm
	_exhaust.draw_pass_1 = em
	_exhaust.amount = 40
	_exhaust.lifetime = 0.55
	_exhaust.one_shot = false
	_exhaust.explosiveness = 0.0
	_exhaust.position = Vector3(0.0, -0.75, 0.0)
	add_child(_exhaust)
	_exhaust.emitting = true

	# ── Trail light ───────────────────────────────────────────────────────────
	_trail_light = OmniLight3D.new()
	_trail_light.light_color  = Color(1.0, 0.5, 0.1)
	_trail_light.light_energy = 3.0
	_trail_light.omni_range   = 10.0
	_trail_light.shadow_enabled = false
	add_child(_trail_light)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _max_lifetime:
		queue_free()
		return

	var prev_pos: Vector3 = global_position
	velocity.y -= GRAVITY * delta
	var new_pos: Vector3 = prev_pos + velocity * delta

	if velocity.length_squared() > 0.01:
		look_at(new_pos, Vector3.UP)

	# Flicker trail light
	if _trail_light:
		_trail_light.light_energy = randf_range(2.5, 4.0)

	# Collision raycast — all layers so players, towers, and terrain all trigger impact
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos)
	var result: Dictionary = space.intersect_ray(query)

	if not result.is_empty():
		_impact(result.position)
		return

	# Also detonate if we've passed below target height (overshot edge)
	if prev_pos.y > target_pos.y and new_pos.y <= target_pos.y:
		_impact(new_pos)
		return

	global_position = new_pos

# ── Impact ────────────────────────────────────────────────────────────────────

func _impact(pos: Vector3) -> void:
	# Stop emitting trail
	if _exhaust and is_instance_valid(_exhaust):
		_exhaust.emitting = false

	# Apply damage server-side (or singleplayer)
	var is_server: bool = BridgeClient.is_host()
	if is_server:
		_apply_blast_damage(pos)

	# VFX — runs on all peers
	_spawn_explosion(pos)

	queue_free()

func _apply_blast_damage(pos: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.collision_mask = 0xFFFFFFFF
	var overlaps: Array = space.intersect_shape(params, 64)

	for overlap in overlaps:
		var body: Object = overlap.get("collider")
		if body == null:
			continue
		# Ghost hitbox — route via GameSync like other projectiles do
		if _handle_ghost_hit(body, blast_damage):
			continue
		# All other damageable bodies — CombatUtils handles player_team fallback + friendly-fire guard
		if CombatUtils.should_damage(body, shooter_team):
			body.take_damage(blast_damage, "missile", shooter_team, shooter_peer_id)

	# Destroy trees in blast radius
	_request_destroy_trees_in_radius(pos)

func _request_destroy_trees_in_radius(pos: Vector3) -> void:
	# Fire multiple tree-destroy calls at cardinal offsets to cover the radius
	var offsets: Array = [
		Vector3.ZERO,
		Vector3(blast_radius * 0.5,  0.0, 0.0),
		Vector3(-blast_radius * 0.5, 0.0, 0.0),
		Vector3(0.0, 0.0,  blast_radius * 0.5),
		Vector3(0.0, 0.0, -blast_radius * 0.5),
	]
	for off in offsets:
		var p: Vector3 = pos + off
		LobbyManager.request_destroy_tree(p)

# ── Massive explosion VFX ─────────────────────────────────────────────────────

func _spawn_explosion(pos: Vector3) -> void:
	var root: Node = get_tree().root

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 1.2, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 18.0, "vel_max": 42.0, "gravity": Vector3(0.0, -4.0, 0.0),
		"scale_min": 1.2, "scale_max": 2.8, "quad_size": Vector2(1.8, 1.8),
		"color": Color(1.0, 0.94, 0.5, 1.0),
		"emission_enabled": true, "emission_color": Color(1.0, 0.5, 0.0), "emission_energy": 8.0,
		"amount": 80, "lifetime": 0.55, "explosiveness": 1.0})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.8, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 8.0, "vel_max": 22.0, "gravity": Vector3(0.0, -2.0, 0.0),
		"scale_min": 0.9, "scale_max": 2.2, "quad_size": Vector2(1.4, 1.4),
		"color": Color(1.0, 0.45, 0.08, 0.95),
		"emission_enabled": true, "emission_color": Color(0.9, 0.25, 0.0), "emission_energy": 6.0,
		"amount": 55, "lifetime": 0.8, "explosiveness": 0.9,
		"offset": Vector3(0.0, 0.5, 0.0)})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 2.0, "direction": Vector3.UP, "spread": 30.0,
		"vel_min": 5.0, "vel_max": 14.0, "gravity": Vector3(0.0, 0.6, 0.0),
		"scale_min": 1.5, "scale_max": 3.5, "quad_size": Vector2(2.5, 2.5),
		"color": Color(0.08, 0.07, 0.06, 0.9),
		"amount": 50, "lifetime": 4.5, "explosiveness": 0.6,
		"offset": Vector3(0.0, 1.0, 0.0)})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.3, "direction": Vector3(0.0, 0.0, 1.0), "spread": 180.0,
		"vel_min": 20.0, "vel_max": 38.0, "gravity": Vector3(0.0, -50.0, 0.0),
		"scale_min": 0.4, "scale_max": 0.9, "quad_size": Vector2(0.6, 0.6),
		"color": Color(0.9, 0.75, 0.55, 0.7),
		"amount": 120, "lifetime": 0.5, "explosiveness": 1.0,
		"offset": Vector3(0.0, 0.1, 0.0)})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.3, "direction": Vector3.UP, "spread": 85.0,
		"vel_min": 22.0, "vel_max": 55.0, "gravity": Vector3(0.0, -20.0, 0.0),
		"scale_min": 0.08, "scale_max": 0.22, "quad_size": Vector2(0.18, 0.18),
		"color": Color(1.0, 0.82, 0.15, 1.0), "alpha": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.55, 0.0), "emission_energy": 7.0,
		"amount": 90, "lifetime": 1.4, "explosiveness": 1.0})

	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 1.0, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 8.0, "vel_max": 20.0, "gravity": Vector3(0.0, -18.0, 0.0),
		"scale_min": 0.8, "scale_max": 2.0, "quad_size": Vector2(1.2, 1.2),
		"color": Color(0.62, 0.49, 0.33, 0.8),
		"amount": 60, "lifetime": 2.2, "explosiveness": 0.95})

	# ── Layer 7: Secondary mini-fireballs — scatter in blast zone ─────────────
	var rng := RandomNumberGenerator.new()
	for i in range(5):
		var delay: float = rng.randf_range(0.05, 0.35)
		var offset := Vector3(
			rng.randf_range(-blast_radius * 0.55, blast_radius * 0.55),
			rng.randf_range(0.0, 2.5),
			rng.randf_range(-blast_radius * 0.55, blast_radius * 0.55)
		)
		get_tree().create_timer(delay).timeout.connect(
			func() -> void: _spawn_secondary_fireball(pos + offset)
		)

	# ── Massive flash light ────────────────────────────────────────────────────
	VfxUtils.spawn_flash_light(root, pos, {
		"color": Color(1.0, 0.65, 0.2), "energy": 18.0, "range": 40.0,
		"duration": 0.8, "offset": Vector3(0.0, 1.5, 0.0)})

	# ── Screen shake — broadcast to any local cameras ──────────────────────────
	_do_screen_shake(pos)
	SoundManager.play_3d(SND_EXPLOSION, pos, 4.0, randf_range(0.85, 1.0))

func _spawn_secondary_fireball(pos: Vector3) -> void:
	var root: Node = get_tree().root
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.4, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 5.0, "vel_max": 14.0, "gravity": Vector3(0.0, -5.0, 0.0),
		"scale_min": 0.5, "scale_max": 1.3, "quad_size": Vector2(0.9, 0.9),
		"color": Color(1.0, 0.6, 0.1, 0.95),
		"emission_enabled": true, "emission_color": Color(0.9, 0.3, 0.0), "emission_energy": 5.0,
		"amount": 25, "lifetime": 0.45, "explosiveness": 1.0})

	# Mini flash per secondary
	VfxUtils.spawn_flash_light(root, pos, {
		"color": Color(1.0, 0.5, 0.1), "energy": 5.0, "range": 10.0,
		"duration": 0.3, "offset": Vector3.ZERO})

func _do_screen_shake(impact_pos: Vector3) -> void:
	# Apply camera shake to any Camera3D currently in the scene that is active.
	# Uses a simple position-offset impulse on the camera node itself.
	# Attenuates by distance — full shake within 20 units, none beyond 80.
	var MAX_DIST: float = 80.0
	var MIN_DIST: float = 20.0
	var SHAKE_STRENGTH: float = 0.55
	var SHAKE_DURATION: float = 0.45
	var SHAKE_FREQ: int      = 12

	for cam in get_tree().get_nodes_in_group("cameras"):
		if cam is Camera3D and (cam as Camera3D).current:
			_shake_camera(cam, impact_pos, MAX_DIST, MIN_DIST, SHAKE_STRENGTH, SHAKE_DURATION, SHAKE_FREQ)
			return

	# Fallback: shake the currently active viewport camera
	var vp: Viewport = get_tree().root
	var cam: Camera3D = vp.get_camera_3d()
	if cam != null:
		_shake_camera(cam, impact_pos, MAX_DIST, MIN_DIST, SHAKE_STRENGTH, SHAKE_DURATION, SHAKE_FREQ)

func _shake_camera(cam: Camera3D, impact_pos: Vector3,
		max_dist: float, min_dist: float,
		strength: float, duration: float, freq: int) -> void:
	var dist: float = cam.global_position.distance_to(impact_pos)
	var t: float = 1.0 - clampf((dist - min_dist) / (max_dist - min_dist), 0.0, 1.0)
	if t <= 0.01:
		return
	var actual_strength: float = strength * t
	var steps: int = int(duration * float(freq))
	var tween: Tween = cam.create_tween()
	var origin: Vector3 = cam.position
	for i in range(steps):
		var decay: float = 1.0 - float(i) / float(steps)
		var r := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-0.3, 0.3)
		).normalized() * actual_strength * decay
		tween.tween_property(cam, "position", origin + r, 1.0 / float(freq))
	tween.tween_property(cam, "position", origin, 1.0 / float(freq))
