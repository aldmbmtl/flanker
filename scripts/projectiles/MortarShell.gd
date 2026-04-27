extends ProjectileBase
## Mortar Shell — TowerBase subclass. Long-range ballistic arc, large splash.

const FLIGHT_TIME       := 3.5
const SPLASH_RADIUS     := 6.0
const SPLASH_DAMAGE_MULT := 0.5

var target_pos: Vector3 = Vector3.ZERO

var _trail_timer: float = 0.0
const TRAIL_INTERVAL := 0.06

func _ready() -> void:
	source       = "mortar_shell"
	max_lifetime = FLIGHT_TIME + 1.0

	_build_shell_mesh()

	var start: Vector3 = global_position
	var dt: float = FLIGHT_TIME
	velocity.x = (target_pos.x - start.x) / dt
	velocity.z = (target_pos.z - start.z) / dt
	velocity.y = (target_pos.y - start.y + 0.5 * gravity * dt * dt) / dt

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
	var is_server: bool = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if is_server:
		if collider is StaticBody3D and collider.has_meta("ghost_peer_id"):
			var target_peer: int = collider.get_meta("ghost_peer_id") as int
			if not GameSync.player_dead.get(target_peer, false):
				var ghost_team: int = GameSync.get_player_team(target_peer)
				if ghost_team != shooter_team:
					var new_hp: float = GameSync.damage_player(target_peer, damage, shooter_team, -1)
					LobbyManager.apply_player_damage.rpc(target_peer, new_hp)
					if new_hp <= 0.0:
						LobbyManager.notify_player_died.rpc(target_peer)
		elif CombatUtils.should_damage(collider, shooter_team):
			collider.take_damage(damage, source, shooter_team)
		_apply_splash(pos, SPLASH_RADIUS, damage * SPLASH_DAMAGE_MULT, "mortar_splash", collider)
	_spawn_impact(pos)

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
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0.0, 1.0, 0.0)
	pm.scale_min = 0.2
	pm.scale_max = 0.5
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.6, 0.6, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = 4
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.restart()
	p.call_deferred("free")

