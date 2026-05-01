extends ProjectileBase

const FLIGHT_TIME        := 2.5
const SPLASH_RADIUS      := 3.0
const SPLASH_DAMAGE_MULT := 0.5

const SND_EXPLOSION := "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_000.ogg"
const SND_WOOD      := "res://assets/kenney_impact-sounds/Audio/impactWood_heavy_000.ogg"

var target_pos: Vector3 = Vector3.ZERO

var _light: OmniLight3D = null
var _flicker_timer: float = 0.0
const FLICKER_INTERVAL := 0.05

func _ready() -> void:
	max_lifetime = FLIGHT_TIME + 1.0
	_light = get_node_or_null("OmniLight3D")

	# Ballistic arc: arrive at target_pos in FLIGHT_TIME seconds.
	init_ballistic_arc(target_pos, FLIGHT_TIME)

# ── Hit handling ──────────────────────────────────────────────────────────────

func _on_hit(pos: Vector3, collider: Object) -> void:
	# Tree hit — wood/leaf VFX, destroy tree, no combat damage
	if collider != null and collider.has_meta("tree_trunk_height"):
		_spawn_tree_impact(pos)
		_request_destroy_tree(pos)
		SoundManager.play_3d(SND_WOOD, pos, 0.0, randf_range(0.9, 1.1))
		return

	var is_server: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_server:
		if not _handle_ghost_hit(collider, damage):
			if CombatUtils.should_damage(collider, shooter_team):
				collider.take_damage(damage, "cannonball", shooter_team)
		_apply_splash(pos, SPLASH_RADIUS, damage * SPLASH_DAMAGE_MULT, "cannonball_splash", collider)
	_spawn_impact(pos)
	SoundManager.play_3d(SND_EXPLOSION, pos, 0.0, randf_range(0.88, 1.05))

# ── Trail flicker ─────────────────────────────────────────────────────────────

func _after_move() -> void:
	if _light:
		_flicker_timer += get_process_delta_time()
		if _flicker_timer >= FLICKER_INTERVAL:
			_flicker_timer = 0.0
			_light.light_energy = randf_range(1.6, 2.4)

# ── Tree clearing ─────────────────────────────────────────────────────────────
# _request_destroy_tree is inherited from ProjectileBase.

# ── VFX ───────────────────────────────────────────────────────────────────────

func _spawn_tree_impact(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# Layer 1: Wood splinters
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.2, "direction": Vector3.UP, "spread": 150.0,
		"vel_min": 6.0, "vel_max": 16.0, "gravity": Vector3(0.0, -14.0, 0.0),
		"scale_min": 0.15, "scale_max": 0.4, "quad_size": Vector2(0.18, 0.06),
		"color": Color(0.52, 0.32, 0.14, 1.0), "alpha": false, "billboard": false,
		"amount": 28, "lifetime": 0.8, "explosiveness": 1.0,
		"offset": Vector3(0.0, 1.0, 0.0)})

	# Layer 2: Leaf scatter
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.5, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 2.0, "vel_max": 7.0, "gravity": Vector3(0.0, -1.5, 0.0),
		"scale_min": 0.4, "scale_max": 0.9, "quad_size": Vector2(0.22, 0.22),
		"color": Color(0.18, 0.55, 0.12, 0.9),
		"amount": 22, "lifetime": 1.8, "explosiveness": 0.8,
		"offset": Vector3(0.0, 1.5, 0.0)})

	# Layer 3: Bark dust puff
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.3, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 1.5, "vel_max": 4.0, "gravity": Vector3(0.0, -3.0, 0.0),
		"scale_min": 0.5, "scale_max": 1.0, "quad_size": Vector2(0.5, 0.5),
		"color": Color(0.42, 0.33, 0.22, 0.7),
		"amount": 14, "lifetime": 1.2, "explosiveness": 0.9,
		"offset": Vector3(0.0, 0.5, 0.0)})

func _spawn_impact(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# Layer 1: Fireball core
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.3, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 8.0, "vel_max": 18.0, "gravity": Vector3(0.0, -6.0, 0.0),
		"scale_min": 0.35, "scale_max": 0.7, "quad_size": Vector2(0.5, 0.5),
		"color": Color(1.0, 0.92, 0.5, 1.0), "billboard": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.55, 0.05), "emission_energy": 5.0,
		"amount": 30, "lifetime": 0.35, "explosiveness": 1.0})

	# Layer 2: Black smoke column
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.5, "direction": Vector3.UP, "spread": 25.0,
		"vel_min": 2.0, "vel_max": 5.0, "gravity": Vector3(0.0, 0.4, 0.0),
		"scale_min": 0.6, "scale_max": 1.1, "quad_size": Vector2(0.8, 0.8),
		"color": Color(0.1, 0.09, 0.08, 0.88),
		"amount": 20, "lifetime": 1.5, "explosiveness": 0.7,
		"offset": Vector3(0.0, 0.3, 0.0)})

	# Layer 3: Shrapnel sparks
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.1, "direction": Vector3.UP, "spread": 90.0,
		"vel_min": 10.0, "vel_max": 22.0, "gravity": Vector3(0.0, -18.0, 0.0),
		"scale_min": 0.05, "scale_max": 0.15, "quad_size": Vector2(0.12, 0.12),
		"color": Color(1.0, 0.8, 0.1, 1.0), "alpha": false, "billboard": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.6, 0.0), "emission_energy": 6.0,
		"amount": 25, "lifetime": 0.6, "explosiveness": 1.0})

	# Layer 4: Ground dust ring
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.2, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 3.0, "vel_max": 7.0, "gravity": Vector3(0.0, -20.0, 0.0),
		"scale_min": 0.25, "scale_max": 0.55, "quad_size": Vector2(0.4, 0.4),
		"color": Color(0.58, 0.45, 0.3, 0.75),
		"amount": 18, "lifetime": 0.9, "explosiveness": 0.95})

	VfxUtils.spawn_flash_light(root, pos, {
		"color": Color(1.0, 0.6, 0.15), "energy": 8.0, "range": 6.0,
		"duration": 0.4, "offset": Vector3(0.0, 0.5, 0.0)})
