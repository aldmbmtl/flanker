## MachineGunTowerAI.gd — Machine gun tower (TowerBase subclass).
## Rapid raycast fire, low damage, short range.
## Stats configured via @export in MachineGunTower.tscn.

class_name MachineGunTowerAI
extends TowerBase

const SND_FIRE := "res://assets/kenney_sci-fi-sounds/Audio/laserSmall_002.ogg"

var attack_damage: float = 12.0

# ── Raycast attack — overrides TowerBase._do_attack() ────────────────────────

func _do_attack(target: Node3D) -> void:
	var from: Vector3 = get_fire_position()
	var to: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)

	# Always fire muzzle flash and sound regardless of raycast result.
	_spawn_muzzle_flash(from)
	SoundManager.play_3d(SND_FIRE, from, -3.0, randf_range(0.92, 1.08))

	# ── Apply damage directly to the validated target ────────────────────────
	# _find_target() already ran a LOS check, so the target is confirmed
	# reachable. Damage is applied here unconditionally rather than relying on
	# the VFX raycast — terrain or other geometry could intercept the ray and
	# prevent damage from ever landing.
	var hit_unit := false
	var target_peer_id: int = target.get("peer_id") if target.get("peer_id") != null else -1
	if target_peer_id > 0:
		# BasePlayer (local or remote) — route through Python bridge.
		var target_team: int = GameSync.get_player_team(target_peer_id)
		if target_team >= 0 and target_team != team:
			BridgeClient.send("damage_player", {
				"peer_id": target_peer_id,
				"amount": attack_damage,
				"source_team": team,
				"killer_peer_id": -1,
			})
			hit_unit = true
	elif target.has_method("take_damage"):
		var target_team: int = _get_body_team(target)
		if target_team >= 0 and target_team != team:
			target.take_damage(attack_damage, "machinegun_tower", team, -1)
			hit_unit = true

	# ── Raycast for VFX hit position / normal only ───────────────────────────
	# Exclude own tower body and the target's HitBody so the ray can reach the
	# target's CharacterBody3D capsule for an accurate impact point.
	var hit_pos: Vector3 = to
	var hit_normal: Vector3 = (from - to).normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var excluded: Array[RID] = [get_rid()]
	var target_hit_body: Node = target.get_node_or_null("HitBody")
	if target_hit_body != null:
		excluded.append(target_hit_body.get_rid())
	query.exclude = excluded
	query.collision_mask = 0b01  # layer 1 — terrain only; fences (layer 4/value 8) are passable
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		hit_pos    = result.position
		hit_normal = result.normal

	_spawn_hit_impact(hit_pos, hit_normal, hit_unit)
	_spawn_tracer(from, hit_pos)
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("fire_projectile", {
			"visual_type": "mg",
			"params": {
				"tower_name": name,
				"from": [from.x, from.y, from.z],
				"hit_pos": [hit_pos.x, hit_pos.y, hit_pos.z],
				"hit_normal": [hit_normal.x, hit_normal.y, hit_normal.z],
				"hit_unit": hit_unit,
			}
		})

## Called by TowerBase._process after turret look_at when in multiplayer.
func _on_turret_rotated(yaw_rad: float) -> void:
	if BridgeClient.is_connected_to_server():
		BridgeClient.send("fire_projectile", {
			"visual_type": "mg_turret_rot",
			"params": {"tower_name": name, "yaw_rad": yaw_rad}
		})

# ── VFX ───────────────────────────────────────────────────────────────────────

func _spawn_hit_impact(pos: Vector3, normal: Vector3, is_unit: bool) -> void:
	var root: Node = get_tree().root

	if is_unit:
		VfxUtils.spawn_particles(root, pos, {
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
			"emission_radius": 0.08, "direction": normal, "spread": 60.0,
			"vel_min": 4.0, "vel_max": 10.0, "gravity": Vector3(0.0, -10.0, 0.0),
			"scale_min": 0.2, "scale_max": 0.5, "quad_size": Vector2(0.45, 0.45),
			"color": Color(0.9, 0.15, 0.05, 0.9),
			"emission_enabled": true, "emission_color": Color(1.0, 0.1, 0.0), "emission_energy": 4.0,
			"amount": 14, "lifetime": 0.35, "explosiveness": 0.9})

		VfxUtils.spawn_particles(root, pos, {
			"direction": normal, "spread": 30.0,
			"vel_min": 6.0, "vel_max": 14.0, "gravity": Vector3(0.0, -15.0, 0.0),
			"scale_min": 0.08, "scale_max": 0.2, "quad_size": Vector2(0.22, 0.22),
			"color": Color(1.0, 0.95, 0.7, 1.0), "alpha": false,
			"emission_enabled": true, "emission_color": Color(1.0, 0.9, 0.4), "emission_energy": 10.0,
			"amount": 8, "lifetime": 0.18, "explosiveness": 1.0})
	else:
		VfxUtils.spawn_particles(root, pos, {
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
			"emission_radius": 0.08, "direction": normal, "spread": 55.0,
			"vel_min": 3.0, "vel_max": 8.0, "gravity": Vector3(0.0, -8.0, 0.0),
			"scale_min": 0.15, "scale_max": 0.45, "quad_size": Vector2(0.45, 0.45),
			"color": Color(0.62, 0.5, 0.35, 0.85),
			"amount": 16, "lifetime": 0.45, "explosiveness": 0.85})

		VfxUtils.spawn_particles(root, pos, {
			"direction": normal, "spread": 40.0,
			"vel_min": 5.0, "vel_max": 12.0, "gravity": Vector3(0.0, -15.0, 0.0),
			"scale_min": 0.06, "scale_max": 0.16, "quad_size": Vector2(0.2, 0.2),
			"color": Color(1.0, 0.95, 0.6, 1.0), "alpha": false,
			"emission_enabled": true, "emission_color": Color(1.0, 0.85, 0.2), "emission_energy": 9.0,
			"amount": 10, "lifetime": 0.25, "explosiveness": 1.0})

func _spawn_muzzle_flash(pos: Vector3) -> void:
	VfxUtils.spawn_particles(get_tree().root, pos, {
		"direction": Vector3.UP, "spread": 80.0,
		"vel_min": 4.0, "vel_max": 10.0, "gravity": Vector3.ZERO,
		"scale_min": 0.15, "scale_max": 0.45, "quad_size": Vector2(0.4, 0.4),
		"color": Color(1.0, 0.9, 0.3, 1.0), "alpha": false,
		"emission_enabled": true, "emission_color": Color(1.0, 0.8, 0.0), "emission_energy": 6.0,
		"amount": 12, "lifetime": 0.14, "explosiveness": 1.0})

## Frees a GPUParticles3D node after its lifetime expires so particles fully play.
## Kept for test compatibility — production code uses VfxUtils.spawn_particles.
func _free_after_lifetime(p: GPUParticles3D) -> void:
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)

## Thin stretched-box tracer from muzzle to hit point.
## Visible at full 22 m attack range.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	if length < 0.1:
		return
	var mid: Vector3 = (from + to) * 0.5
	var dir: Vector3 = (to - from).normalized()

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.55, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 5.0
	bm.material = mat
	mi.mesh = bm
	# Orient box along shot direction: default box Z-axis → dir
	if dir.abs() != Vector3.UP:
		mi.basis = Basis.looking_at(dir, Vector3.UP)
	else:
		mi.basis = Basis.looking_at(dir, Vector3.RIGHT)
	get_tree().root.add_child(mi)
	mi.global_position = mid
	get_tree().create_timer(0.08).timeout.connect(mi.queue_free)
