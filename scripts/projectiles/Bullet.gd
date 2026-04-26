extends ProjectileBase

signal hit_something(hit_type: String)

func _ready() -> void:
	var mi: MeshInstance3D = $MeshInstance3D
	mi.material_override = CombatUtils.make_team_tracer_material(shooter_team)

# ── Hit handling ──────────────────────────────────────────────────────────────

func _on_hit(pos: Vector3, collider: Object) -> void:
	# Ghost hitbox — remote player represented by a StaticBody3D with ghost_peer_id meta.
	# Damage is server-authoritative: routed via GameSync RPC, not take_damage().
	if collider is StaticBody3D and collider.has_meta("ghost_peer_id"):
		var target_peer: int = collider.get_meta("ghost_peer_id")
		if not GameSync.player_dead.get(target_peer, false):
			var ghost_team: int = GameSync.get_player_team(target_peer)
			var friendly: bool = (shooter_team >= 0 and ghost_team == shooter_team)
			if not friendly and multiplayer.is_server():
				var new_hp: float = GameSync.damage_player(target_peer, damage, shooter_team, shooter_peer_id)
				LobbyManager.apply_player_damage.rpc(target_peer, new_hp)
				if new_hp <= 0.0:
					LobbyManager.notify_player_died.rpc(target_peer)
		hit_something.emit("player")
		_spawn_sparks(pos, collider)
		return

	if CombatUtils.should_damage(collider, shooter_team):
		hit_something.emit(_get_hit_type(collider))
		collider.take_damage(damage, source, shooter_team, shooter_peer_id)
	_spawn_sparks(pos, collider)

# ── Orientation ───────────────────────────────────────────────────────────────

func _after_move() -> void:
	if velocity.length() > 0.1:
		var target_pos: Vector3 = global_position + velocity.normalized()
		if (target_pos - global_position).normalized().length() > 0.0:
			look_at(target_pos, Vector3.UP)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_hit_type(hit: Object) -> String:
	if hit is StaticBody3D and hit.has_meta("ghost_peer_id"):
		return "player"
	if hit is StaticBody3D and (hit.is_in_group("towers") or (hit.get_parent() != null and hit.get_parent().is_in_group("towers"))):
		return "tower"
	if hit.has_method("take_damage"):
		var hit_team: int = hit.get("team") if hit.get("team") != null else -999
		if hit_team >= 0:
			return "minion"
	return "building"

func _spawn_sparks(pos: Vector3, hit: Object) -> void:
	var spark_type := "ground"
	if hit is StaticBody3D and hit.has_meta("ghost_peer_id"):
		spark_type = "unit"
	elif hit.has_method("take_damage"):
		if hit is StaticBody3D:
			spark_type = "building"
		else:
			var hit_team: int = hit.get("team") if hit.get("team") != null else -999
			if hit_team >= 0:
				spark_type = "unit"

	var particles := GPUParticles3D.new()
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3.UP
	pmat.spread = 45.0
	pmat.initial_velocity_min = 3.0
	pmat.initial_velocity_max = 6.0
	pmat.gravity = Vector3(0, -15, 0)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true

	if spark_type == "ground":
		mat.albedo_color = Color(0.55, 0.35, 0.2, 1.0)
	elif spark_type == "unit":
		mat.albedo_color = Color(1.0, 0.2, 0.1, 1.0)
	else:
		mat.albedo_color = Color(1.0, 1.0, 0.3, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 0.3)
		mat.emission_energy_multiplier = 4.0

	mesh.material = mat
	particles.process_material = pmat
	particles.draw_pass_1 = mesh
	particles.amount = 20

	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.restart()
	particles.call_deferred("free")
