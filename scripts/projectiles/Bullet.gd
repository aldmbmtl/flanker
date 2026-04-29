extends ProjectileBase

signal hit_something(hit_type: String)

# Shared spark materials — allocated once, reused every hit
static var _mat_ground: StandardMaterial3D = null
static var _mat_unit: StandardMaterial3D = null
static var _mat_building: StandardMaterial3D = null
static var _spark_mesh: QuadMesh = null
static var _spark_pmat: ParticleProcessMaterial = null

const SND_HIT_GROUND    := "res://assets/kenney_impact-sounds/Audio/impactPlate_medium_000.ogg"
const SND_HIT_UNIT      := "res://assets/kenney_impact-sounds/Audio/impactPunch_medium_001.ogg"
const SND_HIT_BUILDING  := "res://assets/kenney_impact-sounds/Audio/impactMetal_medium_000.ogg"

func _ready() -> void:
	var mi: MeshInstance3D = $MeshInstance3D
	mi.material_override = CombatUtils.make_team_tracer_material(shooter_team)
	_ensure_spark_resources()

# ── Hit handling ──────────────────────────────────────────────────────────────

func _on_hit(pos: Vector3, collider: Object) -> void:
	# Tree trunk — clear the tree, bullet is consumed. No sparks, no combat damage.
	if collider != null and collider.has_meta("tree_trunk_height"):
		_request_destroy_tree(pos)
		return

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
		_play_hit_sound(pos, collider)
		return

	if CombatUtils.should_damage(collider, shooter_team):
		hit_something.emit(_get_hit_type(collider))
		collider.take_damage(damage, source, shooter_team, shooter_peer_id)
	_spawn_sparks(pos, collider)
	_play_hit_sound(pos, collider)

# ── Orientation ───────────────────────────────────────────────────────────────

func _after_move() -> void:
	var spd_sq: float = velocity.length_squared()
	if spd_sq > 0.01:
		var spd: float = sqrt(spd_sq)
		var target_pos: Vector3 = global_position + velocity / spd
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

func _play_hit_sound(pos: Vector3, hit: Object) -> void:
	var snd: String = SND_HIT_GROUND
	if hit is StaticBody3D and hit.has_meta("ghost_peer_id"):
		snd = SND_HIT_UNIT
	elif hit.has_method("take_damage"):
		if hit is StaticBody3D:
			snd = SND_HIT_BUILDING
		else:
			snd = SND_HIT_UNIT
	SoundManager.play_3d(snd, pos, -4.0, randf_range(0.9, 1.1))

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
	particles.process_material = _spark_pmat
	particles.draw_pass_1 = _spark_mesh

	match spark_type:
		"ground":    particles.material_override = _mat_ground
		"unit":      particles.material_override = _mat_unit
		_:           particles.material_override = _mat_building

	particles.amount = 20
	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.restart()
	particles.call_deferred("free")


static func _ensure_spark_resources() -> void:
	if _spark_pmat != null:
		return

	_spark_pmat = ParticleProcessMaterial.new()
	_spark_pmat.direction = Vector3.UP
	_spark_pmat.spread = 45.0
	_spark_pmat.initial_velocity_min = 3.0
	_spark_pmat.initial_velocity_max = 6.0
	_spark_pmat.gravity = Vector3(0, -15, 0)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15)
	_spark_mesh = mesh

	_mat_ground = StandardMaterial3D.new()
	_mat_ground.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ground.vertex_color_use_as_albedo = true
	_mat_ground.no_depth_test = true
	_mat_ground.albedo_color = Color(0.55, 0.35, 0.2, 1.0)

	_mat_unit = StandardMaterial3D.new()
	_mat_unit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_unit.vertex_color_use_as_albedo = true
	_mat_unit.no_depth_test = true
	_mat_unit.albedo_color = Color(1.0, 0.2, 0.1, 1.0)

	_mat_building = StandardMaterial3D.new()
	_mat_building.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_building.vertex_color_use_as_albedo = true
	_mat_building.no_depth_test = true
	_mat_building.albedo_color = Color(1.0, 1.0, 0.3, 1.0)
	_mat_building.emission_enabled = true
	_mat_building.emission = Color(1.0, 1.0, 0.3)
	_mat_building.emission_energy_multiplier = 4.0