func _spawn_impact(pos: Vector3) -> void:
	var root: Node = get_tree().root

	# Layer 1: Large fireball core
	var p1 := GPUParticles3D.new()
	var pm1 := ParticleProcessMaterial.new()
	pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm1.emission_sphere_radius = 0.5
	pm1.direction = Vector3.UP
	pm1.spread = 180.0
	pm1.initial_velocity_min = 10.0
	pm1.initial_velocity_max = 24.0
	pm1.gravity = Vector3(0.0, -5.0, 0.0)
	pm1.scale_min = 0.5
	pm1.scale_max = 1.0
	var m1 := QuadMesh.new()
	m1.size = Vector2(0.7, 0.7)
	var mat1 := StandardMaterial3D.new()
	mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat1.albedo_color = Color(1.0, 0.94, 0.55, 1.0)
	mat1.emission_enabled = true
	mat1.emission = Color(1.0, 0.5, 0.02)
	mat1.emission_energy_multiplier = 6.0
	mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m1.material = mat1
	p1.process_material = pm1
	p1.draw_pass_1 = m1
	p1.amount = 40
	p1.lifetime = 0.45
	p1.one_shot = true
	p1.explosiveness = 1.0
	root.add_child(p1)
	p1.global_position = pos
	p1.emitting = true
	p1.restart()
	get_tree().create_timer(p1.lifetime + 0.1).timeout.connect(p1.queue_free)

	# Layer 2: Massive smoke column
	var p2 := GPUParticles3D.new()
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = 0.8
	pm2.direction = Vector3.UP
	pm2.spread = 18.0
	pm2.initial_velocity_min = 2.0
	pm2.initial_velocity_max = 6.0
	pm2.gravity = Vector3(0.0, 0.6, 0.0)
	pm2.scale_min = 0.8
	pm2.scale_max = 1.6
	var m2 := QuadMesh.new()
	m2.size = Vector2(1.2, 1.2)
	var mat2 := StandardMaterial3D.new()
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat2.albedo_color = Color(0.12, 0.1, 0.09, 0.9)
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.material = mat2
	p2.process_material = pm2
	p2.draw_pass_1 = m2
	p2.amount = 35
	p2.lifetime = 2.5
	p2.one_shot = true
	p2.explosiveness = 0.6
	root.add_child(p2)
	p2.global_position = pos + Vector3(0.0, 0.5, 0.0)
	p2.emitting = true
	p2.restart()
	get_tree().create_timer(p2.lifetime + 0.1).timeout.connect(p2.queue_free)

	# Layer 3: Shrapnel sparks
	var p3 := GPUParticles3D.new()
	var pm3 := ParticleProcessMaterial.new()
	pm3.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm3.emission_sphere_radius = 0.2
	pm3.direction = Vector3.UP
	pm3.spread = 180.0
	pm3.initial_velocity_min = 12.0
	pm3.initial_velocity_max = 28.0
	pm3.gravity = Vector3(0.0, -20.0, 0.0)
	pm3.scale_min = 0.05
	pm3.scale_max = 0.18
	var m3 := QuadMesh.new()
	m3.size = Vector2(0.15, 0.15)
	var mat3 := StandardMaterial3D.new()
	mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat3.albedo_color = Color(1.0, 0.75, 0.1, 1.0)
	mat3.emission_enabled = true
	mat3.emission = Color(1.0, 0.55, 0.0)
	mat3.emission_energy_multiplier = 7.0
	m3.material = mat3
	p3.process_material = pm3
	p3.draw_pass_1 = m3
	p3.amount = 40
	p3.lifetime = 0.7
	p3.one_shot = true
	p3.explosiveness = 1.0
	root.add_child(p3)
	p3.global_position = pos
	p3.emitting = true
	p3.restart()
	get_tree().create_timer(p3.lifetime + 0.1).timeout.connect(p3.queue_free)

	# Layer 4: Ground dust ring
	var p4 := GPUParticles3D.new()
	var pm4 := ParticleProcessMaterial.new()
	pm4.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm4.emission_sphere_radius = 0.3
	pm4.direction = Vector3.UP
	pm4.spread = 180.0
	pm4.initial_velocity_min = 4.0
	pm4.initial_velocity_max = 10.0
	pm4.gravity = Vector3(0.0, -22.0, 0.0)
	pm4.scale_min = 0.3
	pm4.scale_max = 0.75
	var m4 := QuadMesh.new()
	m4.size = Vector2(0.55, 0.55)
	var mat4 := StandardMaterial3D.new()
	mat4.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat4.albedo_color = Color(0.55, 0.42, 0.28, 0.8)
	mat4.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat4.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m4.material = mat4
	p4.process_material = pm4
	p4.draw_pass_1 = m4
	p4.amount = 30
	p4.lifetime = 1.2
	p4.one_shot = true
	p4.explosiveness = 0.95
	root.add_child(p4)
	p4.global_position = pos
	p4.emitting = true
	p4.restart()
	get_tree().create_timer(p4.lifetime + 0.1).timeout.connect(p4.queue_free)

	# Layer 5: Secondary splash smoke
	var p5 := GPUParticles3D.new()
	var pm5 := ParticleProcessMaterial.new()
	pm5.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm5.emission_sphere_radius = float(SPLASH_RADIUS) * 0.5
	pm5.direction = Vector3.UP
	pm5.spread = 50.0
	pm5.initial_velocity_min = 1.5
	pm5.initial_velocity_max = 4.0
	pm5.gravity = Vector3(0.0, 0.3, 0.0)
	pm5.scale_min = 0.5
	pm5.scale_max = 1.1
	var m5 := QuadMesh.new()
	m5.size = Vector2(0.9, 0.9)
	var mat5 := StandardMaterial3D.new()
	mat5.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat5.albedo_color = Color(0.7, 0.68, 0.65, 0.6)
	mat5.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat5.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m5.material = mat5
	p5.process_material = pm5
	p5.draw_pass_1 = m5
	p5.amount = 15
	p5.lifetime = 1.8
	p5.one_shot = true
	p5.explosiveness = 0.5
	root.add_child(p5)
	p5.global_position = pos + Vector3(0.0, 0.2, 0.0)
	p5.emitting = true
	p5.restart()
	get_tree().create_timer(p5.lifetime + 0.1).timeout.connect(p5.queue_free)

	# Flash light
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.1)
	flash.light_energy = 14.0
	flash.omni_range = 10.0
	flash.shadow_enabled = false
	root.add_child(flash)
	flash.global_position = pos + Vector3(0.0, 0.8, 0.0)
	var tw: Tween = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)
