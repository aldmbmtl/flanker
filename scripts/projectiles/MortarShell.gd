extends ProjectileBase
## Mortar Shell — TowerBase subclass. Long-range ballistic arc, large splash.

const FLIGHT_TIME       := 3.5
const SPLASH_RADIUS     := 6.0
const SPLASH_DAMAGE_MULT := 0.5

const SND_EXPLOSION := "res://assets/kenney_sci-fi-sounds/Audio/explosionCrunch_002.ogg"

var target_pos: Vector3 = Vector3.ZERO

var _trail_timer: float = 0.0
const TRAIL_INTERVAL := 0.06

func _ready() -> void:
	source       = "mortar_shell"
	max_lifetime = FLIGHT_TIME + 1.0

	_build_shell_mesh()
	init_ballistic_arc(target_pos, FLIGHT_TIME)

func _build_shell_mesh() -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.32, 0.28)
	mat.roughness = 0.9
	mesh_inst.mesh = sphere
	mesh_inst.material_override = mat
	add_child(mesh_inst)

# ── Hit handling ──────────────────────────────────────────────────────────────

func _on_hit(pos: Vector3, collider: Object) -> void:
	# Tree trunk — clear the tree, shell is consumed. No explosion, no splash.
	if collider != null and collider.has_meta("tree_trunk_height"):
		_request_destroy_tree(pos)
		return

	var is_server: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_server:
		if not _handle_ghost_hit(collider, damage):
			if CombatUtils.should_damage(collider, shooter_team):
				collider.take_damage(damage, source, shooter_team)
		_apply_splash(pos, SPLASH_RADIUS, damage * SPLASH_DAMAGE_MULT, "mortar_splash", collider)
	_spawn_impact(pos)
	SoundManager.play_3d(SND_EXPLOSION, pos, 2.0, randf_range(0.85, 1.0))

# ── Trail + orientation ───────────────────────────────────────────────────────

func _after_move() -> void:
	_trail_timer += get_process_delta_time()
	if _trail_timer >= TRAIL_INTERVAL:
		_trail_timer = 0.0
		_spawn_smoke_puff(global_position)
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity.normalized(), Vector3.UP)

# ── VFX ───────────────────────────────────────────────────────────────────────

func _spawn_smoke_puff(pos: Vector3) -> void:
	VfxUtils.spawn_particles(get_tree().root, pos, {
		"direction": Vector3.UP, "spread": 40.0,
		"vel_min": 0.5, "vel_max": 1.5, "gravity": Vector3(0.0, 1.0, 0.0),
		"scale_min": 0.2, "scale_max": 0.5, "quad_size": Vector2(0.3, 0.3),
		"color": Color(0.6, 0.6, 0.6, 0.6),
		"amount": 4, "lifetime": 0.5, "explosiveness": 1.0})

func _spawn_impact(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# Layer 1: Large fireball core
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.5, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 10.0, "vel_max": 24.0, "gravity": Vector3(0.0, -5.0, 0.0),
		"scale_min": 0.5, "scale_max": 1.0, "quad_size": Vector2(0.7, 0.7),
		"color": Color(1.0, 0.94, 0.55, 1.0), "billboard": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.5, 0.02), "emission_energy": 6.0,
		"amount": 40, "lifetime": 0.45, "explosiveness": 1.0})

	# Layer 2: Massive smoke column
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.8, "direction": Vector3.UP, "spread": 18.0,
		"vel_min": 2.0, "vel_max": 6.0, "gravity": Vector3(0.0, 0.6, 0.0),
		"scale_min": 0.8, "scale_max": 1.6, "quad_size": Vector2(1.2, 1.2),
		"color": Color(0.12, 0.1, 0.09, 0.9),
		"amount": 35, "lifetime": 2.5, "explosiveness": 0.6,
		"offset": Vector3(0.0, 0.5, 0.0)})

	# Layer 3: Shrapnel sparks
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.2, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 12.0, "vel_max": 28.0, "gravity": Vector3(0.0, -20.0, 0.0),
		"scale_min": 0.05, "scale_max": 0.18, "quad_size": Vector2(0.15, 0.15),
		"color": Color(1.0, 0.75, 0.1, 1.0), "alpha": false, "billboard": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.55, 0.0), "emission_energy": 7.0,
		"amount": 40, "lifetime": 0.7, "explosiveness": 1.0})

	# Layer 4: Ground dust ring
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": 0.3, "direction": Vector3.UP, "spread": 180.0,
		"vel_min": 4.0, "vel_max": 10.0, "gravity": Vector3(0.0, -22.0, 0.0),
		"scale_min": 0.3, "scale_max": 0.75, "quad_size": Vector2(0.55, 0.55),
		"color": Color(0.55, 0.42, 0.28, 0.8),
		"amount": 30, "lifetime": 1.2, "explosiveness": 0.95})

	# Layer 5: Secondary splash smoke
	VfxUtils.spawn_particles(root, pos, {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
		"emission_radius": float(SPLASH_RADIUS) * 0.5, "direction": Vector3.UP, "spread": 50.0,
		"vel_min": 1.5, "vel_max": 4.0, "gravity": Vector3(0.0, 0.3, 0.0),
		"scale_min": 0.5, "scale_max": 1.1, "quad_size": Vector2(0.9, 0.9),
		"color": Color(0.7, 0.68, 0.65, 0.6),
		"amount": 15, "lifetime": 1.8, "explosiveness": 0.5,
		"offset": Vector3(0.0, 0.2, 0.0)})

	VfxUtils.spawn_flash_light(root, pos, {
		"color": Color(1.0, 0.55, 0.1), "energy": 14.0, "range": 10.0,
		"duration": 0.5, "offset": Vector3(0.0, 0.8, 0.0)})
