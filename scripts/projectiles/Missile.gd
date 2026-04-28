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
	var is_server: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
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
		# Ghost hitbox — remote player in multiplayer; route via GameSync like Bullet/Cannonball do
		if body is StaticBody3D and body.has_meta("ghost_peer_id"):
			var target_peer: int = body.get_meta("ghost_peer_id") as int
			if not GameSync.player_dead.get(target_peer, false):
				var ghost_team: int = GameSync.get_player_team(target_peer)
				if ghost_team != shooter_team:
					var new_hp: float = GameSync.damage_player(target_peer, blast_damage, shooter_team, -1)
					LobbyManager.apply_player_damage.rpc(target_peer, new_hp)
					if new_hp <= 0.0:
						LobbyManager.notify_player_died.rpc(target_peer)
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
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			LobbyManager.sync_destroy_tree.rpc(p)
		elif multiplayer.has_multiplayer_peer():
			LobbyManager.request_destroy_tree.rpc_id(1, p)
		else:
			var tp: Node = get_tree().root.get_node_or_null("Main/World/TreePlacer")
			if tp != null:
				tp.clear_trees_at(p, blast_radius * 0.6)

# ── Massive explosion VFX ─────────────────────────────────────────────────────

func _spawn_explosion(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# ── Layer 1: Primary fireball core — massive, fast burst ──────────────────
	var p1 := GPUParticles3D.new()
	var pm1 := ParticleProcessMaterial.new()
	pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm1.emission_sphere_radius = 1.2
	pm1.direction = Vector3.UP
	pm1.spread = 180.0
	pm1.initial_velocity_min = 18.0
	pm1.initial_velocity_max = 42.0
	pm1.gravity = Vector3(0.0, -4.0, 0.0)
	pm1.scale_min = 1.2
	pm1.scale_max = 2.8
	var m1 := QuadMesh.new()
	m1.size = Vector2(1.8, 1.8)
	var mat1 := StandardMaterial3D.new()
	mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat1.albedo_color = Color(1.0, 0.94, 0.5, 1.0)
	mat1.emission_enabled = true
	mat1.emission = Color(1.0, 0.5, 0.0)
	mat1.emission_energy_multiplier = 8.0
	mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat1.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m1.material = mat1
	p1.process_material = pm1
	p1.draw_pass_1 = m1
	p1.amount = 80
	p1.lifetime = 0.55
	p1.one_shot = true
	p1.explosiveness = 1.0
	root.add_child(p1)
	p1.global_position = pos
	p1.emitting = true
	p1.restart()
	get_tree().create_timer(p1.lifetime + 0.1).timeout.connect(p1.queue_free)

	# ── Layer 2: Secondary orange fireball — slightly delayed, slower ──────────
	var p2 := GPUParticles3D.new()
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = 0.8
	pm2.direction = Vector3.UP
	pm2.spread = 180.0
	pm2.initial_velocity_min = 8.0
	pm2.initial_velocity_max = 22.0
	pm2.gravity = Vector3(0.0, -2.0, 0.0)
	pm2.scale_min = 0.9
	pm2.scale_max = 2.2
	var m2 := QuadMesh.new()
	m2.size = Vector2(1.4, 1.4)
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(1.0, 0.45, 0.08, 0.95)
	mat2.emission_enabled = true
	mat2.emission = Color(0.9, 0.25, 0.0)
	mat2.emission_energy_multiplier = 6.0
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.material = mat2
	p2.process_material = pm2
	p2.draw_pass_1 = m2
	p2.amount = 55
	p2.lifetime = 0.8
	p2.one_shot = true
	p2.explosiveness = 0.9
	root.add_child(p2)
	p2.global_position = pos + Vector3(0.0, 0.5, 0.0)
	p2.emitting = true
	p2.restart()
	get_tree().create_timer(p2.lifetime + 0.1).timeout.connect(p2.queue_free)

	# ── Layer 3: Towering black smoke column ──────────────────────────────────
	var p3 := GPUParticles3D.new()
	var pm3 := ParticleProcessMaterial.new()
	pm3.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm3.emission_sphere_radius = 2.0
	pm3.direction = Vector3.UP
	pm3.spread = 30.0
	pm3.initial_velocity_min = 5.0
	pm3.initial_velocity_max = 14.0
	pm3.gravity = Vector3(0.0, 0.6, 0.0)
	pm3.scale_min = 1.5
	pm3.scale_max = 3.5
	var m3 := QuadMesh.new()
	m3.size = Vector2(2.5, 2.5)
	var mat3 := StandardMaterial3D.new()
	mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat3.albedo_color = Color(0.08, 0.07, 0.06, 0.9)
	mat3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat3.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m3.material = mat3
	p3.process_material = pm3
	p3.draw_pass_1 = m3
	p3.amount = 50
	p3.lifetime = 4.5
	p3.one_shot = true
	p3.explosiveness = 0.6
	root.add_child(p3)
	p3.global_position = pos + Vector3(0.0, 1.0, 0.0)
	p3.emitting = true
	p3.restart()
	get_tree().create_timer(p3.lifetime + 0.1).timeout.connect(p3.queue_free)

	# ── Layer 4: Shockwave ring — flat, expanding outward ─────────────────────
	var p4 := GPUParticles3D.new()
	var pm4 := ParticleProcessMaterial.new()
	pm4.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm4.emission_sphere_radius = 0.3
	pm4.direction = Vector3(0.0, 0.0, 1.0)  # will be overridden by orbit
	pm4.spread = 180.0
	pm4.initial_velocity_min = 20.0
	pm4.initial_velocity_max = 38.0
	pm4.gravity = Vector3(0.0, -50.0, 0.0)  # snap to ground quickly
	pm4.scale_min = 0.4
	pm4.scale_max = 0.9
	var m4 := QuadMesh.new()
	m4.size = Vector2(0.6, 0.6)
	var mat4 := StandardMaterial3D.new()
	mat4.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat4.albedo_color = Color(0.9, 0.75, 0.55, 0.7)
	mat4.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat4.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m4.material = mat4
	p4.process_material = pm4
	p4.draw_pass_1 = m4
	p4.amount = 120
	p4.lifetime = 0.5
	p4.one_shot = true
	p4.explosiveness = 1.0
	root.add_child(p4)
	p4.global_position = pos + Vector3(0.0, 0.1, 0.0)
	p4.emitting = true
	p4.restart()
	get_tree().create_timer(p4.lifetime + 0.1).timeout.connect(p4.queue_free)

	# ── Layer 5: Heavy shrapnel — high velocity, long travel ─────────────────
	var p5 := GPUParticles3D.new()
	var pm5 := ParticleProcessMaterial.new()
	pm5.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm5.emission_sphere_radius = 0.3
	pm5.direction = Vector3.UP
	pm5.spread = 85.0
	pm5.initial_velocity_min = 22.0
	pm5.initial_velocity_max = 55.0
	pm5.gravity = Vector3(0.0, -20.0, 0.0)
	pm5.scale_min = 0.08
	pm5.scale_max = 0.22
	var m5 := QuadMesh.new()
	m5.size = Vector2(0.18, 0.18)
	var mat5 := StandardMaterial3D.new()
	mat5.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat5.albedo_color = Color(1.0, 0.82, 0.15, 1.0)
	mat5.emission_enabled = true
	mat5.emission = Color(1.0, 0.55, 0.0)
	mat5.emission_energy_multiplier = 7.0
	m5.material = mat5
	p5.process_material = pm5
	p5.draw_pass_1 = m5
	p5.amount = 90
	p5.lifetime = 1.4
	p5.one_shot = true
	p5.explosiveness = 1.0
	root.add_child(p5)
	p5.global_position = pos
	p5.emitting = true
	p5.restart()
	get_tree().create_timer(p5.lifetime + 0.1).timeout.connect(p5.queue_free)

	# ── Layer 6: Wide ground dust — large radius ──────────────────────────────
	var p6 := GPUParticles3D.new()
	var pm6 := ParticleProcessMaterial.new()
	pm6.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm6.emission_sphere_radius = 1.0
	pm6.direction = Vector3.UP
	pm6.spread = 180.0
	pm6.initial_velocity_min = 8.0
	pm6.initial_velocity_max = 20.0
	pm6.gravity = Vector3(0.0, -18.0, 0.0)
	pm6.scale_min = 0.8
	pm6.scale_max = 2.0
	var m6 := QuadMesh.new()
	m6.size = Vector2(1.2, 1.2)
	var mat6 := StandardMaterial3D.new()
	mat6.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat6.albedo_color = Color(0.62, 0.49, 0.33, 0.8)
	mat6.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat6.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m6.material = mat6
	p6.process_material = pm6
	p6.draw_pass_1 = m6
	p6.amount = 60
	p6.lifetime = 2.2
	p6.one_shot = true
	p6.explosiveness = 0.95
	root.add_child(p6)
	p6.global_position = pos
	p6.emitting = true
	p6.restart()
	get_tree().create_timer(p6.lifetime + 0.1).timeout.connect(p6.queue_free)

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
	var flash := OmniLight3D.new()
	flash.light_color   = Color(1.0, 0.65, 0.2)
	flash.light_energy  = 18.0
	flash.omni_range    = 40.0
	flash.shadow_enabled = false
	root.add_child(flash)
	flash.global_position = pos + Vector3(0.0, 1.5, 0.0)
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.8)
	tw.tween_callback(flash.queue_free)

	# ── Screen shake — broadcast to any local cameras ──────────────────────────
	_do_screen_shake(pos)
	SoundManager.play_3d(SND_EXPLOSION, pos, 4.0, randf_range(0.85, 1.0))

func _spawn_secondary_fireball(pos: Vector3) -> void:
	var root: Node = get_tree().root
	var ps := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0.0, -5.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var m := QuadMesh.new()
	m.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.1, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.3, 0.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.material = mat
	ps.process_material = pm
	ps.draw_pass_1 = m
	ps.amount = 25
	ps.lifetime = 0.45
	ps.one_shot = true
	ps.explosiveness = 1.0
	root.add_child(ps)
	ps.global_position = pos
	ps.emitting = true
	ps.restart()
	get_tree().create_timer(ps.lifetime + 0.1).timeout.connect(ps.queue_free)

	# Mini flash per secondary
	var mini_flash := OmniLight3D.new()
	mini_flash.light_color  = Color(1.0, 0.5, 0.1)
	mini_flash.light_energy = 5.0
	mini_flash.omni_range   = 10.0
	root.add_child(mini_flash)
	mini_flash.global_position = pos
	var tw2: Tween = mini_flash.create_tween()
	tw2.tween_property(mini_flash, "light_energy", 0.0, 0.3)
	tw2.tween_callback(mini_flash.queue_free)

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
