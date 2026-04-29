## MachineGunTowerAI.gd — Machine gun tower (TowerBase subclass).
## Rapid raycast fire, low damage, short range.
## Stats configured via @export in MachineGunTower.tscn.

extends TowerBase

const SND_FIRE := "res://assets/kenney_sci-fi-sounds/Audio/laserSmall_002.ogg"

var attack_damage: float = 12.0

# ── Raycast attack — overrides TowerBase._do_attack() ────────────────────────

func _do_attack(target: Node3D) -> void:
	var from: Vector3 = get_fire_position()
	var to: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return
	var hit: Object = result.collider
	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var hit_unit := false
	if hit != null and hit.has_method("take_damage"):
		var hit_team: int = _get_body_team(hit)
		if hit_team != team:
			hit.take_damage(attack_damage, "machinegun_tower", team)
			hit_unit = true
	_spawn_hit_impact(hit_pos, hit_normal, hit_unit)
	_spawn_muzzle_flash(from)
	SoundManager.play_3d(SND_FIRE, from, -3.0, randf_range(0.92, 1.08))

# ── VFX ───────────────────────────────────────────────────────────────────────

func _spawn_hit_impact(pos: Vector3, normal: Vector3, is_unit: bool) -> void:
	var root: Node = get_tree().root

	if is_unit:
		var p1 := GPUParticles3D.new()
		var pm1 := ParticleProcessMaterial.new()
		pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm1.emission_sphere_radius = 0.05
		pm1.direction = normal
		pm1.spread = 60.0
		pm1.initial_velocity_min = 2.0
		pm1.initial_velocity_max = 6.0
		pm1.gravity = Vector3(0.0, -10.0, 0.0)
		pm1.scale_min = 0.1
		pm1.scale_max = 0.22
		var m1 := QuadMesh.new()
		m1.size = Vector2(0.18, 0.18)
		var mat1 := StandardMaterial3D.new()
		mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat1.albedo_color = Color(0.9, 0.15, 0.05, 0.9)
		mat1.emission_enabled = true
		mat1.emission = Color(1.0, 0.1, 0.0)
		mat1.emission_energy_multiplier = 3.0
		mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m1.material = mat1
		p1.process_material = pm1
		p1.draw_pass_1 = m1
		p1.amount = 10
		p1.lifetime = 0.3
		p1.one_shot = true
		p1.explosiveness = 0.9
		root.add_child(p1)
		p1.global_position = pos
		p1.emitting = true
		p1.restart()
		p1.call_deferred("free")

		var p2 := GPUParticles3D.new()
		var pm2 := ParticleProcessMaterial.new()
		pm2.direction = normal
		pm2.spread = 30.0
		pm2.initial_velocity_min = 4.0
		pm2.initial_velocity_max = 10.0
		pm2.gravity = Vector3(0.0, -15.0, 0.0)
		pm2.scale_min = 0.03
		pm2.scale_max = 0.08
		var m2 := QuadMesh.new()
		m2.size = Vector2(0.08, 0.08)
		var mat2 := StandardMaterial3D.new()
		mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat2.albedo_color = Color(1.0, 0.95, 0.7, 1.0)
		mat2.emission_enabled = true
		mat2.emission = Color(1.0, 0.9, 0.4)
		mat2.emission_energy_multiplier = 8.0
		m2.material = mat2
		p2.process_material = pm2
		p2.draw_pass_1 = m2
		p2.amount = 6
		p2.lifetime = 0.15
		p2.one_shot = true
		p2.explosiveness = 1.0
		root.add_child(p2)
		p2.global_position = pos
		p2.emitting = true
		p2.restart()
		p2.call_deferred("free")
	else:
		var p1 := GPUParticles3D.new()
		var pm1 := ParticleProcessMaterial.new()
		pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm1.emission_sphere_radius = 0.05
		pm1.direction = normal
		pm1.spread = 55.0
		pm1.initial_velocity_min = 1.5
		pm1.initial_velocity_max = 4.5
		pm1.gravity = Vector3(0.0, -8.0, 0.0)
		pm1.scale_min = 0.08
		pm1.scale_max = 0.22
		var m1 := QuadMesh.new()
		m1.size = Vector2(0.2, 0.2)
		var mat1 := StandardMaterial3D.new()
		mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat1.albedo_color = Color(0.62, 0.5, 0.35, 0.85)
		mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat1.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m1.material = mat1
		p1.process_material = pm1
		p1.draw_pass_1 = m1
		p1.amount = 12
		p1.lifetime = 0.4
		p1.one_shot = true
		p1.explosiveness = 0.85
		root.add_child(p1)
		p1.global_position = pos
		p1.emitting = true
		p1.restart()
		p1.call_deferred("free")

		var p2 := GPUParticles3D.new()
		var pm2 := ParticleProcessMaterial.new()
		pm2.direction = normal
		pm2.spread = 40.0
		pm2.initial_velocity_min = 3.0
		pm2.initial_velocity_max = 8.0
		pm2.gravity = Vector3(0.0, -15.0, 0.0)
		pm2.scale_min = 0.03
		pm2.scale_max = 0.07
		var m2 := QuadMesh.new()
		m2.size = Vector2(0.08, 0.08)
		var mat2 := StandardMaterial3D.new()
		mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat2.albedo_color = Color(1.0, 0.95, 0.6, 1.0)
		mat2.emission_enabled = true
		mat2.emission = Color(1.0, 0.85, 0.2)
		mat2.emission_energy_multiplier = 7.0
		m2.material = mat2
		p2.process_material = pm2
		p2.draw_pass_1 = m2
		p2.amount = 8
		p2.lifetime = 0.2
		p2.one_shot = true
		p2.explosiveness = 1.0
		root.add_child(p2)
		p2.global_position = pos
		p2.emitting = true
		p2.restart()
		p2.call_deferred("free")

func _spawn_muzzle_flash(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.05
	pm.scale_max = 0.15
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = 8
	p.lifetime = 0.12
	p.one_shot = true
	p.explosiveness = 1.0
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.restart()
	p.call_deferred("free")
